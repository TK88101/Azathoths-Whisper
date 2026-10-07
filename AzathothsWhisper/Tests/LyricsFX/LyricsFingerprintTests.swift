import Foundation
import Testing

@testable import AzathothsWhisper

// 歌詞指紋（A1 計劃 §2）：monitor 判同曲改詞、時間軸存檔的 lyricsHash、VM 判「詞變了」共用這一處
@Suite("LyricsFingerprint")
struct LyricsFingerprintTests {
    @Test func lineEndingsDoNotChangeTheFingerprint() {
        let lf = LyricsFingerprint.of("one\ntwo")
        #expect(LyricsFingerprint.of("one\rtwo") == lf)
        #expect(LyricsFingerprint.of("one\r\ntwo") == lf)
    }

    @Test func differentTextHasADifferentFingerprint() {
        #expect(LyricsFingerprint.of("one\ntwo") != LyricsFingerprint.of("one\ntwo!"))
        #expect(LyricsFingerprint.of("") != LyricsFingerprint.of(" "))
    }

    @Test func fingerprintIs32LowercaseHexCharacters() {
        let hex = LyricsFingerprint.of("Some Song").hex
        #expect(hex.count == 32)
        #expect(hex.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func roundTripsThroughJSONAsAPlainString() throws {
        let fingerprint = LyricsFingerprint.of("x")
        let data = try JSONEncoder().encode(fingerprint)
        #expect(String(decoding: data, as: UTF8.self) == "\"\(fingerprint.hex)\"")
        #expect(try JSONDecoder().decode(LyricsFingerprint.self, from: data) == fingerprint)
    }

    @Test func fullWidthHexIsNotAFingerprint() {
        #expect(LyricsFingerprint(hex: String(repeating: "ａ", count: 32)) == nil)
        #expect(LyricsFingerprint(hex: String(repeating: "a", count: 32)) != nil)
    }

    @Test func decodingRejectsNonHexStrings() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(LyricsFingerprint.self, from: Data("\"not-a-hash\"".utf8))
        }
    }
}
