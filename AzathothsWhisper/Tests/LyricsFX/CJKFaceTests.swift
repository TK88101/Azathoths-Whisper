import AppKit
import CoreGraphics
import CoreText
import Testing

@testable import AzathothsWhisper

// ⑤ 中日韓字型計劃 §4.2、§4.6：含中日韓字的行整行換字型（中文蘋方-繁、日文冬青黑體、韓文 Apple SD Gothic Neo），
// 以 PostScript 名指定並以 CoreText 實際排版驗證。歌詞為編造句
@Suite("CJK faces")
struct CJKFaceTests {
    @Test(arguments: [
        (LineScript.cjk, CJKLanguage.japanese, CJKFaceRole.composed, "HiraginoSans-W6"),
        (.cjk, .japanese, .monoCurrent, "HiraginoSans-W5"),
        (.cjk, .japanese, .monoPreview, "HiraginoSans-W4"),
        (.cjk, .chinese, .composed, "PingFangTC-Semibold"),
        (.cjk, .chinese, .monoCurrent, "PingFangTC-Medium"),
        (.cjk, .chinese, .monoPreview, "PingFangTC-Regular"),
        (.hangul, .japanese, .composed, "AppleSDGothicNeo-SemiBold"),
        (.hangul, .chinese, .monoCurrent, "AppleSDGothicNeo-Medium"),
        (.hangul, .japanese, .monoPreview, "AppleSDGothicNeo-Regular"),
    ])
    func eachScriptLanguageAndRoleHasItsFace(script: LineScript, language: CJKLanguage, role: CJKFaceRole, postScript: String) throws {
        let face = try #require(FontFace.lineFace(for: script, language: language, role: role, base: .displayMedium))
        #expect(face.postScriptName == postScript)
        #expect(face.sizeScale == 1)
        #expect(face.spacing == FontFace.cjkSpacing)
    }

    @Test func latinLinesKeepTheBandFace() {
        #expect(FontFace.lineFace(for: .latin, language: .japanese, role: .composed, base: .displayMedium) == nil)
    }

    @Test func theBandFacesUppercaseCarriesOverForLatinLettersInTheLine() throws {
        let upper = FontFace(id: "Bebas", family: "Bebas Neue", weight: nil, uppercase: true)
        let face = try #require(FontFace.lineFace(for: .cjk, language: .japanese, role: .composed, base: upper))
        #expect(face.uppercase)
        let plain = try #require(FontFace.lineFace(for: .cjk, language: .japanese, role: .composed, base: .displayMedium))
        #expect(!plain.uppercase)
        #expect(face.id != plain.id)   // 快取鍵分得開
    }

    // MARK: CoreText 實際字型（§4.6）

    static let representative = "夜明灯籠川流港静骨直東京大阪漢字愛空海風雨雪花月星光影声心時間夢道路街橋森山島雲火水土金銀赤青白黒今日明昨"
        + "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"
        + "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"
        + "、。「」『』（）！？ー・" + "ABCxyz019 ＡＢＣ"

    private func runFonts(_ text: String, postScript: String) -> Set<String> {
        let font = FaceFonts().font(FontFace(id: "probe", family: "", weight: nil, postScriptName: postScript), size: 40)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        return Set(runs.compactMap { run -> String? in
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attributes[kCTFontAttributeName] else { return nil }
            return CTFontCopyPostScriptName(runFont as! CTFont) as String
        })
    }

    @Test(arguments: ["HiraginoSans-W6", "HiraginoSans-W5", "HiraginoSans-W4"])
    func japaneseTextIsSetEntirelyInHiragino(postScript: String) {
        #expect(runFonts(Self.representative, postScript: postScript) == [postScript])
    }

    @Test(arguments: ["PingFangTC-Semibold", "PingFangTC-Medium", "PingFangTC-Regular"])
    func chineseTextIsSetEntirelyInPingFang(postScript: String) {
        #expect(runFonts("紙船靜靜漂流在港口，燈籠點亮了夜晚的河。ABC 123", postScript: postScript) == [postScript])
    }

