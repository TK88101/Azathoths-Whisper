# H-02 缺陷 2／3 的 XCUITest 閘門 —— 實施計劃（v2）

- 日期：2026-09-11
- 上游：`docs/plans/2026-09-09-coverflow-h02.md`（交接檔；本計劃＝其 §5.1 的落地）
- 基線：HEAD `aad6a9b` ＋ 未提交 4 項（缺陷 1 修復、`CoverFlowStripRenderGeometryTests`、pbxproj、交接檔）
- 模式：**normal**（fatboyslim Phase 0）。依據：全程同步、GUI 測試需使用者在場授權；本階段完成條件是
  「新測試在回退版上**因正確原因**穩定紅」，而 loop 的 completion promise＝全綠，會把人往「修綠」推，正好違背交接要求。
- 狀態：**定稿（2026-09-11）**——Codex R1（12 條）＋ Opus 三視角（test-validity／harness-fidelity／scope-simplicity，共 30 條）→ v2；
  Codex R2（接受 10 條駁回、重提 SS2 勝出、新增 6 條）→ v2.1；Codex R3 窄範圍確認「可定稿開工」。逐條處置見 §12。

## 0. 複述

- **目標**＝在**真實 app 組裝**上建立能重現 H-02 缺陷 2（疊放）與缺陷 3（程式化居中少滾）的 XCUITest，
  作為第四次修復的前置閘門，閉合交接檔 §2 記錄的結構性盲區（三次「單測綠 → 真機錯」）。
- **完成標準**＝§6 閘門判定程序給出一個結論（通過／部分通過／不通過／不可建），且 V1–V10 每項都有本會話實跑的證據。
  使用者的硬門檻＝V3（M0 上穩定抓到缺陷）；V4（歷史變異回歸）與 V5（陽性對照）是本計劃為「不自欺」加的。
- **不做**＝任何 CoverFlowStrip／CoverFlowViewModel 修復（§5.2，閘門過後另立計劃）；DMG 重建；ACCEPTANCE 驗收基線變更；提交。

## 1. 目標與非目標

**目標**
- G1　DEBUG-only 的 UI 測試啟動模式：組裝真實 `RootView`＋`AppModel`＋`NowPlayingMonitor`＋`CoverFlowViewModel`＋`ArtworkService`，
  **唯一替換 `MusicControlling`**。
- G2　四條 XCUITest（交接檔 §5.1 的三條沿用命名 ＋ 一條初始值路徑），每條拆成**步驟**，每個落定步驟跑同一個「落定契約」——
  路徑 × 契約的矩陣，測試之間只換路徑、不換判據。
- G3　閘門：M0 偵測（V3）＋ 步驟級差異的歷史變異回歸（V4）＋ 陽性對照（V5）＋ 腳本化判定（§3.12）。
- G4　交接要點明令的最小文檔修正：ACCEPTANCE **H-05 降為「邏輯層通過、交互整合未驗」**（Codex 裁決 #4；不是基線變更，
  是撤回過度宣稱）；交接檔補註兩處已被實測推翻的敘述（§2）。

**非目標**
- N1　修復缺陷 2／3。閘門過後依新測試揭露的事實另立計劃、另走 Codex 評審。
- N2　`contentMargins` 方案的驗證（§5.2 候選，不是已知失敗版本）。
- N3　**過渡態**（捲動／減速中途）的疊放。XCUITest 無法確定性地在中途幀取樣。本計劃只驗落定態；
  修復計劃**必須**自帶過渡態的證偽手段（§3.10）。明示為殘餘盲區，不宣稱已覆蓋。
- N4　H-04／H-05 的交互整合測試（H-05 只做文檔降級）。
- N5　DMG 重建（對應版本要等修復後）。
- N6　ACCEPTANCE 的 ❌ 圖例、H-02 狀態改寫與拆條、M8 收口條件、核表命令——屬驗收基線變更，
  依 Codex 裁決 #3 須有日期與簽字的決策，移到 §5.3 收尾、閘門結論出來之後另立文檔任務。
- N7　視窗 resize 路徑（見 §12 TV1／TV3 駁回理由）。
- N8　在 `CoverFlowStrip` 內加滯後量測儀器（屬修復計劃；見 §12 TV1）。

## 2. 事實基線（本會話實查）

| 事實 | 出處 |
|---|---|
| xcodegen 2.46.0 在 scratch 副本重生成的 pbxproj 與當前工作區**逐字相同** → 新增檔案可安全走 `xcodegen generate`；2.46 支援 scheme 鍵 `captureScreenshotsAutomatically`／`systemAttachmentLifetime`；xcscheme 受 git 追蹤 | scratch 實測；`strings xcodegen`；`git ls-files` |
| Automation Mode 目前 disabled 且需使用者認證；09-08 曾跑通全套 UITests（17 條：1 skip、A-10 flaky 紅、其餘綠） | `automationmodetool`；前會話 `uitests.log` |
| **UI 語言靠 app 級覆寫**：app 網域 `AppLanguage=en`、`AppleLanguages=(en)`；**系統首選語言是 ja-JP**。刪掉 app 級覆寫（例如 M8 的 E-07 手測選 system）→ UI 變日文 → 所有以英文標籤定位的 UITest 失效 | `defaults read com.ibridgezhao.azathothswhisper`、`defaults read -g AppleLanguages` |
| 視窗尺寸由 SwiftUI 自動保存於 app 網域 `NSWindow Frame main = "5 267 1200 800 …"`；`-ApplePersistenceIgnoreState` 管不到它；DMG 版與 Debug 版同一 bundle ID，共寫此值 | 同上；`AppUITestCase.swift:49`；`project.yml:43` |
| 預設窗 1200×800 → `edgePadding`＝470pt ≈ 3.1 個 stride（260−109.2＝150.8），與「少滾 3 項」同量級 | `CoverFlowGeometry` 公式 |
| XCUITest API（Xcode 26.6 SDK 標頭）：`scrollByDeltaX:deltaY:` 在 macOS 可用，註釋「Scroll the view the specified **pixels**」，**無任何 phase／momentum 語義說明**；`typeKey:modifierFlags:` 標頭未保證自動取得焦點；`snapshot()` 可用但 frame 座標系原點未說明；`XCUIScreenshot` 在 macOS 回 `NSImage`，**是否需 Screen Recording 授權：未知**；`XCUICoordinate.scrollByDeltaX:` 為座標式備案 | `XCUIAutomation.framework/Headers/XCUIElement.h:121-129,260-311,338-364`、`XCUIScreenshot.h` |
| 交接檔 §5.1「Apple 明列 swipe*／press(forDuration:thenDragTo:) 為 iOS／Touch Bar 語義」**標頭不支持**（兩者在 macOS 標頭無 iOS-only 標註）。不影響結論（本計劃仍用唯一明文定義為「捲動」的 API），但該理由不得再被引用 | `XCUIElement.h:161-208` |
| `NSScrollViewWillStartLiveScrollNotification`（10.9+）註明「user initiated live scroll tracking (gesture scroll or scroller tracking)」；`ScrollPhase` 需 macOS 15；`contentMargins(for: .scrollContent)` macOS 14 可用 | `NSScrollView.h:144-158`、SwiftUI swiftinterface |
| Editor 在 `existingLyrics` 為空且 Editor tab 可見時會自動抓詞（打網路）→ 假 Music 必須回**非空**歌詞 | `EditorViewModel.swift:82-88` |
| `NoiseOverlay` 以 0.4 不透明度 overlay 混合疊在整窗之上 → 像素判定需區域平均＋雙候選分類 | `NoiseOverlay.swift:15-16` |
| 卡片的 AX 標識掛在「正面＋倒影」整體上：未旋轉外框推算 260×377 → 「正面朝人」判據**不能**沿用交接檔的「長寬比≈1」 | `CoverFlowItem.swift:12,65`、`CoverFlowView.swift:76-77`；S1 實測釘住 |
| 程式化居中的保護窗口是同步的：`centerIfAllowed` 在同一同步段 set→寫 centerID→clear `isCenteringProgrammatically`；之後 SwiftUI 的 binding 回寫走 `scrollPositionDidChange → userDidScroll` 並設 override（Codex 裁決 #4 的機制）→ 任何「偏移」都可能以**回寫漂移**形態出現（label 被靜默改成畫面中心那張，且永久保留：monitor 只在簽名變化時才再發事件） | `CoverFlowViewModel.swift:150-161,232-241`；`NowPlayingMonitor.swift:114` |
| **T0 單測基線（2026-09-11 11:30）**：307 tests／35 suites，6 issues **全在** `edgeItemsAlsoReachCenter`（args 1,4,5,6,7,8 紅；0 過），落點恰為 max(0, 請求−3)；**`runtimeCenterChangeReachesTarget` 3/3 綠**（0→1、0→4、0→8，含末項） | `scratchpad/unit-T0.log` |
| ⇒ **交接檔 §4「RUNTIME 當前亦紅」與實測不符**。少滾 3 項只出在「視圖**帶著預設 centerID 被建立**」的初始值路徑。真實 app 裡對應的使用者操作＝**切走再切回 Cover Flow tab**（`RootView.content` 依 tab 重建 `CoverFlowView`，`centerID` 留在 VM）；首次載入屬哪條路徑**未知**（且受 fixture 延遲影響，見 §3.2） | `RootView.swift:108-121`、`CoverFlowViewModel.swift:210-218`、`AppModel.swift:205-225` |
| **交接檔 §2 的歸因需更正**：真機上裝過的只有兩個**疊加**構建——`a823b743`＝嘗試 1＋2；`98e453f2`＝嘗試 1＋3。**嘗試 1 從未單獨上真機**；「右邊那張壓住中心」是當時助手看疊加構建截圖的推斷歸因。contentMargins 只跑過 EDGE 單測（失敗表與基線逐字節相同），從未上真機 | 前會話 transcript idx 2409／2415／2429／2450／2633／2639；`CDHASH4`／`CDHASH5` |
| 前會話 attempt 2 的實測註記：「用真的 scrollWheel 事件捲動後，anchor 0 與 0.5 都回寫**視覺上居中的那張**」；與其後「真手滑回寫偏左約 3 格」的**推斷**診斷互相矛盾——前者是 app 內合成滾輪事件實測，後者是真機觸控板截圖推斷。推測：差別在 phase／慣性 | 前會話 `coverflow-anchor-fix.patch:34-36`；`M3-attempt1plus3.swift:97-102` |
| 基準雜湊（V2／V8 用）：`CoverFlowStrip.swift` md5 `a9ac2902fac2646d0899157ee231a1e4`；`project.pbxproj` md5 `a06b090908014b558d4cf1abaf86879f`（皆 T1 前） | 本會話 `md5` |

## 3. 設計

### 3.1 測試啟動模式（DEBUG-only）

- 旗標：`AZW_COVERFLOW_UI_TEST=1`（常數定義在共用檔，§3.3），**只在 `#if DEBUG` 內讀取**（同 `unitTestHostFlag` 先例，
  `AppModel.swift:123-129`）。Release 編譯不到。
- 組裝：`AppModel.live()` 開頭的 `#if DEBUG` 分支 → `makeCoverFlowUITestModel()`：
  - `ConfigStore(secrets: EphemeralSecretStore())`、**不跑** legacy 遷移——不碰 Keychain（避開 M6 A1 授權框），token 為空
  - `CoverFlowUITestMusic`；`NowPlayingMonitor(music:)` 照用真實 3s 輪詢；`artworkDiskDirectory: nil`（純記憶體）
  - HTTP client／validator 照用真實型別（假 Music 回非空歌詞 → Editor 不自動抓詞 → 零網路）
  - 若 trace 路徑變數存在 → 啟動 §3.5 的軌跡旁路

### 3.2 假 Music：`CoverFlowUITestMusic`（DEBUG-only，Sendable struct）

- 20 首 `T00…T19`，同一 artist／album，disc 1、track 1…20，lyrics 非空；`currentTrack()` 恆回 **T10**（固定起點）
- `playerState()`→`.playing`；`currentLyrics()`→非空；`setLyrics`→`false`；`albumTracks` 只對 fixture 的 artist／album 回 20 首，其餘 `[]`
- **`albumTracks` 帶固定延遲，預設 400ms**（TV5／HF2）：真實 app 的 albumTracks 走串行 AE（20 首約 140 次往返），
  必然「先掛空視圖、後填資料」；零延遲會讓首次載入走哪條 SwiftUI 路徑取決於 run loop 次序競態。決定路徑的是**次序**，
  不是精確毫秒數——任何遠大於一幀的延遲都保證「先掛空」。環境變數可覆寫（閘門另跑一組 0ms 作資訊對照，只對 T3）
- `artworkData(persistentID:)`→即時生成 512×512 單色 PNG（色板 §3.3），未知 ID→`nil`；不進 repo 二進位 fixture

### 3.3 共用檔（app DEBUG 與 UITests 兩個 target 同編）

`App/UITestSupport/CoverFlowUITestFixture.swift`（常數＋色板）與 `App/UITestSupport/CoverFlowGateLogic.swift`（純函數）。
project.yml 在 UITests target 追加這兩個檔。**單一來源**：旗標名、trace 變數名、延遲變數名、ID 格式、播放索引、色板、
判定純邏輯都只有一份（CX9：不重演 `AZW_UNIT_TEST_HOST` 雙寫再用測試釘的模式）。

- 色板：`hue = ((i × 7) mod 20) / 20`，`s = 0.85`，`v = 0.95` → 相鄰索引色相差 126°、隔一差 108°；
  「邊緣辨識色」落地解讀＝整面單色（重疊區必落在卡片邊緣）
- `CoverFlowGateLogic`（純、無 XCTest 依賴，**先 TDD**，SS8）：`classify`（兩候選＋背景三分類）、`isFacing`、
  C2 參考點與交疊點幾何、stride 分桶、落定判定（序列穩定）、C4 軌跡判定（反向／拉回）、`SIG{}` 格式化

### 3.4 AX 探針（產品碼最小改動）

- `CoverFlowView.strip`：`.accessibilityIdentifier("coverflow-strip")`；若 S1 發現容器標識覆蓋子項標識，才補 `.accessibilityElement(children: .contain)`
- `centerLabel`：`.accessibilityValue(model.centerID ?? "")`，**包在 `#if DEBUG`**（Release 曝光會讓 VoiceOver 讀出 persistentID 原串）
- 卡片：沿用 `coverflow-item-<ID>`；若 S1 發現它沒以「單一元素＋變換後外框」曝光，才於 `CoverFlowItemContainer` 加 `.accessibilityElement(children: .ignore)`

### 3.5 軌跡旁路（trace，DEBUG-only，僅測試模式）

**為何需要**（CX3）：`scrollByDeltaX:` 是阻塞呼叫，XCUITest 只能在它返回**之後**取樣；返回前發生的拉回／反轉看不到。

- 內容（三種行，同一檔、同一序號空間）：
  - `bind`：`CoverFlowView` 的 scrollPosition binding setter 收到的 SwiftUI **原始回寫值**（未經 VM 過濾）
  - `event`：app 內 `NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)`（**本行程局部監聽，不是全域 hook**）記錄
    `phase`、`momentumPhase`、`hasPreciseScrollingDeltas`、`scrollingDeltaX`（HF8）——直接量出合成事件是否帶 phase／慣性
  - `live`：`NSScrollView` 的 willStart／didEnd live scroll 通知
- **生命週期**（R2 Codex）：trace session 是**行程級單例**，只在 `makeCoverFlowUITestModel()` 裡依環境變數建立一次；
  局部事件監聽與 live-scroll 觀察者也只在那裡安裝一次——`CoverFlowView` 切 tab 重建不會重複安裝、不會重複記錄。
  binding 鉤子只呼叫單例的 `record`。trace 路徑由 runner **每次啟動給一個新檔**，檔首寫一行 header：
  `pid`、`Bundle.main.bundleURL.path`、可執行檔大小與修改時間（兼作 §3.13 的二進位身分證據）
- **寫入協議**（HF10；R2 Codex 的 drain 問題）：在**主執行緒**以 `O_APPEND` 的 `write(2)` **同步**追加一行、**不 fsync**。
  寫進 page cache 是微秒級，相對 16ms 的幀時間與 100ms 的 AX 輪詢可忽略；換來的是**沒有待寫佇列**——
  runner 讀到的就是 app 至今記下的全部，不存在「500ms 沒新行 ≠ 已落盤」的邊界問題。
  （這推翻了 R1 對 SS8「交背景串行佇列」的採納：背景佇列會製造一個無法由 runner 驗證的 drain 邊界，代價大於它省下的微秒）
- 短寫或 `write(2)` 失敗 → 該行寫入失敗計數＋1 並在 header 之後補記一行錯誤；runner 見到任何寫入錯誤即判 `[PROBE-TRACE]`（R3 Codex）
- 讀取協議：runner **不截斷檔案**，每段開始時記下位元組長度（水位），落定後只讀水位之後的行；
  S6 驗證序號連續、無 NUL、時間戳單調、header 正確
- 選檔案而非 AX 元素：軌跡若掛成 `@State`／`@Observable`，每次回寫都會觸發 body 重算，觀測本身就可能改變捲動行為

### 3.6 測量原語：`UITests/Support/CoverFlowProbe.swift`

