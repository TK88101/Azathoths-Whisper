import Foundation

/// 一首歌的查找請求。`query` 已知（特效層有 TrackInfo 與曲長）就直接用，nil 時向 Music 唯讀補讀
struct TimingRequest: Equatable, Sendable {
    let persistentID: String
    let lyrics: String
    let query: TimingQuery?
}

enum TimingPriority: Sendable {
    /// 特效層正在顯示的那首：插隊並搶占背景工作
    case visible
    /// 寫入後補做（Editor、Batch）：排隊
    case background
}

struct TimingResolution: Equatable, Sendable {
    enum SkipReason: Equatable, Sendable { case missingMetadata, disabled, queueFull, noLyrics }

    enum Outcome: Equatable, Sendable {
        case found(StoredTimingSource, [TimingRecord.LineStart])
        /// 所有來源都明確回答「沒有」（已存檔，7 天後重試）
        case notFound
        /// 有來源失敗（被擋、逾時、熔斷）：不存檔，記憶體退避
        case unavailable
        case cancelled
        case skipped(SkipReason)
    }

    let persistentID: String
    let lyricsHash: LyricsFingerprint
    let outcome: Outcome
}

extension TimingResolution.Outcome {
    init(_ stored: TimingRecord.Outcome) {
        switch stored {
        case .found(let source, let lines): self = .found(source, lines)
        case .notFound: self = .notFound
        }
    }
}

/// 開發者用的停用開關（非 UI；C 段計劃 §3.5，Codex R1 #10）
struct TimingSwitches: Equatable, Sendable {
    static let allEnabled = TimingSwitches(lookupDisabled: false, disabledSources: [])
    static let lookupDisabledKey = "TimingLookupDisabled"
    static let disabledSourcesKey = "TimingSourcesDisabled"

    let lookupDisabled: Bool
    let disabledSources: Set<StoredTimingSource>

    static func read(from defaults: UserDefaults) -> TimingSwitches {
        let names = defaults.stringArray(forKey: disabledSourcesKey) ?? []
        return TimingSwitches(lookupDisabled: defaults.bool(forKey: lookupDisabledKey), disabledSources: Set(names.compactMap(StoredTimingSource.init)))
    }
}

/// AppModel 與特效層看到的查找介面（測試以替身注入）
protocol TimingResolving: Sendable {
    func resolve(_ request: TimingRequest, priority: TimingPriority) async -> TimingResolution
    /// 存檔是不是同一份詞的 notFound（Cover Flow「尚無時間軸」；只讀本機，不連網）
    func storedNotFound(persistentID: String, lyricsHash: LyricsFingerprint) async -> Bool
    func shutdown() async
}

