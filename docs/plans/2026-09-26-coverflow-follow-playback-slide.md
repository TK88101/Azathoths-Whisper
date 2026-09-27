# Cover Flow 隨 Music 切曲自動滑動（帶動畫）—— 需求記錄與實施計劃（v5.3：直接換牌＋條帶內容位移動畫；Codex R4–R7 收斂，待使用者簽字 §9 第 8 點後定稿）

- 日期：2026-09-26
- 基線：`origin/main` `98af41f`（v2.0.1）
- 分支：`feat/lyrics-notification`——使用者 2026-09-26 指定與「歌詞寫入成功的系統通知」（`2026-09-26-lyrics-notification.md`）**同一次迭代**
- 狀態：v3（2026-09-27）：S7 完成（§8.1）；R1→VM 短暫過渡顯示層；R2→精確身分判向、settle 回報契約、邏輯當前曲（§3.7）；R3→三處收緊（A.3）；§7 已拍板（不重議）；S8 否證 VM 兩段觸發（§8.2）；S9 否證條帶內兩段，量得「不動捲動位置＋條帶內容位移動畫」120/120（§8.3）；**v5（2026-09-27）依 S9 重寫 §3／§4／§6、新增 §9 任務清單；v5.1–v5.3 依 Codex R4–R6 修訂（附錄 A.4–A.6），R7 確認三項條件皆已滿足、無新 P0／P1（A.7）；定稿的唯一條件＝使用者簽字 §9 末第 8 點**；未實作。v4 全文見 git `b5f8f23`。
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
- 使用者手動滑走後（H-05）真實換歌照現行行為**直接**拉回（不帶動畫），之後不搶控制。v4 此處寫「以動畫拉回」，與同版 §3.1-1「接管中維持 direct」互相矛盾；v5 依 §8.3 的根因定為 direct——拉回要無動畫改捲動位置，正是會閃的那一類（**需使用者知悉**，見 §9 末）。
- 系統「減少動態效果」（`accessibilityReduceMotion`）→ 維持瞬間切換。
- 不影響 AC3／H-14 可點判定：動畫途中播放卡按鈕不出現，落定後才出現（既有幾何判定已如此）。

非目標：
- 任何播控（不變）。
- 同曲重發、清單重寫（Genius／插歌）、首次給牌、兩側變動而正中不變：維持不帶動畫（它們沒有「從哪滑到哪」的語義；D6 其餘部分不動）。
- 手動拖曳與方向鍵的手感、升降動畫：不改。
- 1.x Python 版：不動。

## 3. 設計（v5，2026-09-27：直接換牌＋條帶內容位移動畫）

### 3.0 總則與 v4→v5 差異

**一句話**：換歌當下照現行 direct 路徑（同一次更新換牌＋`centerID = target`，捲動位置的數值不變）；「滑過去」的觀感由條帶**內容位移**（`.offset`）從「一個卡距」動畫歸零來呈現。

依據＝§8.3：凡是換牌的同一次更新需要無動畫改捲動位置，就有 15–45% 晚一次畫面提交才生效；不改捲動位置就不出錯（事實 5、8）。

| 項目 | v4 | v5 | 理由 |
|---|---|---|---|
| 換歌當下的 `centerID` | 保持 old，動畫後才是 target | **立即＝target**（現行行為） | 捲動位置不必改 |
| 平移的載體 | 捲動位置動畫（兩段） | 條帶內容位移動畫（一段） | §8.3 事實 1、8 |
| raw 回報契約、staged／animating 兩相、動畫途中回寫判定（v4 §3.3、§3.7） | 需要 | **刪除** | 程式化捲動動畫不存在，K5 不成立；binding 回寫只剩使用者拖曳 |
| `logicalCurrentID` | 新增 | **不需要**：`deck.currentCardID` 就是邏輯當前曲 | `centerID` 不再有過渡值 |
| 落定訊號 | binding 回寫 target／逾時 | 動畫完成回呼／逾時 | §8.3 事實 7 |
| 暫留卡、canonical 不動、方向要可證明、減少動態效果、0.62s | — | **沿用** | §7 已拍板；R1–R3 裁決仍成立 |

不變：`DeckSnapshot.build`、AC8 卡 ID 規則、History／觀察歷史語義（R1-P0-1／P0-2／P2-12）。

### 3.1 何時平移（全部成立才平移，否則維持現行 direct）

判定集中在純函式 `CoverFlowSlidePlan.make(...)`（§3.2），VM 只負責呼叫與套用。

1. `apply(_:isRealChange: true)`；`prefersReducedMotion == false`。
2. 舊當前卡 `old`＝套用前 `deck.currentCardID` 在**目前顯示牌組**中的那張，存在；新當前卡 `target = newDeck.currentCardID` 存在且 `target ≠ old.id`。
3. **畫面停在 `old` 上，且沒有進行中的過渡**——三者同時成立（套用前的值）：
   - `isPlayingCardCentered == true`：條帶依幾何回報播放卡在正中（D6 既有；容差 ±0.2 卡寬）。單看 `centerID` 不夠，它在拖曳途中落後於畫面（R4-2）。
   - `centerID == old.id`：單看幾何回報也不夠，容差內不代表捲動原點已在 `old` 的錨點上（R5-2）。
   - `transition == nil`：過渡中又換歌 → direct（R4-6），不承接尚未歸零的位移。
   - 不看 `userHasOverriddenAutoCenter`：使用者滑走又自己滑回播放卡，可以平移。
   - **不處理的邊界（待使用者簽字，§9 末）**：使用者的手指正在拖、位移還在容差內（≤52pt）的那一瞬間換歌——兩個條件都成立，但捲動原點不在錨點上，起滑可能有 ≤52pt 的跳動。判定得出來（`NSScrollView` 的 live-scroll 通知，macOS 14 可用；R6-A2），但判定之後只能改走 direct，畫面是「整張卡距的瞬間跳」，比「≤52pt 的跳＋平移」更差；為此新增一個系統邊界不划算。
