# Lyrics FX — A2「mono 繪製與實測」實施計劃 v2（已實作；評審、量測與實機結果見 §8）

母計劃：`docs/plans/2026-10-03-lyrics-fx-mode.md`；前段：`docs/plans/2026-10-04-lyrics-fx-a1-contract-and-time.md`（以下稱 A1 計劃）。本檔只管 A2，不重開已定案的決定。
分支：`feature/lyrics-fx`（de5d672）。模式：normal（全程同步；實測要使用者在場，loop 沒有可交出去的環節）。

## 0. 複述
- **目標**：升起層可切到「歌詞特效」，以 mono 一種風格隨播放走；暫停停住、拖進度跟上、換歌換詞；切回是 Cover Flow；重啟保留。
- **範圍＝開工口令 6 項＋P2 定案的 1 項**：
  0. P2-1：同曲 metadata 補讀（§1 辯論結論）。
  1. `RaisedLayerStyle` 偏好（預設 `coverFlow`，重啟保留）＋可見性扇出。
  2. 把手右端兩格圖示切換按鈕（只有按鈕，無選單項、無快捷鍵）。
  3. 繪製引擎：`TimelineView`＋`Canvas`＋純函數 plan，只做 `mono`；`status != .present` 只畫背景與既有狀態字。
  4. 減少動態效果：靜態的當前行＋下一行。
  5. DEBUG 預覽場景（固定假歌詞、假時鐘）＋靜態截圖與短錄影。
  6. 實測：每幀耗時、暫停、拖進度、offset 目視校準。
- **非目標**：mono 以外的風格、模板池、個性、種子亂數、關鍵字粒子、組合器（B）；外部時間軸來源（C）；Settings 介面（含 offset 設定、升起層預設值）；字型嵌入；來源標示 `synced／estimated`（母計劃 §9-E 未拍板）；純音樂退回 Cover Flow；Cover Flow 本身的改動；`history-recheck-flaky` §5 的延後 P2；commit 到 main、push。
- **使用者可見的變化**：把手右端多兩格按鈕；切到歌詞特效後升起層顯示 mono 歌詞。不切就與現在完全相同（預設 `coverFlow`）。

## 1. A1 留下的三條 P2：Codex 辯論結論（2026-10-06，R1 即收斂）
| # | 題目 | 單一結論 | 依據 |
|---|---|---|---|
| P2-1 | 同曲 metadata 補讀 | **A2 內修**（§3.0） | 同 signature 時 `read.metadata` 被丟掉（`NowPlayingMonitor.swift:217-223`）；純文字歌詞在 `duration ≤ 0` 時不建時間軸（`LyricsFXViewModel.swift:108-112`）→ 換歌那次讀曲長失敗，整首有詞卻空白。A2 起使用者看得到。Codex 同意並列為最擔心的一點 |
| P2-2 | 每次輪詢多讀 2 欄 | **維持現狀** | 每 3 秒約 +4 ms（A1 §8.5 的單機量測值，不是保證）；P2-1 的補讀正靠每次都讀；要省得把上次 signature 傳進 AE 端，豁免檔只剩 2 行預算（408／410）。Codex 同意 |
| P2-3 | 換歌通知連發合併 | **不加 debounce**；補一條測試釘住「受閘門的在飛讀取＋N 次 resync＝總共 2 次讀」 | 單飛已把連發合併（`PlaybackPositionClock.swift:124-137`）；debounce 會延後暫停／拖進度的反應，而「拖進度典型 ≤ 2 秒」是 A2 驗收項。Codex 修正一處措辭：不能宣稱所有時序恰 2 次——讀取剛完成時到的通知會開新一輪（屬正確行為） |

Codex 補充（採納）：換曲／停播／forceRefresh 時 metadata 快取要一起重置；metadata 變更要讓 `revision +1`（時間軸身份變了，舊的非同步結果要作廢）。
合併規則（計劃評審 R1 定案，我勝）：本次 nil 不覆蓋已知值；已知值變成另一個非 nil 值＝變更、要發事件（`nil`＝讀不到、`""`／`0`＝Music 明確回覆，`MusicControlling.swift:66-74`）。命名 `mergingLatestKnown(with:)`。

## 2. 概念表
| 概念 | 定義 | 邊界 |
|---|---|---|
| `RaisedLayerStyle` | 升起層畫什麼：`coverFlow`／`lyricsFX` | 與 `LyricsSurface`（升或降）正交；不進 reducer。存 UserDefaults `RaisedLayerStyle`；認不得的值＝`coverFlow` |
| 可見 | `tab == .editor ∧ surface == .coverFlow ∧ style == 該畫面` | **唯一定義在 `AppModel.updateRaisedLayerVisibility()`**；Cover Flow 與特效互斥 |
| `FramePlan` | 某一刻要畫的東西：`glyphs: [GlyphDraw]`＋`backdrop` | 純資料；不含 SwiftUI 型別以外的狀態；不按尺寸快取 |
| `GlyphDraw` | 一個字（grapheme）：`text, fontSize, weight, origin, opacity, tone` | `origin`＝該字行盒的 **top-leading**；Canvas 以 `anchor: .topLeading` 畫（同字級同行盒高，基線自然一致）。只有 mono 用得到的欄位，B 段再加 rotation／scale／blur |
| `LyricsFXMotion` | `.full`／`.reduced` | reduced＝無淡入淡出、無位移 |
| `TextMeasuring` | `advances(of:fontSize:weight:) -> [CGFloat]`（逐 grapheme 的 x 位移，末項＝總寬） | 生產＝CoreText（Space Grotesk）；測試＝固定寬度替身。plan 因此保持純函數 |

## 3. 設計

