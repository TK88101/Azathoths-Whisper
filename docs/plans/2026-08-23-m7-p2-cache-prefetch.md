# M7 P2：Cover Flow 磁碟快取與預取 —— 實施細化

- 日期：2026-08-23
- 狀態：**已實施並通過 Phase 3 評審**（Plan 定稿經 Codex 兩輪對抗評審：R1 12 條＝7 採納／4 修改採納／1 部分駁回；R2 四項駁回中三項 Codex 接受不重提、#7 以措辭重提並採納，另 4 點新設計意見全部採納。記錄見附錄；實施後另跑 3 輪 simcodex，記錄見文末附錄）
- 上游：`docs/plans/2026-08-23-m7-coverflow.md` §5（P2 任務清單與 DoD，**契約層已定稿**，本檔不重議）
- 驗收：`AzathothsWhisper/ACCEPTANCE.md` H-06（預取）／H-07（快取）
- 基線：HEAD `503d620`，單元測試 220 全綠（29 suites，本會話 10:58 實測），覆蓋率 87.5%，`Services/Artwork/` 100%

本檔只做一件事：把 M7 §5 的契約落到**檔案、型別、讀寫順序、併發模型**，
並對 §5 未定的設計點給出決定與理由。§5 已有的 DoD 逐條對映到測試名。

## 0. 勘察事實（已核實）

| 事實 | 位置 |
|---|---|
| `ArtworkService` 是 actor，讀序＝記憶體 → AE；in-flight 去重用 `[String: Task]` | `Services/Artwork/ArtworkService.swift:33-49` |
| `ArtworkProviding` 只有一個方法 `artwork(for:)`；View 用 `.task(id:)` 按需取，VM 無回寫路徑 | `ArtworkService.swift:6-8`／`CoverFlowView.swift:87-101` |
| `MusicAppleEventsClient.run` 是單一串行 `DispatchQueue` 上的**同步** AE 呼叫；artwork 已設 `SBApplication.timeout = 90 ticks`（1.5s）；`currentTrack()` 無 AE timeout；每次 `run` 新建 `SBApplication` | `MusicAppleEventsClient.swift:155-181` |
| `NowPlayingMonitor.tick()` 走 `currentTrack()`＋`currentLyrics()`，與 artwork 共用上述佇列 | `NowPlayingMonitor.swift:95-124` |
| `AppModel.init` 直接 `ArtworkService(music:)`；`live()` 是唯一生產組裝點；`stop()` 是同步方法 | `AppModel.swift:58-61`／`:120-150`／`:184-188` |
| 測試替身：`MockMusicClient.artworkData` 計數 `artworkCalls`／`artworkInFlight`，可掛 `LyricsGate` | `Tests/Support/MockMusicClient.swift:137-148` |
| `StubArtworkProvider` 是 VM 測試的替身（需隨協議擴充） | `Tests/Features/CoverFlowViewModelTests.swift:339` |
| 全庫無 CryptoKit 引用；SHA-256 用 `CryptoKit.SHA256`（macOS 14 deployment target 可用） | grep |
| 覆蓋率閘門只算 `Services/`＋`Infra/` | `Scripts/coverage_gate.sh` |

## 1. 目標與非目標

**目標**
- H-07：磁碟 LRU 快取（actor），冷啟動命中即顯；損毀檔容錯；metadata 原子替換與損毀處理。
- H-06：中心優先、兩側低優先級、可取消的預取；同 ID 共享；失敗 backoff 且到期可重試。
- **AE 公平性（收窄後的承諾，Codex R1 #1）**：artwork 對 monitor 等待的貢獻**最多一個 AE 呼叫**
  （≤`artworkTimeoutTicks` 1.5s）——不承諾 monitor 絕對 deadline（其自身 `currentTrack()` 無 timeout、
  Editor／Batch 的呼叫同樣排隊，皆為 P1 既有狀態，非本階段範圍）。
- M7 §5 的 11＋6 條 DoD 全部有對應測試；`Services/Artwork/` 覆蓋率 ≥ 90%。

**非目標**
- 不改 `MusicAppleEventsClient`（理由見 §3.3）。
- View 層**只改一處**：`CoverFlowItemContainer.task(id:)` 的 key 加入 `artworkRevision`（§3.3 backoff 重試需要，Codex R1 #6）。
- 不動 Editor／Batch／monitor 語義；不新增 `BusySource`（M7 §0 既定約束）。
- 不做 M8 真機效能驗證。

## 2. 檔案佈局

```
Services/Artwork/
  ArtworkDiskCache.swift          新增 ~300 行  actor：檔案 I/O、LRU、原子寫入、啟動清理
  ArtworkDiskCacheMetadata.swift  新增 ~80 行   Codable 模型 + JSON 讀寫 + 異常值清洗
  ArtworkFailureBackoff.swift     新增 ~50 行   失敗退避表（純值型別，可注入時鐘）
  MonotonicClock.swift            新增 ~25 行   單調時鐘協議 + 系統實作
  ArtworkService.swift            重寫 ~260 行  三級讀序 + 單槽 AE 排程 + 預取集合 + 完成通知
Features/CoverFlow/
  CoverFlowPrefetchWindow.swift   新增 ~40 行   純函數：中心±N、方向優先的預取序
  CoverFlowViewModel.swift        修改 +~55 行  預取觸發點、generation 門、artworkRevision
  CoverFlowView.swift             修改 ~3 行    `.task(id:)` key 含 revision
App/AppModel.swift                修改 +~10 行  注入磁碟目錄（live 用 Caches；測試 nil）
Tests/Support/
  SerialAEQueueMusicClient.swift  新增 ~80 行   模擬單一 FIFO AE 佇列的替身（DoD ⑥ 整合測試用）
Tests/Services/
  ArtworkDiskCacheTests.swift     新增          §5 DoD ①–⑪ ＋ 降級測試
  ArtworkFailureBackoffTests.swift 新增
  ArtworkServiceTests.swift       擴充          預取 DoD ①–⑥、取消、狀態機
  ArtworkAEFairnessTests.swift    新增          FIFO 模型整合測試
Tests/Features/
  CoverFlowPrefetchWindowTests.swift 新增
  CoverFlowViewModelTests.swift   擴充          預取觸發矩陣；StubArtworkProvider 記錄 prefetch 呼叫
```

