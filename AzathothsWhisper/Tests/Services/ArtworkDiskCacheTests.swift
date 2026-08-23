import CryptoKit
import Foundation
import Testing

@testable import AzathothsWhisper

// 封面磁碟快取（M7 P2-1）。對應 ACCEPTANCE H-07 與 M7 Plan §5 的 DoD ①–⑪。
//
// **一律走臨時目錄**：真實 Caches 目錄不得被測試碰到（Plan V4）。每個測試自帶
// UUID 目錄並在結束時刪除。
@Suite("ArtworkDiskCache")
struct ArtworkDiskCacheTests {
    // MARK: 測試工具

    /// 每個測試自己的臨時目錄。`body` 結束即刪，不論成敗
    private func withTempDirectory<T>(_ body: (URL) async throws -> T) async rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("azw-artwork-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        return try await body(dir)
    }

    private func bytes(_ count: Int, fill: UInt8 = 0xAB) -> Data {
        Data(repeating: fill, count: count)
    }

    private func fileName(_ id: String) -> String {
        ArtworkDiskCache.fileName(for: id)
    }

    private func fileURL(_ dir: URL, _ id: String) -> URL {
        dir.appendingPathComponent(fileName(id))
    }

    private func metadataURL(_ dir: URL) -> URL {
        dir.appendingPathComponent("metadata.json")
    }

    private func readMetadata(_ dir: URL) throws -> ArtworkDiskCacheMetadata {
        let data = try Data(contentsOf: metadataURL(dir))
        return try JSONDecoder().decode(ArtworkDiskCacheMetadata.self, from: data)
    }

    private func contents(_ dir: URL) -> Set<String> {
        let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        return Set(names ?? [])
    }

    // MARK: 基本存取

