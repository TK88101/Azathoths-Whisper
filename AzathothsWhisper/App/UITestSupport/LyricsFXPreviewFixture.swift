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
    /// "1"＝全部畫合併外框（量主執行緒總量時的向量基線，計劃 2026-10-17 全螢幕缺口 §3.3 V2）
    static let vectorReferenceVariable = "AZW_LYRICSFX_VECTOR_REFERENCE"
    /// "1"＝欄位放純文字（去掉時間標籤）：畫面走估算、角落出 `~`（C 段 E2E）
    static let plainLyricsVariable = "AZW_LYRICSFX_PREVIEW_PLAIN"
    /// "1"＝改用以日文為主的預覽歌詞（⑥a J-Pop E2E；含假名的行 ≥ 3 成）
    static let japaneseLyricsVariable = "AZW_LYRICSFX_PREVIEW_JAPANESE"
    /// 預覽歌手的 MB 曲風（逗號分隔；⑥b E2E，不連網）：設了＝當作已驗證、MB 回這幾個曲風
    static let artistGenresVariable = "AZW_LYRICSFX_PREVIEW_ARTIST_GENRES"

    static func artistGenres(in environment: [String: String]) -> [String]? {
        environment[artistGenresVariable].map { raw in raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    }
    /// 注入假的時間軸退路鏈（C 段 E2E，不連網）："found"＝回「找到」（時間＝本檔 LRC 的時間點）；"notFound"＝回「沒有」
    static let fakeTimingVariable = "AZW_TIMING_FAKE"
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

    /// 8 行中 7 行日文（自編句子）
    static let japaneseLyrics = """
    [00:02.00]紙の舟が港の灯りを過ぎてゆく
    [00:06.00]ロープに塩、夕暮れの鐘
    [00:10.00]潮が戻るまでかもめを数える
    [00:14.00]灯籠が川を流れてゆく夜
    [00:18.00]Lanterns low, lanterns slow
    [00:22.00]静かな港、静かな手
    [00:26.00]朝が紙の舟を見つける
    [00:30.00]渡し舟が名もない歌をうたう
    [00:34.00]
    """

    static func lyrics(in environment: [String: String]) -> String {
        if environment[plainLyricsVariable] == "1" { return plainLyrics }
        if environment[japaneseLyricsVariable] == "1" { return japaneseLyrics }
        return environment[denseVariable] == "1" ? denseLyrics : lyrics
    }

    /// 預覽 LRC 的非空行與其開始秒數（純文字版與假退路鏈共用，兩邊的行序一致）
    static var timedLines: [(start: Double, text: String)] {
        lyrics.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
            let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            let stamp = line[line.index(after: line.startIndex)..<close].split(separator: ":")
            guard !text.isEmpty, stamp.count == 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]) else { return nil }
            return (minutes * 60 + seconds, text)
        }
    }

    static var plainLyrics: String {
        timedLines.map(\.text).joined(separator: "\n")
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
