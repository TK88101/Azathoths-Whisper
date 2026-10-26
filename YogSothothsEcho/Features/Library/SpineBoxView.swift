import RemoteProtocol
import SwiftUI
import UIKit

/// 側封上的一個方盒：自己載 spine 封面（有升級圖時用升級圖）
struct SpineBoxView: View {
    let album: AlbumSummary
    let model: LibraryViewModel
    let pose: BoxPose
    let metrics: SpineCarouselMetrics
    /// 載好的圖放上架，給倒影層用（F10；不另開一份會自己載圖的複本）
    var shelf: SpineImageShelf?
    @State private var image: UIImage?

    static let networkDelay: Duration = .milliseconds(150)

    var body: some View {
        BoxFaces(album: album, image: model.browseArtwork?.image(for: album) ?? image, pose: pose, metrics: metrics)
            .onDisappear { shelf?.images[album.id] = nil }
            .task(id: album.artworkToken ?? album.id) {
                // 只是滑過（150 ms 內離開畫面＝task 被取消）就不向 Mac 要；快取命中照樣立即顯示
                image = await model.image(for: album, networkDelay: Self.networkDelay)
                if !Task.isCancelled { shelf?.images[album.id] = image }
                if !Task.isCancelled { model.metrics.artworkSettled(id: album.id) }
            }
    }
}

/// 側封盒子已載好的 spine 圖（只放可見的幾張）：倒影層讀這裡，不自己載
@MainActor
@Observable
final class SpineImageShelf {
    var images: [String: UIImage] = [:]
}

/// 方盒兩面：正面（封面）與書脊各自 `projectionEffect`；背對使用者的面不畫（CSS backface-visibility: hidden 的對應）。
/// 側封與開合轉場中飛行的那張共用
struct BoxFaces: View {
    let album: AlbumSummary
    let image: UIImage?
    let pose: BoxPose
    let metrics: SpineCarouselMetrics
    var spineOpacity = 1.0

    var body: some View {
        let projection = BoxProjection(metrics: metrics)
        ZStack(alignment: .topLeading) {
            if projection.isFacingViewer(.front, pose: pose) {
                CoverFace(album: album, image: image, length: metrics.cover, side: pose.side).equatable()
                    .projectionEffect(ProjectionTransform(projection.transform(.front, pose: pose)))
            }
            if spineOpacity > 0, projection.isFacingViewer(.spine, pose: pose) {
                SpineFace(album: album, image: image, cover: metrics.cover, thickness: metrics.spine, side: pose.side).equatable()
                    .projectionEffect(ProjectionTransform(projection.transform(.spine, pose: pose)))
                    .opacity(spineOpacity)
            }
        }
    }
}

/// 封面圖（沒有＝穩定的佔位色）：側封正面、飛行封面、詳情封面共用
struct AlbumCoverImage: View {
    let album: AlbumSummary
    let image: UIImage?

    var body: some View {
        // 圖放在底色的 overlay 裡：尺寸由外框決定，非正方形的圖 fill 後才裁得到框內（ZStack 會被撐成圖的大小，#6-1）
        Rectangle().fill(LibraryPresentation.placeholderColor(for: album.id))
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
            .clipped()
    }
}
