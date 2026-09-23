import AppKit
import SwiftUI

// Editor 主面板（py:139-189）：Now Editing 卡片 → 控制列 → 歌詞框
struct EditorView: View {
    @Bindable var model: EditorViewModel
    /// 綁定曲的歌詞狀態（計劃 AC7）；nil＝沒在播或綁定曲不是當前曲
    let lyricsStatus: LyricsStatus?
    /// 「No lyrics for this song」只接受已知缺詞的當前曲（AC5、R6-B3）
    let canMarkNoLyrics: Bool
    let onMarkNoLyrics: () -> Void

    var body: some View {
        VStack(spacing: 24) {                 // gap-6
            nowEditingCard
            controlsRow
            lyricsBox
        }
        .padding(.horizontal, 48)             // md:px-12
        .padding(.vertical, 32)               // md:py-8
        .frame(maxWidth: 1152)                // max-w-6xl
        .frame(maxWidth: .infinity)           // mx-auto
    }

    // MARK: Now Editing（py:140-149）

    private var nowEditingCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: StatusText.nowEditing)
                        .font(Theme.Fonts.display(12))
                        .textCase(.uppercase)
                        .tracking(2.4)            // 0.2em @12px
                        .foregroundStyle(Theme.Gray.g500)
                    Spacer(minLength: 0)
                    statusChip
                }

                HStack(spacing: 0) {
                    Text(verbatim: model.artistLine)
                        .font(Theme.Fonts.mono(30, weight: .bold))
                        .foregroundStyle(.white)
                    Text(verbatim: StatusText.separator)
                        .font(Theme.Fonts.mono(30))
                        .foregroundStyle(Theme.Gray.g600)
                        .padding(.horizontal, 8)
                    Text(verbatim: model.titleLine)
                        .font(Theme.Fonts.mono(30, weight: .light))
                        .foregroundStyle(model.isAccessDenied ? Theme.danger : .white)
                }
                .tracking(-1.5)               // tracking-tighter
            }
            Spacer(minLength: 0)
        }
        .padding(24)                          // p-6
        .background(Theme.cardBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                // 缺詞＝紅色色條（設計稿）；其餘沿用 py:141 的淡白
                .fill(lyricsStatus == .missing ? Theme.danger : Color.white.opacity(0.1))
                .frame(width: 4)              // w-1
        }
        .overlay(Rectangle().strokeBorder(Theme.Gray.g800, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { model.requestHydrate() }   // py:745 headerClick → hydrate
    }

    /// 設計稿：卡片右上角的狀態字（✓ Lyrics in file／✗ Missing lyrics／— Marked: no lyrics）
    @ViewBuilder
    private var statusChip: some View {
        if let lyricsStatus {
            LyricsStatusLabel(status: lyricsStatus)
        }
    }

    // MARK: 控制列（py:150-180）

    private var controlsRow: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("source")
                    .font(Theme.Fonts.display(10, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Theme.Gray.g500)
                    .padding(.leading, 4)
                sourceSelect
                    .frame(width: 256)        // md:w-64
            }

            HStack(spacing: 16) {
                ActionButton(
                    symbol: .cloudDownload,
                    title: String(localized: "fetch_btn"),
                    isEnabled: !model.isBusy,
                    accessibilityID: AccessibilityID.fetchButton
                ) {
                    Task { await model.fetch() }
                }
                ActionButton(
                    symbol: .saveAlt,
                    title: String(localized: "write_btn"),
                    isEnabled: !model.isBusy,
                    accessibilityID: AccessibilityID.writeButton
                ) {
                    Task { await model.save() }
                }
            }
            Spacer(minLength: 0)
            markNoLyricsButton
        }
    }

    /// AC5：純音樂／找不到——記為已處理、升回，下次播不再跳 Editor（設計稿：右側、細框、灰字）
    private var markNoLyricsButton: some View {
        Button(action: onMarkNoLyrics) {
            Text("mark_no_lyrics")
                .font(Theme.Fonts.display(11))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Gray.g400)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .overlay(Rectangle().strokeBorder(Theme.Gray.g800, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canMarkNoLyrics)
        .opacity(canMarkNoLyrics ? 1 : 0.35)
        .accessibilityIdentifier(AccessibilityID.markNoLyrics)
    }

    /// py:154-162 的裝飾性下拉（B-19：切換不影響抓詞路徑）
    private var sourceSelect: some View {
        Menu {
            ForEach(DataSourceOption.allCases) { option in
                Button(option.title) { model.dataSource = option }
            }
        } label: {
            HStack(spacing: 0) {
                Text(verbatim: model.dataSource.title)
                    .font(Theme.Fonts.display(12))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                MaterialSymbol(.arrowDropDown, size: 16)
                    .foregroundStyle(Theme.Gray.g400)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .background(Color.black)
        .overlay(Rectangle().strokeBorder(Theme.Gray.g700, lineWidth: 1))
    }

    // MARK: 歌詞框（py:181-186）

    private var lyricsBox: some View {
        ZStack(alignment: .topLeading) {
            PlainTextEditor(
                // setter 只在使用者輸入時被呼叫（程式寫入走 model → view）：據此取消待升回
                text: Binding(get: { model.lyricsText }, set: { model.userEditedLyrics($0) }),
                font: .monospacedSystemFont(ofSize: 16, weight: .regular),
                textColor: NSColor(Theme.Gray.g300),
                insets: NSSize(width: 24, height: 24),
                accessibilityID: AccessibilityID.lyricsText
            )

            if model.lyricsText.isEmpty {
                Text(verbatim: StatusText.lyricsPlaceholder)
                    .font(Theme.Fonts.mono(16))
                    .foregroundStyle(Theme.Gray.g800)
                    .padding(.horizontal, 29)
                    .padding(.vertical, 24)
                    .allowsHitTesting(false)
            }

            Text(verbatim: StatusText.txtMode)
                .font(Theme.Fonts.mono(10))
                .tracking(1)
                .foregroundStyle(Theme.Gray.g700)
                .opacity(0.5)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.editorBackground)
        .overlay(Rectangle().strokeBorder(Theme.Gray.g800, lineWidth: 1))
    }
}
