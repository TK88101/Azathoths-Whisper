import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.2：解決來源（key＋auditKey＋trace）；`resolve` 由 `explain` 推出、同一份判定
@Suite("Profile explanation")
struct ProfileExplanationTests {
    private func explain(
        _ artist: String = "Velvet Lanterns", genre: String? = "Glimmerwave Foo", mb: ArtistGenres = .unresolved,
        lyrics: LyricsEvidence = .text(isJapanese: false),
        rows: [SongProfileResolver.KeywordRow] = SongProfileResolver.keywordRows,
        genericRows: [SongProfileResolver.KeywordRow] = SongProfileResolver.genericRows
    ) -> ProfileExplanation {
        SongProfileResolver.explain(artist: artist, genre: genre, lyrics: lyrics, artistGenres: mb, rows: rows, genericRows: genericRows)
    }

    @Test func aSignedBandNamesTheBandAndSkipsTheTrace() {
        let explanation = explain("mayhem", genre: "Pop", mb: .verified(["pop punk"]))
        #expect(explanation.key == .signed("Mayhem"))
        #expect(explanation.auditKey == .signed("Mayhem"))
        #expect(explanation.trace.isEmpty)
    }

    @Test func japaneseLyricsAreThePolicy() {
        let explanation = explain(lyrics: .text(isJapanese: true))
        #expect(explanation.key == .jpop)
        #expect(explanation.auditKey == .jpop)
    }

    @Test func unknownLyricsArePendingWithoutAnAuditKey() {
        let explanation = explain(lyrics: .unknown)
        #expect(explanation.key == .pending)
        #expect(explanation.auditKey == nil)
        #expect(explanation.resolution == .pending)
    }

    @Test func aVerifiedMBHitRecordsTheRowsAndTheLayer() {
        let explanation = explain(genre: "Rock", mb: .verified(["black metal"]))
        #expect(explanation.key == .rows(.mbGenre, ["black"]))
        #expect(explanation.auditKey == .rows(["black"]))
        #expect(explanation.trace == [.init(layer: .mbGenre, rowIDs: ["black"], outcome: .adopted)])
    }

    @Test func theAppleLayerIsUsedWhenMBIsUnresolved() {
        let explanation = explain(genre: "Black Metal", mb: .unresolved)
        #expect(explanation.key == .rows(.appleGenre, ["black"]))
        #expect(explanation.trace == [.init(layer: .appleGenre, rowIDs: ["black"], outcome: .adopted)])
    }

    @Test func everyMissedLayerIsInTheTraceBeforeTheGenericHit() {
        let explanation = explain(genre: "Glimmerwave Foo", mb: .verified(["industrial"]))
        #expect(explanation.key == .rows(.genericMB, ["industrial"]))
        #expect(explanation.trace == [
            .init(layer: .mbGenre, rowIDs: [], outcome: .noHit),
            .init(layer: .appleGenre, rowIDs: [], outcome: .noHit),
            .init(layer: .genericMB, rowIDs: ["industrial"], outcome: .adopted),
        ])
    }

    @Test func noMatchKeepsTheWholeTrail() {
        let explanation = explain(genre: "Glimmerwave Foo", mb: .unresolved)
        #expect(explanation.key == .none)
        #expect(explanation.auditKey == nil)
        #expect(explanation.resolution == .noMatch)
        #expect(explanation.trace.map(\.layer) == [.appleGenre, .genericApple])
        #expect(explanation.trace.allSatisfy { $0.outcome == .noHit })
    }

    @Test func theGenericRowIsSuppressedByASpecificHit() {
        #expect(explain(genre: "Rock", mb: .verified(["metal", "black metal"])).key == .rows(.mbGenre, ["black"]))
    }

    @Test func aRowThatCannotComposeIsRecordedAndFallsThrough() {
        let dead = SongProfileResolver.KeywordRow(id: "dead", keywords: ["glimmerwave"], representatives: [], tags: [.frenchhouse], axes: [:], isGeneric: false)
        let explanation = explain(genre: "Glimmerwave Foo", rows: [dead], genericRows: [])
        #expect(explanation.trace.first == .init(layer: .appleGenre, rowIDs: ["dead"], outcome: .notComposable))
        #expect(explanation.key == .none)
    }

    @Test func theSameRowsGiveTheSameAuditKeyAndProfileFromAnyLayer() {
        let mb = explain(genre: "Rock", mb: .verified(["black metal"]))
        let apple = explain(genre: "Black Metal", mb: .unresolved)
        #expect(mb.auditKey == apple.auditKey)
        #expect(mb.resolution.profile == apple.resolution.profile)
    }

    @Test(arguments: [
        ("Mayhem", "Pop", ArtistGenres.unresolved, LyricsEvidence.text(isJapanese: false)),
        ("Velvet Lanterns", "Black Metal", .verified(["industrial"]), .text(isJapanese: false)),
        ("Velvet Lanterns", nil, .unknown, .text(isJapanese: false)),
        ("Velvet Lanterns", nil, .verified(["black metal"]), .text(isJapanese: false)),
        ("Velvet Lanterns", "Pop", .unresolved, .text(isJapanese: true)),
        ("Velvet Lanterns", "Glimmerwave Foo", .verified([]), .text(isJapanese: false)),
        ("Velvet Lanterns", "Electronic", .unresolved, .unknown),
    ] as [(String, String?, ArtistGenres, LyricsEvidence)])
    func resolveIsTheExplanationsResolution(artist: String, genre: String?, mb: ArtistGenres, lyrics: LyricsEvidence) {
        #expect(SongProfileResolver.resolve(artist: artist, genre: genre, lyrics: lyrics, artistGenres: mb)
            == explain(artist, genre: genre, mb: mb, lyrics: lyrics).resolution)
    }

    @Test func rowIDsAreUniqueAcrossKeywordAndGenericRows() {
        let ids = (SongProfileResolver.keywordRows + SongProfileResolver.genericRows).map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
