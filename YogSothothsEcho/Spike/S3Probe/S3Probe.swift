import AppKit
import CryptoKit
import Foundation
import ImageIO
import iTunesLibrary
import UniformTypeIdentifiers

// S3-P1 探針（sprint-3-detail.md §4.1）：在 app 程序內讀 ITLibrary。唯讀；只記數量、耗時、錯誤代碼，
// 不記曲名、專輯名、藝人（N-05）。不進產品。
// 用法：open S3Probe.app --args <load|retry> <結果目錄>

struct Report: Encodable {
    var mode: String
    var bundleID: String
    var hasUsageDescription: Bool
    var events: [Event] = []
    struct Event: Encodable { let t: Double; let step: String; let detail: [String: String] }
}

final class Probe: @unchecked Sendable {
    let queue = DispatchQueue(label: "s3probe.library")   // ITLibrary 只在這條序列上用（P1-a：非主執行緒）
    let out: URL
    let started = Date()
    var report: Report

    init(mode: String, out: URL) {
        self.out = out
        let info = Bundle.main.infoDictionary ?? [:]
        report = Report(mode: mode, bundleID: Bundle.main.bundleIdentifier ?? "-",
                        hasUsageDescription: info["NSAppleMusicUsageDescription"] != nil)
    }

    func log(_ step: String, _ detail: [String: String] = [:]) {
        report.events.append(.init(t: Date().timeIntervalSince(started), step: step, detail: detail))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(report).write(to: out.appendingPathComponent("s3p1-\(report.mode)-\(report.bundleID).json"))
    }

    func open() -> ITLibrary? {
        do {
            let library = try ITLibrary(apiVersion: "1.0")
            log("init.ok", ["mainThread": "\(Thread.isMainThread)"])
            return library
        } catch {
            let ns = error as NSError
            log("init.fail", ["domain": ns.domain, "code": "\(ns.code)", "type": "\(type(of: error))"])
            return nil
        }
    }

    func runLoad() {
        queue.async {
            self.log("start")
            let t0 = Date()
            guard let library = self.open() else { return self.finish() }
            self.log("init.seconds", ["value": String(format: "%.3f", Date().timeIntervalSince(t0))])
            let first = self.snapshot(library)
            self.log("snapshot1", first.counts)
            // 第 1 輪實測每次 reload 記憶體 +45 MB：背景序列上沒有排空 autorelease pool。每輪包 autoreleasepool 驗證
            for i in 1...4 {
                autoreleasepool {
                    let t = Date()
                    let ok = library.reloadData()
                    let snap = self.snapshot(library)
                    self.log("reload\(i)", ["ok": "\(ok)", "seconds": String(format: "%.3f", Date().timeIntervalSince(t)),
                                            "sameHash": "\(snap.hash == first.hash)", "footprintMB": Self.footprint()])
                }
            }
            self.artwork(first)
            self.finish()
        }
    }

    func runRetry() {
        queue.async {
            self.log("start")
            for attempt in 1...36 {   // 每 5 秒一次、最多 3 分鐘：使用者在系統設定改回允許時，同一程序是否能成功
                if let library = self.open() {
                    self.log("retry.ok", ["attempt": "\(attempt)", "items": "\(library.allMediaItems.count)"])
                    return self.finish()
                }
                Thread.sleep(forTimeInterval: 5)
            }
            self.log("retry.gaveUp")
            self.finish()
        }
    }

    struct Snapshot { let counts: [String: String]; let hash: String; let reps: [ITLibMediaItem] }

    func snapshot(_ library: ITLibrary) -> Snapshot {
        var songs = 0, zeroAlbumID = 0
        var albums: [UInt64: [ITLibMediaItem]] = [:]
        var hasher = SHA256()
        for item in library.allMediaItems where item.mediaKind == .kindSong {
            songs += 1
            let albumID = item.album.persistentID.uint64Value
            if albumID == 0 { zeroAlbumID += 1; continue }
            albums[albumID, default: []].append(item)
            var fields = "\(item.persistentID)|\(albumID)|\(item.title)|\(item.album.title ?? "")|\(item.album.albumArtist ?? "")|"
            fields += "\(item.artist?.name ?? "")|\(item.trackNumber)|\(item.album.discNumber)|\(item.modifiedDate?.timeIntervalSince1970 ?? 0)"
            hasher.update(data: Data(fields.utf8))
        }
        let reps = albums.values.compactMap { $0.min { ($0.album.discNumber, $0.trackNumber) < ($1.album.discNumber, $1.trackNumber) } }
        let withArt = reps.filter(\.hasArtworkAvailable).count
        let notFile = reps.filter { $0.locationType != .file }.count
        let hash = hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
        return Snapshot(counts: ["songs": "\(songs)", "albums": "\(albums.count)", "zeroAlbumID": "\(zeroAlbumID)",
                                 "repsWithArtworkFlag": "\(withArt)", "repsNotFile": "\(notFile)", "footprintMB": Self.footprint()],
                        hash: hash, reps: reps)
    }

    /// P1-e／P1-f：取 50 張代表曲的封面，各縮三種尺寸；記耗時與位元組，不存圖
    func artwork(_ snap: Snapshot) {
        let sample = Array(snap.reps.filter(\.hasArtworkAvailable).prefix(50))
        var readable = 0, unreadableNotFile = 0, unreadableFile = 0
        var timings: [Int: [Double]] = [160: [], 600: [], 1600: []]
        var sizes: [Int: [Int]] = [160: [], 600: [], 1600: []]
        for item in sample {
            guard let data = item.artwork?.imageData, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                if item.locationType == .file { unreadableFile += 1 } else { unreadableNotFile += 1 }
                continue
            }
            readable += 1
            for px in [160, 600, 1600] {
                let t = Date()
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                kCGImageSourceThumbnailMaxPixelSize: px, kCGImageSourceCreateThumbnailWithTransform: true]
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { continue }
                let buffer = NSMutableData()
                guard let dest = CGImageDestinationCreateWithData(buffer, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
                CGImageDestinationFinalize(dest)
                timings[px]?.append(Date().timeIntervalSince(t) * 1000)
                sizes[px]?.append(buffer.length)
            }
        }
        var detail = ["sampled": "\(sample.count)", "readable": "\(readable)", "unreadableFile": "\(unreadableFile)",
                      "unreadableNotFile": "\(unreadableNotFile)"]
        for px in [160, 600, 1600] {
            let t = (timings[px] ?? []).sorted(), s = (sizes[px] ?? []).sorted()
            guard let tMax = t.last, let sMax = s.last else { continue }
            detail["ms\(px).p50"] = String(format: "%.1f", t[t.count / 2])
            detail["ms\(px).max"] = String(format: "%.1f", tMax)
            detail["bytes\(px).p50"] = "\(s[s.count / 2])"
            detail["bytes\(px).max"] = "\(sMax)"
        }
        log("artwork", detail)
    }

    func finish() {
        log("done")
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    static func footprint() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return status == KERN_SUCCESS ? String(format: "%.1f", Double(info.phys_footprint) / 1_048_576) : "nan"
    }
}

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "load"
let outDir = URL(fileURLWithPath: args.count > 2 ? args[2] : NSTemporaryDirectory())
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let probe = Probe(mode: mode, out: outDir)
if mode == "retry" { probe.runRetry() } else { probe.runLoad() }
app.run()
