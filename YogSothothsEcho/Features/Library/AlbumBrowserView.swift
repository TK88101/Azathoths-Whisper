import Observation
import RemoteProtocol
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// 整個畫布（視窗）高：側封封面邊長以它起算（SpineCarouselMetrics）；沒設時只受瀏覽區限制
    @Entry var canvasHeight: CGFloat = .infinity
    /// 唱機層蓋住曲庫期間：側封的 UIKit 無障礙容器要自己把元素藏起來（SwiftUI 的 accessibilityHidden 管不到它）
    @Entry var libraryCovered = false
}

/// 捲動偏移放在獨立的 Observable：只有讀它的疊層每幀重算，`AlbumBrowserView` 本身不因捲動重算（12,000 張的 onChange 比較不必每幀做）
@MainActor
@Observable
final class BrowserScrollState {
    var offset: CGFloat = 0
    /// 上次交給封面升級的可見範圍（捲動中範圍沒變就不重做撤回檢查）
    @ObservationIgnored var lastUpgradeRange: Range<Int>?
    /// 同一偏移下疊層、無障礙、封面升級共用一次 `visibleRange`（每次要做十幾張的投影）
    @ObservationIgnored private var cachedRange: (offset: CGFloat, count: Int, metrics: SpineCarouselMetrics, range: Range<Int>)?

    func visibleRange(count: Int, metrics: SpineCarouselMetrics) -> Range<Int> {
        if let cached = cachedRange, cached.offset == offset, cached.count == count, cached.metrics == metrics { return cached.range }
        let range = SpineCarousel.visibleRange(offset: offset, count: count, metrics: metrics)
        cachedRange = (offset, count, metrics, range)
        return range
    }
}

/// 側封瀏覽（sprint-6-detail.md §4.3、D5、D6）：ScrollView 只放等寬的隱形槽位，提供捲動範圍與吸附；
/// 可見盒另在疊層以 `projectionEffect` 畫；點擊與 VoiceOver 都以投影四邊形為準（CarouselHitTest、BrowserAccessibility）
struct AlbumBrowserView: View {
    let model: LibraryViewModel
    /// 開合轉場（S6 §4.5）：點盒子交給它；沒有＝只瀏覽（render 測試）
    var openController: AlbumOpenController?
    @Environment(\.canvasHeight) private var canvasHeight
    @Environment(\.libraryCovered) private var libraryCovered
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var scroll = BrowserScrollState()
    @State private var shelf = SpineImageShelf()
    @State private var centerID: String?
    @State private var isScrolling = false

    private static let space = "albumBrowser"

    /// 詳情開著或轉場中：不捲動、不收點擊（§4.3）
    private var isInteractive: Bool { (openController?.transition.phase ?? .browsing) == .browsing }

    var body: some View {
        GeometryReader { proxy in
            let metrics = SpineCarouselMetrics(browse: CGRect(origin: .zero, size: proxy.size), canvasHeight: canvasHeight)
            let albums = model.displayed
            let origin = proxy.frame(in: .named(AlbumOpenController.space)).origin
            ZStack(alignment: .topLeading) {
                slots(albums, metrics, origin: origin)
                // F10 空間感（E.3）：淡陰影帶 → 倒影（整層鏡射一次）→ 盒子 → 四周壓暗（LibraryView）；Reduce Transparency 關掉陰影帶與倒影。
                // 倒影畫完整的面（使用者 2026-10-23 選完整版）；模擬器最差 1 秒窗 32→15 fps，以實機 N-03 判定（附錄 F）
                if !reduceTransparency {
                    ShadowBandView(floor: SpineCarousel.floor(metrics), width: metrics.browse.width,
                                   unit: metrics.cover / SpineCarouselMetrics.referenceCover)
                    SpineBoxLayer(model: model, albums: albums, metrics: metrics, scroll: scroll, controller: openController, shelf: shelf,
                                  mirror: true)
                        .floorMirror(floor: SpineCarousel.floor(metrics), size: metrics.browse.size)
                }
                SpineBoxLayer(model: model, albums: albums, metrics: metrics, scroll: scroll, controller: openController, shelf: shelf)
                    .allowsHitTesting(false)
                BrowserAccessibilityLayer(albums: albums, metrics: metrics, scroll: scroll, controller: openController,
                                          hidden: libraryCovered || !isInteractive, settled: !isScrolling,
                                          onActivate: { id in open(id, in: albums, metrics: metrics, origin: origin) },
                                          onScroll: { step($0, in: albums, metrics: metrics) })
                    .allowsHitTesting(false)
            }
            .coordinateSpace(.named(Self.space))
            .onChange(of: albums.isEmpty, initial: true) { _, empty in
                guard !empty else { return }
                model.metrics.firstScreen(ids: BrowserFirstScreen.ids(albums: albums, metrics: metrics))
            }
        }
        // CR-027：重開＝上次位置（清單到了才套用）；回桌面再回來＝記憶體中的位置
        .onAppear {
            guard centerID == nil else { return }
            centerID = model.scrollTarget(ids: model.displayed.map(\.id), previousCenter: model.browseCenterID)
        }
        // 只有使用者造成的中心變化更新位置記憶（程式還原、搜尋替換不算；來源閘門＝`isUserScrolling`）
        .onChange(of: centerID) { _, id in if model.isUserScrolling, let id { model.userMovedAnchor(id) } }
        // 陣列 == 在同一個 buffer 時是 O(1)，清單沒變就不付 12,000 張的比較
        .onChange(of: model.displayed) { _, albums in
            let target = model.scrollTarget(ids: albums.map(\.id), previousCenter: centerID)
            if target != centerID { centerID = target }
            if let opened = openController?.album { openController?.hasReturnSlot = albums.contains { $0.id == opened.id } }
        }
    }

