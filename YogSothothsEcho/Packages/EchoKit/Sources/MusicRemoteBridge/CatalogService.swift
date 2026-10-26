#if os(macOS)
import Foundation
import RemoteProtocol

/// 時間來源（外部邊界；測試用假時鐘）
public protocol CatalogClock: Sendable {
    func now() async -> Date
    func sleep(seconds: TimeInterval) async throws
}

public struct SystemCatalogClock: CatalogClock {
    public init() {}
    public func now() async -> Date { Date() }
    public func sleep(seconds: TimeInterval) async throws { try await Task.sleep(for: .seconds(seconds)) }
}

/// Mac 端曲庫服務（sprint-3-detail.md §4.5）：懶載入（第一個請求才讀曲庫）、分頁／搜尋／封面、週期重建。
/// 回應都已套用完整訊息位元組預算；錯誤以 ErrorCode 回給 router。
public actor CatalogService {
    public enum State: Equatable, Sendable {
        case idle, loading
        case ready(version: String)
        case unavailable(code: Int)
    }

    public static let retryInterval: TimeInterval = 10
    public static let artworkCacheBytes = 64 * 1_048_576
    public static let renderConcurrency = 2

    private struct ArtworkKey: Hashable, Sendable {
        let albumID: String
        let token: String
        let size: ArtworkSize
    }

    public private(set) var state: State = .idle
    private let source: any CatalogSource
    private let clock: any CatalogClock
    private let rebuildInterval: TimeInterval
    private let onChange: @Sendable (String) -> Void
    private let onAvailability: @Sendable (Bool) -> Void
    /// 上次通知的曲庫可讀與否；只在翻轉時通知（不再每個請求通知一次）
    private var lastAvailable: Bool?
    private var index: CatalogIndex?
    private var loadTask: Task<Result<CatalogIndex, CatalogSourceError>, Never>?
    private var lastFailureAt: Date?
    private var artworkCache = LRUCache<ArtworkKey, Data>(costLimit: CatalogService.artworkCacheBytes)
    private let limiter = CoalescingQueue<ArtworkKey, Data>(maxConcurrent: CatalogService.renderConcurrency,
                                                            order: .fifo, whenAbandoned: .cancelRunning)
    private var watcher: Task<Void, Never>?
    private var watchGeneration = 0
    /// detail（原檔分塊，CR-018）的傳輸生命週期
    private var detailTransfers = DetailTransferBook()

    public init(source: any CatalogSource, clock: any CatalogClock = SystemCatalogClock(),
                rebuildInterval: TimeInterval = CatalogLimits.rebuildInterval, onChange: @escaping @Sendable (String) -> Void,
                onAvailability: @escaping @Sendable (Bool) -> Void = { _ in }) {
        self.source = source
        self.clock = clock
        self.rebuildInterval = rebuildInterval
        self.onChange = onChange
        self.onAvailability = onAvailability
    }

    private func setAvailable(_ available: Bool) {
        guard lastAvailable != available else { return }
        lastAvailable = available
        onAvailability(available)
    }

    // MARK: 請求

    public func page(_ request: CatalogPageRequest) async -> Result<CatalogPageResponse, ErrorCode> {
        guard request.isValid, !Task.isCancelled else { return .failure(.invalidRequest) }
        let offset = request.cursor.flatMap(CatalogCursor.decode)?.offset ?? 0
        return await currentIndex().map { index in
            let all = index.albums
            let start = min(offset, all.count)
            let candidates = Array(all[start..<min(start + request.limit, all.count)])
            func response(_ count: Int) -> CatalogPageResponse {
                let next = start + count < all.count ? CatalogCursor(version: index.version, offset: start + count).encoded() : nil
                return CatalogPageResponse(version: index.version, total: all.count, albums: Array(candidates.prefix(count)),
                                           nextCursor: next)
            }
            let count = ResponseBudget.largestFittingCount(upTo: candidates.count) {
                Envelope.encode(.catalogPage, response($0))
            }
            // 單筆摘要最壞約 7 KB（T2 測試），0 筆只在預算設定錯誤時發生；跳過該筆以免 iPad 無限重取同一 cursor
            guard count > 0 || candidates.isEmpty else {
                return CatalogPageResponse(version: index.version, total: all.count, albums: [],
                                           nextCursor: CatalogCursor(version: index.version, offset: start + 1).encoded())
            }
            return response(count)
        }
    }

    /// 目前曲的專輯 ID（狀態推送用）。**不觸發載入**：曲庫只在 iPad 請求曲庫時讀（H-31），未載入時回 nil
    public func albumID(ofTrack trackID: String) -> String? { index?.albumOfTrack[trackID] }

    /// album.tracks（S4 T4，CR-013(f)）：依完整訊息位元組預算分頁；未知專輯＝invalidRequest
    public func albumSongs(_ request: AlbumTracksRequest) async -> Result<AlbumTracksResponse, ErrorCode> {
        guard request.isValid, !Task.isCancelled else { return .failure(.invalidRequest) }
        let offset = request.cursor.flatMap(CatalogCursor.decode)?.offset ?? 0
        return await currentIndex().flatMap { index in
            guard let all = index.songsByAlbum[request.albumID] else { return .failure(.invalidRequest) }
            let playable = if case .admitted = index.admission[request.albumID] { true } else { false }
            let start = min(offset, all.count)
            let candidates = Array(all[start...])
            func response(_ count: Int) -> AlbumTracksResponse {
                let next = start + count < all.count ? CatalogCursor(version: index.version, offset: start + count).encoded() : nil
                return AlbumTracksResponse(albumID: request.albumID, version: index.version, songs: Array(candidates.prefix(count)),
                                           nextCursor: next, contextPlayable: playable)
            }
            let count = ResponseBudget.largestFittingCount(upTo: candidates.count) { Envelope.encode(.albumTracks, response($0)) }
            return .success(response(max(count, candidates.isEmpty ? 0 : 1)))
        }
    }

    /// 點歌的許可與捷徑計畫（S4 T7；§4.5 步驟 1「繫結」：以當下索引算出、存在請求內）。
    /// 不合法、未知專輯或曲目不屬於該專輯＝invalidRequest
    public func plan(for request: PlayTrackRequest) async -> Result<AdmissionResult, ErrorCode> {
        guard request.isValid, !Task.isCancelled else { return .failure(.invalidRequest) }
        return await currentIndex().flatMap { index in
            guard index.albumOfTrack[request.trackID] == request.albumID, let admission = index.admission[request.albumID]
            else { return .failure(.invalidRequest) }
            return .success(admission)
        }
    }

    /// 正規化在 actor 外做，不佔住曲庫服務（security review MEDIUM-1）
    public nonisolated func search(_ request: CatalogSearchRequest) async -> Result<CatalogSearchResponse, ErrorCode> {
        guard request.isValid, !Task.isCancelled else { return .failure(.invalidRequest) }
        let needle = TextFold.fold(request.query.trimmingCharacters(in: .whitespacesAndNewlines))
        return await search(needle: needle, limit: request.limit)
    }

    private func search(needle: String, limit: Int) async -> Result<CatalogSearchResponse, ErrorCode> {
        guard !Task.isCancelled else { return .failure(.invalidRequest) }
        return await currentIndex().map { index in
            let hits = index.searchCorpus.indices.lazy.filter { index.searchCorpus[$0].contains(needle) }
                .prefix(limit).map { index.albums[$0] }
            let matches = Array(hits)
            let count = ResponseBudget.largestFittingCount(upTo: matches.count) {
                Envelope.encode(.catalogSearch, CatalogSearchResponse(version: index.version, albums: Array(matches.prefix($0))))
            }
            return CatalogSearchResponse(version: index.version, albums: Array(matches.prefix(count)))
        }
    }

    /// spine＝縮圖；detail＝原檔原樣分塊（CR-018，需要 peer）；full 不合法
    public func artwork(_ request: ArtworkRequest, peer: UUID? = nil) async -> Result<ArtworkResponse, ErrorCode> {
        guard request.isValid, request.size != .detail || peer != nil else { return .failure(.invalidRequest) }
        let index: CatalogIndex
        switch await currentIndex() {
        case .success(let loaded): index = loaded
        case .failure(let code): return .failure(code)
        }
        func reply(_ outcome: ArtworkOutcome, token: String?, jpeg: Data? = nil) -> Result<ArtworkResponse, ErrorCode> {
            .success(ArtworkResponse(albumID: request.albumID, size: request.size, outcome: outcome, artworkToken: token, jpeg: jpeg))
        }
        guard let position = index.position[request.albumID] else { return reply(.stale, token: nil) }
        let current = index.albums[position].artworkToken
        guard current == request.artworkToken else { return reply(.stale, token: current) }
        guard let trackID = index.representative[request.albumID] else { return reply(.none, token: current) }
        if request.size == .detail, let peer { return await detail(request, peer: peer, trackID: trackID, token: current) }
        let key = ArtworkKey(albumID: request.albumID, token: request.artworkToken, size: request.size)
        if let cached = artworkCache.value(for: key) { return reply(.image, token: current, jpeg: cached) }
        let source = self.source
        let jpeg = await limiter.run(key) {
            guard let original = await source.artworkData(trackID: trackID), !Task.isCancelled else { return nil }
            return ArtworkRenderer.spineJPEG(from: original)
        }
        guard let jpeg else { return reply(.none, token: current) }
        artworkCache.set(key, jpeg, cost: jpeg.count)
        return reply(.image, token: current, jpeg: jpeg)
    }

    /// 該 peer 的連線結束或被新連線取代：釋放它的 detail 傳輸與世代紀錄（RelayHost 呼叫）。
    /// 新連線也要釋放：iPad App 重開後世代從頭算，舊紀錄留著會把新請求一直當成遲到的舊請求（simcodex R2）
    public func releasePeer(_ peer: UUID) {
        detailTransfers.peerGone(peer)
    }

    // MARK: detail（CR-018）

    private func detail(_ request: ArtworkRequest, peer: UUID, trackID: UInt64, token: String?) async
        -> Result<ArtworkResponse, ErrorCode> {
        func reply(_ outcome: ArtworkOutcome, _ part: ArtworkDetailPart? = nil) -> Result<ArtworkResponse, ErrorCode> {
            .success(ArtworkResponse(albumID: request.albumID, size: .detail, outcome: outcome, artworkToken: token, jpeg: nil,
                                     detail: part))
        }
        guard let index = request.part, let generation = request.generation else { return .failure(.invalidRequest) }
        let key = DetailTransferBook.Key(albumID: request.albumID, token: request.artworkToken)
        let now = await clock.now()
        if index > 0 {
            guard let digest = request.digest,
                  let part = detailTransfers.part(peer: peer, key: key, digest: digest, generation: generation, index: index, now: now)
            else { return reply(.restart) }
            return reply(.image, part)
        }
        guard let original = await originalArtwork(albumID: request.albumID, token: request.artworkToken, trackID: trackID),
              let mime = ArtworkMime.sniff(original) else { return reply(.none) }
        guard original.count <= DetailArtworkLimits.maxTotalBytes else { return reply(.tooLarge) }
        let payload = DetailTransferBook.Payload(data: original, digest: original.sha256Hex, mime: mime)
        switch detailTransfers.begin(peer: peer, key: key, generation: generation, payload: payload, now: await clock.now()) {
        case .started(let part): return reply(.image, part)
        case .restart: return reply(.restart)
        case .busy: return .failure(.busy)
        }
    }

    /// 原檔位元組：只做同鍵合併，不進共用封面 LRU（最大 6 MiB，十來張就把縮圖擠光；傳輸本身已持有這份 Data）
    private func originalArtwork(albumID: String, token: String, trackID: UInt64) async -> Data? {
        let source = self.source
        return await limiter.run(ArtworkKey(albumID: albumID, token: token, size: .detail), { () -> Data? in
            guard !Task.isCancelled else { return nil }
            return await source.artworkData(trackID: trackID)
        })
    }

    // MARK: 載入

    private func currentIndex() async -> Result<CatalogIndex, ErrorCode> {
        if let index { return .success(index) }
        if let loadTask { return await loadTask.value.mapError { _ in .libraryUnavailable } }
        if let lastFailureAt {
            let now = await clock.now()
            // 等待時鐘期間可能已有別的請求開始載入或載入完成
            if let index { return .success(index) }
            if let loadTask { return await loadTask.value.mapError { _ in .libraryUnavailable } }
            if now.timeIntervalSince(lastFailureAt) < Self.retryInterval { return .failure(.libraryUnavailable) }
        }
        state = .loading
        let task = Task { [source] in await Self.build(from: source) }
        loadTask = task
        let result = await task.value
        loadTask = nil
        switch result {
        case .success(let built):
            if index == nil { install(built) }
            lastFailureAt = nil
            setAvailable(true)
            return .success(index ?? built)
        case .failure(.unavailable(let code)):
            lastFailureAt = await clock.now()
            state = .unavailable(code: code)
            setAvailable(false)
            return .failure(.libraryUnavailable)
        }
    }

    private static func build(from source: any CatalogSource) async -> Result<CatalogIndex, CatalogSourceError> {
        do {
            return .success(CatalogIndexBuilder.build(try await source.load()))
        } catch {
            return .failure(error)
        }
    }

    private func install(_ built: CatalogIndex) {
        index = built
        state = .ready(version: built.version)
        let live = Set(built.albums.compactMap(\.artworkToken))
        artworkCache.removeAll { !live.contains($0.token) }
    }

    // MARK: 週期重建

    /// 已連線 iPad 數 0→1 時呼叫；重複呼叫只保留一個 watcher
    public func startWatching() {
        guard watcher == nil else { return }
        watchGeneration += 1
        let generation = watchGeneration, clock = self.clock, interval = rebuildInterval
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                do { try await clock.sleep(seconds: interval) } catch { return }
                await self?.rebuild(generation)
            }
        }
    }

    /// 已連線 iPad 數 1→0 時呼叫；進行中的重建結果之後到達也會被丟棄
    public func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watchGeneration += 1
    }

    private func rebuild(_ generation: Int) async {
        // 還沒有請求讀過曲庫就不讀（H-31 草稿）；首次載入進行中時不重疊
        guard generation == watchGeneration, let current = index, loadTask == nil else { return }
        let load: CatalogLoad
        do {
            load = try await source.load()
        } catch {
            // 已載入後讀不到（權限被收回、reloadData 失敗）：不再供應舊資料，轉為讀不到並通知（Codex 第 2 輪 P2）；
            // 之後的請求走 currentIndex 的重試節流，恢復時重新載入
            guard generation == watchGeneration else { return }
            index = nil
            lastFailureAt = await clock.now()
            if case .unavailable(let code) = error { state = .unavailable(code: code) }
            setAvailable(false)
            return
        }
        // 未變動是常態：先只算版本，相同就不建搜尋語料、不排序（simplify 效率 #2）
        guard generation == watchGeneration, CatalogIndexBuilder.version(of: load) != current.version else { return }
        let built = CatalogIndexBuilder.build(load)
        install(built)
        onChange(built.version)
    }
}
#endif
