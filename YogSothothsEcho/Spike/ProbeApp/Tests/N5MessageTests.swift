import Foundation
import Testing
@testable import ProbeShared

@Suite struct N5MessageTests {
    @Test func makeProducesPrefixChallengeAndNewline() {
        #expect(N5Message.make(challenge: "123456") == "YSE-N5:123456\n")
    }

    @Test(arguments: ["", "12345", "1234567", "12345a", "１２３４５６", "12 456", "-12345"])
    func makeRejectsMalformedChallenge(_ challenge: String) {
        #expect(N5Message.make(challenge: challenge) == nil)
    }

    @Test func makeKeepsLeadingZeros() {
        #expect(N5Message.make(challenge: "000042") == "YSE-N5:000042\n")
    }

    @Test func parseReturnsChallengeForLfAndCrLf() {
        #expect(N5Message.parse("YSE-N5:654321\n") == "654321")
        #expect(N5Message.parse("YSE-N5:654321\r\n") == "654321")
    }

    @Test func parseAcceptsMissingTerminator() {
        #expect(N5Message.parse("YSE-N5:654321") == "654321")
    }

    @Test(arguments: [
        "", "\n", "YSE-N5:", "YSE-N5:\n", "YSE-N5:12345\n", "YSE-N5:1234567\n", "yse-n5:123456\n",
        "YSE-N4:123456\n", "XYSE-N5:123456\n", "YSE-N5: 123456\n", "YSE-N5:12345a\n",
        "YSE-N5:123456\nYSE-N5:123456\n", "YSE-N5:123456\nextra", "YSE-N5:123456 \n",
    ])
    func parseRejectsMalformedMessage(_ raw: String) {
        #expect(N5Message.parse(raw) == nil)
    }

    @Test func makeThenParseRoundTrips() throws {
        let message = try #require(N5Message.make(challenge: "090909"))
        #expect(N5Message.parse(message) == "090909")
    }

    @Test func frameNeedsMoreUntilNewlineArrives() {
        #expect(N5Message.frame(Data()) == .needMore)
        #expect(N5Message.frame(Data("YSE-N5:12".utf8)) == .needMore)
    }

    @Test func frameReturnsFirstLineOnceNewlinePresent() {
        #expect(N5Message.frame(Data("YSE-N5:123456\n".utf8)) == .challenge("123456"))
        #expect(N5Message.frame(Data("YSE-N5:123456\r\n".utf8)) == .challenge("123456"))
    }

    @Test func frameFlagsGarbageLineAsInvalid() {
        #expect(N5Message.frame(Data("hello\n".utf8)) == .invalid)
        #expect(N5Message.frame(Data("YSE-N5:12x456\n".utf8)) == .invalid)
    }

    @Test func frameFlagsOverlongBufferWithoutNewline() {
        let long = Data(repeating: 0x41, count: N5Message.maxFrameBytes + 1)
        #expect(N5Message.frame(long) == .invalid)
    }

    @Test func frameAtLimitWithoutNewlineStillWaits() {
        let atLimit = Data(repeating: 0x41, count: N5Message.maxFrameBytes)
        #expect(N5Message.frame(atLimit) == .needMore)
    }

    @Test func frameFlagsNonUtf8() {
        #expect(N5Message.frame(Data([0xFF, 0xFE, 0x0A])) == .invalid)
    }

    @Test func madeChallengeIsAlwaysValid() {
        for _ in 0..<200 { #expect(N5Message.isValidChallenge(N5Message.makeChallenge())) }
    }
}