    private func slots(_ albums: [AlbumSummary], _ metrics: SpineCarouselMetrics, origin: CGPoint) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(albums, id: \.id) { album in
                    Color.clear.frame(width: metrics.slot, height: metrics.browse.height)
                        .accessibilityHidden(true)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, max(0, (metrics.browse.width - metrics.slot) / 2), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centerID, anchor: .center)
        .scrollDisabled(!isInteractive)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x + $0.contentInsets.leading }) { _, offset in
            scroll.offset = offset
            // 程式捲動（搜尋後回第 0 張、換版保留中央）不經 scroll phase：沒在拖就當作已停下
            upgradeArtwork(albums, metrics: metrics, settled: !isScrolling)
        }
        .onAppear { upgradeArtwork(albums, metrics: metrics, settled: true) }
        .onScrollPhaseChange { old, phase in
            isScrolling = phase.isScrolling
            if phase == .interacting { model.userScrollBegan() }
            if phase == .idle {
                upgradeArtwork(albums, metrics: metrics, settled: true)
                model.userScrollEnded()
            }
            // 開始捲動：上次停下排的升級還沒到期也要取消（範圍沒變時捲動中的 update 會略過）
            if phase.isScrolling, !old.isScrolling { upgradeArtwork(albums, metrics: metrics, settled: false, force: true) }
        }
        .modifier(FrameRateTracking(layout: .spines))
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { value in
            // 捲動中（含減速）的點擊只讓它停下，不開啟（§4.3）
            guard isInteractive, !isScrolling,
                  let index = CarouselHitTest.index(at: value.location, offset: scroll.offset, count: albums.count, metrics: metrics)
            else { return }
            openAlbum(at: index, in: albums, metrics: metrics, origin: origin)
        })
        .accessibilityIdentifier(AccessibilityID.libraryGrid)
    }

    /// 停下 300 ms 後對螢幕上看得到的盒子要 detail（D7；#6-1 由中心 ±2 擴大）；可見範圍外的撤回。捲動中只在可見範圍改變時撤回（不每幀做、不排程），停下才排程
    private func upgradeArtwork(_ albums: [AlbumSummary], metrics: SpineCarouselMetrics, settled: Bool, force: Bool = false) {
        guard let browse = model.browseArtwork else { return }
        let visible = scroll.visibleRange(count: albums.count, metrics: metrics)
        if !settled, !force, visible == scroll.lastUpgradeRange { return }
        scroll.lastUpgradeRange = visible
        browse.update(candidates: settled ? BrowseArtwork.candidates(albums: albums, offset: scroll.offset, metrics: metrics) : [],
                      visibleIDs: Set(visible.map { albums[$0].id }), schedules: settled)
    }

    private func open(_ id: String, in albums: [AlbumSummary], metrics: SpineCarouselMetrics, origin: CGPoint) {
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }
        openAlbum(at: index, in: albums, metrics: metrics, origin: origin)
    }

    /// 起點＝被點那張當下的 pose（飛行從這裡開始、回程回到這裡）
    private func openAlbum(at index: Int, in albums: [AlbumSummary], metrics: SpineCarouselMetrics, origin: CGPoint) {
        guard isInteractive else { return }
        let pose = SpineCarousel.pose(u: SpineCarousel.u(index: index, offset: scroll.offset, metrics: metrics), metrics: metrics)
        // 以被點那張為界：左邊往左、右邊往右（#6-1 v0.6 F4；開啟當下的快照，換版重排也不改向）
        let outward = SpineCarousel.outward(albums: albums, visible: scroll.visibleRange(count: albums.count, metrics: metrics),
                                            target: index)
        openController?.open(albums[index], from: pose, metrics: metrics, origin: origin, outward: outward)
    }

    /// VoiceOver 三指左右掃：一次一張
    private func step(_ direction: Int, in albums: [AlbumSummary], metrics: SpineCarouselMetrics) -> Bool {
        guard isInteractive, !albums.isEmpty else { return false }
        let current = SpineCarousel.centerIndex(offset: scroll.offset, count: albums.count, metrics: metrics)
        let index = albums.firstIndex { $0.id == centerID } ?? current
        let next = min(albums.count - 1, max(0, index + direction))
        guard next != index else { return false }
        centerID = albums[next].id
        // VoiceOver 也是使用者來源：接管（取消待還原）並記下（CR-027；Codex R5／R6）
        model.userStepped(to: albums[next].id)
        return true
    }
}

