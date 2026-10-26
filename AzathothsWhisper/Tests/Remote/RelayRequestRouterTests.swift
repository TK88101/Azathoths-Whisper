import Foundation
import MusicRemoteBridge
import RemoteProtocol
import RemoteTransport
import Testing

@testable import AzathothsWhisper

// S3 T8（sprint-3-detail.md §4.5）：RelayRequestRouter 只做「解 body → 呼叫曲庫 → 編回覆」，不含業務邏輯

final class FakeCatalogResponder: CatalogResponding, @unchecked Sendable {
    let lock = NSLock()
    var pageResult: Result<CatalogPageResponse, ErrorCode> = .success(CatalogPageResponse(version: "00000000000000aa", total: 0, albums: [], nextCursor: nil))
    var searchResult: Result<CatalogSearchResponse, ErrorCode> = .success(CatalogSearchResponse(version: "00000000000000aa", albums: []))
    var artworkResult: Result<ArtworkResponse, ErrorCode> = .failure(.invalidRequest)
    var seenQueries: [String] = []
    var seenAlbums: [String] = []
    var albumSongsResult: Result<AlbumTracksResponse, ErrorCode> = .success(
        AlbumTracksResponse(albumID: "00000000000000bb", version: "00000000000000aa", songs: [], nextCursor: nil, contextPlayable: true))

    func page(_ request: CatalogPageRequest) async -> Result<CatalogPageResponse, ErrorCode> { lock.withLock { pageResult } }
    func search(_ request: CatalogSearchRequest) async -> Result<CatalogSearchResponse, ErrorCode> {
        lock.withLock { seenQueries.append(request.query); return searchResult }
    }
    var seenArtworkPeers: [UUID?] = []
    func artwork(_ request: ArtworkRequest, peer: UUID?) async -> Result<ArtworkResponse, ErrorCode> {
        lock.withLock { seenArtworkPeers.append(peer); return artworkResult }
    }
    func albumSongs(_ request: AlbumTracksRequest) async -> Result<AlbumTracksResponse, ErrorCode> {
        lock.withLock { seenAlbums.append(request.albumID); return albumSongsResult }
    }
}

private let readback = RemoteProtocol.PlaybackEvent(availability: .ok, trackID: "0000000000000001", albumID: nil, state: .paused,
                                      position: 3, duration: 100, sampledAt: 1)

/// S4 T9：播放服務的替身——記下收到的請求與連線，回設定好的結果
final class FakePlaybackResponder: PlaybackResponding, @unchecked Sendable {
    let lock = NSLock()
    var managed: ManagedOutcome = .control(ControlResult(outcome: .applied, playback: readback))
    var control: Result<ControlResult, ErrorCode> = .success(ControlResult(outcome: .applied, playback: readback))
    var outputsResult: Result<OutputListResponse, ErrorCode> = .success(OutputListResponse(devices: []))
    var calls: [String] = []
    var connections: [UUID] = []

    private func log(_ call: String, _ connection: UUID? = nil) {
        lock.withLock { calls.append(call); if let connection { connections.append(connection) } }
    }

    func play(_ request: PlayTrackRequest, connection: UUID) async -> ManagedOutcome {
        log("play:\(request.trackID)", connection); return lock.withLock { managed }
    }
    func next(connection: UUID) async -> ManagedOutcome { log("next", connection); return lock.withLock { managed } }
    func previous(connection: UUID) async -> ManagedOutcome { log("previous", connection); return lock.withLock { managed } }
    func genius(connection: UUID) async -> ManagedOutcome { log("genius", connection); return lock.withLock { managed } }
    func toggle() async -> Result<ControlResult, ErrorCode> { log("toggle"); return lock.withLock { control } }
    func seek(_ request: SeekRequest) async -> Result<ControlResult, ErrorCode> {
        log("seek:\(request.seconds)"); return lock.withLock { control }
    }
    func outputs() async -> Result<OutputListResponse, ErrorCode> { log("outputs"); return lock.withLock { outputsResult } }
    func setOutputs(_ request: OutputSetRequest) async -> Result<OutputListResponse, ErrorCode> {
        log("setOutputs:\(request.deviceIDs.count)"); return lock.withLock { outputsResult }
    }
    var recorded: [String] { lock.withLock { calls } }
}

private struct Empty: Codable {}

@Suite("RelayRequestRouter")
struct RelayRequestRouterTests {
    let responder = FakeCatalogResponder()
    let playback = FakePlaybackResponder()

    var router: RelayRequestRouter { RelayRequestRouter(catalog: responder, playback: playback) }

    private func request(_ kind: MessageKind, _ body: some Encodable, connection: UUID = UUID()) -> InboundRequest {
        InboundRequest(peerID: UUID(), id: UUID(), kind: kind, message: Envelope.encode(kind, body), connectionID: connection)
    }

