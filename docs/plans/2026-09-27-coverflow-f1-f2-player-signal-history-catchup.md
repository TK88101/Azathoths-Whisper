# F1 封面慢一秒＋F2 剛播完的封面消失——實施計劃（v3 定稿：Codex R3 無 P0／P1）

上游：`docs/plans/2026-09-26-coverflow-follow-playback-slide.md`（下稱「②計劃」）§8.5、§8.6、附錄 A.9。分支 `wip/coverflow-slide-s9`。

## 0. 複述

②的平移已實作、實機通過（下一首／上一首會滑、不閃）。實機發現兩個要在發版前修掉的問題：
- **F1**：Music 已經換到下一首約一秒，Cover Flow 才開始滑。原因＝App 每 3 秒才問一次 Music（`NowPlayingMonitor.interval`，py:769）。
- **F2**：滑完之後，剛播完的那張從左鄰消失約 3 秒才回來。原因＝左側來自 `History.dat`，App 只在換歌當下與每 3 秒輪詢時讀它；換歌當下 Music 可能還沒寫完。

處置方向已由 Codex R1 辯論定案（②計劃 §8.6，**不重議**）：F1 採「通知觸發 `tick()`＋busy 補讀＋單飛合併」；F2 採「有界的履歴短重讀」，AC8 例外不動。

## 1. 目標與非目標

**目標**
- G1：換歌到 Cover Flow 開始滑，由「≤3 秒（平均約 1.5 秒）」縮到「通知送達＋一次 AE 讀取」。
- G2：自然播完換歌時，剛播完的那首在 Music 寫入 `History.dat` 之後的有界時間內出現在左鄰；平移中追上時不打斷平移（沿用②計劃 §3.2 規則 3）。
- G3：3 秒輪詢保留（通知漏送、Music 重啟時的保底），B-02 的「busy 期間不讀 Music」不變。

**非目標**：F3（另立計劃）；播控；1.x Python；A-10；CoverFlowUITests 四條過時閘門；AC8 例外的時長；牌組張數上限的來源；既有測試檔各自的開視窗／落定輔助。

## 2. 已核事實

| # | 事實 | 出處 |
|---|---|---|
| E1 | Music 在換歌（含暫停中按上一首／下一首）時廣播 `com.apple.Music.playerInfo`，帶 `PersistentID`、`Player State` | ②計劃 §8.5（2026-09-27 21:05–21:07 三次實測） |
| E2 | App 未監聽任何 Music 通知 | `grep DistributedNotificationCenter` 無結果 |
| E3 | `NowPlayingMonitor` 是 actor，`tick()` 內 `await music.nowPlaying()`；actor 重入下兩個 `tick()` 可交錯，後完成者覆寫 `lastSignature` | `Services/Music/NowPlayingMonitor.swift` |
| E4 | `forceRefresh()` 先清 `lastSignature` 再 `tick()`；busy 時記 `pendingForceRefresh`，最後一個來源解除時補做 | 同上 |
| E5 | `History.dat` 只在自然播完時寫：21:00:15 寫入（Dead Memories 播完），21:04–21:07 使用者多次按上一首／下一首，檔案修改時間仍是 21:00 | 本 session `ls -la`（21:26） |
| E6 | `Queue.dat` 存整份清單（含已播過的），**沒有**「目前位置」欄位；頂層有 `repeatMode`／`shuffleMode`；換歌不重寫（21:26 時修改時間仍是 14:06） | 本 session 量測器啟動快照 |
| E7 | 換歌當下 `LyricsFlowModel.nowPlaying` 排一次 `readSources`（檔案屬性變了才重讀）；之後只有 3 秒一次的 `refreshSources` | `Features/LyricsFlow/LyricsFlowModel.swift` |
| E8 | 平移中履歴追上（正式牌組左鄰變成同一首的 `h:` 卡）→ 暫留卡原位取代，過渡繼續、不打斷 | ②計劃 §3.2 規則 3；`LyricsFlowModelTests.historyCatchingUpBeforeTheSlideSettlesKeepsItGoing` |

**未核（實作前必須量到）**
- U1（F2 前提）：Music 寫 `History.dat` 相對於 `playerInfo` 通知的時差分布。量測器已在背景唯讀執行（見 §5.1）。
- U2（F1 前提）：收到通知的當下，AE 的 `current track` 是否已經是新曲。若否，通知觸發的讀取會讀到舊曲、等到下一次 3 秒輪詢才發現，F1 等於沒修。量法見 §5.1。

## 3. 設計

### 3.1 F1：換歌訊號（新系統邊界）

