# Cover Flow 隨 Music 切曲自動滑動（帶動畫）—— 需求記錄與實施計劃（v4，評審收斂、§7 已拍板；下一步 S8）

- 日期：2026-09-26
- 基線：`origin/main` `98af41f`（v2.0.1）
- 分支：`feat/lyrics-notification`——使用者 2026-09-26 指定與「歌詞寫入成功的系統通知」（`2026-09-26-lyrics-notification.md`）**同一次迭代**
- 狀態：v3（2026-09-27）：S7 完成（§8.1）；R1→VM 短暫過渡顯示層；R2→精確身分判向、settle 回報契約、邏輯當前曲（§3.7）；R3→三處收緊（A.3）；**Codex 評審收斂；§7 已拍板；S8 否證 VM 兩段觸發（§8.2），下一步 S9：條帶內兩段**；未實作。
- 任務形狀：串行（先 spike 定居中方式，再改 VM／條帶，再驗證），不派多 agent。

## 0. 複述（使用者 2026-09-26 原話要點）

- Cover Flow 升起、正在播的那張在正中時，這首歌播完切到下一首，條帶要**自動滑到**下一張；使用者在 Music 按上一首／下一首也一樣，向左或向右滑。
- 「滑動」是核心：要有動畫的平移感，不是瞬間切換。原話：「它不是那種瞬間切換……我點下一首歌，啪就自動切過去……如果沒有這種滑動的感覺就不對了」「這才是 Cover Flow 最最最核心的東西」。
- 定位：基本功能，必須達到（「這算是基本功能必須要達到的一個點，但現在還沒有」）。仍然**不做播控**：App 只跟隨 Music，不控制 Music（memory `lyrics-tool-not-a-player`）。

目標＝真實換歌後 Cover Flow 以動畫平移到新的當前曲；完成標準＝§5 驗證項；不做＝§2 非目標。

## 1. 已核事實（現況為什麼是瞬間切換）

1. 中心切換走 `CoverFlowViewModel.apply(_:isRealChange:)` → `centerProgrammatically(on:)`：同步改 `centerID`，沒有 `withAnimation`（`AzathothsWhisper/Features/CoverFlow/CoverFlowViewModel.swift:183-187`）。條帶以 `.scrollPosition(id: $centerID, anchor: .center)` 綁定（`CoverFlowStrip.swift:90`），值一變就直接跳到位。
2. 條帶內容一變還會明確 `reader.scrollTo(centerID, anchor: .center)`，註解寫明「不帶動畫」（`CoverFlowStrip.swift:92-98`；2026-09-24 為修「兩側變動時停歪」加的）。
3. 這是有記錄的設計決定 **D6**：「牌組轉場一律在同一次更新內換牌並設 `centerID`、不帶動畫（S5：direct 16/16；兩段式在首次給牌 0/5、動畫在換歌 5/6）」（`docs/plans/2026-09-23-coverflow-queue-drawer.md` D6、§13 S5）。動畫版當時只量「落定後是否在目標卡」，5/6 命中而被放棄；**沒有量過觀感**。
4. 放棄動畫的第二個理由 **K5**：`withAnimation` 捲動途中 `scrollPosition` binding 會回寫中間值，`scrollPositionDidChange` 把它當成使用者拖曳 → `userHasOverriddenAutoCenter = true`（`CoverFlowViewModel.swift:131-142`），破壞 H-05 的自動居中。`isCenteringProgrammatically` 守衛在同一同步段內 set→clear，動畫期間的回寫落在守衛之外（ACCEPTANCE H-05 驗證欄已記載此限制）。
5. 升降動畫刻意只包 `offset`，理由同 K5（`Features/LyricsFlow/LyricsFlowPageView.swift:33-37`）。
6. 卡 ID 規則對平移**部分**準備好了：佇列卡 `q:<epoch>:<itID>` 中心與右側共用，「下一首成為中心時 ID 不變，條帶才能平滑平移（S5）」（`Features/LyricsFlow/DeckSnapshot.swift:19-21`）。所以「新中心」這張卡在換歌前後 ID 穩定。
7. **但「舊中心」在換歌當下會離開牌組**：`DeckSnapshot.build` 的左側只來自 History.dat（`h:` 卡）或觀察歷史（`o:` 卡），不含佇列的前一項（`DeckSnapshot.swift:46-60`）。佇列模式＋History.dat 可讀時，事件當下的牌組是 `[h…, q:B(中心), q:C…]`，剛播完的 `q:A` 消失；等 `readSources` 讀到 History.dat 才以 `h:A#0` 出現在左側（H-02 驗證欄「播完的歌由佇列卡換成履歴卡」）。要有「A 往左滑、B 滑進正中」的觀感，**A 必須在動畫期間留在牌組裡**——這不是只加 `withAnimation` 就能解決的。
8. 上一首：`QueueSession.resolvingCurrent` 真實換歌只接受「上次位置的下一項」，往回跳當下不猜（`currentIndex = nil`、右側 pending），下一次輪詢（≤3s）依唯一性定位（`QueueSession.swift:6-8, 92-99`）。所以「上一首」會先經過退回模式（中心＝`o:` 卡、右側清空），再在下一次輪詢重建為 `q:` 卡；動畫要涵蓋這個兩段過程。
9. ACCEPTANCE **H-04** 原文就是「≤3s 自動**平滑**居中」；目前 ✅ 的是邏輯層（中心 ID 移動），觀感標 ⬜。本需求是把「平滑」落實，不新增驗收項。
10. 部署目標 macOS 14（`project.yml`）；`onScrollPhaseChange` 為 macOS 15+，不能靠它判定捲動落定。
11. 條帶已是 `HStack`（至多 21 張，全數具現，`CoverFlowStrip.swift:55-57`），動畫平移不受 LazyHStack 估算位置影響。

