// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import Foundation

/// 歌詞特效的預覽歌詞與假時鐘設定（A2 計劃 §3.6）。**全部是自編句子**，不放真歌詞。
/// 內嵌 LRC：時間精確，定格截圖與 UI 測試才能指定「某一秒該看到哪一行」。
/// **app 與 UITests 兩個 target 同編此檔**（見 project.yml），故只依賴 Foundation
enum LyricsFXPreviewFixture {
    /// "<秒>"＝暫停在該秒（出定格）；未設＝自啟動起以牆鐘前進、到曲長後回 0
    static let previewAtVariable = "AZW_LYRICSFX_PREVIEW_AT"
    /// "1"＝改用 200 字壓力歌詞（量每幀耗時）
    static let denseVariable = "AZW_LYRICSFX_PREVIEW_DENSE"
    /// "1"＝強制「減少動態效果」（出定格圖用；XCUITest 改不了系統設定）
    static let reduceMotionVariable = "AZW_LYRICSFX_REDUCE_MOTION"
    /// 預覽曲目的樂團名（走樂團覆寫表）／曲風（走關鍵字合成）／nonce（固定配方的抽籤）——B1 計劃 §3.10
    static let artistVariable = "AZW_LYRICSFX_PREVIEW_ARTIST"
    static let genreVariable = "AZW_LYRICSFX_PREVIEW_GENRE"
    static let nonceVariable = "AZW_LYRICSFX_PREVIEW_NONCE"
    /// 直接指定七個元件 id（font,backdrop,enter,exit,fx1,fx2,palette）：效能量測用最重的組合（B1 計劃 T10）
    static let recipeVariable = "AZW_LYRICSFX_PREVIEW_RECIPE"
    static let duration: Double = 60

    /// 12 個時間點：含兩段空檔（間奏）、一行長句、一行 CJK
    static let lyrics = """
    [00:02.00]Paper boats drift past the harbor lights
    [00:05.50]Salt on the rope and the evening bell
    [00:09.00]We count the gulls until the tide turns back
    [00:12.50]
    [00:15.50]Lanterns low, lanterns slow
    [00:19.00]灯籠が川を流れてゆく夜
    [00:22.50]A long line that keeps on walking past the edge of the window so the layout has to fold it into rows
    [00:28.00]Quiet harbor, quiet hands
    [00:31.50]The ferry hums a tune nobody wrote
    [00:35.00]
    [00:39.00]Morning finds the paper boats asleep
    [00:43.00]
    """

    /// 預設視窗（1200×800）下，升起層的畫布在 2.0 秒時恰好畫出 200 個字（`LyricsFXPreviewRenderTests` 釘住）。
    /// 兩行每 7 秒交替、鋪滿整個 60 秒循環：量每幀耗時時一直有字
    static let denseLyrics: String = {
        let lines = stride(from: 1, through: 50, by: 7).enumerated().map { index, second in
            String(format: "[00:%02d.00]", second) + (index.isMultiple(of: 2) ? denseCurrent : denseNext)
        }
        return (lines + ["[00:57.00]"]).joined(separator: "\n")
    }()

    static let denseCurrent = "Lanterns over water, salt along the rope, gulls above the ferry, bells across the bay, and paper boats beside the pier tonight"
    static let denseNext = "Morning finds the harbor quiet and the tide returning slowly to the stones beneath the old pier under pale grey sky"

    static func lyrics(in environment: [String: String]) -> String {
        environment[denseVariable] == "1" ? denseLyrics : lyrics
    }

    /// 定格的秒數；未設或不是數字＝跑動
    static func frozenSeconds(in environment: [String: String]) -> Double? {
        environment[previewAtVariable].flatMap(Double.init)
    }

    /// 跑動時的假位置：自 `start` 起以牆鐘前進、到曲長後回 0
    static func runningSeconds(since start: ContinuousClock.Instant, now: ContinuousClock.Instant) -> Double {
        let components = (now - start).components   // 本檔也編進 UITests，不用 app 內的 `Duration.inSeconds`
        let elapsed = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return elapsed.truncatingRemainder(dividingBy: duration)
    }
}
#endif
