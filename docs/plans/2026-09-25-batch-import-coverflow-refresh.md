# Batch 匯入後 Cover Flow 徽章不刷新（使用者 2026-09-25 實機回報）

模式：normal（Phase 0 判定：同步、無外部等待、單一 bug）。任務形狀：串行，不派多 agent。

## 1. 現象與根因

**現象**：Children of Bodom《Halo of Blood》整張缺詞 → Batch「Fetch Missing」→「Import All」→ 提示 All saved，
iTunes 內逐首確認已寫入；回到 Cover Flow，除正中那張外，同專輯各卡仍是 ✗（截圖 2026-09-25 21.43.26／29）。

**根因（已核事實）**：
1. Batch 的兩條寫入路徑直接呼叫 `music.setLyrics`，不通知任何人——`BatchViewModel.importSelected`、`confirmImportAll`
   （`Features/Batch/BatchViewModel.swift`）。組裝根只接了 `editor.onSaved → lyricsFlow.saved`（`App/AppModel.swift:108`），Batch 沒有對應出口。
2. 卡片徽章＝`CoverFlowViewModel.status(for:)`，只看 `details[pid].lyrics`（`Features/CoverFlow/CoverFlowViewModel.swift`）。
   詳情只在 `coverFlow.details[pid] == nil` 時讀（`LyricsFlowModel.fetchDetails`），`CardDetailsReader` 的快取依設計永不重讀
   （D14：「寫入成功後由呼叫端以 `updateLyrics` 更新該卡，不重讀」）。Batch 不是那個「呼叫端」，快取於是永久停在缺詞。
3. 正中那張是 ✓：推測使用者匯入時正在播 01，之後換到 02——換歌事件（`trackChanged`）會重讀當前曲歌詞，
   只有當前曲因此刷新（推理：monitor 只在 signature 變化時送 `trackChanged`，`NowPlayingMonitor.tick`）。

## 2. 目標與非目標

**目標**：Batch 每一筆**成功**寫入（Import Selected／Import All），Cover Flow 對應卡片的徽章立即反映；寫到當前播放曲時，
與 Editor 寫入同規則（有詞＝Cover Flow、寫入後彩帶撒完升回、補讀確認）。

**非目標**（本次不做，見 §8 待拍板）：
- N1 Batch 寫入當前曲後，Editor 歌詞框仍是舊文字（`EditorViewModel.apply` 同 signature 直接 return）——既有行為，另案
- N2 使用者在 Music.app 內手動改詞，Cover Flow 不會知道（D14 設計即不重讀）
- N3 反向：Editor 寫入後，已載入的 Batch 列表不刷新
- N4 Import All 單曲失敗（false／throw）後仍顯示 "All saved." 並放紙花——原版 py:729-736 即如此（單曲失敗只記錄、不中斷、結尾照報），
  屬 1:1 移植的既有行為；本次只保證失敗曲的**徽章不變**，文案不動
- Python 舊版（`lyrics_fetcher.py`）不動

## 3. 設計

### 3.1 Batch：新增寫入成功出口
```swift
/// 每筆寫入成功（setLyrics 回 true）：（寫入目標, 寫入的文字）→ Cover Flow 徽章（2026-09-25 回報）
var onLyricsWritten: ((String, String) -> Void)?
```
- `importSelected`：`didWrite == true` 時回報 `(selectedID, content)`；**在 stale 守衛之前**回報——寫入已發生在檔案裡，
  專輯切走不改變這個事實。註解寫明：callback 是「寫入事實」事件，不受 Batch session 約束（Codex R1-10）
- `confirmImportAll`：`_ = try await music.setLyrics(...)` 改為依回傳值，true 才回報 `(track.persistentID, track.lyrics)`；
  同樣在下一輪 stale 守衛之前
- false／throw 不回報

### 3.2 LyricsFlowModel：新增 `batchSaved(persistentID:text:)`（薄包裝，Codex R1-5）
- 抽出私有 `applyWrittenLyrics(_:for:) -> LyricsStatus`，職責限定為**寫入事實的資料面**：`reloadMarks` → resolve 狀態 →
  非空則清標記（AC5 既有規則）→ `updateCardLyrics`。**不碰 `LyricsFlowState`**
