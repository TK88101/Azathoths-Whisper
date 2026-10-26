import Foundation
import MusicRemoteBridge
import RemoteProtocol
import RemoteTransport
import Testing

@testable import AzathothsWhisper

// S2 T9（sprint-2-detail.md §4.11、CR-010 ⑥、CR-011）：中繼狀態機、預熱、配對 UI 狀態、生命週期

final class FakeRelayIdentity: RelayIdentity, @unchecked Sendable {
    let lock = NSLock()
    var fp = Fingerprint(bytes: Data(repeating: 0xAB, count: 32))!
    var warmUpResult: Result<Void, IdentityError> = .success(())
    var warmUpCount = 0
    var fingerprintCalls = 0
    /// 唯讀指紋（R7）：false＝沒有身分或鑰匙圈讀不到
    var hasStoredIdentity = true
    var storedCalls = 0
    /// 非 nil 時預熱會停住，直到測試呼叫 release
    var gate: CheckedContinuation<Void, Never>?
    var holdWarmUp = false

    func fingerprint() throws(IdentityError) -> Fingerprint { lock.withLock { fingerprintCalls += 1; return fp } }
    func storedFingerprint() -> Fingerprint? { lock.withLock { storedCalls += 1; return hasStoredIdentity ? fp : nil } }

    func warmUp() async throws(IdentityError) {
        let hold = lock.withLock { warmUpCount += 1; return holdWarmUp }
        if hold { await withCheckedContinuation { c in lock.withLock { gate = c } } }
        try lock.withLock { warmUpResult }.get()
    }

    func release() { lock.withLock { let g = gate; gate = nil; return g }?.resume() }
}

final class FakeRelayServer: RelayServing, @unchecked Sendable {
    let lock = NSLock()
    var started = 0, stopped = 0, approved = 0, rejected = 0, cancelled = 0
    var revoked: [UUID] = []
    let events: AsyncStream<ServerEvent>
    let continuation: AsyncStream<ServerEvent>.Continuation
    let payload = QRPairingPayload(sessionID: Data(repeating: 1, count: 16), macFingerprint: Fingerprint(bytes: Data(repeating: 0xAB, count: 32))!,
                                   secret: Data(repeating: 9, count: 32), instanceName: "Azathoth-ABAB")!

    /// 非 nil 時 start() 停住，直到測試 resume（模擬 listener 還沒 ready）
    let startGate: Locked<CheckedContinuation<Void, Never>?>?

    init(holdStart: Bool = false) {
        (events, continuation) = AsyncStream.makeStream()
        startGate = holdStart ? Locked(nil) : nil
    }

    func start() async throws {
        if let startGate { await withCheckedContinuation { c in startGate.withLock { $0 = c } } }
        lock.withLock { started += 1 }
    }

    func releaseStart() { startGate?.withLock { g in let c = g; g = nil; return c }?.resume() }
    var isHeldInStart: Bool { startGate?.withLock { $0 != nil } ?? false }
    /// 與真實 TransportServer 同序：取消／停止一個開著的窗時，在呼叫內同步送出該窗唯一的 terminal 事件（F-1）
    var windowOpen = false, opened = 0
    func stop() {
        let echo = lock.withLock { stopped += 1; return closeWindow() }
        if echo { continuation.yield(.pairingFinished(.cancelled)) }
    }
    func openPairingWindow() -> QRPairingPayload { lock.withLock { opened += 1; windowOpen = true }; return payload }
    func approvePairing() { lock.withLock { approved += 1 } }
    func rejectPairing() { lock.withLock { rejected += 1 } }
    func cancelPairing() {
        let echo = lock.withLock { cancelled += 1; return closeWindow() }
        if echo { continuation.yield(.pairingFinished(.cancelled)) }
    }
    /// 伺服端自行結束窗（核准、拒絕、過期）
    func finishWindow(_ outcome: PairOutcome) {
        lock.withLock { _ = closeWindow() }
        continuation.yield(.pairingFinished(outcome))
    }
    private func closeWindow() -> Bool { defer { windowOpen = false }; return windowOpen }
    func revoke(peerID: UUID) { lock.withLock { revoked.append(peerID) } }
    var connectedPeers: [UUID] { [] }
    var broadcasts: [String] = []
    func broadcastCatalogChanged(version: String) { lock.withLock { broadcasts.append(version) } }
    /// S4：存活的連線（測試設定）與推出的播放事件
    var aliveConnections: Set<UUID> = []
    var playbackBroadcasts: [RemoteProtocol.PlaybackEvent] = []
    func isConnectionAlive(_ id: UUID) -> Bool { lock.withLock { aliveConnections.contains(id) } }
    func broadcastPlayback(_ event: RemoteProtocol.PlaybackEvent) { lock.withLock { playbackBroadcasts.append(event) } }
}

