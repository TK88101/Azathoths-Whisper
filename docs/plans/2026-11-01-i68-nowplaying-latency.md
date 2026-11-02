# I-68 收尾：掃描中 nowPlaying 延遲量測（計劃 v0.5，/thecure 收斂；待使用者審閱）

## 0. 複述
- 目標＝補上 ⑧ T0 DoD 最後一項「掃描中 `nowPlaying` 延遲最壞 ≤ 1.5 s」的真機數字，達標才簽 I-68。
- 完成標準＝DEBUG-only、脫敏的量測點落地（先紅後綠）；使用者在場一次 Rescan、掃描前中後各切一次歌；`log stream` 錄下的最壞值 ≤ 1.5 s；I-68 狀態欄更新並由使用者簽字。
- 不做＝改任何 Release 行為、改 AE 佇列排程或預算（量完不達標才另議）、碰 YSE、操控使用者的 Music。

## 1. 使用者決定（既定前提，不重議）
- 量測點只加 DEBUG、只記序號與毫秒（2026-11-01 開工口令）。
- 四組量測：`MusicAppleEventsClient.run` 入佇列／開始／完成；`nowPlaying()` 總時；`playerDidChange`→`trackChanged` 端到端；單調時鐘＋每次掃描與每次切歌的關聯 ID；`log stream` 錄（/thecure 2026-11-01，⑧ 增補附錄 H：「量測若無單調時鐘與關聯 ID，掃描與切歌併發時數字無法歸因」）。
- 使用者自己在 Music 播歌、切歌；我不送任何播放控制。

## 2. 事實（2026-11-01 讀碼，已核）
- AE 全部進同一條序列佇列 `MusicAppleEventsClient.queue`（`Services/Music/MusicAppleEventsClient.swift:36`），`run` 在 `:307`；Swift 取消不會中斷已開始的 block。
- 掃描（`Services/LibraryGate/LibraryGateScanner.swift`）：先 `libraryTrackSnapshot()` 一次，再逐寫法 `artistLyrics(artist:)` 491 次，**一次只排一個**；每個 block 以 `AEBudget(total: libraryBudget = 1.5 s)` 限時（`:249`、`:298`）。真機整庫 69.8 s（⑧ 附錄 H），平均每次約 142 ms。
- 掃描**不**設 busy（`AppModel.swift:194/237` 只有 editor／batch），所以 3 秒輪詢與換歌通知在掃描中照常讀 `nowPlaying()`，與掃描的 block 在同一佇列交錯。
- 同一佇列的其他使用者：`PlaybackPositionClock.playbackPosition()`（歌詞特效）、Cover Flow 封面（`artworkTimeoutTicks` 90＝1.5 s）、`trackDetails`（預算 1.5 s）。
- 換歌通知：`MusicPlayerInfoSignal`（主執行緒）→ `AppModel.swift:433` `Task { await monitor.playerDidChange() }` → monitor 單飛讀取（讀取中再來的理由合併成一次補讀，`NowPlayingMonitor.swift:160-185`）→ `continuation.yield(.trackChanged…)`。
- 既有日誌：monitor 每次讀取已記 `read <序號> <理由> changed=<bool> <ms>`（`.debug`，category `monitor`）；掃描完成記 `tracks／reads／elapsed`（`.info`，category `library-gate`）。`.info`／`.debug` 不落盤——⑧ 增補附錄 G 的 `log show` 查不到 library-gate 行即此因（推測，與 OSLog 預設持久化規則一致）。
- 覆蓋率豁免檔 `MusicAppleEventsClient.swift` 目前 483／490 可執行行（⑧ 增補附錄 H 批准 490）。

