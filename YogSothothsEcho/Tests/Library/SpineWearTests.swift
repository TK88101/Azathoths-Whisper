import CoreGraphics
import CryptoKit
import SwiftUI
import Testing

@testable import YogSothothsEcho

// F2 ④磨損 中、每張不同（s6-61-round2.md §4 P1）：形狀依專輯 ID 穩定；向量路徑；快取
@MainActor
struct SpineWearTests {
    @Test func shapeIsStablePerAlbumAndDiffersAcrossAlbums() {
        #expect(SpineWear.shape(albumID: "74b8dcb8fb449734") == SpineWear.shape(albumID: "74b8dcb8fb449734"))
        #expect(SpineWear.shape(albumID: "74b8dcb8fb449734") != SpineWear.shape(albumID: "0000000000000001"))
    }

    @Test func fieldsStayInRange() {
        for i in 0..<500 {
            let s = SpineWear.shape(albumID: String(format: "%016llx", UInt64(i) &* 2_654_435_761))
            #expect((0.6...1.3).contains(s.age))
            #expect(s.corners.count == 4 && s.corners.allSatisfy { (0.15...0.35).contains($0) || (0.5...1.5).contains($0) })
            #expect(s.edges.count == 4 && s.edges.allSatisfy { (0.35...1.45).contains($0) })
            #expect(s.spineEnds.count == 2 && s.spineEnds.allSatisfy { (0.3...1.6).contains($0) })
            #expect((0.35...1.45).contains(s.spineFoldRub))
            #expect((0...3).contains(s.frontNicks.count) && (0...2).contains(s.spineNicks.count))
            #expect((s.frontNicks + s.spineNicks).allSatisfy { (0.1...0.9).contains($0.position) && (1.5...5).contains($0.radius) })
        }
    }

    /// 約 1/5 的角幾乎完好
    @Test func aboutAFifthOfCornersAreNearlyIntact() {
        var intact = 0, total = 0
        for i in 0..<10_000 {
            let s = SpineWear.shape(albumID: "album-\(i)")
            intact += s.corners.filter { $0 <= 0.35 }.count
            total += 4
        }
        let ratio = Double(intact) / Double(total)
        #expect(abs(ratio - 0.22) <= 0.02, "近完好比例 \(ratio)")
    }

    @Test func coreContainsEveryNickCenter() {
        let size = CGSize(width: 764, height: 764)
        for i in 0..<50 {
            let id = "album-\(i)"
            let shape = SpineWear.shape(albumID: id)
            let core = SpineWear.paths(albumID: id, shape: shape, surface: .front, size: size).core
            for nick in shape.frontNicks {
                let center = SpineWear.nickCenter(nick, size: size)
                // 圓心可能正好在面的邊上：往內移 0.5 pt 再測
                let inside = CGPoint(x: min(max(center.x, 0.5), size.width - 0.5), y: min(max(center.y, 0.5), size.height - 0.5))
                #expect(core.contains(inside), "\(id) 缺口 \(nick)")
            }
        }
    }

    /// golden：演算法變了就紅（更新前須經使用者看圖同意）
    @Test func frontCoreGolden() {
        let id = SpineSurfaceRenderTests.fixtureID
        let core = SpineWear.paths(albumID: id, shape: SpineWear.shape(albumID: id), surface: .front, size: CGSize(width: 764, height: 764)).core
        // 以量化到 1/1000 pt 的座標雜湊（不用 Path.description：字串格式非穩定 API，SDK 升級可能假紅）
        var coordinates: [Int64] = []
        core.forEach { element in
            let points: [CGPoint] = switch element {
            case .move(let p), .line(let p): [p]
            case .quadCurve(let p, let c): [p, c]
            case .curve(let p, let c1, let c2): [p, c1, c2]
            case .closeSubpath: []
            }
            coordinates += points.flatMap { [Int64(($0.x * 1000).rounded()), Int64(($0.y * 1000).rounded())] }
        }
        let bytes = coordinates.withUnsafeBytes { Data($0) }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(String(digest.prefix(16)) == Self.goldenFrontCore, "實際 \(digest.prefix(16))")
    }
    static let goldenFrontCore = "fb3290b551c71b28"

    @Test func cacheHitsRebuildsAndEvicts() {
        let cache = SpineWearCache(capacity: 3)
        let a = cache.paths(albumID: "a", surface: .front, size: CGSize(width: 100, height: 100))
        #expect(cache.paths(albumID: "a", surface: .front, size: CGSize(width: 100.2, height: 100)) == a)   // 取到 0.5 pt＝同鍵
        #expect(cache.buildCount == 1)
        _ = cache.paths(albumID: "a", surface: .front, size: CGSize(width: 200, height: 200))
        #expect(cache.buildCount == 2)
        _ = cache.paths(albumID: "b", surface: .front, size: CGSize(width: 100, height: 100))
        _ = cache.paths(albumID: "a", surface: .front, size: CGSize(width: 100, height: 100))   // 觸碰 a，使 a@200 成最久未用
        _ = cache.paths(albumID: "c", surface: .spine, size: CGSize(width: 10, height: 100))   // 第 4 個鍵 → 淘汰 a@200
        #expect(cache.count == 3 && cache.buildCount == 4)
        _ = cache.paths(albumID: "a", surface: .front, size: CGSize(width: 200, height: 200))
        #expect(cache.buildCount == 5)
    }

    /// 路徑規模上限（確定性，不靠時鐘）：冷快取 13 張 × 2 面的生成成本與點數成正比。
    /// 預算 8 ms 指最佳化建置：Mac -O 實測 26 條 2.9–3.4 ms、正面最多 8,129／書脊 1,950 個元素（2026-10-22）；上限留約 25%；實機以 N-03 閘門量
    @Test func pathSizeBound() {
        func elements(_ path: Path) -> Int {
            var n = 0
            path.forEach { _ in n += 1 }
            return n
        }
        var front = 0, spine = 0
        for i in 0..<13 {
            let shape = SpineWear.shape(albumID: "budget-\(i)")
            let f = SpineWear.paths(albumID: "budget-\(i)", shape: shape, surface: .front, size: CGSize(width: 764, height: 764))
            let s = SpineWear.paths(albumID: "budget-\(i)", shape: shape, surface: .spine, size: CGSize(width: 22.92, height: 764))
            front = max(front, elements(f.core) + elements(f.halo) + elements(f.flecks))
            spine = max(spine, elements(s.core) + elements(s.halo) + elements(s.flecks))
        }
        #expect(front <= Self.frontElementBound && spine <= Self.spineElementBound, "正面最多 \(front)、書脊最多 \(spine)")
    }
    static let frontElementBound = 10_000
    static let spineElementBound = 2_500
}
