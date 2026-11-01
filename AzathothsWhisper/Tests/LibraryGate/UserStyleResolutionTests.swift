import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.3：使用者樣式層——樂團表 → pending → J-Pop → 使用者樣式 → MB → Apple → 通用
@Suite("User style resolution")
struct UserStyleResolutionTests {
    private func explain(
        _ artist: String = "Velvet Lanterns", genre: String? = "Black Metal", mb: ArtistGenres = .verified(["symphonic metal"]),
        lyrics: LyricsEvidence = .text(isJapanese: false), decision: ArtistDecision.Choice?
    ) -> ProfileExplanation {
        SongProfileResolver.explain(artist: artist, genre: genre, lyrics: lyrics, artistGenres: mb, decision: decision)
    }

    private func row(_ id: String) throws -> SongProfileResolver.KeywordRow {
        try #require((SongProfileResolver.keywordRows + SongProfileResolver.genericRows).first { $0.id == id })
    }

    @Test func aChosenStyleWinsOverMBAndApple() throws {
        let explanation = explain(decision: .style(rowID: "gothic"))
        #expect(explanation.resolution == .userStyle(SongProfileResolver.compose(rows: [try row("gothic")])!))
        #expect(explanation.key == .rows(.userStyle, ["gothic"]))
        #expect(explanation.auditKey == .rows(["gothic"]), "與單列命中同一個稽核鍵（R3-3）")
        #expect(explanation.resolution.source == .userStyle)
        #expect(explanation.resolution.source?.dependsOnLyrics == false)
    }

    @Test func aGenericRowCanBeChosenForANonSignedArtist() throws {
        #expect(explain(genre: "Rock", mb: .unresolved, decision: .style(rowID: "industrial")).key == .rows(.userStyle, ["industrial"]))
    }

    @Test func theSignedBandStillComesFirst() {
        #expect(explain("Mayhem", decision: .style(rowID: "gothic")).key == .signed("Mayhem"))
    }

    @Test func japaneseLyricsStillAreJPop() {
        #expect(explain(lyrics: .text(isJapanese: true), decision: .style(rowID: "gothic")).key == .jpop)
    }

    @Test func unknownLyricsStayPending() {
        #expect(explain(lyrics: .unknown, decision: .style(rowID: "gothic")).key == .pending)
    }

    @Test func keepFallbackDoesNotChangeTheResult() {
        #expect(explain(decision: .keepFallback) == explain(decision: nil))
        #expect(explain(genre: "Rock", mb: .unresolved, decision: .keepFallback).key == .none)
    }

    @Test func clearingTheDecisionRestoresTheOriginalResult() {
        #expect(explain(decision: nil).key == .rows(.mbGenre, ["symphonic"]))
    }

    @Test func anUnknownRowFallsThroughAndIsTraced() {
        let explanation = explain(decision: .style(rowID: "heavypower"))
        #expect(explanation.trace.first == .init(layer: .userStyle, rowIDs: ["heavypower"], outcome: .noHit))
        #expect(explanation.trace.filter { $0.layer == .userStyle }.count == 1)
        #expect(explanation.key == .rows(.mbGenre, ["symphonic"]))
    }

    @Test func aRejectedChosenRowFallsThrough() {
        let explanation = SongProfileResolver.explain(
            artist: "Velvet Lanterns", genre: "Black Metal", lyrics: .text(isJapanese: false), artistGenres: .unresolved,
            decision: .style(rowID: "gothic"), rejected: [.rows(["gothic"])]
        )
        #expect(explanation.trace.first == .init(layer: .userStyle, rowIDs: ["gothic"], outcome: .rejectedByReadability))
        #expect(explanation.key == .rows(.appleGenre, ["black"]))
    }

    @Test func everySelectableRowIsAuditedSoAChosenStylePassesTheReadabilityGate() {
        for id in ArtistDecisionBook.selectableRowIDs {
            #expect(ReadabilityPolicy.audited.contains(.rows([id])), "\(id)")
        }
    }

    @MainActor @Test func aUserStyleSessionDoesNotRecomposeWhenTheGenreChanges() {
        #expect(!LyricsFXViewModel.shouldCompose(settled: .userStyle, now: .genreRow))
        #expect(LyricsFXViewModel.shouldCompose(settled: .userStyle, now: .jpopPolicy), "跨 J-Pop 邊界照舊重組")
    }
}
