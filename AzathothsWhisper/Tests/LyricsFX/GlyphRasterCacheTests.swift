import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import AzathothsWhisper

// 字形點陣快取（docs/plans/2026-10-16-lyrics-fx-glyph-raster-cache.md §2.2、T1；
// 尺寸分檔與 LRU：docs/plans/2026-10-17-lyrics-fx-raster-fullscreen-gap.md §9.5、T5）
@MainActor
@Suite("Glyph raster cache")
struct GlyphRasterCacheTests {
    static let face = FontFace(id: "Catacombs", family: "Catacombs", weight: nil, uppercase: true)
    /// 113 pt 字（外框 100 pt）在 2× 螢幕上：每個外框單位約 2.27 像素
    static let screenPixelsPerUnit: CGFloat = 1.134 * 2
    static let tier = GlyphRasterCache.Tier(placement: CGAffineTransform(scaleX: 1.134, y: 1.134), deviceScale: 2)

    /// 測試裡的字都建得出點陣
    static func raster(_ cache: GlyphRasterCache, _ text: String, tier: GlyphRasterCache.Tier = tier) throws -> GlyphRasterCache.Entry {
        try #require(cache.entry(path: pathEntry(text), tier: tier))
    }

    static func pathEntry(_ text: String = "A", face: FontFace = face) -> GlyphPathCache.Entry {
        GlyphPathCache().entry(for: GlyphDraw(text: text, face: face, fontSize: 100, origin: .zero, opacity: 1, color: .fg))
    }

    /// 遮罩每個像素的 alpha（0–255）
    static func alpha(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    @Test(arguments: [0.05, 0.4, 1, 1.6, 2, 2.27, 2.84, 3.7, 8, 20] as [CGFloat])
    func theBitmapIsAlwaysOneSixToOneEightySevenTimesTheScreenPixels(_ pixelsPerUnit: CGFloat) {
        let source = GlyphRasterCache.pixelsPerUnit(tier: GlyphRasterCache.tier(pixelsPerUnit: pixelsPerUnit))
        let oversample = source / pixelsPerUnit
        #expect(oversample >= GlyphRasterCache.minimumOversample - 1e-9, "\(pixelsPerUnit) → \(source)")
        #expect(oversample < GlyphRasterCache.maximumOversample + 1e-9, "\(pixelsPerUnit) → \(source)")
    }

    @Test func theTierFollowsTheScreenScaleOfEachAxisButNotPositionOrRotation() {
        let base = GlyphRasterCache.Tier(placement: CGAffineTransform(scaleX: 1.134, y: 1.134), deviceScale: 2)
        let moved = GlyphRasterCache.Tier(placement: CGAffineTransform(scaleX: 1.134, y: 1.134).translatedBy(x: 0.37, y: -12.5), deviceScale: 2)
        let rotated = GlyphRasterCache.Tier(placement: CGAffineTransform(scaleX: 1.134, y: 1.134).concatenating(CGAffineTransform(rotationAngle: 0.3)), deviceScale: 2)
        let mirrored = GlyphRasterCache.Tier(placement: CGAffineTransform(scaleX: -1.134, y: 1.134), deviceScale: 2)
        #expect(moved == base)
        #expect(rotated == base)
        #expect(mirrored == base)
        let squashed = GlyphRasterCache.Tier(placement: CGAffineTransform(scaleX: 1.134, y: 0.3), deviceScale: 2)
        #expect(squashed.x == base.x)
        #expect(squashed.y < base.y)
        let zoomed = GlyphRasterCache.Tier(placement: CGAffineTransform(scaleX: 1.134, y: 1.134), deviceScale: 2 * 1.5)
        #expect(zoomed.x > base.x)
    }

    @Test func theBitmapCoversTheOutlineAtTheTierResolutionWithAMargin() throws {
        let path = Self.pathEntry()
        let raster = try Self.raster(GlyphRasterCache(), "A")
        let scale = GlyphRasterCache.pixelsPerUnit(tier: Self.tier.x)
        #expect(scale / Self.screenPixelsPerUnit >= GlyphRasterCache.minimumOversample - 1e-9, "113 pt × 2× 時點陣是螢幕像素的 1.6 倍以上")
        let inPixels = path.path.boundingBoxOfPath.applying(raster.toPixels)
        #expect(inPixels.minX >= 1 && inPixels.minY >= 1, "四周留抗鋸齒的邊")
        #expect(inPixels.maxX <= CGFloat(raster.cgImage.width) - 1 && inPixels.maxY <= CGFloat(raster.cgImage.height) - 1)
        #expect(abs(raster.toPixels.a - scale) < 1e-9 && abs(raster.toPixels.d - scale) < 1e-9)
        let roundTrip = raster.toPixels.concatenating(raster.fromPixels)
        for (value, expected) in [(roundTrip.a, 1), (roundTrip.b, 0), (roundTrip.c, 0), (roundTrip.d, 1), (roundTrip.tx, 0), (roundTrip.ty, 0)] as [(CGFloat, CGFloat)] {
            #expect(abs(value - expected) < 1e-9, "貼圖用的反矩陣要能還原外框座標")
        }
        #expect(raster.bytes == raster.cgImage.bytesPerRow * raster.cgImage.height)
    }

    @Test func theMaskIsTheSameCoverageAsFillingTheOutlineDirectly() throws {
        let path = Self.pathEntry()
        let raster = try Self.raster(GlyphRasterCache(), "A")
        let image = raster.cgImage
        // 參考：同一外框以 RGBA 直接填，取 alpha
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.concatenate(raster.toPixels)
            context.addPath(path.path)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillPath()
        }
        let reference = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        let mask = Self.alpha(image)
        #expect(mask.contains { $0 > 0 }, "遮罩不是空的")
        #expect(mask == reference)
    }

