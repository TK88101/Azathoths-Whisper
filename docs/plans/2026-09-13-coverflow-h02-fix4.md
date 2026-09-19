# H-02 缺陷 2／3 第四次修復 —— 實施計劃（v4 定稿）

- 日期：2026-09-13
- 上游：`docs/plans/2026-09-11-coverflow-h02-uitest-gate.md`（閘門計劃；§11「R5-6 證據包」、§12「R6」定稿方案＝本計劃的唯一輸入）；
  `docs/plans/2026-09-09-coverflow-h02.md`（交接檔；§2 三次失敗、§5.2 修復方向、§5.3 收尾清單）
- 基線：分支 `feat/h02-uitest-gate`，HEAD `a1d3407`，工作樹乾淨，**未合併 main**
- 模式（fatboyslim Phase 0）：本 session＝**normal**（只做 Phase 1：寫 Plan → Codex 評審辯論 → 定稿；不動產品源碼、不跑 UITest、不 commit）。
  實施 session 開工時重判；本計劃預登記推薦 **normal**——每場 UITest 需使用者在場授權 Automation Mode（memory
  `automation-mode-timeout-needs-user-present`），無人值守段不存在；候選迭代受 §5.1 絕對上限與熔斷約束（操作護欄，需使用者批准）
- 狀態：**v5 定稿（2026-09-18，使用者批准執行）**——macOS 27／Xcode 27 升級使 26.6.2 的全部 UI 基準失效，經 thecure 四輪辯論收斂：新增**場 0 基準重建**（§6；§3 B／N2 的有限例外）、**G6 無 AX 遠跳條款**（範圍擴大，使用者批准）、**H3 改走 b′**（Strip 介面不動）、Z1 五項結案、判定器改 **R27 active profile**（staging→原子啟用）。變更逐條見 §13「v5 提案」，辯論全文 `~/Developer/bjork-h02-gate/fix4/debate-R8/`。以下 v4 沿革保留：
- v4 沿革：**定稿（2026-09-13）**。v1 經 Codex R1（12 條）＋ Opus 四視角（53 條）改為 v2；v2 經 Codex R2（10 條，全部採納）改為 v3；v3 經 Codex R3 整體確認（4 條殘餘，全部採納）改為 v4；Codex R4 窄範圍確認：三處與 §14 R3 表「無異議」，僅 R3-1 措辭殘餘一處，已按其建議改為 `physical_valid_base／_off／_on`（§14 R4）。**使用者 2026-09-13 確認執行並批准 §5 操作護欄**；ACCEPTANCE H-02 狀態變更未另行明示 → 依 N3 留待使用者拍板，本計劃不動 ACCEPTANCE

**用語**：「產品源碼」＝`Features/CoverFlow/*.swift` 等產品側檔案；「產品碼」只指 C0–C7 失敗碼（判定器 `PRODUCT_CODES`）。

## 0. 複述（slipknot 17）

- **目標**＝在真實 app 組裝上修好缺陷 2（傾斜的鄰張壓住正對觀者那張）與缺陷 3（初始值路徑少滾 3 個 stride、末 3 項不可達），
  並以閘門計劃的四條 XCUITest（`-test-iterations 20`）、歷史變異負對照（M2／M3）、過渡態證偽手段、實體觸控板手滑四道閘全部通過為完成。
- **完成標準（本 session）**＝本計劃定稿：C.1–C.7 每條展開成可判定條款（輸入、規則、判定器、無效／不通過／不可建／不可判定的互斥邊界、回 Phase 1 觸發）；
  修復假說與影響面成文；評審辯論記錄入 §14；Codex 最擔心的一點（「受控壞形態能紅」≠「實體觸控板過渡態已覆蓋」）有正面、可證偽的回答（§5.4）。
- **完成標準（實施）**＝§7 W1–W14（W9 分 a／b）每項有實跑證據，§7 結論程序給出「通過」。
- **不做**＝重議 A／B／C／D（§3）；重跑 R5-5；改閘門計劃 §6；動 ACCEPTANCE 驗收基線（另問使用者，§3 D 註）；DMG 重建；H-04 平滑動畫；本 session 寫任何產品源碼。

## 1. 目標與非目標

**目標**
- G1　缺陷 3：初始值路徑（視圖帶著非 nil `centerID` 被建立＝切走再切回 Cover Flow tab；單測 `edgeItemsAlsoReachCenter`）與運行時路徑一樣把目標卡放到視口中心。
- G2　缺陷 2：落定態與過渡態，正對觀者那張都在最上層；疊放次序的輸入與旋轉幾何同源或經 F4 實測證明無滯後停滯。
- G3　C.1–C.7 全部落成可由腳本／程序判定的條款（§5），判定器先 TDD 再用。
- G4　證據包逐條回扣 §7；閘門計劃 §11 記錄的兩格不一致（T1.s3、T2.s2）以 C.3 儀器**解釋**（不裁決）。
- G5　不惡化 H-05：程式化居中（含初始值路徑的補居中與其跨幀回寫）不得被誤判為使用者接管（K5，F7 先紅後綠）。
- G6　**（v5 新增，2026-09-18 使用者批准範圍擴大）** 無 AX 客戶端時，H3 產生的程式化居中（含 `trackChanged`／載入完成／重建的**遠距、尚未具現**目標）必須把 requested 卡置於視口中心，**|Δ| ≤ 3pt**；Δ 定義＝U1c 還原的**變換前 layout midX** − viewport midX（只沿用 C1 的數值閾值，訊號與現行 C1 的 AX 變換後外框不同）。條款只規結果、不規修法。依據：F-JUMP 證偽了「運行時路徑正確」這個 G1 的參照前提（§13）。

**非目標**
- N1　重議使用者既裁定（§3）。
- N2　改閘門計劃 §6 判據、R4-C／R4-F／R4-X；重跑 R5-5。
  **v5 例外（2026-09-18 使用者批准）**：macOS 27／Xcode 27 升級使 26.6.2 上的全部 UI 基準失效（§13 實證），新增**場 0 基準重建**（§6）——在 27 上重跑 M0／M2／M3／既有 UITests 以建立 R27 基準。這是**基準重建，不是重判**：R5-5 的「部分通過」結論與 §3 B 的既裁定不變，舊資料降為 26.6.2 歷史事實。
- N3　ACCEPTANCE H-02 狀態改寫／拆條、❌ 圖例、M8 收口條件、DMG 重建、README——屬交接檔 §5.3 收尾與閘門計劃 N5／N6 的驗收基線變更；R6 的 D 序列「收官」＝閘門計劃 R5-6 證據包＋commit `a1d3407`（已於 2026-09-12 完成）。ACCEPTANCE 是否現在就把 H-02 標為「已驗失敗」由使用者另行拍板（見 §3 D 註），不在本計劃內默認推遲或默認執行。
- N4　H-04 自動平滑居中動畫；H-05 的完整交互整合驗證（本計劃只守 G5／K5 不惡化）。
  **v5 註**：G6 只規結果。若 F7 的**動畫四分法**（裸賦值／`Transaction.disablesAnimations=true`／零時長 animation／可見 animation，同一無 AX 條件、同一目標集合、以 presentation layer 時序判「有無中間位置幀」）證明**唯有可見動畫**能滿足 G6，則停在 F7 前帶數據問使用者是否擴大 H-04，不得先行實作。API 名稱不作「非可見」的證據。
- N5　提高 macOS 部署目標。本計劃**預設維持 14.0**（§4.4 D-A）；若實測證明 macOS 14 API 路線不可行，升目標是使用者決定，另問。
- N6　S7 事件注入（`CGEventCreateScrollWheelEvent` 帶 phase／momentum）作為閘門判據——只保留為 §5.4 的備案手段，須先向使用者報告並取得同意。
- N7　H2-e（顯式 ZStack 自行排序繪製）：v1 曾列為預設候選，R1 裁決刪除——它與 M1 同屬回呼→狀態通道、又拆掉 LazyHStack 惰性（真實專輯無 20 曲上限），改動面最大而無獨立證偽條件。

## 2. 事實基線（本會話實查）

| 事實 | 出處 |
|---|---|
| 分支 `feat/h02-uitest-gate` 相對 main 多 2 個 commit（`b74636f`、`a1d3407`），53 檔 +6847／−11；工作樹乾淨 | `git log main..HEAD`、`git diff main...HEAD --stat`、`git status` |
| `CoverFlowStrip`：`zIndex(stackingOrder(of:))` 讀 **`centerID`**（binding，離散）；旋轉／縮放走 `.visualEffect` 讀**變換前的佈局幾何**（`proxy.frame(in: .named).midX`，即 render 時的 GeometryProxy，不經 @State）；`anchor: .center`；`.safeAreaPadding(.horizontal, edgePadding)`；`.scrollTargetBehavior(.viewAligned)`；`LazyHStack(spacing: −0.42×itemWidth)`；檔頭註明 P1-0 spike 結論「`zIndex` 不能寫在 `.visualEffect` 閉包內」 | `CoverFlowStrip.swift:15-20,31-71` |
| 幾何單位：`CoverFlowGeometry.normalizedDistance` 以 **itemWidth** 歸一化（d＝(midX−viewportMidX)/itemWidth）；相鄰卡中心距 stride＝0.58 itemWidth（150.8pt）；幾何中心卡的 \|d\| 恆 ≤ 0.29；旋轉＝−55°×clamp(d)、縮放＝1−0.18×min(\|d\|,1) | `CoverFlowGeometry.swift:30-51`；`CoverFlowUITestFixture.swift:36` |
| `CoverFlowItem` 以 `.drawingGroup()` 把整張卡（正面＋倒影）合成單一圖層 → 每張卡是否各有 CALayer、CALayer 上是否帶身分＝**未知**（U1） | `CoverFlowItem.swift:20` |
| `CoverFlowViewModel`：`centerID` 一個狀態承擔 command／observed／zIndex／label／預取／override；`scrollPositionDidChange` 過濾 `isCenteringProgrammatically`、nil、同值，其餘一律 `userDidScroll`（寫 centerID 並設 override）；`stepCenter` 直接 `userDidScroll`；`centerIfAllowed` 的保護窗口是**同步**的（set→寫→clear 無 await）；`items` 載入無上限 | `CoverFlowViewModel.swift:19,150-171,212,232-241`；H-05 降級理由 `ACCEPTANCE.md:208`；`CoverFlowViewModelTests.swift:258-275`（明寫「修好之後這條會轉紅」） |
| `CoverFlowView`：binding setter 先 `CoverFlowUITestTrace.recordBinding`（DEBUG）再 `model.scrollPositionDidChange`；卡片 AX 標識 `coverflow-item-<persistentID>`；`RootView.content` 依 tab 重建 `CoverFlowView`，VM 保留 `centerID` → 切 tab 往返＝初始值路徑 | `CoverFlowView.swift:35-45,91`；`RootView.swift:108-121` |
| 三個歷史變異只差 `CoverFlowStrip.swift`：M1＝`@State visualCenterIndex`（`LazyHStack.onGeometryChange(for: Int?.self)` 反算**離散**索引，`withTransaction(disablesAnimations)` 寫入）供 zIndex、binding 作 fallback；M2＝M1＋`anchor: .leading`；M3＝M1＋`ScrollViewReader`＋`.onChange(of: centerID){ guard target != visualCenterIndex; scrollTo }`＋`.task{ sleep 50ms; scrollTo }`。M1 註釋已記 `onGeometryChange` 帶 (old,new) 的重載是 macOS 15+ | `diff` M0 vs `~/Developer/bjork-h02-gate/mutants/M{1,2,3}-*.swift`；md5 M2 `57da040c…`／M3 `48687466…` |
| R5-5 確認性殺死簽名：M2 於 T1.s1／T2.s1＝`C2-STACK\|G=T11\|over=T10\|side=L`；M3 於 T1.s1／T2.s1 同上、T3.s1＝`C2-STACK\|G=T10\|over=T09\|side=L`；三者都含 visualCenterIndex，都讓 M0 上正確的單步／首載疊放變錯（**前一個中心留在最上層**）。M2 的**真機**症狀是 anchor `.leading` 的粗大佈局破壞（右半屏空白、封面擠左），不是過渡態疊放；M1 從未單獨上真機 | 閘門計劃 §11 R5-5；`cf-M2/M3-confirm.v4.txt`；交接檔 §2 與文首補註 |
| M0 確認輪（×10）：T1.s2 10/10 `C2-STACK\|G=T13\|over=T12\|side=L`（途經的上一個對齊卡在上）；T2.s2 9/1（`over=T01\|side=R`）；T2.s3／T4.s1 10/10（`over=T18\|side=L`）；T4.s2 10/10 `C1-OFFSET\|label=T19\|centered=T16\|strides=+3`＋`C2-STACK\|G=T16\|over=T17\|side=R`；**T1.s1／T2.s1／T3.s1 10/10 PASS**；四條測試皆不含切歌（`trackChanged`）步驟 | 閘門計劃 §11 R5-5；`cf-m0-confirm.table.txt`；grep `trackChanged` 於 UITests＝0 |
| 兩格不一致：T1.s3 4 FAIL／6 PASS（探索輪曾 10/10、暫停前 5/4）；T2.s2 9/1（兩輪同形）；PASS 與 FAIL 的 AX 幾何逐項相同，只差交疊點像素分類——產品 z 序時序或截圖／compositing 取樣時機，**只可記推論**（Codex R6 J2） | 閘門計劃 §11、§12 R6 |
| 合成捲動事件 `phase=0 momentum=0 precise=1`，AppKit 仍發 willStart／didEnd live scroll；`XCUIElement.scroll` 為**阻塞**呼叫（runner 在手勢中不能取樣）；一次 snapshot＋截圖 0.18–0.26 s；`readStable`＝snapshot→截圖→snapshot 包夾、**不記時間戳、不輸出取樣點**；C2 由單張截圖一個 5×5 取樣決定；契約報告只印 window／strip／各卡 midX／aspect | 閘門計劃 §11 S4／S6；`CoverFlowProbe.swift:89-137,202-217`；`CoverFlowGateLogic.swift:421-430` |
| `readUntilQuiet` 以**檔案位移**判「軌跡靜止 500 ms」（凍結參數）：任何往同一 trace 檔每幀追加的記錄都會讓它永不靜止、燒滿 5 s 上限 | `CoverFlowProbe.swift:250-267`；`CoverFlowUITests.swift:239` |
| trace 記錄帶微秒時間戳（`ContinuousClock` 自啟動起算，**非 wall-clock**）；種類只有 `bind`／`event`／`live`；`event` 只來自 `.scrollWheel` 局部監聽（**鍵盤不進 trace**）；bind 的 nil 以字串 `nil` 記；trace 檔寫在 runner 的 temporaryDirectory＋隨機 UUID，**運行後未保留** → M0 的 nil 形態分布＝TBD | `CoverFlowTraceFormat.swift:8-34`；`CoverFlowUITestTrace.swift:53-88`；`CoverFlowUITests.swift:102-103`；`ls $TMPDIR` |
| `bindIndices` 把字面 `nil` 與非 fixture ID（含真實曲庫 persistentID）**都**映成 nil；`writebackFindings` 對 gesture／hold 段 `compactMap` 掉 nil（D2 盲區的實作位置） | `CoverFlowProbe.swift:270-273`；`CoverFlowUITestFixture.swift:56-64`；`CoverFlowGateLogic.swift:318-334` |
| 判定器：`table_valid`（缺測試／迭代數／MISSING／xc 與 GATE 不一致／errors）；`_step_status`；`_kill_outcome` 要求 baseline 該步 ALL_PASS、mutant 全 FAIL、簽名集合唯一、碼 ⊆ `PRODUCT_CODES`（**不要求含 C2**）；子命令只有 `table`／`v3`／`v4`／`verdict`；facade `h02_gate_eval.py` 以 `__all__` re-export；`ProductCodeSingleSourceTests` 只掃 `CoverFlowGateLogic.swift` 與 `CoverFlowUITests.swift` 的 `code: "C…"` 字面量；任一 PROBE／UNTAGGED 即整次迭代 invalid | `h02_gate_rules.py:50-60,68-74,203-219`；`h02_gate_cli.py:82-118`；`h02_gate_eval.py:113-124`；`test_h02_gate_parsing.py:110-128`；`h02_gate_table.py:5-6` |
| 凍結參數（閘門計劃 §11）：`unrotatedAspect=2.0`、寬容差 3%、長寬比 0.05、C1 3pt、色距 0.35、落定 100ms×4／10s、保持 1.5s、穩定重試 3、trace 靜止 500ms、捲動量 300（座標式）；閘門配置 `-enableCodeCoverage NO SWIFT_OPTIMIZATION_LEVEL=-O`、`launch(language:"en")`、窗 1200×800、albumTracks 延遲 400ms | 閘門計劃 §11、§3.13；`CoverFlowProbe.swift:36-47` |
| 運行成本：M0 ×10（40 case）測試時間合計 490 s；M2／M3 ×3 各約 147 s；含構建三份約 25 分鐘 → 候選 ×20 估 20–25 分鐘、×3 變異各約 5 分鐘、四測試 ×3 約 5 分鐘 | `cf-*-confirm.log` 逐 case 加總 |
| SDK（Xcode 26.6，MacOSX26.5.sdk；本機 macOS 26.6.2；部署目標 **14.0**）：`scrollPosition(id:anchor:)`／`contentMargins`／單參數 `onGeometryChange(for:of:action:)` **macOS 14**（帶 (old,new) 重載 15+）；`ScrollPosition`（`scrollTo(id:anchor:)`、`isPositionedByUser`、`viewID`）、`onScrollPhaseChange`、`onScrollGeometryChange`、`onScrollTargetVisibilityChange` **macOS 15+**；`NSView.displayLink(target:selector:)` **`API_AVAILABLE(macos(14.0))`**，標頭註明 view hidden／不在顯示器上時不回呼；`open --env NAME=VALUE` 可為正常 LaunchServices 啟動注入環境變數；`screencapture -v`／`-V <seconds>` 可錄影 | swiftinterface `@available` 行；`NSView.h:609-616`；`man open`；`man screencapture` |
| 交接檔記錄的死路：`contentMargins(for:.scrollContent)` 取代 safeAreaPadding → EDGE 失敗表與基線逐字節相同；`.padding` 取代 → 更糟（請求 0→實際 3）；M2 `.leading` 修 command 破 observed；M3 `scrollTo` 與手滑打架；閘門計劃 §2：**首次載入屬哪條路徑未知** | 交接檔 §2；閘門計劃 §2 |
| ~~T0 單測基線：EDGE 6/7 紅（args 1,4,5,6,7,8）、RUNTIME 3/3 綠、RENDERED 綠~~ → **v5：降為 26.6.2 歷史事實**。**T0′（macOS 27，2026-09-18 實跑 `a1d3407`）＝381 tests／8 issues**：EDGE 6 紅（同一參數集合，但 4–7 落點由 d≈0.1 貼齊變為偏 ~17pt）＋**RENDERED 2 條紅**（走同一初始值路徑）；RUNTIME 3/3 仍綠 | `fix4/unit-a1d3407-m27.log`；§13 |
| M2／M3 重建程序（R5-5 已跑通）：rsync 最終 tree → 只換 `CoverFlowStrip.swift` → 獨立 `-derivedDataPath` → 串行 `test` → 溯源（hashlist 只差 Strip、CDHash、products dir、IDENTITY）→ `lsregister -u` | 閘門計劃 §11 T9／R5-5；`mutant-runs-R55/` |
| codex CLI 0.153.2；Automation Mode 需使用者在場（60 s 逾時）；重建後既有 UITests 與非 fixture 啟動會撞鑰匙串授權框（閘門 fixture 模式走 `EphemeralSecretStore` 不受影響） | `which codex`；memory 兩條 |
| **v5 環境基線（2026-09-18 實查）**：本機 **macOS 27（26A428）＋Xcode 27.0（27A266a）＋SDK 27.0**（2026-09-16 升級）；部署目標仍 14.0。上表 SDK 行的可用性結論仍成立，但**單參數 `onGeometryChange(for:of:action:)` 實為 macOS 13+**（15+ 才是 (old,new) 雙參數版）；macOS 14 的**運行時**語義本機無法實證（無 14 機器），凡涉 14 的結論一律標「未證」 | `sw_vers`／`xcodebuild -version`／`softwareupdate --history`；SDK swiftinterface |
| **v5 失效清單**（降為 26.6.2 歷史事實，**不得**作 macOS 27 上的比較基準）：`cf-m0-confirm` 每格結果／七個穩定步驟／兩格不一致；`FROZEN_REGISTRATION`（R4-F）；`R55_KILL_SIGNATURES` 作為當前偏離基準；T0；`ui-T0`；M2／M3 的舊殺死形態；下方 §4.2「運行時路徑正確」敘述；舊運行時間估計。**不失效**：C.1 180/180、C.2 殺死須含 `C2-STACK`、C0–C6 語義、凍結輸入參數、M2／M3 源檔與 hash | §13；thecure R8 辯論 |
| **F-AX（v5）**：一次 in-process AX 讀取會使 LazyHStack 多具現一張卡，並把之後的程式化跳轉落點由 0/48 變 15/15；讀 CALayer 屬性無此效應 → 閘門（XCUITest 讀 AX）對**無 AX 真實使用**的外推力受限 | Z1 第 2 輪 §5.1 |
| **F-JUMP（v5）**：無 AX 時產品同款裸賦值跳到未具現目標落鄰卡（nil→6 +41.5pt、nil→7 −41.0pt，各 3/3）；`withAnimation` 貼齊；RUNTIME 單測在 drive 前已輪詢 AX 且目標 1/4/8 撞不到此形態 | Z1 第 2 輪 §5.2；`CoverFlowStripRenderGeometryTests.swift:308` |

