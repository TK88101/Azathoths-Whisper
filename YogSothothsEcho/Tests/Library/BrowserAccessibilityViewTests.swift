import RemoteProtocol
import Testing
import UIKit

@testable import YogSothothsEcho

// S6 #6-1 g 版 T4（s6-61-g-perf-wear.md §5.4）：無障礙元素按需建立——每幀只收廉價 snapshot，被查詢才建；
// VoiceOver 開著時範圍不變的位移 100 ms 內不重建；結果與 `BrowserAccessibility.items` 相同
@MainActor
struct BrowserAccessibilityViewTests {
    let m = SpineCarouselTests.pro13
    static let albums = (0..<40).map { AlbumSummary(id: String(format: "%016x", $0 + 1), title: "T\($0)", artist: "A", trackCount: 1,
                                                    artworkToken: nil) }

    final class FakeClock { var now: TimeInterval = 0 }

    func view(voiceOver: Bool = false, clock: FakeClock = FakeClock()) -> BrowserAccessibilityView {
        BrowserAccessibilityView(isVoiceOverRunning: { voiceOver }, now: { clock.now })
    }

    func snapshot(_ offset: CGFloat) -> BrowserAccessibilityView.Snapshot {
        .init(albums: Self.albums, offset: offset, metrics: m,
              visible: SpineCarousel.visibleRange(offset: offset, count: Self.albums.count, metrics: m))
    }

    @Test func doesNotBuildUntilQueried() {
        let v = view()
        for i in 0..<30 { v.setSnapshot(snapshot(CGFloat(i) * 7)) }
        #expect(v.buildCount == 0)
        let elements = v.accessibilityElements as? [AlbumAccessibilityElement]
        #expect(v.buildCount == 1)
        let expected = BrowserAccessibility.items(albums: Self.albums, offset: 29 * 7, metrics: m, visible: snapshot(29 * 7).visible)
        #expect(elements?.map(\.albumID) == expected.map(\.albumID))
        #expect(elements?.map(\.accessibilityFrameInContainerSpace) == expected.map(\.frame))
        _ = v.accessibilityElements
        #expect(v.buildCount == 1)
    }

    @Test func voiceOverThrottlesSmallMovesButNotRangeChanges() {
        let clock = FakeClock()
        let v = view(voiceOver: true, clock: clock)
        v.setSnapshot(snapshot(10 * m.slot))
        _ = v.accessibilityElements
        #expect(v.buildCount == 1)
        clock.now = 0.05
        v.setSnapshot(snapshot(10 * m.slot + 2))
        _ = v.accessibilityElements
        #expect(v.buildCount == 1)
        clock.now = 0.2
        _ = v.accessibilityElements
        #expect(v.buildCount == 2)
        clock.now = 0.21
        v.setSnapshot(snapshot(20 * m.slot))
        _ = v.accessibilityElements
        #expect(v.buildCount == 3)
    }

    @Test func settledSnapshotAlwaysRebuilds() {
        let clock = FakeClock()
        let v = view(voiceOver: true, clock: clock)
        v.setSnapshot(snapshot(10 * m.slot))
        _ = v.accessibilityElements
        clock.now = 0.01
        v.setSnapshot(snapshot(10 * m.slot + 1), settled: true)
        _ = v.accessibilityElements
        #expect(v.buildCount == 2)
    }

    @Test func elementLookupBuildsWithLatestSnapshot() {
        let v = view()
        v.setSnapshot(snapshot(15 * m.slot))
        #expect(v.element(for: Self.albums[15].id) != nil)
        #expect(v.buildCount == 1)
    }
}