/// 可見盒疊層：讀捲動偏移、依 `SpineCarousel` 擺 `SpineBoxView`
private struct SpineBoxLayer: View {
    let model: LibraryViewModel
    let albums: [AlbumSummary]
    let metrics: SpineCarouselMetrics
    let scroll: BrowserScrollState
    let controller: AlbumOpenController?
    let shelf: SpineImageShelf
    /// 倒影層：同樣的擺放，只畫面、圖從架上拿（不載圖、不回報量測）
    var mirror = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // 轉場中每幀重算其他盒的位移／模糊／透明；靜止時暫停
        // 封面落定後（open）其他盒已全透明、被點那張歸詳情層：文字浮現期間不必逐幀重畫側封
        TimelineView(.animation(paused: !(controller.map { $0.isAnimating && !$0.transition.phase.isOpen } ?? false))) { _ in
            let channels = controller?.channels()
            boxes(transition: channels.flatMap { controller?.pose($0) },
                  targetHere: channels.map { controller?.owner($0) == .browser } ?? true)
        }
    }

    /// 被點那張：還歸側封時照原槽位、原 zIndex 畫（清場期間不動、層次不換），交給舞台後隱藏；其他盒依快照方向往外滑走
    private func boxes(transition: (album: AlbumSummary, pose: AlbumOpenPose)?, targetHere: Bool) -> some View {
        let offset = scroll.offset
        let others = transition?.pose
        let outward = controller?.outward ?? [:]
        let visible = scroll.visibleRange(count: albums.count, metrics: metrics).map { (index: $0, album: albums[$0]) }
        return ZStack(alignment: .topLeading) {
            ForEach(visible, id: \.album.id) { item in
                let u = SpineCarousel.u(index: item.index, offset: offset, metrics: metrics)
                let isTarget = item.album.id == transition?.album.id
                let pose = boxPose(u: u, pushedOutBy: isTarget ? 0 : (others?.othersOffset ?? 0) * (outward[item.album.id] ?? 0))
                Group {
                    if mirror {
                        BoxFaces(album: item.album, image: image(for: item.album), pose: pose, metrics: metrics)
                    } else {
                        SpineBoxView(album: item.album, model: model, pose: pose, metrics: metrics, shelf: shelf)
                    }
                }
                .blur(radius: isTarget ? 0 : others?.othersBlur ?? 0)
                .opacity(isTarget ? (targetHere ? 1 : 0) : others?.othersOpacity ?? 1)
                .zIndex(SpineCarousel.zIndex(u: u))
            }
        }
        .frame(width: metrics.browse.width, height: metrics.browse.height, alignment: .topLeading)
        .background { if !mirror { prefetch(range: visible.first.map { $0.index..<(visible.last!.index + 1) } ?? 0..<0, offset: offset) } }
    }

    /// 盒子用的圖：有升級圖用升級圖，否則架上的 spine 縮圖（倒影、預熱共用這一條規則）
    private func image(for album: AlbumSummary) -> UIImage? { model.browseArtwork?.image(for: album) ?? shelf.images[album.id] }

    /// 預熱何時換一輪：範圍、升級圖的版本、架上縮圖的實例（不在每幀解析每張的圖；圖只在換輪時才取）
    private struct PrefetchSignature: Equatable {
        let range: Range<Int>
        let browseRevision: Int
        let shelf: [ObjectIdentifier?]
        let scale: CGFloat
        let cover: CGFloat
    }

    /// 書脊烘焙預熱（s6-61-g-perf-wear.md §5.1）：可見範圍或可見盒的圖一變就換一輪需求（兩側都烘）；捲動中範圍不變就不動
    private func prefetch(range: Range<Int>, offset: CGFloat) -> some View {
        let clamped = range.clamped(to: 0..<albums.count)
        let signature = PrefetchSignature(range: clamped, browseRevision: model.browseArtwork?.revision ?? 0,
                                          shelf: clamped.map { shelf.images[albums[$0].id].map(ObjectIdentifier.init) },
                                          scale: displayScale, cover: metrics.cover)
        return Color.clear.onChange(of: signature, initial: true) {
            SpineBakeCache.shared.prefetch(SpineBakePrefetch.requests(albums: albums, range: clamped, offset: offset, metrics: metrics,
                                                                      scale: displayScale, image: image(for:)))
        }
    }

    /// 開啟時其他盒往外滑走（世界座標位移，帶正負號）
    private func boxPose(u: CGFloat, pushedOutBy distance: CGFloat) -> BoxPose {
        var pose = SpineCarousel.pose(u: u, metrics: metrics)
        pose.x += distance
        return pose
    }
}

