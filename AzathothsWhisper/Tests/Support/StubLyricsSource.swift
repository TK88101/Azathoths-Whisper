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

extension LyricsService {
    /// Editor 測試只關心 Genius 分支
    static func stub(genius: LyricsResult) -> LyricsService {
        LyricsService(genius: StubLyricsSource(genius), darkLyrics: StubLyricsSource(.notFound))
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