**推測（未核）**：使用者說「完全沒反應」，可能是同專輯連播時前後兩張封面相同，瞬間跳轉在畫面上不可辨；加動畫後即使封面相同也看得到平移。V4 專門驗這個情況。若換曲後中心標籤／軌號徽章也不變，則另有 bug，另立項。

## 2. 目標與非目標

目標：
- 真實換歌（persistentID 變）→ 條帶以動畫平移到新中心。下一首＝向左滑一張；上一首＝向右滑一張；方向由新舊中心在新牌組中的相對位置決定，不另立規則。
- 使用者手動滑走後（H-05）真實換歌一樣以動畫拉回，之後不搶控制。
- 系統「減少動態效果」（`accessibilityReduceMotion`）→ 維持瞬間切換。
- 不影響 AC3／H-14 可點判定：動畫途中播放卡按鈕不出現，落定後才出現（既有幾何判定已如此）。

非目標：
- 任何播控（不變）。
- 同曲重發、清單重寫（Genius／插歌）、首次給牌、兩側變動而正中不變：維持不帶動畫（它們沒有「從哪滑到哪」的語義；D6 其餘部分不動）。
- 手動拖曳與方向鍵的手感、升降動畫：不改。
- 1.x Python 版：不動。

## 3. 設計（v2，2026-09-27：依 Codex R1 改為 VM 短暫過渡顯示層）

### 3.0 總則
- **canonical 牌組不動**：`DeckSnapshot.build`、AC8 卡 ID 規則、History／觀察歷史語義全部不改（R1-P0-1／P0-2／P2-12）。
- `CoverFlowViewModel` 新增**顯示層**：`displayCards`（條帶實際吃的卡）＝平時等於 `deck.cards`；只在「過渡」期間多一張**暫留卡**。
- 過渡＝真實換歌的一次平移，狀態機：`idle → staged → animating → idle`，帶單調 `transitionGeneration`。

