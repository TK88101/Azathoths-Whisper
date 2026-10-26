import Foundation
import MusicRemoteBridge
import RemoteProtocol
import RemoteTransport

// 業務請求的分派（sprint-3-detail.md §4.5、sprint-4-detail.md §4.3）。這裡只轉接：解 body → 呼叫服務 → 編回覆；
// 曲庫與播放的邏輯都在 EchoKit 的 MusicRemoteBridge。中繼關閉時 TransportServer 不存在，這裡不會被呼叫。

/// Router 需要的播放操作（PlaybackService 實作；測試用替身）
protocol PlaybackResponding: Sendable {
    func play(_ request: PlayTrackRequest, connection: UUID) async -> ManagedOutcome
    func next(connection: UUID) async -> ManagedOutcome
    func previous(connection: UUID) async -> ManagedOutcome
    func genius(connection: UUID) async -> ManagedOutcome
    func toggle() async -> Result<ControlResult, ErrorCode>
    func seek(_ request: SeekRequest) async -> Result<ControlResult, ErrorCode>
    func outputs() async -> Result<OutputListResponse, ErrorCode>
    func setOutputs(_ request: OutputSetRequest) async -> Result<OutputListResponse, ErrorCode>
}

extension PlaybackService: PlaybackResponding {}

struct RelayRequestRouter: RequestHandling {
    let catalog: any CatalogResponding
    let playback: any PlaybackResponding

    /// 量測（sprint-4-detail.md §4.12 D2）：請求到達時記一筆，時間取 OSLog 自帶的時間戳，由 Scripts/d2_pair.py 與 iPad 的回條紀錄
    /// 以請求 ID 逐筆對應。內容見 RelayMeasureLine；經 RelayTrace，Release 不含
    func handle(_ request: InboundRequest) async -> OutboundReply {
        #if DEBUG
        RelayTrace.info(RelayMeasureLine.format(request))
        #endif
        switch request.kind {
        case .catalogPage:
            guard let body = request.body(as: CatalogPageRequest.self) else { return .error(.invalidRequest) }
            return reply(request, await catalog.page(body))
        case .catalogSearch:
            guard let body = request.body(as: CatalogSearchRequest.self) else { return .error(.invalidRequest) }
            return reply(request, await catalog.search(body))
        case .artworkGet:
            guard let body = request.body(as: ArtworkRequest.self) else { return .error(.invalidRequest) }
            return reply(request, await catalog.artwork(body, peer: request.peerID))
        case .albumTracks:
            // S4 控制用極簡曲目選擇器（CR-013(f)）
            guard let body = request.body(as: AlbumTracksRequest.self) else { return .error(.invalidRequest) }
            return reply(request, await catalog.albumSongs(body))
        case .playTrack:
            guard let body = request.body(as: PlayTrackRequest.self) else { return .error(.invalidRequest) }
            return managed(request, await playback.play(body, connection: request.connectionID))
        case .playNext:
            let started = ContinuousClock.now
            return managed(request, await playback.next(connection: request.connectionID), since: started)
        case .playPrevious:
            let started = ContinuousClock.now
            return managed(request, await playback.previous(connection: request.connectionID), since: started)
        case .playGenius:
            // CR-030：Azathoth 本體不碰 AX；按下在 EchoKit 的 GeniusMenu
            let started = ContinuousClock.now
            return managed(request, await playback.genius(connection: request.connectionID), since: started)
        case .playToggle:
            return reply(request, await playback.toggle())
        case .playSeek:
            guard let body = request.body(as: SeekRequest.self) else { return .error(.invalidRequest) }
            return reply(request, await playback.seek(body))
        case .outputList:
            return reply(request, await playback.outputs())
        case .outputSet:
            guard let body = request.body(as: OutputSetRequest.self) else { return .error(.invalidRequest) }
            return reply(request, await playback.setOutputs(body))
        default:
            return .error(.invalidRequest)
        }
    }

    private func reply<Body: Encodable>(_ request: InboundRequest, _ result: Result<Body, ErrorCode>) -> OutboundReply {
        switch result {
        case .success(let body): request.reply(body)
        case .failure(let code): .error(code)
        }
    }

    /// play.track 以 play.result 回（`reply` 依 kind 決定）；next／previous 回 ControlResult
    private func managed(_ request: InboundRequest, _ outcome: ManagedOutcome, since started: ContinuousClock.Instant? = nil) -> OutboundReply {
        switch outcome {
        case .play(let result):
            #if DEBUG
            RelayTrace.notice(RelayMeasureLine.result(result, id: request.id))
            #endif
            return request.reply(result)
        case .control(let result):
            #if DEBUG
            if let started {
                let ms = (ContinuousClock.now - started).secondsValue * 1000
                RelayTrace.notice(RelayMeasureLine.control(request.kind, outcome: result.outcome, milliseconds: ms, id: request.id))
            }
            #endif
            return request.reply(result)
        case .error(let code): return .error(code)
        // 連線已不在：回覆本來就送不出去；不假裝成功
        case .dropped: return .error(.busy)
        }
    }
}

#if DEBUG
/// 量測紀錄的一行：kind、catalog.page 的 limit（回條＝1，一般清單＝預設頁大小）、請求 ID、連線 ID。不含任何 body 內容、不含 peer
enum RelayMeasureLine {
    static func format(_ request: InboundRequest) -> String {
        let limit = request.kind == .catalogPage ? request.body(as: CatalogPageRequest.self).map { " limit=\($0.limit)" } ?? "" : ""
        return "arrival kind=\(request.kind.rawValue)\(limit) id=\(request.id.uuidString) conn=\(request.connectionID.uuidString)"
    }

    /// 上一首／下一首（#4-1 N-01 診斷）：Mac 端到達 → 回覆的毫秒（含排隊）；只有 outcome 與數字
    static func control(_ kind: MessageKind, outcome: ControlOutcome, milliseconds: Double, id: UUID) -> String {
        "result kind=\(kind.rawValue) outcome=\(outcome.rawValue) ms=\(Int(milliseconds.rounded())) id=\(id.uuidString)"
    }

    /// 點歌結果（#4-1 診斷）：只有 outcome 與原因代碼；notice 等級，事後 log show 查得到
    static func result(_ result: PlayResult, id: UUID) -> String {
        "result kind=play.track outcome=\(result.outcome.rawValue) reason=\(result.reason?.rawValue ?? "-") id=\(id.uuidString)"
    }
}
#endif