`Services/Music/PlayerChangeSignal.swift`：
```swift
/// Music 的換歌／播放狀態變化訊號。**只傳「變了」，不帶內容**：
/// 內容一律由 NowPlayingMonitor 經 AE 讀取（單一資料來源），通知的 userInfo 在此丟棄
@MainActor
protocol PlayerChangeSignaling: AnyObject {
    /// 冪等：重複呼叫不重複註冊
    func start(onChange: @escaping @MainActor () -> Void)
    func stop()
}

/// 生產實作：DistributedNotificationCenter 的 `com.apple.Music.playerInfo`（只收不發）
final class MusicPlayerInfoSignal: PlayerChangeSignaling { init(center:name:) … }

/// UI 測試組裝與單元測試 host 用
final class NoopPlayerChangeSignal: PlayerChangeSignaling { … }
```
- `name` 可注入（預設 `com.apple.Music.playerInfo`）：live 實作的單元測試用專屬的通知名自己 post，**不 post Music 的通知名**（會被使用者機上其他監聽者收到）。
- 測試替身 `Tests/Support/SpyPlayerChangeSignal.swift`：記 start／stop 次數、`fire()`。
- 隔離（R1-6）：`MusicPlayerInfoSignal` 整個型別 `@MainActor`，持有 observer token 與 `generation`。`addObserver(forName:object:queue: .main)` 的 block 只做 `MainActor.assumeIsolated { self?.deliver(generation: g) }`；`deliver` 比對世代與「仍在監聽」，`stop()` 移除 observer 並遞增世代——已排進主佇列、晚於 `stop()` 才執行的 block 因世代不符而丟棄。Swift 6 strict concurrency 編譯零警告為閘門。

`AppModel`：
- `init` 新增**必填**參數 `playerSignal: any PlayerChangeSignaling`（不給預設值，同 `notifier`：漏注入＝編譯錯誤）。
- `start()`：`monitor.start()` 之後 `playerSignal.start { [monitor] in Task { await monitor.playerDidChange() } }`（私有接線，不另開公開方法；R1-11）。
- `stop()`：`playerSignal.stop()`。
- `live()`：自動化測試（單元 host 或 UI 測試）→ `NoopPlayerChangeSignal`；否則 `MusicPlayerInfoSignal()`。Release 恆為 live。兩個 UI 測試組裝（`AppModel+LyricsFlowUITest`／`+CoverFlowUITest`）→ Noop。

### 3.2 F1：`NowPlayingMonitor` 的單飛讀取與通知補讀

「為什麼要讀」收成一個小列舉（R1-11：不用多個互相覆蓋的布林）：
```swift
/// 讀取的理由。busy 邊界上的去留各不相同，所以要分開記
enum ReadReason: Sendable, Hashable {
    case poll          // 3 秒輪詢：busy 期間丟棄、不補（B-02）
    case playerSignal  // Music 通知：busy 期間記下，全部空閒時補一次
    case forceRefresh  // 使用者點卡／寫入後補讀：busy 期間記下，補讀時重發當前曲
}
private var isReading = false                 // 至多一個讀取進行中
private var followUp: Set<ReadReason> = []    // 進行中又來的理由：完成後再讀一次（多次合併成一次）
private var deferred: Set<ReadReason> = []    // busy 期間記下的理由（取代 pendingForceRefresh；只收 .playerSignal／.forceRefresh）
```
- 單一入口 `request(_ reason:)`（私有）：
  - busy → `.poll` 丟棄；其餘併入 `deferred`；return。
  - `isReading` → 併入 `followUp`；return。
  - 否則讀：`isReading = true`；迴圈 `{ let reasons = 本次理由 ∪ followUp; followUp = []; await readOnce(resetting: reasons.contains(.forceRefresh)) }`，直到 `followUp` 為空或變 busy；變 busy 時 `followUp` 去掉 `.poll` 後併入 `deferred`（R1-1）；`isReading = false`。
- `readOnce(resetting:)`＝現行 `tick()` 的本體；`resetting` 時先清 `lastSignature`／`lastWasNotPlaying`。
  **理由**：現行 `forceRefresh` 是「先清 `lastSignature` 再 `tick()`」，讀取進行中會失效——進行中的那次讀完會把 `lastSignature` 寫回同一首，合併後的重讀就不再發 `trackChanged`（E3）。改成在該次讀取開始時才清。
- 公開 API：`tick()`＝`request(.poll)`；`forceRefresh()`＝`request(.forceRefresh)`；`playerDidChange()`（新）＝`request(.playerSignal)`。
- `setBusy(false)` 且全部空閒且 `deferred` 非空 → 原子地取出並清空，交給私有 `beginRead(reasons:)`（`request` 的讀取段也走它；R2-2）讀一次（`.forceRefresh` 與 `.playerSignal` 同時 pending 只讀一次，理由集合完整進日誌）。
- `stop()` 之後 `request` 一律 no-op（R2-5：`AppModel` 回呼已建立的 `Task { await monitor.playerDidChange() }` 可能晚於 stop 才到）。
- **讀取次數（R1-2、R2-1 修正文案）**：單飛保證**不並發**——任一時刻至多 1 個讀取進行中＋1 個待補，進行中無論來幾個訊號都合併成 1 次補讀；**不限制總量**：訊號間隔長於一次 AE 讀取時，每個訊號各讀一次。總量受 Music 的通知頻率約束，而通知只在換歌／播放狀態變化時送（人手操作量級）。**不加 debounce 或合併窗**（理由見附錄 A.2 #1）。
- 呼叫端語義變化：`await tick()` 在合併時會立刻返回（讀取由進行中的那一方代做）。全倉呼叫端只有輪詢迴圈與測試（實作時 grep 覆核）；新增測試釘住合併語義。

日誌（OSLog，subsystem 不變，category `monitor`，**只記序號、理由、布林與耗時**）：每次讀取結束記「讀取序號、理由集合、相對前一筆 signature 是否變了、AE 讀取耗時 ms」（耗時供 A.3 遺留 P2 定案）——供 U2 實機判讀（R1-10：只能說「通知觸發的那次讀取看到了變化」，不宣稱對上了某一則通知的曲目），不記曲名與 ID。