/// 曲庫邊界的替身（S3 T8）：記錄 watch 呼叫與處理者
final class FakeRelayCatalog: RelayCatalog, @unchecked Sendable {
    let lock = NSLock()
    var calls: [String] = []
    var changed: (@Sendable (String) -> Void)?
    var availability: (@Sendable (Bool) -> Void)?

    func startWatching() async { lock.withLock { calls.append("start") } }
    func stopWatching() async { lock.withLock { calls.append("stop") } }
    /// CR-018：釋放 peer（detail 傳輸）另記，不混進 watch 呼叫序列
    var gone: [UUID] = []
    func releasePeer(_ peer: UUID) async { lock.withLock { gone.append(peer) } }
    var gonePeers: [UUID] { lock.withLock { gone } }
    func setHandlers(changed: (@Sendable (String) -> Void)?, availability: (@Sendable (Bool) -> Void)?) {
        lock.withLock { self.changed = changed; self.availability = availability }
    }
    var recorded: [String] { lock.withLock { calls } }
    func emitChange(_ version: String) { lock.withLock { changed }?(version) }
    func emitAvailability(_ ok: Bool) { lock.withLock { availability }?(ok) }
}

/// 播放邊界的替身（S4 T9）：記錄輪詢開關與連線通知、持有目前的接口；捷徑檢查與安裝回設定好的結果
final class FakeRelayPlayback: RelayPlayback, @unchecked Sendable {
    let lock = NSLock()
    var calls: [String] = []
    var outlets: PlaybackOutlets?
    var stored = false
    var checkResult = true
    var installPhases: [ShortcutInstaller.Phase] = [.waitingForAdd, .confirmingFirstRun]
    var installOutcome: ShortcutInstaller.Outcome = .installed(ShortcutIdentifier("8CF4FBAD-400E-412D-A7BA-D3BC9D2939CF")!)
    /// 非 nil 時安裝在送出第一個進度後停住，直到測試 release
    var installGate: CheckedContinuation<Void, Never>?
    var holdInstall = false

    var hasStoredShortcut: Bool { lock.withLock { stored } }
    func checkShortcut() async -> Bool { lock.withLock { calls.append("check"); return checkResult } }
    func installShortcut(progress: @escaping @Sendable (ShortcutInstaller.Phase) -> Void) async -> ShortcutInstaller.Outcome {
        let (phases, hold) = lock.withLock { calls.append("install"); return (installPhases, holdInstall) }
        if let first = phases.first { progress(first) }
        if hold { await withCheckedContinuation { c in lock.withLock { installGate = c } } }
        phases.dropFirst().forEach(progress)
        return lock.withLock { installOutcome }
    }
    func releaseInstall() { lock.withLock { let g = installGate; installGate = nil; return g }?.resume() }
    var isHeldInInstall: Bool { lock.withLock { installGate != nil } }

    func startWatching() async { lock.withLock { calls.append("start") } }
    func stopWatching() async { lock.withLock { calls.append("stop") } }
    func connectionAdded() async { lock.withLock { calls.append("added") } }
    func setOutlets(_ outlets: PlaybackOutlets?) { lock.withLock { calls.append(outlets == nil ? "detach" : "attach"); self.outlets = outlets } }
    var recorded: [String] { lock.withLock { calls } }
    var current: PlaybackOutlets? { lock.withLock { outlets } }
}

@MainActor
@Suite("RelayHost")
struct RelayHostTests {
    let identity = FakeRelayIdentity()
    let trust = InMemoryTrustStore()
    let preferences = InMemoryRelayPreferences()
    let servers = RelayServerLog()
    let catalog = FakeRelayCatalog()
    let playback = FakeRelayPlayback()
    var cdHash: String? = "cd01"

    func host(cdHash: String?? = nil, playback: (any RelayPlayback)? = nil) -> RelayHost {
        let servers = servers
        let hash = cdHash ?? self.cdHash
        return RelayHost(dependencies: RelayDependencies(
            identity: identity, trust: trust, preferences: preferences, catalog: catalog, playback: playback ?? self.playback, cdHash: { hash },
            makeServer: { let s = FakeRelayServer(holdStart: servers.holdStart); servers.made.append(s); return s }, now: { Date(timeIntervalSince1970: 100) }))
    }

    /// 在 main actor 上 yield（RelayHost 的事件 Task 在 main actor）；全域 settle(_:) 是 nonisolated，不能代用
    func settle() async { for _ in 0..<20 { await Task.yield() } }

    /// launch＝App 啟動時決定中繼要不要起，每個 host 一次；再呼叫不得重啟（`s6-61-login-launch.md` §5）
    @Test func launchTwiceStartsOnce() async {
        preferences.relayEnabled = true
        preferences.lastWarmedMarker = RelayStartup.marker(cdHash: "cd01", identity: identity.fp)
        let h = host()
        await h.launch()
        await h.launch()
        #expect(identity.warmUpCount == 1)
        #expect(servers.made.count == 1)
        #expect(servers.last?.stopped == 0)
        #expect(h.status == .running)
    }

