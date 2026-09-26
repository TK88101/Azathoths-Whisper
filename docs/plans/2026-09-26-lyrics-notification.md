# 歌詞寫入成功的系統通知 —— 實施計劃（v1）

- 日期：2026-09-26
- 基線：`origin/main` `98af41f`（v2.0.1）
- 分支：`feat/lyrics-notification`
- 狀態：**待使用者審閱**。已拍板：①Batch 全部失敗要彈失敗通知；②通知開關本次一併做，放在 App 內 Settings，預設開；③分支名。

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

- `LyricsNotificationContent.swift` —— **純函式**，是整個功能唯一有邏輯的地方，完整單元測試。
  ```swift
  struct NotificationPayload: Equatable { let title, subtitle, body: String; let threadID: String? }
  enum LyricsNotificationContent {
      static func single(artist:title:album:) -> NotificationPayload
      static func batch(_ summary: BatchWriteSummary) -> NotificationPayload?
  }
  struct BatchWriteSummary: Equatable {
      let artist, album: String
      let albumTrackCount: Int     // 判斷「整張專輯」
      let succeeded: [String]      // 歌名，依寫入順序
      let failed: [String]
  }
  ```
  `succeeded` 和 `failed` 都為空（沒寫任何東西）時回傳 nil，不彈通知。
- `LyricsNotifier.swift` —— protocol `LyricsNotifying { func post(_: NotificationPayload) }`。
  - `SystemLyricsNotifier`：包 `UNUserNotificationCenter`，同時當它的 delegate（前景顯示橫幅）。錯誤只寫 `os_log`，**通知失敗絕不影響寫入流程**。
  - `NoopLyricsNotifier`：單元測試 host 與 UITest 使用。這樣測試不會碰真的通知中心，也不會跳權限框，比照 `EphemeralSecretStore` 的做法。

### 4.2 Editor

`EditorViewModel.save()` 已在 hop 之前擷取 `target`；再加上擷取 `boundTrack`，避免 D8③ 描述的「寫 A、回報成 B」問題。
`onSaved` 改為帶出 `TrackInfo`（或新增 `onSavedTrack`），在 `AppModel` 裡接上 notifier。

### 4.3 Batch

- `importSelected()`：成功時已有 `track`，送單首通知（透過新的回呼 `onImportFinished(.single(track))`）。
- `confirmImportAll()`：
  - 迴圈內收集 `succeeded`／`failed`：`didWrite == false` 和 `throw` 都算失敗。
  - **每一個結束路徑**（正常結束、stale 中途 return）都送出 `onImportFinished(.batch(summary))`，用 `defer` 收口，和 `isImportingAll` 的 `defer` 同一個位置。
  - 送出前檢查通知開關，但判斷放在 AppModel，ViewModel 不需要知道開關的存在。
- 可觀察行為不變：`statusText = allSaved` 與彩紙照原版（計劃 N4 的慣例），只多出通知。
  「All saved.」在部分失敗時不準確是既有問題，**這次不改**，另外記一筆。

### 4.4 通知開關（Settings）

- `ConfigStore` 新增 `Key.notificationsEnabled`，存在 UserDefaults。讀取時用 `object(forKey:) == nil ? true : bool(forKey:)`，
  **預設開**，不能用 `bool(forKey:)`，它的預設是 false。
- `SettingsViewModel.Group` 新增 `.notifications`，modal 顯示一個 `Toggle`，**切換就立即儲存**（toggle 的慣例），不另設 Save 鈕。
- 選單 `Settings` 新增第三項 `Notification Settings...`。依 A-07，選單文案硬編碼英文，和現有兩項一致。
- modal 標題照 D-03 的慣例用英文覆寫：`StatusText.notificationSettingsTitle = "Notification Settings"`。
- 關閉開關只是不送通知，**不**撤銷系統權限。系統層級關閉時 `post` 會靜默失敗，兩層各管各的。

### 4.5 AppModel 組裝

- `init` 多一個 `notifier: any LyricsNotifying` 參數，`live()` 注入 `SystemLyricsNotifier`，測試與 UITest 注入 `Noop`。
- 把 `editor.onSaved`、`batch.onImportFinished` 接到 `postIfEnabled(payload)`。
- `AppDelegate.applicationDidFinishLaunching` 呼叫 `notifier.requestAuthorization()`。
  開關為關時不要權限，等使用者打開開關的那一刻才要。

## 5. 測試（XCTest，比照現有 `Tests/` 結構）

- `Tests/Services/LyricsNotificationContentTests.swift`：§3.2 表格的四種情況，加上：列 3 首＋「等 N 首」截斷、專輯空白的 subtitle、零寫入回傳 nil、歌名含 `%`／引號。
- `Tests/Features/BatchViewModelTests.swift`：用 `MockMusicClient` 設定部分 `setLyrics` 回 false 或 throw，斷言：
  ①只送一次匯總；②成功／失敗名單正確；③迴圈中途 stale 仍送出匯總，且只含實際寫入的曲目；④Import Selected 送單首。
- `Tests/Features/EditorViewModelTests.swift`：成功送單首、失敗不送；save 期間換歌，通知內容仍是原曲。
- `Tests/Features/SettingsViewModelTests.swift`／`ConfigStore`：開關預設 true、關閉後持久化、關閉時 AppModel 不呼叫 notifier（用 spy notifier）。

## 6. 驗證（V 項）

| # | 項目 | 環境 |
|---|---|---|
| V1 | `xcodebuild test` 全綠（含新測試） | Mac（雲端 Linux 無 Xcode，無法建置） |
| V2 | Editor 寫入時 App 在前景，右上角出現橫幅，來源是 App 名稱與圖示，三行內容正確 | 實機 |
| V3 | Batch Import All 8 首只出現 1 則；故意讓 1 首失敗（例如唯讀檔），文案變成部分失敗 | 實機 |
| V4 | Settings 關閉開關 → 寫入不彈通知；重啟後仍是關閉 | 實機 |
| V5 | ad-hoc 重簽後的權限行為（會不會每次重問）；系統設定裡關掉通知 → 靜默、寫入照常 | 實機 |
| V6 | 三語切換重啟後，通知文案跟著變 | 實機 |

## 7. 非目標

- 寫入失敗時的**單首**通知（Editor 已有狀態欄與 `Failed to save`，不重複打擾）。
- 通知點擊行為（例如點擊後跳到該曲）：日後可加，本次點擊只會喚起 App。
- 修正部分失敗時「All saved.」文案不準確的問題（見 §4.3，另外立項）。
- 聲音、通知分類按鈕（actions）。

## 8. 待確認

1. §3.1 把 App 名稱當 title：macOS 通知的標頭本來就顯示 App 名稱（英文 `CFBundleDisplayName`），title 再放一次在地化名稱會重複兩次。
   **備案**：title 改放歌名（Editor）或專輯名（Batch），App 名稱交給系統標頭，版面更精簡。建議先照你的原始需求做，實機看過再決定。
2. 部分失敗時「All saved.」文案不準確的問題，要不要順便在這個分支修掉？
