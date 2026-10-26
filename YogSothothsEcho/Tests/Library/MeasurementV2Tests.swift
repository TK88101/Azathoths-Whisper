import Foundation
import Testing

@testable import YogSothothsEcho

// S6 #6-1 g 版 T5（s6-61-g-perf-wear.md §5.5）：量測 schema v2——layout／axis、p95 幀間隔、>100 ms 次數、強制作廢原因
struct MeasurementV2Tests {
    static func record(layout: BrowseLayout = .grid, axis: MeasurementRecord.Axis = .y, flicks: Int = 10,
                       voidReason: MeasurementRecord.VoidReason? = nil, intervals: [Double] = Array(repeating: 1.0 / 60, count: 120))
        -> MeasurementRecord {
        MeasurementRecord(kind: .scroll, trialID: 1, cache: .warm, device: "x", osVersion: "y", build: "z", firstScreenCells: nil,
                          firstScreenSeconds: nil, frameIntervals: intervals, flickCount: flicks, scrollStartOffset: 0, scrollEndOffset: 900,
                          scrollSeconds: 3, layout: layout, axis: axis, voidReason: voidReason)
    }

    @Test func versionTwoCarriesLayoutAxisAndNewMetrics() throws {
        let object = try #require(try JSONSerialization.jsonObject(with: Self.record().encoded()) as? [String: Any])
        #expect(MeasurementRecord.protocolVersion == 2)
        #expect(object["protocolVersion"] as? Int == 2)
        #expect(object["layout"] as? String == "grid" && object["axis"] as? String == "y")
        #expect(object["p95FrameIntervalMs"] != nil && object["framesOver100ms"] as? Int == 0)
        #expect(Set(object.keys).isSubset(of: MeasurementRecord.allowedKeys))
        let spines = try #require(try JSONSerialization.jsonObject(with: Self.record(layout: .spines, axis: .x).encoded()) as? [String: Any])
        #expect(spines["layout"] as? String == "spines" && spines["axis"] as? String == "x")
    }

    /// 最近秩法：100 個間隔中 95 個 10 ms、5 個 200 ms → p95＝10 ms；>100 ms＝5
    @Test func p95AndOver100msOnKnownSequence() {
        let intervals = Array(repeating: 0.010, count: 95) + Array(repeating: 0.200, count: 5)
        #expect(FrameRateJudge.p95Interval(intervals) == 0.010)
        #expect(FrameRateJudge.intervalsOver(intervals, seconds: 0.1) == 5)
        let shifted = Array(repeating: 0.010, count: 94) + Array(repeating: 0.200, count: 6)
        #expect(FrameRateJudge.p95Interval(shifted) == 0.200)
        #expect(FrameRateJudge.p95Interval([]) == nil)
    }

    @Test func forcedVoidEvenWithTenFlicks() throws {
        let record = Self.record(flicks: 10, voidReason: .layoutChanged)
        #expect(record.isVoid)
        let object = try #require(try JSONSerialization.jsonObject(with: record.encoded()) as? [String: Any])
        #expect(object["void"] as? Bool == true && object["voidReason"] as? String == "layoutChanged")
        #expect(!Self.record(flicks: 10).isVoid)
    }
}

#if DEBUG
@MainActor
struct FrameRateMonitorLayoutTests {
    @Test func switchingLayoutWhileRecordingVoidsTheTrial() {
        let monitor = FrameRateMonitor.shared
        let layout = BrowseLayoutViewModel(store: InMemorySettingsStore())
        monitor.begin(layout: .spines)
        layout.toggle()
        #expect(!monitor.isRecording)
        #expect(monitor.lastVoidReason == .layoutChanged)
        #expect(monitor.lastResult?.hasPrefix("void") == true)
    }

    @Test func beginTakesTheAxisOffsetOfItsLayout() {
        let monitor = FrameRateMonitor.shared
        monitor.scrolled(to: 500, axis: .x)
        monitor.scrolled(to: 70, axis: .y)
        monitor.begin(layout: .grid)
        #expect(monitor.trialStartOffset == 70)
        monitor.end()
    }
}
#endif