新增檔案後跑 `xcodegen generate`（首次重建走後台、不設短 watchdog——M6 closeout 教訓）。

## 3. 設計決定

### 3.1 讀寫順序與磁碟內容

讀序：**記憶體 → 磁碟 → AE**。寫序：AE 成功 → 解碼縮圖（≤512px）→ **寫記憶體 ＋ 寫磁碟**。

磁碟存的是**縮圖的 JPEG 重新編碼**（壓縮係數 0.85），不是 AE 原始位元組。
理由：原始封面常為 1–5MB，50MB 配額只裝得下十幾張，H-07「冷啟動即顯」形同虛設；
512px JPEG 約 30–80KB，200 張 ≈ 10–16MB。上游 §4.8 原文即「磁盤**縮圖**緩存」。

`ArtworkDiskCache` **對內容不可知**（bytes in／bytes out），編解碼留在 `ArtworkService`。
磁碟命中時仍走 `thumbnail(from:)` 解碼；解碼失敗＝損毀 → service 呼叫 `disk.remove(for:)` 後落到 AE。

**persistentID 入口校驗（Codex R1 #8）**：空字串在 `artwork(for:)` 直接回 nil、在 `prefetch` 被過濾，
不讀寫磁碟、不進 backoff、不打 AE（`findTrack` 本就拒絕空 ID）。`ArtworkDiskCache` 同樣拒絕空 ID。

### 3.2 `ArtworkDiskCache`（actor）

```swift
actor ArtworkDiskCache {
    struct Limits: Sendable { var countLimit = 200; var byteLimit = 50 * 1024 * 1024 }
    init(directory: URL, limits: Limits = .init())     // 不做 I/O；首次存取才 load
    func data(for persistentID: String) -> Data?       // 命中更新 access sequence
    func store(_ data: Data, for persistentID: String)
    func remove(for persistentID: String)
    func flush()                                       // 把 access 更新落盤（測試用；生產靠閾值）
    var entryCount: Int { get }
    var totalBytes: Int { get }
}
```

**檔名**：`SHA256(persistentID.utf8)` 的 64 hex，無副檔名。metadata 記 `hash → persistentID`，
讀取時驗證；不匹配 → 刪檔＋刪 entry → miss（Codex #1）。

**metadata**（`metadata.json`，同目錄）：
```json
{ "version": 1, "nextSequence": 124,
  "entries": { "<64hex>": { "persistentID": "…", "size": 41234, "lastAccess": 123 } } }
```
- 寫入：temp 檔（同目錄，`metadata.json.tmp-<UUID>`）→ 首次 `moveItem`／已存在 `replaceItemAt`。
- **讀取失敗分兩類（Codex R1 #4 修改採納）**：
  - **I/O 錯誤**（檔案存在但讀不到：權限、暫時性錯誤）→ 本次 session **降級為純 miss**：不刪任何檔、不寫入；
    每次 `data`／`store` 回 nil／no-op。
  - **內容損毀**（讀到位元組但 JSON 解析失敗、`version` 不符）→ 刪 metadata 並**清空目錄**（見下）。
- 異常值清洗（逐 entry，不整體作廢）：key 非 64 hex、`size < 0`、`lastAccess < 0`、`lastAccess ≥ nextSequence`
  的 entry 丟棄（連同其檔案——只對 64 hex key 建路徑，**非 hex key 永不觸碰檔案系統**，杜絕路徑穿越）。
- 載入時比對檔案系統：entry 指向不存在的檔 → 刪 entry；`size` ≠ 實際檔案大小 → 刪檔＋刪 entry（截斷檔）；
  目錄裡有檔無 entry（orphan）→ 刪檔。

**損毀重建策略＝清除快取檔（對 §5「以檔案 attributes 作 fallback」的具體化；Codex R1 #4 quarantine 建議駁回、R2 接受）**：
完整 SHA-256 單向，metadata 內容損毀後任何檔案的 persistentID 都不可恢復，
§5 已裁定「不匹配即視為 miss 並刪除」——無法驗證的檔案只能歸入「不匹配」。
快取是**可再生資料**（AE 隨時可重取），保留無法驗證的 blob 對使用者零價值，
quarantine 只增加磁碟占用與一套清理策略。代價：原子替換下極罕見的內容損毀後一次冷取圖。
**清除範圍（R2 收緊）**：只刪「檔名為 64 hex」的 artwork、`metadata.json`、`*.tmp-*` 三類；
目錄內任何其他檔案**一律不碰**（`directory` 是外部傳入的 URL，規格不保證專用）。

**LRU**：`nextSequence` 單調遞增，持久化在 metadata；`data(for:)` 命中時 `lastAccess = nextSequence++`。
淘汰：`store` 之後若 `count > countLimit || bytes > byteLimit`，按 `lastAccess` 升序淘汰到限內；
剛寫入的 entry 不在本輪淘汰範圍。單筆 `data.count > byteLimit` 直接拒存。

**落盤時機（Codex R1 #11 修改採納）**：`store`／`remove`／淘汰 **必定**寫 metadata；
`data(for:)` 只更新記憶體中的 sequence 並計 dirty；**累積 16 次 access 更新即落盤**（JSON ≈ 20KB，毫秒級）。
不與 `AppModel.stop()` 耦合——同步 `stop()` 無法等待 actor 落盤，假的「stop 保證」比沒有更糟。
崩潰最多丟 15 次 access 順序（影響未來淘汰次序），不影響正確性——這是**明示接受的耐久性界**。
**dirty 語義（R2 補）**：metadata 寫入失敗 → dirty 計數**保留**，下一次 access／`store`／`remove` 再試；
記憶體中的 entry 表始終反映**檔案系統的實際狀態**（artwork 檔已落地就留 entry，只是尚未持久化索引）——
若到重啟前都沒寫成，該檔下次 load 會被當 orphan 清掉，這是正確結果而非損毀。
load 是首次存取時惰性執行、在同一 actor 呼叫內完成，不存在「load 未完成時的 access」。

