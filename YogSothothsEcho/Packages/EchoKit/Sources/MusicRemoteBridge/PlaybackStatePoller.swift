#if os(macOS)
import Foundation
import os
import RemoteProtocol

// 狀態輪詢與推送（設計 §5.3、CR-006①；sprint-4-detail.md §4.7）。只在有 iPad 連線時由 RelayHost 啟動：
// 每 0.5 s 讀一次（Music 沒在跑時 MusicLane 不送 AE）；`com.apple.Music.playerInfo` 通知只當加速；
// 自動化權限被拒時退避為每 10 s 一次，不連續撞權限。有意義的變化才推（PushPolicy）。

/// 推送原因；DEBUG 診斷記 rawValue（#4-1 D2）。`control`＝控制之後的強制推送
enum PushReason: String { case first, availability, track, state, duration, genius, refresh, jump, control }

/// 推送判定（純函式）：可用性、目前曲、狀態、曲長任一不同；或位置偏離外推值超過 1 s；或距上次推送滿 10 s。
/// 同時有多項不同時依此順序回第一個（PushReasonTests 固定）
enum PushPolicy {
    /// 要推的原因（nil＝不推）
    static func reason(last: PlaybackEvent?, current: PlaybackEvent) -> PushReason? {
        guard let last else { return .first }
        if last.availability != current.availability { return .availability }
        if last.trackID != current.trackID { return .track }
        if last.state != current.state { return .state }
        if last.duration != current.duration { return .duration }
        if last.genius != current.genius { return .genius }
        let elapsed = current.sampledAt - last.sampledAt
        if elapsed >= PlaybackLimits.pushRefreshInterval { return .refresh }
        let predicted = last.state.projected(last.position, after: elapsed)
        return abs(current.position - predicted) > PlaybackLimits.pushPositionTolerance ? .jump : nil
    }

    static func shouldPush(last: PlaybackEvent?, current: PlaybackEvent) -> Bool { reason(last: last, current: current) != nil }
}

