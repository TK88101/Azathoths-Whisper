import Foundation
import Testing

@testable import AzathothsWhisper

// B1 計劃 §3.5：歌曲目標值。樂團覆寫表 → genre 關鍵字合成 → pending／mono
@Suite("Song profile resolver")
struct SongProfileResolverTests {
    private func resolve(_ artist: String, _ genre: String?) -> ProfileResolution {
        SongProfileResolver.resolve(artist: artist, genre: genre, lyrics: .text(isJapanese: false))
    }

    private func profile(_ resolution: ProfileResolution) throws -> SongProfile {
        guard let profile = resolution.profile else {
            Issue.record("期望 profile，實得 \(resolution)")
            throw CancellationError()
        }
        return profile
    }

    @Test func aKnownBandNeedsNoGenre() throws {
        let mayhem = try profile(resolve("Mayhem", nil))
        #expect(mayhem.tags == [.black])
        #expect(mayhem.axes[.aggression] == 0.9 && mayhem.axes[.raw] == 0.95)
        #expect(mayhem.axes[.bounce] == nil, "原型沒宣告的軸＝未知")
    }

    @Test func theOverrideWinsOverTheGenre() throws {
        let cradle = try profile(resolve("Cradle of Filth", "Pop"))
        #expect(cradle.tags == [.black, .gothic, .symphonic] && cradle.axes[.aggression] == 0.88)
    }

    @Test func anUnknownBandWithoutAGenreIsPending() {
        #expect(resolve("Paper Lantern Ensemble", nil) == .pending)
    }

    @Test func anUnknownGenreIsSettledAsMono() {
        #expect(resolve("Paper Lantern Ensemble", "Experimental Foo") == .noMatch)
        #expect(resolve("Paper Lantern Ensemble", "") == .noMatch)
    }

    @Test(arguments: ["Black Metal", "black metal ", "Death Metal/Black Metal", "Pagan Black", "Depressive"])
    func blackGenresResolveToTheBlackTag(genre: String) throws {
        let resolved = try profile(resolve("Paper Lantern Ensemble", genre))
        #expect(resolved.tags.contains(.black))
        #expect((resolved.axes[.aggression] ?? 0) >= 0.65)
    }

    @Test(arguments: ["Symphonic Metal", "Symphony Metal", "Neoclassic", "Soundtrack"])
    func symphonicGenresResolveToTheSymphonicTag(genre: String) throws {
        let resolved = try profile(resolve("Paper Lantern Ensemble", genre))
        #expect(resolved.tags == [.symphonic])
        #expect((resolved.axes[.aggression] ?? 1) < 0.65)
    }

    /// P11：交響不得把黑金屬的侵略性稀釋到溫柔元件的門檻之下
    @Test func symphonicBlackKeepsTheAggressionAndAveragesTheSoftAxes() throws {
        let resolved = try profile(resolve("Paper Lantern Ensemble", "Symphony Black Metal"))
        #expect(resolved.tags == [.black, .symphonic])
        let black = try profile(resolve("x", "Black Metal"))
        let symphonic = try profile(resolve("x", "Symphonic Metal"))
        #expect(resolved.axes[.aggression] == max(black.axes[.aggression]!, symphonic.axes[.aggression]!))
        #expect(resolved.axes[.theatrical] == max(black.axes[.theatrical]!, symphonic.axes[.theatrical]!))
        #expect(abs(resolved.axes[.elegance]! - (black.axes[.elegance]! + symphonic.axes[.elegance]!) / 2) < 1e-12)
        #expect(resolved.axes[.aggression]! >= 0.65)
    }

    @Test func genericKeywordsOnlyCountWithoutASpecificOne() {
        let rows: [SongProfileResolver.KeywordRow] = [
            .init(keywords: ["metal"], tags: [.heavy], axes: [.aggression: 0.5, .bright: 0.9], isGeneric: true),
            .init(keywords: ["black"], tags: [.black], axes: [.aggression: 0.9], isGeneric: false),
        ]
        #expect(SongProfileResolver.compose(genre: "Black Metal", rows: rows) == SongProfile(axes: [.aggression: 0.9], tags: [.black]))
        #expect(SongProfileResolver.compose(genre: "Metal", rows: rows) == SongProfile(axes: [.aggression: 0.5, .bright: 0.9], tags: [.heavy]))
        #expect(SongProfileResolver.compose(genre: "Polka", rows: rows) == nil)
    }

    @Test func everyOverrideHasValuesWithinRange() {
        for (_, profile) in SongProfileResolver.overrides {
            #expect(profile.axes.values.allSatisfy { (0...1).contains($0) } && !profile.tags.isEmpty)
        }
    }
}

// ⑥a J-Pop 計劃 §4.1、§6.1：歌詞證據與判定順序（樂團表 → 歌詞未知＝pending → 日文詞＝J-Pop → 曲風列 → noMatch）
@Suite("J-Pop policy resolution")
struct JPopResolutionTests {
    private let japanese = LyricsEvidence.text(isJapanese: true)
    private let english = LyricsEvidence.text(isJapanese: false)

