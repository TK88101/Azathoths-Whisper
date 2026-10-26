import CoreGraphics
import RemoteProtocol

/// 清單換了之後中央該停在哪張（sprint-6-detail.md §4.3；CR-027）：有待還原的位置（重開、清空搜尋）＝它，不在清單＝第一張；
/// 搜尋改變＝第一張；換版＝保留原中央專輯（仍在清單中時）。與播放狀態無關
enum BrowserScrollAnchor {
    static func target(previousCenter: String?, newIDs: [String], queryChanged: Bool, restore: String? = nil) -> String? {
        if let restore { return newIDs.contains(restore) ? restore : newIDs.first }
        if queryChanged { return newIDs.first }
        if let previousCenter, newIDs.contains(previousCenter) { return previousCenter }
        return newIDs.first
    }
}

struct BrowserAccessibilityItem: Equatable {
    let albumID: String
    let label: String
    let frame: CGRect
}

/// VoiceOver 元素（§4.3「VoiceOver 焦點框」）：每個可見盒一個，frame＝朝向使用者的面的投影外接框（夾在瀏覽區內），左到右。
/// 槽位等寬、盒子非線性外擴，所以不能用槽位當元素
enum BrowserAccessibility {
    static func items(albums: [AlbumSummary], offset: CGFloat, metrics: SpineCarouselMetrics,
                      visible: Range<Int>? = nil) -> [BrowserAccessibilityItem] {
        let projection = BoxProjection(metrics: metrics)
        let visible = visible ?? SpineCarousel.visibleRange(offset: offset, count: albums.count, metrics: metrics)
        return visible.compactMap { index in
            let pose = SpineCarousel.pose(u: SpineCarousel.u(index: index, offset: offset, metrics: metrics), metrics: metrics)
            var frame = CGRect.null
            for face in BoxProjection.Face.allCases where projection.isFacingViewer(face, pose: pose) {
                frame = frame.union(projection.bounds(face, pose: pose))
            }
            frame = frame.intersection(metrics.browse)
            guard !frame.isNull, frame.width >= 1 else { return nil }
            let album = albums[index]
            return BrowserAccessibilityItem(albumID: album.id, label: "\(album.title), \(album.artist)", frame: frame)
        }
    }
}

/// 首屏（§4.12）：第一頁到達後、捲動在起點時的可見盒
enum BrowserFirstScreen {
    static func ids(albums: [AlbumSummary], metrics: SpineCarouselMetrics) -> [String] {
        SpineCarousel.visibleRange(offset: 0, count: albums.count, metrics: metrics).map { albums[$0].id }
    }
}