**原子寫入（artwork 檔）**：temp `"<hash>.tmp-<UUID>"` 同目錄 → 目標不存在 `moveItem`、存在 `replaceItemAt`。
啟動（首次 load）清掉所有 `*.tmp-*`。

**I/O 失敗降級**：任何寫入失敗（目錄不可建、磁碟滿）→ 記 log、該筆視為未快取；讀取失敗 → miss。
絕不拋到呼叫端。

**I/O 模型**：actor 內同步 `FileManager`／`Data(contentsOf:)`。每筆 ≤ 80KB，阻塞毫秒級；
cooperative pool 上短暫阻塞可接受，且 actor 串行化正是 §5 要的「讀取更新＋eviction 不交錯」。

### 3.3 預取與 AE 公平性：**單槽排程在 service 層，不改 AE executor**

M7 §3 曾寫「真正的優先級需要重新設計 executor——這是 P2 的工作」。本檔**修改此判斷**，
Codex R1 #1／#12 要求 executor 級優先級，**駁回**，論證如下：

AE 呼叫是串行佇列上的**同步**呼叫，正在執行的那一張**不可搶佔**（Swift cancellation 不中斷 dispatch block，
M7 §3 事實修正）。因此**任何** executor 級優先級方案，monitor 的最佳界都是「等完當前那一張 artwork」。
單槽排程（service 任一時刻只向 AE 送 **一張** artwork）達成**完全相同的界**：
monitor 的 `currentTrack()` 入列時，佇列中的 artwork 至多一張（正在執行的那張），下一張要等它回到 service 才會送出，
此時 monitor 已排在前面。executor 優先級在此之上**沒有任何增益**，卻要改三方共用的關鍵路徑（陷阱 2）。

差別只在 backlog **在哪裡等**：在 `DispatchQueue` 裡＝FIFO、不可取消、不可重排；在 service 裡＝可取消、可重排。

**此論證成立的前提（Codex R2 要求明列；任一失效即需重評）**：
1. 所有 artwork AE 呼叫**只**由同一個 `ArtworkService` 實例發出（`AppModel` 唯一持有；Editor／Batch 不呼叫 `artworkData`）；
2. service 在前一張回到自己手上之前不送下一張（單槽）；
3. AE 呼叫不可搶佔；
4. executor 對已入列工作 FIFO，monitor 與 artwork 共用同一 executor。

**誠實邊界**：以上只界定 artwork 的貢獻。monitor 還可能排在 Editor／Batch 的呼叫後面、`currentTrack()` 自身無 timeout——
兩者皆為 P1 既有狀態，H-04 已於 2026-08-23 改為條件式保證，本階段不擴大範圍。

```swift
protocol ArtworkProviding: Sendable {
    func artwork(for persistentID: String) async -> NSImage?
    /// 以 ids 取代目前的預取集合：未開始的舊項取消、新項按序排入；空陣列＝全部取消
    func prefetch(_ persistentIDs: [String]) async
}
```

**`ArtworkService` 狀態機（Codex R1 #3 採納，明寫）**：

```
state: pending: [Entry]          // Entry (class)：id, isExplicit, waiters: [UUID: Continuation], seq
       active: Entry?            // 正在 AE 的那一筆（≤1），**持有自己的 waiters**（R2 修正：只存 id 找不回 continuation）
       drainTask: Task<Void, Never>?
       backoff: ArtworkFailureBackoff
       onStored: (@Sendable (String) -> Void)?   // 完成通知（供 VM per-ID revision）

enqueue(entry):  pending.append; ensureDraining()
ensureDraining(): guard drainTask == nil; drainTask = Task { await drain() }
popNext():       explicit 中 seq 最小者；否則 prefetch 中 seq 最小者（**兩類各自 FIFO**，R2 補）
drain():         while let entry = popNext() {      // popNext 同步、無 await
                     active = entry
                     let image = await fetch(entry.id) // 單一 completion path：AE 拋錯／nil／解碼失敗 → nil
                     let waiters = entry.takeWaiters() // 先取空 waiters、再清 active、最後 resume——同一同步段
                     active = nil
                     resume(waiters, image); if image != nil { onStored?(id) }
                 }
                 drainTask = nil                       // 與最後一次 popNext 同一同步段：此刻任何 enqueue 都在它之後、會重啟 drain
fetch(id):       記憶體／磁碟命中 → 回（不打 AE，DoD ③）；backoff 未到期 → nil
                 → music.artworkData → thumbnail → 寫記憶體＋磁碟 → backoff.clear；失敗 → backoff.record
```

- `artwork(for:)`：記憶體 → 磁碟（命中回填記憶體）→ backoff 未到期回 nil → 若 `active?.id == id` 或已在 pending：
  掛 waiter（在 pending 則 `isExplicit = true`）；否則 enqueue explicit entry。
- **waiter 協議（Codex R1 #2 採納、R2 補競態）**：每個 waiter 持 UUID token；
  `withTaskCancellationHandler` 的 onCancel 呼叫 actor 方法 `cancelWaiter(entryID, token)`，
  該方法**只在 token 仍在 entry.waiters 中**時移除並 resume nil（completion 已 `takeWaiters()` 的 token 找不到 → no-op）。
  註冊與取消的交錯：先同步註冊（actor 內）再進入 `withTaskCancellationHandler`——若 Task 在註冊前已取消，
  handler 立即觸發並由同一條 `cancelWaiter` 路徑清掉。**continuation 只有一條 resume 路徑**（移除者才 resume）。
  entry 若因此沒有 waiter、且**不是 active** → 降級為非 explicit（留在 pending，交由下一次 `prefetch` 替換決定去留）。
