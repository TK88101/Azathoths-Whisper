import RemoteTransport
import SwiftUI
import UIKit

/// 掃描器工廠（S6.5 D1）：正式＝VisionKit 掃描器；測試注入 spy，斷言只有兩個掃描態會建立相機
struct PairingScanner {
    let make: @MainActor (@escaping (String) -> Void) -> AnyView

    static let live = PairingScanner { onScan in AnyView(PairingScanView(onScan: onScan)) }

    #if DEBUG
    /// UI 測試：模擬器沒有相機，出現即送出假載荷
    static func fake(_ payload: String) -> PairingScanner {
        PairingScanner { onScan in AnyView(Color.clear.frame(width: 1, height: 1).onAppear { onScan(payload) }) }
    }
    #endif
}

/// 連線頁（CR-033 方向 E Soft Relay；s6-5-pairing-redesign.md §4）：整頁唯一 owner——背景、兩欄、外觀三選一、狀態探針。
/// QR 內容不顯示、不截圖；掃描器離開掃描態即卸下，不保留任何相機畫面（CR-033 修訂 R1）
struct PairingScreen: View {
    let model: ConnectionViewModel
    @Bindable var appearance: AppearanceViewModel
    let preset: BackgroundPreset
    var scanner: PairingScanner = .live
    /// 測試用：系統的「減少透明度」環境值唯讀，基準圖以此覆寫（nil＝跟系統）
    var reduceTransparencyOverride: Bool?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let metrics = PairingLayout.metrics(for: size)
            ZStack(alignment: .bottomLeading) {
                if let content = PairingLayout.content(for: model.state, suffix: model.lastPendingSuffix) {
                    let treatment = PairingStyle.treatment(preset: preset, scheme: colorScheme, size: size, reduceTransparency: reduceTransparency)
                    HStack(alignment: .center, spacing: PairingLayout.gap) {
                        PairingTextColumn(content: content, treatment: treatment, compact: metrics.isCompact,
                                          onAction: perform)
                            .frame(width: metrics.leftWidth)
                            // 左欄不壓到左下角的外觀三選一（§4.2 版面樹）
                            .padding(.bottom, Self.pickerReserve)
                        PairingViewer(viewer: content.viewer, size: metrics.viewer, preset: preset,
                                      reduceTransparency: reduceTransparency, scanner: scanner, onScan: scan)
                            .accessibilitySortPriority(PairingLayout.Region.viewer.rawValue)
                    }
                    .padding(.horizontal, PairingLayout.sideMargin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    appearancePicker
                        .padding(.leading, PairingLayout.sideMargin)
                        .padding(.bottom, Self.pickerBottom)
                }
                stateProbe
            }
            .frame(width: size.width, height: size.height)
        }
        .background {
            PresetGradientView(preset: preset, scheme: colorScheme, reduceTransparency: reduceTransparency).ignoresSafeArea()
        }
    }

    static let pickerBottom: CGFloat = 38
    /// 外觀三選一的高度（約 40）＋與左欄的間距
    static let pickerReserve: CGFloat = pickerBottom + 56

    private var appearancePicker: some View {
        Picker("Appearance", selection: $appearance.setting) {
            ForEach(AppearanceSetting.allCases, id: \.self) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 300)
        .padding(4)
        .tintedGlass(in: Capsule())
        .accessibilityIdentifier(AccessibilityID.appearancePicker)
        .accessibilitySortPriority(PairingLayout.Region.appearance.rawValue)
    }

    /// UI 測試讀的狀態代號：只在 DEBUG（Release 不讓 VoiceOver 念出內部代號）
    @ViewBuilder private var stateProbe: some View {
        #if DEBUG
        Text(verbatim: ConnectionPresentation.stateID(model.state))
            .font(.caption2)
            .foregroundStyle(.clear)
            .accessibilityIdentifier(AccessibilityID.connectionState)
        #endif
    }

    private func scan(_ text: String) {
        // 不用 .task：狀態一變、掃描區消失時 SwiftUI 會取消它，連帶中斷配對（2026-10-15 實測）
        Task { await model.scanned(text) }
    }

    private func perform(_ action: PairingLayout.Action) {
        switch action {
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .scanAgain:
            model.rescan()
        case .forgetMac, .pairAgain:
            Task { await model.forgetMac() }
        }
    }
}

// MARK: 左欄

/// 品牌、說明、主要按鈕。字色依背景自動選（PairingStyle.treatment），不足時下方加柔邊遮罩
struct PairingTextColumn: View {
    let content: PairingLayout.Content
    let treatment: PairingStyle.Treatment
    let compact: Bool
    let onAction: (PairingLayout.Action) -> Void