### 3.1 何時進入過渡（全部成立才進，否則維持現行 direct）
1. `apply(_:isRealChange: true)`；未處於 H-05 接管；未開「減少動態效果」（3.6）。
2. 舊中心卡 `old`（`centerID` 在**舊顯示牌組**中的卡）存在，新中心 `target = newDeck.currentCardID` 存在且 ≠ `old.id`。
3. 方向可**證明**（v3，R2-P0-3：不以 persistentID 距離猜）。依序：
   - (i) `target.id` 在舊顯示牌組中 → 比位置（佇列模式下一首：`q:B` 本在 `q:A` 右側）；
   - (ii) `old.id` 在新 canonical 牌組中 → 比位置（觀察模式下一首：`o:A#k` 播完移到左側 ID 不變）；
   - (iii) 由 `LyricsFlowModel`（持有 `QueueSession`）以 `apply` 的顯式參數 `slideHint` 提供，**在 `nowPlaying` 呼叫 `resolvingCurrent` 之前取證**，且同時成立（v4，R3-2）：舊顯示中心卡 ID ＝ `queue.cardID(at: i)`；`snapshot.entries[i].persistentID ＝ old.persistentID`；新曲 persistentID 在同一快照**恰出現一次**且索引＝i−1（上一首）或 i+1（下一首）。任一不符 → 無 hint；
   - 以上皆不成立（非相鄰跳播、重複曲、清單重寫）→ direct。
   下一首＝`old` 暫留新中心**左側**；上一首＝暫留**右側**（R1-P0-3）。

### 3.2 三個階段
- **staged**（同一次 `apply`；v3 另見 §3.7 的單一狀態與顯示牌組純函式）：`deck = newDeck`；`displayCards = newDeck.cards`，若 `old.id` 不在其中，把 `old` 以原 ID 插到 `target` 的正確一側緊鄰處，並從同側最遠端剔一張，保持 ≤ 21 張（R1-P1 上限）；`centerID` **保持 `old.id`**——條帶 `onChange(items)` 的無動畫 `scrollTo` 會把畫面定在 `old`（S7 keepOld／previous 的第一段）。
- **animating**：由第二次更新觸發 `withAnimation(slide) { centerID = target }`。觸發機制不靠 `Task.yield` 猜 runloop（R1-P1）：候選 (a) 條帶在 `onChange(items)` 完成 `scrollTo` 後回呼 VM；(b) `DispatchQueue.main.async`；(c) 固定 16ms——**S8 以 production 路徑量測後擇一**（§4）。
- **settle → idle**：binding 回寫 `target`（v3：經 §3.7 的 raw 回報契約，不被 `id != centerID` 守衛吞掉），或逾時保險（動畫時長 ×2，帶 generation）到期 → `displayCards = deck.cards`（去掉暫留卡；正中不變、只有一側少一張＝既有「兩側變動」路徑，無動畫，`CoverFlowDeckSideChangeTests` 覆蓋）。

### 3.3 過渡期間的其他事件（R1-P0-4／P0-5／P1）
- **非真實 publish**（`readSources` 讀完 History／Queue、同曲重發）：只更新 `deck` 與 `displayCards`（重新套 3.2 的暫留與 ≤21 規則），**不動 `centerID`**。若 canonical `currentCardID` 在過渡中換身分（上一首的 `o:B` 被解析成 `q:B`）→ 結束過渡、以 direct 居中新身分（同一首換身分本來就不帶動畫）。
- **又一次真實換歌**（A→B→C）：遞增 generation、放棄前一次（逾時與回呼以 generation 自行作廢），以**當下的 `centerID`**當作新的 `old`，重新判定 3.1。
- **binding 回寫 ≠ `target`（staged 之後）**＝使用者接管：立即結束過渡、`displayCards = deck.cards`、照 H-05 設 override（使用者停的那張若已不在 canonical，回當前卡）。前提：S8 證實 production 路徑在程式化動畫途中**不**回寫中間值；若 S8 否證，則改為「動畫期間回寫一律視為動畫、使用者真拖曳列為已知限制」並回報使用者拍板，不默默吞掉。
- `isCenteringProgrammatically` 同步守衛保留給 direct 路徑；動畫路徑以「過渡狀態＋target」判定。

