import Foundation
import Testing

@testable import AzathothsWhisper

// 時間軸存放（母計劃 C.1／C.4；A1 計劃 §3.6）。一律寫在臨時目錄，不碰使用者的 Application Support
@Suite("TimingStore")
struct TimingStoreTests {
    static let id = "0123456789ABCDEF"
    static let hash = LyricsFingerprint.of("Lanterns over the river")
    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("azw-timings-\(UUID().uuidString)")
    }

    static func found(_ source: StoredTimingSource = .lrclib, at date: Date = base, hash: LyricsFingerprint = hash) -> TimingRecord {
        TimingRecord(persistentID: id, lyricsHash: hash, outcome: .found(source: source, lines: [.init(index: 0, start: 1.5), .init(index: 1, start: 4)]), fetchedAt: date)
    }

    static func notFound(at date: Date = base, hash: LyricsFingerprint = hash) -> TimingRecord {
        TimingRecord(persistentID: id, lyricsHash: hash, outcome: .notFound, fetchedAt: date)
    }

    @Test func savesAndLoadsARecord() async throws {
        let store = TimingStore(directory: tempDirectory())
        try await store.save(Self.found())
        #expect(await store.load(persistentID: Self.id) == Self.found())
    }

    /// C 段 §3.4：加了網易雲 → 格式升到 v2（舊版 app 讀到 v2 會判認不出來、不覆寫）；v1 檔照讀
    @Test func neteaseRoundTripsAndIsWrittenAsVersionTwo() async throws {
        let directory = tempDirectory()
        let store = TimingStore(directory: directory)
        try await store.save(Self.found(.netease))
        #expect(await store.load(persistentID: Self.id) == Self.found(.netease))
        let json = try String(contentsOf: directory.appendingPathComponent("\(Self.id).json"), encoding: .utf8)
        #expect(json.contains(#""schemaVersion" : 2"#))
    }

    @Test func aVersionOneFileIsStillRead() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"{"schemaVersion":1,"persistentID":"0123456789ABCDEF","lyricsHash":"\#(Self.hash.hex)","source":"qq","lines":[{"index":0,"start":1.5}],"fetchedAt":"2026-09-21T00:00:00Z"}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("\(Self.id).json"))
        let record = await TimingStore(directory: directory).load(persistentID: Self.id)
        #expect(record?.outcome == .found(source: .qq, lines: [.init(index: 0, start: 1.5)]))
    }

    /// 對齊演算法版本（docs/plans/2026-10-19-lyrics-fx-merged-line-align.md）：沒有這個欄位的舊檔＝版本 1
    @Test func aFileWithoutAlignerRevisionReadsAsRevisionOne() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"{"schemaVersion":2,"persistentID":"0123456789ABCDEF","lyricsHash":"\#(Self.hash.hex)","source":"lrclib","lines":[{"index":0,"start":1.5}],"fetchedAt":"2026-10-19T00:00:00Z"}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("\(Self.id).json"))
        let record = await TimingStore(directory: directory).load(persistentID: Self.id)
        #expect(record?.alignerRevision == 1)
    }

    @Test func savedRecordsCarryTheCurrentAlignerRevision() async throws {
        let directory = tempDirectory()
        let store = TimingStore(directory: directory)
        try await store.save(Self.found())
        #expect(await store.load(persistentID: Self.id)?.alignerRevision == LRCAligner.revision)
        let text = try String(contentsOf: directory.appendingPathComponent("\(Self.id).json"), encoding: .utf8)
        #expect(text.contains("\"alignerRevision\" : \(LRCAligner.revision)"))
    }

    @Test func missingFileIsNil() async {
        #expect(await TimingStore(directory: tempDirectory()).load(persistentID: Self.id) == nil)
    }

    @Test func fileIsNamedByTheUppercasedPersistentIDAndUsesISO8601() async throws {
        let directory = tempDirectory()
        let store = TimingStore(directory: directory)
        let lower = TimingRecord(persistentID: Self.id.lowercased(), lyricsHash: Self.hash, outcome: .notFound, fetchedAt: Self.base)
        try await store.save(lower)
        let file = directory.appendingPathComponent("\(Self.id).json")
        let json = try String(contentsOf: file, encoding: .utf8)
        #expect(json.contains("\"fetchedAt\" : \"2026-"))
        #expect(json.contains("\"schemaVersion\" : 2"))   // C 段 §3.4 升版
        #expect(await store.load(persistentID: Self.id.lowercased())?.persistentID == Self.id)
    }

    @Test(arguments: ["../../etc/passwd", "0123", "0123456789ABCDEFG", "", "0123456789ABCDEZ"])
    func invalidPersistentIDsAreRejected(id: String) async {
        let directory = tempDirectory()
        let store = TimingStore(directory: directory)
        let record = TimingRecord(persistentID: id, lyricsHash: Self.hash, outcome: .notFound, fetchedAt: Self.base)
        await #expect(throws: TimingStore.StoreError.invalidPersistentID) { try await store.save(record) }
        #expect(await store.load(persistentID: id) == nil)
    }

    @Test(arguments: [
        "not json",
        // 比現行（v2，C 段 §3.4）還新的版本
        #"{"schemaVersion":3,"persistentID":"0123456789ABCDEF","lyricsHash":"00000000000000000000000000000000","source":null,"lines":[],"fetchedAt":"2026-09-21T00:00:00Z"}"#,
        #"{"schemaVersion":1,"persistentID":"0123456789ABCDEF","lyricsHash":"00000000000000000000000000000000","source":"lrclib","lines":[],"fetchedAt":"2026-09-21T00:00:00Z"}"#,
        #"{"schemaVersion":1,"persistentID":"0123456789ABCDEF","lyricsHash":"00000000000000000000000000000000","source":null,"lines":[{"index":0,"start":1}],"fetchedAt":"2026-09-21T00:00:00Z"}"#,
        #"{"schemaVersion":1,"persistentID":"0123456789ABCDEF","lyricsHash":"00000000000000000000000000000000","source":"lrclib","lines":[{"index":1,"start":1},{"index":1,"start":2}],"fetchedAt":"2026-09-21T00:00:00Z"}"#,
        #"{"schemaVersion":1,"persistentID":"0123456789ABCDEF","lyricsHash":"00000000000000000000000000000000","source":"lrclib","lines":[{"index":0,"start":-1}],"fetchedAt":"2026-09-21T00:00:00Z"}"#,
        // 時間倒退（C 段：與對齊重建共用同一個錨點合法性定義）
        #"{"schemaVersion":2,"persistentID":"0123456789ABCDEF","lyricsHash":"00000000000000000000000000000000","source":"lrclib","lines":[{"index":0,"start":9},{"index":1,"start":3}],"fetchedAt":"2026-09-21T00:00:00Z"}"#,
        #"{"schemaVersion":1,"persistentID":"FFFFFFFFFFFFFFFF","lyricsHash":"00000000000000000000000000000000","source":null,"lines":[],"fetchedAt":"2026-09-21T00:00:00Z"}"#,
        #"{"schemaVersion":1,"persistentID":"0123456789ABCDEF","lyricsHash":"00000000000000000000000000000000","source":"estimated","lines":[{"index":0,"start":1}],"fetchedAt":"2026-09-21T00:00:00Z"}"#,
    ])
    func unreadableOrInvalidFilesLoadAsNil(contents: String) async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: directory.appendingPathComponent("\(Self.id).json"))
        #expect(await TimingStore(directory: directory).load(persistentID: Self.id) == nil)
    }

    /// 全形 hex 也會被 `isHexDigit` 放行：只認 ASCII（安全評審 LOW）
    @Test func fullWidthHexIsRejected() async {
        let store = TimingStore(directory: tempDirectory())
        let record = TimingRecord(persistentID: "０１２３４５６７８９ＡＢＣＤＥＦ", lyricsHash: Self.hash, outcome: .notFound, fetchedAt: Self.base)
        await #expect(throws: TimingStore.StoreError.invalidPersistentID) { try await store.save(record) }
    }

    /// 同步資料夾裡的超大檔不整檔讀進記憶體（安全評審 MEDIUM）
    @Test func oversizedFilesLoadAsNil() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: TimingStore.maxFileBytes + 1).write(to: directory.appendingPathComponent("\(Self.id).json"))
        #expect(await TimingStore(directory: directory).load(persistentID: Self.id) == nil)
    }

    /// 符號連結（可能指向 FIFO、裝置或別的檔）一律不跟（安全評審 MEDIUM）
    @Test func symbolicLinksAreNotFollowed() async throws {
        let directory = tempDirectory()
        let store = TimingStore(directory: directory)
        try await store.save(Self.found())
        let real = directory.appendingPathComponent("\(Self.id).json")
        let other = "FEDCBA9876543210"
        let otherRecord = TimingRecord(persistentID: other, lyricsHash: Self.hash, outcome: .notFound, fetchedAt: Self.base)
        try await store.save(otherRecord)
        let link = directory.appendingPathComponent("\(other).json")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(await store.load(persistentID: other) == nil)
    }

    @Test func tooManyLinesLoadAsNil() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lines = (0...TimingStore.maxLines).map { #"{"index":\#($0),"start":\#($0)}"# }.joined(separator: ",")
        let json = #"{"schemaVersion":1,"persistentID":"0123456789ABCDEF","lyricsHash":"00000000000000000000000000000000","source":"lrclib","lines":[\#(lines)],"fetchedAt":"2026-09-21T00:00:00Z"}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("\(Self.id).json"))
        #expect(await TimingStore(directory: directory).load(persistentID: Self.id) == nil)
    }

    /// 認不出來的檔（較新版本、沒有版本欄位、超大、符號連結）：讀不懂＝未知，不得蓋掉（安全評審 LOW；simplify R2 altitude）
    @Test(arguments: [
        #"{"schemaVersion":3,"persistentID":"0123456789ABCDEF","whatever":true}"#,
        #"{"version":7,"lines":[]}"#,
    ])
    func anUnrecognizedFileOnDiskIsNotOverwritten(contents: String) async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(Self.id).json")
        try Data(contents.utf8).write(to: file)
        let store = TimingStore(directory: directory)
        await #expect(throws: TimingStore.StoreError.unrecognizedFileOnDisk) { try await store.save(Self.found()) }
        #expect(try String(contentsOf: file, encoding: .utf8) == contents)
    }

    @Test func anOversizedFileOnDiskIsNotOverwritten() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(Self.id).json")
        try Data(repeating: 0x20, count: TimingStore.maxFileBytes + 1).write(to: file)
        await #expect(throws: TimingStore.StoreError.unrecognizedFileOnDisk) { try await TimingStore(directory: directory).save(Self.found()) }
        #expect(try Data(contentsOf: file).count == TimingStore.maxFileBytes + 1)
    }

    @Test func aSymbolicLinkOnDiskIsNotOverwritten() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("elsewhere.txt")
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("\(Self.id).json"), withDestinationURL: target)
        await #expect(throws: TimingStore.StoreError.unrecognizedFileOnDisk) { try await TimingStore(directory: directory).save(Self.found()) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "keep")
    }

    /// 同版本但壞掉的檔可以被新結果取代（不然一個壞檔會讓這首永遠存不進去）
    @Test func aCorruptFileOfTheSameSchemaIsReplaced() async throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("\(Self.id).json"))
        let store = TimingStore(directory: directory)
        try await store.save(Self.found())
        #expect(await store.load(persistentID: Self.id) == Self.found())
    }

    @Test func savingMergesWithWhatIsAlreadyOnDisk() async throws {
        let store = TimingStore(directory: tempDirectory())
        try await store.save(Self.found(at: Self.base))
        try await store.save(Self.notFound(at: Self.base.addingTimeInterval(60)))
        #expect(await store.load(persistentID: Self.id) == Self.found(at: Self.base))
    }
}