## 3. 使用者既裁定（2026-09-12 拍板，閘門計劃 §12 R6 定稿方案；不重議）

- **A**　V4＝必要否決控制：候選不再殺 M2／M3 即否決；殺死亦不抬升結論；不得宣稱為捲動慣性的驗證。
- **B**　部分通過 → 啟動第四次修復；不重跑 R5-5、不改 §6、不改寫「部分通過」；兩格不一致成因記推論，不作開工前閘門。
- **C**　C.1–C.7 預登記（原文見閘門計劃 §12 R6 及 `debate-R5/cure-ask-r6c.md`；本計劃 §5 逐條展開）。
- **D**　順序：確認 → 收官 → 新計劃 Phase 1 → 儀器健康 → 過渡態證紅（M0 或受控壞形態）→ 觸及凍結輸入則回 Phase 1 → 產品修復 → 候選 ×20 → M2／M3 ×3 → 實體手滑 → 結論。
  **註**：「收官」＝R5-6 證據包＋commit `a1d3407`＋push，已完成。ACCEPTANCE H-02 目前仍為「⬜ M8 目視」（`ACCEPTANCE.md:205`），與「已驗失敗、閘門部分通過」的事實不符；依閘門計劃 N6 這是驗收基線變更，**需使用者拍板**是否在 F1 前先做（純文檔、不需在場），本計劃不代決。

評審者若重提以上任何一點，直接駁回並註明「使用者既裁定」。**本計劃在 R6 之外新增的操作護欄**（§5.1 首份有效運行、無效上限、候選總數上限、熔斷）不是 C.1 原文，是實施權限的收緊，一併交使用者批准。

## 4. 缺陷成因與修復假說

### 4.1 缺陷 2（疊放）：事實與推論鏈

事實（閘門計劃 §11）：疊放次序＝`zIndex(−|index − centerIndex|)`，`centerIndex` 由 `centerID` 推得；旋轉＝`.visualEffect` 即時幾何；兩者不同源。落定後留在最上層的是**上一個對齊過的卡**（11→13 留 12；←×25 到 T00 留 T01；重建 label T19／畫面 T16 留 T17）。單步與首載 10/10 正確；T1.s3／T2.s2 時紅時綠。

推論（**推測**，F3／F4 儀器證實或推翻）：
- P2-1：`zIndex` 的重新套用綁在 Strip body 重算；一連串 `centerID` 變更中，最後一次的 z 序沒被套到已在捲動動畫中的子視圖上，之後再無失效事件，「倒數第二個中心」被留下。單步只有一次變更，故正確。
- P2-2：兩格偶發 PASS＝最後一次 z 序套用與截圖取樣時機的競態（產品側 compositing 時序或截圖時機；R6 J2 只准記推論）。
- M1–M3 的 `visualCenterIndex`（`onGeometryChange`→`@State`）在**單步**就把前一個中心留在上層 → 兩種可能：該離散狀態比 binding 回寫更滯後；或捲動動畫中的狀態寫入被吞掉／停在舊值。後者與離散／連續無關，**任何** `onGeometryChange`→`@State` 路線都必須先以 F4 實測排除（K1）。

### 4.2 缺陷 3（初始值路徑少滾 3 stride）：事實與推論鏈

事實：只出在「視圖帶著非 nil `centerID` 被建立」的路徑（EDGE 6/7 紅、T4.s2 10/10 `strides=+3`）；運行時路徑（`onChange` 驅動）正確（RUNTIME 3/3、T2 端點 T00／T19 皆到達）。
> **v5 修正（2026-09-18）**：「運行時路徑正確」**已被 F-JUMP 證偽**——無 AX 客戶端時，裸賦值跳到**未具現**目標會確定性落鄰卡（±41pt）。舊敘述成立的範圍僅限「有 AX 觀察下、目標已具現」。缺陷 3 的機制在 macOS 27 上另有新事實：clip `bounds.origin.x`＝正確位移 − leading `contentInsets` 466（466/150.8＝3.09 stride），殘差 13.6pt 在 27 上不再被 viewAligned 吸附吃掉（§13 U5）。偏移 ≈ `edgePadding / stride`；`.leading` 可歸零但破壞 observed（M2 真機）。偏移形態下 SwiftUI **沒有**回寫 T16（label 仍 T19）。

推論（推測）：初始值路徑與運行時路徑在 SwiftUI 內是兩套定位計算，只有後者對 safeAreaPadding 正確。修法方向＝**讓初始值路徑不存在**：視圖永遠以 nil 建立，佈局就緒後經運行時路徑居中；不再給定位公式打補償。

### 4.3 三次失敗的教訓 → 候選必須滿足的不變式（K1–K8）

| # | 不變式 | 由誰守 |
|---|---|---|
| K1 | 疊放次序不得依賴會**停在舊值**的狀態：任何 `onGeometryChange`→`@State` 通道須先由 F4 spike 實測「滯後 ≤ 1 幀且落定後不停在舊值」，否則否決該路線（適用所有 H2 分枝，無例外） | F4 spike＋C.1 |
| K2 | 不改 `anchor`（維持 `.center`）；不用 `ScrollViewReader.scrollTo` 與使用者捲動競爭；不改 `safeAreaPadding` 為 `.padding`／`contentMargins` | simcodex 審查＋M2／M3 負對照 |
| K3 | `CoverFlowStrip` 泛型介面與 `CoverFlowGeometry` API 源碼相容，歷史變異 Strip 檔可直接替換編譯；**以 F2 spike 實際編譯 M2／M3 檔為準**。修法若需 Strip 新參數 → 先回 Phase 1 辯論變異移植程序 | F2／F9 構建 |
| K4 | **（v5 改寫）候選全量單測零 issue**：EDGE 7/7、RUNTIME 3/3、**RENDERED（缺陷 1 不回歸）**、K5 新測試、G6 的無 AX RED 與全部新增測試皆綠。T0′ 的 8 issues（EDGE 6＋RENDERED 2）只作**修復前 RED**，**不是候選容許的紅燈** | F7 TDD |
| K5 | 程式化居中（含初始值路徑的補居中及其**跨幀**回寫）不得把 `userHasOverriddenAutoCenter` 設為 true；保護窗口必須覆蓋實際持續期。**先紅後綠**：F7 新增 VM 測試「程式化居中期間連送多個途經 id 的 `scrollPositionDidChange`，落定後 override 仍為 false」，並把 `differentIDCallbackIsTreatedAsUserTakeoverEvenIfProgrammatic` 由釘現況改為新契約 | F7 TDD（VM 必改） |
| K6 | Release 不含任何測試／儀器符號；儀器預設關閉、閘門運行永不開啟 | `strings`＋grep（W11） |
| K7 | 候選一律先過單測與 Python 判定器測試，再花 UI 運行 | §6 F9 前置 |
| K8 | 產品源碼改動不得使真實大專輯退化（惰性、預取窗口 H-06／H-07 語義不變）；候選若改變可見項數或 artwork task 數的增長方式，須有單測 | F7 |

### 4.4 修復假說（決策樹；F2／F4 spike 選枝，Phase 1 不鎖死實作）

**H3（缺陷 3）——「初始值路徑不存在」**（macOS 14 API）
- 狀態機（F7 實作前寫死並以 VM 單測釘住；R2-07 補齊 origin／出口／取消）：
  - 命令帶 **origin**：`auto`（切歌 `trackChanged`、載入完成、重建時的保存值）或 `user`（鍵盤步進）。`user` 命令沿現行語義**立即**設 `userHasOverriddenAutoCenter=true`；`auto` 命令不設。
  - 狀態：`idle` → `armed(generation, requested, origin)`（命令已發出、尚未灌入運行時路徑；初始值路徑的視圖以 nil 建立即進 armed）→ `applying`（已灌入，等待回寫）→ `idle`。**進入 armed／applying 與處理回寫在同一同步段內完成**（原子），首次 observed 回寫（含 nil 起始時 SwiftUI 可能回寫的 items[0]）到達時狀態已非 idle。
  - 回寫處理：`armed`／`applying` 期間回寫 ≠ requested → 視為途經、丟棄、不設 override；回寫 ＝ requested → `idle`（settled）。之後的**延遲途經**（`途經 → requested → 延遲途經`）以 generation 比對：只接受 generation ≥ 當前者，settled 後 T_late（預登記 250 ms）內與 requested 不同的回寫仍視為該 generation 的殘餘途經而丟棄。
  - 出口：(a) settled；(b) 被新命令取代（generation+1）；(c) **失敗出口**：進入 applying 後 T_apply（預登記 2 s）內無回寫 ＝ requested → 回 idle、記 log、`centerID` 保持 requested、不設 override（不得永久吞掉之後的使用者捲動）；(d) **取消**：真實使用者輸入——`NSScrollView.willStartLiveScrollNotification`（AppKit，主執行緒觀察；交接檔 §5.2 已建議的 bridge）或鍵盤步進——到達即退出 armed／applying，之後回寫按現行語義視為使用者接管。
  - K5 測試（先紅）至少四組序列：① nil 起始首次回寫 items[0] 不接管；② `途經 → requested → 延遲途經` 不接管；③ requested 永不回寫 → T_apply 後 idle 且後續使用者回寫正常接管；④ applying 期間 live scroll 開始 → 取消並接管。另：⑤ `user` 命令期間途經回寫不重複設 override（冪等）。
- 落點（**v5 改寫，2026-09-18；依 Z1 第 2 輪 U5 實證＋thecure R8**）：
  - **H3-a(b′)＝第一順位**：程式化窗口在 VM（`beginProgrammaticCentering(generation)`），觸發訊號由**呼叫方**取得——`CoverFlowView` 傳給 Strip 的**內容閉包**（或對 Strip 外掛的 modifier）在**首次 `onGeometryChange` 回呼內同步**呼叫 VM 灌入 requested。**Strip 泛型介面與 `CoverFlowGeometry` 完全不動 → K3 天然成立、不觸發 §5.7**。證據：U5 的 B 情境 21/21 貼齊（目標 3／6／7／8）、只一次同值 echo、0 途經，其探針正是掛在內容閉包內。
    - 守衛：**MainActor 上原子消耗的 `(viewEpoch, generation, requested)`**——先消耗再寫 binding；不匹配或已消耗的回呼 no-op。**禁用**每卡 `@State Bool` 與 VM 永久 Bool。
    - **接縫 1（spike 3 必驗）**：現行 binding setter 只交付 `id`、無 generation provenance（`CoverFlowView.swift:35`）→ 要麼證明 setter 閉包能捕獲建立時的 `(viewEpoch, generation)` 且延遲回呼確實回到原閉包，要麼把契約改成「active-generation 時間窗＋live-scroll 取消」，**不得**聲稱能比對回呼自身的 generation。
    - **接縫 2（必做）**：分離 `commandedID` 與傳給 Strip 的 `scrollID`——切 tab 重建時 VM 仍持有 `centerID`，Strip 初次 getter 讀到非 nil，b′ 就沒有消除初始值路徑；b′ 回呼須先原子 `armed → applying` 再寫 `scrollID=requested`。
    - 以**單參數** `onGeometryChange`（deployment target 14）實作，不用 15+ 雙參數版；macOS 14 運行時語義**未證**。
  - ~~H3-a(b)（VM 側非同步觸發族）~~：**實證否決**——`RunLoop.main.perform`（佈局前）24/24 落「請求−3」、`Task.yield` 5/24、固定延遲 50–1500ms 0/48（§13 U5）。否決範圍僅限**已測的 VM 非同步觸發族**。
  - H3-a(a)：Strip 加帶預設值的新參數（例如 `onLayoutReady`）——**第二順位**；K3 明文「修法若需 Strip 新參數 → 先回 Phase 1」，故須先做 K3 spike（M2／M3 檔在含新參數的 tree 直接編譯）**再回 Phase 1 由使用者批准變異移植程序**，才可進 F7。K3 失敗的出口依序：改用可保持舊呼叫相容的 API 形態 → 回 Phase 1 批准新的變異移植程序 → 承認兩條 macOS 14 路線皆失敗、討論 H3-b／升部署目標。
  - H3-b：macOS 15 `ScrollPosition`（`scrollTo`／`isPositionedByUser`）——僅在 (a)(b) 皆被實證否決時，帶證據回 Phase 1 問使用者是否升部署目標（N5、D-A）。
- ~~已知風險：以 nil 起始時 SwiftUI 是否在首次佈局回寫 items[0]（U5）~~ → **v5：U5 已答（2026-09-18）**——nil 起始 21/21 **不回寫 items[0]**、全情境 0 次途經回寫；`applying` 不必為此設計吞噬邏輯（仍須處理同值 echo）。EDGE 單測仍是最便宜的 RED→GREEN 迭代面。
- **v5 新增（G6）**：b′ 實作後，H3 的 auto 命令（`trackChanged`／載入完成／重建）在**無 AX、目標未具現**時也必須把 requested 卡置中（G6）。正式 RED 的位置＝場 0 全過 → spike 3 建立並驗證無 AX 身分與 Δ 量測 → 在未改 H3 產品行為的基線上凍結 RED → 動畫四分法 → 必要時問 H-04 → F7 轉綠。RED 要求：全程到 verdict 不讀 AX；20 張或等價大專輯；覆蓋未具現遠距目標、兩個方向與末端；斷言 requested 身分且 |Δlayout| ≤ 3pt；以 VM 測試證明 `trackChanged`（`CoverFlowViewModel.swift:140`）／載入完成（同檔 `:215`）／重建都匯入同一受驗 command pipeline；凍結測試名、失敗輸出與基線 hash。Z1 第 2 輪的 U5x 只作**發現證據**，不得充當正式 RED（9 張簡化 harness、最後仍讀 AX）。

**H2（缺陷 2）——「z 序不停在舊值」**（F4 以兩個 scratch 變異實測選枝，皆 macOS 14 API）
- S-b（逐項連續 zIndex）：每張卡自己的單參數 `onGeometryChange(for: CGFloat.self)` 寫 |d| 進逐項 `@State`，`zIndex(−|d|)`；旋轉／縮放**維持** `.visualEffect`（缺陷 1 修法不動）。代價：z 序輸入與旋轉輸入仍是兩個通道，但兩者都源於同一幀的佈局幾何；一幀滯後可接受，**停在舊值不可接受**（K1）。
- S-off（單一連續 stack offset）：`LazyHStack` 一個 `onGeometryChange` 取 minX 進 `@State`，rotation／scale／zIndex **三者都**由該狀態算 → 完全同源，但旋轉不再讀 `.visualEffect` 的即時幾何，整條帶落後捲動一幀，且必須重驗 RENDERED（缺陷 1）。
- 選枝規則（預登記，與 K1 同義）：F4 對 S-b／S-off 各跑儀器 ON 四測試 ×3，**否決條件（任一即否決）**：(α) 任一落定格 z 序停在舊值；(β) z 序相對變換前幾何的滯後 > 1 幀（sampler 逐幀比對「最上層卡」與「\|d\| 最小卡」的切換時刻差）；(γ) pre-settle 窗口內出現 P_trans 違反（§5.4 謂詞、δ 同值）。結果：(i) 皆過 → 選 **S-b**；(ii) 只 S-off 過 → 選 S-off 並加 RENDERED＋一幀滯後目視項；(iii) 皆否決 → macOS 14 路線只剩 H2-c（15+）→ 帶證據回 Phase 1 問使用者（D-A）。
- 不得使用 (old,new) 的 `onGeometryChange` 重載（macOS 15+）。

**D-A（部署目標，本計劃立場）**：維持 14.0；先做 H3-a(b)／(a)＋S-b／S-off。升 15 只在 14 路線被實證否決後由使用者決定。

**ADR**（slipknot 18）：F7 開工前在 §13 寫「背景／候選／決定／放棄了什麼與代價／重議條件」，引用 F2／F4 數據。

