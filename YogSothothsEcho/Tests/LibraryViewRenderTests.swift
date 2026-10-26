import Foundation
import RemoteProtocol
import RemoteTransport
import SwiftUI
import Testing
@testable import YogSothothsEcho

// S3 T11／T15：曲庫畫面、Shell、DEBUG 量測面板在各狀態都算得出畫面；量測試次寫出 JSON；換版事件轉換。
// 只驗「算得出、不是空的」；狀態邏輯由 LibraryViewModelTests、流程由 LibraryUITests 驗
@MainActor
struct LibraryViewRenderTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("render-\(UUID().uuidString)")

    func model() -> LibraryViewModel { LibraryViewModel(artworkDirectory: directory, sleep: { _ in await Task.yield() }) }

    func expectRenders(_ view: some View, _ label: String) {
        let image = ImageRenderer(content: view.frame(width: 1180, height: 820)).uiImage
        #expect(image != nil && image!.size.width > 0, "\(label) 畫不出來")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func libraryStatesRender() async {
        let m = model()
        expectRenders(LibraryView(model: m), "idle")
        let client = ScriptedEchoClient(total: 30)
        m.attach(client)
        expectRenders(LibraryView(model: m), "loading")
        #expect(await waitUntil { m.phase == .ready })
        expectRenders(LibraryView(model: m), "ready")
        m.detach()
        expectRenders(LibraryView(model: m), "disconnected")
    }

    @Test func failureStatesRender() async {
        let unavailable = ScriptedEchoClient(total: 3)
        unavailable.lock.withLock { unavailable.failure = .remote(.libraryUnavailable) }
        let m = model()
        m.attach(unavailable)
        #expect(await waitUntil { m.phase == .failed(.libraryUnavailable) })
        expectRenders(LibraryView(model: m), "libraryUnavailable")

        let broken = ScriptedEchoClient(total: 3)
        broken.lock.withLock { broken.failure = .timeout }
        let n = model()
        n.attach(broken)
        #expect(await waitUntil { n.phase == .failed(.network) })
        expectRenders(LibraryView(model: n), "network")

        let unstable = ScriptedEchoClient(total: 250)
        unstable.lock.withLock { unstable.bumpVersionOnCall = Dictionary(uniqueKeysWithValues: (1...20).map { ($0, String(format: "%016llx", UInt64($0))) }) }
        let u = model()
        u.attach(unstable)
        #expect(await waitUntil { u.phase == .failed(.catalogUnstable) })
        expectRenders(LibraryView(model: u), "unstable")
    }

    /// S6 T3：單一方盒（有封面 token／沒有）在中央、兩側都畫得出
    @Test func spineBoxRendersWithAndWithoutArtwork() {
        let m = model()
        let metrics = SpineCarouselTests.pro13
        let plain = AlbumSummary(id: "0000000000000001", title: "Album 1", artist: "Artist", trackCount: 1, artworkToken: nil)
        let withToken = AlbumSummary(id: "0000000000000002", title: "Album 2", artist: "Artist", trackCount: 1, artworkToken: "00000000000000aa")
        for u: CGFloat in [-2, 0, 1.5] {
            let pose = SpineCarousel.pose(u: u, metrics: metrics)
            expectRenders(SpineBoxView(album: plain, model: m, pose: pose, metrics: metrics), "box \(u)")
            expectRenders(SpineBoxView(album: withToken, model: m, pose: pose, metrics: metrics), "box with token \(u)")
        }
    }

    /// S6 T3：側封瀏覽在 0／1／多張／1,000 張時都畫得出（1,000 張不崩、只畫可見盒）
    @Test func browserRendersAtEveryCount() async {
        for total in [0, 1, 30, 1000] {
            let m = model()
            if total > 0 {
                m.attach(ScriptedEchoClient(total: total))
                #expect(await waitUntil { m.phase == .ready && m.albums.count == total })
            }
            expectRenders(AlbumBrowserView(model: m), "browser \(total)")
            expectRenders(LibraryView(model: m), "library \(total)")
        }
    }

    private func turntable(_ nowPlaying: NowPlayingViewModel = NowPlayingViewModel()) -> TurntableViewModel {
        TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: InMemorySettingsStore(), displayScale: 2, artwork: { _ in nil },
                           palette: { _ in .fallback })
    }

    /// S5 T9：唱機畫面在沒有目前曲、有目前曲（各樣式）時都能畫出（素材有無皆可；測試主機用本機素材或後備圖形）
    @Test func turntableRenders() async {
        let empty = turntable()
        expectRenders(TurntableView(model: empty, onClose: {}), "turntable empty")
        let nowPlaying = NowPlayingViewModel()
        let client = FakePlaybackClient()
        nowPlaying.attach(client)
        client.push(PlaybackSamples.event(PlaybackSamples.t1, .playing, at: 1))
        await settle()
        let model = turntable(nowPlaying)
        for style in RecordStyle.allCases {
            model.recordStyle = style
            expectRenders(TurntableView(model: model, onClose: {}), "turntable \(style.rawValue)")
        }
    }

    @Test func shellRendersConnectionAndLibraryLayouts() async {
        let connector = FakeConnector()
        connector.paired = true
        connector.connectResults = [.success(FakeSession())]
        let connection = ConnectionViewModel(connector: connector, camera: FakeCamera(), deviceName: "iPad",
                                             sleep: { _ in await Task.yield() }, jitter: { 1 })
        let library = model()
        let appearance = AppearanceViewModel(store: InMemorySettingsStore())
        expectRenders(ShellView(appearance: appearance, background: BackgroundViewModel(store: InMemorySettingsStore()),
                                detailBackground: DetailBackgroundController(),
                                browseLayout: BrowseLayoutViewModel(store: InMemorySettingsStore()), connection: connection, library: library, nowPlaying: NowPlayingViewModel(),
                                albumTracks: AlbumTracksViewModel(), albumOpen: openController(), turntable: turntable(), fakePayload: nil), "shell suspended")
        await connection.start()
        await settle()
        expectRenders(ShellView(appearance: appearance, background: BackgroundViewModel(store: InMemorySettingsStore()),
                                detailBackground: DetailBackgroundController(),
                                browseLayout: BrowseLayoutViewModel(store: InMemorySettingsStore()), connection: connection, library: library, nowPlaying: NowPlayingViewModel(),
                                albumTracks: AlbumTracksViewModel(), albumOpen: openController(), turntable: turntable(), fakePayload: nil), "shell connected")
        #expect(ShellPresentation.showsLibrary(state: .retrying(inSeconds: 3), hasAlbums: true))
        #expect(!ShellPresentation.showsLibrary(state: .retrying(inSeconds: 3), hasAlbums: false))
        #expect(!ShellPresentation.showsLibrary(state: .pairing, hasAlbums: true))
        connection.suspend()
    }

    /// S4 T11：播放列與曲目清單在各狀態都畫得出來（未連線、有曲目、提示中、清單載入失敗、清單可點）
    @Test func playbackViewsRenderInEachState() async {
        let nowPlaying = NowPlayingViewModel()
        expectRenders(BottomDock(model: nowPlaying), "dock disconnected")
        let client = SyntheticPlaybackClient(arguments: [AccessibilityID.playDegradedArgument])
        nowPlaying.attach(client)
        await settle()
        expectRenders(BottomDock(model: nowPlaying), "dock playing")
        // CR-031：小膠囊（沒有目前曲）含 Genius（可按／未授權）；舊 Mac＝兩欄
        for extra in [[], [AccessibilityID.geniusNeedsAccessibilityArgument], [AccessibilityID.geniusLegacyMacArgument]] {
            let idle = NowPlayingViewModel()
            idle.attach(SyntheticPlaybackClient(arguments: extra))
            await settle()
            #expect(idle.currentTrackID == nil)
            expectRenders(BottomDock(model: idle, layout: .spines), "idle dock genius \(extra)")
        }
        // CR-030：寬膠囊含 Genius（可按／未授權）
        for extra in [[], [AccessibilityID.geniusNeedsAccessibilityArgument], [AccessibilityID.geniusLegacyMacArgument]] {
            let wide = NowPlayingViewModel()
            wide.attach(SyntheticPlaybackClient(arguments: [AccessibilityID.nowPlayingArgument] + extra))
            await settle()
            #expect(wide.currentTrackID != nil)
            expectRenders(BottomDock(model: wide), "dock genius \(extra)")
        }
        let tracks = AlbumTracksViewModel()
        tracks.attach(client)
        let album = AlbumSummary(id: "0000000000000001", title: "Album 1", artist: "Artist", trackCount: 10, artworkToken: nil)
        let opener = openController()
        expectRenders(AlbumDetailView(controller: opener, model: tracks, currentTrackID: nil, background: DetailBackgroundController(),
                                      backgroundSettings: BackgroundViewModel(store: InMemorySettingsStore())), "detail closed")
        opener.open(album, from: SpineCarousel.pose(u: 1, metrics: SpineCarouselTests.pro13), metrics: SpineCarouselTests.pro13, origin: .zero)
        expectRenders(AlbumDetailView(controller: opener, model: tracks, currentTrackID: nil, background: DetailBackgroundController(),
                                      backgroundSettings: BackgroundViewModel(store: InMemorySettingsStore())), "detail opening")
        expectRenders(AlbumStageView(controller: opener), "stage opening")
        await tracks.open(album)
        await tracks.play(tracks.songs[2])
        #expect(tracks.notice == .playedOnlyThis(.missingShortcut))
        expectRenders(AlbumDetailView(controller: opener, model: tracks, currentTrackID: tracks.songs[2].id, background: DetailBackgroundController(),
                                      backgroundSettings: BackgroundViewModel(store: InMemorySettingsStore())), "detail with notice")
        let failing = AlbumTracksViewModel()
        failing.attach(FakePlaybackClient())
        await failing.open(AlbumSummary(id: "00000000000000ee", title: "Missing", artist: "Artist", trackCount: 1, artworkToken: nil))
        expectRenders(AlbumDetailView(controller: opener, model: failing, currentTrackID: nil, background: DetailBackgroundController(),
                                      backgroundSettings: BackgroundViewModel(store: InMemorySettingsStore())), "detail failed")
    }

    private func openController() -> AlbumOpenController {
        AlbumOpenController(now: { 0 }, sleep: { _ in await Task.yield() }, spineCover: { _ in nil }, detailCover: { _ in nil })
    }

    @Test func debugOverlayRenders() {
        expectRenders(LibraryDebugOverlay(model: model()), "debug overlay")
    }

    @Test func placeholderColorIsStablePerID() {
        #expect(LibraryPresentation.placeholderColor(for: "00000000000000ff") == LibraryPresentation.placeholderColor(for: "00000000000000ff"))
    }
}

