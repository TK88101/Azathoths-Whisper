// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import Foundation

/// 捲動軌跡檔的格式與讀取端（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.5）。
///
/// app（寫入端 `CoverFlowUITestTrace`）與 UITests（讀取端）同編此檔，格式只有一個來源。
/// 每行以 `\t` 分欄：
/// - 檔首：`#header  pid=…  bundle=…  exe-size=…  exe-mtime=…`（兼作二進位身分證據，§3.13）
/// - 記錄：`序號  微秒  kind  payload`
/// - 寫入失敗：`#error  errno=…`
enum CoverFlowTraceFormat {
    enum Kind: String, Sendable {
        /// scrollPosition binding 收到的 SwiftUI 原始回寫值
        case bind
        /// 本行程局部監聽到的 scrollWheel 事件性質
        case event
        /// NSScrollView 的 live scroll 通知
        case live
    }

    struct Header: Equatable, Sendable {
        let pid: Int32
        let bundlePath: String
        let executableSize: Int64
        let executableModified: Int64
    }

    struct Record: Equatable, Sendable {
        let sequence: Int
        let microseconds: Int64
        let kind: Kind
        let payload: String
    }

    struct Snapshot: Sendable {
        let header: Header?
        let records: [Record]
        /// 協議違反：`gap`（序號斷）、`time`（時間倒退）、`nul`、`write-error`、`malformed`
        let problems: [String]
        /// 已完整讀入的位元組終點；下一次從這裡讀（尾端半行不計入）
        let endOffset: UInt64
    }

    /// 欄位內不得出現分欄或換行，否則讀取端會切錯行
    static func sanitise(_ text: String) -> String {
        text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    static func headerLine(_ header: Header) -> String {
        "#header\tpid=\(header.pid)\tbundle=\(sanitise(header.bundlePath))"
            + "\texe-size=\(header.executableSize)\texe-mtime=\(header.executableModified)\n"
    }

    static func recordLine(_ record: Record) -> String {
        "\(record.sequence)\t\(record.microseconds)\t\(record.kind.rawValue)\t\(sanitise(record.payload))\n"
    }

    /// **先補一個換行**：短寫可能停在 payload 中途，緊接著寫的錯誤標記若黏在殘缺行尾，
    /// 前三欄仍合法 → 被解析成正常記錄，`write-error` 就永遠不會出現在 problems 裡
    static func errorLine(errno code: Int32) -> String {
        "\n#error\terrno=\(code)\n"
    }

    /// 從 `offset` 起讀到最後一個完整行。序號連續性只在本次讀到的記錄之間檢查
    static func read(path: String, fromOffset offset: UInt64) throws -> Snapshot {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else {
            return Snapshot(header: nil, records: [], problems: [], endOffset: offset)
        }
        let complete = data[data.startIndex...lastNewline]
        var parser = Parser()
        for line in complete.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).dropLast() {
            parser.consume(Data(line))
        }
        return Snapshot(
            header: parser.header, records: parser.records, problems: parser.problems,
            endOffset: offset + UInt64(complete.count)
        )
    }

    private struct Parser {
        var header: Header?
        var records: [Record] = []
        var problems: [String] = []

        mutating func consume(_ line: Data) {
            guard !line.contains(0) else {
                problems.append("nul")
                return
            }
            let fields = String(decoding: line, as: UTF8.self).components(separatedBy: "\t")
            switch fields.first {
            case "#header": header = Self.header(from: fields)
            case "#error": problems.append("write-error:\(fields.dropFirst().joined(separator: " "))")
            default: consumeRecord(fields)
            }
        }

        private mutating func consumeRecord(_ fields: [String]) {
            guard fields.count >= 4, let sequence = Int(fields[0]), let micros = Int64(fields[1]),
                  let kind = Kind(rawValue: fields[2])
            else {
                problems.append("malformed:\(fields.joined(separator: " "))")
                return
            }
            if let previous = records.last {
                if sequence != previous.sequence + 1 { problems.append("gap:\(previous.sequence)->\(sequence)") }
                if micros < previous.microseconds { problems.append("time:\(previous.microseconds)->\(micros)") }
            }
            records.append(Record(
                sequence: sequence, microseconds: micros, kind: kind,
                payload: fields[3...].joined(separator: " ")
            ))
        }

        private static func header(from fields: [String]) -> Header? {
            var values: [String: String] = [:]
            for field in fields.dropFirst() {
                let parts = field.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { values[parts[0]] = parts[1] }
            }
            guard let pid = values["pid"].flatMap(Int32.init), let bundle = values["bundle"],
                  let size = values["exe-size"].flatMap(Int64.init),
                  let modified = values["exe-mtime"].flatMap(Int64.init)
            else { return nil }
            return Header(pid: pid, bundlePath: bundle, executableSize: size, executableModified: modified)
        }
    }
}
#endif
