import Foundation

/// 條帶觀察的輸入。卡 ID 序列與平移指令併成一個值：兩者常在同一次更新一起變，順序由條帶決定
struct CoverFlowStripInput<ID: Hashable>: Equatable {
    let ids: [ID]
    let slide: CoverFlowSlideRequest?
}

/// 條帶對輸入變動的反應（`docs/plans/2026-09-26-coverflow-follow-playback-slide.md` §3.4）。
/// 純函式；條帶只負責執行
enum CoverFlowStripReaction: Equatable {
    case none
    /// 無動畫捲回正中那張（現行的牌組變動路徑）
    case recenter
    /// 條帶出現時就帶著還沒釋放的指令（被重建）：不滑，當場釋放並回報落定
    case settleAtOnce(generation: Int)
    /// 捲回正中、再把內容位移帶動畫歸零
    case slide(generation: Int)

    static func resolve<ID: Hashable>(from old: CoverFlowStripInput<ID>, to new: CoverFlowStripInput<ID>,
                                      releasedGeneration: Int) -> CoverFlowStripReaction {
        if let request = new.slide, request.generation != releasedGeneration {
            // `onChange(initial: true)` 的初值呼叫新舊相同。已釋放的指令不會走到這裡：
            // 條帶只是重新出現時 `@State` 還在，動畫照常由自己落定
            return old == new ? .settleAtOnce(generation: request.generation) : .slide(generation: request.generation)
        }
        return new.ids != old.ids ? .recenter : .none
    }

    /// 內容此刻要往回推幾個卡距：指令還沒釋放才推
    static func pendingSlots(_ slide: CoverFlowSlideRequest?, releasedGeneration: Int) -> Int {
        guard let slide, slide.generation != releasedGeneration else { return 0 }
        return slide.slots
    }
}