    @Test func relayDefaultsOff() async {
        let h = host()
        await h.launch()
        #expect(h.status == .off && !h.isEnabled)
        #expect(servers.made.isEmpty && identity.warmUpCount == 0)
    }

    @Test func enablingWarmsUpThenAdvertisesAndRecordsMarker() async {
        let h = host()
        await h.setEnabled(true)
        #expect(identity.warmUpCount == 1)
        #expect(h.status == .running)
        #expect(servers.last?.started == 1)
        #expect(preferences.relayEnabled)
        #expect(preferences.lastWarmedMarker == RelayStartup.marker(cdHash: "cd01", identity: identity.fp))
    }

    @Test func relayDoesNotAdvertiseBeforeWarmUp() async {
        identity.warmUpResult = .failure(.keychainDenied)
        let h = host()
        await h.setEnabled(true)
        #expect(h.status == .needsKeychainApproval)
        #expect(servers.made.isEmpty)
        #expect(preferences.lastWarmedMarker == nil)
    }

    @Test func warmUpFailureShowsApprovalNeeded_noAutoRetry() async {
        identity.warmUpResult = .failure(.keychainDenied)
        let h = host()
        await h.setEnabled(true)
        await h.handle(.screenUnlocked)
        await h.handle(.didWake)
        #expect(identity.warmUpCount == 1)
        identity.warmUpResult = .success(())
        await h.retryAuthorization()
        #expect(identity.warmUpCount == 2 && h.status == .running)
    }

    @Test func sameBuildRelaunchWarmsUpAutomatically() async {
        preferences.relayEnabled = true
        preferences.lastWarmedMarker = RelayStartup.marker(cdHash: "cd01", identity: identity.fp)
        let h = host()
        await h.launch()
        #expect(identity.warmUpCount == 1 && h.status == .running)
    }

    @Test(arguments: ["newBuild", "newIdentity"]) func newBuildOrNewIdentityRelaunchWaitsForUser(change: String) async {
        preferences.relayEnabled = true
        preferences.lastWarmedMarker = RelayStartup.marker(cdHash: "cd01", identity: identity.fp)
        if change == "newIdentity" { identity.fp = Fingerprint(bytes: Data(repeating: 0xCD, count: 32))! }
        let h = host(cdHash: change == "newBuild" ? "cd02" : "cd01")
        await h.launch()
        #expect(h.status == .needsKeychainApproval && identity.warmUpCount == 0 && servers.made.isEmpty)
    }

    /// R7：唯讀取不到指紋（沒有身分或鑰匙圈讀不到）＝等使用者；啟動不得走 loadOrCreate（讀不到時會重建身分）
    @Test func launchWithoutStoredFingerprintWaitsForUser() async {
        preferences.relayEnabled = true
        preferences.lastWarmedMarker = RelayStartup.marker(cdHash: "cd01", identity: identity.fp)
        identity.hasStoredIdentity = false
        let h = host()
        await h.launch()
        #expect(h.status == .needsKeychainApproval)
        #expect(identity.fingerprintCalls == 0 && identity.warmUpCount == 0 && servers.made.isEmpty)
    }

    /// R7：自動預熱的 marker 只來自唯讀指紋；預熱完成前不呼叫 loadOrCreate
    @Test func sameBuildRelaunchTakesMarkerFromReadOnlyFingerprint() async {
        preferences.relayEnabled = true
        preferences.lastWarmedMarker = RelayStartup.marker(cdHash: "cd01", identity: identity.fp)
        identity.holdWarmUp = true
        let h = host()
        let launching = Task { await h.launch() }
        await settle()
        #expect(h.status == .warmingUp)
        #expect(identity.fingerprintCalls == 0 && identity.storedCalls > 0)
        identity.release()
        await launching.value
        #expect(h.status == .running)
    }

    /// R7（F4）：列裝置清單是純讀——關閉中繼、App 結束時刷新清單不得建立或重建身分
    @Test func listingPeersNeverUsesLoadOrCreate() async {
        let h = host()
        h.shutdown()
        await h.setEnabled(false)
        #expect(identity.fingerprintCalls == 0)
        #expect(identity.storedCalls > 0)
    }

    @Test func unreadableMarkerFailsClosed() async {
        preferences.relayEnabled = true
        preferences.lastWarmedMarker = "garbage"
        let h = host(cdHash: .some(nil))
        await h.launch()
        #expect(h.status == .needsKeychainApproval && identity.warmUpCount == 0)
    }

    @Test func lateWarmUpResultAfterStopIsDiscarded() async {
        identity.holdWarmUp = true
        let h = host()
        let enabling = Task { await h.setEnabled(true) }
        await settle()
        #expect(h.status == .warmingUp)
        await h.setEnabled(false)
        identity.release()
        await enabling.value
        #expect(h.status == .off)
        #expect(servers.made.isEmpty)
        #expect(preferences.lastWarmedMarker == nil)
    }

