import CoreGraphics
import UIKit

/// 包覆式書脊（#6-1 使用者選定 s6-spine-preview.html 樣式 4）：把封面最靠折邊的一條（小樣 4 px／764 pt）拉伸包到書脊上，
/// 字直接印在圖上，字色依那一條的亮度決定（淺底深字）；上端廠牌小方塊＋型號。純函式，SpineFace 只在圖或側別變時呼叫
enum SpineWrap {
    static let edgeFraction: CGFloat = 4.0 / 764
    /// 相對亮度高於此＝淺底，配深字（小樣同值）
    static let lightThreshold = 0.38

    /// 左側盒的書脊接封面左緣、右側盒接右緣
    static func edgeStripRect(imageWidth: Int, imageHeight: Int, side: CarouselSide) -> CGRect {
        let width = max(1, Int((CGFloat(imageWidth) * edgeFraction).rounded()))
        let x = side == .left ? 0 : imageWidth - width
        return CGRect(x: x, y: 0, width: width, height: imageHeight)
    }

    /// 先裁出顯示出來的正方形（`CoverCrop`），再從它的左／右緣取條
    static func edgeStrip(of image: UIImage, side: CarouselSide) -> CGImage? {
        CoverCrop.normalized(image).flatMap { edgeStrip(of: $0, side: side) }
    }

    /// 已是 up 方向的圖（烘焙在背景執行緒用這個）
    static func edgeStrip(of source: CGImage, side: CarouselSide) -> CGImage? {
        guard let visible = source.cropping(to: CoverCrop.visibleRect(pixelWidth: source.width, pixelHeight: source.height)) else { return nil }
        return visible.cropping(to: edgeStripRect(imageWidth: visible.width, imageHeight: visible.height, side: side))
    }

    /// 縮成 1 px 取平均色，回相對亮度（sRGB 線性化，WCAG 同式）
    static func averageLuminance(_ image: CGImage) -> Double {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return RGBColor(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255).luminance
    }

    static func isLight(luminance: Double) -> Bool { luminance > lightThreshold }

    /// 裝飾用型號：由專輯 ID 決定、四位數，穩定不跳
    static func catalogNumber(albumID: String) -> String {
        let seed = UInt64(albumID, radix: 16) ?? albumID.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return String(format: "YSE-%04llu", seed % 10_000)
    }
}