## 3. 推論（推測，標明推理鏈）
- 最壞情境＝`nowPlaying` 剛好排在一個掃描 block 之後：等待 ≤ 該 block 的實際耗時（預算 1.5 s＋最後一個 AE 的回應），再加自身執行。若 snapshot 或某次 `artistLyrics` 吃滿預算，**總時可能超過 1.5 s**。所以「等待」與「執行」要分開記，否則超標時無法判斷是掃描 block 太長還是 `nowPlaying` 自己慢。
- 平均 142 ms 推估多數樣本遠低於門檻；風險集中在 snapshot（12,271 首五欄）與大歌手的歌詞讀取。
- 一次真機掃描只能得到「實際發生的 `nowPlaying` 的**觀測**最大值」：輪詢每 3 秒一次、切歌只有幾次，不會碰上每一種排隊相位（Codex R1-1）。理論上界也算不出來：同一佇列還有 `CardDetailsReader`（actor 在 await 時可重入，能同時排多個 block）、封面、位置時鐘，重掃時兩個掃描也會各排一個（Codex R2）。T0 本身寫的方法就是「DEBUG 量測，使用者在場看日誌」，所以簽字依據定為**本次掃描的觀測最大值**，並在 ACCEPTANCE 照實寫明，不寫成「理論最壞」。
- T0 的另一項「每次 AE ≤ 1.5 s」由 `AEBudget` 結構保證（每個 block 送 AE 前以剩餘預算設 timeout，用完整批作廢）；本計劃的 M2 量的是**AE 工作 block**（一個 `run` closure，可含多個 AE），只作佐證，不另宣稱逐個 AE 的數字（Codex R1-4）。

## 4. 目標與非目標
- 目標：三組數字（§5.1 M1–M3）在一次真機掃描中取得，含掃描前（基線）、中、後。
- 非目標：改佇列優先序、拆小掃描 block、把掃描改成 busy——**只量不改**；不達標時停下，另立方案交使用者。

## 5. 設計

### 5.1 量什麼、判準是什麼
| 代號 | 量什麼 | 起點→終點 | 用途 |
|---|---|---|---|
| M1 | `nowPlaying()` 呼叫端總時（含排隊） | monitor 呼叫 `music.nowPlaying()` 前 → 回傳後 | **簽字依據**：本次掃描期間（§5.4 納入規則）所有實際發生的 `nowPlaying` 的**觀測最大值** ≤ 1.5 s |
| M2 | 每個 AE 工作 block 的 等待／執行 | `run` 入佇列 → `body` 開始 → `body` 結束（`defer` 記錄；`enqueue` 內的 `lastError` 檢查與 continuation 不計入，那兩步是本機呼叫、不送 AE） | 歸因：M1 以請求 ID 連到它自己的 block；報表依實際 `start` 順序列出它入列時尚未完成的所有 block（只是已觀測的排隊，不是理論上界，Codex R2） |
| M3 | 換歌通知 → `trackChanged`（使用者原話「`playerDidChange`→`trackChanged` 端到端」） | 一批 playerInfo 通知（被同一次讀取吸收的）中最早的一則 → monitor `continuation.yield(.trackChanged…)` 那一刻 | 體感觀測；**非驗收、不設門檻**；該批讀取沒有發出 `trackChanged`（同一首、沒在播、讀取失敗）時記結果、不記端到端毫秒；**不宣稱每則通知對應一次切歌**（通知與切歌不是一對一，Codex R1-5） |

- 判讀：觀測最大值 ≤ 1.5 s → 達標，交使用者簽（簽字文字寫「本次掃描觀測最大值 X ms／N 筆」）；> 1.5 s → 未達標，停下另議。
- p50／p95 只作診斷，算法固定 nearest-rank；驗收只看最大值（Codex R1-13）。

### 5.2 事件（只有三種＋一個非驗收流，不可變、全為數字或編譯期字串）
| 事件 | 欄位 |
|---|---|
| `boot` | `app=<啟動 nonce> pid=<pid>`（每行都帶 `app=`，報表只接受單一 app 啟動的資料，Codex R1-10） |
| `scan` | `scan=<token> begin|end outcome=<complete|incomplete|cancelled|error> t=<ms>` |
| `np` | `req=<請求 ID> scan=<交集的 token 清單或 -> start=<ms> end=<ms> total=<ms>` |
| `run` | `run=<序號> req=<請求 ID 或 -> op=<編譯期函式名> enq=<ms> start=<ms> end=<ms> wait=<ms> exec=<ms> scanAtEnq=<token|-> scanAtStart=<token|->` |
| `sig`／`batch`（M3，非驗收） | `sig=<ID> t=<ms>`；`batch req=<請求 ID> sigs=<最小>-<最大> n=<數量> result=<changed|nochange|notplaying|error> e2e=<ms|->`（`e2e` 只在 `changed` 時有值，終點＝`trackChanged` 送出時刻；沒有收到通知的讀取**不寫** batch） |

