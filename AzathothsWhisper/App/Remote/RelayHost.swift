import Foundation
import MusicRemoteBridge
import Observation
import RemoteProtocol
import RemoteTransport

/// Mac 端中繼的狀態與接線（sprint-2-detail.md §4.11）。只負責啟停、預熱、配對 UI 狀態、對端清單，
/// 以及依連線數開關曲庫重建與播放輪詢（S3、S4）；播放控制本身在 PlaybackService。
/// 預熱結果以世代守衛處理（遲到的結果不得啟動廣播、不得寫 marker）。
@MainActor
@Observable
final class RelayHost {
    enum Status: Equatable {
        case off
        case warmingUp
        /// 預熱失敗或重建後首次啟動：等使用者在設定頁授權（CR-010 ⑥、CR-011）
        case needsKeychainApproval
        case running
        /// 螢幕鎖定或睡眠中：已斷線、停廣播，解鎖／喚醒後恢復
        case paused
        case failed
    }

    enum Pairing: Equatable {
        case idle
        case showingQR(text: String, expiresAt: Date)
        case confirming(name: String, suffix: String)
        case finished(PairOutcome)
    }

    struct PeerRow: Identifiable, Equatable {
        let id: UUID
        let name: String
        let suffix: String
        let pairedAt: Date
        let isConnected: Bool
    }

    private(set) var status: Status = .off
    private(set) var pairing: Pairing = .idle
    private(set) var peers: [PeerRow] = []
    private(set) var isEnabled = false
    /// 曲庫讀不到（未授權或讀取失敗）：設定頁顯示說明＋開系統設定（設計 §5.4；CR-012）
    private(set) var libraryUnavailable = false

    /// 設定頁的捷徑區塊（§4.6）。idle＝本次還沒檢查：只顯示是否存過綁定，不跑任何指令
    enum ShortcutPanel: Equatable {
        case idle
        case checking
        case checked(bound: Bool)
        case installing(ShortcutInstaller.Phase)
        case installed
        case installFailed(ShortcutInstaller.Outcome)
    }

    private(set) var shortcut: ShortcutPanel = .idle
    /// Music 自動化權限被拒（輪詢事件 availability=automationDenied；設計 §5.4 #2）。權限恢復或中繼停止即解除
    private(set) var musicNotAuthorized = false
    var hasStoredShortcut: Bool { dependencies.playback.hasStoredShortcut }

    private let dependencies: RelayDependencies
    /// 登入時啟動（S6 §4.10）：狀態以系統為準，設定 modal 出現與回前景時重讀
    let loginItem: LoginItemController
    @ObservationIgnored private var server: (any RelayServing)?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// launch 已用掉：執行過一次，或已 shutdown（之後排到的 launch 一律不起）
    @ObservationIgnored private var didLaunch = false
    @ObservationIgnored private var warmedThisRun = false
    /// 螢幕鎖定或睡眠中：任何路徑都不得啟動伺服端（預熱可照常完成，解除後才起；codex S2 第 1 輪）。
    /// 兩者分開記：喚醒時若設了「需要密碼」，螢幕仍鎖著，要等解鎖（security 補查）
    @ObservationIgnored private var screenLocked = false
    @ObservationIgnored private var asleep = false
    private var isLocked: Bool { screenLocked || asleep }
    @ObservationIgnored private var connected: Set<UUID> = []
    /// 本機已放棄、但伺服端 terminal 事件還沒到的配對窗數（F-1）。每個開過的窗恰好送一個 `.pairingFinished`，
    /// 事件串流 FIFO，所以計數歸零前收到的配對事件都屬於被放棄的窗，不得改畫面
    @ObservationIgnored private var abandonedWindows = 0
    /// 曲庫重建與播放輪詢的開關依序執行（start／stop 不得因 Task 排程而顛倒）
    @ObservationIgnored private var watchChain: Task<Void, Never>?

    init(dependencies: RelayDependencies) {
        self.dependencies = dependencies
        loginItem = LoginItemController(control: dependencies.loginItem)
        isEnabled = dependencies.preferences.relayEnabled
    }

    // MARK: 啟停

    /// App 啟動時決定中繼要不要起；每個 host 一次，再呼叫不重啟（s6-61-login-launch.md §5）。
    /// 使用者重試與開關走 `retryAuthorization`／`setEnabled`，不經此處
    func launch() async {
        guard !didLaunch else { return }
        didLaunch = true
        isEnabled = dependencies.preferences.relayEnabled
        // 中繼關閉時不碰鑰匙圈（F-R-05 預設關、security review S2 LOW-3）。開啟時只唯讀取指紋：
        // 沒有身分或鑰匙圈讀不到（例如登入當下尚未解鎖）＝等使用者，不在啟動時建立或重建身分（R7）
        let current = isEnabled
            ? dependencies.identity.storedFingerprint().flatMap { RelayStartup.marker(cdHash: dependencies.cdHash(), identity: $0) }
            : nil
        switch RelayStartup.decide(enabled: isEnabled, stored: dependencies.preferences.lastWarmedMarker, current: current) {
        case .stayOff: status = .off
        case .waitForUser: status = .needsKeychainApproval
        case .autoWarmUp: await warmUpAndStart()
        }
    }

