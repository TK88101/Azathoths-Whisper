#if DEBUG
import Foundation

/// Documents/metrics（Debug 開了 UIFileSharingEnabled，Finder 看得到）
enum MetricsFile {
    static func write(_ data: Data?, name: String) {
        guard let data else { return }
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("metrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        try? data.write(to: base.appendingPathComponent("\(name)-\(stamp).json"), options: .atomic)
    }
}
#endif