- `readState()`：對 window 做**一次** `snapshot()`（原子），取 strip frame、label value、全部 `coverflow-item-*` frame
- `readStable()`（TV6）：snapshot → 截圖 → snapshot，兩次 frame 相同才採用；最多重試 3 次，否則 `[PROBE-UNSTABLE]`
- `waitForStableCenter(timeout: 10s)`：每 100ms 讀一次，(label, 幾何中心卡 ID, 其 frame 取 0.5pt) 連續 4 次相同＝落定。
  逾時時分流（TV4）：AX 可讀且 frame 仍在變 → **產品碼** `SIG{…|C6-NEVER-SETTLES}`；AX 讀不到 → `[PROBE-AX]`
- **捲動段內暫停 AX 輪詢**（HF9）：事件發送 → 等 trace 靜止（500ms 無新行）→ 才開始落定輪詢，避免跨行程 AX 查詢佔用 app 主執行緒、改變時序
- `isFacing(card)`：寬 ∈ 260 ×[0.97, 1.03] 且 高／寬 與 S1 實測的未旋轉基準差 < 0.05
- 取樣：`app.windows.firstMatch.screenshot()`，5×5 像素平均，`px = (x − window.minX) × scale`，轉 sRGB；
  `classify` 三分類：候選 A／候選 B／背景（近黑）；三者皆超閾值 → 不確定。**閾值在 S2 校準後寫死進 §11，閘門期間不得再調**

### 3.7 落定契約（每個落定步驟都跑）與簽名

`assertSettledContract(step:)`：**先量完全部條款、附報告（文字＋裁切到視窗的截圖），再逐條 `XCTFail`**
（區段內暫設 `continueAfterFailure = true`，同一步驟的所有違反都進 xcresult）。
每個步驟另輸出一行 `GATE{<test.step>|PASS}` 或 `GATE{<test.step>|FAIL|<SIG 碼清單>}`（stdout ＋ 文字附件），供 §3.12 腳本逐步驟判定。

**G（幾何中心卡）**＝外框 midX 距 strip.midX 最近的卡；與 label 無關，所以 C2 量的是「正對觀者那張有沒有被壓住」本身。

| 條款 | 內容 | 產品簽名（計入閘門） |
|---|---|---|
| C0 佈局 | G 非端點時，兩側鄰張位置在**像素上**是卡面（非背景）；AX 缺鄰張但像素是卡面 → `[PROBE-AX-CULL]` | `C0-BLANK-SIDE` |
| C1 居中 | label 所指的卡存在、`abs(midX − strip.midX) ≤ 3pt`、`isFacing` | `C1-OFFSET`（附 `label`／`centered`／`strides`）／`C1-NOT-FACING`／`C1-LABEL-CARD-MISSING` |
| C2 疊放 | 前提 `isFacing(G)`（否則記 `C2-NA` 不判）。對每個已渲染鄰張 N：先取兩個**無遮擋參考點**各自分類為本色（G：G.midX；N：G 外緣與 N±1 內緣之間的中點），再取兩外框水平交集中點（y＝G.minY＋G.width/2）→ 必須為 G。參考點是背景色 → 產品 `C0-BLANK-CARD`；參考點是別張的色 → `[PROBE-REF]`；交疊點是背景、**或兩外框水平交集為空**（負間距下相鄰卡必然交疊，不交＝佈局錯）→ 產品 `C2-GAP`（R2 Codex） | `C2-STACK`（附 `G`／`over`／`side`）／`C2-GAP`／`C0-BLANK-CARD` |
| C3 目標身分（TV2） | 落定後 label ＝ 本步驟的命令目標（各步驟的 `want` 見 §3.8；取焦點那一步用相對目標「按前 label＋1」） | `C3-TARGET-MISS`（附 `want`／`got`） |
| C4 回寫（僅 T1 捲動步驟） | 以 trace 的 `bind` 序列判：① 位移後回寫值有變；② 一次捲動內回寫值的索引**不改變方向**（`viewAligned` 自然吸附選最近項，不會使回寫值反向）；③ 落定後 1.5s 內不再變 | `C4-NO-WRITEBACK`／`C4-REVERSAL`（附序列）／`C4-SNAPBACK`（附 from／to） |
| C5 重建保持（僅 T4.s2） | 切 tab 往返後 label 不得改變 | `C5-DRIFT`（附 before／after） |
| C6 收斂 | 見 `waitForStableCenter` 分流 | `C6-NEVER-SETTLES` |

**簽名格式**（CX7）：`SIG{<test.step>|<碼>|<離散欄位…>}`，例 `SIG{T4.s2|C1-OFFSET|label=T19|centered=T16|strides=+3}`。
只含離散欄位；浮點量（dx、長寬比、色距）只進附件報告。

**探針碼**（不計入閘門；**每個都要附一個與產品行為無關的健康證據才成立**，TV4）：
`[PROBE-FOCUS]`（只定義為「按鍵後 label 完全沒變」；變了但不是＋1 → 產品 `C3-TARGET-MISS`）、`[PROBE-AX]`、`[PROBE-UNSTABLE]`、
`[PROBE-REF]`、`[PROBE-AX-CULL]`、`[PROBE-WINDOW]`（視窗非 1200×800）、`[PROBE-FOREGROUND]`（送事件前 app 不在前台 → 中止，R2）、
`[PROBE-WRONG-BINARY]`（§3.13）、`[PROBE-TRACE]`（軌跡讀不到／序號斷／有 NUL）。腳本層另有 `UNTAGGED`（§3.12）。

### 3.8 四條測試（步驟化）：`UITests/CoverFlowUITests.swift`

共同前置：`launch(language: "en", environment: [旗標, trace 路徑, 延遲])`（HF4、HF11）→ 二進位身分斷言（§3.13）→
`waitForMainUI` → 斷言視窗 1200×800（否則 `[PROBE-WINDOW]`），記錄實際窗寬 → 點 `COVER FLOW` → 等 strip 出現且 label value 非空。
**取焦點一律點擊 label 區**（在 ScrollView 之外，TV8）：點卡片可能把焦點交給 ScrollView，方向鍵就改走原生鍵盤捲動＋回寫（觀測路徑），不是 `.onKeyPress → stepCenter`。

| 步驟 | 操作 | C3 的 want | 備註 |
|---|---|---|---|
| **T1** `testExternalScrollWritesBackAndDoesNotSnapBack`（觀測路徑） | | | |
| T1.s1 | 點 label、按 → 一次，落定 | 按前 label＋1 | 起點前置，**是契約步驟，照常判決**（CX4）；目的是讓量測段從「label＝畫面」且可重現的狀態出發 |
| T1.s2 | 記水位 → 朝一向 `scroll(byDeltaX:)` 約 2 stride → trace 靜止 → 落定 | —（無命令目標） | C4 ＋ C0／C1／C2 |
| T1.s3 | 同上，反向 | — | 同上 |
| **T2** `testKeyboardCommandsCanCenterBothEndpoints`（命令路徑：鍵盤） | | | |
| T2.s1 | 點 label、按 → 一次，落定 | 按前 label＋1 | **V5 的主要非端點陽性對照**（TV7，不依賴 S4） |
| T2.s2 | ← ×25，落定 | T00 | 端點 |
| T2.s3 | → ×25，落定 | T19 | 端點；「末 3 項不可達」的直接檢查 |
| **T3** `testCenteredCardPaintsAboveBothNeighbours`（首次載入自動居中） | | | |
| T3.s1 | 前置後直接落定 | **T10**（fixture 播放索引） | 絕對目標，抓首次載入的漂移形態 |
| **T4** `testReenteringTabKeepsCenteredCardCentered`（初始值路徑：視圖重建） | | | |
| T4.s1 | 點 label、→ ×25，落定 | T19 | 重建前狀態 |
| T4.s2 | 點 `EDITOR` → 點 `COVER FLOW`，落定 | T19 | C5 ＋ 契約；「重建前對、重建後錯」＝缺陷定位在初始值路徑本身 |

### 3.9 預先登記（唯一來源；T7 首跑後把「未知」格凍結成定值，T8 前不得再改）

推算依據：T0 基線（初始值路徑紅、運行時路徑綠）、zIndex 讀 centerID、回寫漂移機制（§2）、attempt 2 實測註記（合成滾輪下觀測路徑對 anchor 不敏感）。
**標「推測」的格都只是線索**（CX6：T0 是 9 項、一次指派；本計劃是 20 項、連續步進、真實組裝，狀態轉移不同）。

| 步驟 | **M0 回退版** | **M2 嘗試1＋2**（閘門） | **M3 嘗試1＋3**（閘門） | M1 嘗試1（資訊性） |
|---|---|---|---|---|
| T1.s1 | PASS（推測） | PASS（推測） | PASS（推測） | PASS（推測） |
| T1.s2／s3 | PASS（推測） | **推測存活（PASS）**：合成滾輪下觀測路徑對 anchor 不敏感（實測註記） | **推測存活（PASS）**：無慣性時 `scrollTo(X)` 只是重定位到已觀測的 X | PASS（推測） |
| T2.s1 | PASS（推測） | PASS（推測，RUNTIME 當時全綠） | PASS（推測） | PASS（推測） |
| T2.s2 | PASS（推測） | PASS（推測） | PASS（推測） | PASS（推測） |
| T2.s3 | PASS（推測） | PASS（推測） | PASS（推測） | PASS（推測） |
| T3.s1 | **未知**，三種形態皆登記：①偏移 → `C1-OFFSET(label=T10,centered=T07,strides=+3)`＋`C2-STACK(G=T07,over=T08,side=R)`；②漂移 → `C3-TARGET-MISS(want=T10,got=T07)`；③運行時式 → PASS | 未知（`.leading` 修好初始值路徑 → 可能 PASS） | 未知（`.task` 補初始路徑；可能經漂移後 PASS 或 `C3`） | 未知；偏移形態下推測 `C1-OFFSET` 但 **C2 過**（疊放讀幾何） |
| T4.s1 | PASS（推測） | PASS（推測） | PASS（推測） | PASS（推測） |
| T4.s2 | **紅（推測，依 EDGE 6/7 紅）**，兩種形態：①偏移 → `C1-OFFSET(strides=+3)`＋`C2-STACK(side=R)`；②漂移 → `C5-DRIFT(before=T19,after=T16)` | 未知 | 未知（`.task` 可能在漂移後才以已漂移的 centerID 捲動 → `C5-DRIFT`） | 推測同 M0 形態但 C2 過 |

- **M2／M3 在合成捲動下推測存活**——這是按機制推演的誠實預期（TV3、SS2）。若屬實，V4「未殺」；
  先看 trace 的 `event` 行：若合成事件**沒有** phase／momentum，即證明 XCUITest 的合成捲動觸發不到兩個變異的真機故障機制 → §3.11 的 S7 升級路徑
- 若 M0 上 T1／T2 某步驟紅：先解釋（代表對應路徑另有缺陷，屬 §5.2 的新事實），不影響缺陷 3 的判定

### 3.10 缺陷 2 的閘門語義（誠實範圍）

- 在 M0 的落定態，「鄰張壓住中心」**只**出現在 centerID ≠ 畫面中心的時候，也就是缺陷 3 的**偏移**形態（zIndex 讀 centerID）；
  若缺陷 3 表現為**漂移**形態（label 被改成畫面中心），zIndex 反而正確，落定態**看不到**缺陷 2（TV1、SS1）。
  缺陷 2 的另一半——捲動中途 zIndex 滯後——屬過渡態（N3）
- 因此本計劃「抓到缺陷 2」的精確含義＝**在落定態抓到偏移誘發的疊放症狀（`C2-STACK`）**，不是抓到缺陷 2 的全部機制。閘門報告必須明寫：
  「**C2 綠 ≠ 缺陷 2 已修**」
- 分支（預先登記）：
  - M0 某步驟 `C2-STACK` 10/10 → 缺陷 2 的落定症狀已抓到
  - M0 只出現漂移形態、全無 `C2-STACK` → 記「**缺陷 2 在 M0 落定態不可重現**」→ 依使用者規則，閘門對缺陷 2 **不算通過**，
    帶選項上報使用者裁決：(a) 接受由修復計劃的真機驗證承擔缺陷 2；(b) 另開 spike 找不依賴程式化偏移的落定失配路徑（例如 resize，須先處理共享窗框設定的副作用）；
    (c) 修復計劃內建滯後量測儀器。**不得為了製造紅燈去改探針或路徑**（§6 護欄）
- 無論哪個分支，修復計劃的**強制 DoD**：本計劃四條測試 `-test-iterations 20` 全綠 ＋ 真實 20 張封面手滑（交接檔 §5.1 末條）＋ 一個能證偽過渡態疊放的手段

### 3.11 歷史 Strip 變異回歸

**定性**（CX8）：把**真機失敗構建裡的 `CoverFlowStrip.swift`** 移植進當前 harness 的變異回歸，**不是**重建當時的構建
（當時完整 tree 未保存）。價值：這兩份 Strip 曾騙過單測、被真機打回；抓不到它們＝盲區仍在。也**不是**重試修法——三條死路不因此重新進入候選。

| 代號 | 來源（保全副本：`~/Developer/bjork-h02-gate/mutants/`；原檔在前會話 scratchpad） | md5 | 內容標記 | 真機證據 | 定位 |
|---|---|---|---|---|---|
| M2 | `M2-attempt1plus2.swift`（原 `CoverFlowStrip.before-warnfix.swift`） | `57da040c…` | visualCenterIndex＋`anchor: .leading` | 構建 `a823b743`；使用者「向左滑動時沒問題 向右滑動 還是有蓋住的」；當時診斷：右半屏空白、封面擠左、標籤與畫面不符 | **閘門** |
| M3 | `M3-attempt1plus3.swift`（原 `CoverFlowStrip.failed-attempt.swift`） | `48687466…` | visualCenterIndex＋`ScrollViewReader.scrollTo`＋`.task` | 構建 `98e453f2`；使用者「完全沒好」；當時診斷：封面偏到一側、位置錯亂 | **閘門** |
| M1 | `M1-attempt1.swift`（原 `CoverFlowStrip.orig.swift`） | `f5ef5967…` | 只有 visualCenterIndex | 無（從未單獨上真機） | 資訊性 |

- M2 與部署源碼的唯一差別是其後一次純機械的 Swift 6 警告修正（`space` 內聯），前會話以 EDGE 結果前後逐位相同佐證無邏輯差
- 三檔都含缺陷 1 修復；只替換 `CoverFlowStrip.swift`。每次變異運行記錄：基底 commit、scratch 副本全部源檔的雜湊清單、變異檔相對 M0 的 diff、被測 app 的 CDHash
- 構建位置：**repo 之外**的 scratch 副本（`rsync` → 替換 → 獨立 `-derivedDataPath`）；結束後 `lsregister -u` 該 app 並刪 scratch DerivedData（HF5）
- **殺死判據＝步驟級差異，允許集合在任何變異運行前寫死**（CX2＋SS2 調和；R2 Codex 重提 SS2 勝出後定案）：
  存在某個 (test.step)，**M0 上該步驟 10/10 PASS**，而變異上該步驟 3/3 FAIL，且三次的正規化簽名集合相同。
  **允許殺死的簽名類別＝全部產品碼**（C0-BLANK-SIDE、C0-BLANK-CARD、C1-*、C2-*、C3-*、C4-*、C5-*、C6-*），對兩個變異一視同仁——
  不再按變異各列子集，因此 §3.9 的「未知」格不影響判定，也沒有任何「看了結果再決定哪些算殺死」的空間。
  M0 上 FAIL（或十次不一致）的步驟**一律不可作殺死步驟**；任一 PROBE／UNTAGGED → 該次變異運行無效。
  「簽名與真機症狀是否相符」只作報告註記，**不是**殺死條件（真機症狀描述如「完全沒好」「位置錯亂」不可證偽，拿來當條件等於開後門）
- **V4 的權重由使用者在閘門時決定**（SS2）：使用者的硬門檻只有 M0；V4 是本計劃加的。V4 未殺 → 閘門「部分通過」，連同 trace 證據上報，
  由使用者決定「帶補償控制（真機手滑）進修復」或「先做 S7」
- **S7 升級路徑**（條件式，**開始前須先向使用者報告並取得同意**）：當 M2／M3 存活且 trace 顯示合成事件無 phase／momentum 時，
  注入帶 phase／momentum 的捲動序列，候選兩種：(a) 測試模式內的 app 自注入（DEBUG 鉤子觸發，以 `NSApp.postEvent` 送出由
  `CGEventCreateScrollWheelEvent`＋phase／momentum 欄位轉成的 `NSEvent`；本行程內，不需任何權限）；
  (b) runner 以 `CGEventPostToPid` 定界投遞到被測 app 的 PID（可能需要輔助使用權限 → 使用者決定）。
  成立判據（R2 Codex 提高）＝trace 出現 `momentumPhase≠0` 的事件、伴隨 willStart live scroll 通知，**且**在 M0 上重現已知的
  「捲動 → 回寫 → 落定後 label＝畫面中心」狀態轉移；只滿足前兩項 → 僅稱「合成事件實驗」，**不得**用於 V4 殺死。
  兩者皆 PID／行程定界，符合 memory `no-global-keystrokes-in-gui-tests`