    @Test func theSameGlyphInTheSameTierIsRasterizedOnce() throws {
        let cache = GlyphRasterCache()
        let first = try Self.raster(cache, "A")
        _ = try Self.raster(cache, "A")
        #expect(cache.misses == 1)
        #expect(cache.bytes == first.bytes)
        #expect(first.bytes > 0)
    }

    @Test func aDifferentTierIsADifferentBitmap() throws {
        let cache = GlyphRasterCache()
        let small = try Self.raster(cache, "A").cgImage
        let large = try Self.raster(cache, "A", tier: GlyphRasterCache.Tier(x: Self.tier.x + 4, y: Self.tier.y)).cgImage
        #expect(cache.misses == 2)
        #expect(large.width > small.width)
        #expect(large.height == small.height)
    }

    @Test func goingOverTheLimitEvictsTheLeastRecentlyUsedBitmapsOnly() throws {
        let probe = try Self.raster(GlyphRasterCache(), "O")
        // 容量放得下約 2 張同大小的點陣
        let cache = GlyphRasterCache(byteLimit: probe.bytes * 2 + probe.bytes / 2)
        cache.beginFrame()
        _ = try Self.raster(cache, "O")
        cache.beginFrame()
        _ = try Self.raster(cache, "Q")
        cache.beginFrame()
        _ = try Self.raster(cache, "Q")  // Q 比 O 新
        _ = try Self.raster(cache, "C")  // 放不下 → 逐出最久沒用的 O
        #expect(cache.bytes <= cache.byteLimit)
        let misses = cache.misses
        _ = try Self.raster(cache, "Q")
        #expect(cache.misses == misses, "Q 還在")
        _ = try Self.raster(cache, "C")
        #expect(cache.misses == misses, "C 已存入")
        cache.beginFrame()
        _ = try Self.raster(cache, "O")
        #expect(cache.misses == misses + 1, "O 被逐出")
    }

