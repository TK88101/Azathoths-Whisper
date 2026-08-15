import AppKit
import SwiftUI

// Batch 面板（py:205-263）：header ／ 列表(flex-2)＋預覽(flex-1) ／ 自帶 footer。
// Batch 有自己的狀態欄與按鈕列，與 Editor 的 footer 是兩套東西（C-25）。
struct BatchView: View {
    @Bindable var model: BatchViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    listPane
                        .frame(width: proxy.size.width * 2 / 3)   // flex-[2] : flex-1
                    previewPane
                }
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(model.alertMessage ?? "", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        }
        .alert(StatusText.importAllConfirm, isPresented: $model.isConfirmingImportAll) {
            Button("Cancel", role: .cancel) { model.cancelImportAll() }
            Button("OK") { Task { await model.confirmImportAll() } }
        }
    }

    /// 原版的 alert() 是一次性彈窗，關閉即清空訊息
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }

    // MARK: 標題列（py:208-214）

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {                                  // gap-3
                Text(verbatim: StatusText.batchTitle)
                    .foregroundStyle(.white)
                Text(verbatim: StatusText.separator)
                    .foregroundStyle(Theme.Gray.g600)
                    .padding(.horizontal, 8)                       // mx-2
                Text(verbatim: model.albumName)
                    .foregroundStyle(Theme.Gray.g400)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(Theme.Fonts.display(18, weight: .bold))          // text-lg font-bold
            .textCase(.uppercase)
            .tracking(1.8)                                         // tracking-widest @18px
            .padding(.horizontal, 24)                              // px-6
            .padding(.vertical, 16)                                // py-4

            Rectangle().fill(Theme.border).frame(height: 1)
        }
        .background(Theme.background)
    }

    // MARK: 列表區（py:218-228）

    private var listPane: some View {
        VStack(spacing: 0) {
            listHeader
            listBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.cardBackground)                          // bg-[#050505]
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.border).frame(width: 1)
        }
    }

    private var listHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // py:220：# 欄無 data-i18n，是硬編碼符號（C-21）
                Text(verbatim: "#")
                    .frame(width: 48)
                    .padding(.vertical, 12)
                    .overlay(alignment: .trailing) { columnDivider }

                Text("col_artist")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .overlay(alignment: .trailing) { columnDivider }

                Text("col_title")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .overlay(alignment: .trailing) { columnDivider }

                Text("col_stat")
                    .frame(width: 96)
                    .padding(.vertical, 12)
            }
            .font(Theme.Fonts.display(10))                         // text-[10px]
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Theme.Gray.g500)

            Rectangle().fill(Theme.border).frame(height: 1)
        }
        .background(Theme.background)
    }

    private var columnDivider: some View {
        Rectangle().fill(Theme.border).frame(width: 1)
    }

    @ViewBuilder
    private var listBody: some View {
        switch model.listState {
        case .loading:
            // py:624：載入中列表區佔位（C-02）
            message(StatusText.loadingTracksFromMusic, color: Theme.Gray.g500)
        case .failed(let text):
            // py:629/636：紅字（C-26；原版此分支實際不可達，見 BatchViewModel 註解）
            message(text, color: Theme.danger)
        case .idle, .loaded:
            trackList
        }
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(Theme.Fonts.mono(12))
            .foregroundStyle(color)
            .padding(16)                                           // p-4
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trackList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.tracks.enumerated()), id: \.element.persistentID) { index, track in
                    BatchRow(
                        number: model.rowNumber(at: index),
                        track: track,
                        isSelected: model.selectedID == track.persistentID
                    ) {
                        model.select(track.persistentID)
                    }
                }
            }
        }
    }

    // MARK: 預覽區（py:231-237）

    private var previewPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("col_preview")
                    .foregroundStyle(Theme.Gray.g500)
                Spacer(minLength: 0)
                Text(verbatim: model.previewMeta)
                    .foregroundStyle(Theme.Gray.g600)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(Theme.Fonts.display(10))
            .textCase(.uppercase)
            .tracking(1)
            .padding(12)                                           // p-3
            .background(Theme.background)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.border).frame(height: 1)
            }

            previewBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)                                 // bg-[#0a0a0a]
    }

    private var previewBody: some View {
        ZStack(alignment: .topLeading) {
            // C-07：唯讀（py:236 readonly），仍可選取與捲動
            PlainTextEditor(
                text: $model.previewText,
                font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                textColor: NSColor(Theme.Gray.g400),
                insets: NSSize(width: 16, height: 16),
                isEditable: false,
                accessibilityID: "batch-preview"
            )

            if model.previewText.isEmpty {
                Text(verbatim: StatusText.previewPlaceholder)
                    .font(Theme.Fonts.mono(12))
                    .foregroundStyle(Theme.Gray.g800)
                    .padding(.horizontal, 21)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 頁尾（py:240-262）

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border).frame(height: 1)

            HStack(spacing: 0) {
                Text(verbatim: model.statusText)
                    .font(Theme.Fonts.display(10))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 16)

                HStack(spacing: 16) {                              // gap-4
                    batchButton(
                        .cloudDownload, "batch_fetch", id: "batch-fetch-missing",
                        isEnabled: !model.isLoadingAlbum && !model.isFetchingMissing
                    ) {
                        Task { await model.fetchMissing() }
                    }
                    // C-18：Import Selected 原版不禁自己，只在載入專輯時隨全體禁用
                    batchButton(
                        .saveAs, "batch_import", id: "batch-import-selected",
                        isEnabled: !model.isLoadingAlbum
                    ) {
                        Task { await model.importSelected() }
                    }
                    batchButton(
                        .doneAll, "batch_all", id: "batch-import-all",
                        isEnabled: !model.isLoadingAlbum && !model.isImportingAll
                    ) {
                        model.requestImportAll()
                    }
                }
            }
            .padding(16)                                           // p-4
        }
        .background(Theme.background)
    }

    private func batchButton(
        _ symbol: MaterialSymbolName,
        _ titleKey: String.LocalizationValue,
        id: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        ActionButton(
            symbol: symbol,
            title: String(localized: titleKey),
            isEnabled: isEnabled,
            horizontalPadding: 20,                                 // px-5
            verticalPadding: 8,                                    // py-2
            fontSize: 12,                                          // text-xs
            symbolSize: 14,                                        // text-[14px]
            accessibilityID: id,
            action: action
        )
    }
}