4. 方向可**證明**（沿用 v4 §3.1-3，R2-P0-3／R3-2）：
   - (i) `target` 在目前顯示牌組中 → 比位置；
   - (ii) `old.id` 在新 canonical 牌組中 → 比位置；
   - (iii) `slideHint`：由 `QueueSession` 在 `resolvingCurrent` **之前**取證，同時成立才給——`currentIndex = i` 已解析、`queue.cardID(at: i) == old.id`、`entries[i].persistentID == old.persistentID`、新曲 persistentID 在同一快照**恰出現一次**且索引＝`i−1`（上一首）或 `i+1`（下一首）。hint 帶 `targetPersistentID`，`make` 再比對 canonical 的 target 是同一首（R4-5）。
   - 皆不成立（非相鄰跳播、重複曲、清單重寫）→ direct。
5. 過渡顯示牌組建得出來，且滿足**位次條件**（§3.2）。

### 3.2 過渡顯示牌組與位次條件（純函式）

```swift
enum CoverFlowSlidePlan: Equatable {
    case direct
    /// slots：內容位移的卡距數。+1＝下一首（old 在 target 左鄰）；−1＝上一首（old 在右鄰）
    case slide(display: [DeckCard], slots: Int)

    static func make(previousDisplay: [DeckCard], old: DeckCard, canonical: DeckSnapshot,
                     hint: SlideHint?, limit: Int) -> CoverFlowSlidePlan

    /// 過渡中每次 canonical 變動都重算；回 nil＝過渡撐不下去（VM 結束過渡）
    static func display(canonical: DeckSnapshot, transition: SlideTransition, limit: Int) -> [DeckCard]?
}

struct SlideTransition: Equatable {
    let generation: Int
    let old: DeckCard
    let target: String
    let slots: Int
    /// 進入過渡時 target 在顯示牌組中的位次；之後每次重算都必須相同
    let targetIndex: Int
}
```

`make` ＝ 判方向＋`display(...)`＋位次條件；兩者共用同一套建法。

建法（`side`＝old 相對 target 的那一側）：
1. `display = canonical.cards`。
2. `old.id` 已在 `display` → 不動。
3. 否則，若 `display` 中 target 在 `side` 側的**緊鄰卡與 old 同 persistentID**（履歴已追上，`h:A#0` 已在左鄰）→ 以 `old`（原 ID）**原位取代**它。
4. 否則把 `old`（原 ID）插到 target 的 `side` 側緊鄰處；插在左側 → 剔掉最左一張（沒有可剔 → `.direct`）；插在右側且超過 `limit`（21）→ 剔掉最右一張。
5. 檢查，任一不成立 → `.direct`：
   - 卡 ID 唯一；`old` 與 `target` 在 `display` 中相鄰、左右與方向一致；
   - **位次條件**：`display` 中 target 的位次 ＝ `previousDisplay` 中 old 的位次。

位次條件是「捲動位置的數值不必改」的**充分條件**，前提是現行的固定幾何（卡寬、間距固定；邊距只隨視窗寬度變）且視窗寬度不變（R4-4）。過渡中改視窗大小不處理：0.62s 內同時換歌與拖拉視窗邊框屬罕見，結果只是回到現行的修正路徑。不成立的典型情況：左側還在長（履歴不足 10 筆時，canonical 的中心位次每換一首加一）。此時 direct，列為已知限制（§6）。

各模式對照（`window = 10`，左側已滿）：
| 情況 | 換歌前顯示 | canonical | 過渡顯示 | slots |
|---|---|---|---|---|
| 佇列，下一首 | `[h×10, q:A, q:B, …]` | `[h×10, q:B, …]` | `[h×9, q:A, q:B, …]`（規則 4） | +1 |
| 佇列，下一首，履歴已追上 | 同上 | `[h×9, h:A#0, q:B, …]` | `[h×9, q:A, q:B, …]`（規則 3） | +1 |
| 佇列，上一首（hint） | `[h×10, q:A, q:X, …]` | `[h×10, o:B]` | `[h×10, o:B, q:A]`（規則 4） | −1 |
| 退回模式，下一首 | `[o×10, o:A]` | `[o×9, o:A, o:B]` | 同 canonical（規則 2） | +1 |

### 3.3 VM（`CoverFlowViewModel`）

**顯示的權威狀態只有兩個：`deck`（canonical）與 `transition: SlideTransition?`**（R2-P0-4、R4 簡化建議）。`displayCards`、`slide` 都是算出來的，不另存（另有記帳用的 `nextGeneration` 與可取消的逾時 task，不參與顯示）：
- `displayCards`＝`transition` 存在時 `CoverFlowSlidePlan.display(canonical: deck, transition:)`，否則 `deck.cards`。`cards` 改回傳它。
- `slide: CoverFlowSlideRequest?`（`generation`、`slots`）＝由 `transition` 導出；沒有過渡即 `nil`。

不變式：`transition != nil` ⇒ `display(...)` 算得出來。由 `apply` 維護——每次換上新的 canonical 都先驗，算不出來就結束過渡。

另有：
- `prefersReducedMotion = true`（安全側，View 同步前不平移；R2-P2-10）。
- 逾時保險：`clock.schedule(after: 動畫時長×2)`（`PollClock`，`init` 注入、預設 `SystemPollClock()`）。

`apply(_ newDeck:, isRealChange:, slideHint:)`：
1. 先算 `plan`（用套用前的 `deck`、`displayCards`、`isPlayingCardCentered`、`centerID`、`transition`）。
2. `deck = newDeck`。當前卡 ID 變了 → 清掉條帶先前的「播放卡在正中」回報（`centredPlayingCardID`），等新的當前卡自己回報。理由：卡片離開 `.current` 之後不會再回報 false，舊值會殘留；過渡中使用者滑走時，殘留值日後可能與換回來的當前卡 ID 相同而誤判可點（R5-2）。
3. `.slide` → `generation += 1`、設 `transition`、排逾時；其餘照現行：解除 H-05 抑制、`centerProgrammatically(on: target)`。
4. `.direct` → 結束進行中的過渡（`transition = nil`、取消逾時），其餘照現行。
5. `details`／`artworkRevisions` 的清理改以 `displayCards` 的 persistentID 為準（暫留卡的封面與詳情在過渡中不被清掉；R2-5／R2-6）。

