import CoreText
import Foundation
import Testing

@testable import AzathothsWhisper

// 打包字型的實際可用性：Space Grotesk 與 Material Symbols 子集是否隨 app 註冊，
// 且 7 個圖示名皆能經連字替換成單一 glyph（原版 CDN 字型的同一機制）。
@Suite("Bundled fonts")
struct MaterialSymbolTests {
    private func font(named name: String, size: CGFloat = 18) -> CTFont {
        CTFontCreateWithName(name as CFString, size, nil)
    }

    @Test func spaceGroteskIsRegistered() {
        let postScriptName = CTFontCopyPostScriptName(font(named: Theme.Fonts.displayName)) as String
        #expect(postScriptName.hasPrefix("SpaceGrotesk"), "實得 \(postScriptName)")
    }

    @Test func materialSymbolsSubsetIsRegistered() {
        let postScriptName = CTFontCopyPostScriptName(font(named: Theme.Fonts.symbolName)) as String
        #expect(postScriptName == "MaterialSymbolsOutlined-Regular", "實得 \(postScriptName)")
    }

    @Test(arguments: MaterialSymbolName.allCases)
    func iconNameResolvesToSingleGlyph(name: MaterialSymbolName) throws {
        let attributed = NSAttributedString(
            string: name.rawValue,
            attributes: [.font: font(named: Theme.Fonts.symbolName)]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let glyphCount = CTLineGetGlyphCount(line)
        #expect(glyphCount == 1, "\(name.rawValue) 未被連字替換（實得 \(glyphCount) 個 glyph）")

        let runs = try #require(CTLineGetGlyphRuns(line) as? [CTRun])
        let run = try #require(runs.first)
        var glyph = CGGlyph()
        CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
        #expect(glyph != 0, "\(name.rawValue) 落到 .notdef")
    }
}