- `prefetch(ids)`：過濾空 ID；移除 queue 中 `!isExplicit && id ∉ ids` 的 entry；對 `ids` 依序新增尚未在 queue／active／
  記憶體／退避中的 entry。`active` 不受影響（AE 已送出，結果照樣寫快取）。
- drain 的 Task 本身不被外部取消；service 以 `deinit` 不做清理（AppModel 同壽命）。

**per-item artworkToken（P1 註記「移到 P2」）**：**不需要**。預取的回寫目標是 service 的快取，
不是 VM 狀態；VM 沒有被過期預取污染的寫入路徑。P1 的 `albumGeneration`／`centerID` 兩守衛足夠。

**Backoff（Codex R1 #6／#7）**：`ArtworkFailureBackoff` 純值型別，`record(id, now)`／`clear(id)`／`isDue(id, now)`。
失敗 count **clamp 至 7**，`delay = min(5s × 2^(min(count,7)−1), 300s)`（飽和計算，無 overflow）。
**無 jitter（明示為非目標，R2 措辭採納）**：單槽下不存在**並行**湧入；**串行 backlog** 的上界由 window 決定
（每次 `prefetch` ≤ 10 張），且 backlog 長度不改變「artwork 對 monitor 的貢獻 ≤ 1 call」這個界，故本階段不做 jitter。
**重試觸發＝到期後的下一次 `prefetch` window 或 explicit 請求**（無 service 內 timer）。
為讓已在畫面上、曾拿到 nil 的項目在之後成功時自動更新：service 每次成功寫入呼叫 `onStored(id)`
（service actor 上的 `@Sendable` closure），VM 端以 `Task { @MainActor in … }` 跳回主 actor、
**按 ID** 遞增 `artworkRevisions[id]`（R2：全域 revision 會讓所有可見項一起重跑）；
`CoverFlowItemContainer` 的 `.task(id: ItemTaskKey(id, revision))` 只重跑該項（命中記憶體）。
不在 `items` 中的 ID（舊專輯的殘留完成）**不記錄**，避免字典無界增長。

### 3.4 VM 側預取策略

`CoverFlowPrefetchWindow.ids(items:centerIndex:direction:limit: 5)` 純函數：
按距離 1…limit 展開，**移動方向那一側先**（direction ≥ 0 → `+d` 先於 `−d`），兩端 clamp，不含中心本身
（中心由 View 的 explicit 請求取，天然優先）。

觸發矩陣（對映 §5 事件表）：

| 事件 | VM 行為 |
|---|---|
| `load` 完成且有 playing track | `prefetch(window(center, direction: +1))` |
| `.trackChanged` 真實切歌並自動居中 | `prefetch(window(newCenter, direction: sign(newIndex − oldIndex)))` |
| `userDidScroll`／`stepCenter` | 同上，方向由索引差決定 |
| `.albumChanged` | `prefetch([])`（取消舊批次），載入完成後再依上表排新批 |
| `tabDeactivated` | `prefetch([])` |
| `tabActivated` 且 items 非空 | `prefetch(window(center))` |

**派發順序保證（Codex R1 #10 採納：generation 門）**：
```swift
prefetchGeneration += 1; let g = prefetchGeneration; let previous = prefetchTask
prefetchTask = Task { await previous?.value; guard g == prefetchGeneration else { return }; await provider.prefetch(ids) }
```
過時命令在呼叫 provider 前自行退出，只有最新集合會送達；順序由串鏈保證。

### 3.5 組裝

`AppModel.init(…, artworkDiskDirectory: URL? = nil)`：nil → 純記憶體（所有既有單元測試不碰磁碟，V4）；
`live()` 傳 `~/Library/Caches/com.ibridgezhao.azathothswhisper/Artwork`。
`ArtworkService.init(music:memory:disk: ArtworkDiskCache? = nil, clock:)`。`stop()` 不動。

## 4. 任務清單（每項帶 DoD → 測試名）

### P2-1a `ArtworkDiskCache`（先寫 RED）

| §5 DoD | 測試 |
|---|---|
| ① 命中磁碟回填記憶體 | `ArtworkServiceTests.diskHitPopulatesMemoryWithoutAE` |
| ② LRU 按張數淘汰 | `ArtworkDiskCacheTests.evictsLeastRecentlyAccessedByCount` |
| ③ LRU 按位元組淘汰 | `evictsLeastRecentlyAccessedByBytes` |
| ④ 首次寫入 vs 覆寫 | `firstStoreMovesTempIntoPlace`／`overwriteReplacesExistingFile`（驗內容更新且無殘留 tmp） |
| ⑤ 損毀檔 → 刪除並回 nil | `truncatedFileIsDeletedAndMisses`＋`ArtworkServiceTests.undecodableDiskEntryIsRemovedAndRefetched` |
| ⑥ hash 碰撞驗證 | `mismatchedPersistentIDIsTreatedAsMissAndDeleted`（手寫 metadata 指向別的 ID） |
| ⑦ 同 ID 併發 miss 只寫一次 | `ArtworkServiceTests.concurrentMissesShareOneAERequest`（既有）＋斷言磁碟僅 1 筆 |
| ⑧ 多 ID 併發寫入 | `concurrentStoresForDistinctIDsAllPersist` |
| ⑨ write 與 eviction 交錯 | `interleavedStoresKeepInvariants`（50 筆，終態 count/bytes 在限內、metadata 與目錄一致） |
| ⑩ metadata 損毀後重啟重建 | `corruptMetadataClearsAndRecovers`（壞 JSON → count 0、舊檔被清、再 store 可命中） |
| ⑪ orphan artwork 處理 | `orphanFilesAreRemovedOnLoad` |
| 補：重啟保留 | `entriesSurviveReinstantiation`（H-07 冷啟動） |
| 補：access 序單調 | `accessSequenceIsMonotonicAcrossRestart` |
| 補：access 閾值落盤 | `accessUpdatesPersistAfterSixteenReads` |
| 補：單筆超額拒存 | `oversizedItemIsRejected` |
| 補：殘留 tmp 清理 | `staleTempFilesAreRemovedOnLoad` |
| 補：特殊字元／空 ID | `handlesPersistentIDsWithSpecialCharacters`／`emptyIDIsRejected` |
| 補（R1 #5）：降級 | `unknownVersionIsTreatedAsCorrupt`／`invalidEntryValuesAreDropped`／`nonHexKeysNeverTouchFilesystem`（目錄外誘餌檔不得被刪）／`unreadableMetadataDegradesWithoutDeleting`／`unwritableDirectoryDegradesToMiss` |