- 時間：`ContinuousClock`（單調），`t`＝自 probe 起點的毫秒，同一 app 啟動內可排序。
- **請求 ID**：monitor 每次讀取產生 `req`，用 DEBUG 的 `@TaskLocal` 帶進 `music.nowPlaying()`；`run` 在 `Self.queue.async` **之前**（`withCheckedThrowingContinuation` 的建立閉包在呼叫端同步執行）把 `req` 與入列時間快照成區域常數，寫進 `run` 事件——`np` 與它自己的 `run` 以 ID 關聯，不用時間猜配（Codex R1-2）。
- **掃描 token**：`beginScan()` 回不可重複 token、`endScan(token, outcome)` 只結束自己；同時進行的掃描可以多個（`rescan()` 取消舊 Task 後立即開新的，舊的 AE block 停不下來，區間會重疊，`LibraryCheckViewModel.swift:58-70`；Codex R1-3）。
- **M3 批次**：通知到達時取 `sig` ID；monitor 某次讀取的理由含 `.playerSignal` 時，在**讀取開始**把當時待配對的通知全部收進這一批（讀取進行中才到的通知會進 `followUp`，屬於下一批），讀完記 `batch`。
- **脫敏**：事件只接受整數、列舉與 `StaticString`。`op` 用 `StaticString`（`#function`）——型別上只能是編譯期字面量，執行期的曲名、歌手、ID、歌詞**無法**傳進來（Codex R2 判此點我方對）。分類封閉靠**報表端**：`ae_latency_report.py` 內建允許的 `op` 清單（目前 `MusicAppleEventsClient` 內呼叫 `run` 的函式名），遇到清單外的 `op` 判量測無效、並列出該名稱——新增呼叫點忘了登記只會讓量測無效（fail-closed），不會靜默錯分。不做解析 Swift 原始碼的測試（脆弱，Codex 整體確認 #5）。所有 OSLog 插值都是 `.public` 的數字或固定字串。

### 5.3 程式（全部在 `#if DEBUG`；Release 的 `run` 簽名與本體不變）
- 新檔 `Services/Music/AELatencyProbe.swift`（整檔 `#if DEBUG`，不 import ScriptingBridge）：
  - `AELatencyLedger`（純值型別，可單元測試）：掃描 token 集合與區間、請求 ID／run 序號／通知 ID 計數器、待配對通知；事件格式化（唯一的格式化入口）。
  - `AELatencyProbe`：薄殼——`OSAllocatedUnfairLock<AELatencyLedger>`、`@TaskLocal static var requestID`、`Logger(category: "latency")`（`.notice`）。啟動時記一次 `boot`。
  - `AELatencyProbe.beginRun(operation:) -> RunToken`：**在呼叫端 task 上**快照 `requestID`、入列時間與當下掃描 token；`RunToken.started()`／`finished()` 在佇列 block 內記開始／結束。這是 `run` 與 TaskLocal 之間唯一的接縫，可不經 ScriptingBridge 單元測試。
- 呼叫點（每處包 `#if DEBUG`）：
  1. `MusicAppleEventsClient.run`：現有 `run` 改名為 private `enqueue`（簽名、本體不變）；`#if DEBUG` 下新增帶 `operation: StaticString = #function` 的 `run` 包裝——先 `beginRun`（在 `queue.async` 之前，呼叫端 task 上），再把 `body` 包成「開始記 `started`、`defer` 記 `finished`」交給 `enqueue`（錯誤照拋、`lastError` 檢查與 continuation 行為不變）；`#else` 下 `run` 直接轉呼叫 `enqueue`、簽名與現在相同（Codex 整體確認 #1：不以「功能等價」取代使用者的 DEBUG-only 指示）。各呼叫點零改動。
  2. `NowPlayingMonitor.readOnce`／`read`：產生 `req`、以 `$requestID.withValue` 包住 `read()`；`nowPlaying()` 前後記 `np`；理由含 `.playerSignal` 時在讀取開始收批；`continuation.yield(.trackChanged…)` 那一刻記批次終點；讀完記 `batch`。
  3. `AppModel` 換歌通知閉包：`sig`（跳進 actor 的 `Task` 之前）。
  4. `LibraryGateScanner.scan`：`beginScan`／`endScan` 以作用域封裝涵蓋所有出口（完成、不完整、取消、丟錯）。
