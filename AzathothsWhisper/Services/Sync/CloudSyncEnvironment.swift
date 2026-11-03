import Foundation

/// 正式時鐘：單調時間＋可取消的 sleep
struct SystemSyncClock: MonotonicClock, PollClock {
    var now: TimeInterval { SystemMonotonicClock().now }

    func sleep(for interval: Duration) async throws {
        try await Task.sleep(for: interval)
    }
}

/// iCloud 同步的外部邊界（⑨ 計劃 §6.7）：位置、硬體身分、鎖、下載狀態、時鐘。測試注入暫存資料夾與替身
struct CloudSyncEnvironment: Sendable {
    let root: URL
    let hardware: any HardwareIdentity
    let lockURL: URL?
    let downloads: any SyncDownloadProbing
    let clock: any MonotonicClock & PollClock
    let readDeadline: any PollClock
    let wallClock: @Sendable () -> Date
    let appVersion: String

    static func live() -> CloudSyncEnvironment {
        CloudSyncEnvironment(
            root: SyncFolder.defaultRoot, hardware: IOKitHardwareIdentity(), lockURL: SyncLock.defaultURL,
            downloads: UbiquitousDownloadProbe(), clock: SystemSyncClock(), readDeadline: SystemPollClock(),
            wallClock: { Date() }, appVersion: AppInfo.version
        )
    }
}
