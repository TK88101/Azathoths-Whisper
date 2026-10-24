import Foundation
import Testing

@testable import AzathothsWhisper

// ⑥b 計劃 §4.4（R1-9、R1-15、R2-3）：歌手曲風存檔。一律寫在臨時目錄；歌手名自編
@Suite("Artist style store")
struct ArtistStyleStoreTests {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("azw-artiststyles-\(UUID().uuidString)")
    }

    private func verified(_ genres: [(String, Int)] = [("black metal", 3)]) -> ArtistStyleBook.Lookup {
        .verified(id: "mb-1", matchedReleaseGroups: ["rg-1"], genres: genres.map { ArtistStyleBook.Genre(name: $0.0, count: $0.1) })
    }

    @Test func aRecordSurvivesARoundTrip() throws {
        let store = ArtistStyleStore(directory: tempDirectory())
        let book = ArtistStyleBook().recording(verified(), forSpelling: "Velvet Lanterns", at: Self.base)
        try store.save(book)
        let loaded = store.load()
        #expect(loaded.book == book)
        #expect(loaded.isWritable)
        #expect(loaded.book.genres(forArtist: "Velvet Lanterns") == .verified(["black metal"]))
    }

    @Test func aMissingFileLoadsAsAnEmptyWritableBook() {
        let loaded = ArtistStyleStore(directory: tempDirectory()).load()
        #expect(loaded.book == ArtistStyleBook() && loaded.isWritable)
    }

    @Test func theFileCarriesSchemaVersionAndSummaryCounts() throws {
        let directory = tempDirectory()
        let book = ArtistStyleBook()
            .recording(verified(), forSpelling: "Velvet Lanterns", at: Self.base)
            .recording(.unresolved(.notFound), forSpelling: "Paper Harbour", at: Self.base)
            .recordingNetworkFailure("timedOut", at: Self.base)
        try ArtistStyleStore(directory: directory).save(book)
        let data = try Data(contentsOf: directory.appendingPathComponent("artists.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == ArtistStyleStore.schemaVersion)
        let summary = try #require(json["summary"] as? [String: Any])
        #expect(summary["verified"] as? Int == 1 && summary["unresolved"] as? Int == 1)
        #expect(summary["lastNetworkError"] as? String == "timedOut")
    }

    @Test(arguments: ["not json", "{\"schemaVersion\": 1, \"artists\": 5}", "[]"])
    func aCorruptFileOfTheCurrentSchemaLoadsEmptyAndMayBeReplaced(contents: String) throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(to: directory.appendingPathComponent("artists.json"), atomically: true, encoding: .utf8)
        let loaded = ArtistStyleStore(directory: directory).load()
        #expect(loaded.book == ArtistStyleBook())
        #expect(loaded.isWritable)
    }

    @Test func aNewerSchemaIsNeitherReadNorOverwritten() throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("artists.json")
        let newer = "{\"schemaVersion\": \(ArtistStyleStore.schemaVersion + 1), \"artists\": {}}"
        try newer.write(to: url, atomically: true, encoding: .utf8)
        let store = ArtistStyleStore(directory: directory)
        #expect(store.load().isWritable == false)
        #expect(throws: ArtistStyleStore.StoreError.unrecognizedFileOnDisk) { try store.save(ArtistStyleBook()) }
        #expect(try String(contentsOf: url, encoding: .utf8) == newer)
    }

    @Test func anOversizedFileIsNotReadOrOverwritten() throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("artists.json")
        try Data(count: ArtistStyleStore.maxFileBytes + 1).write(to: url)
        let store = ArtistStyleStore(directory: directory)
        #expect(store.load().isWritable == false)
        #expect(throws: ArtistStyleStore.StoreError.unrecognizedFileOnDisk) { try store.save(ArtistStyleBook()) }
    }

    @Test func aSymbolicLinkIsNotFollowedOrOverwritten() throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("elsewhere.json")
        try "{}".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("artists.json"), withDestinationURL: target)
        let store = ArtistStyleStore(directory: directory)
        #expect(store.load().isWritable == false)
        #expect(throws: ArtistStyleStore.StoreError.unrecognizedFileOnDisk) { try store.save(ArtistStyleBook()) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "{}")
    }

    // MARK: 查表（R1-7：票數高到低、同票依名稱，取前 3）

    @Test func genresAreTheTopThreeByVotesThenName() {
        let book = ArtistStyleBook().recording(
            verified([("doom metal", 1), ("gothic metal", 4), ("black metal", 4), ("death metal", 2), ("folk", 1)]),
            forSpelling: "Velvet Lanterns", at: Self.base
        )
        #expect(book.genres(forArtist: "Velvet Lanterns") == .verified(["black metal", "gothic metal", "death metal"]))
    }

    @Test func anUnknownArtistIsUnknownAndAnUnresolvedOneIsUnresolved() {
        let book = ArtistStyleBook().recording(.unresolved(.ambiguous), forSpelling: "Paper Harbour", at: Self.base)
        #expect(book.genres(forArtist: "Velvet Lanterns") == .unknown)
        #expect(book.genres(forArtist: "Paper Harbour") == .unresolved)
        #expect(book.hasRecord(forArtist: "Paper Harbour") && !book.hasRecord(forArtist: "Velvet Lanterns"))
    }

    // MARK: 撞鍵（R2-3）

    @Test func aCaseVariantSharesTheRecord() {
        let book = ArtistStyleBook().recording(verified(), forSpelling: "Velvet Lanterns", at: Self.base).noting(spellings: ["VELVET LANTERNS"])
        #expect(book.genres(forArtist: "VELVET LANTERNS") == .verified(["black metal"]))
        #expect(book.genres(forArtist: "Velvet Lanterns") == .verified(["black metal"]))
    }

    @Test func aDifferentSpellingOnTheSameKeyIsACollisionForBoth() {
        let book = ArtistStyleBook().recording(verified(), forSpelling: "AC/DX", at: Self.base).noting(spellings: ["ACDX"])
        #expect(book.genres(forArtist: "ACDX") == .unresolved)
        #expect(book.genres(forArtist: "AC/DX") == .unresolved)
        #expect(book.record(forArtist: "AC/DX")?.mbid == "mb-1", "撞鍵不覆寫 mbid")
        #expect(book.record(forArtist: "AC/DX")?.reason == .collision)
    }

    @Test func aCollisionSurvivesARestart() throws {
        let store = ArtistStyleStore(directory: tempDirectory())
        try store.save(ArtistStyleBook().recording(verified(), forSpelling: "AC/DX", at: Self.base).noting(spellings: ["ACDX"]))
        let reloaded = store.load().book.noting(spellings: ["AC/DX"])
        #expect(reloaded.genres(forArtist: "AC/DX") == .unresolved)
    }

    @Test func notingASpellingWithoutARecordAddsNothing() {
        #expect(ArtistStyleBook().noting(spellings: ["Velvet Lanterns"]) == ArtistStyleBook())
    }
}