@Suite("TimingRecord.merged")
struct TimingRecordMergeTests {
    typealias T = TimingStoreTests

    @Test func newLyricsWinRegardlessOfOutcome() {
        let newHash = LyricsFingerprint.of("Ash in the wind")
        let incoming = T.notFound(at: T.base, hash: newHash)
        #expect(TimingRecord.merged(existing: T.found(at: T.base.addingTimeInterval(99)), incoming: incoming) == incoming)
    }

    @Test func foundBeatsNotFoundForTheSameLyrics() {
        let found = T.found(at: T.base)
        #expect(TimingRecord.merged(existing: found, incoming: T.notFound(at: T.base.addingTimeInterval(60))) == found)
        let later = T.found(at: T.base.addingTimeInterval(60))
        #expect(TimingRecord.merged(existing: T.notFound(at: T.base), incoming: later) == later)
    }

    @Test func newerFetchWinsBetweenLikeOutcomes() {
        let older = T.found(.lrclib, at: T.base)
        let newer = T.found(.youtubeMusic, at: T.base.addingTimeInterval(60))
        #expect(TimingRecord.merged(existing: older, incoming: newer) == newer)
        #expect(TimingRecord.merged(existing: newer, incoming: older) == newer)
        #expect(TimingRecord.merged(existing: T.notFound(at: T.base), incoming: T.notFound(at: T.base.addingTimeInterval(1))) == T.notFound(at: T.base.addingTimeInterval(1)))
    }