    @Test(arguments: ["AppleSDGothicNeo-SemiBold", "AppleSDGothicNeo-Medium", "AppleSDGothicNeo-Regular"])
    func koreanTextIsSetEntirelyInAppleSDGothicNeo(postScript: String) {
        #expect(runFonts("새벽 하늘 아래 lanterns 123", postScript: postScript) == [postScript])
    }

    /// 缺字（emoji）照常由 CoreText 替代、不中斷：替代只發生在那個字
    @Test func aMissingGlyphStillFallsBack() {
        let fonts = runFonts("夜明け🎵", postScript: "HiraginoSans-W6")
        #expect(fonts.contains("HiraginoSans-W6"))
        #expect(fonts.count == 2)
    }

    @Test func thePostScriptNameIsWhatFaceFontsBuilds() {
        let face = FontFace(id: "probe", family: "", weight: nil, postScriptName: "HiraginoSans-W6")
        #expect(CTFontCopyPostScriptName(FaceFonts().font(face, size: 30)) as String == "HiraginoSans-W6")
    }

    // MARK: 組合與素面依行選字型

    static let size = CGSize(width: 900, height: 560)

    private func composed(_ timeline: LyricsTimeline, time: Double, font: String = "Bebas") -> FramePlan {
        let recipe = ComposedRecipe(
            font: font, backdrop: "void", enter: "lash", exit: "fade", fx1: "none", fx2: "none", palette: "ice", seed: 7,
            profile: SongProfile(axes: [.aggression: 0.5], tags: [])
        )
        return LyricsFXFrame.plan(timeline: timeline, time: time, size: Self.size, motion: .full, recipe: .composed(recipe), measurer: FixedWidthMeasurer())
    }

    @Test func aJapaneseLineUsesHiraginoAndAnEnglishLineKeepsTheBandFace() {
        let timeline = LyricsTimeline(lines: [
            TimedLine(start: 1, end: 4, text: "夜明けの灯籠 lanterns", isChorus: false),
            TimedLine(start: 4, end: 8, text: "Paper boats", isChorus: false),
        ], source: .embeddedLRC, duration: 60)
        let japanese = composed(timeline, time: 3.9).glyphs
        #expect(!japanese.isEmpty)
        #expect(japanese.allSatisfy { $0.face.postScriptName == "HiraginoSans-W6" })
        let english = composed(timeline, time: 7.9).glyphs.filter { $0.opacity > 0.5 }
        #expect(!english.isEmpty)
        #expect(english.allSatisfy { $0.face.id == "Bebas" })
    }

    @Test func aChineseSongUsesPingFang() {
        let timeline = LyricsTimeline(lines: [TimedLine(start: 1, end: 4, text: "紙船靜靜漂流", isChorus: false)], source: .embeddedLRC, duration: 60)
        let glyphs = composed(timeline, time: 3.9).glyphs
        #expect(!glyphs.isEmpty)
        #expect(glyphs.allSatisfy { $0.face.postScriptName == "PingFangTC-Semibold" })
    }

    @Test func monoUsesHiraginoForTheCurrentAndPreviewJapaneseLines() {
        let timeline = LyricsTimeline(lines: [
            TimedLine(start: 1, end: 4, text: "灯籠が川を流れる", isChorus: false),
            TimedLine(start: 4, end: 8, text: "静かな港", isChorus: false),
        ], source: .embeddedLRC, duration: 60)
        let glyphs = LyricsFXFrame.plan(timeline: timeline, time: 3, size: Self.size, motion: .full, measurer: FixedWidthMeasurer()).glyphs
        #expect(Set(glyphs.compactMap(\.face.postScriptName)) == ["HiraginoSans-W5", "HiraginoSans-W4"])
        #expect(glyphs.allSatisfy { $0.face.postScriptName != nil })
    }

    @Test func monoKeepsSpaceGroteskForEnglish() {
        let timeline = LyricsTimeline(lines: [TimedLine(start: 1, end: 4, text: "Paper boats", isChorus: false)], source: .embeddedLRC, duration: 60)
        let glyphs = LyricsFXFrame.plan(timeline: timeline, time: 3, size: Self.size, motion: .full, measurer: FixedWidthMeasurer()).glyphs
        #expect(glyphs.allSatisfy { $0.face == .displayMedium })
    }
}