### 3.3 F2：換歌後的有界履歴短重讀

`LyricsFlowModel`：
- 真實換歌且有前一首（`current` 非 nil）時，啟動「履歴追趕」：`expected = 前一首.persistentID`。
- 追趕 task：依時點表逐點 `sleep` → 排進既有串行工作鏈讀 **只有 `History.dat`**（`queueSource.readHistory`，屬性沒變就是 `.unchanged`，成本＝一次 `stat`）。
- **履歴的狀態轉移只留一處**（R1-8）：抽出 `applyHistoryRead(_:) -> Bool`（回傳 `history` 的**值**是否真的變了；R2-3），`readSources` 與追趕共用——`.snapshot(next)` → `changed = history != next` 後寫入、`.missing` → `changed = history != nil` 後清成 nil（退回觀察歷史）、`.failed`／`.unchanged` → 保留、`false`。
- **追趕只在 `history` 真的變了才 `publish`**（R1-4）：`publish` 會順帶 `fetchDetails`，若缺詳情的卡一直讀不到，每個時點都會多一次 Music AE；沒變就不 publish，追趕本身不碰 Music。
- **停止條件**（R1-7）：每次 sleep 前與每次讀完後都看**目前的** `history`（不論本次是 `.snapshot` 還是 `.unchanged`）：`history.recent.last?.persistentID == expected` 就停。換歌當下那次 `readSources` 或期間的 3 秒輪詢已追上 → 不再重讀。
- 時點表（相對換歌事件的**絕對時點**）：起點 `[100ms, 300ms, 700ms]`（0ms＝既有的 `readSources`），**依 §5.1 的 U1 量測結果定稿**。實作 sleep 的是**相鄰時點的差**（100、200、400ms；R1-5），測試斷言 `GatedPollClock.requested` 的值與累計。量測若顯示寫檔常晚於 1 秒 → 停手找使用者（不自行拉長、不動 AC8 例外）。
- **世代守衛**（R1-3）：`historyRecheckGeneration`（單調遞增）。新的真實換歌、`stopPolling()` → 世代 +1、取消舊 task。舊 task 醒來後、入鏈前、在工作鏈內讀完後，三處都比對世代，不符就不寫 `history`、不 publish——`Task.cancel()` 不保證對方已停。
- **生命週期**（R2-4）：`stopPolling()` 設 `isStopped = true`（先於世代 +1）；之後晚到的換歌事件不再建立追趕。
- 使用者跳過（沒播完）時 Music 不寫履歴（E5）→ 追趕跑滿時點表後放棄，接受正式牌組（左鄰＝更早的歌，這是 Music 面板的真相）。
- 時鐘：新增 init 參數 `historyRecheckClock: any PollClock`（`AppModel` 給預設 `SystemPollClock()`；`LyricsFlowModel` 不給預設值）。**不與升回的 `clock` 共用**：`GatedPollClock` 依請求順序放行，混用會讓既有升回測試放錯等待者。
- 時點表只留一處（`LyricsFlowModel.historyRecheckOffsets`）。
- `settleForTesting()` 不等追趕 task（它在 sleep 中）；測試以 `GatedPollClock` 逐點放行後再 settle。

### 3.4 為什麼不用通知的 `PersistentID` 直接換歌
不採（Codex R1 ④）：兩個資料來源會在歌詞、暫停狀態、AE 讀取失敗時分歧；通知只當「該去讀了」的觸發器。

## 4. 測試（TDD；先紅後綠，紅燈摘要回填 §7）

**F1 單元（`NowPlayingMonitorTests` 追加）**
1. `aPlayerChangeReadsAtOnce`：idle 時 `playerDidChange()` → 讀一次、發 `trackChanged`。
2. `aPlayerChangeWhileBusyIsReadOnceWhenIdle`：busy 中收 3 次通知 → 讀 0 次；最後一個來源解除 → 讀恰 1 次。
3. `aPlayerChangeWaitsForEveryBusySource`：editor＋batch 皆 busy，只解除一個 → 0 次。
4. `pollTicksWhileBusyAreStillDropped`：busy 中 `tick()` 不記帳，解除後不補讀（B-02 不變的回歸）。
5. `overlappingTriggersCoalesceIntoOneFollowUpRead`：`MockMusicClient` 加 `nowPlaying` 閘門佇列；第一次讀取卡住時再來 `tick()`×1＋`playerDidChange()`×5 → 讀取中 `nowPlayingCalls == 1`；放行後總數 `== 2`（恰一次補讀）、`maxNowPlayingInFlight == 1`。
5a. `signalsDuringTheFollowUpReadGetOneMore`（R1-2）：補讀也卡住時再來 3 個通知 → 總數 `== 3`，不多不少。
6. `forceRefreshDuringAnInFlightReadStillReemits`：讀取中（同一首）來 `forceRefresh()` → 放行後再發一次 `trackChanged`。
7. `aChangeArrivingMidReadIsSeenByTheFollowUpRead`：第一次讀 A 卡住、腳本下一筆是 B、期間來通知 → 放行後事件序列含 B。
8. `busyStartingMidReadDefersASignalFollowUp`：讀取中來通知、隨即 `setBusy(true)` → 放行後不再讀；解除 busy → 補讀 1 次。
8a. `busyStartingMidReadDropsAPollFollowUp`（R1-1）：讀取中來輪詢、隨即 `setBusy(true)` → 放行後不讀；解除 busy → 仍 0 次。
8b. `noReadAfterStop`（R2-5）：`stop()` 後 `playerDidChange()`／`tick()` → 0 次。
9. 既有 `forceRefreshWhileBusyRunsOnceIdle`／`pendingForceRefreshWaitsForEveryBusySource` 不改即綠；再加 `pendingForceRefreshAndNotificationReadOnlyOnce`（兩者皆 pending → 解除時只讀 1 次）。

