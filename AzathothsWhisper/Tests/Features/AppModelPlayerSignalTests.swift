import Foundation
import Testing

@testable import AzathothsWhisper

// F1 接線（計劃 2026-09-27-coverflow-f1-f2 §3.1、§4 13–14）：經 start()／stop() 驗，不另開公開方法
@MainActor
@Suite("AppModel player signal")
struct AppModelPlayerSignalTests {
    private struct AlwaysValidValidator: TokenValidating {
        func validate(token: String) async -> TokenValidation { .valid }
    }

    @MainActor
    private struct Fixture {
        let model: AppModel
        let signal: SpyPlayerChangeSignal
        let music: MockMusicClient
        let pollClock: GatedPollClock
        let suiteName: String

        func tearDown() {
            model.stop()
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeFixture() -> Fixture {
        let suiteName = "AppModelPlayerSignalTests-\(UUID().uuidString)"
        let store = ConfigStore(secrets: EphemeralSecretStore(), defaults: UserDefaults(suiteName: suiteName)!)
        store.setNotificationsEnabled(false)
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "l")])
        // 輪詢讀一次後停在 sleep：之後的讀取次數只來自訊號
        let pollClock = GatedPollClock()
        let signal = SpyPlayerChangeSignal()
        let model = AppModel(
            configStore: store,
            httpClient: MockHTTPClient(),
            music: music,
            monitor: NowPlayingMonitor(music: music, clock: pollClock),
            validator: AlwaysValidValidator(),
            notifier: SpyLyricsNotifier(),
            playerSignal: signal,
            initialToken: "",
            initialLanguage: .system,
            splashDuration: .milliseconds(1),
            lyricsFlowClock: GatedPollClock(),
            isMusicRunning: { true }
        )
        model.editor.isEditorTabActive = false
        return Fixture(model: model, signal: signal, music: music, pollClock: pollClock, suiteName: suiteName)
    }

    @Test func startListensForPlayerChangesOnce() async {
        let fixture = makeFixture()
        defer { fixture.tearDown() }

        await fixture.model.start()
        await fixture.model.start()

        #expect(fixture.signal.startCount == 1)
    }

    @Test func stopStopsListening() async {
        let fixture = makeFixture()
        defer { fixture.tearDown() }
        await fixture.model.start()

        fixture.model.stop()

        #expect(fixture.signal.stopCount >= 1)
    }

    @Test func aPlayerChangeReachesTheMonitor() async {
        let fixture = makeFixture()
        defer { fixture.tearDown() }
        await fixture.model.start()
        await fixture.pollClock.waitUntilPending(1)
        let before = await fixture.music.nowPlayingCalls

        fixture.signal.fire()
        await waitFor { await fixture.music.nowPlayingCalls == before + 1 }

        #expect(await fixture.music.nowPlayingCalls == before + 1, "訊號觸發恰一次讀取")
    }
}