### 3.0 P2-1：`metadataChanged`
- `PlaybackEvent` 加 `case metadataChanged(persistentID: String, metadata: TrackMetadata)`。
- monitor 記 `lastMetadata: TrackMetadata`：`trackChanged` 時設成該次讀值；同 signature 時 `merged = lastMetadata.mergingLatestKnown(with: read.metadata)`（逐欄：本次 nil 保留舊值，否則取本次），`merged != lastMetadata` 才更新並 yield（帶 merged）。`notPlaying`／`forceRefresh` 清 signature 處一併重置成 `.unknown`。日誌只記布林。
- `TrackMetadata.mergingLatestKnown(with:)` 純函式，放 `MusicControlling.swift` 型別旁；非有限的 duration（NaN／∞）視為讀不到。
- 消費：`LyricsFXViewModel.handle` → `metadataUpdated(persistentID:metadata:)`：只認當前曲、與現值相同＝no-op；否則存 metadata、`revision +1`、重建時間軸與 `genreStyle`（走既有 `apply`）。`EditorViewModel`／`LyricsFlowModel` 各加 `case .metadataChanged: break`；`BatchViewModel` 用 `guard case`，不受影響。
- 事件順序：同一次讀取若歌詞與 metadata 都變，先 `lyricsChanged` 再 `metadataChanged`（各 +1，互不依賴）。

### 3.1 `RaisedLayerStyle` 與可見性扇出（項 1）
- `Services/Config/RaisedLayerStyle.swift`：`enum RaisedLayerStyle: String, Sendable, CaseIterable { case coverFlow, lyricsFX }`。
- `ConfigStore`：`Key.raisedLayerStyle = "RaisedLayerStyle"`、`var raisedLayerStyle`（無值或認不得→`.coverFlow`）、`setRaisedLayerStyle(_:)`。
- `AppModel`：`private(set) var raisedLayerStyle`（init 時讀 store）；`func selectRaisedLayerStyle(_:)`＝同值 no-op，否則存檔＋更新屬性＋`updateRaisedLayerVisibility()`。
- `updateCoverFlowVisibility()` 改名 `updateRaisedLayerVisibility()`：
  `let raised = tab == .editor && lyricsFlow.surface == .coverFlow`；`coverFlow.setVisible(raised && style == .coverFlow)`；`lyricsFX.setVisible(raised && style == .lyricsFX)`。呼叫點：分頁切換、`onSurfaceChanged`、選風格（三處）。
- **已接受的行為改變**：切到歌詞特效＝`coverFlow.setVisible(false)`，與降下時同一條可見性路徑（取消封面預取，切回時由既有路徑恢復）；母計劃 §2.1 既定。不改 Cover Flow 的程式，但它的可見／預取狀態確實會變。
- A1 的 I-10（「生產路徑不啟動時鐘」）改寫成「只有特效可見且有詞才讀位置」。

### 3.2 把手切換（項 2）
- 現況：整條把手是一個 `Button`（`LyricsFlowHandleView.swift:26-55`）。按鈕不能巢狀 → 改成 `HStack { 升降按鈕（標題＋刻度，佔滿剩餘寬） ; 風格切換 }`，外層共用背景與上邊線；升降按鈕的 a11y identifier／label、hover 行為不變。
- `RaisedLayerStyleToggle`（`Features/LyricsFlow/RaisedLayerStyleToggle.swift`）：兩格 28×28 直角按鈕、1 px `Theme.border` 外框；選中格白字＋`Theme.Gray.g800` 底，未選 `g500`。圖示用 SF Symbols（把手已用 `chevron`）：`square.stack`（封面）、`text.alignleft`（歌詞）。
- a11y：`AccessibilityID.styleCoverFlow`／`.styleLyricsFX`；label＝`nav_coverflow`（既有）／新鍵 `raised_style_lyricsfx`（en「Lyrics FX」、zh-Hant「歌詞特效」、ja「歌詞エフェクト」）；選中者加 `.isSelected` trait。
- 升降兩態都顯示、都可按；按下只換偏好與內容，不升降。**產品變更**：把手右端這一小塊原本點了會升降，之後不會 → 更新 ACCEPTANCE 的把手條目。
- 把手左側標題跟著風格走（`coverFlow`→`nav_coverflow`、`lyricsFX`→`raised_style_lyricsfx`）；升降按鈕的 a11y label 新增 `lyricsfx_show`／`lyricsfx_hide` 兩鍵（三語）。純函式 `LyricsFlowHandle.titleKey(style:)`／`.toggleLabelKey(style:isRaised:)`，有單測。
- 不加選單項、不加快捷鍵（母計劃 §9-C 既定）。

### 3.3 頁面掛載（`LyricsFlowPageView`）
- **`CoverFlowView` 維持常駐**（H-02 缺陷 3：條帶不得經初始值路徑重新掛載；也因此本案不碰 Cover Flow）。升起層內容改 `ZStack { CoverFlowView…; if style == .lyricsFX { LyricsFXView… } }`；風格＝特效時 Cover Flow `opacity(0)`、`allowsHitTesting(false)`、`accessibilityHidden(true)`，`isInteractive` 與 `@FocusState` 的觀察值（現 `LyricsFlowPageView.swift:42-45`）都改為 `isRaised && isActive && style == .coverFlow`——切到特效時觀察值由 true 變 false，焦點才會真的放掉。
- 切換不帶轉場動畫（直接換）。
- `LyricsFXView` 只在風格＝特效時掛載；不可見（降下或在 Batch 分頁）時不建任何 `TimelineView`（§3.4 排程表）。
- DEBUG 探針：1 pt 透明文字 `AccessibilityID.raisedStyleProbe`，value＝風格 rawValue（容器上的 value 會被吞，沿用 `surfaceProbe` 的做法）。

### 3.4 繪製引擎（項 3；`Features/LyricsFX/`）
檔案：`LyricsFXFrame.swift`（型別＋`plan`）、`MonoStyle.swift`（mono 的版面與動勢）、`TextMeasuring.swift`（協議＋CoreText 實作＋快取）、`LyricsFXView.swift`（TimelineView／Canvas／overlay）。

