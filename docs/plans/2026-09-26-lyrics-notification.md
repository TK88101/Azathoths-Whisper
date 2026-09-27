# 歌詞寫入成功的系統通知 —— 實施計劃（v1.2 定稿）

- 日期：2026-09-26（v1.1 同日修訂）；2026-09-27 v1.2 定稿（Codex 對抗評審兩輪收斂，附錄 A.3）
- 基線：`origin/main` `98af41f`（v2.0.1）
- 分支：`feat/lyrics-notification`
- 狀態：**定稿**（2026-09-27）。Codex 評審 R1 14 條＋R2 回應已裁決（附錄 A.3）；評審產生的兩項新價值判斷已由使用者拍板（⑦⑧）。
- 已拍板：①Batch 全部失敗要彈失敗通知；②通知開關本次一併做，放在 App 內 Settings，預設開；③分支名；
  ④（2026-09-26）通知版式＝**樣式 A**（§3.1，原計劃版）；⑤（2026-09-26）「All saved.」**這次一起修**，文案＝**候選 1**，部分失敗**不放彩紙**（§4.3a）；
  ⑥（2026-09-26 新增需求）Batch 寫入成功後**自動切回 Editor 分頁**（§4.6）；
  ⑦（2026-09-27）切頁到期時有任何彈框（Settings／About modal、Import All 確認框、Batch 提示框）開著 → **本次不切**；
  ⑧（2026-09-27）等待期間只有「真正開始新工作」才取消切頁（Fetch Missing、Import Selected、確認後的 Import All、載入／切換專輯）；點選曲目看預覽不取消。
  ④⑤ 的選擇依據：樣式參考頁 https://claude.ai/artifact/CFCdb8pZpp7MCoTLbqA9Nm（使用者在頁上點選）。
- 本次迭代同時包含（使用者 2026-09-26 指定）：**Cover Flow 隨 Music 切曲自動滑動（帶動畫）**，需求與計劃見 `2026-09-26-coverflow-follow-playback-slide.md`；兩者同分支、同一次發版。

## 0. 複述

歌詞寫入音樂檔成功後，右上角彈出 macOS 系統通知：
- **Editor**：單首寫入，一首一則，內容含「App 名稱、專輯與歌名、歌詞寫入成功」。
- **Batch**：Import All 整批只彈**一次**匯總，不逐首打擾。
- 使用者可在 Settings 關閉通知，預設開啟。

## 1. 寫入入口盤點（全部走 `MusicControlling.setLyrics`）

| 入口 | 位置 | 現有回呼 | 通知策略 |
|---|---|---|---|
| Editor「寫入」 | `EditorViewModel.save()` | `onSaved(id, text)`／`onSaveFailed(id)` | 單首通知（成功才彈） |
| Batch「Import Selected」 | `BatchViewModel.importSelected()` | `onLyricsWritten(id, text)` | 單首通知（同 Editor 格式） |
| Batch「Import All」 | `BatchViewModel.confirmImportAll()` | 逐首 `onLyricsWritten` | 迴圈結束後**一則匯總** |

`LyricsFlow` 沒有自己的寫入路徑，它的 `setLyrics` 只在 UITest 替身裡，所以不用處理。

**不能**把通知掛在逐首的 `onLyricsWritten` 上，否則 Import All 會一首彈一次。Import All 需要在迴圈結束後給出一個匯總事件。

## 2. 技術選型

採用 **`UNUserNotificationCenter`**（UserNotifications framework，macOS 14 部署目標可直接用，不必加第三方依賴）：
- 通知來源會自動顯示 App 圖示與 `CFBundleDisplayName`。
- App 在前景時，系統預設**不**顯示橫幅。Editor 寫入時使用者一定在 App 裡，所以必須實作
  `userNotificationCenter(_:willPresent:)`，回傳 `[.banner, .list]`。
