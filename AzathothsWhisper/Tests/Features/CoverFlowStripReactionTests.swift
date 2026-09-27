import Foundation
import Testing

@testable import AzathothsWhisper

// 條帶對「卡 ID 序列＋平移指令」變動的反應（計劃 docs/plans/2026-09-26-coverflow-follow-playback-slide.md §3.4）。
// 判斷抽成純函式在這裡逐列驗；SwiftUI 的 `onChange(initial:)` 語義與動畫接線由 `CoverFlowSlideGeometryTests` 開視窗驗。
@Suite("CoverFlowStripReaction")
struct CoverFlowStripReactionTests {
    private typealias Input = CoverFlowStripInput<Int>

    private func request(_ generation: Int, slots: Int = 1) -> CoverFlowSlideRequest {
        CoverFlowSlideRequest(generation: generation, slots: slots)
    }

    private func reaction(from old: Input, to new: Input, released: Int) -> CoverFlowStripReaction {
        CoverFlowStripReaction.resolve(from: old, to: new, releasedGeneration: released)
    }

    // MARK: 條帶出現時（初值：新舊相同）

    @Test func appearingWithoutARequestDoesNothing() {
        let input = Input(ids: [1, 2, 3], slide: nil)
        #expect(reaction(from: input, to: input, released: 0) == .none)
    }

    /// 被重建：`@State` 歸零，指令還在 → 不滑，當場落定
    @Test func appearingWithAnUnreleasedRequestSettlesAtOnce() {
        let input = Input(ids: [1, 2, 3], slide: request(7))
        #expect(reaction(from: input, to: input, released: 0) == .settleAtOnce(generation: 7))
    }

    /// 沒被重建、只是重新出現：動畫正在跑，不得提前落定
    @Test func reappearingWithAReleasedRequestDoesNothing() {
        let input = Input(ids: [1, 2, 3], slide: request(7))
        #expect(reaction(from: input, to: input, released: 7) == .none)
    }

    // MARK: 輸入變動

    @Test func aNewRequestSlides() {
        let old = Input(ids: [1, 2, 3], slide: nil)
        #expect(reaction(from: old, to: Input(ids: [1, 2, 3], slide: request(1)), released: 0) == .slide(generation: 1))
    }

    /// 換牌與指令在同一次更新一起到：只滑，不另外做無動畫的捲回
    @Test func aNewRequestArrivingWithNewCardsSlides() {
        let old = Input(ids: [1, 2, 3], slide: request(1))
        #expect(reaction(from: old, to: Input(ids: [2, 3, 4], slide: request(2)), released: 1) == .slide(generation: 2))
    }

    @Test func onlyTheCardsChangingRecentres() {
        let old = Input(ids: [1, 2, 3], slide: nil)
        #expect(reaction(from: old, to: Input(ids: [0, 1, 2, 3], slide: nil), released: 0) == .recenter)
    }

    /// 過渡中牌組又變（履歴追上）：指令已釋放，照現行捲回正中
    @Test func cardsChangingDuringAReleasedSlideRecentre() {
        let old = Input(ids: [1, 2, 3], slide: request(1))
        #expect(reaction(from: old, to: Input(ids: [1, 9, 3], slide: request(1)), released: 1) == .recenter)
    }

    /// 落定：指令清掉、暫留卡收掉
    @Test func theRequestBeingClearedWithNewCardsRecentres() {
        let old = Input(ids: [1, 2, 3], slide: request(1))
        #expect(reaction(from: old, to: Input(ids: [0, 1, 3], slide: nil), released: 1) == .recenter)
    }

    @Test func theRequestBeingClearedAloneDoesNothing() {
        let old = Input(ids: [1, 2, 3], slide: request(1))
        #expect(reaction(from: old, to: Input(ids: [1, 2, 3], slide: nil), released: 1) == .none)
    }

    // MARK: 位移

    @Test func anUnreleasedRequestPushesTheContentBack() {
        #expect(CoverFlowStripReaction.pendingSlots(request(3, slots: -1), releasedGeneration: 2) == -1)
        #expect(CoverFlowStripReaction.pendingSlots(request(3, slots: 1), releasedGeneration: 0) == 1)
    }

    @Test func aReleasedOrAbsentRequestLeavesTheContentInPlace() {
        #expect(CoverFlowStripReaction.pendingSlots(request(3), releasedGeneration: 3) == 0)
        #expect(CoverFlowStripReaction.pendingSlots(nil, releasedGeneration: 0) == 0)
    }
}
