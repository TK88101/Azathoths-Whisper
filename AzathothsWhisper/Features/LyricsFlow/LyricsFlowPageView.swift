import SwiftUI

/// Editor 頁：Editor＋其上的 Cover Flow 層（計劃 §6、D2）。
///
/// - Cover Flow **常駐**、以 `offset` 升降：降下時只露把手；條帶從掛載起就在，牌組只走運行時路徑
///   （不經初始值路徑——H-02 缺陷 3 的觸發條件在此結構下不存在）
/// - Editor **條件掛載**：只在畫面＝Editor 時存在，被遮住的 NSTextView 不會搶焦點、不會吃點擊
/// - 升降動畫只作用在 `offset`（key＝畫面）；牌組變更不帶動畫（D6）；減少動態效果時無位移動畫
struct LyricsFlowPageView: View {
    let editor: EditorViewModel
    let lyricsFlow: LyricsFlowModel
    let coverFlow: CoverFlowViewModel
    let lyricsFX: LyricsFXViewModel
    /// 升起層畫什麼（A2 計劃 §3.3）
    let raisedStyle: RaisedLayerStyle
    let onSelectStyle: (RaisedLayerStyle) -> Void
    /// Editor 分頁在前（Batch 覆蓋時為 false）
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var coverFlowFocused: Bool

    /// 設計稿：cubic-bezier(.16, 1, .3, 1) 620ms
    private static let riseAnimation = Theme.Motion.layerShift

    private var isRaised: Bool { lyricsFlow.surface == .coverFlow }
    /// Cover Flow 可互動、可持有焦點：升起 ∧ 分頁在前 ∧ 畫面＝Cover Flow（Codex R1 #5：觀察值要含風格，焦點才會真的放掉）
    private var coverFlowIsInteractive: Bool { isRaised && isActive && raisedStyle == .coverFlow }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if !isRaised {
                    editorLayer
                        .padding(.bottom, LyricsFlowHandleView.height)
                }
                coverFlowLayer
                    .frame(height: proxy.size.height)
                    // 動畫只包住 offset：換歌時「畫面翻轉＋換牌」在同一次更新，若用 value 版動畫，
                    // 條帶的捲動位置也會被捲進動畫，中途回呼會被誤判為使用者接管（K5）
                    .animation(reduceMotion ? nil : Self.riseAnimation) { layer in
                        layer.offset(y: isRaised ? 0 : max(0, proxy.size.height - LyricsFlowHandleView.height))
                    }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
        // AC14：升起時 Cover Flow 持有焦點（方向鍵步進），降下時交還（Editor 可打字）
        .onChange(of: coverFlowIsInteractive, initial: true) { _, focusable in
            coverFlowFocused = focusable
        }
        #if DEBUG
        .overlay(alignment: .topTrailing) { surfaceProbe }
        .overlay(alignment: .topLeading) { styleProbe }
        #endif
    }

    #if DEBUG
    /// UITests 判定升降用（見 `AccessibilityID.surfaceProbe`）
    private var surfaceProbe: some View {
        AccessibilityProbe(id: AccessibilityID.surfaceProbe, value: isRaised ? AccessibilityID.raised : AccessibilityID.lowered)
    }

    /// UITests 判定升起層畫面用（見 `AccessibilityID.raisedStyleProbe`）
    private var styleProbe: some View {
        AccessibilityProbe(id: AccessibilityID.raisedStyleProbe, value: raisedStyle.rawValue)
    }
    #endif

    private var editorLayer: some View {
        EditorView(
            model: editor,
            lyricsStatus: boundStatus,
            canMarkNoLyrics: boundStatus == .missing && !editor.isBusy,
            onMarkNoLyrics: markNoLyrics
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.editorLayer)
    }

    private var coverFlowLayer: some View {
        VStack(spacing: 0) {
            LyricsFlowHandleView(
                isRaised: isRaised,
                ticks: LyricsFlowHandle.ticks(cards: coverFlow.cards) { coverFlow.status(for: $0) },
                style: raisedStyle,
                action: lyricsFlow.toggleHandle,
                onSelectStyle: onSelectStyle
            )
            // Cover Flow 常駐、不因切換而重新掛載（H-02 缺陷 3：條帶不得經初始值路徑）；切到特效時只是看不見、點不到
            ZStack {
                CoverFlowView(
                    model: coverFlow,
                    isInteractive: coverFlowIsInteractive,
                    focus: $coverFlowFocused,
                    upcoming: lyricsFlow.upcoming,
                    prefersReducedMotion: reduceMotion,
                    // 傳實際判定值給狀態機（Codex R7-③）：可點資格以條帶最新回報的幾何為準
                    onTapPlayingCard: { lyricsFlow.tapPlayingCard(isCentered: coverFlow.isPlayingCardCentered) }
                )
                .opacity(raisedStyle == .coverFlow ? 1 : 0)
                .allowsHitTesting(raisedStyle == .coverFlow)
                // 不加 `.accessibilityHidden`：透明度 0 本來就不在無障礙樹上；而在這層掛它（即使是 false）
                // 會讓播放卡按鈕的 AX 位置變成無限大、點不到（2026-10-06 UI 測試實測）
                if raisedStyle == .lyricsFX {
                    LyricsFXView(model: lyricsFX, reduceMotion: reduceMotion || lyricsFX.forcesReducedMotion)
                }
            }
        }
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.coverFlowLayer)
    }

    /// Editor 綁定曲＝當前曲時才顯示狀態（B-13：綁定曲可能落後於當前曲）
    private var boundStatus: LyricsStatus? {
        guard let bound = editor.boundTrackID, !bound.isEmpty,
              bound == lyricsFlow.state.nowPlayingPersistentID
        else { return nil }
        return lyricsFlow.status
    }

    private func markNoLyrics() {
        guard let bound = editor.boundTrackID else { return }
        lyricsFlow.markNoLyrics(persistentID: bound)
    }
}
