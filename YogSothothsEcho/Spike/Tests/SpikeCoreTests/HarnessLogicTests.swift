import Foundation
import Testing
@testable import SpikeCore

struct SelectorAuditTests {
    private let allowed: Set<String> = ["playpause", "nextTrack", "setPlayerPosition:"]

    @Test func anExactMatchIsClean() {
        let audit = SelectorAudit.compare(declared: allowed, allowed: allowed)
        #expect(audit.isExact)
    }

    @Test func anExtraSetterIsCaught() {
        let audit = SelectorAudit.compare(declared: allowed.union(["setName:"]), allowed: allowed)
        #expect(!audit.isExact)
        #expect(audit.extra == ["setName:"])
    }

    @Test func aMissingSelectorIsCaught() {
        let audit = SelectorAudit.compare(declared: ["playpause", "nextTrack"], allowed: allowed)
        #expect(!audit.isExact)
        #expect(audit.missing == ["setPlayerPosition:"])
    }
}

struct ResultPathTests {
    private let directory = URL(fileURLWithPath: "/tmp/s0-results", isDirectory: true)
    private let instant = Date(timeIntervalSince1970: 1_792_000_000)

    @Test func pathIsInsideTheDirectoryWithAFixedNameFormat() throws {
        let url = try ResultPath.make(directory: directory, experiment: "b6-base", at: instant)
        #expect(url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(url.lastPathComponent.hasPrefix("b6-base-"))
        #expect(url.pathExtension == "jsonl")
    }

    @Test(arguments: ["../escape", "b6/base", "B6", "", "b6 base"])
    func experimentNamesOutsideTheAllowedAlphabetAreRejected(_ name: String) {
        #expect(throws: ResultPath.Failure.self) {
            try ResultPath.make(directory: directory, experiment: name, at: instant)
        }
    }
}

struct MonitorReadParsingTests {
    @Test func parsesTheAzathothMonitorLine() {
        let read = MonitorRead.parse(message: "read 42 poll+signal changed=true 87ms", timestamp: 10.5)
        #expect(read == MonitorRead(serial: 42, changed: true, timestamp: 10.5))
    }

    @Test func unchangedReadsAreParsedToo() {
        let read = MonitorRead.parse(message: "read 7 poll changed=false 12ms", timestamp: 3)
        #expect(read?.changed == false)
    }

    @Test(arguments: ["lyrics changed on the current track", "read x poll changed=true 1ms", ""])
    func otherMonitorMessagesAreIgnored(_ message: String) {
        #expect(MonitorRead.parse(message: message, timestamp: 0) == nil)
    }
}

struct B6PairingTests {
    private func change(_ t: Double) -> MonitorRead { MonitorRead(serial: 1, changed: true, timestamp: t) }
    private func noChange(_ t: Double) -> MonitorRead { MonitorRead(serial: 1, changed: false, timestamp: t) }

    @Test func exactlyOneChangeInTheWindowIsPaired() {
        let outcome = B6Pairing.pair(start: 100, reads: [noChange(99), change(100.09)], targetMatched: true)
        #expect(outcome == .paired(milliseconds: 90))
    }

    @Test func noChangeWithinThreeSecondsIsATimeout() {
        let outcome = B6Pairing.pair(start: 100, reads: [change(103.01)], targetMatched: true)
        #expect(outcome == .timeout)
    }

    @Test func twoChangesInTheWindowInvalidateTheSample() {
        let outcome = B6Pairing.pair(start: 100, reads: [change(100.1), change(101)], targetMatched: true)
        #expect(outcome == .invalidAmbiguous)
    }

    @Test func aChangeInTheQuietPeriodBeforeTheStartInvalidatesTheSample() {
        let outcome = B6Pairing.pair(start: 100, reads: [change(98.6), change(100.1)], targetMatched: true)
        #expect(outcome == .invalidNotQuiet)
    }

