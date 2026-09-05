# ACCEPTANCE — Azathoth's Whisper 2.0 行為驗收對照總表

- 依據：`docs/plans/2026-08-09-swift-rewrite.md` §6；行為真源＝`lyrics_fetcher.py`（v1.2.4，行號以此為準）。
- 狀態圖例：`✅ 通過`／`⚠️ 偏差（附說明＋用戶簽字）`／`⬜ 未驗`。標「修正⚠️」的行＝計劃已批准的安全/兼容/數據修正，驗收時按新語義驗、簽字欄記錄偏差性質。
- M8 收口條件：全表無 ⬜ 且所有 ⚠️ 有簽字。
- 建表進度：G 段 M0 落檔；A–F/H 段 M1 落檔（本版）。
- M1 落地備註：①Material Symbols 子集打包順延至 M5（需字型子集化工具，屆時定案：申請 fonttools 或打包靜態字重）；②UITests target 順延至 M5（隨冒煙用例一起建）——兩項均不影響 M1 DoD 的骨架/測試/字型 demo 驗證。

## A 外殼與生命週期（12 條）

| ID | 行為描述 | 依據 | 驗證方式 | 狀態 |
|---|---|---|---|---|
| A-01 | 啟動首屏＝splash：黑底六角形 logo＋標題副標，淡入淡出時序（container 3s／logo 1s@0.5s／text 1s@1.5s） | splash.py:3-90 | `ShellUITests.testSplashIsShownBeforeMainUI`（首屏元素＋截圖附件）；時序參數照 splash.py 1:1 實作，動畫觀感待 M8 並排目視 | ✅ M5 |
| A-02 | splash 3.5s 後同窗切換主 UI（非開新窗） | py:1896 | 同上（`windows.count == 1`＋splash 元素消失） | ✅ M5 |
| A-03 | 主窗默認 1200×800、可縮放 | py:1863-1871 | `testWindowGeometryAndTitle` | ✅ M5 |
| A-04 | 窗口標題 "Azathoth's Whisper" | py:1864 | 同上（`windows["Azathoth's Whisper"]`） | ✅ M5 |
| A-05 | 菜單 Settings → Token Settings... / Language Settings... 開對應 modal | py:1909-1918 | `testSettingsMenuOpensTokenModal`／`testSettingsMenuOpensLanguageModal` | ✅ M5 |
| A-06 | 菜單 Help → About 開 About modal | py:1919-1922 | `testHelpMenuOpensAboutModal` | ✅ M5 |
| A-07 | 菜單文案硬編碼英文，不隨語言變 | py:1909-1923 | `testColdStartInJapaneseLocalizesUIButNotMenus`（ja 冷啟動下 Settings／Help 仍為英文）。實作差異：SwiftUI 的系統 Help 菜單標題由 AppKit 在地化，故清空系統組＋自建英文 Help 菜單，並在 `AppDelegate` 移除空的頂層菜單 | ✅ M5 |
| A-08 | 紅色關閉鈕＝隱藏窗口，app 不退出 | py:2052-2060 | `testRedCloseButtonHidesWindowWithoutTerminating`（視窗消失＋`app.state != .notRunning`） | ✅ M5 |
| A-09 | Dock 圖標點擊→重新顯示已隱藏窗口 | py:1877-1893 | `applicationShouldHandleReopen` 已實作；Dock 點擊無法在 XCUITest 內定界模擬，M8 真人操作 | ⬜ |
| A-10 | Cmd+Q 真退出 | py:753-761,1969-1995 | `testQuitMenuItemTerminatesApp`（走 app 自身 Quit 菜單項，與 Cmd+Q 同一 `terminate:` 路徑；不模擬全域按鍵）。**2026-08-23 註**：單獨跑通過（7.2s），連跑時穩定失敗。**2026-09-05 更新——狀況變差且已排除本次改動**：現在**單獨跑也失敗**（18.4s，`app.state` 停在 4 而非 1）。已用獨立 git worktree 在乾淨的 HEAD `cc88a53`（不含任何 M8 改動）複驗，**同樣失敗**（72.6s）→ 非 M8 引入；且 M8 的改動經 `git diff --stat` 確認**未觸及 `App/`（含 AppDelegate 與退出邏輯）與 `UI/`**。依熔斷紀律不重啟調查（M7 計劃附錄已記 6 輪未進展、4 假設被砍）。**產品行為本身未被證偽**：`AppDelegate` 無 `applicationShouldTerminate`，退出路徑是 M5 驗收過的；失敗的是 XCUITest 觀測 `app.state` 的時序，非 Quit 功能。真人操作驗證列入 M8-14 | ✅ M5（連跑 flaky） |
| A-11 | Dock 右鍵 Quit 真退出 | py:1925-1967 | 與 A-10 同一 `terminate:` 路徑；Dock 選單需真人操作，M8 手動 | ⬜ |
| A-12 | 自動化權限被拒→曲目卡紅字 "Access Denied"／"Check macOS Permissions" | py:1122-1125,448-453 | `EditorViewModelTests.permissionDeniedShowsAccessDeniedCard`（邏輯層）；真機 `tccutil reset AppleEvents` 待 M8 | ✅ M5（邏輯層） |

## B Editor（23 條）

