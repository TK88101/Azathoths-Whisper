import Foundation

// golden fixture 加載器（M0 產物 → Swift 表驅動測試）
// 佈局：Fixtures/golden/*.json（期望值）、Fixtures/html/*.html（真實頁面存檔）
enum GoldenFixtures {
    struct File: Decodable {
        let source: String
        let note: String
        let cases: [Case]
    }

    // 各 golden 檔的 case 欄位聯集；缺席欄位為 nil
    struct Case: Decodable {
        let input: String?
        let expected: String?
        let page: String?
        let targetTitle: String?
        let artist: String?
        let title: String?

        private enum CodingKeys: String, CodingKey {
            case input, expected, page, artist, title
            case targetTitle = "target_title"
        }
    }

    private static let bundle = Bundle(for: FixtureBundleToken.self)

    static func fixturesRoot() throws -> URL {
        guard let root = bundle.resourceURL?.appendingPathComponent("Fixtures") else {
            throw FixtureError.bundleMissing
        }
        return root
    }

    static func golden(_ name: String) throws -> File {
        let url = try fixturesRoot().appendingPathComponent("golden/\(name)")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(File.self, from: data)
    }

    static func html(_ name: String) throws -> String {
        // 內聯 page 標記（"(inline) <html>..."）直接回傳其內容，對齊 make_fixtures.py 的記法
        if name.hasPrefix("(inline) ") {
            return String(name.dropFirst("(inline) ".count))
        }
        let url = try fixturesRoot().appendingPathComponent("html/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    enum FixtureError: Error {
        case bundleMissing
    }
}

private final class FixtureBundleToken {}
