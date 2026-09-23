// 唯讀 spike（docs/plans/2026-09-23-coverflow-queue-drawer.md §8 S0／S1／SEQ-S）。
// 用完即棄的量測碼，不併入任何 target（slipknot 18）。
//
// 編譯（輸出放 scratch，不進 repo）：
//   swiftc -O -parse-as-library queue_spike.swift queue_spike_negative_control.swift -framework ScriptingBridge -o <scratch>/queue_spike
//
// 只讀保證（三道，任何一道不過都在送出第一個 Apple Event 之前退出）：
//   1. 執行期自檢：以 protocol_copyMethodDescriptionList 列出本檔 @objc 協議的全部選擇器，
//      必須 ⊆ 允許清單（只有 getter）、零 setter、零 required 方法。
//   2. Music 必須已在執行（NSRunningApplication）；以 pid 定址，Music 中途退出時 AE 失敗而不會把它叫起來。
//   3. 授權預檢 AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false)：未授權即退出、不彈授權框。
// 另：sendMode 帶 kAENeverInteract（Music 端不得彈任何互動）；每步新建 SBApplication、timeout 以 ticks（秒×60）設定。
// 輸出去識別化：曲目以 persistentID 的 SHA-256 前 8 碼表示；曲名只在明確帶 --show-titles 時印到終端。
import AppKit
import CoreServices
import CryptoKit
import Foundation
import ObjectiveC
import ScriptingBridge

// MARK: - 協議（只宣告 getter）

@objc(AZWSpikeAppProto) protocol SpikeAppProto {
    @objc optional var playerState: UInt32 { get }
    @objc optional var currentTrack: SBObject { get }
    @objc optional var currentPlaylist: SBObject { get }
    @objc optional var shuffleEnabled: Bool { get }
    @objc optional var shuffleMode: UInt32 { get }
    @objc optional var fixedIndexing: Bool { get }
}

@objc(AZWSpikeItemProto) protocol SpikeItemProto {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var persistentID: String { get }
    @objc optional var lyrics: String { get }
    @objc optional var discNumber: Int { get }
    @objc optional var trackNumber: Int { get }
    @objc optional var index: Int { get }
    @objc optional var specialKind: UInt32 { get }
    @objc optional func tracks() -> SBElementArray
}

extension SBApplication: SpikeAppProto {}
extension SBObject: SpikeItemProto {}

// MARK: - 自檢

enum SelfCheck {
    static let allowList: [String: Set<String>] = [
        "AZWSpikeAppProto": ["playerState", "currentTrack", "currentPlaylist", "shuffleEnabled", "shuffleMode", "fixedIndexing"],
        "AZWSpikeItemProto": [
            "name", "artist", "album", "persistentID", "lyrics", "discNumber", "trackNumber", "index", "specialKind", "tracks",
        ],
    ]

    static func selectors(of proto: Protocol) -> [(selector: String, required: Bool)] {
        var out: [(String, Bool)] = []
        for required in [true, false] {
            for instance in [true, false] {
                var count: UInt32 = 0
                guard let list = protocol_copyMethodDescriptionList(proto, required, instance, &count) else { continue }
                for i in 0..<Int(count) {
                    if let sel = list[i].name { out.append((NSStringFromSelector(sel), required)) }
                }
                free(list)
            }
        }
        return out
    }

    /// 每個選擇器至多一條違規（required 另計）
    static func violations(protocolName: String, allowed: Set<String>) -> [String] {
        guard let proto = NSProtocolFromString(protocolName) else {
            return ["\(protocolName): runtime 找不到協議（無法自檢＝拒跑）"]
        }
        var out: [String] = []
        for (sel, required) in selectors(of: proto) {
            if required { out.append("\(protocolName): required \(sel)") }
            if sel.hasPrefix("set") {
                out.append("\(protocolName): setter \(sel)")
            } else if !allowed.contains(sel) {
                out.append("\(protocolName): 不在允許清單 \(sel)")
            }
        }
        return out
    }

