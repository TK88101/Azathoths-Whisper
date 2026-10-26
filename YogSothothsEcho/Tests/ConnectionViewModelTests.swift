import Foundation
import RemoteProtocol
import RemoteTransport
import Testing
@testable import YogSothothsEcho

// S2 T10（sprint-2-detail.md §4.12）：iPad 連線與配對狀態機

final class FakeConnector: RemoteConnecting, @unchecked Sendable {
    let lock = NSLock()
    var paired = false
    var pairResult: PairingAttemptResult = .failed(.rejected)
    var pendingSuffix: String?
    var connectResults: [Result<any RemoteSessionHandle, ConnectFailure>] = []
    var connectCalls = 0
    /// 每次 connect 收到的 Bonjour 時窗（S4 F14）
    var windows: [TimeInterval] = []
    /// 第幾次呼叫（1 起算）要停住，直到 release 或被取消（模擬 30 s 的等 Mac 窗）
    var holdCall: Int?
    var cancelledHolds = 0
    private var held: CheckedContinuation<Void, Never>?
    var pairCalls = 0
    var lastDeviceName: String?
    /// 配對停在「等 Mac 允許」，直到 releasePair()（S6.5：畫 pairing 態）
    var holdPair = false
    private var heldPair: CheckedContinuation<Void, Never>?
    private var pairReleased = false

    /// 先放行再停住也不會卡（release 可能早於 pair 進到等待）
    func releasePair() {
        lock.withLock { () -> CheckedContinuation<Void, Never>? in
            pairReleased = true
            defer { heldPair = nil }
            return heldPair
        }?.resume()
    }

    var hasPairedMac: Bool { lock.withLock { paired } }

    func pair(payload: QRPairingPayload, deviceName: String, onPending: @escaping @Sendable (String) -> Void) async -> PairingAttemptResult {
        let (suffix, result) = lock.withLock { () -> (String?, PairingAttemptResult) in
            pairCalls += 1
            lastDeviceName = deviceName
            return (pendingSuffix, pairResult)
        }
        if let suffix { onPending(suffix) }
        if lock.withLock({ holdPair }) {
            await withCheckedContinuation { c in
                let released = lock.withLock { () -> Bool in
                    if pairReleased { return true }
                    heldPair = c
                    return false
                }
                if released { c.resume() }
            }
        }
        if case .approved = result { lock.withLock { paired = true } }
        return result
    }

    func connect(discoveryWindow: TimeInterval) async -> Result<any RemoteSessionHandle, ConnectFailure> {
        let mustHold = lock.withLock { () -> Bool in
            connectCalls += 1
            windows.append(discoveryWindow)
            return holdCall == connectCalls
        }
        if mustHold {
            await withTaskCancellationHandler {
                await withCheckedContinuation { c in
                    let cancelled = lock.withLock { () -> Bool in
                        if Task.isCancelled { return true }
                        held = c
                        return false
                    }
                    if cancelled { c.resume() }
                }
            } onCancel: {
                lock.withLock { () -> CheckedContinuation<Void, Never>? in defer { held = nil }; return held }?.resume()
            }
            if Task.isCancelled {
                lock.withLock { cancelledHolds += 1 }
                return .failure(.notFound)
            }
        }
        return lock.withLock { connectResults.isEmpty ? .failure(.network) : connectResults.removeFirst() }
    }

    var isHolding: Bool { lock.withLock { held != nil } }
    func releaseHold() { lock.withLock { () -> CheckedContinuation<Void, Never>? in defer { held = nil }; return held }?.resume() }

    func forgetMacs() { lock.withLock { paired = false } }
}

final class FakeSession: RemoteSessionHandle, @unchecked Sendable {
    let macName: String
    let client: any EchoClient = SyntheticEchoClient(albumCount: 3)
    let playback: any PlaybackClient = SyntheticPlaybackClient()
    private let lock = NSLock()
    private var open = true
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(macName: String = "Azathoth-ABCD") { self.macName = macName }
    var isOpen: Bool { lock.withLock { open } }

    func close() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            open = false
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }

    func waitUntilClosed() async {
        await withCheckedContinuation { c in
            let resumeNow = lock.withLock { () -> Bool in
                if !open { return true }
                waiters.append(c)
                return false
            }
            if resumeNow { c.resume() }
        }
    }
}