**F1 邊界（`PlayerChangeSignalTests`，新檔）**
10. `liveSignalCallsBackOnThePostedName`：以專屬通知名（含 UUID）建 `MusicPlayerInfoSignal`，post 帶 userInfo 的 distributed 通知 → 回呼一次（有逾時上界）。
11. `stopRemovesTheObserver`：stop 後 post，再 post 一則**哨兵**到另一個仍在監聽的專屬名、等哨兵送達（R1-9：以「後發的已到」界定「先發的不會再到」，不靠固定等待）→ 被 stop 的那個 0 次。
12. `startIsIdempotent`：start 兩次 → post 一次只回呼一次；`start→stop→start` 後 post 一次只回呼一次。

**F1 整合（`AppModelTests` 追加；Spy 注入；經 `start()`／`stop()`，不另開公開方法）**
13. `startListensForPlayerChanges`／`stopStopsListening`：start 後 Spy 的 startCount == 1（start 兩次仍 1）；stop 後 stopCount == 1。
14. `aPlayerChangeReachesTheMonitor`：monitor 用 `GatedPollClock`（輪詢讀一次後停在 sleep）；`start()` 後 Spy `fire()` → `music.nowPlayingCalls` 恰增 1。

**F2 單元／整合（`LyricsFlowModelTests` 追加；`GatedPollClock` 當 `historyRecheckClock`；臨時目錄夾具）**
15. `historyWrittenAfterTheChangeIsPickedUpByTheRecheck`：換歌當下 History 尾端＝更早的歌；於第 2 個時點前把夾具換成尾端＝剛播完的歌 → 放行第 1、2 點後，`coverFlow.deck` 左鄰＝剛播完的那首。
16. `recheckStopsOnceTheFinishedTrackAppears`：第 1 點追上 → 之後不再請求 sleep（`GatedPollClock.requested.count` 不增）。
17. `recheckGivesUpAfterTheLastOffset`：跳過（履歴永不含前一首）→ 放行全部時點後不再請求；牌組＝正式牌組。
18. `aNewChangeRestartsTheRecheck`：追趕中又換歌 → 舊的等待者被取消、新的 `expected` 生效。
18a. `aStaleRecheckThatAlreadyWokeCannotPublish`（R1-3）：用不理會取消的時鐘替身讓舊 task 在新換歌之後才醒 → 它不寫 `history`、不 publish。
19. `alreadyCaughtUpAtTheChangeDoesNotRecheck`：換歌當下 `readSources` 已讀到剛播完的那首 → 不請求 sleep。
19a. `aPollThatCatchesUpStopsTheRecheck`（R1-7）：第 1 點之前 3 秒輪詢先讀到 → 第 1 點醒來讀到 `.unchanged` 後停，不再請求 sleep。
19b. `anUnchangedRecheckDoesNotFetchDetails`（R1-4）：某卡詳情讀取失敗（缺詳情）→ 追趕各點 `.unchanged` 時 `trackDetailsRequests` 不增。
19c. `recheckFollowsTheSameHistoryTransitions`（R1-8）：追趕讀到 `.missing` → 左側退回觀察歷史（與 `readSources` 同）；`.failed` → 保留。
19d. `aRewrittenButIdenticalHistoryDoesNotPublish`（R2-3）：檔案屬性變、內容相同 → 不 publish、`trackDetailsRequests` 不增。
19e. `noRecheckAfterStopPolling`（R2-4）：`stopPolling()` 後的換歌事件不請求 sleep。
20. `historyCatchingUpDuringTheSlideKeepsIt`：已有 `historyCatchingUpBeforeTheSlideSettlesKeepsItGoing`；追加一條以追趕路徑觸發的版本（第 1 點追上時 `coverFlow.transition` 仍在、generation 不變）。
21. `recheckSleepsTheGapsBetweenOffsets`（R1-5）：跑滿時 `requested` ＝相鄰差（100、200、400ms），累計＝時點表；時點表遞增、首項 > 0、末項 ≤ `slideTimeout`（1.24s）——末項大於過渡時長就不再是「平移中追上」而是落定後再換一次，§5.1 若量出更晚的需要要回報。

**閘門**：`no_playback_gate.sh`（新檔不含禁用 API；`DistributedNotificationCenter` 只 `addObserver`）；`MusicSelectorAllowListTests` 不受影響（沒有新 AE）。

## 5. 驗證項

