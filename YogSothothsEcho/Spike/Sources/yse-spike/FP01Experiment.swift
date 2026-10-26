import Foundation
import iTunesLibrary
import SpikeCore

// F-P-01 點歌脈絡（s0-report.md「F-P-01 點歌脈絡：N1 後續方案」）。
// ② n1-library：只記事實。③ fp01-preflight／fp01：捷徑點歌，曲目、Mac 段延遲、佇列三項各自判定。
// 結果檔只記 ID 與數值；專輯名只送進捷徑的 stdin，不寫檔、不印出。
@MainActor
extension Experiments {
    static let fp01PlayTimeout: Duration = .seconds(5)
    static let queueSettleTimeout: Duration = .seconds(15)
    static let queueReadEvery: Duration = .milliseconds(500)
    /// 2026-10-15 n1-library 首跑：跨 1 s 穩定仍讀到點歌前的舊佇列（Queue.dat 延遲寫入），故拉長到 3 s
    static let queueMinGap = 3.0

    // MARK: 曲庫（ITLibrary，唯讀）

    struct AlbumEntry {
        let id: String
        let title: String
        let albumArtist: String
        let artist: String
        let tracks: [AlbumTrack]
        let multiDisc: Bool
        /// nil＝可交給捷徑；否則降級為只播這首（ShortcutGate）
        let refusal: ShortcutGate.Refusal?
    }

    static func hex(_ number: NSNumber) -> String { String(format: "%016llX", number.uint64Value) }

    /// 可當樣本的專輯：有專輯名、≥ 2 首、曲序有定義。專輯藝人可空（約半數沒填）。
    /// 是否可交給捷徑由 ShortcutGate 判定；名稱索引用曲庫「全部」項目（不限歌曲），查找可能撈到的都算進去
    static func albumCatalog() throws -> (albums: [AlbumEntry], excluded: [String: Int], libraryID: String?) {
        let library = try ITLibrary(apiVersion: "1.0")
        let titleIndex = ShortcutGate.titleIndex(library.allMediaItems.compactMap { item in
            item.album.title.map { (title: $0, albumID: hex(item.album.persistentID)) }
        })
        let songs = library.allMediaItems.filter { $0.mediaKind == .kindSong }
        let grouped = Dictionary(grouping: songs) { hex($0.album.persistentID) }
        var excluded: [String: Int] = [:]
        var albums: [AlbumEntry] = []
        for (id, items) in grouped {
            let tracks = items.map { AlbumTrack(id: hex($0.persistentID), disc: $0.album.discNumber, number: $0.trackNumber) }
            guard let title = items[0].album.title, !title.isEmpty else { excluded["no-title", default: 0] += 1; continue }
            guard tracks.count >= 2 else { excluded["single-track", default: 0] += 1; continue }
            guard AlbumSuffix.ordered(tracks) != nil else { excluded["order-undefined", default: 0] += 1; continue }
            let artists = Set(items.map { $0.artist?.name ?? "" })
            let refusal = ShortcutGate.check(albumID: id, trackTitles: items.map { $0.album.title ?? "" }, tracks: tracks,
                                             titleIndex: titleIndex)
            albums.append(AlbumEntry(id: id, title: title, albumArtist: items[0].album.albumArtist ?? "",
                                     artist: artists.count == 1 ? artists.first ?? "" : "", tracks: tracks,
                                     multiDisc: Set(tracks.map { max($0.disc, 1) }).count > 1, refusal: refusal))
        }
        let libraryID = library.allPlaylists.first(where: \.isPrimary).map { hex($0.persistentID) }
        return (albums, excluded, libraryID)
    }

    /// 閘門拒絕的原因計數（分母＝可用專輯數）
    static func refusalCounts(_ albums: [AlbumEntry]) -> [String: Int] {
        albums.reduce(into: [:]) { counts, album in
            if let refusal = album.refusal { counts[refusal.rawValue, default: 0] += 1 }
        }
    }

    /// 只從閘門放行的專輯依類型分層抽 count 張（每層先取 1 張），起點 k 依種子
    static func fp01Samples(_ albums: [AlbumEntry], count: Int) -> [(album: AlbumEntry, position: Int)] {
        let allowed = albums.filter { $0.refusal == nil }
        let byID = Dictionary(uniqueKeysWithValues: allowed.map { ($0.id, $0) })
        let picked = StratifiedSampler.sample(allowed.map { ($0.id, FP01Plan.kind(multiDisc: $0.multiDisc, sharedTitle: false)) },
                                              count: count, seed: FP01Plan.seed)
        return picked.enumerated().compactMap { index, id in
            byID[id].map { ($0, FP01Plan.startPosition(trackCount: $0.tracks.count, sampleIndex: index, seed: FP01Plan.seed)) }
        }
    }

    // MARK: ② n1-library（只記事實）

