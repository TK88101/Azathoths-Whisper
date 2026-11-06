import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.5「時間軸，跨 persistentID」＋ §12-1（/thecure）：歌詞雜湊、歌手曲名 exactKey 完全相同、曲長差 ≤ 0.5 s、
// 錨點套得上、對齊器版本不低於現行；sourceRef 去重後唯一、或多份錨點完全一致才採用。歌詞與名字自編
@Suite("Remote timing index")
struct RemoteTimingIndexTests {
    static let lyrics = "Lanterns over the river\nAsh in the wind\nCount the silent bells\nPaper boats at dawn"
    static let hash = LyricsFingerprint.of(lyrics)
    static let query = TimingQuery(artist: "Some Band", title: "Lantern Song", duration: 200)
    static let anchors = [TimingRecord.LineStart(index: 0, start: 10), .init(index: 1, start: 14), .init(index: 2, start: 20), .init(index: 3, start: 24)]
    static let shifted = anchors.map { TimingRecord.LineStart(index: $0.index, start: $0.start + 1) }
    static let base = Date(timeIntervalSince1970: 1_800_000_000)

    static func remote(
        pid: String = "BBBB000000000001", origin: String = "000000000000000b", lines: [TimingRecord.LineStart] = anchors,
        artist: String = "Some Band", title: String = "Lantern Song", duration: Double = 200, revision: Int = LRCAligner.revision,
        sourceRef: String? = nil, match: Bool = true, hash: LyricsFingerprint = hash
    ) -> TimingRecord {
        TimingRecord(persistentID: pid, lyricsHash: hash, outcome: .found(source: .lrclib, lines: lines), fetchedAt: base,
                     alignerRevision: revision, origin: origin, sourceRef: sourceRef ?? "\(origin):\(pid)",
                     match: match ? TimingMatch(artist: artist, title: title, duration: duration) : nil)
    }

    private func pick(_ records: [TimingRecord]) -> TimingRecord? {
        RemoteTimingIndex.pick(records, for: Self.query, lyricsHash: Self.hash, lineCount: 4)
    }

    @Test func aSingleExactCandidateIsPicked() {
        #expect(pick([Self.remote()]) == Self.remote())
    }

    @Test func caseAndWidthDifferencesStillCountAsExact() {
        #expect(pick([Self.remote(artist: "SOME BAND", title: "lantern song")]) != nil)
    }

    @Test(arguments: [
        ("one letter off in the artist", remote(artist: "Some Bands")),
        ("one letter off in the title", remote(title: "Lantern Songs")),
        ("a remaster marker", remote(title: "Lantern Song (Remastered)")),
        ("duration 0.6 s apart", remote(duration: 200.6)),
        ("an incompatible older aligner", remote(revision: LRCAligner.foundCompatibleRevision - 1)),
        ("no match fields", remote(match: false)),
        ("anchors past the last line", remote(lines: [.init(index: 0, start: 1), .init(index: 9, start: 5)])),
        ("different lyrics", remote(hash: LyricsFingerprint.of("some other invented words"))),
    ])
    func aCandidateThatIsNotExactIsRefused(_ label: String, _ record: TimingRecord) {
        #expect(pick([record]) == nil, "\(label)")
    }

    @Test func aNotFoundIsNeverUsedAcrossIDs() {
        let notFound = TimingRecord(persistentID: "BBBB000000000001", lyricsHash: Self.hash, outcome: .notFound, fetchedAt: Self.base,
                                    origin: "000000000000000b", match: TimingMatch(artist: "Some Band", title: "Lantern Song", duration: 200))
        #expect(pick([notFound]) == nil)
    }

    @Test func twoCopiesOfTheSameSourceCountAsOne() {
        let original = Self.remote()
        let forwarded = Self.remote(pid: "CCCC000000000001", origin: "000000000000000c", sourceRef: original.sourceRef)
        #expect(pick([original, forwarded]) != nil, "別台轉存的同一份只算一個候選（R2-B1）")
    }

    @Test func twoSourcesThatAgreeExactlyAreAccepted() {
        let a = Self.remote(pid: "BBBB000000000001", origin: "000000000000000b")
        let b = Self.remote(pid: "CCCC000000000001", origin: "000000000000000c")
        #expect(pick([a, b]) == a, "錨點完全一致＝視為一致，取 sourceRef 小者")
        #expect(pick([b, a]) == a)
    }

    @Test func twoSourcesThatDisagreeAreRefused() {
        let a = Self.remote(pid: "BBBB000000000001", origin: "000000000000000b")
        let b = Self.remote(pid: "CCCC000000000001", origin: "000000000000000c", lines: Self.shifted)
        #expect(pick([a, b]) == nil)
    }

    @Test func versionsOfOneSourceResolveToTheSameRepresentativeInAnyOrder() {
        let older = Self.remote(lines: Self.anchors, revision: LRCAligner.foundCompatibleRevision - 1)
        let newer = Self.remote(lines: Self.shifted, revision: LRCAligner.foundCompatibleRevision)
        #expect(pick([older, newer]) == newer)
        #expect(pick([newer, older]) == newer, "R3-4：同一 sourceRef 依全序選代表")
    }