| ID | 行為描述 | 依據 | 驗證方式 | 狀態 |
|---|---|---|---|---|
| B-01 | 3 秒輪詢當前曲目 | py:769 | `NowPlayingMonitor.interval`＋事件序列單測（M4）；UI 端 M5 觀察 | ✅ M4（邏輯層） |
| B-02 | isBusy 期間輪詢跳過 | py:508-510 | `NowPlayingMonitorTests.skipsPollWhileBusy` | ✅ M4 |
| B-03 | 曲目識別＝persistentID 為主（無 ID fallback 全簽名）（修正⚠️：原版 (artist,title) 簽名） | py:511-517＋Plan §4.4 | `detectsTrackChangeByPersistentIDEvenWhenTitlesMatch`＋真機冒煙 | ✅ M4 |
| B-03a | paused 仍視為有當前曲（僅 stopped/無曲＝notPlaying）（修正⚠️：語義顯式化） | py:1108-1128 | `pausedStateStillReportsCurrentTrack`＋真機 | ✅ M4 |
| B-04 | 切歌且 Music 已有詞→自動載入＋狀態 "Lyrics loaded from music app" | py:466-476 | `trackWithExistingLyricsLoadsThemAndReportsStatus`＋真機截圖（AC/DC 曲目已載入並顯示該文案） | ✅ M5 |
| B-05 | 切歌且無詞→清空＋100ms 後自動 fetch；僅 Editor tab 激活時觸發（語義默認已向用戶聲明） | py:478-486 | `trackWithoutLyricsClearsAndAutoFetches`／`autoFetchSkippedWhenEditorTabInactive`／`AppModelTests.switchingTabTogglesEditorAutoFetchFlag` | ✅ M5 |
| B-06 | Now Editing 卡片點擊＝手動 hydrate | py:745 | `cardTapRequestsHydrate`（VM）＋`EditorView` 的 `onTapGesture` → `NowPlayingMonitor.forceRefresh` | ✅ M5 |
| B-07 | 卡片 artist／title 兩行；title＝" - " 首分割後其餘 join | py:454-461 | `TrackLabelTests`（4 案，含 artist 自身帶 " - " 的原版缺陷照搬） | ✅ M5 |
| B-08 | 無播放→ "No Artist"／"No Track" | py:441-447 | `notPlayingShowsPlaceholderLines`＋冷啟動截圖 | ✅ M5 |
| B-09 | Editor Fetch 僅走 Genius，不 fallback DarkLyrics | py:2082-2097 | `LyricsServiceTests`（M2）＋`dataSourceSelectionDoesNotAffectFetchPath` | ✅ M5 |
| B-10 | Fetch 中狀態 "Fetching from Genius..." | py:521 | `inFlightFetchDoesNotOverwriteNewlySwitchedTrack`（抓詞中斷言 statusText） | ✅ M5 |
| B-11 | 結果三態文案："Lyrics fetched"／"Lyrics not found"／"Fetch failed" | py:519-536 | `fetchReportsFetchedForFoundResult`／`fetchReportsNotFoundForNotFoundResult`／`fetchReportsFetchFailedWhenMusicIsUnreachable` | ✅ M5 |
| B-11a | **Genius 拋異常時不把錯誤訊息當歌詞**（⚠️ 已批准偏差）：原版 py:2095 只判 `startswith("Error")`，而異常路徑回 `"Genius Error: …"` 不以 Error 開頭 → 會被填進歌詞框並顯示綠色 "Lyrics fetched"。新版一律降為 "Lyrics not found"，不污染使用者歌詞欄 | py:2095、1283-1284 | `LyricsServiceTests.editorMapsNotFoundAndErrorToNotFound` | ⚠️ 已批准偏差 |
| B-12 | Save："Saving to Music..."→"Saved"＋confetti | py:538-552 | `successfulSaveTriggersConfetti`／`saveReportsFailedToSaveWhenWriteReturnsFalse`／`saveReportsWriteFailedWhenMusicThrows`＋`ConfettiPhysicsTests`（五連發參數逐項對照） | ✅ M5 |
| B-13 | Save 寫入畫面綁定的 persistentID（修正⚠️：原版寫「當前曲目」，競態下 A 詞入 B 曲） | Plan §4.10 | `saveWritesToBoundTrackIdentifier` | ✅ M5 |
| B-14 | Fetch 進行中切歌→結果不套用到新曲（世代守衛）（修正⚠️） | Plan §4.10 | `inFlightFetchDoesNotOverwriteNewlySwitchedTrack`（閘門式來源製造真實競態窗口） | ✅ M5 |
| B-15 | 行數統計＝`\n` split 計數，輸入即時更新 | py:419-427 | `lineCountFollowsPythonSplitSemantics`＋`carriageReturnLyricsAreNormalizedLikeTextarea`（新發現：Music 以 CR 分行，缺 textarea 的隱式正規化會把整首歌算成 1 行——見 `Infra/LineEndings.swift`） | ✅ M5 |
| B-16 | 歌詞框 placeholder "// Waiting for input stream..."；拼寫檢查關閉 | py:181-186 | 首啟截圖（placeholder 可見）＋`PlainTextEditor` 顯式關閉 continuous spell/grammar check | ✅ M5 |
| B-17 | 角落裝飾字 "TXT_MODE: UTF-8" | py:185 | `testLaunchShowsEditorShellAfterSplash` 斷言 | ✅ M5 |
| B-18 | 假指標 "Mem: 64MB"／"Lat: 12ms" 靜態顯示（半透明） | py:200-201 | 同上 | ✅ M5 |
| B-19 | Data Source 下拉三選項 genius(默認)/darklyrics/metalarchives，純裝飾無功能 | py:151-163 | `dataSourceSelectionDoesNotAffectFetchPath`（切成 darklyrics 後仍由 Genius 供詞） | ✅ M5 |
| B-20 | Fetch/Save 按鈕 hover：白遮罩下往上滑入＋文字反色（blend difference），300ms | py:165-178 | 已按 HTML 參數實作（`.blendMode(.difference)`＋300ms）；hover 動畫需真人移入目視，M8 | ⬜ |
| B-21 | busy 時全部按鈕禁用＋wait 光標（⚠️ 偏差：wait 光標） | py:406-417 | 按鈕禁用＝`ActionButton(isEnabled: !isBusy)`＋`busyStateIsPublishedAroundFetch`。**偏差**：AppKit 無公開的 "wait" 光標（網頁 `cursor:wait` 由瀏覽器提供，對應的系統轉輪由 WindowServer 控制），故不模擬；isBusy 語義與按鈕禁用 1:1 保留 | ⚠️ 已簽字（用戶 2026-08-15） |
| B-22 | 狀態欄初始文案 status_ready（en="Ready"——修正⚠️數據錯，原值為日文） | py:196,962 | `LocalizationTests.englishDataDefectsAreFixed`＋footer 綁定（statusText 為 nil 時取本地化 status_ready） | ✅ M5 |
| B-23 | Footer "Status:"/"Lines:" 標籤走 i18n | py:192-199 | `testLaunchShowsEditorShellAfterSplash`（en）＋ja／zh-Hant 冷啟動斷言 | ✅ M5 |

## C Batch（30 條）