過渡期間的事件：
- **非真實 publish**（`readSources` 讀完、同曲重發）：`deck = newDeck`；`display(...)` 算得出來（暫留卡仍相鄰、target 位次不變、當前卡沒換身分）→ 過渡繼續，`generation` 不動；算不出來 → 結束過渡、走現行路徑。
- **又一次真實換歌**：§3.1-3 不成立 → direct（結束過渡、位移歸零）。落定之後的換歌照常判定。
- **使用者拖曳**：binding 回寫走現行 `scrollPositionDidChange`（不改）。過渡照常落定。
- **落定** `slideDidSettle(generation:)`：完成回呼、逾時、條帶的初值補救共用這一個入口，開頭一律 `guard transition?.generation == generation else { return }`，通過後**先**清 `transition`、取消逾時，再做後續——嚴格冪等，遲到或重複的回報都是 no-op（R5-1）。落定後以 canonical 的 `deck.cards` 再清一次 `details`／`artworkRevisions`（暫留卡的資料此時才清）。正中卡位次不變（暫留卡在同側一進一出），不需要改捲動位置（§8.3 事實 4）。落定時 `centerID` 指向的卡若已不在牌組（使用者停在暫留卡上）→ 照現行規則回到當前卡、解除抑制。
- **減少動態效果中途開啟**：結束過渡。

canonical 專用的讀取不變：`isPlayingCardCentered`、`playingCardTitle`、`currentCardID` 仍讀 `deck`。

### 3.4 條帶（`CoverFlowStrip`）

新增參數（皆有預設值，既有呼叫端不必改）：`slide: CoverFlowSlideRequest?`、`slideAnimation: Animation`、`onSlideSettled: (Int) -> Void`。

- 位移量由輸入**同步算出**：`slide` 尚未釋放（`slide.generation != releasedGeneration`）時＝`CoverFlowGeometry.slideOffset(slots:)`（＝slots × 卡距），否則 0。與換牌在同一次更新生效，畫面不動。
- `HStack` 加 `.offset(x: 位移量)`。
- 單一 `onChange(of: 卡 ID 序列＋slide, initial: true)`，指令只在這裡被消費：
  - **初值**：只處理**尚未釋放**的指令（`slide.generation != releasedGeneration`）→ 直接釋放（不帶動畫）並回報落定；這是條帶被重建（`@State` 歸零）的情況（R4-1）。指令已釋放（條帶沒被重建、只是重新出現，動畫正在跑）→ no-op，不回報（R6-A1）。不另掛 `onAppear`：兩個入口會搶同一個指令（R5-1c）。
  - **新指令** → 照現行明確捲回 `centerID`（無動畫）→ `withAnimation(slideAnimation, completionCriteria: .logicallyComplete) { releasedGeneration = generation } completion: { onSlideSettled(generation) }`。
  - 沒有新指令、只有卡 ID 變 → 現行路徑不變。
- 釋放留在條帶（推論，未核）：它要發生在「位移已套用」之後的另一次更新。S7 sameUpdate、S8 證實的是捲動位置的兩段操作在 VM 端不可靠；內容位移的 VM 端釋放沒有量過，已量過且 120/120 的是條帶端。
- `CoverFlowStripCell` 改為 `Animatable`，帶 `shift`（＝位移量）：**只**加進疊放與正中判定的距離；旋轉／縮放（`visualEffect`）不加（§8.3 事實 6：它的幾何本來就含 `.offset`）。

### 3.5 View 與接線

- `CoverFlowView`：把 `model.slide`、動畫、`model.slideDidSettle` 傳給條帶；`accessibilityReduceMotion` 在 `onAppear`／`onChange` 寫進 `model.prefersReducedMotion`（不在 body 內改狀態，R1-P2）。
- `LyricsFlowModel.nowPlaying`：在 `resolvingCurrent` **之前**取 `queue.slideHint(to: track.persistentID)`，經 `publish` 傳給 `coverFlow.apply`。非真實 publish 傳 `nil`。
- `QueueSession.slideHint(to:)`：純函式，回傳 `SlideHint(oldCardID:, oldPersistentID:, targetPersistentID:, direction:)` 或 `nil`。

### 3.6 動畫參數（同一語義只留一處）

`Theme.Motion.layerShift`（`timingCurve(0.16, 1, 0.3, 1, duration: 0.62)`）與 `Theme.Motion.layerShiftDuration`。`LyricsFlowPageView.riseAnimation` 改為引用它（值不變，升降行為不變）。§7-1「與升降同長同曲線」由此保證，不靠兩處各寫一次。

### 3.7 顯示牌組的消費端（逐一審，R2-P1-5）

| 消費端 | 讀哪個 | 過渡中的行為 |
|---|---|---|
| 條帶 `items`、把手刻度、鍵盤步進、預取窗口 | `displayCards` | 含暫留卡 |
| 中心標籤、狀態字 | `displayCards`＋`centerID` | 起滑當下就換成新曲（`centerID` 已是 target） |
| 徽章角落（`LyricsBadge.corner`） | `displayCards`＋`centerID` | 起滑當下以新中心計算：暫留卡與目標卡的徽章角落在起滑瞬間換位（已知外觀細節，V2 目視） |
| 播放卡可點（AC3／H-14） | `deck.currentCardID`＋條帶幾何 | 目標卡滑到正中才可點（疊放與正中判定吃 `shift`） |
| `LyricsFlowModel.publish` 的 `deck != coverFlow.deck` | `deck` | 不受顯示層影響 |

## 4. 測試策略（TDD；紅燈摘要回填本節）