    @Test func storesAndRetrievesByPersistentID() async {
        await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            let payload = bytes(128)
            await cache.store(payload, for: "PID1")
            #expect(await cache.data(for: "PID1") == payload)
        }
    }

    @Test func missReturnsNil() async {
        await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            #expect(await cache.data(for: "absent") == nil)
        }
    }

    @Test func removeDeletesEntryAndFile() async {
        await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(64), for: "PID1")
            await cache.remove(for: "PID1")

            #expect(await cache.data(for: "PID1") == nil)
            #expect(await cache.entryCount == 0)
            #expect(!FileManager.default.fileExists(atPath: fileURL(dir, "PID1").path))
        }
    }

    /// persistentID 來自 AE，可能含路徑穿越字元。檔名走 SHA-256，必須落在目錄內
    @Test func handlesPersistentIDsWithSpecialCharacters() async {
        await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            let weird = "../../etc/passwd\u{1}\u{0}名前"
            let payload = bytes(32)
            await cache.store(payload, for: weird)

            #expect(await cache.data(for: weird) == payload)
            #expect(contents(dir).contains(fileName(weird)), "檔案必須以 hash 命名並落在目錄內")
        }
    }

    /// 空 ID 會固定 hash 成同一個檔名，不同「未知曲目」會互相覆寫
    @Test func emptyIDIsRejected() async {
        await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(16), for: "")

            #expect(await cache.data(for: "") == nil)
            #expect(await cache.entryCount == 0)
        }
    }

    // MARK: DoD ④ 首次寫入 vs 覆寫（兩條路徑行為不同）

    @Test func firstStoreMovesTempIntoPlace() async {
        await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(100), for: "PID1")

            let names = contents(dir)
            #expect(names.contains(fileName("PID1")))
            #expect(!names.contains { $0.contains(".tmp-") }, "不得留下 temp 檔")
        }
    }

    @Test func overwriteReplacesExistingFile() async {
        await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(100, fill: 0x11), for: "PID1")
            await cache.store(bytes(60, fill: 0x22), for: "PID1")

            #expect(await cache.data(for: "PID1") == bytes(60, fill: 0x22), "覆寫須反映新內容")
            #expect(await cache.entryCount == 1, "覆寫不得增加 entry")
            #expect(await cache.totalBytes == 60, "位元組總量須反映新大小")
            #expect(!contents(dir).contains { $0.contains(".tmp-") }, "覆寫不得留下 temp 檔")
        }
    }

    // MARK: DoD ②③ LRU 淘汰

    @Test func evictsLeastRecentlyAccessedByCount() async {
        await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir, limits: .init(countLimit: 3))
            for id in ["A", "B", "C"] { await cache.store(bytes(10), for: id) }

            // 讓 A 成為最近使用，B 最久未用
            _ = await cache.data(for: "A")
            _ = await cache.data(for: "C")
            await cache.store(bytes(10), for: "D")

            #expect(await cache.entryCount == 3)
            #expect(await cache.data(for: "B") == nil, "最久未存取者應被淘汰")
            #expect(await cache.data(for: "A") != nil)
            #expect(await cache.data(for: "D") != nil, "剛寫入者不得在本輪被淘汰")
        }
    }

    @Test func evictsLeastRecentlyAccessedByBytes() async {
        await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir, limits: .init(countLimit: 100, byteLimit: 300))
            await cache.store(bytes(100), for: "A")
            await cache.store(bytes(100), for: "B")
            _ = await cache.data(for: "A")           // A 較新
            await cache.store(bytes(150), for: "C")  // 總量 350 > 300 → 淘汰最舊的 B

            #expect(await cache.totalBytes <= 300)
            #expect(await cache.data(for: "B") == nil)
            #expect(await cache.data(for: "A") != nil)
            #expect(await cache.data(for: "C") != nil)
        }
    }

    /// 單筆就超過總配額的資料直接拒存——存了必然立刻被淘汰，白做一次 I/O
    @Test func oversizedItemIsRejected() async {
        await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir, limits: .init(byteLimit: 100))
            await cache.store(bytes(200), for: "BIG")

            #expect(await cache.data(for: "BIG") == nil)
            #expect(await cache.entryCount == 0)
            #expect(contents(dir).isEmpty || !contents(dir).contains(fileName("BIG")))
        }
    }

    // MARK: DoD ⑥ hash 碰撞驗證

    /// metadata 記的 persistentID 與請求不符 → 視為 miss 並刪除。
    /// 沒有這層驗證，SHA-256 碰撞（或 metadata 被竄改）會回傳**另一首歌的封面**
    @Test func mismatchedPersistentIDIsTreatedAsMissAndDeleted() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(50), for: "PID1")
            await cache.flush()

            // 手動把 entry 的 persistentID 改成別首歌
            var meta = try readMetadata(dir)
            let key = fileName("PID1")
            meta.entries[key]?.persistentID = "SOMEONE-ELSE"
            try JSONEncoder().encode(meta).write(to: metadataURL(dir))

            let reopened = ArtworkDiskCache(directory: dir)
            #expect(await reopened.data(for: "PID1") == nil, "persistentID 不匹配須視為 miss")
            #expect(!FileManager.default.fileExists(atPath: fileURL(dir, "PID1").path), "不匹配的檔案須刪除")
        }
    }

    // MARK: DoD ⑤ 損毀檔

    /// 檔案大小與 metadata 記錄不符＝被截斷（半寫、磁碟錯誤）→ 刪除並 miss
    @Test func truncatedFileIsDeletedAndMisses() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(200), for: "PID1")
            await cache.flush()

            try bytes(10).write(to: fileURL(dir, "PID1"))   // 截斷

            let reopened = ArtworkDiskCache(directory: dir)
            #expect(await reopened.data(for: "PID1") == nil)
            #expect(await reopened.entryCount == 0)
            #expect(!FileManager.default.fileExists(atPath: fileURL(dir, "PID1").path))
        }
    }

    // MARK: DoD ⑩⑪ metadata 損毀、orphan、殘留 temp

    @Test func corruptMetadataClearsAndRecovers() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(40), for: "PID1")
            await cache.flush()

            try Data("{ not json".utf8).write(to: metadataURL(dir))

            let reopened = ArtworkDiskCache(directory: dir)
            #expect(await reopened.entryCount == 0, "損毀的 metadata 須重建為空")
            #expect(
                !FileManager.default.fileExists(atPath: fileURL(dir, "PID1").path),
                "無法驗證身分的快取檔須清除（SHA-256 單向，persistentID 不可還原）"
            )

            await reopened.store(bytes(40), for: "PID2")
            #expect(await reopened.data(for: "PID2") != nil, "重建後須能正常運作")
        }
    }

    /// version 不符＝欄位語義可能已變，猜測比重建更危險
    @Test func unknownVersionIsTreatedAsCorrupt() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(40), for: "PID1")
            await cache.flush()

            var meta = try readMetadata(dir)
            meta.version = 999
            try JSONEncoder().encode(meta).write(to: metadataURL(dir))

            let reopened = ArtworkDiskCache(directory: dir)
            #expect(await reopened.entryCount == 0)
            #expect(await reopened.data(for: "PID1") == nil)
        }
    }

    /// 清除範圍限於快取自身的三類檔案——`directory` 由外部傳入，規格不保證它是專用目錄
    @Test func corruptMetadataLeavesForeignFilesAlone() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(40), for: "PID1")
            await cache.flush()

            let foreign = dir.appendingPathComponent("important-notes.txt")
            try Data("do not delete".utf8).write(to: foreign)
            try Data("{ not json".utf8).write(to: metadataURL(dir))

            let reopened = ArtworkDiskCache(directory: dir)
            #expect(await reopened.entryCount == 0)
            #expect(
                FileManager.default.fileExists(atPath: foreign.path),
                "非快取格式的檔案不得因 metadata 損毀被刪除"
            )
        }
    }

    /// entry 的異常值逐筆丟棄，不整體作廢
    @Test func invalidEntryValuesAreDropped() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(40), for: "GOOD")
            await cache.store(bytes(40), for: "BAD")
            await cache.flush()

            var meta = try readMetadata(dir)
            meta.entries[fileName("BAD")]?.size = -5
            try JSONEncoder().encode(meta).write(to: metadataURL(dir))

            let reopened = ArtworkDiskCache(directory: dir)
            #expect(await reopened.data(for: "GOOD") != nil, "正常 entry 不得被異常鄰居連累")
            #expect(await reopened.data(for: "BAD") == nil)
        }
    }

    /// metadata 是磁碟資料、可被竄改。非 hex 的 key 一律不得拼成檔案路徑
    @Test func nonHexKeysNeverTouchFilesystem() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(40), for: "GOOD")
            await cache.flush()

            let decoy = dir.appendingPathComponent("decoy.txt")
            try Data("bait".utf8).write(to: decoy)

            var meta = try readMetadata(dir)
            meta.entries["../decoy.txt"] = .init(persistentID: "EVIL", size: 4, lastAccess: 0)
            try JSONEncoder().encode(meta).write(to: metadataURL(dir))

            let reopened = ArtworkDiskCache(directory: dir)
            _ = await reopened.data(for: "GOOD")
            #expect(FileManager.default.fileExists(atPath: decoy.path), "非 hex key 不得觸碰檔案系統")
        }
    }

    /// 檔案還在、只是這次讀不到（權限／暫時性 I/O）——**不得**當成損毀刪掉。
    /// 這是與 metadata 讀取失敗、列目錄失敗同一條原則的第三個落點
    @Test func unreadableFileKeepsEntryForLaterRetry() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            let payload = bytes(64)
            await cache.store(payload, for: "PID1")
            await cache.flush()

            let file = fileURL(dir, "PID1")
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

            #expect(await cache.data(for: "PID1") == nil, "讀不到就回 miss")
            #expect(await cache.entryCount == 1, "暫時性讀取失敗不得刪掉 entry")
            #expect(FileManager.default.fileExists(atPath: file.path), "不得刪檔")

            // 權限恢復後應能重新命中
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            #expect(await cache.data(for: "PID1") == payload, "權限恢復後須重新命中")
        }
    }

    /// 反方向的失配：metadata 有 entry，但磁碟檔案整個不見了（外部刪除、磁碟錯誤）。
    /// 該 entry 必須連同它佔的配額一起消失，否則配額計算會永久偏移
    @Test func entryWithMissingFileIsDroppedFromQuota() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(100), for: "GONE")
            await cache.store(bytes(40), for: "KEPT")
            await cache.flush()

            try FileManager.default.removeItem(at: fileURL(dir, "GONE"))

            let reopened = ArtworkDiskCache(directory: dir)
            #expect(await reopened.data(for: "GONE") == nil)
            #expect(await reopened.entryCount == 1)
            #expect(await reopened.totalBytes == 40, "消失的檔案不得繼續佔用配額")
            #expect(await reopened.data(for: "KEPT") != nil, "其餘 entry 不受影響")
        }
    }

    /// 有檔無 entry（上次寫入後 metadata 沒寫成）→ 無法驗證身分，清掉
    @Test func orphanFilesAreRemovedOnLoad() async throws {
        try await withTempDirectory { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let orphan = dir.appendingPathComponent(fileName("GHOST"))
            try bytes(20).write(to: orphan)

            let cache = ArtworkDiskCache(directory: dir)
            #expect(await cache.entryCount == 0)
            #expect(!FileManager.default.fileExists(atPath: orphan.path), "orphan 須在載入時清除")
        }
    }

    /// 上次寫入中途崩潰留下的 temp 檔
    @Test func staleTempFilesAreRemovedOnLoad() async throws {
        try await withTempDirectory { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stale = dir.appendingPathComponent("\(fileName("X")).tmp-\(UUID().uuidString)")
            let staleMeta = dir.appendingPathComponent("metadata.json.tmp-\(UUID().uuidString)")
            try bytes(20).write(to: stale)
            try bytes(20).write(to: staleMeta)

            let cache = ArtworkDiskCache(directory: dir)
            _ = await cache.entryCount
            #expect(!FileManager.default.fileExists(atPath: stale.path))
            #expect(!FileManager.default.fileExists(atPath: staleMeta.path))
        }
    }

    /// temp 清理只認**快取自己**的檔名格式。寬鬆地比對 `.tmp-` 子字串會刪掉
    /// 使用者放在同一目錄、碰巧含該字串的檔案
    @Test func foreignTempLikeNamesAreNotDeleted() async throws {
        try await withTempDirectory { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let decoys = [
                "important.tmp-notes",                       // 後綴不是 UUID
                "\(fileName("X")).tmp-not-a-uuid",           // 前綴合法但後綴不是 UUID
                "notes.tmp-\(UUID().uuidString)",            // 後綴是 UUID 但前綴不是快取檔名
            ].map { dir.appendingPathComponent($0) }
            for decoy in decoys { try bytes(8).write(to: decoy) }

            let cache = ArtworkDiskCache(directory: dir)
            _ = await cache.entryCount

            for decoy in decoys {
                #expect(
                    FileManager.default.fileExists(atPath: decoy.path),
                    "外部檔案 \(decoy.lastPathComponent) 不得被 temp 清理刪除"
                )
            }
        }
    }

    // MARK: 冷啟動與序號持久化（H-07）

    @Test func entriesSurviveReinstantiation() async {
        await withTempDirectory { dir in
            let payload = bytes(77)
            let first = ArtworkDiskCache(directory: dir)
            await first.store(payload, for: "PID1")

            let second = ArtworkDiskCache(directory: dir)
            #expect(await second.data(for: "PID1") == payload, "冷啟動須命中磁碟")
            #expect(await second.entryCount == 1)
        }
    }

    /// 序號**必須跨重啟單調遞增**：重置會讓舊 entry 的 lastAccess 看起來比新的還大，LRU 反向
    @Test func accessSequenceIsMonotonicAcrossRestart() async throws {
        try await withTempDirectory { dir in
            let first = ArtworkDiskCache(directory: dir)
            await first.store(bytes(10), for: "A")
            await first.store(bytes(10), for: "B")
            await first.flush()
            let sequenceBefore = try readMetadata(dir).nextSequence

            let second = ArtworkDiskCache(directory: dir)
            await second.store(bytes(10), for: "C")
            await second.flush()

            #expect(try readMetadata(dir).nextSequence > sequenceBefore, "序號不得倒退")
        }
    }

    /// 純讀取也要落盤，否則重啟後 LRU 次序回到寫入序、剛用過的反而先被淘汰
    @Test func accessUpdatesPersistAfterThresholdReads() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(10), for: "A")
            await cache.store(bytes(10), for: "B")
            await cache.flush()
            let before = try readMetadata(dir).entries[fileName("A")]?.lastAccess ?? -1

            for _ in 0..<16 { _ = await cache.data(for: "A") }

            let after = try readMetadata(dir).entries[fileName("A")]?.lastAccess ?? -1
            #expect(after > before, "累積達閾值的存取更新須自動落盤，不依賴 flush()")
        }
    }

    // MARK: DoD ⑧⑨ 併發

    @Test func concurrentStoresForDistinctIDsAllPersist() async {
        await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<20 {
                    group.addTask { await cache.store(self.bytes(30), for: "PID\(index)") }
                }
            }

            #expect(await cache.entryCount == 20)
            for index in 0..<20 {
                #expect(await cache.data(for: "PID\(index)") != nil)
            }
        }
    }

    /// 寫入與淘汰交錯後，終態仍須滿足配額，且 metadata 與目錄內容一致
    @Test func interleavedStoresKeepInvariants() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir, limits: .init(countLimit: 10, byteLimit: 400))
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<50 {
                    group.addTask {
                        await cache.store(self.bytes(30), for: "PID\(index)")
                        _ = await cache.data(for: "PID\(index % 5)")
                    }
                }
            }
            await cache.flush()

            let count = await cache.entryCount
            let total = await cache.totalBytes
            #expect(count <= 10)
            #expect(total <= 400)

            let meta = try readMetadata(dir)
            #expect(meta.entries.count == count, "metadata 須與記憶體狀態一致")
            let files = contents(dir).filter { ArtworkDiskCacheMetadata.isValidFileName($0) }
            #expect(files == Set(meta.entries.keys), "目錄內容須與 metadata 一致，無殘留無漏刪")
            #expect(!contents(dir).contains { $0.contains(".tmp-") }, "不得留下 temp 檔")
        }
    }

    // MARK: I/O 失敗降級

    /// 列目錄失敗不得被當成「目錄是空的」——那會刪光 metadata，把磁碟上的快取檔變成永久 orphan
    @Test func unreadableDirectoryDegradesWithoutDiscardingEntries() async throws {
        try await withTempDirectory { dir in
            let cache = ArtworkDiskCache(directory: dir)
            await cache.store(bytes(50), for: "PID1")
            await cache.flush()

            // 移除目錄的執行/讀取權限：contentsOfDirectory 會失敗，但 metadata.json 仍在
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

            let reopened = ArtworkDiskCache(directory: dir)
            _ = await reopened.data(for: "PID1")   // 降級後回 nil，但**不得**寫回截斷的索引

            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            #expect(
                FileManager.default.fileExists(atPath: fileURL(dir, "PID1").path),
                "列目錄失敗不得刪除既有快取檔"
            )
            let meta = try readMetadata(dir)
            #expect(meta.entries.count == 1, "列目錄失敗不得把 entry 從 metadata 抹掉")
        }
    }

    /// 目錄路徑被一個**檔案**佔住 → 無法建目錄。快取須靜默降級為 miss，不得拋錯或崩潰
    @Test func unwritableDirectoryDegradesToMiss() async throws {
        try await withTempDirectory { dir in
            let parent = dir.deletingLastPathComponent()
            let blocker = parent.appendingPathComponent("azw-blocker-\(UUID().uuidString)")
            try Data("x".utf8).write(to: blocker)
            defer { try? FileManager.default.removeItem(at: blocker) }

            let cache = ArtworkDiskCache(directory: blocker.appendingPathComponent("sub"))
            await cache.store(bytes(20), for: "PID1")

            #expect(await cache.data(for: "PID1") == nil)
            #expect(await cache.entryCount == 0)
        }
    }
}
