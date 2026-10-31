import SwiftUI

/// 唱機浮層（sprint-5-detail.md §4.5、D2）：左上「關閉」、下方唱片樣式五選一；點唱片與唱臂以外切換，5 s 自動隱藏。
/// 提示（S4 文案）不隨浮層隱藏，常駐底部
struct TurntableOverlay: View {
    let model: TurntableViewModel
    let onClose: () -> Void
    @State private var showsSkinPicker = false
    @State private var smokeRowWidth: CGFloat = 0
    @AccessibilityFocusState private var focusedVariant: SmokeVariantChoice?

    var body: some View {
        ZStack {
            if model.overlay.isVisible {
                VStack {
                    HStack {
                        Button(action: onClose) {
                            Label("Close", systemImage: "xmark").overlayCircleButton()
                        }
                        .accessibilityIdentifier(AccessibilityID.turntableClose)
                        Spacer()
                        // CR-034 增補 A：有兩款以上才有入口；轉場中照樣可開，格子停用並說明
                        if model.canBrowseSkins { skinButton }
                    }
                    Spacer()
                    #if DEBUG
                    tuningPanel
                    measurement
                    if model.resolvedStyle.isSwirl { swirlSeedControl }
                    if model.skin.spec.spriteLayers != nil { spriteDiagnostics }
                    #endif
                    stylePicker
                }
                // 煙渦第二排錨定在 SMOKE 按鈕上（主排捲動時也跟著），左右夾在浮層內；收合時這層沒有內容、不攔點擊
                .overlayPreferenceValue(SmokeAnchorKey.self) { anchor in
                    GeometryReader { proxy in
                        if model.isSmokeRowOpen, let anchor {
                            let point = proxy[anchor]
                            smokeRow
                                .fixedSize()
                                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { smokeRowWidth = $0 }
                                .position(x: SmokeRowLayout.centerX(anchorX: point.x, rowWidth: smokeRowWidth, containerWidth: proxy.size.width),
                                          y: point.y - SmokeRowLayout.verticalOffset)
                        }
                    }
                }
                .padding(64)
                .transition(.opacity)
            }
            VStack {
                Spacer()
                notice.padding(.bottom, 40)
            }
        }
        // 防線：視圖被移出（斷線、關唱機）時 popover 的回呼不一定跑；VM 另在 close／hideImmediately 清空（r2-1）
        .onDisappear {
            model.overlay.endHold(.skinPicker)
            model.overlay.endHold(.smokeVariants)
        }
    }

