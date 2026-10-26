// RemoteProtocol v1 的訊息種類（基本設計 §4.3）：封閉列舉，未知值一律拒絕。
// 配對與 session 的 kind 由 CR-010 加入（sprint-2-detail.md §4.2）。

public enum ProtocolVersion {
    public static let current = 1
}

public enum MessageKind: String, Codable, Sendable, CaseIterable {
    case catalogPage = "catalog.page"
    case catalogSearch = "catalog.search"
    case albumTracks = "album.tracks"
    case artworkGet = "artwork.get"
    case playTrack = "play.track"
    case playResult = "play.result"
    case playToggle = "play.toggle"
    case playNext = "play.next"
    case playPrevious = "play.previous"
    case playSeek = "play.seek"
    /// CR-030：以目前曲為種子觸發 Music 的 Genius 隨機播放（空 body；回覆 ControlResult）
    case playGenius = "play.genius"
    case outputList = "output.list"
    case outputSet = "output.set"
    case eventPlayback = "event.playback"
    case eventCatalogChanged = "event.catalogChanged"
    case pairProof = "pair.proof"
    case pairPending = "pair.pending"
    case pairResult = "pair.result"
    case sessionHello = "session.hello"
    case error
}

extension MessageKind {
    /// 回覆所用的 kind：`play.track` 的結果以 `play.result` 回（設計 §4.3、sprint-4-detail.md §3），其餘同 kind
    public var replyKind: MessageKind { self == .playTrack ? .playResult : self }
}
