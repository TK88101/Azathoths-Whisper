import CoreGraphics
import UIKit

/// 封面「顯示出來的那塊」（#6-1 第二輪 F2 附帶）：`AlbumCoverImage` 以 scale-to-fill 置中顯示，非正方形的圖只露出中間的正方形。
/// 書脊折邊條要從同一塊取邊，畫面與書脊才接得上
enum CoverCrop {
    /// 轉成方向為 up 的 CGImage（`cgImage` 不含 EXIF 方向；非 up 時重繪一次）
    static func normalized(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }.cgImage
    }

    /// normalized 圖的 pixel 座標中、scale-to-fill 置中的正方形
    static func visibleRect(pixelWidth: Int, pixelHeight: Int) -> CGRect {
        let side = min(pixelWidth, pixelHeight)
        return CGRect(x: (pixelWidth - side) / 2, y: (pixelHeight - side) / 2, width: side, height: side)
    }
}