| ID | 行為描述 | 依據 | 驗證方式 | 狀態 |
|---|---|---|---|---|
| C-01 | 切入 Batch tab 且**列表為空**時自動載入當前專輯（py:396 判的是 batchData.length，非「首次」） | py:379-383 | `activatingTabWithEmptyListLoadsAlbum`／`activatingTabWithLoadedListDoesNotReload` | ✅ M6（邏輯層） |
| C-02 | 載入中 "Loading tracks from Music..." | py:624 | `loadingStateIsObservableWhileFetching`（以閘門定格一閃而過的載入態，目視不可靠） | ✅ M6（邏輯層） |
| C-03 | 專輯過濾＝album＋artist 雙條件 | py:1154-1183 | 真機實測（2026-08-15）：Music 暫停於 Allen-Lande《The Showdown》時切入 Batch，列表載入該專輯 12 曲且 artist 欄全為 Allen-Lande；`albumTracks(artist:album:)` 走 AE 雙條件過濾。**反向驗證**（庫中存在同名不同藝人專輯時只取當前藝人）需特定曲庫資料，未於本機構造，沿用 M1 spike 證據 | ✅ M6（真機正向） |
| C-04 | 行格式：補零序號（padStart 2）/artist/title/狀態點 | py:556-601 | `rowNumberIsListIndexPaddedToTwoDigits`／`tracksKeepAppleEventsOrderWithoutSorting` | ✅ M6（邏輯層） |
| C-05 | 有詞＝白點（Has Lyrics）；缺詞＝暗紅點（Missing） | py:571-575 | `whitespaceOnlyLyricsCountAsMissing`（判定層）＋`BatchRow.statusDot`；色值目視待 M8 | ✅ M6（邏輯層） |
| C-06 | 行點擊→高亮＋預覽填充＋meta "Artist - Title" | py:604-613 | `selectingTrackFillsPreviewAndMeta` | ✅ M6（邏輯層） |
| C-07 | 預覽面板只讀 | py:236 | `BatchUITests.testPreviewPaneIsReadOnly`（點入後鍵入，內容不變且不出現在畫面） | ✅ M6 |
| C-08 | Fetch Missing：無缺詞項→提示 "No missing lyrics to fetch!" | py:648-654 | `fetchMissingWithNothingMissingShowsAlert` | ✅ M6（邏輯層） |
| C-09 | Fetch Missing 串行逐條，進度 "Fetching (i/n): title" | py:655-668 | `fetchMissingRunsSeriallyWithProgressText`（閘門斷言串行性＋進度格式） | ✅ M6（邏輯層） |
| C-10 | 逐條 fallback：Genius→DarkLyrics，傳 album（決策 5 修正⚠️：原版不傳） | py:2229-2243＋Plan 決策 5 | `fetchMissingPassesAlbumToSource`（決策 5 傳 album）＋M2 golden G-10/G-12 | ✅ M6（邏輯層） |
| C-10a | **fallback 觸發條件（用戶 2026-08-10 拍板修正）**：原版 py:2232 只判 `startswith("Error")`，故 Genius 回「Lyrics not found on Genius.」時直接返回、不 fallback——DarkLyrics 實際只在 token 未配置/拋異常時才跑，決策 5 的 album 修正等同無效。新版改為 Genius 非命中即 fallback 到 DarkLyrics。可見變化：Batch 抓詞成功率上升，部分曲目改由 DarkLyrics 供詞 | py:2232（偏離） | 單測 `batchFallsBackWhenGeniusReportsNotFound` | ⚠️ 已拍板修正（M2 實現） |
| C-11 | 命中即時重繪；選中項同步預覽 | py:669-676 | `fetchedLyricsUpdateListAndSelectedPreview` | ✅ M6（邏輯層） |
| C-12 | 結束 "Fetch complete." | py:678 | `fetchMissingRunsSeriallyWithProgressText`（結尾斷言） | ✅ M6（邏輯層） |
| C-13 | Import Selected 未選中→提示 "Please select a track first..." | py:684-686 | `importSelectedWithoutSelectionShowsAlert` | ✅ M6（邏輯層） |
| C-14 | Import Selected 用預覽框文本寫入→"Saved"＋confetti | py:688-706 | `importSelectedWritesPreviewTextAndTriggersConfetti` | ✅ M6（邏輯層） |
| C-15 | Import All 確認框文案 "Writes lyrics for ALL tracks in list where lyrics are present. Continue?" | py:715 | `testImportAllShowsConfirmationWithExactWording`（sheet 內文案逐字比對＋Cancel 後狀態欄不變） | ✅ M6 |
| C-16 | Import All 串行寫入全部有詞項→"All saved."＋confetti | py:716-738 | `importAllWritesEveryTrackThatHasLyrics` | ✅ M6（邏輯層） |
| C-17 | 切專輯→列表清空；Batch 可見則自動重載 | py:488-498 | `albumChangeClearsListAndReloadsWhenVisible`／`albumChangeClearsListWithoutReloadWhenHidden` | ✅ M6（邏輯層） |
| C-18 | **逐操作禁用範圍 1:1（原 Plan §4.10 前提有誤，2026-08-14 複核修正）**：載入專輯＝全部 5 按鈕禁用＋輪詢停；Fetch Missing／Import All＝只禁自己按鈕、輪詢照跑；Import Selected＝不禁任何按鈕、輪詢照跑。原描述「批處理期間按鈕全禁＋輪詢停」只對「載入專輯」成立 | py:621/639（載入調 toggleBusy）、657/678（Fetch 只禁自己）、723/738（All 只禁自己）、682-709（Selected 無任何禁用）、508-510（輪詢跳過只看 isBusy） | `onlyAlbumLoadSuspendsPolling`／`fetchMissingDisablesOnlyItsOwnButton`／`loadingStateIsObservableWhileFetching`。**2026-08-23 補修重疊載入偏差**：舊實作在每個 `loadAlbum()` 的 `defer` 無條件落下 busy，先完成者會提前解除（按鈕提前啟用、輪詢提前恢復）——切專輯路徑在原版不可能發生（輪詢在 isBusy 時跳過 py:508-510），故違反本條。改為 `loadsInFlight` 在飛請求計數，歸零才落下。另修 Editor／Batch 各自裸布林覆寫 monitor 單一 isBusy 的缺陷（一方送 false 清掉另一方）：由 `NowPlayingMonitor` 自己維護 `busySources: Set<BusySource>`，`setBusy(_:source:)` 顯式帶來源（記帳責任在狀態擁有者，新增來源只需擴列舉）。並把 `onBusyChange` 改為 `async`、以 `withBusy`／`withLoadingAlbum` 作用域取代 `defer`——消除原先 `Task { await monitor.setBusy(...) }` 的 fire-and-forget 跳板，使「isBusy 變更」與「monitor 記帳」嚴格有序（原先測試只能靠讓步 N 輪賭它送達，實際存在 polling window）。`fetch()` 刻意不套作用域：其釋放受 `fetchSeq` 條件約束，被取代的舊抓詞不送 false。新增用例：`overlappingLoadKeepsBusyUntilLastCompletes`／`overlappingLoadSuspendsPollingUntilLastCompletes`（整合層，驅動 monitor.tick 斷言輪詢確實停）／四條 `loadsInFlight` 不變量／`batchLoadCompletionMustNotClearEditorBusy` | ✅ M6＋M6收尾 |
| C-19 | Batch 作業中切 tab／專輯變更→session ID 校驗防過期回寫（縱深，修正⚠️） | Plan §4.10 | `staleFetchLoopStopsWritingAfterAlbumReload`（閘門製造真實競態窗口） | ✅ M6（邏輯層） |
| C-20 | 隱藏窗口不中斷 Batch 任務 | Plan §4.10（對齊原版隱藏語義） | `BatchLiveUITests.testHiddenWindowDoesNotInterruptBatchFetch`（預設跳過，需 AZW_MUSIC_TESTS=1——與 `LiveMusicTests` 同一閘門變數）：於 `FETCHING (1/12)` 時點紅鈕隱藏，35s 後 app 仍存活；os_log 顯示 12 條 fetch progress 全數產生（00:10:41.200→00:10:48.273），即隱藏後續跑完剩餘 11 首 | ✅ M6（真機） |
| C-21 | 表頭 Artist/Title/Stat 走 i18n（col_*）；`#` 欄為硬編碼符號**不**走 i18n；預覽面板標題走 col_preview | py:219-224, 233 | `testBatchShellInEnglish`／`…InJapanese`／`…InTraditionalChinese`（三語表頭＋`#` 欄不 i18n） | ✅ M6 |
| C-22 | Import All 無可寫項（全部缺詞）→ 提示 "No tracks have lyrics to save."，不進入寫入循環 | py:718-721 | `importAllWithNoLyricsShowsAlertAfterConfirmation` | ✅ M6（邏輯層） |
| C-23 | 載入專輯期間 **Editor** 狀態欄三態："Processing album batch..." → 成功 "Album loaded"／異常 "Batch failed"（設的是主狀態欄，非 Batch 自己的狀態欄） | py:623/633/637 | `loadingPublishesPlaceholderAndEditorStatus` | ✅ M6（邏輯層） |
| C-24 | Batch header 專輯名三態：初始 "Loading..."／有資料取**首曲的 album 欄位**／無資料 "No Data / Album" | py:212/559/561 | `loadedAlbumTakesHeaderNameFromFirstTrack`／`emptyAlbumShowsNoDataHeader` | ✅ M6（邏輯層） |
| C-25 | Batch footer 狀態欄初始 "Ready" ＝**硬編碼英文，不隨語言變**（對比 Editor footer 的 status_ready 走 i18n——原版兩處不一致，照搬） | py:241 vs py:196 | `testBatchColumnsLocalizeButStatusStaysEnglishInJapanese`（ja 下狀態欄仍 READY，且畫面查無 status_ready 的 ja 值「準備完了」） | ✅ M6 |
| C-26 | 載入失敗兩態在新版**不可達**（照搬原版語義）：py:1180-1182 的 `except` 吞掉全部異常回 `[]`，故 JS 的兩個紅字分支（非陣列／"Failed to load tracks."）實際到不了。Swift 同樣把 Music 層異常降為空專輯（header "No Data / Album"、Editor 狀態 "Album loaded"），但錯誤不靜默丟棄——落 os_log。`ListState.failed` 分支保留於 UI 但無生產觸發點。**2026-08-23 裁決：維持保留**（Codex 複審勝方＝保留方；理由：這是規格要求的不可達碼，非漏清理；刪除須先修訂並重新簽署本條）。已於 `BatchViewModel.ListState` 與 `StatusText` 兩處加防誤判註釋 | py:628-637 vs py:1180-1182 | `musicFailureIsSwallowedAsEmptyAlbumLikePython` | ✅ M6 |
| C-27 | 三操作的前置與逐條進度文案：Fetch Missing "Fetching {n} tracks..." → "Fetching (i/n): {title}"；Import All "Saving {n} tracks..." → "Saving (i/n): {title}"；Import Selected "Saving {title}..." | py:658/662/724/728/692 | `fetchMissingRunsSeriallyWithProgressText`／`importAllReportsPerTrackProgress`／`importSelectedReportsSavingProgress` | ✅ M6（邏輯層） |
| C-28 | Import Selected 結果文案**帶句點**："Saved."／"Save failed."／"Error saving."——與 Editor Save 的 "Saved"（無句點）不同，照搬此差異 | py:700/703/707 vs py:543 | `importSelectedWritesPreviewTextAndTriggersConfetti`／`…ReportsSaveFailedWhenWriteReturnsFalse`／`…ReportsErrorSavingWhenMusicThrows` | ✅ M6（邏輯層） |
| C-29 | **缺詞判定採 trim 語義**（⚠️ 已拍板修正 2026-08-14）：純空白歌詞（如 "   "）視為缺詞。原版三處篩選（狀態點/Fetch Missing/Import All）用未 strip 的 `length > 0`，而後端算好的 `has_lyrics`（strip 判空）從未被使用——屬原版內部不一致。可見變化：純空白曲目改顯暗紅點、會被 Fetch Missing 抓、不再被 Import All 把空白寫回音樂庫 | py:587/651/717（實際用）vs py:2253-2254（算了沒用） | `whitespaceOnlyLyricsCountAsMissing`／`importAllWritesEveryTrackThatHasLyrics`（純空白 fixture 三處斷言） | ⚠️ 已拍板修正 |
| C-30 | **Batch 不把 Genius 錯誤訊息當歌詞**（⚠️ 與 B-11a 同源，按其先例修正）：原版 py:2232 只判 `startswith("Error")`，而 Genius 異常路徑回 "Genius Error: …" 不以 Error 開頭 → 直接當歌詞回傳；前端過濾只擋 "No track"／"Lyrics not found" 兩前綴亦放行 → 錯誤訊息入列表顯白點 → **Import All 會將其寫進音樂檔 lyrics 欄位**。新版 `LyricsResult` 為列舉，`.error` 不會被當 `.found` | py:2232、1283-1284、665 | `sourceErrorIsNeverStoredAsLyrics`＋`LyricsServiceTests`（已綠） | ⚠️ 按 B-11a 先例修正 |

