import Foundation
import Testing
@testable import SpikeCore

// F-P-01 點歌脈絡（s0-report.md「N1 後續方案」）：期待序列、佇列穩定判定、樣本與判定、捷徑輸入。
struct AlbumSuffixTests {
    private let album = [
        AlbumTrack(id: "C", disc: 1, number: 3), AlbumTrack(id: "A", disc: 1, number: 1),
        AlbumTrack(id: "D", disc: 2, number: 1), AlbumTrack(id: "B", disc: 1, number: 2),
    ]

    @Test func ordersByDiscThenNumberAndStartsAtTarget() {
        #expect(AlbumSuffix.ordered(album) == ["A", "B", "C", "D"])
        #expect(AlbumSuffix.expected(album, from: "B") == ["B", "C", "D"])
    }

    @Test func positionIsOneBased() {
        #expect(AlbumSuffix.position(of: "C", in: album) == 3)
        #expect(AlbumSuffix.position(of: "Z", in: album) == nil)
    }

    @Test func missingDiscCountsAsDiscOne() {
        let tracks = [AlbumTrack(id: "X", disc: 0, number: 2), AlbumTrack(id: "Y", disc: 1, number: 1)]
        #expect(AlbumSuffix.ordered(tracks) == ["Y", "X"])
    }

    @Test func unknownTargetHasNoExpectation() {
        #expect(AlbumSuffix.expected(album, from: "Z") == nil)
    }

    /// 同一 disc／曲序出現兩次＝順序無定義，不產生期待值（樣本改選別的專輯）
    @Test func duplicatePositionsHaveNoDefinedOrder() {
        let tracks = album + [AlbumTrack(id: "E", disc: 1, number: 2)]
        #expect(AlbumSuffix.ordered(tracks) == nil)
        #expect(AlbumSuffix.expected(tracks, from: "A") == nil)
    }

    @Test func zeroTrackNumberHasNoDefinedOrder() {
        #expect(AlbumSuffix.ordered([AlbumTrack(id: "A", disc: 1, number: 0)]) == nil)
    }
}

struct QueueSettleTests {
    @Test func stableWhenSameSequenceSpansTheGap() {
        let reads: [QueueRead] = [.init(at: 0, ids: ["A"]), .init(at: 0.5, ids: ["A", "B"]),
                                  .init(at: 1.0, ids: ["A", "B"]), .init(at: 1.5, ids: ["A", "B"])]
        #expect(QueueSettle.stable(reads, minGap: 1.0) == ["A", "B"])
    }

    @Test func notStableBeforeTheGapElapses() {
        let reads: [QueueRead] = [.init(at: 0, ids: ["A"]), .init(at: 0.5, ids: ["A"])]
        #expect(QueueSettle.stable(reads, minGap: 1.0) == nil)
    }

    @Test func aChangeRestartsTheRun() {
        let reads: [QueueRead] = [.init(at: 0, ids: ["A"]), .init(at: 0.6, ids: ["B"]), .init(at: 1.2, ids: ["A"])]
        #expect(QueueSettle.stable(reads, minGap: 1.0) == nil)
    }

    @Test func unreadableReadsBreakTheRun() {
        let reads: [QueueRead] = [.init(at: 0, ids: ["A"]), .init(at: 0.5, ids: nil), .init(at: 1.0, ids: ["A"])]
        #expect(QueueSettle.stable(reads, minGap: 1.0) == nil)
    }
}

struct FP01VerdictTests {
    private func sample(latency: Double? = 120, track: Bool = true, queue: Bool = true) -> FP01Sample {
        FP01Sample(albumID: "AL", position: 2, trackCount: 5, multiDisc: false, sharedTitle: false,
                   exitCode: 0, latencyMilliseconds: latency,
                   readID: track ? "B" : "Z", state: .playing, expectedStartID: "B",
                   settledQueue: queue ? ["B", "C"] : ["B"], expectedQueue: ["B", "C"])
    }

    @Test func sampleChecksAreIndependent() {
        let good = sample()
        #expect(good.trackCorrect && good.queueCorrect)
        #expect(!sample(track: false).trackCorrect)
        #expect(!sample(queue: false).queueCorrect)
    }

    @Test func unsettledQueueIsNotCorrect() {
        let unsettled = FP01Sample(albumID: "AL", position: 1, trackCount: 2, multiDisc: false, sharedTitle: false,
                                   exitCode: 0, latencyMilliseconds: 50, readID: "A", state: .playing,
                                   expectedStartID: "A", settledQueue: nil, expectedQueue: ["A", "B"])
        #expect(!unsettled.queueCorrect)
    }

    @Test func allGoodPasses() {
        #expect(FP01Verdict.judge(Array(repeating: sample(), count: 20)) == .pass)
    }

    @Test func tooFewSamplesIsUndetermined() {
        #expect(FP01Verdict.judge(Array(repeating: sample(), count: 19)) == .undetermined)
    }

    @Test func onlyLatencyFailingIsLatencyOnly() {
        let samples = Array(repeating: sample(latency: 800), count: 20)
        #expect(FP01Verdict.judge(samples) == .latencyOnly)
    }

    @Test func missingLatencyCountsAsSlow() {
        let samples = Array(repeating: sample(), count: 19) + [sample(latency: nil)]
        #expect(FP01Verdict.judge(samples) == .latencyOnly)
    }

    @Test func anyWrongTrackOrQueueFails() {
        #expect(FP01Verdict.judge(Array(repeating: sample(), count: 19) + [sample(track: false)]) == .fail)
        #expect(FP01Verdict.judge(Array(repeating: sample(), count: 19) + [sample(queue: false)]) == .fail)
        #expect(FP01Verdict.judge(Array(repeating: sample(latency: 900), count: 19) + [sample(queue: false)]) == .fail)
    }

