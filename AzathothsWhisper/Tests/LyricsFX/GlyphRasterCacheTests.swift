import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// 字形點陣快取（docs/plans/2026-10-16-lyrics-fx-glyph-raster-cache.md §2.2、T1）
@MainActor
@Suite("Glyph raster cache")
struct GlyphRasterCacheTests {
    static let face = FontFace(id: "Catacombs", family: "Catacombs", weight: nil, uppercase: true)

    /// 測試裡的字都建得出點陣
    static func raster(_ cache: GlyphRasterCache, _ text: String, scale: CGFloat = 2) throws -> GlyphRasterCache.Entry {
        try #require(cache.entry(text: text, face: face, path: pathEntry(text), pixelsPerPoint: scale))
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

    @Test func theBoxCoversTheOutlineWithASmallMarginAndTheBitmapMatchesItsPixelSize() throws {
        let path = Self.pathEntry()
        let raster = try Self.raster(GlyphRasterCache(), "A")
        let bounds = path.path.boundingBoxOfPath
        #expect(raster.box.contains(bounds))
        for gap in [bounds.minX - raster.box.minX, bounds.minY - raster.box.minY, raster.box.maxX - bounds.maxX, raster.box.maxY - bounds.maxY] {
            #expect(gap >= 1 && gap < 2, "外擴 1 pt 再取整：\(gap)")
        }
        let image = raster.cgImage
        #expect(image.width == Int((raster.box.width * 2).rounded(.up)))
        #expect(image.height == Int((raster.box.height * 2).rounded(.up)))
        #expect(raster.bytes == image.bytesPerRow * image.height)
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
            context.scaleBy(x: 2, y: -2)
            context.translateBy(x: -raster.box.minX, y: -raster.box.maxY)
            context.addPath(path.path)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillPath()
        }
        let reference = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        let mask = Self.alpha(image)
        #expect(mask.contains { $0 > 0 }, "遮罩不是空的")
        #expect(mask == reference)
    }

    @Test func theSameGlyphAtTheSameScaleIsRasterizedOnce() throws {
        let cache = GlyphRasterCache()
        let first = try Self.raster(cache, "A")
        _ = try Self.raster(cache, "A")
        #expect(cache.misses == 1)
        #expect(cache.bytes == first.bytes)
        #expect(first.bytes > 0)
    }

    @Test func aDifferentDisplayScaleIsADifferentBitmap() throws {
        let cache = GlyphRasterCache()
        let double = try Self.raster(cache, "A", scale: 2).cgImage
        let single = try Self.raster(cache, "A", scale: 1).cgImage
        #expect(cache.misses == 2)
        #expect(double.width == single.width * 2)
    }

    @Test func goingOverTheByteLimitClearsTheCacheOnce() throws {
        let probe = try Self.raster(GlyphRasterCache(), "A")
        // 容量放得下約 2 張 "A" 大小的點陣
        let cache = GlyphRasterCache(byteLimit: probe.bytes * 2 + probe.bytes / 2)
        cache.beginFrame()
        for letter in ["A", "B"] { _ = try Self.raster(cache, letter) }
        let full = cache.bytes
        _ = try Self.raster(cache, "C")
        #expect(cache.bytes < full, "第三張放不下 → 先清空再存")
        #expect(cache.bytes <= cache.byteLimit)
        // 清空後 A 已不在快取 → 再取一次算 miss
        let misses = cache.misses
        _ = try Self.raster(cache, "A")
        #expect(cache.misses == misses + 1)
    }

    @Test func aSecondOverflowInTheSameFrameDrawsWithoutCachingUntilTheNextFrame() throws {
        let probe = try Self.raster(GlyphRasterCache(), "A")
        let cache = GlyphRasterCache(byteLimit: probe.bytes + probe.bytes / 2)
        cache.beginFrame()
        _ = try Self.raster(cache, "A")
        _ = try Self.raster(cache, "B")  // 第一次超額：清空、存 B
        let afterFirstClear = cache.bytes
        _ = try Self.raster(cache, "C")  // 同幀第二次超額：只畫不存
        #expect(cache.bytes == afterFirstClear, "同一幀不再清空")
        let misses = cache.misses
        _ = try Self.raster(cache, "C")
        #expect(cache.misses == misses + 1, "C 沒進快取")
        cache.beginFrame()
        _ = try Self.raster(cache, "C")  // 下一幀：可以再清空並存入
        let stored = cache.misses
        _ = try Self.raster(cache, "C")
        #expect(cache.misses == stored, "下一幀 C 已存入")
    }

    @Test func aSingleBitmapLargerThanTheLimitIsDrawnButNeverCached() throws {
        let cache = GlyphRasterCache(byteLimit: 16)
        cache.beginFrame()
        _ = try Self.raster(cache, "A")
        #expect(cache.bytes == 0)
    }
}
