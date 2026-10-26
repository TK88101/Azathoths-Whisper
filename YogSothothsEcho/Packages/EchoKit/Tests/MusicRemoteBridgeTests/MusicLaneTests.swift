#if os(macOS)
import Foundation
import ScriptingBridge
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// S4 T5（sprint-4-detail.md §3、§4.4；#4-0 P1-d）：MusicLane——綁 PID、不代為啟動 Music、錯誤映射、單一序列

final class FakeScripting: MusicScripting, @unchecked Sendable {
    let lock = NSLock()
    var state: UInt32? = 0x6B50_5350
    var current: (id: String, duration: Double?)? = ("ABCDEF0123456789", 200)
    var position: Double? = 12
    var pendingError: Int?
    var lookupHits: Set<String> = []
    var devices: [(id: String, kind: UInt32, selected: Bool)] = []
    private(set) var calls: [String] = []
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    var delay: TimeInterval = 0

    private func record(_ call: String) {
        lock.withLock { calls.append(call); inFlight += 1; maxInFlight = max(maxInFlight, inFlight) }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        lock.withLock { inFlight -= 1 }
    }

    func playerState() -> UInt32? { record("state"); return state }
    func currentTrack() -> (id: String, duration: Double?)? { record("current"); return current }
    func playerPosition() -> Double? { record("position"); return position }
    func setPlayerPosition(_ seconds: Double) { record("seek \(seconds)") }
    func playPause() { record("playpause") }
    func nextTrack() { record("next") }
    func previousTrack() { record("previous") }
    func playOnce(persistentID: String) -> Bool { record("playOnce \(persistentID)"); return lookupHits.contains(persistentID) }
    func airPlayDevices() -> [(id: String, kind: UInt32, selected: Bool)] { record("airplay"); return devices }
    func setAirPlayDevices(_ ids: [String]) -> Bool { record("setAirplay \(ids)"); return true }
    func takeLastErrorCode() -> Int? { lock.withLock { defer { pendingError = nil }; return pendingError } }
}