- `saved` ＝ `applyWrittenLyrics` ＋ `dispatch(.writeSucceeded)`（行為不變）
- `batchSaved`：當前曲（非空 ∧ `== state.nowPlayingPersistentID`）→ **直接呼叫既有 `saved`**（升回、forceRefresh 補讀確認、讀回缺詞提示，同一條路）；
  非當前曲 → 只 `applyWrittenLyrics`，**絕不 dispatch、絕不改 `LyricsFlowState`**
- 非當前曲不補讀的理由：reducer 對非當前曲只回 `.forceRefresh`，其存在理由是「Editor 寫入期間 monitor busy、換歌會漏掉」；
  Batch 匯入期間 monitor 不 busy（C-18：只有載入專輯會停輪詢），補讀是純浪費——Import All 11 首＝11 次多餘的 AE 讀取＋11 個同曲 `trackChanged`。
  當前曲仍需補讀：它驗證寫入真的落地，並驅動「讀回仍缺詞」的既有提示（Codex R1-6）

**已考慮的更簡方案（駁回，待 Codex 辯）**：直接 `batch.onLyricsWritten = lyricsFlow.saved`，零新 API。代價即上段的 N 次 forceRefresh。

### 3.3 AppModel 接線
```swift
batch.onLyricsWritten = { [weak self] persistentID, text in
    self?.lyricsFlow.batchSaved(persistentID: persistentID, text: text)
}
```

## 4. 任務清單（TDD：每項先紅後綠）

| # | 任務 | DoD |
|---|---|---|
| T1 | `MockMusicClient` 加逐 ID 的 setLyrics 結果覆寫（部分失敗用） | 既有測試不變綠 |
| T2 | BatchViewModel 單元：Selected 成功回報／false 不報／throw 不報／寫入後專輯切走仍回報；Import All 逐首回報、跳過失敗、順序一致 | 先紅（無此屬性編譯失敗算紅）→ 綠 |
| T3 | LyricsFlowModel 單元：非當前曲 → 卡片 `.present`、無 forceRefresh、畫面不動、無計時；當前缺詞曲 → 彩帶後升回＋補讀；已標記曲 → 標記清除、徽章 ✓；空文字 → 徽章 ✗ 且不升回 | 先紅 → 綠 |
| T4 | AppModel 整合：真實組裝（mock Music），播過 A（缺詞）後換到 B → Batch 載入含 A 的專輯（列表中 A 有詞）→ **經 `model.batch.confirmImportAll()`** → A 卡 `.missing`→`.present`；匯入期間 `nowPlayingCalls` 不增加（非當前曲不補讀）。不得直接呼叫 `batchSaved`（Codex R1-9） | 先紅 → 綠 |
| T3b | 回歸防線：詳情讀取在飛（閘門擋住）時 Batch 寫入 → 放行後該卡不得是寫入前的舊歌詞（`.missing`），`.present` 或 `.unknown` 皆可（Codex R1-8） | 綠（既有 stamp 設計應已滿足；若紅＝R1 比預估嚴重，停下回報） |
| T5a | UITest 組裝：場景 `batchImport`＋逐首初始歌詞 `initialLyrics(at:)`（取代 `scenario == .present` 二元判定）＋此場景 `albumTracks` 回 5 首＋專用 HTTP 替身；組裝測試斷言 5 首 ID／順序／初始歌詞（Codex R1-1、R1-11） | 綠 |
| T5b | DEBUG 卡片徽章探針：卡片加 `accessibilityValue(present/missing/marked/unknown)`，僅 DEBUG；對應純函數單元測試（Codex R1-2） | 綠 |
| T5c | 替身 HTML 以真實 `DarkLyricsParser` 解析：1、4 → `.lyrics`，0、2、3 → `.titleNotFound`（Codex R1-12） | 綠 |
| T5 | E2E：新 UITest（見 §5.3）| 使用者在場取紅 → 修後取綠 |
| T6 | 實作 §3.1–3.3 | T2–T5 全綠 |