    /// SB 類別上掛的 AZW 前綴協議只能是允許的那幾個（防「另開協議再 extension」繞過）
    static func conformanceViolations() -> [String] {
        var out: [String] = []
        for cls in [SBObject.self, SBApplication.self] as [AnyClass] {
            var count: UInt32 = 0
            guard let list = class_copyProtocolList(cls, &count) else { continue }
            for i in 0..<Int(count) {
                let name = NSStringFromProtocol(list[i])
                if name.hasPrefix("AZW"), allowList[name] == nil {
                    out.append("\(NSStringFromClass(cls)) 掛了未允許的協議 \(name)")
                }
            }
        }
        return out
    }

    static func productionViolations() -> [String] {
        allowList.flatMap { violations(protocolName: $0.key, allowed: $0.value) } + conformanceViolations()
    }

    /// 負對照（queue_spike_negative_control.swift）：必須恰好抓到 4 條
    static func negativeControlViolations() -> [String] {
        _ = SpikeNegativeControlAnchor.protocolName
        return violations(protocolName: SpikeNegativeControlAnchor.protocolName, allowed: ["shuffleEnabled"])
    }
}

// MARK: - 共用

let musicBundleID = "com.apple.Music"
let clock = ContinuousClock()

func fail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write(Data("SPIKE STOP(\(code)): \(message)\n".utf8))
    exit(code)
}

