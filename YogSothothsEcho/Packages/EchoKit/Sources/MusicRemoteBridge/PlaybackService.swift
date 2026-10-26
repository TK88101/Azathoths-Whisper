#if os(macOS)
import Foundation
import os
import RemoteProtocol

// 播放服務（sprint-4-detail.md §4.2、§4.4、§4.7）：把 MusicLane、受管佇列、點歌狀態機與狀態輪詢組成 App/Remote 的單一入口。
// 全部元件共用同一個時鐘實例（各 SystemControlClock 的起點不同，sampledAt 才可比）與同一份 LocalOperationLog。
// 連線存活與推送在伺服端起來後由 RelayHost 接上（setOutlets）；接上前與拆下後一律視為無連線：
// 等待中的受管指令不執行、事件不送（fail closed）。

/// 服務需要的 Music 操作（正式＝MusicLane；測試＝替身）
public protocol PlaybackMusic: PlayTarget {
    func outputs() async throws(MusicLaneError) -> [OutputDeviceSummary]
    func setOutputs(_ ids: [String]) async throws(MusicLaneError) -> Bool
}

extension MusicLane: PlaybackMusic {}

/// 傳輸層提供的兩個接口：連線是否仍在（`TransportServer.isConnectionAlive`）、廣播 `event.playback`
public struct PlaybackOutlets: Sendable {
    public let isAlive: @Sendable (UUID) -> Bool
    public let push: @Sendable (PlaybackEvent) -> Void

    public init(isAlive: @escaping @Sendable (UUID) -> Bool, push: @escaping @Sendable (PlaybackEvent) -> Void) {
        self.isAlive = isAlive
        self.push = push
    }

    static let detached = PlaybackOutlets(isAlive: { _ in false }, push: { _ in })
}

public actor PlaybackService {
    private let music: any PlaybackMusic
    private let plans: any PlayPlanProviding
    private let commands: RemoteCommandQueue
    private let poller: PlaybackStatePoller
    private let machine: PlayTrackMachine
    private let outlets: OSAllocatedUnfairLock<PlaybackOutlets>

    public init(music: any PlaybackMusic, plans: any PlayPlanProviding, albumOf: @escaping @Sendable (String) async -> String?,
                binding: any ShortcutBindingChecking, starter: any ShortcutStarting, queueReader: any QueueReading,
                clock: any ControlClock = SystemControlClock(),
                geniusAvailability: (@Sendable () -> GeniusAvailability)? = nil, genius: (any GeniusPressing)? = nil) {
        // nil＝正式（Azathoth 本身的輔助使用權限）；GeniusMenu 不對外公開
        let geniusAvailability = geniusAvailability ?? GeniusMenu.availability
        let outlets = OSAllocatedUnfairLock(initialState: PlaybackOutlets.detached)
        let push: @Sendable (PlaybackEvent) -> Void = { event in outlets.withLock { $0 }.push(event) }
        let event: @Sendable (MusicSnapshot) async -> PlaybackEvent = { snapshot in
            // 時間戳取在查專輯之前：查詢被延遲時，舊的觀測不得帶著較新的 sampledAt（Codex S4 R3 P2）
            let sampledAt = await clock.now()
            let albumID: String? = if let id = snapshot.trackID { await albumOf(id) } else { nil }
            return PlaybackEvent(snapshot: snapshot, albumID: albumID, sampledAt: sampledAt, genius: geniusAvailability())
        }
        let local = LocalOperationLog()
        // 目標曲到達即推（N-01 點歌終點）；輪詢器之後可能再推一次同值，iPad 端無害
        let machine = PlayTrackMachine(plans: plans, binding: binding, starter: starter, music: music, queue: queueReader,
                                       clock: clock, local: local, onArrival: { snapshot in Task { push(await event(snapshot)) } })
        self.music = music
        self.plans = plans
        self.machine = machine
        self.outlets = outlets
        commands = RemoteCommandQueue(target: music, playTrack: machine, clock: clock, event: event,
                                      isAlive: { id in outlets.withLock { $0 }.isAlive(id) }, local: local, genius: genius)
        // 隔離期間才讀 Queue.dat（靜止觀測）；平時輪詢不碰該檔
        poller = PlaybackStatePoller(music: music, clock: clock, albumOf: albumOf, genius: geniusAvailability, push: push,
                                     onSnapshot: { snapshot in
            guard await machine.isQuarantined else { return }
            await machine.observeQuiet(snapshot, queue: await queueReader.read())
        })
    }

    /// nil＝拆下（伺服端停止）
    public nonisolated func setOutlets(_ value: PlaybackOutlets?) {
        outlets.withLock { $0 = value ?? .detached }
    }

    // MARK: 輪詢（RelayHost：連線數 0→1 start、1→0 stop、其他新連線 connectionAdded）

    public func startWatching() async { await poller.start() }
    public func stopWatching() async { await poller.stop() }
    public func connectionAdded() async { await poller.resendCurrent() }

    // MARK: 受管指令

    /// 收件時先驗形狀與「曲目屬於該專輯」：不合法者不進佇列，也就不會取代等待中的點歌
    public func play(_ request: PlayTrackRequest, connection: UUID) async -> ManagedOutcome {
        guard request.isValid else { return .error(.invalidRequest) }
        // 隔離中連目錄都不查（索引不在時 plan 會讀 ITLibrary；simcodex R3 Codex P2），一律回「暫停接受點歌」
        if await machine.isQuarantined { return .play(PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)) }
        if case .failure(let code) = await plans.plan(for: request) { return .error(code) }
        return await commands.submit(.playTrack(request), connection: connection)
    }

    public func next(connection: UUID) async -> ManagedOutcome { await controlled(await commands.submit(.next, connection: connection)) }
    public func previous(connection: UUID) async -> ManagedOutcome {
        await controlled(await commands.submit(.previous, connection: connection))
    }

    /// CR-030：以目前曲觸發 Genius（受管佇列；Azathoth 沒有輔助使用權限＝accessibilityDenied）
    public func genius(connection: UUID) async -> ManagedOutcome {
        await controlled(await commands.submit(.genius, connection: connection))
    }

    // MARK: 不受閘門管的指令

    public func toggle() async -> Result<ControlResult, ErrorCode> { await controlled(await commands.toggle()) }

    public func seek(_ request: SeekRequest) async -> Result<ControlResult, ErrorCode> {
        guard request.isValid else { return .failure(.invalidRequest) }
        return await controlled(await commands.seek(request))
    }

    /// 控制之後讓輪詢器下一次一律推送（回覆裡的讀回可能還是舊狀態）
    private func controlled<T>(_ result: T) async -> T {
        await poller.controlApplied()
        return result
    }

    // MARK: AirPlay（§4.13）

    public func outputs() async -> Result<OutputListResponse, ErrorCode> {
        do {
            return .success(OutputListResponse(devices: try await music.outputs()))
        } catch {
            return .failure(RemoteCommandQueue.code(error))
        }
    }

    /// 只接受目前列得出的裝置；設定後讀回實際選取狀態
    public func setOutputs(_ request: OutputSetRequest) async -> Result<OutputListResponse, ErrorCode> {
        guard request.isValid else { return .failure(.invalidRequest) }
        do {
            let known = Set(try await music.outputs().map(\.id))
            guard Set(request.deviceIDs).isSubset(of: known) else { return .failure(.invalidRequest) }
            _ = try await music.setOutputs(request.deviceIDs)
            return .success(OutputListResponse(devices: try await music.outputs()))
        } catch {
            return .failure(RemoteCommandQueue.code(error))
        }
    }
}
#endif
