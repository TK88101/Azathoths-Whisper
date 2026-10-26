#if os(macOS)
import Foundation
import os
import RemoteProtocol

// play.track 狀態機（設計 §5.3、CR-005、CR-014；sprint-4-detail.md §4.5）。期限全部可注入時鐘：
// 許可 → 捷徑可用（識別碼仍在）→ 基準觀測 → 啟動捷徑（自此不可取消）→ 等目標曲到達 → 等捷徑結束
// → 佇列穩定 → 比對（符合＝verified；不符＝降級一次）。捷徑無回應＝全域隔離；結果出來前偵測到 Mac 上手動操作＝indeterminate。
// 本型別只對自己的請求動 Music；降級最多一次；回覆後不再為這筆請求操作。

/// 點歌計畫來源（正式＝CatalogService）
public protocol PlayPlanProviding: Sendable {
    func plan(for request: PlayTrackRequest) async -> Result<AdmissionResult, ErrorCode>
}

extension CatalogService: PlayPlanProviding {}

public protocol ShortcutBindingChecking: Sendable {
    func status() async -> ShortcutBindingStatus
}

extension ShortcutBinding: ShortcutBindingChecking {}

public protocol ShortcutStarting: Sendable {
    func start(_ shortcut: ShortcutIdentifier, input: ShortcutInput) -> RunningShortcut?
}

extension ShortcutRunner: ShortcutStarting {}

/// 狀態機需要的 Music 操作
public protocol PlayTarget: ControlTarget {
    func playOnce(trackID: String) async throws(MusicLaneError) -> Bool
}

extension MusicLane: PlayTarget {}

/// Queue.dat 的唯讀觀測（實作在 App/Remote，包 Azathoth 既有唯讀模組；EchoKit 不碰該檔，echo_gate E6）。
/// nil＝讀不到或不是順序播放；ID 一律小寫
public protocol QueueReading: Sendable {
    func read() async -> [String]?
}

/// iPad 送來、已執行的 toggle／seek（AE 完成並讀回後記下）：狀態機用來區分本地操作與 Mac 上的手動操作
public actor LocalOperationLog {
    public enum Operation: Sendable, Equatable {
        case toggle(stateAfter: PlaybackState)
        case seek(positionAfter: Double)
    }

    public struct Entry: Sendable, Equatable {
        public let operation: Operation
        public let at: Double
    }

    private var entries: [Entry] = []
    /// 在途意圖：指令送出前登記的預期效果，讀回確認（confirm）或沒生效／失敗（revoke）前都算本地操作——
    /// 點歌狀態機與 toggle 讀回交錯讀 Music，讀回結束前就可能看到變化（simcodex R2 第 5 項，Codex 設計）
    private var pending: [UUID: Entry] = [:]

    public init() {}

    public func record(_ operation: Operation, at time: Double) {
        entries.append(Entry(operation: operation, at: time))
        entries.removeAll { time - $0.at > PlaybackLimits.localOperationWindow * 4 }
    }

    public func begin(_ operation: Operation, at time: Double) -> UUID {
        let id = UUID()
        pending[id] = Entry(operation: operation, at: time)
        return id
    }

    /// 讀回確認：在途意圖換成實際讀到的效果
    public func confirm(_ id: UUID, as operation: Operation, at time: Double) {
        pending[id] = nil
        record(operation, at: time)
    }

    public func revoke(_ id: UUID) { pending[id] = nil }

    func recent(now: Double) -> [Entry] {
        let confirmed = entries.filter { now - $0.at <= PlaybackLimits.localOperationWindow && $0.at <= now }
        return confirmed + pending.values.filter { $0.at <= now }.sorted { $0.at < $1.at }
    }
}

/// 判成手動操作的規則與數值（只有 ID 與數字）；字面只在 DEBUG 診斷時才組（description 與舊字串逐字相同）
enum ManualReason: CustomStringConvertible {
    case track(from: String?, to: String?)
    case state(from: PlaybackState, to: PlaybackState)
    case jump(predicted: Double, actual: Double, state: PlaybackState)

    var description: String {
        switch self {
        case .track(let from, let to): "track \(from ?? "-")→\(to ?? "-")"
        case .state(let from, let to): "state \(from.rawValue)→\(to.rawValue)"
        case .jump(let predicted, let actual, let state):
            String(format: "jump predicted=%.2f actual=%.2f state=%@", predicted, actual, state.rawValue)
        }
    }
}