    @Test func p95AtThresholdPasses() {
        let samples = Array(repeating: sample(latency: 300), count: 20)
        #expect(FP01Verdict.judge(samples) == .pass)
    }
}

struct ShortcutInputTests {
    @Test func jsonIsDeterministicAndRoundTrips() throws {
        let input = ShortcutInput(album: "A \"B\" / C: 1\u{00E9}\n", albumArtist: "", artist: "X & Y", position: 3,
                                  expectedCount: 12)
        let data = try input.json()
        #expect(String(decoding: data, as: UTF8.self)
                == #"{"album":"A \"B\" \/ C: 1é\n","albumArtist":"","artist":"X & Y","expectedCount":12,"position":3}"#)
        #expect(try JSONDecoder().decode(ShortcutInput.self, from: data) == input)
    }
}

struct FP01StartPositionTests {
    /// 起點 k 落在 1…n-1：佇列至少剩 2 首，才看得出有沒有接續
    @Test func startLeavesAtLeastTwoTracks() {
        for count in 2...30 {
            for index in 0..<20 {
                let k = FP01Plan.startPosition(trackCount: count, sampleIndex: index, seed: 7)
                #expect((1...(count - 1)).contains(k), "n=\(count) i=\(index) k=\(k)")
            }
        }
    }

    @Test func isDeterministic() {
        #expect(FP01Plan.startPosition(trackCount: 12, sampleIndex: 3, seed: 7)
                == FP01Plan.startPosition(trackCount: 12, sampleIndex: 3, seed: 7))
    }

    @Test func kindPutsMultiDiscAndSharedTitleInTheirOwnStrata() {
        #expect(FP01Plan.kind(multiDisc: true, sharedTitle: true) == "multi-disc")
        #expect(FP01Plan.kind(multiDisc: false, sharedTitle: true) == "shared-title")
        #expect(FP01Plan.kind(multiDisc: false, sharedTitle: false) == "plain")
    }
}

/// 捷徑許可閘門：只在「專輯名查找必定只撈到這張」時才交給捷徑，其餘降級為只播這首
struct ShortcutGateTests {
    private let tracks = [AlbumTrack(id: "A", disc: 1, number: 1), AlbumTrack(id: "B", disc: 1, number: 2)]

    private func index(_ entries: [(String, String)]) -> [String: Set<String>] {
        ShortcutGate.titleIndex(entries.map { (title: $0.0, albumID: $0.1) })
    }

    @Test func uniqueConsistentTitleIsAllowed() {
        let titles = index([("Night Drive", "AL1"), ("Night Drive", "AL1"), ("Day Trip", "AL2")])
        #expect(ShortcutGate.check(albumID: "AL1", trackTitles: ["Night Drive", "Night Drive"], tracks: tracks,
                                   titleIndex: titles) == nil)
    }

    @Test func emptyTitleIsRefused() {
        #expect(ShortcutGate.check(albumID: "AL1", trackTitles: ["", ""], tracks: tracks, titleIndex: [:]) == .emptyTitle)
    }

    /// 2026-10-15 fp01 #13：同一專輯 ID 下有曲目專輯名不同，名稱查找只撈到一部分
    @Test func inconsistentTitlesWithinAlbumAreRefused() {
        let titles = index([("Night Drive", "AL1"), ("Night Drive (Deluxe)", "AL1")])
        #expect(ShortcutGate.check(albumID: "AL1", trackTitles: ["Night Drive", "Night Drive (Deluxe)"], tracks: tracks,
                                   titleIndex: titles) == .inconsistentTitle)
    }

    /// 2026-10-15 fp01 #3：另一張同名專輯
    @Test func sameTitleOnAnotherAlbumIsRefused() {
        let titles = index([("Night Drive", "AL1"), ("Night Drive", "AL2")])
        #expect(ShortcutGate.check(albumID: "AL1", trackTitles: ["Night Drive", "Night Drive"], tracks: tracks,
                                   titleIndex: titles) == .ambiguousTitle)
    }

    @Test func titlesDifferingOnlyByCaseWidthOrAccentAreAmbiguous() {
        for variant in ["NIGHT DRIVE", "Ｎｉｇｈｔ Ｄｒｉｖｅ", "Night Dri\u{0301}ve", " Night Drive "] {
            let titles = index([("Night Drive", "AL1"), (variant, "AL2")])
            #expect(ShortcutGate.check(albumID: "AL1", trackTitles: ["Night Drive", "Night Drive"], tracks: tracks,
                                       titleIndex: titles) == .ambiguousTitle, "\(variant)")
        }
    }

    @Test func undefinedOrderIsRefused() {
        let titles = index([("Night Drive", "AL1")])
        let duplicated = [AlbumTrack(id: "A", disc: 1, number: 1), AlbumTrack(id: "B", disc: 1, number: 1)]
        #expect(ShortcutGate.check(albumID: "AL1", trackTitles: ["Night Drive", "Night Drive"], tracks: duplicated,
                                   titleIndex: titles) == .orderUndefined)
    }

    /// 索引裡查不到自己（呼叫端漏建索引）不能當成唯一
    @Test func missingFromIndexIsRefused() {
        #expect(ShortcutGate.check(albumID: "AL1", trackTitles: ["Night Drive", "Night Drive"], tracks: tracks,
                                   titleIndex: [:]) == .ambiguousTitle)
    }
}