    @Test func anUnknownArtistWithJapaneseLyricsIsJPop() {
        let resolution = SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: "Pop", lyrics: japanese)
        #expect(resolution == .jpop)
        #expect(resolution.source == .jpopPolicy)
    }

    @Test func aSignedBandWinsOverJapaneseLyrics() {
        let resolution = SongProfileResolver.resolve(artist: "Mayhem", genre: nil, lyrics: japanese)
        #expect(resolution.source == .signedBand)
        #expect(resolution.profile?.tags == [.black])
    }

    @Test func lyricsNotYetReadArePendingEvenWithAKnownGenre() {
        #expect(SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: "Black Metal", lyrics: .unknown) == .pending)
        #expect(SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: "Black Metal", lyrics: .unknown).source == nil)
    }

    @Test func englishLyricsFollowTheGenreRows() {
        let resolution = SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: "Black Metal", lyrics: english)
        #expect(resolution.source == .genreRow)
        #expect(resolution.profile?.tags.contains(.black) == true)
    }

    @Test func englishLyricsWithoutAMatchingGenreAreNoMatch() {
        let resolution = SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: "Experimental Foo", lyrics: english)
        #expect(resolution == .noMatch)
        #expect(resolution.source == .noMatch && resolution.profile == nil)
    }

    @Test func hanOnlyLyricsAreNotJapanese() {
        let evidence = LyricsEvidence.of("春風細雨\n山高水長")
        #expect(evidence == .text(isJapanese: false))
        #expect(SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: "Experimental Foo", lyrics: evidence) == .noMatch)
    }

    /// 使用者 2026-10-23：MONGOL800 照規則當 J-Pop，不開例外
    @Test func mongol800FollowsTheRuleWithoutAnException() {
        #expect(SongProfileResolver.resolve(artist: "MONGOL800", genre: "Rock", lyrics: japanese) == .jpop)
    }

    @Test func blankLyricsFallThroughToTheGenre() {
        let blank = LyricsEvidence.of(" \n\t")
        #expect(SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: nil, lyrics: blank) == .pending)
        #expect(SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: "Black Metal", lyrics: blank).source == .genreRow)
    }

    @Test(arguments: [
        (String?.none, LyricsEvidence.unknown), (" \n\t", .text(isJapanese: false)), ("walking down the river", .text(isJapanese: false)),
        ("ひかりの道を歩く", .text(isJapanese: true)), ("Sunday morning ねむいけど", .text(isJapanese: true)),
    ])
    func evidenceComesFromTheRawLyrics(lyrics: String?, expected: LyricsEvidence) {
        #expect(LyricsEvidence.of(lyrics) == expected)
    }

    @Test(arguments: [
        ("walking down the river", false), ("바람이 분다", false), ("ＡＢＣ１２３！？", false), ("春風細雨", false),
        ("Sunday morning ねむいけど", true), ("カタカナだけ", true),
    ])
    func containsKanaTruthTable(text: String, expected: Bool) {
        #expect(LyricsScript.containsKana(text) == expected)
    }

    private static let english9 = (1...9).map { "walking down the river \($0)" }.joined(separator: "\n")

    /// ⑥a 計劃 §4.1（2026-10-23 依曲庫掃描修訂）：有字母的歌詞行中含假名者 ≥ 3 成才是日文歌（Gorillaz 一首 1／10 不算）
    @Test(arguments: [
        ("ひかりの道を歩く", true),                                         // 1/1
        ("ひかりの道を歩く\nwalking down the river", true),                  // 1/2
        ("ひかりの道を歩く\none\ntwo\nthree", false),                      // 1/4
        (english9 + "\nひかりの道を歩く", false),                           // 1/10
        ("[Verse]\n" + english9 + "\nひかりの道を歩く", false),            // 段落標題不進分母
        ("ひかり\nみち\nあさ\n" + (1...7).map { "line \($0)" }.joined(separator: "\n"), true),   // 3/10
        ("春風細雨\n山高水長", false),                                        // 只有漢字：進分母、不進分子
        ("♪ ♪\n123\n...\nひかり\nみち\nあさ", true),                       // 符號與數字行不進分母
        ("[ti:ひかりの歌]\n[ar:Paper Lantern]\n[00:01.00]walking down the river\n[00:05.00]paper boats at dawn", false),   // LRC 標籤不算證據
        ("[00:01.00]ひかりの道を歩く\n[00:05.00]紙の舟が朝を待つ", true),
        ("", false), ("   ", false),
    ])
    func japaneseSongTruthTable(lyrics: String, expected: Bool) {
        #expect(LyricsScript.isJapaneseSong(lyrics) == expected)
    }
}

@Suite("Artist normalization")
struct ArtistNormalizationTests {
    @Test(arguments: [
        ("The Offspring", "offspring"), ("Blink‐182", "blink182"), ("blink-182", "blink182"),
        ("Motörhead", "motorhead"), ("  Cradle of Filth ", "cradleoffilth"), ("THEATRE OF TRAGEDY", "theatreoftragedy"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(SongProfileResolver.normalizedArtist(input) == expected)
    }

    @Test func normalizingTwiceChangesNothing() {
        for name in ["The Offspring", "Motörhead", "Dimmu Borgir", "İstanbul Ensemble"] {
            let once = SongProfileResolver.normalizedArtist(name)
            #expect(SongProfileResolver.normalizedArtist(once) == once)
        }
    }

    @Test func turkishDottedIDoesNotDependOnTheSystemLocale() {
        #expect(SongProfileResolver.normalizedArtist("İstanbul") == "istanbul")
    }
}