## 5. 測試策略

### 5.1 單元／整合（T2–T4），命令同 `2026-09-23-coverflow-queue-drawer.md` §9.3：必帶 flaky skip（帶括號）＋超時上界＋coverage
### 5.2 覆蓋：`BatchViewModel.swift`、`LyricsFlowModel.swift` 逐檔行覆蓋 ≥ 80%（xccov）；`coverage_gate.sh` 綠
### 5.3 E2E（T5）
- 場景 `batchImport`：正在播第 2 首**有詞**（Cover Flow 升起、Editor 不自動抓詞）；1、4 缺詞（✗），0、3 有詞
- `LyricsFlowUITestMusic.albumTracks` 在此場景回 5 首 fixture（其他場景維持 `[]`，不擾動既有 UITests）
- 此場景專用 HTTP 替身：**僅** DarkLyrics 直連 URL（`DarkLyricsSource.directURL(artist:album:)`＝`…/lyrics/azwlyricsflow/lyricsflowfixture.html`）
  回 parser 相容的專輯頁（含 1、4 兩首）；其餘 GET／POST 一律 404。Genius 不會被呼叫：組裝的 token 為空，
  `GeniusSource.fetchLyrics` 在空 token 時直接回錯、不發請求（已核 `GeniusSource.swift:21-23`）
- 流程：升起 → 卡 1（左，`h:<pid1>#0`）與卡 4（右，`q:0:104`）的 value＝`missing` → `nav-batch` → Fetch Missing → 「FETCH COMPLETE.」→
  Import All → 確認 → 「ALL SAVED.」→ `nav-editor` → 兩卡 value＝`present`；卡 0、3 維持 `present`
- **需使用者在場**：本機 `automationmodetool` 恆為 disabled、使用者裁定不永久免認證，XCUITest runner 啟動時的 Automation Mode 授權框
  60 秒無人點即整輪中止（memory `automation-mode-timeout-needs-user-present`）——與 app 是否發 Apple Event 無關。本專案無 CI。
  不鍵入文字，輸入法不影響

## 6. 驗收標準

| AC | 判定 | 方式 |
|---|---|---|
| AC1 | Import All 成功寫入的每首，卡片徽章立即 ✓，不需換歌／重啟 | T3＋T4＋T5 |
| AC2 | Import Selected 同 AC1 | T2＋T3 |
| AC3 | 寫入失敗（false／throw）的曲徽章不變 | T2 |
| AC4 | Batch 寫到當前缺詞曲：**畫面升降與補讀**與 Editor 寫入同規則（Editor 歌詞框文字不在此列，見 N1） | T3 |
| AC5 | 已標記「沒有歌詞」的曲被 Batch 寫入非空 → 標記清除、徽章 ✓ | T3 |
| AC6 | 非當前曲的 Batch 寫入不觸發 forceRefresh、不動畫面 | T3 |
| AC7 | 寫入後專輯切走，已完成的寫入仍回報 | T2 |
| AC8 | 全量單元綠（skip 已知 flaky 一條）；coverage_gate 綠；UITests 回歸集合（Shell＋Batch＋LyricsFlow）不新增紅燈（A-10 已知 flaky 除外）；`no_playback_gate.sh` 綠 | xcodebuild＋腳本 |

## 7. 影響面、風險與回退

**改動檔**：`Features/Batch/BatchViewModel.swift`、`Features/LyricsFlow/LyricsFlowModel.swift`、`App/AppModel.swift`、
`Features/CoverFlow/CoverFlowView.swift`（DEBUG 徽章探針）、`Features/LyricsFlow/LyricsFlowPresentation.swift`（探針值純函數）、`UI/AccessibilityID.swift`、
`App/UITestSupport/{LyricsFlowUITestScenario,LyricsFlowUITestMusic,AppModel+LyricsFlowUITest}.swift`、
`Tests/Support/MockMusicClient.swift`、`Tests/Features/{BatchViewModelTests,AppModelTests}.swift`、
`Tests/Features/LyricsFlow/LyricsFlowModelTests.swift`、`UITests/LyricsFlowUITests.swift`（或新檔）。無 schema、設定、依賴變動。

