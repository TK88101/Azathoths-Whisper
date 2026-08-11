import Foundation
import Testing

// M1 骨架測試：驗證測試 target 可跑＋fixture 資源可達（M2 起被 golden 表驅動測試取代/擴充）
@Suite("Skeleton")
struct SkeletonTests {
    @Test func fixturesBundleAccessible() throws {
        let bundle = Bundle(for: BundleToken.self)
        let fixturesURL = try #require(bundle.resourceURL?.appendingPathComponent("Fixtures"))
        let goldenURL = fixturesURL.appendingPathComponent("golden/sanitize_title.json")
        let data = try Data(contentsOf: goldenURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let cases = try #require(json?["cases"] as? [[String: Any]])
        #expect(cases.count == 22)
    }
}

private final class BundleToken {}
