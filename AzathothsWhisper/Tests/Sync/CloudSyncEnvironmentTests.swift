import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.7：正式組裝的位置與時鐘（只看設定值，不讀寫 iCloud）
@Suite("Cloud sync environment")
struct CloudSyncEnvironmentTests {
    @Test func theLiveAssemblyPointsAtICloudDriveAndTheLocalLock() {
        let environment = CloudSyncEnvironment.live()
        #expect(environment.root.path.hasSuffix("Library/Mobile Documents/com~apple~CloudDocs/Azathoth's Whisper"))
        #expect(environment.lockURL?.path.hasSuffix("Library/Application Support/com.ibridgezhao.azathothswhisper/sync.lock") == true)
        #expect(environment.appVersion == AppInfo.version)
        #expect(abs(environment.wallClock().timeIntervalSinceNow) < 5)
    }

    @Test func theSystemClockMovesForwardAndSleeps() async throws {
        let clock = SystemSyncClock()
        let before = clock.now
        try await clock.sleep(for: .milliseconds(5))
        #expect(clock.now > before)
    }
}