### 3.12 閘門判定腳本：`AzathothsWhisper/Scripts/h02_gate_eval.py`（HF1、SS4）

- 輸入：xcodebuild 日誌 ＋ xcresult。按（測試 × 迭代 × 步驟）輸出一格一結果：PASS／FAIL＋`SIG` 集合／PROBE／INVALID
- 規則：
  - 測試狀態取自 xcresult（Passed／Failed），**綠基準＝狀態 Passed 且各步驟 `GATE{…|PASS}`**，不是「沒數到簽名」
  - Failed 的每條失敗訊息必須以 `SIG{` 或 `[PROBE-` 開頭，否則記 `UNTAGGED` → 該迭代作廢、本輪判「無效運行」
    （`waitForMainUI` 斷言、執行逾時、事件合成錯誤都屬此類）
  - 核對每個測試的迭代數確實是 10（或 3）
  - 提供 V3／V4／V5 的判定子命令（M0 對變異的步驟級差異）
- 測試：`Scripts/test_h02_gate_eval.py`（unittest，三類夾具：全過、帶 SIG 失敗、無標籤失敗）先 RED 後 GREEN；
  T7 首跑時再以**真實 xcresult** 做 dry-run：含「同一步驟多個 SIG」與故意失敗兩種，確認解析的是 failure message 欄位本身、
  而不是 XCTest 包裝後的人類可讀文字（R2 Codex）；該 xcresult 留作腳本測試的真實夾具
- 舊 §10 的 `grep` 命令作廢
- **R4 修訂（2026-09-11，Phase 1 快速複審定稿，§12 R4）**——判定器語義以此為準：
  - **唯一的 `table_valid`**（V3／V4／V5 共用；V4 的 baseline 與 mutant 各自須成立）：T1–T4 四條測試全部存在；每條恰好 N 次
    （xcresult 迭代數與日誌 started 配對數皆 N）；每次迭代每個預期步驟恰有一條 GATE（無 MISSING、無重複）；
    每次迭代 `xc_result ∈ {Passed, Failed}`，且 Passed ⇔ 全部 GATE 為 PASS、Failed ⇔ 至少一條 GATE 為 FAIL；
    `errors == []`；零 PROBE／UNTAGGED／invalid iteration
  - **V5**、**V3**、**結論**的機械語義見 §6 R4 條文；`verdict` 子命令依 §6 R4-C 的優先序輸出唯一結論，V4 權重留給使用者
  - 失敗文字解析：真實形態是 `<檔>.swift:<行>: failed - <XCTFail 訊息>`；剝前綴後只再剝一次 XCTFail 的 `failed - `，
    其他斷言巨集的包裝不剝（§11「判定腳本缺陷」）
  - **R4-F（2026-09-12 R5）**：`evaluate_v3` 另回傳 `frozen_conformity_ok`／`frozen_conformity_reasons`／`frozen_deviations`（§6 R4-F），`verdict` 把不相符列入不可判定；`v3`／`verdict` 子命令印出三欄
  - **R4 補正（2026-09-11 三視角對抗核查，§11）**：① GATE 與 SIG 的交叉核對比**碼集合**（產出端 GATE 碼去重、
    每個 finding 一條 SIG，故兩側同碼合法）；② GATE／SIG 的 `<test>.` 前綴必須等於本測試，否則記 error 且不頂替該步驟
    （不得掩蓋 MISSING）；③ 日誌 `started` 必須與 `passed/failed` 成對，數目不符記 error（截斷的運行不得判有效）；
    ④ `GATE{…|FAIL|}`（FAIL 但無碼）記 error——簽名為空不得成為「殺死」

### 3.13 運行配置（S 階段起的所有 UITest 運行一致，M0 與變異同一配置）

- `-enableCodeCoverage NO`、`SWIFT_OPTIMIZATION_LEVEL=-O`（保留 DEBUG 編譯條件，測試模式照常可用）——真機失敗構建是 Release，
  Debug `-Onone`＋覆蓋率插樁會改變時序，而 M3 的故障本身就是時序競態（HF9）
- scheme test action 關閉系統自動截圖（project.yml `captureScreenshotsAutomatically: false`；HF6）：閘門預期大量紅燈，
  而系統截圖範圍可能是全螢幕（推測），使用者此時在場授權、螢幕上是使用者自己的畫面。改由測試碼只附**裁切到視窗**的截圖
- **二進位身分**（HF5；R2 Codex 要求先 spike）：主證據＝trace header 由 app 自報的 `bundleURL` 必須位於本輪預期的 Products 目錄
  （經 `TEST_RUNNER_AZW_EXPECTED_APP_DIR` 轉發給 runner）——它證明「寫這份 trace 的就是這個構建」，且不依賴 runner 能否列舉行程；
  輔證＝runner 以 `NSRunningApplication` 斷言同 bundle ID **恰好一個**實例。可行性由 **S0** 在 M0 與一個 scratch 構建上各驗一次；
  不符 → `[PROBE-WRONG-BINARY]`。只加在新測試類裡，**不改** `AppUITestCase.terminateStaleInstances` 的既有行為
- 語言：`launch(language: "en")`（argument domain 覆蓋 app 級設定；§2）
- 持久化（HF12）：變異源、雜湊清單、`unit-T0.xcresult`、閘門 xcresult 與日誌拷到 `~/Developer/bjork-h02-gate/`（非 iCloud、非 repo）；每次使用前比對 md5

## 4. Spike（S1–S7）：先驗測量原語，再寫正式斷言

在真實 harness 上以一條臨時 `testProbeDump`（只輸出數據、不斷言）執行，結果寫回 §11；該臨時測試**不進交付物**。
S 階段結束時凍結全部閾值（§6 護欄）。

| # | 問題 | 成立判據 | 不成立時的預登記備案 |
|---|---|---|---|
| S0 | 二進位身分（§3.13）：trace header 自報路徑可讀且等於預期 Products 目錄？runner 能否列舉 `NSRunningApplication`？在 M0 與一個 scratch 構建上各驗一次 | 兩種構建都能正確區分 | header 可用而列舉不可用 → 只用 header；header 不可用 → 變異回歸不可建（無法證明跑的是哪個構建），上報 |
| S1 | 卡片是否以單一元素＋變換後外框曝光？未旋轉基準寬高？ | 中心卡寬≈260、兩側外框寬縮高增 | 加 `.accessibilityElement(children: .ignore)` 後重測；仍不成立 → 閘門「不可建」上報 |
| S2 | `window.screenshot()` 是否含真實窗內容？座標換算正確？分類閾值？ | 在 G 中心取樣分類命中 G；在已知背景點分類為背景 | 改 `XCUIScreen.main.screenshot()` 並**在記憶體內裁到視窗後才用**；仍不成立 → C2 不可建，上報 |
| S3 | 點 label 後方向鍵是否送達 `.onKeyPress`？是否誤走原生鍵盤捲動？ | 按一次 → label＋1；判別式：從 label≠畫面的狀態按一次，`stepCenter` 得 label＋1、原生捲動得畫面＋1 | 仍不行 → 屬**真實產品發現**（H-09 焦點），上報 |
| S4 | `scroll(byDeltaX:)` 能否移動條帶、單位與符號、是否吸附與回寫？事件性質？單次 snapshot 耗時？ | 條帶位移、`bind` 行出現；記錄 `event` 行的 phase／momentum | 改 `XCUICoordinate.scroll(byDeltaX:deltaY:)`；仍不行 → T1 不可建，上報。**不吸附**（停在 stride 之間）→ T1 的 C1 改判「label 指向最近中心卡」，「合成捲動不吸附」作為獨立觀察上報，不混入閘門 |
| S5 | `.accessibilityValue` 能否被 `XCUIElement.value` 讀到？ | 讀到 `T10` | 退回從 label 文字解析 ID（fixture 標題含 ID） |
| S6 | runner 能否讀到 app 追加寫入的 trace？協議正確？ | 序號連續、無 NUL、時間戳單調、水位讀取正確 | 改 app 暫存目錄＋絕對路徑；仍不行 → C4 退回只用落定後 label 序列，V4 明示「M3 殺死判據弱化」 |
| S7（條件式） | 見 §3.11 | 見 §3.11 | 需額外權限或不可行 → V4 對該變異記「XCUITest 能力外」，上報 |

## 5. 任務清單（每項帶 DoD）

| # | 任務 | DoD |
|---|---|---|
| T0 | 基線：單測全量（**已完成**，§11）；既有 UITests 一次（需使用者在場授權）；基準雜湊（§2 末列，已記）；持久化拷貝（§3.13） | §11 有兩份基線紅燈清單；`~/Developer/bjork-h02-gate/` 內 md5 與原檔一致 |
| T1 | 共用檔 fixture＋`CoverFlowGateLogic`（TDD：先寫 `CoverFlowGateLogicTests`／`CoverFlowUITestFixtureTests` → RED → 實作 → GREEN） | 新單測綠；色板相鄰色距 ≥ 閾值；分類／落定／C4 軌跡判定／SIG 格式各有正反例 |
| T2 | 假 Music（含延遲）＋ `AppModel.live()` DEBUG 分支（TDD） | 單測：20 首排序與 ID、封面可被 `ArtworkService.thumbnail` 解碼且中心色符合色板、延遲生效、未知 ID→nil、歌詞非空；`AppModel` 讀取的旗標名＝共用檔常數（單一來源的接線測試） |
| T3 | trace 模組（TDD：header、序號連續、時間戳單調、O_APPEND 同步寫、水位讀取、單例只安裝一次）＋ binding setter 鉤子＋局部事件監聽＋live scroll 通知 | 新單測綠；非測試模式下 trace 完全不啟動（單測斷言）；重複呼叫安裝不會重複記錄（單測斷言） |
| T4 | AX 探針；`AppUITestCase.launch` 加預設為空的 `environment:` 參數（向後相容）；scheme 關系統截圖；xcodegen 重生成 | V2；單測紅燈清單與 T0 相同 |
| T5 | `CoverFlowProbe`（UITests，薄殼，判定邏輯全在 `CoverFlowGateLogic`）＋ 判定腳本與其測試 | 編譯通過；腳本測試綠 |
| T6 | S0–S6（需使用者在場授權 Automation Mode；S0 需先有一個 scratch 構建）；按備案處置；**凍結閾值**寫進 §11 | §11 每項有實測值；凍結清單完整 |
| T7 | 四條測試；M0 首跑 1 次；把 §3.9 的「未知」格凍結成定值（寫進 §11）；腳本 dry-run | 首跑結果逐格對照 §3.9，差異記錄；凍結表完成 |
| T8 | **M0 閘門**：`-test-iterations 10`（含 T3 的 0ms 資訊對照另跑一輪） | V3、V5 |
| T9 | **變異回歸** M2／M3（＋M1 資訊性）：`-test-iterations 3`；結束清理 | V4、V8 |
| T10 | 回歸：單測全量＋既有 UITests＋Release 排除＋附件掃描 | V6、V7、V9 |
| T11 | ACCEPTANCE H-05 降級；交接檔補註（歸因更正、RUNTIME 綠、指向本計劃）；證據包 | V10；證據包逐條回扣 V1–V10 |

**R4 續行任務**（2026-09-11，使用者確認執行；編號用 R5-x，與 Spike S1–S7 區分）

| # | 任務 | DoD |
|---|---|---|
| R5-1 | 本計劃同步修訂：§3.12、§5、§6（V3／V5／V6、R4-X、R4-C）、§11（本晚運行降為探索資料）、§12（R4 辯論記錄） | 各節條文到位；之後才准任何證據運行 |
| R5-2 | 判定器 TDD（先 RED）：`table_valid`（缺整條測試、缺 GATE、迭代數不符、xc_result 與 GATE 不一致、errors 非空）；V5（端點逐次、其他碼致敗、EXCLUDED 不可作端點）；V3（缺陷 2／3 精確謂詞；10 PASS／10 C2／9-1／1-9／兩格混合／混入其他碼）；EXCLUDED 格不進 defect2/3、V5、V4；V4 在 baseline 或 mutant 無效時回無效；`verdict` 子命令按 R4-C 優先序 | 新測試先 RED 後 GREEN；對本晚 cf-m0 輸出（探索）結論可復算；3 視角對抗核查（Opus 5）無未處置異議 |
| R5-3 | 真 T0 基線：scratch＝`git archive aad6a9b` 的 AzathothsWhisper/ ＋ 四檔（`Features/CoverFlow/CoverFlowStrip.swift` a9ac2902fac2646d0899157ee231a1e4；`Tests/UI/CoverFlowStripRenderGeometryTests.swift` a12d926ec55c26e8465d7100a135dc88（無 T0 快照，單測檔）；`pbxproj-preT1` a06b090908014b558d4cf1abaf86879f；`xcscheme-preT1` 42656fcfc18aab6a8744c522dce104a4）；preflight（不計證據）→ 17 條既有 UITests 證據輪 | 與最終代碼上的既有 UITests 逐條比對＝V6（正規化見 §6 V6） |
| R5-4 | Phase 3 `/simcodex`；觸及契約、閾值或驅動路徑 → 回 Phase 1 | simcodex 報告全綠或殘留逐條裁決 |
| R5-5 | Phase 4 在最終代碼上：Python 判定器測試；單測全量；V1；V2；V7；V8；既有 UITests；**確認性閘門** `cf-m0-confirm`（M0 ×10，閘門配置）＋ `cf-M2-confirm`、`cf-M3-confirm`（×3，由最終代碼重建 scratch 副本；無條件重跑）；V9 | 各 V 在最終代碼上重驗 |
| R5-6 | `verdict` 機械結論＋證據包 → 使用者；使用者裁決 V4 權重 | 證據包逐條回扣 V1–V10 |

## 6. 驗收標準與閘門判定程序

| # | 標準 | 判定方式 |
|---|---|---|
| V1 | 新單測全綠；新增純邏輯檔（`CoverFlowGateLogic`、fixture、trace 寫入端）行覆蓋率 ≥80% | xcresult ＋ `xccov` 逐檔 |
| V2 | xcodegen 重生成後，pbxproj／xcscheme 相對 **T1 前快照**（md5 `a06b0909…`）只多出新檔條目與截圖設定 | diff |
| V3 | **M0 閘門**（R4 修訂）：`table_valid`（§3.12）；**缺陷 3**＝T4.s2 10/10 FAIL、每次含 {`C1-OFFSET`、`C3-TARGET-MISS`、`C5-DRIFT`} 之一、且十次完整正規化簽名集合相同；**缺陷 2**＝至少一個非 EXCLUDED 的 C2 登記步驟（T1.s2／T1.s3／T2.s2／T2.s3／T4.s1／T4.s2）10/10 FAIL、每次含 `C2-STACK`（同格可兼有其他產品碼）、且十次簽名集合相同；否則依 §3.10「不可重現」分支；**一致性**＝其餘步驟十次結果一致，例外見下 R4-X | §3.12 腳本 |
| V4 | **歷史變異回歸**：M2、M3 各自是否被步驟級差異殺死（§3.11：M0 該步驟 10/10 PASS、變異 3/3 FAIL 且簽名集合一致、簽名屬全部產品碼）；baseline 與 mutant 各自須 `table_valid`；EXCLUDED 格不可作殺死步驟；結果連同 trace 事件性質上報，權重由使用者決定 | 同上 |
| V5 | **陽性對照**（R4 修訂）：M0 上 T2.s1 10/10 全契約 PASS；且至少一個非 EXCLUDED 的端點步驟（T2.s2／T2.s3／T4.s1）**十次結果一致**（ALL_PASS 或 ALL_FAIL_CONSISTENT）且**每一次**結果 ∈ {PASS, 碼集恰為 {`C2-STACK`} 的 FAIL}——即端點陽性子契約 C0、C1、C3、C6 十次皆綠，`C2-STACK` 不參與 V5 成敗，任何其他產品碼即 V5 失敗；S2 已知點分類命中。**「十次一致」為 R4 補正**（2026-09-11 對抗核查：否則一個時紅時綠的端點可充當陽性對照，且多一個無關 flake 反而使結論變寬鬆）——只收緊不放寬；**已於 R5（2026-09-12）Phase 1 快速複審通過並由使用者拍板**，精確解讀：ALL_PASS＝十格皆 PASS；ALL_FAIL_CONSISTENT＝十格皆 FAIL 且十次完整正規化 `sig_set` 相同且產品碼投影恰為 {`C2-STACK`}；INCONSISTENT 與 EXCLUDED 皆不得為 V5 候選 | 同上＋§11 |
| V6 | **不回歸**：單測紅燈清單與 T0 完全相同（只多出新單測的綠）；既有 UITests 與 **T0 樹**（R4：`git archive aad6a9b`＋§11 R5-3 所列四檔重建）同一命令的結果逐條相同——A-10 為 PASS 或已知失敗（`ShellUITests.swift:174`，state≠notRunning）皆視同基線，BatchLive skip，其餘逐條相同 | 清單 diff |
| V7 | **Release 排除**：主證據＝源碼結構（app target 內每個新增檔整檔包在 `#if DEBUG … #endif`；`AppModel.live()` 分支、trace 鉤子、label AX value 都在 `#if DEBUG` 內；grep 腳本逐檔驗）＋ Release 構建成功；輔證＝`strings` 不含旗標名與型別名 | grep＋構建＋`strings` |
| V8 | repo 內無變異碼：`CoverFlowStrip.swift` md5 始終 ＝ `a9ac2902…`（T0 基準） | md5 |
| V9 | 附件：系統自動截圖已關；`xcresulttool` 列出全部附件，逐張確認為裁切到視窗的 Cover Flow 畫面；證據包只含裁切圖與表格，不含原始 xcresult | 腳本列表 |
| V10 | H-05 行文與 Codex 裁決 #4 一致；交接檔補註到位 | 人工核對 |

