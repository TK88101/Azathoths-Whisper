import Foundation
import SpikeCore

// 依賴使用者專輯脈絡的實驗與 B5（sprint-0-detail.md §4.3、§4.3.2、§4.3.3）。
// 每個實驗都在 Session 內：快照成功才控制、結束一律還原。只記 ID 與數值。
@MainActor
enum Experiments {
    static let repeatOff: UInt32 = 0x6B52_704F   // 'kRpO'
    static let steps = 20

    // MARK: 共用：oracle 前置與每樣本檢查

    /// oracle（2026-10-15 現場修訂，Codex 辯論推薦 B）：從專輯頁播放時 current playlist 是整個曲庫，
    /// 故改用 Queue.dat 的順序清單（唯讀、ordered）＋當前曲 ID 恰好出現一次定位。
    /// 前置：shuffle／repeat 關、佇列可解析且 ≥ 22 首、整份無重複、當前曲在其中。任一不成立＝不可判定。
    static func oracle(_ session: Session) throws -> (oracle: PlaybackOracle, identity: String) {
        let modes = session.bridge.shuffleAndRepeat().value
        guard modes.shuffle == false, modes.repeatMode == repeatOff else {
            throw Session.Stop.precondition("隨機或重複播放沒有關")
        }
        guard let ids = MusicFileReader.queue().ids else {
            throw Session.Stop.precondition("佇列讀不到或不是順序模式：B2／B4／B6 不可判定")
        }
        guard let oracle = PlaybackOracle(sequence: ids), oracle.hasRoom(forSteps: steps + 1) else {
            throw Session.Stop.precondition("佇列要 ≥ 22 首且整份不重複：B2／B4／B6 不可判定")
        }
        guard let current = session.bridge.currentTrackID().value, ids.contains(current) else {
            throw Session.Stop.precondition("目前曲目不在佇列中：B2／B4／B6 不可判定")
        }
        return (oracle, oracle.contextHash)
    }

    /// §4.3.2：每個樣本前後脈絡身分與 shuffle／repeat 不得改變
    static func assertContext(_ session: Session, identity: String) throws {
        let current = try oracle(session).identity
        guard current == identity else { throw Session.Stop.precondition("播放脈絡在量測中改變") }
    }

    /// §4.3.3：seek 0＋上一首，逐步回到序列第 1 首（不點歌、不換脈絡）
    static func resetToStart(_ session: Session, oracle: PlaybackOracle) async throws {
        for _ in 0...steps + 2 {
            guard let current = session.bridge.currentTrackID().value else { break }
            if current == oracle.sequence[0] { break }
            let expected = oracle.expectedPrevious(before: current)
            _ = try await session.command { session.bridge.seek(to: 0) }
            _ = try await session.command { session.bridge.previous() }
            let read = await session.waitFor(session.bridge.currentTrackID) { $0 == expected }
            guard read.matchedAt != nil else { throw Session.Stop.precondition("重置時上一首不符 oracle") }
        }
        _ = try await session.command { session.bridge.seek(to: 0) }
        guard session.bridge.currentTrackID().value == oracle.sequence[0] else {
            throw Session.Stop.precondition("重置後不在序列第 1 首")
        }
    }

    /// §4.3.2 前置實證：從第 1 首起 3 次下一首、3 次上一首，每步讀回都要符合 oracle，否則 B2／B4／B6 不可判定
    static func verifyOracle(_ session: Session, oracle: PlaybackOracle) async throws {
        for kind in [B2Check.Kind.next, .previous] {
            for _ in 0..<3 {
                let current = session.bridge.currentTrackID().value ?? ""
                let expected = kind == .next ? oracle.expectedNext(after: current) : oracle.expectedPrevious(before: current)
                if kind == .previous { _ = try await session.command { session.bridge.seek(to: 0) } }
                _ = try await session.command { kind == .next ? session.bridge.next() : session.bridge.previous() }
                let read = await session.waitFor(session.bridge.currentTrackID) { $0 == expected }
                guard read.matchedAt != nil else {
                    throw Session.Stop.precondition("oracle 前置實證不符（\(kind.rawValue)）：B2／B4／B6 不可判定")
                }
            }
        }
    }

    /// 前置實證後回到序列第 1 首：oracle 驗證、重置一起做
    static func prepare(_ session: Session) async throws -> (oracle: PlaybackOracle, identity: String) {
        let (oracle, identity) = try oracle(session)
        try await resetToStart(session, oracle: oracle)
        try await verifyOracle(session, oracle: oracle)
        try await resetToStart(session, oracle: oracle)
        return (oracle, identity)
    }

    // MARK: 實驗外殼

    /// 唯一的操控入口：同意 → 無待還原 → 快照落盤 → （背景負載）→ 實驗 → 停背景負載 → 還原。
    /// background 有值時啟動 relay-load 子程序，其 seek 配額先從本實驗上限預扣，還原前一定停掉並等它結束。
    static func run<Record: Encodable>(_ name: String, budget: OperationBudget.Experiment, background: Double? = nil,
                                        backgroundSeeks: Int = RelayLoad.seekQuota,
                                        body: (Session) async throws -> [Record]) async -> Bool {
        guard ProcessInfo.processInfo.environment["YSE_CONSENT"] == "yes" else {
            print("未取得使用者同意（YSE_CONSENT=yes，§6）；不送任何指令")
            return false
        }
        guard Recovery.pendingSnapshot() == nil else {
            print("有未還原的快照：先執行 `yse-spike recover`")
            return false
        }
        guard let bridge = MusicBridge.connect() else {
            print("Music 未開或自檢不過；不送任何指令")
            return false
        }
        let session = Session(bridge: bridge, experiment: budget)
        do {
            try session.takeSnapshot()
        } catch {
            print("\(name) 未開始：\(error)")
            return false
        }
        var relay: Process?
        do {
            if let interval = background {
                try session.reserve(backgroundSeeks)
                relay = RelayLoad.spawn(interval: interval, maxSeeks: backgroundSeeks)
            }
            let records = try await body(session)
            print("written:", try ResultWriter.save(experiment: name, records: records).path)
        } catch {
            print("\(name) 中止：\(error)")
        }
        RelayLoad.stop(relay)
        let check = await session.restore()
        print("還原：", check.map { $0.unrestored.isEmpty ? "必須還原項全部還原" : "未還原 \($0.unrestored)" } ?? "失敗")
        return check?.unrestored.isEmpty == true
    }
}