- 權限：在 `applicationDidFinishLaunching` 呼叫一次 `requestAuthorization(options: [.alert])`（不要聲音，避免打擾）。
  不要等第一次寫入才要權限，否則第一則通知會被權限對話框吃掉。
- 不需要 entitlement（`ENABLE_APP_SANDBOX: NO`）。風險是 **ad-hoc 簽名**（`CODE_SIGN_IDENTITY: "-"`），
  每次重簽後系統的通知設定可能被視為新 App、重問一次權限。要實機驗證（§6 V5），不影響設計。

不採用 `osascript display notification`：來源會顯示成「Script Editor」，不符合「顯示軟體名稱」的需求。
不採用 `NSUserNotification`：macOS 11 起已棄用。

## 3. 文案設計

### 3.1 單首（Editor／Import Selected）

```
[icon] 阿撒托斯的低語                ← title：app_title（跟隨 App 語言）
       Opeth ·《Blackwater Park》      ← subtitle：藝人 · 專輯（專輯空白則只有藝人）
       ✓「The Drapery Falls」歌詞寫入成功 ← body
```

歌名放在 body，不和專輯擠在 subtitle：subtitle 單行容易被截斷，歌名是最重要的資訊。

**v1.1 拍板（2026-09-26）：採此版式（樣式 A）。** 實際文字以 §3.3 字串表為準，**不加** ✓／✕ 前綴
（上面與 §3.2 的 ✓／✕ 只是示意；使用者選定的參考頁版本不含前綴）。
「macOS 橫幅不另印 App 名稱、title 不會重複」屬推測，由 V2 實機確認；若實機確實重複，回報使用者再議，不自行改版式。

### 3.2 Batch 匯總（Import All）

以**專輯**為主體，附上數量；歌名最多列 3 首，其餘寫「等 N 首」。Batch 本身限定當前專輯＋同藝人，所以用專輯當主體最自然；
通知 body 只有 2～4 行，列出全部歌名一定被截斷。

| 情況 | body（zh-Hant） |
|---|---|
| 全成功，且寫入數＝專輯曲目數 | ✓ 整張專輯 8 首歌詞寫入成功 |
| 全成功，只寫了部分 | ✓ 5 首歌詞寫入成功：The Leper Affinity、Bleak、Harvest 等 5 首 |
| 部分失敗 | 6 / 8 首寫入成功，2 首失敗：Dirge for November、The Funeral Portrait |
| 全部失敗（已拍板要彈） | ✕ 8 首歌詞全部寫入失敗 |

- 部分失敗時列出**失敗**的歌，因為那是使用者要處理的。
- title／subtitle 同 §3.1（subtitle 用 Batch 的 `albumName` 與首曲藝人）。
- `threadIdentifier` 設為專輯名，同一張專輯的通知在通知中心收成一組。
- 被 sessionID 作廢的批次（中途切專輯）照樣彈匯總，內容以**實際寫入的結果**為準。
  理由同 `onLyricsWritten` 的註解：檔案已經被寫了，這是事實事件。

### 3.3 字串（加進 `Resources/Localizable.xcstrings`，三語齊備）

| key | en | zh-Hant | ja |
|---|---|---|---|
| `notify_single_ok` | Lyrics saved for "%@" | 「%@」歌詞寫入成功 | 「%@」の歌詞を書き込みました |
| `notify_batch_full` | Lyrics saved for all %lld tracks | 整張專輯 %lld 首歌詞寫入成功 | アルバム全 %lld 曲の歌詞を書き込みました |
| `notify_batch_some` | Lyrics saved for %lld tracks: %@ | %lld 首歌詞寫入成功：%@ | %lld 曲の歌詞を書き込みました：%@ |
| `notify_batch_partial` | %1$lld/%2$lld saved, %3$lld failed: %4$@ | %1$lld / %2$lld 首寫入成功，%3$lld 首失敗：%4$@ | %1$lld/%2$lld 曲成功、%3$lld 曲失敗：%4$@ |
| `notify_batch_all_failed` | Failed to save lyrics for %lld tracks | %lld 首歌詞全部寫入失敗 | %lld 曲すべての書き込みに失敗しました |
| `notify_more` | and %lld more | 等 %lld 首 | ほか %lld 曲 |
| `settings_notify_label` | Notifications | 通知 | 通知 |
| `settings_notify_toggle` | Notify when lyrics are saved | 歌詞寫入後顯示系統通知 | 歌詞の書き込み後に通知する |

