# G1 對比 4 條固有超時：量測與處置（計劃 v0.3，/thecure 收斂）

## 0. 複述
- 目標＝`LyricsFXContrastTests` 4 條在 120 s 上限下必超時的問題，量清楚時間花在哪，比較「加速」與「專屬時限」兩案，收斂成一個結論交使用者拍板。
- 完成標準＝拍板的方案實作後，全量單元在既定上限（`-default-test-execution-time-allowance 120`）下這 4 條全部**跑完並通過**；涵蓋（935 組配對 × 英／日 × 5 種效果）與門檻（5 百分位 ≥ 4.5、`inkDifference` 48、內縮 1 像素）完全不變。
- 不做＝刪測試、降門檻、減涵蓋、抽樣、放寬任何斷言；改 app 程式。

## 1. 使用者決定（既定前提，不重議）
- 任何方案都不得刪測試、不得降門檻、不得減涵蓋（2026-11-01 開工口令）。
- 兩案比較後經 /thecure 收斂成一個結論交使用者拍板（同上）。

## 2. 事實（2026-11-01，已核）
- F1 **超時的是哪 4 條**（xcresult：`e54a0515/scratchpad/g1-1013.xcresult`、`full-1520.xcresult`）：`mainTextStaysReadableOnEveryReachableBackdrop`、`japaneseMainTextStaysReadableOnEveryReachableBackdrop`、`japaneseMainTextStaysReadableWithEffectsThatTouchTheText(fx:)`、`mainTextStaysReadableWithEffectsThatTouchTheText(fx:)`，各在 2 分鐘失敗。另外 5 條（`everyPlayablePairStaysReadable` 0.15 s、`batchThreeNever…` 0.02 s、`everyBannedPair…` 6 s、`crimsonVelvet…` 4 s、`strongVignette…` 21 s）通過。
- F2 **參數化的兩條只跑了第一個參數就被砍**：兩份 xcresult 的 Arguments 都只有 `"glow"`（Failed，2 分），`neonstroke`、`rgbsplit`、`misreg`、`reflect` **根本沒有執行**。→ 自 e734671（2026-10-22）起，每次 120 s 上限的全量，這 8 個參數組合（英文 4、日文 4）都沒有驗到；包括 B2 批 5（2026-11-01）新增配對在這些效果下的對比。上次全部跑完是 10-29 的 600 s 上限量測（全綠，⑧ 增補附錄 F）。
- F3 **配對數**：`reachablePairs` 935 組、回退（`playablePairs` 不在 reachable 內）0 組；涵蓋 73 種配色、55 種背景、134 個 profile（scratchpad `g1count/`：照抄測試的篩選邏輯、編入 app 原始碼唯讀計數，不繪製）。→ 4 條共 12 個參數案例 × 935 組 × 每組 4 張圖。
- F4 **時間花在哪**（scratchpad `g1time/`：照抄測試的 `render`／`rgba`／`core`，抽 41 組，`swiftc -Onone`＝測試 target 的 Debug 最佳化等級）：每組 218.5 ms ＝ 4 張離屏渲染 2.9 ms ＋ 4 次轉 RGBA 3.5 ms ＋ **`core()` 210.4 ms（96 %）** ＋ 對比計算 1.7 ms。`-O` 編譯下同一流程每組只要 3.8 ms（`core` 0.8 ms）。→ 開工口令推測的「配對數 × 4 張離屏渲染」不是瓶頸；瓶頸是 `core()` 以巢狀閉包（`map`／`filter`／`allSatisfy`／`contains`）逐像素運算，在未最佳化建置下每次呼叫都付閉包與陣列邊界檢查成本。換算：935 組 × 218.5 ms ≈ 204 s，加上建 timeline／排版，與實測每參數約 230 s 吻合。
- F5 **同一算式改寫成索引迴圈**（`UnsafeBufferPointer`，不改判定：任一通道差 > 48 算字形、九格全在字形內才算核心）：`-Onone` 下 `core` 從每次約 209 ms 降到約 10.5 ms（約 20 倍），20 組抽樣輸出**逐位相同**（`g1time/fast-v2.swift`）。只把陣列換成不帶閉包的迴圈、仍用陣列下標時只快 23 %——慢的主要是 Debug 下的陣列存取，不只是閉包。
- F6 **「主字單獨」「什麼都沒有」兩張圖與背景無關**：讀碼，背景只進 `back`／`underText`／`front` 三層（`ComposedStyle.swift:226-228`），這三層在這兩張圖裡都被清空；種子由行文字、行號與 recipe.seed 推出，不含背景（`ComposedStyle.swift:563`）。實測 12 種配色 × 2 種圖、各取兩個不同背景，24 組**逐位相同**。
- F7 **專屬時限可行**（scratchpad `tlprobe/`，Xcode 27.1）：`-default-test-execution-time-allowance 60` 下，Swift Testing `@Test(.timeLimit(.minutes(3)))` 單獨跑 90 s 的測試 → 通過；不加 trait 的對照 → 60 s「Time limit was exceeded」。XCTest 的 `executionTimeAllowance = 180` 同樣可蓋過。
- F8 **超時會讓同行程並行中的其他測試消失**（同一次實驗）：對照組在 60 s 超時的那一刻，同時在跑的 `withTrait3min` 有「started」、沒有結果，xcresult 裡也不存在這條（不算失敗也不算通過）。推測：超時後 runner 被終止重啟，進行中的測試被丟棄。→ 推測全量時 G1 每次超時也可能讓並行中的其他 suite 測試靜默消失（未在本 repo 驗證，TBD）。

