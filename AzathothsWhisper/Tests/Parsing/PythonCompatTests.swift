import Foundation
import Testing

@testable import AzathothsWhisper

// 釘住 M2 對抗審查（2026-08-10）確認的四處 CPython vs ICU 語義差異的修復。
@Suite("PythonCompat")
struct PythonCompatTests {
    // 審查第 1 條：Foundation 的 .whitespacesAndNewlines 會剝 U+200B，CPython str.strip() 不會
    @Test func stripKeepsZeroWidthSpace() {
        let zwsp = "\u{200B}"
        #expect("Plain Title\(zwsp)".pythonStripped() == "Plain Title\(zwsp)")
        #expect("\(zwsp)Plain Title".pythonStripped() == "\(zwsp)Plain Title")
        // 對照組：Foundation 的集合會剝掉，證明兩者確實不同
        #expect("Plain Title\(zwsp)".trimmingCharacters(in: .whitespacesAndNewlines) == "Plain Title")
    }

    // 審查第 1/4 條：CPython 會剝 U+001C–U+001F，Foundation 不會
    @Test func stripRemovesFileSeparators() {
        for scalar: UInt32 in 0x1C...0x1F {
            let control = String(Unicode.Scalar(scalar)!)
            #expect("Plain Title\(control)".pythonStripped() == "Plain Title")
            #expect("\(control)Plain Title".pythonStripped() == "Plain Title")
        }
    }

    @Test func stripMatchesPythonOnCommonWhitespace() {
        // NBSP / 全形空白 / 行列分隔符等兩邊一致的情況，確保沒有改壞
        for text in ["\u{00A0}x\u{00A0}", "\u{3000}x\u{3000}", "\u{2028}x\u{2029}", " \t\r\nx \t\r\n"] {
            #expect(text.pythonStripped() == "x")
        }
        #expect("".pythonStripped() == "")
        #expect("   ".pythonStripped() == "")
    }

    // 審查第 2 條：CPython 套用希臘文末尾 sigma 規則，ICU 不套用
    @Test func lowercasedAppliesGreekFinalSigma() {
        #expect("ΟΔΟΣ".pythonLowercased() == "οδος")            // 末尾 → ς (U+03C2)
        #expect("ΟΔΟΣ".pythonLowercased().unicodeScalars.last?.value == 0x03C2)
        #expect("ΟΔΟΣΤΡΩΜΑ".pythonLowercased().contains("\u{03C3}"))  // 詞中 → σ
        #expect("ΟΔΟΣΤΡΩΜΑ".pythonLowercased().contains("\u{03C2}") == false)
        // 對照組：ICU 一律給 σ
        #expect("ΟΔΟΣ".lowercased().unicodeScalars.last?.value == 0x03C3)
    }

    @Test func lowercasedHandlesSigmaEdgeCases() {
        #expect("Σ".pythonLowercased() == "σ", "前方無 cased 字元 → 非末尾形")
        #expect("ΑΣ.".pythonLowercased().unicodeScalars.map(\.value).contains(0x03C2), "標點屬 Case_Ignorable，仍算末尾")
        #expect("abc".pythonLowercased() == "abc")
        #expect("ÄÖÜ".pythonLowercased() == "äöü")
    }

    // 審查第 3 條：re.IGNORECASE 折疊土耳其 ı/İ，ICU 不折疊 → 顯式列進字符類
    @Test func sanitizeStripsTurkishDottedKeywords() {
        #expect(TitleSanitizer.sanitize("Song (REMİX)") == "Song")
        #expect(TitleSanitizer.sanitize("Song (Remıx)") == "Song")
        #expect(TitleSanitizer.sanitize("Song (LİVE)") == "Song")
        #expect(TitleSanitizer.sanitize("Song (VERSİON 2)") == "Song")
        #expect(TitleSanitizer.sanitize("Song - 2015 Remİx") == "Song")
    }

    // 審查第 6 條：HTMLText 走訪不得因深度而爆棧（經 DarkLyricsParser 間接驅動）。
    // 實測補充：本專案的深度天花板其實在 SwiftSoup.parse —— 10,000 層嵌套會讓解析器自身
    // 爆棧（診斷過程見 M3 筆記），故走訪層的遞迴風險在實際管線中不可達；迭代版屬防禦性改進。
    @Test func deeplyNestedDocumentDoesNotOverflowStack() {
        let depth = 1_000
        let nested = String(repeating: "<span>", count: depth) + "Deep Song" + String(repeating: "</span>", count: depth)
        let html = "<div class=\"lyrics\"><h3>1. \(nested)</h3>lyric body<br></div>"

        let outcome = DarkLyricsParser.parse(html: html, targetTitle: "Deep Song")
        #expect(outcome == .lyrics("lyric body"))
    }
}
