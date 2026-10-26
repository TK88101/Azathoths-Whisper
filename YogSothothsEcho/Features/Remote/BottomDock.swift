import RemoteProtocol
import SwiftUI
import UIKit

/// 底部膠囊的判斷（CR-023；s6-61-f8f9-shell.md §5.3）：只看「是否有目前曲」，未連線＝idle
enum DockPresentation {
    enum State: Equatable { case idle, hasCurrentTrack }

    /// 控制層在寬膠囊內的內縮
    static let controlInset = (horizontal: CGFloat(62), vertical: CGFloat(7))
    static let bottomMargin: CGFloat = 26
    static let controlCornerRadius: CGFloat = 25
    /// 上一首／下一首圖示框邊長；▶▶ 圖形右側留白＝框寬 3/24
    static let skipIconSide: CGFloat = 22
    /// 小封面離左緣、▶▶ 可見圖形離右緣都是 16 pt
    static let controlPadding = (leading: CGFloat(16), trailing: CGFloat(16) - skipIconSide * 3 / 24)
    static let coverSide: CGFloat = 36
    static let frostTint = 0.5
    static let controlTint = 0.14
    static let widthAnimation = 0.35

    static func state(currentTrackID: String?, isConnected: Bool) -> State {
        isConnected && currentTrackID != nil ? .hasCurrentTrack : .idle
    }

    static func size(_ state: State) -> CGSize {
        state == .idle ? CGSize(width: 168, height: 46) : CGSize(width: 640, height: 64)
    }

    /// 控制層透到背景：字色依控制層後面背景的亮度（同詳情頁門檻與遲滯；使用者 2026-10-23「太黑的背景時看不清」）
    static func controlInk(luminance: Double, previous: DetailInk?) -> DetailInk {
        DetailBackgroundModel.ink(luminance: luminance, previous: previous)
    }

    /// 控制層在畫面上的框（取樣背景亮度用）
    static func controlRect(in canvas: CGSize) -> CGRect {
        let dock = size(.hasCurrentTrack)
        let width = dock.width - 2 * controlInset.horizontal, height = dock.height - 2 * controlInset.vertical
        return CGRect(x: (canvas.width - width) / 2, y: canvas.height - bottomMargin - controlInset.vertical - height,
                      width: width, height: height)
    }

    /// 霧面下層上的圖示：深灰（不跟主題）
    static let frostInk = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x40 / 255)
}

enum ShellChrome {
    /// 詳情開著時設定鈕隱藏、返回鍵佔左上（使用者 2026-10-23 認可）
    static func showsSettingsButton(detailOpen: Bool) -> Bool { !detailOpen }

    /// 左上設定鈕、右上搜尋框離安全區邊緣（命中框 44 pt、視覺 38 pt）
    static let cornerInset = (horizontal: CGFloat(22), vertical: CGFloat(12))
}

/// 霧面膠囊挖掉控制層那塊（控制層比下層透明）
private struct DockRing: Shape {
    let controlInset: (horizontal: CGFloat, vertical: CGFloat)

    func path(in rect: CGRect) -> Path {
        let outer = Path(roundedRect: rect, cornerRadius: rect.height / 2)
        let inner = Path(roundedRect: rect.insetBy(dx: controlInset.horizontal, dy: controlInset.vertical),
                         cornerRadius: DockPresentation.controlCornerRadius)
        return outer.subtracting(inner)
    }
}

/// 底部霧面膠囊（F-P-08，CR-023）：無目前曲＝兩鈕小膠囊（展示方式、唱盤；CR-029）；有目前曲＝加寬，中間疊控制層。
/// 控制層 ◀◀ 前有 Genius 鈕（CR-030；舊 Mac 不顯示）。展示方式鈕由殼層給（nil＝不顯示）
struct BottomDock: View {
    let model: NowPlayingViewModel
    var onOpenTurntable: () -> Void = {}
    var turntableButtonFocus: AccessibilityFocusState<Bool>.Binding?
    /// 控制層小封面
    var cover: ((AlbumSummary) async -> UIImage?)?
    /// CR-024：目前展示方式（左鍵圖示顯示點了會變成的樣子）；nil＝不顯示左鍵
    var layout: BrowseLayout?
    var onToggleLayout: () -> Void = {}
    /// 控制層後面背景的 WCAG 亮度（殼層以背景純函式取樣）；nil＝依主題
    var backgroundLuminance: Double?
    @State private var lastInk: DetailInk?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var coverImage: UIImage?

    private var state: DockPresentation.State {
        DockPresentation.state(currentTrackID: model.currentTrackID, isConnected: model.isConnected)
    }