/// 手動操作偵測（純值）：以錨點外推；期待序列內的「下一首」＝自然推進；本地操作在讀回後 2 s 內可解釋
struct ManualChangeDetector {
    let expected: [String]
    private(set) var anchor: MusicSnapshot
    private var anchorAt: Double
    /// 最近一次判成手動操作的規則與數值（只有 ID 與數字；DEBUG 診斷用）
    private(set) var lastReason: ManualReason?
    /// 短暫異常（空 ID、同一首忽然停止）開始的時刻：持續未滿 `transientTolerance` 不判、錨點不動
    private var transientSince: Double?

    init(expected: [String], anchor: MusicSnapshot, at time: Double) {
        self.expected = expected
        self.anchor = anchor
        anchorAt = time
    }

    /// 以這次觀測為新錨點（不判斷）
    mutating func rebase(_ snapshot: MusicSnapshot, at time: Double) {
        anchor = snapshot
        anchorAt = time
    }

    /// true＝無法解釋的變化（Mac 上的手動操作）
    /// `checkPosition`：到達前為 false——捷徑下播放指令時 Music 會先回報「舊曲目 ID、位置歸零」（#4-1 實測），位置跳動不可靠
    mutating func observe(_ snapshot: MusicSnapshot, at now: Double, local: [LocalOperationLog.Entry],
                          checkPosition: Bool = true) -> Bool {
        // #4-1 N-01 真機：換曲瞬間 Music 會短暫回報空 ID 或「停止」，下一次讀回就恢復——曾誤判手動、終止捷徑並隔離
        if isTransient(snapshot) {
            let since = transientSince ?? now
            transientSince = since
            if now - since < PlaybackLimits.transientTolerance { return false }
        } else {
            transientSince = nil
        }
        defer { anchor = snapshot; anchorAt = now }
        if snapshot.trackID != anchor.trackID {
            lastReason = .track(from: anchor.trackID, to: snapshot.trackID)
            guard let current = anchor.trackID, let index = expected.firstIndex(of: current), index + 1 < expected.count
            else { return true }
            return snapshot.trackID != expected[index + 1]
        }
        // 同一首由「停止」變「播放中」＝開始播放的過程（#4-1 實測：捷徑換歌時 Music 先回報目標曲停止、位置 0，0.1 s 後才播放），不判手動
        let startedPlaying = anchor.state == .stopped && snapshot.state == .playing
        if snapshot.state != anchor.state, !startedPlaying,
           !local.contains(where: { $0.operation == .toggle(stateAfter: snapshot.state) }) {
            lastReason = .state(from: anchor.state, to: snapshot.state)
            return true
        }
        guard checkPosition else { return false }
        let predicted = anchor.state.projected(anchor.position, after: now - anchorAt)
        guard abs(snapshot.position - predicted) > PlaybackLimits.manualJumpTolerance else { return false }
        lastReason = .jump(predicted: predicted, actual: snapshot.position, state: snapshot.state)
        return !local.contains { entry in
            guard case .seek(let target) = entry.operation else { return false }
            let progressed = snapshot.state.projected(target, after: now - entry.at)
            return abs(snapshot.position - progressed) <= PlaybackLimits.manualJumpTolerance
        }
    }
}

extension ManualChangeDetector {
    private func isTransient(_ snapshot: MusicSnapshot) -> Bool {
        if anchor.trackID != nil, snapshot.trackID == nil { return true }
        return snapshot.trackID == anchor.trackID && snapshot.state == .stopped && anchor.state != .stopped
    }
}

