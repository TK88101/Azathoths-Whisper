import Foundation

/// 讀 Music 自存的 `Queue.dat`（待播清單）與 `History.dat`（履歴）——**只讀**（計劃 D13、D16、D17、AC8c）。
///
/// - 單一 actor＝單一串行讀取工人：兩個檔案共用，同時至多一個 plist 解碼（20MB 的 Queue.dat 解析 p50 59ms，S9）
/// - 只在檔案屬性（大小＋修改時間）變了才重讀；讀前讀後屬性不同＝正被寫入，本次放棄、下次再讀（R3-3）
/// - 解析失敗回報 `.failed`，由 `QueueSession` 保留上一份有效快照
/// - 結果只保留精簡快照，不留原始 `Data`
/// - 本檔不得出現任何寫入／移動／刪除 API（`Scripts/no_playback_gate.sh` 檢查）
actor QueueFileSource {
    enum Read<Snapshot: Equatable & Sendable>: Equatable, Sendable {
        case snapshot(Snapshot)
        case unchanged
        case missing
        case failed
    }

    static let queueFileName = "Queue.dat"
    static let historyFileName = "History.dat"

    /// 預設曲庫位置；自訂位置一律退回（L7，產品限制）
    static let defaultDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music/Music/Music Library.musiclibrary/Preferences")

    private struct Stamp: Equatable {
        let size: Int
        let modified: Date
    }

    private let directory: URL?
    private var queueStamp: Stamp?
    private var historyStamp: Stamp?
    private var historyKeepLast: Int?

    /// `directory` 為 nil＝停用（單元測試 host：不讀使用者的曲庫）
    init(directory: URL?) {
        self.directory = directory
    }

    func readQueue() -> Read<QueueSnapshot> {
        guard let url = directory?.appendingPathComponent(Self.queueFileName) else { return .missing }
        switch Self.readStable(url, previous: queueStamp) {
        case .missing: return .missing
        case .unchanged: return .unchanged
        case .unstable: return .unchanged
        case .data(let data, let stamp):
            guard let snapshot = QueueSnapshot.parse(data) else { return .failed }
            queueStamp = stamp
            return .snapshot(snapshot)
        }
    }

    func readHistory(keepLast: Int) -> Read<HistorySnapshot> {
        guard let url = directory?.appendingPathComponent(Self.historyFileName) else { return .missing }
        // 窗口大小變了要重讀，即使檔案沒變
        let previous = historyKeepLast == keepLast ? historyStamp : nil
        switch Self.readStable(url, previous: previous) {
        case .missing: return .missing
        case .unchanged: return .unchanged
        case .unstable: return .unchanged
        case .data(let data, let stamp):
            guard let snapshot = HistorySnapshot.parse(data, keepLast: keepLast) else { return .failed }
            historyStamp = stamp
            historyKeepLast = keepLast
            return .snapshot(snapshot)
        }
    }

    // MARK: - 內部

    private enum RawRead {
        case missing
        case unchanged
        /// 讀的過程中檔案變了（Music 正在寫）
        case unstable
        case data(Data, Stamp)
    }

    private static func readStable(_ url: URL, previous: Stamp?) -> RawRead {
        guard let before = stamp(of: url) else { return .missing }
        guard before != previous else { return .unchanged }
        guard let data = try? Data(contentsOf: url) else { return .missing }
        guard stamp(of: url) == before else { return .unstable }
        return .data(data, before)
    }

    private static func stamp(of url: URL) -> Stamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return Stamp(size: size, modified: modified)
    }
}