## 3. 推論（推測，標明推理鏈）
- 方案 A（加速）只改 `core()` 的寫法：每組 ≈ 2.9＋3.5＋10.5＋1.7 ≈ 19 ms → 每參數 ≈ 935 × 19 ms ≈ 18 s（推估，含排版約 20–25 s），比 120 s 上限有 5 倍左右餘裕；4 條 12 個參數合計約 4–5 分鐘（現在 600 s 上限下約 46 分鐘）。
- 再把 `core` 依（配色, 效果, 歌詞, 時刻）快取（F6）可把 `core` 呼叫從每參數 935 次降到 73 次，推估每參數再降到約 8 s。**條件式不做**：G2 以真實測試宿主跑完後，若最慢案例明顯低於 120 s（目標 ≤ 60 s）就不做；否則才重評（Codex R1-3）。
- 上面的秒數是 CLI（非測試宿主）外推，只支持方向；是否達標**唯一以 G2 的真實 `xcodebuild test` 為準**（Codex R1-Q2）。
- 曲目元件逐批增加：配對數每批成長（批 5 後 935）。A 的餘裕約可容納配對數再增 4–5 倍；B 的時限要隨配對數手動調。

## 4. 兩案比較
| 項目 | A 加速（改寫 `core`） | B 專屬時限（4 條加 `.timeLimit`） |
|---|---|---|
| 改動 | 測試端 1 個函式改寫（判定式不變）＋等價測試 | 4 個 `@Test` 加 trait＋理由註解 |
| 120 s 上限下能否跑完 | 能（推估每參數約 20 s，G2 實測為準） | 能（F7 證實 trait 蓋過預設），但每案例實測約 230 s，時限要設 5–6 分鐘以上 |
| 涵蓋／門檻 | 不變（逐位相同；由等價測試釘住） | 不變 |
| 全量時間 | 4 條約 46 分 → 約 4–5 分 | 不變（約 46 分；全量單元仍約 2 小時） |
| 風險 | 改寫出錯會讓判定悄悄變了 → 等價測試把新舊實作在抽樣配對上逐位比對 | 配對數成長後時限又不夠；超時時並行測試可能消失（F8）的情況延後發生而非消除 |
| 未來成本 | 低 | 每批加元件要重估時限 |