    private func decoded<Body: Decodable>(_ reply: OutboundReply, as type: Body.Type) -> Body? {
        guard case .message(let data) = reply else { return nil }
        return InboundRequest(peerID: UUID(), id: UUID(), kind: .catalogPage, message: data).body(as: type)
    }

    private func replyKind(_ reply: OutboundReply) -> MessageKind? {
        guard case .message(let data) = reply else { return nil }
        return try? EnvelopeHeader.decode(data).get().kind
    }

    private func errorCode(_ reply: OutboundReply) -> ErrorCode? {
        guard case .error(let code) = reply else { return nil }
        return code
    }

    @Test func pageIsForwardedAndEncodedWithSameKind() async {
        let reply = await router.handle(request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 10)))
        #expect(decoded(reply, as: CatalogPageResponse.self)?.version == "00000000000000aa")
    }

    /// CR-018：artwork.get 把請求的 peer 交給曲庫（detail 傳輸依 peer 計名額與世代）
    @Test func artworkIsForwardedWithPeer() async {
        let peer = UUID()
        let body = ArtworkRequest(albumID: "00000000000000bb", size: .spine, artworkToken: "00000000000000aa")
        _ = await router.handle(InboundRequest(peerID: peer, id: UUID(), kind: .artworkGet, message: Envelope.encode(.artworkGet, body)))
        #expect(responder.lock.withLock { responder.seenArtworkPeers } == [peer])
    }

    @Test func searchIsForwarded() async {
        _ = await router.handle(request(.catalogSearch, CatalogSearchRequest(query: "Night", limit: 5)))
        #expect(responder.seenQueries == ["Night"])
    }

    @Test func serviceErrorBecomesErrorReply() async {
        responder.lock.withLock { responder.pageResult = .failure(.libraryUnavailable) }
        let reply = await router.handle(request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 10)))
        guard case .error(let code) = reply else { Issue.record("\(reply)"); return }
        #expect(code == .libraryUnavailable)
    }

    @Test func undecodableBodyIsInvalidRequest() async {
        let reply = await router.handle(request(.catalogPage, ["unexpected": 1]))
        guard case .error(let code) = reply else { Issue.record("\(reply)"); return }
        #expect(code == .invalidRequest)
    }

    /// S4 T4（CR-013(f)）：album.tracks 已由 S6 前移到 S4，轉給曲庫服務
    @Test func albumTracksIsForwardedAndEncodedWithSameKind() async {
        let reply = await router.handle(request(.albumTracks, AlbumTracksRequest(albumID: "00000000000000bb", cursor: nil)))
        #expect(decoded(reply, as: AlbumTracksResponse.self)?.albumID == "00000000000000bb")
        #expect(responder.seenAlbums == ["00000000000000bb"])
    }

    // MARK: S4 T9 播放控制（每 kind 一正一反）

    @Test func playTrackRepliesAsPlayResultAndPassesConnection() async {
        let connection = UUID()
        playback.lock.withLock { playback.managed = .play(PlayResult(outcome: .verified, reason: nil)) }
        let reply = await router.handle(request(.playTrack, PlayTrackRequest(trackID: "0000000000000002", albumID: "00000000000000bb"),
                                                connection: connection))
        #expect(replyKind(reply) == .playResult)
        #expect(decoded(reply, as: PlayResult.self) == PlayResult(outcome: .verified, reason: nil))
        #expect(playback.connections == [connection])
    }

    @Test func playTrackWithUndecodableBodyIsInvalidAndNotForwarded() async {
        #expect(errorCode(await router.handle(request(.playTrack, ["x": 1]))) == .invalidRequest)
        #expect(playback.recorded.isEmpty)
    }

    @Test(arguments: [MessageKind.playNext, .playPrevious])
    func stepsReplyControlResultWithSameKind(kind: MessageKind) async {
        let connection = UUID()
        let reply = await router.handle(request(kind, Empty(), connection: connection))
        #expect(replyKind(reply) == kind)
        #expect(decoded(reply, as: ControlResult.self)?.playback == readback)
        #expect(playback.recorded == [kind == .playNext ? "next" : "previous"] && playback.connections == [connection])
    }

    /// CR-030：Genius 與 next／previous 同形（受管、ControlResult、同 kind 回）；沒按的原因走錯誤回覆
    @Test func geniusRepliesControlResultWithSameKind() async {
        let connection = UUID()
        let reply = await router.handle(request(.playGenius, Empty(), connection: connection))
        #expect(replyKind(reply) == .playGenius)
        #expect(decoded(reply, as: ControlResult.self)?.playback == readback)
        #expect(playback.recorded == ["genius"] && playback.connections == [connection])
    }

    @Test(arguments: [ErrorCode.accessibilityDenied, .notApplied, .busy, .musicNotRunning])
    func geniusErrorsBecomeErrorReplies(code: ErrorCode) async {
        playback.lock.withLock { playback.managed = .error(code) }
        #expect(errorCode(await router.handle(request(.playGenius, Empty()))) == code)
    }

    @Test(arguments: [ErrorCode.busy, .superseded, .musicNotRunning])
    func managedErrorsBecomeErrorReplies(code: ErrorCode) async {
        playback.lock.withLock { playback.managed = .error(code) }
        #expect(errorCode(await router.handle(request(.playNext, Empty()))) == code)
    }

    /// 連線已不在：回覆本來就送不出去；仍回一個錯誤值（busy）而不是假裝成功
    @Test func droppedManagedCommandIsNotReportedAsSuccess() async {
        playback.lock.withLock { playback.managed = .dropped }
        #expect(errorCode(await router.handle(request(.playPrevious, Empty()))) == .busy)
    }

    @Test func toggleRepliesAndForwardsErrors() async {
        #expect(decoded(await router.handle(request(.playToggle, Empty())), as: ControlResult.self)?.outcome == .applied)
        playback.lock.withLock { playback.control = .failure(.musicNotAuthorized) }
        #expect(errorCode(await router.handle(request(.playToggle, Empty()))) == .musicNotAuthorized)
    }

    @Test func seekIsForwardedAndUndecodableSeekIsInvalid() async {
        let reply = await router.handle(request(.playSeek, SeekRequest(trackID: "0000000000000001", seconds: 12)))
        #expect(replyKind(reply) == .playSeek && playback.recorded == ["seek:12.0"])
        #expect(errorCode(await router.handle(request(.playSeek, ["seconds": "x"]))) == .invalidRequest)
        #expect(playback.recorded == ["seek:12.0"])
    }

    @Test func outputListAndSetAreForwarded() async {
        #expect(replyKind(await router.handle(request(.outputList, Empty()))) == .outputList)
        let set = await router.handle(request(.outputSet, OutputSetRequest(deviceIDs: ["00000000000000c1"])))
        #expect(replyKind(set) == .outputSet)
        #expect(errorCode(await router.handle(request(.outputSet, ["deviceIDs": 1]))) == .invalidRequest)
        #expect(playback.recorded == ["outputs", "setOutputs:1"])
    }

    /// Mac 才送的 kind 由 iPad 送來：不轉給任何服務
    @Test(arguments: [MessageKind.playResult, .eventPlayback, .eventCatalogChanged])
    func macOnlyKindsAreInvalidRequest(kind: MessageKind) async {
        #expect(errorCode(await router.handle(request(kind, ["x": 1]))) == .invalidRequest)
        #expect(playback.recorded.isEmpty)
    }
}