注意：語言覆寫走 per-app `AppleLanguages`，重啟才生效（E-09），通知文案跟著 `Bundle.main` 的語言走，和 UI 一致。

## 4. 設計與改動

### 4.1 新增 `Services/Notifications/`

- `LyricsNotificationContent.swift` —— **純函式**，完整單元測試。
  ```swift
  struct NotificationPayload: Equatable, Sendable { let title, subtitle, body: String; let threadID: String? }
  struct BatchWriteSummary: Equatable, Sendable {
      let artist, album: String
      let albumTrackCount: Int     // 判斷「整張專輯」：succeeded.count == albumTrackCount 且 failed 為空
      let succeeded: [String]      // 歌名，依寫入順序
      let failed: [String]
  }
  enum LyricsNotificationContent {
      static func single(artist:title:album:bundle:) -> NotificationPayload
      static func batch(_ summary: BatchWriteSummary, bundle:) -> NotificationPayload?   // 兩清單皆空 → nil
  }
  ```
  - title 用 `String(localized: "app_title", bundle:)`（R1-12：`AppInfo.title` 是寫死英文，不能沿用；shell／視窗的固定產品名不動）。
  - 格式化用 localized format API，歌名只作參數，不進格式字串（`%` 安全）。`bundle` 參數供三語測試注入對應 `.lproj`，生產用 `.main`。
- `LyricsNotifier.swift`
  - `@MainActor protocol LyricsNotifying: AnyObject { func requestAuthorization(); func post(_: NotificationPayload) }`（R1-8）。
  - `NotificationCenterClient`（薄 protocol，同步呼叫＋`@Sendable` completion，R1-13）：`requestAuthorization(options:completion:)`、`add(_:completion:)`。
    生產實作 `SystemNotificationCenter` 包 `UNUserNotificationCenter.current()`，並在 init 設 delegate＝`ForegroundPresenter`（保留強參照）。
  - `ForegroundPresenter`：`NSObject, UNUserNotificationCenterDelegate`，只實作 `willPresent` 回 `[.banner, .list]`，不碰 AppModel。
  - `SystemLyricsNotifier`（`@MainActor`）：`post` 建 `UNMutableNotificationContent`（title／subtitle／body／threadIdentifier），identifier＝UUID、trigger＝nil（立即）；
    `add` 的 error 只在 completion 裡以 `os_log` 記**錯誤類型**（不記曲名、歌詞），**不回拋、不影響寫入流程**。授權同理：`options: [.alert]`，失敗只 log。
  - `NoopLyricsNotifier`：UITest 組裝與單元測試 host 使用。
- **delegate 安裝時機（R1-1 裁決）**：在 `SystemNotificationCenter.init`（隨 `AppModel.live()` 建立）設定即可。
  依據：本次沒有「啟動時已送達、需要處理回應」的通知（點擊行為為 §7 非目標），且第一則 `post` 只在使用者寫入歌詞後才發生，delegate 必定已就位。
  **日後若加通知點擊／啟動回應，必須把 delegate 安裝移到 app 啟動階段（`applicationWillFinishLaunching`）。**
- **授權策略（R1-7 裁決）**：不緩衝、不等待授權結果；`post` 照發、寫入不受阻，系統未授權時靜默丟棄。不加 process-lifetime 旗標：
  `requestAuthorization` 系統冪等，只在首次提示（Apple 文件）。

### 4.2 Editor