final class UptimeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Double
    init(_ value: Double) { current = value }
    var value: Double {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

final class FakeLocator: MusicProcessLocating, @unchecked Sendable {
    let lock = NSLock()
    var pid: pid_t? = 100
    func musicPID() -> pid_t? { lock.withLock { pid } }
}

final class FakeFactory: @unchecked Sendable {
    let lock = NSLock()
    let scripting = FakeScripting()
    private(set) var boundPIDs: [pid_t] = []
    func make(_ pid: pid_t) -> any MusicScripting { lock.withLock { boundPIDs.append(pid) }; return scripting }
}

struct MusicLaneTests {
    let locator = FakeLocator()
    let factory = FakeFactory()
    var lane: MusicLane { MusicLane(locator: locator, makeScripting: { [factory] in factory.make($0) }) }

    /// 暫停後的舊位置在 MusicLane 這一層就修正：輪詢推送、控制回覆的讀回都拿到修正後的值
    @Test func snapshotCorrectsStalePausePosition() async throws {
        let clock = UptimeBox(10)
        let lane = MusicLane(locator: locator, makeScripting: { [factory] in factory.make($0) }, uptime: { clock.value })
        factory.scripting.position = 25.5
        _ = try await lane.snapshot()
        factory.scripting.state = 0x6B50_5370          // 'kPSp' 暫停
        factory.scripting.position = 19.85
        clock.value = 10.5
        #expect(try await lane.snapshot().position == 26)
    }

    @Test func musicNotRunningThrowsWithoutBindingOrSending() async {
        locator.pid = nil
        await #expect(throws: MusicLaneError.notRunning) { try await lane.snapshot() }
        await #expect(throws: MusicLaneError.notRunning) { try await lane.next() }
        #expect(factory.boundPIDs.isEmpty && factory.scripting.calls.isEmpty)
    }

    @Test(arguments: [(-1743, MusicLaneError.notAuthorized), (-600, .notRunning), (-609, .notRunning), (-1712, .failed(code: -1712))])
    func appleEventErrorsAreMapped(code: Int, expected: MusicLaneError) async {
        factory.scripting.pendingError = code
        await #expect(throws: expected) { try await lane.togglePlayPause() }
    }

    @Test func bindsToTheCurrentPIDEveryOperation() async throws {
        let lane = self.lane
        _ = try await lane.snapshot()
        locator.pid = 200
        _ = try await lane.snapshot()
        #expect(factory.boundPIDs == [100, 200])
    }

    @Test(arguments: [(UInt32(0x6B50_5350), PlaybackState.playing), (0x6B50_5370, .paused), (0x6B50_5353, .stopped),
                      (0x6B50_5346, .playing), (0x6B50_5352, .playing), (0x1234_5678, .stopped)])
    func playerStateCodesMap(raw: UInt32, expected: PlaybackState) async throws {
        factory.scripting.state = raw
        #expect(try await lane.snapshot().state == expected)
    }

    @Test func snapshotLowercasesIDsAndCarriesDurationAndPosition() async throws {
        let snapshot = try await lane.snapshot()
        #expect(snapshot.trackID == "abcdef0123456789" && snapshot.duration == 200 && snapshot.position == 12)
    }

    @Test func noCurrentTrackIsNotAnError() async throws {
        factory.scripting.current = nil
        let snapshot = try await lane.snapshot()
        #expect(snapshot.trackID == nil && snapshot.duration == nil)
    }

    @Test func playOnceUsesUppercasePersistentIDAndReportsLookup() async throws {
        factory.scripting.lookupHits = ["00000000000000AA"]
        #expect(try await lane.playOnce(trackID: "00000000000000aa"))
        #expect(try await !lane.playOnce(trackID: "00000000000000bb"))
    }

    /// security review MEDIUM-2：SB 回非有限值（串流、電台等邊界）時不得進事件——JSONEncoder 預設遇 NaN／∞ 會拋錯
    @Test func nonFiniteValuesAreSanitized() async throws {
        factory.scripting.current = ("ABCDEF0123456789", .infinity)
        factory.scripting.position = .nan
        let snapshot = try await lane.snapshot()
        #expect(snapshot.duration == nil && snapshot.position == 0)
        factory.scripting.current = ("ABCDEF0123456789", -1)
        #expect(try await lane.snapshot().duration == nil)
    }

    /// #4-1 真機實測：換歌瞬間 Music 的目前曲可能帶空字串 ID——當成「沒有目前曲」（曾被當成專輯外換歌而誤報 manualChange）
    @Test func emptyTrackIDMeansNoCurrentTrack() async throws {
        factory.scripting.current = ("", 200)
        #expect(try await lane.snapshot().trackID == nil)
    }

    /// CR-015：上一首送 `previous track`（直接到前一首）；`back track` 會先回曲頭（#4-1 真機）
    @Test func previousSendsPreviousTrack() async throws {
        try await lane.previous()
        #expect(factory.scripting.calls.contains("previous") && !factory.scripting.calls.contains("back"))
    }

    @Test func seekSendsSeconds() async throws {
        try await lane.seek(to: 42.5)
        #expect(factory.scripting.calls.contains("seek 42.5"))
    }

    @Test func outputsAreLowercasedSummaries() async throws {
        factory.scripting.devices = [("AABBCCDDEEFF0011", 1, true)]
        #expect(try await lane.outputs() == [OutputDeviceSummary(id: "aabbccddeeff0011", kind: 1, selected: true)])
    }

    /// S4 T14（§4.13）：設定輸出時把協定的小寫 ID 還原成 Music 的大寫 persistentID
    @Test func setOutputsSendsUppercasePersistentIDs() async throws {
        #expect(try await lane.setOutputs(["aabbccddeeff0011"]))
        #expect(factory.scripting.calls.contains("setAirplay [\"AABBCCDDEEFF0011\"]"))
    }

    @Test func operationsNeverOverlap() async throws {
        factory.scripting.delay = 0.02
        let lane = self.lane
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try await lane.snapshot() } }
            try await group.waitForAll()
        }
        #expect(factory.scripting.maxInFlight == 1)
    }
}

struct TrackLookupTests {
    @Test func emptyOrMalformedIDNeverQueries() {
        var queried = 0
        #expect(TrackLookup.resolve(persistentID: "", matches: { _ in queried += 1; return [1] }) == nil)
        #expect(queried == 0)
    }

