// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import CryptoKit
import Foundation

/// 閘門證據的落地位置與清單（docs/plans/2026-09-13-coverflow-h02-fix4.md §5.7 (7)）。
///
/// **為何需要**：R5-5 的 trace 寫在 runner 的 temporaryDirectory＋隨機 UUID，運行後沒有保留——
/// 「M0 的 nil 形態分布」因此只能記 TBD（計劃 §2）。§5 把「證據完整」寫進了運行有效的定義：
/// 每個 test／iteration 的 trace 與 marks 檔都要在、且與 manifest 的 md5 相符，缺任一即整次運行無效。
///
/// app 與 UITests 兩個 target 同編此檔（見 project.yml）：命名規則與 manifest 格式只有一個來源。
enum CoverFlowEvidence {
    // MARK: 環境變數（runner 端；以 `TEST_RUNNER_` 前綴轉發）

    /// 證據目錄；未設即退回 temporaryDirectory＋UUID（閘門輪行為不變）
    static let directoryVariable = "AZW_EVIDENCE_DIR"
    static let treeHashVariable = "AZW_TREE_HASH"
    static let cdhashVariable = "AZW_CDHASH"

    static let manifestSchema = 1

    enum Extension: String {
        case trace
        case marks
        case manifest = "manifest.json"
    }

    // MARK: 命名與序號

    /// n＝該測試已存在的 `<test>-*.trace` 數 ＋1。
    ///
    /// XCTest 不暴露 `-test-iterations` 的迭代序號（`XCTestCase` 上沒有公開 API 可問），只能以檔數推序：
    /// 每次迭代開場各寫一份 trace，故第 k 次啟動時目錄裡已有 k−1 份。**前提**：證據目錄每輪清空，
    /// 否則序號會接著上一輪繼續長（判定器比對 manifest 的 ordinal 與檔名時看得出來）
    static func ordinal(test: String, existingFileNames: [String]) -> Int {
        existingFileNames.filter { isTraceFile($0, test: test) }.count + 1
    }

    private static func isTraceFile(_ name: String, test: String) -> Bool {
        let prefix = "\(test)-"
        let suffix = ".\(Extension.trace.rawValue)"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
        // `T1-` 也是 `T10-1.trace` 的前綴：中段必須是純數字，否則 T1 會把 T10 的檔算進自己的序號
        let middle = name.dropFirst(prefix.count).dropLast(suffix.count)
        return !middle.isEmpty && middle.allSatisfy { $0.isASCII && $0.isNumber }
    }

    static func fileName(test: String, ordinal: Int, extension kind: Extension) -> String {
        "\(test)-\(ordinal).\(kind.rawValue)"
    }

    static func path(directory: String, test: String, ordinal: Int, extension kind: Extension) -> String {
        URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent(fileName(test: test, ordinal: ordinal, extension: kind)).path
    }

    /// 一次迭代的證據落點。`directory == nil`＝沒設 `AZW_EVIDENCE_DIR`：trace 走呼叫端給的
    /// temporaryDirectory 退路、marks 為 no-op、不寫 manifest（閘門輪行為與 R5-5 相同）
    struct Destination: Equatable, Sendable {
        let directory: String?
        let ordinal: Int?
        let tracePath: String
        let marksPath: String?
    }

    static func destination(
        directory: String?, test: String, existingFileNames: [String], fallbackTracePath: String
    ) -> Destination {
        guard let directory, !directory.isEmpty else {
            return Destination(directory: nil, ordinal: nil, tracePath: fallbackTracePath, marksPath: nil)
        }
        let ordinal = ordinal(test: test, existingFileNames: existingFileNames)
        return Destination(
            directory: directory,
            ordinal: ordinal,
            tracePath: path(directory: directory, test: test, ordinal: ordinal, extension: .trace),
            marksPath: path(directory: directory, test: test, ordinal: ordinal, extension: .marks)
        )
    }

    // MARK: manifest