    @Test func screenLockCancelsWindowAndDisconnectsThenUnlockRestarts() async {
        let h = host()
        await h.setEnabled(true)
        h.startPairing()
        await h.handle(.screenLocked)
        #expect(servers.made.first?.stopped == 1)
        #expect(h.pairing == .idle)
        #expect(h.status == .paused)
        await h.handle(.screenUnlocked)
        #expect(servers.made.count == 2 && servers.last?.started == 1)
        #expect(identity.warmUpCount == 1)
        #expect(h.status == .running)
    }

    /// codex 第 1 輪 P1：預熱還在等鑰匙圈時上鎖——預熱照常完成（不取消授權），但鎖定期間不得啟動廣播；解鎖後才起
    @Test func lockDuringWarmUpDefersServerUntilUnlock() async {
        identity.holdWarmUp = true
        let h = host()
        let enabling = Task { await h.setEnabled(true) }
        await settle()
        await h.handle(.screenLocked)
        identity.release()
        await enabling.value
        #expect(servers.made.isEmpty)
        #expect(h.status == .paused)
        await h.handle(.screenUnlocked)
        #expect(servers.made.count == 1 && servers.last?.started == 1)
        #expect(h.status == .running && identity.warmUpCount == 1)
    }

    /// security 補查 LOW：睡眠後喚醒但螢幕仍鎖著（需密碼）＝不廣播，要等解鎖
    @Test func wakeWhileScreenStillLockedWaitsForUnlock() async {
        let h = host()
        await h.setEnabled(true)
        await h.handle(.screenLocked)
        await h.handle(.willSleep)
        await h.handle(.didWake)
        #expect(servers.made.count == 1 && h.status == .paused)
        await h.handle(.screenUnlocked)
        #expect(servers.made.count == 2 && h.status == .running)
    }

    /// 睡眠時沒有鎖屏（未設喚醒需密碼）：喚醒即恢復
    @Test func wakeWithoutScreenLockResumes() async {
        let h = host()
        await h.setEnabled(true)
        await h.handle(.willSleep)
        await h.handle(.didWake)
        #expect(servers.made.count == 2 && h.status == .running)
    }

    /// codex 第 1 輪 P1：伺服端啟動中（listener 未 ready）上鎖——停掉它、不進 running
    @Test func lockWhileServerStartingStopsIt() async {
        servers.holdStart = true
        let h = host()
        let enabling = Task { await h.setEnabled(true) }
        for _ in 0..<50 where servers.last?.isHeldInStart != true { await Task.yield() }
        await h.handle(.screenLocked)
        servers.last?.releaseStart()
        await enabling.value
        #expect(servers.last?.stopped ?? 0 >= 1)
        #expect(h.status == .paused)
    }

    /// security review S2 LOW-3：中繼關閉時啟動不碰鑰匙圈（取指紋＝loadOrCreate 會建立長期身分）
    @Test func relayOffLaunchDoesNotTouchKeychain() async {
        let h = host()
        await h.launch()
        #expect(identity.fingerprintCalls == 0 && identity.storedCalls == 0)
    }

    /// security review S2 LOW-8：關掉設定 modal＝取消進行中的配對窗（看不到確認窗就不該讓它繼續開著）
    @Test func closingSettingsCancelsAnOpenPairing() async {
        let h = host()
        await h.setEnabled(true)
        h.startPairing()
        h.settingsClosed()
        #expect(servers.last?.cancelled == 1)
        #expect(h.pairing == .idle)
        h.settingsClosed()
        #expect(servers.last?.cancelled == 1)
    }

    @Test func pairingFlowDrivesUIState() async {
        let h = host()
        await h.setEnabled(true)
        h.startPairing()
        guard case .showingQR(let text, _) = h.pairing else { Issue.record("no QR"); return }
        #expect(text == servers.last!.payload.encoded())
        servers.last!.continuation.yield(.pairingPending(name: "iPad", suffix: "0A0B"))
        await settle()
        #expect(h.pairing == .confirming(name: "iPad", suffix: "0A0B"))
        h.approvePairing()
        #expect(servers.last!.approved == 1)
        try? trust.add(PeerRecord(peerID: UUID(), fingerprint: Fingerprint(bytes: Data(repeating: 1, count: 32))!,
                                  localFingerprint: identity.fp, name: "iPad", pairedAt: Date()))
        servers.last!.continuation.yield(.pairingFinished(.approved))
        await settle()
        #expect(h.pairing == .finished(.approved))
        #expect(h.peers.count == 1)
    }

    // MARK: F-1：本機放棄的配對窗，其遲到事件不得改畫面

    @Test func localCancelEchoDoesNotReopenResultPanel() async {
        let h = host()
        await h.setEnabled(true)
        h.startPairing()
        h.settingsClosed()
        await settle()
        #expect(h.pairing == .idle)
    }

