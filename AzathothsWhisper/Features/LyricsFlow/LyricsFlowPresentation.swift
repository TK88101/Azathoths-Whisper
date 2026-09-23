import Foundation

/// 卡片徽章與狀態字（計劃 AC7、§9.5；設計稿：✓ 綠／✗ 紅／— 灰，中心卡附軌號）。純函數，畫面只取結果
enum LyricsBadge {
    enum Tone: Equatable, Sendable {
        case present
        case missing
        case marked
        case unknown
    }

    static func tone(for status: LyricsStatus) -> Tone {
        switch status {
        case .present: return .present
        case .missing: return .missing
        case .markedNone: return .marked
        case .unknown: return .unknown
        }
    }

    static func symbol(for status: LyricsStatus) -> String {
        switch status {
        case .present: return "✓"
        case .missing: return "✗"
        case .markedNone: return "—"
        case .unknown: return "?"
        }
    }

    /// 中心卡附兩位數軌號（`✓ 07`）；沒有軌號（0）或非中心卡只顯示符號
    static func text(for status: LyricsStatus, trackNumber: Int?, isCurrent: Bool) -> String {
        let symbol = symbol(for: status)
        guard isCurrent, let trackNumber, trackNumber > 0 else { return symbol }
        return "\(symbol) \(String(format: "%02d", trackNumber))"
    }

    enum Corner: Equatable, Sendable {
        case leading
        case trailing
    }

    /// 徽章放在卡片露出的那一角（使用者 2026-09-23 拍板）：正中左側的卡右上角被較靠中心的卡蓋住 → 左上；
    /// 其餘（正中、右側、找不到中心或卡）→ 右上。以「相對當下正中」判定，方向鍵瀏覽時跟著換邊
    static func corner(of cardID: String, in cardIDs: [String], centerID: String?) -> Corner {
        guard let centerID,
              let centerIndex = cardIDs.firstIndex(of: centerID),
              let cardIndex = cardIDs.firstIndex(of: cardID) else { return .trailing }
        return cardIndex < centerIndex ? .leading : .trailing
    }

    /// 狀態字的 i18n 鍵（§9.5）
    static func statusKey(for status: LyricsStatus) -> String {
        switch status {
        case .present: return "lyrics_status_present"
        case .missing: return "lyrics_status_missing"
        case .markedNone: return "lyrics_status_marked"
        case .unknown: return "lyrics_status_unknown"
        }
    }
}

/// 把手上的一道刻度：一張卡一道（設計稿：播過的短、接下來的長、中心白色）
struct HandleTick: Equatable, Sendable {
    let side: DeckCard.Side
    let tone: LyricsBadge.Tone
}

enum LyricsFlowHandle {
    static func ticks(cards: [DeckCard], status: (DeckCard) -> LyricsStatus) -> [HandleTick] {
        cards.map { HandleTick(side: $0.side, tone: LyricsBadge.tone(for: status($0))) }
    }
}