    var body: some View {
        VStack(spacing: 8) {
            notice
            dock
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: DockPresentation.widthAnimation), value: state)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.nowPlayingBar)
    }

    @ViewBuilder private var dock: some View {
        let size = DockPresentation.size(state)
        switch state {
        case .idle:
            // CR-031：Genius 可見＝三等分；舊 Mac（hidden）＝不產生中間欄，版面同兩欄
            HStack(spacing: 0) {
                layoutButton.frame(maxWidth: .infinity).accessibilitySortPriority(3)
                if model.geniusButton != .hidden {
                    geniusButton.frame(maxWidth: .infinity).foregroundStyle(DockPresentation.frostInk).accessibilitySortPriority(2)
                }
                turntableButton.frame(maxWidth: .infinity).accessibilitySortPriority(1)
            }
            .frame(width: size.width, height: size.height)
            .frostedGlass(in: Capsule())
        case .hasCurrentTrack:
            ZStack {
                Color.clear.frostedGlass(in: DockRing(controlInset: DockPresentation.controlInset))
                HStack(spacing: 0) {
                    layoutButton.frame(width: DockPresentation.controlInset.horizontal)
                    controlLayer
                        .padding(.vertical, DockPresentation.controlInset.vertical)
                    turntableButton.frame(width: DockPresentation.controlInset.horizontal)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private var inkKind: DetailInk {
        DockPresentation.controlInk(luminance: backgroundLuminance ?? (colorScheme == .dark ? 0 : 1), previous: lastInk)
    }

    private var ink: Color { inkKind.color }

    private var controlLayer: some View {
        let enabled = PlaybackPresentation.controlsEnabled(model.availability)
        let playing = model.clock?.event.state == .playing
        return HStack(spacing: 14) {
            coverView
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: model.albumTitle ?? "—").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(verbatim: model.currentAlbum?.artist ?? "").font(.caption).opacity(0.72).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // VoiceOver 與 UI 測試讀的是目前曲名（畫面上顯示專輯・樂團，使用者 2026-10-23）
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(Text(verbatim: model.trackTitle ?? (model.currentTrackID == nil ? "—" : "…")))
            .accessibilityValue(Text(verbatim: [model.albumTitle, model.currentAlbum?.artist].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityIdentifier(AccessibilityID.nowPlayingTitle)
            HStack(spacing: 4) {
                geniusButton
                button(.previous, .skip(forward: false), label: "Previous", id: AccessibilityID.nowPlayingPrevious) { await model.previous() }
                button(.toggle, .symbol(playing ? "pause.fill" : "play.fill"), label: playing ? "Pause" : "Play",
                       id: AccessibilityID.nowPlayingToggle) { await model.toggle() }
                button(.next, .skip(forward: true), label: "Next", id: AccessibilityID.nowPlayingNext) { await model.next() }
            }
            .disabled(!enabled)
        }
        .foregroundStyle(ink)
        .onChange(of: inkKind, initial: true) { _, value in lastInk = value }
        .padding(.leading, DockPresentation.controlPadding.leading)
        .padding(.trailing, DockPresentation.controlPadding.trailing - TransportButton.dockHitInset)
        .frame(maxHeight: .infinity)
        .clearGlass(in: RoundedRectangle(cornerRadius: DockPresentation.controlCornerRadius))
    }

    @ViewBuilder private var coverView: some View {
        Group {
            if let album = model.currentAlbum {
                AlbumCoverImage(album: album, image: coverImage)
                    .task(id: album.artworkToken ?? album.id) { coverImage = await cover?(album) }
            } else {
                Color.gray.opacity(0.4)
            }
        }
        .frame(width: DockPresentation.coverSide, height: DockPresentation.coverSide)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private func button(_ control: NowPlayingViewModel.Control, _ glyph: TransportButton.Glyph, label: LocalizedStringKey, id: String,
                        action: @escaping @MainActor () async -> Void) -> some View {
        TransportButton(glyph: glyph, label: label, id: id, pendingCount: model.pendingCount(control),
                        isSlow: model.isSlow(control), size: .dock, action: action)
    }

    /// Genius（CR-030）：與 ◀◀／❚❚／▶▶ 同尺寸；未授權仍可按（只給提示），停止中停用
    @ViewBuilder private var geniusButton: some View {
        let state = model.geniusButton
        if state != .hidden {
            TransportButton(glyph: .genius, label: "Genius", id: AccessibilityID.nowPlayingGenius,
                            pendingCount: model.pendingCount(.genius), isSlow: model.isSlow(.genius), size: .dock,
                            hint: state == .needsAccessibility ? PlaybackPresentation.text(.needsAccessibility) : nil) {
                await model.genius()
            }
            .disabled(!GeniusPresentation.isPressable(state))
        }
    }

    @ViewBuilder private var layoutButton: some View {
        if let layout {
            Button(action: onToggleLayout) {
                Group {
                    if layout.buttonIcon == .squares {
                        Image(systemName: "square.grid.2x2.fill").font(.system(size: 20))
                    } else {
                        SpineStackGlyph().frame(width: 24, height: 24)
                    }
                }
                    .foregroundStyle(DockPresentation.frostInk)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(layout.buttonIcon == .squares ? Text("Show as grid") : Text("Show as spines"))
            .accessibilityIdentifier(AccessibilityID.browseLayoutButton)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var turntableButton: some View {
        let button = Button(action: onOpenTurntable) {
            // 使用者 2026-10-24：同心圓（record.circle）不像；SF Symbols 無黑膠唱片（推測），選實心光碟
            Image(systemName: "opticaldisc.fill")
                .font(.system(size: 22))
                .foregroundStyle(DockPresentation.frostInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Turntable"))
        .disabled(!model.isConnected)
        .accessibilityIdentifier(AccessibilityID.nowPlayingOpenTurntable)
        if let turntableButtonFocus { button.accessibilityFocused(turntableButtonFocus) } else { button }
    }

    /// 提示：非行動提示由 `fader` 淡出；可重試的錯誤持續到狀態恢復（同現行 PlaybackNoticeRow）
    @ViewBuilder private var notice: some View {
        if let notice = model.notice {
            PlaybackNoticeRow(notice: notice, id: AccessibilityID.nowPlayingNotice, onResync: model.resync, onRetry: model.resync)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .tintedGlass(in: Capsule())
        } else if let text = PlaybackPresentation.availabilityText(model.availability) {
            HStack(spacing: 12) {
                Text(text).font(.footnote)
                    .accessibilityIdentifier(AccessibilityID.nowPlayingNotice)
                if model.availability == .musicNotRunning {
                    Button("Retry") { model.resync() }.font(.footnote).accessibilityIdentifier(AccessibilityID.nowPlayingRetry)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .tintedGlass(in: Capsule())
        }
    }
}
