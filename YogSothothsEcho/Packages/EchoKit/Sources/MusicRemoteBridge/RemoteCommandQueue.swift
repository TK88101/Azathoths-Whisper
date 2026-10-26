#if os(macOS)
import Foundation
import os
import RemoteProtocol

// 確認式節奏（設計 §5.3、CR-006②；sprint-4-detail.md §4.4）：受管指令（next／previous／play.track）單一 FIFO，
// 同一時間只執行一筆；閘門期間等待者最多 3 筆、不合併；尚未執行的 play.track 被新的取代（superseded）；
// 入列時做完成期限准入（預約 deadline 超過 80 s＝busy）；toggle／seek 不排隊。
// 連線撤離：每筆記連線 ID，輪到它時連線已不在＝丟棄（不執行、不回覆）。

/// 時間來源（外部邊界：正式＝ContinuousClock；測試＝手動時鐘）。秒，單調
public protocol ControlClock: Sendable {
    func now() async -> Double
    func sleep(seconds: Double) async throws
}

public struct SystemControlClock: ControlClock {
    private let origin = ContinuousClock.now
    public init() {}

    public func now() async -> Double {
        (ContinuousClock.now - origin).secondsValue
    }

    public func sleep(seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
}

/// 佇列需要的 Music 操作（正式＝MusicLane；測試＝替身）
public protocol ControlTarget: Sendable {
    func snapshot() async throws(MusicLaneError) -> MusicSnapshot
    func next() async throws(MusicLaneError)
    func previous() async throws(MusicLaneError)
    func togglePlayPause() async throws(MusicLaneError)
    func seek(to seconds: Double) async throws(MusicLaneError)
}

extension MusicLane: ControlTarget {}

public enum PlayTrackOutcome: Sendable, Equatable {
    case result(PlayResult)
    case error(ErrorCode)
    /// 還沒對 Music 做任何事之前連線就不在了（中繼關閉、iPad 被撤銷）：沒有動 Music，也沒有人收回覆
    case abandoned
}

/// play.track 狀態機（T7；測試＝替身）。`shouldContinue`：每個不可逆動作（啟動捷徑、降級點歌）之前查一次，
/// 不成立就放棄（security review MEDIUM-1）；已啟動的捷徑照 §4.4 做完
public protocol PlayTrackRunning: Sendable {
    func play(_ request: PlayTrackRequest, shouldContinue: @escaping @Sendable () -> Bool) async -> PlayTrackOutcome
}

public enum ManagedCommand: Sendable, Equatable {
    case next, previous
    case playTrack(PlayTrackRequest)
    /// CR-030：以目前曲觸發 Genius
    case genius

    var kind: ManagedKind {
        switch self {
        case .next, .previous: .nextPrevious
        case .playTrack: .playTrack
        case .genius: .genius
        }
    }
}

public enum ManagedKind: String, Sendable, Equatable {
    case nextPrevious, playTrack, genius

    var worst: Double {
        switch self {
        case .nextPrevious: PlaybackLimits.worstNextPrevious
        case .playTrack: PlaybackLimits.worstPlayTrack
        case .genius: PlaybackLimits.worstGenius
        }
    }
}

public enum ManagedOutcome: Sendable, Equatable {
    case control(ControlResult)
    case play(PlayResult)
    case error(ErrorCode)
    /// 連線已不在：不執行、不回覆
    case dropped
}

/// 准入的純模型（可枚舉測試）：每筆一個預約 deadline；執行中者保留原預約，等待者依序累加最壞耗時
struct ManagedAdmission: Sendable {
    struct Reservation: Sendable, Equatable {
        let id: UUID
        let kind: ManagedKind
        var deadline: Double
        var started: Bool
    }

    enum Decision: Equatable {
        case accepted(deadline: Double, superseded: UUID?)
        case rejected
    }

    private(set) var reservations: [Reservation] = []

    var waitingCount: Int { reservations.filter { !$0.started }.count }

