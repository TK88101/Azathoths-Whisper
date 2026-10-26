import CoreGraphics
import RemoteProtocol
import Testing

@testable import YogSothothsEcho

// S6 T3（sprint-6-detail.md §4.3、§4.12）：捲動錨點、VoiceOver 元素框、首屏的可見盒
struct BrowserLayoutTests {
    let m = SpineCarouselTests.pro13

    static func albums(_ count: Int) -> [AlbumSummary] {
        (0..<count).map {
            AlbumSummary(id: String(format: "%016llx", UInt64($0 + 1)), title: "Album \($0 + 1)", artist: "Artist \($0 % 3)",
                         trackCount: 1, artworkToken: nil)
        }
    }

    /// 搜尋改變＝捲回第 0 張；換版＝保留原中央專輯（仍在清單中），不在了＝第 0 張；空清單＝nil
    @Test func scrollAnchorRules() {
        let ids = ["a", "b", "c"]
        #expect(BrowserScrollAnchor.target(previousCenter: "c", newIDs: ids, queryChanged: true) == "a")
        #expect(BrowserScrollAnchor.target(previousCenter: "c", newIDs: ["x", "c"], queryChanged: false) == "c")
        #expect(BrowserScrollAnchor.target(previousCenter: "z", newIDs: ids, queryChanged: false) == "a")
        #expect(BrowserScrollAnchor.target(previousCenter: nil, newIDs: ids, queryChanged: false) == "a")
        #expect(BrowserScrollAnchor.target(previousCenter: "c", newIDs: [], queryChanged: false) == nil)
        // CR-027（使用者 2026-10-23）：還原目標（重開、清空搜尋）優先；不在清單＝第一張；與播放狀態無關
        #expect(BrowserScrollAnchor.target(previousCenter: "a", newIDs: ids, queryChanged: true, restore: "c") == "c")
        #expect(BrowserScrollAnchor.target(previousCenter: "a", newIDs: ids, queryChanged: false, restore: "c") == "c")
        #expect(BrowserScrollAnchor.target(previousCenter: "b", newIDs: ids, queryChanged: true, restore: "zz") == "a")
        #expect(BrowserScrollAnchor.target(previousCenter: "b", newIDs: ids, queryChanged: false, restore: nil) == "b")
    }

    /// 每個可見盒一個元素：frame＝朝向使用者的面（正面＋書脊）投影外接框；左到右；標籤「專輯名, 藝人」
    @Test func accessibilityItemsFollowProjectedBoxes() {
        let albums = Self.albums(40)
        let offset = 10 * m.slot + 37
        let items = BrowserAccessibility.items(albums: albums, offset: offset, metrics: m)
        let range = SpineCarousel.visibleRange(offset: offset, count: albums.count, metrics: m)
        let projection = BoxProjection(metrics: m)
        let expectedIDs = range.map { albums[$0].id }.filter { id in
            items.contains { $0.albumID == id }
        }
        #expect(items.map(\.albumID) == expectedIDs)
        #expect(items.count >= 5)
        for item in items {
            let index = albums.firstIndex { $0.id == item.albumID }!
            let pose = SpineCarousel.pose(u: SpineCarousel.u(index: index, offset: offset, metrics: m), metrics: m)
            let frame = BoxProjection.Face.allCases.filter { projection.isFacingViewer($0, pose: pose) }
                .map { projection.bounds($0, pose: pose) }.reduce(CGRect.null) { $0.union($1) }.intersection(m.browse)
            #expect(abs(item.frame.minX - frame.minX) <= 0.5 && abs(item.frame.maxX - frame.maxX) <= 0.5)
            #expect(abs(item.frame.minY - frame.minY) <= 0.5 && abs(item.frame.maxY - frame.maxY) <= 0.5)
            #expect(item.label == "\(albums[index].title), \(albums[index].artist)")
        }
        let xs = items.map(\.frame.midX)
        #expect(xs == xs.sorted())
    }

    /// 完全在瀏覽區外的緩衝盒不給元素（VO 掃不到看不見的東西）
    @Test func offscreenBufferBoxesHaveNoElement() {
        let items = BrowserAccessibility.items(albums: Self.albums(1000), offset: 500 * m.slot, metrics: m)
        #expect(items.allSatisfy { !$0.frame.isEmpty && m.browse.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) })
    }

    @Test func firstScreenIsTheVisibleBoxesAtStart() {
        let albums = Self.albums(300)
        let ids = BrowserFirstScreen.ids(albums: albums, metrics: m)
        let range = SpineCarousel.visibleRange(offset: 0, count: 300, metrics: m)
        #expect(ids == range.map { albums[$0].id })
        #expect(ids.first == albums[0].id && ids.count < 40)
        #expect(BrowserFirstScreen.ids(albums: [], metrics: m).isEmpty)
    }
}