- **結論（/thecure 收斂，附錄 B）：A-only，不加 B。** 理由：F4 顯示瓶頸是測試自身的寫法，不是被測對象的固有成本；A 讓這 4 條繼續受 120 s 回歸警報保護。B 不是關掉上限，而是要把上限提高到 5–6 分鐘以上——防掛住變弱、全量仍慢約 46 分鐘、配對數成長後又要再調（Codex R1-1 修正我原本「B 等於關掉防線」的說法）。A＋B 也不採：A 若達標，B 沒有收益、只會掩蓋未來退化；A 若不達標，表示 A 未完成，回頭再議。

## 5. 設計（A；拍板後才實作）
- `LyricsFXContrastTests.core(text:empty:width:height:)` 改為 `UnsafeBufferPointer` 索引迴圈（F5 的寫法），回傳型別、順序、語義不變。
- **參考實作（characterization oracle）**：現有閉包版改名 `referenceCore` 留在測試檔，只供等價測試使用（註明「判定式的可讀版本；改 `core` 時兩者要一起改」）。
- **等價測試 `fastCoreMatchesTheReferenceDefinition`**（Codex R1-2、Q4：選樣寫成可稽核矩陣）：
  - 真實渲染：固定 12 組**分層具名**配對——`reachablePairs` 依背景 `tone` 分三層（亮、暗、無 tone），各層依 id 排序取 4 組，背景與配色先都不重複、該層背景用完才允許重複背景（亮層只有 halftone、sunset 兩種；原句「配色不重複」會讓每層 4 組都是同一個背景，實作時修正）；選出的 12 組 id 寫死在測試裡，日後元件增加不改選樣× 語言 {英, 日} × 效果 {none, glow, neonstroke, rgbsplit, misreg, reflect} 中輪流指派（每組配對各取英日兩種、效果依序輪換，共 24 個輸入，6 種效果各至少 4 次）；新舊版輸出逐位相同。成本估約 24 × 0.22 s ≈ 5–6 s。
  - 合成遮罩（不渲染，直接給 `text`／`empty` 位元組）：①全空 → `[]`；②全滿 5×5 → 內部 3×3 的 9 個索引；③1 像素寬的直線 → `[]`；④3×3 實心 → 中心 1 個；⑤寬或高 < 3（2×5、5×2）→ `[]`；⑥通道差恰為 48（不算）與 49（算）各一。每案預期索引寫死在測試裡，新舊兩版都要等於預期。
- 不動：`minimum`、`percentile`、`inkDifference`、`reachablePairs`、`playablePairs`、所有 `@Test` 的參數與斷言、`render`、`rgba`、`contrast`。

## 6. 任務清單（拍板後；單人主 session 依序）
| # | 任務 | DoD |
|---|---|---|
| G1 | 等價測試先紅 | 先寫等價測試（呼叫尚不存在的 `fastCore` → **編譯紅**，附錄記為「編譯紅」，不是測試判定失敗）＋合成遮罩預期；把舊 `core` 改名 `referenceCore` |
| G2 | 實作 `fastCore` 並切換 | 等價測試綠；`core` 呼叫端改用 `fastCore`；`LyricsFXContrastTests` 以原命令（`-test-timeouts-enabled YES -default-test-execution-time-allowance 120`）單獨跑：**4 個超時方法的 12 個執行案例**（`mainText…OnEveryReachableBackdrop`、`japaneseMainText…OnEveryReachableBackdrop`、兩個參數化方法各 `glow`／`neonstroke`／`rgbsplit`／`misreg`／`reflect`）在 xcresult **具名出現且 passed**，其餘 5 個方法亦 passed；逐案例記耗時。任何新不及格：保存配對、效果、語言、對比值，走 ⑧ 附錄 E 配對級硬禁止程序另案，不加時限、不跳過、不再改 `core` 消音 |
| G3 | 全量單元 | 同命令全量；以 `full-1520.xcresult`（2026-11-01，1,991 個測試案例）的具名清單為基準，識別碼＝suite＋測試名＋參數，輸出「基準有、本次無」差集——**差集必須為空**（新增案例不算缺），總數只作輔助（Codex R1-4、Q5）。限制：基準本身也是 120 s 下的全量、可能曾因超時漏報，所以差集只防「既有案例消失」，G1 的 12 案例仍以 G2 的具名驗證為準；G1 12 案例 passed |
| G4 | 文件 | ACCEPTANCE I-69：**保留**原「G1 4 條超時」事實、日期、原命令與原因；另加處置紀錄（commit、完整命令、xcresult 路徑、12 案例結果與耗時、「產品行為未變、只改測試判定的實作」）。計劃附錄記實測 |