## D Settings / About（13 條）

| ID | 行為描述 | 依據 | 驗證方式 | 狀態 |
|---|---|---|---|---|
| D-01 | 菜單 Token Settings→modal 顯示 token 組並 focus 輸入框 | py:776-797 | `testSettingsMenuOpensTokenModal`＋`AppModelTests.openingSettingsPrefillsCurrentValues`；focus 由 `@FocusState` 於 onAppear 設定 | ✅ M5 |
| D-01a | **token 輸入框以圓點遮蔽（`SecureField`）**（⚠️ 已拍板偏差 2026-09-05）：原版 py:275-280 與 2.0 M5 實作均為明文 `TextField`。改動理由＝憑證明文有兩條外洩路徑：肩窺，以及 **XCTest 失敗時的自動截圖**（會繞過「不主動截圖此 modal」的人工紀律，見 memory `no-credential-fields-in-ui-screenshots`）。**保存邏輯零改動**——仍綁同一個 `model.tokenInput`；`testSettingsMenuOpensTokenModal` 不依賴 `app.textFields` 定位，不受影響。**遮蔽本身的回歸保護＝`tokenFieldIsMasked`（本次新增）**：斷言 `app.secureTextFields` 有一個、`app.textFields` 為零。**不得引用 D-04／05／06**——那三條驅動的是 `SettingsViewModel`，全倉沒有任何測試實例化過 SwiftUI view，把 `SecureField` 改回 `TextField` 它們照樣全綠；拿邏輯層測試充當渲染層屬性的證據，正是本次已在 H-03／H-04 修訂掉的同一個錯（M8 對抗驗證發現） | Plan §7 #3（使用者拍板） | `SettingsModalView.swift` 的 `SecureField`＋既有 D-04/D-05/D-06 測試 | ⚠️ 已拍板偏差（使用者 2026-09-05） |
| D-02 | 菜單 Language Settings→modal 顯示 lang 組（兩組互斥） | py:776-797 | `testSettingsMenuOpensLanguageModal`（同時斷言 token 欄位不存在） | ✅ M5 |
| D-03 | modal 標題覆寫英文 "Token Settings"/"Language Settings"（繞過 i18n，照搬） | py:784-792 | `SettingsViewModelTests.titleOverridesLocalizationPerGroup`＋UI 測試 | ✅ M5 |
| D-04 | token 空值→紅字 "Token cannot be empty." | py:838-842 | `emptyTokenIsRejectedWithoutCallingValidator` | ✅ M5 |
| D-05 | 驗證中 "Validating..."→成功綠字 "Success! Token is valid and saved." | py:844-853 | `validTokenIsSavedThenModalCloses` | ✅ M5 |
| D-06 | 驗證成功 1.5s 後自動關 modal | py:854 | 同上（注入時鐘，斷言 onClose 被呼叫一次） | ✅ M5 |
| D-07 | 驗證失敗紅字 "Invalid Token: {msg}" | py:856-858 | `invalidTokenShowsPrefixedMessageAndKeepsModalOpen` | ✅ M5 |
| D-08 | token 驗證走 Genius account API；保存後即時生效（無需重啟） | py:2141-2152,2200-2210 | `TokenValidatorTests`（5 案，含 Bearer 標頭斷言）＋`AppModelTests.savingTokenPersistsAndRebuildsGeniusSource` | ✅ M5 |
| D-09 | 語言三選項 en/zh_TW/ja；保存→提示 "Language saved. Restart app to apply." | py:863-871,2212-2216 | `savingLanguageStoresValueAndAsksForRestart`；下拉維持三選項（儲存值為 system 時無選項匹配＝原版同行為） | ✅ M5 |
| D-10 | About：圖標＋Version 2.0.0＋Created By iBridge Zhao＋mailto＋GitHub 兩鏈接可點 | py:297-331 | `testHelpMenuOpensAboutModal`（四項元素斷言＋截圖）；圖標＝從 py:304 base64 抽出的原圖 | ✅ M5 |
| D-11 | About 圓角例外樣式（全 app 唯一圓角區） | py:299-330 | 截圖：外框 16px、卡片 8px、Close 膠囊；其餘畫面全 0 圓角 | ✅ M5 |
| D-12 | modal＝主窗內覆蓋層（非獨立窗/sheet）；modal 開啟時紅鈕關窗＝隱藏整窗 | Plan §4.2 | `ModalScrim` 為 ZStack 覆蓋層（截圖可見主 UI 在其後模糊）；modal 開啟時關窗的組合操作待 M8 手動 | ⬜ |
| D-13 | modal 背景：黑 80%＋背景模糊 | py:266-267 | 截圖（`VisualEffectView(.withinWindow)`＋`Color.black.opacity(0.8)`） | ✅ M5 |

