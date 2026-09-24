import Foundation

/// 「純空白＝缺詞」（C-29）的唯一定義。狀態推導（`LyricsStatus`）、Editor 自動抓詞、Batch 缺詞篩選
/// （`AlbumTrack.hasLyrics`）共用這一處，避免三份各自漂移。
///
/// 字元集＝CPython `str.strip()`（`PythonCompat.whitespace`），與 Python 版 `bool(lyrics.strip())`（py:2254）一致。
/// 取捨：只含 U+FEFF（BOM）或 U+200B（ZWSP）的歌詞判為「有詞」——Python 版如此，本版以它為對照基準
/// （對抗覆核 P2 B10，Codex R2 裁決）。
enum LyricsText {
    static func isBlank(_ lyrics: String) -> Bool {
        lyrics.pythonStripped().isEmpty
    }
}