    @Test func noneOneOrManyMatches() {
        #expect(TrackLookup.resolve(persistentID: "00000000000000AA", matches: { _ in [] }) == nil)
        #expect(TrackLookup.resolve(persistentID: "00000000000000AA", matches: { _ in ["one"] }) as? String == "one")
        // persistent ID 在 Music 內唯一；萬一回多筆取第一筆（TrackLookup 依 E3 不得計數或列舉）
        #expect(TrackLookup.resolve(persistentID: "00000000000000AA", matches: { _ in ["first", "second"] }) as? String == "first")
    }

    @Test func predicateFiltersByPersistentIDOnly() {
        var seen: NSPredicate?
        _ = TrackLookup.resolve(persistentID: "00000000000000AA", matches: { seen = $0; return [] })
        #expect(seen?.predicateFormat == "persistentID == \"00000000000000AA\"")
    }
}

/// D12（sprint-1-detail.md §4.2；H-27）：SB 類別採用的 AZW 協定集合完全等於指定集合
struct RemoteProtocolAdoptionTests {
    private func adopted(_ cls: AnyClass) -> Set<String> {
        var count: UInt32 = 0
        guard let list = class_copyProtocolList(cls, &count) else { return [] }
        defer { free(UnsafeMutableRawPointer(list)) }
        return Set((0..<Int(count)).map { String(cString: protocol_getName(list[$0])) }.filter { $0.hasPrefix("AZW") })
    }

    @Test func scriptingBridgeClassesAdoptExactlyTheRemoteProtocols() {
        #expect(adopted(SBApplication.self) == ["AZWMusicRemoteProto", "AZWMusicRemoteLibraryProto"])
        #expect(adopted(SBObject.self) == ["AZWMusicRemoteTrackProto", "AZWMusicRemoteAirPlayProto"])
    }
}
/// #4-1 N-01 真機：Music 一直開著，程序清單偶爾短暫查不到（`lane no-pid`，推測是清單更新的時間差）——
/// 改用上一次查到、且確認仍是 Music 的程序編號；確認不了才算 Music 沒開
struct MusicPIDResolverTests {
    @Test func listedPIDWinsAndIsRemembered() {
        var resolver = MusicPIDResolver()
        #expect(resolver.resolve(listed: 42, isMusic: { _ in true }) == 42)
        #expect(resolver.resolve(listed: nil, isMusic: { $0 == 42 }) == 42)
    }

    /// S4 後半 security LOW-4：清單以 bundle ID 查到的程序也要是 Music 本體（同使用者可自建同 bundle ID 的 app）
    @Test func listedPIDThatIsNotMusicIsRejected() {
        var resolver = MusicPIDResolver()
        #expect(resolver.resolve(listed: 42, isMusic: { _ in false }) == nil)
        #expect(resolver.resolve(listed: nil, isMusic: { _ in true }) == nil)   // 沒被記住
    }

    /// 同一個 PID 只確認一次（每 0.1 s 都會查，不重複讀核心路徑）
    @Test func listedPIDIsVerifiedOnlyWhenItChanges() {
        var resolver = MusicPIDResolver()
        var checks = 0
        let isMusic: (pid_t) -> Bool = { _ in checks += 1; return true }
        _ = resolver.resolve(listed: 42, isMusic: isMusic)
        _ = resolver.resolve(listed: 42, isMusic: isMusic)
        _ = resolver.resolve(listed: 43, isMusic: isMusic)
        #expect(checks == 2)
    }

    @Test func rememberedPIDThatIsNoLongerMusicIsNotUsed() {
        var resolver = MusicPIDResolver()
        _ = resolver.resolve(listed: 42, isMusic: { _ in true })
        #expect(resolver.resolve(listed: nil, isMusic: { _ in false }) == nil)
        #expect(resolver.resolve(listed: nil, isMusic: { _ in true }) == nil)   // 失效後已忘記，不再回頭用
    }

    /// 備用確認改由核心取執行檔路徑（#4-1 N-01 真機：清單查不到的同一瞬間，以 PID 建 NSRunningApplication 也失敗）
    @Test func musicExecutableIsRecognizedByPath() {
        #expect(MusicPIDResolver.isMusicExecutable("/System/Applications/Music.app/Contents/MacOS/Music"))
        #expect(!MusicPIDResolver.isMusicExecutable("/Applications/Other.app/Contents/MacOS/Music"))
        #expect(!MusicPIDResolver.isMusicExecutable("/System/Applications/Music.app/Contents/MacOS/MusicHelper"))
        #expect(!MusicPIDResolver.isMusicExecutable(nil))
    }