**純函數**
```
LyricsFXFrame.plan(timeline: LyricsTimeline?, time: Double?, size: CGSize,
                   motion: LyricsFXMotion, measurer: any TextMeasuring) -> FramePlan
```
- `timeline == nil` 或 `time == nil` 或尺寸過小（任一邊 < 120）→ 只有背景、無字。
- `current`＝`start ≤ t < end` 的行，**一律尊重既有 `TimedLine.end`、不重推**（builder 已把空時間點變成前一行的 end 並丟掉它自己，`LyricsTimelineEstimator.swift:119-128`——這就是間奏空檔）；`next`＝其後第一個文字非空白的行。

**mono（母計劃 §2.6 表：左對齊、Space Grotesk、當前行大＋下一行小灰；當前行淡入上移、舊行淡出；無逐字）**
- 邊距：左右 `max(32, w×0.06)`；內容寬＝w−2×邊距。
- 字級：當前行 `S = clamp(w×0.052, 24, 54)`、weight medium、`Theme.coldWhite`；下一行 `0.5×S`、regular、`Theme.Gray.g500`。行高 1.25×字級。
- 換行：以 `TimedLine.words` 為單位貪婪折行；單詞超寬時逐字折（CJK 本來就是逐字）。當前行區塊最多 4 列、下一行最多 2 列，超出截掉（不縮字級，避免每行字級跳動）。
- 位置：當前行區塊第一列的行盒 top 在 `h×0.36`；下一行區塊的 top 在當前行區塊底下 `0.6×S`。
- 定位依「整列以 CoreText 排版後各 grapheme 的 x 位移」。只保證 Space Grotesk 的 Latin／CJK 範圍；連字、RTL、複雜文字不保證與整列 shaping 完全相同。
- 動勢（`.full`）：`enter = 0.35 s`、`exit = 0.35 s`、位移 `0.3×S`，緩動 ease-out cubic。
  - 當前行：`p = clamp((t − start)/enter)`，opacity＝p、dy＝(1−p)×位移。
  - 剛結束的行：`q = clamp((t − end)/exit)`，opacity＝1−q、dy＝−q×位移；`q ≥ 1` 不畫。LRC 行 end＝下一行 start，所以舊行淡出與新行淡入重疊，畫在同一區塊位置。
  - 下一行預覽：只在「有當前行」或「距它的 start ≤ `previewLead = 2 s`」時畫，opacity 0.55；它成為當前行時不做位置過渡（直接由當前行的淡入接手）。
  - 因此：`t < 第一行 start − 2 s` 無字；`t ≥ 最後行 end + exit` 無字。（母計劃 §2.7 寫「t < 第一行 start 無字」；mono 有下一行預覽，故放寬成提前 2 秒，記為 mono 的規則。）
- `.reduced`：當前行 opacity 1、dy 0；不畫正在淡出的行；下一行預覽規則相同。
- 每個 grapheme 一個 `GlyphDraw`（空白不產生）。整列一起動，但資料形狀已是逐字——B 段的逐字個性直接掛上，且 200 字預算量得到真實成本。
- A2 不做：種子亂數（mono 無隨機）、`nextBoundary`、`isChorus` 演出（mono 無サビ參數）、關鍵字粒子。

**View**
- `LyricsFXView(model: LyricsFXViewModel, reduceMotion: Bool)`：
  - 排程由純函式決定（有單測）：`LyricsFXSchedule.resolve(isVisible:isRunning:reduceMotion:)`，`isRunning`＝`positionClock.anchor` 為 `.running`（讀 observable 的 anchor，暫停／恢復時 body 會重算）。
    | 可見 | 播放中 | 減少動態 | 結果 |
    |---|---|---|---|
    | 否 | — | — | `none`：只畫背景，不建 TimelineView |
    | 是 | 否 | — | `none`：以當下位置畫一次靜態 Canvas（暫停停住；不留定時器） |
    | 是 | 是 | 否 | `animation`：`TimelineView(.animation)` |
    | 是 | 是 | 是 | `periodic`：`TimelineView(.periodic(from: .now, by: 0.25))`（母計劃 §2.7 R1-5：不能靠 anchor 的 Observable 觸發；0.25 s 讓換行延遲 ≤ 0.25 s） |
  - 每幀：`t = model.positionClock.position(at: .now)` → `plan` → `Canvas` 逐字 `context.draw(resolved, at:)`。同一幀內以 `(text, fontSize, weight, tone)` 為鍵暫存 resolved text（跨幀不快取，先量再決定要不要加，母計劃 §2.7 的順序）。
  - overlay：`model.statusText`（未播放／權限被拒，既有英文常數，mono 11 pt 灰）；否則 `status != .present` 時 `LyricsStatusLabel(status:)`。`status == .present` 但沒有時間軸或位置未知 → 只有背景。
  - 背景：`Theme.background`。
  - a11y：`accessibilityElement(children: .ignore)`、identifier `AccessibilityID.lyricsFXLayer`、label＝`raised_style_lyricsfx`、value＝當前行文字（無則空）。
- 時間來源一律走 `PlaybackPositionClock`；預覽場景靠假 Music 的 `playbackPosition()` 腳本餵時鐘（§3.6），不另開第二條時間路徑。
- offset：維持 A1 的固定 0，本段不動時鐘（見 §6-4）。

### 3.5 減少動態效果（項 4）
`@Environment(\.accessibilityReduceMotion)` 由 `LyricsFlowPageView` 傳入（既有），對應 `.reduced`。DEBUG 預覽場景可用 `AZW_LYRICSFX_REDUCE_MOTION=1` 強制（出截圖用；XCUITest 改不了系統設定）。