- 覆蓋率豁免檔：先量後定。實作後跑 coverage_gate，`MusicAppleEventsClient.swift` 若超過 490 → **停下請使用者批准**，不自行調預算（Codex R1-8）。probe 的 ledger 以單元測試覆蓋，薄殼只留鎖與 log 呼叫。

### 5.4 樣本納入規則（報表可重算，Codex R1-6）
- M1 納入＝`np` 的 `[start, end]` 與任一 `scan` 的 `[begin, end]` 有交集；另分「掃描前」「掃描後」兩段作基線。
- M2 歸因的「掃描 block」＝`op` 為 `libraryTrackSnapshot()`／`artistLyrics(artist:)` 的 `run`。

### 5.5 報表（`Scripts/ae_latency_report.py`，fail-closed，Codex R1-7）
- 輸入：live `log stream --style ndjson` 檔（**唯一證據**；`log show` 只作診斷，不回填）。
- 輸出：三段（前／中／後）M1 筆數、最大值、p50／p95（nearest-rank）、原始排序值；M1 最大那筆的 `run` 與它入列時尚未完成的 block；M3 批次表；納入／排除清單與理由。
- **量測無效（不出結論、不可簽）**：
  - session：`boot` 不是恰好一筆、或不是第一筆事件；任一行的 `app=`／`pid=` 與 `boot` 不同；任一行解析失敗或缺欄位。
  - 掃描：任一 `scan` 缺 begin 或 end；沒有 `outcome=complete` 的掃描；**任兩個掃描區間重疊**（Codex R2）。
  - 關聯：每個 `req` 必須**恰有**一筆 `np` 與一筆 `run`（雙向一對一，拒絕重複與孤兒）；`run` 序號不連續；出現未知 `op`。
  - 樣本：掃描期間 M1 為 0 筆。

## 6. 任務清單（單人主 session 依序；每項先紅後綠）
| # | 任務 | DoD |
|---|---|---|
| L1 | `AELatencyLedger`＋`beginRun` 接縫 | 單元測試（Swift Testing）：token 唯一、重疊掃描「舊取消→新開始→舊晚結束」各自正確結束；交集清單；請求 ID／run 序號遞增；通知批次＝讀取開始時待配對者、進行中到達者歸下一批、無通知時不產生 batch、`changed` 才有 e2e；**`beginRun` 在 `$requestID.withValue(7)` 內呼叫 → token 的 req＝7；在 `DispatchQueue.async` 內（無 task）呼叫 → req 為空**（釘住「必須在 `queue.async` 之前快照」的理由，Codex 整體確認 #2）；毫秒換算（含 attoseconds）；格式化輸出逐行符合 allow-list regex（只有固定字樣、數字、`StaticString` 函式名字元集） |
| L2 | 四個呼叫點接線 | 既有測試全綠（`NowPlayingMonitorTests`、`LibraryGateScannerTests`、`AppModel*`、`MusicSelectorAllowListTests`）；新增：替身 music 下 monitor 讀取期間替身讀到的 `requestID` 等於該次 `np` 的 `req`（只證明 monitor 端設好 TaskLocal；**不**當成 AE client 的證據）；真 client 的 `run`↔`np` 一對一由 L5 報表的 fail-closed 規則在真機證明；選擇器白名單不變；`no_playback_gate.sh` 綠；coverage_gate 豁免檔 ≤ 490（超過即停） |
| L3 | `ae_latency_report.py` | Python 單元測試：三段切分、交集納入、排隊歸因、nearest-rank、批次表；§5.5 每一種無效情形各一條（含清單外 `op`） |
| L4 | Release 驗證 | `xcodebuild -showBuildSettings -configuration Release` 的 `SWIFT_ACTIVE_COMPILATION_CONDITIONS` 不含 `DEBUG`；Release 建置（`-derivedDataPath` 用 `mktemp -d`）後 app 執行檔 `nm` 無 `AELatencyProbe`／`AELatencyLedger` 符號、`strings` 無事件字樣（`req=`、`scanAtEnq=`、`batch req=`） |
| L5 | 使用者在場 #1（§7） | 報表判定「有效」；掃描中至少 1 次使用者切歌（M3 有 ≥ 1 批 changed） |
| L6 | ACCEPTANCE I-68 | 狀態欄記「本次掃描觀測最大值／筆數」、歸因、M3 批次；依 §5.1 判讀交使用者簽（含原暫緩條件「6 組合 264 首可抽配色改變」） |

