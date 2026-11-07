import Foundation
import Testing

@testable import AzathothsWhisper

// ⑪ 計劃 §4.1–§4.3：可用條件、存檔與畫面是否一致（provenance）、角落 `~`／`!` 的判定。歌詞為編造句
@Suite("Timing flag provenance")
struct TimingFlagProvenanceTests {
    static let pid = "0123456789ABCDEF"
    static let hash = LyricsFingerprint.of("Lanterns over the river\nAsh in the wind")
    static let anchors: [TimingRecord.LineStart] = [.init(index: 0, start: 5), .init(index: 1, start: 9)]
    static let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(
        hash: LyricsFingerprint = hash, outcome: TimingRecord.Outcome = .found(source: .lrclib, lines: anchors)
    ) -> TimingRecord {
        TimingRecord(persistentID: Self.pid, lyricsHash: hash, outcome: outcome, fetchedAt: Self.fetchedAt, alignerRevision: 3,
                     origin: "machine-a", sourceRef: "machine-a:\(Self.pid)")
    }

    private let applied = AppliedTiming(source: .lrclib, anchors: anchors)

    @Test func aStoredRecordIdenticalToTheScreenIsMatched() {
        let result = TimingFlagProvenance.resolve(applied: applied, lyricsHash: Self.hash, record: record())
        #expect(result.provenance == .matched)
        #expect(result.stored == TimingFlag.StoredIdentity(
            source: .lrclib, alignerRevision: 3, fetchedAt: Self.fetchedAt, sourceRef: "machine-a:\(Self.pid)", origin: "machine-a"
        ))
    }

    @Test func noStoredRecordIsStoreMissing() {
        let result = TimingFlagProvenance.resolve(applied: applied, lyricsHash: Self.hash, record: nil)
        #expect(result.provenance == .storeMissing)
        #expect(result.stored == nil)
    }

    @Test(arguments: [
        TimingRecord.Outcome.notFound,
        .found(source: .netease, lines: anchors),
        .found(source: .lrclib, lines: [.init(index: 0, start: 5), .init(index: 1, start: 9.5)]),
    ])
    func aStoredRecordThatDiffersFromTheScreenIsStoreMismatch(outcome: TimingRecord.Outcome) {
        let result = TimingFlagProvenance.resolve(applied: applied, lyricsHash: Self.hash, record: record(outcome: outcome))
        #expect(result.provenance == .storeMismatch)
        #expect(result.stored == nil)
    }

    @Test func aStoredRecordForOtherLyricsIsStoreMismatch() {
        let result = TimingFlagProvenance.resolve(applied: applied, lyricsHash: Self.hash, record: record(hash: .of("Quiet harbor")))
        #expect(result.provenance == .storeMismatch)
    }

    @Test func embeddedLRCNeverConsultsTheStore() {
        let embedded = AppliedTiming(source: .embeddedLRC, anchors: Self.anchors)
        let result = TimingFlagProvenance.resolve(applied: embedded, lyricsHash: Self.hash, record: record())
        #expect(result.provenance == .embedded)
        #expect(result.stored == nil)
    }

    // MARK: 角落標記（可標記與 `!` 共用「畫面有快照」一個判斷：VM 的 `appliedTiming` 只在非估算時存在）

    private func timeline(_ source: TimingSource) -> LyricsTimeline {
        LyricsTimeline(lines: [TimedLine(start: 5, end: 9, text: "Lanterns over the river", isChorus: false)], source: source, duration: 200)
    }

    @Test func theCornerShowsTheTildeForEstimatedTimingEvenWhenFlagged() {
        #expect(LyricsFXTimingMark.resolve(timeline: timeline(.estimated), status: .present, flag: .flagged, hasAppliedTiming: false) == .estimated)
    }

    @Test func theCornerShowsTheFlagOnlyForAFlaggedAppliedTimeline() {
        #expect(LyricsFXTimingMark.resolve(timeline: timeline(.lrclib), status: .present, flag: .flagged, hasAppliedTiming: true) == .flagged)
        #expect(LyricsFXTimingMark.resolve(timeline: timeline(.lrclib), status: .present, flag: .unflagged, hasAppliedTiming: true) == .none)
        #expect(LyricsFXTimingMark.resolve(timeline: timeline(.lrclib), status: .present, flag: .pending, hasAppliedTiming: true) == .none)
        #expect(LyricsFXTimingMark.resolve(timeline: timeline(.lrclib), status: .present, flag: .flagged, hasAppliedTiming: false) == .none)
    }

    @Test func lineStartsFollowTheDisplayedLines() {
        let timeline = LyricsTimeline(lines: [
            TimedLine(start: 1, end: 3, text: "Lanterns", isChorus: false),
            TimedLine(start: 3.5, end: 6, text: "Ash", isChorus: false),
        ], source: .embeddedLRC, duration: 10)
        #expect(timeline.lineStarts == [.init(index: 0, start: 1), .init(index: 1, start: 3.5)])
    }
}