## 5. C.1–C.7 可判定條款

**通用定義**
- **運行有效**＝`table_valid(table, N)` 成立（四條測試齊、每條恰 N 次、每次每步恰一條 GATE、xc 狀態與 GATE 一致、`errors==[]`、零 PROBE／UNTAGGED／MISSING、tearDown 全檔 audit 乾淨、IDENTITY 每次指向本輪 Products 且實例數 1）＋ **證據完整**（§5.7 (7)：每個 test/iteration 的 trace 與 marks 檔存在且 manifest 相符；缺任一＝無效）。
- **候選 K<n>**＝一棵確定的源碼樹：`cand-K<n>/hashlist.txt`（全部源檔 md5）＋`worktree.patch`＋CDHash＋一段「相對 K<n−1> 的機制差異」說明（純格式／註釋 diff 不構成新候選）。
- **首份有效運行規則（通用，C.1／C.2／C.4／C.6 皆適用）**：對同一 K<n> 的同一運行種類，**第一份有效運行即結論**；無效運行不消耗，但受無效上限約束。C.6 的重做只限「手勢未達 §5.6 登記參數」，每路徑最多重做 2 次，全部次數進證據包。
- **實體有效（C.6 每次重複；三層定義）**：
  - `physical_valid_base`＝啟動身分相符（trace header 的 bundle／exe 大小／mtime＝本輪構建；操作者腳本另記 CDHash 與 pid 可執行檔路徑）∧ 啟動時同 bundle ID 實例數＝1 ∧ **動作有效**（依路徑型別：P1–P6 依 §5.6 手勢定義由 trace `event` 判；P7＝切回後 label 為第 19 張且畫面重建（R-off 以錄影＋trace `bind`／`live` 判，R-on 另有 `view-appear` mark）；P8＝重啟後首次落定（R-on 以 `launch`→首個 `settle` mark 判）；P9＝Music 切歌後自動居中發生（R-on 以 `center-change|origin=auto` mark 判））∧ 錄影檔存在且可逐幀。
  - `physical_valid_off`（R-off）＝ `physical_valid_base` ∧ 啟動環境**未設** `AZW_COVERFLOW_SAMPLER_PATH`（trace ON、sampler OFF）。
  - `physical_valid_on`（R-neg／R-on）＝ `physical_valid_base` ∧ 啟動環境設有 `AZW_COVERFLOW_SAMPLER_PATH` ∧ sampler 檔存在且 header 身分相符 ∧ 段有效（§5.4）。
  - 缺任一＝該次無效（不計結論，計入重做額度）；重做額度耗盡 → 該路徑**不可判定** → §7 第 3 條。
- **操作護欄（R6 之外，需使用者批准）**：(a) 同一 K<n> 同一運行種類**連續 2 份無效** → 停手，帶 PROBE 證據上報使用者裁決（PROBE 依 C.1 原文仍＝無效，不轉為不通過；但候選首次出現的 PROBE 碼須在報告中標明 R5-5 基線 PROBE＝0）；(b) 候選總數 ≤ **5**；(c) 熔斷：連續 3 個候選在同一 (step, 正規化簽名) 不通過、**或**連續 3 個候選在任一 step 不通過、或連續 3 個候選 P_trans 同 (step, G／over／side) 觸發、或連續 3 個候選同 (路徑, F 謂詞) 實體失敗 → 停手上報（slipknot 08）。

### 5.1 C.1 候選閘門（單一規則）

- 輸入：`cf-cand-K<n>`＝四條測試 `-test-iterations 20`，閘門配置（§2 凍結參數），儀器 **OFF**（`AZW_COVERFLOW_SAMPLER_PATH` 未設），trace 照常（寫入 §5.7 (7) 的持久目錄）。
- 規則（`h02_gate_eval.py candidate`，F1 TDD）：
  - **無效**：運行無效或證據不完整 → 不是產品結論；只准以基建修正（PROBE 類，且不觸及 §5.7 觸發清單）後重跑；受無效上限。
  - **通過** ⇔ 有效 ∧ 180 格（9 步 × 20）全部 `PASS`。
  - **不通過** ⇔ 有效 ∧ 任一格 `FAIL`（任何產品碼 C0–C6，含 §5.5 新碼）。無 R4-X、無 EXCLUDED、無 V5、無 R4-F。T1.s3／T2.s2 的時紅時綠在此規則下＝不通過。
- **量測成因預登記**（Opus swiftui F5）：若 F3／F4 的儀器證據顯示 T1.s3／T2.s2 在落定後 z 序**恆定**、PASS／FAIL 之差落在截圖取樣窗口內（§5.3 (b) 記為 Z1-AMBIGUOUS），則在任何候選運行之前帶證據回 Phase 1 請使用者裁決（改取樣方式屬 §5.7 觸發），不進候選迭代、不消耗護欄額度。
- 前置（K7）：單測全量（K4）、Python 判定器測試、`build-for-testing`、Release `strings`（W11）、`git diff --name-only` 列出候選改動的產品源檔（供 §5.2 分支判定）——任一不成立不得花 UI 運行。

### 5.2 C.2 負對照（M2／M3 從候選同一 tree 重建 ×3）

- 時機：K<n> 的 C.1 通過之後。
- 構建：`M2_K`／`M3_K`＝K<n> tree 只換 `Features/CoverFlow/CoverFlowStrip.swift` 為 `mutants/M2-attempt1plus2.swift`（`57da040c…`）／`M3-attempt1plus3.swift`（`48687466…`）；獨立 derivedData；溯源同 R5-5；`-test-iterations 3`，閘門配置，儀器 OFF；結束 `lsregister -u`、刪 scratch DerivedData。
- 規則（`h02_gate_eval.py negative-control`，F1 TDD；殺死謂詞沿用 `_kill_outcome` 並加一條）：
  - 每份變異運行須**有效**；無效 → 修基建後重跑（受無效上限）。
  - 殺死(step) ⇔ K<n> 該步 20/20 PASS ∧ 變異該步 3/3 FAIL ∧ 三次完整正規化簽名集合相同 ∧ 碼 ⊆ `PRODUCT_CODES` ∧ **產品碼投影含 `C2-STACK`**（其他碼可併存但不得單獨構成殺死——防止 §5.5 新碼把與疊放無關的差異算成殺死）。
  - **通過** ⇔ M2_K 在 {T1.s1, T2.s1} ≥ 1 步殺死 ∧ M3_K 在 {T1.s1, T2.s1, T3.s1} ≥ 1 步殺死。
  - **簽名偏離（v5 改寫）**：比對對象＝**場 0 凍結並已原子啟用的 R27 active profile**（M2／M3 各自的殺死簽名）。判定器同時輸出兩欄：`active_profile_deviation`（參與結論）與 `historical_R55_deviation`（26.6.2 舊值 M2：`C2-STACK|G=T11|over=T10|side=L`；M3：同＋T3.s1 `C2-STACK|G=T10|over=T09|side=L`，**只作跨版本資料、不參與結論**）。active 偏離 → 列示＋解釋；**解釋不出 → 不可判定，上報**。**無 active profile（仍在 staging 或場 0 未全過）→ 運行無效**，不得以 R55 下結論。`REQUIRED_KILL_STEPS` 與「殺死須含 `C2-STACK`」不因換 profile 而改，且**不得依場 0 結果改寫**；若 R27 上 required 集合已無 baseline PASS，跑變異前就停（§7 場 0 停止分支）。
  - **殺死點消失且候選改了 Strip 以外的產品源檔**（VM／Geometry；由 K7 前置的 `git diff --name-only` 機械判定）→ 不判 C.2 不通過、不計熔斷，回 Phase 1 辯論變異移植程序（例如同時回退 VM 改動的第二份變異）。K5 已使 VM 成為必改檔，此分支預期會被觸發，屆時的移植程序須先辯論。
  - **編譯不相容** → 該變異「不可建」→ 上報（不算殺死、不算不通過）。

### 5.3 C.3 診斷儀器（訊號源；只解釋、不裁決）

- 形態：DEBUG-only 取樣器 `CoverFlowUITestSampler`，環境變數 `AZW_COVERFLOW_SAMPLER_PATH=<檔>` 存在且 trace 已安裝時啟動；`NSView.displayLink(target:selector:)` 驅動，**以 `.common` 模式加入 run loop**（live scroll tracking 期間主 run loop 在 event-tracking 模式，`.default` 會靜音）；宿主 view＝主視窗 `contentView`，視窗未就緒時重試安裝。**寫入獨立檔**（不進 trace，`readUntilQuiet` 與契約報告 notes 完全不受影響）；檔首 header 含 `pid`／`epoch-us`（wall-clock 錨點）／bundle。
- 每幀記錄（`frame`）：`t_us`（與 trace 同一 `ContinuousClock` 起點）、VM `centerID` 在 `items` 中的序位（由組裝時注入的 provider 讀取，DEBUG）、每張可見卡：`items` 序位、**變換前**佈局 midX、變換後外框、z 序訊號；以及在幾何中心卡 G 與兩鄰張的交疊點上「最上層卡序位」。
- ~~**Z1 spike（F2，動工前必須解決，拆三項）**~~ → **v5 結案（2026-09-18，Z1 第 2 輪；詳見 §13）**：
  - **U1a 成立**：z 序訊號＝卡層父層的 `sublayers` 次序（單調反映 zIndex，`zPosition` 全 0），`layer.hitTest`（model 與 presentation 皆可）作交叉核對，50/50＋50/50 命中 zIndex 最大者。**AX hit-test 已證無效**（回樹序），階梯跳過該級。
  - **U1b 主方法不成立**（卡層無身分載體、同一卡跨位置換 CALayer 物件）。**計劃備案（同幀 AX 外框配對）雖可行（9/9、殘差 0.000pt）但不採用**——F-AX 證明 AX 讀取會改變 LazyHStack 行為，逐幀讀 AX 的 sampler 會自己製造觀察者效應。**改為無 AX 方案**：P_trans 只用**同幀層身分**（G＝分解後佈局 midX 最近視口中心者的層；top＝`sublayers` 次序／`hitTest`；判 `top === G`），**不需卡片語義身分**；絕對 `Txx` 序位只作**非裁決診斷**，**不得由 z 頂層推導**（會循環論證），跨幀追蹤若證不出唯一就刪除絕對序位輸出。卡片語義身分（G6 與 C.3 解釋需要）依序試：① `CoverFlowView` 內容閉包內 DEBUG-only 被動 `NSViewRepresentable` marker（Coordinator 以 `persistentID` 註冊弱引用、逐幀讀 window frame 與層配對，須做 ON／OFF 觀察者效應驗證）；② 純色 contents 指紋；③ 事後 AX 單幀標記（**只限落定快照**，且 AX 前後完整層投影——`ObjectIdentifier`／ancestry／class／bounds／position／anchorPoint／transform／zPosition——逐值不變才可追溯貼標；**不得宣稱排除觀察者效應**、不得用於跨幀或後續行為證據）。
  - **U1c 成立**：transform 分解（軸邊以齊次 `w≈1` 判別、以軸邊長還原 scale、再回推佈局 midX），落定 max|Δ理論| 1.0pt（除 p=8 的共同 −1pt 落定偏移外 ≤0.4pt），運動中與解析法差 ≤0.2pt，|d|→0 不退化。**NSScrollView 解析法不可獨立使用**（LazyHStack 估計尺寸使 DocumentView 1467→1358、整體偏 108.4pt）。AX 外框備案的偏差上界：|d|<0.05 ≤2.07pt、[0.05,0.20) ≤7.28pt、[0.20,0.29] ≤9.16pt、>1 ≤18.29pt。
  - **取樣層**：幾何與 z 序**預設讀 presentation layer**；本輪程式化捲動下 model 與 presentation transform 272 樣 0 差異，但真實 live scroll 未驗 → 要降為 model layer 須先由 F3b 實證。
  - **U-DL 成立（代理）**：sampler 必須以 `.common` 加入 run loop——`.default` 在 event-tracking 泵下 3/3 完全靜音；`.common` 四種泵 ×3 全過（中位 8.33ms@120Hz、最大 ≤20.03ms）。真實觸控板 live scroll 由 F3b (e) 實證。
  - **sampler 一律不讀 AX**（manifest 記 `identity_source`）；F3b (c) 的觀察者效應量測須涵蓋身分方案本身。
- 角色分離：儀器＝訊號源。C.3 用途＝解釋兩格不一致與 K1 的滯後量測，結論只寫「觀察／推論／未排除」；不改 C.1／C.2 判據；候選 ×20 與變異 ×3 一律儀器 OFF。§5.4 對同一訊號套預登記謂詞，且先經負對照驗證才可裁決過渡態。
- **F3a 基建等價對照（儀器 OFF）**：基建改動後的 M0 tree，四測試 ×3 儀器 OFF：運行有效；每格產品碼投影 ⊆ 閘門計劃 R4-F 的 F(step)；R5-5 七個 10/10 穩定步驟（T1.s1／T1.s2／T2.s1／T2.s3／T3.s1／T4.s1／T4.s2）結果與凍結表相同。這是 §5.7「行為差異」的實證，不是 ON 輪。
- **F3b 儀器健康（儀器 ON，四測試 ×3）**：
  - (a) 運行有效；七個穩定步驟結果同凍結表；每格產品碼 ⊆ F(step)；
  - (b) **Z1 交叉核對**：runner 在契約報告輸出截圖起訖 wall-clock（`shot-begin`／`shot-end` marks）與 C2 實際取樣點座標；對七個穩定步驟的每個有 C2 判定的落定格，取 [shot-begin, shot-end] 內全部 frame：若儀器回報的最上層卡**恆定**，必須＝像素分類（命中率 100%）；若不恆定 → 記 `Z1-AMBIGUOUS`，作為 C.3 對取樣時機競態的證據，不計健康失敗。T1.s3／T2.s2 兩格只記資訊，不進健康 DoD；
  - (c) 觀察者效應（結果面，ON vs OFF 各 ×3 同 tree）：逐 test case 秒數中位數差 ≤ 10%；每步落定耗時與輪詢次數（報告新增輸出）中位數差 ≤ 10%；gesture 段 `bind` 記錄數與 `live:start→end` 時長中位數差 ≤ 10%；七個穩定步驟產品碼分布相同；任一超標 → C.3 結論帶保留；
  - (d) 12 次 tearDown audit 乾淨；trace 與 sampler 檔 manifest 齊全；
  - (e) 儀器自證：每個運動段的 **pre-settle 窗口**（§5.4）內 `frame` 數 ≥ 窗口毫秒數／20、最大相鄰 frame 間隙 ≤ 40 ms，且全程 frame 間隔中位數 ≈ 1／刷新率（±20%）；鍵盤／首載／重建段無 `live` 記錄，一律以 pre-settle 窗口判；任一不足 → 該段 `PROBE-SAMPLER`（不得回「零觸發」）；儀器 OFF 為預設；Release `strings` 對儀器符號為 0。
- 產出：`Scripts/h02_sampler_report.py`（TDD）：`timeline`（逐步驟時間序列）、`trans`（§5.4）、`nil`（§5.5 校準）。

### 5.4 C.4 過渡態證偽手段（先證紅，再拿候選的綠）

- **分段來源**
  - 閘門／trans 運行（有 runner）：runner 寫 marks 檔（`<evidence>/<test>-<iteration>.marks`，wall-clock µs）：`step-begin`／`step-end`／`key`／`scroll-begin`／`scroll-end`／`shot-begin`／`shot-end`／`settled`。
  - 實體輪（無 runner）：**app 內 marks**（sampler 檔內 `mark` 記錄，與 frame 同一時鐘）：`launch`、`view-appear`（Strip 首次佈局）、`center-change|from|to|origin`（VM provider 差分）、`settle`（sampler 連續 24 幀變換前幾何逐卡不變＝約 400 ms，與 runner 的 100 ms×4 同義）；捲動邊界取 trace 的 `event`（實體事件帶 phase／momentum）與 `live:start/end`。路徑分段：P1–P6 ＝ [第一個 `event`（前 1 s 無事件）, `settle`＋2 s]；P7 ＝ [`view-appear`, `settle`＋2 s]；P8 ＝ [`launch`, 首個 `settle`＋2 s]；P9 ＝ [`center-change|origin=auto`, `settle`＋2 s]。操作者腳本每次重複生成一份 manifest（路徑、次序、檔名、md5、CDHash）。
  - 兩種 marks 都以 sampler／trace header 的 `epoch-us` 錨點對齊；時鐘不一致（runner 與 app 同機 wall-clock 差 > 50 ms）→ 該段無效。
- **單位**：P_trans 的 d 與產品同義＝`(midX − viewportMidX) / itemWidth`（`CoverFlowGeometry.normalizedDistance`）；stride＝0.58 itemWidth；幾何中心卡 G_f 的 \|d\| 恆 ≤ 0.29。
- **失敗謂詞 P_trans**（預登記）：運動段內每幀 f，G_f＝變換前 \|d\| 最小的卡（tie → 該幀不可評）；當 \|d(G_f)\| ≤ **δ_trans＝0.20 itemWidth**（＝0.345 stride；幾何預登記，**不由紅綠結果校準**：此時 G_f 旋轉 ≤ 11°、縮放 ≥ 0.964；任一鄰張 \|d\| ≥ 0.38 → 旋轉 ≥ 21°、縮放 ≤ 0.932，「應在最上層」無歧義；(0.20, 0.29] 為合法交叉區排除），對**存在且與 G_f 有非空交疊、且交疊點最上層可讀**的每一側鄰張，最上層必須是 G_f；否則該側 NA。任一側違反 → 段記 `C7-TRANSIENT-STACK`（`t_us`／`G`／`over`／`side`／連續幀數）。單位由單測釘住（fixture：\|d\|=0.20 恰為 52 pt）。
- **段有效性**（任一不足 → 該段**不可判定**，記 `PROBE-SAMPLER`，不得輸出零觸發）：段分 **pre-settle 窗口**［起點, `settled`）與 **hold 窗口**［`settled`, 段末］，分別檢查：(a) pre-settle frame 數 ≥ 窗口毫秒／20 且最大相鄰間隙 ≤ 40 ms；(b) hold frame 數 ≥ 窗口毫秒／20；(c) **逐側**可評覆蓋：對每一側，若該側鄰張在 pre-settle 內存在且與 G_f 有交疊的幀 ≥ 1，則該側**可評幀**（非 tie ∧ \|d(G_f)\| ≤ δ ∧ 該側有交疊且最上層可讀）≥ max(5, 30% × pre-settle frame 數)；只有鄰張不存在（端點）或全程無交疊的側才豁免；(d) 卡片映射成功率 ≥ 95%。單側不可讀不得靠另一側達標而讓整段有效。NA／不可評／跳過統計進證據包。
- **運行模式**：`cf-<tree>-trans`＝四條測試 `-test-iterations 10`，儀器 ON，其餘同閘門；P_trans 離線判定（`h02_sampler_report.py trans`），不進 GATE、不改 C.1。
- **負對照（合成路徑）**，F5，順序固定，δ 不得回調：
  1. `cf-m0-trans`（＝F4 的 M0 ON ×10 同一份運行）：M0 若在任一運動步驟 ≥ 5/10 **有效段**觸發 → M0＝負對照。
  2. 否則 `cf-M1diag-trans`（儀器化 M0 tree＋M1 Strip，純 zIndex 路線；hash 固定）：T1.s1／T2.s1 ≥ 5/10 有效段觸發 → M1＝受控壞形態（明記「M1 真機形態屬首次觀測」）。**不用 M2**（真機形態是 `.leading` 佈局破壞）。
  3. 皆不紅 → P_trans／訊號無區分力 → C.4 不可建 → 上報使用者，選項：(i) runner 高頻截圖（≈5 Hz；**撤回**「同一訊號」宣稱，實體路徑無 runner → W9b 的 P_trans 欄不可評）；(ii) S7 app 內自注入（需同意）；(iii) 明示過渡態盲區保留、只靠實體人工判讀。
