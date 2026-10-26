import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// S7 T6 E1b（sprint-7-detail.md §4.5）：iPad 重連迴圈長跑。迴圈在 ConnectionViewModel（EchoKit 的單次 connect 證明不了），
// 所以用可逐步放行的假 connector 與假 sleep，每輪以屏障推進：連上 → 斷線 → 重連失敗一次 → 退避 → 再連上

/// 每次 connect 都停住，直到測試給出結果；記錄同時在 connect 中的最大數量（＝連線迴圈數）
final class GatedConnector: RemoteConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: CheckedContinuation<Result<any RemoteSessionHandle, ConnectFailure>, Never>?
    private var inFlight = 0
    private(set) var maxInFlight = 0
    private(set) var calls = 0

    var hasPairedMac: Bool { true }
    func pair(payload: QRPairingPayload, deviceName: String, onPending: @escaping @Sendable (String) -> Void) async -> PairingAttemptResult {
        .failed(.rejected)
    }
    func forgetMacs() {}

    func connect(discoveryWindow: TimeInterval) async -> Result<any RemoteSessionHandle, ConnectFailure> {
        let result = await withCheckedContinuation { c in
            lock.withLock {
                calls += 1
                inFlight += 1
                maxInFlight = max(maxInFlight, inFlight)
                waiting = c
            }
        }
        lock.withLock { inFlight -= 1 }
        return result
    }

    var isWaiting: Bool { lock.withLock { waiting != nil } }
    var callCount: Int { lock.withLock { calls } }
    var peakConcurrency: Int { lock.withLock { maxInFlight } }

    func answer(_ result: Result<any RemoteSessionHandle, ConnectFailure>) {
        lock.withLock { () -> CheckedContinuation<Result<any RemoteSessionHandle, ConnectFailure>, Never>? in
            defer { waiting = nil }
            return waiting
        }?.resume(returning: result)
    }
}

/// 退避的 sleep 停住，直到測試放行；記錄每次的秒數
final class GatedSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var held: CheckedContinuation<Void, Never>?
    private(set) var delays: [TimeInterval] = []

    func sleep(_ seconds: TimeInterval) async {
        await withCheckedContinuation { c in lock.withLock { delays.append(seconds); held = c } }
    }

    var isHolding: Bool { lock.withLock { held != nil } }
    var lastDelay: TimeInterval? { lock.withLock { delays.last } }
    func release() { lock.withLock { () -> CheckedContinuation<Void, Never>? in defer { held = nil }; return held }?.resume() }
}

@MainActor
@Suite(.timeLimit(.minutes(2)))
struct ConnectionReconnectEnduranceTests {
    static let rounds = 200
    nonisolated static let jitter = 1.1

    /// 主執行緒讓出，直到條件成立（假物件的狀態由背景迴圈推進）
    /// 等不到就記失敗並回 false，呼叫端立即結束（否則後續每輪都空轉到時限）
    private func until(_ what: String, round: Int, _ condition: () -> Bool) async -> Bool {
        for _ in 0..<5_000 where !condition() { await Task.yield() }
        #expect(condition(), "第 \(round) 輪等不到：\(what)")
        return condition()
    }

    @Test func reconnectLoopSurvivesManyDropsWithOneLoopAndFreshBackoff() async {
        let connector = GatedConnector(), sleeper = GatedSleeper()
        let m = ConnectionViewModel(connector: connector, camera: FakeCamera(), deviceName: "iPad",
                                    sleep: { await sleeper.sleep($0) }, jitter: { Self.jitter })
        await m.start()
        let firstDelay = ReconnectBackoff.delay(attempt: 1, jitter: Self.jitter)
        for round in 1...Self.rounds {
            // ① 迴圈進到 connect → 給 session → connected
            guard await until("進入 connect", round: round, { connector.isWaiting }) else { return }
            let session = FakeSession()
            connector.answer(.success(session))
            guard await until("connected", round: round, { if case .connected = m.state { true } else { false } }) else { return }
            // 前景回來（scenePhase）再叫一次 start：不得開第二條迴圈
            await m.start()
            // ② 斷線 → 立刻重連一次但失敗 → retrying，退避從第 1 次算起（上一輪成功已歸零）
            session.close()
            guard await until("斷線後重連", round: round, { connector.isWaiting }) else { return }
            connector.answer(.failure(.network))
            guard await until("退避 sleep", round: round, { sleeper.isHolding }) else { return }
            #expect(m.state == .retrying(inSeconds: Int(firstDelay.rounded(.up))), "第 \(round) 輪狀態 \(m.state)")
            #expect(sleeper.lastDelay == firstDelay, "第 \(round) 輪退避 \(String(describing: sleeper.lastDelay))")
            // ③ 放行 sleep → 回到①
            sleeper.release()
        }
        // 最後一輪放行 sleep 後迴圈會再進一次 connect：等它進去再數（每輪 2 次＋這 1 次）
        guard await until("最後一次 connect", round: Self.rounds, { connector.isWaiting }) else { return }
        #expect(connector.peakConcurrency == 1)
        #expect(connector.callCount == Self.rounds * 2 + 1)
        m.suspend()
        connector.answer(.failure(.network))
    }
}
