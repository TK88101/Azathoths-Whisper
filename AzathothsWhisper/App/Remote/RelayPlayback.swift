import AppKit
import Foundation
import MusicRemoteBridge
import RemoteProtocol

// 播放控制的接線（sprint-4-detail.md §4.2、§4.7、§4.10）。RelayHost 以已連線 iPad 數 0↔1 開關狀態輪詢
// （與曲庫重建同一條順序鏈），伺服端起來後接上連線存活與推送、停止時拆下。
// 中繼關閉或無連線時不送任何 Apple Event、不跑捷徑、不讀 Queue.dat（D13）。

/// RelayHost 看到的播放邊界（protocol＋替身）
protocol RelayPlayback: AnyObject, Sendable {
    /// 已連線 iPad 數 0→1
    func startWatching() async
    /// 已連線 iPad 數 1→0
    func stopWatching() async
    /// 其他新連線（含同 peer 取代舊連線）：把目前狀態再推一次
    func connectionAdded() async
    /// nil＝伺服端停止
    func setOutlets(_ outlets: PlaybackOutlets?)
    /// 已存過綁定的識別碼（只讀偏好設定，不跑任何指令）
    var hasStoredShortcut: Bool { get }
    /// 設定頁「重新檢查」：清快取後跑一次 `shortcuts list`；true＝綁定的捷徑還在
    func checkShortcut() async -> Bool
    /// 設定頁「安裝捷徑」（§4.6 安裝契約）
    func installShortcut(progress: @escaping @Sendable (ShortcutInstaller.Phase) -> Void) async -> ShortcutInstaller.Outcome
}

final class LiveRelayPlayback: RelayPlayback {
    /// 捷徑的檢查與安裝（正式組裝才有；D13 測試只組 service）
    struct Shortcuts: Sendable {
        let store: any ShortcutBindingStore
        let binding: ShortcutBinding
        let installer: ShortcutInstaller
    }

    let service: PlaybackService
    private let shortcuts: Shortcuts?

    init(service: PlaybackService, shortcuts: Shortcuts? = nil) {
        self.service = service
        self.shortcuts = shortcuts
    }

    /// 正式組裝：所有元件共用同一個時鐘實例（sampledAt 可比）
    static func make(catalog: CatalogService) -> LiveRelayPlayback {
        let clock = SystemControlClock()
        let runner = ShortcutRunner()
        runner.sweep()   // 上次異常結束留下的捷徑暫存檔（只在自己的暫存目錄內）
        let store = UserDefaultsShortcutBindingStore()
        let binding = ShortcutBinding(store: store, lister: runner, clock: clock)
        let installer = ShortcutInstaller(signer: runner, binding: binding, open: openInShortcutsApp, starter: runner, clock: clock)
        return LiveRelayPlayback(
            service: PlaybackService(music: MusicLane(), plans: catalog, albumOf: { await catalog.albumID(ofTrack: $0) },
                                     binding: binding, starter: runner,
                                     queueReader: RelayQueueReader(directory: QueueFileSource.defaultDirectory), clock: clock),
            shortcuts: Shortcuts(store: store, binding: binding, installer: installer))
    }

    static let shortcutsAppBundleID = "com.apple.shortcuts"

    /// §4.6 步驟 3：只開簽好的檔（型別只有 ShortcutRunner.sign 能造）、只交給「捷徑」App
    @MainActor
    private static func openInShortcutsApp(_ signed: SignedShortcut) async -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: shortcutsAppBundleID) else { return false }
        return (try? await NSWorkspace.shared.open([signed.url], withApplicationAt: app,
                                                   configuration: NSWorkspace.OpenConfiguration())) != nil
    }

    func startWatching() async { await service.startWatching() }
    func stopWatching() async { await service.stopWatching() }
    func connectionAdded() async { await service.connectionAdded() }
    func setOutlets(_ outlets: PlaybackOutlets?) { service.setOutlets(outlets) }

    var hasStoredShortcut: Bool { shortcuts?.store.load() != nil }

    func checkShortcut() async -> Bool {
        guard let shortcuts else { return false }
        await shortcuts.binding.invalidate()
        return await shortcuts.binding.status() != .missing
    }

    func installShortcut(progress: @escaping @Sendable (ShortcutInstaller.Phase) -> Void) async -> ShortcutInstaller.Outcome {
        guard let shortcuts else { return .listUnavailable }
        return await shortcuts.installer.install(progress: progress)
    }
}

/// 單元／UI 測試與預設：什麼都不做、不碰 Music、不跑捷徑
final class InertRelayPlayback: RelayPlayback {
    func startWatching() async {}
    func stopWatching() async {}
    func connectionAdded() async {}
    func setOutlets(_ outlets: PlaybackOutlets?) {}
    var hasStoredShortcut: Bool { false }
    func checkShortcut() async -> Bool { false }
    func installShortcut(progress: @escaping @Sendable (ShortcutInstaller.Phase) -> Void) async -> ShortcutInstaller.Outcome {
        .listUnavailable
    }
}