### 5.1 量測（唯讀；不操控 Music、不記曲名）
- **U1**：scratchpad 量測器 `recorder`（`DistributedNotificationCenter` 收 `playerInfo`＋每 10ms `stat` 兩個檔，檔案變了就解析、只記 persistentID 的 SHA-256 前 3 位元組）。取「通知 → `History.dat` 修改時間（與偵測到的時刻）」的差，**至少 5 次自然播完**，報中位數與最大值（R1-10），並記 macOS／Music 版本。
- **U2**：F1 實作後，Debug 版實機跑，讀 OSLog `monitor` category 的「通知觸發讀取是否讀到新曲」布林。量測期間 Music 須有自然換歌；**Music 的播放由使用者自己進行**，我只讀。

### 5.2 全量
全量單元（帶 skip＋超時；失敗集合＝基線 `CoverFlowStripRenderGeometry` 的 7 個斷言逐條相同）→ `coverage_gate.sh <單元 xcresult>` → `no_playback_gate.sh` → `Scripts` Python 測試。

## 6. 影響面、風險與回退

| 檔案 | 改動 |
|---|---|
| `Services/Music/PlayerChangeSignal.swift` | 新增 |
| `Services/Music/NowPlayingMonitor.swift` | 單飛、`playerDidChange`、`resetBeforeNextRead` |
| `App/AppModel.swift` | 必填 `playerSignal`、`connectPlayerSignal()`、`historyRecheckClock` 轉交 |
| `App/UITestSupport/AppModel+*UITest.swift`（2 檔） | 注入 Noop |
| `Features/LyricsFlow/LyricsFlowModel.swift` | 履歴追趕 |
| `Tests/…` | 見 §4；`MockMusicClient` 加 `nowPlaying` 閘門；`AppModelTests`／`AppModelNotificationTests`／`BatchOverlappingLoadTests` 的組裝補參數 |
| `ACCEPTANCE.md` | H-04 證據欄補 F1；H-19a 補 F2；B-01/B-02 補單飛與通知補讀 |
| `project.yml` | 不改（新檔在既有目錄，`xcodegen generate` 重產即可） |

風險：
- R1：通知密集（連按下一首、播放／暫停快速切換）→ 單飛保證不並發、讀取中的訊號合併；總量不設上限，受人手操作速率約束（A.2 #1）。
- R2：U2 不成立（通知早於 AE 可讀）→ F1 效果打折；對策待量測後定（例如通知後延遲一小段再讀），**屬設計變更，回 Phase 1**。
- R3：`tick()` 合併後提早返回，改變了「await tick() 之後事件已送出」的隱含假設 → 全倉 grep `tick()` 呼叫端逐一審；只有測試與輪詢迴圈。
- 回退：`live()` 改注入 Noop 即回到純輪詢；追趕時點表設空即停用 F2。

## 7. 紅燈摘要（實作時回填）

**F1（2026-09-27 21:42）**：最小樁（型別存在、行為空）下跑 `NowPlayingMonitorSingleFlightTests`／`PlayerChangeSignalTests`／`AppModelPlayerSignalTests`／`NowPlayingMonitorTests`：AppModel 接線 3 條紅（startCount／stopCount／讀取次數）；單飛與通知補讀 7 條紅；`aPlayerChangeReadsAtOnce`、`aChangeArrivingMidRead…` 因空樁掛到 120s 逾時（紅）。`forceRefreshDuringAnInFlightReadStillReemits`／`pendingForceRefreshAndPlayerChangeReadOnlyOnce`／`pollTicksWhileBusyAreStillDropped` 在舊碼即綠——舊碼沒有單飛，並發的第二個讀取恰好重發；它們是新碼的回歸守衛。
**F1 綠（21:50）**：上述 4 檔＋`AppModelTests`／`AppModelNotificationTests` 共 70 條全綠；新檔與改動檔零警告（Swift 6 strict）。

**F2 機制（22:00）**：`LyricsFlowHistoryRecheckTests` 12 條，樁下 7 條紅（追上、停止、sleep 相鄰差、輪詢先追上、換歌重來、`.missing` 轉移、平移中追上）；另 5 條（已追上不重讀、舊世代醒來不 publish、沒變不問詳情、stop 後不重讀、時點表形狀）是「不該發生」的守衛，樁下本來就綠。
**F2 機制綠（22:01）**：12＋既有 `LyricsFlowModelTests` 36 條全綠。
**實作偏離 §3.3（筆誤級，留痕）**：世代只在「醒來後／入鏈前／讀之前」比對，**讀完後不比對**——讀到的是檔案最新內容，丟掉會讓屬性戳已更新的那份內容永遠讀不到（lost update）；鏈上讀取串行，後讀的不可能比先讀的舊，所以讀完一律套用是安全的。

## 8. 量測記錄

### 8.1 U1：History.dat 寫入 vs 換歌通知（量測器 `recorder2`，唯讀）
| # | 換歌方式 | 通知 | History.dat mtime | 差 |
|---|---|---|---|---|
| 1 | 自然播完 | 22:02:07.777 `Playing` | 22:02:12.824 | **+5.05s** |
| 2 | 自然播完 | 22:06:04.745 | 22:06:09.789 | **+5.04s** |
| 3 | 自然播完 | 22:09:55.351 | 22:10:00.397 | **+5.05s** |
| 4 | 自然播完 | 22:13:26.681 | 22:13:31.545 | **+4.86s** |
| 5 | 播了 47 秒後按下一首（使用者授權我操控，23:02） | 23:02:43.404 | 23:02:48.422 | **+5.0s**（播了 47 秒就跳過，仍寫入履歴） |
| 6 | 單曲循環重播（23:04） | 23:04:59.125 `Playing`（同一首） | 23:05:07.549 | +8.4s（含拖進度的時間） |