### 3.7 v3 補（Codex R2）

- **單一過渡狀態**（R2-P0-4）：`SlideTransition { generation, old: DeckCard, target: String, side: .left/.right, phase: .staged/.animating }`；`displayCards` 一律由純函式 `SlideDisplay.cards(canonical:transition:limit:)` 派生（每次 publish 重算），規則：以 card ID 去重（canonical 已含 `old.id` 則不插）；插入後超過 21 張才剔同側最遠一張；同側無可剔（只剩 target／暫留卡）→ 放棄過渡、direct（R2-P1-8／R2-7）。「History 在過渡內追上」「清單重寫」「≤21 邊界」進純函式測試。
- **raw 回報契約**（R2-P0-1／P0-5）：View 的 binding setter 改呼叫 `scrollPositionDidReport(_ raw: String?)`：過渡中 raw＝target → settle；raw≠target 且 phase＝animating → 使用者接管（結束過渡、照 H-05）；staged 階段**只忽略 raw＝`old.id`**（條帶把畫面定在 old 的回寫；`nil` 亦忽略），其他任何有效卡 ID 一律立即接管、取消過渡（v4，R3-1；S8 加「staged 真拖曳至非 old」子案）；idle → 走既有 `scrollPositionDidChange` 邏輯（不變）。
- **邏輯當前曲**（R2-P0-2；v4 R3-3 定時序）：每次 `apply` **開頭**先存 `previousLogicalCurrentID`、隨即 `logicalCurrentID = newDeck.currentCardID`，再走過渡／direct／H-05 分支；使用者接管只改 `centerID`、**不改** logical 值；新的真實換歌以 `logicalCurrentID` 為 `old`（在 staged 中又換歌時即舊 target B，不是畫面上的 A），先作廢前一 generation。
- **第二段觸發**（R2-P1-4）：`ScrollViewReader.scrollTo` 無完成回呼，(a)(b)(c) 都是時序假設。S8 選定後加「未提交偵測」：第二段開動畫前確認 `old` 已位於正中（條帶回報的置中卡＝`old`）；否則放棄過渡、direct。
- **cards 消費端**（R2-P1-5／P2-6）：`cards` 改回傳 `displayCards`，另設 `canonicalCards`；逐一審：中心標籤、徽章角落、鍵盤步進（顯示層）、把手刻度（顯示層）、`artworkRevisions`／`details` 清理與 `artworkDidStore` 存活判定改以 `displayCards` 為準、settle 後再清；`isPlayingCardCentered`／`currentCardID` 用 canonical。
- **減少動態效果**（R2-P2-10／P1-8）：VM 預設 `prefersReducedMotion = true`（安全側，未同步前不開動畫）；View `onAppear`／`onChange` 寫入實值；過渡中變為 true → 作廢 generation、移除暫留卡、direct。

### 3.4 動畫參數
曲線沿用升降的 `timingCurve(0.16, 1, 0.3, 1)`；時長初值 0.45s（S7 量得約 0.35s 視覺到位）；實機看手感後拍板（§7-1）。

### 3.5 上一首的兩段過程
佇列往回跳當下 `currentIndex = nil`，canonical 為 `[左…, o:B]`；3.1-3 以 persistentID 找到舊顯示牌組左側的 `h:B`／`o:B` → 判為上一首，`old = q:A` 暫留 `o:B` 右側 → 立即向右滑一張。≤3s 後輪詢解析為 `q:B`＝3.3 的換身分 → direct（畫面位置不變）。是否要「第一段就滑」仍待 §7-2。

### 3.6 減少動態效果
View 讀 `accessibilityReduceMotion`，在 `onAppear`／`onChange` 寫入 VM 的 `prefersReducedMotion`（不在 body 內改狀態，R1-P2）；為 true 時 3.1 不成立＝一次 direct 更新，不走兩段。

