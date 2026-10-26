import Foundation
import RemoteProtocol
import RemoteTransport
import Testing
import UIKit

@testable import YogSothothsEcho

// S3 T11／T12（sprint-3-detail.md §4.4、§4.6、§4.8）：曲庫畫面的狀態機。名稱一律自編

/// 可程式化的曲庫：可在指定頁換版、可失敗、可擋住
final class ScriptedEchoClient: EchoClient, @unchecked Sendable {
    let lock = NSLock()
    var total: Int
    var version = "00000000000000a1"
    /// 第 n 次 page 呼叫（從 1 起）回傳時改成這個版本
    var bumpVersionOnCall: [Int: String] = [:]
    var pageCalls = 0
    var failure: EchoRequestError?
    /// 第 n 次 page 呼叫（從 1 起）丟這個錯（優先於 `failure`；F-L1）
    var failuresOnCall: [Int: EchoRequestError] = [:]
    /// 第 n 次 page 呼叫停住直到 `releasePages`，不理會取消（模擬已送出、回覆在途中；F-L1 R2⑤）
    var holdOnCall: Int?
    private(set) var cursors: [String?] = []
    private var pageGates: [CheckedContinuation<Void, Never>] = []
    var searchQueries: [String] = []
    let changes: AsyncStream<String>
    let changeContinuation: AsyncStream<String>.Continuation

    init(total: Int) {
        self.total = total
        (changes, changeContinuation) = AsyncStream.makeStream()
    }

    private func album(_ i: Int) -> AlbumSummary {
        AlbumSummary(id: String(format: "%016llx", UInt64(i + 1)), title: String(format: "Album %03d", i + 1), artist: "Artist",
                     trackCount: 1, artworkToken: nil)
    }

    func page(cursor: String?) async throws(EchoRequestError) -> CatalogPageResponse {
        let (failure, version, total, hold) = lock.withLock { () -> (EchoRequestError?, String, Int, Bool) in
            pageCalls += 1
            cursors.append(cursor)
            if let bumped = bumpVersionOnCall[pageCalls] { self.version = bumped }
            return (failuresOnCall[pageCalls] ?? self.failure, self.version, self.total, holdOnCall == pageCalls)
        }
        if hold { await withCheckedContinuation { c in lock.withLock { pageGates.append(c) } } }
        if let failure { throw failure }
        let offset = cursor.flatMap(CatalogCursor.decode)?.offset ?? 0
        let end = min(offset + 100, total)
        let next = end < total ? CatalogCursor(version: version, offset: end).encoded() : nil
        return CatalogPageResponse(version: version, total: total, albums: (offset..<end).map(album), nextCursor: next)
    }

    func search(_ query: String) async throws(EchoRequestError) -> CatalogSearchResponse {
        let (version, total) = lock.withLock { () -> (String, Int) in searchQueries.append(query); return (self.version, self.total) }
        return CatalogSearchResponse(version: version, albums: (0..<min(3, total)).map(album))
    }

    func artwork(albumID: String, token: String) async throws(EchoRequestError) -> ArtworkResponse {
        ArtworkResponse(albumID: albumID, size: .spine, outcome: .none, artworkToken: nil, jpeg: nil)
    }

    func catalogChanges() -> AsyncStream<String> { changes }
    var calls: Int { lock.withLock { pageCalls } }
    var queries: [String] { lock.withLock { searchQueries } }
    var requestedCursors: [String?] { lock.withLock { cursors } }
    var heldPages: Int { lock.withLock { pageGates.count } }
    func releasePages() { lock.withLock { () -> [CheckedContinuation<Void, Never>] in defer { pageGates = [] }; return pageGates }.forEach { $0.resume() } }
}

/// 假睡眠：記錄要求的秒數，由測試放行
actor ManualSleeper {
    private(set) var requested: [Duration] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func sleep(_ duration: Duration) async {
        requested.append(duration)
        await withCheckedContinuation { waiters.append($0) }
    }
    func wake() { waiters.forEach { $0.resume() }; waiters.removeAll() }
    var waiting: Int { waiters.count }
}

@MainActor
func settleMain() async { for _ in 0..<50 { await Task.yield() } }

