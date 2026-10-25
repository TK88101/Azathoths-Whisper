import Foundation
import Testing

@testable import AzathothsWhisper

// ⑥b 計劃 §4.3（R1-8）：MB 層的落層規則——只升不降、不等、組不出來就落下一層
@Suite("Artist genre resolution")
struct ArtistGenreResolutionTests {
    private func resolve(
        _ artist: String = "Velvet Lanterns", genre: String?, mb: ArtistGenres, lyrics: LyricsEvidence = .text(isJapanese: false),
        rows: [SongProfileResolver.KeywordRow] = SongProfileResolver.keywordRows
    ) -> ProfileResolution {
        SongProfileResolver.resolve(artist: artist, genre: genre, lyrics: lyrics, artistGenres: mb, rows: rows)
    }

    @Test func verifiedMBGenresThatHitARowWin() {
        let resolution = resolve(genre: "Rock", mb: .verified(["black metal"]))
        #expect(resolution == .artistGenreRow(SongProfileResolver.compose(genres: ["black metal"])!))
        #expect(resolution.source == .verifiedArtistGenre)
        #expect(resolution.source?.dependsOnLyrics == false)
    }

    @Test func mbGenresThatHitNothingFallToTheAppleGenre() {
        #expect(resolve(genre: "Black Metal", mb: .verified(["experimental"])) == .genreRow(SongProfileResolver.compose(genres: ["Black Metal"])!))
    }

    @Test(arguments: [ArtistGenres.unresolved, .unknown, .verified([])])
    func noUsableMBEvidenceFallsToTheAppleGenre(mb: ArtistGenres) {
        #expect(resolve(genre: "Black Metal", mb: mb) == .genreRow(SongProfileResolver.compose(genres: ["Black Metal"])!))
        // 沒有任何列（含 ⑦ 通用列）認得的虛構曲風；⑦ 之前這裡用 "Experimental"，它已是實驗族的關鍵字
        #expect(resolve(genre: "Glimmerwave Foo", mb: mb) == .noMatch)
    }

    @Test func aVerifiedHitDoesNotWaitForTheAppleGenre() {
        #expect(resolve(genre: nil, mb: .verified(["black metal"])).source == .verifiedArtistGenre)
        #expect(resolve(genre: nil, mb: .unknown) == .pending, "MB 沒命中時照舊等 genre")
    }

    @Test func theSignedBandAndJPopStillComeFirst() {
        #expect(resolve("Mayhem", genre: "Pop", mb: .verified(["pop punk"])).source == .signedBand)
        #expect(resolve(genre: "Rock", mb: .verified(["black metal"]), lyrics: .text(isJapanese: true)) == .jpop)
        #expect(resolve(genre: "Rock", mb: .verified(["black metal"]), lyrics: .unknown) == .pending)
    }

    /// R3-4：合成後組不出六槽＝該層沒命中，落下一層；Apple 層也組不出來＝noMatch
    @Test func anUnplayableProfileFallsToTheNextLayer() {
        let unplayable = SongProfileResolver.KeywordRow(id: "probe", keywords: ["chiptune"], representatives: [], tags: [.frenchhouse], axes: [.bright: 0.5], isGeneric: false)
        let rows = SongProfileResolver.keywordRows + [unplayable]
        #expect(resolve(genre: "Black Metal", mb: .verified(["chiptune"]), rows: rows) == .genreRow(SongProfileResolver.compose(genres: ["Black Metal"])!))
        #expect(resolve(genre: "Chiptune", mb: .unknown, rows: rows) == .noMatch)
    }

    @Test func theDefaultCallKeepsTheOldBehaviour() {
        #expect(SongProfileResolver.resolve(artist: "Velvet Lanterns", genre: "Black Metal", lyrics: .text(isJapanese: false))
            == .genreRow(SongProfileResolver.compose(genres: ["Black Metal"])!))
    }
}