- **對 Codex 最擔心一點的正面回答**（「受控壞形態能紅」≠「實體觸控板過渡態已覆蓋」）：
  - 同一訊號：儀器在 app 內、與驅動來源無關；實體輪以 `open --env` 正常啟動並開儀器，`event` 記錄自帶實體事件的 phase／momentum；分段以 app 內 marks，不依賴 runner。
  - 同一謂詞語義：F1（人工）與 P_trans（機械）是同一失敗語義的兩個實作；對齊規則＝同一路徑同一次重複、同側（L／R）、P_trans 違反窗口落在人工標記的運動區間內（錄影逐幀審閱；若錄影 fps < 刷新率，人工判讀只證實不否證）。
  - **實體負對照（F10 第一段，固定第一批 N=5，禁止看結果追加）**：壞形態（步驟 1 成立用 M0；否則 M1diag）在 P3／P4／P5 各 5 次有效重複：P_trans 每路徑 ≥ **3/5** 觸發且觸發次與人工判讀對齊。3/5 是**工程資格門檻**，不是命中率估計；5 次樣本不足以推論真實命中率，故本計劃不作候選漏檢機率宣稱。
  - 若壞形態合成路徑紅、實體路徑 < 3/5 → 只可宣稱「合成路徑可證偽」，實體盲區保留並公開，候選實體輪只靠人工 F1–F4 → §7 第 3 條。
- 凍結：δ_trans、單位、取樣率、交疊點取法、段有效性門檻在 F2 結束時寫進 §13 並凍結；之後改動回 Phase 1。

### 5.5 C.5 D2 盲區二擇一（各附可證偽條件；校準後選定並凍結；F6 後 Phase 1 checkpoint）

盲區：gesture 段 `A→nil→A→B`（同值往返）、hold 段 `nil→settled`（離開對齊再回來），以及 R2-05 指出的第三形態 gesture 段 `A→nil(長停)→B`（卡住／偏移後才前進）——現行 C4 皆看不見。

- bind 解析先分型：`.fixture(index)`／`.literalNil`／`.unknown(payload)`；`unknown` 在 fixture 模式＝`PROBE-TRACE`。
- **(i) `C4-NIL-DWELL`**（trace-only；儀器 OFF 的候選運行可判）：任一 `.literalNil` 到下一個非 nil 記錄的時間 ≥ N_nil（段尾 nil 以段結束計）。
  - 校準資料＝場 1 的 **M0 儀器 OFF T1 ×10** trace（與候選同儀器狀態）。標籤：`A→nil→A`（同值往返）與 hold 段 nil＝**病灶形態集 P**；gesture 段 `A→nil→B`（A≠B）＝**合法集 L**。此標籤只描述 bind 型態，不是病灶真值，故 (i) **只宣稱覆蓋 P 的兩種形態**；`A→nil(長停)→B` 由 (ii) 處理，(i) 不宣稱閉合它。
  - 有區分力 ⇔ \|P\| ≥ 3 ∧ \|L\| ≥ 1 ∧ min(P) > max(L)（微秒域）；N_nil（微秒）＝ L_us + ⌈(P_us − L_us)/2⌉，其中 L_us＝max(L)、P_us＝min(P)，並須滿足 L_us < N_us ≤ P_us；任一不成立 → (i) 無區分力。整數微秒域計算，報告時再換算 ms。
  - 先證紅（構造性，如實標註）：新碼對校準集中每個 P 段觸發、對每個 L 段不觸發（單測正反例以真實校準片段為夾具）；**獨立驗證**＝F4 M0 ON ×10 的 trace（同時有 bind 與 frame）上，(i) 觸發的段須同時被 (ii) 的幾何判定標為停滯或回拉，否則記為 (i) 的假陽性並列示。
  - 風險登記：候選若因合理動畫時長產生更長 nil → 紅；不得放寬，帶證據回 Phase 1。
- **(ii) `C4-NIL-SHIFT`**（sampler 幾何，**只在儀器 ON 的 `-trans` 模式**，gesture 與 hold 段皆判）：任一 nil 窗內，中心卡變換前 midX 的進展**停滯**（連續 ≥ 100 ms 位移 < 3 pt）或**回拉**（方向反轉 > 3 pt）；hold 段 nil 窗內相對落定值偏移 > 3 pt 亦算。有區分力 ⇔ F4 M0 ON ×10 中至少一個 nil 窗量到上述訊號。(ii) 覆蓋三種形態，但只在 ON 輪可判。
- 選擇程序（預登記）：(i) 有區分力 → 採 (i)（候選 OFF 輪可判，覆蓋 P 兩形態）；(ii) 有區分力 → 亦採 (ii)（trans 輪覆蓋三形態）；兩者可並存。結論用語：(i)＋(ii) 皆採＝「D2 三形態於 trans 輪閉合、兩形態於候選輪閉合」；只 (i)＝「兩形態閉合、長停形態保留」；只 (ii)＝「僅 trans 輪閉合」；皆無＝「未閉合」。不得寫「已處置」以外的更強措辭。
- **Phase 1 checkpoint（F6 結束）**：校準數據、\|P\|／\|L\|、N_nil、(i) 假陽性列表寫入 §13 並向使用者報告後才進 F7。
- 落地：新碼進 `PRODUCT_CODES`＋Swift 字面量（掃描清單同步）；`C4-NIL-SHIFT` 與 `C7-TRANSIENT-STACK` 只存在於 Python 離線判定，Swift 側不得出現對應 `code:` 字面量。

### 5.6 C.6 實體手滑＝可判定程序

- 構建與啟動（身分護欄，R2-10；分輪環境，R4）：K<n> 閘門配置構建（Debug＋`-O`），**不設** fixture 旗標（真實 Music）。每次重複前：以 bundle ID 定界終止既有實例（`NSRunningApplication`／`pgrep -f` 取 pid 後 `kill`，不用全域按鍵；memory `no-global-keystrokes-in-gui-tests`）→ 確認實例數 0 → 依輪別啟動：
  - **R-off**：`open --env AZW_COVERFLOW_TRACE_PATH=<檔> -a "<Products>/Azathoth's Whisper.app"`（trace ON、sampler OFF）→ 判 `physical_valid_off`；
  - **R-neg／R-on**：`open --env AZW_COVERFLOW_TRACE_PATH=<檔> --env AZW_COVERFLOW_SAMPLER_PATH=<檔> -a …`（trace ON、sampler ON）→ 判 `physical_valid_on`。
  啟動後操作者腳本記錄 pid 的可執行檔路徑、`codesign -dvvv` CDHash、tree hash，與 trace／sampler header（bundle、exe 大小／mtime）比對一致才算該次有效。會撞鑰匙串授權框 → 使用者在場放行，先跑一次 preflight。
- 資料：使用者選定的一張 **20 曲、20 張封面**專輯（資料規模）。非 fixture 模式下 trace／sampler 以「ID 在當前 `items` 中的序位」記錄（§5.7 (8)），runner 端 `bindIndices` 不參與實體輪判讀。
- 失敗謂詞（任一即該次失敗）：F1 非應在最上層的鄰張遮住當下應 frontmost 的卡（運動中或靜止；正常遠張被近張蓋住不算）；F2 落定後 label ≠ 畫面正對那張，或首幀錯位後跳動；F3 放手後回拉／反向跳動／漂移；F4 首尾項不可達中心。
- 有效手勢定義（由 trace `event` 記錄判，不達即該次作廢、重做、計數；每路徑最多重做 2 次）：慢滑＝該段 `momentum≠0` 事件數＝0；甩動＝該段至少一個 `momentum≠0` 事件；反轉（P5）＝第一個 `momentum≠0` 事件之後 ≤ 1 s 內出現反向 `dx` 的 `phase≠0` 事件。
- 三輪（次數固定，第一批即結論，禁止追加）：
  - **R-neg**（負對照，儀器 ON，壞形態 build）：P3／P4／P5 各 **5** 次。
  - **R-off**（候選，儀器 OFF，人工 F1–F4）：P1–P9 各 **5** 次——這是不帶儀器的實際產品行為。
  - **R-on**（候選，儀器 ON，P_trans＋人工）：P3／P4／P5 各 **10** 次，P7／P8／P9 各 5 次。
- 路徑登記：

| 路徑 | 起點 | 手勢 | 反轉／終點 | 觀察區間 |
|---|---|---|---|---|
| P1 | 第 10 張（鍵盤定位） | 雙指慢滑向右 1–2 張（無慣性） | — | 運動中＋落定後 2 s |
| P2 | 同上 | 雙指慢滑向左 1–2 張 | — | 同上 |
| P3 | 第 10 張 | 快速甩動向右（帶慣性） | 任其落定 | 全程至落定後 2 s |
| P4 | 第 10 張 | 快速甩動向左 | 同上 | 同上 |
| P5 | 第 10 張 | 甩動向右，第一個 momentum 事件後 ≤ 1 s 反向甩動 | 中途反轉 | 同上 |
| P6L | 第 10 張 | 連續甩動至最左端（含回彈） | 端點 | 端點落定＋F4 |
| P6R | 第 10 張 | 連續甩動至最右端（含回彈） | 端點 | 同上 |
| P7 | 第 10 張 | 鍵盤 → ×9 到第 19 張 → 切 EDITOR → 切回 COVER FLOW | 初始值路徑 | 重建後落定 |
| P8 | 冷啟動 | Cmd-Q 結束 app → `open --env` 重啟 → 切入 Cover Flow（自動居中） | 首載 | 首載落定 |
| P9 | 任意 | 在 Music 切到同專輯另一曲（自動居中，H-04／H-05 路徑） | 切歌 | 落定＋2 s |

- 證據：`screencapture -v`（或 QuickTime）全程錄影＋逐次結果表（路徑／次序／有效手勢／F1–F4／P_trans／備註）＋ trace／sampler 檔；離線 P_trans（R-neg／R-on）＝**同幀層判定 `top === G`**（不需卡片語義身分）。
  **v5 改寫**：原「落定時幾何中心序位 vs VM centerID 序位」的核對，**只在 §5.3 的卡片語義身分方案（marker／contents 指紋／事後 AX 單幀標記）之一成立時才做**，且屬非裁決診斷；三案皆不成立 → 刪除該核對，缺口明記（W15 註）。**實體輪一律無 AX 客戶端**：無 XCTest runner、不開 Accessibility Inspector／VoiceOver，sampler 絕不讀 AX；manifest 記 `identity_source`。
- 判定：R-neg 依 §5.4；候選＝R-off 全部零失敗 ∧ R-on 零失敗且 P_trans 零觸發（段皆有效）；人工與 P_trans 不一致的那一次 → 記錄並查明，不得單方覆蓋。

### 5.7 C.7 回 Phase 1 觸發 ＋ 本計劃核准的基建改動

- **觸發**（任一即回 Phase 1）：修改契約 C0–C6 條款、閾值（§2 凍結參數）、截圖／取樣方式、settle／hold 時間、捲動驅動路徑（座標式 300px）、事件路由、測試 build 配置、`CoverFlowStrip`／`CoverFlowGeometry` 對外介面（K3）、`deploymentTarget`、以及凍結後的 δ_trans／N_nil／段有效性門檻。普通產品修復不觸發。
- **本計劃核准**（定稿即視為已過 Phase 1；等價性由 F3a 實證，「行為差異」定義＝在 F3a 的預登記檢查下無產品碼／結果差異，不宣稱位元組級零差異）：
  1. trace header 增 `epoch-us` 欄（每輪多寫一行常數；解析端相容）；
  2. bind 解析分型 `.fixture／.literalNil／.unknown`，讀取端帶時間戳；`unknown` → PROBE-TRACE；
  3. `AppModel.live()` DEBUG 分支：安裝條件＝`tracePath 非空 && !isUnitTestHost`，fixture ON 時行為不變、fixture OFF 也安裝（單測：fixture ON→安裝一次；fixture OFF＋path＋unitTestHost=1→不安裝）；
  4. 新碼 `C4-NIL-DWELL`（進 `PRODUCT_CODES`）與／或 `C4-NIL-SHIFT`（僅 Python 離線，trans 輪）——依 §5.5 選擇程序，可並存；F6 checkpoint 後生效；`C7-TRANSIENT-STACK` 僅 Python 離線；
  5. 判定器 `candidate`／`negative-control` 子命令、`PRODUCT_CODES` 擴充、R5-5 殺死簽名常量、殺死含 C2 條款；facade `h02_gate_eval.py` `__all__` 與 `test_h02_gate_parsing.py` 掃描清單同步；
     **（v5 追加）profile 機制**：新模組承載 R27 profile（外部 JSON，倉庫外；含 M0 每步登記與允許碼／M2·M3 殺死簽名／ui-T0′ 三份基準），`staging → 原子啟用`（四份齊全且各自有效才以含四者 hash 的 manifest 一次寫入啟用），`_signature_deviations` 改讀 active profile 並雙列 historical R55，缺 active → 無效；`R55_KILL_SIGNATURES` 與 `REQUIRED_KILL_STEPS` 逐字不動；
     **R4-F 的甲案裁定（2026-09-18，實施中補記）**：`evaluate_frozen_conformity` 的判據改讀 `active_profile.m0[(label, step)].allowed_codes`／`.sig_set`；**無 active profile、或該步未登記於 `profile.m0` 時，與 `FROZEN_REGISTRATION`／`FROZEN_ALLOWED_CODES` 的差異一律只入 `frozen_deviations`（26.6.2 historical 欄），不產生 `reasons`、不使結論落入「不可判定」**——場 0 的 `cf-m0-27` 首跑正是此情形（呼應第 4 項「只列雙欄偏離、不停」）。舊表的**值**逐字不動，只改消費方式。`activate_r27` 要求 `m0` **登記全部 9 個步驟**，缺一拒絕啟用（殘缺 profile 會讓未登記步驟永遠不被檢查）。
     **溯源欄位的裁定（2026-09-18，主線程裁決，覆核意見未採納）**：profile 的 `tree_hash`／`cdhash` 是**場 0 基準樹的溯源資訊**，**不得**與受評運行的 tree hash 作相等比對後判無效——`M2_K`／`M3_K` 依設計就是從候選 tree 重建（§5.2），樹 hash 本來就不同，那樣做會讓 C.2 恆為無效。溯源只印進報告；**該比的是環境指紋**（§10 R13）：profile 有指紋而運行端未提供 → `unmeasured` → **無效（fail-closed）**，有值不符 → 無效，profile 無指紋 → `unknown` 不影響結論。此決定須有測試釘住。
  11. **（v5）G6 的無 AX host 測試基建**：layer-only 幾何讀取與 U1c 分解的測試側工具、卡片語義身分方案（§5.3 三案）之實作與其 ON／OFF 觀察者效應驗證；
  12. **（v5）場 0 四棵樹的預構建與身分記錄**（`fix4/trees/`、`fix4/dd/`，倉庫與 iCloud 樹之外；`build-for-testing` 後全程 `test-without-building`）；
  6. `Scripts/h02_sampler_report.py`（`timeline`／`trans`／`nil`）；
  7. **證據持久化**：runner 讀 `TEST_RUNNER_AZW_EVIDENCE_DIR`，trace／sampler／marks 以 `<test>-<iteration>.*` 命名寫入；缺省退回現行 temporaryDirectory（閘門輪行為不變，單測釘住）；tearDown 寫 manifest（tree hash、CDHash、test、iteration、各檔 md5）；判定器把 manifest 缺檔判無效；
  8. 儀器 `CoverFlowUITestSampler`（獨立檔、`.common` run loop、presentation layer、provider 注入 centerID／items 序位）；非 fixture 模式的序位映射；**（v5）一律不讀 AX**；卡片語義身分依 §5.3 的三案排序，其中 ① 需在 `CoverFlowView` 內容閉包加 DEBUG-only 被動 `NSViewRepresentable` marker（產品檔 DEBUG 區塊，屬本項儀器範圍，不另觸發 §5.7；須做 ON／OFF 觀察者效應驗證）；
  9. 契約報告新增：截圖起訖 wall-clock、C2 取樣點座標與候選卡、落定耗時與輪詢次數（只增輸出，不改判定）；
  10. runner marks 檔（步驗邊界、按鍵、捲動、截圖、落定）。
  每項先 TDD；(1)(2)(3)(7)(9)(10) 對儀器 OFF 閘門的等價由 F3a 驗證；(4) 依 §5.5 checkpoint；(5) 須與修正後 C.1／C.2 完全一致；(6)(8) 只作用於 ON 輪。

## 6. 任務清單（每項帶 DoD）與場次表

**場次表**（每場一次 Automation Mode 授權，使用者在場；先 preflight）

| 場 | 內容 | 估時 |
|---|---|---|
| **場 0（v5 新增，先於場 1）** | 基準重建（四棵樹已預構建；全程 `test-without-building`、串行、每次驗 Products 身分）：(i) OS 27 的 S2／V5 最小健康 preflight（不計證據輪）→ (ii) `cf-m0-27` ×10（a1d3407），首份有效即凍結 R27 staging → (iii) M2 ×3、M3 ×3 → (iv) `ui-T0′`（鑰匙串 preflight 不計證據）。四份皆有效且未觸發停止 → 原子啟用 `active_profile=R27`。任一停止條件觸發即當場停、不續跑 | 60–75 分 |
| 場 1 | F3a：M0（＝基建 tree `1055ff0`＋sampler）OFF 四測試 ×3，**對照已啟用的 R27**；F6 校準：M0 OFF T1 ×10；F3b／F4／F5：M0 ON 四測試 ×10（＝`cf-m0-trans`）；F4 spike：S-b ON ×3、S-off ON ×3；F5 備案：M1diag ON ×10（僅 M0 不紅時） | 55–70 分 |
| 場 2 | F9：`cf-cand-K<n>` ×20 → M2_K／M3_K ×3 → `cf-cand-K<n>-trans` ON ×10；F9b：既有 UITests 17 條（preflight＋證據輪） | 60–75 分 |
| 場 3 | F10：R-neg（15 手勢）→ R-off（50）→ R-on（45）；錄影 | 60–90 分 |

