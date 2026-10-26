import CoreImage
import UIKit

/// BLUR 背景（F-V-06；sprint-5-detail.md §4.7；spec「BLUR 主題背景」）：封面縮到 1/8（雙線性）→ 高斯模糊 σ＝0.4×25＋0.6
/// （AOSP 半徑 25 換算，以縮圖像素計）→ 視圖鋪滿後疊黑 20%。換曲才重算，不在每幀做
enum TurntableBackground {
    static let downscale: CGFloat = 8
    static let sigma: Double = 0.4 * 25 + 0.6
    static let dimOpacity: Double = 0.2

    private static let context = CIContext()

    static func blurred(_ image: UIImage) -> UIImage? {
        guard let source = image.cgImage else { return nil }
        let width = max(1, Int((CGFloat(source.width) / downscale).rounded())), height = max(1, Int((CGFloat(source.height) / downscale).rounded()))
        let scaled = CIImage(cgImage: source).transformed(by: CGAffineTransform(scaleX: CGFloat(width) / CGFloat(source.width),
                                                                                 y: CGFloat(height) / CGFloat(source.height)))
        // 先夾邊再模糊、最後裁回原範圍：避免邊緣被透明拉暗
        let blurred = scaled.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return context.createCGImage(blurred, from: blurred.extent).map { UIImage(cgImage: $0) }
    }
}

extension AlbumPalette {
    /// 取色的邊長：先縮到 64×64 再量化（大圖不整張逐像素掃）
    static let sampleSide = 64

    static func extract(from image: UIImage) -> AlbumColors {
        guard let source = image.cgImage else { return .fallback }
        let side = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? extract(rgba: pixels) : .fallback
    }
}