全部走 `FileManager.default.temporaryDirectory/UUID`，`defer` 清理。

### P2-1b `ArtworkService` 接磁碟

讀序三級；寫序雙寫；解碼失敗刪磁碟；空 ID 拒絕。測試見上表 ①⑤⑦ ＋ `emptyIDReturnsNilWithoutAEOrDisk`。

### P2-2a `ArtworkFailureBackoff` ＋ `MonotonicClock`

`backoffGrowsExponentiallyAndCaps`／`countIsSaturatedAtSeven`（count 1000 不溢位且 delay == cap）／
`successClearsFailure`／`notDueBeforeRetryAfter`。

### P2-2b `ArtworkService` 預取、單槽排程、取消、狀態機

| DoD | 測試 |
|---|---|
| §5 ① 預取可取消 | `prefetchReplacementDropsUnstartedEntries`（gate 卡第 1 張，替換後原第 2–5 張不打 AE） |
| §5 ② 切專輯取消舊批次 | `CoverFlowViewModelTests.albumChangeCancelsPrefetch` |
| §5 ③ cache hit 不排 AE | `prefetchSkipsMemoryAndDiskHits` |
| §5 ④ 同 ID 共享 | `explicitRequestJoinsPendingPrefetch`（AE 1 次、explicit 拿到圖） |
| §5 ⑤ 失敗 backoff | `failedIDIsNotRefetchedUntilBackoffElapses`（ManualClock 推進前後）／`expiredBackoffIsRetriedByNextPrefetchWindow` |
| §5 ⑥ 在飛不變量 | `prefetchKeepsAEInFlightAtMostOne`（10 張預取＋gate，任何時刻 `artworkInFlight ≤ 1`）／`explicitRequestIsServedBeforePendingPrefetch` |
| R1 #2 取消 | `cancelledExplicitWaiterIsRemovedAndEntryDemoted`／`newCenterIsServedBeforeCancelledExplicit`／`activeEntrySharesResultWithLateWaiter`（R2：active 持 waiters） |
| R1 #3 狀態機 | `failedFetchDoesNotStallQueue`（第 1 張拋錯，第 2 張仍完成）／`drainRestartsAfterQueueDrains`（排空後再 enqueue 仍處理）／`prefetchReplacementKeepsActiveEntry`（R2） |
| R1 #6 完成通知 | `onStoredFiresOnceForEachSuccessfulFetch` |
| R2 清除範圍 | `ArtworkDiskCacheTests.corruptMetadataLeavesForeignFilesAlone`（目錄內非快取格式檔在清除後仍在） |

### P2-2b′ AE 公平性整合測試（Codex R1 #9 採納）

`Tests/Support/SerialAEQueueMusicClient`：一個 actor 內部以 **FIFO 逐一執行** 所有 `MusicControlling` 呼叫
（模擬 `MusicAppleEventsClient` 的單一串行 `DispatchQueue`），artwork 作業可被 gate 卡住，並記錄**執行順序**。
`ArtworkAEFairnessTests.monitorCallWaitsBehindAtMostOneArtworkDuringPrefetch`：
預取 10 張 → 在第 1 張卡住期間呼叫 `currentTrack()` → 放行 → 斷言 `currentTrack()` 在執行序中位於**第 2 個 artwork 之前**。
這證明的是「artwork 對 monitor 等待的貢獻 ≤ 1 call」這個排程性質；**1.5s 的實際時間界由 `SBApplication.timeout` 給出，
屬 M8 真機驗證**——V6 按此措辭，不寫成 deadline 已驗。

### P2-2c VM 觸發

`CoverFlowPrefetchWindowTests`：`ordersByDistanceWithMovingSideFirst`／`clampsAtBothEnds`／`excludesCenter`／`emptyWhenSingleItem`。
`CoverFlowViewModelTests`：`loadCompletionPrefetchesAroundCenter`／`userScrollPrefetchesInScrollDirection`／
`albumChangeCancelsPrefetch`／`tabDeactivationCancelsPrefetch`／`stalePrefetchCommandsAreSkipped`（連發 3 次只送達最後一次，且序正確）／
`artworkRevisionBumpsOnlyForStoredID`／`storedNotificationForUnknownIDIsIgnored`。

### P2-3 組裝與驗收

`AppModel` 注入；`CoverFlowView` 的 task key；ACCEPTANCE H-06 預取欄／H-07 狀態更新；`xcodegen generate`。

## 5. 驗收標準

