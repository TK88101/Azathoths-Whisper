# 修 `anUnchangedOrIdenticalRecheckDoesNotFetchDetails` 不穩定——計劃 v3（已實作；Codex R1–R3 收斂）

分支 `fix/history-recheck-flaky`（自 main 558aed4）。模式：normal。

## 0. 複述
- 目標：找出 `LyricsFlowHistoryRecheckTests.anUnchangedOrIdenticalRecheckDoesNotFetchDetails` 時紅時綠的根因並修掉。
- 完成標準：單獨跑 20 次全綠；全量不新增紅燈（基線＝`CoverFlowStripRenderGeometry` 7 斷言紅）；根因與證據記在本檔。
- 非目標：不改產品行為、不改重讀時點表、不動其他測試的斷言、不跳過／放寬任何斷言。

## 1. 根因

### 1.1 已核事實
- F1 基線重現（main 558aed4，孤立跑 6 次）：5 紅 1 綠，全部紅在 `:214` `trackDetailsRequests.count == before + 1`。
- F2 診斷（暫時在斷言前記錄數值，再多讓 4000 輪後重讀；8 次）：

  | 次數 | 斷言當下 count | 斷言當下左鄰 | 稍後 count | 稍後左鄰 |
  |---|---|---|---|---|
  | 6 次 | 3（＝before） | `q:0:10`（暫定卡還在） | 4 | `h:…6E#0` |
  | 2 次 | 4（＝before+1） | `h:…6E#0` | 4 | `h:…6E#0` |

  → 產品最終一律「移除暫定卡＋恰好多問一次」；從未出現 +2。紅燈＝斷言跑在「放棄」那步落地之前。
- F3 程式結構（`LyricsFlowModel.swift`）：放棄那步是 `historyRecheckTask` 在 `await self.workTask?.value` **之後**才 `enqueue { dropPendingPlayed }`（:385–393）。`settleForTesting()`（:245）只追 `workTask` 與 `detailsTask`，不知道 `historyRecheckTask` 還有尾巴要排。
- F4 測試 helper `releaseNextRecheck`（測試檔 :76）：`releaseNext()` → `settle(200)`（固定 200 次 yield）→ `settleForTesting()`。放行後追趕 task 要經 clock actor → MainActor → `QueueFileSource` actor（真的 stat／讀檔）→ MainActor 才排得到放棄工作；固定 200 次 yield 與真實檔案 IO 之間沒有同步關係。

### 1.2 推理
- 測試與追趕 task 同時在等同一個 `workTask`（重讀那步）。它完成時兩邊的續體都排上 MainActor，先後不定：測試先醒 → `settleForTesting` 看到 `workTask` 沒變就返回 → 斷言時放棄工作尚未排入（F2 的 6 次）；追趕 task 先醒 → 放棄工作已排入 → 綠（F2 的 2 次）。另一條路：200 次 yield 內連重讀都還沒排上，結果相同。
- 結論：本次不穩定斷言的**直接根因是測試同步缺口**（等的對象不含追趕 task 的尾巴）。產品端「7 秒到期」與「移除暫定卡」之間隔著一個 task 邊界，期間的新換歌／停止輪詢由世代守衛擋下（既有測試 `aStaleRecheckThatAlreadyWokeCannotPublish`、`aNewChangeRestartsTheRecheck`、`noRecheckAfterStopPolling`）；本次未發現產品端錯誤結果（F2：最終狀態 8/8 正確），也不宣稱已窮舉該空窗的所有交錯——那不在本次範圍。
- 同一個 helper 的其他呼叫端有同型的潛在賭注（例如 `recheckSleepsTheGapsBetweenOffsetsAndGivesUp` 放棄後斷言左側）；目前未觀察到紅，屬推測風險，隨 helper 一起收斂。

## 2. 設計
單一語義「追趕的這一步做完了」只留一處定義（helper）：放行後，這一步做完的訊號只有兩種——**追趕再度入睡**（時鐘多一筆 sleep 請求）或**追趕 task 結束**（追上／作廢／放棄）。

1. 產品檔加一個唯讀測試縫（`#if DEBUG`，與既有 `settleForTesting` 並列，不改行為）：
   ```swift
   #if DEBUG
   /// 測試用：目前的履歴追趕 task。只供測試判定「這一步做完了」（再度入睡或結束），不得用於產品邏輯
   var historyRecheckTaskForTesting: Task<Void, Never>? { historyRecheckTask }
   #endif
   ```
