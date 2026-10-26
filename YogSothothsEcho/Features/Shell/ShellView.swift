import SwiftUI

/// 未連線：連線／配對頁 `PairingScreen`（S2；S6.5 CR-033 改版）。已連線或已有清單：頂列（連線狀態、外觀）＋曲庫（S3）
struct ShellView: View {
    @Bindable var appearance: AppearanceViewModel
    @Bindable var background: BackgroundViewModel
    let detailBackground: DetailBackgroundController
    let browseLayout: BrowseLayoutViewModel
    let connection: ConnectionViewModel
    let library: LibraryViewModel
    let nowPlaying: NowPlayingViewModel
    let albumTracks: AlbumTracksViewModel
    let albumOpen: AlbumOpenController
    let turntable: TurntableViewModel
    let fakePayload: String?
    #if DEBUG
    var benchmark: ControlBenchmark?
    #endif
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    /// 唱機關閉後 VoiceOver 回到播放列的唱機鈕（S5 D2 規則；fullScreenCover 改殼層內一層後要自己做）
    @AccessibilityFocusState private var turntableButtonFocused: Bool
    /// 唱機滑動進度：1＝在畫面外右側、0＝蓋滿（TurntableEntrance.offsets）
    @State private var turntableSlide: CGFloat = 1
    @State private var showsSettings = false