    /// 步驟編號圓圈跟字級縮放（最大字級時固定 28 會讓數字溢出）
    @ScaledMetric(relativeTo: .subheadline) private var stepBadge: CGFloat = 28

    private var palette: PairingStyle.Palette { PairingStyle.palette(treatment.ink) }
    private var primary: Color { treatment.ink.color }
    private var secondary: Color { palette.primary.color.opacity(PairingStyle.Palette.secondaryAlpha) }

    var body: some View {
        // 放得下就直接排（ImageRenderer 畫不出 ScrollView）；最大字級放不下時才捲動
        ViewThatFits(in: .vertical) {
            column
            ScrollView(.vertical) { column }
                .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(primary)
    }

    /// 遮罩只鋪在文字內容底下（不鋪滿欄高）
    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 38)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.pairingHeader)
                .accessibilitySortPriority(PairingLayout.Region.header.rawValue)
            message
                .accessibilitySortPriority(PairingLayout.Region.body.rawValue)
            if let action = content.action {
                actionButton(action)
                    .padding(.top, 20)
                    .accessibilitySortPriority(PairingLayout.Region.action.rawValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { scrim }
        .padding(.vertical, 24)
    }

    @ViewBuilder private var scrim: some View {
        if treatment.scrim > 0 {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(palette.scrim.color.opacity(treatment.scrim))
                .padding(-Self.scrimOutset)
                .blur(radius: Self.scrimFeather)
                .allowsHitTesting(false)
        }
    }

    /// 遮罩比左欄各邊大 32、羽化 16：取樣點都落在全不透明的內區
    static let scrimOutset: CGFloat = 32
    static let scrimFeather: CGFloat = 16

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pair with your Mac")
                .font(PairingStyle.eyebrow)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(secondary)
                .padding(.bottom, 4)
            Text(verbatim: "Yog-Sothoth's Echo")
                .font(PairingStyle.brand(compact: compact))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Use this iPad as a remote for Music on your Mac.")
                .font(.body)
                .foregroundStyle(secondary)
        }
    }

    @ViewBuilder private var message: some View {
        switch content.text {
        case .steps(let invalidCode):
            VStack(alignment: .leading, spacing: 16) {
                step(1) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("On your Mac, open Azathoth's Whisper")
                        // A-07：Mac 選單寫死英文，三語都顯示原文
                        Text(verbatim: "Settings › Remote Settings...")
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .tintedGlass(in: Capsule())
                    }
                }
                step(2) { Text("Choose **Pair new iPad**.") }
                step(3) { Text("Hold this iPad up to the code on your Mac.") }
                if invalidCode {
                    Text("That isn't an Azathoth's Whisper pairing code.")
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.warning.color)
                        .padding(.top, 4)
                }
            }
        case .cameraDenied: Text("Camera access is off. Turn it on to scan the pairing code.")
        case .cameraUnavailable: Text("This iPad can't scan codes with its camera.")
        case .confirmCode:
            VStack(alignment: .leading, spacing: 6) {
                Text("Check the 4 characters on your Mac.")
                Text("If they match, click Allow on your Mac.").foregroundStyle(secondary)
            }
        case .failed(let failure): Text(ConnectionPresentation.failureMessage(failure))
        case .connected(let name):
            VStack(alignment: .leading, spacing: 6) {
                Label { Text("Connected") } icon: { Image(systemName: "checkmark.circle.fill") }
                Text(verbatim: name).font(.headline)
            }
        case .retrying(let seconds):
            VStack(alignment: .leading, spacing: 6) {
                Text("Can't reach your Mac. Make sure Remote Settings is on in Azathoth's Whisper.")
                Text(verbatim: "\(seconds)s").foregroundStyle(secondary)
            }
        case .waitingForMac: Text("Waiting for your Mac… Turn on Remote Settings in Azathoth's Whisper.")
        case .needsRepair: Text("Your Mac no longer recognizes this iPad.")
        }
    }

    private func step(_ number: Int, @ViewBuilder _ label: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(verbatim: "\(number)")
                .font(PairingStyle.stepNumber)
                .foregroundStyle(secondary)
                .frame(width: stepBadge, height: stepBadge)
                .overlay(Circle().strokeBorder(secondary.opacity(0.6), lineWidth: 1))
                .accessibilityHidden(true)
            label()
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func actionButton(_ action: PairingLayout.Action) -> some View {
        switch action {
        case .openSettings:
            ctaButton("Open Settings") { onAction(action) }.accessibilityIdentifier(AccessibilityID.openSettingsButton)
        case .scanAgain:
            ctaButton("Scan again") { onAction(action) }.accessibilityIdentifier(AccessibilityID.scanAgainButton)
        case .pairAgain:
            ctaButton("Pair again") { onAction(action) }
        case .forgetMac:
            Button("Forget this Mac", role: .destructive) { onAction(action) }
                .font(.body)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .tintedGlass(in: Capsule())
        }
    }

    private func ctaButton(_ title: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .frame(minHeight: 44)
                .background(PairingStyle.cta.color, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// 按下縮 0.95（不變淡：使用者 2026-10 規則「按鈕處理中不得變淡」）
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: 取景窗

/// 右側圓角玻璃取景窗：掃描態掛相機；其餘狀態為程序化抽象光斑底（不用相機畫面，CR-033 修訂 R1）
struct PairingViewer: View {
    let viewer: PairingLayout.Viewer
    let size: CGSize
    let preset: BackgroundPreset
    let reduceTransparency: Bool
    let scanner: PairingScanner
    let onScan: (String) -> Void

    static let outerRadius: CGFloat = 28
    static let inset: CGFloat = 8

    var body: some View {
        ZStack {
            switch viewer {
            case .liveCamera(let invalid):
                Color.black.overlay(scanner.make(onScan))
                ScanCorners(invalid: invalid)
            case .abstract(let tone, let center):
                AbstractGlow(preset: preset, tone: tone, solid: reduceTransparency)
                centerView(center)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.outerRadius - Self.inset, style: .continuous))
        .padding(Self.inset)
        .frame(width: size.width, height: size.height)
        .tintedGlass(in: RoundedRectangle(cornerRadius: Self.outerRadius, style: .continuous))
    }

    @ViewBuilder private func centerView(_ center: PairingLayout.Center) -> some View {
        switch center {
        case .code(let suffix):
            if let suffix {
                Text(verbatim: suffix)
                    .font(PairingStyle.code)
                    .tracking(9)
                    .foregroundStyle(.white)
                    .speechSpellsOutCharacters()
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .plate(radius: 24)
                    .clearGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .accessibilityIdentifier(AccessibilityID.pairingSuffix)
            } else {
                ProgressView().tint(.white).controlSize(.large)
            }
        case .symbol(let symbol):
            Image(systemName: symbol.systemName)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityHidden(true)
        case .progress(let connecting):
            VStack(spacing: 12) {
                ProgressView().tint(.white).controlSize(.large)
                if connecting {
                    Text("Connecting to your Mac…").font(.body).foregroundStyle(.white)
                }
            }
            .padding(20)
            .plate(radius: 20)
        }
    }
}

private extension View {
    /// 取景窗內文字的底板：白字疊在 60% 黑上（§4.2 對比）
    func plate(radius: CGFloat) -> some View {
        background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// 取景框四角（無效碼變橘）；Reduce Motion 時靜止
private struct ScanCorners: View {
    let invalid: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let inset = min(w, h) * 0.16, arm: CGFloat = 44
            Path { p in
                for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (w - inset, inset, -1, 1), (inset, h - inset, 1, -1), (w - inset, h - inset, -1, -1)] {
                    p.move(to: CGPoint(x: x, y: y + dy * arm))
                    p.addLine(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + dx * arm, y: y))
                }
            }
            .stroke(invalid ? PairingStyle.palette(.white).warning.color : .white,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .opacity(dimmed ? 0.65 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dimmed = true }
        }
    }
}

/// 程序化抽象底：頁面背景同一組顏色點在取景窗內畫成大幅模糊光斑（不新增素材、不用相機畫面）
private struct AbstractGlow: View {
    let preset: BackgroundPreset
    let tone: PairingLayout.Tone
    /// Reduce Transparency：只畫底色
    let solid: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base = BackgroundModel.baseColor(preset: preset, scheme: scheme).color
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                base
                if !solid {
                    ForEach(Array(BackgroundModel.points(preset).enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(point.color(scheme).color)
                            .frame(width: size.width * 0.9, height: size.width * 0.9)
                            .position(x: point.x * size.width, y: point.y * size.height)
                    }
                    .blur(radius: tone == .blurred ? 90 : 60)
                }
                if tone == .dimmed { Color.black.opacity(0.4) }
            }
            .saturation(tone == .dimmed ? 0.5 : 1)
        }
        .accessibilityHidden(true)
    }
}