public actor PlaybackStatePoller {
    static let playerInfoNotification = Notification.Name("com.apple.Music.playerInfo")
    static let deniedBackoff: Double = 10
    /// 通知觸發的補讀之間至少隔這麼久（持續灌通知也不會連續打 AE）
    static let kickMinimumGap: Double = 0.25

    private let music: any ControlTarget
    private let clock: any ControlClock
    private let albumOf: @Sendable (String) async -> String?
    private let genius: @Sendable () -> GeniusAvailability
    private let push: @Sendable (PlaybackEvent) -> Void
    private let onSnapshot: (@Sendable (MusicSnapshot) async -> Void)?
    private var last: PlaybackEvent?
    private var watcher: Task<Void, Never>?
    private var generation = 0
    private var denied = false
    /// playerInfo 通知的合併（security review MEDIUM-3：任何本機程序都能發這個通知）
    private var kickRunning = false
    private var kickPending = false
    /// 控制之後的下一次輪詢一律推送（#4-1：控制回覆的讀回可能還是舊狀態，較早時間戳的新狀態會被 iPad 當亂序丟掉）
    private var pushNext = false
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    /// `onSnapshot`：每次成功讀到狀態都回報（PlaybackService 用來在捷徑隔離期間觀測靜止）
    public init(music: any ControlTarget, clock: any ControlClock = SystemControlClock(),
                albumOf: @escaping @Sendable (String) async -> String?, genius: @escaping @Sendable () -> GeniusAvailability,
                push: @escaping @Sendable (PlaybackEvent) -> Void,
                onSnapshot: (@Sendable (MusicSnapshot) async -> Void)? = nil) {
        self.music = music
        self.clock = clock
        self.albumOf = albumOf
        self.genius = genius
        self.push = push
        self.onSnapshot = onSnapshot
    }

    /// 重複呼叫只會有一個 watcher
    public func start() async {
        guard watcher == nil else { return }
        generation += 1
        let token = generation
        observePlayerInfo()
        await pollOnce()
        // 讀取期間插進來的 stop() 已遞增世代：不再登記 watcher，否則之後的 start() 全成 no-op（security review LOW-8）
        guard token == generation else { return }
        watcher = Task { [weak self] in await self?.loop(token) }
    }

    public func stop() {
        generation += 1
        watcher?.cancel()
        watcher = nil
        last = nil
        denied = false
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
    }

    /// iPad 的控制已執行：下一次輪詢不論有無變化都推（帶新的時間戳）
    public func controlApplied() { pushNext = true }

    /// Music 的 playerInfo 通知：多讀一次（只當加速，不倚賴；S0 B4 0/20 由通知觸發）。
    /// 讀取進行中再來的通知只記一次；讀完若有，隔 kickMinimumGap 再補讀一次（合併＋限速，security MEDIUM-3）
    public func playerInfoChanged() async {
        guard watcher != nil else { return }
        guard !kickRunning else {
            kickPending = true
            return
        }
        kickRunning = true
        await pollOnce()
        while kickPending, watcher != nil {
            kickPending = false
            try? await clock.sleep(seconds: Self.kickMinimumGap)
            guard watcher != nil else { break }
            await pollOnce()
        }
        kickRunning = false
    }

    /// 新連線建立：立即讀一次並推送（不論是否有變化；廣播即可，其他連線收到重複值無害）。
    /// 讀取暫時失敗時推上一次的值。沒在輪詢（無連線）時不讀 Music（D13）
    public func resendCurrent() async {
        guard watcher != nil else { return }
        let token = generation
        guard let event = await read() ?? last, token == generation else { return }   // 讀取期間 stop() 了：作廢
        Self.trace("resend", event)
        emit(event)
    }

    private func loop(_ token: Int) async {
        while token == generation, !Task.isCancelled {
            do {
                try await clock.sleep(seconds: denied ? Self.deniedBackoff : PlaybackLimits.pollInterval)
            } catch {
                return
            }
            guard token == generation else { return }
            await pollOnce()
        }
    }

    /// 定期與通知觸發：有意義的變化才推
    private func pollOnce() async {
        let token = generation
        // 讀取期間 stop() 了：結果作廢（不更新 last、不推）
        guard let event = await read(), token == generation else { return }
        guard let why = pushNext ? .control : PushPolicy.reason(last: last, current: event) else { return }
        pushNext = false
        Self.trace(why.rawValue, event)
        emit(event)
    }

    /// #4-1 D2 診斷（DEBUG）：推送原因、狀態、位置、取樣時刻（只有 ID 與數字）
    private static func trace(_ reason: @autoclosure () -> String, _ event: PlaybackEvent) {
        RelayTrace.notice(pushLine(reason(), event))
    }

    static func pushLine(_ reason: String, _ event: PlaybackEvent) -> String {
        "push reason=\(reason) state=\(event.state.rawValue) pos=\(String(format: "%.2f", event.position)) track=\(event.trackID ?? "-")"
    }

    private func emit(_ event: PlaybackEvent) {
        last = event
        push(event)
    }

    /// 讀一次狀態；暫時失敗回 nil（不推新值，下一次再讀）
    private func read() async -> PlaybackEvent? {
        let now = await clock.now()
        do {
            let snapshot = try await music.snapshot()
            denied = false
            await onSnapshot?(snapshot)
            let albumID: String? = if let id = snapshot.trackID { await albumOf(id) } else { nil }
            return PlaybackEvent(snapshot: snapshot, albumID: albumID, sampledAt: now, genius: genius())
        } catch {
            switch error {
            case .notRunning: denied = false; return .unavailable(.musicNotRunning, at: now, genius: genius())
            case .notAuthorized: denied = true; return .unavailable(.automationDenied, at: now, genius: genius())
            case .failed: return nil
            }
        }
    }

    private func observePlayerInfo() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.playerInfoNotification, object: nil, queue: nil) {
            [weak self] _ in
            Task { await self?.playerInfoChanged() }
        }
    }
}
#endif
