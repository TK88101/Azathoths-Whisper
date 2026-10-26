#if DEBUG
import Foundation
import UIKit
import RemoteProtocol
import RemoteTransport

/// 只在 DEBUG 存在的 UI 測試替身（比照 Azathoth 的 App/UITestSupport；Release 不含）
enum UITestSupport {
    static let fakeRemoteArgument = AccessibilityID.fakeRemoteArgument
    static let cameraDeniedArgument = AccessibilityID.cameraDeniedArgument
    static let fakePayloadArgument = AccessibilityID.fakePayloadArgument

    static func connector(_ arguments: [String]) -> (any RemoteConnecting)? {
        arguments.contains(fakeRemoteArgument) ? UITestRemoteConnector() : nil
    }

    static func camera(_ arguments: [String]) -> (any CameraAuthorizing)? {
        if arguments.contains(cameraDeniedArgument) { return FixedCamera(access: .denied) }
        // 模擬器沒有可用的掃描器（DataScannerViewController.isSupported＝false）：假載荷模式視為已授權
        if arguments.contains(fakePayloadArgument) { return FixedCamera(access: .authorized) }
        return nil
    }

    /// 給 UI 測試的有效樣本載荷（秘密為固定測試值，只配 UITestRemoteConnector）
    static func fakePayload(_ arguments: [String]) -> String? {
        guard arguments.contains(fakePayloadArgument) else { return nil }
        return QRPairingPayload(sessionID: Data(repeating: 1, count: 16), macFingerprint: Fingerprint(bytes: Data(repeating: 2, count: 32))!,
                                secret: Data(repeating: 3, count: 32), instanceName: "Azathoth-TEST")?.encoded()
    }
}

struct FixedCamera: CameraAuthorizing {
    let access: CameraAccess
    func status() -> CameraAccess { access }
    func request() async -> Bool { access == .authorized }
}

/// 配對：先回 pending（末 4 碼 0A0B）、5 秒後核准（留時間給 XCUITest 讀等待畫面）；連線：一律成功、保持開著
final class UITestRemoteConnector: RemoteConnecting {
    /// S5：「一開始就在播」的測試直接視為已配對（跳過假配對流程）
    private let paired = Locked(ProcessInfo.processInfo.arguments.contains(AccessibilityID.nowPlayingArgument))
    var hasPairedMac: Bool { paired.withLock { $0 } }

    func pair(payload: QRPairingPayload, deviceName: String, onPending: @escaping @Sendable (String) -> Void) async -> PairingAttemptResult {
        onPending("0A0B")
        try? await Task.sleep(for: .seconds(5))
        paired.withLock { $0 = true }
        return .approved(PeerRecord(peerID: UUID(), fingerprint: payload.macFingerprint,
                                    localFingerprint: Fingerprint(bytes: Data(repeating: 4, count: 32))!,
                                    name: payload.instanceName, pairedAt: Date()))
    }

    func connect(discoveryWindow: TimeInterval) async -> Result<any RemoteSessionHandle, ConnectFailure> { .success(OpenSession()) }
    func forgetMacs() { paired.withLock { $0 = false } }
}

final class OpenSession: RemoteSessionHandle {
    let macName = ProcessInfo.processInfo.arguments.contains(AccessibilityID.longMacNameArgument)
        ? String(repeating: "W", count: 40) : "Azathoth-TEST"
    let client: any EchoClient = SyntheticEchoClient()
    let playback: any PlaybackClient = SyntheticPlaybackClient(arguments: ProcessInfo.processInfo.arguments)
    private let open = Locked(true)
    var isOpen: Bool { open.withLock { $0 } }
    func close() { open.withLock { $0 = false } }
    func waitUntilClosed() async {
        while isOpen {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        }
    }
}
/// UI 測試與 Preview 用的合成曲庫（S3）：名稱全為自編（記憶「測試字串不用真歌詞」）；封面是單色 JPEG
struct SyntheticEchoClient: EchoClient {
    static let version = "00000000000000e1"
    var albumCount = 240