## 7. 使用者在場 #1（一次一步，回報後才給下一步）
1. 我建 Debug 版（derivedData 在 session scratchpad）、背景啟動 `log stream --predicate 'subsystem == "com.ibridgezhao.azathothswhisper" AND category == "latency"' --level info --style ndjson` 到 scratchpad 檔，確認檔案已開始寫入。請你關掉正式版（只留一個 Azathoth's Whisper）、開 Debug 版、點完鑰匙圈授權框（若跳出 Music 自動化授權也請允許）。
   - **開量前的關卡**（Codex 整體確認 #4）：我確認①只有一個 Azathoth's Whisper 行程、②日誌裡有該 PID 的 `boot`、③已有至少一筆成功的 `np`＋對應 `run`（Debug 版真的讀得到 Music）。任一不成立 → 處理授權後重開 Debug 版、換新的日誌檔再來，不進第 2 步。
2. 請你在 Music 播歌，等 10 秒後切一首（掃描前基線）。
3. 請你開 `Settings ▸ Library Check...` 按 Rescan，掃描進行中（約 70 秒）切一首；想多切幾次更好。**掃描中不要再按 Rescan**（會多一個重疊掃描，報表判無效、要重做）。
4. 掃描結束後再切一首。我跑報表：無效就說明原因、重做一次；有效就給結果。
- 我不碰 Music；輪詢本身在掃描中約有 20 多次 `nowPlaying`，也都算進 M1。

## 8. 測試策略
- 單元：L1（Swift Testing）、L3（Python unittest）。
- 整合：L2 的既有 monitor／scanner／AppModel 測試保證量測點不改控制流；新增 `req` 關聯一條。
- E2E：在場 #1 本身即真機端到端；不新增 XCUITest（量的是真 Music 的 AE 時間，替身量不出來）。

## 9. 影響面
- 新檔 3（probe、report）＋測試 2；改檔 4（AE client、monitor、AppModel、scanner）。AE client 的 `run` 改名 `enqueue`（本體不變），Release 的 `run` 只轉呼叫、簽名不變；其餘全是 `#if DEBUG` 區塊。Release 以 L4 驗證（不宣稱二進位不變）。

## 10. 風險與回退
- 量測本身拖慢讀取：每次多一次鎖＋一行 notice 日誌，推測 < 1 ms，相對 142 ms 平均可忽略；報表裡可見 `exec` 是否異常。
- 不達標：停下，不改程式；把歸因與候選方案（例：掃描 block 預算下修、掃描中讓 `nowPlaying` 插隊）交 /thecure 後給使用者。
- 回退：刪 probe 檔與 DEBUG 區塊，`enqueue` 改回 `run`。

## 附錄 A Codex 評審與辯論紀錄

