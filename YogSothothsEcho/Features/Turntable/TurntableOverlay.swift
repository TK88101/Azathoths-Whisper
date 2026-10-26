import SwiftUI

/// 唱機浮層（sprint-5-detail.md §4.5、D2）：左上「關閉」、下方唱片樣式五選一；點唱片與唱臂以外切換，5 s 自動隱藏。
/// 提示（S4 文案）不隨浮層隱藏，常駐底部
struct TurntableOverlay: View {
    let model: TurntableViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            if model.overlay.isVisible {
                VStack {
                    HStack {
                        Button(action: onClose) {
                            Label("Close", systemImage: "xmark").labelStyle(.iconOnly).font(.title2.weight(.semibold))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.black.opacity(0.3)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
                                .foregroundStyle(.white)
                        }
                        .accessibilityIdentifier(AccessibilityID.turntableClose)
                        Spacer()
                    }
                    Spacer()
                    #if DEBUG
                    tuningPanel
                    measurement
                    #endif
                    stylePicker
                }
                .padding(64)
                .transition(.opacity)
            }
            VStack {
                Spacer()
                notice.padding(.bottom, 40)
            }
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
            Slider(value: Binding(get: { value }, set: set), in: 0...1, step: 0.05) { editing in model.overlay.setEditing(editing) }
                .frame(width: 240)
                .accessibilityIdentifier(id)
            Text(verbatim: String(format: "%.2f", value)).frame(width: 40, alignment: .trailing)
        }
    }
    #endif

    private var stylePicker: some View {
        HStack(spacing: 20) {
            ForEach(RecordStyle.allCases, id: \.self) { style in
                Button {
                    model.recordStyle = style
                } label: {
                    styleIcon(style)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: model.recordStyle == style ? 2 : 0))
                }
                .accessibilityLabel(Text(style.title))
                .accessibilityAddTraits(model.recordStyle == style ? .isSelected : [])
                .accessibilityIdentifier(AccessibilityID.turntableStyle(style.rawValue))
            }
        }
        .padding(12)
        .background(Capsule().fill(Color.black.opacity(0.3)))
    }

    /// 原版的小唱片預覽（#5-1 G6）；RANDOM 或缺素材＝圓底加符號
    @ViewBuilder private func styleIcon(_ style: RecordStyle) -> some View {
        if let image = style.preview.flatMap(VinylAssets.image) {
            Image(uiImage: image).resizable().clipShape(Circle())
        } else {
            Circle().fill(Color(white: style == .random ? 0.5 : 0.15))
                .overlay(Image(systemName: style == .random ? "shuffle" : "circle.circle").foregroundStyle(.white.opacity(0.8)))
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

extension RecordStyle {
    var title: LocalizedStringKey {
        switch self {
        case .random: "Random"
        case .classic: "Classic"
        case .transparent: "Transparent"
        case .splash: "Splash"
        case .marble: "Marble"
        }
    }
}