| 測試 | 類型 | 內容 |
|---|---|---|
| `CoverFlowSlidePlanTests`（新） | 單元（純函式） | §3.2 對照表四列；規則 3（同 persistentID 原位取代）；左側無可剔 → direct；位次條件不成立（左側還在長）→ direct；非相鄰 → direct；方向與 hint 矛盾 → direct；hint 的 old 卡 ID／persistentID／targetPersistentID 不符 → direct；卡 ID 重複 → direct；張數 ≤ limit；輸入不被修改。`display(...)`：履歴追上（規則 4 → 規則 3）target 位次不變；左側張數改變 → nil；當前卡換身分 → nil |
| `QueueSessionTests`（增） | 單元 | `slideHint`：唯一相鄰下一首／上一首；新曲重複出現 → nil；非相鄰 → nil；當前位置未解析 → nil；無快照 → nil |
| `CoverFlowViewModelSlideTests`（新） | 單元 | 平移：`centerID` 立即＝target、`slide.generation` 遞增、`slots` 正負、`displayCards` 含暫留卡、H-05 抑制解除；落定（回呼）→ `displayCards == deck.cards`、`slide == nil`、正中卡位次不變；落定（逾時，注入時鐘）；過期 generation 的回呼與逾時不生效；非真實 publish 不動 generation、暫留卡保留；非真實 publish 破壞位次條件 → 結束過渡；當前卡換身分 → 結束過渡；A→B→C：第二次在過渡中 → direct、`slide == nil`、中心＝C；第二次在落定後 → 再平移、generation 加一；條帶未回報播放卡在正中（含回報為 false）→ direct；幾何回報在正中但 `centerID ≠ old.id`（落後）→ direct；`centerID == old.id` 但幾何回報不在正中 → direct；滑走後滑回（兩者皆成立）→ 平移；落定冪等：同一 generation 回報兩次、完成回呼與逾時先後到、過渡已被 direct 結束後舊 generation 才到——都不改變狀態，使用者其後的接管不被推翻；當前卡 ID 改變即清掉舊的「在正中」回報，換回同一張卡 ID 時須重新回報才算；減少動態效果 → direct、中途開啟 → 結束過渡；過渡中使用者拖曳 → 抑制成立、照常落定；落定時 `centerID` 在暫留卡上 → 回當前卡；暫留卡的 `details`／`artworkRevisions` 過渡中保留、落定後清掉；`isPlayingCardCentered`／`playingCardTitle` 讀 canonical。顯示牌組的消費端（§3.7）：過渡中鍵盤步進以含暫留卡的牌組為索引；預取窗口含暫留卡；中心標籤與狀態字是新曲；把手刻度張數＝顯示牌組張數 |
| `CoverFlowGeometryTests`（增） | 單元 | `slideOffset(slots:)`＝slots × 卡距；0 → 0 |
| `LyricsFlowModelTests`（增） | 整合 | `advancingWithinTheSameQueueMovesTheCentre` 加斷言：發出平移指令、落定後抑制仍為 false；往回跳（唯一相鄰）帶 hint、`slots = −1`；往回跳到重複曲 → direct；換歌後 `readSources` 在落定前 publish，落定後中心＝新曲、`displayCards == deck.cards` |
| `CoverFlowSlideGeometryTests`（新，正式、進全量） | 幾何整合 | production `CoverFlowView`＋VM 開視窗：下一首／上一首各 3 次，**每一步都斷言**（R4-3；S9 只印統計、不算回歸證據）。斷言：卡格相位還原的位移有 ≥3 幀介於起訖且單調、總位移＝一個卡距、方向正確；捲動原點全程不變；落定對齊（<1pt）；起滑後第一個取樣 `isPlayingCardCentered == false`、落定後為 true；落定後 `displayCards == deck.cards`。減少動態效果 → 無位移。另三案：過渡中插入一次非真實 publish（履歴追上）→ 仍平移、落定對齊；過渡中又換歌 → 位移歸零、中心＝C、對齊；VM 帶著未落定的指令時才掛載條帶（重建）→ 位移為 0、VM 收到落定；正常起滑不被初值補救切掉（起滑後第一個取樣的位移 > 半個卡距）；動畫中把 hosting view 移出視窗再放回（不重建）→ VM 的過渡不被提前結束，仍由完成回呼或逾時落定。量法沿用 `StackReader`；先空牌掛載再給牌（§8.3 量測起點） |
| 既有防線（不改動即綠） | — | `CoverFlowDeckSideChangeTests` 5/5、`CoverFlowStripStackingTests`、`CoverFlowStripRenderGeometryTests`、`DeckSnapshotTests`、`CoverFlowViewModelDeckTests`、`CoverFlowViewModelPrefetchTests` |
| E2E（使用者在場） | UITest／實機 | `LyricsFlowUITests` 現有流程沿用；V2–V7 |

S9 量測碼（`CoverFlowSlideSpikeS9*.swift`）預設關閉，不是正式測試；實作不從它長出來（spike 用完即棄）。去留待使用者決定（§9 末）。

## 5. 驗證項（V）

| # | 項目 | 環境 |
|---|---|---|
| V1 | `xcodebuild test` 全綠（含新測試）；`CoverFlowDeckSideChangeTests` 5/5、`CoverFlowStripStackingTests` 仍綠 | Mac |
| V2 | 循序播放、自然播完 → 條帶向左滑一張、動畫可見；剛播完那張留在左側；中心標籤與軌號徽章換成新曲 | 實機 |
| V3 | Music 按下一首／上一首 → 分別向左／向右滑；上一首最多晚一個輪詢週期（≤3s） | 實機 |
| V4 | 同專輯（封面相同）連播 → 仍看得到平移（對應「完全沒反應」的推測） | 實機 |
| V5 | 手動滑走 → 換歌時直接拉回（不帶動畫，現行行為），之後不再被搶；滑走後自己滑回當前曲 → 換歌時照常平移（H-05 交互整合，原 ⬜） | 實機 |
| V6 | 系統「減少動態效果」→ 瞬間切換、無動畫 | 實機 |
| V7 | 換到缺詞曲 → 降下露出 Editor 的同時條帶照常平移，不觸發接管；升回後中心正確 | 實機 |
| V8 | 起滑瞬間與落定瞬間沒有「閃一下」（慢動作錄影逐幀看：正中那張不得先跳到別張再回來）；徽章角落換位可接受 | 實機 |

