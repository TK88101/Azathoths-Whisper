import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// H-02 UI 測試閘門的固定資料（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.2–3.3）。
//
// fixture 是閘門結論的一部分：色板若分不開、ID 若解析錯、幾何常數若與產品漂移，
// UITest 的紅燈就不再指向產品。這些前提在這裡用單元測試釘住，而不是留給 UITest 事後才暴露。
@Suite("CoverFlowUITestFixture")
struct CoverFlowUITestFixtureTests {
    private typealias Fixture = CoverFlowUITestFixture

    // MARK: ID

    @Test func idsAreZeroPaddedAndRoundTrip() {
        #expect(Fixture.persistentID(at: 0) == "T00")
        #expect(Fixture.persistentID(at: 19) == "T19")
        for index in 0..<Fixture.trackCount {
            #expect(Fixture.index(of: Fixture.persistentID(at: index)) == index)
        }
    }

    @Test func foreignOrOutOfRangeIDsDoNotParse() {
        for id in ["", "T", "T20", "T-1", "X05", "T5", "T005", "t05", " T05"] {
            #expect(Fixture.index(of: id) == nil, "「\(id)」不得被當成 fixture ID")
        }
    }

    /// 起點必須在中段：兩側都有鄰張，C2 才能兩側都驗
    @Test func playingIndexIsInteriorSoBothNeighboursExist() {
        #expect(Fixture.playingIndex > 0)
        #expect(Fixture.playingIndex < Fixture.trackCount - 1)
    }

    // MARK: 色板

    /// 閘門只在「中心卡 vs 鄰張 vs 背景」之間分類，所以只要求這三者兩兩分得開；
    /// 不相鄰的兩張可以相近（實測最小 0.18），那不影響判定。
    @Test func paletteSeparatesEveryCardFromItsNeighboursAndBackground() {
        let black = GateRGB(red: 0, green: 0, blue: 0)
        for index in 0..<Fixture.trackCount {
            let color = Fixture.color(at: index)
            #expect(CoverFlowGateLogic.distance(color, black) >= 0.9)
            for step in 1...2 where index + step < Fixture.trackCount {
                let other = Fixture.color(at: index + step)
                #expect(
                    CoverFlowGateLogic.distance(color, other) >= 0.9,
                    "T\(index) 與 T\(index + step) 色距不足，交疊區會分不出誰在上層"
                )
            }
        }
    }

    @Test func paletteComponentsAreInUnitRange() {
        for index in 0..<Fixture.trackCount {
            let color = Fixture.color(at: index)
            for component in [color.red, color.green, color.blue] {
                #expect((0...1).contains(component))
            }
        }
    }

    // MARK: 旗標

    @Test func flagIsOnlyEnabledByExactOne() {
        #expect(Fixture.isEnabled(in: [Fixture.launchFlag: "1"]))
        for value in ["0", "", "true", "YES", " 1"] {
            #expect(!Fixture.isEnabled(in: [Fixture.launchFlag: value]))
        }
        #expect(!Fixture.isEnabled(in: [:]))
    }

    @Test func albumDelayDefaultsAndAcceptsOnlyNonNegativeIntegers() {
        let key = Fixture.albumDelayVariable
        #expect(Fixture.albumDelayMilliseconds(in: [:]) == Fixture.defaultAlbumDelayMilliseconds)
        #expect(Fixture.albumDelayMilliseconds(in: [key: "0"]) == 0)
        #expect(Fixture.albumDelayMilliseconds(in: [key: "250"]) == 250)
        for bad in ["-5", "abc", "", "1.5"] {
            #expect(Fixture.albumDelayMilliseconds(in: [key: bad]) == Fixture.defaultAlbumDelayMilliseconds)
        }
    }

    // MARK: 幾何必須與產品同源

    /// UITests 不能 `@testable import` 產品模組，只能用 fixture 裡的鏡像常數算 stride；
    /// 產品一改卡片尺寸或覆疊比例，這條就轉紅，而不是讓 UITest 把錯位誤判成 `C1-OFFSET`。
    @Test func geometryMirrorsTheProductView() {
        #expect(Fixture.itemWidth == CoverFlowView.itemWidth)
        let productStride = CoverFlowView.itemWidth
            + CoverFlowGeometry(itemWidth: CoverFlowView.itemWidth).spacing
        #expect(abs(Fixture.stride - productStride) < 1e-9)
    }
}
