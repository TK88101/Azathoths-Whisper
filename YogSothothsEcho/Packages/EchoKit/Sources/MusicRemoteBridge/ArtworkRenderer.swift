#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import RemoteProtocol
import UniformTypeIdentifiers

/// 原圖 → spine JPEG（sprint-3-detail.md §4.3）。品質 0.8 起，超過位元組預算每次降 0.1，最低 0.4 仍超過回 nil
public enum ArtworkRenderer {
    static let qualities: [Double] = [0.8, 0.7, 0.6, 0.5, 0.4]

    public static func spineJPEG(from original: Data, maxBytes: Int = CatalogLimits.spineMaxJPEGBytes) -> Data? {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: CatalogLimits.spinePixels,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        for quality in qualities {
            if let jpeg = encode(image, quality: quality), jpeg.count <= maxBytes { return jpeg }
        }
        return nil
    }

    private static func encode(_ image: CGImage, quality: Double) -> Data? {
        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(buffer, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? buffer as Data : nil
    }
}
#endif
