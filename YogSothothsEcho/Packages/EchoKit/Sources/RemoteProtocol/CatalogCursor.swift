import Foundation

/// 分頁 cursor（sprint-3-detail.md §4.4）：base64url(版本 ‖ ":" ‖ offset)。Mac 不信任內容，只解析；不合法＝nil
public struct CatalogCursor: Sendable, Equatable {
    public let version: String
    public let offset: Int

    /// offset 上限：曲庫專輯數遠低於此；超過視為竄改
    static let maxOffset = 1_000_000

    public init(version: String, offset: Int) {
        self.version = version
        self.offset = offset
    }

    public func encoded() -> String { Self.encodeRaw("\(version):\(offset)") }

    public static func decode(_ text: String) -> CatalogCursor? {
        guard let raw = decodeRaw(text) else { return nil }
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, HexID.isValid(String(parts[0])),
              parts[1].utf8.allSatisfy({ (0x30...0x39).contains($0) }), parts[1].utf8.count <= 7,
              let offset = Int(parts[1]), offset <= maxOffset else { return nil }
        return CatalogCursor(version: String(parts[0]), offset: offset)
    }

    static func encodeRaw(_ text: String) -> String { Data(text.utf8).base64URLEncoded() }

    private static func decodeRaw(_ text: String) -> String? {
        guard text.utf8.count <= 64, let data = Data(base64URL: text) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
