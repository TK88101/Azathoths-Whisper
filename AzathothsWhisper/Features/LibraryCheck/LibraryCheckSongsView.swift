import SwiftUI

extension LibraryGateReport.Row: Identifiable {
    var id: String { track.persistentID }
}

/// 逐首來源（⑧ 計劃 §4.2）：全曲庫表格、可搜尋、可只看不合格。曲名等只在畫面顯示，不寫日誌
struct LibraryCheckSongsView: View {
    let rows: [LibraryGateReport.Row]
    @State private var failingOnly = true
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("library_check_failing_only", isOn: $failingOnly).toggleStyle(.checkbox)
                TextField("library_check_search", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            }
            Table(LibraryCheckPresentation.filter(rows, failingOnly: failingOnly, search: search)) {
                TableColumn("library_check_column_title") { Text(verbatim: $0.track.name) }
                TableColumn("library_check_column_artist") { Text(verbatim: $0.track.artist) }
                TableColumn("library_check_column_album") { Text(verbatim: $0.track.album) }
                TableColumn("library_check_column_source") { row in sourceText(row) }
                TableColumn("library_check_column_mb") { Text(LocalizedStringKey(LibraryCheckPresentation.mbStatus($0.mbStatus))) }
                TableColumn("library_check_column_issues") { row in issuesText(row) }
            }
        }
    }

    private func sourceText(_ row: LibraryGateReport.Row) -> some View {
        let text = LibraryCheckPresentation.source(row.explanation.key)
        return HStack(spacing: 4) {
            Text(LocalizedStringKey(text.key))
            if !text.detail.isEmpty { Text(verbatim: text.detail).foregroundStyle(Theme.Gray.g400) }
            if let reason = row.noStyleReason { Text(LocalizedStringKey(LibraryCheckPresentation.noStyleReason(reason))).foregroundStyle(Theme.Gray.g400) }
        }
    }

    private func issuesText(_ row: LibraryGateReport.Row) -> some View {
        let issues = row.issues.sorted { "\($0)" < "\($1)" }
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