/// 外部時間軸的退路鏈（C 段計劃 §3.5）。
///
/// - 存檔先行：指紋相符的 found（且錨點套得上）或未滿 7 天的 notFound 直接回，不連網
/// - 依序問來源；每個來源依中繼資料排出前 3 名逐筆取、對齊，只在通過者（`LRCAligner.Alignment.isAccepted`）之間挑最好的存檔並停
///   （候選排序計劃 §3.4；第 2、3 名只在已用 ≤ 10 s 時才取，全對上就不再取）
/// - 全部明確說沒有才存 notFound；任一來源失敗＝unavailable、不存檔、記憶體退避
/// - 同 pid 同指紋加入同一份工作；新指紋取消舊工作；存檔前再比一次最新指紋，舊結果不蓋新詞
/// - 同一時間只跑一首；visible 插隊並搶占正在跑的 background（被搶占的放回佇列）；每首總時限 20 s，
///   到期時從這次已通過的候選挑（到期後才完成的不算），沒有就 unavailable
/// - `shutdown()` 後一切取消、不發請求、不寫檔
actor TimingResolver: TimingResolving {
    static let defaultQueueLimit = 500
    static let deadline: Duration = .seconds(20)
    /// 超過一天的曲長不是歌（防 `Int(duration)` 溢位，安全評審 LOW-4）
    static let maximumDuration: TimeInterval = 86_400
    /// 這首已用時間超過它就不再取同一來源的第 2、3 名（軟截點：已開始的請求仍可能用滿自己的逾時；候選排序計劃 §3.4）
    static let extraCandidateCutoff: TimeInterval = 10

    /// 一首歌的一份查找工作；同 pid 同時最多一份（`jobs` 以 pid 為鍵，以參照比對身分）
    private final class Job {
        let request: TimingRequest
        let hash: LyricsFingerprint
        var priority: TimingPriority
        var waiters: [CheckedContinuation<TimingResolution, Never>] = []
        var task: Task<Void, Never>?
        var preempted = false

        init(request: TimingRequest, hash: LyricsFingerprint, priority: TimingPriority) {
            self.request = request
            self.hash = hash
            self.priority = priority
        }
    }

    private let providers: [any TimedLyricsProvider]
    private let store: TimingStore
    private let metadata: @Sendable (String) async -> TimingQuery?
    private let switches: TimingSwitches
    private let deadlineSleeper: any PollClock
    private let clock: any MonotonicClock
    private let now: @Sendable () -> Date
    private let queueLimit: Int
    private let diagnostics: any TimingDiagnostics

    private var jobs: [String: Job] = [:]
    private var pending: [Job] = []
    private var running: Job?
    private var latestHash: [String: LyricsFingerprint] = [:]
    private var backoff = ArtworkFailureBackoff()
    private var isShutDown = false
    /// 每次執行查找配一個新號（被搶占後重跑也換號）：只有目前收集中的那一號能寫 `provisional`
    private var runCounter: UInt64 = 0
    private var acceptingRun: UInt64?
    /// 目前這個來源已通過的候選：時限到時從這裡挑（候選排序計劃 §3.5）
    private var provisional: Provisional?

    private struct Provisional {
        let run: UInt64
        let source: StoredTimingSource
        let accepted: [RankedAlignment]
        let tried: Int
    }

    init(
        providers: [any TimedLyricsProvider], store: TimingStore, metadata: @escaping @Sendable (String) async -> TimingQuery?,
        switches: TimingSwitches, deadlineSleeper: any PollClock = SystemPollClock(), clock: any MonotonicClock = SystemMonotonicClock(),
        now: @escaping @Sendable () -> Date = { Date() }, queueLimit: Int = TimingResolver.defaultQueueLimit,
        diagnostics: any TimingDiagnostics = NoopTimingDiagnostics()
    ) {
        self.providers = providers
        self.store = store
        self.metadata = metadata
        self.switches = switches
        self.deadlineSleeper = deadlineSleeper
        self.clock = clock
        self.now = now
        self.queueLimit = queueLimit
        self.diagnostics = diagnostics
    }

    var pendingCount: Int { pending.count }
    /// 目前這次查找還收不收「已通過」的候選（時限到即停收；測試用）
    var isCollectingCandidates: Bool { acceptingRun != nil }

    func resolve(_ request: TimingRequest, priority: TimingPriority) async -> TimingResolution {
        let pid = request.persistentID
        let hash = LyricsFingerprint.of(request.lyrics)
        let finished = { (outcome: TimingResolution.Outcome) in TimingResolution(persistentID: pid, lyricsHash: hash, outcome: outcome) }
        guard !isShutDown else { return finished(.cancelled) }
        // 全域停用、或每個來源都被停用：不查也不存（存 notFound 會讓重新開啟後 7 天內查不到；codex R3）
        guard !switches.lookupDisabled, providers.contains(where: { !switches.disabledSources.contains($0.source) }) else {
            return finished(.skipped(.disabled))
        }
        // 沒有歌詞行就無從對齊：不連網、不存「沒有」（codex R3）
        guard !LyricsLines.lyricTexts(request.lyrics).isEmpty else { return finished(.skipped(.noLyrics)) }
        latestHash[pid] = hash
        if let existing = jobs[pid], existing.hash != hash { finish(existing, .cancelled) }
        if let existing = jobs[pid] { return await join(existing, raisingTo: priority) }
        if let stored = await storedOutcome(for: request, hash: hash) { return finished(stored) }
        // 讀存檔期間可能已關閉、詞又變了、或別的呼叫者已開了同一份工作
        guard !isShutDown, latestHash[pid] == hash else { return finished(.cancelled) }
        if let existing = jobs[pid] { return await join(existing, raisingTo: priority) }
        guard backoff.isDue(pid, now: clock.now) else { return finished(.unavailable) }
        let job = Job(request: request, hash: hash, priority: priority)
        jobs[pid] = job
        enqueue(job)
        return await join(job, raisingTo: priority)
    }

    func storedNotFound(persistentID: String, lyricsHash: LyricsFingerprint) async -> Bool {
        guard let record = await store.load(persistentID: persistentID) else { return false }
        return record.lyricsHash == lyricsHash && record.outcome == .notFound
    }

    func shutdown() {
        isShutDown = true
        jobs.values.forEach { finish($0, .cancelled) }
    }

    // MARK: 存檔

    private func storedOutcome(for request: TimingRequest, hash: LyricsFingerprint) async -> TimingResolution.Outcome? {
        guard let record = await store.load(persistentID: request.persistentID),
              !TimingLookupPolicy.shouldLookup(record: record, currentHash: hash, now: now())
        else { return nil }
        // 錨點套不上目前的歌詞（壞檔、手改）＝當作沒有存檔，重新查找（Codex R1 #7）
        if case .found(_, let lines) = record.outcome,
           !LRCAligner.storedLinesFit(lines, lineCount: LyricsLines.lyricTexts(request.lyrics).count) {
            return nil
        }
        return TimingResolution.Outcome(record.outcome)
    }

    private func save(_ outcome: TimingRecord.Outcome, for request: TimingRequest, hash: LyricsFingerprint) async -> TimingResolution.Outcome {
        guard !Task.isCancelled, latestHash[request.persistentID] == hash else { return .cancelled }
        var kept = outcome
        do {
            // 合併後的結果才是答案：同詞已有 found 時，這次的 notFound 不會蓋掉它
            kept = try await store.save(TimingRecord(persistentID: request.persistentID, lyricsHash: hash, outcome: outcome, fetchedAt: now())).outcome
        } catch {
            diagnostics.record(.storeFailed)
        }
        backoff.recordSuccess(request.persistentID)
        return TimingResolution.Outcome(kept)
    }

    // MARK: 佇列

    private func join(_ job: Job, raisingTo priority: TimingPriority) async -> TimingResolution {
        await withCheckedContinuation { continuation in
            job.waiters.append(continuation)
            if priority == .visible { raise(job) }
            pump()
        }
    }

    private func enqueue(_ job: Job) {
        switch job.priority {
        case .visible:
            demoteOtherVisible(than: job)
            insertAheadOfBackground(job)
            preemptBackground()
        case .background:
            pending.append(job)
            dropOverflow()
        }
    }

    /// visible 排在所有 background 之前（visible 之間先來先跑）
    private func insertAheadOfBackground(_ job: Job) {
        pending.insert(job, at: pending.firstIndex { $0.priority == .background } ?? pending.endIndex)
    }

    /// 特效層一次只顯示一首：別首還沒開始的 visible 工作降為背景（快速切歌不插隊堆積，安全評審 LOW-2）。
    /// 降級而不取消：加入同一份工作的寫入後補查不得無聲消失（R3 層級審查）；降級後受背景佇列上限管。
    /// 所有變成 visible 的路徑（新工作、已在排隊或正在跑的工作被升級）都經過這裡
    private func demoteOtherVisible(than job: Job) {
        for other in pending where other.priority == .visible && other !== job {
            other.priority = .background   // 位置不動：已在背景佇列最前，新的 visible 會插在它前面
        }
        dropOverflow()
    }

    /// 已在排隊的背景工作被特效層要求：升成 visible、移到前面
    private func raise(_ job: Job) {
        guard job.priority == .background else { return }
        job.priority = .visible
        demoteOtherVisible(than: job)
        guard let index = pending.firstIndex(where: { $0 === job }) else { return }
        pending.remove(at: index)
        enqueue(job)
    }

    private func preemptBackground() {
        guard let current = running, current.priority == .background else { return }
        current.preempted = true
        current.task?.cancel()
    }

    private func dropOverflow() {
        let waiting = pending.filter { $0.priority == .background }
        guard waiting.count > queueLimit, let oldest = waiting.first else { return }
        finish(oldest, .skipped(.queueFull))
    }

    private func pump() {
        guard running == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        running = job
        job.task = Task { await self.run(job) }
    }

    private func run(_ job: Job) async {
        let outcome = await lookupWithinDeadline(job.request, hash: job.hash)
        if jobs[job.request.persistentID] === job {
            if job.preempted, outcome == .cancelled {
                job.preempted = false
                job.task = nil
                insertAheadOfBackground(job)   // 被搶占的放回背景佇列最前
            } else {
                finish(job, outcome)
            }
        }
        running = nil   // pump 只在 running == nil 時啟動工作：此刻在跑的必是這一份
        pump()
    }

    private func finish(_ job: Job, _ outcome: TimingResolution.Outcome) {
        if jobs[job.request.persistentID] === job { jobs[job.request.persistentID] = nil }
        pending.removeAll { $0 === job }
        job.task?.cancel()
        let resolution = TimingResolution(persistentID: job.request.persistentID, lyricsHash: job.hash, outcome: outcome)
        let waiters = job.waiters
        job.waiters = []
        waiters.forEach { $0.resume(returning: resolution) }
    }

    // MARK: 退路鏈

    private enum Race: Sendable {
        case finished(TimingResolution.Outcome)
        /// 時限到：當下凍結的已通過候選（之後才完成的不算）
        case expired(Provisional?)
    }

    /// 一個來源問完的結果
    private enum SourceAnswer {
        case picked(RankedAlignment, tried: Int)
        case noAnswer(hadFailure: Bool)
        case cancelled
    }

    /// 查找與 20 s 計時器賽跑；計時器被取消（查找先完成或整份工作被取消）回 nil、略過
    private func lookupWithinDeadline(_ request: TimingRequest, hash: LyricsFingerprint) async -> TimingResolution.Outcome {
        runCounter += 1
        let run = runCounter
        acceptingRun = run
        provisional = nil
        defer {
            if acceptingRun == run { acceptingRun = nil }
            if provisional?.run == run { provisional = nil }
        }
        let sleeper = deadlineSleeper
        let race = await withTaskGroup(of: Race?.self) { group -> Race in
            group.addTask { .finished(await self.lookup(request, hash: hash, run: run)) }
            group.addTask { (try? await sleeper.sleep(for: Self.deadline)) == nil ? nil : .expired(nil) }
            defer { group.cancelAll() }
            for await case let result? in group {
                // 時限勝出的這一刻（等子工作結束之前）就停收並取快照
                if case .expired = result { return .expired(stopCollecting(run)) }
                return result
            }
            return .finished(.cancelled)
        }
        let outcome: TimingResolution.Outcome
        switch race {
        case .finished(let finished):
            outcome = finished
        case .expired(let snapshot):
            if let snapshot, let best = RankedAlignment.best(of: snapshot.accepted) {
                diagnostics.record(.picked(snapshot.source, rank: best.rank, tried: snapshot.tried))
                return await save(.found(source: snapshot.source, lines: best.alignment.lineStarts), for: request, hash: hash)
            }
            outcome = .unavailable
        }
        if outcome == .unavailable { backoff.record(request.persistentID, now: clock.now) }
        return outcome
    }

    private func stopCollecting(_ run: UInt64) -> Provisional? {
        if acceptingRun == run { acceptingRun = nil }
        return provisional?.run == run ? provisional : nil
    }

    /// 只在這一號還在收集、且沒被取消時記下（時限到、被搶占、新詞取消之後都寫不進來）
    private func remember(_ accepted: [RankedAlignment], tried: Int, from source: StoredTimingSource, run: UInt64) {
        guard acceptingRun == run, !Task.isCancelled else { return }
        provisional = Provisional(run: run, source: source, accepted: accepted, tried: tried)
    }

    private func lookup(_ request: TimingRequest, hash: LyricsFingerprint, run: UInt64) async -> TimingResolution.Outcome {
        guard let query = await validQuery(for: request) else {
            diagnostics.record(.skipped(.missingMetadata))
            return .skipped(.missingMetadata)
        }
        let lookupStarted = clock.now
        var hadFailure = false
        for provider in providers where !switches.disabledSources.contains(provider.source) {
            guard !Task.isCancelled else { return .cancelled }
            let started = clock.now
            let ranked: [TimingCandidate]
            do {
                let candidates = try await provider.candidates(for: query)
                ranked = TimingCandidate.ranked(candidates, for: query)
                guard !ranked.isEmpty else {
                    diagnostics.record(.noTiming(provider.source, .miss(among: candidates.count), elapsed: clock.now - started))
                    continue
                }
            } catch {
                guard error != .cancelled, !Task.isCancelled else { return .cancelled }
                hadFailure = true
                diagnostics.record(.failure(provider.source, error, elapsed: clock.now - started))
                continue
            }
            switch await ask(provider, for: ranked, query: query, lyrics: request.lyrics, run: run, since: lookupStarted) {
            case .cancelled:
                return .cancelled
            case .picked(let best, let tried):
                diagnostics.record(.picked(provider.source, rank: best.rank, tried: tried))
                return await save(.found(source: provider.source, lines: best.alignment.lineStarts), for: request, hash: hash)
            case .noAnswer(let failed):
                hadFailure = hadFailure || failed
            }
        }
        if hadFailure { return .unavailable }
        return await save(.notFound, for: request, hash: hash)
    }

    /// 依名次逐筆取時間軸並對齊；全對上就不再取，已用超過 `extraCandidateCutoff` 就不再開始下一筆
    private func ask(
        _ provider: any TimedLyricsProvider, for ranked: [TimingCandidate], query: TimingQuery, lyrics: String, run: UInt64, since lookupStarted: TimeInterval
    ) async -> SourceAnswer {
        var accepted: [RankedAlignment] = []
        var hadFailure = false
        var tried = 0
        candidates: for (rank, candidate) in ranked.enumerated() {
            if rank > 0, clock.now - lookupStarted > Self.extraCandidateCutoff { break }
            guard !Task.isCancelled else { return .cancelled }
            tried += 1
            remember(accepted, tried: tried, from: provider.source, run: run)
            let started = clock.now
            do {
                let outcome = try await provider.timing(of: candidate, for: query)
                guard !Task.isCancelled else { return .cancelled }
                switch outcome {
                case .timed(let lines, _):
                    let alignment = await Self.align(lyrics: lyrics, lrc: lines)
                    guard !Task.isCancelled else { return .cancelled }
                    diagnostics.record(.answer(provider.source, rank: rank, alignment: alignment, elapsed: clock.now - started))
                    guard let alignment, alignment.isAccepted else { continue }
                    let passed = RankedAlignment(rank: rank, alignment: alignment)
                    accepted.append(passed)
                    remember(accepted, tried: tried, from: provider.source, run: run)
                    if passed.isPerfect { break candidates }
                case .noTiming(let reason):
                    diagnostics.record(.noTiming(provider.source, reason, elapsed: clock.now - started))
                }
            } catch {
                guard error != .cancelled, !Task.isCancelled else { return .cancelled }
                hadFailure = true
                diagnostics.record(.failure(provider.source, error, elapsed: clock.now - started))
            }
        }
        if let best = RankedAlignment.best(of: accepted) { return .picked(best, tried: tried) }
        return .noAnswer(hadFailure: hadFailure)
    }

    /// 對齊是同步 CPU 工作：在 actor 外跑，不佔住 resolver（resolve／shutdown 照常進得來；R2 層級審查）
    @concurrent
    private nonisolated static func align(lyrics: String, lrc: [LRCLine]) async -> LRCAligner.Alignment? {
        LRCAligner.alignment(lyrics: lyrics, lrc: lrc)
    }

    /// artist、title 非空且不超過比對上限，duration 有限、> 0、< 一天（Codex R1 #5；過長就不送請求）
    private func validQuery(for request: TimingRequest) async -> TimingQuery? {
        let known: TimingQuery?
        if let given = request.query {
            known = given
        } else {
            known = await metadata(request.persistentID)
        }
        guard let query = known,
              !query.artist.trimmingCharacters(in: .whitespaces).isEmpty, !query.title.trimmingCharacters(in: .whitespaces).isEmpty,
              query.artist.count <= TrackMatcher.maxNameLength, query.title.count <= TrackMatcher.maxNameLength,
              query.duration.isFinite, query.duration > 0, query.duration < Self.maximumDuration
        else { return nil }
        return query
    }
}