`EditorViewModel.save()` 在 hop 前同處擷取 `boundTrack`（與 `boundTrackID` 同時賦值，`EditorViewModel.swift:92-93`），避免 D8③ 的「寫 A、回報成 B」。
新增回呼 `onSavedTrack: ((TrackInfo) -> Void)?`，寫入成功時緊接在 `onSaved` 之後送出（`onSaved` 簽名不動，LyricsFlow 既有接線與測試不受影響）。
AppModel 接 `onSavedTrack` → `postIfEnabled(.single(...))`。Editor 不自動切頁（本來就在 Editor）。

### 4.3 Batch：完成事件（R1-2／R1-5／R1-10 裁決）

新增事實事件（**由 BatchViewModel 判定 outcome，AppModel 與通知 formatter 不重算**）：
```swift
enum BatchImportOutcome: Equatable { case allSucceeded, someFailed, allFailed, stale }
enum BatchImportResult: Equatable {
    case single(artist: String, title: String, album: String, isStale: Bool)   // Import Selected，只在 didWrite 時送
    case batch(BatchWriteSummary, BatchImportOutcome)                          // Import All
}
var onImportFinished: ((BatchImportResult) -> Void)?
```
- `importSelected()`：`didWrite == true` 才送。非 stale 時送出位置在「套用列表、`statusText = Saved.`、`confettiTrigger += 1`」**之後**；
  stale 時仍送（`isStale: true`，檔案已寫＝事實事件），但不改狀態欄與彩紙（原版行為）。false／throw 不送（單首失敗通知為非目標）。
- `confirmImportAll()`：
  - 在 `toSave` 與 `session` 同一同步區段，從 `toSave` 快照 `artist`（首曲）、`album`（首曲）、`albumTrackCount`（`tracks.count`）（R1-5：
    切專輯會立即清空 `tracks`、把 `albumName` 改成 Loading）。
  - 迴圈內每次 `setLyrics` 回來**先**記入 succeeded／failed（`false` 與 throw 都算失敗），下一輪開頭才檢查 stale；stale 以 `break` 離開。
  - 單一出口決定 outcome：stale → `.stale`；否則 failed 空 → `.allSucceeded`、succeeded 空 → `.allFailed`、其餘 `.someFailed`。
  - 同一個 switch 決定狀態欄、彩紙、完成事件（§4.3a），`onImportFinished` 在狀態欄與彩紙**之後**送出。
- `onLyricsWritten`（逐首，Cover Flow 徽章）維持原樣，不承擔通知。

### 4.3a Import All 結束文案與彩紙（偏離原版 py:736，ACCEPTANCE C-31 ⚠️）

| outcome | Batch 狀態欄（寫死英文，E-05；帶句點，C-28） | 彩紙 | 通知 |
|---|---|---|---|
| `.allSucceeded` | `All saved.`（不變） | 放 | 匯總 |
| `.someFailed`（例 6/8） | `Saved 6 of 8. 2 failed.`（新增 `StatusText.savedSomeFailed(saved:of:failed:)`） | **不放** | 匯總 |
| `.allFailed` | `Save failed.`（沿用 `StatusText.batchSaveFailed`） | 不放 | 匯總 |
| `.stale` | 不寫（維持原版） | 不放（維持原版） | 匯總（只含實際寫入） |

- 現況核對：`.allFailed` 在現行程式碼同樣顯示 `All saved.`＋彩紙（`BatchViewModel.swift:348-350`），一併屬於本條偏離。
- 既有斷言 `BatchViewModelTests.swift:400、421` 都是全成功路徑，不需要修改。

### 4.4 通知開關（Settings）

