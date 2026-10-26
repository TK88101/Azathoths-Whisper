import Foundation
import MusicRemoteBridge
import RemoteProtocol
import RemoteTransport

// 曲庫的接線（sprint-3-detail.md §4.5、§4.7）。請求的轉接在 RelayRequestRouter；
// 讀曲庫、分頁、封面都在 EchoKit 的 MusicRemoteBridge。中繼關閉時這裡不會被呼叫（H-31 草稿）。

/// RelayHost 看到的曲庫邊界（protocol＋替身）
protocol RelayCatalog: AnyObject, Sendable {
    /// 已連線 iPad 數 0→1 時呼叫
    func startWatching() async
    /// 已連線 iPad 數 1→0 時呼叫
    func stopWatching() async
    /// peer 的連線結束或被新連線取代：釋放該 peer 的 detail 封面傳輸與世代紀錄（CR-018）
    func releasePeer(_ peer: UUID) async
    /// changed：曲庫換版（RelayHost 轉成 broadcast）；availability：曲庫讀得到／讀不到，只在翻轉時呼叫（設定頁顯示）。nil＝解除
    func setHandlers(changed: (@Sendable (String) -> Void)?, availability: (@Sendable (Bool) -> Void)?)
}

/// Router 需要的三個請求（CatalogService 實作；測試用替身）
protocol CatalogResponding: Sendable {
    func page(_ request: CatalogPageRequest) async -> Result<CatalogPageResponse, ErrorCode>
    func search(_ request: CatalogSearchRequest) async -> Result<CatalogSearchResponse, ErrorCode>
    /// peer：detail（原檔分塊，CR-018）依 peer 計傳輸名額與世代；spine 不用
    func artwork(_ request: ArtworkRequest, peer: UUID?) async -> Result<ArtworkResponse, ErrorCode>
    func albumSongs(_ request: AlbumTracksRequest) async -> Result<AlbumTracksResponse, ErrorCode>
}

extension CatalogService: CatalogResponding {}

/// 正式版：LibraryReader（唯一碰 ITLibrary）→ CatalogService → Router
final class LiveRelayCatalog: RelayCatalog {
    private struct Handlers: Sendable {
        var changed: (@Sendable (String) -> Void)?
        var availability: (@Sendable (Bool) -> Void)?
    }

    private let handlers = Locked(Handlers())
    /// Router 與播放服務（點歌計畫、trackID → albumID）共用同一個曲庫服務
    let service: CatalogService

    init(source: any CatalogSource = LibraryReader()) {
        let handlers = self.handlers
        // 可讀與否由 CatalogService 在狀態翻轉時通知（不再由每個回覆反推）
        let service = CatalogService(source: source, onChange: { version in handlers.withLock { $0.changed }?(version) },
                                     onAvailability: { ok in handlers.withLock { $0.availability }?(ok) })
        self.service = service
    }

    func startWatching() async { await service.startWatching() }
    func stopWatching() async { await service.stopWatching() }
    func releasePeer(_ peer: UUID) async { await service.releasePeer(peer) }

    func setHandlers(changed: (@Sendable (String) -> Void)?, availability: (@Sendable (Bool) -> Void)?) {
        handlers.withLock { $0 = Handlers(changed: changed, availability: availability) }
    }
}

/// 單元／UI 測試與預設：什麼都不做、不碰曲庫
final class InertRelayCatalog: RelayCatalog {
    func startWatching() async {}
    func stopWatching() async {}
    func releasePeer(_ peer: UUID) async {}
    func setHandlers(changed: (@Sendable (String) -> Void)?, availability: (@Sendable (Bool) -> Void)?) {}
}
