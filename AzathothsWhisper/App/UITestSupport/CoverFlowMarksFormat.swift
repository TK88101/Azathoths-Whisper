// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import Foundation

/// runner marks 檔的格式（docs/plans/2026-09-13-coverflow-h02-fix4.md §5.4「分段來源」、§5.7 (10)）。
///
/// **為何需要**：過渡態判定（P_trans）要把每幀幾何切成「運動段／hold 段」，段邊界只有 runner 知道——
/// 按鍵、捲動、截圖、落定各發生在哪個 wall-clock 時刻。trace 記的是 app 內的相對微秒，
/// 兩條時間軸靠 trace header 的 `epoch-us` 錨點對齊，所以 marks 一律記 **wall-clock 微秒**。
///
/// 每行以 `\t` 分欄：`epoch_us  kind  payload`。**不寫進 trace**：往同一份 trace 追加會讓
/// `readUntilQuiet` 的「檔案位移 500 ms 無變化」永遠不成立（計劃 §2）。
enum CoverFlowMarksFormat {
    /// 預登記詞彙（§5.7 (10)）；離線判定按這些名字找段邊界，改名即對不上
    enum Kind: String, CaseIterable, Sendable {
        /// payload＝步驟名
        case stepBegin = "step-begin"
        case stepEnd = "step-end"
        /// payload＝按鍵名
        case key
        /// payload＝deltaX
        case scrollBegin = "scroll-begin"
        case scrollEnd = "scroll-end"
        /// `readStable` 的截圖前後；C2 的像素取樣就落在這個窗口內
        case shotBegin = "shot-begin"
        case shotEnd = "shot-end"
        /// payload＝步驟名
        case settled
    }

    /// 欄位內不得出現分欄或換行，否則讀取端會切錯行（與 trace 同協議）
    static func sanitise(_ text: String) -> String {
        text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    static func line(epochMicroseconds: Int64, kind: Kind, payload: String) -> String {
        "\(epochMicroseconds)\t\(kind.rawValue)\t\(sanitise(payload))\n"
    }
}
#endif