    var body: some View {
        GeometryReader { proxy in
            content(size: proxy.size)
                .environment(\.canvasHeight, proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
        }
    }

    private func content(size: CGSize) -> some View {
        Group {
            if ShellPresentation.showsLibrary(state: connection.state, hasAlbums: !library.albums.isEmpty) {
                libraryAndTurntable(size: size)
            } else {
                PairingScreen(model: connection, appearance: appearance, preset: background.preset, scanner: pairingScanner)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) { orientationProbe }
        // 斷線而殼層換成連線畫面：轉場重設、曲目清單關閉、唱機層直接移出（§4.5 外部事件、§4.8）
        .onChange(of: ShellPresentation.showsLibrary(state: connection.state, hasAlbums: !library.albums.isEmpty)) { _, shows in
            if !shows {
                albumOpen.reset()
                turntable.hideImmediately()
            }
        }
        // 開合轉場中開唱機：轉場凍結，關唱機（移出樹）後續跑（§4.5 外部事件表）
        .onChange(of: turntable.layer.isPresent) { _, present in
            if present {
                albumOpen.freeze()
            } else {
                albumOpen.resume()
                turntableButtonFocused = true
            }
        }
        #if DEBUG
        .onChange(of: connection.state) { _, state in
            if case .connected = state, ProcessInfo.processInfo.arguments.contains(AccessibilityID.openTurntableArgument) {
                turntable.open(reduceMotion: reduceMotion)
            }
        }
        #endif
    }

    /// 根層 ZStack（§4.7）：曲庫殼層群組（頂列＋瀏覽區＋播放列）整組可水平位移；唱機層為其 sibling，存在期間曲庫殼層不可點、不在 AX 樹
    private func libraryAndTurntable(size: CGSize) -> some View {
        let offsets = TurntableEntrance.offsets(slide: turntableSlide, width: size.width, reduceMotion: reduceMotion)
        return ZStack {
            libraryShell(size: size)
                .offset(x: offsets.library)
                .allowsHitTesting(!turntable.layer.isPresent)
                .accessibilityHidden(turntable.layer.isPresent)
            if turntable.layer.isPresent {
                TurntableView(model: turntable, onClose: { turntable.close(reduceMotion: reduceMotion) })
                    // 封套與唱片各帶自己的動畫，不隔離時它們會自行內插位置、不跟頁面一起滑（實測封套停在終點）
                    .geometryGroup()
                    .offset(x: offsets.turntable)
                    .opacity(offsets.turntableOpacity)
                    // 等同 UIKit accessibilityViewIsModal：兄弟（曲庫殼層）對輔助使用隱藏
                    .accessibilityAddTraits(.isModal)
                    .zIndex(1)
            }
        }
        // 唱機開著時回桌面：殼層暫時換成連線畫面、唱機被直接收掉，這裡的 onChange 不在樹上收不到 → 回來時依唱機實際狀態對齊（#6-1）
        .onAppear { turntableSlide = TurntableEntrance.slideTarget(turntable.layer) }
        // 插入時進度在 1（畫面外），下一拍才動畫到 0；離場動畫回 1，滑完 VM 才把唱機層移出樹
        .onChange(of: TurntableEntrance.slideTarget(turntable.layer)) { _, target in
            guard target == 0 else { return withAnimation(slideAnimation) { turntableSlide = 1 } }
            turntableSlide = 1
            Task { @MainActor in withAnimation(slideAnimation) { turntableSlide = 0 } }
        }
    }

    private var slideAnimation: Animation {
        .easeInOut(duration: (reduceMotion ? TurntableEntrance.reduceMotionFade : TurntableEntrance.slide).secondsValue)
    }

    /// CR-023 外殼（s6-61-f8f9-shell.md §5.1）：背景鋪滿全畫面；內容不讓位；左上設定鈕、右上搜尋（LibraryView 內）、底部霧面膠囊浮在上面。
    /// 詳情是殼層內蓋住曲庫的一層（CR-020），底部膠囊在它之上、照常可按
    private func libraryShell(size: CGSize) -> some View {
        // 鍵盤疊在曲庫與詳情上、不讓它們讓位（使用者 2026-10-23 回報：搜尋時鍵盤把側封盒子壓成一半，
        // 此時開專輯，詳情沿用縮小的尺寸＝封面變小、名稱與播放鍵上移）；底部膠囊照舊浮在鍵盤上方
        ZStack(alignment: .topLeading) {
            LibraryView(model: library, openController: albumOpen, layout: browseLayout.layout)
                .ignoresSafeArea(.keyboard)
            albumDetail
                .ignoresSafeArea(.keyboard)
            AlbumStageView(controller: albumOpen, background: detailBackground)
                .ignoresSafeArea(.keyboard)
        }
        .coordinateSpace(.named(AlbumOpenController.space))
        // F10（E.3）：背景漸層鋪滿全畫面（含安全區）；詳情層蓋上自己的背景
        .background { PresetGradientView(preset: background.preset, scheme: colorScheme, reduceTransparency: reduceTransparency).ignoresSafeArea() }
        .overlay(alignment: .topLeading) { settingsButton }
        .overlay(alignment: .bottom) {
            BottomDock(model: nowPlaying, onOpenTurntable: { turntable.open(reduceMotion: reduceMotion) },
                       turntableButtonFocus: $turntableButtonFocused, cover: { await library.image(for: $0) },
                       layout: browseLayout.layout, onToggleLayout: { browseLayout.toggle() },
                       backgroundLuminance: dockLuminance(size: size))
                .padding(.bottom, DockPresentation.bottomMargin)
        }
        // 側封的 UIKit 無障礙容器不受 SwiftUI accessibilityHidden 管，經環境值自己藏
        .environment(\.libraryCovered, turntable.layer.isPresent)
        .sheet(isPresented: $showsSettings) {
            SettingsSheet(appearance: appearance, background: background, connection: connection)
        }
        .onAppear { albumOpen.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, value in albumOpen.reduceMotion = value }
    }

    /// 控制層後面的背景亮度：詳情開著＝詳情背景；否則＝側封漸層（側封另疊四周壓暗）
    private func dockLuminance(size: CGSize) -> Double {
        let preset = background.preset, scheme = colorScheme, rt = reduceTransparency
        let detailOpen = albumOpen.album != nil, content = detailBackground.content, spines = browseLayout.layout == .spines
        return DetailBackgroundModel.averageLuminance(in: DockPresentation.controlRect(in: size)) { point in
            if detailOpen {
                return DetailBackgroundModel.color(content, preset: preset, scheme: scheme, reduceTransparency: rt, at: point, in: size)
            }
            let base = rt ? BackgroundModel.baseColor(preset: preset, scheme: scheme)
                : BackgroundModel.presetColor(preset: preset, scheme: scheme, at: point, in: size)
            return spines ? base.over(.black, alpha: BackgroundModel.vignetteAlpha(at: point, in: size)) : base
        }
    }

    /// 左上設定鈕（CR-023 D2）：詳情開著時隱藏、返回鍵佔左上
    @ViewBuilder private var settingsButton: some View {
        if ShellChrome.showsSettingsButton(detailOpen: albumOpen.album != nil) {
            Button { showsSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 17, weight: .medium))
                    .frame(width: 38, height: 38)
                    .tintedGlass(in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Settings"))
            .accessibilityIdentifier(AccessibilityID.settingsButton)
            .padding(.leading, ShellChrome.cornerInset.horizontal)
            .padding(.top, ShellChrome.cornerInset.vertical)
            .transition(.opacity)
        }
    }

    @ViewBuilder private var albumDetail: some View {
        #if DEBUG
        AlbumDetailView(controller: albumOpen, model: albumTracks, currentTrackID: nowPlaying.currentTrackID,
                        background: detailBackground, backgroundSettings: background, benchmark: benchmark)
        #else
        AlbumDetailView(controller: albumOpen, model: albumTracks, currentTrackID: nowPlaying.currentTrackID,
                        background: detailBackground, backgroundSettings: background)
        #endif
    }

    /// 系統「減少動態效果」；DEBUG 另可用啟動參數強制（XCUITest 動不到系統設定，§4.9）
    private var reduceMotion: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(AccessibilityID.forceReduceMotionArgument) { return true }
        #endif
        return systemReduceMotion
    }

    /// 掃描器：DEBUG 的 UI 測試以假載荷代替相機（模擬器沒有相機）
    private var pairingScanner: PairingScanner {
        #if DEBUG
        if let fakePayload { return .fake(fakePayload) }
        #endif
        return .live
    }

    /// UI 測試讀的方向值（F-V-01）：只在 DEBUG 建置出現。XCUITest 的視窗 frame 以裝置座標回報、
    /// 轉直後即使畫面仍是橫的也會讀成直的（2026-10-15 實測 1032×1376），所以由 app 自己報
    @ViewBuilder private var orientationProbe: some View {
        #if DEBUG
        GeometryReader { proxy in
            Text(verbatim: proxy.size.width > proxy.size.height ? "landscape" : "portrait")
                .font(.caption2)
                .foregroundStyle(.clear)
                .accessibilityIdentifier(AccessibilityID.shellOrientation)
        }
        #endif
    }
}

enum ShellPresentation {
    /// 連上就顯示曲庫；斷線後若已有清單仍顯示（灰掉的狀態列見 LibraryView），配對與首次連線時顯示連線畫面
    static func showsLibrary(state: ConnectionViewModel.State, hasAlbums: Bool) -> Bool {
        switch state {
        case .connected: true
        case .connecting, .retrying, .waitingForMac: hasAlbums
        case .unpaired, .pairing, .pairingFailed, .needsRepair, .suspended: false
        }
    }
}