func hashID(_ id: String?) -> String {
    guard let id, !id.isEmpty else { return "<empty>" }
    return SHA256.hash(data: Data(id.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
}

func ms(_ d: Duration) -> Double {
    Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

func stats(_ values: [Double]) -> String {
    guard !values.isEmpty else { return "n=0" }
    let s = values.sorted()
    let p = { (q: Double) in s[min(s.count - 1, Int((Double(s.count - 1) * q).rounded()))] }
    return String(format: "n=%d p50=%.1fms p95=%.1fms max=%.1fms", s.count, p(0.5), p(0.95), s.last!)
}

func fourCC(_ v: UInt32) -> String {
    String([24, 16, 8, 0].compactMap { Unicode.Scalar((v >> UInt32($0)) & 0xFF).map(Character.init) })
}

/// 前置 2＋3：Music 已執行、已授權。回傳 pid
func preflight() -> pid_t {
    guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleID).first else {
        fail(3, "Music 未執行——不送任何 Apple Event（也不啟動它）")
    }
    let pid = running.processIdentifier
    let target = NSAppleEventDescriptor(processIdentifier: pid)
    let status = AEDeterminePermissionToAutomateTarget(
        target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false
    )
    guard status == OSStatus(noErr) else {
        fail(4, "自動化授權預檢未通過 status=\(status)（-1744＝需使用者同意、-1743＝被拒）；不彈框、不送 AE")
    }
    return pid
}

/// 每步新建：與 production 的 run() 同形；pid 定址 → Music 退出時 AE 失敗而非重新啟動
func makeApp(pid: pid_t, timeoutSeconds: Double) -> SBApplication {
    guard let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated else {
        fail(5, "Music 已退出——停止，不重新啟動")
    }
    guard let app = SBApplication(processIdentifier: pid) else { fail(6, "SBApplication(processIdentifier:) 為 nil") }
    app.sendMode = AESendMode(kAEWaitReply | kAENeverInteract | kAEDontRecord)
    app.timeout = Int(timeoutSeconds * 60)      // 單位 ticks
    return app
}

func lastErrorText(_ app: SBApplication) -> String {
    guard let error = app.lastError() as NSError? else { return "ok" }
    return "AE error \(error.code)"
}

func pinnedCurrentTrack(_ app: SBApplication) -> SBObject? {
    guard let ref = (app as SpikeAppProto).currentTrack else { return nil }
    return ref.get() as? SBObject
}

/// 描述只保留類別碼與數字 id 的骨架（不含任何名稱）
func specifierSkeleton(_ object: SBObject?) -> String {
    guard let object else { return "nil" }
    return String(describing: object)
        .replacingOccurrences(of: #"0x[0-9a-f]+"#, with: "0x…", options: .regularExpression)
}

// MARK: - 模式

/// S0：只自檢，不送任何 AE
func runSelfCheck() {
    let production = SelfCheck.productionViolations()
    let negative = SelfCheck.negativeControlViolations()
    print("SELFCHECK production violations=\(production.count)")
    production.forEach { print("  \($0)") }
    print("SELFCHECK negative-control violations=\(negative.count)（期望 4）")
    negative.forEach { print("  \($0)") }
    exit(production.isEmpty && negative.count == 4 ? 0 : 1)
}

/// S1：當前曲讀取——釘住 vs 未釘住
func runNowPlaying(pid: pid_t, iterations: Int) {
    var pinnedTimes: [Double] = [], unpinnedTimes: [Double] = []
    var agree = 0, disagree = 0, errors: [String] = []
    for i in 0..<iterations {
        let app = makeApp(pid: pid, timeoutSeconds: 2)
        var pinnedPID = "", fields: [Any?] = []
        let t1 = clock.measure {
            guard let track = pinnedCurrentTrack(app) else { return }
            let item = track as SpikeItemProto
            pinnedPID = item.persistentID ?? ""
            fields = [item.name, item.artist, item.album, item.discNumber, item.trackNumber, item.lyrics.map { $0.count }]
            if i == 0 { print("S1 pinned specifier: \(specifierSkeleton(track))") }
        }
        let e1 = lastErrorText(app)
        pinnedTimes.append(ms(t1))

        // 對照：現行 production 形狀（未釘住，逐屬性各自重新解析 current track；歌詞另一次）
        let app2 = makeApp(pid: pid, timeoutSeconds: 2)
        var unpinnedPID = ""
        let t2 = clock.measure {
            guard let ref = (app2 as SpikeAppProto).currentTrack else { return }
            let item = ref as SpikeItemProto
            unpinnedPID = item.persistentID ?? ""
            _ = [item.name, item.artist, item.album] as [String?]
            _ = [item.discNumber, item.trackNumber] as [Int?]
            _ = item.lyrics
        }
        let e2 = lastErrorText(app2)
        unpinnedTimes.append(ms(t2))
        if e1 != "ok" || e2 != "ok" { errors.append("iter \(i): pinned=\(e1) unpinned=\(e2)") }
        if pinnedPID == unpinnedPID { agree += 1 } else { disagree += 1 }
        if i == 0 { print("S1 fields-read=\(fields.filter { $0 != nil }.count)/6 pid=\(hashID(pinnedPID))") }
    }
    print("S1 pinned   \(stats(pinnedTimes))")
    print("S1 unpinned \(stats(unpinnedTimes))")
    print("S1 pid agree=\(agree) disagree=\(disagree)（disagree＞0 可能只是讀取間換歌）")
    errors.forEach { print("S1 \($0)") }
}

/// S1b：findTrack 路徑（全庫以 persistentID 過濾）
func runFindTrack(pid: pid_t, iterations: Int) {
    let app0 = makeApp(pid: pid, timeoutSeconds: 2)
    guard let current = pinnedCurrentTrack(app0), let target = (current as SpikeItemProto).persistentID, !target.isEmpty
    else { fail(7, "讀不到當前曲 persistentID：\(lastErrorText(app0))") }
    var times: [Double] = [], found = 0
    for _ in 0..<iterations {
        let app = makeApp(pid: pid, timeoutSeconds: 5)
        var hit = false
        let t = clock.measure {
            guard let all = (app as SpikeItemProto).tracks?() else { return }
            let matches = all.filtered(using: NSPredicate(format: "persistentID == %@", target))
            hit = ((matches.first as? SBObject) as SpikeItemProto?)?.persistentID == target
        }
        times.append(ms(t))
        if hit { found += 1 }
        let e = lastErrorText(app)
        if e != "ok" { print("S1b \(e)") }
    }
    print("S1b findTrack(pid=\(hashID(target))) found=\(found)/\(iterations) \(stats(times))")
}

struct QueueRow {
    let position: Int      // 1-based，在釘住的當前清單內
    let pid: String
    let title: String
    let hasLyrics: Bool?
}

func readRow(_ tracks: SBElementArray, position: Int, withLyrics: Bool) -> QueueRow {
    let item = (tracks.object(at: position - 1) as! SBObject) as SpikeItemProto
    let title = "\(item.name ?? "?") — \(item.artist ?? "?")"
    let lyrics = withLyrics ? item.lyrics.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } : nil
    return QueueRow(position: position, pid: item.persistentID ?? "", title: title, hasLyrics: lyrics)
}

/// SEQ-S：當前清單的順序是否＝實際播放順序（含隨機）
func runQueue(pid: pid_t, window: Int, showTitles: Bool) {
    let app = makeApp(pid: pid, timeoutSeconds: 5)
    let proto = app as SpikeAppProto
    print("Q shuffleEnabled=\(proto.shuffleEnabled.map(String.init) ?? "nil") shuffleMode=\(proto.shuffleMode.map(fourCC) ?? "nil") fixedIndexing=\(proto.fixedIndexing.map(String.init) ?? "nil") [\(lastErrorText(app))]")

    guard let playlistRef = proto.currentPlaylist, let playlist = playlistRef.get() as? SBObject else {
        fail(8, "讀不到 current playlist：\(lastErrorText(app))")
    }
    let pl = playlist as SpikeItemProto
    print("Q playlist specifier: \(specifierSkeleton(playlist)) specialKind=\(pl.specialKind.map(fourCC) ?? "nil")")
    if showTitles { print("Q playlist name: \(pl.name ?? "?")") }
    guard let tracks = pl.tracks?() else { fail(9, "playlist.tracks() nil") }
    var count = 0
    let tCount = clock.measure { count = tracks.count }
    print(String(format: "Q playlist count=%d (%.1fms)", count, ms(tCount)))

    guard let current = pinnedCurrentTrack(app) else { fail(10, "讀不到 current track：\(lastErrorText(app))") }
    let currentItem = current as SpikeItemProto
    let currentPID = currentItem.persistentID ?? ""
    let currentIndex = currentItem.index ?? -1
    print("Q current track specifier: \(specifierSkeleton(current)) index=\(currentIndex) pid=\(hashID(currentPID))")

    // 驗證 index 指向的就是當前曲
    if currentIndex >= 1, currentIndex <= count {
        let atIndex = readRow(tracks, position: currentIndex, withLyrics: false)
        print("Q playlist[index].pid == current? \(atIndex.pid == currentPID)")
    }

    // 批次取 persistentID（小清單才做）：找當前曲在清單中的位置，與 index 比對
    if count > 0, count <= 2000 {
        var ids: [String] = []
        let tBulk = clock.measure {
            ids = tracks.array(byApplying: #selector(getter: SpikeItemProto.persistentID)).compactMap { $0 as? String }
        }
        let positions = ids.enumerated().filter { $0.element == currentPID }.map { $0.offset + 1 }
        print(String(format: "Q bulk persistentID n=%d (%.1fms) current at positions=%@", ids.count, ms(tBulk), positions.description))
    } else {
        print("Q bulk persistentID skipped (count=\(count) > 2000)")
    }

    guard currentIndex >= 1 else { print("Q no usable index — stop"); return }
    var rows: [QueueRow] = []
    let tWindow = clock.measure {
        let lower = max(1, currentIndex - window), upper = min(count, currentIndex + window)
        for position in lower...upper {
            rows.append(readRow(tracks, position: position, withLyrics: true))
        }
    }
    print(String(format: "Q window ±%d rows=%d (%.1fms, %.1fms/row) [%@]", window, rows.count, ms(tWindow), ms(tWindow) / Double(max(rows.count, 1)), lastErrorText(app)))
    for row in rows {
        let offset = row.position - currentIndex
        let marker = offset == 0 ? "▶" : (offset > 0 ? "+\(offset)" : "\(offset)")
        let lyric = row.hasLyrics.map { $0 ? "✓" : "✗" } ?? "?"
        let label = showTitles ? row.title : hashID(row.pid)
        print("Q \(marker.padding(toLength: 4, withPad: " ", startingAt: 0)) \(lyric) \(label)")
    }
}

/// SEQ-S 被動命中率：不動播放，等自然換歌，比對「換歌前預測的下一首」
func runWatch(pid: pid_t, minutes: Double) {
    let deadline = clock.now.advanced(by: .seconds(minutes * 60))
    var lastPID: String?
    var predictedNext: String?
    var predictedWindow: [String] = []
    var changes = 0, hits = 0, windowHits = 0
    print("W watching \(minutes) min, poll 3s")
    while clock.now < deadline {
        let app = makeApp(pid: pid, timeoutSeconds: 2)
        if let track = pinnedCurrentTrack(app) {
            let item = track as SpikeItemProto
            let pidNow = item.persistentID ?? ""
            if pidNow != lastPID {
                if lastPID != nil {
                    changes += 1
                    let hit = pidNow == predictedNext
                    let inWindow = predictedWindow.contains(pidNow)
                    if hit { hits += 1 }
                    if inWindow { windowHits += 1 }
                    let shuffle = (app as SpikeAppProto).shuffleEnabled.map(String.init) ?? "nil"
                    print("W change#\(changes) \(hit ? "HIT" : "MISS") inNext5=\(inWindow) shuffle=\(shuffle) new=\(hashID(pidNow)) predicted=\(hashID(predictedNext))")
                }
                lastPID = pidNow
                // 以新曲重新預測：釘住當前清單，取 index 之後的 1 首與 5 首
                let appQ = makeApp(pid: pid, timeoutSeconds: 3)
                if let playlist = (appQ as SpikeAppProto).currentPlaylist?.get() as? SBObject,
                   let tracks = (playlist as SpikeItemProto).tracks?(),
                   let current = pinnedCurrentTrack(appQ),
                   let index = (current as SpikeItemProto).index {
                    let count = tracks.count
                    let next = (index + 1)...min(count, index + 5)
                    predictedWindow = next.isEmpty ? [] : next.map { readRow(tracks, position: $0, withLyrics: false).pid }
                    predictedNext = predictedWindow.first
                } else {
                    predictedWindow = []
                    predictedNext = nil
                    print("W predict failed: \(lastErrorText(appQ))")
                }
            }
        }
        Thread.sleep(forTimeInterval: 3)
    }
    print("W done changes=\(changes) hits=\(hits) inNext5=\(windowHits)")
}

/// Queue.dat（Music 自存的待播清單檔）與 AE 當前曲的一致性：只讀檔案，不寫、不鎖
func queueFileHead() -> (pid: String, count: Int, mtime: Date)? {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music/Music/Music Library.musiclibrary/Preferences/Queue.dat")
    guard let data = try? Data(contentsOf: url),
          let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let segments = root["sega"] as? [[String: Any]],
          let items = ((segments.first?["items"] as? [String: Any])?["list"] as? [String: Any])?["items"] as? [String: Any],
          let list = items["iar"] as? [[String: Any]],
          let first = list.first,
          let spec = (first["pm"] as? [String: Any])?["piObjSpec"] as? [String: Any],
          let tid = (spec["tID"] as? NSNumber)?.int64Value,
          let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let mtime = attrs[.modificationDate] as? Date
    else { return nil }
    return (String(format: "%016llX", UInt64(bitPattern: tid)), list.count, mtime)
}

func runQueueFileWatch(pid: pid_t, minutes: Double) {
    let deadline = clock.now.advanced(by: .seconds(minutes * 60))
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"
    var last = ""
    print("QF watching \(minutes) min, poll 3s")
    while clock.now < deadline {
        let app = makeApp(pid: pid, timeoutSeconds: 2)
        let current = pinnedCurrentTrack(app).flatMap { ($0 as SpikeItemProto).persistentID } ?? ""
        let state = (app as SpikeAppProto).playerState.map(fourCC) ?? "nil"
        let head = queueFileHead()
        let line = "current=\(hashID(current)) file0=\(hashID(head?.pid)) match=\(head?.pid == current) n=\(head?.count ?? -1) mtime=\(head.map { fmt.string(from: $0.mtime) } ?? "nil") state=\(state)"
        if line != last {
            print("QF \(fmt.string(from: Date())) \(line)")
            fflush(stdout)
            last = line
        }
        Thread.sleep(forTimeInterval: 3)
    }
    print("QF done")
}

/// S6：卡片詳情批次讀取成本（Queue.dat 前 N 個 persistentID）
func queueFileIDs(limit: Int) -> [String] {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music/Music/Music Library.musiclibrary/Preferences/Queue.dat")
    guard let data = try? Data(contentsOf: url),
          let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let segments = root["sega"] as? [[String: Any]],
          let items = ((segments.first?["items"] as? [String: Any])?["list"] as? [String: Any])?["items"] as? [String: Any],
          let list = items["iar"] as? [[String: Any]]
    else { return [] }
    return list.prefix(limit).compactMap { item in
        guard let spec = (item["pm"] as? [String: Any])?["piObjSpec"] as? [String: Any],
              let tid = (spec["tID"] as? NSNumber)?.int64Value else { return nil }
        return String(format: "%016llX", UInt64(bitPattern: tid))
    }
}

func runDetails(pid: pid_t, count: Int, iterations: Int) {
    let ids = queueFileIDs(limit: count)
    guard !ids.isEmpty else { fail(11, "Queue.dat 讀不到 persistentID") }
    print("S6 ids=\(ids.count)")

    // (a) 逐首：全庫 persistentID 過濾 → 4 屬性
    var perTrack: [Double] = [], foundA = 0
    for _ in 0..<iterations {
        let app = makeApp(pid: pid, timeoutSeconds: 3)
        var found = 0
        let t = clock.measure {
            guard let all = (app as SpikeItemProto).tracks?() else { return }
            for id in ids {
                guard let obj = all.filtered(using: NSPredicate(format: "persistentID == %@", id)).first as? SBObject else { continue }
                let item = obj as SpikeItemProto
                if item.persistentID == id { found += 1 }
                _ = [item.name, item.artist, item.album] as [String?]
                _ = item.lyrics.map { $0.isEmpty }
            }
        }
        perTrack.append(ms(t)); foundA = found
        let e = lastErrorText(app); if e != "ok" { print("S6a \(e)") }
    }
    print("S6a per-track found=\(foundA)/\(ids.count) \(stats(perTrack))")

    // (b) OR 串接 whose 一次取元素 → 逐屬性批次
    var batched: [Double] = [], foundB = 0, bridged = true
    for _ in 0..<iterations {
        let app = makeApp(pid: pid, timeoutSeconds: 3)
        var found = 0
        let t = clock.measure {
            guard let all = (app as SpikeItemProto).tracks?() else { return }
            let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: ids.map { NSPredicate(format: "persistentID == %@", $0) })
            let matches = all.filtered(using: predicate)
            guard let elements = (matches as NSArray) as? SBElementArray else { bridged = false; return }
            let pids = elements.array(byApplying: #selector(getter: SpikeItemProto.persistentID)).compactMap { $0 as? String }
            _ = elements.array(byApplying: #selector(getter: SpikeItemProto.name))
            _ = elements.array(byApplying: #selector(getter: SpikeItemProto.artist))
            _ = elements.array(byApplying: #selector(getter: SpikeItemProto.album))
            let lyrics = elements.array(byApplying: #selector(getter: SpikeItemProto.lyrics))
            found = Set(pids).intersection(ids).count
            _ = lyrics.count
        }
        batched.append(ms(t)); foundB = found
        let e = lastErrorText(app); if e != "ok" { print("S6b \(e)") }
    }
    print("S6b batched bridgedAsSBElementArray=\(bridged) found=\(foundB)/\(ids.count) \(stats(batched))")
}

/// S8：Queue.dat 行為矩陣觀察（使用者操作 Music；本程式只讀檔＋讀當前曲，Music 未執行時不送 AE、不啟動它）
struct QueueEntry { let pid: String; let itID: Int64 }

func queueFileEntries() -> (entries: [QueueEntry], size: Int, mtime: Date, hash: String)? {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music/Music/Music Library.musiclibrary/Preferences/Queue.dat")
    guard let before = try? FileManager.default.attributesOfItem(atPath: url.path),
          let data = try? Data(contentsOf: url),
          let after = try? FileManager.default.attributesOfItem(atPath: url.path),
          (before[.size] as? Int) == (after[.size] as? Int),
          (before[.modificationDate] as? Date) == (after[.modificationDate] as? Date),
          let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let segments = root["sega"] as? [[String: Any]],
          let items = ((segments.first?["items"] as? [String: Any])?["list"] as? [String: Any])?["items"] as? [String: Any],
          let list = items["iar"] as? [[String: Any]]
    else { return nil }
    let entries = list.compactMap { item -> QueueEntry? in
        guard let spec = (item["pm"] as? [String: Any])?["piObjSpec"] as? [String: Any],
              let tid = (spec["tID"] as? NSNumber)?.int64Value else { return nil }
        return QueueEntry(pid: String(format: "%016llX", UInt64(bitPattern: tid)), itID: (item["itID"] as? NSNumber)?.int64Value ?? -1)
    }
    let hash = SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
    return (entries, data.count, (after[.modificationDate] as? Date) ?? .distantPast, hash)
}

func runMatrixWatch(minutes: Double) {
    let deadline = clock.now.advanced(by: .seconds(minutes * 60))
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"
    var last = ""
    var checkedPID: pid_t = 0
    print("S8 watching \(minutes) min, poll 3s")
    while clock.now < deadline {
        var parts: [String] = []
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleID).first {
            let pid = running.processIdentifier
            if pid != checkedPID {
                let target = NSAppleEventDescriptor(processIdentifier: pid)
                let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
                guard status == OSStatus(noErr) else { fail(4, "授權預檢未通過 status=\(status)") }
                checkedPID = pid
            }
            let app = makeApp(pid: pid, timeoutSeconds: 2)
            let current = pinnedCurrentTrack(app).flatMap { ($0 as SpikeItemProto).persistentID } ?? ""
            let state = (app as SpikeAppProto).playerState.map(fourCC) ?? "nil"
            parts.append("music=pid\(pid) state=\(state) current=\(hashID(current))")
            if let file = queueFileEntries() {
                let occurrences = file.entries.enumerated().filter { $0.element.pid == current }.map { $0.offset }
                let around = occurrences.first.map { i in
                    (max(0, i - 1)...min(file.entries.count - 1, i + 2)).map { "\($0):\(file.entries[$0].itID)" }.joined(separator: ",")
                } ?? "-"
                parts.append("file n=\(file.entries.count) mtime=\(fmt.string(from: file.mtime)) hash=\(file.hash) currentAt=\(occurrences) itIDs[\(around)] dupPIDs=\(file.entries.count - Set(file.entries.map(\.pid)).count)")
            } else {
                parts.append("file=unreadable-or-missing")
            }
        } else {
            checkedPID = 0
            parts.append("music=not-running")
            parts.append(queueFileEntries().map { "file n=\($0.entries.count) mtime=\(fmt.string(from: $0.mtime)) hash=\($0.hash)" } ?? "file=unreadable-or-missing")
        }
        let line = parts.joined(separator: " ")
        if line != last {
            print("S8 \(fmt.string(from: Date())) \(line)")
            fflush(stdout)
            last = line
        }
        Thread.sleep(forTimeInterval: 3)
    }
    print("S8 done")
}

// MARK: - main

@main
enum QueueSpikeMain {
    static func main() {
        let args = CommandLine.arguments.dropFirst()
        let mode = args.first ?? "selfcheck"
        let showTitles = args.contains("--show-titles")
        let numbers = args.compactMap { Double($0) }

        // 自檢永遠先跑；不過就在任何 AE 之前退出
        let production = SelfCheck.productionViolations()
        let injectNegative = ProcessInfo.processInfo.environment["SPIKE_INJECT_NEGATIVE"] == "1"
        let blocking = production + (injectNegative ? SelfCheck.negativeControlViolations() : [])
        if !blocking.isEmpty {
            blocking.forEach { FileHandle.standardError.write(Data("SELFCHECK VIOLATION \($0)\n".utf8)) }
            fail(2, "自檢未通過，未送任何 Apple Event")
        }
        if mode == "selfcheck" { runSelfCheck() }
        if mode == "matrix" { runMatrixWatch(minutes: numbers.first ?? 30); exit(0) }

        let pid = preflight()
        switch mode {
        case "nowplaying": runNowPlaying(pid: pid, iterations: Int(numbers.first ?? 20))
        case "findtrack": runFindTrack(pid: pid, iterations: Int(numbers.first ?? 5))
        case "queue": runQueue(pid: pid, window: Int(numbers.first ?? 10), showTitles: showTitles)
        case "watch": runWatch(pid: pid, minutes: numbers.first ?? 15)
        case "queuefile": runQueueFileWatch(pid: pid, minutes: numbers.first ?? 15)
        case "matrix": runMatrixWatch(minutes: numbers.first ?? 30)
        case "details": runDetails(pid: pid, count: Int(numbers.first ?? 20), iterations: Int(numbers.dropFirst().first ?? 10))
        case "preflight": print("PREFLIGHT ok pid=\(pid)")
        default: fail(1, "未知模式 \(mode)")
        }
    }
}
