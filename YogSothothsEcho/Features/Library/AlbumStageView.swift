import SwiftUI

/// 開合舞台（sprint-6-detail.md §4.5「互動只在 2D」）：只在被點那張歸舞台時（飛行中；Reduce Motion 為詳情框原地淡入）畫它，
/// 沿用側封投影；落定後交給詳情層的 2D 封面（同框、同圖，T0b 驗過無位移）。投影＝深色板隨飛行長出（#6-1 v0.6 F5）。不收觸控
struct AlbumStageView: View {
    let controller: AlbumOpenController
    /// F10（E.4）：投影定值隨詳情背景亮度（沒有＝深色值）
    var background: DetailBackgroundController?

    var body: some View {
        TimelineView(.animation(paused: !controller.isAnimating)) { _ in
            let channels = controller.channels()
            if controller.owner(channels) == .stage, let current = controller.pose(channels), let metrics = controller.metrics {
                let front = BoxProjection(metrics: metrics).bounds(.front, pose: current.pose.flight)
                ZStack(alignment: .topLeading) {
                    DetailCoverShadowView(frame: front, opacity: background?.ink.coverShadowOpacity ?? DetailBackgroundModel.shadowOpacity.dark,
                                          progress: channels.flight * current.pose.flightOpacity)
                    BoxFaces(album: current.album, image: controller.cover, pose: current.pose.flight, metrics: metrics,
                             spineOpacity: current.pose.spineOpacity)
                        .opacity(current.pose.flightOpacity)
                }
                .offset(x: controller.browseOrigin.x, y: controller.browseOrigin.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 封面後方的深色板（`DetailCoverShadow`）：放在封面框的同一位置、往下錯開、模糊，只從下緣露出來
struct DetailCoverShadowView: View {
    let frame: CGRect
    let opacity: Double
    let progress: Double

    var body: some View {
        let shadow = DetailCoverShadow(coverSide: frame.width, opacity: opacity, progress: progress)
        if shadow.opacity > 0 {
            Rectangle()
                .fill(.black.opacity(shadow.opacity))
                .frame(width: frame.width, height: frame.height)
                .blur(radius: shadow.blur)
                .offset(x: frame.minX, y: frame.minY + shadow.offsetY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
