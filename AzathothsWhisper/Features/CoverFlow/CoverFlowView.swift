import SwiftUI

/// Cover Flow（Editor 頁內的一層，計劃 §2.1、D2、D6）。**純展示——無任何播控**（決策 6）：
/// 唯一可點的是「正在播 ∧ 位於幾何正中」的那張，點了只開 Editor。
struct CoverFlowView: View {
    @Bindable var model: CoverFlowViewModel
    /// 畫面＝Cover Flow ∧ Editor 分頁在前：才可取得焦點、才接方向鍵（AC14）
    let isInteractive: Bool
    var focus: FocusState<Bool>.Binding
    /// 右側可用性（AC8b）：`unavailable` 才標明讀不到
    let upcoming: DeckSnapshot.Upcoming
    let onTapPlayingCard: () -> Void

    /// 單張封面邊長。負間距與邊距都由 `CoverFlowGeometry` 依此推導。
    /// `static`（非 private）是為了讓 H-02 UI 測試閘門的 fixture 以單元測試釘住同源，見 `CoverFlowUITestFixtureTests`
    static let itemWidth: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            strip
                .overlay(alignment: .trailing) { upNextNotice }
            centerLabel
            centerStatus
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        // H-09：窗口內按鍵，**無全域監聽**（全域 hook 會誤傷其他 app）；降下時不持有焦點（AC14）
        .focusable(isInteractive)
        .focused(focus)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
    }

    private func step(_ offset: Int) -> KeyPress.Result {
        guard isInteractive else { return .ignored }
        model.stepCenter(by: offset)
        return .handled
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
        ) { card, isCentered in
            CoverFlowItemContainer(
                model: model,
                card: card,
                size: Self.itemWidth,
                // D6：可點＝播放中 ∧ 幾何正中（容差 ±0.2 卡寬，捲動跨中點途中沒有卡可點）
                isPlayingAndCentered: card.side == .current && isCentered,
                onTap: onTapPlayingCard
            )
        }
        .frame(maxHeight: .infinity)
        // H-02 UI 測試閘門的 AX 探針：strip 外框＝視口，其 midX 是「居中」的基準
        .accessibilityIdentifier("coverflow-strip")
    }

    /// 退回模式：右側留空並明示讀不到，不捏造（AC8b）
    @ViewBuilder
    private var upNextNotice: some View {
        if upcoming == .unavailable {
            Text("upnext_unavailable")
                .font(Theme.Fonts.mono(11))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Gray.g500)
                .padding(.trailing, 48)
                .accessibilityIdentifier(AccessibilityID.upNextUnavailable)
        }
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
            .padding(.top, 20)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(AccessibilityID.centerLabel)
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

    /// 中心那張卡的歌詞狀態字（設計稿：✓ Lyrics in file／✗ Missing lyrics／— Marked: no lyrics）
    @ViewBuilder
    private var centerStatus: some View {
        if let card = model.cards.first(where: { $0.id == model.centerID }) {
            let status = model.status(for: card)
            (Text(verbatim: LyricsBadge.symbol(for: status) + " ") + Text(LocalizedStringKey(LyricsBadge.statusKey(for: status))))
                .font(Theme.Fonts.mono(11))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(LyricsBadge.tone(for: status).color)
        }
    }
}

/// 單項容器：取圖、生命週期、徽章、可點與否。
/// 圖片用 `.task(id:)` 按需取——view 消失時 SwiftUI 自動取消，這正是 VM 層不需要 artworkToken 的原因。
private struct CoverFlowItemContainer: View {
    let model: CoverFlowViewModel
    let card: DeckCard
    let size: CGFloat
    let isPlayingAndCentered: Bool
    let onTap: () -> Void

    @State private var image: NSImage?
    @State private var isHovering = false

    var body: some View {
        Group {
            if isPlayingAndCentered {
                Button(action: onTap) { item }
                    .buttonStyle(.plain)
                    .onHover { isHovering = $0 }
                    .accessibilityIdentifier(AccessibilityID.playingCard)
                    .accessibilityLabel(Text("edit_lyrics_of \(title)"))
            } else {
                // 非播放中的卡不是按鈕（AC3）：沒有點擊處理，點了畫面、綁定曲、抓詞都不變
                item
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.cardPrefix + card.id)
            }
        }
        // key 帶版本號：取圖失敗時先顯示佔位，退避到期重取成功後 service 會通知 VM
        // 遞增**該 ID** 的版本，只讓這一項重讀（命中記憶體，不驚動其他可見項）
        .task(id: ItemTaskKey(
            persistentID: card.persistentID,
            revision: model.artworkRevision(for: card.persistentID)
        )) {
            image = await model.artwork(for: card.persistentID)
        }
    }

    private var title: String {
        model.details[card.persistentID]?.title ?? ""
    }

    /// 徽章與提示疊在封面正面上（H-08：不改變封面尺寸）
    private var item: some View {
        ZStack(alignment: .top) {
            CoverFlowItem(artwork: image, size: size)
            faceOverlay
                .frame(width: size, height: size)
        }
    }

    private var faceOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                badge
            }
            Spacer(minLength: 0)
            if isPlayingAndCentered, isHovering {
                Text("edit_lyrics_hint")
                    .font(Theme.Fonts.mono(11))
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.72))
            }
        }
    }

    /// AC7：✓ 有詞／✗ 缺詞／— 已標記／? 讀不到；中心（播放中）卡附軌號
    private var badge: some View {
        let status = model.status(for: card)
        return Text(verbatim: LyricsBadge.text(
            for: status,
            trackNumber: model.details[card.persistentID]?.trackNumber,
            isCurrent: card.side == .current
        ))
        .font(Theme.Fonts.mono(12))
        .foregroundStyle(LyricsBadge.tone(for: status).color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.55))
        .padding(12)
    }
}

/// `.task(id:)` 的 key：ID 或版本任一改變都重跑
private struct ItemTaskKey: Equatable {
    let persistentID: String
    let revision: Int
}
