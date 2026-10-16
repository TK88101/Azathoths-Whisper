import CoreGraphics
import SwiftUI

/// 字形點陣快取（計劃 2026-10-16 §2.2）：外框在 `GlyphPathCache.Entry` 的座標下、以螢幕像素密度光柵化成只有 alpha 的遮罩，
/// 畫時當 template 圖上色、套同一個 `transform(for:)`——基線與旋轉軸由構造保證和合併外框的畫法一致。
/// 不按動畫縮放分檔：實測分檔與固定高解析度都比「點陣＝螢幕像素」更偏離向量畫法（計劃 §1 F5）。
/// 只在主執行緒用（同 `GlyphPathCache`）
final class GlyphRasterCache {
    struct Entry {
        let image: Image
        let cgImage: CGImage?
        /// 點陣涵蓋的範圍（外框座標）：外框外擴 1 pt 留抗鋸齒、再取整
        let box: CGRect
        let bytes: Int
    }

    private struct Key: Hashable {
        let text: String
        let face: FontFace
        let size: CGFloat
        let pixelsPerPoint: CGFloat
    }

    static let defaultByteLimit = 16 * 1024 * 1024

    let byteLimit: Int
    private(set) var bytes = 0
    /// 累計建圖次數（DEBUG 量測摘要用）
    private(set) var misses = 0
    private var store: [Key: Entry] = [:]
    private var clearedThisFrame = false

    init(byteLimit: Int = GlyphRasterCache.defaultByteLimit) {
        self.byteLimit = byteLimit
    }

    /// 每幀開頭呼叫：每幀最多整批清空一次，同幀再超額的點陣只畫不存（計劃 §2.2）
    func beginFrame() {
        clearedThisFrame = false
    }

    func entry(text: String, face: FontFace, path: GlyphPathCache.Entry, pixelsPerPoint: CGFloat) -> Entry {
        let key = Key(text: text, face: face, size: path.size, pixelsPerPoint: pixelsPerPoint)
        if let hit = store[key] { return hit }
        misses += 1
        let made = Self.rasterize(path.path, pixelsPerPoint: pixelsPerPoint)
        guard made.bytes <= byteLimit else { return made }
        if bytes + made.bytes > byteLimit {
            guard !clearedThisFrame else { return made }
            store.removeAll(keepingCapacity: true)
            bytes = 0
            clearedThisFrame = true
        }
        store[key] = made
        bytes += made.bytes
        return made
    }

    static func rasterize(_ path: CGPath, pixelsPerPoint scale: CGFloat) -> Entry {
        let outline = path.boundingBoxOfPath
        let box = (outline.isNull ? .zero : outline).insetBy(dx: -1, dy: -1).integral
        let width = max(1, Int((box.width * scale).rounded(.up))), height = max(1, Int((box.height * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return Entry(image: Image(decorative: emptyImage, scale: 1), cgImage: nil, box: .zero, bytes: 0) }
        // 外框座標 y 向下（`GlyphPathCache.outline` 已翻過）；點陣第 0 列在上
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -box.minX, y: -box.maxY)
        context.addPath(path)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        guard let image = context.makeImage() else {
            return Entry(image: Image(decorative: emptyImage, scale: 1), cgImage: nil, box: .zero, bytes: 0)
        }
        return Entry(image: Image(decorative: image, scale: scale).renderingMode(.template), cgImage: image, box: box, bytes: context.bytesPerRow * height)
    }

    /// 建不出點陣時的替代（1×1 透明）：畫了也看不見，不中斷整幀
    private static let emptyImage: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
        return context.makeImage()!
    }()
}
