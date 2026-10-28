import Foundation
import Testing

@testable import AzathothsWhisper

// ⑧ 曲庫閘門計劃 §4.3：使用者決定。鍵＝寫法家族（大小寫／全半形合併、保留標點）；一律寫在臨時目錄；歌手名自編
@Suite("Artist decision store")
struct ArtistDecisionStoreTests {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("azw-decisions-\(UUID().uuidString)")
    }

    // MARK: 決定簿

    @Test func aStyleDecisionIsFoundByEverySpellingOfTheSameFamily() throws {
        let book = try ArtistDecisionBook().deciding(.style(rowID: "gothic"), forArtists: ["Paper Harbour"], at: Self.base)
        #expect(book.decision(forArtist: "PAPER HARBOUR")?.choice == .style(rowID: "gothic"))
        #expect(book.decision(forArtist: "Ｐａｐｅｒ Harbour")?.choice == .style(rowID: "gothic"))
        #expect(book.decision(forArtist: "Paper Harbour")?.decidedAt == Self.base)
    }

    @Test func spellingsThatOnlyShareANormalizedNameStayApart() throws {
        let book = try ArtistDecisionBook().deciding(.keepFallback, forArtists: ["AC/DX"], at: Self.base)
        #expect(SongProfileResolver.normalizedArtist("AC/DX") == SongProfileResolver.normalizedArtist("ACDX"))
        #expect(book.decision(forArtist: "AC/DX")?.choice == .keepFallback)
        #expect(book.decision(forArtist: "ACDX") == nil, "不同寫法家族不自動合併（R4 A-1）")
    }

    @Test func applyingToSeveralFamiliesIsExplicit() throws {
        let book = try ArtistDecisionBook().deciding(.style(rowID: "punk"), forArtists: ["AC/DX", "ACDX"], at: Self.base)
        #expect(book.decision(forArtist: "AC/DX")?.choice == .style(rowID: "punk"))
        #expect(book.decision(forArtist: "ACDX")?.choice == .style(rowID: "punk"))
    }

    @Test func aDecisionCanBeChangedAndCleared() throws {
        let first = try ArtistDecisionBook().deciding(.style(rowID: "gothic"), forArtists: ["Paper Harbour"], at: Self.base)
        let changed = try first.deciding(.keepFallback, forArtists: ["paper harbour"], at: Self.base.addingTimeInterval(60))
        #expect(changed.decision(forArtist: "Paper Harbour") == ArtistDecision(choice: .keepFallback, decidedAt: Self.base.addingTimeInterval(60)))
        #expect(first.decision(forArtist: "Paper Harbour")?.choice == .style(rowID: "gothic"), "不可變：舊值不受影響")
        let cleared = changed.clearing(forArtists: ["Paper Harbour"])
        #expect(cleared.decision(forArtist: "Paper Harbour") == nil)
    }

    @Test func aSignedBandCannotTakeAStyle() {
        #expect(throws: ArtistDecisionBook.DecisionError.signedBand) {
            try ArtistDecisionBook().deciding(.style(rowID: "gothic"), forArtists: ["Mayhem"], at: Self.base)
        }
    }

    @Test func onlyExistingRowsCanBeChosen() {
        #expect(throws: ArtistDecisionBook.DecisionError.unknownRow) {
            try ArtistDecisionBook().deciding(.style(rowID: "heavypower"), forArtists: ["Paper Harbour"], at: Self.base)
        }
        #expect(ArtistDecisionBook.selectableRowIDs == (SongProfileResolver.keywordRows + SongProfileResolver.genericRows).map(\.id))
    }

    @Test func anEmptySpellingIsIgnored() throws {
        let book = try ArtistDecisionBook().deciding(.keepFallback, forArtists: ["   "], at: Self.base)
        #expect(book == ArtistDecisionBook())
    }

    // MARK: 存檔

    @Test func decisionsSurviveARoundTrip() throws {
        let store = ArtistDecisionStore(directory: tempDirectory())
        let book = try ArtistDecisionBook()
            .deciding(.style(rowID: "gothic"), forArtists: ["Paper Harbour"], at: Self.base)
            .deciding(.keepFallback, forArtists: ["Velvet Lanterns"], at: Self.base)
        try store.save(book)
        let loaded = store.load()
        #expect(loaded.book == book)
        #expect(loaded.isWritable)
    }

    @Test func aMissingFileLoadsEmptyAndWritable() {
        let loaded = ArtistDecisionStore(directory: tempDirectory()).load()
        #expect(loaded.book == ArtistDecisionBook() && loaded.isWritable)
    }

    @Test(arguments: ["not json", "{\"schemaVersion\": 1, \"decisions\": 5}", "[]"])
    func aCorruptFileLoadsEmptyAndMayBeReplaced(contents: String) throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: directory.appendingPathComponent(ArtistDecisionStore.fileName))
        let store = ArtistDecisionStore(directory: directory)
        #expect(store.load() == .init(book: ArtistDecisionBook(), isWritable: true))
        try store.save(ArtistDecisionBook().deciding(.keepFallback, forArtists: ["Velvet Lanterns"], at: Self.base), now: Self.base)
        #expect(store.load().book.decision(forArtist: "Velvet Lanterns") != nil)
        let prefix = "\(ArtistDecisionStore.fileName).bak-\(Int(Self.base.timeIntervalSince1970))-"
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(prefix) }
        #expect(backups.count == 1)
        #expect(try backups.first.map { try Data(contentsOf: directory.appendingPathComponent($0)) } == Data(contents.utf8), "壞檔先留一份再覆寫")
    }

    @Test func aSecondCorruptionInTheSameSecondStillSaves() throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(ArtistDecisionStore.fileName)
        let store = ArtistDecisionStore(directory: directory)
        for round in 0..<2 {
            try Data("not json \(round)".utf8).write(to: url)
            try store.save(ArtistDecisionBook().deciding(.keepFallback, forArtists: ["Velvet Lanterns"], at: Self.base), now: Self.base)
        }
        #expect(store.load().book.decision(forArtist: "Velvet Lanterns") != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".bak-") }.count == 2)
    }

    @Test func aNewerSchemaIsNeitherReadNorOverwritten() throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(ArtistDecisionStore.fileName)
        let newer = Data("{\"schemaVersion\": 99, \"decisions\": {}}".utf8)
        try newer.write(to: url)
        let store = ArtistDecisionStore(directory: directory)
        #expect(store.load() == .init(book: ArtistDecisionBook(), isWritable: false))
        #expect(throws: ArtistDecisionStore.StoreError.unrecognizedFileOnDisk) { try store.save(ArtistDecisionBook()) }
        #expect(try Data(contentsOf: url) == newer)
    }

    @Test func aSymbolicLinkIsNotFollowed() throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("elsewhere.json")
        try Data("{\"schemaVersion\": 1, \"decisions\": {}}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(ArtistDecisionStore.fileName), withDestinationURL: target)
        #expect(ArtistDecisionStore(directory: directory).load().isWritable == false)
    }

    @Test func anOversizedFileIsNotRead() throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: ArtistDecisionStore.maxFileBytes + 1).write(to: directory.appendingPathComponent(ArtistDecisionStore.fileName))
        #expect(ArtistDecisionStore(directory: directory).load().isWritable == false)
    }
}
