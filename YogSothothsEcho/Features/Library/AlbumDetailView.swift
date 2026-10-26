import RemoteProtocol
import SwiftUI

/// 詳情層的版面（唯一定義）：曲目欄的框與資訊區間距，View 與 F10 字色取樣（`DetailBackgroundModel`）共用
enum DetailLayout {
    static let listGapToWidth: CGFloat = 0.096
    static let listTrailing: CGFloat = 40
    /// 曲目欄頂端比封面頂端高出的量
    static let listRise: CGFloat = 30
    /// 封面下緣到專輯名
    static let metaGap: CGFloat = 20

    static func tracksFrame(cover: CGRect, size: CGSize) -> CGRect {
        let leading = cover.maxX + listGapToWidth * size.width, top = max(0, cover.minY - listRise)
        return CGRect(x: leading, y: top, width: max(0, size.width - leading - listTrailing), height: max(0, size.height - top))
    }
}

/// 詳情層（sprint-6-detail.md §4.6，照原版「左封面右清單」）：殼層 ZStack 裡蓋住曲庫的一層，播放列不在其內（CR-020）。
/// 底色隨轉場混入；封面落定（owner＝detail）才換成這裡的 2D 版（飛行中由 `AlbumStageView` 畫）；
/// 文字「從深處浮上來」（#6-1 v0.6 F6）：專輯名 → 藝人 → Play，右欄逐列；關閉時倒放
struct AlbumDetailView: View {
    let controller: AlbumOpenController
    let model: AlbumTracksViewModel
    /// 目前曲（Mac 推來）：標示正在播放
    let currentTrackID: String?
    /// F10（E.4）：詳情背景、字色與投影
    let background: DetailBackgroundController
    let backgroundSettings: BackgroundViewModel
    #if DEBUG
    var benchmark: ControlBenchmark?
    #endif
    @AccessibilityFocusState private var titleFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast


    var body: some View {
        if let album = controller.album, let metrics = controller.metrics {
            // 與時間無關、只隨曲目變的值在逐幀閉包外算一次
            let list = TrackListLayout(songs: model.songs)
            GeometryReader { proxy in
                let cover = AlbumOpenPose.detailCoverFrame(metrics: metrics).offsetBy(dx: controller.browseOrigin.x, dy: controller.browseOrigin.y)
                // 轉場中（含文字浮現）每幀重畫；靜止時暫停
                TimelineView(.animation(paused: !controller.isAnimating)) { _ in
                    let channels = controller.channels()
                    let reveal = Reveal(elapsed: channels.reveal, end: controller.transition.revealEnd, reduceMotion: controller.reduceMotion)
                    ZStack(alignment: .topLeading) {
                        DetailBackgroundView(content: background.content, preset: backgroundSettings.preset, scheme: colorScheme,
                                             reduceTransparency: reduceTransparency, reduceMotion: controller.reduceMotion)
                            .opacity(AlbumOpenPose.backgroundBlend(channels))
                            .ignoresSafeArea()
                        if controller.owner(channels) == .detail {
                            // D13：投影走封套同一條路徑（SleeveFace 的 background），值取自深色板（#6-1 v0.6 F5）
                            SleeveFace(image: controller.cover, placeholder: LibraryPresentation.placeholderColor(for: album.id),
                                       size: cover.size, cornerRadius: 0,
                                       shadow: DetailCoverShadow(coverSide: cover.width, opacity: background.ink.coverShadowOpacity, progress: 1).sleeve)
                                .offset(x: cover.minX, y: cover.minY)
                                .accessibilityHidden(true)
                        }
                        meta(album, cover: cover, reveal: reveal)
                        tracksPane(album, list: list, cover: cover, size: proxy.size, reveal: reveal)
                    }
                }
                .overlay(alignment: .topLeading) { backButton }
                .onChange(of: DetailBackgroundController.Layout(cover: cover, size: proxy.size, preset: backgroundSettings.preset,
                                                                reduceTransparency: reduceTransparency), initial: true) { _, layout in
                    background.updateLayout(layout)
                }
            }
            // 換專輯、換圖（spine → 原檔、無 → 有）、換模式、換主題
            .onChange(of: DetailBackgroundController.Request(albumID: album.id, artworkToken: album.artworkToken, image: controller.cover,
                                                             mode: backgroundSettings.detailMode, scheme: colorScheme),
                      initial: true) { _, request in background.update(request) }
            // 先宣告為容器：直接在容器上掛 action 會把它變成單一元素、子元素併進去（實測返回鍵的框被撐成整個詳情區）
            .accessibilityElement(children: .contain)
            .accessibilityAction(.escape) { controller.close() }
            .onChange(of: controller.transition.tracksTappable) { _, shown in if shown { titleFocused = true } }
            .onChange(of: list.schedule.end, initial: true) { _, end in
                if model.phase == .ready { controller.updateRevealEnd(end) }
            }
        }
    }

