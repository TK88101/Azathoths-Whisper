import CoreGraphics
import Testing
import UIKit

@testable import YogSothothsEcho

// S6 #6-1 g 版 T0／T2（s6-61-g-perf-wear.md §5.1）：書脊整面烘焙——不規則 alpha 輪廓、泛白磨損、鍵＝全部像素輸入
struct SpineBakeTests {
    /// 13 吋：A＝764、書脊厚＝A × spineToCover；scale 2
    static let cover: CGFloat = SpineCarouselMetrics.referenceCover
    static let thickness: CGFloat = SpineCarouselMetrics.referenceCover * SpineCarouselMetrics.spineToCover
    static let scale: CGFloat = 2

    /// 以 gradeFixturesAreStable 首跑找出、寫死（各級 2 個）；之後不再搜尋
    static let fixtures: [(id: String, grade: SpineWear.Grade)] = [
        ("wear-3", .new), ("wear-4", .new), ("wear-0", .normal), ("wear-1", .normal), ("wear-2", .heavy), ("wear-13", .heavy),
    ]

    static func input(_ id: String, title: String = "Seen Through The Veils", artist: String = "Gehenna",
                      side: CarouselSide = .left, strip: CGImage? = nil, dark: Bool = true) -> SpineBake.Input {
        let key = SpineBake.Key(albumID: id, title: title, artist: artist, source: strip == nil ? .placeholder : .artwork(token: "t", pixelWidth: strip?.width ?? 0),
                                side: side, thickness: thickness, cover: cover, scale: scale)
        let base = dark ? RGBColor(r: 0.12, g: 0.12, b: 0.14) : RGBColor(r: 0.85, g: 0.85, b: 0.85)
        return SpineBake.Input(key: key, cover: strip, placeholder: base)
    }