@MainActor
struct FrameRateMonitorTests {
    private var metricsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("metrics", isDirectory: true)
    }

    @Test func trialCountsFlicksAndWritesJSON() async throws {
        let monitor = FrameRateMonitor()
        // 檔名只到秒（`scroll-1-<秒>.json`）：同一秒內重跑會覆蓋舊檔，數量不增（-test-iterations 壓測時 8／10 假紅）→ 改看本次寫出的修改時間
        let started = Date().addingTimeInterval(-0.001)
        monitor.begin(layout: .spines)
        #expect(monitor.isRecording && monitor.trialID == 1)
        for _ in 0..<10 { monitor.flicked() }
        monitor.scrolled(to: 4200, axis: .x)
        try await Task.sleep(for: .milliseconds(200))
        monitor.end()
        #expect(!monitor.isRecording && monitor.flickCount == 10 && monitor.lastResult != nil)
        monitor.recordFirstScreen(seconds: 0.9, cells: 15)
        let written = try FileManager.default.contentsOfDirectory(at: metricsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("scroll-1-") && $0.pathExtension == "json" }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        #expect(written.contains { $0 >= started })
        monitor.flicked()
        #expect(monitor.flickCount == 10)                 // 沒在錄就不計
    }
}

struct CatalogVersionStreamTests {
    @Test func onlyCatalogChangedEventsBecomeVersions() async {
        let (events, continuation) = AsyncStream<InboundEvent>.makeStream()
        let versions = EventFanout(events).catalogVersions
        continuation.yield(InboundEvent(kind: .eventPlayback, message: Envelope.encode(.eventPlayback, CatalogChangedEvent(version: "00000000000000aa"))))
        continuation.yield(InboundEvent(kind: .eventCatalogChanged, message: Data("{}".utf8)))
        continuation.yield(InboundEvent(kind: .eventCatalogChanged, message: Envelope.encode(.eventCatalogChanged, CatalogChangedEvent(version: "00000000000000bb"))))
        continuation.finish()
        var collected: [String] = []
        for await version in versions { collected.append(version) }
        #expect(collected == ["00000000000000bb"])
    }
}
