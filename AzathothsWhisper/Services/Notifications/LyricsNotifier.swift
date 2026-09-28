import Foundation
import OSLog
import UserNotifications

/// 歌詞寫入通知的出口（計劃 2026-09-26-lyrics-notification §4.1）。
/// 通知失敗絕不影響寫入流程：兩個方法都不回拋、不等待結果。
@MainActor
protocol LyricsNotifying: AnyObject {
    func requestAuthorization()
    func post(_ payload: NotificationPayload)
}

/// `UNUserNotificationCenter` 的薄邊界：同步呼叫＋`@Sendable` completion，讓 Spy 能在測試裡取代它
protocol NotificationCenterClient: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping @Sendable (Bool, (any Error)?) -> Void)
    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable ((any Error)?) -> Void)
}

/// 日誌只記錯誤的 domain／code，不記曲名、歌詞（CLAUDE.md 日誌脫敏）
private let notificationLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "notification")

private func logFailure(_ operation: StaticString, _ error: any Error) {
    let nsError = error as NSError
    notificationLog.error("\(operation, privacy: .public) failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
}

/// App 在前景時系統預設不顯示橫幅；Editor 寫入時使用者一定在 App 裡，所以要明確要求橫幅。
/// 只處理前景送達，不碰 AppModel（點擊行為是計劃 §7 的非目標）
final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let options: UNNotificationPresentationOptions = [.banner, .list]

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.options
    }
}

/// 生產用的通知中心。delegate 在這裡設定即可（R1-1 裁決）：本次沒有「啟動時已送達、需要處理回應」的通知，
/// 第一則 post 只在使用者寫入歌詞之後。**日後若加通知點擊／啟動回應，delegate 必須移到 `applicationWillFinishLaunching`。**
final class SystemNotificationCenter: NotificationCenterClient {
    private let center = UNUserNotificationCenter.current()
    /// center.delegate 是 weak，這裡保留強參照
    private let presenter = ForegroundPresenter()

    init() {
        center.delegate = presenter
    }

    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        center.requestAuthorization(options: options, completionHandler: completion)
    }

    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable ((any Error)?) -> Void) {
        center.add(request, withCompletionHandler: completion)
    }
}

@MainActor
final class SystemLyricsNotifier: LyricsNotifying {
    private let center: any NotificationCenterClient

    init(center: any NotificationCenterClient) {
        self.center = center
    }

    /// 系統本身冪等：只在第一次詢問使用者，之後重複呼叫不再彈框（R1-7 裁決，不另設旗標）。
    /// 不要聲音，避免打擾（§2）
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert]) { _, error in
            if let error { logFailure("authorization", error) }
        }
    }

    /// 不緩衝、不等授權結果：系統未授權時由系統靜默丟棄
    func post(_ payload: NotificationPayload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.subtitle = payload.subtitle
        content.body = payload.body
        if let threadID = payload.threadID {
            content.threadIdentifier = threadID
        }
        // 每則各自一個 identifier：重用會覆蓋尚未顯示的上一則；trigger＝nil 表示立即送出
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { logFailure("post", error) }
        }
    }
}

#if DEBUG
/// 單元測試 host 與 UI 測試組裝使用：不碰真的通知中心，也不會跳權限框（比照 `EphemeralSecretStore`）
@MainActor
final class NoopLyricsNotifier: LyricsNotifying {
    func requestAuthorization() {}
    func post(_ payload: NotificationPayload) {}
}
#endif