## E i18n（10 條）

| ID | 行為描述 | 依據 | 驗證方式 | 狀態 |
|---|---|---|---|---|
| E-01 | en 修正三處：status_ready="Ready"＋batch_fetch/batch_import/batch_all 補齊（觀察行為不變）（修正⚠️數據錯） | py:962,951-998 | `LocalizationTests.englishDataDefectsAreFixed`（讀編譯後的 en.lproj，非讀原始 catalog） | ✅ M5 |
| E-02 | zh-Hant 全鍵值與 TRANSLATIONS.zh_TW 逐鍵一致 | py:999-1049 | `traditionalChineseAndJapaneseMatchSource`＋`everyUIKeyResolvesInAllThreeLanguages` | ✅ M5 |
| E-03 | ja 全鍵值逐鍵一致 | py:1050-1100 | 同上 | ✅ M5 |
| E-04 | UI 內 19 個 i18n 位點三語正確呈現 | py:874-882 | `everyUIKeyResolvesInAllThreeLanguages`（20 鍵 × 3 語）＋ja／zh-Hant 冷啟動 UI 斷言（導航／footer 實際文字） | ✅ M5 |
| E-05 | 運行時狀態文案保持硬編碼英文（StatusText 常量，勿本地化） | py:519-552,620-740 | `runtimeStatusTextIsNotLocalized`（三語 catalog 均查無此字串） | ✅ M5 |
| E-06 | "system"＝跟隨系統：app 域→全局域 AppleLanguages 判定鏈 | py:1621-1644 | G-15 golden（`language_mapping.json` 10 組合）＋`SystemLanguageDetector` 單測 | ✅ M5 |
| E-07 | 冷啟動四態實測：system/en/zh_TW/ja 各自呈現正確語言 | Plan §4.6 | ja／zh-Hant 兩態已由 `testColdStartInJapaneseLocalizesUIButNotMenus`／`testColdStartInTraditionalChinese` 自動化（`-AppleLanguages` 僅作用於該次啟動）；system／en 兩態待 M8 於使用者機器實測 | ⬜ |
| E-08 | 語言寫入 per-app AppleLanguages：en→["en"]、zh_TW→["zh-Hant"]、ja→["ja"]、system→刪鍵 | Plan §4.6 | `AppModelTests.savingLanguageWritesAppleLanguagesOverride`＋`ConfigMigrationTests.systemLanguageRemovesAppleLanguagesOverride` | ✅ M5 |
| E-09 | 語言變更重啟生效（無熱切換） | py:2212-2216 | 保存路徑已測（D-09）；「重啟後生效」需真人重開，M8 手動 | ⬜ |
| E-10 | 新鍵 nav_coverflow 三語（Cover Flow／封面瀏覽／カバーフロー） | Plan §4.6 | `coverFlowKeyIsTranslated`＋兩語冷啟動 UI 斷言 | ✅ M5 |

## F 配置遷移（9 條）

| ID | 行為描述 | 依據 | 驗證方式 | 狀態 |
|---|---|---|---|---|
| F-01 | 未遷移時 legacy 讀取語義＝G-15 golden 7 組合（env>JSON>defaults、裸 token、缺鍵補齊） | py:1565-1609 | `LegacyConfigTests.legacyResolutionMatchesGolden` | ✅ M3 |
| F-02 | 遷移落位：token→Keychain（generic password）、language→UserDefaults | Plan §4.9 | `ConfigMigrationTests.migratesTokenFromEnvIntoSecretStore` | ✅ M3 |
| F-03 | 一次性旗標 legacyConfigMigrated：置位後不再讀 legacy；重跑冪等 | Plan §4.9 | `migrationIsIdempotentAndKeepsLegacyFiles` | ✅ M3 |
| F-04 | 遷移不刪舊檔（.env／~/.azathoths_whisper_config 原樣保留） | Plan §4.9 | 同上（斷言檔案仍存在） | ✅ M3 |
| F-05 | 遷移後 Keychain/UserDefaults 為唯一真源，不再讀 .env（⚠️偏差：原版 env 恆優先屬缺陷——新 token 會被舊 .env 覆蓋） | Plan §4.9 | 同上（改 token 後二次遷移不回退） | ⚠️ 已批准偏差 |
| F-06 | 未遷移讀取時 .env 三級路徑順序：腳本目錄→可執行目錄→~/Documents/Bjork/.env | py:910-931 | `dotEnvUsesFirstExistingPath`／`dotEnvParsesCommentsQuotesAndBlankLines`；本機 .env 鍵名格式已核（未讀值） | ✅ M3 |
| F-07 | Settings 保存 token→Keychain 更新，UI 流程與文案不變 | py:2200-2210 | `AppModelTests.savingTokenPersistsAndRebuildsGeniusSource`（走 SecretStore 抽象，測試用 InMemory 替身） | ✅ M5 |
| F-08 | 測試禁讀真實 .env（全部臨時目錄＋假 token）；開發機手動遷移驗證一次且日誌脫敏 | Plan §4.9 | 測試碼審查通過（值全為 fake-*） | ✅ M3 |
| F-09 | Keychain 條目 service 名固定、單條、可重複寫入更新 | Plan §4.9 | `KeychainStoreTests`（5 案，測試專用 service 名） | ✅ M3 |

## G 歌詞源保真（M0 落檔，golden 驅動）

驗證方式統一為：Swift 測試以 `Tests/Fixtures/golden/<檔>` 表驅動斷言（M2/M3 實現）。