**風險**：
- R1 詳情讀取在飛時寫入（本次不處理，記為 P2；T3b 為回歸防線）。兩種時序（推測，讀碼推得、未執行）：
  (a) 常見：`reader.updateLyrics` 先於 Music 讀回執行 → stamp 拒收舊值、`details()` 回傳不含該首 → 卡片暫為 `unknown`，下次 publish 補讀
  (b) 罕見：`updateCardLyrics` 經 `enqueue` 排在工作鏈尾（鏈上若有 `readSources` 在 await 檔案讀取），Music 先讀回 →
  舊值以發出時序號入快取、`fetchDetails` 完成時套上 `coverFlow.details`；之後 `updateLyrics` 才更新 reader 快取，
  但 `coverFlow.details` 那份舊值已錯過 `updateCardLyrics` 當下的同步更新 → 該卡維持 ✗ 直到離開牌組再回來。
  窗口需「換歌讓新卡進牌組」∧「該卡恰被 Batch 寫入」∧「工作鏈忙」同時成立；既有 Editor 寫入路徑同樣存在
- R2 當前曲在 Batch 分頁上被寫入 → 升回發生在看不見的層；回到 Editor 分頁即為 Cover Flow——符合「有詞＝Cover Flow」
- R3 E2E 新場景的 HTTP 替身若誤用於既有場景，會讓 `missing` 場景自動抓詞命中 → 以場景分支隔離

**回退**：單一提交，`git revert` 即可；無資料遷移。

## 8. 待使用者拍板
- N1（Batch 寫入當前曲後 Editor 歌詞框不同步）是否併入本次；不併入則收官時列為已知限制（Codex R1-13）

## 附錄 A：評審辯論記錄

### R1（Codex gpt-5.6-terra, medium，13 條）
| # | 嚴重度 | 主張 | 裁決 | 理由 |
|---|---|---|---|---|
| 1 | 高 | `albumTracks` 恆回 `[]`，需列為具體任務＋組裝測試 | 採納 | 原 Plan 只一句帶過；拆為 T5a |
| 2 | 高 | 卡片 label 是 `.combine` 合成，無穩定契約含徽章文字 | 採納 | 已核：現無任何測試以 label 斷言徽章；加 DEBUG value 探針（T5b） |
| 3 | 高 | 假 Music／假 HTTP 不應依賴使用者在場 | 駁回 | 在場需求來自 XCUITest runner 的 Automation Mode 授權（本機恆 disabled、使用者拒絕永久免認證，memory 記錄 2026-09-12 兩次因此中止），與 app 是否發 AE 無關；本專案無 CI |
| 4 | 中 | Import All 部分失敗仍報 All saved | 修改 | 原版 py:729-736 即如此，屬 1:1 移植；不改文案，列 N4 |
| 5 | 中 | `batchSaved` 做薄包裝、helper 職責要定義 | 採納 | §3.2 改寫：helper 只管資料面、當前曲直接委派 `saved` |
| 6 | 中 | 當前曲仍需補讀 | 採納 | 與原設計一致，改寫措辭 |
| 7 | 中 | R1 描述不精確：詳情不存在時只會暫時 unknown | 修改 | 常見時序同意；但工作鏈忙時存在「舊值套上畫面、之後錯過同步更新」的罕見時序（§7 R1(b)），比 Codex 描述嚴重。回餵再辯 |
| 8 | 中 | R1 本次不處理，加回歸測試 | 採納 | T3b |
| 9 | 中 | 整合測試須經 `confirmImportAll`、斷言不補讀 | 採納 | T4 改寫 |
| 10 | 低 | stale 前回報的語義寫進註解 | 採納 | §3.1 |
| 11 | 低 | 場景初始歌詞改逐首函數 | 採納 | T5a |
| 12 | 低 | Stub 要寫明 Genius 404、HTML 需 parser 相容 | 修改 | Genius 在空 token 時不發請求（已核）；其餘 404＋parser 測試 T5c 採納 |
| 13 | 低 | N1 列已知限制、AC4 措辭限縮 | 採納 | AC4 改寫、§8 |