## 6. 影響面、風險與回退

**影響檔**
| 檔案 | 改動 |
|---|---|
| `Features/CoverFlow/CoverFlowSlidePlan.swift`（新） | 純函式：過渡顯示牌組、位次條件、`SlideHint`、`CoverFlowSlideRequest` |
| `Features/CoverFlow/CoverFlowViewModel.swift` | 顯示層、過渡狀態、落定、逾時、減少動態效果；`init` 多一個有預設值的 `clock` |
| `Features/CoverFlow/CoverFlowStrip.swift` | 平移指令、內容位移、`Animatable` 卡片 |
| `Features/CoverFlow/CoverFlowGeometry.swift` | `slideOffset(slots:)` |
| `Features/CoverFlow/CoverFlowView.swift` | 接線、減少動態效果同步 |
| `Features/LyricsFlow/QueueSession.swift` | `slideHint(to:)` |
| `Features/LyricsFlow/LyricsFlowModel.swift` | 取 hint、傳給 `apply` |
| `Features/LyricsFlow/LyricsFlowPageView.swift` | `riseAnimation` 改引用 `Theme.Motion`（值不變） |
| `UI/Theme.swift` | `Theme.Motion` |
| `ACCEPTANCE.md` | H-19（AC8 暫時例外＋簽字 2026-09-27）、H-04、H-05 |
| 測試 | §4 所列；新增檔後跑 `xcodegen generate` |

不動：`DeckSnapshot.swift`、`App/AppModel.swift`（`clock` 用預設值）、1.x Python、`project.yml` 的版本號（發版時再改）。

**風險**
| # | 風險 | 偵測 | 處置 |
|---|---|---|---|
| R1 | 卡片改為 `Animatable` 後，動畫期間 21 張逐幀重算，掉幀 | V2 目視；`CoverFlowSlideGeometryTests` 取樣數 | 回退 |
| R2 | tick 0 內「先以位移 0 排版、再套位移」在某些機器上被畫出來（§8.3 推論） | V8 慢動作錄影 | 回退或另立 spike |
| R3 | 位次條件不成立的情況比預期多（左側還在長、履歴讀不到的前 10 首）→ 常常不滑 | V2／V3 實機；`CoverFlowSlidePlanTests` 列舉 | 已知限制；另立項評估以捲動動畫補這一類（§8.3 事實 2） |
| R4 | 過渡中 canonical 改變左側張數 → 結束過渡、走現行修正路徑，可能閃一幀 | 單元測試釘住「結束過渡」；畫面屬現行行為 | 現行行為，不新增風險 |
| R5 | 既有條帶測試因 `Animatable`／合併 `onChange` 變紅 | 既有防線（§4） | 修實作，不改測試 |
| R6 | 連按下一首（0.62s 內兩次換歌）：第二次不滑、直接定位（§3.1-3） | 單元＋幾何測試；V3 實機連按 | 已知限制（§9 末） |
| R7 | S9 harness 的條帶與 View 是複本，結論外推到 production 失敗（S7→S8 有前例） | T8 以 production `CoverFlowView` 逐步斷言；V2–V8 實機 | T8 紅 → 停手回報，不硬改測試 |

**回退**：VM 不發平移指令（`CoverFlowSlidePlan.make` 一律回 `.direct`）即等同現行行為；條帶位移量恆為 0。整體回退＝revert 本功能的 commit。

**ACCEPTANCE**：H-19 記 AC8 暫時例外（僅 VM 顯示層、≤ 動畫時長×2、原 ID、canonical 不變；簽字 2026-09-27）；H-04 驗證欄補「平滑」的證據（`CoverFlowSlideGeometryTests`＋V2／V3）；H-05 補「畫面在舊當前卡才平移」與 V5。

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

### 8.3 S9 spike（2026-09-27，`CoverFlowSlideSpikeS9Tests`，`TEST_RUNNER_AZW_SPIKE_S9=1`）

**設置**：`CoverFlowStrip`／`CoverFlowView` 的測試內複本（`S9Strip`／`S9View`，只多出平移指令；生產碼未動）＋production 的 `CoverFlowViewModel`、`DeckCard`、binding setter（→ `scrollPositionDidChange`）；動畫 0.62s。條帶在**同一次更新**內收到過渡牌組＋平移指令後自行動作，測試端不再介入。每組 20 步，共八輪（全矩陣 48 組；`binding` 手段 24 組＋基線；補數 6 組；`keptIndex` 2 組；內容位移各變體 4 輪）。原始輸出在 session scratchpad（不入庫）。

**量法**
- 平移：逐幀（16ms×50）取樣捲動原點，≥3 幀介於起訖且單調。
- 落定：條帶幾何判定的「正中」只有目標卡、有卡層對齊視口中點（<1pt）、捲動原點落在目標卡的位次上。
- 畫面提交序列：每個「正中」判定事件標上 runloop tick（`beforeWaiting`、order 取最大＝排在 Core Animation 提交之後）。同一 tick 內的中間狀態不會被畫出來；跨 tick 的才會。
- 傾斜：最靠近視口中點的卡層之投影矩陣透視項（|m14|×1000；0＝正面）。真實捲動的曲線＝起滑 0、途中峰值 0.35–0.40、落定 0。
- 量測起點修正：掛載當下就帶牌組，走的是 `scrollPosition` 的初值路徑，畫面停在第一張（原點 −466、正中＝最左那張）。S8「第 1 步起點未穩」同因。S9 改為先空牌掛載、渲染後才首次給牌（＝production 的順序），並以 `#require` 驗起點。