- `ConfigStore` 新增 `Key.notificationsEnabled`（UserDefaults），讀取 `object(forKey:) == nil ? true : bool(forKey:)`，**預設開**。
- `SettingsViewModel.Group` 新增 `.notifications`；`open(...)` 帶入目前開關值；`Toggle` **切換即存**（回呼 `onNotificationsToggled(Bool)` → AppModel 存 ConfigStore）。
- 選單 `Settings` 新增第三項 `Notification Settings...`（A-07：硬編碼英文）；同步更新 A-07 驗證方式（`testColdStartInJapaneseLocalizesUIButNotMenus` 補斷言第三項）。
- modal 標題英文覆寫（D-03 慣例）：`StatusText.notificationSettingsTitle = "Notification Settings"`。
- 關閉開關只是不送通知，**不**撤銷系統權限。從關切到開時呼叫 `notifier.requestAuthorization()`（R2-7：與 `start()` 重複無害）。
- 新增驗收條目 D-14（預設開、切換即存、重啟後保持）。

### 4.5 AppModel 組裝

- `init` 新增 `notifier: any LyricsNotifying`（**不給預設值**，漏注入＝編譯錯誤）與 `batchSwitchClock: any PollClock = SystemPollClock()`。
- 建構點共**四處**（R1-9）：`live()`（生產注入 `SystemLyricsNotifier`；單元測試 host 分支注入 Noop）、`makeLyricsFlowUITestModelIfRequested`（Noop）、
  `makeCoverFlowUITestModelIfRequested`（Noop）、`AppModelTests.makeModel`（**Spy**，驗 post、授權與切頁）。
- `start()`（`didStart` 守衛內）：開關為開才 `notifier.requestAuthorization()`；開關為關時不要權限，等打開那一刻。
- `postIfEnabled(_:)`：每次讀 `configStore.notificationsEnabled`，開才 `notifier.post`。
- 接線：`editor.onSavedTrack` → 單首通知；`batch.onImportFinished` → 通知＋（條件成立時）排切頁。

### 4.6 Batch 寫入成功後自動切回 Editor 分頁

- 需求原話：「Batch 寫入成功以後，介面也得跟 Editor 一樣，在寫入成功後的特定時間內，自動切換成 Cover Flow。」
- 現況（已核）：Batch 寫到當前播放曲時，`LyricsFlowModel.batchSaved` 已讓 Editor 分頁內的畫面在 `riseDelay` 後升回 Cover Flow
  （`Features/LyricsFlow/LyricsFlowModel.swift:149`），但使用者停在 Batch 分頁看不到。缺的是**分頁切換**。
- 拍板（使用者 2026-09-26／27）：
  - **觸發**：只有 `.batch(_, .allSucceeded)` 與 `.single(isStale: false)`。`someFailed`／`allFailed`／`stale`／`single(isStale: true)` **絕不排程**。
  - **目的地**：`tab = .editor`，畫面照現有規則（有詞＝Cover Flow、缺詞＝Editor），不強制 Cover Flow。
  - **時機**：等 `LyricsFlowModel.riseDelay`（＝`ConfettiTiming.lifetime`，彩紙撒完）。起點＝該次成功**觸發彩紙之刻**（`onImportFinished` 在彩紙之後送出）。
    這是**獨立排程**（注入的 `batchSwitchClock`），只共用時長常數，不與 LyricsFlow 的逐首升回計時同步（R1-6）。
  - **到期時有彈框 → 本次不切**（⑦）：`activeModal != nil`、`batch.isConfirmingImportAll`、`batch.alertMessage != nil` 任一成立即放棄。
  - **取消**（⑧）：`BatchViewModel.operationGeneration`（單調遞增，`@ObservationIgnored`）在真正開始新工作時遞增——
    `fetchMissing` 過了「無缺詞」早退之後、`importSelected` 過了兩個早退之後、`confirmImportAll` 過了「無有詞曲」早退之後、`loadAlbum` 開頭、`handle(.albumChanged)`。
    `select(_:)`（曲目預覽）與 `requestImportAll`（只開確認框，由⑦處理）**不**遞增。AppModel 排程時擷取，到期比對不等即放棄（拉取式，R1-3）。