| ID | 行為描述 | Python 依據 | 驗證方式 | 狀態 |
|---|---|---|---|---|
| G-01 | sanitize_title 22 案例逐一相等（IGNORECASE、多重括號、Unicode 保留、非關鍵詞不剝） | py:1201-1219 | golden `sanitize_title.json` | ✅ M2 |
| G-02 | DarkLyrics URL normalize 12 案例逐一相等（lower→刪一切非 a-z0-9；變音/CJK/標點全刪） | py:1305-1306 | golden `darklyrics_normalize.json` | ✅ M2 |
| G-03 | DarkLyrics 專輯頁解析：5 頁×首曲/中段曲真實命中，文本逐字節相等 | py:1371-1432 | golden `darklyrics_parse.json`（命中案例） | ✅ M2 |
| G-04 | DarkLyrics 模糊匹配：帶 "(Remastered 2009)" 尾綴經 sanitize 後雙向 substring 仍命中 | py:1393-1407 | golden `darklyrics_parse.json`（fuzzy 案例） | ✅ M2 |
| G-05 | DarkLyrics 未命中→"Song title not found on album page."；無 div.lyrics→"Error: Could not parse lyrics container." | py:1384-1412 | golden `darklyrics_parse.json`（miss 案例） | ✅ M2 |
| G-06 | Genius 主管線（庫路徑等價）：4 真實頁 → data-lyrics-container 選擇器＋LyricsHeader 刪除＋br/文本遍歷＋段頭 `(\[.*?\])*` 剝除＋`\n{2}`→`\n`＋strip('\n')，最終文本相等 | lyricsgenius 3.7.5 genius.py:126-206（生產主路徑） | golden `genius_library_clean.json`（**主口徑**，Plan R3） | ✅ M2 |
| G-07 | Genius 首行標題頭剝除：首行 strip 後 endswith("Lyrics") 整行刪 | py:1236-1241 | golden `genius_library_firstline.json` | ✅ M2 |
| G-08 | Genius 手動 fallback legacy 參照（Lyrics__Container 選擇器，含頁面雜訊）——Swift 不以此為符合性目標，偏差已記錄 | py:1245-1276 | golden `genius_manual_parse.json`＋Fixtures/README 差異說明 | ⚠️ 已簽字（用戶 2026-08-15） |
| G-09 | Genius search 選 hit＝hits[0].result.url；無 hits→notFound | py:1252-1256,1281 | `LyricsSourceTests.geniusMapsEmptySearchHitsToNotFound` 等 | ✅ M3 |
| G-10 | DarkLyrics 直連 URL 構造：`http://www.darklyrics.com/lyrics/{norm_artist}/{norm_album}.html`，200 即解析 | py:1296-1315 | `darkLyricsUsesDirectAlbumURLWhenAvailable`＋線上測試 | ✅ M3 |
| G-11 | 直連非 200 → DDG fallback（POST 先行，非 200 轉 GET） | py:1316-1336 | `darkLyricsFallsBackToSearchWhenDirectMisses` | ✅ M3 |
| G-12 | 無 album → 直接 DDG；查詢串＝`site:darklyrics.com "{artist}" "{title}"` | py:1321-1333 | 同上（斷言 posted form q） | ✅ M3 |
| G-13 | DDG 全阻 → "Error: Could not search for song (DDG Lite Blocked)." | py:1338-1339 | `darkLyricsReportsBlockedSearch` | ✅ M3 |
| G-14 | DDG 無 darklyrics 鏈接 → notFound；result-link 取首個含 /lyrics/ 者並去 # 錨點 | py:1344-1357 | `darkLyricsReportsNotFoundWhenSearchHasNoLink` | ✅ M3 |
| G-15 | 配置讀取 7 組合＋語言檢測 10 組合（app→global 落穿、zh→ja→en 優先序） | py:1565-1609,1621-1644 | golden `config_migration.json`＋`language_mapping.json` | ✅ M3 |
| G-16 | **CPython vs ICU 字串語義對齊**（M2 審查確認）：`str.strip()` 集合（保留 U+200B、剝 U+001C–1F）、希臘末尾 sigma、土耳其 ı/İ 折疊 | CPython str.strip/lower、re.IGNORECASE | `PythonCompatTests`（6 案） | ✅ M3 |

### G 區段附錄：fixture 清單（M0 DoD）

`sanitize_title.json`(22) / `darklyrics_normalize.json`(12) / `darklyrics_parse.json`(17) / `genius_manual_parse.json`(5) / `genius_library_clean.json`(4) / `genius_library_firstline.json`(6) / `darklyrics_flow.json`(5) / `config_migration.json`(7) / `language_mapping.json`(10)。生成器 `Scripts/make_fixtures.py`，重跑冪等已驗證（2026-08-10）。

## 附錄：M2 對抗審查裁決記錄（2026-08-10）

四視角並行審查＋逐條駁斥驗證，34 條提出、8 條經證據確認、26 條駁回或未達證據門檻（其中 html 視角 7 條因外部限額未完成驗證，列為 P2 待查）。裁決：

| 條目 | 裁決 | 落點 |
|---|---|---|
| trim 字符集差異（U+200B / U+001C–1F），有端到端可見分歧 | 採納 | `PythonCompat.whitespace`＋五處替換；G-16 |
| 希臘末尾 sigma（Swift 會回傳「別首歌」的歌詞） | 採納 | `PythonCompat.lowercased`；G-16 |
| 土耳其 ı/İ 不折疊 → (REMİX) 清不掉 | 採納 | 三個關鍵字補字符類；G-16 |
| 正則 `\s` 不覆蓋 U+001C–1F | **部分駁回** | trim 側已修；正則側維持（該類控制字元不可能出現在曲名括號前後），列已知偏差 |
| Editor 把 Genius 異常訊息當歌詞顯示（py:2095 只判 "Error" 前綴，而異常回 "Genius Error: …"） | 採納建議 | 保留 Swift 語義（不寫進歌詞欄）；見 B-11a |
| HTMLText 遞迴深 DOM 爆棧 | 採納（附實測修正） | 改迭代走訪。**實測補充：真正的深度天花板在 SwiftSoup.parse 自身（10,000 層即爆棧），走訪層風險在實際管線中不可達**；迭代版屬防禦性改進 |
| 測試未斷言 artist 傳遞（mutation 存活） | 採納 | 補斷言 |
| 對非 throwing API 用 `try?` | 採納 | 移除 |

**P2 遺留（本輪不修，記錄待查）**：①SwiftSoup 對超深巢狀 HTML 會硬崩潰，而 Python 側 BeautifulSoup 會拋 RecursionError 被 try/except 優雅降級——真實歌詞站不會產生此類頁面，但屬健壯性差異。②html 視角 7 條未完成驗證的 SwiftSoup vs bs4 差異假設（Windows-1252 實體重映射、Comment 節點、空白塌縮、`<template>`/`<rt>`、未知實體分號、選擇器大小寫敏感性、畸形 HTML 樹構造）。

## 附錄：M5 落地備註（2026-08-11）

**新增依賴／資源**：Material Symbols Outlined **子集**（7 glyph，4KB TTF，Apache 2.0 隨附）——經 Google Fonts CSS API 的 `icon_names=` 取得 truetype 子集，無需 fonttools、無新增套件依賴；連字（ligature）機制與原版 CDN 字型一致，`MaterialSymbolTests` 逐一驗證 7 個名稱都替換成單一非 .notdef glyph。About 圖標由 py:304 的 base64 抽出為 `Resources/AboutLogo.png`。

**目視比對抓到、單測抓不到的 4 個缺陷（已修）**：
1. `.textCase(.uppercase)` 會傳播到圖示 `Text`，令連字失效、圖示退化成字面文字 "CLOUD_DOWNLOAD"。→ `MaterialSymbol` 強制 `.textCase(nil)`。
2. `ActionButton` 內以 `GeometryReader` 當 ZStack 同層 → 按鈕撐滿容器。→ 白遮罩改走 `.background`（不參與尺寸協商）＋`.clipped()`。
3. 導航底線放在 `VStack` 內 → 整個導航項撐滿剩餘寬度。→ 底線改 `.overlay(alignment: .bottom)`。
4. `.frame(width:)` 預設置中，令 Data Source 欄位偏移。→ 改套在下拉本身。

**行為級新發現**：Music 的 lyrics 欄位以 CR 分行，原版經 `<textarea>` 隱式正規化成 LF，故 Lines 統計與寫回內容都是 LF 版。Swift 端補 `Infra/LineEndings.swift`，否則整首歌顯示為 1 行（見 B-15）。

**安全事件（已處置）**：Token Settings 的 UI 測試截圖會把 Keychain 預填的**真實 token 明文**寫進 xcresult 附件。已刪除全部含該截圖的產物（scratchpad 與 DerivedData/Logs/Test 共 8 份），並改為不對該 modal 截圖（僅斷言標題與欄位標籤）。

**測試現況**：126 個單元測試（22 suites）＋10 個 XCUITest 全綠；Services+Infra 行覆蓋 82.3%（門檻 80%）。UI 測試不模擬全域按鍵、以 `app.terminate()` PID 定界收尾、語言以 `-AppleLanguages` 僅注入該次啟動。

## H Cover Flow（11 條，對 spec＝Plan §4.8）