    mutating func admit(_ kind: ManagedKind, now: Double, id: UUID) -> Decision {
        var candidate = reservations
        var superseded: UUID?
        if kind == .playTrack, let index = candidate.firstIndex(where: { !$0.started && $0.kind == .playTrack }) {
            let replaced = candidate[index].id
            superseded = replaced
            candidate.removeAll { $0.id == replaced }
        }
        guard candidate.filter({ !$0.started }).count < PlaybackLimits.maxPendingManaged else { return .rejected }
        candidate.append(Reservation(id: id, kind: kind, deadline: 0, started: false))
        Self.recompute(&candidate, now: now)
        guard let deadline = candidate.last?.deadline, deadline - now <= PlaybackLimits.managedAdmissionBudget else { return .rejected }
        reservations = candidate
        return .accepted(deadline: deadline, superseded: superseded)
    }

    mutating func start(_ id: UUID) {
        guard let index = reservations.firstIndex(where: { $0.id == id }) else { return }
        reservations[index].started = true
    }

    /// 完成、丟棄或被取代：釋放預約（命名避開 echo_gate E2 的 `.remove(`）。其餘預約不重算（只會偏大＝保守），下一次 admit 以當下時間重算
    mutating func release(_ id: UUID) { reservations.removeAll { $0.id == id } }