    struct N1LibraryRecord: Encodable {
        let specifier = "library-playlist-by-persistent-id"
        let found: Bool
        let playlistTrackCount: Int?
        let startIndex: Int
        let albumFollowing: [String]
        let settledQueue: [String]?
    }

    static func n1Library() async -> Bool {
        let libraryID: String?
        do { libraryID = try albumCatalog().libraryID } catch { print("ITLibrary 讀不到：\(error)"); return false }
        guard let libraryID else { print("找不到資料庫清單"); return false }
        return await run("n1-library", budget: .n1) { session in
            let (oracle, _) = try oracle(session)
            let startIndex = 2
            let target = oracle.sequence[startIndex]
            let played = try await session.command { session.bridge.play(trackID: target, inPlaylist: libraryID) }
            let reached = await session.waitFor(session.bridge.currentTrackID) { $0 == target }.matchedAt != nil
            guard reached else { throw Session.Stop.precondition("點歌後 2 s 內目前曲不是目標曲") }
            return [N1LibraryRecord(found: played.value.found, playlistTrackCount: played.value.playlistTrackCount,
                                    startIndex: startIndex, albumFollowing: Array(oracle.sequence.dropFirst(startIndex + 1)),
                                    settledQueue: await settledQueue())]
        }
    }

    // MARK: ③ 捷徑

    /// 間隔讀 Queue.dat，同一序列跨越 queueMinGap 才算穩定；逾時回 nil。呼叫前須已確認目前曲＝目標曲
    static func settledQueue() async -> [String]? {
        let start = ContinuousClock.now
        var reads: [QueueRead] = []
        while ContinuousClock.now - start < queueSettleTimeout {
            let elapsed = ContinuousClock.now - start
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            reads.append(QueueRead(at: seconds, ids: MusicFileReader.queue().ids))
            if let stable = QueueSettle.stable(reads, minGap: queueMinGap) { return stable }
            try? await Task.sleep(for: queueReadEvery)
        }
        return nil
    }

