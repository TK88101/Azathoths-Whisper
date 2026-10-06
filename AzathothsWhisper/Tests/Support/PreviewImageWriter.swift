import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 把離屏渲染的圖寫成 PNG／GIF（只給預覽產物用，A2 計劃 §3.6）
enum PreviewImageWriter {
    enum Failure: Error {
        case cannotCreate(URL)
        case cannotFinalize(URL)
    }

    @discardableResult
    static func png(_ image: CGImage, to url: URL) throws -> URL {
        try write([image], type: .png, to: url, frameProperties: nil, fileProperties: nil)
    }

    /// 無限循環；每幀 `delay` 秒
    @discardableResult
    static func gif(_ frames: [CGImage], delay: Double, to url: URL) throws -> URL {
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
        let file = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        return try write(frames, type: .gif, to: url, frameProperties: frame, fileProperties: file)
    }

    private static func write(_ images: [CGImage], type: UTType, to url: URL, frameProperties: CFDictionary?, fileProperties: CFDictionary?) throws -> URL {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, images.count, nil) else {
            throw Failure.cannotCreate(url)
        }
        if let fileProperties { CGImageDestinationSetProperties(destination, fileProperties) }
        images.forEach { CGImageDestinationAddImage(destination, $0, frameProperties) }
        guard CGImageDestinationFinalize(destination) else { throw Failure.cannotFinalize(url) }
        return url
    }
}
