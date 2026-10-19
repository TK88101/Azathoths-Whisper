import Foundation
import Testing

@testable import AzathothsWhisper

/// 退路鏈的替身：記錄每個請求；回應由測試腳本決定，可掛住到放行
actor SpyTimingResolver: TimingResolving {
    struct Call: Equatable, Sendable {
        let request: TimingRequest
        let priority: TimingPriority
    }

    private(set) var calls: [Call] = []
    private(set) var didShutDown = false
    private var outcomes: [TimingResolution.Outcome]
    private let holdFirst: Bool
    private var held: [CheckedContinuation<Void, Never>] = []

    init(_ outcomes: [TimingResolution.Outcome], holdFirst: Bool = false) {
        self.outcomes = outcomes
        self.holdFirst = holdFirst
    }

    func resolve(_ request: TimingRequest, priority: TimingPriority) async -> TimingResolution {
        calls.append(Call(request: request, priority: priority))
        let outcome = outcomes.isEmpty ? .notFound : outcomes.removeFirst()
        if holdFirst, calls.count == 1 { await withCheckedContinuation { held.append($0) } }
        return TimingResolution(persistentID: request.persistentID, lyricsHash: .of(request.lyrics), outcome: outcome)
    }

    var storedNotFoundAnswer = false

    func storedNotFound(persistentID: String, lyricsHash: LyricsFingerprint) async -> Bool {
        storedNotFoundAnswer
    }

    func release() {
        held.forEach { $0.resume() }
        held = []
    }

    func shutdown() {
        didShutDown = true
    }
}

// C 段計劃 §3.8：寫入成功後（Editor、Batch）背景補做；特效層顯示時以 visible 補做並熱替換；舊結果不套用。歌詞為編造句
@MainActor
@Suite("AppModel timing")
struct AppModelTimingTests {
    private struct AlwaysValidValidator: TokenValidating {
        func validate(token: String) async -> TokenValidation { .valid }
    }

    static let track = TrackInfo.fixture(id: "0123456789ABCDEF")
    static let lyrics = "Lanterns over the river\nAsh in the wind"

    @MainActor
    private struct Fixture {
        let model: AppModel
        let monitor: NowPlayingMonitor
        let timing: SpyTimingResolver
        let suiteName: String

