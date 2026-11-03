import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.5「MB 歌手」：寫法聯集後照現有撞鍵規則重判、collision 保留；不撞鍵時 verified 勝 unresolved、
// 同狀態取 origin 小者；§6.3 依狀態分開逐筆驗證（R2-B2、R2-B5）。歌手名與 mbid 自編
@Suite("Artist style merge")
struct ArtistStyleMergeTests {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)
    static let macA = "000000000000000a"
    static let macB = "000000000000000b"
    static let mbid1 = "11111111-1111-4111-8111-111111111111"
    static let mbid2 = "22222222-2222-4222-8222-222222222222"

    private func verified(_ spellings: [String], mbid: String = mbid1, genre: String = "gothic metal", origin: String? = macB) -> ArtistStyleBook.Record {
        ArtistStyleBook.Record(spellings: spellings, mbid: mbid, matchedReleaseGroups: [], genres: [.init(name: genre, count: 3)],
                               reason: nil, fetchedAt: Self.base, origin: origin)
    }

    private func unresolved(_ spellings: [String], _ reason: ArtistIdentity.UnresolvedReason = .notFound, origin: String? = macB) -> ArtistStyleBook.Record {
        ArtistStyleBook.Record(spellings: spellings, mbid: nil, matchedReleaseGroups: [], genres: [], reason: reason, fetchedAt: Self.base, origin: origin)
    }

    private func key(_ artist: String) -> String { ArtistStyleBook.key(artist) }

    @Test func aRemoteRecordForAnArtistThisMacHasNotQueriedIsAdopted() {
        let merged = ArtistStyleBook().merging(remote: [key("Paper Harbour"): verified(["Paper Harbour"])])
        #expect(merged.book.genres(forArtist: "Paper Harbour") == .verified(["gothic metal"]))
        #expect(merged.rejected == 0)
    }

    @Test func verifiedBeatsUnresolvedEitherWay() {
        let local = ArtistStyleBook(records: [key("Paper Harbour"): unresolved(["Paper Harbour"], origin: Self.macA)])
        let merged = local.merging(remote: [key("Paper Harbour"): verified(["Paper Harbour"])]).book
        #expect(merged.genres(forArtist: "Paper Harbour") == .verified(["gothic metal"]))
        let back = ArtistStyleBook(records: merged.records).merging(remote: local.records).book
        #expect(back == merged)
    }

    @Test func onTheSameStatusTheSmallerOriginWins() {
        let local = ArtistStyleBook(records: [key("Paper Harbour"): verified(["Paper Harbour"], mbid: Self.mbid2, genre: "doom metal", origin: Self.macB)])
        let remote = [key("Paper Harbour"): verified(["Paper Harbour"], origin: Self.macA)]
        #expect(local.merging(remote: remote).book.genres(forArtist: "Paper Harbour") == .verified(["gothic metal"]))
    }

    @Test func aRemoteVerifiedRecordCannotOverrideALocalCollision() {
        let local = ArtistStyleBook(records: [key("AC/DX"): unresolved(["AC/DX", "ACDX"], .collision, origin: Self.macA)])
        let merged = local.merging(remote: [key("AC/DX"): verified(["AC/DX"])]).book
        #expect(merged.records[key("AC/DX")]?.reason == .collision)
        #expect(merged.genres(forArtist: "AC/DX") == .unresolved)
    }

    @Test func spellingsFromTwoMacsThatDifferInPunctuationBecomeACollision() {
        let local = ArtistStyleBook(records: [key("AC/DX"): verified(["AC/DX"], origin: Self.macA)])
        let merged = local.merging(remote: [key("ACDX"): verified(["ACDX"], mbid: Self.mbid2)]).book
        let record = merged.records[key("AC/DX")]
        #expect(record?.reason == .collision)
        #expect(record?.spellings == ["AC/DX", "ACDX"])
    }

    @Test func sameFamilySpellingsAreUnitedWithoutACollision() {
        let local = ArtistStyleBook(records: [key("Paper Harbour"): verified(["Paper Harbour"], origin: Self.macA)])
        let merged = local.merging(remote: [key("Paper Harbour"): verified(["PAPER HARBOUR"])]).book
        #expect(merged.records[key("Paper Harbour")]?.reason == nil)
        #expect(merged.records[key("Paper Harbour")]?.spellings == ["PAPER HARBOUR", "Paper Harbour"])
    }

    @Test func threeMacsConvergeInAnyOrder() {
        let books = [
            [key("Paper Harbour"): unresolved(["Paper Harbour"], origin: "000000000000000a")],
            [key("Paper Harbour"): verified(["PAPER HARBOUR"], mbid: Self.mbid2, origin: "000000000000000c")],
            [key("Paper Harbour"): verified(["Paper Harbour"], origin: "000000000000000b")],
        ]
        let expected = books.dropFirst().reduce(ArtistStyleBook(records: books[0])) { $0.merging(remote: $1).book }
        for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            let merged = order.dropFirst().reduce(ArtistStyleBook(records: books[order[0]])) { $0.merging(remote: books[$1]).book }
            #expect(merged.records == expected.records)
        }
        #expect(expected.records[key("Paper Harbour")]?.mbid == Self.mbid1, "verified 中 origin 小者（b）")
    }

    // MARK: 逐筆驗證

    @Test(arguments: [
        ("verified without a UUID", ArtistStyleBook.Record(spellings: ["Paper Harbour"], mbid: "not-a-uuid", matchedReleaseGroups: [], genres: [], reason: nil, fetchedAt: base, origin: macB)),
        ("unresolved with an mbid", ArtistStyleBook.Record(spellings: ["Paper Harbour"], mbid: mbid1, matchedReleaseGroups: [], genres: [], reason: .notFound, fetchedAt: base, origin: macB)),
        ("negative votes", ArtistStyleBook.Record(spellings: ["Paper Harbour"], mbid: mbid1, matchedReleaseGroups: [], genres: [.init(name: "doom", count: -1)], reason: nil, fetchedAt: base, origin: macB)),
        ("empty genre name", ArtistStyleBook.Record(spellings: ["Paper Harbour"], mbid: mbid1, matchedReleaseGroups: [], genres: [.init(name: "", count: 1)], reason: nil, fetchedAt: base, origin: macB)),
        ("duplicate genre", ArtistStyleBook.Record(spellings: ["Paper Harbour"], mbid: mbid1, matchedReleaseGroups: [], genres: [.init(name: "doom", count: 1), .init(name: "doom", count: 2)], reason: nil, fetchedAt: base, origin: macB)),
        ("no spellings", ArtistStyleBook.Record(spellings: [], mbid: mbid1, matchedReleaseGroups: [], genres: [], reason: nil, fetchedAt: base, origin: macB)),
        ("spelling under another key", ArtistStyleBook.Record(spellings: ["Velvet Lanterns"], mbid: mbid1, matchedReleaseGroups: [], genres: [], reason: nil, fetchedAt: base, origin: macB)),
        ("unstamped", ArtistStyleBook.Record(spellings: ["Paper Harbour"], mbid: mbid1, matchedReleaseGroups: [], genres: [], reason: nil, fetchedAt: base, origin: nil)),
    ])
    func anInvalidRemoteRecordIsDropped(_ label: String, _ record: ArtistStyleBook.Record) {
        let merged = ArtistStyleBook().merging(remote: [ArtistStyleBook.key("Paper Harbour"): record])
        #expect(merged.book.records.isEmpty, "\(label)")
        #expect(merged.rejected == 1)
    }

    @Test func aCollisionRecordMayKeepItsMbid() {
        let record = ArtistStyleBook.Record(spellings: ["AC/DX", "ACDX"], mbid: Self.mbid1, matchedReleaseGroups: [], genres: [.init(name: "rock", count: 1)],
                                            reason: .collision, fetchedAt: Self.base, origin: Self.macB)
        #expect(ArtistStyleBook().merging(remote: [key("AC/DX"): record]).rejected == 0, "照現有 adding 語義：撞鍵不覆寫 mbid")
    }

    @Test func stampingFillsOnlyMissingOrigins() {
        let book = ArtistStyleBook(records: [key("Paper Harbour"): verified(["Paper Harbour"], origin: nil), key("Velvet Lanterns"): verified(["Velvet Lanterns"], origin: Self.macB)])
        let stamped = book.stamped(by: Self.macA)
        #expect(stamped.records[key("Paper Harbour")]?.origin == Self.macA)
        #expect(stamped.records[key("Velvet Lanterns")]?.origin == Self.macB)
        #expect(stamped.unstampedCount == 0)
        #expect(book.unstampedCount == 1)
    }

    @Test func theLocalFileIsSanitizedOnLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("azw-mb-sanitize-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ArtistStyleStore(directory: directory)
        let good = verified(["Paper Harbour"], origin: nil)
        let bad = ArtistStyleBook.Record(spellings: ["Velvet Lanterns"], mbid: "nope", matchedReleaseGroups: [], genres: [], reason: nil, fetchedAt: Self.base, origin: nil)
        try store.save(ArtistStyleBook(records: [key("Paper Harbour"): good, key("Velvet Lanterns"): bad]))
        #expect(store.load().book.records.keys.sorted() == [key("Paper Harbour")], "R1-13：本機載入也走同一個驗證器")
    }
}
