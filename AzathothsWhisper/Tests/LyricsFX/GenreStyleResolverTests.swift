import Testing

@testable import AzathothsWhisper

// 曲風 → 體系＋家族（母計劃 §2.5；A1 計劃 §3.5）。標籤取自使用者曲庫採樣
// `docs/plans/2026-10-03-lyrics-fx-genre-sample.txt` 的全部 69 個；英文歌詞一律用編造句
@Suite("GenreStyleResolver")
struct GenreStyleResolverTests {
    static let english = "Lanterns over the river"

    static let libraryTags: [(String, StyleFamily)] = [
        ("ロック", .jrock), ("Metal", .chrome), ("Alternative", .indie), ("Hard Rock", .rock),
        ("Indie Rock", .indie), ("Rock", .rock), ("Black Metal", .frost), ("Death Metal/Black Metal", .frost),
        ("Pop", .pop), ("Electronica", .circuit), ("Symphony Black Metal", .cathedral), ("Melodic Death Metal", .slab),
        ("Adult Alternative", .indie), ("Industrial Metal", .stencil), ("Britpop", .indie), ("J-Pop", .jpop),
        ("Dance & House", .circuit), ("Viking/Power Metal", .hearth), ("Neoclassic", .cathedral), ("Symphony Metal", .cathedral),
        ("Punk Rock", .riot), ("emo-rock", .riot), ("Nu-Metal", .stencil), ("Alternative Rock", .indie),
        ("Black/Death Metal", .frost), ("Symphonic Metal", .cathedral), ("Worldwide", .hearth), ("Hip-Hop/Rap", .block),
        ("Folk", .hearth), ("BritPop", .indie), ("Folk/Viking Metal", .hearth), ("Folk Black Metal", .frost),
        ("Pagan Black Metal", .frost), ("Thrash Metal", .chrome), ("Gothic/Symphonic Metal", .cathedral), ("Electronic", .circuit),
        ("Death Metal", .slab), ("Gothic Metal", .velvet), ("Viking/Black Metal", .frost), ("Melodic Doom Death Metal", .velvet),
        ("Gothic Rock", .velvet), ("Viking Metal", .hearth), ("Symphonic Black Metal", .cathedral), ("Progressive Black Metal", .frost),
        ("Melodic Death/Black Metal", .frost), ("Country & Folk", .hearth), ("Symphony Power Metal", .cathedral),
        ("New Wave of American Heavy Metal", .stencil), ("Epic Pagan Metal", .frost), ("Death/Viking Metal", .slab),
        // 首個命中者勝：doom（第 3 列）先於 death（第 5 列）。母計劃表的例欄把它寫在 slab，與規則矛盾，照規則（A1 計劃 §3.5）
        ("Death/Doom Metal", .velvet),
        ("Sympho Power Metal", .chrome), ("Ambient Black Metal", .frost), ("Power Metal", .chrome), ("Pagan Metal", .frost),
        ("Neoclassical Black Metal", .cathedral), ("Music", .mono), ("Death/Black Metal", .frost), ("Atmospheric Doom Metal", .velvet),
        ("Progressive Metal", .chrome), ("Epic heathen Metal", .frost), ("Hrad Rock", .rock), ("Depressive Black Metal", .frost),
        ("Soundtrack", .cathedral), ("Tropical/Grit/POP", .pop), ("R&B/Soul", .block), ("Original Score", .cathedral),
        ("Country", .hearth), ("Afro-Pop", .pop),
    ]

    @Test func everyTagInTheLibrarySampleIsCovered() {
        #expect(Self.libraryTags.count == 69)
        #expect(Set(Self.libraryTags.map(\.0)).count == 69)
    }

    @Test(arguments: libraryTags)
    func libraryTagMapsToFamily(tag: String, family: StyleFamily) {
        #expect(GenreStyleResolver.resolve(genre: tag, lyrics: Self.english).family == family, "\(tag)")
    }

    @Test func trailingWhitespaceAndCaseDoNotMatter() {
        #expect(GenreStyleResolver.resolve(genre: "Symphonic Metal ", lyrics: nil).family == .cathedral)
        #expect(GenreStyleResolver.resolve(genre: "  BLACK METAL", lyrics: nil).family == .frost)
    }

    /// 短關鍵字只比整詞：trap 不是 rap、democore 不是 emo
    @Test func shortKeywordsMatchWholeWordsOnly() {
        #expect(GenreStyleResolver.resolve(genre: "Trap", lyrics: Self.english).family == .mono)
        #expect(GenreStyleResolver.resolve(genre: "Democore", lyrics: Self.english).family == .mono)
        #expect(GenreStyleResolver.resolve(genre: "Gangsta Rap", lyrics: Self.english).family == .block)
    }

    @Test func emptyOrMissingGenreIsMono() {
        #expect(GenreStyleResolver.resolve(genre: "", lyrics: Self.english) == GenreStyle(family: .mono))
        #expect(GenreStyleResolver.resolve(genre: nil, lyrics: nil) == GenreStyle(family: .mono))
    }

    @Test func japaneseLyricsMakeTheJapaneseSystem() {
        let japanese = "夜明けの鐘が鳴る\n川の上の灯り"
        #expect(GenreStyleResolver.resolve(genre: "Metal", lyrics: japanese) == GenreStyle(family: .jrock))
        #expect(GenreStyleResolver.resolve(genre: "Pop", lyrics: japanese) == GenreStyle(family: .jpop))
        #expect(GenreStyleResolver.resolve(genre: nil, lyrics: japanese).family == .jrock)
    }

    @Test func japaneseTagsMakeTheJapaneseSystemEvenWithEnglishLyrics() {
        #expect(GenreStyleResolver.resolve(genre: "ロック", lyrics: Self.english).system == .japanese)
        #expect(GenreStyleResolver.resolve(genre: "J-Pop", lyrics: Self.english).family == .jpop)
    }

    @Test func aFewJapaneseWordsInEnglishLyricsStayEnglish() {
        let mixed = "Lanterns over the river, sayonara\nAsh in the wind 夜"
        #expect(GenreStyleResolver.resolve(genre: "Rock", lyrics: mixed).system == .english)
    }

    @Test func japaneseRatioCountsKanaAndKanjiAmongLetters() {
        #expect(GenreStyleResolver.japaneseRatio("あア漢a") == 0.75)
        #expect(GenreStyleResolver.japaneseRatio("123 !?") == 0)
    }
}