**R4-X（V3 一致性的唯一例外，2026-09-11 R4）**：僅限 R5-5 的 M0 確認性運行，最多一個步驟可標為 `EXCLUDED-INCONSISTENT`，須同時成立：
(a) 該步驟凍結登記為 FAIL{C2-STACK}（T1.s2／T1.s3／T2.s2／T2.s3／T4.s1 之一）；(b) 十次中 PASS 與 FAIL{C2-STACK} **各至少出現一次**，且不得出現其他結果；
(c) 該步驟不進缺陷 2／3 證據、V5 端點候選、V4 可殺集合。不適用任何變異運行或修復候選（修復候選仍須四測試 ×20 全綠，§3.10）。
其根因只記為推論（「觀察到渲染次序不確定；推論：產品側 z 序時序，亦可能是截圖相對 compositing 的取樣時機」）

**R4-F 凍結表相符（2026-09-12 R5，變體 N′；使用者拍板）**：只對 `cf-m0-confirm`（變異運行不適用——V4 已是步驟級差異，變異本就該產生 M0 沒有的碼）。
以 §11 凍結預登記表定義每個登記步驟的允許產品碼集合 F(step)：PASS 步驟（T1.s1／T2.s1／T3.s1）＝∅；T1.s2／T1.s3／T2.s2／T2.s3／T4.s1＝{`C2-STACK`}；
T4.s2＝{`C1-OFFSET`, `C3-TARGET-MISS`, `C5-DRIFT`, `C2-STACK`}（§6 V3 明文接受以 C1／C3／C5 之一抓缺陷 3，相符檢查不得縮掉它）。
判定：每次迭代每格若為 FAIL，其產品碼投影必須 ⊆ F(step)；出現 F 外碼（哪怕 1/10）＝與預登記矛盾 → R4-C「不可判定」的獨立觸發（不併入 `table_valid`）。
**不要求**凍結為 FAIL 的步驟日後仍失敗：翻成 PASS 或碼集合為登記的子集只記 `frozen_deviations`（報告用），結論交既有 V3 一致性／V5 端點 ALL_PASS／§3.10 缺陷 2 不可重現分支。
PROBE／MISSING／UNTAGGED 格由 `table_valid` 處理，不重複計。實作：`evaluate_frozen_conformity`（`h02_gate_rules.py`）、`FROZEN_REGISTRATION`／`FROZEN_ALLOWED_CODES`（`h02_gate_model.py`）；`v3`／`verdict` 印出三個新欄位。
（我方原提案「變體 S」——另要求凍結 FAIL 步驟不得十次全 PASS——被 Codex 以三個反例駁回，見 §12 R5）

**D1 預登記（2026-09-12 R5）**：確認性運行若前置 C6 導致任一登記步驟 MISSING、或由 `s0`／`setup` 產生「未知步驟」error，依現行 `table_valid` 判不可判定；保留證據、重跑前回 Phase 1。不新增 blocked-step 規格碼（C6 落在最後登記步驟時表格仍可有效，走既有謂詞）。
**D2 預登記（2026-09-12 R5）**：C4 維持「nil 原始回寫不算變」；已知盲區＝「11→12→nil→12→13」與 hold「nil→13」的瞬時擺動不可偵測（C1／C2 只量落定終態、C5 只涵蓋切 tab），證據包明列，留待修復計劃結合 nil 持續時間或同步幾何取樣再議。

**閘門結論**（R4-C：機械判定、按下列優先序取第一個成立者；V4 權重由使用者在看到結果後裁決）
1. **不可建**：S 階段備案用盡 → 上報
2. **不可判定**：任一確認性運行（`cf-m0-confirm`、`cf-M2-confirm`、`cf-M3-confirm`）`table_valid` 不成立，或 V5 不成立，或 R4-F 凍結表不相符（只對 `cf-m0-confirm`）→ 保留該份證據；重跑須先回 Phase 1 明言修訂
3. **不通過**：缺陷 3 未抓到或 T4.s2 不穩定 → **禁止第四次修復**
4. **部分通過**：缺陷 3 穩定，但以下任一——缺陷 2 落「不可重現」分支；V4 有變異未殺；V3 一致性不成立（≥2 格不一致，或不一致格不符 R4-X）→ 帶選項上報，使用者裁決是否開始第四次修復
5. **通過**：其餘（V3 全部成立＋V5 成立＋V4 兩變異皆殺）
- **只有 R5-5 的首份確認性運行可作結論依據**；此前一切運行（含 2026-09-11 晚的 `cf-m0`、`cf-M1/M2/M3` 與 R5-4 中任何診斷運行）一律為**探索資料**

**護欄**（SS5）
- T6 結束時凍結全部閾值（C1 的 3pt、`isFacing` 容差、色距閾值、落定 100ms×4／10s、保持 1.5s、穩定重試 3 次、trace 靜止 500ms）；
  T7 結束時凍結預登記表。凍結後任何改動 → 回 Phase 1 修訂本計劃、重跑 V5
- 「修測試」只限 `[PROBE-*]`／基建問題；觸及契約、閾值或驅動路徑 → 回 Phase 1
- 「產品在此路徑未重現」→ 記錄並上報，**不**進修測試分支、不計入熔斷
- 同一 PROBE 失敗連續 3 次 → 熔斷上報（slipknot 08）

## 7. 測試策略與流程偏離聲明

- 單元：T1／T2／T3 的新單測（純邏輯、fixture、假 Music、trace、旗標接線）；判定腳本的 unittest。
- 集成：組裝分支在真實 app 啟動（每條 UITest 的共同前置本身）。
- E2E：四條 XCUITest。
- 覆蓋率：`coverage_gate.sh` 只量 Services＋Infra（本計劃不動）；新純邏輯檔以 V1 逐檔量。
- **流程偏離（交付時請使用者簽字）**（SS3、HF7）：本階段的測試集**按設計不會全綠**——EDGE 誠實紅（使用者既裁定），
  新測試在 M0 上的紅以 §11 凍結表為準。故 fatboyslim Phase 3 閘門「代碼測試全綠」讀作「除凍結的預期紅集合外全綠，且預期紅以登記的簽名紅」；
  Phase 4 normal 終點「全量測試通過」改由 §6 閘門結論取代。預期紅集合**只有一個來源**：§11 凍結表（§3.9 是其凍結前版本）。
  不採用 `XCTExpectFailure` 把紅燈包成預期失敗（見 §12 SS3）。

## 8. 影響面

新增
- `AzathothsWhisper/App/UITestSupport/CoverFlowUITestFixture.swift`（DEBUG；兩個 target）
- `AzathothsWhisper/App/UITestSupport/CoverFlowGateLogic.swift`（DEBUG；兩個 target）
- `AzathothsWhisper/App/UITestSupport/CoverFlowUITestMusic.swift`（DEBUG）
- `AzathothsWhisper/App/UITestSupport/CoverFlowUITestTrace.swift`（DEBUG）
- `AzathothsWhisper/App/UITestSupport/AppModel+CoverFlowUITest.swift`（DEBUG）
- `AzathothsWhisper/Tests/Features/CoverFlowGateLogicTests.swift`、`CoverFlowUITestFixtureTests.swift`、`CoverFlowUITestMusicTests.swift`、`CoverFlowUITestTraceTests.swift`
- `AzathothsWhisper/UITests/CoverFlowUITests.swift`、`AzathothsWhisper/UITests/Support/CoverFlowProbe.swift`
- `AzathothsWhisper/Scripts/h02_gate_eval.py`、`AzathothsWhisper/Scripts/test_h02_gate_eval.py`

修改
- `AppModel.swift`：`live()` 開頭數行 DEBUG 分支
- `CoverFlowView.swift`：AX 探針 2–4 行；binding setter 內 DEBUG-only trace 呼叫 1 處
- `UITests/Support/AppUITestCase.swift`：`launch` 加預設為空的 `environment:` 參數（向後相容；既有兩類測試屬 V6 回歸面）
- `project.yml`：UITests target 追加兩個共用檔；scheme test 加 `captureScreenshotsAutomatically: false`；`project.pbxproj`／xcscheme 由 xcodegen 重生成
- `ACCEPTANCE.md`：**只改 H-05 一行**
- `docs/plans/2026-09-09-coverflow-h02.md`：補註

不動：`CoverFlowStrip.swift`（V8）、`CoverFlowViewModel.swift`、`Services/*`、既有測試的斷言。
repo 外：`~/Developer/bjork-h02-gate/`（持久化證據與變異源，本機目錄，不進 git）。

## 9. 風險與回退

| # | 風險 | 緩解 |
|---|---|---|
| R1 | Automation Mode 需認證，無人值守必掛 | 跑 UITest 時請使用者在場；是否永久免認證由使用者自決，不代為變更 |
| R2 | 合成事件落到其他 app | 只用 XCUIApplication 定界操作；送事件前斷言 app 在前台，否則 `[PROBE-FOREGROUND]` 中止 |
| R3 | 合成捲動 ≠ 觸控板慣性 | trace 直接量事件性質；S7 升級路徑；真機手滑仍是修復的強制 DoD |
| R4 | 過渡態不可測 | N3、§3.10 |
| R5 | AX 外框假設不成立 | S1；前置單測已對自家 pid 實證同一機制 |
| R6 | 截圖拿不到窗內容 | S2 |
| R7 | 變異與主工作區混淆／附著到錯的實例 | repo 外構建；二進位身分斷言；V8；結束清理 lsregister 與 DerivedData |
| R8 | 測試模式外洩到 Release | `#if DEBUG` ＋ V7 |
| R9 | iCloud 同步樹產生「 2」副本 | 寫檔後 `ls` 檢查；構建產物與證據只放 DerivedData／scratch／`~/Developer` |
| R10 | 截圖含憑證或使用者畫面 | EphemeralSecretStore；系統截圖關閉；只附裁切到視窗的圖；V9 |
| R11 | 共享 UserDefaults（語言、窗框）隨使用者操作漂移 | 語言走 argument domain；窗尺寸以 `[PROBE-WINDOW]` 斷言並記錄；本計劃不 resize、不寫窗框 |
| R12 | 觀察者效應（trace、AX 輪詢改變時序） | trace 在主執行緒只做一次微秒級 `write(2)`（不 fsync、不進 SwiftUI 失效圖）；捲動段內暫停 AX 輪詢；S4 量 snapshot 耗時 |
| R13 | 為製造紅燈而改測試（「修紅」） | §6 護欄 |
| R14 | `-O` 構建使 DEBUG 斷言或行為與 T0 不同 | T0 單測基線用預設 Debug；閘門配置自 S 階段起固定，M0 與變異同配置，比較只在同配置內進行 |

**回退**：改動＝新增檔 ＋ 一小段 DEBUG 分支 ＋ AX 探針 ＋ trace 鉤子 ＋ `launch` 參數 ＋ scheme 截圖設定。
回退＝刪新增檔、還原修改檔、xcodegen 重生成。產品 Release 行為不變。

## 10. 運行命令

```bash
G=~/Developer/bjork-h02-gate            # 持久化證據目錄
cd AzathothsWhisper

# 單元測試全量（memory：skip 必帶括號 ＋ 超時上界）
xcodebuild test -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper \
  -destination 'platform=macOS' -only-testing:AzathothsWhisperTests \
  -skip-testing:"AzathothsWhisperTests/BatchOverlappingLoadTests/overlappingLoadSuspendsPollingUntilLastCompletes()" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -resultBundlePath "$G/unit-<tag>.xcresult"

# 新 UITest（閘門配置，§3.13）
TEST_RUNNER_AZW_EXPECTED_APP_DIR="<Products 目錄>" \
xcodebuild test -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper \
  -destination 'platform=macOS' -only-testing:AzathothsWhisperUITests/CoverFlowUITests \
  -enableCodeCoverage NO SWIFT_OPTIMIZATION_LEVEL=-O \
  [-test-iterations 10] -test-timeouts-enabled YES -default-test-execution-time-allowance 300 \
  -resultBundlePath "$G/cf-<tag>.xcresult" 2>&1 | tee "$G/cf-<tag>.log"

# 判定
python3 Scripts/h02_gate_eval.py --log "$G/cf-<tag>.log" --xcresult "$G/cf-<tag>.xcresult" [--baseline "$G/cf-m0.*"]

# 既有 UITests
xcodebuild test ... -only-testing:AzathothsWhisperUITests/ShellUITests \
  -only-testing:AzathothsWhisperUITests/BatchUITests -resultBundlePath "$G/ui-<tag>.xcresult"

# Release 排除（V7 輔證）
xcodebuild -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper -configuration Release \
  -derivedDataPath "$G/rel" build
strings "$G/rel/Build/Products/Release/Azathoth's Whisper.app/Contents/MacOS/Azathoth's Whisper" \
  | grep -c 'AZW_COVERFLOW_UI_TEST\|CoverFlowUITestMusic'    # 期望 0
```

## 11. 實測記錄（實施中回填）

### T0 單測基線（2026-09-11 11:30，改碼前，預設 Debug 配置）
- 307 tests／35 suites，**6 issues，全在 `edgeItemsAlsoReachCenter`**（initialCenter 1→0、4→1、5→2、6→3、7→4、8→5；0→0 過）；
  `centerCoverFacesViewerAndSidesTiltAway` 過；`runtimeCenterChangeReachesTarget` **3/3 過**。其餘全綠。xcresult：`scratchpad/unit-T0.xcresult`
- 既有 UITests 基線：待使用者在場授權 Automation Mode 後補跑

### T1–T5 實施記錄（2026-09-11，TDD：每段先以編譯失敗為 RED 再 GREEN）
- T1 共用檔 fixture＋`CoverFlowGateLogic`：GREEN。T2 假 Music＋`AppModel.live()` DEBUG 分支：GREEN。
  **TDD 抓到一個真問題**：以 `NSColor.usingColorSpace(.sRGB)` 讀色會再套一次裝置描述檔，色板色偏 0.08–0.16
  （足以把 UITest 的疊放分類推過閾值）→ 改為 `CoverFlowGateLogic.averageSRGB`（經 CoreGraphics 畫進 sRGB 位圖再讀位元組），
  並以「sRGB 圖經 P3 位圖轉回」的單測釘住
- T3 trace（格式／讀取端共用、寫入端 app-only、行程級單例、主執行緒同步 `write(2)`）：GREEN
- T4：AX 探針（strip 標識、label 的 DEBUG-only AX value）；`AppUITestCase.launch(language:environment:)`；
  project.yml（UITests 同編 3 個共用檔；scheme `captureScreenshotsAutomatically: false` → xcscheme `systemAttachmentLifetime = "keepNever"`）
- T5：`CoverFlowProbe`＋四條測試＋臨時 `testProbeDump`（預設 skip）；全 target 編譯通過。
  Swift 6 隔離：XCUI 型別為 `@MainActor`、`XCUIElementSnapshot` 非 Sendable → 探針 `@MainActor`、測試方法逐個 `@MainActor`
  （類本身不能標：父類 `AppUITestCase` 非隔離）
- `CoverFlowView.itemWidth` 由 `private let` 改 `static let`（值不變），供 fixture 同源單測
- 判定腳本（並行 worker，Sonnet 5）：`Scripts/h02_gate_eval.py`＋28 條 unittest GREEN（先 RED）；847 行，超出 800 行規範——留給 Phase 3 simplify 處置
- **單測回歸（V6 單測部分）**：363 tests／39 suites，6 issues ＝ T0 的 EDGE 集合逐條相同（args 1,4,5,6,7,8）；新增 56 條全綠。xcresult：`~/Developer/bjork-h02-gate/unit-T5.xcresult`

### S0–S6 實測（2026-09-11，使用者在場授權 Automation Mode）
| # | 結果 | 實測值 |
|---|---|---|
| S0 | ✅ | trace header 自報 `bundle=<DerivedData>/Build/Products/Debug/Azathoth's Whisper.app`＝預期目錄；同 bundle ID 實例數 1 |
| S1 | ✅ | 卡片以聯集外框曝光。中心卡 **260×520（長寬比 2.000）**——倒影元素回報未裁剪高度，故基準**不是** 1.45；鄰張 247×582（2.356）、次鄰 177×619（3.487）。strip AX 外框 `(265,131,680,664)`，左右各內縮一個 itemWidth，但 **midX=605＝視窗中心**，C1 的基準成立 |
| S2 | ✅ | `window.screenshot()` 為真實視窗內容，2400×1600（scale 2）；座標換算正確：每張卡在自身 midX 分類為本色（距離 0.011–0.108），背景點分類為 background。閾值 0.35 維持 |
| S3 | ✅ | 點 label（ScrollView 之外）後按 → ：label T10→T11 |
| S4 | ✅（走備案） | `strip.scroll(byDeltaX:)` 報 `Unable to find hit point for ScrollView` → 改**座標式** `coordinate(withNormalizedOffset:).scroll(byDeltaX:)` 成功。**合成事件 `phase=0 momentum=0 precise=1`（無 phase／慣性）**，但 AppKit 仍發 willStart／didEnd live scroll。捲動後 `viewAligned` **會吸附**（落定後中心卡 dx=−0.0、長寬比 2.000）→ C1 照 3pt 嚴格判 |
| S5 | ✅ | `.accessibilityValue` 可讀（label=T10／T13／T11） |
| S6 | ✅ | trace 水位讀取正常，`problems=[]`；bind／event／live 三種記錄齊全；單次 snapshot＋截圖耗時 0.18–0.26s |

