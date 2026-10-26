import Foundation
import RemoteProtocol
import RemoteTransport

/// iPad 對 Mac 曲庫的非同步介面（sprint-3-detail.md §4.6；外部邊界：protocol＋替身）
protocol EchoClient: Sendable {
    func page(cursor: String?) async throws(EchoRequestError) -> CatalogPageResponse
    func search(_ query: String) async throws(EchoRequestError) -> CatalogSearchResponse
    func artwork(albumID: String, token: String) async throws(EchoRequestError) -> ArtworkResponse
    /// Mac 推來的曲庫新版本（event.catalogChanged）；連線結束時串流結束
    func catalogChanges() -> AsyncStream<String>
    #if DEBUG
    /// D2 量測回條（§4.12）：最小的讀取請求，帶指定的請求 ID；Mac 以它的到達時間當「iPad 收到事件」的上界
    func measurementReceipt(id: UUID) async
    #endif
}

#if DEBUG
extension EchoClient {
    func measurementReceipt(id: UUID) async {}
}
#endif

/// iPad 對 Mac 播放的非同步介面（sprint-4-detail.md §4.3、§4.8；外部邊界：protocol＋替身）。
/// 逾時依 kind 由協定決定（受管指令 95 s，其餘 10 s）
protocol PlaybackClient: Sendable {
    func albumTracks(albumID: String, cursor: String?) async throws(EchoRequestError) -> AlbumTracksResponse
    func play(trackID: String, albumID: String) async throws(EchoRequestError) -> PlayResult
    func toggle() async throws(EchoRequestError) -> ControlResult
    func next() async throws(EchoRequestError) -> ControlResult
    func previous() async throws(EchoRequestError) -> ControlResult
    /// CR-030：以目前曲觸發 Genius
    func genius() async throws(EchoRequestError) -> ControlResult
    func seek(trackID: String, seconds: Double) async throws(EchoRequestError) -> ControlResult
    func outputs() async throws(EchoRequestError) -> OutputListResponse
    func setOutputs(_ deviceIDs: [String]) async throws(EchoRequestError) -> OutputListResponse
    /// Mac 推來的播放狀態（event.playback）；連線結束時串流結束
    func playbackEvents() -> AsyncStream<PlaybackEvent>
}

/// LiveEchoClient 需要的傳輸能力（正式＝ClientSession；測試＝替身）
protocol EchoRequesting: Sendable {
    /// `id`：請求 ID（量測時由呼叫端指定，見 measurementReceipt）
    func request<Request: Encodable, Response: Decodable>(_ kind: MessageKind, _ body: Request, as type: Response.Type,
                                                         timeout: TimeInterval?, id: UUID) async throws(EchoRequestError) -> Response
    /// Mac 推送的事件；單一消費者串流，只取一次（由 EventFanout 分流）
    func inboundEvents() -> AsyncStream<InboundEvent>
}

extension EchoRequesting {
    func request<Request: Encodable, Response: Decodable>(_ kind: MessageKind, _ body: Request, as type: Response.Type,
                                                         timeout: TimeInterval?) async throws(EchoRequestError) -> Response {
        try await request(kind, body, as: type, timeout: timeout, id: UUID())
    }
}

extension ClientSession: EchoRequesting {
    func inboundEvents() -> AsyncStream<InboundEvent> { events }
}

/// 把一條事件串流分成曲庫版本與播放狀態兩條（各自單一消費者）；解不開的事件略過，來源結束時兩條一起結束
final class EventFanout: Sendable {
    let catalogVersions: AsyncStream<String>
    let playback: AsyncStream<PlaybackEvent>

    init(_ events: AsyncStream<InboundEvent>) {
        let (versions, versionSink) = AsyncStream<String>.makeStream()
        let (playback, playbackSink) = AsyncStream<PlaybackEvent>.makeStream()
        catalogVersions = versions
        self.playback = playback
        Task {
            for await event in events {
                switch event.kind {
                case .eventCatalogChanged:
                    if let body = event.body(as: CatalogChangedEvent.self) { versionSink.yield(body.version) }
                case .eventPlayback:
                    if let body = event.body(as: PlaybackEvent.self) { playbackSink.yield(body) }
                default:
                    break
                }
            }
            versionSink.finish()
            playbackSink.finish()
        }
    }
}

/// 無 body 的請求（toggle／next／previous／output.list）
private struct EmptyBody: Codable {}