## 4. 測試策略（TDD；紅燈摘要回填本節）

- **S8 spike（開工前提，production 路徑）**：真實 `CoverFlowView`＋`CoverFlowViewModel` 掛進視窗（沿用 S5／S7 的 `SpikeSession`／`StackReader`），量：①程式化動畫途中 binding 回寫序列（有無非 target 中間值）②第二段觸發 (a)/(b)/(c) 各 ×10 的平移率與落定率 ③過渡中插入一次非真實 publish 是否仍平移。結果回填 §8.2，定 3.2 觸發機制與 3.3 接管判定。
- **單元（VM，`CoverFlowViewModelSlideTests`）**：下一首／上一首的暫留側與位置；≤21 剔最遠；方向判定不了→direct；H-05 接管中→direct；reduce motion→direct；非真實 publish 不動中心、暫留卡保留；換身分→結束過渡；A→B→C（第二次在 staged、animating、idle 三時點）最終中心＝C、無舊 generation 回寫；回寫≠target→接管；回寫＝target→settle；逾時→settle；settle 後 `displayCards == deck.cards`。
- **正式幾何整合測試**（v3，R2 反駁 P2-11 採納）：`CoverFlowSlideGeometryTests`——比照 `CoverFlowDeckSideChangeTests`（正式、進全量、開視窗量幾何），以 production `CoverFlowView`＋VM 驗「下一首／上一首各 3 次：有 ≥3 幀介於起訖、單調、落定對齊、方向正確」；時長上限控制在數秒。
- **S8 矩陣擴充**（R2-P1-9）：觸發 (a)(b)(c) ×20；各含「換歌後立即非真實 publish」「staged 時 A→B→C」「動畫中注入一次非 target 回寫（模擬拖曳）」子案。
- **既有防線**：`CoverFlowDeckSideChangeTests` 5/5、`CoverFlowStripStackingTests`、`DeckSnapshotTests` 不改動即綠（canonical 不變的證據）。
- **整合**：`LyricsFlowModelTests.advancingWithinTheSameQueueMovesTheCentre` 加斷言：落定後 override 仍為 false；新增「換歌後 readSources 在 settle 前 publish」仍落定於新中心。
- **E2E（使用者在場）**：`LyricsFlowUITests` 現有 `waitForRaisedAndSettled` 沿用；V2–V7 實機。

## 5. 驗證項（V）

| # | 項目 | 環境 |
|---|---|---|
| V1 | `xcodebuild test` 全綠（含新測試）；`CoverFlowDeckSideChangeTests` 5/5、`CoverFlowStripStackingTests` 仍綠 | Mac |
| V2 | 循序播放、自然播完 → 條帶向左滑一張、動畫可見；剛播完那張留在左側；中心標籤與軌號徽章換成新曲 | 實機 |
| V3 | Music 按下一首／上一首 → 分別向左／向右滑；上一首最多晚一個輪詢週期（≤3s） | 實機 |
| V4 | 同專輯（封面相同）連播 → 仍看得到平移（對應「完全沒反應」的推測） | 實機 |
| V5 | 手動滑走 → 換歌時以動畫拉回，之後不再被搶（H-05 交互整合，原 ⬜） | 實機 |
| V6 | 系統「減少動態效果」→ 瞬間切換、無動畫 | 實機 |
| V7 | 換到缺詞曲 → 降下露出 Editor 的同時，條帶不因動畫回寫觸發接管；升回後中心正確 | 實機 |

## 6. 影響面、風險與回退

