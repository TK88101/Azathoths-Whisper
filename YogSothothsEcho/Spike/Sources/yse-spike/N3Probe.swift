import Darwin
import Foundation
import iTunesLibrary
import SpikeCore

// N3：ITLibrary 讀整個曲庫並建「專輯 → 曲目」索引的耗時與記憶體（sprint-0-detail.md §4.3 n3）。
// 唯讀；只記數量，不記曲名。第一次執行可能跳「媒體與 Apple Music」授權框，故排在使用者在場時跑（#0-1）。
enum N3Probe {
    struct Record: Encodable {
        let experiment = "n3"
        let result: N3Result?
        let meetsExpectation: Bool?
        let error: String?
    }

    static func run() -> Record {
        let before = footprintMB()
        let started = ContinuousClock.now
        let library: ITLibrary
        do {
            library = try ITLibrary(apiVersion: "1.0")
        } catch {
            return Record(result: nil, meetsExpectation: nil, error: "\(type(of: error)) \((error as NSError).code)")
        }
        var tracksByAlbum: [NSNumber: [NSNumber]] = [:]
        var locationKinds: [String: Int] = [:]
        var songCount = 0
        for item in library.allMediaItems where item.mediaKind == .kindSong {
            songCount += 1
            tracksByAlbum[item.album.persistentID, default: []].append(item.persistentID)
            locationKinds[locationName(item.locationType), default: 0] += 1
        }
        let elapsed = ContinuousClock.now - started
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let result = N3Result(seconds: seconds, footprintDeltaMB: footprintMB() - before, songCount: songCount,
                              albumCount: tracksByAlbum.count, locationKinds: locationKinds)
        return Record(result: result, meetsExpectation: result.meetsExpectation, error: nil)
    }

    private static func locationName(_ type: ITLibMediaItemLocationType) -> String {
        switch type {
        case .file: "file"
        case .URL: "url"
        case .remote: "remote"
        case .unknown: "unknown"
        @unknown default: "other"
        }
    }

    /// 程序的 phys_footprint（MB）
    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return .nan }
        return Double(info.phys_footprint) / 1_048_576
    }
}