**場次的人工守則（v5；判定器不強制，靠人守，違反即證據包作廢）**
- **候選禁止提前開始**：`active_profile=R27` 原子啟用之前，不得跑任何 `cf-cand-K<n>` 運行。判定器只擋「無 active profile 時 C.2 下結論」（回無效），**不擋 C.1 開跑**——C.1 的語義本就與 profile 無關（§5.1）。
- **場 0 (i) preflight 的方法（待使用者於場 0 當天確認）**：跑一輪 `-only-testing:AzathothsWhisperUITests/CoverFlowUITests`**不計證據輪**，只驗 Automation Mode／鑰匙串／Products 身分健康與 S2 已知點分類命中；V5 的「十次一致」留給 (ii) 的 ×10 判（§7 preflight 定義不含 V5）。**這是推論**（§7 第 3 條 preflight 的字面讀法），非原文明寫。
- **既有 UITests（場 0 (iv)、場 2 F9b）不帶閘門參數**：歷史 `ui-T0` 的真實 invocation 無任何 build settings 覆寫（預設 Debug ＝ `-Onone`），選擇器須覆蓋 **17 條／三個 suite**（Shell 11＋Batch 5＋BatchLive 1 skip，`BatchLiveUITests` 是獨立 class）；ui-T0′ 的樹也必須以同配置構建，否則與 ui-T0 不是同一比較條件（W10）。

| # | 任務 | DoD |
|---|---|---|
| F0 | **本 session**：Plan 定稿（Codex R1／Opus 四視角 → v2 → Codex R2 → R3 整體確認） | §14 逐條處置；使用者確認執行＋批准操作護欄 |
| F1 | 判定器 TDD（Python）：`candidate`（通過／不通過／無效；夾具：180 全 PASS、1/180 C2、1 PROBE、19 次、UNTAGGED、manifest 缺檔）；`negative-control`（殺死含 C2、偏離列示、未解釋→不可判定、殺死點消失＋非 Strip diff 分支、無效、不可建）；`PRODUCT_CODES` 佔位；facade 與掃描清單同步 | RED→GREEN；既有 92 條仍綠 |
| F2 | 基建：§5.7 (1)(2)(3)(7)(9)(10)＋儀器 (8)＋Z1 spike（U1a／U1b／U1c，各出結論）＋K3 spike（M2／M3 檔在含 H3-a(a) 參數草案的 tree 是否編譯）＋H3 觸發 spike（nil 起始是否回寫 items[0]） | Swift 單測 RED→GREEN；儀器 OFF 預設；`strings` 0；Z1 三項結論寫 §13 並**立即上報**使用者（成立／備案／不可建），再開場 1 |
| | **v5 結算（2026-09-18）**：(1)(2)(3)(7)(9)(10) 已完成並驗收（`strings` 全 0、`ProductCodeSingleSourceTests` 綠）；**Z1 已結案**（U1a／U1c／U-DL 成立、U5 已答、U1b 改無 AX 方案）；**儀器 (8) 與報告腳本 (6) 移到場 0 之後**（場 0 是存亡門，先做可能白做）；**K3 spike 只在 b′ 被否決後才需要**（b′ 不動 Strip 介面）；單測基準改 T0′ | — |
| **F2b**（v5 新增） | 判定器 R27 profile（staging→原子啟用、雙列偏離、缺 active 即無效）TDD ＋ 場 0 四棵樹預構建與身分記錄 ＋ **R27 staging 產生器與 `profile stage`／`profile activate` CLI**（從 `cf-m0-27`／M2／M3／ui-T0′ 的運行產物產出 staging JSON；場 0 當天不得手寫 JSON） | Python 測試 RED→GREEN 且既有全綠；`PREBUILD.md` 四棵樹表齊全（tree hash／Strip md5／CDHash／Products／log）；M2·M3 與 M0 只差 Strip；未跑任何測試 |
| **F2c**（v5 新增，場 0 之後） | spike 3（不需使用者在場）：§5.3 的無 AX 卡片語義身分三案；b′ 在真實組裝的六項（20 曲非同步填入、切 tab 重建只灌一次、佔位圖→`.task` 不再觸發命令、generation 取代與遲到回呼、已佈局後的 `trackChanged` 邊界、單參數 `onGeometryChange` 編譯路徑）；動畫四分法 | 各項有數字結論；身分方案定案或明記缺口；b′ 兩接縫有結論 |
| **F2d**（v5 新增，F2c 之後） | G6 的無 AX 正式 RED 凍結（測試名、失敗輸出、基線 hash） | RED 在未改 H3 的基線上重現；覆蓋遠距、兩方向、末端 |
| F3 | 場 1 前半：F3a 等價對照（**v5：基建 tree OFF ×3 對已啟用的 R27**）；F3b 健康 (a)–(e) | 全成立；否則 §10 R2 階梯上報 |
| F4 | 場 1 後半：M0 ON ×10 時間序列（兩格不一致的觀察／推論／未排除）；S-b／S-off ON ×3 → K1 選枝 ADR | `timeline` 報告；ADR 入 §13 |
| F5 | 同場：`trans` 離線判定 M0 ON ×10；不紅則 M1diag ON ×10；凍結門檻 | §5.4 步驟 1–3 之一成立；不可建則上報 |
| F6 | 離線：以 M0 OFF T1 ×10 trace 做 (i) 標定；(ii) 以 ON 輪 hold 段；選定＋實作＋單測 → **Phase 1 checkpoint 報告使用者** | §5.5 程序有數據；N_nil 唯一 |
| F7 | 產品修復（TDD）：K5 VM 測試先紅；EDGE 7/7 作 RED；H3 狀態機（**v5：走 b′，含 `commandedID`／`scrollID` 分離與原子守衛**）；H2 依 ADR；同源／不停舊值單測；**RENDERED 轉綠**（v5：T0′ 上它是紅，屬修復前 RED）；**G6 的無 AX 遠跳 RED→GREEN（W15）**；K8 大專輯測試（visible items／artwork task 數有界） | K1–K8 逐項有測試；全量單測零 issue；`git diff --stat` 相稱 |
| F8 | Phase 3 `/simcodex`（最終 tree）；觸及 §5.7 觸發清單 → 回 Phase 1；任何產品源碼改動 → 重走 F7→F8 | 全綠或殘留逐條裁決 |
| F9 | 場 2：K7 前置 → `cf-cand-K<n>` ×20 → C.1 → M2_K／M3_K ×3 → C.2 → `-trans` ×10 → P_trans。分支：無效→修基建重跑同 K（受上限）；不可建→上報；不通過→F7 | 三者通過 |
| F9b | 同場：既有 UITests 17 條（preflight＋證據輪）＝W10；xccov＝W1；pbxproj／xcscheme diff＝W14；Release `strings`＝W11 | 各項成立 |
| F10 | 場 3：R-neg → R-off → R-on；錄影＋結果表＋trace | §5.4 實體負對照成立；候選零失敗零觸發 |
| F11 | 結論與證據包（slipknot 28）；unknowns 對賬（§12）；收尾事項依 N3 | §7 全部回扣；證據在 `~/Developer/bjork-h02-gate/fix4/` |

## 7. 驗收標準與結論程序

每個 W 恰歸一個失敗類別（見結論程序編號）：

| # | 標準 | 判定 | 不成立時歸類 |
|---|---|---|---|
| W1 | 新單測全綠；新增純邏輯行覆蓋 ≥ 80%；Python 判定器測試全綠 | xcresult＋`xccov`；unittest | 4 不通過（回 F7／F8 補測） |
| W2 | **（v5 改寫）候選全量單測零 issue**：EDGE 7/7、RUNTIME 3/3、RENDERED、K5 新 VM 測試、**G6 的無 AX 遠跳測試**與全部新增測試皆綠。T0′ 的 8 issues 只作修復前 RED，不是容許紅燈 | 全量單測輸出 | 4 不通過 |
| W3a | F3a 等價對照成立 | F3a | 3 不可判定（基建改動非等價 → 回 Phase 1） |
| W3b | F3b 健康 (a)–(e) 成立 | F3b | 1 不可建（經 §10 R2 階梯；(c) 超標例外 → 3） |
| W4 | C.4 負對照成立（合成）且門檻凍結 | F5 | 1 不可建（§5.4 步驟 3） |
| W5 | D2 選定有數據、N_nil 唯一並經 checkpoint；或明列閉合範圍 | F6 | 3 不可判定（僅影響閉合宣稱） |
| W6 | **C.1**：`cf-cand-K<n>` ×20 有效且 180/180 PASS | `candidate` | 4 不通過（無效 → 2） |
| W7 | **C.2**：M2_K／M3_K ×3 有效；殺死（含 C2）達標；偏離已列示並解釋。**（v5）偏離比對對象＝已啟用的 R27 active profile**；`R55_KILL_SIGNATURES` 只出現在 historical 欄、不參與結論；無 active profile → 無效 | `negative-control` | 殺死不足 → 4；未解釋／殺死點消失＋非 Strip diff → 3；編譯不相容 → 1；無效（含缺 active profile）→ 2 |
| W8 | **C.4**：`cf-cand-K<n>-trans` ×10 全部段有效且 P_trans 零觸發 | `trans` | 觸發 → 4；任一段不可判定 → 3；運行無效 → 2 |
| W9a | **C.6 負對照**：R-neg 每路徑 ≥ 3/5 且與人工對齊 | 結果表＋trace | 3 不可判定 |
| W9b | **C.6 候選**：R-off 零失敗；R-on 零失敗且零觸發（段皆有效） | 結果表＋trace | 失敗／觸發 → 4；段不可判定或重做額度耗盡 → 3；`physical_valid_off／on` 缺且仍有額度 → 2 |
| W10 | 既有 UITests 17 條與 **`ui-T0′`（v5：場 0 在 macOS 27 上於 `aad6a9b`＋R5-3 四檔重建的 T0 樹跑出的首份有效運行）** 逐條相同；舊 `ui-T0`（26.6.2）只作歷史 | 清單 diff | 4 不通過 |
| W15 | **（v5 新增，G6）** 無 AX 遠跳 RED→GREEN：修復前 RED 已凍結（測試名、失敗輸出、基線 hash），候選上轉綠；覆蓋未具現遠距目標、兩方向與末端；斷言 requested 身分且 \|Δlayout\| ≤ 3pt；VM 測試證明 `trackChanged`／載入完成／重建匯入同一 command pipeline | 全量單測＋凍結的 RED 紀錄 | 4 不通過；身分來源三案皆不成立 → 3（缺口明記，舉證推到 C.6＋C.1） |
| W11 | Release `strings` 對測試／儀器符號全 0；新增 DEBUG 檔整檔 `#if DEBUG` | grep＋`strings` | 4 不通過 |
| W12 | 附件只含裁切到視窗的圖；實體輪 trace 去識別化摘要 | 腳本＋人工核 | 2 無效（證據包退回重出，不重跑） |
| W13 | K3：M2／M3 變異檔在 K<n> tree 直接編譯 | F9 構建日誌 | 1 不可建 |
| W14 | pbxproj／xcscheme 相對 T1 前快照只多新檔條目 | diff | 4 不通過（回 F8 修基建） |

**結論程序**（互斥、按序取第一個成立者）：
1. **不可建**：W3b 健康經 §10 R2 階梯用盡仍不成立；W4 依 §5.4 步驟 3 不可建；W13 編譯不相容 → 上報（帶選項）。
2. **無效**：任一終點運行（`cf-cand`／`M2_K`／`M3_K`／`-trans`／F9b）運行無效或證據不完整；實體重複 `physical_valid_off／on` 缺**且該路徑仍有重做額度**；W12 證據包不合格 → 修基建／補證據、重跑同 K 或重做／重出（受無效上限）。額度耗盡不落此類。
3. **不可判定／待使用者裁決**：W3a 不成立（基建非等價 → 回 Phase 1）；W3b (c) 觀察者效應超標；W5 閉合範圍受限；W7 偏離未解釋或殺死點消失＋候選改了 Strip 以外檔（回 Phase 1 辯論移植）；W8／W9b 任一段不可判定；W9a 不成立（含 Z1 退到 runner 截圖備案使實體 P_trans 不可評）；實體重做額度耗盡；§5.1 量測成因預登記觸發 → 帶證據上報，使用者裁決。
4. **不通過**：W1／W2／W6／W7（殺死不足）／W8（觸發）／W9b（失敗或觸發）／W10／W11／W14／**W15** 任一不成立 → 回 F7／F8（受護欄約束；產品源碼改動則重走 F7→F8→F9）。

**（v5 新增）場 0 的停止分支**（在 W1–W15 之前適用；場 0 未全過則不進場 1，後續 W 一律不評）：
1. preflight（Automation Mode／鑰匙串／S2 身分健康）**不計證據輪、不計無效**；
2. 對固定 `(tree, run-kind)`，**第一份有效批次先落盤、hash、凍結**，之後才評 V5 陽性對照／缺陷 2／缺陷 3；
3. 第一份有效**未抓到缺陷即停止**，禁止以第二份有效重抽（首份規則）；
4. 尚無有效批次時，同一 `(tree, run-kind)` 累積**兩份無效即停**；其他 run-kind 插入不重置計數；
5. 場 0 停止一律歸類「**環境前置未成立／待使用者裁決**」（不屬 1–4 類，也不重判 R5-5）；
6. R27 全程只寫 `staging`，**四份（M0／M2／M3／ui-T0′）皆有效且未觸發停止**才以含四者 hash 的 manifest **原子切換** `active_profile=R27`；中途停止保留 staging 但不啟用、候選禁止開始。
5. **通過** ⇔ W1–W14 全部成立且第 3 條無任何觸發。

## 8. 測試策略與流程偏離聲明

- 單元：判定器（unittest）；trace 分型／manifest／sampler 記錄解析／`writebackFindings` 新碼（Swift Testing）；VM 狀態機與 K5；產品側「z 序不停舊值」純函數（S-b／S-off 選定後）；EDGE／RUNTIME／RENDERED 接線測試；K8 大專輯測試。
- 集成：F3a／F3b＝真實組裝上的基建與儀器接線；M2／M3 構建＝介面相容。
- E2E：四條 XCUITest ×20、變異 ×3、trans ×10、既有 UITests、實體三輪。
- 覆蓋率：`coverage_gate.sh` 只量 Services＋Infra（不動）；新純邏輯以 W1 逐檔量。
- **流程偏離**：fatboyslim Phase 3「代碼測試全綠」＝W2（**v5：＝候選全量單測零 issue**）；Phase 4「全量測試通過」由 §7 結論程序取代；F9／F9b／F10 一律在 simcodex 之後、最終 tree 上執行。
- 跑任何 UITest 前確認使用者在場；非 fixture 啟動先 preflight 鑰匙串授權框。

## 9. 影響面

新增（皆 DEBUG／測試）
- `App/UITestSupport/CoverFlowUITestSampler.swift`；`Tests/Features/CoverFlowUITestSamplerTests.swift`；`CoverFlowTraceFormatTests`／`CoverFlowGateLogicTests`／`CoverFlowViewModelTests` 增測
- `Scripts/h02_sampler_report.py`＋`test_h02_sampler_report.py`；`Scripts/test_h02_gate_candidate.py`
- `~/Developer/bjork-h02-gate/fix4/`（證據、trace／sampler／marks、manifest、候選 hashlist；repo 外）

修改
- 產品源碼：`Features/CoverFlow/CoverFlowStrip.swift`（H3 觸發＋H2 選枝；介面不變 K3）；**`CoverFlowViewModel.swift`（必改：K5 狀態機）**；`CoverFlowView.swift`（binding setter 配合，若 H3-a(b)）；`CoverFlowGeometry.swift` 不動
- 測試基建：`CoverFlowTraceFormat.swift`、`CoverFlowUITestTrace.swift`、`AppModel+CoverFlowUITest.swift`／`AppModel.live()` DEBUG 分支、`CoverFlowGateLogic.swift`、`UITests/Support/CoverFlowProbe.swift`（bind 分型、報告新增輸出、marks）、`UITests/CoverFlowUITests.swift`（evidence dir、marks；步驟與契約不變）
- 判定器：`h02_gate_model.py`、`h02_gate_rules.py`、`h02_gate_cli.py`、`h02_gate_eval.py`（facade）、`test_h02_gate_parsing.py`（掃描清單）
- `project.yml`：新增檔入 target（xcodegen 重生成）

不動：閘門計劃 §6、凍結參數、`CoverFlowUITestFixture`／`CoverFlowUITestMusic`、既有測試斷言、ACCEPTANCE、交接檔。

## 10. 風險與回退

| # | 風險 | 緩解 |
|---|---|---|
| R1 | 儀器改變時序 | 獨立檔（不觸 `readUntilQuiet`）；F3b (c) 結果面量化；候選 ×20 與變異 ×3 儀器 OFF |
| R2 | Z1 不成立（`drawingGroup` 合成單層、層無身分、無法還原變換前 midX） | 階梯：CALayer 次序／hitTest → AX hit-test → 層外框與 in-process AX 配對 → runner 高頻截圖（撤回同一訊號宣稱）→ 不可建上報；F2 spike 一出結論立即上報 |
| R3 | 取樣器在實體 live scroll 期間靜音（run loop 模式） | `.common` 模式；(e) 自證斷言 → `PROBE-SAMPLER` |
| R4 | H3 以 nil 起始的首次回寫被誤判為使用者接管 | K5 狀態機；F2 spike U5；EDGE／T4.s2 會抓 |
| R5 | S-b／S-off 皆停在舊值 | 選枝規則 (iv)：回 Phase 1 問升 15 |
| R6 | 候選改 VM 使 M2_K／M3_K 殺死點消失 | §5.2 第四分支：回 Phase 1 辯論移植，不計熔斷 |
| R7 | D2 新碼在候選上因合理動畫時長假紅 | 只能回 Phase 1，不放寬 |
| R8 | 實體輪 trace 含真實曲目資訊 | W12 去識別化；trace 留本機 |
| R9 | 授權框／Automation Mode 逾時 | 場次表、preflight、使用者在場 |
| R10 | 為求綠改測試／跑到綠為止 | §5.7 觸發清單；首份規則；無效上限；候選上限；多維熔斷 |
| R11 | 部署目標被順手改動 | §5.7 觸發清單含 `deploymentTarget` |
| R12 | 使用者在場成本（**v5：四場 ≈ 4–5 小時**） | 場次表合併運行；Z1 spike 先報結論再開場；場 0 的構建全部在到場前完成 |
| **R13**（v5） | 環境再度漂移（macOS／Xcode 又升級）使 R27 基準再失效 | R27 profile 的 m0 段記**環境指紋三鍵** `os_build`／`xcode_build`／`sdk`（逐字相等比對，**fail-closed**：不符 → 無效；profile 有指紋而運行端未以 `--run-env-fingerprint` 提供 → `unmeasured` → 無效；profile 無指紋 → `unknown` 不影響結論）。**顯示設定**另記在 m0 頂層 `display`，只作溯源、印進報告、**不參與比對**（沒有兩端通用的標準字串，放進相等比對只會製造假 mismatch；2026-09-18 主線程裁定） |
| **R14**（v5） | F-AX：閘門（XCUITest 讀 AX）與無 AX 真實使用走不同路徑，使候選「全綠但真實失敗」 | G6／W15 的無 AX RED→GREEN；C.6 實體輪明定無 AX 客戶端；sampler 不讀 AX；身分方案須 ON／OFF 驗證 |
| **R15**（v5） | b′ 的成功窗口極窄（首次佈局回呼內同步才 21/21，落到下一週期即 0/48）；真實組裝多了非同步載入、tab epoch、圖片 task | F2c spike 3 六項先驗；失敗則回 Phase 1（H3-a(a)＋K3，或 H3-b／升目標） |

