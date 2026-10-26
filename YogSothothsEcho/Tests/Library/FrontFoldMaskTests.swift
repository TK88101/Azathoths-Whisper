import CoreGraphics
import RemoteProtocol
import SwiftUI
import Testing

@testable import YogSothothsEcho

// G2 接縫 spike（s6-61-g-perf-wear.md 附錄 C）：正面折邊兩角挖掉與書脊同一組缺口，非折邊兩角保持方正
struct FrontFoldMaskTests {
    static let cover: CGFloat = SpineCarouselMetrics.referenceCover
    static let thickness = cover * SpineCarouselMetrics.spineToCover
    static let rect = CGRect(x: 0, y: 0, width: cover, height: cover)

    static func mask(_ id: String, _ side: CarouselSide) -> Path {
        FrontFoldMask(albumID: id, thickness: thickness, side: side).path(in: rect)
    }

    static func inside(_ path: Path, _ point: CGPoint) -> Bool { path.contains(point) }

    @Test(arguments: SpineBakeTests.fixtures.map(\.id), [CarouselSide.left, .right])
    func foldCornersAreCutOthersKept(id: String, side: CarouselSide) {
        let path = Self.mask(id, side)
        let foldX: CGFloat = side == .left ? 0.3 : Self.cover - 0.3
        let farX: CGFloat = side == .left ? Self.cover - 0.3 : 0.3
        #expect(!Self.inside(path, CGPoint(x: foldX, y: 0.3)), "\(id) \(side) 折邊上角")
        #expect(!Self.inside(path, CGPoint(x: foldX, y: Self.cover - 0.3)), "\(id) \(side) 折邊下角")
        #expect(Self.inside(path, CGPoint(x: farX, y: 0.3)), "\(id) \(side) 非折邊上角保留")
        #expect(Self.inside(path, CGPoint(x: farX, y: Self.cover - 0.3)))
        #expect(Self.inside(path, CGPoint(x: Self.cover / 2, y: Self.cover / 2)))
        #expect(Self.inside(path, CGPoint(x: foldX, y: Self.cover / 2)), "折邊中段不動")
    }

    /// 同一缺口：正面挖掉的範圍＝書脊烘焙的折邊角缺口延伸（左側盒正面 x＝書脊 x − w）
    @Test func cutIsTheSpineChipContinued() {
        let chips = SpineBakeOutline.cornerChips(albumID: "wear-0", shape: SpineWear.shape(albumID: "wear-0"),
                                                 size: CGSize(width: Self.thickness, height: Self.cover))
        let foldTop = chips[1]
        let path = Self.mask("wear-0", .left)
        for dx in stride(from: CGFloat(0.5), to: 6, by: 0.5) {
            let spinePoint = CGPoint(x: Self.thickness + dx, y: 0.5)
            #expect(foldTop.contains(spinePoint) == !Self.inside(path, CGPoint(x: dx, y: 0.5)), "dx \(dx)")
        }
    }

    /// 右側盒是左側的鏡像
    /// 上下緣在折邊處與書脊端面等高（書脊在折邊的內縮＝正面在折邊的內縮），往內收回到 0
    @Test func edgeContinuesSpineEndAtTheFold() {
        let shape = SpineWear.shape(albumID: "wear-1"), u: CGFloat = 1
        let p = SpineBakeOutline.profile(shape, u: u)
        let spineInset = SpineBakeOutline.endInset(p, end: 0, x: Self.thickness, width: Self.thickness, seed: SpineWear.seed(albumID: "wear-1"))
        let path = Self.mask("wear-1", .left)
        let radius = p.cornerRadius * 1.4 + 1
        // 缺口外、折邊附近：內縮以上被挖、以下保留
        let x = radius + 0.5
        let reach = FrontFoldMask.taperFactor * p.ends[0] + p.cornerRadius
        if x < reach {
            let t = 1 - x / reach
            let expected = SpineBakeOutline.endInset(p, end: 0, x: Self.thickness + x, width: Self.thickness, seed: SpineWear.seed(albumID: "wear-1")) * t * t
            #expect(!Self.inside(path, CGPoint(x: x, y: max(0.05, expected - 0.3))))
            #expect(Self.inside(path, CGPoint(x: x, y: expected + 0.3)))
        }
        #expect(spineInset > 0)
        // 收回距離之外＝原本的上緣
        #expect(Self.inside(path, CGPoint(x: reach + 2, y: 0.2)))
    }

    @Test func rightIsMirrorOfLeft() {
        let left = Self.mask("wear-2", .left), right = Self.mask("wear-2", .right)
        for x in stride(from: CGFloat(0.5), to: 8, by: 1) {
            for y in stride(from: CGFloat(0.5), to: 8, by: 1) {
                #expect(Self.inside(left, CGPoint(x: x, y: y)) == Self.inside(right, CGPoint(x: Self.cover - x, y: y)))
            }
        }
    }
}

// CoverFace 套上遮罩：折邊角像素透明、非折邊角不透明
@MainActor
struct CoverFaceFoldRenderTests {
    @Test(arguments: [CarouselSide.left, .right])
    func coverFoldCornerIsTransparent(side: CarouselSide) throws {
        FaceTextureCache.shared.rendersSynchronously = true
        let album = AlbumSummary(id: "wear-2", title: "T", artist: "A", trackCount: 1, artworkToken: nil)
        let renderer = ImageRenderer(content: CoverFace(album: album, image: nil, length: 400, side: side).frame(width: 400, height: 400))
        renderer.scale = 2
        let p = SpineBakeTests.pixels(try #require(renderer.cgImage))
        let fold = side == .left ? 0 : p.width - 1, far = side == .left ? p.width - 1 : 0
        #expect(p.alpha(fold, 0) < 255 && p.alpha(fold, p.height - 1) < 255, "\(side) 折邊角")
        #expect(p.alpha(far, 0) == 255 && p.alpha(far, p.height - 1) == 255, "\(side) 非折邊角")
    }
}
