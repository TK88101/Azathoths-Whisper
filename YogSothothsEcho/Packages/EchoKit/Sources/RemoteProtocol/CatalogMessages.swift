import Foundation

// 曲庫訊息的 body（sprint-3-detail.md §4.3；kind 已在 MessageKind）。`isValid` 只驗形狀，
// Mac 收到時不合法＝invalidRequest、不執行。Data 以 JSONEncoder 預設的 base64 編碼。

public struct AlbumSummary: Codable, Sendable, Equatable {
    /// ITLibAlbum.persistentID，16 位小寫十六進位
    public let id: String
    public let title: String
    public let artist: String
    public let trackCount: Int
    /// nil＝沒有封面；有值＝快取鍵的一部分，封面換了就變
    public let artworkToken: String?

    public init(id: String, title: String, artist: String, trackCount: Int, artworkToken: String?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.trackCount = trackCount
        self.artworkToken = artworkToken
    }
}

public struct CatalogPageRequest: Codable, Sendable, Equatable {
    public let cursor: String?
    public let limit: Int

    public init(cursor: String?, limit: Int) {
        self.cursor = cursor
        self.limit = limit
    }

    public var isValid: Bool {
        (1...CatalogLimits.maxPageSize).contains(limit) && (cursor.map { CatalogCursor.decode($0) != nil } ?? true)
    }
}

public struct CatalogPageResponse: Codable, Sendable, Equatable {
    public let version: String
    public let total: Int
    /// 筆數可少於 limit（完整訊息位元組預算）；結束與否只看 nextCursor
    public let albums: [AlbumSummary]
    public let nextCursor: String?

    public init(version: String, total: Int, albums: [AlbumSummary], nextCursor: String?) {
        self.version = version
        self.total = total
        self.albums = albums
        self.nextCursor = nextCursor
    }
}

public struct CatalogSearchRequest: Codable, Sendable, Equatable {
    public let query: String
    public let limit: Int

    public init(query: String, limit: Int) {
        self.query = query
        self.limit = limit
    }

    public var isValid: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && query.count <= CatalogLimits.maxQueryCharacters
            && query.unicodeScalars.count <= CatalogLimits.maxQueryScalars
            && (1...CatalogLimits.maxSearchResults).contains(limit)
    }
}

public struct CatalogSearchResponse: Codable, Sendable, Equatable {
    public let version: String
    public let albums: [AlbumSummary]

    public init(version: String, albums: [AlbumSummary]) {
        self.version = version
        self.albums = albums
    }
}

/// spine＝曲庫格子的 160 px 縮圖；detail＝原檔原樣分塊（CR-018）；full 不實作（請求一律不合法）
public enum ArtworkSize: String, Codable, Sendable, CaseIterable {
    case spine, detail, full
}

/// detail 分塊的上限（CR-018；sprint-5-detail.md §11）：每塊原始 45,000 B，最壞完整外層訊息仍 ≤ responseBudgetBytes（測試證明）
public enum DetailArtworkLimits {
    public static let maxTotalBytes = 6 * 1_048_576
    public static let chunkBytes = 45_000
    public static let maxParts = partCount(totalBytes: maxTotalBytes)
    /// SHA-256 十六進位字數
    public static let digestLength = 64

    public static func partCount(totalBytes: Int) -> Int { (totalBytes + chunkBytes - 1) / chunkBytes }

    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == digestLength && value.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}

/// 原檔格式：以 magic bytes 判定，只收 JPEG 與 PNG
public enum ArtworkMime: String, Codable, Sendable {
    case jpeg, png

    private static let jpegMagic: [UInt8] = [0xFF, 0xD8, 0xFF]
    private static let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    public static func sniff(_ data: Data) -> ArtworkMime? {
        if data.starts(with: jpegMagic) { return .jpeg }
        return data.starts(with: pngMagic) ? .png : nil
    }
}

public struct ArtworkRequest: Codable, Sendable, Equatable {
    public let albumID: String
    public let size: ArtworkSize
    public let artworkToken: String
    /// 以下只用於 detail：塊序號（0 起）、part > 0 時帶 part 0 回覆的完整 SHA-256、iPad 每次選新封面遞增的世代
    public let part: Int?
    public let digest: String?
    public let generation: UInt64?

