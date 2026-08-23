import Foundation

@testable import AzathothsWhisper

// 固定回應的歌詞來源替身
struct StubLyricsSource: LyricsSource {
    let result: LyricsResult

    init(_ result: LyricsResult) {
        self.result = result
    }

    func fetchLyrics(for query: LyricsQuery) async -> LyricsResult { result }
}

/// 可控放行時點的閘門。
///
/// **語義：`open()` 是 broadcast——一次放行全部等待者，不是單一令牌。**
/// 需要「一次只放行一個」語義的測試必須另建型別，不要改這裡。
///
/// 歷史（2026-08-23 A1 根因）：本型別原先只存**單一** continuation，兩個等待者時
/// 後者會覆蓋前者、前者永不 resume。後果不是用例失敗，而是 `await` 該 task 的測試
/// 永久掛起 → 整個 test run 不收束 → xcodebuild 超時後報
/// `The test runner hung before establishing connection` 且 0 條測試執行。
/// 證據見 docs/plans/2026-08-23-m6-closeout.md 附錄 A1。
actor LyricsGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// 放行**全部**等待者。重複呼叫不重放（waiters 已清空），故不會重複 resume。
    ///
    /// 取消語義：等待中的 Task 被取消時，其 continuation 仍留在 `waiters` 裡，
    /// 由本次 `open()` 一併 resume（`CheckedContinuation<Void, Never>` 對已取消的
    /// Task resume 是安全的）。此替身僅供測試，不實作可取消的等待機制。
    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

struct GatedLyricsSource: LyricsSource {
    let gate: LyricsGate
    let result: LyricsResult

    func fetchLyrics(for query: LyricsQuery) async -> LyricsResult {
        await gate.wait()
        return result
    }
}

/// 記錄每次查詢、並可在第 N 次調用時卡住的來源：
/// 用來斷言 Batch 逐條抓詞確為串行，以及製造「抓詞中切專輯」的競態窗口
actor RecordingLyricsSource: LyricsSource {
    private(set) var queries: [LyricsQuery] = []
    /// 結果路由委派給 ScriptedLyricsSource——本型別只負責「記錄」與「卡住」兩件事
    private let scripted: ScriptedLyricsSource
    private let gate: LyricsGate?
    private let gateAtCall: Int

    init(_ byTitle: [String: LyricsResult], gate: LyricsGate? = nil, gateAtCall: Int = 1) {
        self.scripted = ScriptedLyricsSource(byTitle)
        self.gate = gate
        self.gateAtCall = gateAtCall
    }

    func fetchLyrics(for query: LyricsQuery) async -> LyricsResult {
        queries.append(query)
        if queries.count == gateAtCall, let gate {
            await gate.wait()
        }
        return await scripted.fetchLyrics(for: query)
    }
}

/// 按曲名路由結果的來源：Batch 逐條抓詞需要每首曲目有不同結果
struct ScriptedLyricsSource: LyricsSource {
    let byTitle: [String: LyricsResult]
    let fallback: LyricsResult

    init(_ byTitle: [String: LyricsResult], fallback: LyricsResult = .notFound) {
        self.byTitle = byTitle
        self.fallback = fallback
    }

    func fetchLyrics(for query: LyricsQuery) async -> LyricsResult {
        byTitle[query.title] ?? fallback
    }
}

extension LyricsService {
    /// Editor 測試只關心 Genius 分支
    static func stub(genius: LyricsResult) -> LyricsService {
        LyricsService(genius: StubLyricsSource(genius), darkLyrics: StubLyricsSource(.notFound))
    }

    /// Batch 測試：Genius 按曲名腳本化，DarkLyrics 預設不命中
    static func scripted(
        genius: [String: LyricsResult],
        darkLyrics: LyricsResult = .notFound
    ) -> LyricsService {
        LyricsService(
            genius: ScriptedLyricsSource(genius),
            darkLyrics: StubLyricsSource(darkLyrics)
        )
    }
}

/// 反覆讓出執行緒若干輪，讓沒有同步可觀察條件的跨 actor 工作有機會落地
/// （典型場景：`Task { await someActor.method() }` 這類非結構化跳板）。
///
/// 與 `waitUntil` 的分工：有可輪詢的條件用 `waitUntil`（會提前返回）；
/// 沒有條件可等、只能「讓一會兒」時用本函式。
func settle(_ iterations: Int = 100) async {
    for _ in 0..<iterations { await Task.yield() }
}

/// 反覆讓出主執行緒直到條件成立（供不確定調度時點的非同步斷言使用）
@MainActor
func waitUntil(_ condition: () -> Bool, iterations: Int = 200) async {
    for _ in 0..<iterations {
        if condition() { return }
        await Task.yield()
    }
}