- 影響檔：`Features/LyricsFlow/DeckSnapshot.swift`、`Features/CoverFlow/CoverFlowViewModel.swift`、`Features/CoverFlow/CoverFlowStrip.swift`、（可能）`CoverFlowView.swift`；測試 `Tests/Features/DeckSnapshotTests.swift`、`Tests/Features/CoverFlowViewModelDeckTests.swift`、`Tests/UI/CoverFlowDeckTransitionSpikeTests.swift`。
- R1 動畫與 `scrollTo` 打架 → 瞬移或停歪（回退：關閉動畫路徑＝現狀；`CoverFlowDeckSideChangeTests` 是防線）。
- R2 途中回寫誤判接管（§3.3 守衛重做；`LyricsFlowModelTests` 加斷言）。
- R3 3.1 補卡與 History 去重打架，出現同曲兩張（`DeckSnapshotTests` 釘住）。
- ACCEPTANCE：H-04 驗證欄補「平滑」證據；H-05「交互整合未驗」可能隨 V5 轉 ✅；AC8 卡 ID 規則若採 3.1 備案需修訂並簽字。

## 7. 已拍板（2026-09-27）

1. **動畫時長 0.62s**（與升降同長同曲線 `timingCurve(0.16, 1, 0.3, 1)`）：使用者交由 Jev 判斷，Jev（jev-1.13.0，choice）選 0.62s（0.74；0.45s 0.24；0.35s 0.02）。實機 V2 手感不對再調常數。§3.4 初值 0.45s 作廢。
2. **上一首：能證明時立刻向右滑**（§3.1-3 (iii)；重複曲 direct）——使用者選定。
3. **AC8 暫時例外：同意**——使用者請 Codex 與 Jev 各自判斷、一致即採：Codex 同意（95%）、Jev noul 0.86。實作時修訂 ACCEPTANCE AC8（註明僅 VM 顯示層、≤ 動畫時長×2、原 ID、canonical 不變）並記使用者簽字 2026-09-27。
4. **版本號 2.0.2**（與通知同一次發版）——使用者選定。

## 8. 實測記錄（實施中回填）

### 8.1 S7 spike（2026-09-27，`CoverFlowSlideSpikeS7Tests`，`TEST_RUNNER_AZW_SPIKE_S7=1`）

真實 `CoverFlowStrip`＋21 張純色卡，動畫 `timingCurve(0.16, 1, 0.3, 1)` 0.45s；每組連續換歌 10 次，逐幀（16ms×50）取樣目標卡離正中的距離。

| 牌組形狀 | sameUpdate（同一次更新換牌＋withAnimation 設中心） | splitUpdate（先換牌，16ms 後 withAnimation 設中心） |
|---|---|---|
| keepOld（下一首，舊中心留左側） | 落定 10/10，**平移 0/10** | 落定 10/10，**平移 10/10** |
| dropOld（下一首，舊中心離開牌組） | 落定 10/10，平移 1/10 | 落定 10/10，平移 1/10 |
| previous（上一首，舊中心留右側） | 落定 10/10，平移 0/10 | 落定 10/10，**平移 10/10** |

- 60 次換歌 binding 回寫皆只有 1 次、值＝目標（stray 0/60）；本 harness 下 K5 未重現（VM 層 `scrollPositionDidChange` 的判定仍需在 3.3 以單元測試釘住）。
- splitUpdate 首次樣本（keepOld）：138,110,86,67,52,40,31,24,19,15,11,8,6,5,4,2,2,1,1,1,1,0（≈0.35s 到位、單調減速）。

結論（已核事實，出自上表）：
1. **sameUpdate 不可用**：條帶 `onChange(of: items)` 的無動畫 `scrollTo` 在同一次更新內蓋掉動畫——這是 S5「animated」被放棄的真因（當時只量落定，未量平移）。§3.2 採 **splitUpdate**（換牌與動畫居中分兩次更新）。
2. **舊中心必須留在牌組**：dropOld 兩種觸發都只有 1/10 看得到平移（中心卡被移除時鄰卡直接補位）。§3.1 不是可選優化而是前提；主案（補 `o:` 卡）與備案（`q:` 卡留左側）皆滿足，取捨仍待 §7-3 拍板。
3. 推測（未核）：dropOld 第 1 次的 1/10 是牌組形狀剛由校準狀態轉入時的偶然，不代表可用路徑。

