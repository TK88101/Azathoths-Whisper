import Foundation
import SpikeCore

// 操控 Music 的實驗外殼（sprint-0-detail.md §4.4、§6）：快照落盤成功才准控制；各種結束路徑都還原；
// 指令數受 OperationBudget 硬上限約束；讀回一律重試到 2 s。
@MainActor
final class Session {
    enum Stop: Error, CustomStringConvertible {
        case budgetExhausted(OperationBudget.Experiment)
        case userAborted
        case snapshotFailed
        case precondition(String)

        var description: String {
            switch self {
            case .budgetExhausted(let e): "\(e.rawValue) 已達指令硬上限，停下並還原；繼續需要使用者重新同意"
            case .userAborted: "使用者中止"
            case .snapshotFailed: "快照失敗，不送任何控制指令"
            case .precondition(let why): "前置條件不成立：\(why)"
            }
        }
    }

    static let readDeadline: Duration = .seconds(2)
    static let readInterval: Duration = .milliseconds(100)
    static let commandGap: Duration = .milliseconds(300)
    /// 還原最多 4 個指令（曲目、位置、狀態、AirPlay），由結構決定；§6 的 70 是整輪約 12 次還原的總量
    static let restoreCommands = 4

    let bridge: MusicBridge
    private(set) var budget: OperationBudget
    private(set) var snapshot: MusicSnapshot?

    init(bridge: MusicBridge, experiment: OperationBudget.Experiment, restoring snapshot: MusicSnapshot? = nil) {
        self.bridge = bridge
        budget = OperationBudget(experiment: experiment)
        self.snapshot = snapshot
    }

    /// Ctrl-C 只設旗標；下一個指令前停下，讓呼叫端照常還原（§4.4）
    static var interruptRequested = false
    private static var interruptSource: DispatchSourceSignal?

    static func installInterruptHandler() {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { interruptRequested = true } }
        source.resume()
        interruptSource = source
    }

    // MARK: 快照

    /// 純讀取：「必須還原」四項任一讀取出錯、或不在播放／暫停狀態，都不算快照
    static func capture(_ bridge: MusicBridge) throws -> MusicSnapshot {
        let state = bridge.state()
        let track = bridge.currentTrackID()
        let position = bridge.position()
        let airPlay = bridge.airPlaySelection()
        guard [state.errorCode, track.errorCode, position.errorCode, airPlay.errorCode].allSatisfy({ $0 == nil }) else {
            throw Stop.snapshotFailed
        }
        // playPause 只能在播放／暫停之間切換，停止狀態無法還原，故不從停止狀態開始
        guard state.value == .playing || state.value == .paused else {
            throw Stop.precondition("Music 要在播放或暫停狀態才能開始（停止狀態無法還原）")
        }
        let context = bridge.context().value
        return MusicSnapshot(
            trackID: track.value,
            position: position.value,
            state: state.value,
            airPlayDeviceIDs: airPlay.value,
            contextHash: PlaybackOracle(sequence: context.sequence).map { "\(context.playlistID ?? "-"):\($0.contextHash)" },
            queueHash: MusicFileReader.queue().hash
        )
    }

    /// 復原點：讀取並落盤；落盤失敗就丟錯，不准開始控制（§4.4）
    func takeSnapshot() throws {
        let current = try Self.capture(bridge)
        _ = try ResultWriter.save(experiment: "snapshot", records: [current])
        snapshot = current
    }

    // MARK: 指令

    /// 預扣 n 個指令：先看中止，再看上限
    func reserve(_ count: Int = 1) throws {
        guard !Self.interruptRequested else { throw Stop.userAborted }
        guard budget.spend(count) else { throw Stop.budgetExhausted(budget.experiment) }
    }

    /// -1712 Apple Event 逾時、-600／-609 Music 已結束：停下這一輪並還原（§9），不再對它送指令
    static let fatalErrorCodes: Set<Int> = [-1712, -600, -609]

    /// 每個控制指令先預扣上限，送出後間隔 300 ms；致命錯誤碼立即中止
    func command<Value>(_ body: () -> Timed<Value>) async throws -> Timed<Value> {
        try reserve()
        let result = body()
        if let code = result.errorCode, Self.fatalErrorCodes.contains(code) {
            throw Stop.precondition("Music 回 \(code)（逾時或已結束），中止這一輪")
        }
        try await Task.sleep(for: Self.commandGap)
        return result
    }

    /// 重試讀取直到符合期待或 2 s 到期；回傳最後讀到的值與第一次符合的時刻
    func waitFor<Value>(_ read: () -> Timed<Value>, until accept: (Value) -> Bool) async -> (value: Value, matchedAt: ContinuousClock.Instant?) {
        let deadline = ContinuousClock.now + Self.readDeadline
        var last = read().value
        while !accept(last) {
            guard ContinuousClock.now < deadline else { return (last, nil) }
            try? await Task.sleep(for: Self.readInterval)
            last = read().value
        }
        return (last, ContinuousClock.now)
    }

    // MARK: 還原

    /// 還原「必須還原」四項並讀回驗證；結果落 restore-*（Recovery 據此判斷是否還有待還原）
    func restore() async -> RestoreCheck? {
        guard let target = snapshot else { return nil }
        if let id = target.trackID, bridge.currentTrackID().value != id {
            _ = bridge.play(trackID: id)
            _ = await waitFor(bridge.currentTrackID) { $0 == id }
        }
        if let position = target.position { _ = bridge.seek(to: position) }
        if bridge.state().value != target.state {
            _ = bridge.playPause()
            _ = await waitFor(bridge.state) { $0 == target.state }
        }
        if bridge.airPlaySelection().value != target.airPlayDeviceIDs {
            _ = bridge.selectAirPlay(target.airPlayDeviceIDs)
        }
        guard let after = try? Self.capture(bridge) else { return nil }
        let check = RestoreCheck(before: target, after: after)
        do {
            _ = try ResultWriter.save(experiment: "restore", records: [RestoreRecord(check: check)])
        } catch {
            print("還原紀錄寫不進去：\(error)；下次啟動會再要求 recover")
        }
        return check
    }
}

struct RestoreRecord: Codable {
    let unrestored: [String]
    let recordOnlyChanges: [String]

    init(check: RestoreCheck) {
        unrestored = check.unrestored.map(\.rawValue)
        recordOnlyChanges = check.recordOnlyChanges.map(\.rawValue)
    }
}