// MARK: VoiceOver（§4.3「VoiceOver 焦點框」）：UIKit 容器，每個可見盒一個元素、frame＝投影外接框

private struct BrowserAccessibilityLayer: View {
    let albums: [AlbumSummary]
    let metrics: SpineCarouselMetrics
    let scroll: BrowserScrollState
    let controller: AlbumOpenController?
    let hidden: Bool
    let settled: Bool
    let onActivate: (String) -> Void
    let onScroll: (Int) -> Bool

    var body: some View {
        // 每幀只交廉價 snapshot；元素在被查詢時才建（s6-61-g-perf-wear.md §5.4；實機 n03-b 每幀建 items 佔主執行緒 1.9%）
        BrowserAccessibilityContainer(snapshot: .init(albums: albums, offset: scroll.offset, metrics: metrics,
                                                      visible: scroll.visibleRange(count: albums.count, metrics: metrics)),
                                      settled: settled, hidden: hidden,
                                      focusRequest: controller?.focusRequest, onFocused: { controller?.consumeFocusRequest() },
                                      onActivate: onActivate, onScroll: onScroll)
            .frame(width: metrics.browse.width, height: metrics.browse.height)
    }
}

private struct BrowserAccessibilityContainer: UIViewRepresentable {
    let snapshot: BrowserAccessibilityView.Snapshot
    let settled: Bool
    let hidden: Bool
    let focusRequest: String?
    let onFocused: () -> Void
    let onActivate: (String) -> Void
    let onScroll: (Int) -> Bool

    func makeUIView(context: Context) -> BrowserAccessibilityView { BrowserAccessibilityView() }

    func updateUIView(_ view: BrowserAccessibilityView, context: Context) {
        view.onActivate = onActivate
        view.onScroll = onScroll
        view.accessibilityElementsHidden = hidden
        view.setSnapshot(snapshot, settled: settled)
        // §4.9：詳情關閉、元素依新 offset 重建後，把 VoiceOver 焦點送回原專輯的元素
        if let focusRequest, let element = view.element(for: focusRequest) {
            UIAccessibility.post(notification: .layoutChanged, argument: element)
            Task { @MainActor in onFocused() }
        }
    }
}