**過渡牌組形狀**
| 形狀 | 內容 | 舊中心在牌組中的位次 |
|---|---|---|
| movingWindow | v4 §3.2 的 staged：換上新窗口、舊中心留著（S8 的形狀） | 改變 → 需要第一段「退回舊中心」 |
| heldWindow | 過渡期間沿用原牌組（卡 ID 不變），落定後換上新窗口 | 不變；落定後正中卡位次改變 |
| insertedTarget | 舊中心旁放進新身分的目標卡（next＝尾端追加；previous＝左鄰換身分），落定後換上新窗口 | 不變；落定後正中卡位次改變 |
| keptIndex | 同 heldWindow，但落定後換上的牌組保住正中卡的位次（左側多留／少放幾張） | 全程不變 |
| direct | 基線：現行 production 換歌（同一次更新換牌＋設中心，無動畫） | — |
| flip | 同基線直接換牌＋設中心，舊中心留著；平移改由條帶內容的 `.offset` 動畫呈現，**捲動位置不動** | 改變，但目標卡的新位次＝舊中心的原位次 |
| flipInserted | 同 flip，目標卡是新身分的卡（next＝退回模式左側已滿、尾端追加；previous＝往回跳當下的 `o:` 中心，右側只剩暫留的舊中心） | 同上 |

**結果（各輪合計）**
| 形狀 | 觸發 | 平移 | 落定 | 平移途中無錯誤提交 | 落定後換牌無錯誤提交 |
|---|---|---|---|---|---|
| movingWindow | inline | 0/120 | 120/120 | — | — |
| movingWindow | stateHop | 0/120 | 120/120 | — | — |
| movingWindow | taskHop | 94/120（各組 13–19/20） | 120/120 | 120/120 | — |
| movingWindow | geometryGate | 87/120 | 120/120 | 94/120 | — |
| heldWindow | 四種皆同 | 520/520 | 520/520 | 520/520 | 402/520 |
| insertedTarget | 四種皆同 | 520/520 | 520/520 | 520/520 | 404/520 |
| keptIndex | inline | 80/80 | 80/80 | 80/80 | **80/80** |
| direct（基線） | — | 0/40（無動畫） | 40/40 | 40/40 | — |
| flip（位移不餵值） | inline | 120/120 | 120/120 | 見事實 6 | — |
| flip（位移同時餵旋轉與疊放） | inline | 80/80 | 80/80 | 見事實 6 | — |
| flip（位移只餵疊放與正中判定） | inline | **80/80** | 80/80 | **80/80** | 不需要換牌 |
| flipInserted（同上） | inline | **40/40** | 40/40 | **40/40** | 不需要換牌 |

觸發：`inline`＝同一個 onChange 內緊接著做；`stateHop`＝改條帶的 @State、下一輪更新做；`taskHop`＝排一個主執行緒工作；`geometryGate`＝`taskHop`＋確認舊中心已在幾何正中才做。

**已核事實**
1. **條帶內兩段（口令定義的 S9）不可靠**：`inline`／`stateHop` 0/240，第一段的無動畫 `reader.scrollTo(old)` 尚未生效就被第二段蓋掉（瞬移）。`taskHop` 94/120，失敗步同為瞬移。`geometryGate` 每步都會滑，但 33/120 是「等到舊中心回到正中才起滑」，其中 26 步的提交序列為 `old→target→old→∅→target`——換牌後目標先在正中被提交一次，再退回舊中心起滑（16ms 取樣同時讀到首幀位移 0）。
2. **舊中心位次不變時，一次動畫就夠**：heldWindow＋insertedTarget＋keptIndex 共 1120/1120 平移、落定、途中無錯誤提交，四種觸發、兩種手段皆然。不需要「退回」這一步。
3. **落定後換上「正中卡位次改變」的牌組，22.5% 會提交一次錯誤狀態**（234/1040）：提交序列 `target→鄰張→target` 或 `target→∅→target`，修正晚 1–2 個 tick。這條路徑就是 production 現有的 `onChange(items) → reader.scrollTo(centerID)`（2026-09-24 兩側變動修正）。
4. **保住正中卡位次的換牌不會閃**：keptIndex 80/80。
5. **基線不閃**（40/40）：窗口隨中心移動，捲動位置的數值前後相同，沒有東西需要修正。
6. **`.offset` 只進一半的幾何**：
   - 旋轉／縮放（`visualEffect`）的幾何**含** `.offset`：位移不餵任何值時，傾斜曲線已與真實捲動相同（起滑 0、峰值 0.33–0.40）。
   - 疊放與正中判定（`onGeometryChange`）**不含** `.offset`：位移不餵值時「正中」事件在換牌當下（`target+@0`）就發生。
   - 把位移值同時餵給兩者會算兩次：傾斜峰值 0.63–0.77、起滑第一幀最大 0.77。
7. **動畫完成回呼可用**：`withAnimation(_:completionCriteria:.logicallyComplete:completion:)`（macOS 14+）480/480 次都有回呼，離指令 0.635–0.666s，回呼當下離終點 0pt。
8. **內容位移可行**：位移值只餵疊放與正中判定（卡片視圖設為 `Animatable`，動畫期間逐幀以內插值重算），旋轉沿用原幾何——120/120 平移、落定；提交序列全為 `old→∅→target`；傾斜起滑 0、峰值 0.35–0.40、落定 0；VM 同步 120/120（換牌當下就是目標，回寫 1 次）；捲動原點全程不變。
9. **手段**：`binding`（條帶在動畫內寫 `centerID`）VM 同步 1120/1120，回寫 2 次皆為目標；`reader`（`reader.scrollTo`）VM 不同步 0/480，目標值的回寫延到下一次換牌才到。
10. **非目標回寫 0**（全部 1960 步）。