    /// 此刻的文字段進度：各元素依出場時刻算自己的 pose；Reduce Motion 只此一處決定
    struct Reveal {
        let elapsed: Double
        let end: Double
        let reduceMotion: Bool

        func pose(delay: Double) -> DetailRevealPose {
            reduceMotion ? .reduced(progress: end > 0 ? elapsed / end : 1) : .at(elapsed: elapsed, delay: delay)
        }
    }

    /// 右欄的排序與出場序號（只隨曲目變）：碟片標題佔一格、每首一格、尾端總長最後一格
    struct TrackListLayout {
        let songs: [TrackSummary]
        let showsDiscs: Bool
        /// 第 i 首前面是否有碟片標題，以及兩者的出場序號
        let disc: [Int?]
        let row: [Int]
        let summary: Int
        let schedule: DetailRevealSchedule
        let numbered: [(offset: Int, element: TrackSummary)]
        let summaryText: String

        init(songs unordered: [TrackSummary]) {
            songs = AlbumDetailPresentation.ordered(unordered)
            showsDiscs = AlbumDetailPresentation.showsDiscTitles(songs)
            var next = 0
            var disc: [Int?] = [], row: [Int] = []
            for (index, song) in songs.enumerated() {
                if showsDiscs, index == 0 || songs[index - 1].disc != song.disc {
                    disc.append(next)
                    next += 1
                } else {
                    disc.append(nil)
                }
                row.append(next)
                next += 1
            }
            self.disc = disc
            self.row = row
            summary = next
            schedule = DetailRevealSchedule(itemCount: next + 1)
            numbered = Array(songs.enumerated())
            summaryText = AlbumDetailPresentation.summary(songCount: songs.count, total: AlbumDetailPresentation.totalDuration(songs))
        }
    }

    private var backButton: some View {
        Button { controller.close() } label: {
            // 與曲目列表同字色（F10 字色自動白／深；使用者 2026-10-23：不要系統藍）
            Image(systemName: "chevron.left").font(.title2.weight(.semibold)).frame(width: 44, height: 44)
                .foregroundStyle(background.ink.list.color)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Close"))
        .accessibilityIdentifier(AccessibilityID.albumTracksClose)
        .opacity(isClosable ? 1 : 0)
        .animation(.easeInOut(duration: 0.2).delay(isClosable ? 0.3 : 0), value: isClosable)
        .disabled(!isClosable)
        .padding(.leading, 12)
        .padding(.top, 8)
    }

    private var isClosable: Bool { controller.transition.phase.isClosable }

    /// 次要文字：同字色、平常 0.6（系統「增加對比」時不透明）
    private func secondary(_ ink: DetailInk) -> Color {
        ink.color.opacity(ink.secondaryOpacity(increasedContrast: contrast == .increased))
    }

    private func meta(_ album: AlbumSummary, cover: CGRect, reveal: Reveal) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: album.title).font(.title3.weight(.bold)).lineLimit(2).multilineTextAlignment(.center)
                .accessibilityFocused($titleFocused)
                .revealed(reveal.pose(delay: DetailRevealSchedule.title))
            Text(verbatim: album.artist).font(.body).foregroundStyle(secondary(background.ink.info)).lineLimit(1)
                .revealed(reveal.pose(delay: DetailRevealSchedule.artist))
            Button { Task { await model.playFirst() } } label: {
                // CR-023：透明有色玻璃膠囊（44 pt 高）
                Label("Play", systemImage: "play.fill").font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .tintedGlass(in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!controller.transition.tracksTappable
                      || !AlbumDetailPresentation.playEnabled(songCount: model.songs.count, phase: model.phase, canPlay: model.canPlay))
            .tint(background.ink.info.color)
            .padding(.top, 10)
            .revealed(reveal.pose(delay: DetailRevealSchedule.play))
        }
        .foregroundStyle(background.ink.info.color)
        .frame(width: cover.width)
        .offset(x: cover.minX, y: cover.maxY + DetailLayout.metaGap)
    }

    private func tracksPane(_ album: AlbumSummary, list: TrackListLayout, cover: CGRect, size: CGSize, reveal: Reveal) -> some View {
        let frame = DetailLayout.tracksFrame(cover: cover, size: size)
        return listContent(album, list: list, reveal: reveal)
            .foregroundStyle(background.ink.list.color)
            .tint(background.ink.list.color)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }

    @ViewBuilder private func listContent(_ album: AlbumSummary, list: TrackListLayout, reveal: Reveal) -> some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let failure):
            VStack(spacing: 12) {
                Text(failure == .libraryUnavailable ? PlaybackPresentation.text(.libraryUnavailable) : PlaybackPresentation.text(.failed))
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await model.retry() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier(AccessibilityID.albumTracksNotice)
        case .ready:
            tracks(album, list: list, reveal: reveal)
        }
    }

    private func tracks(_ album: AlbumSummary, list: TrackListLayout, reveal: Reveal) -> some View {
        let schedule = list.schedule
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !model.contextPlayable {
                    Text("Picking a song from this album plays only that song.").font(.footnote).foregroundStyle(secondary(background.ink.list))
                        .padding(.vertical, 8)
                        .revealed(reveal.pose(delay: schedule.item(0)))
                }
                if let notice = model.notice {
                    PlaybackNoticeRow(notice: notice, id: AccessibilityID.albumTracksNotice, onResync: model.resync,
                                      onRetry: { Task { await model.retryPlay() } })
                }
                ForEach(list.numbered, id: \.element.id) { index, song in
                    if let disc = list.disc[index] {
                        Text("Disc \(song.disc)").font(.subheadline.weight(.semibold)).padding(.top, 18).padding(.bottom, 6)
                            .revealed(reveal.pose(delay: schedule.item(disc)))
                    }
                    row(song, album: album)
                        .revealed(reveal.pose(delay: schedule.item(list.row[index])))
                }
                Text(verbatim: list.summaryText)
                    .font(.footnote).foregroundStyle(secondary(background.ink.list)).padding(.vertical, 16)
                    .revealed(reveal.pose(delay: schedule.item(list.summary)))
                #if DEBUG
                if let benchmark {
                    BenchmarkPanel(benchmark: benchmark, albumID: album.id, songs: model.songs).padding(.bottom, 24)
                        .revealed(reveal.pose(delay: schedule.item(list.summary)))
                }
                #endif
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier(AccessibilityID.albumTracksList)
    }

    private func row(_ song: TrackSummary, album: AlbumSummary) -> some View {
        let state = PlaybackPresentation.rowState(trackID: song.id, pending: model.pendingTrackID, current: currentTrackID)
        return Button { Task { await model.play(song) } } label: {
            HStack(spacing: 14) {
                Text(verbatim: String(format: "%02d", song.number)).font(.body.monospacedDigit()).foregroundStyle(secondary(background.ink.list))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: song.title).lineLimit(1)
                    if AlbumDetailPresentation.showsArtist(song, albumArtist: album.artist) {
                        Text(verbatim: song.artist).font(.caption).foregroundStyle(secondary(background.ink.list)).lineLimit(1)
                    }
                }
                Spacer()
                switch state {
                case .preparing:
                    Text("Preparing…").font(.footnote).foregroundStyle(secondary(background.ink.list))
                case .playing:
                    Image(systemName: "speaker.wave.2.fill").accessibilityLabel(Text("Now playing"))
                case .idle:
                    Text(verbatim: song.duration.map(PlaybackPresentation.time) ?? "").font(.footnote.monospacedDigit())
                        .foregroundStyle(secondary(background.ink.list))
                }
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!controller.transition.tracksTappable || !model.canPlay)
        .accessibilityIdentifier(AccessibilityID.albumTracksRow(song.number))
    }
}