### R1（2026-11-01，審 v0.1）處置
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| 1 | 阻斷 | 單次掃描只得觀測最大值，不能證明「最壞」；建議受控 `forceRefresh` 取樣 | **部分採納**：判準改「觀測最大值」並加相位無關上界 B（§5.1）；兩者不一致交使用者拍板。**駁回**受控取樣：`forceRefresh` 會清 `lastSignature` 並重發 `trackChanged`，Editor／歌詞特效會重新處理當前曲（`NowPlayingMonitor.swift:182-188`），量測會改變被量系統；B 已涵蓋相位 |
| 2 | 阻斷 | `np` 與 `run` 無共同 ID | **採納**：`@TaskLocal` 請求 ID |
| 3 | 阻斷 | 重掃時掃描區間重疊，「覆寫」會錯關新掃描 | **採納**：token（讀碼確認 `rescan()` 取消後立即新開） |
| 4 | 高 | M2 是 block 不是單個 AE | **採納**：改稱 AE 工作 block；「每次 AE ≤ 1.5 s」由 `AEBudget` 結構保證，M2 只佐證 |
| 5 | 高 | 通知與切歌非一對一，逐筆配對是假歸因 | **採納**：M3 改批次、非驗收 |
| 6 | 高 | `scan=` 語義未定義 | **採納**：§5.4 交集規則，`run` 分記入列／開始時的 token |
| 7 | 高 | 報表完整性規則不足 | **採納**：§5.5 fail-closed 清單 |
| 8 | 高 | 豁免預算只剩 7 行，「約 3」是估算 | **採納**：先量；超過 490 停下請使用者批准 |
| 9 | 中 | 格式化測試無效；`op` 應為列舉白名單 | **採納**唯一格式化入口＋allow-list regex；**駁回**列舉：`StaticString` 型別上只能是編譯期字面量，執行期資料無法傳入，保證強於列舉，且不必改十多個呼叫點（待 R2 反駁） |
| 10 | 中 | `.notice` 不保證落盤；跨行程污染 | **採納**：live stream 唯一證據、`boot` nonce＋pid、單一啟動 |
| 11 | 中 | `strings` 不足；預設參數若不包 DEBUG 已改 Release | **採納**檢查編譯條件＋`nm` 符號＋字樣、改稱「功能等價」；**部分駁回**：`operation` 參數兩種建置都存在（包 DEBUG 需複製整個 `run` 簽名），Release 不讀它、行為不變（待 R2 反駁） |
| 12 | 中 | 過度設計；精簡為三種事件 | **採納**：§5.2 三種事件＋M3 獨立非驗收流 |
| 13 | 低 | p50／p95 算法未定 | **採納**：nearest-rank，只診斷 |

### R2（2026-11-01，審 v0.2）
| 項目 | 判定 | 處置（v0.3） |
|---|---|---|
| R1-1 受控取樣 | 各對一半：拒絕 `forceRefresh` 對（會改變被量系統）；但 v0.2 說 B 涵蓋相位不對 | 簽字依據明寫「本次掃描觀測最大值」（T0 原定方法即 DEBUG 量測＋在場看日誌），ACCEPTANCE 照實寫 |
| R1-9 `StaticString` | **我方勝**（型別阻斷執行期資料）；Codex 補「分類要封閉」成立 | 保留 `StaticString`；允許 `op` 清單＋未知即無效＋測試比對原始碼 |
| R1-11 `operation` 參數 | 各對一半 | 宣稱改為「Release 功能等價」，不稱全部 DEBUG-only |
| B 不是上界 | **Codex 勝**（`CardDetailsReader.swift:21` actor 可重入、封面／位置時鐘同佇列） | 刪除 B；M2 只做已觀測排隊的歸因 |
| 重疊掃描 | **Codex 勝**（`LibraryCheckViewModel.swift:58`） | 重疊即量測無效 |
| TaskLocal 讀取時點 | 已解決（Codex 確認可行，提醒要在 `queue.async` 前快照） | §5.2 寫明 |
| 空批 schema | 採納 | 無通知不寫 batch |
| 關聯一對一、session 邊界 | 採納 | §5.5 補齊 |

### R3（2026-11-01，審 v0.3）
- Codex：「可定稿。附錄 A R2 各項處置已落實於 §3、§5、§6、§7，未見阻斷或高嚴重度遺留／新引入問題。」

