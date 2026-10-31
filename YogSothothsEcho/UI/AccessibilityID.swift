// a11y identifier 與 UI 測試旗標的單一來源（app 與 UITests 同編）
enum AccessibilityID {
    static let shellOrientation = "shell.orientation"
    static let appearancePicker = "appearance.picker"
    /// F10：頂列背景選單（CR-022 E.2）
    static let backgroundMenu = "background.menu"
    /// CR-023：左上設定鈕與設定頁
    static let settingsButton = "settings.button"
    /// CR-024：底部左鍵（側封↔小圖）
    static let browseLayoutButton = "browse.layoutButton"
    static let settingsForget = "settings.forget"
    static let settingsForgetConfirm = "settings.forgetConfirm"
    static let settingsDone = "settings.done"
    /// 頂部狀態膠囊
    static let libraryStatus = "library.status"
    /// 只在 DEBUG：玻璃強制走 material 退路
    static let forceMaterialGlassArgument = "-YSEForceMaterialGlass"
    /// 只在 DEBUG：啟動 15 秒後自動 Forget this Mac（CR-023 後詳情開著時拿不到設定鈕，UI 測試以此模擬「詳情中忘記 Mac」）
    static let forgetAfterDelayArgument = "-YSEUITestForgetAfterDelay"
    /// 只在 DEBUG：假 Mac 名稱改成 40 字元（頂列不重疊的版面驗證，E.2）
    static let longMacNameArgument = "-YSEUITestLongMacName"
    /// 只在 DEBUG 生效：啟動時清掉設定，讓 UI 測試從乾淨狀態開始
    static let resetSettingsArgument = "-YSEUITestResetSettings"
    /// UI 測試：清掉位置記憶（CR-027 起前一條測試停下的位置會存檔，影響下一條「從第一張開始」的假設）
    static let resetPositionArgument = "-YSEUITestResetPosition"
    static let connectionState = "connection.state"
    static let pairingSuffix = "connection.pairingSuffix"
    /// S6.5：連線頁左欄的品牌標題區（UI 測試量版面）
    static let pairingHeader = "connection.pairingHeader"
    static let scanAgainButton = "connection.scanAgain"
    static let openSettingsButton = "connection.openSettings"
    static let librarySearch = "library.search"
    static let libraryGrid = "library.grid"
    static let libraryNoResults = "library.noResults"
    static let libraryUnavailable = "library.unavailable"
    static let libraryFirstScreen = "library.firstScreenSeconds"
    static let libraryCount = "library.count"
    // S4 播放
    static let nowPlayingBar = "nowPlaying.bar"
    static let nowPlayingTitle = "nowPlaying.title"
    static let nowPlayingToggle = "nowPlaying.toggle"
    static let nowPlayingNext = "nowPlaying.next"
    /// CR-030：寬膠囊 ◀◀ 前的 Genius 鈕
    static let nowPlayingGenius = "nowPlaying.genius"
    static let nowPlayingPrevious = "nowPlaying.previous"
    static let nowPlayingNotice = "nowPlaying.notice"
    static let albumTracksList = "albumTracks.list"
    static let albumTracksNotice = "albumTracks.notice"
    static let albumTracksClose = "albumTracks.close"
    static func albumTracksRow(_ number: Int) -> String { "albumTracks.row.\(number)" }
    static func libraryAlbum(_ id: String) -> String { "library.album.\(id)" }
    /// UI 測試旗標（與 App/UITestSupport.swift 同值；UITests 只編本檔）
    static let fakeRemoteArgument = "-YSEUITestFakeRemote"
    static let cameraDeniedArgument = "-YSEUITestCameraDenied"
    static let fakePayloadArgument = "-YSEFakePairingPayload"
    /// 合成播放的點歌結果改為降級（Mac 缺少捷徑）／不確定
    static let playDegradedArgument = "-YSEUITestPlayDegraded"
    static let playUncertainArgument = "-YSEUITestPlayUncertain"
    /// 合成播放一開始回報 Music 未開／未允許控制，數秒後恢復
    static let musicNotRunningArgument = "-YSEUITestMusicNotRunning"
    static let musicDeniedArgument = "-YSEUITestMusicDenied"
    /// 合成器的事件：Genius 未授權／舊 Mac（不帶 genius）；預設 ready
    static let geniusNeedsAccessibilityArgument = "-YSEUITestGeniusNeedsAccessibility"
    static let geniusLegacyMacArgument = "-YSEUITestGeniusLegacyMac"
    static let nowPlayingRetry = "nowPlaying.retry"
    /// S5 唱機畫面
    static let nowPlayingOpenTurntable = "nowPlaying.openTurntable"
    static let turntable = "turntable"
    static let turntableRecord = "turntable.record"
    static let turntableArm = "turntable.arm"
    static let turntableClose = "turntable.close"
    /// DEBUG 調整面板（v2.1 T8）：磨砂盤主色濃淡、霧濃淡
    static let turntableTuningTint = "turntable.tuning.tint"
    static let turntableTuningHaze = "turntable.tuning.haze"
    static let turntableTuningOtherTint = "turntable.tuning.otherTint"
    static let turntableTuningOtherHaze = "turntable.tuning.otherHaze"
    static let turntableNotice = "turntable.notice"
    static func turntableStyle(_ raw: String) -> String { "turntable.style.\(raw)" }
    /// CR-037 煙渦第二排的五個選項（SmokeVariantChoice 的 rawValue）
    static func turntableSmokeVariant(_ raw: String) -> String { "turntable.smokeVariant.\(raw)" }
    /// CR-034 唱機皮膚切換（皮膚 id）：選擇器的格子
    static func turntableSkin(_ id: String) -> String { "turntable.skin.\(id)" }
    /// CR-034 增補 A：唱機浮層開選擇器的圓鈕、設定頁「唱機外觀」那一列
    static let turntableSkinButton = "turntable.skinButton"
    static let settingsTurntableSkin = "settings.turntableSkin"
    /// 合成播放器一開始就在播；連上後自動開唱機（只在 DEBUG 有作用）
    static let nowPlayingArgument = "-YSEUITestNowPlaying"
    static let openTurntableArgument = "-YSEUITestOpenTurntable"
    /// S6 §4.9：XCUITest 走 Reduce Motion 分支（系統設定測試動不到）
    static let forceReduceMotionArgument = "-YSEForceReduceMotion"
}
