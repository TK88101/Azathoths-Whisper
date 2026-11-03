import AppKit
import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.5「單一採用入口」、§6.6、T7／§8-2、§8-9：開啟後匯出、他機資料不重啟即生效、關閉後不讀寫、重設只刪自己。
// 一律在臨時目錄、假硬體身分；不碰使用者的 iCloud
@MainActor
@Suite("AppModel cloud sync")
struct AppModelCloudSyncTests {
    nonisolated static let other = "000000000000000b"
    nonisolated static let wall = Date(timeIntervalSince1970: 1_790_000_000)

    struct FixedHardware: HardwareIdentity {
        func platformUUID() throws(SyncWriterID.Failure) -> String { "6F1C2E1A-0000-4000-8000-0000000000AA" }
    }

    struct NoHardware: HardwareIdentity {
        func platformUUID() throws(SyncWriterID.Failure) -> String { throw .unavailable }
    }

    /// 時間由測試推進；sleep 卡在閘上（run 迴圈不空轉）
    final class TestSyncClock: MonotonicClock, PollClock, @unchecked Sendable {
        let gate = GatedPollClock()
        private let lock = NSLock()
        private var current: TimeInterval = 1_000
        var now: TimeInterval { lock.withLock { current } }
        func advance(by seconds: TimeInterval) { lock.withLock { current += seconds } }
        func sleep(for interval: Duration) async throws { try await gate.sleep(for: interval) }
    }

    struct AlwaysValidValidator: TokenValidating {
        func validate(token: String) async -> TokenValidation { .valid }
    }

    struct NeverDeadline: PollClock {
        func sleep(for interval: Duration) async throws { try await Task.sleep(for: .seconds(86_400)) }
    }

    struct Fixture {
        let model: AppModel
        let root: URL
        let clock: TestSyncClock
        let defaults: UserDefaults
        let suiteName: String
        let timingStore: TimingStore
        let me: String
        let base: URL

        var ownFolder: URL { root.appendingPathComponent("Sync/\(me)") }

        /// 啟動做完＝第一份狀態發布、且 run 迴圈已停在時鐘閘上（最多等 5 秒實際時間）
        @MainActor func waitUntilStarted() async {
            for _ in 0..<500 where model.cloudSyncStatus == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
            await clock.gate.waitUntilPending(1)
        }