- AppModel 實作：
  - `pendingSwitchTask`；新成功事件 → cancel 舊的、重排（連續 Import Selected 以最後一次為準）。
  - 公開 `select(_:)`（使用者導覽）**任何呼叫都取消** `pendingSwitchTask`，**含選到目前同一分頁**（契約，有測試釘住；防 Batch→Editor→Batch 的 ABA，R1-4）。
  - 原 `select` 內容抽為私有 `applySelection(_:)`；自動切頁走 `applySelection(.editor)`，不經公開 `select`，避免 task 取消自己（R2-4）。
  - 到期檢查順序：未取消 ∧ `tab == .batch` ∧ generation 相同 ∧ 無彈框 → `applySelection(.editor)`。
- 偏離原版（原版匯入後停在 Batch）：ACCEPTANCE C-32 ⚠️。

## 5. 任務清單（最小可驗證單元，依序；TDD：每項先紅後綠）

| # | 任務 | DoD |
|---|---|---|
| T1 | `LyricsNotificationContent`＋`BatchWriteSummary`／`NotificationPayload`；§3.3 的 8 個新鍵加入 `Scripts/make_xcstrings.py` 的 `NEW_KEYS` 並重生 catalog | `LyricsNotificationContentTests` 綠：§3.2 四情況、3 首＋「等 N 首」截斷、專輯空白 subtitle、零寫入回 nil、歌名含 `%`／引號、三語 title 與 body 精確字串；`LocalizationTests` 覆蓋新鍵；`python3 -m unittest` 綠 |
| T2 | `LyricsNotifying`／`NotificationCenterClient`／`SystemLyricsNotifier`／`ForegroundPresenter`／`Noop` | Spy center 測試綠：request 的 title／subtitle／body／threadIdentifier、authorization options＝`.alert`、`add` error 被吞且呼叫端不受影響、presenter 回 `[.banner, .list]` |
| T3 | `ConfigStore.notificationsEnabled` | 預設 true、寫 false 後新實例讀回 false |
| T4 | `BatchViewModel`：outcome、快照、`onImportFinished`、§4.3a 文案與彩紙、`operationGeneration`、`StatusText.savedSomeFailed` | `BatchViewModelTests`／`BatchWriteReportTests` 新案綠：四種 outcome 的狀態欄／彩紙／事件；stale 中途只含實際寫入且 metadata 為舊專輯；Import Selected 成功／stale／false／throw；generation 的五個遞增點與兩個不遞增點；既有測試全綠 |
| T5 | `EditorViewModel.onSavedTrack` | 成功送原曲 `TrackInfo`、失敗／throw 不送；save 期間換歌仍回報原曲 |
| T6 | Settings `.notifications` 群組、Toggle、標題、選單第三項 | `SettingsViewModelTests`：open 帶入值、切換即回呼、標題英文 |
| T7 | AppModel 組裝＋四處注入＋授權＋`postIfEnabled`＋§4.6 切頁 | `AppModelTests`（Spy notifier＋GatedPollClock 分開注入）：開關開／關的 post；start 授權只在開時；關→開觸發授權；allSucceeded 到期切 Editor；someFailed／allFailed／stale／single stale 不排程；到期前手動 `select`（含同分頁）取消；Batch→Editor→Batch 不被切；新工作（generation 變）取消；彈框（modal／確認框／alert）開著不切；連續成功重排；整合：Import All 首曲較早寫入、LyricsFlow 已升回後，切頁計時到期才切 |
| T8 | ACCEPTANCE：C-31、C-32 ⚠️、D-14、A-07 驗證方式更新；UI 測試斷言選單第三項 | 條目齊、簽字日 2026-09-26／27 |
| T9 | 全量單元測試、`coverage_gate.sh`、`no_playback_gate.sh`、Scripts 測試 | 全綠（已知基線紅另列）；Services/ 覆蓋率 ≥ 80% |

