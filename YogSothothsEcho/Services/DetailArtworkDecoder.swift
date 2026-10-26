import ImageIO
import UIKit

/// 原圖解碼（CR-018；simcodex R1 security MEDIUM-1、efficiency #3）：先只讀檔頭的像素尺寸，過大＝不解碼直接拒收（PNG 可以
/// 用很小的檔宣告巨大尺寸）；通過後在呼叫端的執行緒降採樣到唱機顯示需要的大小並立即解碼，不把幾十 MB 的全尺寸點陣留到第一次繪製
enum DetailArtworkDecoder {
    /// 唱機封面套約 560–680 pt（@2x 1100–1360 px），留一點餘裕
    static let displayMaxPixels = 1600
    static let maxSourceEdge = 8192
    static let maxSourcePixels = 40_000_000

    /// 只讀檔頭：是圖、尺寸在上限內（不解像素；快取命中時的驗證用，解碼交給各端依自己的尺寸做）
    static func isAcceptable(_ data: Data) -> Bool { acceptedSource(data) != nil }

    private static func acceptedSource(_ data: Data) -> (source: CGImageSource, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, max(width, height) <= maxSourceEdge, width * height <= maxSourcePixels else { return nil }
        return (source, width, height)
    }

    static func displayImage(_ data: Data, maxPixels: Int = displayMaxPixels) -> UIImage? {
        guard let (source, width, height) = acceptedSource(data) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixels, max(width, height)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// 不在呼叫端（常是主執行緒）解：nonisolated async 在全域執行器上跑
    nonisolated static func decoded(_ data: Data, maxPixels: Int = displayMaxPixels) async -> UIImage? {
        displayImage(data, maxPixels: maxPixels)
    }
}
