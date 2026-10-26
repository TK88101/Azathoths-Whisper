import CoreGraphics
import SwiftUI
import Testing
import UIKit

@testable import YogSothothsEcho

// S6 T13（sprint-6-detail.md D13、§4.13）：唱機封套投影＋內陰影；投影畫在 clipShape 之外、跟著封套動（詳情封面的投影見 DetailRevealTests）
struct SleeveShadowTests {
    /// 原版：高度 8 dp×縮放（寬視窗 12 dp），向下位移＝模糊半徑
    @Test func turntableShadowScalesWithLayout() {
        let narrow = SleeveShadow.turntable(scale: 1, containerWidth: 700)
        let wide = SleeveShadow.turntable(scale: 1, containerWidth: 1376)
        #expect(narrow.radius == 8 && wide.radius == 12)
        #expect(SleeveShadow.turntable(scale: 2, containerWidth: 1376).radius == 24)
        #expect(wide.offsetY == wide.radius)
        for shadow in [narrow, wide] {
            #expect((0...1).contains(shadow.opacity) && (0...1).contains(shadow.innerOpacity))
        }
        #expect(SleeveShadow.turntable(scale: 1, containerWidth: 1376).opacity == 0.35)
        #expect(SleeveShadow.turntable(scale: 1, containerWidth: 1376).innerOpacity == 0.28)
    }

    /// 完整投影外框＝封套外框往下位移後向四周擴張模糊半徑
    @Test func extentCoversOffsetAndBlur() {
        let shadow = SleeveShadow(radius: 10, offsetY: 10, opacity: 0.3, innerOpacity: 0)
        #expect(shadow.extent(of: CGRect(x: 100, y: 100, width: 200, height: 200)) == CGRect(x: 90, y: 100, width: 220, height: 220))
    }
}

/// 不被裁切：投影畫在封套自身（clipShape 之外），封套下緣外側看得到陰影；旋轉後也一樣
@MainActor
struct SleeveFaceRenderTests {
    private func luminance(_ view: some View, size: CGSize, at point: CGPoint) -> Double? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -point.x, y: point.y - CGFloat(image.height) + 1, width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / 3
    }

    @Test(arguments: [0.0, 7.0])
    func shadowIsVisibleBelowTheSleeve(degrees: Double) throws {
        let shadow = SleeveShadow.turntable(scale: 1, containerWidth: 1376)
        let face = SleeveFace(image: nil, placeholder: .gray, size: CGSize(width: 200, height: 200), cornerRadius: 5, shadow: shadow)
        let scene = ZStack { Color.white; face.rotationEffect(.degrees(degrees)) }
        let size = CGSize(width: 400, height: 400)
        let below = try #require(luminance(scene, size: size, at: CGPoint(x: 200, y: 300 + shadow.offsetY)))
        let far = try #require(luminance(scene, size: size, at: CGPoint(x: 200, y: 395)))
        #expect(below < far - 10, "封套下緣外應有投影：\(below) vs \(far)")
    }

    /// 內陰影只在圓角內：封套中心仍是封面本色（內陰影不蓋滿）
    @Test func innerShadowStaysAtTheEdges() throws {
        let shadow = SleeveShadow.turntable(scale: 1, containerWidth: 1376)
        let face = SleeveFace(image: nil, placeholder: Color(white: 0.5), size: CGSize(width: 200, height: 200), cornerRadius: 5, shadow: shadow)
        let scene = ZStack { Color.white; face }
        let size = CGSize(width: 400, height: 400)
        let center = try #require(luminance(scene, size: size, at: CGPoint(x: 200, y: 200)))
        let edge = try #require(luminance(scene, size: size, at: CGPoint(x: 102, y: 200)))
        #expect(abs(center - 127.5) < 6)
        #expect(edge < center - 3, "內陰影應讓邊緣比中心暗：\(edge) vs \(center)")
    }
}