| # | 標準 | 判定 |
|---|---|---|
| V1 | 單元測試全綠，數量 ≥ 220 ＋ 新增 | `xcodebuild test -only-testing:AzathothsWhisperTests` |
| V2 | 覆蓋率閘門 ≥ 80%；`Services/Artwork/` ≥ 90% | `Scripts/coverage_gate.sh` |
| V3 | H-06 預取欄與 H-07 由 ⬜ 轉 ✅（邏輯層） | ACCEPTANCE 複查 |
| V4 | 測試不碰真實 Caches | grep 測試檔無 `cachesDirectory`；AppModel 測試走 nil |
| V5 | Editor／Batch／monitor 既有用例全綠；`MusicAppleEventsClient` **零 diff** | `git diff --stat` |
| V6 | artwork 對 monitor 等待的貢獻 ≤ 1 call（FIFO 模型整合測試）；**實際 1.5s 界未於單元層驗證，留 M8** | `ArtworkAEFairnessTests` ＋ ACCEPTANCE 註記 |
| V7 | 非 live UITests 不退化（A-10 既有 flaky 除外） | 16 條，≥15 過／1 skipped |

## 6. 影響面

| 檔案 | 性質 | 風險 |
|---|---|---|
| `Services/Artwork/*` | 新增 4 檔、重寫 1 檔 | 低——只有 VM 與 AppModel 呼叫 |
| `ArtworkProviding` 協議 | 新增 `prefetch` | 低——唯一替身 `StubArtworkProvider` 同步擴充 |
| `CoverFlowViewModel` | 新增觸發點、revision | 低——既有 26 條 VM 測試把關守衛語義 |
| `CoverFlowView` | task key 多一個欄位 | 低 |
| `AppModel` | 新增一個可選參數 | 低——預設 nil 不改既有路徑 |
| `MusicAppleEventsClient`／`NowPlayingMonitor`／Editor／Batch | **不動** | — |

## 7. 風險與回退

| 風險 | 徵兆 | 對策 |
|---|---|---|
| actor 內同步 I/O 拖慢 cooperative pool | 滑動卡頓 | 每筆 ≤ 80KB；M8 真機觀察；必要時改 `Task.detached` 包 I/O |
| JPEG 重編碼畫質 | 封面糊 | 0.85 係數、512px；M8 目視，可調 |
| 預取與 explicit 競爭造成中心延遲 | 中心封面晚於兩側 | explicit 優先 ＋ `prefetch` 替換集合；測試 `explicitRequestIsServedBeforePendingPrefetch` |
| revision 重跑 task 造成抖動 | 可見項閃爍 | task 命中記憶體同步回同一 NSImage，SwiftUI 不重繪相同值；M8 目視 |
| 磁碟目錄不可寫 | 零命中 | I/O 失敗靜默降級為 miss（記 log） |

回退單位：`Services/Artwork/` 新檔可整組刪除；`ArtworkService`／VM／View 的 P1 版本在 `503d620`。

## 8. 執行順序

P2-1a（RED→GREEN）→ P2-1b → P2-2a → P2-2b → P2-2b′ → P2-2c → P2-3 → 全量測試 → `/simcodex` → 使用者拍板 commit。

---

## 附錄：Codex 對抗評審辯論記錄（Round 1，2026-08-23，codex-cli 0.147.0）

### 採納（7 條）

| # | Codex 意見 | 處置 |
|---|---|---|
| 2 | explicit waiter 的 `.task` 取消不會通知 service，entry 永遠 explicit、阻塞預取重排 | `withTaskCancellationHandler` 移除 waiter；無 waiter 的未開始 entry 降級為 prefetch；兩條測試 |
| 3 | drain／active／重入未定義，可能停滯或雙 drain | §3.3 明寫狀態機；單一 completion path；`failedFetchDoesNotStallQueue`／`drainRestartsAfterQueueDrains` |
| 5 | 降級場景只測壞 JSON | 補 unknown version／異常值／非 hex key 不出目錄／不可讀／不可寫 五條 |
| 6 | backoff 只在請求時回 nil，到期無人重試，placeholder 永久 | 明定重試觸發＝下一次 window／explicit；`onStored` → VM `artworkRevision` → 可見項重讀 |
| 8 | 空 persistentID 固定 hash 成同一檔，互相覆寫 | service 與 disk cache 入口拒絕空 ID |
| 9 | `prefetchKeepsAEInFlightAtMostOne` 不能證明 monitor 插隊 | 加 FIFO 模型替身 `SerialAEQueueMusicClient` 與整合測試；V6 措辭收窄 |
| 10 | 串鏈 Task 會送出一串過時 `prefetch` 呼叫 | generation 門：過時命令在呼叫 provider 前退出 |

### 修改採納（4 條）

| # | Codex 主張 | 我方修改 |
|---|---|---|
| 1 | 單槽不能推出 monitor deadline；需 executor 級優先級 | **承諾收窄採納**：改為「artwork 對 monitor 等待的貢獻 ≤ 1 call」，並明列 Editor／Batch 排隊與 `currentTrack()` 無 timeout 為 P1 既有邊界。**executor 優先級駁回**：同步 AE 不可搶佔 → 任何 executor 方案的最佳界同為「等完當前一張」，單槽已達此界，改共用關鍵路徑零增益（見 §3.3） |
| 4 | metadata 損毀清空目錄＝不可逆資料損失，應 quarantine | **分類採納**：I/O 讀取錯誤 ≠ 內容損毀——前者降級不刪檔。**quarantine 駁回**：快取是可再生資料，無法驗證的 blob 對使用者零價值，quarantine 只換來磁碟占用與一套清理策略 |
| 7 | `2^(count-1)` 溢位；無 jitter | **clamp 採納**（count 飽和至 7，補極大 count 測試）。**jitter 駁回**：單槽串行下同時到期只是排隊，不存在湧入 |
| 11 | 同步 `stop()` 發 `flush()` 無法保證落盤 | **採納問題、換解法**：去掉 stop 耦合，改為 access 更新累積 16 次即落盤（有界失真、無生命週期依賴） |

### 部分駁回（1 條）

| # | Codex 主張 | 裁決 |
|---|---|---|
| 12 | 過度設計；應分段交付；executor priority 比 service 側模擬更簡單 | 分段交付**已是計劃**（P2-1 無預取先完成）。executor priority **駁回**，理由同 #1。其餘組件（metadata、LRU、backoff、取消）均直接對應 §5 已定稿的 DoD，無可刪項 |

