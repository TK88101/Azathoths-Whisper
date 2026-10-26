import Observation
import RemoteProtocol
import SwiftUI
import UIKit

/// CR-024（s6-61-f8f9-shell.md §5.4）：側封／小圖（專輯牆）切換
enum BrowseLayout: String, Sendable {
    case spines, grid

    /// 左鍵圖示＝點了會變成的樣子：側封時顯示四方塊、小圖時顯示側封
    enum Icon: Equatable { case squares, spines }

    var toggled: BrowseLayout { self == .spines ? .grid : .spines }
    /// 捲動方向（量測用）：側封橫向、小圖縱向
    var scrollAxis: MeasurementRecord.Axis { self == .spines ? .x : .y }
    var buttonIcon: Icon { self == .spines ? .squares : .spines }
}

/// 小圖展示的純函式
enum GridBrowser {
    static let sideInset: CGFloat = 44
    static let columnSpacing: CGFloat = 28
    static let rowSpacing: CGFloat = 34
    static let targetCellWidth: CGFloat = 220
    static let minimumColumns = 3

    /// 欄數＝max(3, floor((寬−2·44＋28)/(220＋28)))：13 吋 5 欄、11 吋 4 欄
    static func columns(width: Double) -> Int {
        let usable = width - 2 * sideInset + columnSpacing
        return max(minimumColumns, Int((usable / (targetCellWidth + columnSpacing)).rounded(.down)))
    }

    /// 畫面上看得到的格（frames 與 viewport 須在同一個 named space；frames 只含目前清單內、已建立的格）：由上而下、由左而右
    static func visibleIDs(frames: [String: CGRect], viewport: CGRect) -> [String] {
        frames.filter { !$0.value.intersection(viewport).isEmpty }
            .sorted { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }
            .map(\.key)
    }

    /// 中心格＝與 viewport 中心距離最近的可見格（位置記憶的 anchor）
    static func centerCell(frames: [String: CGRect], viewport: CGRect) -> String? {
        let center = CGPoint(x: viewport.midX, y: viewport.midY)
        func distance(_ r: CGRect) -> CGFloat { hypot(r.midX - center.x, r.midY - center.y) }
        return frames.filter { $0.value.intersects(viewport) }.min { distance($0.value) < distance($1.value) }?.key
    }
}

/// 同 `AppearanceViewModel`：記在設定裡，讀到未知值回預設
@MainActor
@Observable
final class BrowseLayoutViewModel {
    static let storageKey = "browse.layout"

    @ObservationIgnored private let store: SettingsStore

    var layout: BrowseLayout {
        didSet {
            store.set(layout.rawValue, forKey: Self.storageKey)
            #if DEBUG
            // 量測試次不得跨展示（g 版 T5）：錄製中切換＝該試次作廢；唯一接線點
            if layout != oldValue { FrameRateMonitor.shared.end(voidReason: .layoutChanged) }
            #endif
        }
    }

    init(store: SettingsStore) {
        self.store = store
        layout = store.string(forKey: Self.storageKey).flatMap(BrowseLayout.init(rawValue:)) ?? .spines
    }

    func toggle() { layout = layout.toggled }
}

/// 小圖各格的框（同一 named space）與專輯：參照型別、不可觀察——捲動中每幀更新框不使 `GridBrowserView.body` 重算
/// （simcodex R1 效率：原為 @State，每幀每格一次寫入就重建 1,000 格的 ForEach）
@MainActor
final class GridGeometry {
    var frames: [String: CGRect] = [:]
    var albums: [String: AlbumSummary] = [:]
    /// 格子進出、首次拿到框：同一輪 run loop 內只排一次升級（simcodex R2：逐格呼叫＋初次框晚於 onAppear 會漏升級）
    var upgradeScheduled = false

    func prune(keeping ids: Set<String>) {
        frames = frames.filter { ids.contains($0.key) }
        albums = albums.filter { ids.contains($0.key) }
    }
}

/// 小圖（專輯牆）：Music 式封面＋專輯名＋藝人；點封面開詳情（開合轉場起點＝該格封面框，不做 3D 轉正）
struct GridBrowserView: View {
    let model: LibraryViewModel
    var openController: AlbumOpenController?
    @Environment(\.canvasHeight) private var canvasHeight
    @State private var geometry = GridGeometry()
    @State private var isScrolling = false

    private var isInteractive: Bool { (openController?.transition.phase ?? .browsing) == .browsing }

