import Foundation

// 舊版 .env 讀取（僅遷移期使用）。
// 對齊 lyrics_fetcher.py:910-931 的三級 fallback 路徑順序，以及 python-dotenv 的基本行格式。
enum DotEnv {
    /// 依序回傳候選 .env 路徑（存在與否由呼叫方判斷）。
    /// py 的順序：腳本目錄 → （frozen 時）可執行檔目錄 → ~/Documents/Bjork/.env
    static func candidatePaths(
        bundleURL: URL = Bundle.main.bundleURL,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            bundleURL.deletingLastPathComponent().appendingPathComponent(".env"),
            bundleURL.appendingPathComponent("Contents/MacOS/.env"),
            homeURL.appendingPathComponent("Documents/Bjork/.env"),
        ]
    }

    /// 解析 KEY=VALUE 行；忽略空行與 # 註釋，去除成對引號。
    static func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2 {
                let first = value.first!
                if (first == "\"" || first == "'") && value.last == first {
                    value = String(value.dropFirst().dropLast())
                }
            }
            result[key] = value
        }
        return result
    }

    /// 讀第一個存在的候選檔並解析；全部不存在回空字典。
    static func loadFirstAvailable(
        paths: [URL],
        fileManager: FileManager = .default
    ) -> [String: String] {
        for path in paths where fileManager.fileExists(atPath: path.path) {
            guard let contents = try? String(contentsOf: path, encoding: .utf8) else { continue }
            return parse(contents)
        }
        return [:]
    }
}