private extension View {
    /// 從深處浮上來的畫面值；模糊只在還沒清楚時才掛（R5 中 3：未開始或已清楚的不掛模糊層）。
    /// 透明度至少 0.01：0 會讓元素離開 AX 樹（S5 坑），VoiceOver 浮現期間仍讀得到
    func revealed(_ pose: DetailRevealPose) -> some View {
        scaleEffect(pose.scale)
            .blur(radius: pose.blur > 0.05 && pose.opacity > 0 ? pose.blur : 0)
            .offset(y: pose.offsetY)
            .opacity(max(0.01, pose.opacity))
    }
}

#if DEBUG
/// 量測面板（S4 §4.12；S6 由舊曲目清單搬到詳情清單底部）：選好專輯後按種類開始；結果寫 Documents/metrics。文案只給開發者看，不本地化
private struct BenchmarkPanel: View {
    @Bindable var benchmark: ControlBenchmark
    let albumID: String
    let songs: [TrackSummary]
    @State private var seed: UInt64 = 20261018

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ForEach(BenchmarkPlan.Kind.allCases, id: \.self) { kind in
                    Button { benchmark.start(kind, albumID: albumID, songs: songs, seed: seed) } label: { Text(verbatim: kind.rawValue) }
                        .buttonStyle(.bordered)
                        .disabled(benchmark.running != nil)
                }
            }
            HStack {
                Toggle(isOn: Binding(get: { benchmark.receiptMode }, set: { benchmark.setReceiptMode($0) })) {
                    Text(verbatim: "D2 receipt")
                }
                Button { benchmark.loadRunning ? benchmark.stopLoad() : benchmark.startLoad() } label: {
                    Text(verbatim: benchmark.loadRunning ? "stop B6 load" : "start B6 load")
                }
            }
            Text(verbatim: benchmark.running.map { "\($0.rawValue) \(benchmark.done)/\(benchmark.total)" } ?? (benchmark.lastSummary ?? "seed \(seed)"))
        }
        .font(.caption.monospacedDigit())
    }
}
#endif
