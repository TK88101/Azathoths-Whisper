import Foundation

/// 整庫讀取的純轉換（⑧ 曲庫閘門）：ScriptingBridge 讀回的字串欄→列。
/// 欄數不對、各欄長度不一、或根本沒讀到（nil）＝讀不完整，一律 throw——不能被當成「空曲庫」（計劃 §4.5-4）。
/// 放在豁免檔之外、有單元測試保護（/thecure 2026-10-28：coverage 豁免只限 ScriptingBridge 邊界）
enum LibraryColumns {
    static func trackRows(_ columns: [[String]]?) throws -> [LibraryTrackRow] {
        let c = try validated(columns, count: 5)
        return c[0].indices.map { LibraryTrackRow(persistentID: c[0][$0], name: c[1][$0], artist: c[2][$0], album: c[3][$0], genre: c[4][$0]) }
    }

    static func lyricsRows(_ columns: [[String]]?) throws -> [ArtistLyricsRow] {
        try pairs(columns).map { ArtistLyricsRow(persistentID: $0, lyrics: $1) }
    }

    static func pairs(_ columns: [[String]]?) throws -> [(String, String)] {
        let c = try validated(columns, count: 2)
        return Array(zip(c[0], c[1]))
    }

    private static func validated(_ columns: [[String]]?, count: Int) throws -> [[String]] {
        guard let columns, columns.count == count, Set(columns.map(\.count)).count <= 1 else {
            throw MusicError.scriptingFailure("library read incomplete")
        }
        return columns
    }
}
