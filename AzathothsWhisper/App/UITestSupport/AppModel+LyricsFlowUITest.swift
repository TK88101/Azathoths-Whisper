// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import Foundation

extension AppModel {
    /// 「Cover Flow × 找歌詞」UI 測試的組裝（計劃 Q3.5）。場景 env 未設或不認得 → nil，走正常的 `live()`。
    ///
    /// 真實 RootView／AppModel／monitor／LyricsFlowModel／CoverFlowViewModel，只換掉：
    /// - Music：`LyricsFlowUITestMusic`（不送 AE、`setLyrics` 只寫記憶體）
    /// - HTTP：恆 404（自動抓詞不上網）；batchImport 例外：DarkLyrics 直連專輯頁回替身頁（見 `LyricsFlowUITestLyricsPage`）
    /// - 設定：測試專屬 suite（**從不碰使用者的 `.standard`**，D4）；secret 走 `EphemeralSecretStore`，不碰 Keychain
    /// - Queue.dat／History.dat：app 暫存目錄裡的假檔；Music 一律視為執行中
    static func makeLyricsFlowUITestModelIfRequested(environment: [String: String]) -> AppModel? {
        typealias Scenario = LyricsFlowUITestScenario
        guard let scenario = Scenario.requested(in: environment) else { return nil }
        if environment[Scenario.resetDefaultsVariable] == "1" {
            UserDefaults().removePersistentDomain(forName: Scenario.defaultsSuiteName)
        }
        guard let defaults = UserDefaults(suiteName: Scenario.defaultsSuiteName) else { return nil }
        let store = ConfigStore(secrets: EphemeralSecretStore(), defaults: defaults)

        var seeds = (environment[Scenario.seedMarksVariable] ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        if scenario == .marked {
            seeds.append(Scenario.persistentID(at: Scenario.playingIndex))
        }
        seeds.forEach { store.markNoLyrics($0) }

        let music = LyricsFlowUITestMusic(scenario: scenario)
        let client = UITestStubHTTPClient(pages: scenario == .batchImport ? LyricsFlowUITestLyricsPage.pages : [:])
        return AppModel(
            configStore: store,
            httpClient: client,
            music: music,
            monitor: NowPlayingMonitor(music: music),
            validator: GeniusTokenValidator(client: client),
            initialToken: "",
            initialLanguage: store.language,
            artworkDiskDirectory: nil,
            // 假檔寫不出來就退回「觀察到的歷史」模式（右側標明讀不到），不讓測試組裝本身崩潰
            queueDirectory: try? LyricsFlowUITestQueueFiles.write(),
            isMusicRunning: { true }
        )
    }
}
#endif
