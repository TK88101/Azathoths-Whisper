import Foundation

/// Settings 的 iCloud 同步狀態（⑨ 計劃 §6.6）：要顯示哪幾行是純函式，畫面只負責排版
struct CloudSyncDisplay: Equatable, Sendable {
    struct Line: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            case lastExport, lastImport
            case otherMacs(Int)
            case skipped(Int)
            case pendingDownloads(Int)
            /// 錯誤類型代號（英文，不含路徑或內容；E-05 狀態文案慣例）
            case error(String)
            /// 讀不到硬體身分：不能同步
            case unavailable
        }

        let kind: Kind
        let date: Date?
        var id: String { String(describing: kind) }
    }

    var enabled: Bool
    var unavailable = false
    var status: CloudSyncCoordinator.Status?

    var otherMacs: Int { status?.otherWriters.count ?? 0 }

    var statusLines: [Line] {
        if unavailable { return [Line(kind: .unavailable, date: nil)] }
        guard let status else { return [] }
        var lines: [Line] = []
        if let date = status.lastExport { lines.append(Line(kind: .lastExport, date: date)) }
        if let date = status.lastImport { lines.append(Line(kind: .lastImport, date: date)) }
        if status.lastImport != nil { lines.append(Line(kind: .otherMacs(otherMacs), date: nil)) }
        if status.skipped > 0 { lines.append(Line(kind: .skipped(status.skipped), date: nil)) }
        if status.pendingDownloads > 0 { lines.append(Line(kind: .pendingDownloads(status.pendingDownloads), date: nil)) }
        if let error = status.lastError { lines.append(Line(kind: .error(error), date: nil)) }
        return lines
    }
}