    #if DEBUG
    /// N-02 量測（#5-1）：模糊圖就緒後才可按，量測期間不做網路與解碼工作
    private var measurement: some View {
        let monitor = TurntableMeasurement.shared
        let ready = model.backgroundSource != nil
        let context = ["assets": "\(VinylAssets.image(.base) != nil)", "blurReady": "\(ready)", "style": model.resolvedStyle.rawValue]
        return HStack(spacing: 12) {
            Button { monitor.start(.spin, context: context) } label: { Text(verbatim: "measure spin 30 s") }
            if let result = monitor.lastResult { Text(verbatim: result) }
        }
        .disabled(!ready || monitor.running != nil)
        .font(.caption.monospacedDigit())
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// CR-037 §4.7：換一組花紋種子（只存記憶體、App 重開即消失）；生效中顯示 override
    private var swirlSeedControl: some View {
        HStack(spacing: 12) {
            Button { model.swirlDebugSalt += 1 } label: { Text(verbatim: "swirl seed +1") }
            if model.swirlDebugSalt != 0 {
                Text(verbatim: "override \(model.swirlDebugSalt)")
                Button { model.swirlDebugSalt = 0 } label: { Text(verbatim: "reset") }
            }
        }
        .font(.caption.monospacedDigit())
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// CR-034 附錄 F 在場對照：A′（關唱機保留）、E（解碼優先序）開關、清快取（模擬冷開）、存 trace
    private var spriteDiagnostics: some View {
        @Bindable var diagnostics = SpriteDiagnostics.shared
        return HStack(spacing: 12) {
            Toggle(isOn: $diagnostics.keepOnClose) { Text(verbatim: "A′ keep") }.fixedSize()
            Toggle(isOn: $diagnostics.prioritized) { Text(verbatim: "E order") }.fixedSize()
            Button { model.sprites.release() } label: { Text(verbatim: "clear cache") }
            Button { diagnostics.save() } label: { Text(verbatim: "save trace") }
            if let saved = diagnostics.lastSaved { Text(verbatim: saved) }
            Text(verbatim: "sprites \(model.sprites.residentBytes / 1_048_576) MiB")
        }
        .font(.caption.monospacedDigit())
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// v2.1 T8／T10 調整面板：磨砂盤紅色／其他兩組的主色與霧，拖動即時套用、重開保留；拖動中浮層不自動隱藏
    private var tuningPanel: some View {
        let store = TransparentTuningStore.shared
        let tuning = store.tuning
        return VStack(alignment: .leading, spacing: 6) {
            tuningRow("紅 主色", value: tuning.red.frostedTint, id: AccessibilityID.turntableTuningTint) {
                store.tuning = TransparentTuning(red: .init(frostedTint: $0, material: store.tuning.red.material), other: store.tuning.other)
            }
            tuningRow("紅 霧", value: tuning.red.material, id: AccessibilityID.turntableTuningHaze) {
                store.tuning = TransparentTuning(red: .init(frostedTint: store.tuning.red.frostedTint, material: $0), other: store.tuning.other)
            }
            tuningRow("其他 主色", value: tuning.other.frostedTint, id: AccessibilityID.turntableTuningOtherTint) {
                store.tuning = TransparentTuning(red: store.tuning.red, other: .init(frostedTint: $0, material: store.tuning.other.material))
            }
            tuningRow("其他 霧", value: tuning.other.material, id: AccessibilityID.turntableTuningOtherHaze) {
                store.tuning = TransparentTuning(red: store.tuning.red, other: .init(frostedTint: store.tuning.other.frostedTint, material: $0))
            }
            Button { store.reset() } label: { Text(verbatim: "重設") }
        }
        .font(.caption.monospacedDigit())
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func tuningRow(_ title: String, value: Double, id: String, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: title).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: 0...1, step: 0.05) { editing in editing ? model.overlay.beginHold(.tuningSlider) : model.overlay.endHold(.tuningSlider) }
                .frame(width: 240)
                .accessibilityIdentifier(id)
            Text(verbatim: String(format: "%.2f", value)).frame(width: 40, alignment: .trailing)
        }
    }
    #endif

    /// 唱機外觀：一顆圓鈕（與 Close 同樣式）開選擇器 popover，唱機在背後即時換（CR-034 增補 A §4.4）。
    /// 按下的同一個動作裡先停浮層計時，否則浮層 5 s 隱藏時錨點消失、popover 連帶收起（r1-4）
    private var skinButton: some View {
        Button {
            model.overlay.beginHold(.skinPicker)
            showsSkinPicker = true
        } label: {
            Label("Turntable Skin", systemImage: "record.circle").overlayCircleButton()
        }
        .accessibilityIdentifier(AccessibilityID.turntableSkinButton)
        .popover(isPresented: $showsSkinPicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Turntable Skin").font(.headline)
                TurntableSkinPicker(model: model)
            }
            .padding(16)
            .frame(width: TurntableSkinPicker.threeColumnWidth + 32)
            .preferredColorScheme(.dark)
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: showsSkinPicker) { _, shown in
            if !shown { model.overlay.endHold(.skinPicker) }
        }
    }

    /// 樣式主排（CR-037：9 顆）。容器太窄（Split View 等）時改水平捲動、維持 40 pt 觸控尺寸；煙渦第二排見 body 的 overlayPreferenceValue
    private var stylePicker: some View {
        ViewThatFits(in: .horizontal) {
            styleRow
            ScrollView(.horizontal, showsIndicators: false) { styleRow }
        }
    }