public actor PlayTrackMachine: PlayTrackRunning {
    private let plans: any PlayPlanProviding
    private let binding: any ShortcutBindingChecking
    private let starter: any ShortcutStarting
    private let music: any PlayTarget
    private let queue: any QueueReading
    private let clock: any ControlClock
    private let local: LocalOperationLog
    private let onArrival: @Sendable (MusicSnapshot) -> Void
    /// 全域隔離：捷徑無回應時起算；至少 10 s，之後觀測到連續 3 s 靜止才解除（§4.5 步驟 9）
    private var quarantinedAt: Double?
    private var quiet: (key: String, since: Double)?

    public init(plans: any PlayPlanProviding, binding: any ShortcutBindingChecking, starter: any ShortcutStarting,
                music: any PlayTarget, queue: any QueueReading, clock: any ControlClock = SystemControlClock(),
                local: LocalOperationLog, onArrival: @escaping @Sendable (MusicSnapshot) -> Void) {
        self.plans = plans
        self.binding = binding
        self.starter = starter
        self.music = music
        self.queue = queue
        self.clock = clock
        self.local = local
        self.onArrival = onArrival
    }

    public var isQuarantined: Bool { quarantinedAt != nil }

    // MARK: 隔離

    /// 輪詢器在隔離期間回報觀測（目前曲、狀態、Queue.dat）；最短隔離過後連續 3 s 不變即解除
    public func observeQuiet(_ snapshot: MusicSnapshot, queue ids: [String]?) async {
        guard let since = quarantinedAt else { return }
        let now = await clock.now()
        guard now - since >= PlaybackLimits.shortcutQuarantine else { return }
        let key = "\(snapshot.trackID ?? "-")|\(snapshot.state.rawValue)|\((ids ?? []).joined(separator: ","))"
        if let quiet, quiet.key == key {
            if now - quiet.since >= PlaybackLimits.queueStableSpan { quarantinedAt = nil; self.quiet = nil }
        } else {
            quiet = (key, now)
        }
    }

    private func quarantine() async {
        quarantinedAt = await clock.now()
        quiet = nil
    }

    // MARK: 點歌

    public func play(_ request: PlayTrackRequest, shouldContinue: @escaping @Sendable () -> Bool) async -> PlayTrackOutcome {
        // 捷徑啟動前都還沒動 Music：每個不可逆動作之前確認連線仍在，不在就放棄（security review MEDIUM-1）。
        // 捷徑啟動後（含其後的降級）照 §4.4「執行中的照常做完」，不再查
        func degradeIfStill(_ reason: PlayReason) async -> PlayTrackOutcome {
            shouldContinue() ? await degrade(request.trackID, reason) : .abandoned
        }
        // 隔離中一律擋（連目錄閘門拒絕後的降級 playOnce 也不做；simcodex R2 security LOW-2，使用者 2026-10-19 同意）
        if isQuarantined { return Self.indeterminate(.shortcutUnresponsive) }
        let plan: ShortcutPlan
        switch await plans.plan(for: request) {
        case .failure(let code): return .error(code)
        case .success(.refused(let reason)): return await degradeIfStill(reason)
        case .success(.admitted(let admitted)): plan = admitted
        }
        guard case .bound(let shortcut) = await binding.status() else { return await degradeIfStill(.shortcutMissing) }
        guard let input = plan.input(startingAt: request.trackID), let expected = plan.expected(from: request.trackID)
        else { return .error(.invalidRequest) }
        let baseline: MusicSnapshot
        do { baseline = try await music.snapshot() } catch { return .error(RemoteCommandQueue.code(error)) }
        let baselineQueue = await queue.read()
        guard shouldContinue() else { return .abandoned }
        guard let running = starter.start(shortcut, input: input) else { return await degradeIfStill(.shortcutFailed) }
        let exit = ExitBox()
        Task { exit.set(await running.wait()) }
        return await follow(running, exit: exit, target: request.trackID, expected: expected, album: Set(plan.order),
                            baseline: baseline, baselineQueue: baselineQueue)
    }

    private func follow(_ running: RunningShortcut, exit: ExitBox, target: String, expected: [String], album: Set<String>,
                        baseline: MusicSnapshot, baselineQueue: [String]?) async -> PlayTrackOutcome {
        let started = await clock.now()
        var beforeArrival = ManualChangeDetector(expected: [], anchor: baseline, at: started)
        // 5. 等目標曲到達
        var arrived: MusicSnapshot?
        while arrived == nil {
            let now = await clock.now()
            let snapshot: MusicSnapshot
            do { snapshot = try await music.snapshot() } catch { return await abandon(running, exit, error) }
            if snapshot.trackID == target,
               baseline.trackID != target || Self.restarted(snapshot, from: baseline, after: now - started) || exit.value?.code == 0 {
                arrived = snapshot
                onArrival(snapshot)
                break
            }
            if await manualBeforeArrival(snapshot, at: now, detector: &beforeArrival, album: album) {
                Self.trace("pre-arrival \(beforeArrival.lastReason.map { String(describing: $0) } ?? "track-outside-album \(snapshot.trackID ?? "-")")")
                return await manualChange(running, exit)
            }
            if let ended = exit.value {
                guard ended.code != 0 else {
                    if now - started >= PlaybackLimits.targetArrivalDeadline { return Self.indeterminate(.targetTimeout) }
                    try? await clock.sleep(seconds: PlaybackLimits.arrivalPollInterval)
                    continue
                }
                return await untouched(baseline, baselineQueue) ? await degrade(target, .shortcutFailed) : Self.indeterminate(.lateChange)
            }
            if now - started >= PlaybackLimits.targetArrivalDeadline {
                return await unresponsive(running)
            }
            try? await clock.sleep(seconds: PlaybackLimits.arrivalPollInterval)
        }
        var detector = ManualChangeDetector(expected: expected, anchor: arrived!, at: await clock.now())
        // 6. 等捷徑結束（verified／degraded 的前提）
        while exit.value == nil {
            if await clock.now() - started >= PlaybackLimits.shortcutExitDeadline { return await unresponsive(running) }
            try? await clock.sleep(seconds: PlaybackLimits.arrivalPollInterval)
            if await observe(&detector) != nil {
                Self.trace("waiting-exit \(detector.lastReason.map { String(describing: $0) } ?? "-")")
                return await manualChange(running, exit)
            }
        }
        guard exit.value?.code == 0 else { return Self.indeterminate(.lateChange) }
        // 7. 佇列穩定（捷徑結束後起算）
        let exitedAt = await clock.now()
        var reads: [(at: Double, ids: [String]?)] = []
        while true {
            let now = await clock.now()
            if let manual = await observe(&detector) {
                Self.trace("queue-settle \(detector.lastReason.map { String(describing: $0) } ?? "-")")
                return manual
            }
            let ids = await queue.read()
            reads.append((now, ids))
            if let stable = Self.stable(reads) {
                // 8. 比對：自然推進後的佇列是「從目前曲起」的後綴
                let current = detector.anchor.trackID ?? target
                let start = expected.firstIndex(of: current) ?? 0
                return stable == Array(expected[start...]) ? .result(PlayResult(outcome: .verified, reason: nil))
                                                           : await degrade(target, .queueMismatch)
            }
            if now - exitedAt >= PlaybackLimits.queueSettleDeadline { return Self.indeterminate(.queueTimeout) }
            try? await clock.sleep(seconds: PlaybackLimits.queuePollInterval)
        }
    }

    /// 點的正是正在播的那首時（#4-1 N-01 真機），要看到它從頭開始才算到達：位置比照常播放應到的位置明顯倒回
    private static func restarted(_ snapshot: MusicSnapshot, from baseline: MusicSnapshot, after elapsed: Double) -> Bool {
        let expected = baseline.state.projected(baseline.position, after: elapsed)
        return snapshot.position + PlaybackLimits.rewindTolerance < expected
    }

    /// 到達前（§4.5「從捷徑發起到出結果之間」）：還停在基準曲時被暫停、且本地操作無法解釋＝手動（位置跳動不判，見 observe）
    /// （由停住變播放可能是捷徑本身，只換錨點不判）；換到基準曲與這張專輯以外的曲目＝手動
    private func manualBeforeArrival(_ snapshot: MusicSnapshot, at now: Double, detector: inout ManualChangeDetector,
                                     album: Set<String>) async -> Bool {
        // 換到專輯內的其他曲目：可能是捷徑排佇列的過渡，不判；錨點留在基準曲（到達後由步驟 6 的偵測接手）
        guard snapshot.trackID == detector.anchor.trackID else {
            return snapshot.trackID.map { !album.contains($0) } ?? false
        }
        if detector.anchor.state != .playing, snapshot.state == .playing {
            detector.rebase(snapshot, at: now)
            return false
        }
        return detector.observe(snapshot, at: now, local: await local.recent(now: now), checkPosition: false)
    }

    /// 觀測一次並判斷手動操作；讀取失敗不判（下一次再看）
    private func observe(_ detector: inout ManualChangeDetector) async -> PlayTrackOutcome? {
        let now = await clock.now()
        guard let snapshot = try? await music.snapshot() else { return nil }
        let recent = await local.recent(now: now)
        return detector.observe(snapshot, at: now, local: recent) ? Self.indeterminate(.manualChange) : nil
    }

    /// 同一 ID 序列連續觀測、跨 queueStableSpan 才算穩定；中間不同或讀不到就重新起算（S0 QueueSettle）
    static func stable(_ reads: [(at: Double, ids: [String]?)]) -> [String]? {
        var runStart: (at: Double, ids: [String])?
        for read in reads {
            guard let ids = read.ids else { runStart = nil; continue }
            guard let start = runStart, start.ids == ids else { runStart = (read.at, ids); continue }
            if read.at - start.at >= PlaybackLimits.queueStableSpan { return ids }
        }
        return nil
    }

    /// 捷徑非零結束後再讀兩次（間隔 0.5 s）：目前曲、狀態、Queue.dat 都與基準相同且兩次一致＝Music 未被動過
    private func untouched(_ baseline: MusicSnapshot, _ baselineQueue: [String]?) async -> Bool {
        var observations: [(String?, PlaybackState, [String]?)] = []
        for index in 0..<2 {
            if index > 0 { try? await clock.sleep(seconds: PlaybackLimits.queuePollInterval) }
            guard let snapshot = try? await music.snapshot() else { return false }
            observations.append((snapshot.trackID, snapshot.state, await queue.read()))
        }
        return observations.allSatisfy { $0.0 == baseline.trackID && $0.1 == baseline.state && $0.2 == baselineQueue }
    }

    /// DEBUG 診斷：判成手動操作時記下觸發規則（只有曲目 ID 與數字）；Release 不含
    static func trace(_ message: @autoclosure () -> String) { RelayTrace.notice("manual \(message())") }

    /// 偵測到 Mac 上的手動操作：捷徑若還在跑就終止並隔離，免得它之後蓋掉使用者的操作（Codex S4 R3 P1；同步驟 9 的理由）
    private func manualChange(_ running: RunningShortcut, _ exit: ExitBox) async -> PlayTrackOutcome {
        if exit.value == nil {
            running.terminate()
            await quarantine()
        }
        return Self.indeterminate(.manualChange)
    }

    private func unresponsive(_ running: RunningShortcut) async -> PlayTrackOutcome {
        running.terminate()
        await quarantine()
        return Self.indeterminate(.shortcutUnresponsive)
    }

    /// 捷徑啟動後 Music 讀不到（關掉或權限被收回）：還在跑的捷徑終止並隔離，回對應錯誤
    private func abandon(_ running: RunningShortcut, _ exit: ExitBox, _ error: MusicLaneError) async -> PlayTrackOutcome {
        if exit.value == nil {
            running.terminate()
            await quarantine()
        }
        return .error(RemoteCommandQueue.code(error))
    }

    /// 只播這首（整個請求最多一次）：查不到、AE 失敗或 6 s 內沒到＝fallbackFailed
    private func degrade(_ trackID: String, _ reason: PlayReason) async -> PlayTrackOutcome {
        do {
            guard try await music.playOnce(trackID: trackID) else { return Self.indeterminate(.fallbackFailed) }
            let started = await clock.now()
            while await clock.now() - started < PlaybackLimits.targetArrivalDeadline {
                if try await music.snapshot().trackID == trackID { return .result(PlayResult(outcome: .degraded, reason: reason)) }
                try? await clock.sleep(seconds: PlaybackLimits.arrivalPollInterval)
            }
            return Self.indeterminate(.fallbackFailed)
        } catch {
            return .error(RemoteCommandQueue.code(error))
        }
    }

    static func indeterminate(_ reason: PlayReason) -> PlayTrackOutcome {
        .result(PlayResult(outcome: .indeterminate, reason: reason))
    }
}

/// 捷徑子行程的結束結果（背景等待寫入，狀態機輪詢讀取）
final class ExitBox: @unchecked Sendable {
    private let lock = NSLock()
    private var exit: ProcessExit?
    var value: ProcessExit? { lock.withLock { exit } }
    func set(_ value: ProcessExit) { lock.withLock { exit = value } }
}
#endif
