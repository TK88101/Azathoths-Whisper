#if os(macOS)
import Foundation
import Network
import RemoteProtocol
import Testing
@testable import MusicRemoteBridge
@testable import RemoteTransport

// S4 T9（sprint-4-detail.md §7「L」、D1、D6；§4.9 #4、#6）：真 TransportServer／TransportClient＋PlaybackService＋替身 Music。
// 走真時間（輪詢 0.5 s、閘門 1–3 s），每條測試數秒內結束

private let album = "00000000000000bb"

/// 替身 Music：next／previous 立即換曲（`ignoresSteps` 時不理會）；toggle、seek、playOnce 立即生效
actor WireMusic: PlaybackMusic {
    var state: PlaybackState = .playing
    var track = 1
    var position: Double = 10
    var ignoresSteps = false

    func set(ignoresSteps value: Bool) { ignoresSteps = value }
    /// 模擬使用者在 Mac 上手動暫停
    func pauseOnMac() { state = .paused }

    private var trackID: String { String(format: "%016llx", UInt64(track)) }

    func snapshot() async throws(MusicLaneError) -> MusicSnapshot {
        MusicSnapshot(state: state, trackID: trackID, duration: 200, position: position)
    }
    func playOnce(trackID: String) async throws(MusicLaneError) -> Bool {
        track = Int(trackID, radix: 16) ?? track
        state = .playing
        return true
    }
    func next() async throws(MusicLaneError) { if !ignoresSteps { track += 1; position = 0 } }
    func previous() async throws(MusicLaneError) { if !ignoresSteps { track -= 1; position = 0 } }
    func togglePlayPause() async throws(MusicLaneError) { state = state == .playing ? .paused : .playing }
    func seek(to seconds: Double) async throws(MusicLaneError) { position = seconds }
    func outputs() async throws(MusicLaneError) -> [OutputDeviceSummary] { [] }
    func setOutputs(_ ids: [String]) async throws(MusicLaneError) -> Bool { false }
}

private struct AlbumPlans: PlayPlanProviding {
    func plan(for request: PlayTrackRequest) async -> Result<AdmissionResult, ErrorCode> {
        .success(.admitted(ShortcutPlan(album: "A", albumArtist: "", artist: "B", order: [request.trackID])))
    }
}

private struct NoShortcut: ShortcutBindingChecking {
    func status() async -> ShortcutBindingStatus { .missing }
}

private struct NeverStarts: ShortcutStarting {
    func start(_ shortcut: ShortcutIdentifier, input: ShortcutInput) -> RunningShortcut? { nil }
}

private struct NoQueue: QueueReading {
    func read() async -> [String]? { nil }
}

struct Empty: Codable {}

/// 測試用的最小轉接（正式版是 Azathoth 的 RelayRequestRouter，其分派另有單元測試）
private struct PlaybackHandler: RequestHandling {
    let service: PlaybackService

    func handle(_ request: InboundRequest) async -> OutboundReply {
        switch request.kind {
        case .playToggle: return reply(request, await service.toggle())
        case .playSeek:
            guard let body = request.body(as: SeekRequest.self) else { return .error(.invalidRequest) }
            return reply(request, await service.seek(body))
        case .playNext: return managed(request, await service.next(connection: request.connectionID))
        case .playTrack:
            guard let body = request.body(as: PlayTrackRequest.self) else { return .error(.invalidRequest) }
            return managed(request, await service.play(body, connection: request.connectionID))
        default: return .error(.invalidRequest)
        }
    }

    private func reply(_ request: InboundRequest, _ result: Result<ControlResult, ErrorCode>) -> OutboundReply {
        switch result {
        case .success(let body): request.reply(body)
        case .failure(let code): .error(code)
        }
    }

    private func managed(_ request: InboundRequest, _ outcome: ManagedOutcome) -> OutboundReply {
        switch outcome {
        case .play(let result): request.reply(result)
        case .control(let result): request.reply(result)
        case .error(let code): .error(code)
        case .dropped: .error(.busy)
        }
    }
}

private final class ServiceBox: @unchecked Sendable {
    var service: PlaybackService?
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct PlaybackEndToEndTests {
    let music = WireMusic()
    let service: PlaybackService

    init() {
        service = PlaybackService(music: music, plans: AlbumPlans(), albumOf: { _ in album }, binding: NoShortcut(),
                                  starter: NeverStarts(), queueReader: NoQueue())
    }

    /// 配對、接上接口（同 RelayHost 的 attachPlayback）、連線
    private func connect() async throws -> (Harness, ClientSession) {
        let h = try await Harness(handler: PlaybackHandler(service: service))
        let server = h.server
        service.setOutlets(PlaybackOutlets(isAlive: { server.isConnectionAlive($0) },
                                           push: { server.broadcast(.eventPlayback, $0) }))
        guard case .approved = await h.pair() else { throw EchoRequestError.disconnected }
        let session = try await h.client().connect(endpoint: h.endpoint).get()
        return (h, session)
    }

    private func nextEvent(_ events: inout AsyncStream<InboundEvent>.Iterator, within seconds: Double) async -> PlaybackEvent? {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            guard let event = await events.next() else { return nil }
            if let body = event.body(as: PlaybackEvent.self) { return body }
        }
        return nil
    }

