import Foundation
import Testing

@testable import YogSothothsEcho

// CR-018：detail 原檔的磁碟快取——獨立目錄與 300 MiB 配額（不擠 spine 的 500 MiB）；鍵含 detail；啟動清暫存；超額依 LRU 淘汰

struct DetailArtworkStoreTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("detail-store-\(UUID().uuidString)", isDirectory: true)

    @Test func quotaIsSeparateFromSpine() {
        #expect(DetailArtworkStore.diskLimit == 300 * 1_048_576 && DetailArtworkStore.diskLimit < ArtworkCache.diskLimit)
        #expect(DetailArtworkStore.defaultDirectory != ArtworkCache.defaultDirectory)
    }

    @Test func storesAndReadsBackByAlbumAndToken() async {
        let store = DetailArtworkStore(directory: directory)
        await store.put(Data([1, 2, 3]), albumID: "00000000000000a1", token: "00000000000000f1")
        #expect(await store.data(albumID: "00000000000000a1", token: "00000000000000f1") == Data([1, 2, 3]))
        #expect(await store.data(albumID: "00000000000000a1", token: "00000000000000f2") == nil)
        // 新實例從磁碟讀得到（重開 App）
        #expect(await DetailArtworkStore(directory: directory).data(albumID: "00000000000000a1", token: "00000000000000f1") == Data([1, 2, 3]))
    }

    @Test func evictsLeastRecentlyUsedOverLimit() async {
        let store = DetailArtworkStore(directory: directory, diskLimit: 10, diskTarget: 6)
        await store.put(Data(count: 4), albumID: "00000000000000a1", token: "00000000000000f1")
        await store.put(Data(count: 4), albumID: "00000000000000a2", token: "00000000000000f1")
        _ = await store.data(albumID: "00000000000000a1", token: "00000000000000f1")   // a1 變成較新
        await store.put(Data(count: 4), albumID: "00000000000000a3", token: "00000000000000f1")
        #expect(await store.data(albumID: "00000000000000a2", token: "00000000000000f1") == nil)
        #expect(await store.data(albumID: "00000000000000a3", token: "00000000000000f1") != nil)
    }

    /// 索引遺失（損毀、寫到一半被殺）：以目錄內的檔案重建，舊檔仍計入配額並可被淘汰（simcodex R1）
    @Test func missingIndexIsRebuiltFromDirectory() async throws {
        let first = DetailArtworkStore(directory: directory, diskLimit: 10, diskTarget: 6)
        await first.put(Data(count: 4), albumID: "00000000000000a1", token: "00000000000000f1")
        try FileManager.default.removeItem(at: directory.appendingPathComponent(DetailArtworkStore.indexFileName))
        let store = DetailArtworkStore(directory: directory, diskLimit: 10, diskTarget: 6)
        #expect(await store.data(albumID: "00000000000000a1", token: "00000000000000f1") == Data(count: 4))
        await store.put(Data(count: 4), albumID: "00000000000000a2", token: "00000000000000f1")
        await store.put(Data(count: 4), albumID: "00000000000000a3", token: "00000000000000f1")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".bin") }
        #expect(files.count == 1)
    }

    /// 啟動時清掉上次殘留的暫存（傳到一半被殺掉）
    @Test func startupClearsTemporaryParts() throws {
        let temp = DetailArtworkStore.temporaryDirectory(in: directory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: temp.appendingPathComponent("x.part").path, contents: Data([9]))
        _ = DetailArtworkStore(directory: directory)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []).isEmpty)
    }
}