## 附錄：Codex 複審裁決（Round 2，2026-08-23）

回餵四項駁回理由後：

| # | Codex 回覆 | 裁決 |
|---|---|---|
| 1／12 executor 優先級 | **接受駁回，不重提**。認可「不可搶佔 ＋ 單槽 ⇒ executor 優先級無額外界」，要求明列四個前提（單一 service 實例、單槽、不可搶佔、共用 FIFO executor） | **我方勝**；前提已寫入 §3.3 |
| 4 quarantine | **接受駁回**；但指出「清空目錄」在 `directory` 非專用時會誤刪外部檔案 | **我方勝**；清除範圍收緊為三類快取格式檔（§3.2），補測試 `corruptMetadataLeavesForeignFilesAlone` |
| 7 jitter | **重提，但降為壅塞控制而非正確性**：「不存在湧入」應改為「不存在並行湧入，仍可能有串行 backlog」；建議明示為非目標或加 jitter | **Codex 措辭勝、我方結論維持**：採納措辭，並補上 backlog 上界（window ≤ 10）與「backlog 不改變 monitor 貢獻 ≤ 1 call」的論證；jitter 列為明示非目標 |
| 11 閾值落盤 | 方向正確；要求補 dirty 保留、寫入失敗的記憶體／磁碟狀態、load 前 access | **採納**，§3.2 補齊 |

修訂後新設計的 4 點意見，**全部採納**：

| 意見 | 處置 |
|---|---|
| `active: String?` 找不回 continuation，無法支援「active 共享」 | `active: Entry?`；completion 先 `takeWaiters()` 再清 active 再 resume；兩類各自 FIFO |
| waiter 取消 vs 註冊 vs 完成三者競態、double-resume | token 化 waiter；`cancelWaiter` 只在 token 仍在場時移除並 resume；resume 只有「移除者」一條路徑 |
| drain 測試不足 | 補 `prefetchReplacementKeepsActiveEntry`；「排空瞬間 enqueue 不丟失」由 `drainTask = nil` 與最後 `popNext` 同一同步段保證，`drainRestartsAfterQueueDrains` 覆蓋 |
| 全域 `artworkRevision` 讓所有可見項重跑；callback 跨 actor 未明定；舊專輯殘留通知 | per-ID revision；`Task { @MainActor }` 跳轉；不在 `items` 的 ID 不記錄 |

有輸有贏（R1：7 採納／4 修改／1 部分駁回；R2：3 駁回成立／1 措辭採納／4 新意見採納）符合裁決有效性判準。

---

## 附錄：Phase 3 simcodex 裁決記錄（2026-08-23，3 輪 + 收斂複審）

記在此處是為了**防輪回**：後續評審者若重提以下條目，先看這裡。

### Round 1

**codex review：1 條，我方上調嚴重度 P2 → P1**

| 主張 | 裁決 |
|---|---|
| `reconcileWithFileSystem` 的 `contentsOfDirectory` 失敗時回 `[]`，會被當成「目錄是空的」→ 刪光 metadata entry → 後續 persist 寫回截斷索引 → 快取檔全成永久 orphan | **採納，上調 P1**。理由：它與 `readMetadata` 已實作的「I/O 讀取錯誤 ≠ 內容損毀，降級不刪」**同一條原則**，只是在相鄰函式漏了。不是效能建議，是使用者資料被清空。修法：列目錄失敗 → `isDegraded = true` 並直接返回。新增 `unreadableDirectoryDegradesWithoutDiscardingEntries` |

**simplify 四視角（reuse／simplification／efficiency／altitude 並行）去重後 12 條**

採納 8 條：
- `[weak self]` 未傳遞進巢狀 closure（外層解出的 optional 被內層**強**捕獲，外層 `[weak self]` 等於白寫）
- `observeArtworkStores` 吃具體型別 `ArtworkService` → 改吃 `any ArtworkProviding`，`setOnStored` 提升進協議。**關鍵成本**：收窄型別讓 `StubArtworkProvider` 物理上無法傳入，那條 actor→MainActor 橋接便沒有任何測試跑得到
- `Entry.sequence`／`nextSequence`／`takeSequence()` 冗餘（`pending` 只 append／removeAll，本就保序）
- `totalBytes` 改增量計數器（**後於 Round 2 回退，見下**）
- 抽出 `resolveCached` 消除兩處逐字重複
- inline `isCurrentPrefetch`
- VM 檔頭註解過時（仍寫「沒有 VM 層回寫路徑」）
- 測試 setup 樣板抽 `centeredOnT4()`

駁回 4 條：

| 主張 | 裁決理由 |
|---|---|
| `store()` 改批次 persist | 已簽署設計（Codex R1 #11 辯論產物）：`store`／`remove` 必定落盤換取 artwork 檔與索引一致；改批次會讓「檔在、索引沒寫」窗口變大，下次啟動當 orphan 刪掉、白取圖 |
| 「`waitUntil` 全庫零呼叫點」 | **事實錯誤**：`BatchOverlappingLoadTests` 正在用它 |
| 合併 `albumGeneration` 與 `prefetchGeneration` | 前者守衛載入回寫、後者守衛命令派發，語義與生命週期不同（同 M6 P2-2「isolation 不同不該為消重合併」） |
| `onStored` 下沉到 `ArtworkMemoryCache` | 該型別是 NSCache 薄包裝、非 actor；`loadFromDisk` 早退路徑不發通知是正確的（呼叫者直接拿到回傳值）。改為加註釋說明邊界 |
| 延後 `reconcileWithFileSystem` 的逐 entry stat | 提出者自陳「確有正當用途」；延後會讓配額計算基於未驗證的 size，正是要防的 |
| `AsyncStream(bufferingNewest(1))` 取代 generation+chaining | 投機性泛化，提出者自己說「等第二個消費者出現再收斂」 |

### Round 2

**codex review：2 條，第二條我方上調 P2 → P1**