    func setEnabled(_ enabled: Bool) async {
        dependencies.preferences.relayEnabled = enabled
        isEnabled = enabled
        if enabled {
            await warmUpAndStart()
        } else {
            stopServer()
            status = .off
        }
    }

    /// 使用者在設定頁按「重試並在 Mac 上授權」
    func retryAuthorization() async {
        guard isEnabled, status != .warmingUp else { return }
        await warmUpAndStart()
    }

    func shutdown() {
        didLaunch = true
        stopServer()
        status = .off
    }

    private func warmUpAndStart() async {
        stopServer()
        let token = generation
        status = .warmingUp
        do {
            try await dependencies.identity.warmUp()
        } catch {
            guard token == generation else { return }
            status = .needsKeychainApproval
            return
        }
        guard token == generation, isEnabled else { return }
        warmedThisRun = true
        if let fingerprint = try? dependencies.identity.fingerprint(),
           let marker = RelayStartup.marker(cdHash: dependencies.cdHash(), identity: fingerprint) {
            dependencies.preferences.lastWarmedMarker = marker
        }
        guard !isLocked else {
            status = .paused
            return
        }
        await startServer(token)
    }

    private func startServer(_ token: Int) async {
        do {
            let server = try dependencies.makeServer()
            self.server = server
            attachCatalog(to: server)
            attachPlayback(to: server)
            subscribe(server)
            try await server.start()
            guard token == generation else {   // 上鎖時 stopServer() 已遞增世代（server 在 start 前即賦值）
                server.stop()
                return
            }
            status = .running
            refreshPeers()
        } catch {
            guard token == generation else { return }
            stopServer()
            status = .failed
        }
    }

    /// 停伺服端（作廢配對窗、斷全部連線），並使任何在途的預熱／啟動結果失效
    private func stopServer() {
        generation += 1
        eventsTask?.cancel()
        eventsTask = nil
        server?.stop()
        if server != nil {
            dependencies.catalog.setHandlers(changed: nil, availability: nil)
            dependencies.playback.setOutlets(nil)
        }
        server = nil
        // 停伺服端是直接拆連線、不會再送 peerDisconnected：逐一通知曲庫釋放 detail 傳輸（CR-018）
        for id in connected { enqueueWatch { catalog, _ in await catalog.releasePeer(id) } }
        if !connected.isEmpty { setWatching(false) }
        connected = []
        refreshPeers()   // F13：關遙控、上鎖後設定頁的綠點要滅
        libraryUnavailable = false
        musicNotAuthorized = false
        pairing = .idle
        abandonedWindows = 0
    }

    // MARK: 生命週期（CR-010 ②(l)）

    func handle(_ event: RelayLifecycleEvent) async {
        switch event {
        case .screenLocked: screenLocked = true
        case .willSleep: asleep = true
        case .screenUnlocked: screenLocked = false
        case .didWake: asleep = false
        }
        if isLocked {
            // 已在跑、或預熱成功後伺服端正在起：都停下（預熱本身還在等鑰匙圈時不取消，完成後見 warmUpAndStart）
            guard status == .running || server != nil else { return }
            stopServer()
            status = .paused
        } else {
            guard status == .paused, isEnabled, warmedThisRun else { return }
            await startServer(generation)
        }
    }

    // MARK: 配對

    func startPairing() {
        guard status == .running, let server, !isPairingInProgress else { return }
        let payload = server.openPairingWindow()
        pairing = .showingQR(text: payload.encoded(), expiresAt: dependencies.now().addingTimeInterval(TransportLimits.qrLifetime))
    }

    func approvePairing() { server?.approvePairing() }
    func rejectPairing() { server?.rejectPairing() }

    func cancelPairing() {
        if isPairingInProgress { abandonedWindows += 1 }
        server?.cancelPairing()
        pairing = .idle
    }

    private var isPairingInProgress: Bool {
        switch pairing {
        case .showingQR, .confirming: true
        case .idle, .finished: false
        }
    }

    /// 設定 modal 關閉：進行中的配對（QR 顯示中、等確認）一併取消——使用者看不到確認窗就不該讓窗繼續開著（security review S2 LOW-8）
    func settingsClosed() {
        switch pairing {
        case .showingQR, .confirming: cancelPairing()
        case .finished: dismissPairingResult()
        case .idle: break
        }
    }

    func dismissPairingResult() {
        if case .finished = pairing { pairing = .idle }
    }

    func revoke(_ peerID: UUID) {
        if let server {
            server.revoke(peerID: peerID)
        } else {
            try? dependencies.trust.remove(peerID: peerID)
        }
        connected.remove(peerID)
        refreshPeers()
    }

    // MARK: 事件