**凍結參數**（T8 起不得再改）：`unrotatedAspect=2.0`、寬容差 3%、長寬比容差 0.05、C1 3pt、色距閾值 0.35、
落定 100ms×4／逾時 10s、保持 1.5s、穩定重試 3 次、trace 靜止 500ms、捲動量 300（座標式）。

### T7 首跑（M0，1 次迭代）與凍結預登記表
```
GATE{T1.s1|PASS}                      GATE{T2.s1|PASS}           GATE{T3.s1|PASS}
GATE{T1.s2|FAIL|C2-STACK}             GATE{T2.s2|FAIL|C2-STACK}  GATE{T4.s1|FAIL|C2-STACK}
GATE{T1.s3|FAIL|C2-STACK}             GATE{T2.s3|FAIL|C2-STACK}  GATE{T4.s2|FAIL|C1-OFFSET,C2-STACK}
SIG{T1.s2|C2-STACK|G=T13|over=T12|side=L}   SIG{T1.s3|C2-STACK|G=T11|over=T12|side=R}
SIG{T2.s2|C2-STACK|G=T00|over=T01|side=R}   SIG{T2.s3|C2-STACK|G=T19|over=T18|side=L}
SIG{T4.s1|C2-STACK|G=T19|over=T18|side=L}   SIG{T4.s2|C1-OFFSET|label=T19|centered=T16|strides=+3}
SIG{T4.s2|C2-STACK|G=T16|over=T17|side=R}
```
- **缺陷 3 抓到**：T4.s2 `C1-OFFSET strides=+3`——切 tab 重建（初始值路徑）後，label 仍是 T19、畫面中心卻是 T16，與 EDGE 單測的 `max(0, 請求−3)` 同量級
- **缺陷 2 抓到，且與缺陷 3 無關**：C2-STACK 出現在 label 與畫面一致的步驟（T1.s2/s3、T2.s2/s3、T4.s1）。
  形態一致：**剛才還居中的那張卡（來向的鄰張）仍留在最上層**——正是「zIndex 讀滯後的 centerID」。
  首次載入（T3.s1）不紅，因為中心從未變過、沒有滯後值
- **與 §3.9 預登記的偏離（如實記錄，不改判據）**：預登記推算 T1.s2/s3、T2.s2/s3、T4.s1 為 PASS，實測 FAIL `C2-STACK`。
  原因是推算只想到「偏移態才會疊放錯」，沒想到滯後的 zIndex 在任何一次中心變更後都會留下來。這推翻了 §3.10 對缺陷 2
  「只能作為缺陷 3 的副產物」的顧慮——缺陷 2 在落定態可獨立重現
- **陽性對照**：T1.s1、T2.s1、T3.s1 三個非端點狀態全綠（含兩側 C2）→ 探針會綠，不是永遠紅
- 一個探針錯誤已被自身抓到並修正：`unrotatedAspect` 誤用 1.45（由倒影比例推算）→ 每步 `C1-NOT-FACING`；改為 S1 實測 2.0 後恢復

**凍結預登記表（M0，T8 起以此判 V3）**：T1.s1／T2.s1／T3.s1＝PASS；
T1.s2／T1.s3／T2.s2／T2.s3／T4.s1＝FAIL{C2-STACK}；T4.s2＝FAIL{C1-OFFSET, C2-STACK}。

### T8 M0 閘門（**中途暫停**，使用者 2026-09-11 喊停）
已完成 T3 ×10、T1 ×10、T2 第 1 次；T2 其餘 9 次與 T4 十次**未跑**。部分結果：

| 步驟 | 10 次結果 |
|---|---|
| T1.s1 | **10/10 PASS**（非端點陽性對照成立） |
| T1.s2 | **10/10 FAIL{C2-STACK}**（簽名每次相同） |
| T1.s3 | **不一致**：5 FAIL{C2-STACK}／4 PASS／1 `[PROBE-FOREGROUND]` |
| T3.s1 | **10/10 PASS** |
| T2.s1 | 1/1 PASS（樣本不足） |

- **T1.s3 不穩定**是新事實：反向捲回時，滯後的 zIndex 有時不留下（約一半）。這不影響缺陷偵測（T1.s2 穩定 10/10），
  但按 §6 護欄，T1.s3 在 V3 判定裡屬 INCONSISTENT，需在完整跑完後決定是「該步驟不作閘門依據」還是查清時序條件——
  **不得**為了讓它穩定而放寬判據
- `[PROBE-FOREGROUND]` 出現 1 次：閘門運行期間機器被其他操作搶了前台。重跑時應讓機器閒置

### 暫停狀態（2026-09-11）
- **未提交任何東西**（全域 §1）。工作區：8 個修改檔 ＋ 7 個新增檔／目錄（含本計劃、交接檔補注、判定腳本）
- 證據在 `~/Developer/bjork-h02-gate/`：`unit-T0/T5.xcresult`、`spike2.log`、`m0-first2.log`、`m0-gate.log`（部分）、變異源與 md5
- 變異體工作副本已備妥（repo 外 scratch，三份，`xcodegen` 已生成，**尚未構建**）
- **恢復時的下一步**：① 重跑 T8（10 次迭代，機器閒置）；② T9 變異回歸（M2／M3 閘門、M1 資訊性）；
  ③ T10 回歸（單測全量＋既有 UITests＋Release 排除＋附件掃描）；④ 刪臨時 `testProbeDump`；⑤ 證據包與閘門結論；
  ⑥ Phase 3 `/simcodex`（含判定腳本 847 行超規的處置）；⑦ Phase 4 全量測試
- **已恢復（2026-09-11 晚）**，實測見下列各節。證據目錄同上；變異副本在本會話 scratchpad 重建（上一會話的副本未使用）

### 判定腳本缺陷（恢復後首次判定時發現，已修；屬 §6 允許的基建修正，不動判據）
- 真實 xcresult 的失敗文字是 `CoverFlowUITests.swift:74: failed - SIG{…}`（XCTFail 的 `compactDescription` 包裝），
  腳本只剝 `檔名:行號:` 前綴、要求其後以 `SIG{` 開頭 → cf-m0 首次判定把**全部** SIG 判成 UNTAGGED、`run_valid=False`
- 根因：§3.12 R2-6 要求的「T7 以真實 xcresult dry-run 並留作真實夾具」**上一會話未執行**；`testdata/h02/` 全是手寫合成夾具（缺 `failed - `）
- 修正：`failure_message_body()` 剝前綴後再剝一次 XCTFail 包裝；其他斷言巨集的包裝（`XCTAssertTrue failed - …`）不剝，仍屬 UNTAGGED。
  TDD：新增 5 條（真實 SIG／PROBE／框架失敗 `Unable to find hit point…`（取自 spike.xcresult）／其他斷言包裝／真實夾具端到端），
  合成夾具產生器改為真實形態 → RED 8 條 → GREEN 33/33（`/usr/bin/python3` 3.9.6）。真實夾具 `testdata/h02/real_m0_t4.*`
  取自 cf-m0 的 T4 前 2 次迭代（同一步驟雙 SIG），日誌只留 `Test Case`／`GATE` 行、不含本機路徑

### T8 M0 閘門（完整重跑，2026-09-11，機器閒置，使用者在場授權 Automation Mode）
`cf-m0.xcresult`：40 tests（4×10），`run_valid=True`，**零 PROBE、零 UNTAGGED、零 errors**，迭代數核對 10

| 步驟 | 凍結表 | 10 次實測 | 對照 |
|---|---|---|---|
| T1.s1 | PASS | 10/10 PASS | ✓ |
| T1.s2 | FAIL{C2-STACK} | 10/10 `C2-STACK\|G=T13\|over=T12\|side=L` | ✓ |
| T1.s3 | FAIL{C2-STACK} | 10/10 `C2-STACK\|G=T11\|over=T12\|side=R` | ✓（暫停前那輪 5 FAIL／4 PASS／1 PROBE；本輪一致） |
| T2.s1 | PASS | 10/10 PASS | ✓ |
| **T2.s2** | FAIL{C2-STACK} | **9 FAIL `C2-STACK\|G=T00\|over=T01\|side=R`／1 PASS（iter 4）** | **✗ INCONSISTENT** |
| T2.s3 | FAIL{C2-STACK} | 10/10 `C2-STACK\|G=T19\|over=T18\|side=L` | ✓ |
| T3.s1 | PASS | 10/10 PASS | ✓ |
| T4.s1 | FAIL{C2-STACK} | 10/10 `C2-STACK\|G=T19\|over=T18\|side=L` | ✓ |
| T4.s2 | FAIL{C1-OFFSET, C2-STACK} | 10/10 `C1-OFFSET\|label=T19\|centered=T16\|strides=+3`＋`C2-STACK\|G=T16\|over=T17\|side=R` | ✓ |

- T2.s2 iter 4 的 PASS：與 iter 3（FAIL）的契約報告**AX 幾何逐項相同**（T00 dx=0.0、各卡 frame 一致），只差交疊點像素分類——
  iter 3 是 T01 在上、iter 4 是 T00 在上。即滯後的 zIndex 有時在截圖前已刷新：產品側的渲染時序競態，與暫停前 T1.s3 的 5/4 同一現象、換了步驟出現
- **T3 0ms 資訊對照**（`cf-m0-t3-0ms`，`TEST_RUNNER_AZW_COVERFLOW_ALBUM_DELAY_MS=0`）：10/10 PASS——首次載入路徑對 albumTracks 延遲不敏感

### T9 變異回歸（2026-09-11，`-test-iterations 3`，同閘門配置）
- 構建：三份 scratch 副本並行 `build-for-testing`（此時無測試在跑），之後逐個串行 `xcodebuild test`（構建 no-op，零 CompileSwift）
- 溯源（`~/Developer/bjork-h02-gate/mutant-runs/`）：基底 `aad6a9b`；三份副本全源檔雜湊相對 M0 **只差 `CoverFlowStrip.swift`**；
  Strip md5 M1 `f5ef5967…`／M2 `57da040c…`／M3 `48687466…`；CDHash M0 `6e93fb4c…`／M1 `41aa0c0d…`／M2 `7d355b8e…`／M3 `1ae6a3d2…`；
  每份 12 條 IDENTITY 皆指向自己的 Products、instances=1
- 判定（`h02_gate_eval.py v4`，基準 cf-m0；殺死步驟只限 M0 10/10 PASS 者＝T1.s1／T2.s1／T3.s1）：

| 變異 | 運行 | 殺死步驟（3/3 一致） | 其餘註記 |
|---|---|---|---|
| **M2**（閘門） | 有效 | **T1.s1、T2.s1**：`C2-STACK\|G=T11\|over=T10\|side=L` | T3.s1 PASS；T4.s2 **PASS**（`.leading` 讓初始值路徑的 C1-OFFSET 消失） |
| **M3**（閘門） | 有效 | **T1.s1、T2.s1**（同上）、**T3.s1**：`C2-STACK\|G=T10\|over=T09\|side=L` | T4.s2 只剩 `C2-STACK\|G=T19\|over=T18\|side=L`（`.task` 讓 C1-OFFSET 消失） |
| M1（資訊） | 有效 | 同 M3 三步 | T4.s2 只剩 `C1-OFFSET strides=+3`、C2 過（與 §3.9 對 M1 的推測一致） |

- 報告註記（**不是**殺死條件）：M2 在「向右一步」後左鄰壓住中心，與當年真機回報「向左滑動時沒問題 向右滑動 還是有蓋住的」同形；
  三個變異都含嘗試 1（visualCenterIndex），都讓 M0 上本來正確的單步／首載疊放變錯
- 事件性質：殺死全部落在鍵盤與首次載入步驟，**不依賴**合成捲動是否帶慣性（S4：`phase=0 momentum=0`）→ S7 升級路徑不需要
- 收尾（HF5）：三個變異 app 與三個 UITest Runner 均 `lsregister -u`、scratch DerivedData 已刪，LaunchServices 殘留 0 條

### T10 回歸（2026-09-11）
- **單測全量**（預設 Debug，`unit-T10.xcresult`）：363 tests／39 suites，6 issues，紅燈清單與 **T0、T5 逐條相同**（EDGE args 1,4,5,6,7,8）→ V6 單測 ✓
- **既有 UITests**（ShellUITests＋BatchUITests＋BatchLiveUITests＝17 條，與 09-08 基準同構；按 §10 **不帶**閘門參數）
  - 第一輪（`ui-T10`）：13 條在 `AppUITestCase.swift:59`（`app.launch()`）約 74s 後報 `does not have a process ID`，最後 3 條綠。
    **根因（spindump 實證）**：app 進程在，主執行緒卡在 `AppModel.live()` → `LegacyConfigMigrator.migrateIfNeeded` →
    `ConfigStore.token` → `KeychainStore.read` → `SecItemCopyMatching` 等 securityd——重建後 CDHash 變了（ad-hoc 簽名），
    鑰匙串 ACL 不再認可此二進位、授權框擋住 `App.init`。與本次改動無關（閘門模式走 EphemeralSecretStore，70 餘次閘門啟動從未碰到）。
    統一日誌在本機沙箱內讀不到（窗口內 0 行），故先前「無 SecurityAgent」為假陰性
  - 第二輪（`ui-T10b`，同一二進位 CDHash `cc98df4f…`、零重編譯）：**15 綠、1 skip（BatchLive）、1 紅＝A-10 `testQuitMenuItemTerminatesApp`**
    （18.3s、state 停 3；ACCEPTANCE 09-05 記為單跑亦紅、18.4s、state 4）→ 與 09-08 基準一致，V6 既有 UITests ✓
  - 偏離（如實記錄）：T0 的既有 UITests 基線當時未跑，比對基準改用 §2 記錄的 09-08 結果
- **Release 排除**（V7）：`rel/` Release 構建成功；`strings -a` 對 `AZW_COVERFLOW_UI_TEST`／`…TRACE_PATH`／`…ALBUM_DELAY_MS`／
  `CoverFlowUITestMusic`／`CoverFlowUITestTrace`／`CoverFlowGateLogic`／`CoverFlowUITestFixture`／`makeCoverFlowUITestModel` 全為 0；
  陽性對照 `coverflow-center-label` 2、`CoverFlowViewModel` 6、`CoverFlowStrip` 4（首選的 `coverflow-strip` 為 15 字節小字串、內聯不進 `__cstring`，不可作對照）；
  源碼結構：6 個新增 app 檔首尾皆 `#if DEBUG`／`#endif`，`live()` 分支、trace 鉤子、label AX value 皆在 DEBUG 內 → V7 ✓
- **附件**（V9）：xcscheme `systemAttachmentLifetime = "keepNever"`；cf-m0 90 張、M1／M2／M3 各 27 張、0ms 輪 10 張 PNG **全為 2400×1600（視窗 1200×800 ×2）**、
  命名皆 `*-window`；txt 只有契約報告與 XCUITest 元素查詢自帶的 debug description（範圍限 target app）。
  `ui-T10.xcresult` 內含 XCTest 啟動失敗時自動擷取的全系統 spindump——只留本機，不進證據包 → V9 ✓
- **V1 覆蓋率**：GateLogic 97.8%、Fixture 100%、TraceFormat 91.0%、Music 100%、組裝分支 100%；trace 寫入端 `CoverFlowUITestTrace` 原為 **72.1%（<80%）**，
  補 3 條特徵測試（非 RED→GREEN：對既有行為補測）：未安裝單例時 binding 鉤子為 no-op、live-scroll 通知入軌跡、經 `NSApp.sendEvent` 的零位移合成
  scrollWheel 事件被局部監聽記下 phase／momentum／precise → **87.5%（91/104）**。未覆蓋＝單例安裝正路徑（裝了收不回，會污染同行程其他測試）與短寫失敗路徑 → V1 ✓
- **V2**：pbxproj 相對 T1 前快照刪 0 行、增 62 行，全為新檔條目與 UITestSupport 分組；xcscheme 只多 `systemAttachmentLifetime` → ✓。
  **V8**：`CoverFlowStrip.swift` md5 始終 `a9ac2902…` → ✓。**V10**：ACCEPTANCE 只改 H-05 一行；交接檔補註在位 → ✓
- ④ 臨時 `testProbeDump` 與其 `dump(_:)` 已刪（`CoverFlowUITests.swift` 224 行，無殘留引用，全 target 編譯通過）

