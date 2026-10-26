import CoreGraphics
import SwiftUI

/// F2 紋理（紙纖維、邊緣磨白、磨損）的點陣快取。
/// 已核（2026-10-23 Time Profiler＋實機 N-03 1.4 fps）：平鋪圖（`resizingMode: .tile`）與圖樣筆刷（`ImagePaint`）在 SwiftUI 底下
/// 走 CoreGraphics 的 CPU 圖樣填色，捲動時每格重鋪；改為每張專輯每個面在背景以 CoreGraphics 畫一次成一張圖，畫面只貼圖（GPU）。
/// 密度同原本（紋理以 1 倍繪製）
enum FaceTexture {
    /// 正面：紙纖維＋邊緣磨白＋磨損（三層在正面本就相鄰疊在最上）。書脊改由 `SpineBake` 整面烘焙
    struct Key: Hashable, Sendable {
        let albumID: String
        /// 正方形邊長（pt）
        let side: Int

        static func front(albumID: String, length: CGFloat) -> Key { Key(albumID: albumID, side: Int(length.rounded())) }
    }

    /// 正面邊緣磨白：四邊、寬 4 pt × u
    static func edgeWidth(size: CGSize) -> CGFloat { 4 * size.height / SpineCarouselMetrics.referenceCover }
    static let edgeOpacity = 0.55

    /// 在任意執行緒以 CoreGraphics 繪製（路徑座標＝面的本地座標，左上為原點）
    static func render(_ key: Key) -> CGImage? {
        let size = CGSize(width: key.side, height: key.side)
        guard key.side > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: key.side, height: key.side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        let rect = CGRect(origin: .zero, size: size)
        TextureDrawing.tile(ctx, PaperFiber.tileImage, in: rect)
        TextureDrawing.edgeBands(ctx, in: rect, width: edgeWidth(size: size), allSides: true, opacity: edgeOpacity)
        drawWear(ctx, albumID: key.albumID, surface: .front, size: size)
        return ctx.makeImage()
    }

    /// 起毛帶以纖維圖填、細邊碎屑以碎屑圖填，再填紙漿色實心；裁在該面內
    private static func drawWear(_ ctx: CGContext, albumID: String, surface: SpineWear.Surface, size: CGSize) {
        let paths = SpineWear.paths(albumID: albumID, shape: SpineWear.shape(albumID: albumID), surface: surface, size: size)
        let rect = CGRect(origin: .zero, size: size)
        ctx.saveGState()
        ctx.clip(to: rect)
        TextureDrawing.tile(ctx, PaperFiber.haloImage, in: rect, clip: paths.halo.cgPath)
        TextureDrawing.tile(ctx, PaperFiber.fleckImage, in: rect, clip: paths.flecks.cgPath)
        ctx.addPath(paths.core.cgPath)
        ctx.setFillColor(red: PaperFiber.pulp.red, green: PaperFiber.pulp.green, blue: PaperFiber.pulp.blue, alpha: 1)
        ctx.fillPath()
        ctx.restoreGState()
    }
}

extension CGImage {
    /// 快取成本：寬×高×4（`bytesPerRow` 有對齊補位，不用）——FaceTexture、SpineBake、BrowseArtwork 的 LRU 共用
    var byteCost: Int { width * height * 4 }
}

/// 紋理平鋪與邊緣磨白（正面 FaceTexture 與書脊 SpineBake 共用）：紋理以 1 張圖素對 1 pt 平鋪（同原本以 1 倍繪製的密度）
enum TextureDrawing {
    static func tile(_ ctx: CGContext, _ image: CGImage, in rect: CGRect, clip: CGPath? = nil, alpha: Double = 1,
                     blend: CGBlendMode = .normal) {
        ctx.saveGState()
        if let clip {
            ctx.addPath(clip)
            ctx.clip()
        } else {
            ctx.clip(to: rect)
        }
        ctx.setAlpha(alpha)
        ctx.setBlendMode(blend)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), byTiling: true)
        ctx.restoreGState()
    }

    /// 淺色雜點只留在邊緣 `width` 內：兩段條帶近似由邊緣往內淡出（外半 0.75、內半 0.25）
    static func edgeBands(_ ctx: CGContext, in rect: CGRect, width: CGFloat, allSides: Bool, opacity: Double) {
        tile(ctx, PaperFiber.edgeLightImage, in: rect, clip: EdgeBands(from: 0, to: width / 2, allSides: allSides).path(in: rect).cgPath,
             alpha: 0.75 * opacity)
        tile(ctx, PaperFiber.edgeLightImage, in: rect, clip: EdgeBands(from: width / 2, to: width, allSides: allSides).path(in: rect).cgPath,
             alpha: 0.25 * opacity)
    }
}

/// 點陣的快取（最久未用先淘汰，`MemoryLRU` 以位元組計）。正面一張約 2.2 MiB（764² RGBA），預算 48 MiB≈21 張正面
/// （側封可見約 10 張＋兩側預熱）；書脊極小。s6-61-g-perf-wear.md T1
@MainActor
final class FaceTextureCache {
    static let shared = FaceTextureCache()
    static let byteLimit = 48 * 1_048_576

    /// 單元／Render 測試：缺圖時當場同步繪製（ImageRenderer 不等非同步）
    var rendersSynchronously = false
    private(set) var renderCount = 0

    private var entries: MemoryLRU<FaceTexture.Key, CGImage>
    private var inFlight: [FaceTexture.Key: Task<CGImage?, Never>] = [:]

    init(byteLimit: Int = FaceTextureCache.byteLimit) {
        entries = MemoryLRU(costLimit: byteLimit)
    }

    var totalBytes: Int { entries.totalCost }

    func cached(_ key: FaceTexture.Key) -> CGImage? {
        if let hit = entries.value(for: key) { return hit }
        guard rendersSynchronously, let image = FaceTexture.render(key) else { return nil }
        renderCount += 1
        store(key, image)
        return image
    }

    /// 背景繪製；同一張圖同時只畫一次
    func load(_ key: FaceTexture.Key) async -> CGImage? {
        if let hit = entries.value(for: key) { return hit }
        let task = inFlight[key] ?? Task.detached(priority: .userInitiated) { FaceTexture.render(key) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            renderCount += 1
            store(key, image)
        }
        return image
    }

    private func store(_ key: FaceTexture.Key, _ image: CGImage) {
        entries.set(key, image, cost: image.byteCost)
    }
}

/// 貼一張紋理點陣；尚未畫好時先不顯示（新捲進來的盒子紋理晚一兩格出現）
struct FaceTextureView: View {
    let key: FaceTexture.Key
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let shown = image ?? FaceTextureCache.shared.cached(key) {
                Image(decorative: shown, scale: 1).resizable()
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .task(id: key) {
            guard FaceTextureCache.shared.cached(key) == nil else { return }
            image = await FaceTextureCache.shared.load(key)
        }
    }
}