2. `releaseNextRecheck` 改為條件等待，取代 `settle(200)`。前置條件（寫進註解）：`recheckClock` 是追趕專用的時鐘，且同時只有一個活著的追趕 task（舊世代已取消，其 sleep 會丟出、不再請求）。
   ```swift
   let clock = gated(h)
   await waitFor { await clock.pendingCount >= 1 }          // 濾掉已取消者（不用 waitUntilPending：它數的是含取消者的 sleepers）
   let asked = await clock.requested.count
   let task = h.model.historyRecheckTaskForTesting
   let finished = OSAllocatedUnfairLock(initialState: false)
   await clock.releaseNext()
   Task { await task?.value; finished.withLock { $0 = true } }
   let stepDone: @Sendable () async -> Bool = {
       if finished.withLock({ $0 }) { return true }
       return await clock.requested.count > asked
   }
   await waitFor(stepDone)
   #expect(await stepDone(), "追趕這一步沒做完（既沒再入睡也沒結束）")   // 等不到就明確紅，不靜默繼續
   await h.model.settleForTesting()
   ```
   - 結束路徑：放棄工作是 task 的最後一個同步動作，旗標成立 ⇒ task 已結束 ⇒ 放棄工作已在工作鏈上 → `settleForTesting` 等到 `dropPendingPlayed` → `publish` 同步設好 `detailsTask` → 迴圈再等詳情。
   - 再入睡路徑：下一次 sleep 只在這一步的讀檔與 guard 都做完後才請求。
   - 不直接 `await task.value`：非結束步會等到測試自己還沒放行的時鐘而掛住。
   - `settleForTesting` 照舊無條件呼叫：工作鏈只等檔案 IO，不等任何閘門時鐘，與修改前相同。
3. 移除診斷碼；`:214` 斷言與其他斷言原文不動。
4. 不採用的方案：只在這一條測試加等待（helper 的賭注留著）；加大 `settle` 次數（仍是賭）；改產品把放棄併進同一個工作（改行為，非目標）。

## 3. 任務（各帶 DoD）
- T1 產品縫：`LyricsFlowModel` 加 `historyRecheckTaskForTesting`。DoD：編譯過，無行為變動。
- T2 helper 改條件等待＋移除診斷。DoD：該測試孤立 20/20 綠；整個 suite 孤立 5/5 綠。
- T3 全量單元測試。DoD：僅基線 7 斷言紅。
- T4 閘門：`no_playback_gate.sh`、Python 測試、coverage_gate（傳單元測試的 xcresult）。DoD：全過。
- T5 回填本檔 §5。

## 4. 影響面與風險
- 檔案：`Features/LyricsFlow/LyricsFlowModel.swift`（+2 行，唯讀存取）、`Tests/Features/LyricsFlow/LyricsFlowHistoryRecheckTests.swift`、本計劃。不動 ACCEPTANCE（無可觀察行為變化）。
- 風險：`waitFor` 預設 20000 輪上限仍是有界等待；若負載極端下不夠，表現是斷言紅（不會掛住）。回退：還原兩個檔。
- `feature/lyrics-fx` 上同一測試 6/6 紅（A1 §8.2）：修復併回 main 後由該分支合併取得，屆時在該分支重驗。

## 5. 結果（2026-10-04）
| 項目 | 結果 |
|---|---|
| 修復前（main 558aed4，孤立） | 6 次：5 紅 1 綠（§1.1 F1） |
| 修復後，該測試孤立 | **20/20 綠** |
| 修復後，整個 suite 孤立（16 tests） | 5/5 綠 |
| 全量單元測試（skip 已熔斷的 `overlappingLoadSuspendsPollingUntilLastCompletes()`） | 827 tests／86 suites，**僅基線 `CoverFlowStripRenderGeometry` 7 斷言紅** |
| `no_playback_gate.sh` | exit 0 |
| `Scripts` Python 測試 | OK |
| `coverage_gate.sh`（傳入單元測試 xcresult） | Services+Infra 95.3%（門檻 80%），豁免 378／400 行 |

改動：`LyricsFlowModel.swift` +5 行（`#if DEBUG` 唯讀測試縫）；`LyricsFlowHistoryRecheckTests.swift` helper 改條件等待、`import os`；斷言原文未動。

