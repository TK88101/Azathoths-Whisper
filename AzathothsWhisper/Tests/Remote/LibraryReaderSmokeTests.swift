import Foundation
import MusicRemoteBridge
import RemoteProtocol
import Testing

@testable import AzathothsWhisper

// S3 T6 的真曲庫 smoke（sprint-3-detail.md §7「實機」、附錄 C T6 偏差）：要在帶 NSAppleMusicUsageDescription 的
// Azathoth 宿主內跑（swift test 程序沒有這個鍵，ITLibrary 必回 4097）。預設跳過；使用者在場時以
// TEST_RUNNER_YSE_LIBRARY_TESTS=1 開啟（可能跳「媒體與 Apple Music」授權框）。只讀、只斷言數量與版本，不記名稱。
@Suite("LibraryReaderSmoke", .enabled(if: ProcessInfo.processInfo.environment["YSE_LIBRARY_TESTS"] == "1"))
struct LibraryReaderSmokeTests {
    @Test func realLibraryLoadsAndIsUnchangedByReading() async throws {
        let reader = LibraryReader()
        let first = CatalogIndexBuilder.build(try await reader.load())
        #expect(!first.albums.isEmpty)
        if let expected = ProcessInfo.processInfo.environment["YSE_EXPECTED_ALBUMS"].flatMap(Int.init) {
            #expect(first.albums.count == expected)
        }
        let again = CatalogIndexBuilder.build(try await reader.load())
        #expect(again.version == first.version)        // 只讀：讀兩次版本相同
        #expect(first.skipped.values.reduce(0, +) >= 0)
    }
}

/// S4 T12 真曲庫版（#4-1 前置；同上旗標與宿主）：每張放行專輯以名稱查找必定只撈到自己、首數與順序＝捷徑計畫。
/// 失敗時只列專輯 ID 與件數，不列名稱
@Suite("AdmittedAlbumIdentityLibrary", .enabled(if: ProcessInfo.processInfo.environment["YSE_LIBRARY_TESTS"] == "1"))
struct AdmittedAlbumIdentityLibraryTests {
    @Test func everyAdmittedAlbumInTheRealLibraryLooksUpExactlyItself() async throws {
        let load = try await LibraryReader().load()
        let index = CatalogIndexBuilder.build(load)
        let admitted = index.admission.values.filter { if case .admitted = $0 { true } else { false } }.count
        #expect(admitted > 0)
        // #4-1 前後比對用：只印版本雜湊與數量（不含名稱）
        print("YSE-LIBRARY version=\(index.version) albums=\(index.albums.count) admitted=\(admitted)")
        let violations = AdmittedAlbumIdentity.violations(load, index: index)
        #expect(violations.isEmpty, "\(violations.count) 張放行專輯同定失敗：\(violations.prefix(20))")
    }
}
