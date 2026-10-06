import AppKit
import CoreText

/// 生產用的字寬量測：CoreText 對整列排版，取每個 grapheme 起點的 x 位移（A2 計劃 §3.4）。
/// 同一列每幀都會被量，結果依（文字、字級、粗細）快取；只在主執行緒用（View 持有）
final class CoreTextMeasurer: TextMeasuring {
    private struct Key: Hashable {
        let text: String
        let fontSize: CGFloat
        let weight: GlyphWeight
    }

    /// 上限：一首歌的列數遠低於此；超過就整個清掉（不做 LRU，避免為罕見情況加複雜度）
    private static let capacity = 2000

    private var cache: [Key: [CGFloat]] = [:]
    private let fonts = DisplayFontCache()

    func advances(of text: String, fontSize: CGFloat, weight: GlyphWeight) -> [CGFloat] {
        let key = Key(text: text, fontSize: fontSize, weight: weight)
        if let cached = cache[key] { return cached }
        if cache.count >= Self.capacity { cache.removeAll(keepingCapacity: true) }
        let measured = measure(text, font: fonts.font(size: fontSize, weight: weight))
        cache[key] = measured
        return measured
    }

    private func measure(_ text: String, font: CTFont) -> [CGFloat] {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        var offsets: [CGFloat] = []
        offsets.reserveCapacity(text.count + 1)
        var index = text.startIndex
        while index < text.endIndex {
            let utf16 = text.utf16.distance(from: text.startIndex, to: index)
            offsets.append(CTLineGetOffsetForStringIndex(line, utf16, nil))
            index = text.index(after: index)
        }
        offsets.append(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        return offsets
    }
}

/// 與畫面的 `Theme.Fonts.display(_:weight:)` 同一枚字型（Space Grotesk，可變字重）；量測與外框路徑共用
final class DisplayFontCache {
    private struct Key: Hashable {
        let size: CGFloat
        let weight: GlyphWeight
    }

    private var fonts: [Key: CTFont] = [:]

    func font(size: CGFloat, weight: GlyphWeight) -> CTFont {
        let key = Key(size: size, weight: weight)
        if let font = fonts[key] { return font }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: Theme.Fonts.displayName,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.nsWeight],
        ])
        let font = (NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)) as CTFont
        fonts[key] = font
        return font
    }
}

/// 每個字的外框路徑（A2 計劃 §3.7：實測逐字 `draw(Text)` 是 200 字超出 2 ms 的主因，改畫路徑）。
/// 路徑以字的行盒 top-leading 為原點、y 向下（與 `GlyphDraw.origin` 同一座標）。只在主執行緒用
final class GlyphPathCache {
    private struct Key: Hashable {
        let text: String
        let fontSize: CGFloat
        let weight: GlyphWeight
    }

    private static let capacity = 4000
    private var store: [Key: CGPath] = [:]
    private let fonts = DisplayFontCache()

    func path(for glyph: GlyphDraw) -> CGPath {
        let key = Key(text: glyph.text, fontSize: glyph.fontSize, weight: glyph.weight)
        if let path = store[key] { return path }
        if store.count >= Self.capacity { store.removeAll(keepingCapacity: true) }
        let path = Self.outline(glyph.text, font: fonts.font(size: glyph.fontSize, weight: glyph.weight))
        store[key] = path
        return path
    }

    /// 經 CTLine 排版（含字型替代：CJK 會落到系統字型），把各 run 的字形外框收進一條路徑；基線在 ascent 處
    private static func outline(_ text: String, font: CTFont) -> CGPath {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        var ascent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, nil, nil)
        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let runFont = ((CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as? NSFont).map { $0 as CTFont } ?? font
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                guard let outline = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                // CoreText 的 y 向上、原點在基線 → 翻成 y 向下、原點在行盒 top
                let transform = CGAffineTransform(translationX: position.x, y: ascent).scaledBy(x: 1, y: -1)
                path.addPath(outline, transform: transform)
            }
        }
        return path
    }
}

extension GlyphWeight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        }
    }
}
