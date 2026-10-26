import CoreGraphics
import Testing
import UIKit

@testable import YogSothothsEcho

// #6-1 書脊改包覆式（s6-spine-preview.html 樣式 4，使用者 2026-10-22 選定）：封面最靠折邊的一條拉伸到書脊上、
// 字色依那一條的亮度決定（淺底深字）、上端廠牌小方塊＋型號
struct SpineWrapTests {
    static func solid(_ color: UIColor, width: Int = 100, height: Int = 100) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.cgImage!
    }

    /// 左側盒的書脊接封面左緣、右側盒接右緣；寬＝封面寬的 4/764，至少 1 px
    @Test func stripComesFromTheFoldEdge() {
        #expect(SpineWrap.edgeStripRect(imageWidth: 1000, imageHeight: 1000, side: .left) == CGRect(x: 0, y: 0, width: 5, height: 1000))
        #expect(SpineWrap.edgeStripRect(imageWidth: 1000, imageHeight: 1000, side: .right) == CGRect(x: 995, y: 0, width: 5, height: 1000))
        #expect(SpineWrap.edgeStripRect(imageWidth: 100, imageHeight: 80, side: .right) == CGRect(x: 99, y: 0, width: 1, height: 80))
    }

    /// 實際裁出來的是那一側的顏色
    @Test func croppedStripHasTheEdgeColor() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let halves = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            UIColor.white.setFill()
            context.fill(CGRect(x: 100, y: 0, width: 100, height: 200))
        }
        let left = try #require(SpineWrap.edgeStrip(of: halves, side: .left))
        let right = try #require(SpineWrap.edgeStrip(of: halves, side: .right))
        #expect(SpineWrap.averageLuminance(left) < 0.05)
        #expect(SpineWrap.averageLuminance(right) > 0.95)
    }

    @Test func luminanceAndInkChoice() {
        #expect(SpineWrap.averageLuminance(Self.solid(.white)) > 0.95)
        #expect(SpineWrap.averageLuminance(Self.solid(.black)) < 0.05)
        #expect(SpineWrap.isLight(luminance: 0.9) && SpineWrap.isLight(luminance: 0.39))
        #expect(!SpineWrap.isLight(luminance: 0.37) && !SpineWrap.isLight(luminance: 0.05))
        // 黃色（相對亮度高）算淺、深藍算深
        #expect(SpineWrap.isLight(luminance: SpineWrap.averageLuminance(Self.solid(.yellow))))
        #expect(!SpineWrap.isLight(luminance: SpineWrap.averageLuminance(Self.solid(UIColor(red: 0.1, green: 0.1, blue: 0.5, alpha: 1)))))
    }

    /// 型號由專輯 ID 決定（穩定、四位數）
    @Test func catalogNumberIsStable() {
        let a = SpineWrap.catalogNumber(albumID: "74b8dcb8fb449734")
        #expect(a == SpineWrap.catalogNumber(albumID: "74b8dcb8fb449734"))
        #expect(a.hasPrefix("YSE-") && a.count == 8 && a.dropFirst(4).allSatisfy(\.isNumber))
        #expect(a != SpineWrap.catalogNumber(albumID: "0000000000000001"))
    }
}
