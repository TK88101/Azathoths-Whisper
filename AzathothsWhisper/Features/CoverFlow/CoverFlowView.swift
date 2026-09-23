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

    /// 條帶的實際尺寸：推算正中那張封面正面的位置（點擊、懸停、無障碍按鈕都以它為準）
    @State private var stripSize: CGSize = .zero
    @State private var isHoveringCentre = false

    /// 單張封面邊長。負間距與邊距都由 `CoverFlowGeometry` 依此推導。
    /// `static`（非 private）是為了讓 H-02 UI 測試閘門的 fixture 以單元測試釘住同源，見 `CoverFlowUITestFixtureTests`
    static let itemWidth: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            // 播放卡按鈕與條帶並列（不掛在條帶的 overlay 上：那會被併進捲動區、不出現在 AX 樹）
            ZStack {
                strip
                playingCardOverlay
            }
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
            // 卡片純展示、**不掛任何手勢**：實測（2026-09-23 E1–E5）條帶內容一帶手勢（Button、點擊、懸停），
            // 換牌後的捲動定位就失效——VM 的中心已是播放卡，畫面卻停在第一張
            CoverFlowItemContainer(model: model, card: card, size: Self.itemWidth)
                // D6：可點＝播放中 ∧ 幾何正中（容差 ±0.2 卡寬，與疊放同一條幾何路徑）
                .onChange(of: isCentered, initial: true) { _, centred in
                    guard card.side == .current else { return }
                    model.playingCardCentering(cardID: card.id, isCentered: centred)
                }
        }
        .frame(maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { stripSize = $0 }
        // 點擊與懸停在條帶層判定，只認「正中播放卡的封面正面」；其他卡點了無效（AC3）
        .onTapGesture(coordinateSpace: .local) { location in
            guard model.isPlayingCardCentered, centreFace.contains(location) else { return }
            onTapPlayingCard()
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                isHoveringCentre = centreFace.contains(location)
            case .ended:
                isHoveringCentre = false
            }
        }
        // H-02 UI 測試閘門的 AX 探針：strip 外框＝視口，其 midX 是「居中」的基準
        .accessibilityIdentifier("coverflow-strip")
    }

    /// 正中那張的封面正面（不含倒影）：卡片在條帶內垂直置中，高＝邊長 ×（1＋倒影比）
    private var centreFace: CGRect {
        let size = Self.itemWidth
        let cardHeight = size * (1 + CoverFlowItem.reflectionRatio)
        return CGRect(x: (stripSize.width - size) / 2, y: (stripSize.height - cardHeight) / 2, width: size, height: size)
    }

    /// 正中播放卡的無障礙按鈕與懸停提示。**不接收滑鼠**：觸控板捲動照常落到條帶，點擊由條帶層判定；
    /// VoiceOver 與 UITests 仍看得到、按得到它（AC3：唯一的按鈕）
    @ViewBuilder
    private var playingCardOverlay: some View {
        if model.isPlayingCardCentered {
            // 按鈕＋倒影高度的空白直排、整體在 ZStack 中置中：按鈕恰好蓋住封面正面（AX 框也對齊；
            // `offset` 只移繪製、不移 AX 框）
            VStack(spacing: 0) {
                Button(action: onTapPlayingCard) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if isHoveringCentre {
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
                    .frame(width: Self.itemWidth, height: Self.itemWidth)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.playingCard)
                .accessibilityLabel(Text("edit_lyrics_of \(playingTitle)"))
                Color.clear
                    .frame(width: Self.itemWidth, height: Self.itemWidth * CoverFlowItem.reflectionRatio)
                    .accessibilityHidden(true)
            }
            .allowsHitTesting(false)
        }
    }

    private var playingTitle: String {
        guard let id = model.deck.currentCardID, let card = model.cards.first(where: { $0.id == id }) else { return "" }
        return model.details[card.persistentID]?.title ?? ""
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
            LyricsStatusLabel(status: model.status(for: card))
        }
    }
}

/// 單項容器：取圖、生命週期、徽章。**純展示**——可點與否不在這裡（見 `CoverFlowView.playingCardOverlay`）。
/// 圖片用 `.task(id:)` 按需取——view 消失時 SwiftUI 自動取消，這正是 VM 層不需要 artworkToken 的原因。
private struct CoverFlowItemContainer: View {
    let model: CoverFlowViewModel
    let card: DeckCard
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .top) {
            CoverFlowItem(artwork: image, size: size)
            // 徽章疊在封面正面上（H-08：不改變封面尺寸），放在露出的那一角
            badge
                .frame(width: size, height: size, alignment: badgeAlignment)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.cardPrefix + card.id)
        // key 帶版本號：取圖失敗時先顯示佔位，退避到期重取成功後 service 會通知 VM
        // 遞增**該 ID** 的版本，只讓這一項重讀（命中記憶體，不驚動其他可見項）
        .task(id: ItemTaskKey(
            persistentID: card.persistentID,
            revision: model.artworkRevision(for: card.persistentID)
        )) {
            image = await model.artwork(for: card.persistentID)
        }
    }

    private var badgeAlignment: Alignment {
        switch LyricsBadge.corner(of: card.id, in: model.cards.map(\.id), centerID: model.centerID) {
        case .leading: return .topLeading
        case .trailing: return .topTrailing
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