### 3.6 DEBUG 預覽場景（項 5；`App/UITestSupport/`，整檔 `#if DEBUG`）
- `LyricsFlowUITestScenario` 加 `case lyricsFX`：播放中有詞（自編句子，內嵌 LRC：約 12 行、含一段 3 秒間奏空檔、一行長句、一行 CJK），`duration` 60 s；設定 suite 預植 `raisedLayerStyle = lyricsFX`（由環境變數 `AZW_UITEST_RAISED_STYLE` 指定，預設不預植）。
- `LyricsFlowUITestMusic.playbackPosition()`：該場景下依環境變數回讀數——`AZW_LYRICSFX_PREVIEW_AT=<秒>`＝暫停在該秒（frozen，出定格）；未設＝自啟動起以牆鐘前進、到曲長後回 0（循環播放的假時鐘）。`AZW_LYRICSFX_PREVIEW_DENSE=1`＝改用 200 字壓力歌詞（量每幀耗時用）。其餘場景維持回 `nil`。
- **先做最小 spike**（Codex 列為最易失敗的一步）：固定尺寸 Canvas → `ImageRenderer.cgImage` → 檢查有非背景像素、Space Grotesk 有載入。過了才做下面的 PNG 與 GIF；不過就立刻改 `NSHostingView` bitmap 路徑。GIF 明定 2x、sRGB、每幀 0.05 s。
- 截圖與短錄影**不靠螢幕錄製**：`Tests/LyricsFX/LyricsFXPreviewRenderTests`（app 宿主）用 `ImageRenderer` 把同一個 Canvas 繪製函式離屏畫成 PNG（進場中／停留／換行重疊／間奏只剩預覽／reduced／狀態字 6 張）與一支 6 秒 GIF（20 fps，ImageIO），寫到 `NSTemporaryDirectory()/azw-lyricsfx-preview/`；測試斷言檔案存在、尺寸正確、定格圖有非背景像素。產物我先自己看過再給使用者。真視窗的觀感留到「使用者在場」一併看。
- 繪製函式因此抽成 `LyricsFXCanvas.draw(_ plan:, in: inout GraphicsContext)`，View 與離屏渲染共用。

### 3.7 每幀耗時量測（項 6 之一）
- `#if DEBUG` 的 `LyricsFXFrameMeter`：記最近 600 幀的「plan＋Canvas 繪製指令」耗時（`ContinuousClock`）與該幀 `glyphs.count`，每 5 秒以 OSLog 記 `frames／p50／p95／max／glyphs`（純數字）。純記帳（環形緩衝＋百分位）抽成值型別、有單測。
- 壓力歌詞：以真實量測器在預覽視窗尺寸下，單測斷言定格時刻**實際畫出恰 200 個 glyph**（折行截斷後仍是 200，不是「輸入 200 字」）。
- 量法：Debug 建置以 `open --env` 啟動預覽場景（dense，視窗在前景），跑 30 秒，`log show` 取 p50／p95／max 回填 §8。
- **結論的範圍（Codex R1 勝）**：這量的是「主執行緒 plan＋Canvas 指令編碼」，不含 render server 光柵化，Debug 未最佳化是上界。整幀證據另試一次 `xcrun xctrace`（Animation Hitches）；跑不起來就在 §8 明記「整幀未量」，不宣稱。
- 門檻：200 glyph 的主執行緒 p50 ≤ 2 ms。超過 → 依母計劃 §2.7 順序處理（跨幀快取 resolved text → glyph path）；p50 > 4 ms 且快取無效＝母計劃 §6 的熔斷點，停手回報。
- 不寫「時間斷言」的單元測試（會變成不穩定測試）；單測只釘 plan 的輸出。

## 4. 任務清單（TDD：先紅後綠；紅燈摘要回填 §8）
| # | 任務 | DoD |
|---|---|---|
| T1 | P2-1：`TrackMetadata.mergingLatestKnown`、`metadataChanged`、monitor 快取、VM `metadataUpdated`、兩個 no-op case | `NowPlayingMonitorMetadataChangedTests`、`LyricsFXViewModelTests` 新增條目綠；既有 monitor／Editor／LyricsFlow 測試無新紅 |
| T2 | P2-3：時鐘合併測試 | `PlaybackPositionClockTests.manyResyncsDuringAGatedReadCauseExactlyOneMore` 綠（預期首跑即綠＝行為已在；若紅則修時鐘） |
| T3 | 項 1：`RaisedLayerStyle`、ConfigStore、AppModel 屬性與扇出、改名 | `ConfigStoreRaisedLayerStyleTests`、`AppModelLyricsFXTests` 新增條目綠 |
| T4 | 項 3a：`TextMeasuring`、`FramePlan`、`MonoStyle`、`LyricsFXFrame.plan` | `LyricsFXFrameTests`、`MonoLayoutTests` 綠 |
| T5 | 項 2＋3b＋4：`RaisedLayerStyleToggle`、把手重排、`LyricsFXView`／`LyricsFXCanvas`、頁面掛載、三語字串、AccessibilityID | 建置過；`LyricsFlowHandleTests` 新增條目綠；`make_xcstrings.py` 重產、Python 測試綠 |
| T6 | 項 5：`lyricsFX` 場景、假時鐘、離屏渲染測試 | `LyricsFlowUITestAssemblyTests` 新增條目、`LyricsFXPreviewRenderTests` 綠；6 張 PNG＋1 支 GIF 我看過 |
| T7 | 項 6a：`LyricsFXFrameMeter`＋量測 | 單測綠；dense 場景 30 秒的 p50／p95 回填 §8 |
| T8 | `LyricsFXUITests`（切換出現、切回、重啟保留）＋`xcodegen generate` | 編譯過；**執行＝使用者在場 #1** |
| T9 | ACCEPTANCE：I-10 改寫、新增 I-11…（§7） | 文件更新 |
| T10 | 閘門（T11 前跑一次；T11 若引出任何修改，改完**再跑一次**才算最終）：全量單元（skip `overlappingLoadSuspendsPollingUntilLastCompletes()`）、白名單、`no_playback_gate.sh`、Python、`coverage_gate.sh <xcresult>` | 全過；僅基線 `CoverFlowStripRenderGeometry` 7 斷言紅 |
| T11 | **使用者在場 #1**（一次問完）：UITests 授權與執行、真機四項（跟著走／暫停／拖進度／換歌換詞） | 量測值回填 §8；I 段狀態更新 |

