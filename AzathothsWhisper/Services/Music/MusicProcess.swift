import AppKit

/// Music 是否在執行（D15）。只問 LaunchServices、**不送 AE**——送 AE 會把沒開的 Music 啟動起來（AC13）
enum MusicProcess {
    static let bundleIdentifier = "com.apple.Music"

    static func isRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains { !$0.isTerminated }
    }
}