### 整體確認（/thecure 第 7 步，2026-11-01，審 v0.3）
| # | 異議 | 判定 | 處置（v0.4） |
|---|---|---|---|
| 1 | `operation` 參數留在 Release 與使用者「只加 DEBUG-only」衝突 | **Codex 勝**（我方 R2 以「功能等價」帶過，不能取代使用者指示；我方自查同結論） | `run` 改名 `enqueue`；DEBUG 包裝帶 `operation`，Release 的 `run` 簽名不變 |
| 2 | 替身不走 `MusicAppleEventsClient.run`，L2 的 `req` 關聯測試證明不了 client | **Codex 勝**（`NowPlayingMonitor` 注入 `any MusicControlling`） | 抽 `beginRun` 接縫單測快照時點；L2 只證明 monitor 端；client 端一對一由真機報表 fail-closed 證明 |
| 3 | §1 寫「`playerDidChange`→`trackChanged`」，M3 卻量到讀取結束 | **Codex 勝**；選照使用者原話 | 終點改為 `trackChanged` 送出時刻 |
| 4 | 在場關卡不足（授權、正式版未關） | 採納 | §7 第 1 步加三項關卡 |
| 5 | 解析原始碼鎖 `op` 清單太脆弱 | 採納方向；方案不同：不改呼叫點，改由報表端清單＋清單外即無效 | §5.2 脫敏段（待 R2 確認） |
- 順序：Codex 建議 L1 →（真 `run` 接縫）→ 其他接線 → 報表 → Release 驗證 → 在場關卡 → 量測 → 簽；v0.4 的 L1 已含接縫，順序等價。
- 最容易失敗的一步：L2（原設計會給出誤導性的綠燈）→ 已拆。

### R2（2026-11-01，審 v0.4）
- 第 5 條（報表端清單＋清單外即無效）：Codex 判「可接受，且是對的」。第 1–4 條已落實、無矛盾。
- 新異議 2 條，皆採納：①`finished` 在 `lastError` 檢查前 → M2 終點明定為 `body` 結束、以 `defer` 記錄；②`beginRun` 單測證明不了 `run` 真的在 `queue.async` 前呼叫 → 列為 code-review 不變條件；另外真機報表本身會抓到：若快照放錯位置，`run` 的 `req` 會是空的，§5.5「每個 `req` 恰有一筆 `np` 與一筆 `run`」即判量測無效。
- 未解決清單：無。

## 附錄 B 實作記錄（2026-11-01，`wip/lyrics-leftovers-2026-11`）
- **L1**：`Tests/Services/AELatencyProbeTests.swift` 先寫 → **編譯紅**（`AELatencyLedger`／`AELatencyFormat`／`AELatencyProbe` 未定義）→ 實作 `Services/Music/AELatencyProbe.swift`（整檔 `#if DEBUG`）→ 13 條綠。過程中兩處是測試本身寫錯、已改正（非放寬）：`#expect` 內不能呼叫 mutating 方法（先取值再斷言）；allow-list 正則的欄位名漏了數字（`e2e`），欄位名仍限固定字樣。
- **L2**：`NowPlayingMonitorLatencyProbeTests` 先紅（替身看到的請求 ID 為空）→ 接線後綠。接線位置與計劃的差異：掃描 token 的作用域放在 `AppModel` 組裝 `scanLibrary` 的閉包（`AELatencyProbe.measuringScan`），不改 `LibraryGateScanner` 本身——效果相同、scanner 零改動。`run` 的本體改名 `enqueue`（原計劃寫 `perform`，撞到 `no_playback_gate.sh` R3 禁止的 `perform(` 字樣，改名、閘門不動）。受影響 18 suite 174 條綠；`no_playback_gate.sh` exit 0。