| 主張 | 裁決 |
|---|---|
| [P1] 取消競態：Task 在 continuation 註冊前被取消 → onCancel 找不到 token（no-op）→ continuation 隨後入表卻永不 resume → SwiftUI `.task` 永久掛起 | **採納**。Plan §3.3 原本就寫了要防這個，實作沒做到。修法：註冊時檢查 `Task.isCancelled`，已取消就當場 resume(nil) |
| [P2] temp 清理謂詞 `name.contains(".tmp-")` 過寬，會刪 `important.tmp-notes` | **採納，上調 P1**。與我方在 R1 明訂的「只碰快取自身三類檔案」直接矛盾——同一條原則沒貫徹到 temp 路徑。修法：`isOwnTempFileName` 要求前綴為 64 hex 或 `metadata.json`、後綴為合法 UUID |

**simplify 三視角（simplification／altitude／efficiency）**

**最重要的一條：`runningTotalBytes` 回退——推翻 Round 1 自己的裁決**

Round 1 的 efficiency 視角建議把 `totalBytes` 改成增量計數器（我採納了）；Round 2 的 simplification 視角建議刪掉它改回即時 reduce。兩者立場相反。

**裁決：採納 Round 2，回退 Round 1 的改動。** 決定性論證（我方提出，非任一評審者給出）：
`store()` 每次必定呼叫 `persist()`，而 `persist()` 做的是 `JSONEncoder().encode(metadata)`——
**這本身就是對全部 entries 的完整遍歷加序列化，比 200 次整數加總貴幾個數量級**。
O(entries) 已是每次寫入的既定成本，再消除一個更便宜的 O(entries) 收益為零，
代價卻是 5 個手動同步點（其中 `purgeAllCacheFiles` 那個已被 efficiency 視角自己標為
「隱含契約、未來新增呼叫點會靜默脫鉤」）。

**這是我在 Round 1 的裁決失誤**：採納了一個優化，其收益被同一函式裡貴幾個量級的操作完全淹沒，
卻引入了衍生狀態。記錄於此，供後續評審者判斷同類提議。

其餘採納：
- `reconcileWithFileSystem` 的「有 entry 無檔」分支統一改用 `discard(key)`（原本同一函式內對「丟棄 entry」有兩種寫法）
- `load()` 的重複 `schedulePrefetch()`（`centerIfAllowed` 成功時已排過一次）→ 改回傳 Bool
- **`artworkMissedIDs` 整個刪除**：「是否為失敗恢復」的判定移進 `ArtworkService.fetch`——
  它的退避表本就記著誰失敗過，VM 再建一份鏡像狀態只會多出需要人工同步的第二份真相
- `entryCount`／`totalBytes` 補 `isDegraded` 守衛（降級後回報陳舊值等於謊稱快取可用）
- `setOnStored` 的**單一訂閱者**語意文件化（後註冊者覆蓋前者，非多播）
- VM `artworkRevisions` 註解修正：Observation 是屬性粒度，被限縮的是「哪一項的 `.task` 重跑」，不是 body 重評

駁回：拆分 `ArtworkProviding` 成多個小協議（YAGNI，僅一個訂閱者；提出者自己建議「記錄成技術債而非現在動手」）。

### Round 3

**codex review：1 條 P1，切中「一個修復的兩半」**

| 主張 | 裁決 |
|---|---|
| Round 2 修取消競態時只讓 continuation `resume(nil)`，但 entry 已被建立並標為 explicit 入列——沒有等待者卻仍會被 drain 取走打 AE，佔住三方共用的串行佇列 | **採納**。症狀（掛起）消失了，真目標（取消應當取消工作）沒達成。修法要精確：本次**新建**的 entry 移除；由既有預取項**升級**而來的降回預取——不能誤刪別人排的預取。新增 `withdraw(_:wasNewlyCreated:)` 與兩條測試 |

**codex 複審（R3 修完後）：1 條新 P2，我方上調 P1**

| 主張 | 裁決 |
|---|---|
| `data(for:)` 的 `Data(contentsOf:)` 失敗被當成損毀 → `discard` 刪掉本來好好的快取 | **採納，上調 P1**。理由不是單條嚴重，而是這是「I/O 錯誤 ≠ 內容損毀」在**第三處**又漏了（R1 修 `readMetadata`、R2 修列目錄失敗）。同一原則靠逐處手寫、缺結構性保證。修法：抽 `readFile(_:expectedSize:)` 把三態（`.bytes`／`.invalid`／`.unreadable`）收攏成單一 helper，讓原則只寫一次 |

**simplify 兩視角**

altitude 三條全採納：
- 檔名策略分居兩處（驗證側在 Codable 模型、產生側在 cache）→ 三面收攏進 `ArtworkDiskCacheMetadata`，cache 轉發
- `hasRecord` →（跑 AE）→ `clear` 這個 check-then-clear 序列沒被型別強制 → 收攏成 `backoff.recordSuccess(_:) -> Bool` 原子操作
- `AppModel` 註解標錯驗收條目（標 H-06，但退避恢復通知屬 H-07 的容錯語義）

altitude 同時確認 `isDegraded` 已貫徹全部六個公開入口。

simplification 兩條全採納：
- `totalBytesUnchecked` 的「避免重入 `ensureLoaded`」理由不成立（`didLoad` 旗標保護，重複呼叫是免費 no-op）→ 砍掉
- `ArtworkService` 的 `Logger` 是零呼叫點的僵屍宣告 → 連同 `import OSLog` 刪除

### 收斂

最終 codex review：**「No definite, actionable bugs were identified in the staged, unstaged, or untracked changes.」**
達成 simcodex early-exit 條件。

有輸有贏（三輪合計：codex 5 條全採納且 3 條由我方上調嚴重度；simplify 17 條採納、7 條駁回；
其中一條由我方**推翻自己上一輪的裁決**）符合裁決有效性判準。