### R2（**降級：未經 Codex 反駁**——2026-09-25 Codex 回 `usage limit`，23:20 才恢復；由主 session 自評）
駁回／修改的 4 條已帶證據送出，但 Codex 未能回覆。主 session 自評維持原裁決：
- #3 維持駁回：在場需求的證據是本機 Automation Mode 設定與 2026-09-12 兩次實測中止，與假 Music 無關
- #4 維持修改：原版 py:729-736 行為，列 N4
- #7 維持修改：R1(b) 時序由讀碼推得（`enqueue` 先 await 前一個 workTask；`updateCardLyrics` 的同步更新只在 `details[id]` 已存在時發生），Plan 已標「推測」；不影響本次設計
- #12 維持修改：`GeniusSource.swift:21-23` 空 token 直接回錯
Phase 3 的 `/simcodex` 若 Codex 已恢復，實作評審照常走 Codex。

**Plan 定稿**（2026-09-25）。N1 預設不併入（非目標），待使用者拍板；核心修復不依賴 N1。

## 9. 實施後多視角評審與 Plan 修正（2026-09-25 23:2x）

評審：workflow `wf_b4e84410-ab1`，4 個評審面向（正確性／測試／慣例／回歸）並行，Opus 5.5；每面向 1 個驗證者串行、在 scratch worktree **實際執行**（改碼突變、臨時測試、對照 main）。

| # | 來源 | 發現 | 驗證 | 裁決 |
|---|---|---|---|---|
| F1 | correctness-C1 | §7 R1(b) 描述錯：真實 client 的 AE 全走同一條序列佇列，「Music 讀回舊值晚到」不可達。**可達的是 reader 快取命中**：X 曾在牌組（reader 快取＝""）→ 離開牌組（`coverFlow.details[X]` 被濾掉）→ 工作鏈上 `readSources` 正 await 時 Batch 寫 X（`updateCardLyrics` 無同步更新、reader 更新排鏈尾）→ `readSources` 讓 X 回牌組 → `fetchDetails` 快取命中、不 await、直接回 "" → ✗，且 `details[X] != nil` 之後不再重讀 | CONFIRMED（臨時測試：寫入後 `missing`，下一輪輪詢仍 `missing`；對照組 `present`；T3b 照綠＝未覆蓋此路） | **採納，本次修**：違反 AC1。Editor 寫入路徑同樣受益 |
| F2 | correctness-C2＋regression-R1 | 當前曲**本已有詞**時，Import All 以同一份詞重寫 → `batchSaved` 走 `saved()` → reducer 排升回，蓋掉使用者手動降下的 Editor；main 上 Batch 從不動畫面 | CONFIRMED（整合測試 HEAD 紅、main 9b0fbc6 綠） | **採納**：見 §9.2 |
| F3 | tests-T1 | T3b 用 `settle(300)`、`!= .missing` 可能空轉 | REFUTED（9000 次探測 0 次滑過；突變 M2 下 T3b 確實轉紅） | 駁回 |
| F4 | tests-T2 | 「空文字寫入保留標記」無測試（突變存活全套件）；測試註解「標記不動」不實 | CONFIRMED | 採納：補測試、註解改實 |
| F5 | conventions-C1 | `probeValue` 未包 `#if DEBUG` | 失敗情境 REFUTED（Release `-O` WMO dead-strip，nm 0 符號）；源碼不一致屬實 | 修改：按慣例包 `#if DEBUG`（一致性，不是缺陷） |
| F6 | conventions-C2 | 「是否當前曲」判定在 reducer／`markNoLyrics`／`batchSaved` 三處手寫 | CONFIRMED（突變後 106 條既有測試全綠、漂移可觀察） | 採納：`LyricsFlowState.isCurrent(_:)` 單一定義（memory「同一語義只留一處定義」） |
| F7 | conventions-C3 | `AppModel+LyricsFlowUITest.swift:10`、組裝測試標頭仍寫「HTTP 恆 404」 | CONFIRMED | 採納 |
| F8 | conventions-C4 | `AppModelBatchCoverFlowTests` 複製了 `AppModelTests` 的 fixture | CONFIRMED（兩條測試搬進 `AppModelTests` 照綠） | 採納：併入 `AppModelTests`、刪新檔；§7 改動檔清單更正 |

