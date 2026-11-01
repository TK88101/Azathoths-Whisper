import SwiftUI

/// 待處理歌手（以寫法家族列，⑧ 計劃 §4.3）：指定樣式／照目前樣式／清除；全合格者可批次照目前樣式
struct LibraryCheckArtistsView: View {
    let model: LibraryCheckViewModel
    @State private var bulk: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !bulk.isEmpty {
                Button("library_check_bulk_keep \(bulk.count)") {
                    model.keepFallbackInBulk(keys: Array(bulk))
                    bulk = []
                }
                .accessibilityIdentifier(AccessibilityID.libraryCheckBulkKeep)
            }
            List(model.report?.artists ?? [], id: \.key) { artist in
                LibraryCheckArtistRow(model: model, artist: artist, isInBulk: Binding(
                    get: { bulk.contains(artist.key) },
                    set: { if $0 { bulk.insert(artist.key) } else { bulk.remove(artist.key) } }
                ))
            }
            .scrollContentBackground(.hidden)
        }
    }
}

struct LibraryCheckArtistRow: View {
    let model: LibraryCheckViewModel
    let artist: LibraryGateReport.ArtistIssue
    @Binding var isInBulk: Bool
    @State private var alsoApply: Set<String> = []

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if artist.canKeepFallbackInBulk && artist.decision == nil && !artist.isSigned {
                Toggle(isOn: $isInBulk) { EmptyView() }.toggleStyle(.checkbox).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: artist.spellings.joined(separator: " / ")).font(.headline)
                Text("library_check_songs_albums \(artist.songs) \(artist.albums)").font(.caption).foregroundStyle(Theme.Gray.g400)
                HStack(spacing: 8) {
                    ForEach(LibraryGateReport.Issue.ordered(artist.issues), id: \.self) { issue in
                        Text(LocalizedStringKey(LibraryCheckPresentation.issue(issue)))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .background(Theme.dangerDeep)
                    }
                    Text(LocalizedStringKey(LibraryCheckPresentation.mbStatus(artist.mbStatus))).font(.caption).foregroundStyle(Theme.Gray.g400)
                    if let decision = artist.decision { decisionText(decision.choice).font(.caption) }
                }
                if !artist.sameNormalizedName.isEmpty && !artist.isSigned {
                    Toggle(isOn: Binding(
                        get: { alsoApply == Set(artist.sameNormalizedName) },
                        set: { alsoApply = $0 ? Set(artist.sameNormalizedName) : [] }
                    )) {
                        Text("library_check_apply_too \(artist.sameNormalizedName.joined(separator: " / "))").font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Spacer()
            if artist.isSigned {
                Text("library_check_signed_note").font(.caption).foregroundStyle(Theme.Gray.g400).frame(maxWidth: 240, alignment: .trailing)
            } else {
                actions
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.libraryCheckArtistPrefix + artist.key)
    }

    private var targets: [String] {
        artist.spellings + Array(alsoApply)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Menu("library_check_choose_style") {
                Section("library_check_style_genre") {
                    ForEach(LibraryCheckPresentation.styleChoices.genre, id: \.self) { id in
                        Button(id) { model.decide(.style(rowID: id), forArtists: targets) }
                    }
                }
                Section("library_check_style_generic") {
                    ForEach(LibraryCheckPresentation.styleChoices.generic, id: \.self) { id in
                        Button(id) { model.decide(.style(rowID: id), forArtists: targets) }
                    }
                }
            }
            .fixedSize()
            .accessibilityIdentifier(AccessibilityID.libraryCheckChooseStyle)
            Button("library_check_keep_fallback") { model.decide(.keepFallback, forArtists: targets) }
                .accessibilityIdentifier(AccessibilityID.libraryCheckKeepFallback)
            if artist.decision != nil {
                Button("library_check_clear") { model.clear(forArtists: targets) }
            }
        }
    }

    private func decisionText(_ choice: ArtistDecision.Choice) -> Text {
        switch choice {
        case .style(let id): Text("library_check_decision_style \(id)")
        case .keepFallback: Text("library_check_decision_keep")
        }
    }
}