### 閘門判定（字面結果）——**已失效，僅作歷史**
> 2026-09-11 R4 修訂後（§6、§12 R4）：本節所據的 `cf-m0`、`cf-M1/M2/M3` 一律降為**探索資料**（它們暴露了判據缺陷，不得再作結論依據）；
> 結論只出自 R5-5 的首份確認性運行。下表保留作為「為何修訂」的證據。
| # | 結果 |
|---|---|
| V3 | 缺陷 3 ✓（T4.s2 10/10 `C1-OFFSET strides=+3`，簽名一致）；缺陷 2 ✓，落 `C2-STACK` 分支（五個步驟 10/10）；零 PROBE／UNTAGGED／無效運行 ✓；**「其餘步驟十次結果一致」✗（T2.s2 9/1）** |
| V4 | M2、M3 **皆被殺**（M1 資訊性亦被殺）；權重待使用者裁決 |
| V5 | T2.s1 10/10 PASS ✓；S2 已知點命中 ✓；**「至少一個端點步驟 10/10 PASS」✗**——凍結表把全部端點步驟登記為 FAIL{C2-STACK}，此條在 M0 上**按構造不可滿足**（T7 凍結時未標出） |
| V1／V2／V6–V10 | ✓ |

- 字面上 §6 四個結論都落不進：「通過」「部分通過」皆以 V5 成立為前提；「不通過」的條件（缺陷 3 未抓到或不穩定）不成立 → 判據缺口，不自行解讀

### R4 續行實測（2026-09-11 晚，使用者確認執行）
- **R5-1**：§3.12、§5（R5-x）、§6（V3／V4／V5／V6、R4-X、R4-C）、§11（上節標為失效）、§12 R4 寫入完畢，之後才有證據運行
- **R5-3 真 T0 基線**（V6 既有 UITests）：scratch＝`git archive aad6a9b` 的 AzathothsWhisper/ ＋ §5 R5-3 所列四檔（md5 皆核對）；T0 構建 CDHash `7ec4e483…`。
  preflight 第一次卡鑰匙串授權框（76s `does not have a process ID`，當時無人處理）→ 使用者處理後第二次 preflight 9s 通過（兩次皆不計證據）。
  **T0 證據輪 `ui-T0`**（零重編譯）：17 條＝15 綠、1 skip（BatchLive）、1 紅＝A-10（`ShellUITests.swift:174` state 停 3）；
  與當前代碼的 `ui-T10b` **逐條結論相同**（排序後逐行 diff 為空）。R5-5 在最終代碼上再比一次。T0 構建已 `lsregister -u`、DerivedData 已刪
- **R5-2 判定器 TDD**：新增 37 條（`table_valid`／V3 R4／V5 R4／V4 R4／`verdict` 優先序），舊 V3 測試按新 API 改寫 → RED 37（原因全為 API 未實作或 V4 不理 errors）→ GREEN 68/68。
  以本晚探索資料復算 `verdict`：T2.s2 為唯一 EXCLUDED 格、V5 經 T2.s3／T4.s1 成立、M2／M3 皆殺 → 「通過」——**只作判定器自檢，不是結論**（R4-C）。
  判定腳本現 1007 行、測試 906 行（超 800）→ R5-4 拆分
- **R5-2 三視角對抗核查**（Opus 5 ×3，唯讀、只准寫 scratch；每條需附可復跑的反例）：去重後 5 條「會改結論」的缺陷，逐條復現後全部採納並先 RED 後 GREEN 修正：
  ① GATE↔SIG 比多重集，而產出端 GATE 碼去重（兩側同為 `C2-STACK` 是 `CoverFlowGateLogicTests.bothSidesAreReportedIndependently` 釘住的形態）→ 合法運行被判無效；
  ② `EXCLUDED` 只在「全表僅一格不一致」時標記，多一個無關 flake 反而讓該格重獲 V5 端點資格（非單調）；
  ③ V5 端點候選未要求該步驟自身一致；④ GATE／SIG 解析丟掉 `<test>.` 前綴，別的測試的 GATE 可頂替本測試的缺失步驟；
  ⑤ 日誌 `started` 未與收尾行配對（截斷仍判有效），且 `GATE{…|FAIL|}` 可產生空簽名的「殺死」。
  修正後 73/73 綠；以探索資料復算 `verdict` 仍為「通過」（這五種形態在本晚資料中都沒出現，故結論未變）
- **R5-4 Phase 3（`/simcodex`）Round 1**：simplify 四視角（reuse／simplification／efficiency／altitude，Sonnet 5 並行）＋ codex review（gpt-5.6-sol，high）
  - 採納並修（基建／測量保真，不動契約與閾值）：① SIG 的 `<test>.` 前綴同 GATE 一樣必須是本測試（先前只修了 GATE，codex 給出可復跑反例）；
    ② `parse_log` 改追蹤「開著的迭代」，孤兒收尾行不再抵消未收尾的 started；③ **C4 觀測空窗**——落定後從原始水位重讀整段作 gesture，
    hold 由該段 `endOffset` 起算（codex 最擔心的一條：軌跡靜止與落定之間的回寫原本兩邊都不進）；④ trace 寫滿為止（短寫續寫、EINTR 重試），
    錯誤標記開頭補換行（否則黏進殘缺 record 被當成正常記錄）；⑤ 水位改用最後完整行的 `endOffset`，quiet 以位移判活動；
    ⑥ `readStable` 比 `CoverFlowGateLogic.stabilityKey`（label＋strip＋window＋每張卡）而非只比中心卡，且瞬時讀取失敗改為用掉重試而非放棄；
    ⑦ 落定逾時分流抽成純函數 `settleOutcome`，AX 失效不得報成產品 C6；⑧ 二進位身分：`expected` 缺失即 `[PROBE-WRONG-BINARY]`，比對走路徑元件邊界
  - 層級修正：`C5-DRIFT` 判據從 `CoverFlowUITests.swift` 搬進 `CoverFlowGateLogic.driftFindings`（原本裸寫在測試編排檔、**零單測覆蓋**），補 2 條單測；
    新增 `ProductCodeSingleSourceTests` 釘住 Python `PRODUCT_CODES` ≡ Swift 兩檔的 `code: "C…"` 字面量集合（CX9 單一源頭紀律的延伸）
  - 拆檔（P0，超 800 行規範）：判定器 1007 行 → facade 122 行 ＋ model／parse／table／rules／cli 五個模組；測試 906 行 → fixtures ＋ 6 個模組。
    機械簡化：刪死欄位 `Cell.raw_gate_codes`、`IterationInfo.invalid` 改由 `invalid_reasons` 推導、合併重複分支、`_build_iteration` 拆到每個函數 ≤50 行、
    `parse_xcresult` 由 4 次走樹改單次索引；`AppModel.live()` 的 DEBUG 分支只讀一次 environment
  - **上報使用者、未自行實施**（觸及判據語義）：① 前置步驟出產品 C6 → 方法提前 return → 後續步驟 MISSING → 被「不可判定」吞掉（修法需新增 blocked-step 規格碼）；
    ② C4 是否把落定後的 `nil` 原始回寫算作「變」（會改變 T1.s2/s3 的簽名集合）；③ 閘門組裝仍讀 `.standard` UserDefaults（只用到 language，語言本就由啟動參數覆蓋）
  - 驗證：Python 76/76；Swift 373 tests／39 suites、6 issues 全在既有 EDGE（無新增紅燈）；`build-for-testing` 成功；
    以同一份探索資料復算 `verdict`，拆檔前後**逐格相同**（通過、T2.s2 為 EXCLUDED、M2／M3 皆殺）
- **R5-4 Round 2（codex review，配額恢復後執行）**：**無新 P0；4 條新 P1**，並逐條驗收 Round 1 的修法。
  - Round 1 驗收：SIG 前綴、C4 空窗、`readStable` 穩定鍵、binary identity、`readStable` 重試＝**已堵住**；
    started/finished 與 AX/C6 分流＝**只修一半**（見下 ①③）；短寫寫入端正確但全行程健康檢查未閉合（見下 ②）
  - 新 P1（**未修，留待下一 session；均為保守方向或量測失真，非結論放寬**）：
    ① **落定樣本不是真正「連續」**：`readState()` 失敗時只設 `lastReadFailed`、沒清空 streak → 「成功×3 ＋ 失敗 ＋ 成功」會被當成連續四次而提前 `.settled`，
    繞過新的 `settleOutcome`（它只在逾時後才分流）。修法：讀取失敗即清 streak，並補「3 成功＋1 失敗＋1 成功不得 settled」測試
    ② **trace 健康檢查不是全行程閉合**：`watermark()` 讀完前綴只留 `endOffset`，前綴裡的 `write-error`／malformed／gap 被永久跳過；
    `verifyIdentity()` 只看 header 不看同一 snapshot 的 problems；hold 的 `trace.read` 失敗被 `?? []` 當成「沒有回寫」；非 T1 測試沒有全檔 audit。
    修法：每條測試結束前從 0 做一次全檔 audit，任何 problem → 未歸屬 `[PROBE-TRACE]` 使該迭代 invalid
    ③ **單獨的孤兒收尾行仍被接受**：`parse_log` 對「沒有開著迭代的 finish」只是靜默略過（我的修法只擋住了「孤兒 finish ＋ 未關 start」那一半）。
    修法：`parse_log` 回傳 pairing errors，無對應 start 的 finish、覆蓋已開迭代的 start 都進 `table.errors`
    ④ **T4 的單次 AX 失敗可冒充產品 C5**：`let before = probe.readState()?.label ?? "nil"` 把量測失敗變成 `C5-DRIFT`。修法：讀不到就報 PROBE 並停止該路徑
  - Q2 等價性（codex 以真實資料實跑）：閘門行為等價——`parse_xcresult` 同名節點仍取 DFS 第一個（實跑驗證）、`invalid` 改 property 後所有讀取點與 JSON 輸出不變、
    刪 `Cell.raw_gate_codes` 等價；唯一命名差異是 facade 不再有私有名 `_find_test_case_nodes`（改名為 `_index_test_case_nodes`＋`_match_test_case_node`），列 P2
  - Q3 殘餘風險排序（對確認性結論）：第 8 條（前置 C6 → 後續 MISSING，方向是假紅／假不可判定，不會假綠）＞ 第 10 條（nil 回寫語義，可能假綠也可能假紅，但不影響目前 V4 的殺死點）＞ 第 5 條（跨段序號／時間）
  - 本輪實跑：Python 76/76 OK；探索資料復算仍為「通過」、T2.s2 EXCLUDED、M2／M3 皆殺（與拆檔前一致）

### 暫停狀態（2026-09-11 深夜，使用者收工；已 commit 並 push）——**已於 2026-09-12 恢復並完成 R5-4 P1／R5-5／R5-6，見下列各節**
- **完成**：R5-1（計劃修訂）、R5-2（判定器 TDD＋3 視角對抗核查修正）、R5-3（真 T0 基線，V6 逐條相同）、R5-4（simcodex Round 1 全部落地＋Round 2 codex 驗收）
- **未跑**：R5-5（確認性閘門：`cf-m0-confirm` M0 ×10 ＋ `cf-M2-confirm`／`cf-M3-confirm` ×3，需使用者在場授權 Automation Mode、機器閒置約 25 分鐘）、R5-6（機械結論＋證據包）
- **恢復前必須先處置**（否則確認性運行的證據會帶著已知量測缺口）：R5-4 Round 2 的 4 條新 P1（落定 streak、trace 全檔 audit、孤兒收尾行、T4 的 `?? "nil"`）
- **待使用者裁決的三項**（觸及判據語義，不得自行實施）：① 前置 C6 → 後續 MISSING 的 blocked-step 規格碼；② C4 是否把落定後的 `nil` 回寫算作「變」；
  ③ V5 端點「十次一致」這條 R4 補正是否需再過一輪 Phase 1（它只收緊不放寬）
- 證據目錄 `~/Developer/bjork-h02-gate/`（含 `debate-R4/` 辯論全文、`mutant-runs/` 溯源、各輪 xcresult 與日誌）在 repo 之外，**未進版本庫**

### R5-4 Round 2 的 4 條 P1 修法落地（2026-09-12，恢復後第一步；基建修正、不動判據）
- TDD：先寫 6 條 Swift＋3 條 Python 測試 → RED（Swift 以 `audit` 未實作的編譯失敗為 RED；Python 2 failures＋1 error）→ 實作 → GREEN
  - ① 落定 streak：`GateSettleTracker`（不可變、`observing(nil)` 清空 readings 並記 lastReadFailed）進 `CoverFlowGateLogic`；`CoverFlowProbe.waitForStableCenter` 只用 tracker。
    單測 `readFailureClearsTheSettleStreak`（3 成功＋1 失敗＋1 成功 → 未 settled、outcome＝axUnreadable）、`trackerReportsNeverSettlesOnlyWhileAxStaysReadable`
  - ② trace 全檔 audit：`CoverFlowTraceFormat.audit(path:)`（從 0 重讀：unreadable／no-header／partial-tail／gap／time／nul／write-error／malformed）；
    `CoverFlowUITests.tearDown` 先於 `super.tearDown()`（app 未終止）做一次，問題以**未歸屬**的 `XCTFail("[PROBE-TRACE] <T>.audit …")` 上報（不印 GATE 行）→ 該迭代 invalid；
    `verifyIdentity` 同一 snapshot 有 problems → PROBE-TRACE；`scrollStep` 的 hold 讀不到 → PROBE-TRACE（不再 `?? []`）。
    單測 `fullFileAuditSeesProblemsBeforeTheWatermark`（水位之後看不見前綴 write-error，audit 看得見）、`auditReportsMissingHeaderPartialTailAndUnreadableFile`、`cleanTraceAuditsClean`
  - ③ `parse_log` 回傳第 4 元 `pairing_errors`：孤兒收尾行（無對應 started、或開著的是別的測試）與 started 覆蓋已開迭代都進 `table.errors` → `table_valid` False。
    測試 `test_lone_orphan_finish_line_is_an_error`（總數仍對得上的孤兒收尾行）、`test_start_overlapping_an_open_iteration_is_an_error`、`test_parse_log_returns_pairing_errors`
  - ④ T4：切 tab 前 label 讀不到 → `reportSingle(step: "T4.s2", code: "PROBE-AX")` 並 return；`driftFindings(before: String?, after: String?)` 任一側 nil → `PROBE-AX`（絕不 `C5-DRIFT`）。
    單測 `unreadableLabelAroundRebuildIsProbeNotDrift`
- 驗證（最終代碼）：Python 79/79；Swift 全量 **379 tests／39 suites、6 issues＝EDGE args 1,4,5,6,7,8，紅燈清單與 T0 逐條相同**（`unit-R55.xcresult`）；UITests target 編譯通過。
  V1：GateLogic 98.1%、TraceFormat 97.8%、`CoverFlowUITestTrace` 89.8%、Fixture／Music／組裝分支 100%。V2：pbxproj 相對 T1 前快照刪 0／增 62（與 T10 同）、xcscheme 只多 `systemAttachmentLifetime`。
  V7：`rel-R55/` Release 構建成功，`strings -a` 對 8 個測試專用符號＋`GateSettleTracker` 全為 0，陽性對照 `coverflow-center-label` 2／`CoverFlowViewModel` 6；6 個新增 app 檔首尾 `#if DEBUG`／`#endif`，`live()` 分支、binding 鉤子、AX value 皆在 DEBUG 內。V8：Strip md5 `a9ac2902…` 不變
- 產品碼集合未動（`ProductCodeSingleSourceTests` 綠）；凍結參數、凍結預登記表、§6 判據皆未觸及
- **對抗核查**（Opus 5，4 條修法 × 3 透鏡＝12 票，唯讀、每票須附可復跑反例）：11 票未駁倒（high）；**1 票駁倒（medium）**＋4 條殘餘疑慮，處置如下（均為量測保真，不動判據）：
  - 駁倒：`audit` 的 partial-tail 先讀後 stat 是 TOCTOU（假紅方向）→ 改為**同一份位元組**解析＋比對尾端（`CoverFlowTraceFormat.parse(_:offset:)` 抽出，`read` 與 `audit` 共用）
  - T4 的 `before` 單次無重試、一 nil 即整輪作廢 → 改取 T4.s1 **落定狀態**（連續 4 次相同讀數）的 label；仍 nil → PROBE-AX
  - streak 清空使逾時分流的 C6 觀測窗縮到「最後一段連續成功」，一次晚期 AX 失敗會把真正在動的產品 C6 降成探針 → tracker 另留全部成功樣本 `samples`；
    `timeoutOutcome`：AX 一路可讀**且尾段仍在變**才報 C6，尾段全同卻從未連續四次成功＝AX 斷續失敗 → 探針。新增單測 `lateSingleReadFailureKeepsProductNeverSettles`、`intermittentAxWithSteadyFramesIsProbeNotC6`
  - **實證關閉兩條疑慮**（臨時 XCTest 類 `-test-iterations 2`，用後即刪、檔案已還原）：tearDown 內的 XCTFail 掛在該次 **Repetition** 節點下、該次 `result=Failed`
    （`_iterations_from_test_case_node` 收得到，不會被丟棄）；日誌每次迭代只印一行 `failed` 收尾（不產生孤兒收尾行）
  - 記錄不處置：`s0`／`setup` 的 GATE 行引用未知步驟（既有結構；與未歸屬 PROBE 同樣落 invalid → 不可判定，無語義差）；持續性 I/O 失敗會留下內部自洽的截斷檔（需真實磁碟故障）；
    `""` label 是產品狀態（C1-LABEL-CARD-MISSING），guard 只攔 nil；凍結表產生時的落定實作允許跨失敗拼接，本次修法改變了該量測程序——R5-5 本就是重跑 V5 的確認性運行，差異若出現逐格上報
