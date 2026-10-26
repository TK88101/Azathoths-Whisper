import CoreGraphics
import SwiftUI
import Testing

@testable import YogSothothsEcho

// F2 ①微圓 1.5（s6-61-round2.md §4 P1）：折邊明暗以「距該邊的 pt」定義，依 u＝cover／764 等比例
struct SpineFoldShadingTests {
    @Test func frontStopsMatchSpec() {
        let stops = SpineFoldShading.front(u: 1)
        let r: CGFloat = 1.5
        #expect(stops == [FoldStop(white: true, opacity: 0.18, distance: 0), FoldStop(white: true, opacity: 0.26, distance: 1.2 * r),
                          FoldStop(white: false, opacity: 0.16, distance: 3.2 * r), FoldStop(white: false, opacity: 0.05, distance: 7 * r),
                          FoldStop(white: false, opacity: 0, distance: 7 * r + 10)])
    }

    @Test func spineStopsMatchSpec() {
        let r: CGFloat = 1.5
        #expect(SpineFoldShading.spineFold(u: 1) == [FoldStop(white: true, opacity: 0.24, distance: 0), FoldStop(white: true, opacity: 0.30, distance: 1.2 * r),
                                                     FoldStop(white: true, opacity: 0.06, distance: 3 * r), FoldStop(white: true, opacity: 0, distance: 3 * r + 3)])
        #expect(SpineFoldShading.spineBack(u: 1) == [FoldStop(white: false, opacity: 0.26, distance: 0), FoldStop(white: false, opacity: 0, distance: 2 + r)])
    }

    /// 等比例：u 加倍，所有 distance 加倍；嚴格遞增；最後一個透明
    @Test func scalesWithCoverAndEndsTransparent() {
        for make in [SpineFoldShading.front, SpineFoldShading.spineFold, SpineFoldShading.spineBack] {
            let one = make(1), two = make(2)
            #expect(zip(one, two).allSatisfy { abs($1.distance - 2 * $0.distance) < 1e-9 && $1.opacity == $0.opacity })
            #expect(zip(one, one.dropFirst()).allSatisfy { $0.distance < $1.distance })
            #expect(one.last?.opacity == 0)
        }
    }

    /// location＝distance／面寬，夾在 0…1（書脊寬 22.92 時正面的 stops 會超出）
    @Test func locationsAreClamped() {
        let locations = SpineFoldShading.locations(SpineFoldShading.front(u: 1), length: 10)
        #expect(locations.first == 0 && locations.allSatisfy { (0...1).contains($0) })
        #expect(locations.last == 1)
        #expect(SpineFoldShading.locations(SpineFoldShading.spineBack(u: 1), length: 22.92) == [0, 3.5 / 22.92])
    }
}