    @Test func nothingOnDiskTakesTheIncoming() {
        #expect(TimingRecord.merged(existing: nil, incoming: T.notFound()) == T.notFound())
    }
}

@Suite("TimingLookupPolicy")
struct TimingLookupPolicyTests {
    typealias T = TimingStoreTests
    static let day: TimeInterval = 86_400

    @Test func noRecordMeansLookUp() {
        #expect(TimingLookupPolicy.shouldLookup(record: nil, currentHash: T.hash, now: T.base))
    }

    @Test func changedLyricsMeansLookUpAtOnce() {
        #expect(TimingLookupPolicy.shouldLookup(record: T.found(), currentHash: LyricsFingerprint.of("other"), now: T.base))
    }

    @Test func foundIsNeverLookedUpAgain() {
        #expect(!TimingLookupPolicy.shouldLookup(record: T.found(), currentHash: T.hash, now: T.base.addingTimeInterval(365 * Self.day)))
    }

    /// 舊演算法對出來的 found 要重查一次，否則修好的對齊永遠到不了已存過的歌
    @Test func foundFromAnOlderAlignerIsLookedUpAgain() {
        let found = T.found()
        let old = TimingRecord(persistentID: found.persistentID, lyricsHash: found.lyricsHash, outcome: found.outcome, fetchedAt: found.fetchedAt, alignerRevision: LRCAligner.revision - 1)
        #expect(TimingLookupPolicy.shouldLookup(record: old, currentHash: T.hash, now: T.base))
    }

