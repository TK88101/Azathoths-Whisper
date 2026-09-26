# Cover Flow 隨 Music 切曲自動滑動（帶動畫）—— 需求記錄與實施計劃（v0，待審閱）

- 日期：2026-09-26
- 基線：`origin/main` `98af41f`（v2.0.1）
- 分支：`feat/lyrics-notification`——使用者 2026-09-26 指定與「歌詞寫入成功的系統通知」（`2026-09-26-lyrics-notification.md`）**同一次迭代**
- 狀態：**需求已記錄，設計為草案；未經 Codex 評審；未實作。** 使用者指示本 session 只記錄、不動手。
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

## 3. 設計草案（待 Codex 評審與使用者拍板）

- **3.1 舊中心留在牌組（對應事實 7）**：真實換歌當下，若左側來源是 History.dat 且其最新一筆不是剛播完那首，則把剛播完的那首以觀察歷史卡（`o:<pid>#<場次>`，`listening` 已在事件當下記錄）補在左側末端；History.dat 讀到後由 `h:A#0` 取代（同位置換身分＝「正中不變、兩側變動」路徑，不帶動畫，`CoverFlowDeckSideChangeTests` 已覆蓋）。改在 `DeckSnapshot.build`（純函式），去重規則沿用（兩側與中心同 ID 剔兩側；左側與中心不以 persistentID 互相去重）。
  備案：讓 `q:A` 以 `side: .played` 留在左側直到 History 追上——ID 完全不變、動畫最乾淨，但要修 AC8「`q:` 只供中心與右側」的規格。
- **3.2 動畫觸發點**：只在 `apply(_:isRealChange: true)` 且舊中心與新中心都在新牌組內時走動畫路徑；其餘維持 direct。兩個實作方向待 spike（§4 S7）：
  - A：VM 內 `withAnimation(slide) { centerID = target }`，並讓 `CoverFlowStrip` 的 `onChange(of: items)` → `scrollTo` 在動畫路徑下不打斷動畫（同一 transaction 或跳過）。
  - B：VM 只發「滑到 X」意圖，View 在 `ScrollViewReader` 內 `withAnimation { reader.scrollTo(target, anchor: .center) }`，binding 落定後同步 `centerID`。
  - S5 動畫版 5/6 的那一次失敗要先弄清是動畫與 `scrollTo` 打架，還是換內容時的量測問題。
- **3.3 K5 守衛重做**：`isCenteringProgrammatically` 改為「程式化目標」狀態 `pendingProgrammaticTarget: String?`：binding 回寫 ≠ 目標 → 忽略（不算使用者接管）；＝ 目標 → 清除。落定判定不能用 macOS 15 API（事實 10），候選：目標回寫到達即清除＋逾時保險（動畫時長 × 2）自動清除；使用者在動畫途中真的拖曳的情況列為已知限制或以逾時後的回寫判定。
- **3.4 動畫參數**：曲線沿用升降的 `timingCurve(0.16, 1, 0.3, 1)`；時長初值 0.45s（升降為 0.62s）；實機看手感後拍板。
- **3.5 上一首的兩段過程（事實 8）**：第一段（退回模式）新舊中心是否都在牌組取決於 3.1；第二段「同一首換身分」不帶動畫。要不要在第一段就滑、還是等解析後一次滑，待拍板（§7）。
- **3.6 減少動態效果**：`accessibilityReduceMotion` 由 View 讀取（`LyricsFlowPageView` 已有），傳給 VM 或在 View 層決定是否包 `withAnimation`。

## 4. 測試策略（TDD；紅燈摘要回填本節）

- **S7 spike**（沿用 `Tests/UI/CoverFlowDeckTransitionSpikeTests.swift` 的 `SpikeSession`／`StackReader`，`AZW_SPIKE_S7=1` 才跑）：以真實牌組形狀（舊中心離開／留下兩種）做 animated 換歌 ×10，量：落定命中率、途中 binding 回寫序列、逐幀 `scrollX` 是否單調且至少 N 幀介於起訖之間（證明是平移不是跳）。結果寫進本檔 §8，定出 3.1／3.2 的做法後轉正式測試 `CoverFlowDeckSlideTests`。
- **單元（純函式）**：`DeckSnapshotTests` 新增「換歌當下舊中心留在左側末端」「History 追上後以 `h:` 取代、位置不變」「History 最新一筆已是該曲時不重複補」。
- **單元（VM）**：`CoverFlowViewModelDeckTests` 新增：真實換歌產生動畫居中意圖、同曲重發／清單重寫／首次給牌不產生；動畫途中的中間回寫不設 override；目標回寫清除 pending；逾時清除；`reduceMotion` 下無動畫意圖。
- **整合**：`LyricsFlowModelTests.advancingWithinTheSameQueueMovesTheCentre` 加斷言：落定後 override 仍為 false。
- **E2E（使用者在場）**：`LyricsFlowUITests` 現有 `waitForRaisedAndSettled`（播放卡按鈕出現＝落定）沿用，不斷言動畫時長。

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

## 7. 待拍板

1. 動畫時長與曲線（§3.4）。
2. 上一首第一段（退回模式）就滑，還是等解析後一次滑（§3.5）。
3. 3.1 主案（補 `o:` 卡）還是備案（`q:` 卡留左側、修 AC8 規格）。
4. 與通知功能同一分支合併發版（使用者已指定同一迭代；分支名維持 `feat/lyrics-notification`）——版本號 2.0.2 或 2.1.0 待定。

## 8. 實測記錄（實施中回填）

（空）