    /// 一個樣本：發起 → 輪詢到 Music 正在播目標曲（延遲終點）→ 等捷徑結束 → 佇列穩定後比對
    static func fp01Sample(_ session: Session, shortcut: String, album: AlbumEntry, position: Int,
                           label: String) async throws -> FP01Sample {
        guard album.refusal == nil else { throw Session.Stop.precondition("閘門未放行的專輯不得交給捷徑") }
        guard let order = AlbumSuffix.ordered(album.tracks) else { throw Session.Stop.precondition("曲序無定義") }
        let startID = order[position - 1]
        let input = try ShortcutInput(album: album.title, albumArtist: album.albumArtist, artist: album.artist,
                                      position: position, expectedCount: order.count).json()
        try session.reserve()
        let started = ContinuousClock.now
        let running = try ShortcutRunner.start(name: shortcut, input: input)
        var latency: Double?
        while ContinuousClock.now - started < fp01PlayTimeout {
            if session.bridge.currentTrackID().value == startID, session.bridge.state().value == .playing {
                let elapsed = ContinuousClock.now - started
                latency = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let outcome = await ShortcutRunner.finish(running, label: label)
        let settled = await settledQueue()
        return FP01Sample(albumID: album.id, position: position, trackCount: album.tracks.count,
                          multiDisc: album.multiDisc, sharedTitle: false, exitCode: outcome.exitCode,
                          latencyMilliseconds: latency, readID: session.bridge.currentTrackID().value,
                          state: session.bridge.state().value, expectedStartID: startID, settledQueue: settled,
                          expectedQueue: Array(order[(position - 1)...]))
    }

    struct PreflightStep: Encodable {
        let step: String
        let exitCode: Int32?
        let timedOut: Bool
        /// 失敗路徑不該動到 Music：前後目前曲、播放狀態、佇列是否改變
        let musicChanged: Bool
        /// 變動的部分：track／state／queue（queue-unreadable＝讀不到穩定佇列）
        let changedParts: [String]
    }

    /// 異常輸入一覽（s0-report「C 案」步驟 3，A 沿用）：每項都不得播放或改動佇列
    static func malformedInputs(_ album: AlbumEntry) throws -> [(String, Data)] {
        let count = album.tracks.count
        func input(album title: String, position: Int, expectedCount: Int) throws -> Data {
            try ShortcutInput(album: title, albumArtist: album.albumArtist, artist: album.artist, position: position,
                              expectedCount: expectedCount).json()
        }
        return [
            ("malformed-json", Data("{".utf8)),
            ("empty-object", Data("{}".utf8)),
            ("empty-album", try input(album: "", position: 1, expectedCount: count)),
            ("unknown-album", try input(album: "yse-fp01-unknown-\(UInt32.random(in: 0...UInt32.max))", position: 1,
                                        expectedCount: count)),
            ("missing-count", Data(#"{"album":"x","position":1}"#.utf8)),
            ("count-as-string", Data(#"{"album":"x","expectedCount":"2","position":1}"#.utf8)),
            ("count-mismatch", try input(album: album.title, position: 1, expectedCount: count + 1)),
            ("position-out-of-range", try input(album: album.title, position: count + 1, expectedCount: count)),
        ]
    }

    /// 佇列取「穩定後」的值（Queue.dat 延遲寫入）；讀不到＝nil，比對時視為有變動（fail-closed）
    static func musicSnapshot(_ session: Session) async -> (String?, PlayerStateValue?, [String]?) {
        let queue = await settledQueue()
        return (session.bridge.currentTrackID().value, session.bridge.state().value, queue)
    }

    struct FP01PreflightRecord: Encodable {
        let steps: [PreflightStep]
        let success: FP01Sample?
    }

    /// 非互動與失敗路徑可辨（捷徑不存在、無輸入、格式錯誤），再走一次成功路徑（優先多 disc 專輯）
    static func fp01Preflight(shortcut: String) async -> Bool {
        let albums: [AlbumEntry]
        do { albums = try albumCatalog().albums } catch { print("ITLibrary 讀不到：\(error)"); return false }
        let allowed = albums.filter { $0.refusal == nil }
        guard let probe = allowed.first(where: \.multiDisc) ?? allowed.first else { print("沒有閘門放行的專輯"); return false }
        return await run("fp01-preflight", budget: .fp01) { session in
            var steps: [PreflightStep] = []
            let failures: [(String, String, Data?)] = [
                ("missing-shortcut", "yse-fp01-missing-\(UInt32.random(in: 0...UInt32.max))", Data("{}".utf8)),
                ("no-input", shortcut, nil),
            ] + (try malformedInputs(probe)).map { ($0.0, shortcut, $0.1) }
            var before = await musicSnapshot(session)
            for (step, name, input) in failures {
                try session.reserve()
                let running = try ShortcutRunner.start(name: name, input: input)
                let outcome = await ShortcutRunner.finish(running, label: step)
                let after = await musicSnapshot(session)
                let parts = [before.0 != after.0 ? "track" : nil, before.1 != after.1 ? "state" : nil,
                             before.2 == nil || after.2 == nil ? "queue-unreadable" : before.2 != after.2 ? "queue" : nil]
                    .compactMap { $0 }
                steps.append(PreflightStep(step: step, exitCode: outcome.exitCode, timedOut: outcome.timedOut,
                                           musicChanged: !parts.isEmpty, changedParts: parts))
                before = after
                print("preflight \(step)：exit \(outcome.exitCode.map(String.init) ?? "逾時")、Music \(steps.last!.changedParts.isEmpty ? "未動" : "變動 \(steps.last!.changedParts)")")
            }
            let success = try await fp01Sample(session, shortcut: shortcut, album: probe, position: 1, label: "success")
            print("preflight 成功路徑：曲目 \(success.trackCorrect)、佇列 \(success.queueCorrect)、延遲 \(success.latencyMilliseconds.map { "\(Int($0)) ms" } ?? "逾時")")
            return [FP01PreflightRecord(steps: steps, success: success)]
        }
    }

    struct FP01Record: Encodable {
        let samples: [FP01Sample]
        let verdict: FP01Verdict.Outcome
        let excludedAlbums: [String: Int]
        /// 閘門拒絕（降級為只播這首）的原因計數與分母
        let gateRefused: [String: Int]
        let catalogAlbums: Int
    }

    static func fp01(shortcut: String) async -> Bool {
        let catalog: (albums: [AlbumEntry], excluded: [String: Int], libraryID: String?)
        do { catalog = try albumCatalog() } catch { print("ITLibrary 讀不到：\(error)"); return false }
        let plan = fp01Samples(catalog.albums, count: FP01Verdict.requiredSamples)
        return await run("fp01", budget: .fp01) { session in
            var samples: [FP01Sample] = []
            for (index, entry) in plan.enumerated() {
                let sample = try await fp01Sample(session, shortcut: shortcut, album: entry.album, position: entry.position,
                                                  label: "\(index + 1)/\(plan.count)")
                print("[\(index + 1)/\(plan.count)] 曲目 \(sample.trackCorrect)、佇列 \(sample.queueCorrect)、延遲 \(sample.latencyMilliseconds.map { "\(Int($0)) ms" } ?? "逾時")")
                samples.append(sample)
            }
            let verdict = FP01Verdict.judge(samples)
            print("F-P-01 ③ 判定：", verdict.rawValue)
            return [FP01Record(samples: samples, verdict: verdict, excludedAlbums: catalog.excluded,
                               gateRefused: refusalCounts(catalog.albums), catalogAlbums: catalog.albums.count)]
        }
    }
}