影響面：`Services/Notifications/`（新）、`Features/Batch`、`Features/Editor`、`Features/Settings`、`App/AppModel.swift`、`App/AzathothsWhisperApp.swift`、
`App/UITestSupport/` 兩個組裝入口、`UI/StatusText.swift`、`Resources/Localizable.xcstrings`、`Scripts/make_xcstrings.py`、`ACCEPTANCE.md`、對應測試。
新增原始檔後跑 `xcodegen generate`。
風險與回退：通知層失敗只 log，不影響寫入；切頁邏輯集中在 AppModel 一處，回退＝移除 `onImportFinished` 的排程分支。

## 6. 驗證（V 項）

| # | 項目 | 環境 |
|---|---|---|
| V1 | `xcodebuild test` 全綠（含新測試） | Mac |
| V2 | Editor 寫入時 App 在前景，右上角出現橫幅，來源是 App 名稱與圖示，三行內容正確（順帶確認 title 是否與系統 App 名重複） | 實機 |
| V3 | Batch Import All 8 首只出現 1 則；故意讓 1 首失敗（例如唯讀檔），通知變成部分失敗，狀態欄顯示 `Saved 7 of 8. 1 failed.`、不放彩紙、**不**切分頁 | 實機 |
| V4 | Settings 關閉開關 → 寫入不彈通知；重啟後仍是關閉；再打開 → 恢復 | 實機 |
| V5 | ad-hoc 重簽後的權限行為（會不會每次重問）；系統設定裡關掉通知 → 靜默、寫入照常 | 實機 |
| V6 | 三語切換重啟後，通知文案（含 title）跟著變 | 實機 |
| V7 | Batch 分頁：Import All 全成功、Import Selected 成功 → 彩紙撒完後自動切回 Editor 分頁（當前曲有詞＝Cover Flow）；延遲期間手動切分頁、開 Settings、開始新工作則不切 | 實機 |

## 7. 非目標

- 寫入失敗時的**單首**通知（Editor 已有狀態欄與 `Failed to save`，不重複打擾）。
- 通知點擊行為（例如點擊後跳到該曲）：日後可加，本次點擊只會喚起 App。
- ~~修正部分失敗時「All saved.」文案~~ —— v1.1 改為本次範圍（§4.3a）。
- 聲音、通知分類按鈕（actions）。

## 8. 待確認（v1.1：兩項均已拍板，保留原文供追溯）

1. ~~§3.1 把 App 名稱當 title 會不會重複~~ → **採樣式 A**（2026-09-26，使用者在樣式參考頁選定），重複與否由 V2 實機確認。
2. ~~「All saved.」要不要順修~~ → **這次一起修**，文案候選 1，部分失敗不放彩紙（2026-09-26，§4.3a）。

## 附錄 A　評審記錄

### A.1 2026-09-26 Codex 評審 R1 —— 未產出（額度用盡）

- 呼叫：`codex exec -m gpt-5.6-terra -c model_reasoning_effort=medium "…" </dev/null`（900 秒上限）。
- 結果：`ERROR: You've hit your usage limit … try again at Sep 30th, 2026 4:25 PM.`，**零條評審意見**。
- 使用者裁定（2026-09-26）：不降級自評，也不以其他模型代替；能拍板的先拍板，**Codex 評審與實作等額度恢復後的下一個 session 再做**。
- 因此本計劃 v1.1 **未經任何對抗評審**。下一個 session 的 Codex 評審範圍＝全文，重點看 v1.1 新增的 §4.3a、§4.5 修正、§4.6。

### A.2 主 session 程式碼核對（非對抗評審，只記與程式碼不符之處）

