import CoreGraphics
import Testing

@testable import YogSothothsEcho

// §4.2b v1.4（#5-1 G3 定案 Label Close-up）：標籤版面以標籤直徑 L 為單位——環狀字以 12 點為中心、固定字距、字頭朝外；
// 品牌字、條碼（水平）在中心孔下方（v1.6 起不畫條碼數字）

struct LabelLayoutTests {
    @Test func ringTextIsCenteredOnTwelveOClockWithFixedSpacing() {
        let angles = LabelLayout.ringAngles(count: LabelLayout.ringText.count)
        #expect(angles.count == LabelLayout.ringText.count)
        #expect(abs(angles.first! + angles.last!) < 1e-9)   // 首尾相對 12 點鏡像
        for (a, b) in zip(angles, angles.dropFirst()) { #expect(abs(b - a - LabelLayout.ringStep) < 1e-12) }
        #expect(abs(angles.last! - angles.first!) < 2 * Double.pi * 0.9)   // 不繞滿一圈，下方留口
    }

    @Test func ringGlyphPositionAndRotation() {
        let center = CGPoint(x: 100, y: 100), diameter: CGFloat = 200
        let top = LabelLayout.ringGlyph(angle: 0, center: center, diameter: diameter)
        #expect(abs(top.position.x - 100) < 1e-9 && abs(top.position.y - (100 - 0.437 * 200)) < 1e-9 && top.rotation == 0)
        let right = LabelLayout.ringGlyph(angle: .pi / 2, center: center, diameter: diameter)
        #expect(abs(right.position.x - (100 + 0.437 * 200)) < 1e-9 && abs(right.position.y - 100) < 1e-9)
        #expect(abs(right.rotation - .pi / 2) < 1e-12)   // 字頭朝外＝順時針轉中心角
    }

    @Test func ringTextIsTheChosenLine() {
        #expect(LabelLayout.ringText == "DESIGNED BY YOG-SOTHOTH'S ECHO IN FUKUOKA · MADE IN JAPAN")
    }

    /// 品牌字在中心孔下方、條碼在品牌字下方（不畫數字，#5-1 第 2 項），全部在環狀字內圈以內
    @Test func belowSpindleStackOrder() {
        #expect(LabelLayout.wordmarkTop > 0 && LabelLayout.barcodeTop > LabelLayout.wordmarkTop + LabelLayout.wordmarkFont)
        let bottom = LabelLayout.barcodeTop + LabelLayout.barcodeHeight * LabelLayout.guardExtension
        let corner = hypot(LabelLayout.barcodeWidth / 2, bottom)
        #expect(corner < LabelLayout.ringRadius - LabelLayout.ringFont)
        #expect(LabelLayout.wordmark == "YOG-SOTHOTH'S ECHO")
    }

    /// 條碼水平排：95 個模組平均分在 0.32L 寬內，置中；護條（首尾與中間）較長；
    /// 拿掉數字後條紋加長到原本「條碼＋數字」的總長（護條底緣＝原數字底緣 0.3238L）
    @Test func barcodeBarsAreHorizontalAndCentered() throws {
        let modules = try #require(UPCABarcode.modules("01234567890"))
        let bars = LabelLayout.barcodeBars(modules, diameter: 100)
        #expect(abs(bars.first!.minX - (-16)) < 1e-9)
        #expect(bars.allSatisfy { abs($0.minY - 20.5) < 1e-9 })
        #expect(bars.contains { abs($0.height - 10.6 * 1.12) < 1e-9 } && bars.contains { abs($0.height - 10.6) < 1e-9 })
        #expect(abs(bars.last!.maxX - 16) < 1e-9)
    }
}