### 9.1 F1 修法（Codex 複審 R1 後改寫：原「覆蓋層」方案時序不封閉，作廢）
原方案的破口（Codex 高-1，採納）：覆蓋層在 reader 確認後即移除，但一個**已拿到舊快取**的詳情讀取可能晚於移除才回到 MainActor，把舊值蓋回去。

改為「寫入確認（ack）時收口」，全在 MainActor、`LyricsFlowModel` 內，不改 `CardDetailsReader`：
- `updateCardLyrics`：同步更新既有卡片（不變）；記 `latestWrite[id] = serial`（自增序號）；排上工作鏈的 `reader.updateLyrics` 完成後呼叫 `writeAcknowledged(id, serial, lyrics)`
- `writeAcknowledged`：只認該首**最後一筆**寫入（序號不符即返回——同首連寫時舊 ack 不得把舊詞蓋回）→ `detailsGeneration += 1`（作廢所有在飛的詳情讀取：它們可能讀到 ack 前的快取）→ 卡片已有詳情且歌詞不同時，再套一次寫入的歌詞
- 封閉性（以「詳情 task 回到 MainActor 套用的時刻相對於 ack」分類，Codex R2 低-1）：詳情讀取若在 ack **前**套上舊值 → ack 時被重套蓋正；在 ack **後**才回來 → 世代不符被丟棄，該卡暫為 unknown、下次 publish 重讀（此時 reader 快取已更新）；ack **後**才發出的讀取 → 讀到新快取
- 代價：ack 會連帶丟棄同批其他卡的詳情，下次輪詢 publish 補讀（reader 快取命中、不問 Music）
- 當前曲事件（Codex 高-2，R2 部分採納）：當前曲的每一筆 Batch 寫入**都要讀回一次**（見 §9.2 修正）——讀回的 AE 排在寫入之後（單一序列佇列），其事件在 stream 裡排在任何先前讀到的舊事件之後（stream 元素 FIFO），故當前曲最終收斂到新鮮讀取
- **已知限制 K1**（Codex R3 接受為風險取捨）：「讀取早於寫入 X、處理卻晚於寫入」的**換曲事件**恰好把剛寫完的 X 變成當前曲——寫入回報時 X 還不是當前曲、走非當前分支不讀回，之後舊事件把舊詞套上 X。stream 元素 FIFO，但跨 task 的 MainActor 排程**不承諾** FIFO，故此交錯可達；機率低（AE 讀取結束到事件入列是微秒級、寫入 AE 是毫秒級，且須恰逢換曲到被寫入的那首）。封住它要讓 `MusicControlling` 回傳 AE 序號、改 AE client（ScriptingBridge 邊界）與全部替身，代價與本 bug 不成比例。收官時列入遺留清單
- 實作約束（Codex R2）：`writeAcknowledged` 在排上工作鏈的同一個 closure 內、`reader.updateLyrics` 之後直接呼叫，不另開 `Task`、本身不含 `await`
- 測試（Codex R2 中-3：拆開三分法兩側）：(1) F1 原時序（快取命中）→ settle 後不是舊值、`refreshSources()`＋settle 後必 ✓；(2) 舊詳情在 ack **前**套上 → ack 後被重套為 ✓；(3) 舊詳情在 ack **後**才回來 → 被世代丟棄、不得是舊值；(4) 同首連寫兩次 → 最終為第二筆；先紅後綠