    @Test func cancelThenImmediateNewWindowKeepsNewQR() async {
        let h = host()
        await h.setEnabled(true)
        h.startPairing()
        h.cancelPairing()
        h.startPairing()
        await settle()
        guard case .showingQR = h.pairing else { Issue.record("new QR replaced: \(h.pairing)"); return }
    }

    @Test func pendingQueuedBeforeCancelIsIgnored() async {
        let h = host()
        await h.setEnabled(true)
        h.startPairing()
        servers.last!.continuation.yield(.pairingPending(name: "iPad", suffix: "0A0B"))
        h.cancelPairing()
        await settle()
        #expect(h.pairing == .idle)
    }

    @Test func eventsFromStoppedServerDoNotTouchNewWindow() async {
        let h = host()
        await h.setEnabled(true)
        let old = servers.last!
        h.startPairing()
        await h.handle(.screenLocked)
        await h.handle(.screenUnlocked)
        h.startPairing()
        old.continuation.yield(.pairingPending(name: "iPad", suffix: "0A0B"))
        old.continuation.yield(.pairingFinished(.expired))
        await settle()
        #expect(servers.made.count == 2)
        guard case .showingQR = h.pairing else { Issue.record("stale event applied: \(h.pairing)"); return }
    }

    @Test func expiryWhileShowingQRShowsResult() async {
        let h = host()
        await h.setEnabled(true)
        h.startPairing()
        servers.last!.finishWindow(.expired)
        await settle()
        #expect(h.pairing == .finished(.expired))
        h.startPairing()
        guard case .showingQR = h.pairing else { Issue.record("no new QR after expiry"); return }
    }

    @Test func approveThenCloseHidesResultButRefreshesPeers() async {
        let h = host()
        await h.setEnabled(true)
        h.startPairing()
        servers.last!.continuation.yield(.pairingPending(name: "iPad", suffix: "0A0B"))
        await settle()
        h.approvePairing()
        try? trust.add(PeerRecord(peerID: UUID(), fingerprint: Fingerprint(bytes: Data(repeating: 1, count: 32))!,
                                  localFingerprint: identity.fp, name: "iPad", pairedAt: Date()))
        servers.last!.finishWindow(.approved)
        h.settingsClosed()
        await settle()
        #expect(h.pairing == .idle)
        #expect(h.peers.count == 1)
    }

    @Test func startPairingWhileWindowOpenIsIgnored() async {
        let h = host()
        await h.setEnabled(true)
        h.startPairing()
        h.startPairing()
        #expect(servers.last!.opened == 1)
    }

    @Test func revokeRemovesPeerThroughServer() async {
        let id = UUID()
        try? trust.add(PeerRecord(peerID: id, fingerprint: Fingerprint(bytes: Data(repeating: 1, count: 32))!,
                                  localFingerprint: identity.fp, name: "iPad", pairedAt: Date()))
        let h = host()
        await h.setEnabled(true)
        #expect(h.peers.map(\.id) == [id])
        h.revoke(id)
        #expect(servers.last!.revoked == [id])
    }

    @Test func disablingStopsServerAndPersists() async {
        let h = host()
        await h.setEnabled(true)
        await h.setEnabled(false)
        #expect(servers.last?.stopped == 1 && h.status == .off && !preferences.relayEnabled)
    }

    @Test func peersOnlyShowRecordsOfCurrentIdentity() async {
        try? trust.add(PeerRecord(peerID: UUID(), fingerprint: Fingerprint(bytes: Data(repeating: 1, count: 32))!,
                                  localFingerprint: Fingerprint(bytes: Data(repeating: 0xEE, count: 32))!, name: "old", pairedAt: Date()))
        let h = host()
        await h.setEnabled(true)
        #expect(h.peers.isEmpty)
    }
    // MARK: S3 T8：曲庫接線（sprint-3-detail.md §4.5、§4.7、附錄 D H-31 草稿）

    /// 中繼關閉時不碰曲庫邊界（H-31 草稿：不讀 ITLibrary、不會出現媒體庫授權框）
    @Test func relayOffNeverTouchesCatalog() async {
        let h = host()
        await h.launch()
        await settle()
        #expect(catalog.recorded.isEmpty)
        #expect(catalog.changed == nil && catalog.availability == nil)
    }

    @Test func firstPeerStartsWatchingAndLastPeerStopsIt() async throws {
        let h = host()
        await h.setEnabled(true)
        let server = try #require(servers.last)
        let a = UUID(), b = UUID()
        server.continuation.yield(.peerConnected(a))
        server.continuation.yield(.peerConnected(b))
        server.continuation.yield(.peerDisconnected(a))
        await settle()
        #expect(catalog.recorded == ["start"])
        server.continuation.yield(.peerDisconnected(b))
        await settle()
        #expect(catalog.recorded == ["start", "stop"])
        server.continuation.yield(.peerConnected(a))
        await settle()
        #expect(catalog.recorded == ["start", "stop", "start"])
    }