    public init(albumID: String, size: ArtworkSize, artworkToken: String, part: Int? = nil, digest: String? = nil,
                generation: UInt64? = nil) {
        self.albumID = albumID
        self.size = size
        self.artworkToken = artworkToken
        self.part = part
        self.digest = digest
        self.generation = generation
    }

    public var isValid: Bool {
        guard HexID.isValid(albumID), HexID.isValid(artworkToken) else { return false }
        switch size {
        case .spine: return part == nil && digest == nil && generation == nil
        case .full: return false
        case .detail:
            guard let part, generation != nil, (0..<DetailArtworkLimits.maxParts).contains(part) else { return false }
            if part == 0 { return digest == nil }
            return digest.map(DetailArtworkLimits.isDigest) ?? false
        }
    }
}

public enum ArtworkOutcome: String, Codable, Sendable {
    /// 有圖
    case image
    /// 沒有封面或縮圖失敗
    case none
    /// 請求的 token 已不是目前的（換版）；iPad 不寫快取、觸發重同步
    case stale
    /// detail：這次傳輸已失效（被取代、逾時或 digest 不符）；丟棄已收的塊，從 part 0 重來
    case restart
    /// detail：原檔超過 DetailArtworkLimits.maxTotalBytes；沿用 spine（不是永久「沒有封面」）
    case tooLarge
}

/// detail 的一塊（只在 size == .detail 且 outcome == .image 時出現）
public struct ArtworkDetailPart: Codable, Sendable, Equatable {
    public let part: Int
    public let partCount: Int
    public let totalBytes: Int
    /// 原檔完整 SHA-256（64 字小寫十六進位）
    public let digest: String
    public let mime: ArtworkMime
    public let chunk: Data

    public init(part: Int, partCount: Int, totalBytes: Int, digest: String, mime: ArtworkMime, chunk: Data) {
        self.part = part
        self.partCount = partCount
        self.totalBytes = totalBytes
        self.digest = digest
        self.mime = mime
        self.chunk = chunk
    }

    /// 塊數與總長一致、序號在範圍內、非末塊長度＝塊長、末塊長度＝餘數
    public var isValid: Bool {
        guard (1...DetailArtworkLimits.maxTotalBytes).contains(totalBytes), DetailArtworkLimits.isDigest(digest),
              partCount == DetailArtworkLimits.partCount(totalBytes: totalBytes), (0..<partCount).contains(part) else { return false }
        let expected = part == partCount - 1 ? totalBytes - part * DetailArtworkLimits.chunkBytes : DetailArtworkLimits.chunkBytes
        return chunk.count == expected
    }
}

public struct ArtworkResponse: Codable, Sendable, Equatable {
    public let albumID: String
    public let size: ArtworkSize
    public let outcome: ArtworkOutcome
    public let artworkToken: String?
    /// 只在 spine 且 outcome == .image 時有值
    public let jpeg: Data?
    /// 只在 detail 且 outcome == .image 時有值（spine 時不編碼，線上內容與 CR-018 前相同）
    public let detail: ArtworkDetailPart?

    public init(albumID: String, size: ArtworkSize, outcome: ArtworkOutcome, artworkToken: String?, jpeg: Data?,
                detail: ArtworkDetailPart? = nil) {
        self.albumID = albumID
        self.size = size
        self.outcome = outcome
        self.artworkToken = artworkToken
        self.jpeg = jpeg
        self.detail = detail
    }

    public var isValid: Bool {
        let isImage = outcome == .image
        switch size {
        case .spine: return detail == nil && isImage == (jpeg != nil) && outcome != .restart && outcome != .tooLarge
        case .detail: return jpeg == nil && isImage == (detail != nil) && (detail?.isValid ?? true)
        case .full: return false
        }
    }
}

public struct CatalogChangedEvent: Codable, Sendable, Equatable {
    public let version: String
    public init(version: String) { self.version = version }
}
