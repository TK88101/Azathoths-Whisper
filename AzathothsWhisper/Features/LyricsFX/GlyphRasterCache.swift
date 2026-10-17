import CoreGraphics
import SwiftUI

/// 字形點陣快取（計劃 2026-10-16 §2.2；尺寸策略改版：計劃 2026-10-17 全螢幕缺口 §9.2–9.5）。
/// 外框在 `GlyphPathCache.Entry` 的座標下光柵化成只有 alpha 的遮罩，畫時當 template 圖上色、套同一個 `transform(for:)`。
/// 尺寸：Canvas 貼圖固定是雙線性取樣，點陣只要被放大、落在次像素、或旋轉就會偏離向量畫法；以「螢幕上需要的像素 × 1.6–1.87 倍」
/// 建點陣再縮小貼上，對任何相位與旋轉都最接近向量（spike M1–M8）。所以按字在螢幕上的 x／y 縮放分檔，每檔差 1.87/1.6 倍。
/// 只在主執行緒用（同 `GlyphPathCache`）
final class GlyphRasterCache {
    struct Entry {
        let image: Image
        let cgImage: CGImage
        /// 外框座標 → 點陣像素（y 向下、原點在點陣左上）
        let toPixels: CGAffineTransform
        /// 上式的反矩陣，貼圖時用（建圖時算一次，不必每幀每字求逆）
        let fromPixels: CGAffineTransform
        let bytes: Int
    }

    /// 點陣的檔位：x、y 各自的 `pixelsPerUnit` 指數
    struct Tier: Hashable {
        let x: Int
        let y: Int
    }

    private struct Key: Hashable {
        let text: String
        let face: FontFace
        let size: CGFloat
        let tier: Tier
    }

    private struct Slot {
        let entry: Entry
        var lastUsedFrame: Int
    }

    /// 點陣比螢幕需要的像素多出的倍數區間（spike 3a：[1.6, 1.87) 讓 V3 全案達標）
    static let minimumOversample: CGFloat = 1.6
    static let maximumOversample: CGFloat = 1.87
    static let defaultByteLimit = 16 * 1024 * 1024

    let byteLimit: Int
    private(set) var bytes = 0
    /// 累計建圖次數（DEBUG 量測摘要用）
    private(set) var misses = 0
    private var store: [Key: Slot] = [:]
    private var frame = 0

    init(byteLimit: Int = GlyphRasterCache.defaultByteLimit) {
        self.byteLimit = byteLimit
    }

    /// 相鄰兩檔的解析度比：檔位 n 的點陣是每個外框單位 `tierRatio^n` 像素
    private static let tierRatio = maximumOversample / minimumOversample
    /// 每幀每字都要算檔位，log 的除數先算好
    private static let inverseLogTierRatio = 1 / log(tierRatio)
    /// 字縮到幾乎看不見時的下限，免得 log 發散
    private static let smallestPixelsPerUnit: CGFloat = 1e-3

    /// 螢幕上每個外框單位需要 `pixelsPerUnit` 像素時的檔位：取點陣 ≥ 1.6 倍螢幕像素的最小一檔
    static func tier(pixelsPerUnit: CGFloat) -> Int {
        Int((log(minimumOversample * max(pixelsPerUnit, smallestPixelsPerUnit)) * inverseLogTierRatio).rounded(.up))
    }

    /// 檔位對應的點陣解析度（每個外框單位幾像素）
    static func pixelsPerUnit(tier: Int) -> CGFloat {
        pow(tierRatio, CGFloat(tier))
    }

    /// 每幀開頭呼叫：本幀用到的點陣不會被逐出
    func beginFrame() {
        frame += 1
    }

    /// 建不出點陣（配置失敗）回 nil：這個字這一幀不畫、也不進快取
    func entry(text: String, face: FontFace, path: GlyphPathCache.Entry, tier: Tier) -> Entry? {
        let key = Key(text: text, face: face, size: path.size, tier: tier)
        if let index = store.index(forKey: key) {
            store.values[index].lastUsedFrame = frame
            return store.values[index].entry
        }
        misses += 1
        guard let made = Self.rasterize(path.path, scaleX: Self.pixelsPerUnit(tier: tier.x), scaleY: Self.pixelsPerUnit(tier: tier.y)) else { return nil }
        guard made.bytes <= byteLimit else { return made }
        if bytes + made.bytes > byteLimit { evict(toFit: made.bytes) }
        // 本幀用到的都不能逐出、還是放不下 → 這一張只畫不存，下一幀再試
        guard bytes + made.bytes <= byteLimit else { return made }
        store[key] = Slot(entry: made, lastUsedFrame: frame)
        bytes += made.bytes
        return made
    }

    /// 由最久沒用的開始逐出，只逐到放得下為止；本幀用過的不逐出（整批清空會讓那一幀重建全部點陣，實測掉兩格，計劃 §9.5 3b）
    private func evict(toFit incoming: Int) {
        let candidates = store.filter { $0.value.lastUsedFrame < frame }.sorted { $0.value.lastUsedFrame < $1.value.lastUsedFrame }
        for (key, slot) in candidates {
            guard bytes + incoming > byteLimit else { return }
            store[key] = nil
            bytes -= slot.entry.bytes
        }
    }

    func removeAll() {
        store.removeAll(keepingCapacity: true)
        bytes = 0
    }

    /// 外框以 (scaleX, scaleY) 光柵化；四周各留 2 像素給抗鋸齒，原點取整
    static func rasterize(_ path: CGPath, scaleX: CGFloat, scaleY: CGFloat) -> Entry? {
        let outline = path.boundingBoxOfPath
        guard !outline.isNull else { return nil }
        let scaling = CGAffineTransform(scaleX: scaleX, y: scaleY)
        let scaled = outline.applying(scaling)
        let originX = floor(scaled.minX) - 2, originY = floor(scaled.minY) - 2
        let width = Int(ceil(scaled.maxX - originX) + 2), height = Int(ceil(scaled.maxY - originY) + 2)
        let toPixels = scaling.concatenating(CGAffineTransform(translationX: -originX, y: -originY))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return nil }
        // 外框座標 y 向下（`GlyphPathCache.outline` 已翻過）；點陣第 0 列在上
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.concatenate(toPixels)
        context.addPath(path)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        guard let image = context.makeImage() else { return nil }
        return Entry(image: Image(decorative: image, scale: 1).renderingMode(.template), cgImage: image, toPixels: toPixels, fromPixels: toPixels.inverted(), bytes: context.bytesPerRow * height)
    }
}

extension GlyphRasterCache.Tier {
    /// placement＝外框座標 → 畫布點；deviceScale＝畫布點 → 螢幕像素（displayScale × 整屏縮放）。
    /// 旋轉不改兩軸的長度；兩軸等長（絕大多數的字）時只算一次檔位
    init(placement: CGAffineTransform, deviceScale: CGFloat) {
        let scaleX = hypot(placement.a, placement.b) * deviceScale
        let scaleY = hypot(placement.c, placement.d) * deviceScale
        let tierX = GlyphRasterCache.tier(pixelsPerUnit: scaleX)
        self.init(x: tierX, y: scaleX == scaleY ? tierX : GlyphRasterCache.tier(pixelsPerUnit: scaleY))
    }
}
