// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import Foundation

extension AppModel {
    /// H-02 UI 測試閘門的組裝（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.1）。
    ///
    /// 真實 RootView／AppModel／NowPlayingMonitor／CoverFlowViewModel／ArtworkService，**只換 Music**。
    /// - secret：`EphemeralSecretStore`，且不跑 legacy 遷移——不碰 Keychain（M6 A1 的授權框阻塞），token 恆空，
    ///   截圖裡沒有憑證可洩
    /// - 封面：純記憶體（不寫使用者 Caches，也不會有上一次運行留下的磁碟命中）
    /// - 旗標未設 → nil，走正常的 `live()` 路徑
    static func makeCoverFlowUITestModelIfRequested(environment: [String: String]) -> AppModel? {
        guard CoverFlowUITestFixture.isEnabled(in: environment) else { return nil }
        // 軌跡旁路只在這裡安裝一次（行程級單例）；未給路徑即不記錄
        CoverFlowUITestTrace.installIfRequested(environment: environment)
        let store = ConfigStore(secrets: EphemeralSecretStore())
        let delay = CoverFlowUITestFixture.albumDelayMilliseconds(in: environment)
        let music = CoverFlowUITestMusic(albumDelay: .milliseconds(delay))
        let client = URLSessionHTTPClient()
        return AppModel(
            configStore: store,
            httpClient: client,
            music: music,
            monitor: NowPlayingMonitor(music: music),
            validator: GeniusTokenValidator(client: client),
            initialToken: "",
            initialLanguage: store.language,
            artworkDiskDirectory: nil
        )
    }
}
#endif