**並行候選：無。** 任務形狀是串行鏈（T3→T5→T6→T8 逐層依賴），且全部經同一個 xcodebuild 與同一個 ad-hoc 簽名的測試宿主（與 A1 相同的理由）。主執行緒依序做，不派子 agent。

## 5. 測試（Swift Testing；歌詞一律自編句子）
- `NowPlayingMonitorMetadataChangedTests`：換歌時 duration 讀失敗、下一輪讀到 → 發一次 `metadataChanged`（帶合併值）；值相同不發；本次 nil 不覆蓋、不發；genre 由 A 變 B 發；換曲只發 `trackChanged`；`notPlaying`／`forceRefresh` 後快取重置；同一次讀取歌詞與 metadata 都變 → 先 `lyricsChanged` 後 `metadataChanged`。
- `LyricsFXViewModelTests` 追加：`metadataUpdated` 讓原本 nil 的時間軸建起來且 revision +1；genre A→B 時 `genreStyle` 更新且 revision +1；非當前曲忽略；值相同 no-op。
- `TrackMetadataMergeTests`：nil 不覆蓋；非 nil 覆蓋；`0`／`""` 是已知值、會覆蓋；非有限 duration 視為 nil。
- `LyricsFXScheduleTests`：§3.4 排程表四列。
- `ConfigStoreRaisedLayerStyleTests`：預設 `coverFlow`；存讀往返；認不得的字串→`coverFlow`。
- `AppModelLyricsFXTests` 追加：預設風格下升起也不讀位置（改寫既有 `theClockStaysIdle…`）；選 `lyricsFX` 且升起且有詞 → 開始讀位置、`coverFlow.isVisible` 變 false；切回 → 停讀、變回 true；降下／切到 Batch → 停讀；偏好寫進 store、以同一個 store 重建 AppModel 後保留；同值重選不重複扇出。
- `LyricsFXFrameTests`（固定寬度量測替身）：timeline／time 為 nil、尺寸過小 → 無字；`t` 在第一行前 2 秒外無字、2 秒內只有預覽；行內：當前行 glyph 數＝非空白 grapheme 數、opacity 與 dy 隨 enter 單調；換行瞬間舊行與新行同時存在且 opacity 互補方向；`t ≥ 末行 end + exit` 無字；間奏空檔只剩預覽（距下一行 ≤ 2 s）或無字（精確例：`[00:01]a [00:04]（空）[00:10]b` → 4–8 s 無字、8–10 s 只有 b 的預覽）；所有 glyph 落在畫布邊距內；opacity ∈ [0,1]；`.reduced`：無淡出行、opacity 只有 1 與預覽值、dy＝0；同輸入兩次輸出相等；LRC 空文字行不成為當前行。
- `MonoLayoutTests`：折行不超內容寬；超長單詞逐字折；列數上限截斷；CJK 逐字；字級夾在上下限。
- `LyricsFlowHandleTests` 追加：`titleKey`／`toggleLabelKey` 四種組合。
- `LyricsFXFrameMeterTests`：環形覆寫、百分位、空緩衝。
- `LyricsFlowUITestAssemblyTests` 追加：`lyricsFX` 場景的組裝（有詞、LRC 時間軸、預植風格）、`PREVIEW_AT` 回 paused 讀數、未設時讀數隨時間前進。
- `LyricsFXPreviewRenderTests`：見 §3.6。
- E2E `LyricsFXUITests`（使用者在場 #1）：`present` 場景點歌詞格 → `lyricsFXLayer` 出現、探針＝`lyricsFX`、升降探針仍 `raised`；點封面格 → 消失；`lyricsFX` 風格下重啟（不重置 defaults）仍是 `lyricsFX`；`lyricsFX` 場景＋`PREVIEW_AT` → 特效層的 a11y value＝該時刻的行；特效顯示時方向鍵不移動 Cover Flow 的中心、切回後恢復；兩格按鈕的 identifier／選中態／label。
- Scripts：`no_playback_gate.sh`、`python3 -m unittest discover -p 'test_*.py'`、`coverage_gate.sh <單元測試 xcresult>`。

## 6. 實機驗證（使用者在場 #1，一次做完）
1. XCUITest 授權 → 跑 `LyricsFXUITests`（先切 ABC 輸入法；先 preflight 放行鑰匙串）。
2. 真 Music、切到歌詞特效：(a) 播放中字跟著走；(b) 暫停→畫面停住，恢復→繼續；(c) 拖進度→量「拖動到畫面跟上」；(d) 換歌→換詞；(e) 切回 Cover Flow、退出重開仍保留。使用者只需操作 Music 並回報看到的現象。
3. 拖進度的量法：同時跑唯讀的 `LiveLyricsFXMeasurementTests.seekCatchUp`（每 50 ms 讀一次位置，記下跳動時刻），對照 app 日誌 `reanchored` 的時刻，差值即跟上時間；做 5 次取典型值。順帶記換歌時的通知數與位置讀取數（P2-3）。
4. offset：**本段不校準，`defaultOffset` 維持 0**。使用者 2026-10-06 確認曲庫沒有內嵌 LRC 的歌，估算時間軸校不了 offset；延到 C 段（有 LRCLIB 時間軸時）再目視校準。`AZW_LYRICSFX_OFFSET_MS` 的 DEBUG 覆寫因此本段不做（YAGNI，C 段需要時再加）。

