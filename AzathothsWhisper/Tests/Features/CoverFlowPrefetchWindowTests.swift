import Foundation
import Testing

@testable import AzathothsWhisper

// 預取視窗（M7 P2-2）：純函數，決定「中心兩側先取誰」。
@Suite("CoverFlowPrefetchWindow")
struct CoverFlowPrefetchWindowTests {
    private func items(_ count: Int) -> [AlbumTrack] {
        (0..<count).map { .fixture(id: "T\($0)", title: "T\($0)", track: $0 + 1) }
    }

    /// 由近而遠展開，且**移動方向那一側先**——使用者往哪滑，那一側就是他即將看到的
    @Test func ordersByDistanceWithMovingSideFirst() {
        let ids = CoverFlowPrefetchWindow.ids(items: items(9), centerIndex: 4, direction: 1, limit: 2)
        #expect(ids == ["T5", "T3", "T6", "T2"])

        let backwards = CoverFlowPrefetchWindow.ids(items: items(9), centerIndex: 4, direction: -1, limit: 2)
        #expect(backwards == ["T3", "T5", "T2", "T6"])
    }

    /// 中心由 View 的 explicit 請求取，重複排入只會佔掉單槽的位置
    @Test func excludesCenter() {
        let ids = CoverFlowPrefetchWindow.ids(items: items(5), centerIndex: 2)
        #expect(!ids.contains("T2"))
    }

    @Test func clampsAtBothEnds() {
        let head = CoverFlowPrefetchWindow.ids(items: items(4), centerIndex: 0, limit: 5)
        #expect(head == ["T1", "T2", "T3"], "頭部只有右側可取")

        let tail = CoverFlowPrefetchWindow.ids(items: items(4), centerIndex: 3, direction: -1, limit: 5)
        #expect(tail == ["T2", "T1", "T0"], "尾部只有左側可取")
    }

    @Test func emptyWhenSingleItem() {
        #expect(CoverFlowPrefetchWindow.ids(items: items(1), centerIndex: 0).isEmpty)
    }

    @Test func emptyForInvalidCenterOrLimit() {
        #expect(CoverFlowPrefetchWindow.ids(items: items(3), centerIndex: 7).isEmpty)
        #expect(CoverFlowPrefetchWindow.ids(items: [], centerIndex: 0).isEmpty)
        #expect(CoverFlowPrefetchWindow.ids(items: items(3), centerIndex: 1, limit: 0).isEmpty)
    }

    /// 上限不得超出實際項數（重複 ID 會讓同一張圖排兩次）
    @Test func doesNotRepeatIDs() {
        let ids = CoverFlowPrefetchWindow.ids(items: items(6), centerIndex: 2, limit: 5)
        #expect(Set(ids).count == ids.count)
        #expect(ids.count == 5)
    }
}
