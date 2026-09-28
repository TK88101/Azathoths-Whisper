import AppKit
import SwiftUI
import Testing

@testable import AzathothsWhisper

// S9（docs/plans/2026-09-26-coverflow-follow-playback-slide.md §8.3）：條帶內兩段——條帶／View 複本與記錄器
// （量測本體在 `CoverFlowSlideSpikeS9Tests.swift`）
//
// 量測碼，預設關閉：只在 `TEST_RUNNER_AZW_SPIKE_S9=1` 時執行，結果印成 `S9 …` 行寫進該計劃 §8.3。
// S8 否證了「VM 兩段觸發」：第二段與 SwiftUI 提交第一段之間沒有順序保證。S9 把兩步都放進條帶——
// 條帶在**同一次更新**內收到新牌組＋平移指令，自己先無動畫退回舊中心、再帶動畫滑到目標。
// 不改生產碼：`S9Strip`／`S9View` 是 `CoverFlowStrip`／`CoverFlowView` 的複本，只多出平移指令；
// VM、卡片內容、binding setter（→ `scrollPositionDidChange`）皆為 production。
// 量法同 S8：逐幀取樣 NSScrollView 捲動原點（平移）、落定對齊、binding 原始回寫（非目標值）；
// 另記條帶幾何的「正中」事件序列（舊中心被重新置中、目標被置中兩次＝畫面閃過一次別的位置）。
// 牌組形狀三種（`S9Shape`）：v4 的 staged（舊中心位次改變，需要第一段退回）與兩種「舊中心位次不變」的過渡牌組；
// 後兩者在落定後另量「換上正式牌組」這一步會不會停歪或閃動。
//
// 縮小矩陣：`TEST_RUNNER_AZW_SPIKE_S9_ONLY=movingWindow,reader`（逗號分隔，全部命中才跑）；
// 步數：`TEST_RUNNER_AZW_SPIKE_S9_STEPS=3`（預設 20）。

let s9ViewSize = CGSize(width: 1192, height: 620)
/// 與 `CoverFlowView.itemWidth` 同值（後者隔離在 MainActor，全域常數讀不到；量測開頭會比對）
let s9ItemWidth: CGFloat = 260
let s9Stride = s9ItemWidth * 0.58     // itemWidth + spacing（−0.42 itemWidth）
let s9ViewportSpace = "coverflow.viewport.s9"

/// 條帶收到的一次平移指令：與新牌組在同一次更新內給
struct S9SlideRequest<ID: Hashable & Sendable>: Equatable, Sendable {
    let generation: Int
    let from: ID
    let to: ID
}

/// 第二段（帶動畫滑到目標）在條帶內的觸發時機
enum S9Trigger: String, CaseIterable, Sendable {
    /// 與第一段同一個 onChange 內緊接著做
    case inline
    /// 第一段後改條帶自己的 @State，由下一輪更新的 onChange 做
    case stateHop
    /// 第一段後排一個主執行緒工作（排在 SwiftUI **已處理**換牌之後；S8 是排在之前）
    case taskHop
    /// taskHop＋確認舊中心已在幾何正中才做（§3.7 未提交偵測）；250ms 未確認＝無動畫直達
    case geometryGate
}

/// 第二段的捲動手段
enum S9Mechanism: String, CaseIterable, Sendable {
    /// `withAnimation { reader.scrollTo(target) }`
    case reader
    /// `withAnimation { centerID = target }`（經 production binding setter）
    case binding
    /// 不動捲動位置：換牌當下以內容位移抵銷版面位移（畫面不變），再把位移動畫歸零（只配 `flip` 形狀）
    case translation
    /// 同 `translation`，另把位移值餵進每張卡的**疊放與正中判定**。
    /// 旋轉／縮放（`visualEffect`）不餵：它的幾何本來就含 `.offset`，再加會算兩次（實測傾斜峰值 0.77 對 0.40）
    case awareTranslation

    var isTranslation: Bool { self == .translation || self == .awareTranslation }
}

enum S9Direction: String, CaseIterable, Sendable {
    case next
    case previous
}

