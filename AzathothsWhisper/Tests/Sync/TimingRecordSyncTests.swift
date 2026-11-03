import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.5「時間軸，同 persistentID」：不用時鐘決勝——本機沒有→採用；同詞 found 勝 notFound、
// 兩邊 found 取 alignerRevision 大者，其餘保留本機；異詞保留本機。§6.3 origin／sourceRef 的生命週期（整體確認 1、2）。
// 歌詞自編
@Suite("Timing record sync")
struct TimingRecordSyncTests {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)
    static let pid = "AAAA000000000001"
    static let macA = "000000000000000a"
    static let macB = "000000000000000b"
    static let lyrics = LyricsFingerprint.of("first invented line\nsecond invented line")
    static let otherLyrics = LyricsFingerprint.of("a different invented line")
    static let anchors = [TimingRecord.LineStart(index: 0, start: 1), .init(index: 1, start: 5)]
    static let otherAnchors = [TimingRecord.LineStart(index: 0, start: 2), .init(index: 1, start: 6)]

    private func found(_ hash: LyricsFingerprint = lyrics, _ lines: [TimingRecord.LineStart] = anchors, revision: Int = LRCAligner.revision,
                       origin: String? = macB, sourceRef: String? = nil, fetchedAt: Date = base) -> TimingRecord {
        TimingRecord(persistentID: Self.pid, lyricsHash: hash, outcome: .found(source: .lrclib, lines: lines), fetchedAt: fetchedAt,
                     alignerRevision: revision, origin: origin, sourceRef: sourceRef ?? origin.map { "\($0):\(Self.pid)" })
    }

    private func notFound(_ hash: LyricsFingerprint = lyrics, origin: String? = macB) -> TimingRecord {
        TimingRecord(persistentID: Self.pid, lyricsHash: hash, outcome: .notFound, fetchedAt: Self.base, origin: origin)
    }

    @Test func aRemoteRecordIsAdoptedWhenThisMacHasNone() {
        #expect(TimingRecord.importMerged(local: nil, remote: found()) == found())
    }

    @Test func aRemoteFoundBeatsALocalNotFoundForTheSameLyrics() {
        #expect(TimingRecord.importMerged(local: notFound(origin: Self.macA), remote: found()) == found())
    }

    @Test func aRemoteNotFoundNeverReplacesALocalFound() {
        let local = found(origin: Self.macA)
        #expect(TimingRecord.importMerged(local: local, remote: notFound()) == local)
    }

    @Test func betweenTwoFoundsTheNewerAlignerWinsOtherwiseLocalStays() {
        let local = found(revision: 1, origin: Self.macA)
        let remote = found(Self.lyrics, Self.otherAnchors, revision: 2)
        #expect(TimingRecord.importMerged(local: local, remote: remote) == remote)
        let sameRevision = found(origin: Self.macA)
        #expect(TimingRecord.importMerged(local: sameRevision, remote: found(Self.lyrics, Self.otherAnchors)) == sameRevision,
                "同版本不用時鐘決勝：保留本機")
    }

    @Test func differentLyricsKeepTheLocalRecord() {
        let local = found(Self.otherLyrics, origin: Self.macA, fetchedAt: Self.base)
        let newerRemote = found(fetchedAt: Self.base.addingTimeInterval(86_400 * 30))
        #expect(TimingRecord.importMerged(local: local, remote: newerRemote) == local, "R1-5：不信任 wall clock")
    }

    @Test func importingTheSameRecordTwiceChangesNothing() {
        let once = TimingRecord.importMerged(local: notFound(origin: Self.macA), remote: found())
        #expect(TimingRecord.importMerged(local: once, remote: found()) == once)
    }

    // MARK: 驗證

    @Test func aRemoteRecordFromTheFutureIsRejected() {
        let now = Self.base
        #expect(found(fetchedAt: now.addingTimeInterval(86_400 * 2)).isAcceptableRemote(now: now) == false)
        #expect(found(fetchedAt: now.addingTimeInterval(3_600)).isAcceptableRemote(now: now))
    }

    @Test func anUnstampedRemoteRecordIsRejected() {
        #expect(found(origin: nil).isAcceptableRemote(now: Self.base) == false)
    }

    // MARK: origin／sourceRef 生命週期

    @Test func stampingGivesAFreshFoundItsOwnSourceRef() {
        let fresh = TimingRecord(persistentID: Self.pid, lyricsHash: Self.lyrics, outcome: .found(source: .lrclib, lines: Self.anchors), fetchedAt: Self.base)
        let stamped = fresh.stamped(by: Self.macA)
        #expect(stamped.origin == Self.macA)
        #expect(stamped.sourceRef == "\(Self.macA):\(Self.pid)")
        #expect(stamped.stamped(by: Self.macB) == stamped, "蓋過的不改")
    }

    @Test func stampingKeepsAnAdoptedSourceRef() {
        let adopted = found(origin: Self.macB, sourceRef: "\(Self.macB):BBBB000000000002")
        #expect(adopted.stamped(by: Self.macA).sourceRef == "\(Self.macB):BBBB000000000002")
    }

    @Test func aNewExternalFoundReplacesAnAdoptedRecordWithANewSourceRef() {
        let adopted = found(Self.lyrics, Self.otherAnchors, origin: Self.macB, sourceRef: "\(Self.macB):BBBB000000000002", fetchedAt: Self.base)
        let lookedUp = TimingRecord(persistentID: Self.pid, lyricsHash: Self.lyrics, outcome: .found(source: .deezer, lines: Self.anchors),
                                    fetchedAt: Self.base.addingTimeInterval(60))
        let merged = TimingRecord.merged(existing: adopted, incoming: lookedUp).stamped(by: Self.macA)
        #expect(merged.sourceRef == "\(Self.macA):\(Self.pid)")
    }

    @Test func aLaterNotFoundKeepsTheExistingSourceRefAndMatch() {
        let match = TimingMatch(artist: "Invented Artist", title: "Invented Title", duration: 200)
        let existing = TimingRecord(persistentID: Self.pid, lyricsHash: Self.lyrics, outcome: .found(source: .lrclib, lines: Self.anchors),
                                    fetchedAt: Self.base, alignerRevision: 1, origin: Self.macB, sourceRef: "\(Self.macB):BBBB000000000002", match: match)
        let merged = TimingRecord.merged(existing: existing, incoming: notFound(origin: nil))
        #expect(merged.sourceRef == existing.sourceRef)
        #expect(merged.origin == existing.origin)
        #expect(merged.match == match)
    }

    // MARK: 存檔

    @Test func theNewOptionalFieldsRoundTripAndOldFilesStillRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("azw-timing-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TimingStore(directory: directory)
        let record = TimingRecord(persistentID: Self.pid, lyricsHash: Self.lyrics, outcome: .found(source: .lrclib, lines: Self.anchors),
                                  fetchedAt: Self.base, origin: Self.macA, sourceRef: "\(Self.macA):\(Self.pid)",
                                  match: TimingMatch(artist: "Invented Artist", title: "Invented Title", duration: 201.5))
        try await store.save(record)
        #expect(await store.load(persistentID: Self.pid) == record)
        let old = """
        {"schemaVersion":2,"persistentID":"AAAA000000000002","lyricsHash":"\(Self.lyrics.hex)","source":"lrclib","lines":[{"index":0,"start":1}],"fetchedAt":"2026-09-21T10:00:00Z","alignerRevision":2}
        """
        try Data(old.utf8).write(to: directory.appendingPathComponent("AAAA000000000002.json"))
        let loaded = await store.load(persistentID: "AAAA000000000002")
        #expect(loaded?.origin == nil)
        #expect(loaded?.match == nil)
    }

    @Test func adoptWritesOnlyWhenTheMergeChangesSomething() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("azw-timing-adopt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TimingStore(directory: directory)
        #expect(try await store.adopt(found()))
        #expect(try await store.adopt(found()) == false, "冪等")
        #expect(try await store.adopt(notFound()) == false)
        #expect(await store.allRecords().map(\.persistentID) == [Self.pid])
    }

    @Test func stampAllStampsOnlyWhatIsMissing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("azw-timing-stamp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TimingStore(directory: directory)
        try await store.save(TimingRecord(persistentID: Self.pid, lyricsHash: Self.lyrics, outcome: .notFound, fetchedAt: Self.base))
        try await store.save(found(origin: Self.macB).withPersistentID("AAAA000000000009"))
        #expect(try await store.stampAll(by: Self.macA) == 1, "已蓋章的那筆不動")
        #expect(await store.load(persistentID: Self.pid)?.origin == Self.macA)
        #expect(await store.load(persistentID: "AAAA000000000009")?.origin == Self.macB)
    }

    @Test func afterStampingNewLookupsAreStampedOnWrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("azw-timing-stamp-write-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TimingStore(directory: directory)
        try await store.stampAll(by: Self.macA)
        try await store.save(TimingRecord(persistentID: Self.pid, lyricsHash: Self.lyrics, outcome: .found(source: .lrclib, lines: Self.anchors), fetchedAt: Self.base))
        let stored = await store.load(persistentID: Self.pid)
        #expect(stored?.origin == Self.macA)
        #expect(stored?.sourceRef == "\(Self.macA):\(Self.pid)")
        #expect(try await store.stampAll(by: Self.macB) == 0, "之後不再全掃")
    }

    /// ⑨ T6：查找的寫入（save／replace）成功才通知；匯入（adopt）與蓋章不通知；寫失敗不通知
    @Test func onlyLookupWritesNotifyCloudSync() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("azw-timing-hook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TimingStore(directory: directory)
        let saves = Counter()
        await store.setOnSaved { saves.increment() }
        try await store.save(notFound(origin: nil))
        #expect(saves.value == 1)
        try await store.replace(found())
        #expect(saves.value == 2)
        _ = try await store.adopt(found(revision: LRCAligner.revision + 1))
        _ = try await store.stampAll(by: Self.macA)
        #expect(saves.value == 2)
        await #expect(throws: TimingStore.StoreError.invalidPersistentID) {
            try await store.save(TimingRecord(persistentID: "not-a-pid", lyricsHash: Self.lyrics, outcome: .notFound, fetchedAt: Self.base))
        }
        #expect(saves.value == 2)
    }

    // MARK: 安全評審 MEDIUM-3、LOW-6

    @Test func aRemoteRecordFromANewerAlignerIsRejected() {
        #expect(found(revision: LRCAligner.revision + 1).isAcceptableRemote(now: Self.base) == false)
        #expect(found(revision: Int.max).isAcceptableRemote(now: Self.base) == false)
        #expect(found(revision: 0).isAcceptableRemote(now: Self.base) == false)
    }

    @Test(arguments: ["", "x", "000000000000000b", "000000000000000b:aaaa000000000001", "000000000000000b:AAAA000000000001:x", "!:AAAA000000000001"])
    func aMalformedSourceRefIsRejected(_ sourceRef: String) {
        #expect(found(sourceRef: sourceRef).isAcceptableRemote(now: Self.base) == false)
    }

    @Test func aMalformedOriginIsRejected() {
        #expect(found(origin: "!", sourceRef: "\(Self.macB):\(Self.pid)").isAcceptableRemote(now: Self.base) == false)
    }
}
