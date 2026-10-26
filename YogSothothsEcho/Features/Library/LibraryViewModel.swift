import Foundation
import Observation
import RemoteProtocol
import RemoteTransport
import UIKit

/// 曲庫畫面（sprint-3-detail.md §4.4、§4.6、§4.8）：分頁取完整清單、換版重同步、搜尋、封面、讀不到曲庫時退避重試。
/// 完整清單與搜尋各自一個世代號（偏差說明見附錄 C T11：共用會讓打字中斷清單載入）；清單載完若搜尋框有字就重新搜尋
@MainActor
@Observable
final class LibraryViewModel {
    enum Phase: Equatable {
        case idle
        case loading(loaded: Int)
        case ready
        case failed(LibraryFailure)

        var isLoading: Bool { if case .loading = self { true } else { false } }
    }

    enum LibraryFailure: Equatable {
        /// Mac 讀不到曲庫（CR-012）
        case libraryUnavailable
        /// 連續換版 3 次仍取不完（§4.4）
        case catalogUnstable
        case network
    }

    static let maxRestarts = 3
    static let searchDebounce: Duration = .milliseconds(300)
    static let unavailableBackoff: [Duration] = [.seconds(10), .seconds(20), .seconds(40), .seconds(60)]

    private(set) var phase: Phase = .idle
    private(set) var albums: [AlbumSummary] = []
    private(set) var total: Int?
    private(set) var version: String?
    private(set) var isConnected = false
    private(set) var searchResults: [AlbumSummary]?
    /// `searchResults` 是哪個搜尋字的結果（零結果提示只認目前的字；Codex 確認輪 P2）
    private(set) var searchResultsQuery: String?
    var query = "" { didSet { if query != oldValue { queryChanged() } } }
    var displayed: [AlbumSummary] { searchResults ?? albums }
    /// 側封的 detail 升級（S6 D7）：由組裝根注入，沒有＝只用 spine
    @ObservationIgnored var browseArtwork: BrowseArtwork?
    /// 位置記憶（CR-027，使用者 2026-10-23）：側封中央／小圖中心格的專輯 ID，兩種展示共用。
    /// 只有使用者造成的移動（`userMovedAnchor`）更新；App 進背景時殼層換成連線畫面、側封被拆掉，回來時靠它捲回原位
    @ObservationIgnored private(set) var browseCenterID: String?
    /// 待還原的位置：重開 App＝上次關掉時那張；清空搜尋＝搜尋前那張。畫面在目前清單出現它時套用一次（`scrollTarget`）
    @ObservationIgnored private(set) var pendingRestore: String?
    @ObservationIgnored private var preSearchAnchor: String?
    @ObservationIgnored private var isSearchSession = false
    @ObservationIgnored private let store: SettingsStore?

    static let anchorKey = "browse.anchor"
    /// 使用者手勢開始的捲動（interacting 起到 idle）：只有這段期間的中心變化算使用者移動；程式捲動不經 scroll phase，恆為 false
    @ObservationIgnored private(set) var isUserScrolling = false

    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void
    /// 清單分頁遇 busy／rateLimited 的短重試（F-L1）；`sleep` 另供搜尋 debounce 與 libraryUnavailable 長退避，不共用
    @ObservationIgnored private let shortRetry: ShortTransientRetry.Options
    @ObservationIgnored private let clientBox = Locked<(any EchoClient)?>(nil)
    @ObservationIgnored private var artworkCache: ArtworkCache!
    @ObservationIgnored private var client: (any EchoClient)?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var unavailableAttempt = 0
    @ObservationIgnored private var staleResyncedVersion: String?
    @ObservationIgnored let metrics = LibraryMetrics()

    init(store: SettingsStore? = nil, artworkDirectory: URL = ArtworkCache.defaultDirectory,
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         retry: ShortTransientRetry.Options = .live) {
        self.sleep = sleep
        shortRetry = retry
        self.store = store
        browseCenterID = store?.string(forKey: Self.anchorKey)
        pendingRestore = browseCenterID
        let box = clientBox
        artworkCache = ArtworkCache(directory: artworkDirectory, fetch: { (albumID, token) throws(EchoRequestError) in
            guard let client = box.withLock({ $0 }) else { throw .disconnected }
            return try await client.artwork(albumID: albumID, token: token)
        }, onStale: { [weak self] in Task { @MainActor in self?.artworkWasStale() } }, retry: retry)
    }

    // MARK: 連線

    func attach(_ client: any EchoClient) {
        self.client = client
        clientBox.withLock { $0 = client }
        isConnected = true
        changesTask?.cancel()
        let changes = client.catalogChanges()
        changesTask = Task { [weak self] in
            for await version in changes { self?.catalogChanged(to: version) }
        }
        metrics.loadStarted()
        reload()
    }