enum S9Shape: String, CaseIterable, Sendable {
    /// v4 §3.2 的 staged（S8 的形狀）：換上新窗口、舊中心留著——舊中心在牌組中的位次改變，需要第一段「退回」
    case movingWindow
    /// 過渡期間沿用原牌組（卡 ID 序列不變），落定後才換上新窗口
    case heldWindow
    /// 過渡期間在舊中心旁放進**新身分**的目標卡、舊中心位次不變
    /// （next＝右側為空時尾端追加；previous＝左鄰換身分），落定後才換上新窗口
    case insertedTarget
    /// 基線：現行 production 的換歌（同一次更新內換上新窗口＋設中心、不帶動畫、沒有平移指令）
    case direct
    /// 與基線同樣直接換牌＋設中心（捲動位置數值不變），舊中心留在牌組裡；平移由內容位移動畫呈現
    case flip
    /// 同 flip，但目標卡是**新身分**的卡（next＝退回模式左側已滿、尾端追加；previous＝往回跳當下的 `o:` 中心，
    /// 右側只剩暫留的舊中心）
    case flipInserted
    /// 同 heldWindow，但落定後換上的牌組**保住正中卡的位次**（左側多留／少放幾張），不需要改捲動位置
    case keptIndex

    var isFlip: Bool { self == .flip || self == .flipInserted }
}

struct S9Case: Sendable, CustomTestStringConvertible {
    let shape: S9Shape
    let trigger: S9Trigger
    let mechanism: S9Mechanism
    let direction: S9Direction

    var name: String { "\(shape.rawValue)/\(trigger.rawValue)/\(mechanism.rawValue)/\(direction.rawValue)" }
    var testDescription: String { name }

    static let selected: [S9Case] = {
        // 分號分隔多組條件、組內逗號分隔：任一組全部命中就跑
        let groups = (ProcessInfo.processInfo.environment["AZW_SPIKE_S9_ONLY"] ?? "")
            .split(separator: ";").map { $0.split(separator: ",").map(String.init) }
        var all: [S9Case] = []
        for shape in S9Shape.allCases {
            for trigger in S9Trigger.allCases {
                for mechanism in S9Mechanism.allCases {
                    for direction in S9Direction.allCases {
                        // 基線不經平移指令，觸發與手段無關：只留一組
                        if shape == .direct, trigger != .inline || mechanism != .binding { continue }
                        // 內容位移只配 flip 形狀，且不分觸發時機
                        if shape.isFlip != mechanism.isTranslation { continue }
                        if shape.isFlip, trigger != .inline { continue }
                        if shape == .flipInserted, mechanism != .awareTranslation { continue }
                        all.append(S9Case(shape: shape, trigger: trigger, mechanism: mechanism, direction: direction))
                    }
                }
            }
        }
        return all.filter { testCase in
            let parts = Set(testCase.name.split(separator: "/").map(String.init))
            return groups.isEmpty || groups.contains { $0.allSatisfy(parts.contains) }
        }
    }()
}

struct S9CentringEvent {
    let id: String
    let isCentred: Bool
    let tick: Int
}

@MainActor
final class S9Recorder {
    /// scrollPosition binding 的每次原始回寫（含條帶自己以 binding 手段寫的目標值）
    var rawWrites: [String?] = []
    /// 條帶依佈局幾何判定此刻在正中的卡（與 production 的可點判定同一條路徑）
    var centredIDs: Set<String> = []
    /// 每次「正中」判定改變（含新卡的初值），附當時的 tick
    var centringEvents: [S9CentringEvent] = []
    /// 主 runloop 每次進入等待前（order 最大＝排在 Core Animation 提交之後）加一：
    /// 同一個 tick 內的事件屬於同一次畫面提交，跨 tick 的中間狀態才會被畫出來
    private(set) var tick = 0
    private var observer: CFRunLoopObserver?

    func startTicking() {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.tick += 1 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    func stopTicking() {
        guard let observer else { return }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = nil
    }
    /// 平移動畫的完成回呼（`withAnimation(_:completionCriteria:_:completion:)`）：第幾次指令、何時
    var completions: [(generation: Int, at: ContinuousClock.Instant)] = []
    var gateImmediate = 0
    var gateWaited = 0
    var gateTimedOut = 0
}

@MainActor
@Observable
final class S9Driver {
    let model: CoverFlowViewModel
    var slide: S9SlideRequest<String>?
    @ObservationIgnored let recorder = S9Recorder()

