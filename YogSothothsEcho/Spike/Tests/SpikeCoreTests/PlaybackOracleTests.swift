import Foundation
import Testing
@testable import SpikeCore

struct PlayerStateCodeTests {
    @Test func fourCharCodesDecode() {
        #expect(PlayerStateCode.decode(0x6B50_5350) == .playing)   // 'kPSP'
        #expect(PlayerStateCode.decode(0x6B50_5370) == .paused)    // 'kPSp'
        #expect(PlayerStateCode.decode(0x6B50_5353) == .stopped)   // 'kPSS'
        #expect(PlayerStateCode.decode(0) == .other)
    }
}

struct PlaybackOracleTests {
    private let sequence = (1...25).map { String(format: "%016X", $0) }

    @Test func nextAndPreviousFollowTheSequence() throws {
        let oracle = try #require(PlaybackOracle(sequence: sequence))
        #expect(oracle.expectedNext(after: sequence[4]) == sequence[5])
        #expect(oracle.expectedPrevious(before: sequence[4]) == sequence[3])
    }

    @Test func theEndsHaveNoNeighbour() throws {
        let oracle = try #require(PlaybackOracle(sequence: sequence))
        #expect(oracle.expectedNext(after: sequence[24]) == nil)
        #expect(oracle.expectedPrevious(before: sequence[0]) == nil)
    }

    @Test func aTrackOutsideTheSequenceHasNoExpectation() throws {
        let oracle = try #require(PlaybackOracle(sequence: sequence))
        #expect(oracle.expectedNext(after: "FFFFFFFFFFFFFFFF") == nil)
    }

    @Test func aSequenceWithDuplicatesIsRejectedBecausePositionsAreAmbiguous() {
        #expect(PlaybackOracle(sequence: ["A", "B", "A"]) == nil)
    }

    @Test func roomForTwentyStepsNeedsTwentyOneTracks() throws {
        #expect(try #require(PlaybackOracle(sequence: Array(sequence.prefix(21)))).hasRoom(forSteps: 20))
        #expect(!(try #require(PlaybackOracle(sequence: Array(sequence.prefix(20)))).hasRoom(forSteps: 20)))
    }

    @Test func contextHashChangesWithOrder() throws {
        let a = try #require(PlaybackOracle(sequence: ["A", "B", "C"]))
        let b = try #require(PlaybackOracle(sequence: ["A", "C", "B"]))
        #expect(a.contextHash != b.contextHash)
        #expect(a.contextHash == (try #require(PlaybackOracle(sequence: ["A", "B", "C"]))).contextHash)
    }
}

struct QueueIDsTests {
    private func plist(_ ids: [Int64], shuffle: String? = "off") throws -> Data {
        let iar: [[String: Any]] = ids.map { ["pm": ["piObjSpec": ["tID": NSNumber(value: $0)]], "itID": NSNumber(value: 7)] }
        var items: [String: Any] = ["list": ["items": ["iar": iar]]]
        if let shuffle { items["shuffleMode"] = shuffle }
        let root: [String: Any] = ["sega": [["items": items]]]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    @Test func readsTheOrderedListAsUppercaseHex() throws {
        let ids = QueueIDs.parse(try plist([1, -1]))
        #expect(ids == ["0000000000000001", "FFFFFFFFFFFFFFFF"])
    }

    @Test func shuffledQueuesAreNotReadAsAnOrder() throws {
        #expect(QueueIDs.parse(try plist([1, 2], shuffle: "on")) == nil)
    }

    @Test func anEntryWithoutTrackIDMakesTheWholeQueueUnusable() throws {
        let root: [String: Any] = ["sega": [["items": ["list": ["items": ["iar": [["pm": [:]]]]]]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        #expect(QueueIDs.parse(data) == nil)
    }

    @Test func garbageIsUnusable() {
        #expect(QueueIDs.parse(Data("not a plist".utf8)) == nil)
    }
}

struct B2VerdictTests {
    private func checks(_ kind: B2Check.Kind, _ count: Int, correct: Bool = true) -> [B2Check] {
        (0..<count).map { _ in B2Check(kind: kind, expectedID: "X", readID: correct ? "X" : "Y",
                                       expectedState: .playing, readState: .playing) }
    }

    @Test func twentyCorrectOfEachKindPass() {
        let all = B2Check.Kind.allCases.flatMap { checks($0, 20) }
        #expect(B2Verdict.judge(all) == .pass)
    }

    @Test func oneWrongTrackInAnyKindFails() {
        let all = checks(.pause, 20) + checks(.resume, 20) + checks(.next, 19) + checks(.next, 1, correct: false)
            + checks(.previous, 20)
        #expect(B2Verdict.judge(all) == .fail)
    }

    @Test func aWrongStateFails() {
        var all = B2Check.Kind.allCases.flatMap { checks($0, 20) }
        all[0] = B2Check(kind: .pause, expectedID: "X", readID: "X", expectedState: .paused, readState: .playing)
        #expect(B2Verdict.judge(all) == .fail)
    }

    @Test func aKindWithFewerThanTwentyIsUndetermined() {
        let all = checks(.pause, 20) + checks(.resume, 20) + checks(.next, 20) + checks(.previous, 19)
        #expect(B2Verdict.judge(all) == .undetermined)
    }
}