    private var styleRow: some View {
        HStack(spacing: 20) {
            ForEach(RecordStyle.allCases, id: \.self) { style in
                Button {
                    model.tapStyle(style)
                } label: {
                    styleIcon(style)
                        .frame(width: SmokeRowLayout.iconSize, height: SmokeRowLayout.iconSize)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: model.recordStyle == style ? 2 : 0))
                }
                .accessibilityLabel(Text(style.title))
                .accessibilityAddTraits(model.recordStyle == style ? .isSelected : [])
                .accessibilityIdentifier(AccessibilityID.turntableStyle(style.rawValue))
                .modifier(SmokeButtonAccessibility(isSmoke: style == .smoke, isOpen: model.isSmokeRowOpen))
                .anchorPreference(key: SmokeAnchorKey.self, value: .center) { style == .smoke ? $0 : nil }
            }
        }
        .padding(SmokeRowLayout.rowPadding)
        .background(Capsule().fill(Color.black.opacity(0.3)))
    }

    /// 煙渦第二排（CR-037 §4.5b）：選了立即換花紋、不收合；強調色退回時加註
    private var smokeRow: some View {
        HStack(spacing: 8) {
            ForEach(SmokeVariantChoice.allCases, id: \.self) { choice in
                let selected = model.smokeVariant == choice
                let note = choice == .accent && selected ? model.smokeAccentFallback.map(Self.fallbackNote) : nil
                Button {
                    model.smokeVariant = choice
                } label: {
                    HStack(spacing: 6) {
                        Text(choice.title)
                        if let note { Text(note).font(.caption2).opacity(0.75) }
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .foregroundStyle(selected ? Color.black : Color.white)
                    .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.16)))
                }
                .accessibilityLabel(note.map { Text(choice.title) + Text(verbatim: " ") + Text($0) } ?? Text(choice.title))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier(AccessibilityID.turntableSmokeVariant(choice.rawValue))
                .accessibilityFocused($focusedVariant, equals: choice)
            }
        }
        .padding(8)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        // 展開時 VoiceOver 焦點移到目前選項
        .onAppear { focusedVariant = model.smokeVariant }
    }

    static func fallbackNote(_ ink: SmokeInk) -> LocalizedStringKey {
        ink == .light ? "(Light Ink for this song)" : "(Dark Ink for this song)"
    }

    /// 原版的小唱片預覽（#5-1 G6）、SWIRL 系列的自製灰階圖（CR-037）；RANDOM 或缺素材＝圓底加符號
    @ViewBuilder private func styleIcon(_ style: RecordStyle) -> some View {
        if let image = Self.iconImage(style.icon) {
            Image(uiImage: image).resizable().clipShape(Circle())
        } else {
            Circle().fill(Color(white: style == .random ? 0.5 : 0.15))
                .overlay(Image(systemName: style == .random ? "shuffle" : "circle.circle").foregroundStyle(.white.opacity(0.8)))
        }
    }

    static func iconImage(_ source: RecordStyle.IconSource) -> UIImage? {
        switch source {
        case .vinylAsset(let name): VinylAssets.image(name)
        case .bundled(let name): UIImage(named: name)
        case .symbol: nil
        }
    }

    @ViewBuilder private var notice: some View {
        let nowPlaying = model.nowPlaying
        if let notice = nowPlaying.notice {
            PlaybackNoticeRow(notice: notice, id: AccessibilityID.turntableNotice, onResync: nowPlaying.resync, onRetry: nowPlaying.resync)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .frame(maxWidth: 520)
        } else if let text = PlaybackPresentation.availabilityText(nowPlaying.availability) {
            Text(text).font(.footnote).padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .accessibilityIdentifier(AccessibilityID.turntableNotice)
        }
    }
}


private extension Label where Title == Text, Icon == Image {
    /// 浮層角落的圓鈕（關閉、唱機外觀）：只顯示圖示、40 pt 半透明黑圓
    func overlayCircleButton() -> some View {
        labelStyle(.iconOnly).font(.title2.weight(.semibold))
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.black.opacity(0.3)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
            .foregroundStyle(.white)
    }
}

/// 煙渦第二排的位置（CR-037 §4.5b）：水平中心對齊主排上的 SMOKE 圖示，超出畫面時整排往內平移、左右各留邊界
enum SmokeRowLayout {
    static let margin: CGFloat = 16
    /// 主排圖示與內距（styleRow 用同一組值）
    static let iconSize: CGFloat = 40
    static let rowPadding: CGFloat = 12
    /// 主排上緣到第二排下緣的間隔；第二排高＝膠囊 44＋上下內距 8
    static let gap: CGFloat = 12
    static let smokeRowHeight: CGFloat = 44 + 2 * 8
    /// 第二排中心在 SMOKE 圖示中心上方的距離
    static let verticalOffset = iconSize / 2 + rowPadding + gap + smokeRowHeight / 2

    static func centerX(anchorX: CGFloat, rowWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let half = rowWidth / 2
        let low = margin + half, high = containerWidth - margin - half
        guard low <= high else { return containerWidth / 2 }
        return min(max(anchorX, low), high)
    }
}

/// 主排上 SMOKE 按鈕的中心（第二排的錨點）
struct SmokeAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>? { nil }
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) { value = value ?? nextValue() }
}

/// SMOKE 主按鈕的展開狀態與提示（VoiceOver）
private struct SmokeButtonAccessibility: ViewModifier {
    let isSmoke: Bool
    let isOpen: Bool

    func body(content: Content) -> some View {
        if isSmoke {
            content
                .accessibilityValue(Text(isOpen ? "Expanded" : "Collapsed"))
                .accessibilityHint(Text("Shows Smoke variants"))
        } else {
            content
        }
    }
}

extension SmokeVariantChoice {
    var title: LocalizedStringKey {
        switch self {
        case .auto: "Auto"
        case .water: "Water"
        case .darkInk: "Dark Ink"
        case .lightInk: "Light Ink"
        case .accent: "Accent"
        }
    }
}

extension RecordStyle {
    var title: LocalizedStringKey {
        switch self {
        case .random: "Random"
        case .classic: "Classic"
        case .transparent: "Transparent"
        case .splash: "Splash"
        case .marble: "Marble"
        case .smoke: "Smoke"
        case .streak: "Streak"
        case .flake: "Flake"
        case .chunk: "Chunk"
        }
    }
}
