import SwiftUI

/// 唱片（F-V-02／F-V-03；sprint-5-detail.md §4.6）：投影 → 樣式層（只有圖案層與標籤隨 `angle` 轉，含溝槽與高光的 base 不轉）→
/// 外沿光環 → 文字標籤 → 中心孔。尺寸全部以 `side`（＝474s）等比換算
struct VinylRecordView: View {
    let side: CGFloat
    let style: RecordStyle
    let splash: SplashStyle
    let colors: AlbumColors
    let label: TurntableViewModel.Label
    let angle: Double
    /// 磨砂盤的主色與霧濃淡（v2.1 T8）；Release 恆 `.standard`
    var tuning: TransparentTuning = .standard
    /// SWIRL 系列的花紋配方（CR-037）；其他樣式＝nil
    var swirl: SwirlRecipe? = nil
    var swirlStore: SwirlArtworkStore = .shared

    /// 烘焙邊長上限（M1 一張 4 MiB；顯示時放大，花紋本身柔和）
    static let swirlBakeLimit = 1024

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var swirlKey: SwirlArtworkStore.Key? {
        guard let swirl else { return nil }
        let palette = SwirlPalette.resolve(swirl, colors: colors, reduceTransparency: reduceTransparency)
        return SwirlArtworkStore.Key(recipe: swirl, colors: palette, side: min(Self.swirlBakeLimit, max(1, Int((side * displayScale).rounded()))))
    }

    private var shadowOpacity: Double {
        if let key = swirlKey { return key.colors.opacity < 1 ? 0.08 : 0.2 }
        return transparentFinish?.shadowOpacity ?? 0.2
    }

    private var s: CGFloat { side / TurntableMetrics.recordSize }