中位數 5.05s、最大 5.05s（自然播完 4 筆）。macOS 27.0、Music（系統內建版本）。**遠超過 1 秒線 → F2 依指示停手，帶數據找使用者。**
另：只播 4 秒就跳過的兩次，**沒有**寫履歴；暫停中往回跳（②計劃 §8.5）、播放中往回跳（23:03）也都沒寫。

### 8.2 U3（新）：播放中切歌的通知序列
播放中手動切歌，Music 先廣播 `Stopped`、約 40–50ms 後再廣播 `Playing`（21:57:07–11，4 次皆然）；暫停中切歌只有 `Paused`（②計劃 §8.5）；自然播完只有 `Playing`（8.1 #1）。
**風險（推測）**：收到 `Stopped` 就讀，若讀到 stopped，`MusicAppleEventsClient.nowPlaying` 回 nil（`:60`）→ monitor 送 `.notPlaying` → LyricsFlow 走「沒在播」→ 平移被打斷或畫面閃一下。量測器已加「收到通知即唯讀 `player state`」，待播放中切歌的樣本。
**量測（23:02–23:05，使用者授權我操控）**：播放中用下一首／上一首換歌 4 次、自然播完 4 次、單曲循環 1 次，**都只送 `Playing`**，通知當下唯讀 `player state` 皆為 `playing`（24–117ms）。`Stopped→Playing` 只出現在使用者在清單裡直接點歌（每次伴隨 `Queue.dat` 重寫；21:57 四次）——那一種的 `Stopped` 當下讀到什麼**仍未量到**（TBD）。播放 >3 秒時按上一首只回到曲首，不換歌、不送通知。

## 附錄 A　評審記錄

### A.1 Codex R1（v1，gpt-5.6-terra，read-only，對照程式碼）與裁決（v2）

原始輸出：scratchpad `codex-f12-r1.txt`（不入庫）。

| # | 嚴重度 | 要點 | 裁決 |
|---|---|---|---|
| 1 | P1 | `readAgain` 混了輪詢與通知：讀取中來輪詢、隨即 busy，會在 busy 後補讀，違反 B-02 | **採納**：`ReadReason` 分開記，busy 邊界丟 `.poll`；加測試 8a |
| 2 | P1 | 通知風暴下補讀可一直循環，「進行中 1＋補讀 1」的說法不成立 | **部分採納**：改文案為「任一時刻 ≤1 進行中＋1 待補、總讀取 ≤ 通知數＋1、串行」；加測試 5a。**駁回 debounce**：會把 F1 要消除的延遲加回來，Music 通知是人手操作量級 |
| 3 | P1 | `Task.cancel()` 不保證追趕 task 已停，舊 task 可能在新換歌後寫 `history` | **採納**：世代守衛三處比對；測試 18a |
| 4 | P1 | 追趕的 `publish` 會順帶 `fetchDetails`，缺詳情時每個時點多一次 Music AE | **採納**：只在 `history` 真的變了才 publish；測試 19b |
| 5 | P1 | 時點表若逐點 sleep 絕對值會變成 100／400／1100ms | **採納**：sleep 相鄰差；測試 21 驗 `requested` |
| 6 | P1 | live signal 的 Swift 6 隔離與 stop 後已排隊 block | **採納**：`@MainActor` 型別＋token＋世代；strict concurrency 零警告為閘門 |
| 7 | P2 | 停止條件只看 `.snapshot`，輪詢先追上時追趕仍跑滿 | **採納**：每點前後都看目前 `history`；測試 19a |
| 8 | P2 | 追趕對 `.missing`／`.failed` 的行為未定義 | **採納**：抽 `applyHistoryRead` 兩路共用；測試 19c |
| 9 | P2 | distributed 通知非同步，「stop 後不回呼」只立即斷言會假綠 | **採納**：哨兵通知界定；測試 11、12 |
| 10 | P2 | U1 三次樣本不足；U2 不能宣稱對上特定通知 | **採納**：≥5 次、報中位數與最大值；U2 日誌與措辭改 |
| 11 | P2 | 為測試抽 `connectPlayerSignal()` 擴大表面 | **採納**：經 `start()`／`stop()` 測，monitor 用 `GatedPollClock` 讓輪詢停住 |

### A.2 Codex R2（v2）與裁決（v3）

原始輸出：scratchpad `codex-f12-r2.txt`。結論：**0 條 P0／P1**；A.1 十一條逐條對照 §3／§4 正文確認已補（#2 部分）。