    private static func recompute(_ list: inout [Reservation], now: Double) {
        var previous = now
        for index in list.indices {
            if list[index].started {
                previous = max(previous, list[index].deadline)
            } else {
                list[index].deadline = max(previous, now) + list[index].kind.worst
                previous = list[index].deadline
            }
        }
    }
}

public actor RemoteCommandQueue {
    private struct Entry {
        let id: UUID
        let command: ManagedCommand
        let connection: UUID
        let continuation: CheckedContinuation<ManagedOutcome, Never>
    }

    private let target: any ControlTarget
    private let player: any PlayTrackRunning
    private let clock: any ControlClock
    private let event: @Sendable (MusicSnapshot) async -> PlaybackEvent
    private let isAlive: @Sendable (UUID) -> Bool
    private let local: LocalOperationLog?
    private let genius: any GeniusPressing
    private var admission = ManagedAdmission()
    private var waiting: [Entry] = []
    /// 執行中那筆的種類（到放行為止，含 hold；nil＝閒置）：Genius 執行中 toggle／seek＝busy
    private var runningKind: ManagedKind?
    /// 被接受的受管指令數（測試用來固定到達順序）
    private(set) var acceptedCount = 0

    public init(target: any ControlTarget, playTrack: any PlayTrackRunning, clock: any ControlClock = SystemControlClock(),
                event: @escaping @Sendable (MusicSnapshot) async -> PlaybackEvent, isAlive: @escaping @Sendable (UUID) -> Bool,
                local: LocalOperationLog? = nil, genius: (any GeniusPressing)? = nil) {
        self.target = target
        self.genius = genius ?? GeniusMenu()
        self.player = playTrack
        self.clock = clock
        self.event = event
        self.isAlive = isAlive
        self.local = local
    }

    // MARK: 受管指令

    public func submit(_ command: ManagedCommand, connection: UUID) async -> ManagedOutcome {
        let now = await clock.now()
        dropDeadWaiters()
        let id = UUID()
        guard case .accepted(_, let superseded) = admission.admit(command.kind, now: now, id: id) else { return .error(.busy) }
        if let superseded, let entry = waiting.first(where: { $0.id == superseded }) {
            waiting.removeAll { $0.id == superseded }
            entry.continuation.resume(returning: .error(.superseded))
        }
        acceptedCount += 1
        return await withCheckedContinuation { continuation in
            waiting.append(Entry(id: id, command: command, connection: connection, continuation: continuation))
            startNextIfIdle()
        }
    }

    private func dropDeadWaiters() {
        for entry in waiting where !isAlive(entry.connection) {
            admission.release(entry.id)
            entry.continuation.resume(returning: .dropped)
        }
        waiting.removeAll { !isAlive($0.connection) }
    }

    private func startNextIfIdle() {
        guard runningKind == nil else { return }
        dropDeadWaiters()
        guard !waiting.isEmpty else { return }
        let entry = waiting.removeFirst()
        runningKind = entry.command.kind
        admission.start(entry.id)
        Task {
            let (outcome, holdUntil) = await self.execute(entry)
            entry.continuation.resume(returning: outcome)
            // 回覆與放行分開（thecure 2026-10-18，N-01）：換曲後回覆提早，但執行中那筆的位置與預約要保留到
            // 「換曲觀測＋gateSettle」，期間不送下一個受管指令（S0 B2：太快連送 Music 會延遲或吞指令）
            if let holdUntil, case let wait = holdUntil - (await self.clock.now()), wait > 0 {
                try? await self.clock.sleep(seconds: wait)
            }
            await self.release(entry)
        }
    }

    private func release(_ entry: Entry) {
        admission.release(entry.id)
        runningKind = nil
        startNextIfIdle()
    }

    /// 回傳結果，以及（換曲成功時）佇列要保留到的時刻
    private func execute(_ entry: Entry) async -> (ManagedOutcome, holdUntil: Double?) {
        let isAlive = self.isAlive, connection = entry.connection
        let alive: @Sendable () -> Bool = { isAlive(connection) }
        switch entry.command {
        case .next: return await step(forward: true, alive: alive)
        case .previous: return await step(forward: false, alive: alive)
        case .genius: return await pressGenius(alive: alive)
        case .playTrack(let request):
            switch await player.play(request, shouldContinue: alive) {
            case .result(let result): return (.play(result), nil)
            case .error(let code): return (.error(code), nil)
            case .abandoned: return (.dropped, nil)
            }
        }
    }

    /// 閘門：送出後每 0.1 s 讀回；看到目前曲改變＝立刻回 applied，佇列保留到觀測後 gateSettle；
    /// 送完後 3 s 內沒變＝notApplied（附讀回狀態、立刻放行）。期限與硬上限都自「送完」起算（設計 §4.4「自送出起」；
    /// Music 忙時 Apple Event 本身可花到 2 s，Codex S4 後半 P2），倒回判斷的外推仍自送出前起算（送出期間歌也在播）。
    /// 上一首另認「同一首倒回開頭」（Music 的 previous track 播數秒後先回開頭，#4-1 真機）：見 `RewindWatch`，確認後同樣保留 gateSettle。
    /// 送出前連線已不在＝不送（security review MEDIUM-1）；等待中連線不在＝不再讀 Music、以 .dropped 結束。
    /// 硬上限「3 s 期限＋確認倒回所需的 gateSettle」：倒回候補後 Music 一直回報沒有目前曲也不會無限讀下去（S4 後半 security MEDIUM-1）
    private func step(forward: Bool, alive: @Sendable () -> Bool) async -> (ManagedOutcome, holdUntil: Double?) {
        let before: MusicSnapshot
        let sentAt: Double
        let dispatchedAt: Double
        do {
            before = try await target.snapshot()
            sentAt = await clock.now()
            guard alive() else { return (.dropped, nil) }
            try await (forward ? target.next() : target.previous())
            dispatchedAt = await clock.now()
        } catch {
            return (.error(Self.code(error)), nil)
        }
        var rewind = forward ? nil : RewindWatch(before: before, sentAt: sentAt)
        var last = before
        // 送出後還沒讀成功過＝期限到時回最後一次讀取錯誤，不拿送出前的舊狀態假裝 notApplied（simcodex R2 Codex P2）
        var lastFailure: MusicLaneError?
        var readOnce = false
        while true {
            try? await clock.sleep(seconds: PlaybackLimits.arrivalPollInterval)
            guard alive() else { return (.dropped, nil) }
            // 過了期限就不再開新的讀回（Codex 2026-10-19 第 3 輪）：最後一次讀回必在期限前開始，最壞＝送出前讀回 2 s＋送出 2 s＋4 s＋讀回 2 s＝10 s（`worstNextPrevious` 取 11）
            let startAt = await clock.now()
            if startAt - dispatchedAt >= PlaybackLimits.gateNoChangeDeadline + PlaybackLimits.gateSettle
                || (rewind?.candidateAt == nil && startAt - dispatchedAt >= PlaybackLimits.gateNoChangeDeadline) {
                Self.trace(Self.gateLine(forward: forward, path: "none", sendSeconds: dispatchedAt - sentAt, detectSeconds: startAt - sentAt))
                if !readOnce, let lastFailure { return (.error(Self.code(lastFailure)), nil) }
                return (.control(ControlResult(outcome: .notApplied, playback: await event(last))), nil)
            }
            // 有沒有換曲：以讀回「開始」的時刻判（期限內開始的讀回看到變化就算，不製造假的「沒有生效」）；
            // 要不要結束：以讀回「讀完」的時刻判（讀回很慢時也不會多讀一輪，最壞仍在 `worstNextPrevious` 內；Codex 2026-10-19）。
            // 判定與開始讀回之間不再取第二次時間（Codex 第 4 輪）
            let now = startAt
            let snapshot: MusicSnapshot
            do {
                snapshot = try await target.snapshot()
            } catch {
                // 讀取失敗可重試：交給迴圈開頭的期限判定結束（倒回候補照樣讀到硬上限；曾讀成功過就回最後一次讀到的狀態）
                guard case .failed = error else { return (.error(Self.code(error)), nil) }
                lastFailure = error
                continue
            }
            let readDoneAt = await clock.now()
            last = snapshot
            readOnce = true
            let changed = rewind?.candidateAt == nil && snapshot.trackID != before.trackID
            let rewound = !changed && rewind?.observe(snapshot, at: now, beforeDeadline: now - dispatchedAt < PlaybackLimits.gateNoChangeDeadline) == true
            if changed || rewound {
                Self.trace(Self.gateLine(forward: forward, path: changed ? "changed" : "rewind", sendSeconds: dispatchedAt - sentAt,
                                         detectSeconds: now - sentAt))
                return (.control(ControlResult(outcome: .applied, playback: await event(snapshot))), now + PlaybackLimits.gateSettle)
            }
            let pastHardCap = readDoneAt - dispatchedAt >= PlaybackLimits.gateNoChangeDeadline + PlaybackLimits.gateSettle
            if pastHardCap || (rewind?.candidateAt == nil && readDoneAt - dispatchedAt >= PlaybackLimits.gateNoChangeDeadline) {
                Self.trace(Self.gateLine(forward: forward, path: "none", sendSeconds: dispatchedAt - sentAt, detectSeconds: readDoneAt - sentAt))
                return (.control(ControlResult(outcome: .notApplied, playback: await event(snapshot))), nil)
            }
        }
    }

    /// Genius（CR-030）：定位後才取按下前讀回（定位期間的自然換歌不算 Genius 生效）；按下前最後一刻查連線。
    /// 沒按＝錯誤回覆；按了＝一律以讀回確認：看到目前曲換了（空 ID 略過）＝applied、保留 gateSettle；
    /// 按完 3 s 內沒換＝ControlResult.notApplied（按下可能已改寫「接下來」，iPad 顯示「無法確認」）。讀回全失敗也回 ControlResult
    private func pressGenius(alive: @escaping @Sendable () -> Bool) async -> (ManagedOutcome, holdUntil: Double?) {
        let target = self.target
        let prepared = OSAllocatedUnfairLock<Result<MusicSnapshot, MusicLaneError>?>(initialState: nil)
        let press = await genius.pressGenius(prepare: {
            do throws(MusicLaneError) {
                let snapshot = try await target.snapshot()
                prepared.withLock { $0 = .success(snapshot) }
                return true
            } catch {
                prepared.withLock { $0 = .failure(error) }
                return false
            }
        }, stillWanted: { alive() })
        switch press {
        case .refused(let code):
            return (.error(code), nil)
        case .withheld:
            if case .failure(let error) = prepared.withLock({ $0 }) { return (.error(Self.code(error)), nil) }
            return (.dropped, nil)
        case .pressed:
            guard case .success(let before) = prepared.withLock({ $0 }) else { return (.dropped, nil) }
            return await confirmGenius(before: before, pressedAt: await clock.now(), alive: alive)
        }
    }

    private func confirmGenius(before: MusicSnapshot, pressedAt: Double,
                               alive: @Sendable () -> Bool) async -> (ManagedOutcome, holdUntil: Double?) {
        var last = before
        while true {
            try? await clock.sleep(seconds: PlaybackLimits.arrivalPollInterval)
            guard alive() else { return (.dropped, nil) }
            let startAt = await clock.now()
            if startAt - pressedAt >= PlaybackLimits.gateNoChangeDeadline { break }
            guard let snapshot = try? await target.snapshot() else { continue }
            last = snapshot
            if let id = snapshot.trackID, id != before.trackID {
                Self.trace("genius path=changed detectMs=\(Int(((startAt - pressedAt) * 1000).rounded()))")
                return (.control(ControlResult(outcome: .applied, playback: await event(snapshot))), startAt + PlaybackLimits.gateSettle)
            }
            if await clock.now() - pressedAt >= PlaybackLimits.gateNoChangeDeadline { break }
        }
        Self.trace("genius path=none")
        return (.control(ControlResult(outcome: .notApplied, playback: await event(last))), nil)
    }

    /// #4-1 N-01 診斷（DEBUG）：方向、判定路徑、送出耗時（送出開始 → 送完）、送出開始 → 看到變化；只有數字
    static func gateLine(forward: Bool, path: String, sendSeconds: Double, detectSeconds: Double) -> String {
        "gate dir=\(forward ? "next" : "previous") path=\(path) sendMs=\(Int((sendSeconds * 1000).rounded())) detectMs=\(Int((detectSeconds * 1000).rounded()))"
    }

    private static func trace(_ line: @autoclosure () -> String) { RelayTrace.notice(line()) }

    /// 播放／暫停讀回中（單飛）
    private var toggleInFlight = false

    // MARK: 不受閘門管的指令（仍經 MusicLane 單一序列）

    /// 送出後讀回到狀態改變＝applied；期限內都沒變＝notApplied（附讀回）。Music 會晚幾百毫秒才反映（#4-1）。
    /// 讀回期間再來的 toggle＝busy、不送第二個 playpause（互相翻回會讓每筆都讀滿期限；S4 後半 security LOW-2）
    public func toggle() async -> Result<ControlResult, ErrorCode> {
        guard !toggleInFlight, runningKind != .genius else { return .failure(.busy) }
        toggleInFlight = true
        defer { toggleInFlight = false }
        var intent: UUID?
        do {
            let before = try await target.snapshot()
            // 送出前登記在途意圖（讀回期間點歌狀態機就能解釋這次變化）；確認或撤銷見下（simcodex R2 第 5 項）
            intent = await local?.begin(.toggle(stateAfter: before.state == .playing ? .paused : .playing), at: await clock.now())
            try await target.togglePlayPause()
            let sentAt = await clock.now()
            var after = try await target.snapshot()
            var reads = [after.state.rawValue]
            while after.state == before.state, await clock.now() - sentAt < PlaybackLimits.toggleReadbackDeadline {
                try? await clock.sleep(seconds: PlaybackLimits.toggleReadbackInterval)
                after = try await target.snapshot()
                reads.append(after.state.rawValue)
            }
            let doneAt = await clock.now()
            // #4-1 N-01 重量：連續切換偶發等滿 1 s 的 notApplied，記下送出前與每次讀回的狀態以判讀（DEBUG 才組字）
            Self.trace("toggle before=\(before.state.rawValue) reads=\(reads.joined(separator: ",")) readMs=\(Int((doneAt - sentAt) * 1000))")
            let applied = after.state != before.state
            if let intent {
                if applied { await local?.confirm(intent, as: .toggle(stateAfter: after.state), at: doneAt) } else { await local?.revoke(intent) }
            }
            return .success(ControlResult(outcome: applied ? .applied : .notApplied, playback: await event(after)))
        } catch {
            if let intent { await local?.revoke(intent) }
            return .failure(Self.code(error))
        }
    }

    /// 只對請求指定的曲目生效：目前曲已換或超過曲長＝notApplied（請求本身合法）
    public func seek(_ request: SeekRequest) async -> Result<ControlResult, ErrorCode> {
        guard runningKind != .genius else { return .failure(.busy) }
        var intent: UUID?
        do {
            let before = try await target.snapshot()
            // #6-1 F11 診斷：只記曲目 ID 末 6 碼與秒數
            let line = "seek req=\((request.trackID).suffix(6)) to=\(Int(request.seconds)) now=\((before.trackID ?? "-").suffix(6)) pos=\(Int(before.position)) dur=\(before.duration.map { String(Int($0)) } ?? "nil")"
            guard before.trackID == request.trackID, request.seconds <= (before.duration ?? .infinity) else {
                Self.trace("\(line) outcome=notApplied why=\(before.trackID == request.trackID ? "beyondDuration" : "trackMismatch")")
                return .success(ControlResult(outcome: .notApplied, playback: await event(before)))
            }
            intent = await local?.begin(.seek(positionAfter: request.seconds), at: await clock.now())
            try await target.seek(to: request.seconds)
            let after = try await target.snapshot()
            Self.trace("\(line) outcome=applied after=\(Int(after.position))")
            if let intent { await local?.confirm(intent, as: .seek(positionAfter: after.position), at: await clock.now()) }
            return .success(ControlResult(outcome: .applied, playback: await event(after)))
        } catch {
            Self.trace("seek req=\((request.trackID).suffix(6)) to=\(Int(request.seconds)) error=\(error)")
            if let intent { await local?.revoke(intent) }
            return .failure(Self.code(error))
        }
    }

    /// Music 沒在跑／未授權照實回；其他 AE 錯誤（逾時等）＝busy（可重試）
    static func code(_ error: MusicLaneError) -> ErrorCode {
        switch error {
        case .notRunning: .musicNotRunning
        case .notAuthorized: .musicNotAuthorized
        case .failed: .busy
        }
    }
}
#endif

/// 上一首的「同一首倒回」判定（thecure 2026-10-18 定案）：
/// 候補＝送出前有目前曲、讀回同一首且不是停止、進度比「照常播放應到的位置」少 `rewindTolerance` 以上（只在 3 s 期限內才立候補）；
/// 候補後每次讀回都要仍是同一首、進度不超過「候補位置＋候補後應走的時間＋容差」，滿 `gateSettle`＝確認。
/// 空 ID 的讀回略過（換歌瞬間 Music 會回報空 ID）；單發的 0（讀不到進度）會在下一次讀回被取消。
struct RewindWatch {
    private let before: MusicSnapshot
    private let sentAt: Double
    private(set) var candidateAt: Double?
    private var candidatePosition: Double = 0

    init(before: MusicSnapshot, sentAt: Double) {
        self.before = before
        self.sentAt = sentAt
    }

    /// 回傳 true＝倒回已確認
    mutating func observe(_ snapshot: MusicSnapshot, at now: Double, beforeDeadline: Bool) -> Bool {
        guard let trackID = before.trackID, before.state != .stopped else { return false }
        guard let current = snapshot.trackID else { return false }
        guard current == trackID, snapshot.state != .stopped else { candidateAt = nil; return false }
        if let candidateAt {
            let allowed = snapshot.state.projected(candidatePosition, after: now - candidateAt) + PlaybackLimits.rewindTolerance
            guard snapshot.position <= allowed else { self.candidateAt = nil; return false }
            return now - candidateAt >= PlaybackLimits.gateSettle
        }
        let expected = before.state.projected(before.position, after: now - sentAt)
        if beforeDeadline, snapshot.position + PlaybackLimits.rewindTolerance < expected {
            candidateAt = now
            candidatePosition = snapshot.position
        }
        return false
    }
}