        @MainActor func cleanUp() {
            model.stop()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: base)
        }
    }

    private func fixture(hardware: any HardwareIdentity = FixedHardware(), enabled: Bool = false) async throws -> Fixture {
        let suiteName = "AppModelCloudSyncTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(enabled, forKey: ConfigStore.Key.cloudSyncEnabled)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("azw-appmodel-sync-\(UUID().uuidString)")
        // iCloud Drive 本身（`iCloud/` 的上層）要先在
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let clock = TestSyncClock()
        let music = MockMusicClient(script: [.notPlaying], repeatLast: true)
        let artistStore = ArtistStyleStore(directory: root.appendingPathComponent("local/ArtistStyles"))
        let timingStore = TimingStore(directory: root.appendingPathComponent("local/Timings"))
        let environment = CloudSyncEnvironment(
            root: root.appendingPathComponent("iCloud"), hardware: hardware, lockURL: nil, downloads: UbiquitousDownloadProbe(),
            clock: clock, readDeadline: NeverDeadline(), wallClock: { Self.wall }, appVersion: "3.1.0"
        )
        let model = AppModel(
            configStore: ConfigStore(secrets: EphemeralSecretStore(), defaults: defaults),
            httpClient: MockHTTPClient(), music: music, monitor: NowPlayingMonitor(music: music, clock: GatedPollClock()),
            validator: AlwaysValidValidator(), notifier: SpyLyricsNotifier(), playerSignal: SpyPlayerChangeSignal(),
            initialToken: "", initialLanguage: .system, artistStylesClock: GatedPollClock(), lyricsFlowClock: GatedPollClock(),
            positionPollClock: GatedPollClock(), isMusicRunning: { true },
            artistStyles: { publish in
                ArtistStyleSync(music: music, store: artistStore, identify: { _, _ throws(ProviderFailure) in .unresolved(.notFound) }, publish: publish)
            },
            artistDecisions: ArtistDecisionStore(directory: root.appendingPathComponent("local/ArtistDecisions")),
            cloudSync: environment, timingStore: timingStore, remoteTimingIndex: RemoteTimingIndex()
        )
        let me = (try? SyncWriterID.current(from: hardware)) ?? ""
        return Fixture(model: model, root: environment.root, clock: clock, defaults: defaults, suiteName: suiteName, timingStore: timingStore, me: me,
                       base: root)
    }

    /// 他機資料夾的 fixture：本機沒有的歌手、時間軸、決定、標記
    private func writeOtherMac(_ root: URL) throws {
        let folder = SyncFolder(root: root, writerID: Self.other, appVersion: "3.1.0", downloads: UbiquitousDownloadProbe())
        let decision = SyncRegister(value: ArtistDecisionPayload(choice: .keepFallback, decidedAt: Self.wall, spellings: ["Paper Harbour"]),
                                    version: SyncVersion(revision: 1, origin: Self.other))
        try folder.write([ArtistDecisionBook.key("Paper Harbour"): decision] as SyncPayload.Decisions, kind: .decisions, at: Self.wall)
        try folder.write(["AAAA000000000001": SyncRegister(value: true, version: SyncVersion(revision: 1, origin: Self.other))] as SyncPayload.NoLyrics,
                         kind: .nolyrics, at: Self.wall)
        let artist = ArtistStyleBook.Record(spellings: ["Velvet Lanterns"], mbid: "33333333-3333-4333-8333-333333333333", matchedReleaseGroups: [],
                                            genres: [.init(name: "doom metal", count: 2)], reason: nil, fetchedAt: Self.wall, origin: Self.other)
        try folder.write([ArtistStyleBook.key("Velvet Lanterns"): artist] as SyncPayload.Artists, kind: .artists, at: Self.wall)
        let timing = TimingRecord(persistentID: "AAAA000000000002", lyricsHash: LyricsFingerprint.of("an invented line"),
                                  outcome: .found(source: .lrclib, lines: [.init(index: 0, start: 3)]), fetchedAt: Self.wall,
                                  origin: Self.other, sourceRef: "\(Self.other):AAAA000000000002")
        try folder.write(SyncPayload.canonicalTimings([timing]), kind: .timings, at: Self.wall)
    }

    @Test func syncIsOffByDefaultAndTouchesNothing() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.model.cloudSyncEnabled == false)
        fixture.model.startCloudSyncIfEnabled()
        #expect(fixture.model.cloudSync == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.root.path) == false, "關閉＝不讀不寫")
    }

    @Test func turningItOnExportsAllFourKinds() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanUp() }
        fixture.model.setCloudSyncEnabled(true)
        await fixture.waitUntilStarted()
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.ownFolder.path).sorted()
        #expect(names == ["artists.json", "decisions.json", "nolyrics.json", "timings.json"])
        #expect(fixture.defaults.bool(forKey: ConfigStore.Key.cloudSyncEnabled))
        #expect(fixture.model.cloudSyncStatus?.lastExport == Self.wall)
    }

    @Test func otherMacDataTakesEffectWithoutARestart() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanUp() }
        try writeOtherMac(fixture.root)
        fixture.model.setCloudSyncEnabled(true)
        await fixture.waitUntilStarted()
        let model = fixture.model
        #expect(model.lyricsFX.artistDecision("Paper Harbour") == .keepFallback, "決定：下次播放生效")
        #expect(model.libraryCheck.decisions.decision(forArtist: "Paper Harbour")?.choice == .keepFallback)
        #expect(model.lyricsFlow.isMarkedNoLyrics("AAAA000000000001"), "標記：Cover Flow 立刻看得到")
        #expect(model.artistBook?.genres(forArtist: "Velvet Lanterns") == .verified(["doom metal"]), "MB：發布新 snapshot")
        #expect(await fixture.timingStore.load(persistentID: "AAAA000000000002")?.sourceRef == "\(Self.other):AAAA000000000002")
        #expect(model.cloudSyncStatus?.otherWriters == [Self.other: Self.wall])
    }

    @Test func aDecisionMadeAfterwardsIsExportedOnceTheQuietPeriodPasses() async throws {
        let fixture = try await fixture(enabled: true)
        defer { fixture.cleanUp() }
        fixture.model.startCloudSyncIfEnabled()
        await fixture.waitUntilStarted()
        let file = fixture.ownFolder.appendingPathComponent("decisions.json")
        let before = try Data(contentsOf: file)
        fixture.model.libraryCheck.decide(.keepFallback, forArtists: ["Velvet Lanterns"])
        // markDirty 經一個 Task 送進 coordinator：推進時間、tick，直到匯出（上限 50 次）
        var after = before
        for _ in 0..<50 where after == before {
            try await Task.sleep(for: .milliseconds(10))
            fixture.clock.advance(by: 11)
            await fixture.model.cloudSync?.tick()
            after = try Data(contentsOf: file)
        }
        #expect(after != before)
        let exported = try SyncCodec.decode(after, as: SyncPayload.Decisions.self, kind: .decisions, expectedWriter: fixture.me).get()
        #expect(exported.payload[ArtistDecisionBook.key("Velvet Lanterns")]?.version.origin == fixture.me, "匯出前蓋上這台的章")
    }

    @Test func turningItOffStopsReadingAndWriting() async throws {
        let fixture = try await fixture(enabled: true)
        defer { fixture.cleanUp() }
        fixture.model.startCloudSyncIfEnabled()
        await fixture.waitUntilStarted()
        fixture.model.setCloudSyncEnabled(false)
        #expect(fixture.model.cloudSync == nil)
        try writeOtherMac(fixture.root)
        fixture.model.markCloudSyncDirty(.decisions)
        #expect(fixture.model.lyricsFlow.isMarkedNoLyrics("AAAA000000000001") == false)
        #expect(FileManager.default.fileExists(atPath: fixture.ownFolder.path), "關閉不刪任何檔")
    }

    /// 關閉同步後，查找不得再用他機的時間軸候選
    @Test func turningSyncOffForgetsOtherMacsTimelines() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanUp() }
        try writeOtherMac(fixture.root)
        fixture.model.setCloudSyncEnabled(true)
        await fixture.waitUntilStarted()
        let hash = LyricsFingerprint.of("an invented line")
        #expect(await fixture.model.remoteTimingIndex?.candidates(for: hash).count == 1)
        fixture.model.setCloudSyncEnabled(false)
        await fixture.model.cloudSyncIndexClear?.value
        #expect(await fixture.model.remoteTimingIndex?.candidates(for: hash).isEmpty == true)
    }

    /// codex review R2：關了又立刻開，新匯入的候選不被上一次的清除清掉
    @Test func reEnablingRightAwayKeepsFreshTimelines() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanUp() }
        try writeOtherMac(fixture.root)
        fixture.model.setCloudSyncEnabled(true)
        await fixture.waitUntilStarted()
        fixture.model.setCloudSyncEnabled(false)
        fixture.model.cloudSyncStatus = nil
        fixture.model.setCloudSyncEnabled(true)
        for _ in 0..<500 where fixture.model.cloudSyncStatus == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.model.remoteTimingIndex?.candidates(for: LyricsFingerprint.of("an invented line")).count == 1)
    }

    @Test func resettingDeletesOnlyThisMacsCopyAndTurnsSyncOff() async throws {
        let fixture = try await fixture(enabled: true)
        defer { fixture.cleanUp() }
        try writeOtherMac(fixture.root)
        fixture.model.startCloudSyncIfEnabled()
        await fixture.waitUntilStarted()
        await fixture.model.resetCloudSyncCopy()
        #expect(fixture.model.cloudSyncEnabled == false)
        #expect(FileManager.default.fileExists(atPath: fixture.ownFolder.path) == false)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Sync/\(Self.other)/decisions.json").path))
        #expect(fixture.model.decisionBook.decision(forArtist: "Paper Harbour")?.choice == .keepFallback, "本機正本不動")
    }

    @Test func withoutAHardwareIdentityItReportsUnavailable() async throws {
        let fixture = try await fixture(hardware: NoHardware())
        defer { fixture.cleanUp() }
        fixture.model.setCloudSyncEnabled(true)
        #expect(fixture.model.cloudSyncUnavailable)
        #expect(fixture.model.cloudSync == nil)
        #expect(fixture.model.cloudSyncEnabled == false)
        #expect(fixture.defaults.bool(forKey: ConfigStore.Key.cloudSyncEnabled) == false)
        #expect(fixture.model.settings.cloudSync.unavailable, "設定頁顯示無法開啟")
    }

    /// §6.4：結束 app 時匯出 dirty 的類別（不等安靜期）
    @Test func quittingFlushesDirtyKinds() async throws {
        let fixture = try await fixture(enabled: true)
        defer { fixture.cleanUp() }
        fixture.model.startCloudSyncIfEnabled()
        await fixture.waitUntilStarted()
        let file = fixture.ownFolder.appendingPathComponent("decisions.json")
        let before = try Data(contentsOf: file)
        fixture.model.libraryCheck.decide(.keepFallback, forArtists: ["Velvet Lanterns"])
        try await Task.sleep(for: .milliseconds(50))
        await fixture.model.flushCloudSync()
        #expect(try Data(contentsOf: file) != before)
    }

    @Test func withSyncOffQuittingIsImmediate() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanUp() }
        let delegate = AppDelegate(model: fixture.model)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }
}