    init(model: CoverFlowViewModel) {
        self.model = model
    }
}

/// 條帶自己記的「哪些卡此刻在幾何正中」，與等待某張回到正中的一次性回呼。不進 Observation：改它不重繪
@MainActor
final class S9Gate<ID: Hashable> {
    private(set) var centred: Set<ID> = []
    private var armed: (id: ID, fire: () -> Void)?

    func report(_ id: ID, isCentred: Bool) {
        if isCentred { centred.insert(id) } else { centred.remove(id) }
        guard isCentred, let waiting = armed, waiting.id == id else { return }
        armed = nil
        waiting.fire()
    }

    /// - Returns: 當下就已在正中（立即觸發）
    func arm(waitingFor id: ID, fire: @escaping () -> Void) -> Bool {
        if centred.contains(id) {
            fire()
            return true
        }
        armed = (id, fire)
        return false
    }

    /// - Returns: 解除前是否仍在等
    func disarm() -> Bool {
        defer { armed = nil }
        return armed != nil
    }
}

struct S9StripInput<ID: Hashable & Sendable>: Equatable {
    let ids: [ID]
    let slide: S9SlideRequest<ID>?
}

// MARK: - 條帶複本（＝CoverFlowStrip＋平移指令）

struct S9Strip<Item: Identifiable, Content: View>: View where Item.ID: Sendable {
    let items: [Item]
    let itemWidth: CGFloat
    @Binding var centerID: Item.ID?
    let slide: S9SlideRequest<Item.ID>?
    let trigger: S9Trigger
    let mechanism: S9Mechanism
    let animation: Animation
    let recorder: S9Recorder
    @ViewBuilder let content: (Item, Bool) -> Content

    @State private var hop: S9SlideRequest<Item.ID>?
    /// 內容位移已開始歸零的那次指令
    @State private var releasedGeneration = 0
    @State private var gate = S9Gate<Item.ID>()

    private static var gateTimeout: Duration { .milliseconds(250) }

    private var geometry: CoverFlowGeometry {
        CoverFlowGeometry(itemWidth: itemWidth)
    }

    /// 內容位移：由輸入同步算出，與換牌在同一次更新生效。指令剛到＝把目標卡推回它「平移前」的位置
    private var translation: CGFloat {
        guard mechanism.isTranslation, let slide, slide.generation != releasedGeneration,
              let from = items.firstIndex(where: { $0.id == slide.from }),
              let to = items.firstIndex(where: { $0.id == slide.to })
        else { return 0 }
        return CGFloat(to - from) * (itemWidth + geometry.spacing)
    }

