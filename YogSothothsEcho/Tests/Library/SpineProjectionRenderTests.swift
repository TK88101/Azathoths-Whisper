import CoreGraphics
import RemoteProtocol
import SwiftUI
import Testing
import UIKit

@testable import YogSothothsEcho

// S6 T0b（sprint-6-detail.md §5 T0b ①②、D5）：SwiftUI `projectionEffect` 實際渲染出的位置＝`BoxProjection` 計算值。
// ① 共用消失點：兩個不同 x、同角度的盒子，渲染出的像素外框與計算的投影外框相符（±1 pt）
// ② 交接：同一個 2D 框以仿射 CATransform3D 經 projectionEffect 畫出，與直接 frame＋offset 畫出的像素相同
@MainActor
struct SpineProjectionRenderTests {
    let m = SpineCarouselTests.pro13

    /// 以 1× 渲染，回傳指定顏色（純紅／純藍）像素的外框（pt）
    private func pixelBounds(_ view: some View, size: CGSize, match: (UInt8, UInt8, UInt8) -> Bool) -> CGRect? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard data[i + 3] > 200, match(data[i], data[i + 1], data[i + 2]) else { continue }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func face(_ face: BoxProjection.Face, pose: BoxPose, color: Color) -> some View {
        let projection = BoxProjection(metrics: m)
        let size = projection.size(of: face)
        return color.frame(width: size.width, height: size.height)
            .projectionEffect(ProjectionTransform(projection.transform(face, pose: pose)))
    }

    private func near(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.maxX - b.maxX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }

    @Test func projectionEffectMatchesComputedQuads() {
        let projection = BoxProjection(metrics: m)
        let left = SpineCarousel.pose(u: -1.5, metrics: m)
        let right = SpineCarousel.pose(u: 2.5, metrics: m)
        let scene = ZStack(alignment: .topLeading) {
            Color.white
            face(.front, pose: left, color: Color(red: 1, green: 0, blue: 0))
            face(.spine, pose: left, color: Color(red: 0, green: 1, blue: 0))
            face(.front, pose: right, color: Color(red: 0, green: 0, blue: 1))
        }
        let size = m.browse.size
        let red = pixelBounds(scene, size: size) { r, g, b in r > 200 && g < 60 && b < 60 }
        let green = pixelBounds(scene, size: size) { r, g, b in g > 200 && r < 60 && b < 60 }
        let blue = pixelBounds(scene, size: size) { r, g, b in b > 200 && r < 60 && g < 60 }
        let expectedRed = projection.bounds(.front, pose: left).intersection(m.browse)
        let expectedGreen = projection.bounds(.spine, pose: left)
        let expectedBlue = projection.bounds(.front, pose: right).intersection(m.browse)
        #expect(red.map { near($0, expectedRed) } == true, "紅 \(String(describing: red)) vs \(expectedRed)")
        #expect(green.map { near($0, expectedGreen) } == true, "綠 \(String(describing: green)) vs \(expectedGreen)")
        #expect(blue.map { near($0, expectedBlue) } == true, "藍 \(String(describing: blue)) vs \(expectedBlue)")
    }

    @Test func affineHandoffMatchesPlainLayout() {
        let target = CGRect(x: 213, y: 155, width: 370, height: 370)   // 詳情封面框（約 0.43H）
        let side = CGFloat(m.cover)
        var affine = CATransform3DMakeScale(target.width / side, target.height / side, 1)
        affine = CATransform3DConcat(affine, CATransform3DMakeTranslation(target.minX, target.minY, 0))
        let flown = ZStack(alignment: .topLeading) {
            Color.white
            Color(red: 1, green: 0, blue: 0).frame(width: side, height: side)
                .projectionEffect(ProjectionTransform(affine))
        }
        let plain = ZStack(alignment: .topLeading) {
            Color.white
            Color(red: 1, green: 0, blue: 0).frame(width: target.width, height: target.height)
                .offset(x: target.minX, y: target.minY)
        }
        let isRed: (UInt8, UInt8, UInt8) -> Bool = { r, g, b in r > 200 && g < 60 && b < 60 }
        let a = pixelBounds(flown, size: m.browse.size, match: isRed)
        let b = pixelBounds(plain, size: m.browse.size, match: isRed)
        #expect(a != nil && a == b, "\(String(describing: a)) vs \(String(describing: b))")
        #expect(b.map { near($0, target, tolerance: 0.5) } == true)
    }

    /// #6-1：非正方形封面（直式）以 fill 放大後要裁在正方形框內，不得上下超出盒子
    @Test func nonSquareArtworkStaysInsideTheSquareFrame() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 200), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 200))
        }
        let album = AlbumSummary(id: "00000000000000aa", title: "Made-up", artist: "Someone", trackCount: 1, artworkToken: "00000000000000bb")
        let view = ZStack { AlbumCoverImage(album: album, image: tall).frame(width: 100, height: 100) }
        let bounds = try #require(pixelBounds(view, size: CGSize(width: 100, height: 300)) { r, g, b in r > 200 && g < 40 && b < 40 })
        #expect(abs(bounds.minY - 100) <= 1 && abs(bounds.height - 100) <= 1)
        #expect(abs(bounds.width - 100) <= 1)
    }
}
