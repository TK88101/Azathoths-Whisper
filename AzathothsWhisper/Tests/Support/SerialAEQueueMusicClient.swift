import Foundation

@testable import AzathothsWhisper

/// 模擬 `MusicAppleEventsClient` 的**單一串行佇列**：所有 AE 呼叫排成 FIFO 逐一執行。
///
/// 為何需要它：`MockMusicClient` 各方法互相獨立，觀察不到「monitor 的 `currentTrack()`
/// 排在幾張 artwork 之後」這件事——而那正是 P2 的 AE 公平性主張所斷言的性質。
/// 本替身把「共用一條佇列」這個結構補回來，讓排程不變量可被測試。
///
/// **邊界**：它證明的是**排程性質**（誰排在誰前面），不是真實時間界。
/// 「monitor 最多多等 1.5 秒」由此不變量 ＋ `SBApplication.timeout` 推出，真機時序留 M8。
actor SerialAEQueueMusicClient: MusicControlling {
    /// 佇列上實際執行的操作序，供「artwork 對 monitor 的貢獻 ≤ 1 call」斷言
    private(set) var executionOrder: [String] = []

    private var artwork: [String: Data] = [:]
    private var artworkGate: LyricsGate?
    private var queueTail: Task<Void, Never>?

    func setArtwork(_ data: Data, for persistentID: String) {
        artwork[persistentID] = data
    }

    /// 卡住 artwork 的執行，製造「monitor 在 artwork 進行中入列」的窗口
    func setArtworkGate(_ gate: LyricsGate) {
        artworkGate = gate
    }

    /// 把 `body` 串到佇列尾端，前一項完成前不開始——等同 `MusicAppleEventsClient`
    /// 的 `queue.async`，但可在測試裡觀察順序
    private func enqueue<T: Sendable>(_ label: String, _ body: @escaping @Sendable () async -> T) async -> T {
        let previous = queueTail
        let task = Task { [weak self] () -> T in
            await previous?.value
            await self?.markExecuting(label)
            return await body()
        }
        queueTail = Task { _ = await task.value }
        return await task.value
    }

    private func markExecuting(_ label: String) {
        executionOrder.append(label)
    }

    // MARK: MusicControlling

    func playerState() async throws -> PlayerState {
        await enqueue("playerState") { .playing }
    }

    func currentTrack() async throws -> TrackInfo? {
        await enqueue("currentTrack") { TrackInfo.fixture() }
    }

    func currentLyrics() async throws -> String {
        await enqueue("currentLyrics") { "" }
    }

    func albumTracks(artist: String, album: String) async throws -> [AlbumTrack] {
        await enqueue("albumTracks") { [] }
    }

    func setLyrics(persistentID: String, lyrics: String) async throws -> Bool {
        await enqueue("setLyrics") { true }
    }

    func artworkData(persistentID: String) async throws -> Data? {
        let gate = artworkGate
        let payload = artwork[persistentID]
        return await enqueue("artwork:\(persistentID)") {
            await gate?.wait()
            return payload
        }
    }
}
