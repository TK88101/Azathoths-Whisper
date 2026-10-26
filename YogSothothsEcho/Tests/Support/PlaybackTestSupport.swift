import Foundation
import RemoteProtocol
import RemoteTransport

@testable import YogSothothsEcho

/// S4 T11：可程式化的播放 client。每個方法回設定好的結果；`holdPlay` 時點歌停住直到 releasePlay；事件由測試推送。名稱一律自編
final class FakePlaybackClient: PlaybackClient, @unchecked Sendable {
    let lock = NSLock()
    var calls: [String] = []
    var tracks: [String: Result<AlbumTracksResponse, EchoRequestError>] = [:]
    var playResults: [Result<PlayResult, EchoRequestError>] = [.success(PlayResult(outcome: .verified, reason: nil))]
    var controlResult: Result<ControlResult, EchoRequestError>
    var holdPlay = false
    var holdControl = false
    /// 曲目清單停住直到 releaseTracks；被取消的會計數並丟 `.cancelled`（F7：斷線／關閉／換專輯要取消在途載入）
    var holdTracks = false
    /// 依序消耗的曲目結果（key 同 `tracks`）；用完才回 `tracks`（F-L1 R3：busy 幾次後成功）
    var trackSequence: [String: [Result<AlbumTracksResponse, EchoRequestError>]] = [:]
    /// 曲目清單停住直到 `releaseStubbornTracks`，不理會取消（模擬已送出、回覆在途中；F-L1 R3）
    var holdTracksStubbornly = false
    private var stubbornGates: [CheckedContinuation<Void, Never>] = []
    private(set) var cancelledTracks = 0
    private var trackGates: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var controlGates: [CheckedContinuation<Void, Never>] = []
    private var playGates: [CheckedContinuation<Void, Never>] = []
    let events: AsyncStream<PlaybackEvent>
    let eventSink: AsyncStream<PlaybackEvent>.Continuation

    init() {
        (events, eventSink) = AsyncStream.makeStream()
        controlResult = .success(ControlResult(outcome: .applied, playback: PlaybackSamples.event()))
    }

    private func log(_ call: String) { lock.withLock { calls.append(call) } }
    var recorded: [String] { lock.withLock { calls } }

    func albumTracks(albumID: String, cursor: String?) async throws(EchoRequestError) -> AlbumTracksResponse {
        log("tracks:\(albumID):\(cursor ?? "-")")
        if lock.withLock({ holdTracks }), !(await waitForTracksGate()) {
            lock.withLock { cancelledTracks += 1 }
            throw .cancelled
        }
        let key = albumID + "|" + (cursor ?? "")
        let (result, stubborn) = lock.withLock { () -> (Result<AlbumTracksResponse, EchoRequestError>?, Bool) in
            if let next = trackSequence[key], !next.isEmpty { return (trackSequence[key]!.removeFirst(), holdTracksStubbornly) }
            return (tracks[key] ?? tracks[albumID], holdTracksStubbornly)
        }
        if stubborn { await withCheckedContinuation { c in lock.withLock { stubbornGates.append(c) } } }
        guard let result else { throw .remote(.invalidRequest) }
        return try result.get()
    }

    func play(trackID: String, albumID: String) async throws(EchoRequestError) -> PlayResult {
        log("play:\(trackID)")
        // 結果在呼叫當下就配給（依呼叫順序）；放行後才取的話，同時放行的兩個呼叫誰拿到哪個結果取決於排程
        let result = lock.withLock { playResults.count > 1 ? playResults.removeFirst() : playResults[0] }
        if lock.withLock({ holdPlay }) { await withCheckedContinuation { c in lock.withLock { playGates.append(c) } } }
        return try result.get()
    }