### 9.2 F2 修法（Codex 複審 R1 後改寫條件與理由）
- 規則：Batch 寫入當前曲時，**寫入前狀態＝有詞 ∧ 寫入結果＝有詞**（「寫入前狀態」取 `batchSaved` 執行當下的 `LyricsFlowState.status`——`setLyrics` await 期間若有事件改變了狀態，以事件後的狀態為準：那正是 Music 的最新真值；Codex R3 中-1） → 更新資料面（卡片、標記）＋**讀回一次**，**不經狀態機**：不改畫面、不排升回。文字相同與否不影響此規則（Codex 中-4 採納：「必同文」不是程式保證，Import Selected 的 `previewText` 可殘留舊專輯內容）
- 讀回保留（Codex R1 中-5、R2 高-1 採納）：「不改畫面」與「來源確認」拆開——讀回讓當前曲收斂到 Music 的真值（見 §9.1 當前曲事件）；每次匯入至多 1 次額外 AE（只有一首是當前曲）。讀回事件走 `sameTrack`，present→present 不動畫面（AC6）
- present→空文字仍走 `saved()`，讓 `state.status` 跟著變，與卡片一致
- Editor 的 `saved()` 不變（使用者在 Editor 親手寫入＝該升回）
- 測試：present＋手動降下 → 同文寫入／不同文字寫入皆不 dispatch `writeSucceeded`、不排升回、畫面不動，且恰有一次讀回；整合層經 `confirmImportAll`，斷言讀回恰 1 次、最終仍是 Editor。「讀回在寫入之後」由結構保證（讀回只在 `setLyrics` 回傳後的 callback 內請求），不另以序列替身斷言（Codex R3 中-2 修改）

### 9.3 驗收標準增補
| AC | 判定 | 方式 |
|---|---|---|
| AC9 | 當前曲已有詞、使用者手動降下 Editor → Batch Import All 後畫面仍是 Editor、無升回計時；恰讀回一次 | 單元＋整合（經 `confirmImportAll`） |
| AC10 | F1 時序（卡片離開又回到牌組、期間被 Batch 寫入）→ 回牌組後徽章**不得是舊值**（可暫為 unknown）；下一次輪詢（`refreshSources`）後必 ✓ | 單元 |
| AC11 | 已標記「沒有歌詞」的曲被 Batch 寫入空文字 → 標記保留、徽章 — | 單元 |

§7 R1 更正：(a) 成立（暫為 unknown、下次 publish 補讀）；(b) 經 Music 讀回的版本不可達；可達的是 F1 的快取命中版本，本次以 §9.1 修掉。

### 9.4 Plan 修正的 Codex 複審記錄（3 輪，收斂）
| 輪 | Codex 主張 | 裁決 |
|---|---|---|
| R1 高-1 | 覆蓋層在 ack 後移除、在飛舊讀取可晚到蓋回 | 採納：改 ack 收口（§9.1） |
| R1 高-2 | 當前曲事件需走 revision 閘門 | R2 部分採納（當前曲保留讀回）；R3 其餘列 K1，Codex 接受 |
| R1 中-3 | 覆蓋層生命週期 | 隨覆蓋層作廢 |
| R1 中-4 | 「必同文」非程式保證 | 採納：條件改「前後皆有詞」 |
| R1 中-5 | 略過 saved() 同時丟了讀回確認 | 採納：保留讀回、只拆掉畫面轉換 |
| R1 低-6 | 修在 reader 內 | 修改：ack 收口全在 MainActor，reader 不變（更小） |
| R2 低-1 | 三分法以「套用時刻」分類 | 採納（措辭） |
| R2 中-3 | 測試拆開三分法兩側 | 採納（§9.1 測試 (1)–(4)） |
| R2 約束 | ack 在同一 closure、不 await；測試明確 refreshSources | 採納 |
| R3 高-1 | AC10「立即 ✓」與暫態 unknown 衝突 | 採納：AC10 改寫 |
| R3 高-2 | AC9／§9.2 測試仍寫「不補讀」 | 採納：改寫 |
| R3 中-1 | 「寫入前狀態」取樣點未定義 | 採納：取 callback 當下 |
| R3 中-2 | 以序列替身斷言「寫後讀」 | 修改：因果由結構保證，只斷言次數與結果 |
| R3 低 | 「FIFO」措辭易誤讀 | 採納 |