## 7. ACCEPTANCE I 段增修
- I-10 改寫：只有「特效可見（Editor 分頁、升起、風格＝歌詞特效）且有詞」才讀播放位置；其餘零位置讀取。
- H 段把手條目：右端兩格為風格切換，不觸發升降（其餘區域照舊）。
- I-11 升起層畫面偏好：預設 Cover Flow；把手右端兩格按鈕切換；只換內容不升降；重啟保留；無選單項、無快捷鍵。
- I-12 mono：當前行大、下一行小灰；隨播放位置換行；暫停停住；拖進度典型 ≤ 2 s 跟上（量測值）；換歌、同曲改詞、寫入後顯示新詞。
- I-13 沒有詞可畫時：已標記無詞／讀不到→背景＋既有狀態字；未播放／權限被拒→既有英文狀態字；不跑動畫、不讀位置。
- I-14 減少動態效果：靜態的當前行＋下一行，無淡入淡出與位移。
- I-15 同曲 metadata 補讀：曲長／曲風晚一步才讀到時，特效自動補上時間軸。
- I-16 特效層無障礙：VoiceOver 只讀當前行。
- 每條附驗證方式（測試名）與狀態；實機項在 T11 後更新。

## 8. 紅燈摘要／量測記錄

### 8.1 TDD 紅燈摘要（2026-10-06）
| 任務 | 紅燈（骨架上跑） | 綠燈 |
|---|---|---|
| T1 同曲 metadata 補讀 | 9 tests／11 issues（monitor 5、合併規則 2、VM 2） | 連同既有 monitor 測試 66 tests 全綠 |
| T2 時鐘連發合併 | 首跑即綠（行為 A1 已在，測試只是釘住） | 20 tests 綠 |
| T3 偏好與可見性扇出 | 5 tests／12 issues | 連同既有 `AppModelTests` 37 tests 全綠 |
| T4 mono plan／折行／排程 | 19 tests／19 issues（首次因測試內強制解包而崩潰，改 `#require` 後取得正常紅燈） | 19 tests 全綠 |
| T5 把手鍵與按鈕 ID | 3 tests／10 issues | 綠 |
| T6 預覽場景 | **未先取紅**：組裝測試與實作同一步寫成（6 條）；壓力歌詞「恰 200 字」紅一次（186）後補足 | 20＋5 tests 綠 |
| T7 幀耗時記帳 | 3 tests／2 issues | 綠 |
| 全量 | — | **1032 tests／116 suites，僅基線 `CoverFlowStripRenderGeometry` 7 斷言紅**（skip `overlappingLoadSuspendsPollingUntilLastCompletes()`） |

### 8.2 每幀耗時（2026-10-06；Debug 建置、預設視窗、壓力歌詞、每窗 600 幀）
量的是**主執行緒 plan＋Canvas 指令編碼**，不含 render server 光柵化；Debug 未最佳化，屬上界。
| 畫法 | glyph 數 | p50 | p95 | max |
|---|---|---|---|---|
| 逐字 `draw(Text)`（初版） | 200（換行重疊時至 305） | 2.7–3.0 ms | 5.0–5.7 ms | 6.6–8.6 ms |
| ＋跨幀快取 resolved text | 同上 | 離屏拆分量測無變化（1.30 → 1.30 ms） | — | — |
| **字形外框路徑、同透明度同色併成一條 Path 一次 fill（定案）** | 200（至 305） | **1.04–1.09 ms** | **1.44–1.56 ms** | 穩態 1.9–2.2 ms；第一窗（含暖機）5.1 ms、第二窗 3.6 ms |
- 拆分量測（離屏，200 字）：plan 約 0.10 ms；繪製 1.30 ms → 0.20 ms。結論：成本在逐字的 draw 呼叫本身，不在 resolve、不在 plan。
- **門檻（200 glyph 主執行緒 p50 ≤ 2 ms）：過。**
- **整幀未量**：`xcrun xctrace record --template 'Animation Hitches'` 錄了 25 秒，匯出時 `Document Missing Template Error`；照 §3.7 只試一次，不宣稱整幀數字。
- 與計劃的差異：§3.7 寫的順序是「跨幀快取 → glyph path」，兩步都做了，第一步實測無效已移除。資料形狀仍是逐字 `GlyphDraw`。
- 離屏 GIF 用 1x（計劃寫 2x）：120 幀 2x 檔案過大，定格圖仍是 2x。

### 8.3 閘門（T11 前；T11 若引出修改需重跑）
- `no_playback_gate.sh` exit 0；`Scripts` Python 333 tests OK；選擇器白名單 suite 綠。
- `coverage_gate.sh <單元測試 xcresult>`：Services+Infra 96.2%（門檻 80%）；豁免檔 408／410 行（未動）。
- `xcodebuild build-for-testing`（含 `LyricsFXUITests`）成功；UI 測試**尚未執行**（使用者在場 #1）。

### 8.4 Phase 3 實施後評審（/simcodex 3 輪；無安全敏感改動，未派 security-reviewer）
| 輪 | 來源 | 採納並修 | 駁回／延後（理由） |
|---|---|---|---|
| R1 | simplify ×4 | 量測器與路徑快取共用 `DisplayFontCache`；三份 a11y 探針抽成 `AccessibilityProbe`；預覽歌詞收斂到場景一處；「減少動態」強制由 View 讀環境變數改為組裝時注入 VM；非有限曲長改在 `TrackMetadata.init` 清洗（換歌與補讀事件同一種值）；動畫上限 60 fps | 按行界排程取代連續動畫＝mono 專用，B 段逐字停留動畫會讓它作廢；每幀重建 Path、新行第一幀冷快取＝實測在預算內（暖機窗 max 5.1 ms，單幀）；其餘 P2 見下 |
| R1 | codex | 特效層的 a11y label／value 被外層 `children: .ignore` 吃掉 → 移到每幀重算的 Canvas 元素（它標 P2，會讓 I-16 與定格 UI 測試失敗，當 P1 修） | — |
| R2 | simplify ×2 | UI 測試的觀察窗 helper 重複 → `assertStaysFalse` 移到 `AppUITestCase` | — |
| R2 | codex | — | 兩條都指向本來就未追蹤、與本功能無關的檔（`docs/lrclib-missing-synced-lyrics.txt`、「 2.xcodeproj」）：駁回，從未進暫存區。提醒成立的部分：那份清單含曲庫資料，不得提交 |
| R3 | simplify ×1 | 無 P0／P1 | — |
| R3 | codex | 同一首強制重讀而曲長讀失敗時，VM 沿用已知值（原本歌詞會消失到下次輪詢） | — |

