import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// S3 T9（sprint-3-detail.md §4.6）：LiveEchoClient 把三個請求與換版事件對應到 ClientSession
// S4 T11（sprint-4-detail.md §4.3、§4.8）：播放請求、事件分流（一個事件串流 → 曲庫版本＋播放狀態）、逾時表

final class FakeRequester: EchoRequesting, @unchecked Sendable {
    let lock = NSLock()
    var sent: [(MessageKind, Data)] = []
    var timeouts: [TimeInterval?] = []
    var ids: [UUID] = []
    var replies: [MessageKind: Result<Data, EchoRequestError>] = [:]
    let events: AsyncStream<InboundEvent>
    let eventContinuation: AsyncStream<InboundEvent>.Continuation
    private(set) var eventStreamsTaken = 0

    init() { (events, eventContinuation) = AsyncStream.makeStream() }

    func request<Request: Encodable, Response: Decodable>(_ kind: MessageKind, _ body: Request, as type: Response.Type,
                                                         timeout: TimeInterval?, id: UUID) async throws(EchoRequestError) -> Response {
        let reply = lock.withLock { () -> Result<Data, EchoRequestError>? in
            sent.append((kind, try! JSONEncoder().encode(body)))
            timeouts.append(timeout)
            ids.append(id)
            return replies[kind]
        }
        guard let reply else { throw .invalidResponse }
        let data = try reply.get()
        guard let decoded = try? JSONDecoder().decode(type, from: data) else { throw .invalidResponse }
        return decoded
    }

    func inboundEvents() -> AsyncStream<InboundEvent> { lock.withLock { eventStreamsTaken += 1 }; return events }

    func push<Body: Encodable>(_ kind: MessageKind, _ body: Body) {
        eventContinuation.yield(InboundEvent(kind: kind, message: Envelope.encode(kind, body)))
    }

    func reply<Body: Encodable>(_ kind: MessageKind, _ body: Body) {
        lock.withLock { replies[kind] = .success(try! JSONEncoder().encode(body)) }
    }
    func fail(_ kind: MessageKind, _ error: EchoRequestError) { lock.withLock { replies[kind] = .failure(error) } }
    func lastBody<Body: Decodable>(_ type: Body.Type) -> Body? {
        lock.withLock { sent.last.flatMap { try? JSONDecoder().decode(type, from: $0.1) } }
    }
    var kinds: [MessageKind] { lock.withLock { sent.map(\.0) } }
}

struct EchoClientTests {
    let requester = FakeRequester()
    var client: LiveEchoClient { LiveEchoClient(requester: requester) }

    @Test func pageSendsDefaultPageSizeAndCursor() async throws {
        requester.reply(.catalogPage, CatalogPageResponse(version: "00000000000000aa", total: 1, albums: [], nextCursor: nil))
        let page = try await client.page(cursor: "abc")
        #expect(page.version == "00000000000000aa")
        let sent = try #require(requester.lastBody(CatalogPageRequest.self))
        #expect(sent.cursor == "abc" && sent.limit == CatalogLimits.defaultPageSize)
    }

    @Test func searchSendsTrimmedQueryWithDefaultLimit() async throws {
        requester.reply(.catalogSearch, CatalogSearchResponse(version: "00000000000000aa", albums: []))
        _ = try await client.search("  night  ")
        let sent = try #require(requester.lastBody(CatalogSearchRequest.self))
        #expect(sent.query == "night" && sent.limit == CatalogLimits.defaultSearchResults)
    }

    @Test func artworkRequestsSpineWithToken() async throws {
        requester.reply(.artworkGet, ArtworkResponse(albumID: "0123456789abcdef", size: .spine, outcome: .none, artworkToken: nil, jpeg: nil))
        _ = try await client.artwork(albumID: "0123456789abcdef", token: "fedcba9876543210")
        let sent = try #require(requester.lastBody(ArtworkRequest.self))
        #expect(sent.size == .spine && sent.artworkToken == "fedcba9876543210")
    }

    @Test func remoteErrorsPassThrough() async {
        requester.fail(.catalogPage, .remote(.libraryUnavailable))
        await #expect(throws: EchoRequestError.remote(.libraryUnavailable)) { try await client.page(cursor: nil) }
    }