**推論（未核）**
- 由事實 1、3、4、5 歸納：凡是「換牌的同一次更新需要無動畫改捲動位置」，那次修正有 15–45% 晚一次畫面提交才生效；不需要改捲動位置就不會出錯。
- 跨 tick 的錯誤狀態至少顯示一幀：未做像素層驗證（螢幕擷取需要錄影權限），依據是 tick 的定義與 16ms 取樣讀到的首幀位移。
- 位移不餵值的 flip，畫面上會是「換牌當下疊放先對調（目標壓到舊中心上面），再平移」：由事實 6 推得，未目視。
- 事實 8 的每一步在 tick 0 內都有一組 `old−、鄰張＋、old＋`：同一次提交內先以位移 0 排版、再套上位移，未被提交。未目視。

**已排除的做法**
| 做法 | 排除依據 |
|---|---|
| VM 兩段觸發（mainAsync／sleep16／yield） | S8：隨機失敗 10–45% |
| 條帶內兩段，任何觸發時機 | 事實 1 |
| 同一次更新內換牌＋動畫設中心（sameUpdate） | S7：0/10；事實 1 的 inline 同因 |
| `reader.scrollTo` 做動畫 | 事實 9：VM 拿不到落定回寫 |
| 條帶內容 `.offset` 位移，位移不餵值／同時餵給旋轉與疊放 | 事實 6 |
| 落定後照現行路徑換上正式牌組 | 事實 3：22.5% 閃一幀 |

**範圍外的發現（只記錄，另立項）**
- production 現有的兩側變動修正與事實 3 同一條路徑：履歴晚到且正中卡位次改變時，同樣有機率閃一幀。
- `CoverFlowView` 若在掛載當下就帶著牌組，畫面會停在第一張。production 是先空牌掛載再給牌，未受影響。

## 9. 任務清單（v5；串行，主執行緒 TDD，不派 agent）

| # | 任務 | DoD |
|---|---|---|
| T1 | `Theme.Motion`；`LyricsFlowPageView` 改引用 | 常數值與現行相同；全量單元不新增紅 |
| T2 | `QueueSession.slideHint(to:)` | `QueueSessionTests` 新增案例先紅後綠 |
| T3 | `CoverFlowSlidePlan`（純函式） | `CoverFlowSlidePlanTests` 先紅後綠；§3.2 對照表四列皆有案例 |
| T4 | `CoverFlowGeometry.slideOffset(slots:)` | `CoverFlowGeometryTests` 新增案例先紅後綠 |
| T5 | VM 顯示層與過渡狀態 | `CoverFlowViewModelSlideTests` 先紅後綠；`CoverFlowViewModelDeckTests`／`PrefetchTests` 不改即綠 |
| T6 | 條帶：平移指令、內容位移、`Animatable` 卡片 | 既有條帶測試（§4 既有防線）不改即綠 |
| T7 | `CoverFlowView` 接線、減少動態效果同步 | 編譯綠；T8 涵蓋行為 |
| T8 | `CoverFlowSlideGeometryTests`（正式） | 下一首／上一首各 3 次全綠，連跑 3 輪皆綠；T6／T7 還原任一處即紅 |
| T9 | `LyricsFlowModel` 傳 hint | `LyricsFlowModelTests` 新增案例先紅後綠 |
| T10 | `ACCEPTANCE.md`：H-19、H-04、H-05 | 條目含依據、驗證方式、狀態、簽字日期 |
| T11 | `/simcodex` → 全量單元（帶 skip＋超時）→ `coverage_gate.sh <單元 xcresult>` → `no_playback_gate.sh` → `Scripts` 的 Python 測試 | 全綠（已知基線紅除外，逐條列出）；無新增 skip／放寬斷言 |
| T12 | 列出使用者在場的實機驗證項 V2–V8 | 每項有操作步驟與預期畫面 |

順序：T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12。T3 依賴 T2 的 `SlideHint` 型別；T5 依賴 T3；T8 依賴 T5–T7。

**需使用者知悉／簽字（不擋實作；實機驗證時一併確認）**

會滑：畫面停在正在播的那張上，切到緊鄰的下一首；或切到上一首且清單能證明它就是前一項。

不滑（照現行瞬間切換）：
1. 手動滑走後換歌：直接拉回，不是滑回去（§2、V5）。
2. 左側還在長的前 10 首（履歴不足或讀不到時）（R3）。
3. 0.62 秒內連按兩次：第一次滑、第二次直接定位（R6）。
4. 跳播到不相鄰的歌、同一首歌在清單裡出現多次、清單被重寫（插歌、Genius）、往回跳但清單證明不了（§2 非目標、§3.1-4）。
5. 系統開了「減少動態效果」；動畫途中才開 → 動畫當場結束。

可能看到一幀跳動（現行行為，本功能不新增也不修）：
6. 動畫的 0.62 秒內，履歴更新剛好改變了左側張數 → 過渡中止，走現行的修正路徑（R4）。
7. 動畫的 0.62 秒內拖拉視窗邊框。

**待簽字的限制**
8. 手指正在拖、且離正中不到 52pt 的那一瞬間換歌：起滑可能有 ≤52pt 的跳動（§3.1-3）。

**待決定**
9. S9 量測碼與工作樹裡的 `AzathothsWhisper 2.xcodeproj`（xcodegen 重產時留下的舊副本，未入庫）要不要刪。

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

### A.4 2026-09-27 Codex R4（v5）與裁決（v5.1）

R4 結論：核心方向可行；P1×3、P2×3、簡化建議一則。最擔心：條帶重建時位移被重新套上卻沒有動畫。原始輸出：session scratchpad `codex-v5-r4.txt`（不入庫）。

