import Foundation
import Observation
import OSLog

/// 日誌只記序號、狀態、是否重錨與毫秒，不記曲目（CLAUDE.md 日誌脫敏）
private let clockLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "positionClock")

/// 歌詞特效的播放位置時鐘（母計劃 §2.3；A1 計劃 §3.3）。
///
/// **錨點法**（LyricsX／lyrimuse 同款）：不存位置，存「起播時刻」`origin = readAt − seconds`，
/// 查詢時以牆鐘外推。讀數與外推差在 `tolerance` 內就不動（吃 AE 延遲與 0.1 s 精度抖動），超過才當 seek 重錨。
/// 只有 `anchor` 是 observable：容差內不改值，View 不會白白失效（母計劃 §2.7 R1-5）。
///
/// 讀取節奏：只在 active 且有當前曲時跑；播放中每 2 s、其餘每 6 s（暫停也要讀：
/// 暫停→播放的通知可能漏掉，母計劃 §2.3 R2-Q3）。busy 期間不送 AE、空閒時補讀一次（與 monitor 同一個 BusySource）
@MainActor
@Observable
final class PlaybackPositionClock {
    static let playingInterval: Duration = .seconds(2)
    static let pausedInterval: Duration = .seconds(6)
    /// 初值；實機量測後回填計劃 §8（母計劃 §2.3：不得寫成固定的驗收保證）
    static let defaultTolerance = 0.5

    enum Anchor: Equatable, Sendable {
        case running(origin: ContinuousClock.Instant)
        case frozen(seconds: Double)
    }

    private(set) var anchor: Anchor?

    /// 已處理（套用或丟棄）的讀數數；測試與日誌用
    @ObservationIgnored private(set) var readSerial = 0

    @ObservationIgnored private let music: any MusicControlling
    @ObservationIgnored private let pollClock: any PollClock
    @ObservationIgnored private let tolerance: Double
    /// 顯示時間的固定平移（秒）：兩態都加，重錨判斷不含它（Codex R1／R2）
    @ObservationIgnored private let offset: Double

    @ObservationIgnored private var trackID: String?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var busyLedger = BusyLedger()
    /// 停讀或換曲時 +1：在飛的舊讀數回來時以此自我作廢（Codex R1：生命週期世代守衛）
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isReading = false
    @ObservationIgnored private var readAgain = false
    @ObservationIgnored private var lastState: PlayerState = .stopped
    /// 上一筆套用的讀數時刻：重錨時記「距上一筆多久」，即拖進度後跟上時間的上界（A2 計劃 §6）
    @ObservationIgnored private var lastReadAt: ContinuousClock.Instant?
    @ObservationIgnored private var loopTask: Task<Void, Never>?

    init(
        music: any MusicControlling,
        pollClock: any PollClock = SystemPollClock(),
        tolerance: Double = PlaybackPositionClock.defaultTolerance,
        offset: Double = 0
    ) {
        self.music = music
        self.pollClock = pollClock
        self.tolerance = tolerance
        self.offset = offset
    }

    /// 某時刻的播放位置（秒）；nil＝不知道
    func position(at now: ContinuousClock.Instant) -> Double? {
        switch anchor {
        case .running(let origin): return (now - origin).inSeconds + offset
        case .frozen(let seconds): return seconds + offset
        case nil: return nil
        }
    }

    /// 當前曲變了才清 anchor、作廢在飛讀數；同一首重送是 no-op（Codex R2）。nil＝停讀
    func setTrack(_ persistentID: String?) {
        guard persistentID != trackID else { return }
        trackID = persistentID
        restart()
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        restart()
    }

    /// 與 monitor 同一組來源（母計劃 §2.3 R2）。全部空閒的那一刻補讀一次
    func setBusy(_ busy: Bool, source: BusySource) {
        guard busyLedger.set(busy, source: source) == .becameIdle, canRead else { return }
        Task { await read() }
    }

    /// Music 的 playerInfo 通知：不等輪詢，立刻讀（讀完重新排下一次睡眠）
    func resync() {
        guard canRead else { return }
        startLoop()
    }

    // MARK: 內部

    private var canRead: Bool { isActive && trackID != nil }

    private func restart() {
        generation += 1
        lastReadAt = nil
        loopTask?.cancel()
        loopTask = nil
        setAnchor(nil)
        if canRead { startLoop() }
    }

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self, pollClock] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.read()
                let interval = self.lastState == .playing ? Self.playingInterval : Self.pausedInterval
                do {
                    try await pollClock.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    /// 單飛：讀取進行中又被要求時，讀完再讀一次（多次合併）
    private func read() async {
        guard canRead, busyLedger.isIdle else { return }
        guard !isReading else {
            readAgain = true
            return
        }
        isReading = true
        repeat {
            readAgain = false
            await readOnce()
        } while readAgain && canRead && busyLedger.isIdle
        isReading = false
    }

    private func readOnce() async {
        let token = (generation, trackID)
        let outcome: Result<PlaybackPosition?, any Error>
        do {
            outcome = .success(try await music.playbackPosition())
        } catch {
            outcome = .failure(error)
        }
        readSerial += 1
        guard token == (generation, trackID), canRead else {
            clockLog.debug("reading \(self.readSerial, privacy: .public) discarded: stale")
            return
        }
        apply(outcome)
    }

    private func apply(_ outcome: Result<PlaybackPosition?, any Error>) {
        switch outcome {
        case .success(let reading?):
            guard reading.persistentID == trackID else { return }
            apply(reading)
        case .success(nil), .failure(MusicError.notRunning):
            lastState = .stopped
            setAnchor(nil)
        case .failure:
            break   // AE 暫時性錯誤：保留外推，下一輪再試
        }
    }

    private func apply(_ reading: PlaybackPosition) {
        lastState = reading.state
        let roundTrip = Int(reading.roundTrip.inSeconds * 1000)
        let sinceLast = lastReadAt.map { Int((reading.readAt - $0).inSeconds * 1000) } ?? -1
        lastReadAt = reading.readAt
        guard reading.state == .playing else {
            setAnchor(.frozen(seconds: reading.seconds))
            clockLog.debug("reading \(self.readSerial, privacy: .public) paused \(roundTrip, privacy: .public)ms")
            return
        }
        // 用不含 offset 的原始外推比較：含 offset 會讓 offset > tolerance 時每次都重錨（Codex R2）
        if case .running(let origin) = anchor, abs((reading.readAt - origin).inSeconds - reading.seconds) <= tolerance {
            clockLog.debug("reading \(self.readSerial, privacy: .public) kept \(roundTrip, privacy: .public)ms")
            return
        }
        setAnchor(.running(origin: reading.readAt - .seconds(reading.seconds)))
        clockLog.debug("reading \(self.readSerial, privacy: .public) reanchored \(roundTrip, privacy: .public)ms sinceLast \(sinceLast, privacy: .public)ms")
    }

    /// 值不變不寫：Observation 對任何指派都會通知
    private func setAnchor(_ new: Anchor?) {
        if anchor != new { anchor = new }
    }
}
