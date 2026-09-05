import AppKit

// Resources/ 下的原始圖檔（未走 Assets.xcassets：兩張圖、無多解析度需求）
enum BundleAssets {
    static let noise = image(named: "noise", extension: "png")
    static let aboutLogo = image(named: "AboutLogo", extension: "png")

    private static func image(named name: String, extension ext: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return NSImage(contentsOf: url)
    }
}
