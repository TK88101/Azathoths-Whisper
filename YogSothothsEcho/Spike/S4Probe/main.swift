import AppKit
import CryptoKit
import Foundation
import iTunesLibrary
import ScriptingBridge
import SQLite3

// S4-P1 探針（docs/plans/2026-10-14-yse/sprint-4-detail.md §4.1）。不進產品。
// 與 SpikeCore（FP01／Playback／Verdicts）一起編成單一模組。只記數量、耗時、退出碼、錯誤代碼，
// 不記曲名、專輯名（N-05）。寫檔只限結果目錄與自己的暫存子目錄；Queue.dat 只讀。
// 用法：open S4Probe.app --args <命令> <結果目錄> [參數]
//   sign <mode>            P1-b：模板 → shortcuts sign（anyone／people-who-know-me）
//   import                 P1-b：以「捷徑」App 開啟簽好的檔（使用者按「加入」）
//   integrity <name>       P1-c：唯讀讀 Shortcuts.sqlite，算原始／正規化雜湊並與模板比對
//   tcc                    P1-a：以必停的輸入跑捷徑（未知專輯），確認 Music 未動
//   bind                   P1-d：等 Music 結束，比較「綁 PID」與「綁 bundle id」送事件是否叫起 Music
//   timing <n>             P1-e：放行專輯點歌 n 次，量到達／捷徑結束／佇列穩定

let shortcutName = "YSE Play v1"
let shortcutsCLI = "/usr/bin/shortcuts"

final class Probe: @unchecked Sendable {
    let out: URL
    let command: String
    let args: [String]
    let started = ContinuousClock.now
    var events: [[String: String]] = []

    init(command: String, out: URL, args: [String]) {
        self.command = command; self.out = out; self.args = args
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    func elapsed() -> Double {
        let d = ContinuousClock.now - started
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    func log(_ step: String, _ detail: [String: String] = [:]) {
        var e = detail; e["step"] = step; e["t"] = String(format: "%.3f", elapsed())
        events.append(e)
        let data = try? JSONSerialization.data(withJSONObject: ["command": command, "bundle": Bundle.main.bundleIdentifier ?? "-", "events": events],
                                               options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: out.appendingPathComponent("s4p1-\(command).json"))
    }

    // MARK: 子行程

    struct Ran { let code: Int32?; let stderrNonEmpty: Bool; let seconds: Double }

    func run(_ arguments: [String], timeout: Double) -> Ran {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shortcutsCLI)
        p.arguments = arguments
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        let err = Pipe(); p.standardError = err
        let t0 = elapsed()
        do { try p.run() } catch { return Ran(code: nil, stderrNonEmpty: false, seconds: 0) }
        while p.isRunning, elapsed() - t0 < timeout { usleep(20_000) }
        if p.isRunning { p.terminate(); return Ran(code: nil, stderrNonEmpty: false, seconds: elapsed() - t0) }
        let nonEmpty = !err.fileHandleForReading.availableData.isEmpty   // 內容丟棄，只記是否非空
        return Ran(code: p.terminationStatus, stderrNonEmpty: nonEmpty, seconds: elapsed() - t0)
    }

    var workDir: URL { out.appendingPathComponent("work", isDirectory: true) }

    // MARK: P1-b

    func sign() {
        let mode = args.first ?? "people-who-know-me"
        let template = URL(fileURLWithPath: args.count > 1 ? args[1] : "")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let input = workDir.appendingPathComponent("unsigned.shortcut")
        let output = workDir.appendingPathComponent("\(shortcutName).shortcut")
        try? FileManager.default.removeItem(at: output)
        guard let data = try? Data(contentsOf: template) else { return log("template.missing") }
        try? data.write(to: input)
        let r = run(["sign", "--mode", mode, "--input", input.path, "--output", output.path], timeout: 60)
        let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? -1
        log("sign", ["mode": mode, "exit": r.code.map(String.init) ?? "timeout", "stderr": "\(r.stderrNonEmpty)",
                     "seconds": String(format: "%.2f", r.seconds), "outputBytes": "\(size)"])
    }

    func importSigned() {
        let file = workDir.appendingPathComponent("\(shortcutName).shortcut")
        guard FileManager.default.fileExists(atPath: file.path),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts")
        else { return log("import.missing") }
        let sema = DispatchSemaphore(value: 0)
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: .init()) { _, error in
            self.log("import.opened", ["error": error.map { "\(($0 as NSError).code)" } ?? "none"]); sema.signal()
        }
        sema.wait()
    }

