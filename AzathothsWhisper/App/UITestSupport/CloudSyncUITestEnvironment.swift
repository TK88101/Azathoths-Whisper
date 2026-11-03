#if DEBUG
import Foundation

/// ⑨ iCloud 同步的 UI 測試組裝：根目錄由測試指定（臨時資料夾）、固定硬體身分、不上鎖。整檔只在 DEBUG
extension CloudSyncEnvironment {
    private struct UITestHardware: HardwareIdentity {
        func platformUUID() throws(SyncWriterID.Failure) -> String { "00000000-0000-4000-8000-0000000000AA" }
    }

    static func uiTest(environment: [String: String]) -> CloudSyncEnvironment? {
        guard let path = environment[LyricsFlowUITestScenario.cloudSyncRootVariable], !path.isEmpty else { return nil }
        return CloudSyncEnvironment(
            root: URL(fileURLWithPath: path), hardware: UITestHardware(), lockURL: nil, downloads: UbiquitousDownloadProbe(),
            clock: SystemSyncClock(), readDeadline: SystemPollClock(), wallClock: { Date() }, appVersion: AppInfo.version
        )
    }
}
#endif