    /// 斷線：保留畫面上的清單，重連後背景重同步（§4.7）
    func detach() {
        client = nil
        clientBox.withLock { $0 = nil }
        isConnected = false
        loadGeneration += 1
        searchGeneration += 1
        [loadTask, searchTask, changesTask, retryTask].forEach { $0?.cancel() }
    }

    /// 使用者按「重試」：立即重試並重設退避
    func retry() {
        unavailableAttempt = 0
        retryTask?.cancel()
        reload()
    }

    func image(for album: AlbumSummary, networkDelay: Duration = .zero) async -> UIImage? {
        guard let token = album.artworkToken else { return nil }
        return await artworkCache.image(albumID: album.id, token: token, networkDelay: networkDelay)
    }

    /// 封面回 stale＝Mac 已換版：同一版本只重同步一次（§4.4）
    func artworkWasStale() {
        guard isConnected, staleResyncedVersion != version else { return }
        staleResyncedVersion = version
        reload()
    }

    private func catalogChanged(to newVersion: String) {
        guard newVersion != version else { return }
        reload()
    }

    // MARK: 完整清單

    private func reload() {
        guard let client else { return }
        retryTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        if albums.isEmpty { phase = .loading(loaded: 0) }
        loadTask?.cancel()
        loadTask = Task { [weak self] in await self?.load(client, generation) }
    }

    private func load(_ client: any EchoClient, _ generation: Int) async {
        let showProgressively = albums.isEmpty
        do {
            for _ in 0...Self.maxRestarts {
                guard let (collected, pageVersion, pageTotal) = try await collectAll(client, generation, progressive: showProgressively) else {
                    guard generation == loadGeneration else { return }
                    continue
                }
                guard generation == loadGeneration else { return }
                albums = collected
                version = pageVersion
                total = pageTotal
                phase = .ready
                unavailableAttempt = 0
                if !query.isEmpty { runSearch() }
                return
            }
            guard generation == loadGeneration else { return }
            phase = .failed(.catalogUnstable)
        } catch {
            guard generation == loadGeneration else { return }
            handle(error)
        }
    }

    /// 取完所有頁；任一頁的版本與第一頁不同＝回 nil（呼叫端從頭重來）；取消或世代已換＝丟 `.cancelled`（nil 只表示換版；Codex R5-1）
    private func collectAll(_ client: any EchoClient, _ generation: Int,
                            progressive: Bool) async throws(EchoRequestError) -> ([AlbumSummary], String, Int)? {
        var collected: [AlbumSummary] = []
        var cursor: String?
        var firstVersion: String?
        var lastTotal = 0
        repeat {
            let page = try await fetchPage(client, cursor: cursor, generation)
            if let firstVersion, page.version != firstVersion { return nil }
            firstVersion = page.version
            collected += page.albums
            lastTotal = page.total
            if progressive {
                albums = collected
                total = page.total
            }
            phase = progressive ? .loading(loaded: collected.count) : phase
            cursor = page.nextCursor
        } while cursor != nil
        guard let firstVersion else { return nil }
        return (collected, firstVersion, lastTotal)
    }

    /// 一頁；busy／rateLimited 只重送這一頁（ShortTransientRetry）。發請求前、回覆後（不論成敗）、睡醒後都確認
    /// task 未取消且世代未換，否則丟 `.cancelled`：不再發請求、不採用回覆（Codex R1 高-4、R3-2、R4-2）。曲目分頁同一套：`PlaybackClient.tracksPage`
    private func fetchPage(_ client: any EchoClient, cursor: String?, _ generation: Int) async throws(EchoRequestError) -> CatalogPageResponse {
        var attempt = 1
        while true {
            guard isCurrent(generation) else { throw .cancelled }
            let result: Result<CatalogPageResponse, EchoRequestError>
            do throws(EchoRequestError) { result = .success(try await client.page(cursor: cursor)) } catch { result = .failure(error) }
            guard isCurrent(generation) else { throw .cancelled }
            switch result {
            case .success(let page):
                return page
            case .failure(let error):
                guard ShortTransientRetry.shouldRetry(error, afterAttempt: attempt) else { throw error }
                attempt += 1
                try await ShortTransientRetry.wait(beforeAttempt: attempt, after: error, shortRetry)
            }
        }
    }

    private func isCurrent(_ generation: Int) -> Bool { !Task.isCancelled && generation == loadGeneration }

    private func handle(_ error: EchoRequestError) {
        switch error {
        case .remote(.libraryUnavailable):
            phase = .failed(.libraryUnavailable)
            scheduleUnavailableRetry()
        case .cancelled, .disconnected:
            break
        default:
            phase = .failed(.network)
        }
    }

