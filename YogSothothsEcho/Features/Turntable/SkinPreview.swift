import CoreGraphics
import Foundation

/// 選擇器預覽的一層（CR-034 增補 A §4.3）：唱片框 u 座標、rest 姿態（不轉）
struct SkinPreviewLayer: Equatable, Sendable {
    /// 宣告順序＝Z 序（由下而上）
    enum Kind: Hashable, Sendable {
        case base, baseMiddle, armShadow, arm, baseOverlay
    }

    let kind: Kind
    let rect: CGRect
}

/// 選擇器格子＝整支唱臂；設定頁那一列＝支點與底座（整支直立唱臂塞進列裡太細，m-3）
enum SkinPreviewCrop: Hashable, Sendable {
    case wholeArm, head
}

/// 預覽幾何（純函式）：圖層、rest 幀、裁切範圍都由皮膚自己的畫框推出，與唱機版面同一公式
enum SkinPreviewGeometry {
    static func layers(for skin: ResolvedTurntableSkin) -> [SkinPreviewLayer] {
        let spec = skin.spec, sprite = spec.spriteLayers
        func layer(_ kind: SkinPreviewLayer.Kind, _ frame: ArtworkFrame?) -> SkinPreviewLayer? {
            frame.map { SkinPreviewLayer(kind: kind, rect: CGRect(origin: spec.origin(of: $0), size: $0.size)) }
        }
        return [layer(.base, spec.base), layer(.baseMiddle, sprite?.middle), layer(.armShadow, sprite?.shadow), layer(.arm, spec.arm),
                layer(.baseOverlay, sprite?.overlay)]
            .compactMap { $0 }
    }

    /// 唱臂停著時畫的那一幀（m-1：不寫死 000，與唱機取幀同一函式）
    static func restFrame(for skin: ResolvedTurntableSkin) -> Int {
        TonearmSpriteCache.frameIndex(angle: skin.restDegrees, rest: skin.restDegrees, count: SpriteSkinAssets.frameCount)
    }

    /// 以支點為中心的正方形，左右涵蓋三層固定底座（下層、中層、上層；增補 B，Codex r2-4）
    static func headRegion(for skin: ResolvedTurntableSkin) -> CGRect {
        let spec = skin.spec, pivot = spec.kinematics.pivot
        let fixed = [spec.base, spec.baseMiddle, spec.baseOverlay].compactMap { $0 }
            .map { CGRect(origin: spec.origin(of: $0), size: $0.size) }
            .reduce(CGRect.null) { $0.union($1) }
        let half = max(pivot.x - fixed.minX, fixed.maxX - pivot.x)
        return CGRect(x: pivot.x - half, y: pivot.y - half, width: half * 2, height: half * 2)
    }

    /// 合成範圍：整支唱臂＝各層聯集（之後再依 alpha 裁）；head＝固定正方形
    static func region(for skin: ResolvedTurntableSkin, crop: SkinPreviewCrop) -> CGRect {
        switch crop {
        case .wholeArm: layers(for: skin).map(\.rect).reduce(CGRect.null) { $0.union($1) }
        case .head: headRegion(for: skin)
        }
    }
}

/// 把各層圖畫成一張預覽（輸出恰為要求的像素尺寸，等比置中）
enum SkinPreviewComposer {
    /// 先以輸出的 2 倍密度合成，裁切後再縮進輸出，邊緣較乾淨
    static let oversample: CGFloat = 2

    /// 合成時每 u 的像素數（各層解碼尺寸也依此）
    static func pixelsPerUnit(region: CGRect, pixelSize: CGSize) -> CGFloat {
        min(pixelSize.width / region.width, pixelSize.height / region.height) * oversample
    }

    static func compose(_ layers: [(SkinPreviewLayer, CGImage)], skin: ResolvedTurntableSkin, crop: SkinPreviewCrop,
                        pixelSize: CGSize) -> CGImage? {
        let region = SkinPreviewGeometry.region(for: skin, crop: crop)
        guard !layers.isEmpty, pixelSize.width >= 1, pixelSize.height >= 1, region.width > 0, region.height > 0 else { return nil }
        let k = pixelsPerUnit(region: region, pixelSize: pixelSize)
        let width = Int((region.width * k).rounded(.up)), height = Int((region.height * k).rounded(.up))
        guard let canvas = context(width: width, height: height) else { return nil }
        for (layer, image) in layers {
            let rect = layer.rect
            // CG 原點在左下：唱片框 y 向下 → 翻轉
            canvas.draw(image, in: CGRect(x: (rect.minX - region.minX) * k, y: CGFloat(height) - (rect.maxY - region.minY) * k,
                                          width: rect.width * k, height: rect.height * k))
        }
        guard var composed = canvas.makeImage() else { return nil }
        if crop == .wholeArm, let bounds = alphaBounds(composed), let cropped = composed.cropping(to: bounds) { composed = cropped }
        let outWidth = Int(pixelSize.width), outHeight = Int(pixelSize.height)
        guard let output = context(width: outWidth, height: outHeight) else { return nil }
        let scale = min(CGFloat(outWidth) / CGFloat(composed.width), CGFloat(outHeight) / CGFloat(composed.height))
        let drawn = CGSize(width: CGFloat(composed.width) * scale, height: CGFloat(composed.height) * scale)
        output.draw(composed, in: CGRect(x: (CGFloat(outWidth) - drawn.width) / 2, y: (CGFloat(outHeight) - drawn.height) / 2,
                                         width: drawn.width, height: drawn.height))
        return output.makeImage()
    }

    /// alpha > 0 的外接框（左上原點、像素）；全透明＝nil
    static func alphaBounds(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard let context = context(width: width, height: height), let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.interpolationQuality = .high
        return context
    }
}

/// 預覽圖源邊界（Bjork 慣例：外部邊界 protocol＋替身）
protocol SkinPreviewImageSource: Sendable {
    /// 該層的圖；沒有或解不開＝nil
    func image(_ kind: SkinPreviewLayer.Kind, skin: ResolvedTurntableSkin, maxPixelSize: Int) async -> CGImage?
}

/// 正式圖源：classic＝本機 MD Vinyl 素材（不入 repo）；序列圖＝bundle 內 rest 幀與兩層底座（與唱機同一解碼函式）
struct BundleSkinPreviewSource: SkinPreviewImageSource {
    /// 序列圖皮膚的檔名；classic＝nil
    static func fileName(_ kind: SkinPreviewLayer.Kind, skin: ResolvedTurntableSkin) -> String? {
        guard skin.spec.spriteLayers != nil else { return nil }
        let rest = SkinPreviewGeometry.restFrame(for: skin)
        return switch kind {
        case .base: SpriteSkinAssets.baseFile
        case .baseMiddle: SpriteSkinAssets.middleFile
        case .armShadow: SpriteSkinAssets.shadowFile(rest)
        case .arm: SpriteSkinAssets.armFile(rest)
        case .baseOverlay: SpriteSkinAssets.overlayFile
        }
    }

    func image(_ kind: SkinPreviewLayer.Kind, skin: ResolvedTurntableSkin, maxPixelSize: Int) async -> CGImage? {
        if let assets = skin.spec.spriteLayers?.assets, let name = Self.fileName(kind, skin: skin) {
            return SpriteDecoder.decode(.init(folder: assets.folder, name: name, maxPixelSize: maxPixelSize))
        }
        let name: VinylAssets.Name? = switch kind {
        case .base: .armBase
        case .arm: .arm
        case .baseMiddle, .armShadow, .baseOverlay: nil
        }
        guard let name else { return nil }
        return await MainActor.run { VinylAssets.image(name)?.cgImage }
    }
}