| ID | 行為描述 | 依據 | 驗證方式 | 狀態 |
|---|---|---|---|---|
| H-01 | 第三 nav tab（Editor｜Batch｜Cover Flow），激活時懶加載 | Plan §4.8 | `activatingTabWithEmptyListLoads`／`activatingTabWithLoadedListDoesNotReload`（判定同 Batch 的 C-01：資料為空才載入，非「首次」） | ✅ M7-P1（邏輯層） |
| H-02 | 3D 形態五要素：中心正面／兩側 ±55° 斜角／負間距覆疊／倒影漸變／viewAligned 吸附 | Plan §4.8 | **幾何參數**已由 `CoverFlowGeometryTests`（15 條）釘住：旋轉 ±55° 含 clamp、縮放 1.0→0.82、負間距 −0.42×itemWidth、zIndex −\|d\|、perspective 0.55、首尾可達中心的 edgePadding。**觀感**（實際吸附行為、3D 疊放、resize）待 M8 並排目視——同 A-01／B-20 先例，依 Plan §1「視覺盡可能貼近（非像素級）」不做截圖比對 | ⬜ M8 目視 |
| H-03 | 中心下方標籤 "ARTIST // TITLE"（mono 排版語言） | Plan §4.8 | **文案組裝**＝`CoverFlowCenterLabelTests` 7 條（`composesArtistAndTitleWithDoubleSlash`／`returnsPlaceholderWhenCenterIDIsNilEvenWithItems`／`returnsPlaceholderWhenListIsEmpty`／`returnsPlaceholderWhenCenterIDNotInItems`／`emptyArtistStillComposesRatherThanFallingBackToPlaceholder`／`duplicateIDsUseFirstMatch`／`slashesInsideFieldsArePreservedVerbatim`）——M8 把 `CoverFlowView.centerText` 提為純函數 `CoverFlowCenterLabel.text(centerID:items:)` 才可測。**不斷言大寫**：大寫來自 View 的 `.textCase(.uppercase)` 這個渲染修飾符，純函數與 `accessibilityLabel` 拿到的都是原串，對其斷言大寫會假失敗（M8 三角評審發現）。**mono 排版與大寫觀感**待 M8-14 目視 | ⬜ 觀感待 M8-14 目視（文案組裝已驗，見證據欄）——與 H-02／H-08 同口徑 |
| H-04 | 切歌 ≤3s（一個輪詢週期）自動平滑居中——**條件式保證**（2026-08-23 拍板）：在正常 AE 回應與已定義的 timeout budget 下成立；若 Music.app 超過 AE budget 無回應，本輪允許延遲或缺少封面，但**不得**造成後續輪詢無界餓死。理由：`SBApplication` 的 AE 呼叫同步佔用串行佇列，Swift 層 timeout 無法撤回已送出的 Apple Event，client 端只能保證 bounded wait | Plan §4.8 | **拆兩半，只關掉可關的那半**。**① 調度層「不無界餓死」＝已驗**：`ArtworkAEFairnessTests.monitorCallWaitsBehindAtMostOneArtworkDuringPrefetch`（預取 10 張時 monitor 的 `currentTrack()` 前面至多一張 artwork）。**② 1.5s 時間界＝未驗，待 M8-13 真機**：由 `SBApplication.timeout`（`MusicAppleEventsClient.swift:153` `artworkTimeoutTicks = 90`／`:167-168`）給出，**mock 無法覆蓋**——該測試檔 `:11-14` 自己聲明「這裡不證明什麼：實際的 1.5 秒時間界…在此斷言秒數會是自欺」；且飢餓發生在 `MusicAppleEventsClient` 的 AE 串行化上，而 monitor 的 `currentTrack()` **根本不經過 `ArtworkService` 的佇列**（後者有獨立的 `pending`／`active`／`drainTask`）——**mock 在結構上不可達的是「時間界」本身，不是排程不變量**——後者可測，正因替身裡 monitor 與預取共用同一條 FIFO；而真實路徑上飢餓由 `SBApplication.timeout` 決定，替身沒有這個東西（M8 評審修正）。**故本條不得因引用 ① 而整條標 ✅** | ⬜ 時間界待 M8-13 真機（調度層已驗，見證據欄） |
| H-05 | 用戶手動滑走後不搶控制；下次真實切歌才拉回 | Plan §4.8 | 四條測試：`manualScrollSuppressesAutoCenter`／`sameTrackRefreshDoesNotClearOverride`（**真實切歌＝persistentID 變更**，forceRefresh 對同曲重發事件不算）／`realTrackChangeClearsOverrideAndCenters`／`programmaticCenteringDoesNotSetOverride`（程式化捲動回呼不得誤判為使用者滑動） | ✅ M7-P1（邏輯層） |
| H-06 | 切專輯→重建條目＋中心向兩側預取 | Plan §4.8 | **重建**：`albumChangedQueriesUsingEventKeyNotCurrentTrack`（用事件 albumKey 查詢，不重讀 currentTrack——後者在快速切歌時會拿到下一張專輯）＋`staleAlbumLoadDoesNotOverwriteNewer`（albumGeneration 守衛）＋`albumChangeResetsOverride`。**預取（M7-P2）**：視窗＝`CoverFlowPrefetchWindowTests` 6 條（距離序、方向優先、兩端 clamp、不含中心、不重複）；觸發＝`loadCompletionPrefetchesAroundCenter`／`userScrollPrefetchesInScrollDirection`／`keyboardStepPrefetchesInStepDirection`／`albumChangeCancelsPrefetch`／`tabDeactivationCancelsPrefetch`／`hiddenTabDoesNotPrefetch`／`stalePrefetchCommandsAreSkipped`；排程＝`prefetchKeepsAEInFlightAtMostOne`（單槽不變量）／`explicitRequestIsServedBeforePendingPrefetch`（中心優先）／`explicitRequestJoinsPendingPrefetch`（同 ID 共享）／`prefetchReplacementDropsUnstartedEntries`（可取消）／`prefetchSkipsMemoryAndDiskHits`／`failedIDIsNotRefetchedUntilBackoffElapses`（退避）。**AE 公平性的邊界**：單元層證明的是「送進 AE 的 artwork ≤ 1」這個排程不變量；「monitor 最多多等 1.5s」由該不變量＋`SBApplication.timeout` 推出，真機時序待 M8 | ✅ M7-P2（邏輯層） |
| H-07 | 封面緩存：冷啟動磁盤即顯；損毀檔容錯（刪除重取） | Plan §4.8 | `ArtworkDiskCacheTests` 25 條（全部走臨時目錄，不碰真實 Caches）：**冷啟動**＝`entriesSurviveReinstantiation`／`ArtworkServiceTests.diskHitPopulatesMemoryWithoutAE`（磁碟命中回填記憶體且不打 AE）；**損毀容錯**＝`truncatedFileIsDeletedAndMisses`（大小不符）／`undecodableDiskEntryIsRemovedAndRefetched`（位元組解不開）／`corruptMetadataClearsAndRecovers`／`unknownVersionIsTreatedAsCorrupt`／`invalidEntryValuesAreDropped`／`orphanFilesAreRemovedOnLoad`／`staleTempFilesAreRemovedOnLoad`；**身分驗證**＝`mismatchedPersistentIDIsTreatedAsMissAndDeleted`（完整 SHA-256 檔名＋metadata 記 persistentID，碰撞不得回傳別首歌的封面）；**LRU**＝`evictsLeastRecentlyAccessedByCount`／`ByBytes`／`accessSequenceIsMonotonicAcrossRestart`（單調序，不用會倒退的 wall-clock）；**原子寫入**＝`firstStoreMovesTempIntoPlace`／`overwriteReplacesExistingFile`（move 與 replaceItemAt 兩條路徑各自驗）；**併發**＝`concurrentStoresForDistinctIDsAllPersist`／`interleavedStoresKeepInvariants`；**安全**＝`nonHexKeysNeverTouchFilesystem`／`corruptMetadataLeavesForeignFilesAlone`（清除只限快取自身的三類檔案）／`unwritableDirectoryDegradesToMiss` | ✅ M7-P2（邏輯層） |
| H-08 | 無封面占位＝六角形 logo 暗紋，佈局不跳動 | Plan §4.8 | 已實作：佔位與封面**同尺寸固定 frame**（`CoverFlowItem.face` 的 `.frame(width:height:)` 在兩個分支之外），六角形 logo 走 `BundleAssets.aboutLogo` opacity 0.12 暗紋；目視待 M8 | ⬜ M8 目視 |
| H-09 | 左右方向鍵步進（窗口內按鍵，無全局監聽） | Plan §4.8 | 已實作 `.focusable()` ＋ `.onKeyPress(.leftArrow/.rightArrow)`（**窗口內**，無全域 hook——全域監聽會誤傷其他 app）；`stepMovesCenterByOffset`／`stepIsClampedAtBothEnds`（兩端不越界）／`keyboardStepSuppressesAutoCenter`（步進與拖曳同樣算使用者接管）／`stepOnEmptyListIsNoOp`；焦點行為待 UITests | ✅ M7-P1（邏輯層） |
| H-10 | 純展示：無雙擊播放、無任何播控動詞（決策 6） | Plan 決策 6 | **編譯期證據（強於任何運行時斷言）**：`MusicControlling` 協議六個方法（`playerState`／`currentTrack`／`currentLyrics`／`albumTracks`／`setLyrics`／`artworkData`，`Services/Music/MusicControlling.swift:68-75`）**無任何播控動詞**——Cover Flow 在編譯期就不可能觸發播放；`grep onTapGesture Features/CoverFlow/*.swift` 零命中。**M8 明確不寫 live UITest**：原設想的「雙擊後 persistentID 不變」在 Music 播放時會因自動跳曲假失敗，且 test runner 讀 Music 需其自身的 TCC 授權；且該斷言在「無播控邏輯」與「有播控 bug」兩種情況下都通過，無區分力 | ✅ M8（靜態／編譯期證據） |
| H-11 | 穩定排序：disc→track number→AE 返回序 fallback（⚠️兼容修正，待簽字） | Plan §4.8 | `itemsUseStableDisplayOrder`（多碟亂序輸入 → disc→track 排序）；排序函式 `sortedForDisplay()` 為 M2 既有實作 | ⚠️ 已實作，待用戶簽字（兼容修正） |