| # | 位置 | 事實（出處） | 處置 |
|---|---|---|---|
| R0-1 | §4.5 權限請求 | `AppDelegate` 由 `@NSApplicationDelegateAdaptor` 建立，無 `AppModel` 參照（`App/AzathothsWhisperApp.swift:8-9`、`App/AppDelegate.swift`） | 改到 `AppModel.start()` |
| R0-2 | §4.5 Noop 注入 | UITest 有兩個組裝入口＋單元測試 host 分支（`App/AppModel.swift` `live()`、`App/UITestSupport/AppModel+LyricsFlowUITest.swift`） | 三處列全，`notifier` 參數不給預設值。**v1.2 更正（R1-9）：漏列 `AppModelTests.makeModel`，實為四處** |
| R0-3 | §4.4 選單 | 新選單項落在 A-07 覆蓋範圍（`ACCEPTANCE.md` A-07） | 同步更新 A-07 驗證方式＋新增開關驗收條目 |
| R0-4 | §4.2 Editor | `save()` 目前只在 hop 前擷取 `boundTrackID`／`lyricsText`（`Features/Editor/EditorViewModel.swift` `save()`），`boundTrack` 未擷取 | 維持 §4.2 原設計：同處加擷取 `boundTrack` |

### A.3 2026-09-27 Codex 對抗評審 R1／R2（gpt-5.6-terra，reasoning medium，read-only，對照程式碼）

額度已恢復。R1 產出 14 條（無 P0；P1×6、P2×8）；R2 回餵裁決與反駁，Codex 逐條回應後收斂，未進第 3 輪。

| # | 嚴重度 | 議題 | 裁決 | 理由／落點 |
|---|---|---|---|---|
| 1 | P1 | delegate 須在啟動完成前設定 | **駁回（結論 Codex R2 接受）**，理由措辭依 R2 修正 | 只用 willPresent；首則 post 在使用者寫入後；點擊為非目標。日後做點擊須移到啟動階段（§4.1） |
| 2 | P1 | summary 不足以判定全成功／stale | 採納 | `BatchImportOutcome` 由 VM 判定（§4.3） |
| 3 | P1 | 取消條件無事件來源 | 採納（拉取式 `operationGeneration`）；R2 指出「開確認框即遞增」過寬 → 交使用者拍板⑧ | §4.6 |
| 4 | P1 | 到期只查 tab 有 ABA | 採納；R2 補「自動切頁不可經公開 select」→ 採納 `applySelection` | §4.6 |
| 5 | P1 | stale 匯總 metadata 未快照 | 採納 | §4.3 |
| 6 | P1 | 與 LyricsFlow 升回並非同一計時 | 採納：起點＝觸發彩紙之刻、獨立 clock，只共用時長 | §4.6 |
| 7 | P2 | 授權冪等與首則競態 | 部分採納：不緩衝、不阻塞；駁回 process 旗標（系統冪等，R2 接受） | §4.1、§4.4 |
| 8 | P2 | Swift 6 隔離 | 採納 `@MainActor` protocol＋同步呼叫／`@Sendable` completion | §4.1 |
| 9 | P2 | 注入點漏列 AppModelTests | 採納（四處，測試注入 Spy） | §4.5、A.2 |
| 10 | P2 | `savedSomeFailed` 不存在、outcome 不應反推 | 採納 | §4.3a |
| 11 | P2 | catalog 由 `make_xcstrings.py` 全量重建 | 採納（加 `NEW_KEYS`） | T1 |
| 12 | P2 | `AppInfo.title` 是寫死英文 | 採納（`app_title`） | §4.1 |
| 13 | P2 | 缺 identifier 與系統層測試 | 部分採納：薄 client＋UUID；不測 identifier 格式（R2 接受） | §4.1、T2 |
| 14 | P2 | modal 情境未決 | 新價值判斷 → Codex R2 與主 session 同傾向「不切」→ **使用者拍板⑦** | §4.6 |
| R2 補 | — | stale／失敗不得排程；排程在彩紙之後；LyricsFlow 已升回後的整合測試；同分頁 select 也取消須成契約 | 全採納 | §4.3、§4.6、T7 |

原始輸出：session scratchpad `codex-r1.txt`／`codex-r2.txt`（不入庫）。

