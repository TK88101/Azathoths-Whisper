import Foundation
import Observation
import RemoteProtocol
import RemoteTransport

/// iPad 的連線與配對狀態（sprint-2-detail.md §4.12）。世代守衛：suspend／forget 之後，在途的配對與重連結果一律丟棄
@MainActor
@Observable
final class ConnectionViewModel {
    enum Scan: Equatable {
        case scanning, cameraDenied, cameraUnavailable, invalidCode
    }

    enum State: Equatable {
        case unpaired(Scan)
        case pairing
        case pairingFailed(PairingFailure)
        case connecting
        case connected(macName: String)
        case retrying(inSeconds: Int)
        /// 區網內看不到配對過的 Mac：開著瀏覽器等它出現（S4 F14）
        case waitingForMac
        /// Mac 一再拒絕（已被解除或 Mac 換了身分）：請重新配對
        case needsRepair
        case suspended
    }

    /// 連續被 Mac 拒絕幾次就停止重試、改請使用者重新配對
    static let maxRejectedBeforeRepair = 3

    private(set) var state: State = .suspended
    /// Mac 端顯示的末 4 碼（iPad 等待畫面同顯，CR-010 ②(f)）
    private(set) var lastPendingSuffix: String?

    private let connector: any RemoteConnecting
    private let camera: any CameraAuthorizing
    private let deviceName: String
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let jitter: @Sendable () -> Double
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var session: (any RemoteSessionHandle)?
    /// 連上／斷線時通知組裝根（S3：Library 依此取得或釋放曲庫 client）
    @ObservationIgnored var onSessionOpened: ((any EchoClient, any PlaybackClient) -> Void)?
    @ObservationIgnored var onSessionClosed: (() -> Void)?

    init(connector: any RemoteConnecting, camera: any CameraAuthorizing, deviceName: String,
         sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
         jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.8...1.2) }) {
        self.connector = connector
        self.camera = camera
        self.deviceName = deviceName
        self.sleep = sleep
        self.jitter = jitter
    }

    func start() async {
        // scenePhase 的 inactive→active（控制中心、App 切換器）也會呼叫：連線／重連／配對進行中就維持，
        // 不得重開第二條連線或丟下等待 Mac 確認的配對（simplify S2 第 1 輪）
        switch state {
        case .connecting, .connected, .retrying, .waitingForMac, .pairing: return
        case .unpaired, .pairingFailed, .needsRepair, .suspended: break
        }
        generation += 1
        if connector.hasPairedMac {
            startConnectLoop()
        } else {
            await enterScanning()
        }
    }

    /// App 進背景：丟棄掃描與配對中狀態、關連線（CR-010 ②(l)）
    func suspend() {
        generation += 1
        loopTask?.cancel()
        loopTask = nil
        session?.close()
        session = nil
        lastPendingSuffix = nil
        state = .suspended
    }

    func resume() async { await start() }

    func rescan() {
        guard case .pairingFailed = state else { return }
        state = .unpaired(.scanning)
    }

    func forgetMac() async {
        suspend()
        connector.forgetMacs()
        generation += 1
        await enterScanning()
    }

    // MARK: 配對

    private func enterScanning() async {
        switch camera.status() {
        case .authorized: state = .unpaired(.scanning)
        case .denied: state = .unpaired(.cameraDenied)
        case .unavailable: state = .unpaired(.cameraUnavailable)
        case .notDetermined:
            let token = generation
            let granted = await camera.request()
            guard token == generation else { return }
            state = .unpaired(granted ? .scanning : .cameraDenied)
        }
    }

    func scanned(_ text: String) async {
        guard case .unpaired(let scan) = state, scan == .scanning || scan == .invalidCode else { return }
        guard case .success(let payload) = QRPairingPayload.decode(text) else {
            state = .unpaired(.invalidCode)
            return
        }
        let token = generation
        state = .pairing
        lastPendingSuffix = nil
        let result = await connector.pair(payload: payload, deviceName: deviceName) { suffix in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.lastPendingSuffix = suffix
            }
        }
        guard token == generation else { return }
        switch result {
        case .approved: startConnectLoop()
        case .failed(let failure): state = .pairingFailed(failure)
        }
    }

    // MARK: 連線與重連

    private func startConnectLoop() {
        loopTask?.cancel()
        let token = generation
        loopTask = Task { [weak self] in await self?.connectLoop(token) }
    }

    private func connectLoop(_ token: Int) async {
        var attempt = 0
        var rejected = 0
        // 上一次完全看不到配對過的 Mac：這一次開 30 s 的等 Mac 窗、不睡（S4 F14，thecure 2026-10-19）
        var waitingForMac = false
        while token == generation, !Task.isCancelled {
            state = waitingForMac ? .waitingForMac : .connecting
            let result = await connector.connect(discoveryWindow: waitingForMac ? DiscoveryWindow.waitingForMac : DiscoveryWindow.standard)
            waitingForMac = false
            switch result {
            case .success(let handle):
                guard token == generation else {
                    handle.close()
                    return
                }
                session = handle
                attempt = 0
                rejected = 0
                state = .connected(macName: handle.macName)
                onSessionOpened?(handle.client, handle.playback)
                await handle.waitUntilClosed()
                onSessionClosed?()
                guard token == generation else { return }
                session = nil
                continue
            case .failure(.notPaired):
                await enterScanning()
                return
            case .failure(.rejectedByMac), .failure(.pinMismatch):
                rejected += 1
                if rejected >= Self.maxRejectedBeforeRepair {
                    state = .needsRepair
                    return
                }
            case .failure(.notFound):
                // 看不到 Mac（多半是遙控關著）：同一個瀏覽器等它出現、看到就連（F14）；attempt 不累加。
                // 連線器保證沒看到時等滿時窗，所以這裡不會空轉
                waitingForMac = true
                continue
            case .failure:
                break
            }
            attempt += 1
            await retry(after: ReconnectBackoff.delay(attempt: attempt, jitter: jitter()))
        }
    }

    private func retry(after delay: TimeInterval) async {
        state = .retrying(inSeconds: Int(delay.rounded(.up)))
        await sleep(delay)
    }
}
