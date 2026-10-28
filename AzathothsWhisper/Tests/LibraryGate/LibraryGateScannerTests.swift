import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.5：整庫五欄＋逐寫法讀歌詞；同時只排一個 AE 工作、取消後不再排、讀不完整不發布。歌手、歌詞自編
@Suite("Library gate scanner")
struct LibraryGateScannerTests {
    static let english = "Lanterns drift across the harbour\nPaper boats remember rain"
    static let japanese = "かみのふねがながれる\nあめのおとをおぼえてる"
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func row(_ id: String, _ artist: String, genre: String = "Rock") -> LibraryTrackRow {
        LibraryTrackRow(persistentID: id, name: "Song \(id)", artist: artist, album: "Paper Boats", genre: genre)
    }

    private func scanner(_ music: MockMusicClient) -> LibraryGateScanner {
        LibraryGateScanner(music: music, now: { Self.start })
    }

    actor Progress {
        private(set) var steps: [(done: Int, total: Int)] = []
        func record(_ done: Int, _ total: Int) { steps.append((done, total)) }
    }

    @Test func aCompleteScanCarriesLyricsFlagsPerTrack() async throws {
        let music = MockMusicClient()
        await music.setSnapshot([row("1", "Paper Harbour"), row("2", "Paper Harbour"), row("3", "Velvet Lanterns")])
        await music.setArtistLyrics([.init(persistentID: "1", lyrics: Self.japanese), .init(persistentID: "2", lyrics: "  \n")], for: "Paper Harbour")
        await music.setArtistLyrics([.init(persistentID: "3", lyrics: Self.english)], for: "Velvet Lanterns")
        let progress = Progress()
        let outcome = try await scanner(music).scan { done, total in await progress.record(done, total) }
        guard case .complete(let scan) = outcome else { Issue.record("\(outcome)"); return }
        #expect(scan.tracks.map(\.persistentID) == ["1", "2", "3"])
        #expect(scan.tracks.map(\.isJapanese) == [true, false, false])
        #expect(scan.tracks.map(\.hasLyrics) == [true, false, true])
        #expect(scan.startedAt == Self.start && scan.finishedAt == Self.start)
        #expect(await progress.steps.last.map { $0.done == $0.total } == true)
    }

    @Test func everySpellingOfAGroupIsAskedAndDuplicatesAreMerged() async throws {
        let music = MockMusicClient()
        await music.setSnapshot([row("1", "Paper Harbour"), row("2", "PAPER HARBOUR")])
        // AE 的比對可能不分大小寫：兩種寫法都回同一批曲
        let both: [ArtistLyricsRow] = [.init(persistentID: "1", lyrics: Self.english), .init(persistentID: "2", lyrics: Self.english)]
        await music.setArtistLyrics(both, for: "Paper Harbour")
        await music.setArtistLyrics(both, for: "PAPER HARBOUR")
        let outcome = try await scanner(music).scan { _, _ in }
        guard case .complete(let scan) = outcome else { Issue.record("\(outcome)"); return }
        #expect(Set(await music.artistLyricsRequests) == ["Paper Harbour", "PAPER HARBOUR"])
        #expect(scan.tracks.count == 2, "以 persistentID 去重，不重複計數（R3-1）")
    }

    @Test func aSnapshotFailureIsIncomplete() async throws {
        let music = MockMusicClient()
        await music.failSnapshot(.scriptingFailure("library read incomplete"))
        #expect(try await scanner(music).scan { _, _ in } == .incomplete(.snapshotFailed))
    }

    @Test func aFailedArtistReadIsIncomplete() async throws {
        let music = MockMusicClient()
        await music.setSnapshot([row("1", "Paper Harbour"), row("2", "Velvet Lanterns")])
        await music.setArtistLyrics([.init(persistentID: "1", lyrics: Self.english)], for: "Paper Harbour")
        await music.failArtistLyrics(.scriptingFailure("library read incomplete"), for: "Velvet Lanterns")
        #expect(try await scanner(music).scan { _, _ in } == .incomplete(.artistReadFailed))
    }

    @Test func tracksMissingFromTheArtistReadsAreIncomplete() async throws {
        let music = MockMusicClient()
        await music.setSnapshot([row("1", "Paper Harbour"), row("2", "Paper Harbour")])
        await music.setArtistLyrics([.init(persistentID: "1", lyrics: Self.english)], for: "Paper Harbour")
        #expect(try await scanner(music).scan { _, _ in } == .incomplete(.tracksMissing))
    }

    @Test func anEmptyLibraryIsIncompleteNotAnEmptyPass() async throws {
        #expect(try await scanner(MockMusicClient()).scan { _, _ in } == .incomplete(.emptyLibrary))
    }

    @Test func onlyOneArtistReadIsInFlightAtATime() async throws {
        let music = MockMusicClient()
        await music.setSnapshot((1...5).map { row("\($0)", "Artist \($0)") })
        for index in 1...5 { await music.setArtistLyrics([.init(persistentID: "\(index)", lyrics: Self.english)], for: "Artist \(index)") }
        _ = try await scanner(music).scan { _, _ in }
        #expect(await music.maxArtistLyricsInFlight == 1)
        #expect(await music.artistLyricsRequests.count == 5)
    }

    @Test func cancellationStopsBeforeTheNextRead() async throws {
        let music = MockMusicClient()
        await music.setSnapshot((1...3).map { row("\($0)", "Artist \($0)") })
        let gate = LyricsGate()
        await music.gateArtistLyrics(gate)
        let task = Task { try await scanner(music).scan { _, _ in } }
        while await music.artistLyricsRequests.isEmpty { await Task.yield() }
        task.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await music.artistLyricsRequests.count == 1, "取消後不再排下一個 AE 工作")
    }
}
