#if LIQUID_SAMPLE
import SwiftUI

/// CR-038 預覽畫布（§4.4）：真曲的封面套與標籤、唱片與唱機同尺寸同位置，**沒有唱臂**（不冒充真實播放）；
/// 四態自動循環或手動切換。唱片不是按鈕（沒有播放／暫停動作）
struct LiquidPreviewCanvas: View {
    let model: TurntableViewModel
    @State private var engine = LiquidPreviewEngine()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var sample = LiquidSample.shared
        GeometryReader { proxy in
            let layout = TurntableLayout(container: CGRect(origin: .zero, size: proxy.size), fullCover: false, skin: model.skin)
            let deck = model.groupDeck
            TimelineView(.animation) { timeline in
                let frame = engine.frame(at: timeline.date.timeIntervalSinceReferenceDate, preset: sample.preset,
                                         reduceMotion: sample.reduceMotionPreview)
                ZStack(alignment: .topLeading) {
                    Color(white: 0.2)
                    SleeveFace(image: deck.cover, placeholder: TurntableMetrics.coverPlaceholderColor.color, size: layout.cover.size,
                               cornerRadius: 5 * layout.scale * TurntableMetrics.recordSize / 306,
                               shadow: .turntable(scale: layout.scale, containerWidth: layout.container.width))
                        .rotationEffect(.degrees(CoverSleeveState.rotationDegrees(isFullCover: false)))
                        .offset(x: layout.cover.minX, y: layout.cover.minY)
                        .accessibilityHidden(true)
                    VinylRecordView(side: layout.record.width, style: deck.style, splash: deck.splash, colors: deck.colors,
                                    label: deck.label, angle: frame.discAngle.truncatingRemainder(dividingBy: 360), liquid: frame)
                        .scaleEffect(layout.recordVisibleScale)
                        .offset(x: layout.record.minX, y: layout.record.minY)
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: "Liquid sample record"))
                        .accessibilityIdentifier(AccessibilityID.liquidPreviewRecord)
                    controls(sample: sample)
                        .padding(32)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.liquidPreviewCanvas)
    }

    private func controls(sample: LiquidSample) -> some View {
        @Bindable var sample = sample
        let now = Date.now.timeIntervalSinceReferenceDate
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.title2.weight(.semibold)).frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.3)))
                }
                .accessibilityLabel(Text("Close"))
                    .accessibilityIdentifier(AccessibilityID.liquidPreviewClose)
                Text(verbatim: "Liquid preview · \(engine.phase.rawValue)\(engine.isAuto ? " (auto)" : "")")
                    .font(.headline.monospacedDigit())
            }
            HStack(spacing: 8) {
                ForEach(LiquidPreviewPhase.allCases) { phase in
                    Button { engine.select(phase, at: now) } label: { Text(verbatim: phase.rawValue) }
                        .buttonStyle(.bordered)
                        .tint(engine.phase == phase ? .accentColor : .gray)
                        .accessibilityIdentifier(AccessibilityID.liquidPreviewPhase(phase.rawValue))
                }
                Button { engine.setAuto(true, at: now) } label: { Text(verbatim: "auto") }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(AccessibilityID.liquidPreviewAuto)
                Button { Task { await measureAllPhases(sample: sample) } } label: { Text(verbatim: "measure 4 states") }
                    .buttonStyle(.bordered)
                    .disabled(TurntableMeasurement.shared.running != nil)
                if let result = TurntableMeasurement.shared.lastResult { Text(verbatim: result).font(.caption.monospacedDigit()) }
            }
            LiquidSampleOptions(sample: sample)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

extension LiquidPreviewCanvas {
    /// §4.5-1：每態暖機 5 s 再量 10 s；「剛停」先正常轉 5 s，停下的瞬間起量 6 s。一次跑完四態（約 1 分鐘），使用者重複 3 次
    @MainActor
    private func measureAllPhases(sample: LiquidSample) async {
        let monitor = TurntableMeasurement.shared
        let context = ["preset": sample.preset.rawValue, "reduceMotionPreview": "\(sample.reduceMotionPreview)", "canvas": "preview"]
        let steps: [(LiquidPreviewPhase, TurntableMeasurement.Kind)] = [(.still, .liquidPreviewStill), (.slow, .liquidPreviewSlow),
                                                                        (.normal, .liquidPreviewNormal)]
        for (phase, kind) in steps {
            engine.select(phase, at: Date.now.timeIntervalSinceReferenceDate)
            await monitor.measure(kind, context: context)
        }
        engine.select(.normal, at: Date.now.timeIntervalSinceReferenceDate)
        try? await Task.sleep(for: .seconds(TurntableMeasurement.liquidWarmup))
        engine.select(.justStopped, at: Date.now.timeIntervalSinceReferenceDate)
        await monitor.measure(.liquidPreviewJustStopped, context: context)
    }
}

/// preset 三選一＋Reduce Motion 預覽（預覽畫布與浮層共用）
struct LiquidSampleOptions: View {
    @Bindable var sample: LiquidSample

    var body: some View {
        HStack(spacing: 12) {
            Picker(selection: $sample.preset) {
                ForEach(LiquidPreset.allCases) { Text(verbatim: $0.rawValue).tag($0) }
            } label: { Text(verbatim: "preset") }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .accessibilityIdentifier(AccessibilityID.liquidPreset)
            Toggle(isOn: $sample.reduceMotionPreview) { Text(verbatim: "RM preview") }.fixedSize()
        }
        .font(.caption.monospacedDigit())
    }
}

/// 預覽畫布的時鐘與液體狀態（參考型別：TimelineView 每幀推進，不經 @State 觀察，避免在 body 中改狀態）
@MainActor
final class LiquidPreviewEngine {
    private var driver: LiquidPreviewDriver?
    private var motion: LiquidMotion?

    var phase: LiquidPreviewPhase { driver?.phase ?? .still }
    var isAuto: Bool { driver?.isAuto ?? true }

    func frame(at now: Double, preset: LiquidPreset, reduceMotion: Bool) -> LiquidFrame {
        var driver = driver ?? LiquidPreviewDriver(at: now)
        let disc = driver.tick(at: now)
        var motion = motion.flatMap { $0.preset == preset ? $0 : nil } ?? LiquidMotion(preset: preset, discAngle: disc, at: now)
        motion.advance(to: disc, at: now)
        self.driver = driver
        self.motion = motion
        return motion.frame(reduceMotion: reduceMotion)
    }

    func select(_ phase: LiquidPreviewPhase, at now: Double) { driver?.select(phase, at: now) }
    func setAuto(_ on: Bool, at now: Double) { driver?.setAuto(on, at: now) }
}
#endif