    /// ⑩ 計劃 §4.3：達到 `foundCompatibleRevision` 的版本同級——rev 2 的遠端 found 仍可跨 ID 採用，且 rev 2／3 不以版本分勝負
    @Test func compatibleRevisionsAreEligibleAndRankedEqually() {
        #expect(pick([Self.remote(revision: LRCAligner.foundCompatibleRevision)]) != nil)
        let two = Self.remote(lines: Self.anchors, revision: LRCAligner.foundCompatibleRevision)
        let three = Self.remote(lines: Self.shifted, revision: LRCAligner.revision)
        #expect(pick([two, three]) == pick([three, two]))
        let byDigestOnly = pick([Self.remote(lines: Self.anchors, revision: LRCAligner.revision), Self.remote(lines: Self.shifted, revision: LRCAligner.revision)])
        #expect(pick([two, three])?.outcome == byDigestOnly?.outcome)
    }

    @Test func theIndexKeepsEachWritersRecordsAndReplacesThemWhole() async {
        let index = RemoteTimingIndex()
        await index.replace(writer: "000000000000000b", records: [Self.remote()])
        await index.replace(writer: "000000000000000c", records: [Self.remote(pid: "CCCC000000000001", origin: "000000000000000c")])
        #expect(await index.candidates(for: Self.hash).count == 2)
        await index.replace(writer: "000000000000000c", records: [])
        #expect(await index.candidates(for: Self.hash).count == 1)
    }
}

// 接進 TimingResolver：本機查無可用記錄時，在打外部來源之前先查遠端
@Suite("Remote timing in the resolver")
struct RemoteTimingResolverTests {
    static let id = "0123456789ABCDEF"
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func setUp(_ candidates: [TimingRecord], providers: [FakeTimingProvider]) -> (TimingResolver, TimingStore) {
        let store = TimingStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("azw-remote-resolver-\(UUID().uuidString)"))
        let resolver = TimingResolver(
            providers: providers, store: store, metadata: { _ in RemoteTimingIndexTests.query }, switches: .allEnabled,
            deadlineSleeper: NeverSleeper(), clock: FakeTimingClock(), now: { Self.now },
            remoteCandidates: { _ in candidates }
        )
        return (resolver, store)
    }

    @Test func anExactRemoteTimelineIsUsedWithoutAskingAnySource() async {
        let provider = FakeTimingProvider(.lrclib, [])
        let (resolver, store) = setUp([RemoteTimingIndexTests.remote()], providers: [provider])
        let result = await resolver.resolve(TimingRequest(persistentID: Self.id, lyrics: RemoteTimingIndexTests.lyrics, query: nil), priority: .background)
        #expect(result.outcome == .found(.lrclib, RemoteTimingIndexTests.anchors))
        #expect(await provider.callCount == 0)
        let stored = await store.load(persistentID: Self.id)
        #expect(stored?.sourceRef == "000000000000000b:BBBB000000000001", "保留遠端來源")
        #expect(stored?.origin == "000000000000000b")
    }

    @Test func aStaleLocalRecordForOldLyricsDoesNotBlockTheRemoteMatch() async throws {
        let (resolver, store) = setUp([RemoteTimingIndexTests.remote()], providers: [FakeTimingProvider(.lrclib, [])])
        try await store.save(TimingRecord(persistentID: Self.id, lyricsHash: LyricsFingerprint.of("old invented words"), outcome: .notFound, fetchedAt: Self.now))
        let result = await resolver.resolve(TimingRequest(persistentID: Self.id, lyrics: RemoteTimingIndexTests.lyrics, query: nil), priority: .background)
        #expect(result.outcome == .found(.lrclib, RemoteTimingIndexTests.anchors), "R1-7：不以本機有沒有同 pid 檔決定")
    }

    @Test func withoutAnExactMatchTheChainRunsAndRecordsItsOwnMatch() async {
        let matched = MatchedTrack(artist: "Some Band", title: "Lantern Song", duration: 200)
        let aligned = ProviderOutcome.timed(
            [LRCLine(start: 10, text: "Lanterns over the river"), LRCLine(start: 14, text: "Ash in the wind"),
             LRCLine(start: 20, text: "Count the silent bells"), LRCLine(start: 24, text: "Paper boats at dawn")], matched: matched
        )
        let provider = FakeTimingProvider(.deezer, [.outcome(aligned)])
        let (resolver, store) = setUp([RemoteTimingIndexTests.remote(title: "Lantern Song (Live)")], providers: [provider])
        _ = await resolver.resolve(TimingRequest(persistentID: Self.id, lyrics: RemoteTimingIndexTests.lyrics, query: nil), priority: .background)
        #expect(await provider.callCount == 1)
        let stored = await store.load(persistentID: Self.id)
        #expect(stored?.match == TimingMatch(artist: "Some Band", title: "Lantern Song", duration: 200), "寫入當下的查詢欄位")
        #expect(stored?.sourceRef == nil, "本機新查到的：蓋章時才給自己的 sourceRef")
    }
}