    /// 自己這個測試程序不是 Music
    @Test func ownProcessIsNotMusic() {
        #expect(!MusicPIDResolver.processIsMusic(getpid()))
    }

    @Test func nothingListedAndNothingRememberedIsNotRunning() {
        var resolver = MusicPIDResolver()
        #expect(resolver.resolve(listed: nil, isMusic: { _ in true }) == nil)
    }
}
/// #4-1 D2 真機（21:27:11）：Music 剛暫停時先回報「上一次暫停的位置」，0.1–0.5 s 後才更新——
/// iPad 進度條先跳回再跳到正確位置（使用者：「暫停時進度條會抽動」），也讓每次暫停推兩筆
struct StalePauseFilterTests {
    private let id = "00000000000000aa"
    private func snap(_ state: PlaybackState, _ position: Double, track: String? = nil) -> MusicSnapshot {
        MusicSnapshot(state: state, trackID: track ?? id, duration: 200, position: position)
    }

    @Test func staleOldPausePositionIsReplacedByWhereItActuallyStopped() {
        var filter = StalePauseFilter()
        _ = filter.correct(snap(.playing, 25.5), at: 10)
        #expect(filter.correct(snap(.paused, 19.85), at: 10.5).position == 26)          // 時刻取二進位可精確表示的值
        #expect(filter.correct(snap(.paused, 19.85), at: 10.75).position == 26)         // 還沒更新：維持
        #expect(filter.correct(snap(.paused, 26.04), at: 11.25).position == 26.04)      // 更新了：用真值
    }

    @Test func pauseAheadOfTheLastReadIsKept() {
        var filter = StalePauseFilter()
        _ = filter.correct(snap(.playing, 25.5), at: 10)
        #expect(filter.correct(snap(.paused, 25.9), at: 10.5).position == 25.9)
    }

    @Test func otherTrackOrStillPlayingIsUntouched() {
        var filter = StalePauseFilter()
        _ = filter.correct(snap(.playing, 25.5), at: 10)
        #expect(filter.correct(snap(.paused, 3, track: "00000000000000bb"), at: 10.5).position == 3)
        _ = filter.correct(snap(.playing, 25.5), at: 20)
        #expect(filter.correct(snap(.playing, 3), at: 20.5).position == 3)               // 播放中倒回＝拖進度，不動
    }

    /// #4-1 D2 真機（21:38:03）：按暫停的瞬間 Music 還回報「播放中」，位置卻已是上一次暫停的舊值（35.65），
    /// 接著「暫停 35.65」、再來才是真值 40.89——舊值等於上次暫停時的位置，就認得出來
    @Test func stalePositionWhileStillReportedPlayingIsReplaced() {
        var filter = StalePauseFilter()
        _ = filter.correct(snap(.paused, 35.65), at: 0)
        _ = filter.correct(snap(.playing, 35.75), at: 0.5)
        _ = filter.correct(snap(.playing, 40.5), at: 5.25)
        #expect(filter.correct(snap(.playing, 35.65), at: 5.5).position == 40.75)
        #expect(filter.correct(snap(.paused, 35.65), at: 5.5).position == 40.75)
        #expect(filter.correct(snap(.paused, 40.89), at: 6).position == 40.89)
    }

    /// 播放中真的被拖回（不是上次暫停的位置）：不動
    @Test func seekBackWhilePlayingToAnotherPositionIsKept() {
        var filter = StalePauseFilter()
        _ = filter.correct(snap(.paused, 35.65), at: 0)
        _ = filter.correct(snap(.playing, 40.5), at: 5)
        #expect(filter.correct(snap(.playing, 10), at: 5.5).position == 10)
    }

    /// 已在暫停中、之後讀到更前面的位置＝真的被拖回（不是剛暫停的舊值）
    @Test func seekBackWhilePausedIsKept() {
        var filter = StalePauseFilter()
        _ = filter.correct(snap(.paused, 40), at: 10)
        #expect(filter.correct(snap(.paused, 5), at: 10.5).position == 5)
    }
}
#endif