## 附錄 C simcodex（2026-11-01，3 輪；審 `main...HEAD`＋各輪工作樹修改）
| 輪 | 來源 | 意見 | 處置 |
|---|---|---|---|
| 1 | codex review --base main [P2] | `MockMusicClient` 無條件引用 DEBUG-only 的 `AELatencyProbe`，Release 組態編測試會失敗 | **採納**：包 `#if DEBUG` |
| 1 | security-reviewer | 無 CRITICAL／HIGH。M1：報表遇畸形輸入（非物件 JSON、非字串訊息、`run` 的 `req` 非數字、非 UTF-8、缺檔）會崩潰成退出碼 1＝與「未達標」撞號；L1：`emit` 收任意字串＋`.public`，型別保證有後門；L5：證據檔含本機路徑 | **採納 M1**（每事件欄位表＋讀不了檔回 3，各補測試）、**L1**（`AELatencyLine` 初始化器 fileprivate、`emit` 改 private）、**L5**（證據檔只放 scratchpad、不 commit，ACCEPTANCE 只貼報表輸出）。L4（Release 多一層轉呼叫）功能等價，記錄不改 |
| 1 | simplify 簡化 P1 | 兩套讀取結果列舉＋兩個結構；每個格式函式都傳 `app`／`pid` | **採納**：合併為 `ReadSummary`；前綴在 `AELatencyLine.rendered` 統一加 |
| 1 | simplify P2 | 計數器、通知批次、`endScan` 回傳值、`nowPlayingStarted`、掃描結果判斷 | **採納**（便宜）；`isComplete` 放 probe 檔的 private extension，不改 Release 的 scanner |
| 1 | simplify 重用 P1 | 毫秒換算改用 `Duration.inSeconds` | **駁回**：Double 截斷會把 290 ms 算成 289（0.29 存成 0.28999…）；整數換算才精確 |
| 1 | simplify 層級 P2 | 以測試讀 Swift 原始碼比對 `op` 清單 | **駁回**：/thecure 整體確認 #5 已判定太脆弱，維持報表端清單＋清單外即無效 |
| 2 | codex review --uncommitted | 無 | — |
| 2 | simplify 層級 P1 | 報表逐種補洞；未預料的例外仍會變退出碼 1 | **採納**：`main()` 入口統一攔所有例外回 3，補測試 |
| 3 | codex review --uncommitted [P1] | 巢狀 `RunToken` 不加型別名呼叫外層靜態成員會編不過 | **駁回（誤報）**：重建後 `AELatencyProbeTests`＋`NowPlayingMonitorLatencyProbeTests` 15 條綠，Swift 巢狀型別可直接用外層靜態成員 |
| 3 | simplify 簡化 P1 | `EXIT_CODES.get` 的預設值是死碼 | **採納** |
- 每輪驗證：受影響 18 suite 174 條綠（第 1 輪修正後）、probe 兩個 suite 15 條綠（第 3 輪）；Scripts 471 條綠；`no_playback_gate.sh` 綠；豁免檔 489／490；probe 覆蓋 168／175。
- AppModel 的 `scanLibrary` 保留 DEBUG／Release 各一整行：合併成一個閉包會改到 Release 那一行原文。
- 遺留 P2：報表無效輸出與 `render` 的格式兩處定義；`MockMusicClient` 帶 probe 專用欄位（可改測試端包裝）；monitor 端決定 `nochange`／`notplaying` 語意（可改傳 Bool）。

## 附錄 D 使用者在場 #1（2026-11-01 22:0x–23:1x）
- 第一份錄製（`onsite-1.ndjson`）在掃描前被我設的 `alarm 3600` 截斷（22:04 開、23:03 停）——上限設太短，非程式問題；第二份混到舊行程的行（報表會判無效），作廢；第三份（`onsite-3.ndjson`，Debug 版重開前開錄）有效。證據檔只在 session scratchpad、不 commit（含本機路徑）。
- 開量前關卡：只有一個 Debug 行程、`boot` 為第一行、已有 `np`＋對應 `run` → 通過。
- 報表（`onsite-3-snapshot.ndjson`）：**達標**。掃描中 19 筆，最大 200 ms、p50 85 ms、p95 200 ms；掃描前 722 筆最大 206 ms；掃描後 60 筆最大 130 ms。最慢一筆 run=992：等待 118 ms（前面是 `artistLyrics` 執行 112 ms）、執行 82 ms。掃描讀取：snapshot 1 次 173 ms；`artistLyrics` 491 次，p50 20 ms、最慢 787 ms。換歌通知批次 8 批，`changed` 3 批：157／109／131 ms。
- 推測（非實測）：`nowPlaying` 若恰好排在最慢的 787 ms 讀取後，約 880 ms，仍低於 1.5 s。