延後的 P2（不影響行為）：`titleKey` 只是轉呼叫 `styleLabelKey`；Mono 常數分在兩檔；`MonoStyle.plan` 的 exiting／current 兩段相似；`LyricsFXCanvas.draw` 的分組字典；`LyricsFXFrameSamples` 也編進 Release（只有 DEBUG 用）；`LyricsFXPreviewFixture` 手寫 Duration→秒（該檔與 UITests 共編）；兩處百分位公式不同；量測器的 utf16 位移迴圈、整體清快取、縮放視窗時字級連續變化造成快取抖動；monitor 的三個 per-track 變數可收成一個 struct；`LyricsFlowUITestMusic` 內兩處 `scenario == .lyricsFX`；每幀為 a11y 多算一次 `Moment`；`LyricsFXViewModel.setVisible` 沒有同值守衛。

評審後：1034 tests／116 suites，僅基線 7 斷言紅；`no_playback_gate.sh` 0；Python 333 OK；coverage 見 §8.3（重跑數字相同等級）；`build-for-testing` 成功。

### 8.5 使用者在場 #1（2026-10-06）
**UI 測試**（ABC 輸入法、使用者授權 Automation Mode）
- 首跑 13 條紅 3 條，都是真問題、已修（不是重跑變綠）：
  - `LyricsFlowUITests.testClickingPlayingCardOpensEditor`／`.testOnlyTheFrontFaceOfThePlayingCardIsClickable`：播放卡按鈕 AX frame 變 `{inf, inf}`。根因＝我在 `CoverFlowView` 外層掛了 `.accessibilityHidden(...)`（值是 false 也一樣）。拿掉後恢復；另加斷言確認透明度 0 的 Cover Flow 不在無障礙樹上。
  - `LyricsFXUITests.testAFrozenPreviewShowsTheLineAtThatSecond`：特效層的 value 是空字串。資料面先以單元測試排除（`aFrozenPreviewResolvesTheLineAtThatSecond` 綠），根因＝Canvas 上的 `accessibilityValue` 在 macOS 讀不到 → 改由一枚 1pt 透明文字承載當前行。
- 修後：`LyricsFXUITests` 4／4、`LyricsFlowUITests` 9／9、`ShellUITests` 的日文／繁中冷啟動 2／2、`BatchImportCoverFlowUITests` 1／1，共 16 條全綠。**未跑**：其餘 `ShellUITests`、`BatchUITests`、`BatchLiveUITests`、`CoverFlowUITests`（與本次改動無交集；A-10 已熔斷）。

**真機（真實 Music，使用者操作並回報）**
| 項目 | 結果 |
|---|---|
| 切到歌詞特效後字跟著走 | 過：看得到當前行大字＋下一行小灰字，會換到下一句。使用者指出時間和實際唱的對不上——預期內：曲庫沒有內嵌 LRC，用的是估算時間軸，C 段接 LRCLIB 才會準 |
| 暫停停住、恢復繼續 | 過 |
| 拖進度跟上 | 過：使用者體感「都在一兩秒內」。日誌（`log stream --level debug`，7 次重錨）：距上一筆讀數 2049–2125 ms、位置讀取 7–8 ms。Music 拖進度**不發** playerInfo 通知，靠 2 秒輪詢發現 → 最壞約 2.1 s、平均約 1 s。「典型 ≤ 2 s」成立；最壞值超出約 0.1 s，照實記錄 |
| 換歌換詞 | 過。前奏無字是設計（估算窗從曲長 6% 起，第一句前 2 s 才出預覽） |
| 切回 Cover Flow、再切回、退出重開保留 | 過：`defaults` 存 `RaisedLayerStyle = lyricsFX`，重開直接是歌詞畫面 |
- 實機每幀（真歌、39–68 字）：p50 0.46–0.59 ms、p95 0.67–0.75 ms。
- offset：未校準，維持 0（§6-4）。
- 量測方法的修正：重錨日誌是 debug 等級、系統不存檔，`log show` 事後讀不到；第一輪 5 次拖動因此沒留下數字，改開 `log stream` 請使用者再拖一輪。

**與本案無關、但實機時遇到的現象（未處理）**：重開 Debug 版後反覆跳「媒體與 Apple Music」權限框（`kTCCServiceMediaLibrary`），按許可仍再跳。觸發點是既有的 `Queue.dat`／`History.dat` 讀取，A2 沒有新增檔案存取；Debug 版為 ad-hoc 簽名。推測是系統記的許可綁在別的簽名上（未驗證）。交使用者決定是否另案。

### 8.6 最終閘門（T11 的修正之後重跑）
- 全量單元：**1035 tests／116 suites，僅基線 `CoverFlowStripRenderGeometry` 7 斷言紅**。
- `no_playback_gate.sh` 0；Python 333 OK；選擇器白名單綠；coverage_gate Services+Infra 96.1%，豁免 408／410。

