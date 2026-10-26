import Foundation

/// 曲庫訊息的數值常數（sprint-3-detail.md §4.3）；實作與測試一律引用這裡
public enum CatalogLimits {
    public static let maxPageSize = 200
    public static let defaultPageSize = 200
    public static let maxQueryCharacters = 64
    /// 碼點上限：單一 grapheme 可帶上萬個組合符號，NFKC 正規化 O(n²)（security review MEDIUM-1）
    public static let maxQueryScalars = 256
    public static let maxSearchResults = 50
    public static let defaultSearchResults = 50
    /// 標題／藝人先以 grapheme 截、再以 UTF-8 位元組截
    public static let maxTextCharacters = 200
    public static let maxTextUTF8Bytes = 600
    public static let spinePixels = 160
    /// spine JPEG 原始位元組上限；base64 後加 JSON 外殼仍 < `TransportLimits.responseBudgetBytes`
    public static let spineMaxJPEGBytes = 40_000
    public static let rebuildInterval: TimeInterval = 60
    /// 專輯 ID 與 artworkToken、版本的字串長度（小寫十六進位）
    public static let hexIDLength = 16
}

enum HexID {
    static func isValid(_ value: String) -> Bool {
        value.utf8.count == CatalogLimits.hexIDLength
            && value.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}