    @Test func bitmapsUsedInThisFrameAreNeverEvictedSoTheNewOneIsDrawnWithoutCaching() throws {
        let probe = try Self.raster(GlyphRasterCache(), "O")
        let cache = GlyphRasterCache(byteLimit: probe.bytes + probe.bytes / 2)
        cache.beginFrame()
        _ = try Self.raster(cache, "O")
        _ = try Self.raster(cache, "Q")  // 同一幀：O 正在用，不逐出 → Q 只畫不存
        let misses = cache.misses
        _ = try Self.raster(cache, "O")
        #expect(cache.misses == misses, "O 還在")
        _ = try Self.raster(cache, "Q")
        #expect(cache.misses == misses + 1, "Q 沒進快取")
        cache.beginFrame()
        _ = try Self.raster(cache, "Q")  // 下一幀：O 已是上一幀的，可逐出
        let stored = cache.misses
        _ = try Self.raster(cache, "Q")
        #expect(cache.misses == stored, "下一幀 Q 已存入")
        #expect(cache.bytes <= cache.byteLimit)
    }

    @Test func theByteCountStaysWithinTheLimitAcrossEvictionsAndClearing() throws {
        let probe = try Self.raster(GlyphRasterCache(), "O")
        let cache = GlyphRasterCache(byteLimit: probe.bytes * 3)
        for (frame, letter) in ["O", "Q", "C", "G", "D"].enumerated() {
            cache.beginFrame()
            _ = try Self.raster(cache, letter)
            #expect(cache.bytes <= cache.byteLimit, "第 \(frame) 幀")
        }
        #expect(cache.bytes > probe.bytes, "逐出只逐必要的量，不整批清空")
        cache.removeAll()
        #expect(cache.bytes == 0)
    }

    @Test func aSingleBitmapLargerThanTheLimitIsDrawnButNeverCached() throws {
        let cache = GlyphRasterCache(byteLimit: 16)
        cache.beginFrame()
        _ = try Self.raster(cache, "A")
        #expect(cache.bytes == 0)
    }

    // MARK: 遺留收尾 ②c、②d（docs/plans/2026-10-18-lyrics-fx-leftover-cleanup.md §2.2）

    /// 以正式繪製路徑離屏畫 `frames` 幀，共用同一個外框／點陣快取
    static func draw(_ plan: FramePlan, frames: Int, paths: GlyphPathCache) {
        for _ in 0..<frames {
            let renderer = ImageRenderer(content: Canvas { context, size in
                LyricsFXCanvas.draw(plan, in: context, size: size, paths: paths)
            }.frame(width: 300, height: 200))
            renderer.scale = 2
            _ = renderer.cgImage
        }
    }

    /// 零寬空白排版時不會被濾掉（不是 White_Space），外框為空：直接跳過，不每幀重試建點陣
    @Test func aGlyphWithoutAnOutlineIsSkippedInsteadOfRetriedEveryFrame() {
        #expect(!Character("\u{200B}").isWhitespace)
        let paths = GlyphPathCache()
        let empty = GlyphDraw(text: "\u{200B}", face: Self.face, fontSize: 80, origin: CGPoint(x: 20, y: 20), opacity: 1, color: .fg)
        let letter = GlyphDraw(text: "A", face: Self.face, fontSize: 80, origin: CGPoint(x: 120, y: 20), opacity: 1, color: .fg)
        #expect(paths.entry(for: empty).isEmpty)
        #expect(!paths.entry(for: letter).isEmpty)
        var plan = FramePlan(palette: .mono)
        plan.glyphs = [empty, letter]
        Self.draw(plan, frames: 3, paths: paths)
        #expect(paths.rasters.misses == 1, "只有 A 建過一次點陣")
    }

    /// 同一幀用過的並列最舊者：先建的先出（建立序號決勝，可重現）
    @Test func amongBitmapsLastUsedInTheSameFrameTheEarliestBuiltIsEvictedFirst() throws {
        let probe = try Self.raster(GlyphRasterCache(), "O")
        for _ in 0..<8 {
            let cache = GlyphRasterCache(byteLimit: probe.bytes * 2 + probe.bytes / 2)
            cache.beginFrame()
            _ = try Self.raster(cache, "O")
            _ = try Self.raster(cache, "Q")
            cache.beginFrame()
            _ = try Self.raster(cache, "C")  // 放不下 → 逐出 O、Q 中先建的 O
            let misses = cache.misses
            _ = try Self.raster(cache, "Q")
            #expect(cache.misses == misses, "Q 還在")
            cache.beginFrame()
            _ = try Self.raster(cache, "O")
            #expect(cache.misses == misses + 1, "O 被逐出")
        }
    }