Phase 3 `/simcodex`（14:15，1 輪提前結束）：simplify 四角度 0 個 P0／P1；`codex review --uncommitted`：「No actionable defects」；無安全敏感改動，未派 security-reviewer；本輪無修改，驗證沿用上表（同一份程式碼）。
延後的 P2：helper 的等待 Task 不被 await（測試結束可能殘留一個掛著的等待者，量小）；`stepDone` 在 `waitFor` 後再求值一次；helper 註解偏長；`#if DEBUG` 與既有 `settleForTesting` 不一致（新縫較嚴，保留）；`aStaleRecheckThatAlreadyWokeCannotPublish` 同型的固定 `settle(200)` 賭注，且是負向斷言（可能空過）。

待使用者決定：
- P2（待使用者決定）：「放棄尾端」空窗的交錯回歸測試——不加產品縫寫不出確定性測試（Codex R3 同意），是否接受為此加產品測試縫交使用者決定，見 A.3。

## 附錄 A　Codex 評審記錄

### A.1 R1（gpt-5.6-terra，medium；2026-10-04）
| # | Codex 意見 | 裁決 | 理由 |
|---|---|---|---|
| 1 高 | `waitFor` 逾時靜默返回，之後 `settleForTesting` 無期限 | 部分採納 | 加 `#expect(stepDone)` 讓逾時明確紅。「失敗就別進 `settleForTesting`」駁回：工作鏈只等檔案 IO、不等閘門時鐘，且修改前就無條件呼叫，無新增掛住路徑 |
| 2 中 | `waitUntilPending` 數的是含已取消者的 `sleepers` | 採納 | helper 改等 `pendingCount >= 1`；不改共用的 `GatedPollClock.waitUntilPending`（其他 suite 在用，超出範圍） |
| 3 中 | `requested.count > asked` 沒綁定到目標 task | 修改 | 不加 token 機制（過度設計）：harness 的 `recheckClock` 只有追趕在用，舊世代被取消後 sleep 丟出即返回、不會再請求。前置條件寫進 helper 註解 |
| 4 中 | `Flag` 的隔離沒定義 | 採納 | 用既有慣例的 `OSAllocatedUnfairLock<Bool>`（`GatedPollClock` 已用），不新增型別 |
| 5 中 | 「產品端無可觀察差異」說太滿 | 採納措辭 | §1.2 改寫；另補交錯測試＝駁回（非目標，既有三條世代守衛測試已涵蓋已知競態） |
| 6 低 | 測試縫暴露 `Task` | 部分採納 | 包 `#if DEBUG`＋註解限制用途；語義層 hook 需改寫追趕 task 的多個返回路徑，動到產品結構，駁回 |
| 7 低 | 不變量寫成註解 | 採納 | — |
| 8 低 | 補 helper 層級測試 | 駁回 | suite 內既有測試已分別走「結束」與「再入睡」兩支；逾時由 #1 的 `#expect` 暴露 |

### A.2 R2（2026-10-04）
| # | Codex R2 | 處置 |
|---|---|---|
| 1 後半 | 同意我方 | 結案 |
| 3 | 部分不同意：`GatedPollClock.sleep` 先 `requested.append` 再檢查取消，舊 task 若在 guard 後、進 sleep 前被取消，仍會多一筆請求 | **Codex 勝（措辭）**：註解的前置條件改成「先前被取消的追趕在取消當下已停在時鐘裡」；現有呼叫端都符合（換歌前都先等它入睡），不加 token 機制 |
| 5 後半 | 仍不同意：既有三條沒測到「最後一次 `workTask` 返回後、排入 `dropPendingPlayed` 前」的空窗 | **未決**。我方反證：`:388` guard 到 `:393` enqueue 之間無 suspension point，空窗只在兩個 MainActor 續體的排程先後，測試無法控制（正是本次 flaky 的成因），不加產品縫寫不出確定性測試；R3 見 A.3 |
| 6 後半、8 | 同意我方 | 結案 |
| 新 | 測試檔缺 `import os` | 採納 |

### A.3 R3（2026-10-04 14:12，額度恢復後重送）
- #5 後半：Codex「給不出；同意駁回」——`await workTask?.value` 返回到 `enqueue(dropPendingPlayed)` 之間在 MainActor 上無 suspension、無可控切點，測試只能重現賭注。換歌發生在 enqueue 之後的 generation guard 可確定性補測，但屬擴大範圍。→ **我方勝，列 P2**：是否接受產品測試縫以補這條交錯測試，交使用者決定。