struct LiveEchoClient: EchoClient, PlaybackClient, DetailArtworkRequesting {
    let requester: any EchoRequesting
    var timeout: TimeInterval = ClientSession.defaultRequestTimeout
    private let fanout: EventFanout

    /// 每條連線建一個（事件串流只能被分流一次）
    init(requester: any EchoRequesting) {
        self.requester = requester
        fanout = EventFanout(requester.inboundEvents())
    }

    func page(cursor: String?) async throws(EchoRequestError) -> CatalogPageResponse {
        try await requester.request(.catalogPage, CatalogPageRequest(cursor: cursor, limit: CatalogLimits.defaultPageSize),
                                    as: CatalogPageResponse.self, timeout: timeout)
    }

    func search(_ query: String) async throws(EchoRequestError) -> CatalogSearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await requester.request(.catalogSearch, CatalogSearchRequest(query: trimmed, limit: CatalogLimits.defaultSearchResults),
                                           as: CatalogSearchResponse.self, timeout: timeout)
    }

    func artwork(albumID: String, token: String) async throws(EchoRequestError) -> ArtworkResponse {
        let response = try await requester.request(.artworkGet, ArtworkRequest(albumID: albumID, size: .spine, artworkToken: token),
                                                   as: ArtworkResponse.self, timeout: timeout)
        guard response.isValid else { throw .invalidResponse }
        return response
    }

    func catalogChanges() -> AsyncStream<String> { fanout.catalogVersions }

    /// detail 原檔的一塊（CR-018）；合法性由回覆的 isValid 把關，跨塊核對在 DetailArtworkFetcher
    func artworkDetail(albumID: String, token: String, part: Int, digest: String?, generation: UInt64)
        async throws(EchoRequestError) -> ArtworkResponse {
        let request = ArtworkRequest(albumID: albumID, size: .detail, artworkToken: token, part: part, digest: digest, generation: generation)
        let response = try await requester.request(.artworkGet, request, as: ArtworkResponse.self, timeout: timeout)
        guard response.isValid else { throw .invalidResponse }
        return response
    }

    #if DEBUG
    func measurementReceipt(id: UUID) async {
        _ = try? await requester.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 1), as: CatalogPageResponse.self,
                                         timeout: timeout, id: id)
    }
    #endif

    // MARK: 播放（逾時傳 nil＝依 kind 查 PlaybackLimits.clientTimeout）

    func albumTracks(albumID: String, cursor: String?) async throws(EchoRequestError) -> AlbumTracksResponse {
        try await requester.request(.albumTracks, AlbumTracksRequest(albumID: albumID, cursor: cursor),
                                    as: AlbumTracksResponse.self, timeout: nil)
    }

    func play(trackID: String, albumID: String) async throws(EchoRequestError) -> PlayResult {
        let result = try await requester.request(.playTrack, PlayTrackRequest(trackID: trackID, albumID: albumID),
                                                 as: PlayResult.self, timeout: nil)
        guard result.isValid else { throw .invalidResponse }
        return result
    }

    func toggle() async throws(EchoRequestError) -> ControlResult { try await control(.playToggle, EmptyBody()) }
    func next() async throws(EchoRequestError) -> ControlResult { try await control(.playNext, EmptyBody()) }
    func previous() async throws(EchoRequestError) -> ControlResult { try await control(.playPrevious, EmptyBody()) }
    func genius() async throws(EchoRequestError) -> ControlResult { try await control(.playGenius, EmptyBody()) }

    func seek(trackID: String, seconds: Double) async throws(EchoRequestError) -> ControlResult {
        try await control(.playSeek, SeekRequest(trackID: trackID, seconds: seconds))
    }

    func outputs() async throws(EchoRequestError) -> OutputListResponse {
        try await requester.request(.outputList, EmptyBody(), as: OutputListResponse.self, timeout: nil)
    }

    func setOutputs(_ deviceIDs: [String]) async throws(EchoRequestError) -> OutputListResponse {
        try await requester.request(.outputSet, OutputSetRequest(deviceIDs: deviceIDs), as: OutputListResponse.self, timeout: nil)
    }

    func playbackEvents() -> AsyncStream<PlaybackEvent> { fanout.playback }

    private func control<Body: Encodable>(_ kind: MessageKind, _ body: Body) async throws(EchoRequestError) -> ControlResult {
        try await requester.request(kind, body, as: ControlResult.self, timeout: nil)
    }
}