## 9. 影響面、風險、回退
- 新檔：`Services/Config/RaisedLayerStyle.swift`、`Features/LyricsFX/{LyricsFXFrame,MonoStyle,TextMeasuring,LyricsFXView,LyricsFXFrameMeter}.swift`、`Features/LyricsFlow/RaisedLayerStyleToggle.swift`、對應測試、`UITests/LyricsFXUITests.swift`。需 `xcodegen generate`（逐檔 add；不碰既有未追蹤的「 2.xcodeproj」）。
- 改檔：`MusicControlling.swift`（事件＋`mergingLatestKnown`）、`NowPlayingMonitor.swift`、`EditorViewModel.swift`／`LyricsFlowModel.swift`（各 +1 no-op case）、`LyricsFXViewModel.swift`、`ConfigStore.swift`、`AppModel.swift`、`LyricsFlowHandleView.swift`、`LyricsFlowPageView.swift`、`LyricsFlowPresentation.swift`（把手純函式）、`RootView.swift`（傳參）、`AccessibilityID.swift`、`LyricsFlowUITestScenario.swift`／`LyricsFlowUITestMusic.swift`／`AppModel+LyricsFlowUITest.swift`、`make_xcstrings.py`＋`Localizable.xcstrings`、`ACCEPTANCE.md`。**不改** `MusicAppleEventsClient.swift`（豁免預算不動）、不改 Cover Flow 任何檔。
- AE 量：特效可見且有詞時每 2 s（暫停 6 s）一次位置讀取（4 AE，實測 p50 8 ms）；其餘情況與現在相同。
- 風險：
  - R1 把手由單一按鈕改成兩塊：既有 UITests 以 `lyricsFlowHandle` 點擊升降——identifier 留在升降按鈕上，點擊區縮小但仍佔大部分寬度。既有 UITests 在 T11 一併跑。
  - R2 `Canvas` 逐字 `resolve` 超預算 → §3.7 的處理順序與熔斷點。
  - R3 `ImageRenderer` 離屏畫 Canvas 在測試宿主失敗或字型未註冊 → 退路：改用 `NSHostingView`＋`bitmapImageRepForCachingDisplay`；再不行才用 XCUITest 截圖（需使用者在場）。同一問題 3 輪無進展即熔斷。
  - R4 風格切到特效後 Cover Flow 不可見 → 其預取停止；切回時由既有 `setVisible(true)` 路徑恢復（既有行為，不新增邏輯）。
  - R5 隱私：新增日誌只有幀耗時數字；歌詞不進日誌、不進 a11y identifier（a11y value 是當前行文字，僅供輔助技術）。
- 回退：偏好預設 `coverFlow`；整條分支未併 main。

## 10. 待拍板
- 無需使用者拍板的技術取捨已在 §1、§3 定案（評審後更新本節）。
- 已答（使用者 2026-10-06）：曲庫沒有內嵌 LRC 的歌 → offset 維持 0，校準延到 C 段。使用者在場 #1 只剩 UITests 授權與真機四項。

## 附錄 A　Codex 評審記錄
### A.0 P2 辯論 R1（gpt-5.6-terra，medium；2026-10-06）
| # | 論點 | 提出方 | 狀態 | 證據 |
|---|---|---|---|---|
| P2-1 | A2 內修；新事件 `metadataChanged`；不重發 `trackChanged` | 我 | 一致（Codex 補：revision +1、三處重置快取） | `NowPlayingMonitor.swift:217-223`、`LyricsFXViewModel.swift:108-112`、`EditorViewModel.swift:73-84` |
| P2-2 | 維持每次都讀 | 我 | 一致（Codex 補：4 ms 是單機量測值） | `MusicAppleEventsClient.swift:77-80`、A1 §8.5 |
| P2-3 | 不加 debounce；補測試 | 我 | 部分：Codex 勝一處措辭（不得宣稱所有時序恰 2 次） | `PlaybackPositionClock.swift:108-137` |
三條方向一致不是全採納的失職信號：三條都是我方帶證據的提案，Codex 逐條核了檔案行並各補一項修正，修正全數採納。

### A.1 計劃評審 R1（2026-10-06）
| # | 論點 | 提出方 | 狀態 | 處置／證據 |
|---|---|---|---|---|
| 1 | reduced 分支不隨可見性停 | Codex | Codex 勝 | 不可見不建 TimelineView；排程純函式＋單測（§3.4） |
| 2 | 量測撐不起「200 字 ≤ 2 ms」（不含光柵化、只看 p50、截斷後未必 200） | Codex | Codex 勝 | 主張降級、報 p50／p95／max＋實際 glyph 數、fixture 斷言恰 200、xctrace 試一次（§3.7） |
| 3 | mono 應改 run-level，逐字留到 B | Codex | **我勝（R2 Codex 撤回）** | 母計劃 `:162` 已定案 glyph-level `FramePlan`、`:168`「mono 先實測逐字 resolve」；使用者口令第 6 項 |
| 4 | 切到特效會改 Cover Flow 的可見／預取狀態 | Codex | 採納（措辭） | 列為已接受的行為改變（母計劃 §2.1 既定）；AppModel 測試釘住；不另寫 Cover Flow 內部測試 |
| 5 | 焦點觀察值沒含風格 | Codex | Codex 勝 | §3.3；UI 測試 |
| 6 | ImageRenderer 畫 Canvas 未經驗證 | Codex | 採納 | 先 spike（§3.6） |
| 7 | 把手拆分改了命中範圍 | Codex | 採納 | 記為產品變更、改 ACCEPTANCE、UI 測試 |
| 8 | 合併規則 | 我 | 我勝 | 改名 `mergingLatestKnown`；非有限 duration＝nil |
| 9 | A2 不必測 genre 變更／revision +1 | Codex | R2 Codex 自行反轉：既然合併規則支援非 nil 變更，VM 要有 genre A→B 的測試 | 已加（§5） |
| 10 | 空 LRC 時點的描述會誤導 | Codex | Codex 勝 | 尊重 `TimedLine.end`；精確測試 |
| 11 | draw anchor 未定義 | Codex | Codex 勝 | top-leading 契約；「基線在 h×0.42」改成行盒 top |

### A.2 計劃評審 R2（2026-10-06，整體確認）
- #3 撤回；補一處表述：依整列量測定位，不承諾與整列 shaping 完全一致（已寫進 §3.4）。
- 排程表：暫停時畫一次靜態、不留 periodic（已寫進 §3.4）。
- 順序：最終閘門要對應最後狀態 → T10 在 T11 前跑一次（不拿壞的東西佔使用者時間），T11 有修改就再跑一次。
- 最易失敗的一步：T6 離屏渲染。帳本無 open 項，定稿。