    /// notFound 與演算法版本無關（沒有任何來源給時間），照 7 天規則
    @Test func notFoundFromAnOlderAlignerKeepsTheSevenDayRule() {
        let old = TimingRecord(persistentID: T.id, lyricsHash: T.hash, outcome: .notFound, fetchedAt: T.base, alignerRevision: LRCAligner.revision - 1)
        #expect(!TimingLookupPolicy.shouldLookup(record: old, currentHash: T.hash, now: T.base))
    }

    @Test func notFoundIsRetriedAfterSevenDays() {
        let record = T.notFound(at: T.base)
        #expect(!TimingLookupPolicy.shouldLookup(record: record, currentHash: T.hash, now: T.base.addingTimeInterval(7 * Self.day - 1)))
        #expect(TimingLookupPolicy.shouldLookup(record: record, currentHash: T.hash, now: T.base.addingTimeInterval(7 * Self.day)))
    }

    /// 他機時鐘錯亂寫下未來時間：超過一天就當作該重找，免得永遠不到期
    @Test func aFetchDateFarInTheFutureIsDue() {
        let record = T.notFound(at: T.base.addingTimeInterval(2 * Self.day))
        #expect(TimingLookupPolicy.shouldLookup(record: record, currentHash: T.hash, now: T.base))
        let nearFuture = T.notFound(at: T.base.addingTimeInterval(3600))
        #expect(!TimingLookupPolicy.shouldLookup(record: nearFuture, currentHash: T.hash, now: T.base))
    }
}