### 8.2 S8 spike（2026-09-27，`CoverFlowSlideSpikeS8Tests`，`TEST_RUNNER_AZW_SPIKE_S8=1`）

production `CoverFlowView`＋`CoverFlowViewModel`（StubArtworkProvider 佔位封面），動畫 0.62s；staged＝apply 一副窗口已移到 target、中心仍為 old 的牌組，再以三種觸發 `withAnimation { centerID = target }`；每組 20 次，逐幀（16ms×60）取樣捲動原點與 VM `centerID`。兩次完整重跑（取樣數每步皆 60，量測有效）：

| 觸發 | next 平移 | previous 平移 | 落定 | 非目標回寫 |
|---|---|---|---|---|
| mainAsync | 14／15 | 17／12 | 19/20（第 1 步為起點未穩） | 0 |
| sleep16 | 15／17 | 12／11 | 19/20 | 0 |
| yield | 14／18 | 11／13 | 19/20 | 0 |

已核事實：
1. **非目標回寫 0/240**：production 路徑下程式化動畫途中 SwiftUI 不回寫中間值 → §3.7「非 target 回寫＝使用者接管」的前提成立。
2. **VM 兩段（splitUpdate）在 production 不可靠**：失敗步的 60 幀全停在終點（staged 的「條帶無動畫退回 old」沒有發生，新卡換入時已在正中＝瞬移），三種觸發皆隨機失敗 10–45%，無一可用。R2-4 的風險屬實；S7 的 10/10 是精簡 harness 的結果，不能外推。
3. 推論（未核）：staged 依賴 `onChange(of: items)` 內的 `reader.scrollTo(old)` 在第二段前生效；VM 端無法觀測它是否已生效。可行方向是把「退回 old → 動畫到 target」兩步都放進**條帶自己**（持有 `ScrollViewReader`，順序由它保證）——待 S9 量測。

## 附錄 A　評審記錄

### A.1 2026-09-27 Codex 評審 R1（v1 全文，gpt-5.6-terra，read-only，對照程式碼）

結論：方向正確，P0×5／P1×4／P2×3，不宜直接實作。要點（裁決待 v2 逐條記錄）：
- P0-1 `DeckSnapshot.build` 拿不到 `listening`（History 可讀時只傳 `.musicHistory`），無法在純函式內補 `o:` 卡（`LyricsFlowModel.swift:98-101,297-302`）。
- P0-2 History 無場次資訊，`h:A#n` 由新往舊動態編號，「同位置換身分」不成立；重播 A→B→A 會誤判。
- P0-3 上一首：舊中心應暫留在新中心**右側**，且佇列往回跳當下 `currentIndex=nil`，牌組無 A。
- P0-4 splitUpdate 兩次更新之間，`readSources` 的 `publish(isRealChange:false)` 可直接居中到目標，吞掉動畫。
- P0-5 3.3「回寫≠目標一律忽略」違反 H-05（使用者動畫途中拖曳）。
- P1：`Task.yield` 不保證 SwiftUI 已提交第一段；A→B→C 連續換歌取消規則；補卡突破 21 張上限；S7 未走 production 的 binding adapter／`scrollPositionDidChange`。
- P2：reduce motion 的責任邊界；驗收只驗落定；**更簡方案**：canonical deck 不動，由 VM 持有短暫的 transition display layer（舊卡以原 ID 暫留在正確一側，動畫完即採 canonical）。
原始輸出：session scratchpad `codex-plan2-r1.txt`（不入庫）。

#### A.1 裁決（v2）