## 7. 測試策略
- 單元：等價測試（含邊界合成案例）。
- 整合：G1 全 suite 在既定上限下跑完。
- E2E：不適用（測試端改動，app 行為不變）。

## 8. 影響面
- 只改 `Tests/LyricsFX/LyricsFXContrastTests.swift`。app target 0 改動；`RecipeGoldenTests` 等不受影響。

## 9. 風險與回退
- **被超時遮住的真不及格會浮現**（F2）：8 個參數案例兩週沒跑過完整版，B2 批 5 的新配對在 neonstroke／rgbsplit／misreg／reflect 下沒驗過。若 G2 出現不及格，那是**新發現**，照 ⑧ 附錄 E 的配對級硬禁止程序另案處理，**不放寬、不跳過**。
- 改寫判定錯誤 → 等價測試擋住；回退＝`core` 指回 `referenceCore`。
- G2 實測若最慢案例仍 > 60 s：先做 F6 快取（條件式後備）並重測；仍超過 120 s → 停下另議，不改用 B 消音。

## 附錄 A 量測程式（scratchpad，不進 repo）
- `g1count/`：計數（`files.txt` 沿用 ⑧ 增補附錄 A 清單＋`AppleGenreConsensus.swift`、`LyricsFXPreviewFixture.swift`；測試端 `ReadabilityAudit`／`PlayableSpace`／`GoldenFixtures` 去掉 `@testable import`）。
- `g1time/`：計時與逐位比對（另編入 `LyricsFXView.swift` 的 `LyricsFXCanvas` 部分、字型以 `CTFontManagerRegisterFontsForURL` 從 `Resources/Fonts` 註冊、`noise.png` 以絕對路徑載入）。量測時機器負載約 6（另一個 session 在跑 YSE 測試），絕對值偏保守，比例（`core` 占 96 %）才是結論依據。
- `tlprobe/`：SwiftPM 小套件，驗 `.timeLimit`／`executionTimeAllowance` 與預設上限的關係。

## 附錄 B /thecure 與 Codex 評審紀錄

### R1（2026-11-01，審 v0.1＋A／B 辯論）
| # | 論點 | 判定 | 處置（v0.2） |
|---|---|---|---|
| 1 | 選 A、不加 B | 方向一致；**Codex 勝**一處：B 不是「關掉上限」，是把上限拉到 5–6 分鐘以上（230 s／案例，3 分鐘也不夠） | §4 結論改寫 |
| 2 | 等價測試能釘住判定 | **Codex 勝**：F5 實測只有英文、`fx: none`，與計劃描述不符；且合成邊界數量寫錯 | §5 改為英日 × 6 效果矩陣＋6 種合成遮罩（含 48／49 邊界） |
| 3 | 不做快取 | 一致；Codex 補「條件式」 | §3：G2 最慢 ≤ 60 s 才關 |
| 4 | 全量以總數驗證 | **Codex 勝**（致命）：F8 下總數可掩蓋缺項 | G2／G3 改具名案例清單、差集為空 |
| 5 | 浮現真不及格走硬禁止 | 一致 | G2 補「保存證據、不消音」 |
| Q2 | CLI 量測外推 | **Codex 勝**：CLI 非測試宿主，秒數不可承諾 | §3 註明以 G2 為準；測試 target 確為 Debug `-Onone`（`project.pbxproj` Debug 設定，雙方核過） |
| Q3 | 更好方案（單檔 `-O`、整個 target `-O`、A＋B） | 一致不採：單檔 `-O` 非標準設定；整個 target `-O` 是大範圍建置政策變更；A＋B 會掩蓋退化 | §4 |
| Q4 | G1 空殼紅燈是人為製造 | **Codex 勝** | G1 改為 oracle 流程（編譯紅） |
| Q4 | ACCEPTANCE 不可抹掉歷史 | **Codex 勝** | G4 保留原事實＋新增處置 |
- Codex 最擔心：全量看似通過、實際有測試因超時重啟根本沒被報告（F8）→ G2／G3 的具名清單驗證是唯一不可省的修訂。

