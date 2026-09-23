// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import Foundation

/// 「Cover Flow × 找歌詞」UI 測試的場景、環境變數、假資料與 a11y identifier（計劃 Q3.5、§9.4）。
///
/// **app 與 UITests 兩個 target 同編此檔**（見 project.yml）：場景名、旗標名、identifier 都只有一個來源，
/// 不重演兩邊各寫一份、再用測試釘住的模式。
enum LyricsFlowUITestScenario: String, CaseIterable, Sendable {
    /// 正在播的歌檔內有詞 → Cover Flow（AC1、AC3、AC14）
    case present
    /// 缺詞 → Editor；自動抓詞打到恆 404 的假 HTTP（AC2、AC4、AC5）
    case missing
    /// 缺詞但已標記「沒有歌詞」（組裝時預植）→ Cover Flow、不自動抓詞
    case marked
    /// 沒在播 → Editor 顯示 NO ARTIST／NO TRACK（外殼測試用：不碰使用者的 Music）
    case notPlaying

    // MARK: 環境變數（UITest 以 launchEnvironment 注入）

    static let variable = "AZW_UITEST_SCENARIO"
    /// "1"＝啟動時清空測試專屬的設定 suite（AC5：第一次啟動帶、重啟不帶）
    static let resetDefaultsVariable = "AZW_UITEST_RESET_DEFAULTS"
    /// 逗號分隔的 persistentID：預植「沒有歌詞」標記
    static let seedMarksVariable = "AZW_UITEST_SEED_MARKS"
    /// 測試專屬的設定 suite：**從不碰使用者的 `.standard`**（D4）
    static let defaultsSuiteName = "com.ibridgezhao.azathothswhisper.uitest"

    static func requested(in environment: [String: String]) -> LyricsFlowUITestScenario? {
        environment[variable].flatMap(Self.init(rawValue:))
    }

    static func environment(_ scenario: LyricsFlowUITestScenario, resetDefaults: Bool) -> [String: String] {
        var environment = [variable: scenario.rawValue]
        if resetDefaults {
            environment[resetDefaultsVariable] = "1"
        }
        return environment
    }

    // MARK: 假資料：待播清單 5 首、正在播第 2 首（左＝履歴 2 首、右＝接下來 2 首）

    static let trackCount = 5
    static let playingIndex = 2
    static let artist = "AZW LYRICSFLOW"
    static let album = "LYRICSFLOW FIXTURE"

    /// Queue.dat 的 `tID`；persistentID＝其 16 位大寫 hex（事實 20）
    static func trackID(at index: Int) -> Int64 {
        0x0A2E_5000 + Int64(index)
    }

    static func persistentID(at index: Int) -> String {
        String(format: "%016llX", UInt64(bitPattern: trackID(at: index)))
    }

    static func index(of persistentID: String) -> Int? {
        (0..<trackCount).first { self.persistentID(at: $0) == persistentID }
    }

    static func itemID(at index: Int) -> Int64 {
        100 + Int64(index)
    }

    static func title(at index: Int) -> String {
        "LYRICSFLOW TRACK \(index)"
    }

    /// 非播放中各卡的檔內歌詞：0、3 有詞，1、4 缺詞（徽章 ✓／✗ 都看得到）；播放中那首由場景決定
    static func fixtureLyrics(at index: Int) -> String {
        [0, 3].contains(index) ? "fixture lyrics \(index)" : ""
    }

    // MARK: a11y identifier（計劃 §9.4；View 與 UITests 共用這一組常數）

    enum Identifier {
        static let handle = "lyricsflow-handle"
        static let coverFlowLayer = "lyricsflow-coverflow"
        static let editorLayer = "lyricsflow-editor"
        static let playingCard = "coverflow-playing-card"
        static let cardPrefix = "coverflow-item-"
        static let centerLabel = "coverflow-center-label"
        static let upNextUnavailable = "coverflow-upnext-unavailable"
        static let navEditor = "nav-editor"
        static let navBatch = "nav-batch"
        static let navPrefix = "nav-"
        static let markNoLyrics = "editor-mark-no-lyrics"
        static let writeButton = "editor-write"
        static let lyricsText = "editor-lyrics"
        /// DEBUG 限定：a11y value＝本次啟動的抓詞次數（「未自動抓詞」的判定，§9.4）
        static let fetchCount = "editor-fetch-count"
    }
}
#endif