**總計 128 條**（含 4 條子條目 B-03a／B-11a／C-10a／D-01a；舊寫的「123」是不含子條目的計數，2026-09-05 依 awk 按狀態列實測更正）。

**核表命令**（`grep -c '⬜'` 會數到圖例行，不可用）：
```bash
awk -F'|' '/^\| [A-H]-[0-9]+[a-z]? \|/{n++; s=$(NF-1);
  if(s~/⬜/)b++; else if(s~/⚠️/)w++; else if(s~/✅/)o++}
  END{print "總計"n, "✅"o, "⚠️"w, "⬜"b}' ACCEPTANCE.md
```
**狀態欄不得同時出現兩種狀態字形**——否則統計結果會依賴 awk 的判斷順序（M8 評審發現）。

## 附錄：M6 行為真源複核（2026-08-14）

逐行核對 `lyrics_fetcher.py` 的 Batch 段（HTML py:205-263／JS py:554-740／後端 py:1154-1196, 2218-2255）後，對 C 段做三類修正：

| 類別 | 處置 |
|---|---|
| **事實錯誤 1 條**：C-18 與 Plan §4.10 稱「批處理期間 isBusy 按鈕全禁＋輪詢停」為主防線，實際只有 `runAlbumBatch` 調 `toggleBusy`；Fetch Missing／Import All 只禁自己按鈕，Import Selected 完全不禁，三者輪詢照跑 | C-18 改寫為逐操作禁用範圍；**session ID 守衛由「縱深」升為唯一防線**（Plan §4.10 對應句同步作廢） |
| **遺漏 7 條**可觀察行為（Import All 空集提示、載入三態狀態文案、header 專輯名三態、Batch 狀態欄不隨語言變、載入失敗兩態、進度文案全集、Import Selected 文案帶句點） | 補為 C-22 ~ C-28 |
| **原版缺陷 2 條**：`has_lyrics` 算了不用導致缺詞判定語義分裂；`fetch_single_missing` 會把 "Genius Error: …" 當歌詞並經 Import All 寫入音樂檔 | 補為 C-29（用戶拍板採 trim 語義）、C-30（按 B-11a 先例修正） |

由此產生的真實競態（原版存在，非理論）：Fetch Missing 進行中切專輯 → 輪詢照跑觸發 `batchData = []` 重載（py:492-497）→ 舊循環繼續往已被替換的陣列元素寫入並重繪新列表 → 進度錯亂、命中丟失。新版以 sessionID 守衛在每步回寫前校驗。


## 附錄：M6 收尾（2026-08-23）

### A1 根因：`runner hung before establishing connection` 的真正原因

上游 `docs/plans/2026-08-14-m6-batch.md` §8.3 記「`-skip-testing` 排除該用例後單元 target 恢復全綠
（三次一致），故 destabiliser 確為該用例本身，非環境」——**此歸因錯誤，本次以實驗推翻**。

真正根因：test host app 啟動時讀 Keychain 的 `GENIUS_ACCESS_TOKEN`
（`AppModel.live()` → `KeychainStore.read` → `SecItemCopyMatching`）。app 為 ad-hoc 簽名，
**每次重建重簽後代碼簽名標識改變** → Keychain item 的 ACL 失配 → 系統彈 SecurityAgent 授權框
→ `SecItemCopyMatching` 阻塞 → app 啟動不完成 → runner 連不上。
當時第一次跑觸發彈窗、人點掉後 ACL 恢復，之後三次自然全綠；與被排除的用例無關——把時間先後誤讀為因果。

決定性證據：繞開 xcodebuild 直接啟動重簽後的 app，SecurityAgent 進程數 **0 → 1**。

修法：scheme 的 test action 注入 `AZW_UNIT_TEST_HOST=1`（`project.yml`），`AppModel.live()` 檢測後
改用 `EphemeralSecretStore` 並跳過 legacy 遷移（遷移會讀 `.env` 並**寫回** Keychain，寫入同樣觸發授權框）。
UITests 在 `AppUITestCase` 顯式設回 `"0"`，仍走真實 Keychain，A-05 的 token 預填驗收不受影響。
補上的正是 Plan §4.9「測試禁讀真實 .env／真實 Keychain」的實現缺口。
驗證：同樣的重建＋重簽場景，SecurityAgent 0 → 0，全量單元測試綠。

### 另一個獨立缺陷：`LyricsGate` 單槽 continuation

兩個等待者時後者覆蓋前者，被覆蓋者永不 resume；`await` 該 task 的測試永久掛起。
與上述症狀**獨立**——上游只看到 `runner hung` 的文字卻在此用例上找原因，故熔斷。
已改為 broadcast 多等待者，並以四條語義鎖定測試釘住。

### UITests 未驗（環境限制）

本次無法執行 UITests：runner 在初始化階段即報
`Failed to initialize for UI testing: Timed out while enabling automation mode.`
該階段早於任何測試代碼加載，與本次改動無關；`automation mode` 需 GUI 層授權
（系統設定 → 隱私與安全性 → 輔助功能），無人值守下不可為。
**A／C／D／E 段中依賴 UITests 的條目本次未重跑**，留待有人值守時驗證。