    struct FileEntry: Encodable, Equatable, Sendable {
        /// 相對證據目錄的檔名（絕對路徑會把操作者的目錄結構帶進證據包）
        let path: String
        let md5: String
    }

    struct Manifest: Encodable, Equatable, Sendable {
        /// 缺檔＝該欄 null。**顯式 null 不是缺鍵**：判定器要能分辨「這一輪不產生 sampler」與「欄位忘了寫」
        struct Files: Encodable, Equatable, Sendable {
            let trace: FileEntry?
            let marks: FileEntry?
            let sampler: FileEntry?

            enum CodingKeys: String, CodingKey {
                case trace, marks, sampler
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try encode(trace, forKey: .trace, into: &container)
                try encode(marks, forKey: .marks, into: &container)
                try encode(sampler, forKey: .sampler, into: &container)
            }

            /// 合成的 `Encodable` 對 Optional 走 `encodeIfPresent`（缺鍵）；這裡一律寫出鍵
            private func encode(
                _ entry: FileEntry?, forKey key: CodingKeys,
                into container: inout KeyedEncodingContainer<CodingKeys>
            ) throws {
                if let entry {
                    try container.encode(entry, forKey: key)
                } else {
                    try container.encodeNil(forKey: key)
                }
            }
        }

        let schema: Int
        let test: String
        let ordinal: Int
        let treeHash: String
        let cdhash: String
        let files: Files

        enum CodingKeys: String, CodingKey {
            case schema, test, ordinal, cdhash, files
            case treeHash = "tree_hash"
        }

        init(test: String, ordinal: Int, treeHash: String, cdhash: String, files: Files) {
            self.schema = CoverFlowEvidence.manifestSchema
            self.test = test
            self.ordinal = ordinal
            self.treeHash = treeHash
            self.cdhash = cdhash
            self.files = files
        }
    }

    /// 目錄裡實際存在的檔案 → manifest（缺檔＝該欄 null，判定器據此判證據不完整）
    static func manifest(
        directory: String, test: String, ordinal: Int, treeHash: String, cdhash: String
    ) -> Manifest {
        Manifest(
            test: test, ordinal: ordinal, treeHash: treeHash, cdhash: cdhash,
            files: Manifest.Files(
                trace: fileEntry(directory: directory, test: test, ordinal: ordinal, extension: .trace),
                marks: fileEntry(directory: directory, test: test, ordinal: ordinal, extension: .marks),
                // 本任務不產生 sampler 檔（儀器 §5.7 (8) 另行實作）
                sampler: nil
            )
        )
    }

    static func fileEntry(
        directory: String, test: String, ordinal: Int, extension kind: Extension
    ) -> FileEntry? {
        let name = fileName(test: test, ordinal: ordinal, extension: kind)
        guard let md5 = md5Hex(ofFileAt: path(directory: directory, test: test, ordinal: ordinal, extension: kind))
        else { return nil }
        return FileEntry(path: name, md5: md5)
    }

    /// 鍵順序固定（`.sortedKeys`）：manifest 進 git／diff 時不會因字典序抖動而產生假差異
    static func manifestJSON(_ manifest: Manifest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(manifest), as: UTF8.self)
    }

    /// 寫 `<dir>/<test>-<n>.manifest.json`，回傳寫入路徑
    @discardableResult
    static func writeManifest(
        directory: String, test: String, ordinal: Int, treeHash: String, cdhash: String
    ) throws -> String {
        let json = try manifestJSON(
            manifest(directory: directory, test: test, ordinal: ordinal, treeHash: treeHash, cdhash: cdhash)
        )
        let destination = path(directory: directory, test: test, ordinal: ordinal, extension: .manifest)
        try Data(json.utf8).write(to: URL(fileURLWithPath: destination))
        return destination
    }

    // MARK: md5

    static func md5Hex(of data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 讀不到（缺檔、是目錄、無權限）＝nil，不得回傳空字串冒充「算過了」
    static func md5Hex(ofFileAt path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
            return nil
        }
        return md5Hex(of: data)
    }
}
#endif
