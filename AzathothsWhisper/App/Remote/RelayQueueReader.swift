import Foundation
import MusicRemoteBridge

// 點歌狀態機讀 Queue.dat 的唯讀包裝（sprint-4-detail.md §4.2、§4.10）。另開一個 QueueFileSource 實例，
// 不動 Azathoth 自己的佇列狀態；寫入、移動、刪除 API 由 no_playback_gate.sh R4 擋在 QueueFileSource 之外。
// `.ordered`（定義見 `QueueSnapshot.SequenceKind`）＝小寫 persistent ID 序列；
// 其餘（隨機播放、讀不到、檔案不在）＝nil（點歌比對不猜）。

actor RelayQueueReader: QueueReading {
    private let source: QueueFileSource
    private var last: [String]?

    /// `directory` 為 nil＝停用（永遠回 nil）
    init(directory: URL?) {
        source = QueueFileSource(directory: directory)
    }

    func read() async -> [String]? {
        switch await source.readQueue() {
        case .snapshot(let snapshot):
            last = snapshot.sequenceKind == .ordered ? snapshot.entries.map { $0.persistentID.lowercased() } : nil
        case .unchanged:
            break   // 檔案沒變（或正在寫入）：沿用上一次
        case .missing, .failed:
            last = nil
        }
        return last
    }
}
