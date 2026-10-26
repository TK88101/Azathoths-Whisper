import CoreGraphics
import RemoteProtocol
import SwiftUI
import Testing
import UIKit

@testable import YogSothothsEcho

// #6-1 第二輪 F2 附帶（s6-61-round2.md §4 P1「CoverCrop」）：封面顯示＝scale-to-fill 置中正方形；
// 書脊折邊條要取「顯示出來的那塊」的邊，不是原圖的邊（非正方形封面時兩者不同）
@MainActor
struct CoverCropTests {
    /// 橫向四色條：x 0–25% 綠、25–50% 紅、50–75% 藍、75–100% 黃
    static func fourBands(width: Int = 400, height: Int = 200, vertical: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let colors: [UIColor] = [.green, .red, .blue, .yellow]
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            for (i, color) in colors.enumerated() {
                color.setFill()
                let rect = vertical
                    ? CGRect(x: 0, y: CGFloat(i * height) / 4, width: CGFloat(width), height: CGFloat(height) / 4)
                    : CGRect(x: CGFloat(i * width) / 4, y: 0, width: CGFloat(width) / 4, height: CGFloat(height))
                context.fill(rect)
            }
        }
    }

    static func averageRGB(_ image: CGImage) -> (Double, Double, Double) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    @Test func visibleRectIsCenteredSquare() {
        #expect(CoverCrop.visibleRect(pixelWidth: 400, pixelHeight: 200) == CGRect(x: 100, y: 0, width: 200, height: 200))
        #expect(CoverCrop.visibleRect(pixelWidth: 200, pixelHeight: 400) == CGRect(x: 0, y: 100, width: 200, height: 200))
        #expect(CoverCrop.visibleRect(pixelWidth: 300, pixelHeight: 300) == CGRect(x: 0, y: 0, width: 300, height: 300))
        // 奇數差取整到整數 pixel
        #expect(CoverCrop.visibleRect(pixelWidth: 301, pixelHeight: 200) == CGRect(x: 50, y: 0, width: 200, height: 200))
    }

    @Test func normalizedRedrawsNonUpOrientation() throws {
        let base = try #require(Self.fourBands(width: 40, height: 20).cgImage)
        let rotated = UIImage(cgImage: base, scale: 1, orientation: .right)   // 顯示為 20×40
        let normalized = try #require(CoverCrop.normalized(rotated))
        #expect(normalized.width == 20 && normalized.height == 40)
        let up = UIImage(cgImage: base, scale: 1, orientation: .up)
        #expect(CoverCrop.normalized(up) === base)
    }

    /// 橫圖：書脊左側取「中左紅」、右側取「中右藍」（舊碼取原圖邊＝綠／黃）
    @Test func edgeStripComesFromVisibleSquare() throws {
        let image = Self.fourBands()
        let left = try #require(SpineWrap.edgeStrip(of: image, side: .left))
        let right = try #require(SpineWrap.edgeStrip(of: image, side: .right))
        let (lr, lg, lb) = Self.averageRGB(left), (rr, rg, rb) = Self.averageRGB(right)
        #expect(lr > 0.8 && lg < 0.2 && lb < 0.2, "左 \(lr),\(lg),\(lb)")
        #expect(rb > 0.8 && rr < 0.2 && rg < 0.2, "右 \(rr),\(rg),\(rb)")
        // 寬＝可視正方形邊長 × 4/764，至少 1 px
        #expect(left.width == max(1, Int((200 * SpineWrap.edgeFraction).rounded())) && left.height == 200)
    }

    /// 直圖：可視正方形左右不裁，取原圖左右邊（上下四色帶 → 左右兩邊都含中間兩色）
    @Test func portraitKeepsFullWidth() throws {
        let image = Self.fourBands(width: 200, height: 400, vertical: true)
        let left = try #require(SpineWrap.edgeStrip(of: image, side: .left))
        #expect(left.height == 200)
        let (r, g, b) = Self.averageRGB(left)
        // 可視區＝y 100–300＝紅＋藍各半
        #expect(r > 0.35 && b > 0.35 && g < 0.2, "\(r),\(g),\(b)")
    }

    /// 整合：封面畫面最左／最右欄與書脊取色一致（同一塊可視正方形）
    @Test func coverAndSpineAgreeOnEdges() throws {
        let image = Self.fourBands()
        let album = AlbumSummary(id: "0000000000000001", title: "A", artist: "B", trackCount: 1, artworkToken: nil)
        let renderer = ImageRenderer(content: AlbumCoverImage(album: album, image: image).frame(width: 200, height: 200))
        renderer.scale = 1
        let shot = try #require(renderer.cgImage)
        let leftColumn = try #require(shot.cropping(to: CGRect(x: 1, y: 0, width: 1, height: 200)))
        let rightColumn = try #require(shot.cropping(to: CGRect(x: 198, y: 0, width: 1, height: 200)))
        let (lr, _, _) = Self.averageRGB(leftColumn), (_, _, rb) = Self.averageRGB(rightColumn)
        let (sr, _, _) = Self.averageRGB(try #require(SpineWrap.edgeStrip(of: image, side: .left)))
        let (_, _, sb) = Self.averageRGB(try #require(SpineWrap.edgeStrip(of: image, side: .right)))
        #expect(lr > 0.8 && sr > 0.8, "封面左欄紅 \(lr)、書脊左紅 \(sr)")
        #expect(rb > 0.8 && sb > 0.8, "封面右欄藍 \(rb)、書脊右藍 \(sb)")
    }
}
