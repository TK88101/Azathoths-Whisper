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

// 可控放行時點的來源：用來製造「抓詞進行中」的競態窗口
actor LyricsGate {
    // 注意：只存單一 continuation——同一個閘門若有兩個等待者，後者會覆蓋前者，
    // 前者永遠不被喚醒。現有用例都只有一個等待者；要寫重疊場景需先改成陣列。
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { self.continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
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
    private let byTitle: [String: LyricsResult]
    private let gate: LyricsGate?
    private let gateAtCall: Int

    init(_ byTitle: [String: LyricsResult], gate: LyricsGate? = nil, gateAtCall: Int = 1) {
        self.byTitle = byTitle
        self.gate = gate
        self.gateAtCall = gateAtCall
    }

    func fetchLyrics(for query: LyricsQuery) async -> LyricsResult {
        queries.append(query)
        if queries.count == gateAtCall, let gate {
            await gate.wait()
        }
        return byTitle[query.title] ?? .notFound
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

/// 反覆讓出主執行緒直到條件成立（供不確定調度時點的非同步斷言使用）
@MainActor
func waitUntil(_ condition: () -> Bool, iterations: Int = 200) async {
    for _ in 0..<iterations {
        if condition() { return }
        await Task.yield()
    }
}