    @Test func malformedArtworkResponseIsRejected() async {
        requester.reply(.artworkGet, ArtworkResponse(albumID: "0123456789abcdef", size: .spine, outcome: .image, artworkToken: nil, jpeg: nil))
        await #expect(throws: EchoRequestError.invalidResponse) {
            try await client.artwork(albumID: "0123456789abcdef", token: "fedcba9876543210")
        }
    }

    @Test func catalogChangesForwardVersions() async {
        let stream = client.catalogChanges()
        requester.push(.eventCatalogChanged, CatalogChangedEvent(version: "00000000000000bb"))
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == "00000000000000bb")
    }

    // MARK: S4 T11

    private static let event = PlaybackEvent(availability: .ok, trackID: "0000000000000001", albumID: "00000000000000bb",
                                             state: .playing, position: 3, duration: 100, sampledAt: 7)

    /// 事件串流只取一次並分給兩邊：曲庫版本與播放狀態互不搶（ClientSession.events 是單一消費者串流）
    @Test func oneEventStreamFeedsBothCatalogAndPlayback() async {
        let live = client
        let versions = live.catalogChanges(), playback = live.playbackEvents()
        requester.push(.eventPlayback, Self.event)
        requester.push(.eventCatalogChanged, CatalogChangedEvent(version: "00000000000000cc"))
        requester.eventContinuation.yield(InboundEvent(kind: .eventPlayback, message: Data("{}".utf8)))   // 解不開：略過
        requester.eventContinuation.finish()
        var collectedVersions: [String] = []
        for await version in versions { collectedVersions.append(version) }
        var collectedEvents: [PlaybackEvent] = []
        for await event in playback { collectedEvents.append(event) }
        #expect(collectedVersions == ["00000000000000cc"] && collectedEvents == [Self.event])
        #expect(requester.eventStreamsTaken == 1)
    }

    @Test func albumTracksSendsAlbumAndCursor() async throws {
        requester.reply(.albumTracks, AlbumTracksResponse(albumID: "00000000000000bb", version: "00000000000000aa", songs: [],
                                                          nextCursor: nil, contextPlayable: true))
        _ = try await client.albumTracks(albumID: "00000000000000bb", cursor: "c1")
        let sent = try #require(requester.lastBody(AlbumTracksRequest.self))
        #expect(sent.albumID == "00000000000000bb" && sent.cursor == "c1")
    }

    /// 受管指令用協定的逾時表（95 s）：明確傳 nil 讓 ClientSession 依 kind 決定
    @Test func playSendsTrackAndUsesKindTimeout() async throws {
        requester.reply(.playTrack, PlayResult(outcome: .degraded, reason: .shortcutMissing))
        let result = try await client.play(trackID: "0000000000000002", albumID: "00000000000000bb")
        #expect(result == PlayResult(outcome: .degraded, reason: .shortcutMissing))
        #expect(requester.lastBody(PlayTrackRequest.self) == PlayTrackRequest(trackID: "0000000000000002", albumID: "00000000000000bb"))
        #expect(requester.lock.withLock { requester.timeouts.last } == .some(nil))
    }

    @Test func inconsistentPlayResultIsRejected() async {
        requester.reply(.playTrack, PlayResult(outcome: .verified, reason: .queueMismatch))
        await #expect(throws: EchoRequestError.invalidResponse) {
            try await client.play(trackID: "0000000000000002", albumID: "00000000000000bb")
        }
    }

    @Test func controlsUseTheirOwnKinds() async throws {
        let result = ControlResult(outcome: .applied, playback: Self.event)
        for kind in [MessageKind.playToggle, .playNext, .playPrevious, .playSeek, .playGenius] { requester.reply(kind, result) }
        _ = try await client.toggle()
        _ = try await client.next()
        _ = try await client.previous()
        _ = try await client.genius()
        _ = try await client.seek(trackID: "0000000000000001", seconds: 30)
        #expect(requester.kinds == [.playToggle, .playNext, .playPrevious, .playGenius, .playSeek])
        #expect(requester.lastBody(SeekRequest.self) == SeekRequest(trackID: "0000000000000001", seconds: 30))
    }

    #if DEBUG
    /// D2 回條：最小的清單請求（limit 1），帶呼叫端指定的請求 ID
    @Test func measurementReceiptIsLimitOnePageWithGivenID() async {
        requester.reply(.catalogPage, CatalogPageResponse(version: "00000000000000aa", total: 0, albums: [], nextCursor: nil))
        let id = UUID()
        await client.measurementReceipt(id: id)
        #expect(requester.lastBody(CatalogPageRequest.self)?.limit == 1)
        #expect(requester.lock.withLock { requester.ids.last } == id)
    }
    #endif

    @Test func outputsAreRequested() async throws {
        requester.reply(.outputList, OutputListResponse(devices: []))
        requester.reply(.outputSet, OutputListResponse(devices: []))
        _ = try await client.outputs()
        _ = try await client.setOutputs(["00000000000000c1"])
        #expect(requester.kinds == [.outputList, .outputSet])
        #expect(requester.lastBody(OutputSetRequest.self)?.deviceIDs == ["00000000000000c1"])
    }
}
