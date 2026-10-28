import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.3、§4.5：曲庫檢查畫面的狀態。掃描與存檔都是替身；歌手名自編
@MainActor
@Suite("Library check view model")
struct LibraryCheckViewModelTests {
    nonisolated static let start = Date(timeIntervalSince1970: 1_790_000_000)

    nonisolated private static func track(_ id: String, _ artist: String, genre: String = "Rock") -> ScannedTrack {
        ScannedTrack(persistentID: id, name: "Song \(id)", artist: artist, album: "Paper Boats", genre: genre, hasLyrics: true, isJapanese: false)
    }

    nonisolated private static let library = [
        track("1", "Paper Harbour"),                          // 素面＋身分未查
        track("2", "Velvet Lanterns", genre: "Black Metal"),  // 有樣式、身分未查 → 可批次照目前樣式
    ]

    final class Saved { var books: [ArtistDecisionBook] = []; var fails = false }
    struct SaveFailed: Error {}

    private func model(outcomes: [LibraryScanOutcome] = [.complete(LibraryScan(tracks: library, startedAt: start, finishedAt: start))],
                       saved: Saved = Saved(), ready: Bool = true) -> LibraryCheckViewModel {
        let queue = OutcomeQueue(outcomes)
        let vm = LibraryCheckViewModel(decisions: ArtistDecisionBook(), now: { Self.start })
        vm.scanLibrary = { progress in
            await progress(1, 1)
            return await queue.next()
        }
        vm.artistStyles = { ArtistStyleBook() }
        vm.isArtistDataReady = { ready }
        vm.onDecisionsChanged = { book in
            if saved.fails { throw SaveFailed() }
            saved.books.append(book)
        }
        return vm
    }

