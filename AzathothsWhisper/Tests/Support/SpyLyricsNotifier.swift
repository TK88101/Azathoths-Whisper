import Foundation

@testable import AzathothsWhisper

/// 記錄 AppModel 送出的通知與授權請求（計劃 2026-09-26-lyrics-notification §4.5：AppModelTests 注入 Spy）
@MainActor
final class SpyLyricsNotifier: LyricsNotifying {
    private(set) var posted: [NotificationPayload] = []
    private(set) var authorizationRequests = 0

    func requestAuthorization() {
        authorizationRequests += 1
    }

    func post(_ payload: NotificationPayload) {
        posted.append(payload)
    }
}