    private var albums: [AlbumSummary] {
        (0..<albumCount).map { i in
            AlbumSummary(id: String(format: "%016llx", UInt64(i + 1)), title: String(format: "Synthetic Album %03d", i + 1),
                         artist: String(format: "Test Artist %02d", i % 30 + 1), trackCount: 10,
                         artworkToken: i % 7 == 6 ? nil : String(format: "%016llx", UInt64(i + 1) &* 31))
        }
    }

    func page(cursor: String?) async throws(EchoRequestError) -> CatalogPageResponse {
        let all = albums
        let offset = cursor.flatMap(CatalogCursor.decode)?.offset ?? 0
        let end = min(offset + CatalogLimits.defaultPageSize, all.count)
        let next = end < all.count ? CatalogCursor(version: Self.version, offset: end).encoded() : nil
        return CatalogPageResponse(version: Self.version, total: all.count, albums: Array(all[min(offset, all.count)..<end]), nextCursor: next)
    }

    func search(_ query: String) async throws(EchoRequestError) -> CatalogSearchResponse {
        let needle = TextFold.fold(query)
        let hits = albums.filter { TextFold.fold($0.title + " " + $0.artist).contains(needle) }
        return CatalogSearchResponse(version: Self.version, albums: Array(hits.prefix(CatalogLimits.defaultSearchResults)))
    }