    /// CR-018：每次連上與每個 peer 斷線都通知曲庫釋放該 peer 的 detail 傳輸（不論是否為最後一個；
    /// 連上也釋放＝同 peer 新連線取代舊連線時不會收到 peerDisconnected，App 重開後世代從頭算）
    @Test func everyConnectAndDisconnectReleasesThePeer() async throws {
        let h = host()
        await h.setEnabled(true)
        let server = try #require(servers.last)
        let a = UUID(), b = UUID()
        server.continuation.yield(.peerConnected(a))
        server.continuation.yield(.peerConnected(b))
        server.continuation.yield(.peerDisconnected(a))
        server.continuation.yield(.peerDisconnected(b))
        await settle()
        #expect(catalog.gonePeers == [a, b, a, b])
    }

    /// CR-018／simcodex R1：關遙控（停伺服端）時連線被直接拆掉、不會再收到 peerDisconnected——仍要通知曲庫釋放 detail 傳輸
    @Test func stoppingServerReleasesEveryConnectedPeer() async throws {
        let h = host()
        await h.setEnabled(true)
        let server = try #require(servers.last)
        let a = UUID(), b = UUID()
        server.continuation.yield(.peerConnected(a))
        server.continuation.yield(.peerConnected(b))
        await settle()
        let released = catalog.gonePeers.count
        await h.setEnabled(false)
        await settle()
        #expect(Set(catalog.gonePeers.dropFirst(released)) == [a, b])
    }

    @Test func stoppingServerWithPeersStopsWatchingAndDetachesHandlers() async throws {
        let h = host()
        await h.setEnabled(true)
        try #require(servers.last).continuation.yield(.peerConnected(UUID()))
        await settle()
        await h.setEnabled(false)
        await settle()
        #expect(catalog.recorded == ["start", "stop"])
        #expect(catalog.changed == nil)
    }

    // F13（s4-followups-2026-10-19.md T2）：關遙控、上鎖後綠點要滅；停掉的伺服端晚到的事件不得把綠點加回

    private func connectedPeer(_ h: RelayHost) async throws -> (UUID, FakeRelayServer) {
        let id = UUID()
        try trust.add(PeerRecord(peerID: id, fingerprint: Fingerprint(bytes: Data(repeating: 1, count: 32))!,
                                 localFingerprint: identity.fp, name: "iPad", pairedAt: Date()))
        await h.setEnabled(true)
        let server = try #require(servers.last)
        server.continuation.yield(.peerConnected(id))
        await settle()
        #expect(h.peers.map(\.isConnected) == [true])
        return (id, server)
    }

    @Test func turningRelayOffClearsConnectedDots() async throws {
        let h = host()
        _ = try await connectedPeer(h)
        await h.setEnabled(false)
        #expect(h.peers.map(\.isConnected) == [false])
    }

    @Test func lockingClearsConnectedDots() async throws {
        let h = host()
        _ = try await connectedPeer(h)
        await h.handle(.screenLocked)
        #expect(h.status == .paused)
        #expect(h.peers.map(\.isConnected) == [false])
    }

    @Test func eventsFromStoppedServerAreIgnored() async throws {
        let h = host()
        let (id, server) = try await connectedPeer(h)
        await h.setEnabled(false)
        await settle()   // 關閉時排入的 stop 先跑完，再當基準
        let before = catalog.recorded
        server.continuation.yield(.peerConnected(id))
        await settle()
        #expect(h.peers.map(\.isConnected) == [false])
        #expect(catalog.recorded == before)
    }

    /// simcodex R2 security MEDIUM-1：關遙控之前已送出、還沒處理的舊事件（例如 iPad 剛好重連），關掉後不得生效——
    /// 否則遙控關著卻開始輪詢 Music（違反 D13）、設定頁亮綠點。取消迭代的 Task 不保證不再交出已送達的元素
    @Test func eventQueuedBeforeTurningOffIsIgnored() async throws {
        let h = host()
        let (id, server) = try await connectedPeer(h)
        server.continuation.yield(.peerDisconnected(id))
        await settle()
        let before = catalog.recorded
        server.continuation.yield(.peerConnected(id))   // 同一輪 main actor 內緊接著關閉：事件已送達、還沒處理
        await h.setEnabled(false)
        await settle()
        #expect(h.peers.map(\.isConnected) == [false])
        #expect(catalog.recorded == before)
    }

    @Test func catalogChangeIsBroadcastByCurrentServer() async throws {
        let h = host()
        await h.setEnabled(true)
        catalog.emitChange("00000000000000aa")
        #expect(try #require(servers.last).broadcasts == ["00000000000000aa"])
    }

    // MARK: S4 T9 播放輪詢與接口（§4.7、D13）

    @Test func relayOffNeverTouchesPlayback() async {
        let h = host()
        await h.launch()
        await settle()
        #expect(playback.recorded.isEmpty && playback.current == nil)
    }

