import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.5「使用者決定」：生效／已清除兩態＋revision＋origin＋寫法；存檔 v1→v2；
// 匯入依 choice 分開驗證（R1-9、R1-10）。歌手名自編（樂團表的 Mayhem 除外，用來驗樂團表規則）
@Suite("Artist decision sync")
struct ArtistDecisionSyncTests {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)
    static let macA = "000000000000000a"
    static let macB = "000000000000000b"

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("azw-decision-sync-\(UUID().uuidString)")
    }

    @Test func clearingLeavesATombstoneInsteadOfDeletingTheKey() throws {
        let decided = try ArtistDecisionBook().deciding(.keepFallback, forArtists: ["Paper Harbour"], at: Self.base)
        let cleared = decided.clearing(forArtists: ["Paper Harbour"])
        #expect(cleared.decision(forArtist: "Paper Harbour") == nil)
        let entry = try #require(cleared.entries[ArtistDecisionBook.key("Paper Harbour")])
        #expect(entry.value == nil)
        #expect(entry.version.revision == 2)
    }

    @Test func eachChangeOfTheSameKeyRaisesItsRevision() throws {
        let first = try ArtistDecisionBook().deciding(.style(rowID: "gothic"), forArtists: ["Paper Harbour"], at: Self.base)
        let second = try first.deciding(.keepFallback, forArtists: ["paper harbour"], at: Self.base.addingTimeInterval(1))
        #expect(first.entries[ArtistDecisionBook.key("Paper Harbour")]?.version.revision == 1)
        #expect(second.entries[ArtistDecisionBook.key("Paper Harbour")]?.version.revision == 2)
        #expect(second.entries[ArtistDecisionBook.key("Paper Harbour")]?.value?.spellings == ["paper harbour"])
    }

    @Test func clearingAnUnknownArtistChangesNothing() {
        #expect(ArtistDecisionBook().clearing(forArtists: ["Paper Harbour"]) == ArtistDecisionBook())
    }

    @Test func stampingOnlyTouchesUnstampedEntries() throws {
        let book = try ArtistDecisionBook().deciding(.keepFallback, forArtists: ["Paper Harbour"], at: Self.base).stamped(by: Self.macA)
        let more = try book.deciding(.keepFallback, forArtists: ["Velvet Lanterns"], at: Self.base).stamped(by: Self.macB)
        #expect(more.entries[ArtistDecisionBook.key("Paper Harbour")]?.version.origin == Self.macA)
        #expect(more.entries[ArtistDecisionBook.key("Velvet Lanterns")]?.version.origin == Self.macB)
    }

    @Test func aRemoteTombstoneWithAHigherRevisionClearsTheLocalDecision() throws {
        let local = try ArtistDecisionBook().deciding(.keepFallback, forArtists: ["Paper Harbour"], at: Self.base).stamped(by: Self.macA)
        let remote = local.clearing(forArtists: ["Paper Harbour"]).stamped(by: Self.macB)
        let merged = local.merging(remote: remote.entries)
        #expect(merged.book.decision(forArtist: "Paper Harbour") == nil)
        #expect(merged.book.merging(remote: local.entries).book.decision(forArtist: "Paper Harbour") == nil, "舊的決定不會復活")
    }

    @Test func aRemoteDecisionWithALowerRevisionIsIgnored() throws {
        let remote = try ArtistDecisionBook().deciding(.keepFallback, forArtists: ["Paper Harbour"], at: Self.base).stamped(by: Self.macB)
        let local = try remote.deciding(.style(rowID: "gothic"), forArtists: ["Paper Harbour"], at: Self.base).stamped(by: Self.macA)
        #expect(local.merging(remote: remote.entries).book.decision(forArtist: "Paper Harbour")?.choice == .style(rowID: "gothic"))
    }

    @Test func aRemoteStyleForASignedBandIsRejectedButKeepFallbackIsNot() {
        let style = SyncRegister(value: ArtistDecisionPayload(choice: .style(rowID: "gothic"), decidedAt: Self.base, spellings: ["Mayhem"]),
                                 version: SyncVersion(revision: 1, origin: Self.macB))
        let keep = SyncRegister(value: ArtistDecisionPayload(choice: .keepFallback, decidedAt: Self.base, spellings: ["Mayhem"]),
                                version: SyncVersion(revision: 1, origin: Self.macB))
        let rejected = ArtistDecisionBook().merging(remote: [ArtistDecisionBook.key("Mayhem"): style])
        #expect(rejected.book.decision(forArtist: "Mayhem") == nil)
        #expect(rejected.rejected == 1)
        let accepted = ArtistDecisionBook().merging(remote: [ArtistDecisionBook.key("Mayhem"): keep])
        #expect(accepted.book.decision(forArtist: "Mayhem")?.choice == .keepFallback)
        #expect(accepted.rejected == 0)
    }

    @Test func aRemoteStyleWithARowThisVersionDoesNotKnowIsSkipped() throws {
        let local = try ArtistDecisionBook().deciding(.keepFallback, forArtists: ["Paper Harbour"], at: Self.base).stamped(by: Self.macA)
        let unknown = SyncRegister(value: ArtistDecisionPayload(choice: .style(rowID: "row-from-the-future"), decidedAt: Self.base, spellings: ["Paper Harbour"]),
                                   version: SyncVersion(revision: 9, origin: Self.macB))
        let merged = local.merging(remote: [ArtistDecisionBook.key("Paper Harbour"): unknown])
        #expect(merged.book == local, "這一筆本輪不採用、保留本機")
        #expect(merged.rejected == 1)
    }

    @Test func aRemoteEntryUnderTheWrongKeyIsRejected() {
        let wrong = SyncRegister(value: ArtistDecisionPayload(choice: .keepFallback, decidedAt: Self.base, spellings: ["Paper Harbour"]),
                                 version: SyncVersion(revision: 1, origin: Self.macB))
        let merged = ArtistDecisionBook().merging(remote: ["someone else": wrong])
        #expect(merged.book == ArtistDecisionBook())
        #expect(merged.rejected == 1)
    }

    @Test func threeWritersConvergeInAnyOrder() throws {
        let a = try ArtistDecisionBook().deciding(.keepFallback, forArtists: ["Paper Harbour"], at: Self.base).stamped(by: "000000000000000a")
        let b = try a.deciding(.style(rowID: "gothic"), forArtists: ["Paper Harbour"], at: Self.base).stamped(by: "000000000000000b")
        let c = try a.deciding(.style(rowID: "punk"), forArtists: ["Paper Harbour"], at: Self.base).stamped(by: "000000000000000c")
        let books = [a, b, c]
        let expected = books.dropFirst().reduce(books[0]) { $0.merging(remote: $1.entries).book }
        for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            let merged = order.dropFirst().reduce(books[order[0]]) { $0.merging(remote: books[$1].entries).book }
            #expect(merged == expected)
        }
        #expect(expected.decision(forArtist: "Paper Harbour")?.choice == .style(rowID: "gothic"), "同 revision 取 origin 小者（b）")
    }

    // MARK: 存檔

    @Test func theStoreWritesVersionTwoAndKeepsTombstones() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ArtistDecisionStore(directory: directory)
        let book = try ArtistDecisionBook().deciding(.keepFallback, forArtists: ["Paper Harbour"], at: Self.base)
            .clearing(forArtists: ["Paper Harbour"]).stamped(by: Self.macA)
        try store.save(book)
        #expect(store.load().book == book)
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(ArtistDecisionStore.fileName))) as? [String: Any]
        #expect(raw?["schemaVersion"] as? Int == 2)
    }

    @Test func aVersionOneFileIsReadAsRevisionZero() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = ArtistDecisionBook.key("Paper Harbour")
        let v1 = """
        {"schemaVersion":1,"decisions":{"\(key)":{"choice":{"keepFallback":{}},"decidedAt":"2026-09-21T10:00:00Z"}}}
        """
        try Data(v1.utf8).write(to: directory.appendingPathComponent(ArtistDecisionStore.fileName))
        let loaded = ArtistDecisionStore(directory: directory).load()
        #expect(loaded.isWritable)
        #expect(loaded.book.decision(forArtist: "Paper Harbour")?.choice == .keepFallback)
        let entry = try #require(loaded.book.entries[key])
        #expect(entry.version == SyncVersion(revision: 0, origin: ""))
        #expect(entry.value?.spellings == [key])
    }

    // MARK: 安全評審 HIGH-1、LOW-6

    @Test func aRemoteDecisionWithAHugeRevisionIsRejected() {
        let huge = SyncRegister(value: ArtistDecisionPayload(choice: .keepFallback, decidedAt: Self.base, spellings: ["Paper Harbour"]),
                                version: SyncVersion(revision: Int.max, origin: Self.macB))
        let merged = ArtistDecisionBook().merging(remote: [ArtistDecisionBook.key("Paper Harbour"): huge])
        #expect(merged.book == ArtistDecisionBook())
        #expect(merged.rejected == 1)
    }

    @Test func aRemoteTombstoneUnderAnOversizedKeyIsRejected() {
        let tombstone = SyncRegister<ArtistDecisionPayload>(value: nil, version: SyncVersion(revision: 1, origin: Self.macB))
        let key = String(repeating: "a", count: TrackMatcher.maxNameLength + 1)
        #expect(ArtistDecisionBook().merging(remote: [key: tombstone]).rejected == 1)
    }

    @Test func aRemoteDecisionWithAMalformedOriginIsRejected() {
        let entry = SyncRegister(value: ArtistDecisionPayload(choice: .keepFallback, decidedAt: Self.base, spellings: ["Paper Harbour"]),
                                 version: SyncVersion(revision: 1, origin: "!"))
        #expect(ArtistDecisionBook().merging(remote: [ArtistDecisionBook.key("Paper Harbour"): entry]).rejected == 1)
    }

    /// 安全複查 N9：本機載入不驗選擇——日後拿掉的列，使用者的舊決定不在載入時被丟掉
    @Test func aLocalDecisionForARowThatNoLongerExistsSurvivesLoading() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = ArtistDecisionBook.key("Paper Harbour")
        let v2 = """
        {"schemaVersion":2,"entries":{"\(key)":{"value":{"choice":{"style":{"rowID":"row-removed-later"}},"decidedAt":"2026-09-21T10:00:00Z","spellings":["Paper Harbour"]},"version":{"revision":3,"origin":"000000000000000a"}}}}
        """
        try Data(v2.utf8).write(to: directory.appendingPathComponent(ArtistDecisionStore.fileName))
        #expect(ArtistDecisionStore(directory: directory).load().book.decision(forArtist: "Paper Harbour")?.choice == .style(rowID: "row-removed-later"))
    }

    @Test func aStoredHugeRevisionIsDroppedOnLoadSoChangingItCannotCrash() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = ArtistDecisionBook.key("Paper Harbour")
        let v2 = """
        {"schemaVersion":2,"entries":{"\(key)":{"value":{"choice":{"keepFallback":{}},"decidedAt":"2026-09-21T10:00:00Z","spellings":["Paper Harbour"]},"version":{"revision":9223372036854775807,"origin":"000000000000000b"}}}}
        """
        try Data(v2.utf8).write(to: directory.appendingPathComponent(ArtistDecisionStore.fileName))
        let book = ArtistDecisionStore(directory: directory).load().book
        #expect(book.entries.isEmpty)
        _ = try book.deciding(.keepFallback, forArtists: ["Paper Harbour"], at: Self.base)
    }
}
