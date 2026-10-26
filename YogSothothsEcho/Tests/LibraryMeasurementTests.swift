import Foundation
import Testing

@testable import YogSothothsEcho

// S3 T15（sprint-3-detail.md §4.11）：量測判定器（純函式）、首頁計時、JSON 欄位白名單、首屏格數

struct FrameRateJudgeTests {
    private func steady(fps: Double, seconds: Double, from start: Double = 0) -> [Double] {
        (0...Int(fps * seconds)).map { start + Double($0) / fps }
    }

    @Test func steadySixtyIsSixty() throws {
        let worst = try #require(FrameRateJudge.worstWindowFPS(steady(fps: 60, seconds: 3)))
        #expect(abs(worst - 60) < 1)
    }

    @Test func dipIsFoundBySlidingWindow() throws {
        let samples = steady(fps: 60, seconds: 2) + steady(fps: 20, seconds: 1.2, from: 2.05) + steady(fps: 60, seconds: 2, from: 3.3)
        let worst = try #require(FrameRateJudge.worstWindowFPS(samples.sorted()))
        #expect(worst < 30)
    }

    @Test func longStallCountsAsBelowOneFPS() throws {
        let samples = [0.0, 0.016, 0.032, 1.6, 1.616]
        #expect(try #require(FrameRateJudge.worstWindowFPS(samples)) < 1)
        #expect(try #require(FrameRateJudge.longestInterval(samples)) > 1.5)
    }

    @Test func slowFramesCountsIntervalsOverThirtyThreeMs() {
        #expect(FrameRateJudge.slowFrames([0, 0.016, 0.06, 0.076, 0.2]) == 2)
    }

    @Test func tooFewSamplesGivesNil() {
        #expect(FrameRateJudge.worstWindowFPS([0.0]) == nil)
    }

    @Test func passesOnlyWhenEveryWindowReachesThirty() {
        #expect(FrameRateJudge.passes(steady(fps: 40, seconds: 2)))
        #expect(!FrameRateJudge.passes(steady(fps: 25, seconds: 2)))
    }
}

@MainActor
struct LibraryMetricsTests {
    @Test func firstScreenEndsWhenEveryVisibleCellSettles() {
        var clock = Date(timeIntervalSince1970: 0)
        let metrics = LibraryMetrics(now: { clock })
        metrics.loadStarted()
        metrics.firstScreen(ids: ["a", "b"])
        clock += 0.8
        metrics.artworkSettled(id: "a")
        #expect(metrics.firstScreenSeconds == nil)
        clock += 0.4
        metrics.artworkSettled(id: "b")
        #expect(metrics.firstScreenSeconds.map { abs($0 - 1.2) < 0.001 } == true)
    }

    @Test func cellsOutsideFirstScreenDoNotMatter() {
        let metrics = LibraryMetrics(now: { Date(timeIntervalSince1970: 0) })
        metrics.loadStarted()
        metrics.firstScreen(ids: ["a"])
        metrics.artworkSettled(id: "z")
        #expect(metrics.firstScreenSeconds == nil)
    }
}

struct MeasurementRecordTests {
    @Test func jsonContainsOnlyWhitelistedKeys() throws {
        let record = MeasurementRecord(kind: .scroll, trialID: 3, cache: .cold, device: "iPad16,3", osVersion: "27.0", build: "7",
                                       firstScreenCells: nil, firstScreenSeconds: nil, frameIntervals: Array(repeating: 1.0 / 60, count: 180),
                                       flickCount: 10, scrollStartOffset: 0, scrollEndOffset: 5000, scrollSeconds: 9.5)
        let object = try #require(try JSONSerialization.jsonObject(with: record.encoded()) as? [String: Any])
        #expect(Set(object.keys).isSubset(of: MeasurementRecord.allowedKeys))
        #expect(object["protocolVersion"] as? Int == MeasurementRecord.protocolVersion)
        #expect(object["worstWindowFPS"] != nil && object["passes"] != nil)
    }

    @Test func flickCountOtherThanTenIsVoid() {
        let record = MeasurementRecord(kind: .scroll, trialID: 1, cache: .warm, device: "x", osVersion: "y", build: "z",
                                       firstScreenCells: nil, firstScreenSeconds: nil, frameIntervals: [0.016],
                                       flickCount: 9, scrollStartOffset: 0, scrollEndOffset: 100, scrollSeconds: 3)
        #expect(record.isVoid)
    }
}

struct LibraryPresentationTests {
    @Test func disconnectedWithAlbumsShowsDisconnectedLine() {
        #expect(LibraryPresentation.status(phase: .ready, connected: false, hasAlbums: true) == .disconnected)
        #expect(LibraryPresentation.status(phase: .failed(.libraryUnavailable), connected: true, hasAlbums: true) == .libraryUnavailable)
        #expect(LibraryPresentation.status(phase: .loading(loaded: 100), connected: true, hasAlbums: true, total: 1000)
                == .loading(loaded: 100, total: 1000))
    }
}

// #3-1 補：真機不能帶啟動參數，冷啟動改為「面板預約、下次啟動時清快取並標 cold」
struct ColdStartRequestTests {
    private func fixture() throws -> (UserDefaults, URL) {
        let defaults = try #require(UserDefaults(suiteName: "cold-start-\(UUID().uuidString)"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("tile"))
        return (defaults, directory)
    }

    @Test func requestedLaunchClearsCacheOnceAndReportsCold() throws {
        let (defaults, directory) = try fixture()
        ColdStartRequest.request(defaults: defaults)
        #expect(ColdStartRequest.isPending(defaults: defaults))

        #expect(ColdStartRequest.consume(directory: directory, defaults: defaults))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(!ColdStartRequest.isPending(defaults: defaults))
        #expect(!ColdStartRequest.consume(directory: directory, defaults: defaults))
    }

    @Test func launchWithoutRequestKeepsCacheAndIsWarm() throws {
        let (defaults, directory) = try fixture()
        #expect(!ColdStartRequest.consume(directory: directory, defaults: defaults))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("tile").path))
    }
}
