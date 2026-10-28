import SwiftUI

extension LibraryGateReport.Row: Identifiable {
    var id: String { track.persistentID }
}

/// 逐首來源（⑧ 計劃 §4.2）：全曲庫表格、可搜尋、可只看不合格。曲名等只在畫面顯示，不寫日誌
struct LibraryCheckSongsView: View {
    let rows: [LibraryGateReport.Row]
    /// 報表算出的同歌手共識（來源欄的票數）
    let consensus: [String: AppleGenreConsensus]
    @State private var failingOnly = true
    @State private var search = ""
    /// 只看一位歌手（寫法家族鍵）；nil＝全部
    @State private var family: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("library_check_failing_only", isOn: $failingOnly).toggleStyle(.checkbox)
                TextField("library_check_search", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                if let family, let artist = rows.first(where: { $0.familyKey == family })?.track.artist {
                    Text("library_check_artist_filter \(artist)")
                    Button("library_check_clear_filter") { self.family = nil }
                }
            }
            Table(LibraryCheckPresentation.filter(rows, failingOnly: failingOnly, search: search, family: family)) {
                TableColumn("library_check_column_title") { Text(verbatim: $0.track.name) }
                TableColumn("library_check_column_artist") { Text(verbatim: $0.track.artist) }
                TableColumn("library_check_column_album") { Text(verbatim: $0.track.album) }
                TableColumn("library_check_column_apple_genre") { Text(verbatim: $0.track.genre) }
                TableColumn("library_check_column_source") { row in sourceText(row) }
                TableColumn("library_check_column_mb") { Text(LocalizedStringKey(LibraryCheckPresentation.mbStatus($0.mbStatus))) }
                TableColumn("library_check_column_issues") { row in issuesText(row) }
            }
            .contextMenu(forSelectionType: LibraryGateReport.Row.ID.self) { ids in
                if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                    Button("library_check_show_artist_songs") { family = row.familyKey }
                }
            }
        }
    }

    private func sourceText(_ row: LibraryGateReport.Row) -> some View {
        let text = LibraryCheckPresentation.source(for: row, consensus: consensus[row.familyKey])
        return HStack(spacing: 4) {
            Text(LocalizedStringKey(text.key))
            if !text.detail.isEmpty { Text(verbatim: text.detail).foregroundStyle(Theme.Gray.g400) }
            if let note = text.note { Text(LocalizedStringKey(note)).foregroundStyle(Theme.Gray.g400) }
            if let reason = row.noStyleReason { Text(LocalizedStringKey(LibraryCheckPresentation.noStyleReason(reason))).foregroundStyle(Theme.Gray.g400) }
        }
    }

    private func issuesText(_ row: LibraryGateReport.Row) -> some View {
        let issues = LibraryGateReport.Issue.ordered(row.issues)
        return Group {
            if issues.isEmpty {
                Text("library_check_no_issues").foregroundStyle(Theme.success)
            } else {
                Text(issues.map { String(localized: String.LocalizationValue(LibraryCheckPresentation.issue($0))) }.joined(separator: "、"))
                    .foregroundStyle(Theme.danger)
            }
        }
    }
}