    /// 外沿光環（角度漸層從 3 點鐘順時針）：白光自 3 點鐘起漸亮、6 點鐘最亮；頭尾同為透明，
    /// 繞回 3 點鐘不會有白色斷頭（#5-1 使用者實機回饋：原版起點即全亮，接縫處一截白色尾巴）
    static let rimStops: [Gradient.Stop] = [.init(color: .clear, location: 0),
                                            .init(color: .white.opacity(0.4), location: 0.25),
                                            .init(color: .clear, location: 0.4),
                                            .init(color: .black.opacity(0.15), location: 0.75),
                                            .init(color: .clear, location: 1)]

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.displayScale) private var displayScale

    /// TRANSPARENT 以外一律 nil
    private var transparentFinish: TransparentFinish? {
        style == .transparent ? TransparentFinish.resolve(reduceTransparency: reduceTransparency) : nil
    }

    var body: some View {
        let finish = transparentFinish
        let usesMaterial = finish?.usesMaterial == true
        ZStack {
            // 磨砂層必須在 drawingGroup 之外：合成圖層內的 Material 拿不到後面的封套與背景
            // 透明盤是乳白透光：材質固定淺色版本（深色模式的 Material 會讓盤面發黑）
            if usesMaterial {
                Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .light)
                    .opacity(tuning.look(for: TransparentFinish.tint(for: colors)).material)
            }
            ZStack {
                styleLayers(finish)
                rotationCue(RotationCue.cue(style: style, finish: finish), finish: finish)
                Circle().strokeBorder(AngularGradient(stops: Self.rimStops, center: .center), lineWidth: 3 * s)
                if usesMaterial { Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.2 * s) }
                labelView.rotationEffect(.degrees(angle))
                centerHole
            }
            .drawingGroup()
        }
        .frame(width: side, height: side)
        // 投影放在合成圖層之外：drawingGroup 的範圍只有唱片大小，往下偏移的模糊陰影放在裡面會被切出一條直邊（#5-1 實機發現）
        .background(Circle().fill(Color.black.opacity(shadowOpacity)).blur(radius: 12 * s).offset(y: 12 * s))
        // SWIRL：顯示期間登記使用中（不被淘汰）；鍵改變（換歌、換尺寸、換色、Reduce Transparency）即換一張
        .task(id: swirlKey) {
            if let key = swirlKey { await swirlStore.use(key) }
        }
    }

    /// SWIRL 系列（CR-037 §4.4）：烘好的盤面（底色＋花紋，已含不透明度）只旋轉；未就緒先畫底色，就緒後淡入（Reduce Motion＝直接出現）
    @ViewBuilder private func swirlLayers() -> some View {
        if let key = swirlKey {
            let state = swirlStore.state(for: key)
            ZStack {
                if case .ready(let face) = state {
                    Image(decorative: face.image, scale: 1).resizable()
                        .rotationEffect(.degrees(angle))
                        .transition(reduceMotion ? .identity : .opacity)
                } else {
                    swirlBaseFill(key.colors)
                }
            }
            .animation(reduceMotion ? nil : .easeIn(duration: 0.2), value: state?.isReady == true)
            base(.screen)
        }
    }

    @ViewBuilder private func swirlBaseFill(_ palette: SwirlColors) -> some View {
        switch palette.base {
        case .solid(let color):
            Circle().fill(color.color.opacity(palette.opacity))
        case .gradient(let from, let to):
            Circle().fill(LinearGradient(colors: [from.color, to.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(palette.opacity)
                .rotationEffect(.degrees(angle))
        }
    }

    @ViewBuilder private func styleLayers(_ finish: TransparentFinish?) -> some View {
        switch style {
        case .classic, .random:
            base(.normal)
        case .transparent:
            switch finish ?? .frosted {
            case .frosted:
                // 磨砂：材質上疊主色（主色近黑改用輔色、都近黑不疊色，v2.1 T9）；溝紋用 screen：素材的黑底不壓暗，只留亮的溝線與高光。
                // 點與放射紋在 rotationCue（程序生成，取代 noise 位圖）
                if let tint = TransparentFinish.tint(for: colors) {
                    Circle().fill(tint.color.opacity(tuning.look(for: tint).frostedTint))
                }
                base(.screen).opacity(0.35)
            case .opaque:
                Circle().fill(TransparentFinish.opaqueFill(for: colors).color)
                base(.softLight).opacity(0.35)
            }
        case .splash:
            let pair = splash.colors(colors)
            Circle().fill(colors.primary.color.opacity(0.65))
            spinning(.pattern2, tint: pair.bottom, opacity: 0.8)
            spinning(.pattern1, tint: pair.top, opacity: 1)
            base(.screen)
        case .marble:
            let layer = MarbleLayer(luminance: colors.primary.luminance)
            Circle().fill(colors.primary.color.opacity(0.8))
            spinning(.marble, tint: nil, opacity: layer.alpha)
                .blendMode(layer.blend == .colorBurn ? .colorBurn : .hardLight)
            base(.screen)
        case .smoke, .streak, .flake, .chunk:
            swirlLayers()
        }
    }

    /// 溝槽與高光：不旋轉；沒素材時畫深灰圓＋同心溝紋
    @ViewBuilder private func base(_ blend: BlendMode) -> some View {
        if let image = VinylAssets.image(.base) {
            Image(uiImage: image).resizable().blendMode(blend)
        } else {
            ZStack {
                Circle().fill(Color(white: 0.08))
                ForEach(1..<9) { ring in
                    Circle().stroke(Color.white.opacity(0.06), lineWidth: 1).padding(CGFloat(ring) * side / 22)
                }
            }
            .blendMode(blend)
        }
    }

    /// 轉動參照（§4.2b v2.0）：與標籤共用同一個 `angle`，整組只旋轉一次；遮罩依像素邊長快取
    @ViewBuilder private func rotationCue(_ cue: RotationCue?, finish: TransparentFinish?) -> some View {
        if let cue {
            let pixelSide = max(1, Int((side * displayScale).rounded()))
            ZStack {
                if cue == .sheen {
                    Circle().fill(RotationSheen.gradient)
                        .mask(RingShape(innerFraction: RadialField.innerRadius).fill(style: FillStyle(eoFill: true)))
                } else {
                    if cue == .radialWithSpecks {
                        Rectangle().fill(TransparentFinish.speckColor(for: TransparentFinish.tint(for: colors) ?? .white).color)
                            .mask(Image(uiImage: RotationCueMasks.specks(pixelSide: pixelSide)).resizable())
                            .opacity(TransparentFinish.speckOpacity)
                    }
                    Rectangle().fill(RotationCue.rayColor(finish: finish, colors: colors).color)
                        .mask(Image(uiImage: RotationCueMasks.rays(pixelSide: pixelSide)).resizable())
                }
            }
            .clipShape(Circle())
            .rotationEffect(.degrees(angle))
        }
    }

    /// 隨唱片轉的圖案層；tint＝以顏色填滿圖案形狀（SrcIn）
    @ViewBuilder private func spinning(_ name: VinylAssets.Name, tint: RGBColor?, opacity: Double) -> some View {
        if let image = VinylAssets.image(name) {
            Group {
                if let tint {
                    Rectangle().fill(tint.color).mask(Image(uiImage: image).resizable())
                } else {
                    Image(uiImage: image).resizable()
                }
            }
            .clipShape(Circle())
            .opacity(opacity)
            .rotationEffect(.degrees(angle))
        }
    }

    /// 標籤（§4.2b v1.4）：歌名＋歌手在中心孔上方；印字（環狀字、品牌字、條碼）由 LabelRing 依 LabelLayout 畫
    private var labelView: some View {
        let diameter = Self.labelDiameter * s
        return ZStack(alignment: .top) {
            Circle().fill(colors.primary.color)
            LabelRing(diameter: diameter, color: colors.text.color)
            VStack(spacing: diameter * 0.012) {
                Text(verbatim: label.title).font(.system(size: LabelLayout.titleFont * diameter, weight: .bold))
                Text(verbatim: label.artist).font(.system(size: LabelLayout.artistFont * diameter, weight: .medium)).opacity(0.7)
            }
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .frame(width: LabelLayout.textWidth * diameter, height: (0.5 + LabelLayout.titleBlockBottom) * diameter, alignment: .bottom)
            .foregroundStyle(colors.text.color)
        }
        .frame(width: diameter, height: diameter)
    }

    static let labelDiameter: CGFloat = 214

    @ViewBuilder private var centerHole: some View {
        if let center = VinylAssets.image(.center) {
            Image(uiImage: center).resizable().frame(width: 10 * s, height: 10 * s)
        } else {
            Circle().fill(Color.black).frame(width: 10 * s, height: 10 * s)
        }
    }
}

extension RGBColor {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}
