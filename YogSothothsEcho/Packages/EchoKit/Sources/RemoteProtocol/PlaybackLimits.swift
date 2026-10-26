import Foundation

/// 播放控制的數值常數（sprint-4-detail.md §4.4、§4.5、§4.8；#4-0 附錄 B 實測後定稿）；實作與測試一律引用這裡。秒
public enum PlaybackLimits {
    /// 有 iPad 連線時的狀態輪詢間隔（CR-006①）
    public static let pollInterval: Double = 0.5
    /// 確認式節奏：觀察到換曲後再走過的時間、送出後目前曲沒變就判未生效的期限（CR-006②）
    public static let gateSettle: Double = 1
    public static let gateNoChangeDeadline: Double = 3
    /// 上一首回到本曲開頭的判定容差：實際進度要比「照常播放應到的位置」少這麼多以上（暫定，N-01 後調整；與 manualJumpTolerance 不同語意）
    public static let rewindTolerance: Double = 1
    /// 播放／暫停送出後的讀回：每隔多久讀一次、多久都沒變才判未生效（#4-1：Music 會晚幾百毫秒才反映；CR-016：起播偶發 1.1–1.2 s，期限＝appleEventTimeout）
    public static let toggleReadbackInterval: Double = 0.1
    public static let toggleReadbackDeadline: Double = 2
    /// 閘門期間等待中的受管指令上限（執行中那一筆不算）
    public static let maxPendingManaged = 3
    /// 單一 Apple Event 的等待上限
    public static let appleEventTimeout: Double = 2
    /// `shortcuts list --show-identifiers` 的等待上限（CR-014）
    public static let bindingTimeout: Double = 1
    /// play.track：捷徑發起 → 目標曲到達；捷徑結束；捷徑結束後佇列穩定（#4-0：1.2–1.3 s／+0.15 s／約 4.5 s）
    public static let targetArrivalDeadline: Double = 6
    public static let shortcutExitDeadline: Double = 10
    public static let queuePollInterval: Double = 0.5
    /// 點歌等目標曲到達、等捷徑結束時的觀測間隔（只在 play.track 進行中；N-01 點歌延遲的量化誤差 ≤ 0.1 s）
    public static let arrivalPollInterval: Double = 0.1
    public static let queueStableSpan: Double = 3
    public static let queueSettleDeadline: Double = 10
    /// 捷徑無回應後的最短隔離（之後還要觀測到靜止才解除）
    public static let shortcutQuarantine: Double = 10
    /// 期限圖推得的最壞耗時與准入預算（§4.4、§4.5）。next／previous＝送出前讀回 2＋送出 2＋倒回硬上限 4（3＋gateSettle）＋最後一次讀回 2＝10，
    /// 取 11 留輪詢餘量（simcodex R2 security LOW-1；原 8 漏算送出前讀回。預算 80 不動＝執行中＋等待中 play.track 時 next 回 busy，使用者 2026-10-19 同意）
    public static let worstNextPrevious: Double = 11
    public static let worstPlayTrack: Double = 36
    /// Genius（CR-030）：定位 ≤ 5（3 s 期限＋單次 AX 超時 2）＋按下前讀回 2＋讀啟用 2＋等換曲 3＋跨界讀回 2＝14，取 16 留輪詢餘量
    public static let worstGenius: Double = 16
    public static let managedAdmissionBudget: Double = 80
    /// 手動操作偵測：位置跳動容差、本地操作可解釋的視窗（§4.5）
    public static let manualJumpTolerance: Double = 2
    /// 點歌追蹤中可容忍的短暫異常（空 ID、同一首忽然停止）時長；超過才判手動（#4-1 N-01 真機）
    public static let transientTolerance: Double = 1
    public static let localOperationWindow: Double = 2
    /// 推送：位置與外推值差超過此值、或距上次推送超過校正間隔（§4.7）
    public static let pushPositionTolerance: Double = 1
    public static let pushRefreshInterval: Double = 10
    public static let maxOutputDevices = 8

    /// iPad 端各 kind 的請求逾時：受管指令 ＞ 准入預算＋15 s（§4.8）；其餘維持既有 10 s
    public static func clientTimeout(_ kind: MessageKind) -> Double {
        switch kind {
        case .playTrack, .playNext, .playPrevious, .playGenius: managedAdmissionBudget + 15
        default: 10
        }
    }
}