    // MARK: P1-c

    /// UUID 依出現順序換成序號（匯入時若重產 UUID，引用關係仍保持一致）；其餘照原樣，鍵排序後 JSON 化
    static func normalized(_ actions: Any) -> Data {
        var map: [String: String] = [:]
        func walk(_ v: Any) -> Any {
            if let s = v as? String, UUID(uuidString: s) != nil {
                if let m = map[s] { return m }
                let m = "u\(map.count)"; map[s] = m; return m
            }
            if let d = v as? [String: Any] { return d.mapValues(walk) }
            if let a = v as? [Any] { return a.map(walk) }
            if let data = v as? Data { return data.base64EncodedString() }
            if let date = v as? Date { return date.timeIntervalSince1970 }
            return v
        }
        return (try? JSONSerialization.data(withJSONObject: walk(actions), options: [.sortedKeys])) ?? Data()
    }

    static func hex(_ d: Data) -> String { SHA256.hash(data: d).prefix(8).map { String(format: "%02x", $0) }.joined() }

    func integrity() {
        let name = args.first ?? shortcutName
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Shortcuts/Shortcuts.sqlite").path
        var db: OpaquePointer?
        let t0 = elapsed()
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK, let db else { return log("db.open.fail", ["rc": "\(rc)"]) }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var stmt: OpaquePointer?
        let sql = "select a.ZDATA from ZSHORTCUT s join ZSHORTCUTACTIONS a on a.ZSHORTCUT = s.Z_PK where s.ZNAME = ?1 and ifnull(s.ZTOMBSTONED, 0) = 0"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return log("db.prepare.fail", ["msgBytes": "\(String(cString: sqlite3_errmsg(db)).utf8.count)"])
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var rows = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows += 1
            let bytes = Int(sqlite3_column_bytes(stmt, 0))
            let blob = sqlite3_column_blob(stmt, 0).map { Data(bytes: $0, count: bytes) } ?? Data()
            let plist = try? PropertyListSerialization.propertyList(from: blob, format: nil)
            log("row", ["bytes": "\(bytes)", "raw": Self.hex(blob), "decoded": "\(plist != nil)",
                        "normalized": plist.map { Self.hex(Self.normalized($0)) } ?? "-",
                        "actions": "\((plist as? [Any])?.count ?? -1)"])
        }
        log("db.done", ["rows": "\(rows)", "seconds": String(format: "%.3f", elapsed() - t0)])
        if args.count > 1, let data = try? Data(contentsOf: URL(fileURLWithPath: args[1])),
           let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let actions = root["WFWorkflowActions"] {
            log("template", ["normalized": Self.hex(Self.normalized(actions)), "actions": "\((actions as? [Any])?.count ?? -1)"])
        }
    }

    // P1-c 補查：讀不到是哪一層擋的（只記錯誤代碼）
    func fsAccess() {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Shortcuts")
        do { let n = try fm.contentsOfDirectory(atPath: dir.path).count; log("fs.list", ["entries": "\(n)"]) }
        catch { let e = error as NSError; log("fs.list.fail", ["domain": e.domain, "code": "\(e.code)", "posix": "\((e.userInfo[NSUnderlyingErrorKey] as? NSError)?.code ?? 0)"]) }
        for name in ["Shortcuts.sqlite", "ShareSheetState.plist"] {
            do { let d = try Data(contentsOf: dir.appendingPathComponent(name), options: .alwaysMapped); log("fs.read", ["file": name, "bytes": "\(d.count)"]) }
            catch { let e = error as NSError; log("fs.read.fail", ["file": name, "domain": e.domain, "code": "\(e.code)", "posix": "\((e.userInfo[NSUnderlyingErrorKey] as? NSError)?.code ?? 0)"]) }
        }
        let tccDB = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        log("fs.userTCCdbReadable", ["value": "\(fm.isReadableFile(atPath: tccDB.path) && (try? Data(contentsOf: tccDB, options: .alwaysMapped)) != nil)"])
    }

    // MARK: Music

    var music: SBApplication? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first(where: { !$0.isTerminated })
        else { return nil }
        let sb = SBApplication(processIdentifier: app.processIdentifier)
        sb?.timeout = 120   // ticks（約 2 s）
        return sb
    }

    struct Observation: Equatable { let track: String?; let state: UInt32; let queue: [String]? }

    func observe(_ sb: SBApplication?) -> Observation {
        let state = (sb?.value(forKey: "playerState") as? NSNumber)?.uint32Value ?? 0
        let track = (sb?.value(forKey: "currentTrack") as? NSObject)?.value(forKey: "persistentID") as? String
        return Observation(track: track, state: state, queue: Self.queue())
    }

    static func queue() -> [String]? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/Music/Music Library.musiclibrary/Preferences/Queue.dat")
        return (try? Data(contentsOf: url)).flatMap(QueueIDs.parse)
    }

    func writeInput(_ input: ShortcutInput) -> URL? {
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let file = workDir.appendingPathComponent("input-\(UUID().uuidString).json")
        guard let data = try? input.json(), (try? data.write(to: file)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }

    // MARK: P1-a

    func tcc() {
        let before = observe(music)
        guard let file = writeInput(ShortcutInput(album: "yse-probe-\(UUID().uuidString)", albumArtist: "", artist: "", position: 1, expectedCount: 1))
        else { return log("input.fail") }
        defer { try? FileManager.default.removeItem(at: file) }
        let r = run(["run", shortcutName, "--input-path", file.path], timeout: 30)
        sleep(1)
        let after = observe(music)
        log("tcc", ["exit": r.code.map(String.init) ?? "timeout", "stderr": "\(r.stderrNonEmpty)",
                    "seconds": String(format: "%.2f", r.seconds), "musicUnchanged": "\(before == after)",
                    "musicRunning": "\(music != nil)"])
    }

    // MARK: P1-d

    func bind() {
        guard let first = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            return log("bind.musicNotRunningAtStart")
        }
        let stale = SBApplication(processIdentifier: first.processIdentifier)
        stale?.timeout = 120
        log("bind.waitingForQuit", ["note": "請結束 Music（120 s 內）"])
        let t0 = elapsed()
        while !first.isTerminated, elapsed() - t0 < 120 { usleep(200_000) }
        guard first.isTerminated else { return log("bind.timeoutWaitingQuit") }
        sleep(2)
        _ = stale?.value(forKey: "playerState")
        let staleError = (stale?.lastError() as NSError?)?.code
        sleep(5)
        log("bind.pid", ["error": staleError.map(String.init) ?? "none", "musicRelaunched": "\(music != nil)"])
        guard music == nil else { return }
        let byID = SBApplication(bundleIdentifier: "com.apple.Music")
        byID?.timeout = 120
        _ = byID?.value(forKey: "playerState")
        sleep(5)
        log("bind.bundleID", ["error": ((byID?.lastError() as NSError?)?.code).map(String.init) ?? "none",
                              "musicRelaunched": "\(music != nil)"])
    }

    // MARK: P1-e

    struct Album { let id: String; let title: String; let albumArtist: String; let artist: String; let tracks: [AlbumTrack] }

    func admittedAlbums() -> [Album] {
        guard let library = try? ITLibrary(apiVersion: "1.0") else { log("itlib.fail"); return [] }
        var titles: [(title: String, albumID: String)] = []
        var songs: [String: [(ITLibMediaItem, AlbumTrack)]] = [:]
        for item in library.allMediaItems {
            let albumID = String(format: "%016llX", item.album.persistentID.uint64Value)
            titles.append((item.album.title ?? "", albumID))
            guard item.mediaKind == .kindSong else { continue }
            let track = AlbumTrack(id: String(format: "%016llX", item.persistentID.uint64Value),
                                   disc: item.album.discNumber, number: item.trackNumber)
            songs[albumID, default: []].append((item, track))
        }
        let index = ShortcutGate.titleIndex(titles)
        return songs.compactMap { id, entries -> Album? in
            guard entries.count >= 2,
                  ShortcutGate.check(albumID: id, trackTitles: entries.map { $0.0.album.title ?? "" },
                                     tracks: entries.map(\.1), titleIndex: index) == nil
            else { return nil }
            let first = entries[0].0
            let artists = Set(entries.map { $0.0.artist?.name ?? "" })
            return Album(id: id, title: first.album.title ?? "", albumArtist: first.album.albumArtist ?? "",
                         artist: artists.count == 1 ? artists.first! : "", tracks: entries.map(\.1))
        }.sorted { $0.id < $1.id }
    }

    func timing() {
        let n = Int(args.first ?? "5") ?? 5
        let albums = admittedAlbums()
        log("albums", ["admitted": "\(albums.count)"])
        guard !albums.isEmpty else { return }
        var generator = SeededGenerator(seed: FP01Plan.seed &+ 4)
        for i in 0..<n {
            let album = albums[Int.random(in: 0..<albums.count, using: &generator)]
            guard let order = AlbumSuffix.ordered(album.tracks) else { continue }
            let position = FP01Plan.startPosition(trackCount: order.count, sampleIndex: i, seed: FP01Plan.seed &+ 4)
            let target = order[position - 1]
            let expected = Array(order[(position - 1)...])
            guard let file = writeInput(ShortcutInput(album: album.title, albumArtist: album.albumArtist, artist: album.artist,
                                                      position: position, expectedCount: order.count)) else { continue }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: shortcutsCLI)
            p.arguments = ["run", shortcutName, "--input-path", file.path]
            p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            let t0 = elapsed()
            var arrival: Double?, exit: Double?, stable: Double?
            var reads: [QueueRead] = []
            try? p.run()
            while elapsed() - t0 < 30 {
                let now = elapsed() - t0
                if exit == nil, !p.isRunning { exit = now }
                if arrival == nil, observe(music).track == target { arrival = now }
                if let e = exit, arrival != nil {
                    reads.append(QueueRead(at: now, ids: Self.queue()))
                    if let s = QueueSettle.stable(reads.filter { $0.at >= e }, minGap: 3) {
                        stable = now
                        log("sample", ["i": "\(i)", "tracks": "\(order.count)", "position": "\(position)",
                                       "arrival": String(format: "%.3f", arrival!), "exit": String(format: "%.3f", e),
                                       "stable": String(format: "%.3f", now), "queueMatches": "\(s == expected)",
                                       "exitCode": "\(p.terminationStatus)"])
                        break
                    }
                    usleep(500_000); continue
                }
                usleep(50_000)
            }
            if stable == nil {
                if p.isRunning { p.terminate() }
                log("sample.timeout", ["i": "\(i)", "arrival": arrival.map { String(format: "%.3f", $0) } ?? "-",
                                       "exit": exit.map { String(format: "%.3f", $0) } ?? "-"])
            }
            try? FileManager.default.removeItem(at: file)
            sleep(2)
        }
        // 量完暫停（事先已告知使用者）
        if let sb = music, observe(sb).state == 0x6B505350 { _ = sb.perform(Selector(("playpause"))) }
        log("timing.done")
    }
}

let argv = CommandLine.arguments
guard argv.count >= 3 else { exit(64) }
let probe = Probe(command: argv[1], out: URL(fileURLWithPath: argv[2]), args: Array(argv.dropFirst(3)))
DispatchQueue.global().async {
    probe.log("start")
    switch probe.command {
    case "sign": probe.sign()
    case "import": probe.importSigned()
    case "integrity": probe.integrity()
    case "tcc": probe.tcc()
    case "bind": probe.bind()
    case "timing": probe.timing()
    case "fs": probe.fsAccess()
    default: probe.log("unknownCommand")
    }
    probe.log("end")
    DispatchQueue.main.async { NSApp.terminate(nil) }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
