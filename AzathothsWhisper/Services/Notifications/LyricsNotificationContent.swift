import Foundation

/// 一則系統通知的內容（與 UserNotifications 無關的純值，方便測試）
struct NotificationPayload: Equatable, Sendable {
    let title: String
    let subtitle: String
    let body: String
    /// 通知中心的分組鍵（專輯名）；專輯空白時不分組
    let threadID: String?
}

/// Import All 一整批的寫入結果（歌名依寫入順序）
struct BatchWriteSummary: Equatable, Sendable {
    let artist: String
    let album: String
    /// 判斷「整張專輯」用：成功數＝專輯曲目數且沒有失敗
    let albumTrackCount: Int
    let succeeded: [String]
    let failed: [String]
}

// 歌詞寫入通知的文案（計劃 2026-09-26-lyrics-notification §3，版式＝樣式 A）：
// title＝App 名稱（隨 App 語言）、subtitle＝藝人 · 專輯、body＝結果。
// 歌名一律只當格式參數，不進格式字串（含 % 的歌名不會被當成格式）。
enum LyricsNotificationContent {
    /// 列表最多列出的歌名數，其餘以「及另外 N 首」帶過（通知 body 只有 2～4 行）
    static let maxListedTitles = 3

    static func single(artist: String, title: String, album: String, bundle: Bundle = .main) -> NotificationPayload {
        payload(
            artist: artist, album: album,
            body: format("notify_single_ok", bundle, title),
            bundle: bundle
        )
    }

    /// 什麼都沒寫（成功與失敗皆空）→ nil，不彈通知
    static func batch(_ summary: BatchWriteSummary, bundle: Bundle = .main) -> NotificationPayload? {
        guard let body = batchBody(summary, bundle: bundle) else { return nil }
        return payload(artist: summary.artist, album: summary.album, body: body, bundle: bundle)
    }

    private static func batchBody(_ summary: BatchWriteSummary, bundle: Bundle) -> String? {
        let saved = summary.succeeded.count
        let failed = summary.failed.count
        switch (saved, failed) {
        case (0, 0):
            return nil
        case (0, _):
            return format("notify_batch_all_failed", bundle, failed)
        case (_, 0) where saved == summary.albumTrackCount:
            return format("notify_batch_full", bundle, saved)
        case (_, 0):
            return format("notify_batch_some", bundle, saved, list(summary.succeeded, bundle))
        default:
            // 部分失敗列出**失敗**的歌：那是使用者要處理的
            return format("notify_batch_partial", bundle, saved, saved + failed, failed, list(summary.failed, bundle))
        }
    }

    private static func payload(artist: String, album: String, body: String, bundle: Bundle) -> NotificationPayload {
        let trimmedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = trimmedAlbum.isEmpty ? artist : format("notify_subtitle", bundle, artist, trimmedAlbum)
        return NotificationPayload(
            title: bundle.localizedString(forKey: "app_title", value: nil, table: nil),
            subtitle: subtitle,
            body: body,
            threadID: trimmedAlbum.isEmpty ? nil : trimmedAlbum
        )
    }

    private static func list(_ titles: [String], _ bundle: Bundle) -> String {
        let separator = bundle.localizedString(forKey: "notify_list_separator", value: nil, table: nil)
        let listed = titles.prefix(maxListedTitles).joined(separator: separator)
        let remaining = titles.count - maxListedTitles
        guard remaining > 0 else { return listed }
        return "\(listed) \(format("notify_more", bundle, remaining))"
    }

    private static func format(_ key: String, _ bundle: Bundle, _ arguments: any CVarArg...) -> String {
        let template = bundle.localizedString(forKey: key, value: nil, table: nil)
        return String(format: template, arguments: arguments.map(normalize))
    }

    /// `%lld` 需要 64 位整數；String 以 NSString 傳給 `%@`
    private static func normalize(_ argument: any CVarArg) -> any CVarArg {
        switch argument {
        case let value as Int: return Int64(value)
        case let value as String: return value as NSString
        default: return argument
        }
    }
}
