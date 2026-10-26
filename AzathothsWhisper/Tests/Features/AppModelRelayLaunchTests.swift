import AppKit
import Foundation
import MusicRemoteBridge
import RemoteTransport
import Testing

@testable import AzathothsWhisper

// 登入時啟動後 iPad 連不上（docs/plans/2026-10-14-yse/s6-61-login-launch.md L1）：
// 中繼由 App 啟動（AppDelegate）發起、與視窗無關；開視窗後的 start() 不得重啟中繼
@MainActor
@Suite("AppModel 中繼啟動")
struct AppModelRelayLaunchTests {
    private struct AlwaysValidValidator: TokenValidating {
        func validate(token: String) async -> TokenValidation { .valid }
    }

    let identity = FakeRelayIdentity()
    let preferences = InMemoryRelayPreferences()
    let servers = RelayServerLog()
    /// 畫面路徑的 start() 會訂閱換歌訊號；計數＝0 即證明 start() 沒跑過
    let signal = SpyPlayerChangeSignal()
    let suiteName = "AppModelRelayLaunchTests-\(UUID().uuidString)"

    /// 中繼開著且本建置已授權過（marker 符合）＝launch 走自動預熱
    private func makeModel() -> AppModel {
        preferences.relayEnabled = true
        preferences.lastWarmedMarker = RelayStartup.marker(cdHash: "cd01", identity: identity.fp)
        let servers = servers
        let host = RelayHost(dependencies: RelayDependencies(
            identity: identity, trust: InMemoryTrustStore(), preferences: preferences,
            catalog: FakeRelayCatalog(), playback: FakeRelayPlayback(), cdHash: { "cd01" },
            makeServer: { let s = FakeRelayServer(); servers.made.append(s); return s },
            now: { Date(timeIntervalSince1970: 100) }))
        let store = ConfigStore(secrets: EphemeralSecretStore(), defaults: UserDefaults(suiteName: suiteName)!)
        store.setNotificationsEnabled(false)
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "l")])
        let model = AppModel(
            configStore: store,
            httpClient: MockHTTPClient(),
            music: music,
            monitor: NowPlayingMonitor(music: music, clock: GatedPollClock()),
            validator: AlwaysValidValidator(),
            notifier: SpyLyricsNotifier(),
            playerSignal: signal,
            initialToken: "",
            initialLanguage: .system,
            artistStylesStartDelay: .milliseconds(1),
            lyricsFlowClock: GatedPollClock(),
            isMusicRunning: { true },
            relayHost: host
        )
        model.editor.isEditorTabActive = false
        return model
    }

    private func tearDown(_ model: AppModel) {
        model.stop()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// 中繼啟動是非結構化 Task：正向條件用共用 `waitUntil`（成立即返回，上限給足避免負載下偽紅）
    private static let yields = 20_000

    /// 「不得發生」：真的睡一段牆鐘時間——呼叫端（main actor）讓出，排在 main actor 上的 launch 與
    /// 離開再回來的 warm-up 都有機會跑完。`Tests/Support` 的 `settle(_:)` 是 nonisolated 空轉，不保證這點
    private func letPendingWorkRun() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    private var startedServers: Int { servers.made.reduce(0) { $0 + $1.started } }

    // ① 只由 startRelay 發起（不經畫面的 start()）
    @Test func startRelayAloneBringsTheRelayUp() async {
        let model = makeModel()
        defer { tearDown(model) }
        model.startRelay()
        await waitUntil({ model.relayHost.status == .running }, iterations: Self.yields)
        #expect(startedServers == 1)
        #expect(identity.warmUpCount == 1)
        #expect(model.relayHost.status == .running)
    }

    // ② 之後開視窗（start()）不重啟
    @Test func openingTheWindowLaterDoesNotRestartTheRelay() async {
        let model = makeModel()
        defer { tearDown(model) }
        model.startRelay()
        await waitUntil({ startedServers == 1 }, iterations: Self.yields)
        await model.start()
        await letPendingWorkRun()
        #expect(servers.made.count == 1)
        #expect(servers.made.first?.stopped == 0)
        #expect(identity.warmUpCount == 1)
    }

    // ③ 舊路徑（只有 start()）仍啟動一次
    @Test func startAloneStillBringsTheRelayUpOnce() async {
        let model = makeModel()
        defer { tearDown(model) }
        await model.start()
        await waitUntil({ startedServers == 1 }, iterations: Self.yields)
        #expect(startedServers == 1)
        #expect(servers.made.count == 1)
    }

    // ④ 連呼叫兩次
    @Test func startRelayTwiceLaunchesOnce() async {
        let model = makeModel()
        defer { tearDown(model) }
        model.startRelay()
        model.startRelay()
        await waitUntil({ startedServers == 1 }, iterations: Self.yields)
        await letPendingWorkRun()
        #expect(servers.made.count == 1)
        #expect(identity.warmUpCount == 1)
    }

    // ⑤ 同一回合立刻 stop＝不啟動
    @Test func stopRightAfterStartRelayNeverStartsAServer() async {
        let model = makeModel()
        model.startRelay()
        tearDown(model)
        await letPendingWorkRun()
        #expect(servers.made.isEmpty)
        #expect(identity.warmUpCount == 0)
    }

    // ⑥ launch 已進入、卡在預熱時 stop＝釋放後也不啟動
    @Test func stopDuringWarmUpNeverStartsAServer() async {
        identity.holdWarmUp = true
        let model = makeModel()
        model.startRelay()
        await waitUntil({ identity.warmUpCount == 1 }, iterations: Self.yields)
        #expect(identity.warmUpCount == 1)
        tearDown(model)
        identity.release()
        await letPendingWorkRun()
        #expect(servers.made.isEmpty)
        #expect(model.relayHost.status == .off)
    }

    // 無視窗啟動的回歸：AppDelegate 收到啟動完成就發起，注入的 model 從未跑過畫面的 start()
    @Test func finishLaunchingStartsTheRelayWithoutAnyView() async {
        let model = makeModel()
        defer { tearDown(model) }
        let delegate = AppDelegate(model: model)
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await waitUntil({ startedServers == 1 }, iterations: Self.yields)
        #expect(startedServers == 1)
        #expect(signal.startCount == 0, "start() 沒跑過：中繼不是由畫面發起")
    }
}