| # | 嚴重度 | 要點 | 裁決 |
|---|---|---|---|
| 1 | P2 | 不接受「不加 debounce」：接受純 trailing debounce 會破壞 F1，但建議「leading read＋100–200ms trailing 合併窗」，把快速操作壓到約 2 次 AE；反例＝連按媒體鍵 30 次 → 30 次 `nowPlaying()`，排擠封面／詳情 | **駁回（維持 P2，送 R3 反駁）**：①量級——人手連按約 ≤10 次／秒，單次 `nowPlaying()` 是一個 AE，讀取中到的訊號本來就合併；②每次讀到的換歌本來就要反映，合併窗會跳過中間曲，改變 LyricsFlow 的換歌序列（聆聽歷史、升降），屬行為變更；③合併窗要在 monitor 內多一個計時消費者，與輪詢共用 `clock`，正是 R1-5 指出的「GatedPollClock 依請求序放行」同類陷阱。文案已改為「不並發、不限總量」（R2-1 的另一半建議，採納） |
| 2 | P2 | `deferred` 取出後如何進讀取迴圈未定義 | **採納**：私有 `beginRead(reasons:)` 單一入口 |
| 3 | P2 | `applyHistoryRead` 不能把每次 `.snapshot` 當「變了」 | **採納**：值比較；測試 19d |
| 4 | P2 | `stopPolling()` 後晚到事件仍可建立追趕 | **採納**：`isStopped`；測試 19e |
| 5 | P2 | `monitor.stop()` 後已建立的回呼 Task 仍可讀一次 AE | **採納**：stop 後 `request` no-op；測試 8b |

### A.3 Codex R3（v3）——定稿

原始輸出：scratchpad `codex-f12-r3.txt`。**v3 無新的 P0／P1**；A.2 #2–#5 確認已落到 §3／§4 且各有測試。

A.2 #1（合併窗）的辯論結果：
- Codex 反駁①：「人手 ≤10 次／秒」沒有量測 AE 單次延遲或連按壓力的數據——**成立**，我方無數據。
- Codex 反駁③：合併窗可另注入時鐘，時鐘混線是可測試性問題、不是不可做——**成立**。
- Codex 部分接受②：合併窗會漏掉 App 可觀察到的中間換歌，但「是否必須保留」是產品語義的價值判斷。
- **裁決**：證據定不了，屬「遺留 P2，待量測」。v3 維持不設合併窗（現況行為的最小延伸：3 秒輪詢本來就不併發、不合併）；monitor 日誌加 AE 讀取耗時。若實機日誌顯示連按時讀取排隊明顯拖慢封面，再另開一項加 leading＋trailing 合併窗。不在本次向使用者要取捨：現行設計不讓任何已通過的行為變差。

## 9. F2 在 U1 數據下的選項（待使用者拍板；已依指示停手）

已實作的短重讀（100／300／700ms）在「約 5 秒後才寫」下**抓不到**。畫面現況（F1 之後）：換歌立刻滑；滑完 0.62s 暫留卡收掉，左鄰變成更早的那首；約 5 秒後履歴寫入、下一次讀檔（3 秒輪詢或重讀）讀到，剛播完的那張插回左鄰、其他卡往左挪一格——「消失」約 5–8 秒。

- **甲 接受現況**：撤掉短重讀（它在實測下沒有作用）。消失約 5–8 秒。
- **乙 重讀時點改到 5 秒後**（例如 5.2／6／7 秒）：消失縮短到約 5 秒，但「消失→插回、其他卡挪一格」仍在。不動 AC8 例外。
- **丙 暫留卡留到履歴追上**（上限約 7 秒，超時就收）：滑完後剛播完的那張一直留在左鄰，履歴寫入時原位換成履歴卡，畫面不動。只播幾秒就跳過的（Music 不記），上限到時那張消失、其他卡挪一格（與面板一致）。需要**重簽 AC8 顯示層例外**（≤1.24s → ≤約 7s）；Codex 在②計劃 A.9 以「多一個顯示層狀態、暫留期間又換歌時條件衝突」反對過。

### 9.1 Codex R1 對 §9（原始輸出 scratchpad `codex-f23-r1.txt`）
- 甲：P1（體驗瑕疵照舊）。乙：P2，建議時點 **5.2／6／7 秒**（5.2 覆蓋實測最大 5.05，後兩點防負載尾端），**Codex 推薦乙，信心 85%**；不消除「插回、其他卡挪一格」，只把 5–8 秒縮到約 5.2 秒。
- 丙：P1——`slidePlan` 要求 `transition == nil` 才起滑，暫留 7 秒會讓這段期間的下一次換歌全部 direct；位次條件在 7 秒內更易失效；須重簽 AC8。不推薦。
- 第四案丁（Codex 提出）：另設「待入履歴」的暫定左鄰卡（不動平移的 `transition`），履歴寫入時原位換成 `h:` 卡。畫面不再消失；代價是只播幾秒就跳過（Music 不記）時，會顯示一張 Music 面板沒有的卡，直到上限到時才消失——與 F3「和面板一致」衝突。
- 需使用者拍板：連續觀感（丁）與忠於 Music（乙）的取捨。

### 9.2 使用者拍板（2026-09-27 23:29）
**採乙**：時點改為 5.2／6／7 秒（`LyricsFlowModel.historyRecheckOffsets`）。契約測試改為 `recheckOffsetsCoverTheMeasuredWriteDelay`（紅：舊值 100／300／700ms → 綠）；`LyricsFlowHistoryRecheckTests` 13 條＋`LyricsFlowModelTests` 36 條全綠。§3.3「末項 ≤ slideTimeout」的約束隨之作廢（實測下平移中不可能追上）。

## 10. U3 實機結果與修法（2026-09-27 23:5x，使用者授權我操控 Music；production 原檔編成的命令列工具，從終端機執行）