final class FakeCamera: CameraAuthorizing, @unchecked Sendable {
    var current: CameraAccess = .authorized
    var grantOnRequest = true
    func status() -> CameraAccess { current }
    func request() async -> Bool { current = grantOnRequest ? .authorized : .denied; return grantOnRequest }
}

/// 記錄等待秒數、立即返回（退避不真的睡）
final class RecordingSleeper: @unchecked Sendable {
    var delays: [TimeInterval] = []
    func sleep(_ seconds: TimeInterval) async { delays.append(seconds); await Task.yield() }
}

@MainActor
struct ConnectionViewModelTests {
    let connector = FakeConnector()
    let camera = FakeCamera()
    let sleeper = RecordingSleeper()
    let payload = ConnectionSamples.payload()

    func model() -> ConnectionViewModel {
        let sleeper = sleeper
        return ConnectionViewModel(connector: connector, camera: camera, deviceName: "iPad",
                                   sleep: { await sleeper.sleep($0) }, jitter: { 1 })
    }

    @Test func unpairedStartsScanning() async {
        let m = model()
        await m.start()
        #expect(m.state == .unpaired(.scanning))
    }

    @Test func cameraDeniedIsReported() async {
        camera.current = .denied
        let m = model()
        await m.start()
        #expect(m.state == .unpaired(.cameraDenied))
    }

    @Test func cameraNotDeterminedRequestsPermission() async {
        camera.current = .notDetermined
        camera.grantOnRequest = false
        let m = model()
        await m.start()
        #expect(m.state == .unpaired(.cameraDenied))
    }

    @Test func nonAzathothCodeKeepsScanning() async {
        let m = model()
        await m.start()
        await m.scanned("https://example.com")
        #expect(m.state == .unpaired(.invalidCode))
        #expect(connector.pairCalls == 0)
    }

    @Test func approvedPairingConnects() async {
        connector.pendingSuffix = "0A0B"
        connector.pairResult = .approved(PeerRecord(peerID: UUID(), fingerprint: payload.macFingerprint,
                                                    localFingerprint: Fingerprint(bytes: Data(repeating: 4, count: 32))!,
                                                    name: "Azathoth-0202", pairedAt: Date()))
        connector.connectResults = [.success(FakeSession())]
        let m = model()
        await m.start()
        await m.scanned(payload.encoded())
        await settle()
        #expect(m.lastPendingSuffix == "0A0B")
        #expect(m.state == .connected(macName: "Azathoth-ABCD"))
        #expect(connector.lastDeviceName == "iPad")
    }

    @Test(arguments: [PairingFailure.rejected, .expired, .unavailable, .invalid, .macPinMismatch])
    func pairingFailureIsShownAndRescanAllowed(failure: PairingFailure) async {
        connector.pairResult = .failed(failure)
        let m = model()
        await m.start()
        await m.scanned(payload.encoded())
        #expect(m.state == .pairingFailed(failure))
        m.rescan()
        #expect(m.state == .unpaired(.scanning))
    }

    @Test func pairedStartsConnectingAndBacksOffOnFailure() async {
        connector.paired = true
        connector.connectResults = [.failure(.network), .failure(.timeout), .success(FakeSession())]
        let m = model()
        await m.start()
        await settle()
        #expect(sleeper.delays == [1, 2])
        #expect(m.state == .connected(macName: "Azathoth-ABCD"))
    }

    // F14（thecure 2026-10-19）：看不到 Mac＝不睡，開 30 s 的「等 Mac 出現」窗，畫面維持「正在等你的 Mac」

    @Test func notFoundWaitsForTheMacWithALongWindowAndNoSleep() async {
        connector.paired = true
        connector.connectResults = [.failure(.notFound), .failure(.notFound), .success(FakeSession())]
        let m = model()
        await m.start()
        await settle()
        #expect(connector.windows == [DiscoveryWindow.standard, DiscoveryWindow.waitingForMac, DiscoveryWindow.waitingForMac])
        #expect(sleeper.delays.isEmpty)
        #expect(m.state == .connected(macName: "Azathoth-ABCD"))
    }

    /// Codex 最擔心：迴圈開頭若設回「連線中」，等 Mac 的畫面會一閃就被蓋掉
    @Test func waitingStateHoldsWhileTheLongWindowRuns() async {
        connector.paired = true
        connector.connectResults = [.failure(.notFound)]
        connector.holdCall = 2
        let m = model()
        await m.start()
        while !connector.isHolding { await settle() }
        #expect(m.state == .waitingForMac)
        await m.start()                          // 進前景的 start() 不得再開第二個迴圈
        await settle()
        #expect(connector.connectCalls == 2)
        m.suspend()                              // 進背景：等待被取消、不再連
        await settle()
        #expect(connector.cancelledHolds == 1)
        #expect(m.state == .suspended && connector.connectCalls == 2)
    }

