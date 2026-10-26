import CoreGraphics
import RemoteProtocol
import SwiftUI
import Testing
import UIKit

@testable import YogSothothsEcho

// F2 Render（s6-61-round2.md §4 P1 ④）：固定 fixture 專輯、純灰封面、cover 400 pt、scale 2，取固定點比色
@MainActor
struct SpineSurfaceRenderTests {
    /// 紋理點陣平常在背景畫（FaceTexture）；ImageRenderer 不等非同步，這裡改當場同步畫
    init() { FaceTextureCache.shared.rendersSynchronously = true }

    /// 以 fixtureSearch() 首跑找出、寫死（左上角磨損大、正面有缺口、書脊上端磨損夠深）；之後不再搜尋
    static let fixtureID = "fixture-0"
    static let pulp = (0xEB, 0xE5, 0xD6)
    static let gray = 0x80

    static func fixtureQualifies(_ id: String) -> Bool {
        let s = SpineWear.shape(albumID: id)
        return s.corners[0] * s.age >= 1.0 && s.spineEnds[0] * s.age >= 1.0
            && s.frontNicks.contains { $0.radius * s.age >= 3 }
    }

    /// 首跑用：印出第一個合格的 ID（之後寫進 fixtureID）
    @Test func fixtureIsQualified() {
        let found = (0..<10_000).map { "fixture-\($0)" }.first(where: Self.fixtureQualifies)
        #expect(Self.fixtureQualifies(Self.fixtureID), "首個合格：\(found ?? "無")")
    }

    static func grayImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }

    static func pixels(_ view: some View, size: CGSize) -> (data: [UInt8], width: Int)? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width)
    }

    static func sample(_ p: (data: [UInt8], width: Int), at point: CGPoint) -> (Int, Int, Int) {
        let i = (Int(point.y * 2) * p.width + Int(point.x * 2)) * 4
        return (Int(p.data[i]), Int(p.data[i + 1]), Int(p.data[i + 2]))
    }

    static func near(_ a: (Int, Int, Int), _ b: (Int, Int, Int), tolerance: Int = 40) -> Bool {
        abs(a.0 - b.0) <= tolerance && abs(a.1 - b.1) <= tolerance && abs(a.2 - b.2) <= tolerance
    }

    var album: AlbumSummary { AlbumSummary(id: Self.fixtureID, title: "Fixture", artist: "Artist", trackCount: 10, artworkToken: nil) }

    /// 用右側盒：左上角不是折邊角（G2 接縫起，折邊兩角挖掉與書脊同一組缺口，見 FrontFoldMaskTests）
    @Test func frontShowsWearAtCornerAndNickButNotCenter() throws {
        let size = CGSize(width: 400, height: 400)
        let shot = try #require(Self.pixels(CoverFace(album: album, image: Self.grayImage(), length: 400, side: .right), size: size))
        #expect(Self.near(Self.sample(shot, at: CGPoint(x: 1, y: 1)), Self.pulp), "左上角 \(Self.sample(shot, at: CGPoint(x: 1, y: 1)))")
        let shape = SpineWear.shape(albumID: Self.fixtureID)
        let nick = try #require(shape.frontNicks.max { $0.radius < $1.radius })
        let c = SpineWear.nickCenter(nick, size: size)
        let inside = CGPoint(x: min(max(c.x, 1), 399), y: min(max(c.y, 1), 399))
        #expect(Self.near(Self.sample(shot, at: inside), Self.pulp), "缺口 \(Self.sample(shot, at: inside))")
        #expect(Self.near(Self.sample(shot, at: CGPoint(x: 200, y: 200)), (Self.gray, Self.gray, Self.gray)), "中心 \(Self.sample(shot, at: CGPoint(x: 200, y: 200)))")
    }

    /// g 版（s6-61-g-perf-wear.md §5.1）：書脊上端不再是紙漿色實心塊（使用者：像灰色塊貼上），而是不規則剪影＋泛白——
    /// 上端中央最外一列透明或明顯泛白，往內 40 pt 才回到封面灰
    @Test func spineShowsWearAtTopEnd() throws {
        SpineBakeCache.shared.rendersSynchronously = true
        defer { SpineBakeCache.shared.rendersSynchronously = false }
        let thickness: CGFloat = 400 * SpineCarouselMetrics.spineToCover
        let view = ZStack { Color.black; SpineFace(album: album, image: Self.grayImage(), cover: 400, thickness: thickness, side: .left) }
        let shot = try #require(Self.pixels(view, size: CGSize(width: thickness, height: 400)))
        let top = Self.sample(shot, at: CGPoint(x: thickness / 2, y: 0))
        let inner = Self.sample(shot, at: CGPoint(x: thickness / 2, y: 40))
        #expect(top.0 < 20 || top.0 > inner.0 + 25, "書脊上端 \(top) vs 內側 \(inner)")
    }

    /// 磨損裁在面內：正面外側一圈不畫東西（不溢到鄰盒）
    @Test func wearIsClippedToFace() throws {
        let canvas = CGSize(width: 440, height: 440)
        let view = ZStack { Color.black; CoverFace(album: album, image: Self.grayImage(), length: 400, side: .left).frame(width: 400, height: 400) }
        let shot = try #require(Self.pixels(view, size: canvas))
        for p in [CGPoint(x: 19, y: 19), CGPoint(x: 220, y: 19), CGPoint(x: 19, y: 220), CGPoint(x: 421, y: 421)] {
            let s = Self.sample(shot, at: p)
            #expect(s.0 < 8 && s.1 < 8 && s.2 < 8, "面外 \(p) \(s)")
        }
    }
}