**回退**：產品源碼改動限 `CoverFlowStrip.swift`／`CoverFlowViewModel.swift`／`CoverFlowView.swift`；`git checkout` 即回 M0；測試基建新增檔可整檔刪除、修改檔還原、xcodegen 重生成。

## 11. 運行命令

```bash
G=~/Developer/bjork-h02-gate/fix4
cd AzathothsWhisper
COMMON=(-project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper -destination 'platform=macOS' \
        -enableCodeCoverage NO SWIFT_OPTIMIZATION_LEVEL=-O -test-timeouts-enabled YES -default-test-execution-time-allowance 300)

# 前置 K7
xcodebuild test -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper -destination 'platform=macOS' \
  -only-testing:AzathothsWhisperTests \
  -skip-testing:"AzathothsWhisperTests/BatchOverlappingLoadTests/overlappingLoadSuspendsPollingUntilLastCompletes()" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -resultBundlePath "$G/unit-K<n>.xcresult"
/usr/bin/python3 -m unittest discover -s Scripts -p 'test_h02_*.py'
git diff --name-only a1d3407 -- Features/ > "$G/cand-K<n>/product-files.txt"

# C.1 候選 ×20（儀器 OFF；證據持久化）
TEST_RUNNER_AZW_EXPECTED_APP_DIR="<Products>" TEST_RUNNER_AZW_EVIDENCE_DIR="$G/ev/cand-K<n>" \
xcodebuild test "${COMMON[@]}" -only-testing:AzathothsWhisperUITests/CoverFlowUITests -test-iterations 20 \
  -resultBundlePath "$G/cf-cand-K<n>.xcresult" 2>&1 | tee "$G/cf-cand-K<n>.log"
python3 Scripts/h02_gate_eval.py candidate --log "$G/cf-cand-K<n>.log" --xcresult "$G/cf-cand-K<n>.xcresult" \
  --evidence "$G/ev/cand-K<n>" --iterations 20

# C.2 負對照
python3 Scripts/h02_gate_eval.py negative-control --baseline-log … --baseline-xcresult … \
  --m2-log "$G/cf-M2K.log" --m2-xcresult "$G/cf-M2K.xcresult" --m3-log "$G/cf-M3K.log" --m3-xcresult "$G/cf-M3K.xcresult" \
  --product-files "$G/cand-K<n>/product-files.txt"

# C.4 trans（儀器 ON；四測試 ×10）
TEST_RUNNER_AZW_EXPECTED_APP_DIR="<Products>" TEST_RUNNER_AZW_EVIDENCE_DIR="$G/ev/cand-K<n>-trans" TEST_RUNNER_AZW_COVERFLOW_SAMPLER=1 \
xcodebuild test "${COMMON[@]}" -only-testing:AzathothsWhisperUITests/CoverFlowUITests -test-iterations 10 …
python3 Scripts/h02_sampler_report.py trans --evidence "$G/ev/cand-K<n>-trans" --delta-itemwidth 0.20

# 實體輪（正常 LaunchServices 啟動＋環境注入）
# R-off：只注入 trace（sampler OFF）
open --env AZW_COVERFLOW_TRACE_PATH="$G/ev/physical-K<n>/off-P1-1.trace" -a "<Products>/Azathoth's Whisper.app"
# R-neg／R-on：trace＋sampler
open --env AZW_COVERFLOW_TRACE_PATH="$G/ev/physical-K<n>/on-P3-1.trace" \
     --env AZW_COVERFLOW_SAMPLER_PATH="$G/ev/physical-K<n>/on-P3-1.sampler" -a "<Products>/Azathoth's Whisper.app"
screencapture -v "$G/ev/physical-K<n>/P3-1.mov"
```

（runner 端環境變數以 `TEST_RUNNER_` 前綴轉發；儀器旗標由 `launchCoverFlow` 轉入 app 的 launchEnvironment——F2 實作、單測釘住單一來源。既有 UITests 命令沿用閘門計劃 §10。）

### 11.1 場 0（v5 新增；逐字命令的權威來源＝`~/Developer/bjork-h02-gate/fix4/trees/PREBUILD.md`）

命令**不在本計劃重複**，避免兩處漂移：四棵樹的路徑／CDHash／`RUN_ENV`／`evidence_hash()`／每段 `test-without-building` 與 `profile` 呼叫，一律以 `PREBUILD.md` 的「場 0 當天要跑的命令」段為準（該檔與四棵樹一起凍結，並記有各棵樹的 build invocation 原文）。本節只定不變式：

1. **全部 `test-without-building`**：四棵樹已預構建（`fix4/dd/<tree>`），當天不得再構建（重建會改 CDHash，且 `build-for-testing` 每次都重新註冊 LaunchServices）。開跑前復驗 `lsregister -dump | grep -c bjork-h02-gate/fix4/dd` ＝ 0，並逐一比對 8 個 bundle（app＋runner）的 CDHash。
2. **每段都要帶 `TEST_RUNNER_AZW_EXPECTED_APP_DIR`**（指向該樹的 `Build/Products/Debug`）：空值會被 `CoverFlowUITests.swift`（M0／M2／M3 樹第 136 行）的 `!expected.isEmpty` 守衛直接判 `PROBE-WRONG-BINARY`，**不是**「跳過身分檢查」。
3. **CoverFlow 四測試用閘門配置**（`-enableCodeCoverage NO SWIFT_OPTIMIZATION_LEVEL=-O`）；**既有 UITests（(iv) ui-T0′）不帶任何 build settings 覆寫**（歷史 `ui-T0` 的真實 invocation 即如此），選擇器覆蓋 17 條／三個 suite（`-only-testing:AzathothsWhisperUITests -skip-testing:AzathothsWhisperUITests/CoverFlowUITests`），allowance 明示對齊哪一份歷史基線。
4. **判定一律呼叫 repo 現行判定器的絕對路徑**（樹內 `Scripts/` 是 2026-09-12 舊版，無 `candidate`／`profile` 子命令）。場 0 期間**不給** `--profile-dir`（尚無 active profile；顯式給不存在的路徑＝輸入錯誤 exit 2），**要給** `--run-env-fingerprint "$RUN_ENV"`。
5. **staging 一律走 CLI**：`profile stage-m0`（強制 ×10）→ `profile stage-mutant --name M2|M3`（強制 ×3、baseline ×10）→ `profile stage-ui`（強制 17 條）→ `profile check` → `profile activate --version scene0-run-1`。首份有效即凍結、**無覆蓋開關**；手改 staging 後重跑 check 會被凍結帳本判 STOP；`activate` **現場重算**停止條件，不採信 `scene0-check.json`。
6. **停止即停**：`profile check` 回 STOP（exit 1）當場結束場 0，不得續跑場 1；歸類「環境前置未成立／待使用者裁決」（§7）。
7. **證據**：每段算 `evidence_hash`（log＋xcresult，**排除 `database.sqlite3*`**——首次 `xcresulttool` 讀取會改寫它，含它則事後重算不出來），hash 隨 staging 一起凍結。

## 12. Unknowns 賬本（slipknot 29）

| # | 未知 | 象限 | 處置 |
|---|---|---|---|
| U1a | zIndex 是否反映為 CALayer 子層次序／`hitTest` 可讀 | 已知未知 | **[動工前]** F2 spike |
| U1b | `.drawingGroup()` 後每張卡是否各有可辨識的層（身分對應） | 已知未知 | **[動工前]** F2 spike；備案 AX 配對 |
| U1c | 變換前 midX 能否由層屬性還原 | 已知未知 | **[動工前]** F2 spike；備案 AX bbox＋偏差上界 |
| U2 | M0 過渡態是否真的有 z 序滯後 | 已知未知 | F5；不紅則 M1diag |
| U3 | M0 的 bind nil 形態分布 | 已知未知 | 場 1 OFF T1 ×10 |
| U4 | `onGeometryChange`→`@State` 是否停在舊值、滯後幾幀 | 已知未知 | F4 S-b／S-off spike（不以 M1 推 H2-b） |
| U5 | 以 nil 起始時 SwiftUI 是否在首次佈局回寫 items[0] | 已知未知 | F2 spike（EDGE harness） |
| U6 | 實體慣性事件下 P_trans 區分力 | 已知未知 | F10 R-neg |
| U7 | 儀器對時序的影響量 | 已知未知 | F3b (c) |
| U8 | `screencapture -v` 錄影 fps 是否 ≥ 刷新率 | 已知未知 | F2 核；不足則人工判讀只證實不否證 |
| U9 | Premortem：(a) 合成全綠、實體慣性仍疊——對策 §5.4 實體負對照 3/5；(b) 儀器改時序讓病灶消失——獨立檔＋F3b (c)＋候選 OFF；(c) 為求綠改判據——§5.7＋護欄；(d) 儀器在實體 live scroll 靜音致假綠——`.common`＋(e) 自證 | 未知未知逼出 | 已登記 |
| U10 | 首載走初始值路徑還是運行時路徑；H3 是否改變 T3.s1 行為與 M3 在該步的殺死 | 已知未知 | F2 spike 讀首載 bind 序列；F7 以 T3 驗 |
| U11 | `centerID` 六重角色是否需拆分（架構天花板）；H3-b 即拆法 | 已知未知 | F4 ADR 一併裁決；需拆則屬 K3／§5.7 觸發回 Phase 1。**v5**：b′ 已要求分離 `commandedID`／`scrollID`，等於先拆出兩個角色 |
| **U1a／U1b／U1c／U5／U-DL** | Z1 五項 | **已結案（2026-09-18）** | §5.3、§13；U1b 轉為「無 AX 身分三案」待 F2c |
| **U12**（v5） | F-AX：XCUITest 的 out-of-process AX 是否也改變 LazyHStack 具現與落點 | 已知未知 | F2c spike 3；影響 C.1 對無 AX 真實行為的外推力（R14） |
| **U13**（v5） | F-JUMP 的完整邊界：哪些 origin／距離／方向會落鄰卡；`withAnimation` 為何貼齊 | 已知未知 | F2c 動畫四分法＋F2d 的 RED |
| **U14**（v5） | macOS 14／26 運行時語義（本機只有 27，無法實證） | 已知未知 | 結論範圍明定「27 上驗證、26 僅有修復前歷史證據」；需舊 OS runner 才能補 |
| **U15**（v5） | macOS 27 上 M0 的缺陷 2／缺陷 3 是否仍以足以支撐判據的形態穩定存在 | 已知未知 | **場 0**（存亡門）；不成立則場 0 後停止上報 |

## 13. 實測記錄（實施中回填）

### 2026-09-13 Phase 2 第一段（F1／F2-1／Z1 spike 並行，三個 Opus 5 worker；後兩者因 session limit 中斷）

**F1 判定器（完成）**：`candidate`／`negative-control` 子命令＋`evaluate_evidence`；新測試 52 條，既有 92 條不變（`Ran 144 tests … OK`，主線程複跑確認）。真實 `cf-m0-confirm` → `candidate` 輸出「不通過」，53/90 格 FAIL 與凍結表逐格相符（陰性對照成立）；`negative-control` 以同份為 baseline → 「baseline不合格（非全 PASS）」不崩潰；以真實 `cf-M2/M3-confirm` 復算殺死點，`R55_KILL_SIGNATURES` deviations＝[]。結論值集合：通過／不通過／無效／不可判定-待解釋／回Phase1-變異移植／baseline不合格，各有測試。
- 偏差記賬：`make_fixtures.py` 實為 lyrics_fetcher golden 產生器 → 合成夾具改放 `test_h02_gate_fixtures.py`（保守：不混領域）。
- 接縫：Swift `manifest` 在 marks 檔缺失時寫 `files.marks=null`，Python 判為無效（刻意互鎖；兩側需同此理解）。
- 未做（規格外，需回 Phase 1 才可加）：manifest 跨份一致性（同一運行的 tree_hash／cdhash 全體一致）目前不檢查。
- `--evidence` 未給時證據不判（`evidence_ok=None`）；正式運行務必帶。

**F2-1 基建（§5.7 (1)(2)(3)(7)(9)(10)；worker 於「剩餘驗收檢查」階段中斷，主線程補驗）**：
- 全部 RED→GREEN（worker 記錄）：(1) `Header.epochMicroseconds`；(2) `BindValue{fixture／literalNil／unknown}`＋`bindSamples`；(3) `CoverFlowUITestTrace.shouldInstall(environment:isInstalled:)`＋`AppModel.live()` DEBUG 分支；(7) 新檔 `CoverFlowEvidence.swift`（ordinal／檔名／manifest／md5）；(9) 新檔 `CoverFlowReportTelemetry.swift`；(10) 新檔 `CoverFlowMarksFormat.swift`＋`UITests/Support/CoverFlowMarks.swift`。
- worker 記錄：單測全量 400 tests，紅燈清單＝T0（只有 EDGE 6 條）。主線程補驗：UITests target `build-for-testing`（閘門配置 `-O`）**TEST BUILD SUCCEEDED**；pbxproj diff 刪 0 行、只多 7 個新檔條目；三個新增 app 側檔首尾 `#if DEBUG`／`#endif`。
- **尚未做的驗收**（下一 session F2 收尾）：Release 構建＋`strings` 對新符號＝0（W11）；`ProductCodeSingleSourceTests` 仍綠的最終確認（本輪未加產品碼，理論上綠）；接線層（`CoverFlowUITests`／`CoverFlowProbe` 的 marks／evidence／telemetry 呼叫）只有編譯通過，**沒有**在真實 UITest 運行中驗過（需使用者在場）。
- 工作樹另出現 `AzathothsWhisper/AzathothsWhisper 2.xcodeproj/`（15:46，iCloud 式重複，未追蹤、未入 checkpoint）→ 下一 session 先確認後刪除。

**Z1 spike（worktree `.claude/worktrees/agent-adda23ce384c3f559`，檔已拷存 `~/Developer/bjork-h02-gate/fix4/spike/CoverFlowZ1SpikeTests.swift`；第 1 輪＝純 Rectangle harness，無 `.drawingGroup()`；中斷於改成與產品同構之前）——已核事實：**
- `NSHostingView` 的 root layer `isGeometryFlipped=true`；層總數 19、深度 7；每張**已具現**卡＝兩層（d=6 帶非 identity transform、d=7 bounds 260×260 identity）；LazyHStack 只具現可見 6 張（AX 讀到 9 張）。
- 卡層 `position=(0,0)`、`anchorPoint=(0,0)`、`bounds=(0,0,260,260)`：**平移全部烘進 `layer.transform`** → U1c 需由 transform 分解還原佈局 midX（TBD）。
- `layer.hitTest` 命中層的 `root.convert(bounds)` 與 AX 外框逐值相符（U1b 配對可行，9/9 率未量）。
- **AX hit-test（`AXUIElementCopyElementAtPosition`）回樹序第一個，不是 z 序**（3/3）→ §5.3 備案「AX hit-test」無效，階梯應跳過此級。
- 初始值路徑（centerID=4 建立）畫面停在 #0 居中而 `hitTest` 於 #0/#1 交疊處命中 **#1**（z 序跟 centerID）→ 缺陷 2 形態在單測 host 內可重現（合成負對照的候選來源）；程式化改 centerID=5 後兩側交疊處皆命中 #5。
- **未做**：`.drawingGroup()` 同構 harness（產品真實形態）、U1b 9/9 配對率、U1c transform 分解、U5（nil 起始首次回寫）、U-DL（displayLink `.common` 在捲動期間的回呼率）。Z1 三項**尚未結案**，不得開場 1。

偏差記賬：`session limit 中斷 → 以 wip/ checkpoint 保存、未合回 feat → 全局 §1 例外允許`。

### 2026-09-18 Phase 2 第二段（清理／F2 收尾驗收／Z1 spike 第 2 輪）

**清理（完成）**：`AzathothsWhisper/AzathothsWhisper 2.xcodeproj/` 與正本 `diff -rq` 逐檔相同、git 未追蹤 → 已刪。spike worktree `agent-adda23ce384c3f559`（分支在 `a1d3407` 之上 0 commit；spike 檔 md5 `41acc267…` 與已拷存副本相同）→ 先把其 pbxproj 改動存為 `fix4/spike/round1-pbxproj.diff`，再 `git worktree remove --force` ＋刪分支。

**環境漂移（重大，已核事實）**：本機 **2026-09-16 升級 macOS 27（26A428）**，Xcode 同步為 **27.0（27A266a）**，SDK 27.0（`softwareupdate --history`、`sw_vers`、`xcodebuild -version`）。§2 的 SDK／OS 基線（Xcode 26.6／macOS 26.6.2）、T0、R5-5 凍結表（`cf-m0-confirm`、M2／M3 殺死簽名、兩格不一致）**全部量於 26.6.2**。F2-1 worker 09-13 記錄的「400 tests 紅燈＝T0」也在升級前。