    // MARK: 遺留收尾 ②e：外框與點陣共用語義鍵

    @Test func glyphKeysAreEqualByValueAndHitTheSameSlot() {
        let key = GlyphKey(text: "A", face: Self.face, size: 100)
        let twin = GlyphKey(text: "A", face: Self.face, size: 100)
        #expect(key == twin && key.hashValue == twin.hashValue)
        #expect([key: 1][twin] == 1)
        var other = Self.face
        other.rasterizes = false
        for different in [GlyphKey(text: "B", face: Self.face, size: 100), GlyphKey(text: "A", face: other, size: 100), GlyphKey(text: "A", face: Self.face, size: 100.5)] {
            #expect(different != key)
        }
    }

    /// 外框快取整批清空後，同一個字同一檔仍命中原點陣（點陣鍵是語義鍵，不是外框快取的生命週期）
    @Test func clearingTheOutlineCacheKeepsTheBitmaps() {
        let paths = GlyphPathCache(capacity: 2)
        var plan = FramePlan(palette: .mono)
        plan.glyphs = [GlyphDraw(text: "A", face: Self.face, fontSize: 80, origin: CGPoint(x: 20, y: 20), opacity: 1, color: .fg)]
        Self.draw(plan, frames: 1, paths: paths)
        #expect(paths.rasters.misses == 1)
        for text in ["B", "C", "D"] {
            _ = paths.entry(for: GlyphDraw(text: text, face: Self.face, fontSize: 80, origin: .zero, opacity: 1, color: .fg))
        }
        Self.draw(plan, frames: 2, paths: paths)
        #expect(paths.rasters.misses == 1, "清空外框後 A 仍命中點陣")
    }

}

/// ②a 的框架語義契約（遺留收尾計劃 §2.2）：繪製端從 context 推整屏縮放，靠的是 SwiftUI `GraphicsContext.transform`
/// 不含 displayScale、`drawLayer` 保留外層縮放。這條在 OS 升級後轉紅＝語義變了，改回由 plan 傳 zoom
@MainActor
@Suite("LyricsFX device scale contract")
struct LyricsFXDeviceScaleContractTests {
    @Test(arguments: [CGFloat(1), 2], [CGFloat(1), 1.0398039215686274, 1.04])
    func theDeviceScaleSeenInsideLayersIsTheDisplayScaleTimesTheZoom(scale: CGFloat, zoom: CGFloat) {
        var seen: [CGFloat] = []
        let view = Canvas { context, size in
            var shaken = context
            shaken.translateBy(x: 3.5, y: -2)
            shaken.translateBy(x: size.width / 2, y: size.height / 2)
            shaken.scaleBy(x: zoom, y: zoom)
            shaken.translateBy(x: -size.width / 2, y: -size.height / 2)
            var faded = shaken
            faded.opacity = 0.4
            seen.append(LyricsFXCanvas.deviceScale(of: faded))
            faded.drawLayer { group in seen.append(LyricsFXCanvas.deviceScale(of: group)) }
            shaken.drawLayer { lit in
                lit.addFilter(.shadow(color: .red, radius: 7.4))
                seen.append(LyricsFXCanvas.deviceScale(of: lit))
                var inner = lit
                inner.opacity = 0.5
                inner.drawLayer { group in seen.append(LyricsFXCanvas.deviceScale(of: group)) }
            }
        }.frame(width: 400, height: 300)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        _ = renderer.cgImage
        #expect(seen.count == 4)
        #expect(seen.allSatisfy { $0 == scale * zoom }, "\(seen)")
    }
}