    struct Pixels {
        let data: [UInt8], width: Int, height: Int
        func alpha(_ x: Int, _ y: Int) -> Int { Int(data[(y * width + x) * 4 + 3]) }
        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }
    }

    static func pixels(_ image: CGImage) -> Pixels {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(data: data, width: width, height: height)
    }

    // MARK: 等級與 fixture

    @Test func gradeFixturesAreStable() {
        let found = SpineWear.Grade.allCases.map { grade in
            "\(grade): " + (0..<500).map { "wear-\($0)" }.filter { SpineWear.grade(albumID: $0) == grade }.prefix(4).joined(separator: ",")
        }
        for fixture in Self.fixtures {
            #expect(SpineWear.grade(albumID: fixture.id) == fixture.grade, "候選 \(found)")
        }
    }

    @Test func gradeFollowsSpineScore() {
        #expect(SpineWear.grade(score: 0.3) == .new)
        #expect(SpineWear.grade(score: 0.9) == .normal)
        #expect(SpineWear.grade(score: 1.5) == .heavy)
    }

    // MARK: 輸出尺寸與確定性

    @Test func rendersAtDisplayScale() throws {
        let image = try #require(SpineBake.render(Self.input("wear-2")))
        #expect(image.width == Int((Self.thickness * Self.scale).rounded()))
        #expect(image.height == Int((Self.cover * Self.scale).rounded()))
    }

    @Test func sameIDSamePixelsDifferentIDDifferent() throws {
        let a = Self.pixels(try #require(SpineBake.render(Self.input("wear-2"))))
        let b = Self.pixels(try #require(SpineBake.render(Self.input("wear-2"))))
        let c = Self.pixels(try #require(SpineBake.render(Self.input("wear-3"))))
        #expect(a.data == b.data)
        #expect(a.data != c.data)
    }

    // MARK: 剪影

    /// 左右兩側都要有剪影（simcodex R3 P0：右側曾因 save／restore 丟掉裁切而變回直角）
    @Test(arguments: SpineBakeTests.fixtures.map(\.id), [CarouselSide.left, .right])
    func cornersAreNotFullyOpaque(id: String, side: CarouselSide) throws {
        let p = Self.pixels(try #require(SpineBake.render(Self.input(id, side: side))))
        for (x, y) in [(0, 0), (p.width - 1, 0), (0, p.height - 1), (p.width - 1, p.height - 1)] {
            #expect(p.alpha(x, y) < 255, "\(id) \(side) 角 (\(x),\(y))")
        }
    }

    /// 上下端：每欄第一個 alpha > 128 的列＝內縮；要有內縮且沿寬度方向變化 ≥ 3 次
    @Test(arguments: SpineBakeTests.fixtures.map(\.id))
    func endsAreIrregular(id: String) throws {
        let p = Self.pixels(try #require(SpineBake.render(Self.input(id))))
        for top in [true, false] {
            let insets = (0..<p.width).map { x -> Int in
                let rows = top ? Array(0..<p.height) : Array((0..<p.height).reversed())
                return rows.firstIndex { p.alpha(x, $0) > 128 } ?? p.height
            }
            #expect(insets.max()! > 0, "\(id) \(top ? "上" : "下")端無內縮")
            #expect(Self.directionChanges(insets) >= 3, "\(id) \(top ? "上" : "下")端 \(insets)")
        }
    }

    /// 長邊：取 ≥ 16 列，左右各自 alpha 邊界有位移、且 ≤ 2.5 pt × u
    @Test(arguments: SpineBakeTests.fixtures.map(\.id))
    func longEdgesWobbleWithinLimit(id: String) throws {
        let p = Self.pixels(try #require(SpineBake.render(Self.input(id))))
        let limit = Int((2.5 * Self.scale).rounded(.up))
        let rows = stride(from: p.height / 10, to: p.height * 9 / 10, by: p.height / 40).map { $0 }
        #expect(rows.count >= 16)
        for left in [true, false] {
            let insets = rows.map { y -> Int in
                let columns = left ? Array(0..<p.width) : Array((0..<p.width).reversed())
                return columns.firstIndex { p.alpha($0, y) > 128 } ?? p.width
            }
            #expect(Set(insets).count > 1, "\(id) \(left ? "左" : "右")長邊筆直")
            #expect(insets.max()! <= limit, "\(id) \(left ? "左" : "右")長邊內縮過深 \(insets.max()!)")
        }
    }

    /// 深色底上，輪廓 2 pt 內要有暖灰露紙（比底色亮、R ≥ B）
    @Test(arguments: SpineBakeTests.fixtures.map(\.id))
    func whiteningNearOutline(id: String) throws {
        let p = Self.pixels(try #require(SpineBake.render(Self.input(id))))
        let band = Int(2 * Self.scale)
        var found = 0
        for y in stride(from: 0, to: p.height, by: 2) {
            for x in 0..<p.width where x < band || x >= p.width - band || y < band * 4 || y >= p.height - band * 4 {
                guard p.alpha(x, y) > 200 else { continue }
                let (r, g, b) = p.rgb(x, y)
                if r > 90, r >= b, g > 80 { found += 1 }
            }
        }
        #expect(found > 20, "\(id) 泛白像素 \(found)")
    }

    // MARK: 鍵

    @Test func keyCoversTextSourceAndVersion() {
        let base = Self.input("a").key
        #expect(base != Self.input("a", title: "Other").key)
        #expect(base != Self.input("a", artist: "Other").key)
        #expect(base != Self.input("a", side: .right).key)
        #expect(base.rendererVersion == SpineBake.rendererVersion)
        let thumb = SpineBake.Key(albumID: "a", title: "t", artist: "r", source: .artwork(token: "x", pixelWidth: 160), side: .left,
                                  thickness: 20, cover: 700, scale: 2)
        let browse = SpineBake.Key(albumID: "a", title: "t", artist: "r", source: .artwork(token: "x", pixelWidth: 1024), side: .left,
                                   thickness: 20, cover: 700, scale: 2)
        #expect(thumb != browse)
    }

    static func directionChanges(_ values: [Int]) -> Int {
        var changes = 0, last = 0
        for (a, b) in zip(values, values.dropFirst()) where a != b {
            let sign = b > a ? 1 : -1
            if last != 0, sign != last { changes += 1 }
            last = sign
        }
        return changes
    }
}

// 使用者 2026-10-23：磨損程度一律「普通」——實際用的磨損量壓進普通區間，各專輯仍不同
struct SpineBakeWearLevelTests {
    @Test(arguments: SpineBakeTests.fixtures.map(\.id) + (0..<40).map { "level-\($0)" })
    func effectiveScoreStaysNormal(id: String) {
        let score = SpineBakeOutline.effectiveScore(SpineWear.shape(albumID: id))
        #expect(SpineWear.grade(score: score) == .normal, "\(id) \(score)")
    }

    @Test func effectiveScoreKeepsVariety() {
        let scores = Set((0..<40).map { SpineBakeOutline.effectiveScore(SpineWear.shape(albumID: "level-\($0)")) })
        #expect(scores.count > 30)
    }
}
