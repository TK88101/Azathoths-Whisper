import Foundation
import Testing

@testable import AzathothsWhisper

// 接線（母計劃 §2.8；A1 計劃 §3.3／§3.4）：事件、寫入、busy 與換歌通知都扇出到歌詞特效。歌詞為編造句
@MainActor
@Suite("AppModel lyrics FX")
struct AppModelLyricsFXTests {
    private struct AlwaysValidValidator: TokenValidating {
        func validate(token: String) async -> TokenValidation { .valid }
    }

    static let track = TrackInfo.fixture(id: "0123456789ABCDEF")

    @MainActor
    private struct Fixture {
        let model: AppModel
        let monitor: NowPlayingMonitor
        let signal: SpyPlayerChangeSignal
        let music: MockMusicClient
        let positionPoll: GatedPollClock
        let suiteName: String

        func tearDown() {
            model.stop()
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeFixture(
        _ script: [MockMusicClient.Response],
        suiteName: String = "AppModelLyricsFXTests-\(UUID().uuidString)",
        prepare: (ConfigStore) -> Void = { _ in }
    ) async -> Fixture {
        let store = ConfigStore(secrets: EphemeralSecretStore(), defaults: UserDefaults(suiteName: suiteName)!)
        store.setNotificationsEnabled(false)
        prepare(store)
        let music = MockMusicClient(script: script, repeatLast: script.count == 1)
        await music.setPlaybackPositions([.success(PlaybackPosition(persistentID: Self.track.persistentID, seconds: 1, state: .playing, readAt: .now, roundTrip: .zero))])
        let monitor = NowPlayingMonitor(music: music, clock: GatedPollClock())
        let signal = SpyPlayerChangeSignal()
        let positionPoll = GatedPollClock()
        let model = AppModel(
            configStore: store,
            httpClient: MockHTTPClient(),
            music: music,
            monitor: monitor,
            validator: AlwaysValidValidator(),
            notifier: SpyLyricsNotifier(),
            playerSignal: signal,
            initialToken: "",
            initialLanguage: .system,
            splashDuration: .milliseconds(1),
            lyricsFlowClock: GatedPollClock(),
            positionPollClock: positionPoll,
            isMusicRunning: { true }
        )
        model.editor.isEditorTabActive = false
        return Fixture(model: model, monitor: monitor, signal: signal, music: music, positionPoll: positionPoll, suiteName: suiteName)
    }

    private let present: MockMusicClient.Response = .track(track, lyrics: "Lanterns over the river\nAsh in the wind", metadata: TrackMetadata(genre: "Black Metal", duration: 200))

    @Test func playbackEventsReachLyricsFX() async {
        let fixture = await makeFixture([present, .notPlaying])
        defer { fixture.tearDown() }
        fixture.model.startEventLoop()

        await fixture.monitor.tick()
        await waitUntil({ fixture.model.lyricsFX.identity != nil }, iterations: 2000)
        #expect(fixture.model.lyricsFX.timeline != nil)
        #expect(fixture.model.lyricsFX.genreStyle?.family == .frost)

        await fixture.monitor.tick()
        await waitUntil({ fixture.model.lyricsFX.identity == nil }, iterations: 2000)
        #expect(fixture.model.lyricsFX.statusText == StatusText.noTrackPlaying)
    }

    @Test func editorAndBatchWritesReachLyricsFX() async {
        let fixture = await makeFixture([present])
        defer { fixture.tearDown() }
        fixture.model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil({ fixture.model.lyricsFX.identity != nil }, iterations: 2000)

        fixture.model.editor.onSaved?(Self.track.persistentID, "Quiet harbor")
        #expect(fixture.model.lyricsFX.identity?.revision == 2)
        fixture.model.batch.onLyricsWritten?(Self.track.persistentID, "Paper boats at dawn")
        #expect(fixture.model.lyricsFX.identity?.revision == 3)
    }

    private func visibleWithOneRead(_ fixture: Fixture) async {
        fixture.model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil({ fixture.model.lyricsFX.identity != nil }, iterations: 2000)
        fixture.model.lyricsFX.setVisible(true)
        await waitFor { await fixture.music.playbackPositionCalls == 1 }
        await fixture.positionPoll.waitUntilPending(1)
    }

    @Test func aPlayerChangeAlsoResyncsThePositionClock() async {
        let fixture = await makeFixture([present])
        defer { fixture.tearDown() }
        await fixture.model.start()
        await visibleWithOneRead(fixture)

        fixture.signal.fire()
        await waitFor { await fixture.music.playbackPositionCalls == 2 }
        #expect(await fixture.music.playbackPositionCalls == 2)
    }

    /// 與 monitor 同一組 busy 來源（母計劃 §2.3 R2）：Editor 忙時不讀位置，閒下來補讀一次
    @Test func editorBusyPausesThePositionClock() async {
        let fixture = await makeFixture([present])
        defer { fixture.tearDown() }
        await fixture.model.start()
        await visibleWithOneRead(fixture)

        await fixture.model.editor.onBusyChange?(true)
        fixture.signal.fire()
        await settle()
        #expect(await fixture.music.playbackPositionCalls == 1)
        await fixture.model.editor.onBusyChange?(false)
        await waitFor { await fixture.music.playbackPositionCalls == 2 }
        #expect(await fixture.music.playbackPositionCalls == 2)
    }

    @Test func batchBusyPausesThePositionClock() async {
        let fixture = await makeFixture([present])
        defer { fixture.tearDown() }
        await visibleWithOneRead(fixture)

        await fixture.model.batch.onBusyChange?(true)
        fixture.model.lyricsFX.positionClock.resync()
        await settle()
        #expect(await fixture.music.playbackPositionCalls == 1)
        await fixture.model.batch.onBusyChange?(false)
        await waitFor { await fixture.music.playbackPositionCalls == 2 }
        #expect(await fixture.music.playbackPositionCalls == 2)
    }

    @Test func stopStopsThePositionClock() async {
        let fixture = await makeFixture([present])
        defer { fixture.tearDown() }
        await visibleWithOneRead(fixture)
        fixture.model.stop()
        await fixture.positionPoll.releaseAll()
        await settle()
        #expect(await fixture.music.playbackPositionCalls == 1)
    }

    @Test func markingNoLyricsReachesLyricsFX() async {
        let fixture = await makeFixture([.track(Self.track, lyrics: "", metadata: TrackMetadata(genre: "Black Metal", duration: 200))])
        defer { fixture.tearDown() }
        fixture.model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil({ fixture.model.lyricsFX.identity != nil }, iterations: 2000)
        #expect(fixture.model.lyricsFX.status == .missing)

        fixture.model.lyricsFlow.markNoLyrics(persistentID: Self.track.persistentID)

        #expect(fixture.model.lyricsFX.status == .markedNone)
    }

    // MARK: 升起層畫面偏好與可見性扇出（A2 計劃 §3.1）

    /// 播放有詞的歌 → 升起；回傳時已讀到當前曲
    private func raised(_ fixture: Fixture) async {
        fixture.model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil({ fixture.model.lyricsFX.identity != nil && fixture.model.lyricsFlow.surface == .coverFlow }, iterations: 2000)
    }

    /// 預設 Cover Flow：升起也不讀位置（改寫 A1 的「生產路徑不啟動時鐘」，I-10）
    @Test func theDefaultCoverFlowStyleNeverReadsThePosition() async {
        let fixture = await makeFixture([present])
        defer { fixture.tearDown() }
        await raised(fixture)
        await settle()
        #expect(fixture.model.raisedLayerStyle == .coverFlow)
        #expect(fixture.model.coverFlow.isVisible)
        #expect(!fixture.model.lyricsFX.isVisible)
        #expect(await fixture.music.playbackPositionCalls == 0)
    }

    @Test func choosingLyricsFXSwapsVisibilityAndStartsReading() async {
        let fixture = await makeFixture([present])
        defer { fixture.tearDown() }
        await raised(fixture)

        fixture.model.selectRaisedLayerStyle(.lyricsFX)

        #expect(fixture.model.raisedLayerStyle == .lyricsFX)
        #expect(!fixture.model.coverFlow.isVisible)
        #expect(fixture.model.lyricsFX.isVisible)
        await waitFor { await fixture.music.playbackPositionCalls == 1 }
        #expect(await fixture.music.playbackPositionCalls == 1)

        fixture.model.selectRaisedLayerStyle(.coverFlow)
        #expect(fixture.model.coverFlow.isVisible)
        #expect(!fixture.model.lyricsFX.isVisible)
        await fixture.positionPoll.releaseAll()
        await settle()
        #expect(await fixture.music.playbackPositionCalls == 1, "切回 Cover Flow 就停讀")
    }

    @Test func leavingTheEditorTabHidesLyricsFX() async {
        let fixture = await makeFixture([present])
        defer { fixture.tearDown() }
        await raised(fixture)
        fixture.model.selectRaisedLayerStyle(.lyricsFX)
        #expect(fixture.model.lyricsFX.isVisible)

        fixture.model.select(.batch)
        #expect(!fixture.model.lyricsFX.isVisible)
        #expect(!fixture.model.coverFlow.isVisible)
        fixture.model.select(.editor)
        #expect(fixture.model.lyricsFX.isVisible)
    }

    @Test func loweringHidesLyricsFX() async {
        let fixture = await makeFixture([present])
        defer { fixture.tearDown() }
        await raised(fixture)
        fixture.model.selectRaisedLayerStyle(.lyricsFX)
        #expect(fixture.model.lyricsFX.isVisible)

        fixture.model.lyricsFlow.toggleHandle()

        #expect(fixture.model.lyricsFlow.surface != .coverFlow)
        #expect(!fixture.model.lyricsFX.isVisible)
        #expect(!fixture.model.coverFlow.isVisible)
    }

    @Test func theChoiceIsSavedAndReadBackOnTheNextLaunch() async {
        let suiteName = "AppModelLyricsFXTests-\(UUID().uuidString)"
        let first = await makeFixture([present], suiteName: suiteName)
        first.model.selectRaisedLayerStyle(.lyricsFX)
        first.model.stop()

        let second = await makeFixture([present], suiteName: suiteName)
        defer { second.tearDown() }
        #expect(second.model.raisedLayerStyle == .lyricsFX)
    }

    @Test func aStoredLyricsFXStyleIsUsedOnceRaised() async {
        let fixture = await makeFixture([present]) { $0.setRaisedLayerStyle(.lyricsFX) }
        defer { fixture.tearDown() }
        await raised(fixture)
        #expect(fixture.model.lyricsFX.isVisible)
        #expect(!fixture.model.coverFlow.isVisible)
    }
}