    /// 世代守衛：取消迭代的 Task 仍可能交出已送達的元素——關遙控／上鎖／換伺服端之後，舊伺服端的事件一律丟棄
    /// （simcodex R2 security MEDIUM-1；iPad 端 NowPlayingViewModel 同一做法）
    private func subscribe(_ server: any RelayServing) {
        let events = server.events
        let token = generation
        eventsTask = Task { [weak self] in
            for await event in events {
                guard let self, token == self.generation else { return }
                self.apply(event)
            }
        }
    }

    private func apply(_ event: ServerEvent) {
        switch event {
        case .pairingPending(let name, let suffix):
            guard abandonedWindows == 0 else { return }
            pairing = .confirming(name: name, suffix: suffix)
        case .pairingFinished(let outcome):
            if abandonedWindows > 0 {
                abandonedWindows -= 1
            } else {
                pairing = .finished(outcome)
            }
            refreshPeers()
        case .peerConnected(let id):
            // 新連線（含同 peer 取代舊連線，那時不送 peerDisconnected）：舊連線上的 detail 傳輸與世代紀錄作廢
            enqueueWatch { catalog, _ in await catalog.releasePeer(id) }
            let wasEmpty = connected.isEmpty
            connected.insert(id)
            // 0→1 開始輪詢（開始時即讀一次並推送）；其他新連線（含同 peer 取代舊連線）只把目前狀態再推一次
            if wasEmpty { setWatching(true) } else { enqueueWatch { await $1.connectionAdded() } }
            refreshPeers()
        case .peerDisconnected(let id):
            enqueueWatch { catalog, _ in await catalog.releasePeer(id) }
            guard connected.remove(id) != nil else { return refreshPeers() }
            if connected.isEmpty { setWatching(false) }
            refreshPeers()
        case .listenerFailed:
            stopServer()
            status = .failed
        }
    }

    // MARK: 曲庫（S3）

    private func attachCatalog(to server: any RelayServing) {
        dependencies.catalog.setHandlers(
            changed: { [weak server] version in server?.broadcastCatalogChanged(version: version) },
            availability: { [weak self] ok in Task { @MainActor in self?.libraryUnavailable = !ok } })
    }

    // MARK: 播放（S4）

    private func attachPlayback(to server: any RelayServing) {
        let token = generation
        dependencies.playback.setOutlets(PlaybackOutlets(
            isAlive: { [weak server] id in server?.isConnectionAlive(id) ?? false },
            push: { [weak server, weak self] event in
                server?.broadcastPlayback(event)
                let denied = event.availability == .automationDenied
                Task { @MainActor in
                    guard let self, token == self.generation else { return }
                    self.musicNotAuthorized = denied
                }
            }))
    }

    /// 設定頁「重新檢查」：只在中繼開著、沒有進行中的檢查或安裝時（D13：中繼關閉不跑 shortcuts 指令）
    func checkShortcut() async {
        guard RelayPresentation.canManageShortcut(status: status, panel: shortcut) else { return }
        shortcut = .checking
        shortcut = .checked(bound: await dependencies.playback.checkShortcut())
    }

    /// 設定頁「安裝捷徑」：進度與結果都留在畫面上；中途關掉中繼也讓使用者看到結果（安裝在「捷徑」App 裡照樣進行）
    func installShortcut() async {
        guard RelayPresentation.canManageShortcut(status: status, panel: shortcut) else { return }
        shortcut = .installing(.waitingForAdd)
        let outcome = await dependencies.playback.installShortcut { [weak self] phase in
            Task { @MainActor in
                guard let self, case .installing = self.shortcut else { return }
                self.shortcut = .installing(phase)
            }
        }
        if case .installed = outcome { shortcut = .installed } else { shortcut = .installFailed(outcome) }
    }

    /// 曲庫重建與播放輪詢同開同關
    private func setWatching(_ on: Bool) {
        enqueueWatch { catalog, playback in
            if on {
                await catalog.startWatching()
                await playback.startWatching()
            } else {
                await catalog.stopWatching()
                await playback.stopWatching()
            }
        }
    }

    private func enqueueWatch(_ body: @escaping @Sendable (any RelayCatalog, any RelayPlayback) async -> Void) {
        let previous = watchChain, catalog = dependencies.catalog, playback = dependencies.playback
        watchChain = Task {
            await previous?.value
            await body(catalog, playback)
        }
    }

    /// 只列目前本機身分的有效紀錄（§4.4）。純讀：中繼關閉、App 結束時也會跑，不得建立或重建身分（R7）
    private func refreshPeers() {
        guard let fingerprint = dependencies.identity.storedFingerprint() else {
            peers = []
            return
        }
        peers = dependencies.trust.validRecords(for: fingerprint)
            .sorted { $0.pairedAt < $1.pairedAt }
            .map { PeerRow(id: $0.peerID, name: $0.name, suffix: $0.fingerprint.suffix, pairedAt: $0.pairedAt,
                           isConnected: connected.contains($0.peerID)) }
    }
}