    /// true＝被放行、false＝被取消
    private func waitForTracksGate() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                let cancelled = lock.withLock { () -> Bool in
                    if Task.isCancelled { return true }
                    trackGates[id] = c
                    return false
                }
                if cancelled { c.resume(returning: false) }
            }
        } onCancel: {
            lock.withLock { trackGates.removeValue(forKey: id) }?.resume(returning: false)
        }
    }

    func releaseTracks() { lock.withLock { let g = trackGates.values; trackGates = [:]; return Array(g) }.forEach { $0.resume(returning: true) } }
    var heldTracks: Int { lock.withLock { trackGates.count } }
    var heldStubbornTracks: Int { lock.withLock { stubbornGates.count } }
    func releaseStubbornTracks() {
        lock.withLock { () -> [CheckedContinuation<Void, Never>] in defer { stubbornGates = [] }; return stubbornGates }.forEach { $0.resume() }
    }
    func trackCalls(_ albumID: String) -> [String] { recorded.filter { $0.hasPrefix("tracks:\(albumID):") } }
    var cancelledTrackLoads: Int { lock.withLock { cancelledTracks } }

    func releasePlay() { lock.withLock { let g = playGates; playGates = []; return g }.forEach { $0.resume() } }
    var heldPlays: Int { lock.withLock { playGates.count } }

    func toggle() async throws(EchoRequestError) -> ControlResult { try await control("toggle") }
    func next() async throws(EchoRequestError) -> ControlResult { try await control("next") }
    func previous() async throws(EchoRequestError) -> ControlResult { try await control("previous") }
    func genius() async throws(EchoRequestError) -> ControlResult { try await control("genius") }
    func seek(trackID: String, seconds: Double) async throws(EchoRequestError) -> ControlResult { try await control("seek:\(seconds)") }

    private func control(_ call: String) async throws(EchoRequestError) -> ControlResult {
        log(call)
        if lock.withLock({ holdControl }) { await withCheckedContinuation { c in lock.withLock { controlGates.append(c) } } }
        // 放行後才取：測試可在指令停住時改回覆；所有在途指令拿同一個 controlResult，沒有誰拿到哪個的排程問題
        return try lock.withLock { controlResult }.get()
    }

    func releaseOneControl() { lock.withLock { controlGates.isEmpty ? nil : controlGates.removeFirst() }?.resume() }
    func releaseControls() { lock.withLock { let g = controlGates; controlGates = []; return g }.forEach { $0.resume() } }
    var heldControls: Int { lock.withLock { controlGates.count } }
    func outputs() async throws(EchoRequestError) -> OutputListResponse { OutputListResponse(devices: []) }
    func setOutputs(_ deviceIDs: [String]) async throws(EchoRequestError) -> OutputListResponse { OutputListResponse(devices: []) }
    func playbackEvents() -> AsyncStream<PlaybackEvent> { events }

    func push(_ event: PlaybackEvent) { eventSink.yield(event) }
}

enum PlaybackSamples {
    static let album = "00000000000000bb"
    static let t1 = "0000000000000001", t2 = "0000000000000002", t3 = "0000000000000003"

    static func event(_ track: String? = t1, _ state: PlaybackState = .playing, position: Double = 10, at sampledAt: Double = 1,
                      availability: PlaybackAvailability = .ok, albumID: String? = album,
                      genius: GeniusAvailability? = nil) -> PlaybackEvent {
        PlaybackEvent(availability: availability, trackID: track, albumID: albumID, state: state, position: position,
                      duration: 200, sampledAt: sampledAt, genius: genius)
    }

    static func song(_ id: String, _ number: Int, artist: String = "") -> TrackSummary {
        TrackSummary(id: id, title: "Made-up Song \(number)", artist: artist, disc: 1, number: number, duration: 180)
    }

    static func tracks(_ songs: [TrackSummary], next: String? = nil, contextPlayable: Bool = true) -> AlbumTracksResponse {
        AlbumTracksResponse(albumID: album, version: "00000000000000aa", songs: songs, nextCursor: next, contextPlayable: contextPlayable)
    }

    static let albumSummary = AlbumSummary(id: album, title: "Made-up Album", artist: "Made-up Artist", trackCount: 3, artworkToken: nil)
    static let otherAlbum = "00000000000000cc"
    static let t9 = "0000000000000009"
    static let otherAlbumSummary = AlbumSummary(id: otherAlbum, title: "Another Made-up Album", artist: "Made-up Artist",
                                                trackCount: 1, artworkToken: nil)
}

/// 可前進的本機單調時鐘
final class ManualNow: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 1000
    var now: @Sendable () -> Double { { [self] in lock.withLock { value } } }
    func advance(_ seconds: Double) { lock.withLock { value += seconds } }
}