    func artwork(albumID: String, token: String) async throws(EchoRequestError) -> ArtworkResponse {
        let seed = UInt64(albumID, radix: 16) ?? 0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let jpeg = renderer.jpegData(withCompressionQuality: 0.8) { context in
            UIColor(hue: CGFloat(seed % 36) / 36, saturation: 0.6, brightness: 0.8, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return ArtworkResponse(albumID: albumID, size: .spine, outcome: .image, artworkToken: token, jpeg: jpeg)
    }

    func catalogChanges() -> AsyncStream<String> { AsyncStream { _ in } }
}

/// UI 測試與 Preview 用的合成播放器（S4）：每張合成專輯 10 首自編曲名；點歌、暫停、跳曲、拖進度立即生效並推事件。
/// 點歌結果可設為降級（Mac 缺少捷徑）或不確定；可設一開始 Music 未開／未允許控制、`unavailableSeconds` 秒後恢復
final class SyntheticPlaybackClient: PlaybackClient, @unchecked Sendable {
    static let unavailableSeconds: Double = 4

    private struct State {
        /// nil＝還沒點過歌（Music 停著、沒有目前曲）
        var albumID: String?
        var number = 1
        var playing = false
        var position: Double = 0
        var sampledAt: Double = 0
    }

    static let songsPerAlbum = 10
    static let songLength: Double = 180
    private let playResult: PlayResult
    private let unavailable: PlaybackAvailability?
    private let genius: GeniusAvailability?
    private let state = Locked(State())
    private let events: AsyncStream<PlaybackEvent>
    private let sink: AsyncStream<PlaybackEvent>.Continuation

    init(arguments: [String] = []) {
        playResult = arguments.contains(AccessibilityID.playDegradedArgument) ? PlayResult(outcome: .degraded, reason: .shortcutMissing)
            : arguments.contains(AccessibilityID.playUncertainArgument) ? PlayResult(outcome: .indeterminate, reason: .queueTimeout)
            : PlayResult(outcome: .verified, reason: nil)
        unavailable = arguments.contains(AccessibilityID.musicNotRunningArgument) ? .musicNotRunning
            : arguments.contains(AccessibilityID.musicDeniedArgument) ? .automationDenied : nil
        genius = arguments.contains(AccessibilityID.geniusLegacyMacArgument) ? nil
            : arguments.contains(AccessibilityID.geniusNeedsAccessibilityArgument) ? .needsAccessibility : .ready
        (events, sink) = AsyncStream.makeStream()
        // S5：一開始就在播第一張合成專輯的第 1 首（唱機畫面的 UI 測試與目視）
        if arguments.contains(AccessibilityID.nowPlayingArgument) {
            state.withLock { $0.albumID = String(format: "%016llx", UInt64(1)); $0.playing = true; $0.position = 42 }
        }
    }

    static func trackID(album: String, number: Int) -> String {
        String(format: "%016llx", (UInt64(album, radix: 16) ?? 0) << 8 | UInt64(number))
    }

    private func current() -> PlaybackEvent {
        state.withLock { s in
            s.sampledAt += 1
            guard let album = s.albumID else {
                return PlaybackEvent(availability: .ok, trackID: nil, albumID: nil, state: .stopped, position: 0, duration: nil,
                                     sampledAt: s.sampledAt, genius: genius)
            }
            return PlaybackEvent(availability: .ok, trackID: Self.trackID(album: album, number: s.number), albumID: album,
                                 state: s.playing ? .playing : .paused, position: s.position, duration: Self.songLength,
                                 sampledAt: s.sampledAt, genius: genius)
        }
    }

    private func changed() -> ControlResult {
        let event = current()
        sink.yield(event)
        return ControlResult(outcome: .applied, playback: event)
    }

    func albumTracks(albumID: String, cursor: String?) async throws(EchoRequestError) -> AlbumTracksResponse {
        let songs = (1...Self.songsPerAlbum).map {
            TrackSummary(id: Self.trackID(album: albumID, number: $0), title: String(format: "Synthetic Song %02d", $0), disc: 1,
                         number: $0, duration: Self.songLength)
        }
        return AlbumTracksResponse(albumID: albumID, version: SyntheticEchoClient.version, songs: songs, nextCursor: nil,
                                   contextPlayable: true)
    }

    func play(trackID: String, albumID: String) async throws(EchoRequestError) -> PlayResult {
        let number = Int((UInt64(trackID, radix: 16) ?? 0) & 0xFF)
        state.withLock { $0 = State(albumID: albumID, number: number, playing: true, position: 0, sampledAt: $0.sampledAt) }
        _ = changed()
        return playResult
    }

    func toggle() async throws(EchoRequestError) -> ControlResult {
        state.withLock { $0.playing.toggle() }
        return changed()
    }

    func next() async throws(EchoRequestError) -> ControlResult { step(+1) }
    func previous() async throws(EchoRequestError) -> ControlResult { step(-1) }

    /// Genius（CR-030）：合成器換到下一張合成專輯的第 1 首並播放；沒有目前曲（CR-031）＝從第 1 張起播
    func genius() async throws(EchoRequestError) -> ControlResult {
        state.withLock { s in
            let next = s.albumID.flatMap { UInt64($0, radix: 16) }.map { $0 + 1 } ?? 1
            s = State(albumID: String(format: "%016llx", next), number: 1, playing: true, position: 0, sampledAt: s.sampledAt)
        }
        return changed()
    }

    private func step(_ delta: Int) -> ControlResult {
        let moved = state.withLock { s -> Bool in
            let target = s.number + delta
            guard s.albumID != nil, (1...Self.songsPerAlbum).contains(target) else { return false }
            s.number = target
            s.position = 0
            return true
        }
        guard moved else { return ControlResult(outcome: .notApplied, playback: current()) }
        return changed()
    }

    func seek(trackID: String, seconds: Double) async throws(EchoRequestError) -> ControlResult {
        state.withLock { $0.position = min(seconds, Self.songLength) }
        return changed()
    }

    func outputs() async throws(EchoRequestError) -> OutputListResponse { OutputListResponse(devices: []) }
    func setOutputs(_ deviceIDs: [String]) async throws(EchoRequestError) -> OutputListResponse { OutputListResponse(devices: []) }

    func playbackEvents() -> AsyncStream<PlaybackEvent> {
        guard let unavailable else {
            sink.yield(current())
            return events
        }
        let stamp = state.withLock { s -> Double in s.sampledAt += 1; return s.sampledAt }
        sink.yield(PlaybackEvent(availability: unavailable, trackID: nil, albumID: nil, state: .stopped, position: 0, duration: nil,
                                 sampledAt: stamp, genius: genius))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.unavailableSeconds))
            guard let self else { return }
            self.sink.yield(self.current())
        }
        return events
    }
}
#endif
