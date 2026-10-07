import AppKit
import CoreText

/// 量測與外框路徑共用的參考字級：以 100 pt 存、依字級線性縮放（B1 計劃 §3.3）。
/// 只對「無可變軸或只有 wght」的字型成立；其餘字型退回以字級為鍵（`FaceFonts.scalesLinearly`）
enum UnitGlyphMetrics {
    static let referenceSize: CGFloat = 100
    /// 不能線性縮放的字型，字級量化到這個步距再當鍵
    static let fallbackSizeStep: CGFloat = 0.5

    /// 實際快取用的字級：可線性縮放＝參考字級，否則量化後的字級
    static func cacheSize(for fontSize: CGFloat, linear: Bool) -> CGFloat {
        linear ? referenceSize : (fontSize / fallbackSizeStep).rounded() * fallbackSizeStep
    }
}

/// `FontFace` → `CTFont`，並判斷能否線性縮放。只在主執行緒用（View 持有）
final class FaceFonts {
    private struct Key: Hashable {
        let face: FontFace
        let size: CGFloat
    }

    /// `wght`（0x77676874）
    private static let weightAxis = 0x7767_6874

    private var fonts: [Key: CTFont] = [:]
    private var linear: [FontFace: Bool] = [:]

    func font(_ face: FontFace, size: CGFloat) -> CTFont {
        let key = Key(face: face, size: size)
        if let font = fonts[key] { return font }
        var attributes: [NSFontDescriptor.AttributeName: Any] = [.family: face.family]
        var traits: [NSFontDescriptor.TraitKey: Any] = [:]
        if let weight = face.weight { traits[.weight] = weight.nsWeight }
        if face.italic { traits[.symbolic] = NSFontDescriptor.SymbolicTraits.italic.rawValue }
        if !traits.isEmpty { attributes[.traits] = traits }
        let font = (NSFont(descriptor: NSFontDescriptor(fontAttributes: attributes), size: size) ?? NSFont.systemFont(ofSize: size)) as CTFont
        fonts[key] = font
        return font
    }

    /// 無可變軸或只有 wght → true（字形與 advance 隨字級線性縮放；Codex 計劃辯論 R2）
    func scalesLinearly(_ face: FontFace) -> Bool {
        if let known = linear[face] { return known }
        let axes = (CTFontCopyVariationAxes(font(face, size: UnitGlyphMetrics.referenceSize)) as? [[CFString: Any]]) ?? []
        let identifiers = axes.compactMap { ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.intValue }
        let result = identifiers.allSatisfy { $0 == Self.weightAxis }
        linear[face] = result
        return result
    }
}

/// 生產用的字寬量測：CoreText 對整列排版，取每個 grapheme 起點的 x 位移（A2 計劃 §3.4）。
/// 以 (文字, 字型) 在參考字級快取、乘字級比例（B1 計劃 §3.3）；只在主執行緒用（View 持有）
final class CoreTextMeasurer: TextMeasuring {
    private struct Key: Hashable {
        let text: String
        let face: FontFace
        let size: CGFloat
    }

    /// 上限：一首歌的列數遠低於此；超過就整個清掉（不做 LRU，避免為罕見情況加複雜度）
    private static let capacity = 2000

    private var cache: [Key: [CGFloat]] = [:]
    private let fonts = FaceFonts()

    func advances(of text: String, face: FontFace, fontSize: CGFloat) -> [CGFloat] {
        let size = UnitGlyphMetrics.cacheSize(for: fontSize, linear: fonts.scalesLinearly(face))
        let key = Key(text: text, face: face, size: size)
        let measured: [CGFloat]
        if let cached = cache[key] {
            measured = cached
        } else {
            if cache.count >= Self.capacity { cache.removeAll(keepingCapacity: true) }
            measured = measure(text, font: fonts.font(face, size: size))
            cache[key] = measured
        }
        let ratio = fontSize / size
        return measured.map { $0 * ratio }
    }

    func ascent(face: FontFace, fontSize: CGFloat) -> CGFloat {
        let size = UnitGlyphMetrics.cacheSize(for: fontSize, linear: fonts.scalesLinearly(face))
        return CTFontGetAscent(fonts.font(face, size: size)) * fontSize / size
    }

    private func measure(_ text: String, font: CTFont) -> [CGFloat] {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
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

/// 每個字的外框路徑（A2 計劃 §3.7：實測逐字 `draw(Text)` 是 200 字超出 2 ms 的主因，改畫路徑）。
/// 以 (文字, 字型) 在參考字級存，畫時乘字級比例（B1 計劃 §3.3）。路徑以字的行盒 top-leading 為原點、y 向下。只在主執行緒用
final class GlyphPathCache {
    struct Entry {
        let path: CGPath
        /// 快取時的字級；畫時 `scale = fontSize / size`
        let size: CGFloat
        /// 外框中心（快取字級下），旋轉與縮放的軸
        let center: CGPoint
    }

    private struct Key: Hashable {
        let text: String
        let face: FontFace
        let size: CGFloat
    }

    private static let capacity = 4000
    private var store: [Key: Entry] = [:]
    private let fonts = FaceFonts()

    func entry(for glyph: GlyphDraw) -> Entry {
        let size = UnitGlyphMetrics.cacheSize(for: glyph.fontSize, linear: fonts.scalesLinearly(glyph.face))
        let key = Key(text: glyph.text, face: glyph.face, size: size)
        if let entry = store[key] { return entry }
        if store.count >= Self.capacity { store.removeAll(keepingCapacity: true) }
        let path = Self.outline(glyph.text, font: fonts.font(glyph.face, size: size))
        let bounds = path.boundingBoxOfPath
        let entry = Entry(path: path, size: size, center: CGPoint(x: bounds.midX, y: bounds.midY))
        store[key] = entry
        return entry
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
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}
