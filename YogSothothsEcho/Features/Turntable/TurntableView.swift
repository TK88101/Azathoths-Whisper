import RemoteProtocol
import SwiftUI

/// 唱機畫面（F-V-01〜06；sprint-5-detail.md §4.2–§4.7）。只畫與轉送手勢；判斷全在純值與 TurntableViewModel。
/// 單一 DragGesture 判定意圖：移動超過 tapSlop＝甩動；沒移動就放開＝點擊（唱片／封面套／其他）。唱機不提供拖唱頭（CR-019）
struct TurntableView: View {
    let model: TurntableViewModel
    let onClose: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gesture: GestureMode = .undecided
    @State private var blurred: UIImage?
    /// S6：進場放好唱片後 VoiceOver 焦點到唱片（S5 D2 規則，fullScreenCover 改殼層內一層後自己做）
    @AccessibilityFocusState private var recordFocused: Bool

    private enum GestureMode { case undecided, swipe, ignored }
    private static let tapSlop: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let container = CGRect(origin: .zero, size: proxy.size)
            let layout = TurntableLayout(container: container, fullCover: model.sleeve.isFullCover, skin: model.skin)
            ZStack(alignment: .topLeading) {
                background(size: proxy.size)
                scene(layout, width: proxy.size.width)
                TurntableOverlay(model: model, onClose: onClose)
            }
            .contentShape(Rectangle())
            .gesture(sceneGesture(layout))
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: Text("Previous")) { Task { await model.nowPlaying.previous() } }
            .accessibilityAction(named: Text("Next")) { Task { await model.nowPlaying.next() } }
        }
        .ignoresSafeArea()
        // 依據含 token：曲庫清單晚於事件到達、或封面換版時重新載入
        .task(id: artworkKey) { await model.loadArtwork(albumID: model.nowPlaying.clock?.event.albumID) }
        .task(id: model.backgroundSource.map(ObjectIdentifier.init)) { await updateBlur() }
        .onChange(of: model.nowPlaying.isConnected) { _, connected in
            if !connected { model.connectionLost() }
        }
        .onAppear { model.setDisplayScale(displayScale) }
        .onDisappear { model.cancelTransition() }   // 第二道：close() 當下已收斂 G7（§4.8）
        .onChange(of: model.layer) { _, layer in if layer == .shown { recordFocused = true } }
        // 原版：浮層隱藏時沉浸式（系統列一起藏）
        .statusBarHidden(!model.overlay.isVisible)
        .accessibilityIdentifier(AccessibilityID.turntable)
    }

    // MARK: 背景

    @ViewBuilder private func background(size: CGSize) -> some View {
        ZStack {
            if let blurred {
                Image(uiImage: blurred).resizable().scaledToFill()
            } else if let fallback = VinylAssets.image(.blurBackground) {
                Image(uiImage: fallback).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(white: 0.35), Color(white: 0.15)], startPoint: .top, endPoint: .bottom)
            }
            Color.black.opacity(TurntableBackground.dimOpacity)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
    }

    private func updateBlur() async {
        guard let source = model.backgroundSource else { return }
        let result = await Task.detached(priority: .utility) { TurntableBackground.blurred(source) }.value
        guard !Task.isCancelled else { return }
        blurred = result
    }

    // MARK: 場景

    /// 主組（封面套＋唱片）、轉場中的新組、唱臂。唱臂一律在唱片之上：原版甩動時把唱臂降到 0 是因為唱片會一起動，
    /// 這裡唱片不隨甩動移動，降層會穿模（#5-1 G5）。唱片在封套下（zIndex 0.4）只發生在收碟／換封套／抽碟期間
    private func scene(_ layout: TurntableLayout, width: CGFloat) -> some View {
        let p = model.scenePresentation
        let travel = width * SwipeTransition.maxOffsetWidthFactor
        return ZStack(alignment: .topLeading) {
            armBase(layout).zIndex(0)
            group(model.groupDeck, layout, slot: p.outgoingSlot, recordBelow: p.outgoingRecordBelowCover,
                  sleeveAside: p.outgoingSleeveAside, travel: p.outgoingOffset * travel,
                  drag: model.swipe.coverOffset(containerWidth: width), animation: phaseAnimation(incoming: false))
            if p.showsIncomingGroup, let incoming = model.incomingDeck {
                group(incoming, layout, slot: p.incomingSlot, recordBelow: p.incomingRecordBelowCover,
                      sleeveAside: p.incomingSleeveAside, travel: p.incomingOffset * travel,
                      drag: 0, animation: phaseAnimation(incoming: true))
            }
            armBaseMiddle(layout)
                .zIndex(1.2)
            tonearm(layout)
                .zIndex(1.5)
            armBaseOverlay(layout)
                .zIndex(1.6)
        }
        // 序列圖皮膚依版面縮放解碼（同皮膚同縮放不重解；classic＝釋放）
        .task(id: "\(model.skin.spec.id)|\(layout.scale)") { model.prepareSprites(layoutScale: layout.scale) }
        .animation(.easeInOut(duration: 0.4), value: model.sleeve)
    }

    /// 一組封面套＋唱片：`travel`＝離場／進場位移（整組），`drag`＝拖動中只有封面跟手；
    /// `sleeveAside`＝封套沿斜軸讓開（v2.1 T6）。唱片不加遮罩——投影在唱片框外，遮罩會把它裁成直邊（實機截圖）
    @ViewBuilder
    private func group(_ deck: TurntableDeck, _ layout: TurntableLayout, slot: SwipeTransition.RecordSlot, recordBelow: Bool,
                       sleeveAside: Bool, travel: CGFloat, drag: CGFloat, animation: Animation?) -> some View {
        let sleeveShift = model.sleeve.offsetFraction * layout.cover.width
        let aside = sleeveAside ? layout.sleeveAsideOffset : .zero
        let origin = layout.recordOrigin(slot)
        cover(deck, layout)
            .rotationEffect(.degrees(model.sleeve.rotationDegrees))
            .offset(x: layout.cover.minX + sleeveShift + aside.dx + travel + drag, y: layout.cover.minY + aside.dy)
            .zIndex(model.sleeve.zIndex)
            .animation(animation, value: model.swipe.phase)
            .animation(entranceAnimation, value: model.layer)
        record(deck, layout)
            .offset(x: origin.x + travel, y: origin.y)
            .zIndex(recordBelow ? 0.4 : 1)
            .animation(animation, value: model.swipe.phase)
            .animation(entranceAnimation, value: model.layer)
    }

    /// 進場抽唱片各段（S6 §4.8）以該段時長 easeInOut；其他時候不套
    private var entranceAnimation: Animation? {
        guard case .entering(let phase) = model.layer else { return nil }
        return .easeInOut(duration: TurntableEntrance.duration(of: phase, reduceMotion: model.layerReduceMotion).secondsValue)
    }

    /// 各段以該段時長 easeInOut；換封套段新組比舊組晚 110 ms 起步（重疊）；idle、拖動、等待不套動畫
    private func phaseAnimation(incoming: Bool) -> Animation? {
        guard let seconds = model.swipe.timedDuration?.secondsValue else { return nil }
        guard case .exchanging = model.swipe.phase else { return .easeInOut(duration: seconds) }
        let leg = seconds * SwipeTransition.exchangeLegFraction
        return incoming ? .easeInOut(duration: leg).delay(seconds - leg) : .easeInOut(duration: leg)
    }

    /// 換專輯（Reduce Motion 的交叉淡化）時以 albumID 換身分，淡入淡出
    private func cover(_ deck: TurntableDeck, _ layout: TurntableLayout) -> some View {
        // S6 D13：投影＋內陰影（投影在 clipShape 之外、屬於封套本身，跟著傾斜／全封面／換片／進場一起動）
        SleeveFace(image: deck.cover, placeholder: TurntableMetrics.coverPlaceholderColor.color, size: layout.cover.size,
                   cornerRadius: 5 * layout.scale * TurntableMetrics.recordSize / 306,
                   shadow: .turntable(scale: layout.scale, containerWidth: layout.container.width))
        .accessibilityElement()
        .accessibilityLabel(Text("Album cover"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tapSleeve() }
        .id(deck.albumID)
        .transition(.opacity)
    }

    /// 換曲（同專輯換標籤、Reduce Motion 淡化）時以 trackID 換身分，淡入淡出
    private func record(_ deck: TurntableDeck, _ layout: TurntableLayout) -> some View {
        TimelineView(.animation(paused: model.nowPlaying.clock?.event.state != .playing)) { timeline in
            VinylRecordView(side: layout.record.width, style: deck.style, splash: deck.splash, colors: deck.colors, label: deck.label,
                            angle: model.recordAngle(at: timeline.date.timeIntervalSinceReferenceDate), tuning: Self.tuning, swirl: deck.swirl)
        }
        .scaleEffect(layout.recordVisibleScale)
        .accessibilityElement()
        .accessibilityLabel(Text(model.nowPlaying.clock?.event.state == .playing ? "Pause" : "Play"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(AccessibilityID.turntableRecord)
        .accessibilityFocused($recordFocused)
        .accessibilityAction { Task { await model.tapRecord() } }
        .id(deck.trackID)
        .transition(.opacity)
    }

    /// 磨砂盤可調量：Release 恆 standard；DEBUG 讀調整面板的單一 store（v2.1 T8）
    @MainActor private static var tuning: TransparentTuning {
        #if DEBUG
        TransparentTuningStore.shared.tuning
        #else
        .standard
        #endif
    }

    /// 繪製方式由皮膚決定（CR-034 加新 case 時編譯器會逼這裡處理）
    private func armBase(_ layout: TurntableLayout) -> some View {
        Group {
            switch layout.skin.spec.rendering {
            case .classicImages: classicArmBase(layout)
            case .spriteSequence: spriteStill(model.sprites.base)
            }
        }
        .frame(width: layout.armBase.width, height: layout.armBase.height)
        .offset(x: layout.armBase.minX, y: layout.armBase.minY)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func classicArmBase(_ layout: TurntableLayout) -> some View {
        Group {
            if let image = VinylAssets.image(.armBase) {
                Image(uiImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: 12 * layout.scale).fill(Color(white: 0.25))
            }
        }
    }

    /// 底座上層（序列圖皮膚；畫在唱臂之上）；classic 沒有
    @ViewBuilder private func armBaseOverlay(_ layout: TurntableLayout) -> some View {
        if let rect = layout.armBaseOverlay {
            spriteStill(model.sprites.overlay)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .accessibilityHidden(true)
        }
    }

    /// 底座中層（增補 B；唱片 1 之上、唱臂 1.5 之下：刻度環蓋唱片、臂夾在唱臂下）；沒有中層的皮膚不畫
    @ViewBuilder private func armBaseMiddle(_ layout: TurntableLayout) -> some View {
        if let rect = layout.armBaseMiddle {
            spriteStill(model.sprites.middle)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func spriteStill(_ image: CGImage?) -> some View {
        if let image {
            Image(decorative: image, scale: 1).resizable()
        } else {
            Color.clear
        }
    }

    private func tonearm(_ layout: TurntableLayout) -> some View {
        TimelineView(.animation(paused: model.nowPlaying.clock?.event.state != .playing)) { _ in
            let angle = model.armAngle()
            switch layout.skin.spec.rendering {
            case .classicImages:
                classicArmImage(layout)
                    .frame(width: layout.arm.width, height: layout.arm.height)
                    .rotationEffect(.degrees(layout.skin.armRotation(forAngle: angle)), anchor: Self.anchor(layout.skin.spec.arm))
                    .offset(x: layout.arm.minX, y: layout.arm.minY)
            case .spriteSequence:
                SpriteTonearmView(angle: angle, layout: layout, sprites: model.sprites)
            }
        }
        // 落臂／抬臂：linear 1 s（spec），甩動抬臂 350 ms（與煞停同步）。播放中的進度是每幀算出的連續值，不套動畫（每幀重啟會追不上）
        .animation(.linear(duration: model.swipe.armLifted ? SwipeTransition.liftDuration.secondsValue : 1), value: armIsResting)
        #if DEBUG
        // 附錄 F 卡頓診斷：落臂／抬臂期間記錄取幀與幀間隔
        .onChange(of: armIsResting) {
            SpriteTrace.current?.armMotionStarted(duration: model.swipe.armLifted ? SwipeTransition.liftDuration.secondsValue : 1)
        }
        #endif
        .accessibilityElement()
        .accessibilityLabel(Text("Tonearm"))
        .accessibilityValue(Text(verbatim: PlaybackPresentation.time(model.nowPlaying.position() ?? 0)))
        .accessibilityIdentifier(AccessibilityID.turntableArm)
    }

    private var artworkKey: String {
        let albumID = model.nowPlaying.clock?.event.albumID ?? ""
        return albumID + "|" + (model.nowPlaying.currentAlbum?.artworkToken ?? "")
    }

    private var armIsResting: Bool { model.armAngle() == model.skin.restDegrees }

    private static func anchor(_ frame: ArtworkFrame) -> UnitPoint {
        UnitPoint(x: frame.pivotFraction.x, y: frame.pivotFraction.y)
    }

    @ViewBuilder private func classicArmImage(_ layout: TurntableLayout) -> some View {
        if let image = VinylAssets.image(.arm) {
            Image(uiImage: image).resizable()
        } else {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4 * layout.scale).fill(Color(white: 0.75))
                    .frame(width: 10 * layout.scale)
                Circle().fill(Color(white: 0.5)).frame(width: 60 * layout.scale, height: 60 * layout.scale)
                    .offset(y: 6 * layout.scale)
            }
        }
    }

    // MARK: 手勢

    private func sceneGesture(_ layout: TurntableLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in changed(value) }
            .onEnded { value in ended(value, layout) }
    }

    private func changed(_ value: DragGesture.Value) {
        if gesture == .undecided {
            guard hypot(value.translation.width, value.translation.height) > Self.tapSlop else { return }
            gesture = .swipe
        }
        guard gesture == .swipe else { return }
        model.swipeChanged(value.translation)
        if model.swipe.phase == .ignoringVertical { gesture = .ignored }
    }

    /// 甩動交給狀態機（過閾值＝送指令開始轉場；轉場中再甩＝加速）；沒移動就放開＝點擊
    private func ended(_ value: DragGesture.Value, _ layout: TurntableLayout) {
        defer { gesture = .undecided }
        switch gesture {
        case .swipe, .ignored:
            model.swipeEnded(value.translation, reduceMotion: reduceMotion)
        case .undecided:
            tap(at: value.location, layout)
        }
    }

    /// 依畫面上實際的上下關係判定（TurntableHitTest）；甩動轉場中一律忽略
    private func tap(at point: CGPoint, _ layout: TurntableLayout) {
        guard !model.swipe.isBusy else { return }
        let target = TurntableHitTest.classify(point, layout: layout, sleeve: model.sleeve, armAngle: model.armAngle())
        guard model.handleTap(target, animate: { withAnimation(.spring(duration: 0.4), $0) }) else { return }
        finishSleeveMidway()
    }

    /// 無障礙動作「點封套」：與手指點擊同一個分派
    private func tapSleeve() {
        guard model.handleTap(.cover) else { return }
        finishSleeveMidway()
    }

    /// 封套接受點擊後 400 ms 交棒給 ViewModel
    private func finishSleeveMidway() {
        Task {
            try? await Task.sleep(for: .milliseconds(CoverSleeveState.phaseMilliseconds))
            model.sleeveMidwayFinished()
        }
    }
}