    var body: some View {
        GeometryReader { outer in
          ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: geometry.spacing) {
                    ForEach(items) { item in
                        S9StripCell(
                            geometry: geometry,
                            viewportMidX: outer.frame(in: .named(s9ViewportSpace)).midX,
                            shift: mechanism == .awareTranslation ? translation : 0,
                            onCentred: { isCentred in gate.report(item.id, isCentred: isCentred) }
                        ) { isCentered, _ in
                            content(item, isCentered)
                                .frame(width: itemWidth)
                                .visualEffect { effect, proxy in
                                    let d = geometry.normalizedDistance(
                                        itemMidX: proxy.frame(in: .named(s9ViewportSpace)).midX,
                                        viewportMidX: outer.frame(in: .named(s9ViewportSpace)).midX
                                    )
                                    return effect
                                        .rotation3DEffect(
                                            .degrees(geometry.rotationDegrees(forDistance: d)),
                                            axis: (x: 0, y: 1, z: 0),
                                            anchor: geometry.anchorIsTrailing(forDistance: d)
                                                ? .trailing : .leading,
                                            perspective: geometry.perspective
                                        )
                                        .scaleEffect(geometry.scale(forDistance: d))
                                }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollTargetLayout()
                .offset(x: translation)
            }
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(.horizontal, geometry.edgePadding(viewWidth: outer.size.width))
            .scrollPosition(id: $centerID, anchor: .center)
            .scrollIndicators(.hidden)
            // 換牌與平移指令併成一個觀察值：同一次更新內兩者都變時，只走平移分支、順序由這裡決定
            .onChange(of: S9StripInput(ids: items.map(\.id), slide: slide)) { old, new in
                if mechanism.isTranslation, let request = new.slide, request != old.slide {
                    // 與 production 換牌相同的明確捲回（捲動位置數值不變），再把內容位移動畫歸零
                    if let centerID { reader.scrollTo(centerID, anchor: .center) }
                    withAnimation(animation, completionCriteria: .logicallyComplete) {
                        releasedGeneration = request.generation
                    } completion: {
                        recorder.completions.append((request.generation, ContinuousClock.now))
                    }
                    return
                }
                if let request = new.slide, request != old.slide {
                    // 第一段：無動畫退回舊中心
                    reader.scrollTo(request.from, anchor: .center)
                    startSecondStage(request, reader: reader)
                    return
                }
                guard new.ids != old.ids, let centerID else { return }
                reader.scrollTo(centerID, anchor: .center)
            }
            .onChange(of: hop) { _, request in
                guard let request else { return }
                animate(request, reader: reader)
            }
          }
        }
        .coordinateSpace(.named(s9ViewportSpace))
    }

    private func startSecondStage(_ request: S9SlideRequest<Item.ID>, reader: ScrollViewProxy) {
        switch trigger {
        case .inline:
            animate(request, reader: reader)
        case .stateHop:
            hop = request
        case .taskHop:
            Task { @MainActor in animate(request, reader: reader) }
        case .geometryGate:
            Task { @MainActor in
                let immediate = gate.arm(waitingFor: request.from) { animate(request, reader: reader) }
                if immediate {
                    recorder.gateImmediate += 1
                    return
                }
                try? await Task.sleep(for: Self.gateTimeout)
                if gate.disarm() {
                    recorder.gateTimedOut += 1
                    reader.scrollTo(request.to, anchor: .center)
                } else {
                    recorder.gateWaited += 1
                }
            }
        }
    }

    /// 第二段：帶動畫滑到目標
    private func animate(_ request: S9SlideRequest<Item.ID>, reader: ScrollViewProxy) {
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            switch mechanism {
            case .reader: reader.scrollTo(request.to, anchor: .center)
            case .binding: centerID = request.to
            case .translation, .awareTranslation: break       // 不經這裡（見 onChange 的內容位移分支）
            }
        } completion: {
            recorder.completions.append((request.generation, ContinuousClock.now))
        }
    }
}

/// `Animatable`：位移動畫期間 SwiftUI 逐幀以內插後的 `shift` 重算 body，幾何才跟得上畫面
struct S9StripCell<Card: View>: View, @preconcurrency Animatable {
    let geometry: CoverFlowGeometry
    let viewportMidX: CGFloat
    /// 條帶內容此刻的位移（版面位置之外、畫面上多移的量）
    var shift: CGFloat
    let onCentred: (Bool) -> Void
    @ViewBuilder let card: (Bool, CGFloat) -> Card

    var animatableData: CGFloat {
        get { shift }
        set { shift = newValue }
    }

    @State private var placement = S9StripPlacement(stackingOrder: 0, isCentered: false)
    @State private var isPlaced = false

    var body: some View {
        card(placement.isCentered, shift)
            .onGeometryChange(for: S9StripPlacement.self) { [geometry, viewportMidX, shift] proxy in
                let d = geometry.normalizedDistance(
                    itemMidX: proxy.frame(in: .named(s9ViewportSpace)).midX + shift,
                    viewportMidX: viewportMidX
                )
                return S9StripPlacement(stackingOrder: geometry.stackingOrder(forDistance: d), isCentered: geometry.isCentered(forDistance: d))
            } action: { newPlacement in
                placement = newPlacement
                isPlaced = true
                onCentred(newPlacement.isCentered)
            }
            .opacity(isPlaced ? 1 : 0)
            .zIndex(placement.stackingOrder)
    }
}