#if DEBUG
// S4 #4-1 D2（thecure 收斂）：量測紀錄只含 kind、catalog.page 的 limit、請求 ID、連線 ID——不含任何內容
@Suite("RelayMeasureLine")
struct RelayMeasureLineTests {
    @Test func catalogPageCarriesLimitAndIDs() {
        let id = UUID(), connection = UUID()
        let request = InboundRequest(peerID: UUID(), id: id, kind: .catalogPage,
                                     message: Envelope.encode(.catalogPage, CatalogPageRequest(cursor: nil, limit: 1)), connectionID: connection)
        #expect(RelayMeasureLine.format(request) == "arrival kind=catalog.page limit=1 id=\(id.uuidString) conn=\(connection.uuidString)")
    }

    /// #4-1 診斷：點歌結果只記 outcome 與原因代碼
    @Test func playResultLineCarriesOutcomeAndReasonOnly() {
        let id = UUID()
        #expect(RelayMeasureLine.result(PlayResult(outcome: .indeterminate, reason: .manualChange), id: id)
                == "result kind=play.track outcome=indeterminate reason=manualChange id=\(id.uuidString)")
        #expect(RelayMeasureLine.result(PlayResult(outcome: .verified, reason: nil), id: id)
                == "result kind=play.track outcome=verified reason=- id=\(id.uuidString)")
    }

    /// #4-1 N-01 診斷：上一首／下一首的 Mac 端耗時（到達 → 回覆，毫秒取整）；只有 outcome 與數字
    @Test func controlResultLineCarriesOutcomeAndMacSideMilliseconds() {
        let id = UUID()
        #expect(RelayMeasureLine.control(.playPrevious, outcome: .applied, milliseconds: 312.6, id: id)
                == "result kind=play.previous outcome=applied ms=313 id=\(id.uuidString)")
    }

    @Test func otherKindsHaveNoLimitAndNoBodyContent() {
        let id = UUID(), connection = UUID()
        let request = InboundRequest(peerID: UUID(), id: id, kind: .playSeek,
                                     message: Envelope.encode(.playSeek, SeekRequest(trackID: "0000000000000001", seconds: 12)),
                                     connectionID: connection)
        let line = RelayMeasureLine.format(request)
        #expect(line == "arrival kind=play.seek id=\(id.uuidString) conn=\(connection.uuidString)")
        #expect(!line.contains("0000000000000001"))
    }
}
#endif
