import CoreGraphics
import Foundation
import RemoteProtocol
import Testing
import UIKit

@testable import YogSothothsEcho

// S6 T8（sprint-6-detail.md §4.5、§4.7、§4.9）：開合的協調——時鐘推進轉場、清單何時出現、關閉後回焦、封面先 spine 後 detail、斷線重設

@MainActor
final class ControllerClock {
    var now = 0.0
}

/// 每次 sleep 都推進手動時鐘一格（1/60 s），讓 ticker 在測試裡確定地跑完
actor TickGate {
    func sleep() async { await Task.yield() }
}

@MainActor
struct AlbumOpenControllerTests {
    let clock = ControllerClock()
    let m = SpineCarouselTests.pro13
    let album = AlbumSummary(id: "00000000000000aa", title: "Made-up", artist: "Someone", trackCount: 3, artworkToken: "00000000000000bb")
    let other = AlbumSummary(id: "00000000000000cc", title: "Other", artist: "Someone", trackCount: 1, artworkToken: nil)

    static let spine = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
    static let detail = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }

    func controller(detail: @escaping AlbumOpenController.Cover = { _ in AlbumOpenControllerTests.detail }) -> AlbumOpenController {
        let clock = clock
        return AlbumOpenController(now: { clock.now }, sleep: { _ in await Task.yield() },
                                   spineCover: { _ in Self.spine }, detailCover: detail)
    }

    func run(_ c: AlbumOpenController, seconds: Double) async {
        let end = clock.now + seconds
        while clock.now < end {
            clock.now += 1.0 / 60
            for _ in 0..<5 { await Task.yield() }
        }
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func openRunsToOpenAndShowsRows() async {
        let c = controller()
        var opened: [String] = []
        c.onOpen = { opened.append($0.id) }
        c.open(album, from: SpineCarousel.pose(u: 1, metrics: m), metrics: m, origin: CGPoint(x: 0, y: 80))
        #expect(c.album == album && c.transition.phase == .opening(album.id) && opened == [album.id])
        #expect(!c.transition.tracksTappable && c.browseOrigin == CGPoint(x: 0, y: 80))
        // 0.20 清場＋0.40 飛行＋文字浮現（3 首＋總長＝4 項 → 1.04 s）
        #expect(c.transition.revealEnd == DetailRevealSchedule(itemCount: 4).end)
        await run(c, seconds: 2)
        #expect(c.transition.phase == .open(album.id) && c.transition.tracksTappable)
    }

    /// 方向快照：被點那張左邊的往左、右邊的往右；被點那張先留在側封，飛起來才交給舞台
    @Test func openKeepsTheOutwardSnapshotAndHandsOverWhenFlying() async {
        let c = controller()
        c.open(album, from: SpineCarousel.pose(u: -1, metrics: m), metrics: m, origin: .zero, outward: ["l": -1, "r": 1])
        #expect(c.outward == ["l": -1, "r": 1])
        #expect(c.owner(c.channels()) == .browser)
        await run(c, seconds: 0.35)
        #expect(c.owner(c.channels()) == .stage)
        await run(c, seconds: 0.4)
        #expect(c.owner(c.channels()) == .detail)
        c.reset()
        #expect(c.outward.isEmpty)
    }

    @Test func closeHidesRowsThenReturnsToBrowsingAndRequestsFocus() async {
        let c = controller()
        var closed = 0
        c.onClosed = { closed += 1 }
        c.open(album, from: SpineCarousel.pose(u: 0, metrics: m), metrics: m, origin: .zero)
        await run(c, seconds: 2)
        c.close()
        #expect(!c.transition.tracksTappable && c.transition.phase == .closing(album.id))
        await run(c, seconds: 1.5)
        #expect(c.transition.phase == .browsing && c.album == nil && closed == 1)
        #expect(c.focusRequest == album.id)
        c.consumeFocusRequest()
        #expect(c.focusRequest == nil)
    }

    @Test func secondOpenWhileBusyIsIgnored() async {
        let c = controller()
        c.open(album, from: SpineCarousel.pose(u: 0, metrics: m), metrics: m, origin: .zero)
        c.open(other, from: SpineCarousel.pose(u: 1, metrics: m), metrics: m, origin: .zero)
        #expect(c.album == album)
    }

    /// 封面：先 spine，detail（.opened）到了換上；關閉後晚到的不套用
    @Test func coverUpgradesFromSpineToDetail() async {
        let c = controller()
        c.open(album, from: SpineCarousel.pose(u: 0, metrics: m), metrics: m, origin: .zero)
        await run(c, seconds: 0.1)
        #expect(c.cover === Self.detail)
    }

    @Test func lateDetailAfterCloseIsDropped() async {
        let gate = AsyncStream<Void>.makeStream()
        let c = controller(detail: { _ in
            for await _ in gate.stream { break }
            return AlbumOpenControllerTests.detail
        })
        c.open(album, from: SpineCarousel.pose(u: 0, metrics: m), metrics: m, origin: .zero)
        await run(c, seconds: 0.05)
        #expect(c.cover === Self.spine)
        c.reset()
        gate.continuation.yield()
        await run(c, seconds: 0.05)
        #expect(c.cover == nil && c.album == nil)
    }

    /// 斷線（殼層換成連線畫面）：立即回 browsing、通知關閉
    @Test func resetReturnsToBrowsing() async {
        let c = controller()
        var closed = 0
        c.onClosed = { closed += 1 }
        c.open(album, from: SpineCarousel.pose(u: 0, metrics: m), metrics: m, origin: .zero)
        await run(c, seconds: 0.2)
        c.reset()
        #expect(c.transition.phase == .browsing && c.album == nil && !c.transition.tracksTappable && closed == 1)
        await run(c, seconds: 1)
        #expect(c.transition.phase == .browsing)
    }

    /// 開唱機時凍結：時間走了進度不動；恢復後續跑
    @Test func freezeHoldsTheTransition() async {
        let c = controller()
        c.open(album, from: SpineCarousel.pose(u: 0, metrics: m), metrics: m, origin: .zero)
        await run(c, seconds: 0.2)
        c.freeze()
        let held = c.channels()
        await run(c, seconds: 2)
        #expect(c.channels() == held && c.transition.phase == .opening(album.id))
        c.resume()
        await run(c, seconds: 2)
        #expect(c.transition.phase == .open(album.id))
    }

    /// 曲目載入後以實際項目數更新結束時刻：已走完而延後時要重新逐幀推進
    @Test func revealEndUpdateRestartsTheTicker() async {
        let c = controller()
        c.open(album, from: SpineCarousel.pose(u: 0, metrics: m), metrics: m, origin: .zero)
        await run(c, seconds: 2)
        #expect(!c.isAnimating)
        c.updateRevealEnd(c.transition.revealEnd + 0.5)
        #expect(c.isAnimating)
        await run(c, seconds: 1)
        #expect(!c.isAnimating)
    }
}
