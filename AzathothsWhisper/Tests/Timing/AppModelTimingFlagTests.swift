import CryptoKit
import Foundation
import Testing

@testable import AzathothsWhisper

// ⑪ 計劃 §4.2–§4.3、驗收 2／3：AppModel 把「不準」標記接到存檔；不改時間軸存檔、不觸發查找；檔內不留曲名歌詞。歌詞為編造句
@MainActor
@Suite("AppModel timing flag")
struct AppModelTimingFlagTests {
    private struct AlwaysValidValidator: TokenValidating {
        func validate(token: String) async -> TokenValidation { .valid }
    }

    static let track = TrackInfo.fixture(id: "0123456789ABCDEF")
    static let lyrics = "Lanterns over the river\nAsh in the wind"
    static let anchors: [TimingRecord.LineStart] = [.init(index: 0, start: 5), .init(index: 1, start: 9)]
    static let key = TimingFlagKey(persistentID: track.persistentID, lyricsHash: .of(lyrics))

    @MainActor
    private struct Fixture {
        let model: AppModel
        let monitor: NowPlayingMonitor
        let timing: SpyTimingResolver
        let timingStore: TimingStore
        let timingDirectory: URL
        let flagDirectory: URL
        let suiteName: String

        func tearDown() {
            model.stop()
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeFixture(seedStore: Bool, withFlagStore: Bool = true) async throws -> Fixture {
        let suiteName = "AppModelTimingFlagTests-\(UUID().uuidString)"
        let store = ConfigStore(secrets: EphemeralSecretStore(), defaults: UserDefaults(suiteName: suiteName)!)
        store.setNotificationsEnabled(false)
        let music = MockMusicClient(
            script: [.track(Self.track, lyrics: Self.lyrics, metadata: TrackMetadata(genre: "Black Metal", duration: 200))], repeatLast: true
        )
        await music.setPlaybackPositions([.success(PlaybackPosition(persistentID: Self.track.persistentID, seconds: 42, state: .playing, readAt: .now, roundTrip: .zero))])
        let monitor = NowPlayingMonitor(music: music, clock: GatedPollClock())
        let timing = SpyTimingResolver([.found(.lrclib, Self.anchors)])
        let timingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("azw-flag-timings-\(UUID().uuidString)")
        let flagDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("azw-flag-flags-\(UUID().uuidString)")
        let timingStore = TimingStore(directory: timingDirectory)
        if seedStore {
            try await timingStore.save(TimingRecord(
                persistentID: Self.track.persistentID, lyricsHash: .of(Self.lyrics), outcome: .found(source: .lrclib, lines: Self.anchors),
                fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), alignerRevision: 3
            ))
        }
        let model = AppModel(
            configStore: store, httpClient: MockHTTPClient(), music: music, monitor: monitor, validator: AlwaysValidValidator(),
            notifier: SpyLyricsNotifier(), playerSignal: SpyPlayerChangeSignal(), initialToken: "", initialLanguage: .system,
            artistStylesStartDelay: .milliseconds(1), lyricsFlowClock: GatedPollClock(), positionPollClock: GatedPollClock(),
            isMusicRunning: { true }, timing: timing, timingStore: timingStore,
            timingFlags: withFlagStore ? TimingFlagStore(directory: flagDirectory) : nil
        )
        model.editor.isEditorTabActive = false
        return Fixture(
            model: model, monitor: monitor, timing: timing, timingStore: timingStore,
            timingDirectory: timingDirectory, flagDirectory: flagDirectory, suiteName: suiteName
        )
    }

    private func playingWithFoundTiming(_ fixture: Fixture) async {
        fixture.model.startEventLoop()
        await fixture.monitor.tick()
        await waitUntil({ fixture.model.lyricsFX.identity != nil }, iterations: 2000)
        fixture.model.lyricsFX.setVisible(true)
        await waitUntil({ fixture.model.lyricsFX.timeline?.source == .lrclib }, iterations: 2000)
        await waitUntil({ fixture.model.lyricsFX.positionClock.anchor != nil }, iterations: 2000)
    }

    private func digests(_ directory: URL) -> [String: String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Dictionary(uniqueKeysWithValues: names.compactMap { name in
            (try? Data(contentsOf: directory.appendingPathComponent(name))).map { (name, SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()) }
        })
    }