final class BrowserAccessibilityView: UIView {
    /// 建元素所需的全部輸入（陣列為參照、其餘為純值，每幀交一份很便宜）
    struct Snapshot {
        let albums: [AlbumSummary]
        let offset: CGFloat
        let metrics: SpineCarouselMetrics
        let visible: Range<Int>
    }

    /// VoiceOver 開著時，可見範圍不變的位移最多每 100 ms 重建一次
    static let voiceOverRebuildInterval: TimeInterval = 0.1

    var onActivate: (String) -> Void = { _ in }
    var onScroll: (Int) -> Bool = { _ in false }
    /// 以 albumID 保存元素：同一張專輯捲動中沿用同一個元素，VoiceOver 焦點不會跳（§4.9 回焦也用它）
    private(set) var elementsByID: [String: AlbumAccessibilityElement] = [:]
    private var built: [AlbumAccessibilityElement] = []
    private var visibleIDs: [String] = []
    private var snapshot: Snapshot?
    private var isStale = false
    private var forceNext = false
    private var lastBuild: TimeInterval = -.infinity
    private(set) var buildCount = 0
    private let isVoiceOverRunning: () -> Bool
    private let now: () -> TimeInterval

    init(isVoiceOverRunning: @escaping () -> Bool = { UIAccessibility.isVoiceOverRunning }, now: @escaping () -> TimeInterval = CACurrentMediaTime) {
        self.isVoiceOverRunning = isVoiceOverRunning
        self.now = now
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    /// 不收觸控（點擊交給下面的 ScrollView 與 CarouselHitTest）
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    /// 每幀呼叫：只記下輸入。可見範圍變了（或捲動停下）下次查詢必重建；VoiceOver 開著時範圍一變就通知它
    func setSnapshot(_ next: Snapshot, settled: Bool = false) {
        // 同範圍、同張數但換了一批專輯（搜尋、換版）也算變了（Codex 實作 R1 P2）
        let ids = next.visible.clamped(to: 0..<next.albums.count).map { next.albums[$0].id }
        let rangeChanged = ids != visibleIDs
        visibleIDs = ids
        snapshot = next
        isStale = true
        if rangeChanged || settled { forceNext = true }
        if rangeChanged, isVoiceOverRunning() { UIAccessibility.post(notification: .layoutChanged, argument: nil) }
    }

    override var accessibilityElements: [Any]? {
        get {
            rebuildIfNeeded(force: false)
            return built
        }
        set {}
    }

    private func rebuildIfNeeded(force: Bool) {
        guard isStale, let snapshot else { return }
        if !force, !forceNext, isVoiceOverRunning(), now() - lastBuild < Self.voiceOverRebuildInterval { return }
        update(BrowserAccessibility.items(albums: snapshot.albums, offset: snapshot.offset, metrics: snapshot.metrics, visible: snapshot.visible))
        isStale = false
        forceNext = false
        lastBuild = now()
        buildCount += 1
    }

    private func update(_ items: [BrowserAccessibilityItem]) {
        var next: [String: AlbumAccessibilityElement] = [:]
        for item in items {
            let element = elementsByID[item.albumID] ?? AlbumAccessibilityElement(accessibilityContainer: self, albumID: item.albumID)
            element.owner = self
            element.accessibilityLabel = item.label
            element.accessibilityFrameInContainerSpace = item.frame
            next[item.albumID] = element
        }
        elementsByID = next
        built = items.compactMap { next[$0.albumID] }
    }

    /// 回焦用：先依最新 snapshot 建好再找
    func element(for albumID: String) -> AlbumAccessibilityElement? {
        rebuildIfNeeded(force: true)
        return elementsByID[albumID]
    }
}

final class AlbumAccessibilityElement: UIAccessibilityElement {
    let albumID: String
    weak var owner: BrowserAccessibilityView?

    init(accessibilityContainer container: Any, albumID: String) {
        self.albumID = albumID
        super.init(accessibilityContainer: container)
        accessibilityTraits = .button
        accessibilityIdentifier = AccessibilityID.libraryAlbum(albumID)
    }

    override func accessibilityActivate() -> Bool {
        owner?.onActivate(albumID)
        return owner != nil
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        switch direction {
        case .left: owner?.onScroll(1) ?? false
        case .right: owner?.onScroll(-1) ?? false
        default: false
        }
    }
}