    /// 連線中自動退避重試（10／20／40 s，之後每 60 s）；成功、斷線或改收到其他錯誤即停（CR-012）
    private func scheduleUnavailableRetry() {
        let delay = Self.unavailableBackoff[min(unavailableAttempt, Self.unavailableBackoff.count - 1)]
        unavailableAttempt += 1
        let generation = loadGeneration, sleep = self.sleep
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            await sleep(delay)
            guard !Task.isCancelled, let self, self.isConnected, generation == self.loadGeneration,
                  self.phase == .failed(.libraryUnavailable) else { return }
            self.reload()
        }
    }

    // MARK: 位置記憶（CR-027）

    /// 使用者拖曳／慣性造成的中心變化（程式還原、展示互帶、搜尋替換不得呼叫）；使用者接管即取消待還原
    func userMovedAnchor(_ id: String) {
        browseCenterID = id
        pendingRestore = nil
    }

    /// 側封與小圖共用的來源閘門（CR-027）：手勢開始＝接管（取消待還原），停下＝寫盤
    func userScrollBegan() {
        isUserScrolling = true
        pendingRestore = nil
    }

    func userScrollEnded() {
        guard isUserScrolling else { return }
        isUserScrolling = false
        flushBrowseAnchor()
    }

    /// VoiceOver 三指掃也是使用者來源：接管並立刻記下（Codex R5／R6）
    func userStepped(to id: String) {
        userMovedAnchor(id)
        flushBrowseAnchor()
    }

    /// 寫盤：存的永遠是完整清單下的位置（搜尋中＝搜尋前那張）。捲動停下、搜尋結束、scene 進 inactive／background 時呼叫
    func flushBrowseAnchor() {
        guard let id = isSearchSession ? preSearchAnchor : browseCenterID else { return }
        store?.set(id, forKey: Self.anchorKey)
    }

    /// 搜尋字改了、清單尚未依它捲動過（`scrollTarget` 消耗）
    @ObservationIgnored private(set) var queryChangedSinceScroll = false

    /// 清單出現或換了之後該捲到哪張：待還原的位置（只套一次）優先，否則依 `BrowserScrollAnchor` 規則；空清單不消耗待還原
    func scrollTarget(ids: [String], previousCenter: String?) -> String? {
        scrollTarget(ids: ids, previousCenter: previousCenter, listComplete: searchResults != nil || !phase.isLoading)
    }

    /// 清單還在分頁載入、目標還沒到：先不消耗待還原（Codex 確認輪 P1：上次停在後面幾頁時，第一頁到就回第一張）
    func scrollTarget(ids: [String], previousCenter: String?, listComplete: Bool) -> String? {
        guard !ids.isEmpty else { return nil }
        var restore = pendingRestore
        if let target = restore, !listComplete, !ids.contains(target) { restore = nil } else { pendingRestore = nil }
        let queryChanged = queryChangedSinceScroll
        queryChangedSinceScroll = false
        return BrowserScrollAnchor.target(previousCenter: previousCenter, newIDs: ids, queryChanged: queryChanged, restore: restore)
    }

    nonisolated static func isEffective(query: String) -> Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: 搜尋（F-L-04）

    private func queryChanged() {
        searchTask?.cancel()
        searchGeneration += 1
        queryChangedSinceScroll = true
        let searching = Self.isEffective(query: query)
        if searching, !isSearchSession {
            isSearchSession = true
            preSearchAnchor = browseCenterID
        } else if !searching, isSearchSession {
            isSearchSession = false
            browseCenterID = preSearchAnchor
            pendingRestore = preSearchAnchor
            preSearchAnchor = nil
            flushBrowseAnchor()
        }
        guard searching else {
            searchResults = nil
            return
        }
        let generation = searchGeneration, sleep = self.sleep
        searchTask = Task { [weak self] in
            await sleep(Self.searchDebounce)
            guard !Task.isCancelled else { return }
            await self?.performSearch(generation)
        }
    }

    private func runSearch() {
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        searchTask = Task { [weak self] in await self?.performSearch(generation) }
    }

    private func performSearch(_ generation: Int) async {
        guard let client, generation == searchGeneration else { return }
        let text = query
        guard let response = try? await client.search(text), generation == searchGeneration else { return }
        // 結果與目前顯示的相同＝清單不變、畫面不會收到換清單：不留「搜尋改了」旗標（Codex 確認輪 P2）
        if response.albums == displayed { queryChangedSinceScroll = false }
        searchResults = response.albums
        searchResultsQuery = text
    }
}