- **完整性批評**（Opus 5，對照 Codex ② 四個子句）：12 位核查者一致漏掉一條**假綠**路徑——`scrollStep` 保持期後 `probe.readState()?.labelIndex` 讀取失敗被壓成 nil、
  在 `writebackFindings` 被 `compactMap` 靜默丟掉（沒有 PROBE、沒有碼、迭代仍有效；它是非 binding 驅動拉回的唯一偵測點）→ 已修：讀不到 → PROBE-AX 並停止本步驟。
  ② 的 runner 接線（tearDown → 未歸屬 PROBE → invalid）原本零測試 → 新增 Python 回歸 `test_unattributed_teardown_probe_trace_invalidates_iteration`（依上述實證形態）。
  記錄不處置：判定端無規則要求「audit 曾執行」（缺席只在 launch 前崩潰時發生，該迭代本已 UNTAGGED invalid）；`verifyIdentity` 的 problems 檢查與既有 no-header／PROBE-WINDOW 同樣上報在 `<T>.setup`，
  落 table 級 errors（同路徑，仍為不可判定）；未登記方法的 started 巢狀在已開迭代內不記 pairing error（目前不可觸發）
- 加固後：Swift 兩個 suite 57 條綠、UITests target 編譯通過（`build-for-testing`）；Python 80/80

### R4-F 凍結表相符落地（2026-09-12，使用者拍板後；判據修訂已於 §6／§12 R5 記錄）
- TDD：`test_h02_gate_frozen.py` 12 條先 RED（6 errors＋5 failures）→ 實作 `FROZEN_REGISTRATION`／`FROZEN_ALLOWED_CODES`（model）、`evaluate_frozen_conformity`（rules，
  併入 `evaluate_v3` 三欄與 `verdict` 不可判定清單）、`_print_v3` 印三欄（cli，第三輪辯論補正）→ GREEN **92/92**。
  釘住：CE1（T3.s1 10/10 C6）、CE2（T1.s3 穩定多出 C4-SNAPBACK）、1/10 出現 F 外碼 → 不可判定；CE3（T4.s2 C3＋C2）相符；CE4／CE5（T1.s3／T2.s2 翻 10/10 PASS）相符、記偏離、T2.s2 仍為 V5 候選；
  合法 R4-X 9/1 相符；五個 C2 步驟全 PASS → 部分通過；M2／M3 帶新碼不受限；F 表覆蓋全部登記步驟且 ⊆ PRODUCT_CODES；CLI 輸出含 `frozen_conformity_ok` 與 R4-F 理由
- 探索資料復算（只作判定器自檢）：仍「通過」、T2.s2 EXCLUDED、`frozen_conformity_ok=True`、偏離只有 `T2.s2: 1/10 次與凍結登記 FAIL['C2-STACK'] 不同（iter 4 PASS）`
- R5-5 prep：M2／M3 scratch 由最終代碼（HEAD `b74636f`＋`worktree.patch`）rsync 重建，只差 `CoverFlowStrip.swift`（md5 M2 `57da040c…`／M3 `48687466…`；repo `a9ac2902…`），溯源在 `mutant-runs-R55/`

### R5-5 確認性閘門實測（2026-09-12 晚，使用者在場授權 Automation Mode、機器閒置）
- 兩次中止（不計證據、未進入測試）：`cf-m0-confirm-aborted1/2-automation-timeout.*`——runner 60 秒內未取得 Automation Mode 授權（使用者不在機器前），0 個 Test Case；
  第三次啟動由使用者放行後正常進入
- **`cf-m0-confirm`（M0 ×10，閘門配置；CDHash `2343d542…`，IDENTITY 40 次同一 Products、instances=1；started＝finished＝40；PROBE 0；40 次 tearDown 全檔 audit 皆乾淨）**：

| 步驟 | 十次結果 | 對照凍結表 |
|---|---|---|
| T1.s1／T2.s1／T3.s1 | 10/10 PASS | ＝ |
| T1.s2 | 10/10 FAIL{C2-STACK\|G=T13\|over=T12\|side=L} | ＝（簽名與探索輪相同） |
| **T1.s3** | **4 FAIL{C2-STACK\|G=T11\|over=T12\|side=R}／6 PASS → INCONSISTENT** | 偏離（T8 部分跑曾見 5/4；探索輪 cf-m0 為 10/10） |
| **T2.s2** | **9 FAIL{C2-STACK\|G=T00\|over=T01\|side=R}／1 PASS（iter 8）→ INCONSISTENT** | 偏離（與探索輪同形態） |
| T2.s3 | 10/10 FAIL{C2-STACK\|G=T19\|over=T18\|side=L} | ＝ |
| T4.s1 | 10/10 FAIL{C2-STACK\|G=T19\|over=T18\|side=L} | ＝ |
| T4.s2 | 10/10 FAIL{C1-OFFSET\|label=T19\|centered=T16\|strides=+3, C2-STACK\|G=T16\|over=T17\|side=R} | ＝ |

  - `v3`：`run_valid=True`；`frozen_conformity_ok=True`（零 F 外碼；偏離只有上列兩格翻 PASS）；缺陷 3 **CAUGHT**（T4.s2 10/10 一致）；缺陷 2 由 T1.s2／T2.s3／T4.s1／T4.s2 承擔；
    **不一致兩格 → R4-X 只能豁免一格 → `consistency_ok=False`**（`excluded=None`）
- **`cf-M2-confirm`／`cf-M3-confirm`（×3，閘門配置；scratch 由最終代碼重建、只差 Strip；CDHash M2 `44824442…`／M3 `39b83889…`；IDENTITY 各 12 次指向自己的 Products、instances=1；started＝finished＝12；PROBE 0；audit 全乾淨）**：

| 變異 | 步驟級結果（3/3） | 殺死步驟（M0 10/10 PASS ∧ 變異 3/3 FAIL 簽名一致） |
|---|---|---|
| M2 | T1.s1／T2.s1 FAIL{C2-STACK\|G=T11\|over=T10\|side=L}；T3.s1 PASS；T4.s2 **PASS**（`.leading` 使 C1-OFFSET 消失）；其餘 FAIL{C2-STACK}（T1.s2 2/3） | **T1.s1、T2.s1** |
| M3 | 九格全 FAIL{C2-STACK}（T3.s1＝G=T10\|over=T09\|side=L；T4.s2 只剩 C2、C1-OFFSET 消失） | **T1.s1、T2.s1、T3.s1** |

  與探索輪 T9 的殺死點與簽名逐格相同；殺死全落在鍵盤與首次載入步驟，不依賴合成捲動慣性（S7 不需要）
- **機械結論（`verdict --s2-verified`，R4-C）：部分通過**——唯一理由「V3 一致性不成立：T1.s3、T2.s2」。V5 成立（T2.s1 10/10；端點 T2.s3／T4.s1 ALL_FAIL_CONSISTENT 且碼恰 {C2}）；缺陷 3 CAUGHT；缺陷 2 重現；
  R4-F 相符；三份 `table_valid`；M2／M3 皆殺（權重待使用者裁決）。輸出：`cf-*-confirm.table.txt/json`、`cf-m0-confirm.v3.txt`、`cf-M2/M3-confirm.v4.txt`、`R55-verdict.txt`
- **V9**：三份 xcresult 附件＝視窗截圖 PNG（90／27／27，**全為 2400×1600**）＋ 契約報告 txt（90／27／27）＋ XCUITest 對 `"EDITOR" Button` 的 debug description（範圍限 target app）；spindump 0
- **V6 既有 UITests（`ui-R55`，§10 不帶閘門參數）**：preflight 第一次撞鑰匙串授權框（74s `does not have a process ID`，重建後 CDHash 變化；memory `rebuild-keychain-prompt-blocks-uitests`），
  使用者放行後第二次 preflight 15s 通過（兩次皆不計證據）；證據輪 17 條＝**15 綠、1 skip（BatchLive）、1 紅＝A-10（`ShellUITests.swift:174`，同基線）**，
  與 `ui-T0`（真 T0 樹）正規化後**逐條相同** → V6 ✓
- 收尾（HF5）：M2／M3 app 與 runner `lsregister -u`，LaunchServices 殘留 0；scratch DerivedData 改名退役（未刪）

### R5-6 證據包（2026-09-12；全部證據在 `~/Developer/bjork-h02-gate/`，repo 內只有代碼與本計劃；未 commit、未 push）

| # | 結果 | 證據 |
|---|---|---|
| V1 | ✓ GateLogic 98.1%、TraceFormat 97.8%、Trace 89.8%、Fixture／Music／組裝 100% | `unit-R55.xcresult`（xccov） |
| V2 | ✓ pbxproj 刪 0／增 62（同 T10）；xcscheme 只多 `systemAttachmentLifetime` | diff vs `pbxproj-preT1`／`xcscheme-preT1` |
| V3 | **部分成立**：缺陷 3 CAUGHT（T4.s2 10/10 `C1-OFFSET strides=+3`＋`C2-STACK`）；缺陷 2 重現（T1.s2／T2.s3／T4.s1／T4.s2 10/10 C2）；**一致性 ✗（T1.s3 4/6、T2.s2 9/1 兩格）**；R4-F 相符 | `cf-m0-confirm.*`、`cf-m0-confirm.v3.txt` |
| V4 | M2 殺（T1.s1、T2.s1）；M3 殺（T1.s1、T2.s1、T3.s1）；簽名與探索輪相同；**權重由使用者裁決** | `cf-M2/M3-confirm.*`、`.v4.txt`、`mutant-runs-R55/` |
| V5 | ✓ T2.s1 10/10；端點 T2.s3／T4.s1 ALL_FAIL_CONSISTENT 且碼恰 {C2}；S2 已知點命中（§11） | `cf-m0-confirm.v3.txt` |
| V6 | ✓ 單測 379/39 suites 紅燈＝T0；既有 UITests 17 條與 `ui-T0` 逐條相同 | `unit-R55.*`、`ui-R55.*`、`ui-T0.*` |
| V7 | ✓ Release 構建成功；`strings` 對 9 個測試專用符號全 0；6 個新檔整檔 `#if DEBUG` | `rel-R55/`、`rel-build-R55.log` |
| V8 | ✓ `CoverFlowStrip.swift` md5 `a9ac2902…` | `mutant-runs-R55/M0-hashlist.txt` |
| V9 | ✓ PNG 全 2400×1600（90／27／27）；txt 只有契約報告與 XCUITest debug description；spindump 0 | scratchpad `att-*-222809/` |
| V10 | ✓ H-05 行文與交接檔補註未動（T11 已完成） | `git diff` 不含 ACCEPTANCE／交接檔 |

- **機械結論（R4-C）：部分通過**——缺陷 3 穩定、缺陷 2 重現、V5 成立、M2／M3 皆殺；唯一未成立＝V3 一致性（兩格不一致，R4-X 只能豁免一格）。
  依 R4-C #4「帶選項上報，使用者裁決是否開始第四次修復」；V4 權重亦由使用者裁決
- 已知量測盲區（D2）：C4 對「nil→同值瞬時擺動」不可偵測；殘餘清單見 §11「完整性批評」
- 不一致兩格的觀察（只記事實）：T1.s3＝反向捲回時滯後 zIndex 約半數不留下（T8 部分跑 5/4、探索輪 10/10、本輪 4/6）；T2.s2＝左端點 10 次有 1 次不疊（探索輪 9/1、本輪 9/1）；
  兩者皆為「時紅時綠」的 C2 步驟，不影響缺陷偵測（其餘 C2 步驟 10/10），但按 §6 護欄不得為使其穩定而放寬判據

## 12. 附錄：評審辯論記錄

### R1（2026-09-11）：Codex（CX）＋ Opus 三視角（TV＝test-validity、HF＝harness-fidelity、SS＝scope-simplicity）

| ID | 級 | 摘要 | 處置 | 理由／落點 |
|---|---|---|---|---|
| CX1 | P0 | §3.7 T2「T19 端預期 C1-OFFSET」與 §3.8「T2 綠」矛盾 | 採納 | v1 修訂漏改；§3.9 為唯一預登記來源 |
| CX2 | P0 | 變異可被 M0 已有紅燈「繼承殺死」 | 採納 | §3.11 步驟級差異：M0 該步驟須 10/10 PASS |
| CX3 | P0 | `scrollByDeltaX` 返回前的拉回看不到，T1 對 M3 假陰 | 修改採納 | §3.5 trace（bind＋事件性質＋live 通知）覆蓋整段；合成事件觸發不到機制時 V4 記未殺、走 S7，不宣稱已殺 |
| CX4 | P1 | 暖身不斷言會吞掉首個錯誤 | 採納 | T1.s1 改為契約步驟 |
| CX5 | P1 | C2 缺交疊區定位校準 | 採納 | 參考點前置＋產品／探針分流（§3.7 C2） |
| CX6 | P1 | T0 推不出 T2 綠／T4 紅 | 部分採納 | 標為推測、T7 後凍結；**駁回**另建近產品 render harness：UITest 本身即產品級 harness，孤立 strip 的 20 項 harness 正是 §5.1 自己淘汰的方法 |
| CX7 | P1 | 簽名需正規化 | 採納 | `SIG{test.step|碼|離散欄位}` |
| CX8 | P1 | 變異可追溯性 | 採納 | §3.11 改名定性、記雜湊／diff／CDHash |
| CX9 | P2 | 旗標雙寫 | 採納 | 共用檔單一來源 |
| CX10 | P2 | `strings` 不足為證 | 採納 | V7 主證據改源碼結構 |
| CX11 | P2 | C0 不宜作穩定簽名 | 修改採納 | C0 改像素驗證；AX 缺席但像素是卡 → `[PROBE-AX-CULL]` |
| CX12 | P2 | 範圍膨脹（ACCEPTANCE 治理） | 採納 | 起初傾向駁回；SS7 補強的論證成立（基線變更需簽字；V3 未過時新測試不是有效證據）→ G4 只留 H-05＋交接檔補註，其餘移 N6 |
| TV1 | P0 | 缺陷 2 條款在 M0 上無區分力；漂移形態下必不過、會逼人「修紅」 | 部分採納 | 採 (a)：§3.10 誠實範圍＋分支＋修復計劃強制 DoD；**駁回 (b)** resize 路徑入本計劃：非真機症狀，且會寫入使用者真實 app 共享的窗框設定（§2）——保留為「不可重現」分支的使用者選項；**駁回 (c)** Strip 內儀器：變異替換的正是 Strip，無法同口徑比較，且在待修檔內加儀器有觀察者效應，屬修復計劃 |
| TV2 | P1 | 缺「目標身分」條款，漂移讓 T2／T3 靜默綠、焦點誤判 | 採納 | C3；焦點只定義為 label 未變 |
| TV3 | P1 | M2／M3 預期與實測註記矛盾，按機制大概率存活 | 採納（重登記）／駁回 resize | §3.9 改為推測存活；S7 泛化到 M2；resize 同 TV1(b) |
| TV4 | P1 | PROBE 吸收產品成因 | 採納 | C6、C0-BLANK-CARD、C2-GAP；每個 PROBE 需健康證據 |
| TV5 | P1 | 零延遲假 Music 使首次載入成競態 | 採納 | 400ms 預設＋0ms 資訊對照 |
| TV6 | P2 | frame 與像素不同時刻 | 採納 | snapshot→截圖→snapshot；C2 前提 isFacing(G) |
| TV7 | P2 | 非端點陽性對照只剩 T1 | 採納 | T2.s1 為 V5 主對照 |
| TV8 | P2 | 點卡片可能把焦點交給 ScrollView | 採納 | 點 label；S3 判別式 |
| HF1 | P0 | 判定命令抓不到 SIG、看不見無標籤失敗 | 採納 | §3.12 腳本；綠基準＝Passed |
| HF2 | P1 | 零延遲（同 TV5）；另建議量真機 AE 延遲 | 部分採納 | 採延遲；**駁回**量真機延遲：決定路徑的是次序而非毫秒數，量測需使用者曲庫與 AE 授權，不值得 |
| HF3 | P1 | 漂移歸類錯（同 TV2） | 採納 | 同 TV2 |
| HF4 | P1 | 語言與窗寬取決於共享 UserDefaults | 採納（部分） | `launch(language:"en")`＋`[PROBE-WINDOW]`；**駁回**以 argument domain 釘窗框：斷言已能擋住偏差，釘窗框需寫死螢幕幾何字串，YAGNI |
| HF5 | P1 | 變異運行缺二進位身分證明 | 修改採納 | 身分斷言只加在新測試類；**不改** `terminateStaleInstances` 既有行為（避免擴大既有測試回歸面）；清理 lsregister／DerivedData |
| HF6 | P1 | 系統自動截圖會存全螢幕 | 採納 | scheme 關閉；只附裁切圖；V9 腳本化 |
| HF7 | P1 | §7 與 §3.8 預登記矛盾 | 採納 | §7 改指向單一來源 |
| HF8 | P2 | S4／S7 不量事件性質 | 採納 | 局部 NSEvent 監聽＋live 通知入 trace |
| HF9 | P2 | Debug＋覆蓋率＋AX 輪詢改變時序 | 採納 | §3.13 `-O`、覆蓋率關；捲動段暫停輪詢 |
| HF10 | P2 | trace 截斷偏移陷阱 | 採納 | 水位讀取、O_APPEND、序號 |
| HF11 | P2 | 影響面漏 `AppUITestCase` | 採納 | §8 |
| HF12 | P2 | 證據只在 /private/tmp | 採納 | `~/Developer/bjork-h02-gate/` |
| SS1 | P1 | V3 的缺陷 2「各自」不可滿足；建議開工前問使用者 | 採納拆分／**駁回開工前提問** | 漂移形態是否出現是 T7 首跑才知道的實證問題；§3.10 已把「不可重現」預登記為上報分支，裁決權在閘門時交給使用者——不必先問假設性問題（此點提交 Codex R2 辯論） |
| SS2 | P1 | V4 超出使用者硬門檻、M2 可預見卡死 | 修改採納 | V4 保留但權重由使用者決定；殺死判據改步驟級差異（與 CX2 調和）；trace／S6 保留（CX3 所需）；S7 條件式且須先徵得同意 |
| SS3 | P1 | Phase 3／4 改讀依賴矛盾集合；終點未處理 | 採納／駁回 `XCTExpectFailure` | 凍結表單一來源、流程偏離聲明待簽字；`XCTExpectFailure` 會讓套件轉綠，與使用者「EDGE 誠實紅」裁定相牴觸 |
| SS4 | P1 | grep 抓不到 SIG（同 HF1） | 採納 | 同 HF1 |
| SS5 | P1 | 「只准修測試」開了「修紅」口子 | 採納 | §6 護欄 |
| SS6 | P1 | 缺 C3（同 TV2） | 採納 | 同 TV2 |
| SS7 | P2 | G4 範圍擴張、需簽字 | 採納 | 同 CX12 |
| SS8 | P2 | TDD／覆蓋率未誠實處理；trace 同步 I/O | 採納（寫檔部分於 R2 翻案） | 純邏輯抽出先 TDD；V1 逐檔覆蓋率。「背景佇列寫檔」在 R2 被 Codex 的 drain 邊界問題推翻，改為主執行緒同步 `write(2)`（見 R2-4） |
| SS9 | P2 | 多條 DoD 不可判定 | 採納 | T2 DoD 改單一來源接線測試；T3／T4 順序；V2 對 T1 前快照；V8 以 T0 md5；目視改 AX 讀數 |
| SS10 | P2 | V9 與 S2 全螢幕備案衝突 | 採納 | 同 HF6；S2 備案在記憶體內裁切 |

