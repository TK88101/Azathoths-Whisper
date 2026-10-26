import Foundation
import SpikeCore

// 整個 yse-spike 唯一寫檔的地方（spike_gate.sh 限定）：只寫進 S0_RESULTS_DIR，檔名由 ResultPath 組出。
enum ResultWriter {
    enum Failure: Error, CustomStringConvertible {
        case missingDirectory
        case createFailed(String)

        var description: String {
            switch self {
            case .missingDirectory: "S0_RESULTS_DIR 未設定"
            case .createFailed(let path): "無法建立 \(path)"
            }
        }
    }

    static var directory: String? {
        guard let value = ProcessInfo.processInfo.environment["S0_RESULTS_DIR"], !value.isEmpty else { return nil }
        return value
    }

    static func save<Record: Encodable>(experiment: String, records: [Record]) throws -> URL {
        guard let directory else { throw Failure.missingDirectory }
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        var url = try ResultPath.make(directory: base, experiment: experiment, at: Date())
        // 檔名精度到秒：同一秒已有同名檔就等到下一秒，絕不覆蓋既有紀錄
        while FileManager.default.fileExists(atPath: url.path) {
            Thread.sleep(forTimeInterval: 0.25)
            url = try ResultPath.make(directory: base, experiment: experiment, at: Date())
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var body = Data()
        for record in records {
            body.append(try encoder.encode(record))
            body.append(0x0A)
        }
        guard FileManager.default.createFile(atPath: url.path, contents: body) else {
            throw Failure.createFailed(url.path)
        }
        return url
    }
}