    var body: some View {
        GeometryReader { proxy in
            let albums = model.displayed
            let metrics = SpineCarouselMetrics(browse: CGRect(origin: .zero, size: proxy.size), canvasHeight: canvasHeight)
            let origin = proxy.frame(in: .named(AlbumOpenController.space)).origin
            let viewport = { proxy.frame(in: .named(AlbumOpenController.space)) }
            let columns = Array(repeating: GridItem(.flexible(), spacing: GridBrowser.columnSpacing, alignment: .top),
                                count: GridBrowser.columns(width: proxy.size.width))
            ScrollViewReader { reader in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: GridBrowser.rowSpacing) {
                        ForEach(albums, id: \.id) { album in
                            GridAlbumCell(album: album, model: model)
                                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(AlbumOpenController.space)) }) {
                                    let isNew = geometry.frames[album.id] == nil
                                    geometry.frames[album.id] = $0
                                    if isNew { scheduleUpgrade(viewport) }
                                }
                                // 格子進出：捲動中只撤回、停下（或首屏）才排程
                                .onAppear { geometry.albums[album.id] = album }
                                .onDisappear {
                                    geometry.frames[album.id] = nil
                                    geometry.albums[album.id] = nil
                                    scheduleUpgrade(viewport)
                                }
                                .onTapGesture { open(album, metrics: metrics, origin: origin) }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { open(album, metrics: metrics, origin: origin) }
                                .id(album.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, GridBrowser.sideInset)
                    .padding(.top, LibraryChrome.searchHeight + 44)
                    .padding(.bottom, DockPresentation.size(.hasCurrentTrack).height + DockPresentation.bottomMargin + 40)
                }
                .scrollDisabled(!isInteractive)
                .onScrollPhaseChange { _, phase in
                    isScrolling = phase.isScrolling
                    upgradeArtwork(viewport: viewport(), settled: phase == .idle)
                    if phase == .interacting { model.userScrollBegan() }
                    if phase == .idle {
                        noteCenter(viewport: viewport)
                        model.userScrollEnded()
                    }
                }
                // 位置記憶＝幾何中心格（CR-027；取代舊的 visible.first）；慣性中也即時更新記憶體（進背景 flush 才準）
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, _ in noteCenter(viewport: viewport) }
                .onChange(of: albums) { _, now in
                    let ids = now.map(\.id)
                    geometry.prune(keeping: Set(ids))
                    // 還原（清空搜尋）或搜尋改變＝捲到目標；其他換版不動
                    let restoring = model.pendingRestore != nil
                    guard restoring || model.queryChangedSinceScroll else { return }
                    if let target = model.scrollTarget(ids: ids, previousCenter: nil) {
                        reader.scrollTo(target, anchor: restoring ? .center : .top)
                    }
                }
                .modifier(FrameRateTracking(layout: .grid))
                .onAppear {
                    let ids = albums.map(\.id)
                    if let anchor = model.scrollTarget(ids: ids, previousCenter: model.browseCenterID) {
                        reader.scrollTo(anchor, anchor: .center)
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityID.libraryGrid)
        }
    }

    /// 只在使用者捲動中才算中心格（不在就連 viewport 都不取）
    private func noteCenter(viewport: () -> CGRect) {
        guard model.isUserScrolling, let id = GridBrowser.centerCell(frames: geometry.frames, viewport: viewport()) else { return }
        model.userMovedAnchor(id)
    }

    private func scheduleUpgrade(_ viewport: @escaping () -> CGRect) {
        guard !geometry.upgradeScheduled else { return }
        geometry.upgradeScheduled = true
        Task { @MainActor in
            geometry.upgradeScheduled = false
            upgradeArtwork(viewport: viewport(), settled: !isScrolling)
        }
    }

    /// 小圖清晰版（g 版 T5）：看得到的格由上而下依序向排程器要 512 px；捲動中只撤回
    private func upgradeArtwork(viewport: CGRect, settled: Bool) {
        guard let browse = model.browseArtwork else { return }
        let ids = GridBrowser.visibleIDs(frames: geometry.frames, viewport: viewport)
        let candidates = settled ? ids.enumerated().compactMap { index, id in
            geometry.albums[id].map { BrowseArtwork.Candidate(album: $0, distance: index) }
        } : []
        browse.update(candidates: candidates, visibleIDs: Set(ids), schedules: settled, rendition: .grid)
    }

    /// 起點＝該格封面框（瀏覽區座標）；轉正後的 pose 投影恰為封面框，飛到詳情封面框
    private func open(_ album: AlbumSummary, metrics: SpineCarouselMetrics, origin: CGPoint) {
        guard isInteractive, let frame = geometry.frames[album.id] else { return }
        let cover = CGRect(x: frame.minX - origin.x, y: frame.minY - origin.y, width: frame.width, height: frame.width)
        let pose = AlbumOpenPose.endPose(target: cover, side: .right, metrics: metrics)
        openController?.open(album, from: pose, metrics: metrics, origin: origin, outward: [:])
    }
}

private struct GridAlbumCell: View {
    let album: AlbumSummary
    let model: LibraryViewModel
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AlbumCoverImage(album: album, image: model.browseArtwork?.image(for: album, rendition: .grid) ?? image)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.35), radius: 9, y: 6)
                .padding(.bottom, 6)
            Text(verbatim: album.title).font(.system(size: 16)).lineLimit(1)
            Text(verbatim: album.artist).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(album.title), \(album.artist)"))
        .accessibilityIdentifier(AccessibilityID.libraryAlbum(album.id))
        .task(id: album.artworkToken ?? album.id) {
            image = await model.image(for: album, networkDelay: SpineBoxView.networkDelay)
        }
    }
}