### R2（2026-09-11）：Codex 複審 v2

**(A) 對 R1 駁回／修改項的表態**：CX3、CX6、CX11、TV1(b)(c)、TV3、HF2、HF4、HF5、SS1、SS3 ——**接受**（不再提）。
**SS2 ——重提且論證成立 → Codex 勝**：殺死集合不能在看到變異結果後才補定，而 §3.9 的 M2／M3 多格仍是「未知」。

**(B) 新問題與處置**

| ID | 級 | 摘要 | 處置 | 落點 |
|---|---|---|---|---|
| R2-1 | P0 | V4 的預登記不可執行（＝SS2 重提） | 採納 | §3.11：允許殺死類別＝**全部產品碼**、兩變異一視同仁、殺死步驟限 M0 10/10 PASS 者，於任何變異運行前寫死；症狀相符只作註記 |
| R2-2 | P1 | trace 缺生命週期與 drain 協議（切 tab 重建會重複安裝；背景寫入無可驗證的落盤邊界） | 採納（drain 部分修改） | §3.5：行程級單例、只在測試模式組裝時安裝一次、每次啟動新檔＋header；**不做 flush 握手，改為主執行緒同步 `write(2)`**——從根上消除待寫佇列，比設計一個握手協議簡單且可證 |
| R2-3 | P1 | 二進位身分斷言未經 spike | 採納 | §3.13 主證據改為 trace header 自報 bundle 路徑；新增 S0 |
| R2-4 | P1 | S7 自注入不等同真觸控板 | 採納 | §3.11：S7 成立須在 M0 重現已知的捲動—回寫狀態轉移，否則只稱實驗、不得用於殺死 |
| R2-5 | P1 | C2 空交集行為未定義 | 採納 | §3.7：空交集 → 產品 `C2-GAP`；入 `CoverFlowGateLogic` 正反例 |
| R2-6 | P2 | UNTAGGED 解析需以真實 xcresult 驗證 | 採納 | §3.12：T7 dry-run 用真實 xcresult（同步驟多 SIG＋故意失敗），留作夾具 |

### R3（2026-09-11）：Codex 窄範圍確認

- R2-1（殺死集合＝全部產品碼、限 M0 10/10 PASS 步驟、變異運行前寫死）：**接受**——「消除了事後挑選；集合雖寬，只證明變異破壞了既定產品契約，不構成假殺死」
- R2-2（行程級單例＋主執行緒同步 `write(2)`）：**接受**——「同機讀取不 fsync 不影響可見性」；補充：短寫／寫入錯誤升格為 `[PROBE-TRACE]`（已併入 §3.5）
- 結論：**可定稿開工**

### R4（2026-09-11 晚）：閘門判據缺口的 Phase 1 快速複審（Codex gpt-5.6-sol，reasoning high，三輪；使用者確認執行）
觸發：`cf-m0` 字面上落不進 §6 任何結論分支（V5 端點條款在凍結表下按構造不可滿足；V3 一致性因 T2.s2 9/1 不成立）。全文存 `~/Developer/bjork-h02-gate/debate-R4/`。

| ID | 我方主張 | Codex | 勝方 | 落點 |
|---|---|---|---|---|
| J1 | V5 端點條款是判據缺陷（要求先無缺陷 2 才准修缺陷 2） | 對 | 我方 | §6 V5 修訂 |
| J2 | V5 改寫「只由凍結表推出、不算看結果改判據」 | 錯：凍結表本身就是 T7 的 M0 結果，屬事後修訂；應按**契約維度**排除 C2，且依 §6 護欄「凍結後任何改動 → 重跑 V5」 | Codex | §6 V5 用契約維度寫法；本晚運行降為探索；結論只出自確認性運行 |
| J3 | T2.s2 窄範圍處置「不改 V3 措辭」 | 錯：排除即 V3 修訂；條件不夠窄（未限定運行、未限一格、根因不能寫成已證實） | Codex | §6 R4-X（≤1 格、限確認性 M0、(b) PASS 與 C2 各 ≥1、零證據權重、根因記為推論） |
| J4 | 以 J2＋J3 直接判「通過」 | 錯：須先完成修訂並跑確認性運行 | Codex | R5-5 |
| J5 | Phase 4 對 T2.s2／T1.s3 偶發 PASS 常設容忍 | 錯（**最擔心**）：會讓「偶爾仍疊住」的半修版本過關，重演前三次失敗 | Codex | 撤回；修復候選與變異無任何豁免 |
| J6 | 本會話處置不影響證據 | (i)(ii)(iii) 對；(iv) 錯：09-08 不是 T0 | Codex（iv） | R5-3 重建真 T0 樹；(i)(ii) 記流程偏離 |
| 比例下限 | 不需要（被排除格零權重） | R2 同意 | 我方 | R4-X 不設比例 |
| R2 補強 | — | `table_valid` 須含整條測試存在、每步恰一 GATE、errors 零；V5 逐次檢查而非聯集；(b) 措辭；缺無效運行分支；S1 須同步 §3.12／§5／§11；S5 須在最終代碼重驗 V1／V2／V7–V9 | Codex（已查證 `present_tests`、`evaluate_v4`、MISSING 屬實） | §3.12、§6、§5 R5-x |
| 變異重跑 | 無條件重跑 M2／M3（比「是否改動」或輸入閉包更嚴更簡） | R3 無異議 | 我方 | R5-5 |
| ≥2 格不一致 | 映射為「部分通過」而非無結論 | R3 同意（證據強度不足 ≠ 證據無效） | 我方 | R4-C 第 4 條 |
| R3 補強 | — | `xc_result` 與 GATE 一致性；R4-C 優先序；缺陷 2／3 精確布林謂詞；R5-x 與 Spike S1–S7 撞名 | Codex（已查證 `_build_iteration` 只攔「Failed 無訊息」） | §3.12、§6、§5 |

- 我方輸在哪：想用暴露判據缺陷的同一份資料直接宣布通過，而計劃自己的護欄早已要求修訂後重跑；J5 會開出一個常設豁免，正好是前三次「測試看起來可以、真機仍錯」的通道
- Codex 最擔心的一步（R2／R3）：確認性 M0 可能同時出現兩格不一致 → 依 R4-C 落「部分通過」，交使用者裁決

### R5（2026-09-12）：三項待裁決事項＋判定器凍結表缺口的 Phase 1 快速複審（Codex gpt-5.6-sol，reasoning high，兩輪；thecure）
全文存 `~/Developer/bjork-h02-gate/debate-R5/`。證據：歷史 222 格 GATE（cf-m0／M1／M2／M3／m0-gate／0ms）C6＝0、C4-*＝0；探索 V4 殺死點與 C4 無關。

| ID | 我方主張 | Codex | 勝方 | 落點（**使用者 2026-09-12 拍板：執行**） |
|---|---|---|---|---|
| D1 blocked-step | 不新增、延後；出 C6 一律不可判定 | 方向對；「一律不可判定」錯——只有 C6 造成登記步驟 MISSING 或 `s0`／`setup` 未知步驟 error 才必然 table_valid 失敗（C6 落在最後登記步驟時表格可有效）；若日後加 BLOCKED 只能是診斷型（不算 PASS/FAIL、不進 V3/V4/V5、仍使 table_valid 失敗） | Codex（限縮） | 預登記句採限縮版；不加 BLOCKED |
| D2 C4 nil | 維持 nil 不算變 | 方向對；我方理由 (b)「歷史零 C4」與 (c)「終態由 C1 守住」不成立——`11→12→nil→12→13` 與 hold `nil→13` 的瞬時擺動會假綠，C1／C2 只量落定終態、C5 只涵蓋切 tab；但把 nil 算變會假紅，故凍結現行語義並明列為量測盲區 | Codex（理由） | R5-5 維持；證據包列「nil→同值瞬時擺動」為 C4 盲區 |
| D3 V5 十次一致 | 須過 Phase 1；只收緊 | 對；條文不夠精確：須定義 ALL_PASS＝十格皆 PASS、ALL_FAIL_CONSISTENT＝十格皆 FAIL 且十次完整正規化 `sig_set` 相同且產品碼投影恰為 {C2-STACK}；INCONSISTENT 與 EXCLUDED 皆不得為 V5 候選（與 `evaluate_v5` 實作一致） | Codex（措辭） | 以此精確解讀記入 §12，§11 不動 |
| D4 凍結表缺口（Codex 最擔心） | — | `evaluate_v3`／`verdict` 完全不讀 §11 凍結表：T3.s1 10/10 C6、T1.s3 穩定多出 C4-SNAPBACK 仍「通過」（我方復現，另證 T4.s2 出 C3 替代 C1、T1.s3／T2.s2 翻 10/10 PASS 亦「通過」）；建議 R5-5 前回 Phase 1 | Codex | 見 R4-F |
| R4-F 變體 S（我方） | 每次產品碼 ⊆ F(step) **且**凍結 FAIL 步驟不得十次全 PASS；違反 → 不可判定 | **錯**：把 T7 單次觀察升格為「必須持續失敗」的契約——(1) V5 明文接受端點 ALL_PASS（`test_registered_c2_step_all_pass_is_consistent_not_excluded` 釘住）；(2) 五個 C2 步驟全 PASS 是 §3.10 預登記的「缺陷 2 不可重現 → 部分通過」分支，S 使其不可達；(3) §6 V3 明文接受 T4.s2 以 C1／C3／C5 之一抓缺陷 3 | Codex | 撤回 S |
| R4-F 變體 N′（Codex） | — | PASS 步驟 F＝∅；T1.s2／T1.s3／T2.s2／T2.s3／T4.s1 F＝{C2-STACK}；T4.s2 F＝{C1-OFFSET, C3-TARGET-MISS, C5-DRIFT, C2-STACK}；**每次迭代的產品碼投影 ⊆ F(step)**；不要求凍結 FAIL 步驟日後仍失敗；ALL_PASS 偏離只記證據包、由既有 V3／V5／缺陷 2 分支判定；只對 `cf-m0-confirm`（變異運行不適用，V4 已是步驟級差異）；作為 R4-C「不可判定」的獨立觸發（V3 回傳 `frozen_conformity_ok`／`reasons`，不併入 table_valid）；R5-5 前 TDD 實作 | Codex | 採 N′，寫入 §6 R4-F；先 RED 後 GREEN（見 §11） |

- Codex 最擔心（R2）：把探針越穩、症狀越少的運行制度化成「不可判定」——那會把已知假綠修成假不可判定，比漏讀凍結表更糟
- **R3 整體確認**（thecure 第 7 步；完整方案＋投入順序打包提交）：判定語義無致命欠落・矛盾；兩點補正（採納）：① `_print_v3`／`verdict` 須印出三個新欄位，否則 CE4／CE5 的偏離只存在於記憶體；
  ② §6 V5 的「待使用者確認」須改為已確定、§12 的「待拍板」同步收斂。投入順序妥當。**最易失敗的一步＝`cf-m0-confirm ×10`**：40 次 GUI 迭代中任何一次 PROBE、未歸屬失敗、前置 C6 造成 MISSING 或 F 外碼即不可判定，且首份運行規則不容輕率重試
- 使用者 2026-09-12 拍板：「那就繼續執行吧」——D1／D2／D3／D4（N′）全部按上表落點執行

### R6（2026-09-12 深夜）：閘門結論後的兩項裁決（V4 權重、部分通過後是否啟動第四次修復）——thecure 三輪，Codex gpt-5.6-sol high；全文 `debate-R5/cure-*-r6*.{md,txt}`

| ID | 我方主張 | Codex | 勝方 | 落點 |
|---|---|---|---|---|
| J1 V4 權重 | 「閘門靈敏度已示範」，足以作第四次修復的仲裁者 | 窄義正確：**必要否決控制**（候選不再殺 M2／M3 即否決），不是充分證明；殺死點只在鍵盤／首載，不得宣稱覆蓋捲動慣性 | Codex（限縮） | A |
| J2 啟動修復、不先查兩格不一致 | 不一致是產品行為，量測問題已排除 | 行動對、因果斷言錯：`readStable` 不看 z-order、C2 由單張截圖 5×5 一點決定、T2.s2 PASS／FAIL 的 AX 幾何相同——截圖／compositing 取樣時機未排除，成因只能記推論 | Codex（論證） | B |
| J3 修復計劃預登記 | (a) 候選任一 C2 即不通過 (b) 候選 20/20 PASS 即與 M2/M3 可區分 (c) 只有動 AX／fixture 才回 Phase 1 | (a) 對；(b) 不足：M2／M3 須從候選同一 tree 重建實跑；(c) 過窄：任何凍結輸入改動都回 Phase 1；另缺過渡態手段先證紅、D2 處置、手滑可判定程序 | Codex | C.2／C.4–C.7 |
| J4 不重跑、不改判據 | — | 對；不通過只限缺陷 3 未抓到或 T4.s2 不穩定，本輪不落入 | 我方 | B |
| R2 整體確認 | 打包方案 | 三處文本異議：C.1 **R4-F 不得套到候選**（只屬 cf-m0-confirm）→ 候選改單一規則；C.5 D2 二擇一各自要可證偽條件；C.6「任何可見覆疊」錯（Cover Flow 本有正常交疊）→「非應在最上層的鄰張遮住應 frontmost 的卡」＋逐路徑參數；D 順序「M0 證紅」改「M0 或受控壞形態」 | Codex | 全部採納 |
| R3 修正版整體確認 | — | **「無い」** | — | 定稿 |

- Codex 最擔心：把「受控壞形態能紅」誤當「實體觸控板過渡態已覆蓋」——須同一訊號、同一失敗謂詞、實體手滑證據鏈；最易失敗的一步＝過渡態證偽手段的負對照成立
- **定稿方案（待使用者確認執行）**：A V4＝必要否決控制；B 啟動第四次修復、不重跑 R5-5、不改 §6；C 第四次修復計劃預登記 C.1–C.7（候選單一規則：有效運行且四測試 ×20 每格全 PASS，任何產品 SIG 即不通過，PROBE＝無效；
  M2／M3 從候選同一 tree 重建 ×3 且各保留一個歷史殺死點 3/3 簽名一致；診斷儀器只解釋不裁決；過渡態手段先在 M0 或受控壞形態證紅；D2 二擇一各附可證偽條件 `C4-NIL-DWELL`／`C4-NIL-SHIFT`；
  手滑失敗謂詞與逐路徑參數、每路徑 ≥5 次；任何凍結輸入改動回 Phase 1）；D 順序：確認 → 收官 → 新計劃 Phase 1 → 儀器健康 → 過渡態證紅 → 產品修復 → 候選 ×20 → M2／M3 ×3 → 實體手滑 → 結論

