/// a11y identifier 的單一來源（計劃 §9.4）。畫面與 UITests 共用：UITests target 同編此檔（見 project.yml），
/// 不重演兩邊各寫一份、再用測試釘住的模式。identifier 不隨語言變，是 UITests 唯一可靠的定位鍵
enum AccessibilityID {
    static func nav(_ tab: String) -> String { "nav-\(tab)" }
    static let navPrefix = "nav-"
    static let navEditor = "nav-editor"
    static let navBatch = "nav-batch"

    static let lyricsFlowHandle = "lyricsflow-handle"
    /// Cover Flow 層常駐（降下時只露把手），只看「存在」判斷不了升降
    static let coverFlowLayer = "lyricsflow-coverflow"
    /// DEBUG 限定的升降探針：value＝`raised`／`lowered`。容器（`children: .contain`）上的 value
    /// 會被 SwiftUI 吞掉（2026-09-23 實測），故另設 1pt 透明文字承載
    static let surfaceProbe = "lyricsflow-surface"
    static let raised = "raised"
    static let lowered = "lowered"
    /// Editor 層條件掛載：只在畫面＝Editor 時存在（D2）
    static let editorLayer = "lyricsflow-editor"

    static let playingCard = "coverflow-playing-card"
    static let cardPrefix = "coverflow-item-"
    static let centerLabel = "coverflow-center-label"
    static let upNextUnavailable = "coverflow-upnext-unavailable"

    static let markNoLyrics = "editor-mark-no-lyrics"
    static let fetchButton = "editor-fetch"
    static let writeButton = "editor-write"
    static let lyricsText = "editor-lyrics"
    /// DEBUG 限定：a11y value＝本次啟動的抓詞次數（「未自動抓詞」的判定）
    static let fetchCount = "editor-fetch-count"
    /// DEBUG 限定：a11y value＝本次啟動的強制重讀請求次數（AC3：點非播放卡不得觸發）
    static let hydrateCount = "editor-hydrate-count"
}