        func tearDown() {
            model.stop()
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeFixture(_ timing: SpyTimingResolver) async -> Fixture {
        let suiteName = "AppModelTimingTests-\(UUID().uuidString)"
        let store = ConfigStore(secrets: EphemeralSecretStore(), defaults: UserDefaults(suiteName: suiteName)!)
        store.setNotificationsEnabled(false)
        let music = MockMusicClient(
            script: [.track(Self.track, lyrics: Self.lyrics, metadata: TrackMetadata(genre: "Black Metal", duration: 200))], repeatLast: true
        )
        await music.setPlaybackPositions([.success(PlaybackPosition(persistentID: Self.track.persistentID, seconds: 1, state: .playing, readAt: .now, roundTrip: .zero))])
        let monitor = NowPlayingMonitor(music: music, clock: GatedPollClock())
        let model = AppModel(
            configStore: store, httpClient: MockHTTPClient(), music: music, monitor: monitor, validator: AlwaysValidValidator(),
            notifier: SpyLyricsNotifier(), playerSignal: SpyPlayerChangeSignal(), initialToken: "", initialLanguage: .system,
            splashDuration: .milliseconds(1), lyricsFlowClock: GatedPollClock(), positionPollClock: GatedPollClock(),
            isMusicRunning: { true }, timing: timing
        )
        model.editor.isEditorTabActive = false
        return Fixture(model: model, monitor: monitor, timing: timing, suiteName: suiteName)
    }

    private func playing(_ fixture: Fixture) async {
        fixture.model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil({ fixture.model.lyricsFX.identity != nil }, iterations: 2000)
    }

    @Test func anEditorWriteLooksUpTimingInTheBackground() async {
        let fixture = await makeFixture(SpyTimingResolver([]))
        defer { fixture.tearDown() }
        fixture.model.editor.onSaved?("AAAAAAAAAAAAAAAA", "Quiet harbor")
        await waitFor { await fixture.timing.calls.count == 1 }
        #expect(await fixture.timing.calls == [.init(request: TimingRequest(persistentID: "AAAAAAAAAAAAAAAA", lyrics: "Quiet harbor", query: nil), priority: .background)])
    }

    @Test func aBatchWriteLooksUpTimingInTheBackground() async {
        let fixture = await makeFixture(SpyTimingResolver([]))
        defer { fixture.tearDown() }
        fixture.model.batch.onLyricsWritten?("BBBBBBBBBBBBBBBB", "Paper boats at dawn")
        await waitFor { await fixture.timing.calls.count == 1 }
        #expect(await fixture.timing.calls.first?.priority == .background)
    }

    @Test func nothingIsAskedWhileLyricsFXIsHidden() async {
        let fixture = await makeFixture(SpyTimingResolver([]))
        defer { fixture.tearDown() }
        await playing(fixture)
        await settle()
        #expect(await fixture.timing.calls.isEmpty)
    }

    @Test func showingLyricsFXLooksUpTheCurrentSongAndSwapsInTheFoundTiming() async {
        let fixture = await makeFixture(SpyTimingResolver([.found(.lrclib, [.init(index: 0, start: 5), .init(index: 1, start: 9)])]))
        defer { fixture.tearDown() }
        await playing(fixture)
        #expect(fixture.model.lyricsFX.timeline?.source == .estimated)

        fixture.model.lyricsFX.setVisible(true)
        await waitUntil({ fixture.model.lyricsFX.timeline?.source == .lrclib }, iterations: 2000)
        #expect(fixture.model.lyricsFX.timeline?.lines.map(\.start) == [5, 9])
        let call = await fixture.timing.calls.first
        #expect(call?.priority == .visible)
        #expect(call?.request.query == TimingQuery(artist: Self.track.artist, title: Self.track.title, duration: 200))
    }

    @Test func aResultForLyricsThatHaveSinceChangedIsNotApplied() async {
        let timing = SpyTimingResolver([.found(.lrclib, [.init(index: 0, start: 5), .init(index: 1, start: 9)]), .notFound], holdFirst: true)
        let fixture = await makeFixture(timing)
        defer { fixture.tearDown() }
        await playing(fixture)
        fixture.model.lyricsFX.setVisible(true)
        await waitFor { await timing.calls.count == 1 }

        // 同曲改詞（Music 端事件）。不用 editor.onSaved：寫入後的強制重讀會從 MockMusic 讀回舊詞（替身寫入不影響讀取）
        fixture.model.lyricsFX.lyricsUpdated(persistentID: Self.track.persistentID, text: "Quiet harbor\nSalt on the glass")
        await waitFor { await timing.calls.count >= 2 }
        await timing.release()
        await settle()
        #expect(fixture.model.lyricsFX.timeline?.source == .estimated)
        #expect(fixture.model.lyricsFX.timeline?.lines.map(\.text) == ["Quiet harbor", "Salt on the glass"])
    }

    @Test func aBackgroundNotFoundReachesCoverFlow() async {
        let fixture = await makeFixture(SpyTimingResolver([.notFound]))
        defer { fixture.tearDown() }
        let pid = "AAAAAAAAAAAAAAAA"
        fixture.model.coverFlow.updateDetails([pid: TrackDetails(
            persistentID: pid, artist: "A", title: "T", album: "B", discNumber: 1, trackNumber: 1, lyrics: "Quiet harbor", genre: nil, duration: 200
        )])
        fixture.model.editor.onSaved?(pid, "Quiet harbor")
        await waitUntil({ fixture.model.coverFlow.timingNotFound.contains(pid) }, iterations: 2000)
        #expect(fixture.model.coverFlow.timingNotFound == [pid])
    }

    @Test func stoppingShutsTheLookupDown() async {
        let fixture = await makeFixture(SpyTimingResolver([]))
        fixture.tearDown()
        await waitFor { await fixture.timing.didShutDown }
        #expect(await fixture.timing.didShutDown)
    }
}
