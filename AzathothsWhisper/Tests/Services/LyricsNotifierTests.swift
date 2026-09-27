import Foundation
import Testing
import UserNotifications

@testable import AzathothsWhisper

/// 記錄送進通知中心的請求；completion 同步回呼，可注入 add 失敗
final class SpyNotificationCenter: NotificationCenterClient, @unchecked Sendable {
    private(set) var requests: [UNNotificationRequest] = []
    private(set) var authorizationOptions: [UNAuthorizationOptions] = []
    var addError: (any Error)?

    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        authorizationOptions.append(options)
        completion(true, nil)
    }

    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable ((any Error)?) -> Void) {
        requests.append(request)
        completion(addError)
    }
}

// 計劃 §4.1（R1-8／R1-13）：系統通知層只做轉送；失敗只記 log，不回拋、不影響呼叫端
@MainActor
@Suite("SystemLyricsNotifier")
struct LyricsNotifierTests {
    private let payload = NotificationPayload(
        title: "阿撒托斯的低語", subtitle: "Opeth · 《Blackwater Park》",
        body: "「Bleak」歌詞寫入成功", threadID: "Blackwater Park"
    )

    @Test func postBuildsAnImmediateRequestFromThePayload() throws {
        let center = SpyNotificationCenter()
        let notifier = SystemLyricsNotifier(center: center)

        notifier.post(payload)

        let request = try #require(center.requests.first)
        #expect(center.requests.count == 1)
        #expect(request.content.title == payload.title)
        #expect(request.content.subtitle == payload.subtitle)
        #expect(request.content.body == payload.body)
        #expect(request.content.threadIdentifier == "Blackwater Park")
        #expect(request.trigger == nil, "立即送出")
    }

    // 每則通知各自一個 identifier，不會互相覆蓋
    @Test func eachPostUsesItsOwnIdentifier() {
        let center = SpyNotificationCenter()
        let notifier = SystemLyricsNotifier(center: center)

        notifier.post(payload)
        notifier.post(payload)

        #expect(Set(center.requests.map(\.identifier)).count == 2)
    }

    @Test func missingThreadLeavesThreadIdentifierEmpty() throws {
        let center = SpyNotificationCenter()
        SystemLyricsNotifier(center: center).post(
            NotificationPayload(title: "t", subtitle: "s", body: "b", threadID: nil)
        )
        #expect(try #require(center.requests.first).content.threadIdentifier == "")
    }

    // 送達失敗被吞：之後照樣能送
    @Test func addFailureIsSwallowed() {
        let center = SpyNotificationCenter()
        center.addError = NSError(domain: UNErrorDomain, code: 1)
        let notifier = SystemLyricsNotifier(center: center)

        notifier.post(payload)
        center.addError = nil
        notifier.post(payload)

        #expect(center.requests.count == 2)
    }

    // 不要聲音，避免打擾（§2）
    @Test func authorizationAsksForAlertsOnly() {
        let center = SpyNotificationCenter()
        SystemLyricsNotifier(center: center).requestAuthorization()
        #expect(center.authorizationOptions == [.alert])
    }

    // App 在前景時系統預設不顯示橫幅；Editor 寫入時使用者一定在 App 裡
    @Test func foregroundPresentationShowsBannerAndList() {
        #expect(ForegroundPresenter.options == [.banner, .list])
    }
}
