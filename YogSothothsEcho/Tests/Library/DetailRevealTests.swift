import CoreGraphics
import SwiftUI
import Testing
import UIKit

@testable import YogSothothsEcho

// #6-1 第一輪修正（s6-61-round1-fixes.md v0.6 §3 F6、F5；使用者 2026-10-22 小樣定稿）：
// 文字「從深處浮上來」——縮放 0.90→1、模糊 10→0、下移 16→0、0.42 s；依序：專輯名 → 藝人 → Play，右欄每列晚 0.06 s。
// 詳情封面投影＝同尺寸深色板往下錯開（444 pt 封面：錯開 32.4、模糊 16.2、深色 0.675／淺色 0.45），隨飛行進度長出
struct DetailRevealTests {
    @Test func poseStartsDeepAndEndsSettled() {
        let before = DetailRevealPose.at(elapsed: 0.1, delay: 0.3)
        #expect(before == DetailRevealPose(opacity: 0, scale: 0.90, blur: 10, offsetY: 16))
        let done = DetailRevealPose.at(elapsed: 0.3 + 0.42, delay: 0.3)
        #expect(done == DetailRevealPose(opacity: 1, scale: 1, blur: 0, offsetY: 0))
        #expect(DetailRevealPose.at(elapsed: 5, delay: 0) == .settled)
    }

    @Test func poseIsMonotonic() {
        var last = DetailRevealPose.at(elapsed: 0, delay: 0)
        for step in 1...50 {
            let pose = DetailRevealPose.at(elapsed: Double(step) / 100, delay: 0)
            #expect(pose.opacity >= last.opacity && pose.scale >= last.scale && pose.blur <= last.blur && pose.offsetY <= last.offsetY)
            last = pose
        }
        // 透明度先到：前 1/1.4 段就到 1
        #expect(DetailRevealPose.at(elapsed: 0.42 * 0.8, delay: 0).opacity == 1)
    }

    /// Reduce Motion：只淡入，無縮放、模糊、位移；透明度＝通道值
    @Test func reduceMotionOnlyFades() {
        let pose = DetailRevealPose.reduced(progress: 0.4)
        #expect(pose == DetailRevealPose(opacity: 0.4, scale: 1, blur: 0, offsetY: 0))
    }

    @Test func scheduleOrdersLeftColumnAndRows() {
        let s = DetailRevealSchedule(itemCount: 12)
        #expect(DetailRevealSchedule.title == 0 && DetailRevealSchedule.artist == 0.32 && DetailRevealSchedule.play == 0.62)
        #expect(abs(s.item(0) - 0.04) < 1e-9 && abs(s.item(1) - 0.10) < 1e-9 && abs(s.item(11) - 0.70) < 1e-9)
        #expect(abs(s.end - (0.70 + 0.42)) < 1e-9)
        // 短專輯：最後是 Play
        #expect(abs(DetailRevealSchedule(itemCount: 2).end - (0.62 + 0.42)) < 1e-9)
        // 第 16 項以後封頂：與第 16 項同時出場
        let long = DetailRevealSchedule(itemCount: 200)
        #expect(long.item(40) == long.item(16) && abs(long.end - (0.04 + 16 * 0.06 + 0.42)) < 1e-9)
    }

    /// 關閉＝倒放：最後出現的先沉回去
    @Test func reversedRevealSinksLastItemFirst() {
        let s = DetailRevealSchedule(itemCount: 12)
        let elapsed = s.end - 0.2
        let last = DetailRevealPose.at(elapsed: elapsed, delay: s.item(11))
        let first = DetailRevealPose.at(elapsed: elapsed, delay: s.item(0))
        #expect(last != .settled && last.blur > 0 && first == .settled)
    }

    @Test func coverShadowMatchesTheSignedPreview() {
        let dark = DetailCoverShadow(coverSide: 444, opacity: 0.675, progress: 1)
        #expect(abs(dark.offsetY - 32.4) < 1e-9 && abs(dark.blur - 16.2) < 1e-9 && abs(dark.opacity - 0.675) < 1e-9)
        #expect(abs(DetailCoverShadow(coverSide: 444, opacity: 0.25, progress: 1).opacity - 0.25) < 1e-9)
        let half = DetailCoverShadow(coverSide: 222, opacity: 0.675, progress: 0.5)
        #expect(abs(half.offsetY - 8.1) < 1e-9 && abs(half.blur - 8.1) < 1e-9 && abs(half.opacity - 0.3375) < 1e-9)
        #expect(DetailCoverShadow(coverSide: 444, opacity: 0.675, progress: 0).opacity == 0)
    }
}

/// 深色板只從下緣露出：下緣下方明顯變暗，上方與左右（距邊緣超過模糊半徑＋5 pt）不變
@MainActor
struct DetailCoverShadowRenderTests {
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

    @Test func slabShowsOnlyBelowTheCover() throws {
        let frame = CGRect(x: 100, y: 60, width: 200, height: 200)
        let shadow = DetailCoverShadow(coverSide: frame.width, opacity: 0.45, progress: 1)
        let scene = ZStack(alignment: .topLeading) {
            Color.white
            DetailCoverShadowView(frame: frame, opacity: 0.45, progress: 1)
            Color.white.frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)   // 封面本身蓋住上半
        }
        let size = CGSize(width: 400, height: 400)
        let background = try #require(luminance(scene, size: size, at: CGPoint(x: 5, y: 395)))
        let below = try #require(luminance(scene, size: size, at: CGPoint(x: frame.midX, y: frame.maxY + 10)))
        #expect(below < background * 0.85, "下緣下方 10 pt 應暗 ≥ 15%：\(below) vs \(background)")
        let margin = shadow.blur + 5
        let above = try #require(luminance(scene, size: size, at: CGPoint(x: frame.midX, y: frame.minY - margin)))
        let left = try #require(luminance(scene, size: size, at: CGPoint(x: frame.minX - margin, y: frame.midY)))
        let right = try #require(luminance(scene, size: size, at: CGPoint(x: frame.maxX + margin, y: frame.midY)))
        for value in [above, left, right] { #expect(abs(value - background) < background * 0.03, "\(value) vs \(background)") }
    }
}