    actor OutcomeQueue {
        private var outcomes: [LibraryScanOutcome]
        init(_ outcomes: [LibraryScanOutcome]) { self.outcomes = outcomes }
        func next() -> LibraryScanOutcome { outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0] }
    }

    private func scanned(_ vm: LibraryCheckViewModel) async {
        vm.rescan()
        await vm.waitForScan()
    }

    @Test func aCompleteScanProducesAReport() async {
        let vm = model()
        #expect(vm.status == .notScanned)
        await scanned(vm)
        #expect(vm.report?.identity == .init(songs: 2, artists: 2))
        #expect(vm.report?.composed == .init(songs: 1, artists: 1))
        #expect(vm.status == .failing)
        #expect(vm.scannedAt == Self.start)
    }

    @Test func choosingAStyleRecomputesAndIsSaved() async throws {
        let saved = Saved()
        let vm = model(saved: saved)
        await scanned(vm)
        vm.decide(.style(rowID: "punk"), forArtists: ["Paper Harbour"])
        #expect(vm.report?.composed == .zero)
        #expect(vm.report?.identity == .init(songs: 1, artists: 1))
        #expect(saved.books.last?.decision(forArtist: "Paper Harbour")?.choice == .style(rowID: "punk"))
        #expect(vm.decisionsAppliedAt == Self.start)
    }

    @Test func aFailedSaveDoesNotApplyTheDecision() async {
        let saved = Saved()
        saved.fails = true
        let vm = model(saved: saved)
        await scanned(vm)
        vm.decide(.style(rowID: "punk"), forArtists: ["Paper Harbour"])
        #expect(vm.report?.composed == .init(songs: 1, artists: 1))
        #expect(vm.saveFailed)
        #expect(vm.decisions == ArtistDecisionBook())
    }

    @Test func aSignedBandStyleIsRefused() async {
        let vm = model()
        await scanned(vm)
        vm.decide(.style(rowID: "punk"), forArtists: ["Mayhem"])
        #expect(vm.decisions.decision(forArtist: "Mayhem") == nil)
    }

    @Test func clearingBringsTheIssueBack() async {
        let vm = model()
        await scanned(vm)
        vm.decide(.keepFallback, forArtists: ["Paper Harbour"])
        vm.clear(forArtists: ["Paper Harbour"])
        #expect(vm.report?.identity == .init(songs: 2, artists: 2))
    }

    @Test func bulkKeepFallbackSkipsArtistsWithMonoSongs() async {
        let vm = model()
        await scanned(vm)
        let keys = vm.report?.artists.map(\.key) ?? []
        vm.keepFallbackInBulk(keys: keys)
        #expect(vm.decisions.decision(forArtist: "Velvet Lanterns")?.choice == .keepFallback)
        #expect(vm.decisions.decision(forArtist: "Paper Harbour") == nil, "有素面曲的歌手要一位一位處理")
    }

    @Test func newArtistDataMakesTheResultNeedARescan() async {
        let vm = model(outcomes: [.complete(LibraryScan(tracks: [Self.track("2", "Velvet Lanterns", genre: "Black Metal")], startedAt: Self.start, finishedAt: Self.start))])
        await scanned(vm)
        vm.decide(.keepFallback, forArtists: ["Velvet Lanterns"])
        #expect(vm.status == .passed)
        vm.artistDataChanged()
        #expect(vm.status == .needsRescan)
        await scanned(vm)
        #expect(vm.status == .passed)
    }

    @Test func passingIsNotClaimedBeforeTheArtistDataIsReady() async {
        let vm = model(outcomes: [.complete(LibraryScan(tracks: [Self.track("2", "Velvet Lanterns", genre: "Black Metal")], startedAt: Self.start, finishedAt: Self.start))], ready: false)
        await scanned(vm)
        vm.decide(.keepFallback, forArtists: ["Velvet Lanterns"])
        #expect(vm.status == .needsRescan)
    }

    @Test func anIncompleteScanKeepsThePreviousReportAndCannotPass() async {
        let complete = LibraryScanOutcome.complete(LibraryScan(tracks: Self.library, startedAt: Self.start, finishedAt: Self.start))
        let vm = model(outcomes: [complete, .incomplete(.artistReadFailed)])
        await scanned(vm)
        let previous = vm.report
        await scanned(vm)
        #expect(vm.report == previous)
        #expect(vm.status == .incomplete(.artistReadFailed))
    }

    @Test func aReplacedScanNeverPublishes() async {
        let gate = LyricsGate()
        let vm = LibraryCheckViewModel(decisions: ArtistDecisionBook(), now: { Self.start })
        vm.artistStyles = { ArtistStyleBook() }
        vm.isArtistDataReady = { true }
        vm.onDecisionsChanged = { _ in }
        let calls = Counter()
        vm.scanLibrary = { _ in
            let call = await calls.next()
            if call == 0 { await gate.wait() }
            let tracks = call == 0 ? [Self.track("old", "Paper Harbour")] : [Self.track("new", "Velvet Lanterns", genre: "Black Metal")]
            return .complete(LibraryScan(tracks: tracks, startedAt: Self.start, finishedAt: Self.start))
        }
        vm.rescan()
        while await calls.value == 0 { await Task.yield() }
        vm.rescan()
        await vm.waitForScan()
        await gate.open()
        await Task.yield()
        #expect(vm.report?.rows.map(\.track.persistentID) == ["new"])
    }

    @Test func progressIsShownWhileScanning() async {
        let gate = LyricsGate()
        let vm = LibraryCheckViewModel(decisions: ArtistDecisionBook(), now: { Self.start })
        vm.artistStyles = { ArtistStyleBook() }
        vm.isArtistDataReady = { true }
        vm.onDecisionsChanged = { _ in }
        vm.scanLibrary = { progress in
            await progress(3, 10)
            await gate.wait()
            return .incomplete(.emptyLibrary)
        }
        vm.rescan()
        while vm.status != .scanning(done: 3, total: 10) { await Task.yield() }
        vm.cancelScan()
        await gate.open()
        await vm.waitForScan()
        #expect(vm.status == .notScanned)
    }

    actor Counter {
        private(set) var value = 0
        func next() -> Int { defer { value += 1 }; return value }
    }
}