    @Test func firstPeerStartsPollingOthersResendAndLastStopsIt() async throws {
        let h = host()
        await h.setEnabled(true)
        let server = try #require(servers.last)
        let a = UUID(), b = UUID()
        server.continuation.yield(.peerConnected(a))
        server.continuation.yield(.peerConnected(b))
        server.continuation.yield(.peerDisconnected(a))
        await settle()
        #expect(playback.recorded == ["attach", "start", "added"])
        server.continuation.yield(.peerDisconnected(b))
        await settle()
        #expect(playback.recorded == ["attach", "start", "added", "stop"])
        // 同一 peer 的新連線取代舊連線（CR-012 不送 peerDisconnected）：也要把目前狀態再推一次
        server.continuation.yield(.peerConnected(a))
        server.continuation.yield(.peerConnected(a))
        await settle()
        #expect(playback.recorded == ["attach", "start", "added", "stop", "start", "added"])
    }

    @Test func outletsRouteToCurrentServerAndDetachOnStop() async throws {
        let h = host()
        await h.setEnabled(true)
        let server = try #require(servers.last)
        let alive = UUID()
        server.lock.withLock { server.aliveConnections = [alive] }
        let outlets = try #require(playback.current)
        #expect(outlets.isAlive(alive) && !outlets.isAlive(UUID()))
        let event = RemoteProtocol.PlaybackEvent(availability: .ok, trackID: nil, albumID: nil, state: .stopped, position: 0, duration: nil, sampledAt: 0)
        outlets.push(event)
        #expect(server.lock.withLock { server.playbackBroadcasts } == [event])
        await h.setEnabled(false)
        #expect(playback.current == nil && playback.recorded.last == "detach")
    }

    @Test func stoppingServerWithPeersStopsPolling() async throws {
        let h = host()
        await h.setEnabled(true)
        try #require(servers.last).continuation.yield(.peerConnected(UUID()))
        await settle()
        await h.setEnabled(false)
        await settle()
        #expect(playback.recorded == ["attach", "start", "detach", "stop"])
    }

    /// D13（H-26 的 S4 證據）：中繼關閉、或開啟但沒有 iPad 連線時，真的 PlaybackService 不讀 Music、不跑捷徑、不讀 Queue.dat
    @Test func relayOffSendsNoRemoteAppleEvents() async throws {
        let spy = CountingPlaybackParts()
        let live = LiveRelayPlayback(service: spy.service())
        let h = host(playback: live)
        await h.launch()
        await settle()
        #expect(spy.total == 0)
        await h.setEnabled(true)
        await settle()
        #expect(spy.total == 0)
        // 對照：有連線時確實會讀（證明這個 spy 看得到呼叫）
        let server = try #require(servers.last)
        let peer = UUID()
        server.continuation.yield(.peerConnected(peer))
        try await waitUntil { spy.musicReads > 0 }
        server.continuation.yield(.peerDisconnected(peer))
        await settle()
        try await Task.sleep(for: .milliseconds(300))
        let afterStop = spy.musicReads
        try await Task.sleep(for: .milliseconds(1200))
        #expect(spy.musicReads == afterStop)
        #expect(spy.shortcutStarts == 0 && spy.queueReads == 0 && spy.listings == 0)
        await h.setEnabled(false)
    }

    private func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    // MARK: S4 T9 設定頁：捷徑與 Music 控制權限

    @Test func shortcutActionsAreIgnoredWhileRelayIsOff() async {
        let h = host()
        await h.launch()
        await h.checkShortcut()
        await h.installShortcut()
        #expect(playback.recorded.isEmpty && h.shortcut == .idle)
    }

    @Test func checkShortcutShowsResult() async {
        let h = host()
        await h.setEnabled(true)
        playback.lock.withLock { playback.checkResult = false }
        await h.checkShortcut()
        #expect(h.shortcut == .checked(bound: false))
        #expect(playback.recorded.contains("check"))
    }

    @Test func installShowsEachPhaseThenTheOutcome() async throws {
        let h = host()
        await h.setEnabled(true)
        playback.lock.withLock { playback.holdInstall = true }
        let task = Task { await h.installShortcut() }
        for _ in 0..<200 where !playback.isHeldInInstall { try await Task.sleep(for: .milliseconds(5)) }
        await settle()
        #expect(h.shortcut == .installing(.waitingForAdd))
        // 安裝進行中不接受第二次
        await h.installShortcut()
        #expect(playback.recorded.filter { $0 == "install" }.count == 1)
        playback.releaseInstall()
        await task.value
        #expect(h.shortcut == .installed)
    }

    @Test func installFailureIsShown() async {
        let h = host()
        await h.setEnabled(true)
        playback.lock.withLock { playback.installOutcome = .nameTaken }
        await h.installShortcut()
        #expect(h.shortcut == .installFailed(.nameTaken))
    }

