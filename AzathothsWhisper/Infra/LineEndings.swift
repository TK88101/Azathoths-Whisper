import Foundation

// iTunes/Music 的 lyrics 欄位常以 CR（或 CRLF）分行。
// 原版把歌詞塞進 <textarea>，瀏覽器在賦值時會把 CR/CRLF 正規化成 LF——
// 於是「Lines:」統計（value.split('\n')）與寫回 Music 的內容都是 LF 版本。
// Swift 端沒有這層隱式正規化，必須顯式補上，否則整首歌會被算成 1 行。
enum LineEndings {
    static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// 換行統一後內容相同。Music 會把寫入的 LF 存成 CR：寫入後讀回比對必須用這個，逐字比對會誤判寫入失敗
    static func equivalent(_ a: String, _ b: String) -> Bool {
        normalized(a) == normalized(b)
    }
}