**F2 收尾驗收（2026-09-18，HEAD `1055ff0`，macOS 27）**：
- W11 輔證 ✓：Release 構建 `BUILD SUCCEEDED`（`fix4/rel-F2/`、`rel-build-F2.log`）；`strings -a` 對 F2-1 新符號 21 個（`CoverFlowEvidence`／`CoverFlowMarksFormat`／`CoverFlowReportTelemetry`／`BindSample`／`BindValue`／`bindSamples`／`epochMicroseconds`／`nowEpochMicroseconds`／`literalNilPayload`／`unknownPayload`／`shouldInstall`／`writeManifest`／`manifestJSON`／`treeHashVariable`／`cdhashVariable`／`directoryVariable`／`ShotWindow`／`PixelSample`／`spanMilliseconds`／`AZW_EVIDENCE_DIR`／`AZW_TREE_HASH`）與既有測試符號 11 個（含 `GateSettleTracker`、`installIfRequested`）**全 0**；陽性對照 `coverflow-center-label` 2／`CoverFlowViewModel` 6／`CoverFlowStrip` 4。≤15 字節短字面量（`epoch-us`、`shot-end` 等）內聯不進 `__cstring`，不作證。主證據源碼結構：5 個 app 側檔首行後 `#if DEBUG`、末行 `#endif`；`AppModel.live()` 新呼叫在既有 `#if DEBUG` 區塊內。
- `ProductCodeSingleSourceTests` ✓（`py-F2-pcss.log`）；Python 判定器 `test_h02_*.py` 全綠（`py-F2.log`）。
- **單測全量 ≠ T0** ✗：400 tests／42 suites，8 issues（`unit-F2.log`／`.xcresult`）＝EDGE 6（args 1,4,5,6,7,8；**集合與 T0 相同**）＋ **RENDERED `centerCoverFacesViewerAndSidesTiltAway` 2 條新紅**（左右距 159.7／187.2、aspect 1.143／1.218）。單獨重跑該 suite ×3（`unit-F2-rendered-x3.log`）**3/3 逐值相同** → 確定性，非 flaky。
  - 與 T0 逐行比對：EDGE(4)–(7) 落點由「請求−3、d≈0.1 貼齊」變為「請求−3、偏 ~17pt」（T0 裡只有 EDGE(8) 有此 17.1pt 形態）；RENDERED 走同一條初始值路徑（其數值與 EDGE(4) 逐值相同），故隨之轉紅；RUNTIME 3/3 仍過（0→8 的 d 由 0.0 變 1.2）。
  - 觀察：`a1d3407→1055ff0` 無產品源碼改動（只有 DEBUG 基建＋`live()` DEBUG 分支；單測 host 下 `shouldInstall` 為 false）。推論（推測）：變化來自 macOS 27 runtime 或 SDK 27 的 SwiftUI 初始捲動／吸附行為；未排除：runtime 與 SDK 何者為因（本機只剩 Xcode 27，無法分離）。
- 受影響條款（待使用者裁決，見 ④ 報告）：W2「其餘紅燈清單＝T0 − EDGE」與 K4「RENDERED 綠」的基準；F3a「七個穩定步驟同凍結表」、C.2 `R55_KILL_SIGNATURES` 的比對基準（N2 禁重跑 R5-5）。
- **歸因對照（已核事實）**：`a1d3407`（R5-5 所用 tree，無 F2 基建）在 macOS 27 上跑同一單測命令（臨時 worktree、獨立 derivedData；`unit-a1d3407-m27.log`／`.xcresult`）：381 tests、**同樣 8 issues**（EDGE 6＋RENDERED 2），RENDERED／EDGE／RUNTIME 幾何行與 `1055ff0` **逐字相同** → 漂移與 F2 基建無關，來自 OS／SDK。

**Z1 spike 第 2 輪（macOS 27；Opus worker；報告 `fix4/spike/Z1-round2-report.md`，spike 檔 `CoverFlowZ1SpikeTests.round2.swift` md5 `9af4c224…`）**——harness 直接用產品 `CoverFlowItem`＋`accessibilityIdentifier`（與 `CoverFlowItemContainer` 同構），120Hz／@2x，視窗 1192×620。主線程抽查：U1b 9 位置逐行、U5 C-delay 各變體、U-DL [3] 與報告相符；AX 效應的對照已控探針（`C-delay400-y` probe=true 不讀 AX 0/3 vs `-ax` probe=true 讀 AX 全貼齊）。
- **U1a 成立**：卡層同一 superlayer、`zPosition` 全 0、`sublayers` 次序單調反映 zIndex；model 與 presentation `hitTest` 交疊區 50/50＋50/50 命中 zIndex 最大者（×2 次，plain 同）。product 每卡 3 層（`CALayer`[transform]→`RBDrawingLayer`→`RBImageQueueLayer`）。
- **U1b 主方法不成立**：卡層無身分載體；同一卡的 CALayer 物件跨位置會更換（9 位置 3 次）。計劃備案「同幀 in-process AX 外框配對」：落定 9/9 位置 G±1 唯一配對、殘差 0.000pt；運動 136/136（×2）；AX 讀取中位 4.3ms、最大 9.9ms——**但有觀察者效應**（見 F-AX）。
- **U1c 成立**（transform 分解：軸邊以齊次 w≈1 判別＋軸邊長還原 scale）：落定 max|Δ理論| 1.0pt（p=8 共同 −1pt 落定偏移，其餘 ≤0.4pt），|d|→0 不退化；運動中與解析法差 ≤0.2pt；model＝presentation transform（272 樣 0 差）。NSScrollView 解析法因 LazyHStack 估計尺寸（DocumentView 1467→1358）偏 108.4pt，不可獨立使用；AX 外框備案偏差上界 |d|<0.05 ≤2.07pt、[0.20,0.29] ≤9.16pt。
- **U5 已答**：nil 起始 21/21 **不回寫 items[0]**、0 途經。B（首次 `onGeometryChange` 回呼內同步設 requested）21/21 貼齊（目標 3/6/7/8）；C（VM 側非同步）：`RunLoop.main.perform` 24/24 落「請求−3」、`Task.yield` 5/24、固定延遲 50–1500ms 0/48 → **H3-a(b) 在 macOS 27 上實證不可行**；D／E（現行初始值路徑）24/24 落請求−3，機制：clip origin＝正確位移 − leading `contentInsets` 466（466/150.8＝3.09 stride，殘差 13.6pt；推測 26.6 時被吸附吃掉、27 不再吸附，未回 26 複量）。
- **U-DL 成立（代理）**：`.common` 四種泵 ×3 全過（中位 8.33ms、最大 ≤20.03ms；手動泵 eventTracking 時回呼在 `NSEventTrackingRunLoopMode`）；`.default` 在 eventTracking 泵 3/3 **n=0**。真實觸控板 live scroll 留 F3b (e)。
- 與第 1 輪不同：具現數＝AX 數（第 1 輪層 6／AX 9）；初始值路徑 centerID=4 停 #1、AX +16.4pt（第 1 輪停 #0）；「畫面停在別張、hitTest 跟 centerID 走」仍在。
- **範圍外新發現**：**F-AX** 一次 in-process AX 讀取使 LazyHStack 多具現一張卡並改變之後程式化跳轉落點（0/48 → 15/15）；讀 CALayer 屬性無此效應。**F-JUMP** 無 AX 客戶端時，產品同款裸賦值跳到未具現目標落鄰卡（nil→6 +41.5pt、nil→7 −41.0pt，各 3/3），`withAnimation` 跳轉貼齊；RUNTIME 單測在 drive 前已讀 AX（推測因此看不到）。另：末卡 #8 運行時落定恆 −1pt；`withAnimation(duration: 0.8)` 1→7 約 330ms 完成（原因未查）。
- 仍 TBD：真實 app 組裝上 B 的表現；真實 live scroll 期間回呼率／model≡presentation／途經形態；XCUITest（out-of-process AX）是否觸發 F-AX；非 AX 的層身分方案。
### v5（thecure 四輪辯論收斂；**2026-09-18 使用者批准執行**，已改寫進 §1／§2／§4／§5／§6／§7／§8／§10／§12 規範章節；辯論全文 `fix4/debate-R8/ask{1..4}.md`＋`out{1..4}.txt`）

勝負：我勝——b′ 不觸發 §5.7（Codex 確認）、N4 邊界只規結果、F-JUMP 納入屬範圍擴大須使用者批准、場 0 三段順序。Codex 勝——H3-a(a)（Strip 新參數）確屬 K3／§5.7 觸發（我原判錯）、J2 失效清單漏項、U1b 口徑、R27 需拆三份基準、事後 AX 標記不足以排除觀察者效應、場 0 應排在 spike 3 之前。

1. **歸因口徑**：非 F2 基建；macOS 27 runtime／Xcode 27 SDK／toolchain 至少一項，**未分離**（本機無舊 Xcode）。
2. **失效清單**（降為「26.6.2 歷史事實」，不得作 27 的比較基準）：`cf-m0-confirm` 每格結果／七個穩定步驟／兩格不一致；`FROZEN_REGISTRATION`（R4-F，由 26.6.2 M0 導出）；`R55_KILL_SIGNATURES` 作為當前偏離基準；T0；`ui-T0`；M2／M3 的舊殺死形態；§4.2「運行時路徑正確」敘述（F-JUMP 是反例）；舊運行時間估計。**不失效**：C.1 180/180、C.2 殺死須含 `C2-STACK`、C0–C6 語義、凍結輸入參數（3pt／色距／settle／hold／300px／build 配置）、M2／M3 源檔與 hash。
3. **T0′＝`a1d3407`@macOS 27**（381 tests、8 issues）。K4／F7／W1／W2／§8 需**統一改寫**（只改 W2 會與 K4「其餘紅燈＝T0」、F7「RENDERED 不回歸」、§8 矛盾）：候選全量單測零 issue；EDGE 7/7、RUNTIME 3/3、RENDERED、K5 與全部新增測試全綠；T0′ 的 8 issues 只作修復前 RED。
4. **場 0（新增場次；需使用者明示批准為 §3 B／N2「不重跑 R5-5」的有限例外；不重判「部分通過」）**：**四棵** tree 在使用者到場前預構建、記 tree hash／CDHash（a1d3407＝M0、M2、M3、`aad6a9b`＋R5-3 四檔重建的 T0 樹）；全程 `test-without-building`、串行、每次驗 Products 身分。到場後：(i) OS 27 的 S2／V5 最小健康 preflight（不計證據輪、不計無效）→ (ii) `cf-m0-27` ×10，首份有效即凍結 **R27 基準**（每步完整簽名集合與允許碼、哪些步驟 ×10 穩定／不穩定及其觀察集合、tree hash、CDHash、OS build、Xcode／SDK、顯示設定、evidence hash）→ 檢查 V5 陽性對照、缺陷 2、**缺陷 3（T4.s2 未穩定抓到 C1／C3／C5 即當場停）**、unknown／PROBE／UNTAGGED（「已知產品碼但偏離舊 F(step)」只列雙欄偏離，不停）→ (iii) M2 ×3、M3 ×3，各自凍結 `R27_KILL_SIGNATURES`（`REQUIRED_KILL_STEPS` 不得依結果改寫；凍結 R27 後若 required 集合已無 baseline PASS，跑變異前就停）→ (iv) `ui-T0′`（鑰匙串 preflight 不計證據；首份有效即凍結為 W10 的 active 比較源）。**停止分支入 §7**：優先序＝preflight 不計 → 首份有效先落盤／hash／凍結再評判 → 首份有效未抓到缺陷即停（禁止以第二份有效重抽）→ 同一 `(tree, run-kind)` 累積兩份無效即停（其他 run-kind 插入不重置）→ 場 0 停止歸類「環境前置未成立／待使用者裁決」。M0 缺陷 2 在 27 不重現 → 場 0 後停，不進場 1。
5. **判定器改造（場 0 前必做）**：`R55_KILL_SIGNATURES` 唯讀歷史；新增 R27 profile（M0 每步登記／允許碼、M2／M3 殺死簽名、ui-T0′ 三份分開）；`_signature_deviations`（`h02_gate_rules.py:490`）改讀 active profile；報告雙列 `active_profile_deviation` 與 `historical_R55_deviation`，只有 active 參與 C.2 結論。
6. **F3a**：`1055ff0`＋儀器 OFF ×3 對已凍結的 R27（同 OS 對照）。F6 的 M0 OFF T1 ×10 **留在場 1**（提前會把基線重建與新基建校準混在一起）。
7. **Z1 結論定案**：U1a **成立**；U1c **成立**（sampler 預設讀 presentation layer，至 F3b 實證真實 live scroll 後才可降為 model）；U-DL **代理成立**（F3b (e) 實證）；U5 **已答**；U1b **原方案不成立、無 AX 新方案待 spike 3**。P_trans 改為同幀層判定（G＝分解後佈局 midX 最近視口中心者的層；top＝sibling order／`hitTest`；判 `top === G`）——**不需卡片語義身分**；絕對 `Txx` 只作非裁決診斷，**不得由 z 頂層推導**（會循環）；跨幀追蹤證不出唯一就刪除絕對序位輸出。
8. **無 AX 身分來源**（spike 3 排序）：① `CoverFlowView` 內容閉包內 DEBUG-only 被動 `NSViewRepresentable` marker，Coordinator 以 `persistentID` 註冊弱引用、逐幀讀其 window frame 與層配對（身分來自產品資料流；須做 ON／OFF 觀察者效應驗證）；② 純色 contents 指紋；③ 事後 AX 單幀標記——**只限落定快照**，且 AX 前後完整層投影（`ObjectIdentifier`、ancestry、class、bounds、position、anchorPoint、transform、zPosition）逐值不變才可追溯貼標籤，**不得宣稱排除觀察者效應**、不得用於跨幀或後續行為證據。皆不成立 → 該 host 測試降為「有一張卡置中」，缺口明記，並同步改掉 §5.6 裡「sampler 核對幾何中心序位 vs VM centerID 序位」的措辭。
9. **H3 選枝**：§4.4 正式寫入 **b′＝Strip 介面不動，由呼叫方內容閉包（`CoverFlowView`）的首次 `onGeometryChange` 回呼內同步灌入 requested**，升第一順位（U5 B 21/21 即此形態，spike 檔第 184 行探針在內容閉包內）；VM 側非同步族（`RunLoop.perform`／`Task.yield`／固定延遲）**實證否決**；H3-a(a)（Strip 新參數）降第二順位、仍須 K3 spike＋回 Phase 1。守衛＝MainActor 上原子消耗的 `(viewEpoch, generation, requested)`，先消耗再寫 binding；禁用每卡 `@State Bool` 與 VM 永久 Bool。**兩個接縫（spike 3 必驗）**：(a) 現行 binding setter 只交付 `id`、無 generation provenance（`CoverFlowView.swift:35`）→ 要麼證明 setter 閉包能捕獲建立時的 `(viewEpoch, generation)` 且延遲回呼確實回到原閉包，要麼把契約改成「active-generation 時間窗＋live-scroll 取消」，不得聲稱能比對回呼自身的 generation；(b) 必須分離 `commandedID` 與傳給 Strip 的 `scrollID`——切 tab 重建時 VM 仍持有 `centerID`，Strip 初次 getter 讀到非 nil，b′ 就沒有消除初始值路徑；b′ 回呼須先原子 `armed → applying` 再寫 `scrollID=requested`。以**單參數** `onGeometryChange`（deployment target 14）編譯，不用 15+ 雙參數版；macOS 14 運行時語義**無 14 機器可證**，明記為未證。
10. **範圍（兩個獨立問題，須使用者明示批准；未批准前只登記 U12＝F-AX、U13＝F-JUMP）**：(甲) 是否把「無 AX 下所有產品可達的程式化長跳都須準確置中」納入 H-02（H3 的 auto 命令含 trackChanged／載入完成／重建，子集合≈全集）；(乙) 若只有可見動畫能修，是否同時擴大 H-04。新條款只規**結果**（無 AX 下 requested 卡置中、|Δ| ≤ C1 的 3pt）；可見平滑過渡屬 N4，須另批；「非可見」（零時長／`disablesAnimations`）須由 presentation layer 時序證明無中間位置幀，不能只看 API 名。C.6 明定無 XCTest runner、無 Accessibility Inspector、sampler 絕不讀 AX。
11. **順序**（Codex 末輪修正）：v5 批准 → 判定器 R27 profile 改造＋四棵樹預構建 → **場 0（下一次使用者在場）** → 場 0 全過才做完整 spike 3（身分方案＋b′ 六項＋動畫三分）→ sampler (8)＋報告腳本 (6) → F3a → 場 1 其餘 → F7。使用者短期不能到場時，spike 3 可「機會性先做」，但不是邏輯依賴。
12. **最易失敗的一步**（Codex，含理由）：場 0 的 `cf-m0-27 ×10`——同一 tree 在 27 上單測已確定性改變，且 XCUITest 的 out-of-process AX 在 F-AX 下是否改變 LazyHStack 行為仍未驗證。
13. **R27 staging → 原子啟用**（末輪補，P0）：場 0 全程只寫 `staging_R27`，此期間 `_signature_deviations` 不得以建立中的 R27 自比；M0／M2／M3／ui-T0′ **四者皆有效且未觸發停止條件**後，才以一份含四者 hash 的 manifest **原子切換** `active_profile=R27`；中途停止保留 staging 證據但不啟用、候選禁止開始；R55 永遠只作 historical 列。否則只是把「硬讀單一期望表」從 R55 換成一份可能半成品的表。
14. **P1 條款（範圍甲批准後必須同時接入，否則不成立）**：條款文字＝「無 AX 客戶端時，H3 產生的程式化居中（含 `trackChanged`／載入完成／重建的遠距目標）必須把 requested 卡置於視口中心」；**Δ 定義＝U1c 還原的變換前 layout midX − viewport midX，只沿用 C1 的 3pt 閾值**（現行 C1 讀的是 AX 變換後外框 `CoverFlowGateLogic.swift:386`，訊號不同，不可混寫）。正式 RED 的位置＝**場 0 全過 → spike 3 建立並驗證無 AX 身分與 Δ 量測 → 在未改 H3 產品行為的基線上凍結 RED → 動畫四分法 → 必要時問 H-04 → F7 轉綠**（不得放在場 0 前或塞進場 0）。RED 要求：全程到 verdict 不讀 AX；20 張或等價大專輯；覆蓋未具現遠距目標、兩個方向與末端；斷言 requested 身分且 |Δlayout| ≤ 3pt；以 VM 測試證明 `trackChanged`（`CoverFlowViewModel.swift:140`）／載入完成（同檔 `:215`）／重建都匯入同一受驗 command pipeline；凍結測試名、失敗輸出與基線 hash；明列為 F7 先紅後綠並成為 W1／W2 必要項；失敗必落 §7「不通過」。第 2 輪 U5x 只作發現證據，不得充當正式 RED（9 張簡化 harness、最後仍讀 AX）。
15. **動畫四分法**（取代三分）：裸賦值／`Transaction.disablesAnimations=true`／零時長 animation／可見 animation，四者以相同無 AX 條件、相同目標集合、presentation layer 時序判定「有無中間位置幀」；API 名稱不作證據。只有四者都測完且僅可見動畫可行時，才停在 F7 前問使用者是否擴大 H-04（範圍乙**現在不問**）。
16. **spike 2 worktree 處置**：已封存 `round2-pbxproj.diff`、`round2-worktree-state.txt`（base HEAD `1055ff0`、spike 檔 sha256 `f2b96f66…` 兩處一致）、`xcresult-round2/`（11 份 xcresult＋run/build log，4.0M）→ 待使用者同意後刪除 worktree 與其中的 iCloud 重複 xcodeproj；spike 3 另建新 worktree。DerivedData 可重建，無保留價值。