    @Test func aChangeJustBeforeTheQuietPeriodIsFine() {
        let outcome = B6Pairing.pair(start: 100, reads: [change(98.4), change(100.1)], targetMatched: true)
        #expect(outcome == .paired(milliseconds: 100))
    }

    @Test func theWrongTargetTrackInvalidatesTheSample() {
        let outcome = B6Pairing.pair(start: 100, reads: [change(100.1)], targetMatched: false)
        #expect(outcome == .invalidWrongTrack)
    }
}

struct B6VerdictTests {
    private func paired(_ ms: [Double]) -> [B6Pairing.Outcome] { ms.map { .paired(milliseconds: $0) } }

    @Test func aDifferenceOfExactlyTwoHundredPasses() {
        let base = paired(Array(repeating: 100, count: 20))
        let loaded = paired(Array(repeating: 300, count: 20))
        #expect(B6Verdict.judge(baseline: base, loaded: loaded) == .pass)
    }

    @Test func aDifferenceJustAboveTwoHundredFails() {
        let base = paired(Array(repeating: 100, count: 20))
        let loaded = paired(Array(repeating: 300.1, count: 20))
        #expect(B6Verdict.judge(baseline: base, loaded: loaded) == .fail)
    }

    @Test func timeoutsInTheLoadedRunCountAsFailures() {
        let base = paired(Array(repeating: 100, count: 20))
        let loaded = paired(Array(repeating: 120, count: 18)) + [.timeout, .timeout]
        #expect(B6Verdict.judge(baseline: base, loaded: loaded) == .fail)
    }

    @Test func invalidSamplesDoNotCountTowardTheTwenty() {
        let base = paired(Array(repeating: 100, count: 20))
        let loaded = paired(Array(repeating: 120, count: 19)) + [.invalidAmbiguous]
        #expect(B6Verdict.judge(baseline: base, loaded: loaded) == .undetermined)
    }

    @Test func aBrokenBaselineIsUndetermined() {
        let base = paired(Array(repeating: 100, count: 18)) + [.timeout, .timeout]
        let loaded = paired(Array(repeating: 120, count: 20))
        #expect(B6Verdict.judge(baseline: base, loaded: loaded) == .undetermined)
    }
}

struct RestoreCheckTests {
    private let before = MusicSnapshot(trackID: "A", position: 47, state: .paused, airPlayDeviceIDs: ["D1"],
                                       contextHash: "ctx1", queueHash: "q1")

    @Test func restoredStateIgnoresTheRecordOnlyFields() {
        let after = MusicSnapshot(trackID: "A", position: 48.5, state: .paused, airPlayDeviceIDs: ["D1"],
                                  contextHash: "ctx2", queueHash: "q2")
        let check = RestoreCheck(before: before, after: after)
        #expect(check.unrestored.isEmpty)
        #expect(check.recordOnlyChanges == [.context, .queue])
    }

    @Test func eachMustRestoreFieldIsReported() {
        let after = MusicSnapshot(trackID: "B", position: 50, state: .playing, airPlayDeviceIDs: ["D2"],
                                  contextHash: "ctx1", queueHash: "q1")
        let check = RestoreCheck(before: before, after: after)
        #expect(check.unrestored == [.track, .position, .state, .airPlay])
    }

    @Test func positionToleranceIsTwoSeconds() {
        let edge = MusicSnapshot(trackID: "A", position: 49, state: .paused, airPlayDeviceIDs: ["D1"],
                                 contextHash: "ctx1", queueHash: "q1")
        let beyond = MusicSnapshot(trackID: "A", position: 49.01, state: .paused, airPlayDeviceIDs: ["D1"],
                                   contextHash: "ctx1", queueHash: "q1")
        #expect(RestoreCheck(before: before, after: edge).unrestored.isEmpty)
        #expect(RestoreCheck(before: before, after: beyond).unrestored == [.position])
    }
}
