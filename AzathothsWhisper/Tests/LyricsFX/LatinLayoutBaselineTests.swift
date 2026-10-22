import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// ⑤ 中日韓字型計劃 T3：純英文行的排版必須與改動前完全相同（換行、每字位置、字距、所在列）。
// 指紋在改動前（wip/lyrics-fx-cjk T2，ASCII 排版與 main aa502eb 起相同）以真實 CoreText 量測錄下。歌詞為編造句
@Suite("Latin layout baseline")
struct LatinLayoutBaselineTests {
    static let lines = [
        "Paper boats at dawn",
        "lanterns drift over the quiet water while the evening bell keeps ringing on and on",
        "Supercalifragilisticexpialidociouslyunbelievablelongword fits nowhere",
        "Don't stop, it's 4:20 — ready? Go! (again) \"quoted\"",
        "a",
    ]
    static let fonts = ["Bebas", "Anton", "RockSalt", "Grotesk", "Grimoire", "CormorantIt"]
    static let sizes = [CGSize(width: 900, height: 560), CGSize(width: 480, height: 400)]

    static func composedSignature() -> String {
        let measurer = CoreTextMeasurer()
        var parts: [String] = []
        for font in fonts {
            let recipe = ComposedRecipe(
                font: font, backdrop: "void", enter: "lash", exit: "fade", fx1: "none", fx2: "none", palette: "ice", seed: 7,
                profile: SongProfile(axes: [.aggression: 0.5], tags: [])
            )
            for size in sizes {
                for (index, text) in lines.enumerated() {
                    let line = TimedLine(start: 0, end: 4, text: text, isChorus: false)
                    guard let report = ComposedStyle.fitReport(line: line, index: index, recipe: recipe, size: size, measurer: measurer) else {
                        parts.append("nil"); continue
                    }
                    parts.append(String(format: "%.3f|%d|", report.em, report.breaksLongWords ? 1 : 0) + report.rowWidths.map { String(format: "%.3f", $0) }.joined(separator: ","))
                    parts.append(zip(report.glyphs, report.metrics).map { glyph, metric in
                        "\(glyph.text)\(glyph.wordIndex).\(glyph.row):" + String(format: "%.3f/%.3f", metric.width, metric.advance)
                    }.joined(separator: ";"))
                }
            }
        }
        return parts.joined(separator: "\n")
    }

    static func monoSignature() -> String {
        let measurer = CoreTextMeasurer()
        return sizes.flatMap { size in
            lines.map { text in
                MonoLayout.rows(
                    of: text, fontSize: MonoLayout.currentFontSize(width: size.width), face: .displayMedium,
                    maxWidth: size.width - 2 * MonoLayout.margin(width: size.width), maxRows: 4, measurer: measurer
                ).joined(separator: "⏎")
            }
        }.joined(separator: "\n")
    }

    static let composedFingerprint: UInt64 = 5928042042764253703
    static let monoFingerprint: UInt64 = 4691727377359918205

    @Test func composedLatinLayoutIsUnchanged() {
        let fingerprint = FXHash.fnv1a64(Self.composedSignature())
        print("LATIN-BASELINE composed=\(fingerprint)")
        #expect(fingerprint == Self.composedFingerprint)
    }

    @Test func monoLatinLayoutIsUnchanged() {
        let fingerprint = FXHash.fnv1a64(Self.monoSignature())
        print("LATIN-BASELINE mono=\(fingerprint)")
        #expect(fingerprint == Self.monoFingerprint)
    }
}