## 10. /simcodex（Phase 3，2026-09-26 00:1x–00:3x）
範圍 `main...HEAD`＋未提交變更；codex 以 `codex review --base main`（R1）／`--uncommitted`（R2、R3）。未另開 worktree：已在 `wip/` 分支、每步 checkpoint，可隨時還原。security-reviewer 未派：無新增認證／外部呼叫／檔案操作面（寫檔仍走既有 `setLyrics`）。

| 輪 | /simplify | codex | verify |
|---|---|---|---|
| R1 | 4 面向（Sonnet 5）：P1×2 已修——UITest 的 value 等待器與狀態欄查詢各有重複副本 → 提到 `AppUITestCase`（`element`／`waitForValue`／`staticText(containing:)`／`containsText`）；P2×6 延後 | 0 條 | UITests 編譯綠；全量單元 644 條綠；coverage 95.5% |
| R2 | P1×1 已修（`ShellUITests.swift:137` 註解仍指向已搬走的 `BatchUITests.containsText`）；P2×1 延後 | 0 條 | UITests 編譯綠 |
| R3 | 本輪只有一行註解，主 session 自審 0 條 | 0 條 | 綠 → 提前結束 |

### 10.1 延後的 P2（不影響行為，另案）
1. `CoverFlowItemContainer.body` 的 DEBUG 探針與徽章各算一次 `status(for:)`（僅 DEBUG）
2. `updateCardLyrics` 與 `writeAcknowledged` 的「有卡就套歌詞」三行同形，可抽 `applyCardLyricsIfPresent`
3. `LyricsFlowUITestMusic.albumTracks` 與 `trackDetails` 各自對應同一組欄位
4. `LyricsBadge.probeValue` 另寫一個四分支 switch，可由 `tone(for:)` 推得
5. `writeSucceeded` 事件帶「來源／是否升回」旗標，讓 reducer 統一決定 Batch 與 Editor 的升回（目前 Batch 的有詞→有詞分支在 Model 內自行 forceRefresh）
6. `LyricsFlowUITests` 另有兩處既有的 inline value 等待，可改用 `waitForValue`

### 10.2 已知限制（收官列入）
- K1（§9.1）：延遲的換曲事件恰把剛寫完的非當前曲變成當前曲時，可能套上舊詞；機率低，封住需 AE 序號，代價不成比例
- N1（§2）：Batch 寫入當前曲後 Editor 歌詞框不同步（使用者未指示併入，按預設不做）
- 既有環境問題（與本次無關）：`CoverFlowStripRenderGeometryTests` 在 main 基線同樣紅；A-10 XCUITest flaky

## 11. 全量測試（Phase 3 第 4 步，2026-09-26，終點閘門）
- 全量單元 647 條：唯一失敗＝`CoverFlowStripRenderGeometry`（7 處；main 9b0fbc6 基線同樣 3 條／7 處紅，與本次無關）
- coverage_gate：Services＋Infra 95.5%；改動檔逐檔：BatchViewModel 98.47%、LyricsFlowModel 95.71%、LyricsFlowReducer 99.15%、LyricsFlowPresentation 100%、AppModel 91.12%、UITestSupport 三檔 96–100%；`CoverFlowView.swift` 為 View 宣告檔（R10），探針邏輯抽為純函數 100%、接縫由 E2E 驗
- no_playback_gate 綠；Scripts 單元 12 條、h02 321 條綠；Release 組態編譯綠
- UITests（使用者在場、ABC 輸入法）：26 條 25 綠；唯一紅＝A-10 `testQuitMenuItemTerminatesApp`（`XCUIApplicationState 3≠1`，既知 XCUITest 問題，AC8 除外）
- E2E 紅綠證據：關閉修復 → 紅於「匯入後：左側那張應已 ✓（實際 value：missing）」；打開修復 → 綠；截圖前後對照（匯入前第 2、5 張 ✗，匯入後全 ✓）
