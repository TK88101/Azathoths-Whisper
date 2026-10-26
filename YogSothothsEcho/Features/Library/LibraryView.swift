import RemoteProtocol
import SwiftUI

/// 曲庫畫面：搜尋、狀態列（sprint-3-detail.md §4.6）＋側封瀏覽（S6 取代 S3 的格狀清單，sprint-6-detail.md D12）
struct LibraryView: View {
    @Bindable var model: LibraryViewModel
    /// 點盒子＝開專輯詳情（S6 詳情層與開合轉場；沒有＝只瀏覽）
    var openController: AlbumOpenController?
    /// CR-024：側封或小圖
    var layout: BrowseLayout = .spines

    var body: some View {
        // CR-023：側封鋪滿全畫面；四周壓暗在盒子之上（F10 E.3①）；搜尋框（右上）與狀態膠囊（頂部正中）疊在壓暗之上
        ZStack(alignment: .top) {
            switch layout {
            case .spines:
                AlbumBrowserView(model: model, openController: openController)
                // 四周壓暗只在側封（F10 E.3；小圖背景只有漸層）
                VignetteView().ignoresSafeArea()
            case .grid:
                GridBrowserView(model: model, openController: openController)
            }
            if LibraryPresentation.searchStatus(query: model.query, searchResults: model.searchResults,
                                                resultsQuery: model.searchResultsQuery) == .noResults {
                Text(verbatim: LibraryPresentation.noResultsMessage(query: model.query))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier(AccessibilityID.libraryNoResults)
            }
            chrome
        }
        .overlay(alignment: .topTrailing) { LibraryDebugOverlay(model: model, layout: layout).padding(.top, 64) }
        // 換展示：撤回上一展示的封面升級（g 版 T5；兩者共用排程器的單一傳輸）
        .onChange(of: layout) { model.browseArtwork?.switchLayout() }
        // 書脊紙紋與磨損的平鋪圖在背景先產生（F2；不在第一次捲動時卡主執行緒）
        .task { await Task.detached(priority: .utility) { PaperFiber.prewarm() }.value }
    }

    /// 頂部浮層：詳情開著時淡出、不可操作（原版頂部分段同樣淡出，§4.5）
    private var chrome: some View {
        ZStack(alignment: .top) {
            statusCapsule
            HStack {
                Spacer()
                searchField
            }
        }
        .padding(.top, ShellChrome.cornerInset.vertical + 3)
        .padding(.trailing, ShellChrome.cornerInset.horizontal + 3)
        .opacity(isBrowsing ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: isBrowsing)
        .disabled(!isBrowsing)
        .accessibilityHidden(!isBrowsing)
    }

    /// 右上透明有色玻璃搜尋框（§5.2）
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).accessibilityHidden(true)
            TextField("Search albums", text: $model.query)
                .textFieldStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.librarySearch)
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minWidth: LibraryChrome.searchMinWidth, maxWidth: LibraryChrome.searchWidth, minHeight: LibraryChrome.searchHeight,
               maxHeight: LibraryChrome.searchHeight)
        .tintedGlass(in: Capsule())
    }

    /// 連線狀態：頂部正中透明有色玻璃膠囊；沒有狀態時不顯示
    @ViewBuilder private var statusCapsule: some View {
        if LibraryPresentation.status(phase: model.phase, connected: model.isConnected, hasAlbums: !model.albums.isEmpty,
                                      total: model.total) != .none {
            statusLine
                .font(.footnote)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .tintedGlass(in: Capsule())
                .frame(maxWidth: LibraryChrome.statusMaxWidth)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.libraryStatus)
        }
    }

    private var isBrowsing: Bool { openController?.album == nil }

    @ViewBuilder private var statusLine: some View {
        switch LibraryPresentation.status(phase: model.phase, connected: model.isConnected, hasAlbums: !model.albums.isEmpty,
                                          total: model.total) {
        case .none:
            EmptyView()
        case .loading(let loaded, let total):
            Text(verbatim: String.localizedStringWithFormat(String(localized: "Loading albums… %lld of %lld"), loaded, total))
                .foregroundStyle(.secondary)
        case .disconnected:
            Text("Can't reach your Mac. Showing the last list.").foregroundStyle(.secondary)
        case .libraryUnavailable:
            VStack(spacing: 6) {
                Text("Your Mac can't read the Music library. On your Mac, allow Azathoth's Whisper in Privacy & Security ▸ Media & Apple Music.")
                    .multilineTextAlignment(.center)
                Button("Retry") { model.retry() }
            }
            .accessibilityIdentifier(AccessibilityID.libraryUnavailable)
        case .unstable:
            Text("Your Mac's library is changing. It will refresh automatically.").foregroundStyle(.secondary)
        case .failed:
            VStack(spacing: 6) {
                Text("Couldn't load the album list. Try again later.").multilineTextAlignment(.center)
                Button("Retry") { model.retry() }
            }
        }
    }

}

/// 頂部浮層尺寸（s6-61-f8f9-shell.md §5.2）
enum LibraryChrome {
    static let searchWidth: CGFloat = 220
    static let searchMinWidth: CGFloat = 180
    static let searchHeight: CGFloat = 38
    static let statusMaxWidth: CGFloat = 560
}

/// 會判斷的 View 邏輯（純函式，單測）
enum LibraryPresentation {
    enum Status: Equatable {
        case none, disconnected, libraryUnavailable, unstable, failed
        case loading(loaded: Int, total: Int)
    }

    static func status(phase: LibraryViewModel.Phase, connected: Bool, hasAlbums: Bool, total: Int? = nil) -> Status {
        if !connected { return hasAlbums ? .disconnected : .none }
        switch phase {
        case .idle, .ready: return .none
        case .loading(let loaded): return .loading(loaded: loaded, total: max(total ?? loaded, loaded))
        case .failed(.libraryUnavailable): return .libraryUnavailable
        case .failed(.catalogUnstable): return .unstable
        case .failed(.network): return .failed
        }
    }

    enum SearchStatus: Equatable { case none, noResults }

    /// 零結果提示（g 版 T7）：有效 query（trim 後非空）、搜尋已回應、0 筆。未回應（debounce 中顯示完整清單）與失敗（沿用錯誤態）不顯示
    static func searchStatus(query: String, searchResults: [AlbumSummary]?, resultsQuery: String?) -> SearchStatus {
        guard LibraryViewModel.isEffective(query: query), let searchResults, searchResults.isEmpty,
              resultsQuery?.trimmingCharacters(in: .whitespacesAndNewlines) == query.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return .none }
        return .noResults
    }

    static func noResultsMessage(query: String) -> String {
        String.localizedStringWithFormat(String(localized: "No albums match %@"), query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 無封面的佔位色：由 ID 決定，穩定不閃
    static func placeholderColor(for id: String) -> Color {
        let c = placeholderRGB(for: id)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// 佔位色的唯一定義（書脊烘焙在背景執行緒也要用）：色相由 ID、飽和 0.25、明度 0.55
    nonisolated static func placeholderRGB(for id: String) -> RGBColor {
        let seed = UInt64(id, radix: 16) ?? 0
        return RGBColor(hue: Double(seed % 360), saturation: 0.25, brightness: 0.55)
    }

}
