import Foundation

/// Music 的換歌／播放狀態變化訊號（計劃 2026-09-27-coverflow-f1-f2 §3.1）。
///
/// **只傳「變了」，不帶內容**：當前曲一律由 `NowPlayingMonitor` 經 AE 讀取（單一資料來源），
/// 通知的 userInfo 在此丟棄——兩個來源會在歌詞、暫停狀態、AE 失敗時分歧（Codex R1 ④）
@MainActor
protocol PlayerChangeSignaling: AnyObject {
    /// 冪等：已在監聽時再呼叫不重複註冊
    func start(onChange: @escaping @MainActor () -> Void)
    func stop()
}

/// 生產實作：`DistributedNotificationCenter` 的 `com.apple.Music.playerInfo`。只收不發
@MainActor
final class MusicPlayerInfoSignal: PlayerChangeSignaling {
    static let musicPlayerInfo = Notification.Name("com.apple.Music.playerInfo")

    private let name: Notification.Name
    private var observer: (any NSObjectProtocol)?
    /// stop 時遞增：已排進主佇列、晚於 stop 才執行的 block 因世代不符而丟棄
    private var generation = 0
    private var onChange: (@MainActor () -> Void)?

    /// `name` 只給測試換成專屬名稱：測試絕不 post Music 的通知名
    init(name: Notification.Name = MusicPlayerInfoSignal.musicPlayerInfo) {
        self.name = name
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        guard observer == nil else { return }
        self.onChange = onChange
        let current = generation
        observer = DistributedNotificationCenter.default().addObserver(
            forName: name, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliver(generation: current) }
        }
    }

    func stop() {
        generation += 1
        onChange = nil
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
    }

    private func deliver(generation delivered: Int) {
        guard delivered == generation else { return }
        onChange?()
    }
}

/// 單元測試 host 與 UI 測試組裝用：不監聽使用者機上的 Music
@MainActor
final class NoopPlayerChangeSignal: PlayerChangeSignaling {
    func start(onChange: @escaping @MainActor () -> Void) {}
    func stop() {}
}