    // D1：toggle、seek、next、play.track 經過真傳輸層往返

    @Test func controlsRoundTripOverTheWire() async throws {
        let (h, session) = try await connect()
        let toggled = try await session.request(.playToggle, Empty(), as: ControlResult.self)
        #expect(toggled.outcome == .applied && toggled.playback.state == .paused && toggled.playback.albumID == album)

        let sought = try await session.request(.playSeek, SeekRequest(trackID: "0000000000000001", seconds: 42), as: ControlResult.self)
        #expect(sought.outcome == .applied && sought.playback.position == 42)

        let stepped = try await session.request(.playNext, Empty(), as: ControlResult.self)
        #expect(stepped.outcome == .applied && stepped.playback.trackID == "0000000000000002")

        // 捷徑未安裝 → 降級只播這首；回覆 kind 為 play.result
        let played = try await session.request(.playTrack, PlayTrackRequest(trackID: "0000000000000009", albumID: album),
                                               as: PlayResult.self)
        #expect(played == PlayResult(outcome: .degraded, reason: .shortcutMissing))
        session.close()
        _ = h
    }

    // §4.9 #4：Mac 上手動暫停 → 兩次輪詢內 iPad 收到事件（無錯誤態）

    @Test func manualChangeReachesIPadWithinTwoPolls() async throws {
        let (h, session) = try await connect()
        var events = session.events.makeAsyncIterator()
        await service.startWatching()
        let initial = await nextEvent(&events, within: 2)
        #expect(initial?.state == .playing)
        await music.pauseOnMac()
        let started = ContinuousClock.now
        let changed = await nextEvent(&events, within: 2)
        let elapsed = ContinuousClock.now - started
        #expect(changed?.state == .paused && changed?.availability == .ok)
        #expect(elapsed <= .seconds(2 * PlaybackLimits.pollInterval + 0.2))
        await service.stopWatching()
        session.close()
        _ = h
    }

    // §4.9 #6：斷線 → 重連後收到最新狀態

    @Test func reconnectReceivesFreshPlayback() async throws {
        let (h, first) = try await connect()
        await service.startWatching()
        var initial = first.events.makeAsyncIterator()
        _ = await nextEvent(&initial, within: 2)
        first.close()
        await music.pauseOnMac()
        let second = try await h.client().connect(endpoint: h.endpoint).get()
        var events = second.events.makeAsyncIterator()
        // RelayHost 在新連線時呼叫 connectionAdded；這裡直接呼叫
        try await Task.sleep(for: .milliseconds(100))
        await service.connectionAdded()
        let fresh = await nextEvent(&events, within: 2)
        #expect(fresh?.state == .paused)
        await service.stopWatching()
        second.close()
    }

    // D6：Music 不理會下一首 → 第 1 筆執行中、3 筆排隊、第 5 筆 busy；斷線後排隊者不執行

    @Test func fifthRapidNextIsBusyAndQueuedOnesDieWithTheConnection() async throws {
        let (h, session) = try await connect()
        await music.set(ignoresSteps: true)
        let results = Locked<[Result<ControlResult, EchoRequestError>]>([])
        let tasks = (0..<5).map { index in
            Task {
                try? await Task.sleep(for: .milliseconds(30 * index))   // 固定到達順序
                let result: Result<ControlResult, EchoRequestError>
                do throws(EchoRequestError) { result = .success(try await session.request(.playNext, Empty(), as: ControlResult.self)) }
                catch { result = .failure(error) }
                results.withLock { $0.append(result) }
            }
        }
        for _ in 0..<200 where !results.withLock({ $0.contains { $0 == .failure(.remote(.busy)) } }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(results.withLock { $0.filter { $0 == .failure(.remote(.busy)) }.count } == 1)
        session.close()
        for task in tasks { await task.value }
        // 執行中那筆在斷線後照常做完（3 s 未生效），排隊的 3 筆都以斷線結束、不執行
        #expect(results.withLock { $0.filter { $0 == .failure(.disconnected) }.count } == 4)
        _ = h
    }
}
#endif