struct S9StripPlacement: Equatable {
    let stackingOrder: Double
    let isCentered: Bool
}

// MARK: - CoverFlowView 複本（production 形狀：並列的播放卡按鈕、標籤、狀態字、點擊與懸停、焦點與按鍵）

struct S9View: View {
    @Bindable var model: CoverFlowViewModel
    let driver: S9Driver
    let testCase: S9Case
    let animation: Animation
    let isInteractive: Bool
    var focus: FocusState<Bool>.Binding
    let upcoming: DeckSnapshot.Upcoming
    let onTapPlayingCard: () -> Void

    @State private var stripSize: CGSize = .zero
    @State private var isHoveringCentre = false

    private static var itemWidth: CGFloat { CoverFlowView.itemWidth }

    var body: some View {
        VStack(spacing: 0) {
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
        S9Strip(
            items: model.cards,
            itemWidth: Self.itemWidth,
            centerID: Binding(
                get: { model.centerID },
                set: { newValue in
                    driver.recorder.rawWrites.append(newValue)
                    model.scrollPositionDidChange(to: newValue)
                }
            ),
            slide: driver.slide,
            trigger: testCase.trigger,
            mechanism: testCase.mechanism,
            animation: animation,
            recorder: driver.recorder
        ) { card, isCentered in
            S9ItemContainer(model: model, card: card, size: Self.itemWidth)
                .onChange(of: isCentered, initial: true) { _, centred in
                    driver.recorder.centringEvents.append(
                        S9CentringEvent(id: card.id, isCentred: centred, tick: driver.recorder.tick))
                    if centred {
                        driver.recorder.centredIDs.insert(card.id)
                    } else {
                        driver.recorder.centredIDs.remove(card.id)
                    }
                    guard card.side == .current else { return }
                    model.playingCardCentering(cardID: card.id, isCentered: centred)
                }
        }
        .frame(maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { stripSize = $0 }
        .onTapGesture(coordinateSpace: .local) { location in
            guard CoverFlowGeometry.acceptsPlayingCardTap(
                isCentered: model.isPlayingCardCentered, location: location, face: centreFace
            ) else { return }
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
        .accessibilityIdentifier("coverflow-strip")
    }

    private var centreFace: CGRect {
        CoverFlowGeometry(itemWidth: Self.itemWidth).centreFace(in: stripSize, reflectionRatio: CoverFlowItem.reflectionRatio)
    }

    @ViewBuilder
    private var playingCardOverlay: some View {
        if model.isPlayingCardCentered {
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
                .accessibilityLabel(Text("edit_lyrics_of \(model.playingCardTitle)"))
                Color.clear
                    .frame(width: Self.itemWidth, height: Self.itemWidth * CoverFlowItem.reflectionRatio)
                    .accessibilityHidden(true)
            }
            .allowsHitTesting(false)
        }
    }

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

    private var centerLabel: some View {
        Text(verbatim: model.centerLabel)
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
            .accessibilityLabel(model.centerLabel)
            .accessibilityValue(model.centerID ?? "")
    }

    @ViewBuilder
    private var centerStatus: some View {
        if let card = model.cards.first(where: { $0.id == model.centerID }) {
            LyricsStatusLabel(status: model.status(for: card))
        }
    }
}

struct S9ItemContainer: View {
    let model: CoverFlowViewModel
    let card: DeckCard
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .top) {
            CoverFlowItem(artwork: image, size: size)
            badge
                .frame(width: size, height: size, alignment: badgeAlignment)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.cardPrefix + card.id)
        .accessibilityValue(LyricsBadge.probeValue(for: model.status(for: card)))
        .task(id: S9ItemTaskKey(
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

struct S9ItemTaskKey: Equatable {
    let persistentID: String
    let revision: Int
}

struct S9Harness: View {
    let driver: S9Driver
    let testCase: S9Case
    let animation: Animation
    @FocusState private var focused: Bool

    var body: some View {
        S9View(model: driver.model, driver: driver, testCase: testCase, animation: animation,
               isInteractive: false, focus: $focused, upcoming: .available, onTapPlayingCard: {})
            .frame(width: s9ViewSize.width, height: s9ViewSize.height)
    }
}
