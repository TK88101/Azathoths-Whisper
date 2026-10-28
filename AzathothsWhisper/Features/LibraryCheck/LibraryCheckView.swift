import SwiftUI

/// 曲庫檢查視窗（⑧ 曲庫閘門計劃 §4.5）：四項計數＋待處理歌手＋逐首來源
struct LibraryCheckView: View {
    @Bindable var model: LibraryCheckViewModel
    @State private var tab: Tab = .artists

    enum Tab: Hashable {
        case artists, songs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let report = model.report { LibraryCheckCountsView(report: report) }
            if model.saveFailed {
                Text("library_check_save_failed").foregroundStyle(Theme.danger)
            }
            Picker(selection: $tab) {
                Text("library_check_tab_artists").tag(Tab.artists)
                Text("library_check_tab_songs").tag(Tab.songs)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch tab {
            case .artists: LibraryCheckArtistsView(model: model)
            case .songs: LibraryCheckSongsView(rows: model.report?.rows ?? [])
            }
        }
        .padding(20)
        .frame(minWidth: 960, minHeight: 640, alignment: .topLeading)
        .background(Theme.background)
        .foregroundStyle(Theme.coldWhite)
        .preferredColorScheme(.dark)
        // 計劃 §4.5-3：關視窗就取消掃描
        .onDisappear { model.cancelScan() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(LocalizedStringKey(LibraryCheckPresentation.status(model.status)))
                .font(.title2.weight(.semibold))
                .foregroundStyle(statusColor)
                .accessibilityIdentifier(AccessibilityID.libraryCheckStatus)
            if case .scanning(let done, let total) = model.status {
                Text("library_check_progress \(done) \(total)").foregroundStyle(Theme.Gray.g400)
                Button("library_check_cancel") { model.cancelScan() }
            } else {
                Button("library_check_rescan") { model.rescan() }
                    .accessibilityIdentifier(AccessibilityID.libraryCheckRescan)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let scannedAt = model.scannedAt {
                    Text("library_check_scanned_at \(scannedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                if let decidedAt = model.decisionsAppliedAt {
                    Text("library_check_decided_at \(decidedAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.Gray.g400)
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .passed: Theme.success
        case .failing, .incomplete: Theme.danger
        case .notScanned, .scanning, .needsRescan: Theme.coldWhite
        }
    }
}

/// 四項計數：全曲庫與有詞子集並列（§10-2）；署名待補是素面的子集（§10-1）
struct LibraryCheckCountsView: View {
    let report: LibraryGateReport

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            GridRow {
                Text(verbatim: "")
                Text("library_check_all").foregroundStyle(Theme.Gray.g400)
                Text("library_check_with_lyrics").foregroundStyle(Theme.Gray.g400)
            }
            line("library_check_identity", report.identity, report.identityWithLyrics, id: AccessibilityID.libraryCheckIdentityCount)
            line("library_check_composed", report.composed, report.composedWithLyrics, id: AccessibilityID.libraryCheckComposedCount)
            if report.signedPending != .zero {
                GridRow {
                    Text("library_check_signed_pending").padding(.leading, 16).foregroundStyle(Theme.Gray.g400)
                    count(report.signedPending)
                    Text(verbatim: "")
                }
            }
            line("library_check_readability", report.readability, report.readabilityWithLyrics, id: AccessibilityID.libraryCheckReadabilityCount)
            line("library_check_source", report.source, nil, id: AccessibilityID.libraryCheckSourceCount)
        }
    }

    private func line(_ title: LocalizedStringKey, _ all: LibraryGateReport.Count, _ withLyrics: LibraryGateReport.Count?, id: String) -> some View {
        GridRow {
            Text(title)
            count(all).accessibilityIdentifier(id)
            if let withLyrics { count(withLyrics) } else { Text(verbatim: "") }
        }
    }

    private func count(_ value: LibraryGateReport.Count) -> some View {
        Text("library_check_count \(value.songs) \(value.artists)")
            .monospacedDigit()
            .foregroundStyle(value == .zero ? Theme.success : Theme.coldWhite)
    }
}
