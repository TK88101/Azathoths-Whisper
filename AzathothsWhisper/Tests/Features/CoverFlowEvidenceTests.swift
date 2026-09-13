import Foundation
import Testing

@testable import AzathothsWhisper

// H-02 閘門的證據持久化（docs/plans/2026-09-13-coverflow-h02-fix4.md §5.7 (7)）。
//
// 「運行有效」的定義含**證據完整**：每個 test／iteration 的 trace 與 marks 檔存在且與 manifest 相符，
// 缺任一即整次運行無效（§5「通用定義」）。檔名推序與 manifest 內容因此是判定的一部分，先在單元層釘住。
@Suite("CoverFlowEvidence")
struct CoverFlowEvidenceTests {
    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("azw-evidence-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// XCTest 不暴露 `-test-iterations` 的迭代序號，只能以「同名前綴的 trace 檔數」推序
    @Test func ordinalCountsThisTestsTraceFilesOnly() {
        let existing = [
            "T1-1.trace", "T1-2.trace", "T1-1.marks", "T1-1.manifest.json",
            "T2-1.trace", "T10-1.trace", "T1-x.trace", "T1.trace",
        ]
        #expect(CoverFlowEvidence.ordinal(test: "T1", existingFileNames: existing) == 3)
        #expect(CoverFlowEvidence.ordinal(test: "T2", existingFileNames: existing) == 2)
        #expect(CoverFlowEvidence.ordinal(test: "T3", existingFileNames: existing) == 1)
        #expect(CoverFlowEvidence.ordinal(test: "T1", existingFileNames: []) == 1)
    }

    @Test func destinationNamesFilesByTestAndOrdinal() {
        let destination = CoverFlowEvidence.destination(
            directory: "/tmp/ev", test: "T1", existingFileNames: ["T1-1.trace"], fallbackTracePath: "/tmp/fallback.log"
        )
        #expect(destination.directory == "/tmp/ev")
        #expect(destination.ordinal == 2)
        #expect(destination.tracePath == "/tmp/ev/T1-2.trace")
        #expect(destination.marksPath == "/tmp/ev/T1-2.marks")
    }

    /// 缺省退回現行 temporaryDirectory＋UUID：閘門輪（未設 `AZW_EVIDENCE_DIR`）行為不變、marks 為 no-op
    @Test func destinationWithoutEvidenceDirectoryKeepsTheFallbackPath() {
        let destination = CoverFlowEvidence.destination(
            directory: nil, test: "T1", existingFileNames: [], fallbackTracePath: "/tmp/fallback.log"
        )
        #expect(destination.directory == nil)
        #expect(destination.ordinal == nil)
        #expect(destination.tracePath == "/tmp/fallback.log")
        #expect(destination.marksPath == nil)
    }

    @Test func md5MatchesTheKnownVector() throws {
        #expect(CoverFlowEvidence.md5Hex(of: Data("abc".utf8)) == "900150983cd24fb0d6963f7d28e17f72")
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("x.trace")
        try Data("abc".utf8).write(to: file)
        #expect(CoverFlowEvidence.md5Hex(ofFileAt: file.path) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(CoverFlowEvidence.md5Hex(ofFileAt: directory.appendingPathComponent("missing").path) == nil)
    }

    /// 鍵順序固定（`.sortedKeys`）且 sampler 顯式為 null——缺鍵與 null 對判定器是兩回事
    @Test func manifestJSONIsSortedAndCarriesAnExplicitNullSampler() throws {
        let manifest = CoverFlowEvidence.Manifest(
            test: "T1", ordinal: 1, treeHash: "TH", cdhash: "CD",
            files: CoverFlowEvidence.Manifest.Files(
                trace: CoverFlowEvidence.FileEntry(path: "T1-1.trace", md5: "aa"),
                marks: CoverFlowEvidence.FileEntry(path: "T1-1.marks", md5: "bb"),
                sampler: nil
            )
        )
        let json = try CoverFlowEvidence.manifestJSON(manifest)
        #expect(json == #"{"cdhash":"CD","files":{"marks":{"md5":"bb","path":"T1-1.marks"},"sampler":null,"#
            + #""trace":{"md5":"aa","path":"T1-1.trace"}},"ordinal":1,"schema":1,"test":"T1","tree_hash":"TH"}"#)
    }

    /// 真的把檔案讀起來算 md5：缺檔＝該欄 null（判定器據此判證據不完整）
    @Test func manifestFromDirectoryHashesTheFilesThatExist() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("abc".utf8).write(to: directory.appendingPathComponent("T1-1.trace"))

        let manifest = CoverFlowEvidence.manifest(
            directory: directory.path, test: "T1", ordinal: 1, treeHash: "", cdhash: ""
        )
        #expect(manifest.files.trace?.path == "T1-1.trace")
        #expect(manifest.files.trace?.md5 == "900150983cd24fb0d6963f7d28e17f72")
        #expect(manifest.files.marks == nil, "marks 檔不存在時不得編出假的 md5")
        #expect(manifest.files.sampler == nil, "本任務不產生 sampler 檔")
        #expect(manifest.schema == 1)
    }

    @Test func manifestIsWrittenNextToTheEvidenceItDescribes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("abc".utf8).write(to: directory.appendingPathComponent("T4-2.trace"))

        let path = try CoverFlowEvidence.writeManifest(
            directory: directory.path, test: "T4", ordinal: 2, treeHash: "tree", cdhash: "cd"
        )
        #expect(path == directory.appendingPathComponent("T4-2.manifest.json").path)
        let written = try String(contentsOfFile: path, encoding: .utf8)
        #expect(written.contains(#""tree_hash":"tree""#))
        #expect(written.contains(#""sampler":null"#))
        #expect(written.contains(#""ordinal":2"#))
    }
}