| R1 | 裁決 | 理由／落點 |
|---|---|---|
| P0-1 build 拿不到 listening | 採納 | 改為 VM 過渡顯示層，canonical 不動（§3.0） |
| P0-2 History 無場次、去重不可證 | **部分駁回**：問題成立，但不採「以 History 尾端追加證明後才退休」 | 暫留卡在**動畫落定／逾時**即退休，不依 History；與 History 何時追上無關，去重問題不再出現（§3.2 settle） |
| P0-3 上一首暫留右側 | 採納 | §3.1-3、§3.5 |
| P0-4 兩段之間 publish 吞動畫 | 採納 | 過渡期間非真實 publish 不動中心（§3.3） |
| P0-5 忽略非 target 回寫違反 H-05 | 採納（附條件） | 非 target 回寫＝接管；以 S8 證實前提，否證則回報使用者（§3.3） |
| P1-6 Task.yield 不保證提交 | 採納 | 觸發機制由 S8 以 production 路徑擇一（§3.2、§4） |
| P1-7 A→B→C | 採納 | generation＋以當下 centerID 為新 old（§3.3）；三時點測試（§4） |
| P1-8 ≤21 | 採納 | 同側剔最遠（§3.2） |
| P1-9 S7 未走 production | 採納 | S8（§4） |
| P2-10 reduce motion 邊界 | 採納 | View 在 onAppear／onChange 寫入 VM（§3.6） |
| P2-11 只驗落定 | **部分採納**：方向、暫留側、接管、A→B→C 進 VM 單元測試（阻擋性）；逐幀平移只在 S8 spike 量（環境變數開啟，不進每次全量）——逐幀取樣需開視窗、耗時，放進全量會拖慢並引入時序抖動 | §4 |
| P2-12 更簡方案 | 採納 | 即 v2 主架構 |

### A.2 2026-09-27 Codex R2（v2）與裁決（v3）

R2 接受 P0-1／P0-3／P1-8／P1-9／P2-12；對 P0-2、P1-7、P2-11 的反駁成立，另提 R2-1…R2-9。v3 處置：
| 項 | 裁決 | 落點 |
|---|---|---|
| P0-2 反駁（PID 最近＝猜） | 採納 | §3.1-3：只接受可證明關係；上一首以佇列唯一相鄰證明（iii），否則 direct |
| P1-7 反駁／R2-2（A→B→C 取錯 old） | 採納 | §3.7 `logicalCurrentID` |
| P2-11 反駁（需正式幾何測試） | 採納 | §4 `CoverFlowSlideGeometryTests`（先例：`CoverFlowDeckSideChangeTests`） |
| P0-4 未閉合／R2-7 | 採納 | §3.7 單一狀態＋`SlideDisplay.cards` 純函式 |
| R2-1（target 回寫被守衛吞） | 採納 | §3.7 raw 回報契約 |
| P1-6／R2-4（無完成回呼） | 採納 | §3.7 未提交偵測，失敗即 direct |
| R2-5／R2-6（cards 消費端、details 清理） | 採納 | §3.7 |
| P2-10／R2-8（reduce motion 中途、首次） | 採納 | §3.7 預設安全側 |
| R2-9（S8 矩陣） | 採納 | §4 |
未全數無條件採納的說明：R2-3 建議「沒有精確 ID 即 direct」會使上一首永遠不滑（往回跳當下佇列刻意不解析，解析時只換身分），與需求「上一首向右滑」衝突；故以 (iii) 佇列唯一相鄰證明補足，重複曲仍 direct——**待 R3 覆核**。

### A.3 2026-09-27 Codex R3（v3）與裁決（v4）

R3 無新設計層問題，(iii) 思路成立；三處收緊全採納：R3-1（P0）staged 只忽略 raw＝old.id → §3.7；R3-2（P1）(iii) 三重一致且在 resolvingCurrent 前取證 → §3.1-3；R3-3（P1）logicalCurrentID 於 apply 開頭更新、接管不改 → §3.7。測試補「staged 真拖曳至非 old」「direct 後再換歌」「animating 接管後再換歌」。評審至此收斂（R1→R3），剩 §7 使用者價值判斷。

