import SwiftUI

/// Cover Flow 分頁（ACCEPTANCE H 段）。**純展示**——無雙擊播放、無任何播控動詞（決策 6）。
struct CoverFlowView: View {
    @Bindable var model: CoverFlowViewModel

    /// 單張封面邊長。負間距與邊距都由 `CoverFlowGeometry` 依此推導
    private let itemWidth: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            strip
            centerLabel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        // H-09：窗口內按鍵，**無全域監聽**（全域 hook 會誤傷其他 app）
        .focusable()
        .onKeyPress(.leftArrow) {
            model.stepCenter(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            model.stepCenter(by: 1)
            return .handled
        }
        // tab 生命週期由 AppModel.select(_:) 單一管理（與 Batch 同構），此處不重複驅動
    }

    private var strip: some View {
        CoverFlowStrip(
            items: model.items,
            itemWidth: itemWidth,
            centerID: Binding(
                get: { model.centerID },
                // 經 VM 判定是否為使用者滑動——程式化居中的回呼不得被誤記為使用者接管
                set: { model.scrollPositionDidChange(to: $0) }
            )
        ) { track in
            CoverFlowItemContainer(model: model, track: track, size: itemWidth)
        }
        .frame(maxHeight: .infinity)
    }

    /// H-03：中心下方標籤 `ARTIST // TITLE`，mono 排版語言
    private var centerLabel: some View {
        Text(verbatim: centerText)
            .font(Theme.Fonts.mono(12))
            .textCase(.uppercase)
            .tracking(2)
            .foregroundStyle(Theme.Gray.g400)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("coverflow-center-label")
            .accessibilityLabel(centerText)
    }

    private var centerText: String {
        guard let centerID = model.centerID,
              let track = model.items.first(where: { $0.persistentID == centerID })
        else { return "--" }
        return "\(track.artist) // \(track.title)"
    }
}

/// 單項容器：負責取圖與生命週期。
/// 圖片用 `.task(id:)` 按需取——view 消失時 SwiftUI 自動取消，
/// 這正是 P1 不需要 VM 層 artworkToken 的原因。
private struct CoverFlowItemContainer: View {
    let model: CoverFlowViewModel
    let track: AlbumTrack
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        CoverFlowItem(artwork: image, size: size)
            .accessibilityIdentifier("coverflow-item-\(track.persistentID)")
            .task(id: track.persistentID) {
                image = await model.artwork(for: track.persistentID)
            }
    }
}
