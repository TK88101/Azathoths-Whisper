import Foundation
import Testing

@testable import AzathothsWhisper

// Cannibal Corpse 計劃 v0.6 C1（docs/plans/2026-11-01-cannibal-corpse-entrance.md）：改動前，全部可稽核 profile
//（樂團表、曲風列、通用列、曲庫多列組合）＋J-Pop 三變體的逐槽合格集合（fit > 0）。只含 profile 名稱與元件代號
struct ProfileCandidatesSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let name: String
        let candidates: [String: [String]]
    }

    let schema: Int
    let sourceRevision: String
    let generatedBy: String
    let profiles: [Entry]

    static let fileName = "LyricsFX/profile-candidates-pre-cannibal.json"

    static func load() throws -> ProfileCandidatesSnapshot {
        try JSONDecoder().decode(ProfileCandidatesSnapshot.self, from: Data(contentsOf: GoldenFixtures.fixturesRoot().appendingPathComponent(fileName)))
    }

    static func eligible(_ profile: SongProfile, catalog: [FXComponent]) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: FXSlot.allCases.map { slot in
            (slot.rawValue, catalog.filter { $0.slot == slot && Composer.fit($0, profile) > 0 }.map(\.id).sorted())
        })
    }

    /// 現在的快照：可稽核 profile 用全目錄，J-Pop 三變體用各自鎖定的目錄（`JPopPolicy.catalog`）
    static func current() -> [Entry] {
        ReadabilityAudit.profiles.map { Entry(name: $0.name, candidates: eligible($0.profile, catalog: LyricsFXCatalog.all)) }
            + JPopVariant.allCases.map { Entry(name: "jpop:\($0.rawValue)", candidates: eligible($0.profile, catalog: JPopPolicy.catalog($0))) }
    }
}

@Suite("Profile candidates snapshot")
struct ProfileCandidatesSnapshotPrinter {
    /// 重產：`TEST_RUNNER_AZW_PRINT_PROFILE_CANDIDATES=<commit> xcodebuild test -only-testing:…/printTheSnapshot()`，
    /// 取兩個標記之間的那一行存成 `Tests/Fixtures/LyricsFX/profile-candidates-pre-cannibal.json`（app 宿主測試寫不了專案目錄）
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AZW_PRINT_PROFILE_CANDIDATES"] != nil))
    func printTheSnapshot() throws {
        let snapshot = ProfileCandidatesSnapshot(
            schema: 1, sourceRevision: ProcessInfo.processInfo.environment["AZW_PRINT_PROFILE_CANDIDATES"] ?? "",
            generatedBy: "ProfileCandidatesSnapshotPrinter/printTheSnapshot()", profiles: ProfileCandidatesSnapshot.current()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print("<<<PROFILESNAPSHOT\n\(String(decoding: try encoder.encode(snapshot), as: UTF8.self))\nPROFILESNAPSHOT>>>")
    }

    @Test func profileNamesAreUnique() {
        let names = ProfileCandidatesSnapshot.current().map(\.name)
        #expect(Set(names).count == names.count)
    }
}