## 14. 附錄：評審辯論記錄

### R1（2026-09-13）：Codex gpt-5.6-sol high（12 條）＋ Opus 5 四視角（TV＝test-validity 15 條、HF＝harness-fidelity 14 條、SS＝scope-simplicity 13 條、SM＝swiftui-mechanism 11 條）

Codex 結論：不核准 v1（2 P0）。逐條處置（採納＝依建議改；修改＝採其事實、換落點；駁回＝附理由，回餵 R2）：

| ID | 級 | 摘要 | 處置 | 落點／理由 |
|---|---|---|---|---|
| CX1／TV F-04 | P0 | §7 結論程序不窮盡、「帶保留通過」不可達、編譯不相容兩處定性不一 | 採納 | §7 重寫為互斥真值表；「帶保留」改為「不可判定／待使用者裁決」 |
| CX2／HF-4／TV F-08 | P0 | P_trans 無步驟邊界（鍵盤不進 trace）、無覆蓋率規則、端點單鄰張未定義 | 採納 | §5.4 marks 檔＋段有效性＋NA 規則 |
| CX3／TV F-06／HF-5／SS-08 | P1 | 觀察者效應量法不可比（OFF 無幀）、audit 數 40 誤 | 採納 | §5.3 (c) 結果面量法；(d) 12 次 |
| CX4 | P1 | 實體負對照 1/5 太弱；F1≠P_trans 字面同一；需儀器 OFF 實體輪 | 採納 | §5.4 3/5＋對齊規則；§5.6 R-off／R-on 三輪 |
| CX5／TV F-09／TV F-10／SS-03／HF-12 | P1 | D2 分群不標定病灶；SHIFT runner 側不可行；§5.5 與 F6 OFF/ON 矛盾；bindIndices 混 nil 與未知 ID | 採納 | §5.5 重寫：型態標定、唯一公式、SHIFT 移 sampler hold 段、分型解析 |
| CX6／SM F3／SM F4／SM F10／SS-10 | P1 | H2-e 同屬回呼→狀態、失惰性；M1 不能推 H2-b；`.visualEffect` 去留未定 | 修改 | 刪 H2-e（N7）；F4 以 S-b／S-off 兩個 scratch 變異實測選枝；K1 通用否決；S-b 保 `.visualEffect`，S-off 需重驗 RENDERED |
| CX7／SM F2／SM F1 | P1／P0 | H3-a `.task` 一 turn 是時序賭注；nil 起始首次回寫會被判接管；K5 無會紅的測試 | 採納 | §4.4 H3 狀態機＋觸發條件；K5 先紅測試；VM 必改；三個落點 (b)(a)(H3-b) |
| CX8 | P1 | 首份／熔斷非 R6 原文；未解釋偏離不得帶保留通過 | 採納 | §5 通用定義標「操作護欄需使用者批准」；未解釋→不可判定 |
| CX9 | P1 | §5.7 六項不能整包核准；(4) 改變 C.1 | 採納 | §5.7 逐項等價定義；(4) 依 F6 checkpoint |
| CX10 | P1 | F5 引用尚不存在的 M2_K；F9 分支 | 採納 | F5 改 M1diag（見 SM F6）；F9 三支 |
| CX11 | P1 | 手滑程序非固定次數、無有效手勢定義、P5/P6/P7/P8 未定、錄影 TBD | 採納 | §5.6 重寫；`screencapture -v` 已核 |
| CX12／HF-3 | P2／P0 | trace 未持久化、無 manifest | 採納 | §5.7 (7) |
| TV F-01 | P0 | 無效運行不計數＝跑到綠為止出口；建議候選 PROBE 預設＝不通過 | **駁回後半、採納前半** | R6 C.1 原文「PROBE＝無效，不得當產品失敗」為使用者既裁定，不得改判不通過；改以「同 K 連續 2 份無效即停手上報」＋報告標明 R5-5 PROBE 基線＝0 堵出口 |
| TV F-02／SM F9／HF-11 | P0／P2 | 熔斷可被簽名輪換規避；無候選總數上限；W8／W9 無熔斷坐標 | 採納 | §5 護欄 (b)(c) |
| TV F-03 | P1 | 首份規則只綁 C.1 | 採納 | 通用定義 |
| TV F-05／HF-6／SS-02／SS-07／SM F8 | P1／P0 | Z1 無時間對齊、含兩格不一致必假紅、F3 失敗出口指錯 | 採納 | §5.3 (b) 重寫（shot marks、恆定→100%、不恆定→Z1-AMBIGUOUS、七穩定步驟）；出口指 §10 R2 |
| TV F-07／HF-8 | P1 | δ 由紅綠校準＝擬合；無上界 | 採納 | δ＝0.35 幾何預登記、不由結果調 |
| TV F-11／HF-12 | P1／P2 | 實體輪 ID 映射退化 | 採納 | §5.7 (8) 序位映射；runner bindIndices 不參與實體判讀 |
| TV F-12 | P1 | 殺死可由 C4 新碼構成 | 採納 | §5.2 殺死含 C2 |
| TV F-13 | P2 | model vs presentation layer；同源恆真 | 採納 | §5.3 presentation layer；P_trans 讀渲染側 |
| TV F-14 | P2 | trans 不含 T3／T4 | 採納 | trans＝四測試 ×10 |
| TV F-15 | P2 | 人工不可感知 1–2 幀 glitch | 採納 | 錄影逐幀審閱；fps 不足時只證實不否證 |
| HF-1／SS-01 | P0 | 儀器寫同一 trace 廢掉 `readUntilQuiet`、notes 暴漲 | 採納 | 獨立 sampler 檔 |
| HF-2 | P0 | 同源說法錯（d 是變換前）；U1 未拆身分／幾何 | 採納 | U1a／b／c；§5.3 記變換前 midX |
| HF-7 | P1 | run loop 模式、宿主、自證斷言 | 採納 | §5.3 `.common`＋(e) |
| HF-9 | P1 | 「OFF 差異＝零」引用 ON 輪 | 採納 | F3a OFF 對照 |
| HF-10 | P1 | 候選改 VM 使殺死點消失被誤判不通過 | 採納 | §5.2 第四分支 |
| HF-13 | P2 | CLI 直啟改變 TCC 責任行程 | 修改 | `open --env` 已核實存在，改用之；不另做啟動路徑等價 preflight |
| HF-14 | P2 | 非 fixture 安裝與 unitTestHost 互斥 | 採納 | §5.7 (3) |
| SS-04 | P1 | W10／W1／V2 無任務 | 採納 | F9b、W14 |
| SS-05 | P1 | 在場場次無表、F4／F5 重複 | 採納 | §6 場次表；合併運行 |
| SS-06 | P1 | 「產品碼」雙義 | 採納 | 用語註 |
| SS-09 | P1 | Z1 退備案後「同一訊號」失效未反映 | 採納 | §5.4 步驟 3 (i)；§7 第 3 條 |
| SS-11／SM F11 | P2 | D「收官」被推遲；§5.3 引用掛空；ACCEPTANCE 仍 ⬜ | 修改 | N3／§3 D 註：收官已完成；ACCEPTANCE 屬基線變更**問使用者**（業務決定，不代決） |
| SS-12 | P2 | 影響面漏 facade 與掃描清單；C7 勿進 Swift | 採納 | §5.7 (5)、§9 |
| SS-13 | P2 | U10／U11 | 採納 | §12 |
| SM F5 | P1 | C.1 把量測成因未排除的兩格當必消症狀 | 採納 | §5.1 量測成因預登記 |
| SM F6 | P1 | M2 真機形態是佈局破壞，不宜作過渡態實體負對照 | 採納 | §5.4 用 M0 或 M1diag |
| SM F7 | P2 | `onGeometryChange` 重載版本差；displayLink 已可結案 | 採納 | §2、§4.4 |

- Codex 最擔心（R1）：P_trans「零觸發」因無法分段／缺幀未判無效而假綠，再被不完整的 §7 包裝成通過 → §5.4 段有效性＋marks＋§7 真值表。
- Opus 最擔心：儀器鏈可行性未下探（讀得到什麼、何時讀得到、是否算 d 的那份數）；實體 live scroll 期間取樣器靜音的假綠 → U1a／b／c＋`.common`＋(e) 自證；Z1 spike 一出結論即上報。
- 我方輸在哪：v1 把「同一訊號」建立在未驗證的渲染樹前提上、把 P_trans 的分段與覆蓋當作實作細節、以 M0 全域分群校準 D2 卻無標定、H2-e 換了粒度重演回呼狀態路線、§7 只檢 W6–W9。

### R2（2026-09-13）：Codex gpt-5.6-sol high 複審 v2（10 條：3 P0／7 P1；M1–M6 回餵結果：M2、M4 接受；M1、M5 部分接受；M3 接受＋補身分護欄；M6 checkpoint 接受、標定與公式不接受）

| ID | 級 | 摘要 | 處置 | 落點 |
|---|---|---|---|---|
| R2-01 | P0 | 邊界仍不互斥窮盡：C.6 無有效性定義；trans 段不可判定未入 §7 第 3 類；手勢額度耗盡無終點；W1／W3／W12／W14 單獨失敗無歸類 | 採納 | §5 `physical_valid`；§7 每個 W 加「不成立時歸類」欄；第 2／3 條補齊 |
| R2-02 | P0 | 段覆蓋率只看整段 → 運動期無幀、hold 補足仍「有效」＝假零觸發；無最大間隙、無可評幀下限 | 採納 | §5.4 段有效性拆 pre-settle／hold，間隙 ≤ 40 ms，可評幀 ≥ max(5, 30%)；§5.3 (e) 同步 |
| R2-03 | P0 | 實體輪無 runner marks；P7–P9 無邊界；時鐘未定 | 採納 | §5.4 app 內 marks（launch／view-appear／center-change／settle）＋逐路徑分段規則＋manifest |
| R2-04 | P1 | δ 單位混用 stride 與 itemWidth，角度算錯 | 採納 | §2 單位事實列；§5.4 d 以 itemWidth 歸一化，δ＝0.20 itemWidth（0.345 stride），角度重算，單測釘單位 |
| R2-05 | P1 | 病灶可落在 `A→nil→B`；型態標定非真值；同批資料構造性驗證 | 採納 | §5.5 (i) 只宣稱覆蓋兩形態；長停形態由 (ii) 幾何停滯／回拉判；ON 輪作 (i) 的獨立驗證 |
| R2-06 | P1 | N_nil 公式在 L 為空／ms 取整時非唯一 | 採納 | §5.5 微秒域 `N_us = L_us + ⌈(P_us−L_us)/2⌉`，`L_us < N_us ≤ P_us`，\|L\| ≥ 1 |
| R2-07 | P1 | H3 狀態機缺 origin、原子進入、失敗出口、使用者取消；四組可證偽序列 | 採納 | §4.4 狀態機重寫（origin／armed／T_apply／willStartLiveScroll 取消／T_late）；K5 五組測試 |
| R2-08 | P1 | F4 選枝只否決「停舊值」，與 K1「滯後 ≤ 1 幀」矛盾 | 採納 | §4.4 否決條件 (α)(β)(γ) |
| R2-09 | P1 | 3/5 不能推 p ≥ 0.6，`0.4^10` 宣稱不成立 | 採納 | §5.4 刪統計宣稱，3/5 明訂為工程資格門檻 |
| R2-10 | P1 | `open --env` 只進新 process；既有實例會被喚醒；header 不含 CDHash | 採納 | §5.6 終止既有實例→實例數 0→啟動→核對 exe 路徑／CDHash／tree hash |

- Codex R2 最終裁決原文：「M2、M4 可接受；M1、M5 是部分接受；M3 的 LaunchServices 理由接受但程序需補身份護欄；M6 的 checkpoint 接受，但其型態標定與 N_nil 安全性結論不接受。」以上不接受處已全部按其建議改寫。

### R3（2026-09-13）：Codex gpt-5.6-sol high 整體確認 v3——「有異議」，4 條殘餘（3 P0／1 P1），全部採納 → v4

| ID | 級 | 摘要 | 處置 | 落點 |
|---|---|---|---|---|
| R3-1 | P0 | `physical_valid` 要求 sampler 與手勢，令 R-off（儀器 OFF）與 P7–P9（無手勢）原理上不可通過 | 採納 | §5 拆 `physical_valid_off`／`_on`；動作有效依路徑型別分型 |
| R3-2 | P0 | §7 按序取第一類使「重做額度耗盡 → 第 3 類」被第 2 類遮蔽 | 採納 | §7 第 2 類限定「仍有重做額度」 |
| R3-3 | P0 | 段有效只要求「至少一側可讀」→ 單側全程不可讀仍零觸發（假綠） | 採納 | §5.4 (c) 逐側可評覆蓋，僅端點／全程無交疊側豁免 |
| R3-4 | P1 | §11 `--delta 0.35` 與 δ＝0.20 itemWidth 漂移；§5.5「可並存」與 §5.7「擇一」矛盾 | 採納 | §11 `--delta-itemwidth 0.20`；§5.7 (4) 改「可並存」 |

- R3 三問：(1) 有致命矛盾（上列，已改）；(2) 投入順序與 R6 D 一致、妥當；(3) 最易失敗＝F2 Z1 spike（從 `.drawingGroup()` presentation tree 穩定取卡片身分、變換前 midX、真實 topmost）。
- Codex 最擔心（R3）：單側不可讀仍讓整段有效的安靜假綠 → R3-3 已堵。

### R4（2026-09-13）：Codex gpt-5.6-sol high 窄範圍確認 v4——三處（R3-2／R3-3／R3-4）與 §14 R3 表「無異議」；R3-1 措辭殘餘一處

| ID | 級 | 摘要 | 處置 | 落點 |
|---|---|---|---|---|
| R4-1 | P1 | `physical_valid_on` 繼承 `_off` 全部條件（含 sampler OFF）→ 字面上同時要求 OFF 與 ON；§5.6 啟動命令每次都注入 sampler 路徑 → R-off 實際非 OFF | 採納（按其建議） | §5 改三層 `physical_valid_base／_off／_on`；§5.6 分輪列啟動環境與對應 predicate；§11 分兩條命令 |

- 定稿說明：R4 唯一殘餘為措辭矛盾，修法即 Codex 給出的定義，未再開第五輪確認；辯論全文存 `~/Developer/bjork-h02-gate/debate-R7-fix4/`。
- 歷輪勝負：R1 我方駁回 1 條（Opus TV F-01 後半，理由＝使用者既裁定 C.1 原文）、修改 4 條，其餘採納；R2／R3／R4 Codex 全勝（全部採納）。我方在本輪辯論中沒有一條純靠論證勝出——所有駁回都是引用使用者既裁定。

### 2026-09-18 Phase 2 第三段（v5 前置：判定器 R27 profile、四棵樹預構建；三輪 Opus 5 對抗覆核）

- **形狀**：兩條獨立鏈（判定器 Python／四棵樹預構建）並行，各由 Sonnet 5 實作、Opus 5 對抗覆核；三輪後改由主線程收尾（熔斷紀律：「記載與事實不符」連續三輪出現）。覆核判決全文 `tool-results/b6gd836ti.txt`（第 1 輪）、`b8fghp99u.txt`（第 2 輪）、workflow `wf_7bea0175-556` journal（第 3 輪）。
- **判定器（commit 9056b8c → 17611aa → 0460cfb → 本段收尾）**：R27 profile 模組 `h02_gate_r27_profile.py`；staging→原子啟用（含四份原文、`component_hashes`、`staging_file_hashes`，m0 須登記全部 9 步，重複啟用預設拒絕，空 version 拒絕）；C.2 無 active profile 一律「無效」且優先於 3／4 類；雙列 active／historical R55 偏離；R4-F 甲案；`--profile-dir`＋`--run-env-fingerprint` 接到 v3／verdict／negative-control；環境指紋 fail-closed；溯源只印不比。**主線程收尾兩條**：(a) 顯式給了卻找不到 active/profile.json 的 `--profile-dir` → exit 2（第 3 輪發現 v3／verdict 靜默降級使結論由不可判定翻成通過；只有「不給」才讀預設路徑、缺檔＝無 profile）；(b) `display` 欄（只溯源不比對，見 §10 R13）。測試 144 → 181 → 204 → 223 → **234**，全綠。更正：commit `0460cfb` 訊息寫的「204→223 only 增不減」不確——測試 id 實為 **+20／−1**（`test_profile_only_is_unknown` 依 must_fix 改名為 `_is_unmeasured` 並反轉斷言，合法語義改名）。新測試檔 `test_h02_gate_profile_dir.py`（`test_h02_gate_candidate.py` 超 800 行而拆出）。
- **四棵樹（`~/Developer/bjork-h02-gate/fix4/trees/PREBUILD.md`）**：M0＝`a1d3407`、M2／M3＝只換 Strip（md5 `57da040c…`／`48687466…` 先驗後用，`diff -rq` 證明只差 Strip）、ui-T0′＝`aad6a9b`＋R5-3 四檔（**以歷史 ui-T0 同配置重建：不帶閘門參數，預設 Debug**——第 1 輪誤用 `-O`，被覆核比對歷史 log 第 2 行的真實 invocation 抓到）。四棵樹 app／runner 共 8 個 CDHash 互異並已入 manifest。LaunchServices：`lsregister -dump | grep -c bjork-h02-gate`＝0（主線程實測，含清掉 3 條 Release 版殘留）。場 0 命令草稿已修：(i) preflight 補 `TEST_RUNNER_AZW_EXPECTED_APP_DIR`（M0 樹 `CoverFlowUITests.swift:136` 的 `!expected.isEmpty` 守衛，缺它必撞 `PROBE-WRONG-BINARY`）、既有 UITests 選擇器 17 條含 `BatchLiveUITests`、判定器一律以絕對路徑呼叫 repo 現行版、`RUN_ENV` 環境指紋、`evidence_hash()` 路徑無關且缺檔即失敗。
- **場 0 前仍缺**：R27 staging 產生器與 `profile stage／activate` CLI（F2b 已追加）；`evidence_hash` 的定位（判定器補欄位，或只入 manifest）待定。