    /// §4.9 #2：Music 未允許控制 → 設定頁顯示；權限恢復（事件 availability=ok）或中繼停止 → 解除
    @Test func automationDeniedEventsDriveSettingsState() async throws {
        let h = host()
        await h.setEnabled(true)
        let outlets = try #require(playback.current)
        func event(_ availability: PlaybackAvailability) -> RemoteProtocol.PlaybackEvent {
            RemoteProtocol.PlaybackEvent(availability: availability, trackID: nil, albumID: nil, state: .stopped, position: 0,
                                         duration: nil, sampledAt: 0)
        }
        outlets.push(event(.automationDenied))
        await settle()
        #expect(h.musicNotAuthorized)
        outlets.push(event(.ok))
        await settle()
        #expect(!h.musicNotAuthorized)
        outlets.push(event(.automationDenied))
        await settle()
        await h.setEnabled(false)
        #expect(!h.musicNotAuthorized)
    }

    @Test func libraryAvailabilityDrivesSettingsState() async {
        let h = host()
        await h.setEnabled(true)
        #expect(!h.libraryUnavailable)
        catalog.emitAvailability(false)
        await settle()
        #expect(h.libraryUnavailable)
        catalog.emitAvailability(true)
        await settle()
        #expect(!h.libraryUnavailable)
    }

}

@Suite("RelayStartup")
struct RelayStartupTests {
    let fp = Fingerprint(bytes: Data(repeating: 1, count: 32))!

    @Test func decisions() {
        let marker = RelayStartup.marker(cdHash: "h", identity: fp)
        #expect(RelayStartup.decide(enabled: false, stored: marker, current: marker) == .stayOff)
        #expect(RelayStartup.decide(enabled: true, stored: marker, current: marker) == .autoWarmUp)
        #expect(RelayStartup.decide(enabled: true, stored: marker, current: nil) == .waitForUser)
        #expect(RelayStartup.decide(enabled: true, stored: nil, current: marker) == .waitForUser)
        #expect(RelayStartup.decide(enabled: true, stored: "x", current: marker) == .waitForUser)
    }

    @Test func markerUsesFullCDHashAndFingerprint() {
        let marker = RelayStartup.marker(cdHash: "0123456789abcdef0123456789abcdef01234567", identity: fp)
        #expect(marker?.contains("0123456789abcdef0123456789abcdef01234567") == true)
        #expect(marker?.contains(fp.bytes.map { String(format: "%02x", $0) }.joined()) == true)
        #expect(RelayStartup.marker(cdHash: nil, identity: fp) == nil)
        #expect(RelayStartup.marker(cdHash: "", identity: fp) == nil)
    }

}

/// D13 用：計數每一種對外動作的替身（Music 讀取／指令、捷徑啟動、清單、Queue.dat）
final class CountingPlaybackParts: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func bump(_ key: String) { lock.withLock { counts[key, default: 0] += 1 } }
    private func count(_ key: String) -> Int { lock.withLock { counts[key, default: 0] } }
    var musicReads: Int { count("music") }
    var shortcutStarts: Int { count("start") }
    var queueReads: Int { count("queue") }
    var listings: Int { count("list") }
    var total: Int { lock.withLock { counts.values.reduce(0, +) } }

    func service() -> PlaybackService {
        PlaybackService(music: Music(parts: self), plans: Plans(), albumOf: { _ in nil }, binding: Binding(parts: self),
                        starter: Starter(parts: self), queueReader: Queue(parts: self))
    }

    struct Music: PlaybackMusic {
        let parts: CountingPlaybackParts
        func snapshot() async throws(MusicLaneError) -> MusicSnapshot {
            parts.bump("music")
            return MusicSnapshot(state: .paused, trackID: nil, duration: nil, position: 0)
        }
        func playOnce(trackID: String) async throws(MusicLaneError) -> Bool { parts.bump("music"); return false }
        func next() async throws(MusicLaneError) { parts.bump("music") }
        func previous() async throws(MusicLaneError) { parts.bump("music") }
        func togglePlayPause() async throws(MusicLaneError) { parts.bump("music") }
        func seek(to seconds: Double) async throws(MusicLaneError) { parts.bump("music") }
        func outputs() async throws(MusicLaneError) -> [OutputDeviceSummary] { parts.bump("music"); return [] }
        func setOutputs(_ ids: [String]) async throws(MusicLaneError) -> Bool { parts.bump("music"); return false }
    }

    struct Plans: PlayPlanProviding {
        func plan(for request: PlayTrackRequest) async -> Result<AdmissionResult, ErrorCode> { .failure(.libraryUnavailable) }
    }

    struct Binding: ShortcutBindingChecking {
        let parts: CountingPlaybackParts
        func status() async -> ShortcutBindingStatus { parts.bump("list"); return .missing }
    }

    struct Starter: ShortcutStarting {
        let parts: CountingPlaybackParts
        func start(_ shortcut: ShortcutIdentifier, input: ShortcutInput) -> RunningShortcut? { parts.bump("start"); return nil }
    }

    struct Queue: QueueReading {
        let parts: CountingPlaybackParts
        func read() async -> [String]? { parts.bump("queue"); return nil }
    }
}
