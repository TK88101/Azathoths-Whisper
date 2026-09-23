import SwiftUI

/// Cover Flow 分頁（ACCEPTANCE H 段）。**純展示**——無雙擊播放、無任何播控動詞（決策 6）。
struct CoverFlowView: View {
    @Bindable var model: CoverFlowViewModel

    /// 單張封面邊長。負間距與邊距都由 `CoverFlowGeometry` 依此推導。
    /// `static`（非 private）是為了讓 H-02 UI 測試閘門的 fixture 以單元測試釘住同源，見 `CoverFlowUITestFixtureTests`
    static let itemWidth: CGFloat = 260

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
            items: model.cards,
            itemWidth: Self.itemWidth,
            centerID: Binding(
                get: { model.centerID },
                // 經 VM 判定是否為使用者滑動——程式化居中的回呼不得被誤記為使用者接管
                set: { newValue in
                    #if DEBUG
                    // H-02 UI 測試閘門的軌跡旁路：記 SwiftUI 原始回寫值（未安裝時為 no-op）
                    CoverFlowUITestTrace.recordBinding(newValue)
                    #endif
                    model.scrollPositionDidChange(to: newValue)
                }
            )
        ) { card in
            CoverFlowItemContainer(model: model, card: card, size: Self.itemWidth)
        }
        .frame(maxHeight: .infinity)
        // H-02 UI 測試閘門的 AX 探針：strip 外框＝視口，其 midX 是「居中」的基準
        .accessibilityIdentifier("coverflow-strip")
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
            #if DEBUG
            // H-02 UI 測試閘門：以原始 centerID 供 UITest 比對（C1／C3）。
            // 只在 DEBUG：Release 曝光會讓 VoiceOver 把 persistentID 原串讀出來
            .accessibilityValue(model.centerID ?? "")
            #endif
    }

    private var centerText: String {
        model.centerLabel
    }
}

/// 單項容器：負責取圖與生命週期。
/// 圖片用 `.task(id:)` 按需取——view 消失時 SwiftUI 自動取消，
/// 這正是 P1 不需要 VM 層 artworkToken 的原因。
private struct CoverFlowItemContainer: View {
    let model: CoverFlowViewModel
    let card: DeckCard
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        CoverFlowItem(artwork: image, size: size)
            .accessibilityIdentifier("coverflow-item-\(card.id)")
            // key 帶版本號：取圖失敗時先顯示佔位，退避到期重取成功後 service 會通知 VM
            // 遞增**該 ID** 的版本，只讓這一項重讀（命中記憶體，不驚動其他可見項）
            .task(id: ItemTaskKey(
                persistentID: card.persistentID,
                revision: model.artworkRevision(for: card.persistentID)
            )) {
                image = await model.artwork(for: card.persistentID)
            }
    }
}

/// `.task(id:)` 的 key：ID 或版本任一改變都重跑
private struct ItemTaskKey: Equatable {
    let persistentID: String
    let revision: Int
}
