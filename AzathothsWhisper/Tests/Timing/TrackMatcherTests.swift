import Testing

@testable import AzathothsWhisper

// C 段計劃 §3.3：嚴格曲目比對。案例取自 2026-10-19 探針實際配到的候選（只有歌手、曲名、時長，不含歌詞）
@Suite("TrackMatcher")
struct TrackMatcherTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let note: String
        let wanted: (artist: String, title: String, duration: Double)
        let candidate: (artist: String, title: String, duration: Double?)
        let accepted: Bool
        var testDescription: String { note }
    }

    static let cases: [Case] = [
        // 探針：應該接受
        Case(note: "完全相同", wanted: ("Mayhem", "Watchers", 379), candidate: ("Mayhem", "Watchers", 379.9), accepted: true),
        Case(note: "Remaster 尾綴（同錄音）", wanted: ("Killswitch Engage", "Soilborn", 210), candidate: ("Killswitch Engage", "Soilborn (2004 Remaster)", 210.1), accepted: true),
        Case(note: "remaster＋年份在括號內", wanted: ("Marduk", "The Black... (remaster 2017)", 242), candidate: ("Marduk", "The Black...", 242.7), accepted: true),
        Case(note: "撇號位置不同", wanted: ("Dawn of Ashes", "Nyarlathoteps' Children of the Void", 200), candidate: ("Dawn of Ashes", "Nyarlathotep's Children of the Void", 200.8), accepted: true),
        Case(note: "音譯括號（網易雲）", wanted: ("Rotting Christ", "Русалка", 273), candidate: ("Rotting Christ", "Русалка (Rusalka)", 275), accepted: true),
        Case(note: "feat. 尾綴", wanted: ("Lana Del Rey", "Grandfather please stand on the shoulders of my father while he's deep-sea fishing (feat. RIOPY)", 240), candidate: ("Lana Del Rey", "Grandfather please stand on the shoulders of my father while he's deep-sea fishing", 240.7), accepted: true),
        Case(note: "Live 對 Live - 1991（子集）", wanted: ("AC/DC", "Hells Bells (Live)", 361), candidate: ("AC/DC", "Hells Bells (Live - 1991)", 361.3), accepted: true),
        Case(note: "歌手名尾端空白", wanted: ("Black Abyss ", "Rippers Punch", 278), candidate: ("Black Abyss", "Rippers Punch", 280), accepted: true),
        Case(note: "The 前綴", wanted: ("The Smashing Pumpkins", "To Forgive", 257), candidate: ("Smashing Pumpkins", "To Forgive", 257.7), accepted: true),
        Case(note: "AC/DC 整串比對", wanted: ("AC/DC", "Back In Black", 255), candidate: ("ACDC", "Back In Black", 255), accepted: true),
        Case(note: "合作歌手分段", wanted: ("Lana Del Rey", "Prom", 200), candidate: ("Lana Del Rey, RIOPY", "Prom", 200), accepted: true),
        Case(note: "Æ 轉 AE、附加符號", wanted: ("Häxkapell", "Satans rötter", 424), candidate: ("Haxkapell", "Satans rotter", 424), accepted: true),
        Case(note: "全形英數（QQ／網易雲）", wanted: ("ABC Band", "Song 2", 200), candidate: ("ＡＢＣ Ｂａｎｄ", "Ｓｏｎｇ ２", 200), accepted: true),
        Case(note: "曲名差一個字", wanted: ("Mayhem", "Watehers", 379), candidate: ("Mayhem", "Watchers", 379), accepted: true),
        Case(note: "時長差剛好 3 秒", wanted: ("Mayhem", "Watchers", 379), candidate: ("Mayhem", "Watchers", 382), accepted: true),
        // 探針：應該拒絕
        Case(note: "時長差 4.9 秒", wanted: ("Averse Sefira", "Deathymn", 318), candidate: ("Averse Sefira", "Deathymn", 322.9), accepted: false),
        Case(note: "時長差 3.4 秒", wanted: ("Black Abyss", "Rippers Punch", 278), candidate: ("Black Abyss", "Rippers Punch", 281.4), accepted: false),
        Case(note: "候選沒有時長", wanted: ("Mayhem", "Watchers", 379), candidate: ("Mayhem", "Watchers", nil), accepted: false),
        Case(note: "純音樂配到人聲版（Nightwish）", wanted: ("Nightwish", "Our Decades in the Sun (Instrumental)", 400), candidate: ("Nightwish", "Our Decades in the Sun", 400.9), accepted: false),
        Case(note: "人聲版配到伴奏", wanted: ("Nightwish", "Our Decades in the Sun", 400), candidate: ("Nightwish", "Our Decades in the Sun (Karaoke Version)", 400), accepted: false),
        Case(note: "不同場 Live", wanted: ("Band", "Song (Live at Glastonbury)", 200), candidate: ("Band", "Song (Live at Reading)", 200), accepted: false),
        Case(note: "Live 對錄音室版", wanted: ("HIM", "For You (ACSTC Live G&T Version)", 247), candidate: ("HIM", "For You", 247), accepted: false),
        Case(note: "Remix 對原版", wanted: ("Band", "Song", 200), candidate: ("Band", "Song - Club Remix", 200), accepted: false),
        Case(note: "別首歌（Weezer）", wanted: ("Weezer", "Prom Night", 214), candidate: ("Weezer", "(Girl We Got A) Good Thing", 214), accepted: false),
        Case(note: "別的歌手同曲名", wanted: ("Sapfhier", "Vandring", 233), candidate: ("Isildurs Bane", "Vandring", 233), accepted: false),
        Case(note: "短曲名不容錯字", wanted: ("Band", "Rain", 200), candidate: ("Band", "Pain", 200), accepted: false),
        Case(note: "裸年份不忽略（可能是重錄）", wanted: ("Band", "Song (2019)", 200), candidate: ("Band", "Song", 200), accepted: false),
        Case(note: "曲名差兩個字", wanted: ("Band", "Darkness", 200), candidate: ("Band", "Darknxss!x", 200), accepted: false),
    ]

    @Test(arguments: cases)
    func decides(_ testCase: Case) {
        let wanted = TimingQuery(artist: testCase.wanted.artist, title: testCase.wanted.title, duration: testCase.wanted.duration)
        let candidate = MatchedTrack(artist: testCase.candidate.artist, title: testCase.candidate.title, duration: testCase.candidate.duration)
        #expect(TrackMatcher.matches(wanted, candidate) == testCase.accepted)
    }

    @Test func normalizationDropsPunctuationArticlesAndDiacritics() {
        #expect(TrackMatcher.normalized("The Black... (remaster 2017)") == "black")
        #expect(TrackMatcher.normalized("Æther – Øde") == "aetherode")
        #expect(TrackMatcher.normalized("Song feat. Someone") == "song")
    }
}