    @Test func afterADroppedSessionTheNextAttemptUsesTheStandardWindow() async {
        connector.paired = true
        let session = FakeSession()
        connector.connectResults = [.failure(.notFound), .success(session)]
        let m = model()
        await m.start()
        await settle()
        session.close()
        await settle()
        #expect(Array(connector.windows.prefix(3)) == [DiscoveryWindow.standard, DiscoveryWindow.waitingForMac, DiscoveryWindow.standard])
    }

    @Test func otherFailureAfterWaitingGoesBackToStandardWindowWithBackoff() async {
        connector.paired = true
        connector.connectResults = [.failure(.notFound), .failure(.network), .success(FakeSession())]
        let m = model()
        await m.start()
        await settle()
        #expect(connector.windows == [DiscoveryWindow.standard, DiscoveryWindow.waitingForMac, DiscoveryWindow.standard])
        #expect(sleeper.delays == [1])
    }

    @Test func otherMacsOnlyStillBacksOff() async {
        connector.paired = true
        connector.connectResults = Array(repeating: .failure(.otherMacsOnly), count: 3) + [.success(FakeSession())]
        let m = model()
        await m.start()
        await settle()
        #expect(sleeper.delays == [1, 2, 4])
        #expect(m.state == .connected(macName: "Azathoth-ABCD"))
    }

    @Test func otherFailuresStillBackOff() async {
        connector.paired = true
        connector.connectResults = Array(repeating: .failure(.network), count: 5) + [.success(FakeSession())]
        let m = model()
        await m.start()
        await settle()
        #expect(sleeper.delays == [1, 2, 4, 8, 16])
    }

    @Test func droppedSessionReconnects() async {
        connector.paired = true
        let first = FakeSession()
        connector.connectResults = [.success(first), .success(FakeSession(macName: "Azathoth-9999"))]
        let m = model()
        await m.start()
        await settle()
        first.close()
        await settle()
        #expect(m.state == .connected(macName: "Azathoth-9999"))
        #expect(connector.connectCalls == 2)
    }

    /// 回前景（inactive→active）再呼叫 start()：已連線就維持，不得重開第二條連線或丟下舊 session
    @Test func startWhileConnectedKeepsTheSession() async {
        connector.paired = true
        let session = FakeSession()
        connector.connectResults = [.success(session), .success(FakeSession(macName: "Azathoth-9999"))]
        let m = model()
        await m.start()
        await settle()
        await m.start()
        await settle()
        #expect(connector.connectCalls == 1)
        #expect(session.isOpen)
        #expect(m.state == .connected(macName: "Azathoth-ABCD"))
        m.suspend()
    }

    @Test func pinMismatchOrRevokedStopsRetryingAndAsksToRepair() async {
        connector.paired = true
        connector.connectResults = [.failure(.rejectedByMac), .failure(.rejectedByMac), .failure(.rejectedByMac),
                                    .failure(.rejectedByMac), .failure(.rejectedByMac), .failure(.rejectedByMac)]
        let m = model()
        await m.start()
        await settle()
        #expect(m.state == .needsRepair)
        #expect(connector.connectCalls == ConnectionViewModel.maxRejectedBeforeRepair)
    }

    @Test func clientSuspendDropsPairingState() async {
        let m = model()
        await m.start()
        m.suspend()
        #expect(m.state == .suspended)
        await m.resume()
        #expect(m.state == .unpaired(.scanning))
    }

    @Test func suspendClosesSessionAndResumeReconnects() async {
        connector.paired = true
        let session = FakeSession()
        connector.connectResults = [.success(session), .success(FakeSession())]
        let m = model()
        await m.start()
        await settle()
        m.suspend()
        #expect(!session.isOpen)
        await m.resume()
        await settle()
        #expect(m.state == .connected(macName: "Azathoth-ABCD"))
        #expect(connector.connectCalls == 2)
    }

    @Test func forgetReturnsToScanning() async {
        connector.paired = true
        connector.connectResults = [.success(FakeSession())]
        let m = model()
        await m.start()
        await settle()
        await m.forgetMac()
        #expect(m.state == .unpaired(.scanning))
        #expect(!connector.hasPairedMac)
    }
}