| R4 | 裁決 | 理由／落點 |
|---|---|---|
| 1（P1）條帶重建：`releasedGeneration` 歸零、VM 仍持有舊指令 → 位移卡到逾時 | **採納（修改）** | 問題成立。不採「把釋放的權威放回 VM」：釋放必須發生在位移已套用之後的另一次更新，VM 在同一同步段內做會被合併（S7 sameUpdate 0/10、S8 10–45% 失敗）。改採 R4 的第二案：條帶 `onAppear` 見到未釋放的指令即釋放並回報落定（§3.4）；幾何測試加「重建」一案。佐證：`RootView.swift:122-140` Editor 頁常駐、`LyricsFlowPageView` 註明 Cover Flow 常駐，production 重建屬罕見，但防線便宜 |
| 2（P1）`centerID == old.id` 不等於畫面事實 | **部分採納** | 採納「`centerID` 落後於畫面」（`CoverFlowViewModel.swift:26`）：改用條帶的幾何回報 `isPlayingCardCentered`（§3.1-3）。駁回「違反 H-05」：H-05 原文是「下次真實切歌才拉回」，真實換歌本來就解除抑制（`CoverFlowViewModel.swift:68-70`），v5 不改這條 |
| 3（P1）S9 只印統計、永遠綠 | **採納** | S9 是量測不是回歸測試（與 S5／S7／S8 同）。正式 `CoverFlowSlideGeometryTests` 每一步斷言（§4）；T8 的 DoD 含「還原實作即紅」 |
| 4（P2）位次條件說得過強 | **採納** | 改述為固定幾何、視窗寬度不變下的充分條件；過渡中改視窗大小列為不處理（§3.2） |
| 5（P2）`SlideHint` 缺 target 身分 | **採納** | 加 `targetPersistentID`，`make` 比對（§3.1-4、§3.5） |
| 6（P2）A→B→C 的位移不連續 | **採納（修改）** | 不做相位承接：過渡中又換歌一律 direct（§3.1-3），單元與幾何測試各一案。列為已知限制供使用者知悉（§9 末） |
| 簡化：只存 `deck`＋`transition`，其餘派生 | **採納** | §3.3；`display(...)` 回 nil 時由 `apply` 結束過渡 |
| (i) S9 不足以外推到 production | **採納** | 風險 R7；T8 用 production View |

### A.5 2026-09-27 Codex R5（v5.1）與裁決（v5.2）

R5 結論：v5.1 不可直接定稿，兩個 P1 要先補；補完可進實作。無新 P0。原始輸出：`codex-v5-r5.txt`（不入庫）。

| R5 | 裁決 | 理由／落點 |
|---|---|---|
| 1a「釋放必須留在條帶」是推論不是事實 | **採納** | §3.4 改標「推論，未核」 |
| 1b 落定非冪等（P1） | **採納** | 單一入口＋`transition?.generation` 守衛＋先清後做（§3.3）；測試列舉遲到與重複回報（§4） |
| 1c `onAppear` 可能搶在 `onChange` 前把起滑切掉 | **採納（修改）** | 不用 `onAppear`，改 `onChange(initial: true)` 單一消費點（§3.4）；幾何測試驗「正常起滑不被切掉」 |
| 2a 駁回「違反 H-05」 | Codex 同意 | — |
| 2b `isPlayingCardCentered` 只證明「大致在中間」（P1） | **採納** | 前置條件加 `centerID == old.id`（§3.1-3）。殘餘邊界「手指正在拖且仍在容差內」列為不處理並寫明理由 |
| 2b 殘留回報（推測） | **採納** | 走讀 `CoverFlowView.swift:70-73`：卡片離開 `.current` 後 `guard card.side == .current` 擋掉它的 false 回報，殘留屬實。當前卡 ID 改變即清（§3.3-2） |
| 3 過渡中又換歌 direct | Codex 同意 | — |
| 4「只存兩樣」措辭；落定後清理未寫明 | **採納** | §3.3 |

### A.6 2026-09-27 Codex R6（v5.2，整體確認）與裁決（v5.3）

R6 結論：不可直接定稿；三項必要條件。與 §7、A.1–A.3 無實質衝突。原始輸出：`codex-v5-r6.txt`（不入庫）。

| R6 | 裁決 | 理由／落點 |
|---|---|---|
| A1 `initial` 是「出現」語義不是「重建」語義：已釋放、動畫中再出現會被提前落定（P1） | **採納** | 初值只補救未釋放的指令，已釋放即 no-op（§3.4）；幾何測試加「動畫中移出再放回」一案（§4） |
| A2 「macOS 14 無從判定正在拖」不成立：`NSScrollView` live-scroll 通知可用 | **理由採納、做法不採** | 我方原理由錯了，Codex 勝。但判定出來之後只能改走 direct——畫面是整張卡距的瞬間跳，比 ≤52pt 的跳＋平移更差；且要新增一個系統邊界（依專案慣例須配 protocol＋替身）。依 R6 自己給的第二條路：升格為待使用者簽字的限制（§3.1-3、§9 末第 8 點） |
| B2 §3.7 的消費端沒有會變紅的測試 | **採納** | `cards` 是唯一出口，View 端全部經它；VM 測試補鍵盤步進、預取、中心標籤、把手刻度（§4） |
| B4 使用者會察覺的行為差異列得不全 | **採納** | §9 末改列「會滑／不滑／可能看到一幀跳動／待簽字」 |

### A.7 2026-09-27 Codex R7（v5.3）

R6 三項條件逐項確認：A1 已滿足；A2 設計裁決已滿足（不實作 live-scroll bridge 的理由成立：沒有證據支持 direct 的畫面優於「≤52pt 跳＋平移」），但須使用者簽字；B2／B4 已滿足。本輪無新 P0／P1。

結論（雙方一致）：設計收斂於 v5.3。**進入實作的唯一條件＝使用者對 §9 末第 8 點明確簽字**。Codex 最擔心的一點：≤52pt 的起跳在數值上合理，實機觀感只能靠簽字後的實機驗證確認。原始輸出：`codex-v5-r7.txt`（不入庫）。

R4–R7 勝負：Codex 勝——條帶重建、落定冪等、初值的「出現」語義、`isPlayingCardCentered` 容差、殘留回報、hint 缺 target 身分、「macOS 14 無從判定」的理由錯誤、消費端缺測試。我方勝——駁回「違反 H-05」、過渡中又換歌一律 direct、釋放留在條帶、不實作 live-scroll bridge。

