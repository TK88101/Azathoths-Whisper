import Foundation
import SpikeCore

// 崩潰或還原失敗後的處理（sprint-0-detail.md §4.4）：
// 最新的 snapshot 比最新的 restore 新（上次沒走到還原），或最新的 restore 記著未還原項目＝待還原，
// 此時停止一切實驗，只准 `recover`。檔名含 UTC 時間（ResultPath），字典序即時間序。
enum Recovery {
    static func pendingSnapshot() -> MusicSnapshot? {
        guard let directory = ResultWriter.directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory),
              let snapshotName = names.filter({ $0.hasPrefix("snapshot-") }).max(),
              let snapshot: MusicSnapshot = firstRecord(directory, snapshotName)
        else { return nil }
        guard let restoreName = names.filter({ $0.hasPrefix("restore-") }).max(),
              restoreName.dropFirst("restore-".count) >= snapshotName.dropFirst("snapshot-".count),
              let restore: RestoreRecord = firstRecord(directory, restoreName),
              restore.unrestored.isEmpty
        else { return snapshot }
        return nil
    }

    static func firstRecord<Record: Decodable>(_ directory: String, _ name: String) -> Record? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent(name)),
              let line = data.split(separator: 0x0A).first
        else { return nil }
        return try? JSONDecoder().decode(Record.self, from: Data(line))
    }

    static func latestRecord<Record: Decodable>(prefix: String) -> Record? {
        guard let directory = ResultWriter.directory,
              let name = (try? FileManager.default.contentsOfDirectory(atPath: directory))?
                .filter({ $0.hasPrefix(prefix) }).max()
        else { return nil }
        return firstRecord(directory, name)
    }
}