### 整體確認（/thecure 第 7 步，2026-11-01）
- 異議 3 條，全採納：①「每 78 組取一」不保證跨亮暗 → 改分層具名選樣；②基準 xcresult 也可能漏報 → 差集只防既有案例消失、識別碼含參數，G1 仍以 G2 具名驗證；③G1 是編譯紅要明記。
- 投入順序 G1→G4：Codex 判妥當。
- 最容易失敗的一步：**G2**——真實測試宿主的速度可能不符 CLI 外推，且會首次跑到兩週沒執行的 8 個參數案例，可能浮現真不及格（處置見 §9）。

## 附錄 C 實作記錄（2026-11-02，`wip/lyrics-leftovers-2026-11`）
- 選樣（scratchpad `g1count/` 依規則算出、寫死）：亮 halftone＋britRed、sunset＋chalk、halftone＋cream60、halftone＋mancSky；暗 ampGlow＋acid、bluehour＋bruise、bokeh＋dusk、genAmbBluehour＋genAmbDeep；無 ash＋ampRed、checker＋gigRed、crimsonFog＋ashGrey、embers＋bloodBlack。
- `core` 改名 `referenceCore`（只供對照）；新增 `fastCore`；`contrast` 改用 `fastCore`。新增 `fastCoreMatchesTheReferenceOnRenderedLines`（24 輸入）、`fastAndReferenceCoreAgreeOnSyntheticMasks`（8 種合成遮罩，含 48／49 邊界）。
- **紅燈**（G1）：`fastCore` 暫時回傳空陣列 → 渲染等價 24 個輸入全紅、合成遮罩 `fastCore` 3 個非空案例紅、`referenceCore` 全部符合預期。過程中一處測試資料寫錯已改正（非放寬）：合成遮罩底色 10 加 255 以 `&+` 溢位繞回 9，「全滿」變成差 1；底色改 0。
- **綠燈**（G2，`-default-test-execution-time-allowance 120`）：`LyricsFXContrastTests` 11 條全綠（583.8 s）。4 個原超時方法的 **12 個具名案例全部 passed**：單條 46.7／47.8 s；兩個參數化方法各 5 個效果 46.3–47.9 s。最慢 47.9 s ≤ 60 s → F6 快取不做（§3 條件）。實測約 4.9 倍（CLI 外推約 10 倍偏樂觀，以實測為準），離 120 s 約 2.5 倍餘裕。F2 那 8 個兩週沒跑的效果案例全數通過，未浮現新的不及格配對。
- **全量基線（改動前，同日 00:02–01:27，`full-1102-0002.xcresult`）**：2,006 條，1,977 綠、25 略過、4 紅＝本計劃要修的 4 條超時；coverage_gate exit 0（96.5%，豁免 489／490）。
- **simcodex**（1 輪即符合提前結束：codex review --base 3650401「語義保留、等價測試涵蓋改動」；simplify 四角度皆無 P1）。採納一項強化：合成遮罩原本只動綠色通道，補「只有紅色差 49」「只有藍色差 49」兩例（紅藍兩個判斷分支不再只靠渲染輸入）；兩條等價測試綠。遺留 P2：`rgba()` 與其他三個測試檔的 CGContext 樣板重複（跨檔，另案）；`fastCore` 的緩衝長度 guard 與 `referenceCore` 行為不同（輸入一律來自 `rgba()`，不可達）；三層 `withUnsafe` 巢狀可改名去遮蔽。
- **G3 基準調整**：差集基準改用改動前同日全量 `full-1102-0002.xcresult`（2,006 個案例，含 I-68 新測試）而非計劃原寫的 `full-1520`（1,991）——前者是後者的超集且更新，差集更嚴。
