/// a11y identifier 的單一來源（計劃 §9.4）。畫面與 UITests 共用：UITests target 同編此檔（見 project.yml），
/// 不重演兩邊各寫一份、再用測試釘住的模式。identifier 不隨語言變，是 UITests 唯一可靠的定位鍵
enum AccessibilityID {
    static func nav(_ tab: String) -> String { "nav-\(tab)" }
    static let navPrefix = "nav-"
    static let navEditor = "nav-editor"
    static let navBatch = "nav-batch"

    static let lyricsFlowHandle = "lyricsflow-handle"
    /// Cover Flow 層常駐（降下時只露把手），故以 value 表示升降：`raised`／`lowered`
    static let coverFlowLayer = "lyricsflow-coverflow"
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
}