工具：`NowPlayingMonitor`＋`MusicPlayerInfoSignal`＋`MusicAppleEventsClient` 原檔＋最小 main（scratchpad `f1cli`），記錄「通知 → monitor 事件」延遲。

| 情境 | 結果 |
|---|---|
| 播放中下一首 ×2、上一首 | 通知後 77／79／133ms 送出 `trackChanged`（F1 成立；先前最慢 3 秒） |
| 暫停中下一首 | 80ms |
| 播放／暫停切換 | 只有通知、沒有事件（同一首，正確） |
| **在清單中直接播某首（`play track … of playlist`，模擬使用者點歌）** | `Stopped` 通知 → **13ms 後送出 `notPlaying`** → 25ms 後 `trackChanged` |
| 單曲清單播完 | `notPlaying`（真的停了，正確） |

**U3 成立（已核）**：點歌時 F1 會讓 LyricsFlow／Editor 先收到一次 `notPlaying`，Cover Flow 變成「沒在播」（只剩左側）再換回來，平移也被打斷。F1 之前只在 3 秒輪詢剛好撞上約 40ms 空窗時發生；F1 讓它每次點歌都發生——**是 F1 引入的回歸，發版前必修**。

**副作用（照實記錄）**：模擬點歌把 Music 的「接下來」換成只有一首；已還原原曲、47 秒、暫停，但「接下來」無法原樣還原成原本那張專輯的 25 首（現為資料庫順序）。

### 10.1 修法選項（待 thecure／Codex／Jev 裁決）
- **A 訊號端過濾 `Stopped`**：`MusicPlayerInfoSignal` 讀通知的 `Player State` 一個欄位，是 `Stopped` 就不觸發讀取；真的停止由 3 秒輪詢發現（＝F1 之前的行為，H-04 ≤3s）。改動 1 檔、數行。偏離 R1 ④「丟棄 userInfo」：但只用來決定要不要讀，不當資料來源。
- **B 通知觸發的讀取讀到「沒在播」先不發，隔一小段（例如 150ms）再確認**：monitor 內新增確認讀取與計時；輪詢路徑不變。要再注入一個時鐘、單飛狀態多一種理由。
- **C 一律要連續兩次讀到「沒在播」才發 `notPlaying`**：輪詢與通知都延後一次讀取；真停止的發現從「下一次輪詢」變成「再下一次」（最多約 6 秒）。

### 10.2 裁決與實作（2026-09-27 23:5x）
- Jev（`jev-latest`＝jev-1.13.0，Choice）：A 0.93／B 0.07／C 0.00；「A 讓既有行為退步」0.23；「A 違反單一資料來源」0.15。輸入 scratchpad `jev-u3.json`。
- Codex（thecure，scratchpad `codex-u3.txt`）：推薦 A，信心 0.91；附條件——只讀 `Player State` 當閘門、**失敗放行**（只有字串且精確等於 `Stopped` 才丟）。B 引入計時與新狀態、150ms 是未驗證的魔數；C 真停止最壞 6 秒。**全部採納**。
- 實作：`MusicPlayerInfoSignal.isStopped(_:)`＋observer 閘門。TDD：`PlayerChangeSignalTests.aStoppedNotificationDoesNotTriggerARead` 紅→綠；`everyOtherNotificationTriggersARead` 6 個參數案例（Paused／Playing／小寫 stopped／缺欄位／非字串／無 userInfo）為守衛。
- 實機再驗（重編命令列工具）：清單中點歌 3 次，皆約 120ms 直接 `trackChanged`，**零次 `notPlaying`**。
- 已知行為（接受）：真的停止由 3 秒輪詢發現（＝加通知前的行為）；若 Music 只送 `Stopped` 而不再送任何通知就換了歌，也退回輪詢（≤3 秒）。

## 11. GUI 實機驗證（2026-09-28 00:1x，使用者授權我操控；Debug 版 App 本體）

做法：Debug 版以臨時家目錄啟動（`HOME`／`CFFIXED_USER_HOME` 指向 scratchpad，`Music` 以符號連結指回真曲庫）——找不到 Keychain token 就不跳授權框；Music 的自動化權限沿用終端機。觀測：輔助使用 API 每 50ms 讀 Cover Flow 正中卡 ID 與左鄰卡 ID（persistentID 雜湊輸出）。佇列：暫時建一個含 89 首的播放清單播放，測完刪除。

| 情境 | Cover Flow 觀測 |
|---|---|
| 播放中下一首 ×2、暫停中下一首（F1） | 指令後 0.25–0.26s 正中換新歌（含 osascript 與 50ms 輪詢開銷；改前最慢 3s） |
| 平移 | 換歌當下左鄰＝暫留的剛播完那張；約 0.64s 後落定，左鄰暫為更早那首 |
| F2 | 換歌後約 5.7s，剛播完的那首回到左鄰（5.2s 重讀點）；另一次在 6s 重讀點 |
| 播整個清單／清單中點歌（U3，Music 先送 Stopped） | 188–219ms 正中換新歌，左側不變，未出現空白 |
| 播放超過 3 秒按上一首 | 回曲首、不換歌，Cover Flow 不動（正確） |
| 真的停止 | 正中維持最後一首（既有行為，`.notPlaying` 在 LyricsFlow 為 no-op） |

限制：平移的「觀感」（是否閃一下）只能目視；本輪只驗到卡 ID 與時序。
