/// 上游已出現的錯誤碼（基本設計 §4.3、§5.3、§5.4；CR-006；配對三種為 CR-010、sprint-2-detail.md §4.2）；隨上游 CR 增加
public enum ErrorCode: String, Codable, Sendable, CaseIterable, Error {
    case invalidRequest, protocolMismatch, rateLimited, replayed, musicNotRunning, busy, notApplied, superseded
    /// proof 錯或格式錯；同一 QR 不可再試
    case pairingInvalid
    /// 無配對窗、窗已被佔用或已作廢；需重新掃碼
    case pairingUnavailable
    /// 對端已被解除；Mac 關閉連線前告知
    case notPaired
    /// Mac 讀不到曲庫（未授權或讀取失敗；兩者錯誤相同，無法區分）；CR-012
    case libraryUnavailable
    /// Music 自動化權限被拒（AE -1743）；要到系統設定改，改回後由狀態推送得知恢復（CR-013(a)）
    case musicNotAuthorized
    /// Azathoth 沒有輔助使用權限，Genius 按不到（CR-030）；要到系統設定改，改回後由事件的 genius 欄位得知
    case accessibilityDenied

    /// 對端可以稍後重送同一請求（CR-012：映射集中在這裡）
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .busy, .libraryUnavailable: true
        default: false
        }
    }
}