@MainActor
struct LibraryViewModelTests {
    let sleeper = ManualSleeper()
    let retrySleeper = CancellableSleeper()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)")

    func model() -> LibraryViewModel {
        let sleeper = sleeper
        return LibraryViewModel(artworkDirectory: directory, sleep: { await sleeper.sleep($0) }, retry: retrySleeper.options)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func loadsEveryPageAndShowsAll() async {
        let client = ScriptedEchoClient(total: 250)
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready })
        #expect(vm.albums.count == 250 && vm.total == 250)
        #expect(Set(vm.albums.map(\.id)).count == 250)
    }

    /// F-L-01 規模（S7 T9 追溯缺口）：實際曲庫約 975 張專輯（PRD §7）——10 頁全部取完、不重複
    @Test func loadsALibraryOfRealSize() async {
        let client = ScriptedEchoClient(total: 975)
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready })
        #expect(vm.albums.count == 975 && Set(vm.albums.map(\.id)).count == 975)
        #expect(client.calls == 10)
    }

    @Test func versionChangeMidwayRestartsFromFirstPage() async {
        let client = ScriptedEchoClient(total: 250)
        client.lock.withLock { client.bumpVersionOnCall = [2: "00000000000000a2"] }
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready })
        #expect(vm.albums.count == 250 && vm.version == "00000000000000a2")
        #expect(client.calls == 2 + 3)
    }

    @Test func versionKeepsChangingGivesUpAfterThreeRestarts() async {
        let client = ScriptedEchoClient(total: 250)
        client.lock.withLock { client.bumpVersionOnCall = Dictionary(uniqueKeysWithValues: (1...20).map { ($0, String(format: "%016llx", UInt64($0))) }) }
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .failed(.catalogUnstable) })
    }

    @Test func catalogChangedReplacesListInBackground() async {
        let client = ScriptedEchoClient(total: 120)
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready && vm.albums.count == 120 })
        client.lock.withLock { client.total = 130; client.version = "00000000000000b1" }
        client.changeContinuation.yield("00000000000000b1")
        #expect(await waitUntil { vm.albums.count == 130 })
        #expect(vm.version == "00000000000000b1")
    }

    @Test func disconnectKeepsListAndReconnectResyncs() async {
        let client = ScriptedEchoClient(total: 50)
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready })
        vm.detach()
        #expect(!vm.isConnected && vm.albums.count == 50)
        let again = ScriptedEchoClient(total: 60)
        vm.attach(again)
        #expect(await waitUntil { vm.albums.count == 60 })
    }

    @Test func libraryUnavailableKeepsListAndRetriesWithBackoff() async {
        let client = ScriptedEchoClient(total: 50)
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready })
        client.lock.withLock { client.failure = .remote(.libraryUnavailable) }
        client.changeContinuation.yield("00000000000000c1")
        #expect(await waitUntil { vm.phase == .failed(.libraryUnavailable) })
        #expect(vm.albums.count == 50)
        #expect(await waitUntil2 { await sleeper.waiting == 1 })
        #expect(await sleeper.requested == [.seconds(10)])
        #expect(retrySleeper.durations.isEmpty, "libraryUnavailable 不走短重試（F-L1 R2⑥）")
        await sleeper.wake()
        #expect(await waitUntil2 { await sleeper.requested.count == 2 })
        #expect(await sleeper.requested.last == .seconds(20))
        client.lock.withLock { client.failure = nil }
        await sleeper.wake()
        #expect(await waitUntil { vm.phase == .ready })
    }

    @Test func manualRetryResetsBackoff() async {
        let client = ScriptedEchoClient(total: 5)
        client.lock.withLock { client.failure = .remote(.libraryUnavailable) }
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .failed(.libraryUnavailable) })
        client.lock.withLock { client.failure = nil }
        vm.retry()
        #expect(await waitUntil { vm.phase == .ready })
    }

    @Test func searchIsDebouncedAndEmptyQueryShowsFullList() async {
        let client = ScriptedEchoClient(total: 20)
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready })
        vm.query = "a"
        vm.query = "al"
        vm.query = "alb"
        #expect(await waitUntil2 { await sleeper.waiting >= 1 })
        await sleeper.wake()
        #expect(await waitUntil { vm.searchResults != nil })
        #expect(client.queries == ["alb"])
        vm.query = ""
        #expect(vm.searchResults == nil && vm.displayed.count == 20)
    }

    /// Codex 確認輪 P2：改字但結果與目前相同（清單不變、畫面不會收到換清單）＝不留「搜尋改了」旗標，免得之後不相干的換版跳回第一張
    @Test func equalSearchResultsDoNotLeaveQueryChangedFlag() async {
        let client = ScriptedEchoClient(total: 20)
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready })
        vm.query = "alb"
        #expect(await waitUntil2 { await sleeper.waiting >= 1 })
        await sleeper.wake()
        #expect(await waitUntil { vm.searchResults != nil })
        _ = vm.scrollTarget(ids: vm.displayed.map(\.id), previousCenter: nil)
        vm.query = "albu"
        #expect(vm.queryChangedSinceScroll)
        #expect(await waitUntil2 { await sleeper.waiting >= 1 })
        await sleeper.wake()
        #expect(await waitUntil { client.queries.count == 2 })
        #expect(await waitUntil { !vm.queryChangedSinceScroll })
    }

    @Test func catalogChangeDuringSearchRefreshesOnlySearchResults() async {
        let client = ScriptedEchoClient(total: 20)
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready })
        vm.query = "album"
        #expect(await waitUntil2 { await sleeper.waiting >= 1 })
        await sleeper.wake()
        #expect(await waitUntil { vm.searchResults != nil })
        client.lock.withLock { client.total = 25; client.version = "00000000000000d1" }
        client.changeContinuation.yield("00000000000000d1")
        #expect(await waitUntil { vm.albums.count == 25 })
        #expect(await waitUntil { client.queries.count == 2 })
        #expect(vm.searchResults != nil && vm.query == "album")
    }

    @Test func staleArtworkTriggersOneResyncPerVersion() async {
        let client = ScriptedEchoClient(total: 10)
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready })
        let before = client.calls
        vm.artworkWasStale()
        vm.artworkWasStale()
        #expect(await waitUntil { client.calls == before + 1 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(client.calls == before + 1)
    }

    private func waitUntil2(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
        for _ in 0..<400 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }
}