    @Test func flaggingRecordsTheScreenAndTheMatchingStoredRecord() async throws {
        let fixture = try await makeFixture(seedStore: true)
        defer { fixture.tearDown() }
        await playingWithFoundTiming(fixture)
        let timingsBefore = digests(fixture.timingDirectory)
        let lookupsBefore = await fixture.timing.calls.count

        fixture.model.lyricsFX.toggleTimingFlag()
        await waitUntil({ fixture.model.lyricsFX.timingFlag == .flagged }, iterations: 2000)

        let flags = try await TimingFlagStore(directory: fixture.flagDirectory).all()
        let flag = try #require(flags.first)
        #expect(flags.count == 1)
        #expect(flag.key == Self.key)
        #expect(flag.applied == AppliedTiming(source: .lrclib, anchors: Self.anchors))
        #expect(flag.provenance == .matched)
        #expect(flag.stored?.source == .lrclib)
        #expect(flag.stored?.alignerRevision == 3)
        #expect(flag.positions.count == 1)
        #expect(abs((flag.positions.first ?? 0) - 42) < 0.15)
        // 驗收 2：時間軸存檔逐位不變、沒有觸發查找
        #expect(digests(fixture.timingDirectory) == timingsBefore)
        #expect(await fixture.timing.calls.count == lookupsBefore)
    }

    @Test func aScreenWithoutAStoredRecordIsStillFlaggedAsStoreMissing() async throws {
        let fixture = try await makeFixture(seedStore: false)
        defer { fixture.tearDown() }
        await playingWithFoundTiming(fixture)
        fixture.model.lyricsFX.toggleTimingFlag()
        await waitUntil({ fixture.model.lyricsFX.timingFlag == .flagged }, iterations: 2000)
        let flag = try #require(try await TimingFlagStore(directory: fixture.flagDirectory).all().first)
        #expect(flag.provenance == .storeMissing)
        #expect(flag.stored == nil)
        #expect(flag.applied.anchors == Self.anchors)
    }

    @Test func unflaggingRemovesTheFlag() async throws {
        let fixture = try await makeFixture(seedStore: true)
        defer { fixture.tearDown() }
        await playingWithFoundTiming(fixture)
        fixture.model.lyricsFX.toggleTimingFlag()
        await waitUntil({ fixture.model.lyricsFX.timingFlag == .flagged }, iterations: 2000)
        fixture.model.lyricsFX.toggleTimingFlag()
        await waitUntil({ fixture.model.lyricsFX.timingFlag == .unflagged }, iterations: 2000)
        #expect(try await TimingFlagStore(directory: fixture.flagDirectory).all().isEmpty)
    }

    @Test func theFlagFileHoldsNoTitleArtistOrLyrics() async throws {
        let fixture = try await makeFixture(seedStore: true)
        defer { fixture.tearDown() }
        await playingWithFoundTiming(fixture)
        fixture.model.lyricsFX.toggleTimingFlag()
        await waitUntil({ fixture.model.lyricsFX.timingFlag == .flagged }, iterations: 2000)
        let text = try String(contentsOf: fixture.flagDirectory.appendingPathComponent(TimingFlagStore.fileName), encoding: .utf8)
        for forbidden in [Self.track.title, Self.track.artist, "Lanterns", "Ash in the wind"] where !forbidden.isEmpty {
            #expect(!text.contains(forbidden), "flag file contains \(forbidden)")
        }
    }

    @Test func aFlagStoredEarlierShowsWhenTheSongPlaysAgain() async throws {
        let fixture = try await makeFixture(seedStore: true)
        defer { fixture.tearDown() }
        try await TimingFlagStore(directory: fixture.flagDirectory).flag(TimingFlag(
            persistentID: Self.track.persistentID, lyricsHash: .of(Self.lyrics), markedAt: .now, positions: [1],
            applied: AppliedTiming(source: .lrclib, anchors: Self.anchors), stored: nil, provenance: .storeMissing
        ))
        await playingWithFoundTiming(fixture)
        await waitUntil({ fixture.model.lyricsFX.timingFlag == .flagged }, iterations: 2000)
        #expect(fixture.model.lyricsFX.timingMark == .flagged)
    }

    @Test func withoutAFlagStoreTheMenuIsNotOffered() async throws {
        let fixture = try await makeFixture(seedStore: true, withFlagStore: false)
        defer { fixture.tearDown() }
        await playingWithFoundTiming(fixture)
        #expect(!fixture.model.lyricsFX.canToggleTimingFlag)
    }
}
