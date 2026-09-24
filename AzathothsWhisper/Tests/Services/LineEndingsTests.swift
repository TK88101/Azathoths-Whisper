import Testing

@testable import AzathothsWhisper

// 寫入後讀回比對（2026-09-24 使用者實機試用）：Music 把寫入的 LF 換行存成 CR，
// 逐字比對判成「FAILED TO SAVE」、不升回——實際已寫入。比對前兩邊都統一換行
@Suite("LineEndings")
struct LineEndingsTests {
    @Test func readBackWithMusicsCarriageReturnsIsTheSameLyrics() {
        #expect(LineEndings.equivalent("line one\nline two", "line one\rline two"))
        #expect(LineEndings.equivalent("a\r\nb", "a\nb"))
    }

    @Test func differentWordsAreStillDifferent() {
        #expect(!LineEndings.equivalent("line one\nline two", "line one\rline 2"))
        #expect(!LineEndings.equivalent("words", ""))
    }
}
