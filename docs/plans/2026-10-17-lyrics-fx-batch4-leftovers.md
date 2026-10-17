# Lyrics FX — 批 4 遺留的三個顯示問題（超寬單字、霓虹描邊隨縮字、Anton 字級）

基線：`main` 93dee59。分支：`wip/lyrics-fx-batch4-leftovers`。上游：T7 修正計劃 `docs/plans/2026-10-14-lyrics-fx-b2-batch4-t7-fixes.md` §2.1、§2.6、§9.4（三項都記為後續／已知限制）；ACCEPTANCE I-45。
使用者 2026-10-17：「先做批 4 留下的三個顯示問題……按 123 順序依次做」，並指示自主執行。

## 0. 複述
依序修三個組合畫法的顯示問題：①比歌詞區還寬的單一長字會水平出框；②霓虹描邊寬是整幀一個常數，不隨縮字（I-45）與逐字型字級變細；③原型把 Anton 放大到 0.15 字級，app 沒跟上。

## 1. 已核事實
- F1 折行：`ComposedStyle.layout` 以詞為單位貪婪折行，寬度上限 `size.width × maxWidthRatio(0.86)`（`ComposedStyle.swift` layout）；一個詞比上限還寬時獨占一列、列寬超過上限；列以畫布中心置中（anchor x＝(W − rowWidth)/2），列寬 > W 就左右出框。I-45 的 `fits` 只看上下（`ComposedStyle.swift` fits），所以縮字不會為了寬度觸發。
- F2 斷詞：`TimedWord.split`（`Services/Lyrics/LyricsTimeline.swift:38-56`）：有空白按詞、無空白而含 CJK 按字、其餘整行一詞。所以 CJK 長句不會出框；出框只發生在「無空白的長串拉丁字」（網址、拉長的 "Aaaaah"、整行無空白）與單純很長的單字。
- F3 描邊：`plan()` 末尾 `frame.stroke = size.height × emRatio × strokeRatio(0.06)`，整幀一個值；`LyricsFXCanvas.fill` 對 `plan.glyphs` 的每個 run 用這個寬描邊，`plan.ghosts` 不描邊。原型 `lyrics-fx-preview.html:516,637`：`ctx.lineWidth = st.em × 0.05／0.06`，`st.em`＝該句的 em（`:312` `em = H × style.size`，含字型的 `S.size`）。→ app 在 sizeScale ≠ 1 或縮字時與原型不一致。
- F4 字級：原型 `composer.js:401`：`Butcherman`、`Anton` 的 `S.size = 0.15`（預設 0.12），`RockSalt` 0.085，`Cenobyte` 的 `S.spacing = 0.2`。app 只做了 Rock Salt（`FontFace.sizeScale`，`LyricsFXCatalog.swift:104`）。
  - **Butcherman 不在 app 的字型目錄**（`grep Butcherman Features App Resources` 0 筆）→ ③ 實際只改 Anton。
  - Anton 在 54 團候選基線中出現在 **28 團**（`band-candidates-baseline.json`：Arch Enemy、Cannibal Corpse、Hatebreed、Slayer、Korn、Linkin Park、Slipknot、Green Day、AC/DC、Guns N' Roses…），另有依曲風抽到 Anton 的歌。
  - Cenobyte 的字距是另一個原型落差，不在使用者給的三項內 → 非目標，記後續。
- F5 既有測試 `B2BatchFourT7FixTests.rockSaltIsDrawnAtThePrototypesSmallerSizeAndOtherFontsAreNot` 斷言 Anton `sizeScale == 1`（當時的範圍決定），本次依使用者新指示改寫；`B2BatchOneTests:72-74` 讀 `FramePlan.stroke`。

## 2. 設計
### 2.1 ① 超寬單字（I-45 擴充；R1 #1、#6、#7、#10 修訂）
1. `fits` 加水平條件（R2 後改回**契約 A**）：**每一列的排版寬 ≤ 折行寬度上限（`W × maxWidthRatio`＝0.86 W）**，左右各留 7% 給外框溢出、散布、旋轉與描邊。
   - 為什麼不用 R1 時的水平包絡（契約 B）：R2 指出貪婪折行在 em 變小時會把詞併成一列、多詞列寬可接近 0.86 W，包絡條件因此**不單調**、而且會誤縮本來放得下的多詞列（0.43 W×1.04＋reachX 很容易超過 0.48 W）。
   - 契約 A 的性質（可證）：多詞列由折行保證 ≤ 上限，所以條件只會因「單一詞寬 > 上限」而失敗；單詞寬隨 em 線性（線性字型嚴格；非線性字型以 `fallbackSizeStep` 0.5 pt 量化，只是**近似單調**，與既有上下判定同一前提），二分搜尋在此前提下有效；搜尋結果不依賴單調性的正確性：回傳的 em 一律是實際跑過 `fits` 且通過的候選（現有 `search` 的 `best` 只在通過時更新），最壞只是比最大可行值略小，不會回傳放不下的 em（R3）；不含超寬詞的句子判定結果與現狀完全相同。
   - 保證範圍照實寫：保證**排版框**在折行寬內；真實墨跡在畫布左右安全區內以測試案例（真實字形＋繪製端仿射變換）佐證，不宣稱任意變換下都保證。
2. 縮到下限 0.5 倍仍有列放不下（水平）→ 在 0.5 倍下，於 `layout` 層把放不下的那個詞**按 extended grapheme cluster（Swift `Character`）**斷到多列（不加連字號、貪婪塞滿），保留同一 `wordIndex`、時間與動畫；**不改 `LyricsTimeline`／`TimedWord.split`**。斷完重跑完整 `fits`（上下＋左右）；仍放不下 → 照 0.5 倍＋斷詞畫，並記一次 OSLog（沿用 `FitLog`，加「斷詞」旗標、列數；不記歌詞）。無可行解時允許上下或左右被切，不改單色、不加省略號、不縮到 0.5 以下（與 I-45 下限政策一致）。
3. 快取：`FitCache` 的值改成 `FitResult(ratio, breaksLongWords)`，存完整決策，命中時直接照決策重排。快取只在記憶體、行程結束即清，不加版本號（R1 #8 駁回）。鍵不另加詞邊界簽名：`TimedLine` 只有一個 init，`words` 恆由 `TimedWord.split(text)` 決定（`LyricsTimeline.swift:21-27`），同 text 必同詞界（R2 #8 駁回，若日後加入外部詞界的 init 必須同步改鍵——寫進程式註解）。量測器以型別區分是既有不變條件：app 只有 `CoreTextMeasurer` 一種、無同型不同設定的實例（寫進註解）。
4. 彈片堆（slam）照舊不處理（I-45 3b）。
5. 仍不保證（照實記錄）：進退場的 transform.dx（飛入飛出）、整屏 shake／thump、淡裝飾。
### 2.2 ② 霓虹描邊隨該句的 em（R1 #2、#3、#4、#5 修訂）
- 需求定為「**每句共用一個描邊寬＝該句實際 em × strokeRatio**」（em 含 sizeScale 與縮字比例；與原型 `st.em × 0.06` 同口徑）。**不宣稱與原型像素等價**：原型的描邊另會隨逐字的 scaleX／Y 縮放（`ctx.scale` 後 `strokeText`），app 在畫布座標描邊、不隨逐字縮放——這是既有差異，本次不動。
- `GlyphDraw` 加 `stroke: CGFloat = 0`，**`shifted` 明確複製 stroke**（否則負片、勒索信的主字經 `shifted` 進 `frame.glyphs` 會悄悄失去描邊）；`draw` 在 neonstroke 時對該句的 base 設 stroke。刪 `FramePlan.stroke`。
- `LyricsFXCanvas.runs(of:)` 分段鍵加 stroke；`fill` 用 run 的 stroke；殘影層呼叫 `fill` 時明確「不描邊」（副本帶著 stroke 欄位也不畫，維持現狀）。
- 「與現狀相同」的主張降為：**固定輸入下 plan 的描邊寬數值與改前基線相同**（未縮、sizeScale＝1：`(H×emRatio×1)×strokeRatio` 與 `H×emRatio×strokeRatio` 浮點相同，測試以改前記下的數值斷言）；不宣稱跨 OS 的像素相同。
- 效能：描邊 run 本來就一律走 `vectorMerged`、不用點陣快取；分段只在相鄰兩句 em 不同時多切一段（每幀最多多幾個 run）。V3 量 neonstroke＋兩句同時可見的配方，並記 run 數。
### 2.3 ③ Anton 字級
- 目錄 Anton 加 `sizeScale: 0.15 / 0.12`（照原型；Rock Salt 的前例）。em 一放大，I-45 縮字會更常觸發，這是預期。
- 會改變 28 團已簽字的 app 畫面（往原型靠，簽字時看的是原型）：ACCEPTANCE 記 ⚠️（附使用者原話與日期），真視窗目視列使用者在場。

## 3. 非目標
- Cenobyte 的字距 0.2（原型有、app 沒跟）：記後續，不動。
- 不改左右散布的檢查、不改直排（app 沒有直排）、不改光暈半徑（原型是固定 18）。
- 不動其他字型的字級。

## 4. 驗收標準
- V1 單元（TDD 先紅後綠）：
  - ① 一句含一個超寬單字（例：40 字元的無空白拉丁串）在 1728×945、900×945 下：縮字後每列排版寬 ≤ 上限，且（佐證）主字形墨跡（真實字形＋繪製端仿射變換）左右上下都在安全區內；超寬到 0.5 倍也放不下的串（例：120 字元）被斷開、墨跡左右在安全區內，且斷開後同一詞的字共用同一 `wordIndex`（進場時間不變）；emoji（含 ZWJ 序列）、組合音標、CJK＋拉丁混合、網址標點不被拆壞（每個 `GlyphDraw.text` 都是完整 grapheme）；斷詞後上下放不下時照 0.5 倍畫、不崩潰。
  - ① 基線回歸：改版前在 main（93dee59）記下一組「字型 × 畫布 × 句子」（不含 Anton，含既有長句與 CJK 句）的 `fittedEmRatio`（Double 位元），改版後逐一相同；`FitCache` 命中與未命中結果相同。
  - ③ 整條資料路徑：指定 Anton 配方，未縮時每個主字 `fontSize == H × 0.15 × personality.size`；觸發縮字時 stroke 以縮後 em 計（R2 #9）。
  - ② `shifted(...).stroke == 原字.stroke`（R2 #3）。
  - ② 縮過的句子與 sizeScale ≠ 1 的句子，每個主字形 `stroke == 該句 em × 0.06`；未縮、sizeScale＝1 的句子 stroke 等於改前記下的數值；殘影（ghosts）不描邊；negative、ransom、misreg、reflect、weep 與 neonstroke 並存時主字都帶描邊；不同描邊寬的字不在同一 run。
  - ③ Anton `sizeScale == 0.15/0.12`；其他字型（除 Rock Salt）仍為 1。
- V2 全量單元綠（skip `overlappingLoadSuspendsPollingUntilLastCompletes()` 完整名稱帶括號）；`no_playback_gate.sh` 0；`coverage_gate.sh` ≥ 80%；Scripts Python 測試 OK。`GlyphRasterFidelityTests` 照舊全綠（門檻不動）。
- V3 每幀（-O 建置、`measure.sh` 同法，密集預覽兩句交替＝同時可見兩句）：①Anton＋最重效果組合（從簽字對照檔取 Slipknot／Linkin Park 實際可抽到的最重組合）；②Anton＋neonstroke（直接指定配方）。另記錄該配方每幀的 glyph run 數。門檻 p50 ≤ 2 ms、p95 ≤ 3 ms；超出停下交使用者。既有 7 份不含 Anton／neonstroke，不重量。
- V4 使用者在場：UI 測試 `LyricsFXUITests`＋`LyricsFlowUITests` 20 條；真視窗目視（Anton 團 2–3 首組合器自抽、超寬單字預覽、霓虹描邊縮字）。自主執行階段做完 V1–V3 即停，V4 等使用者。

## 5. 任務清單（每項帶 DoD）
- T1 ① 先寫測試紅 → 實作綠。DoD：新測試綠、既有 `LongLineFitTests` 全綠、紅燈摘要記 §9。
- T2 ② 同上。DoD：新測試綠、`B2BatchOneTests` 改讀 glyph 的 stroke 仍綠、Fidelity 綠。
- T3 ③ 同上。DoD：測試綠；ACCEPTANCE I-45 擴寫、新增 I-47（Anton 字級 ⚠️）。
- T4 V2＋V3。DoD：數據記 §9。
- T5 /simcodex。DoD：評審紀錄記 §9。
- T6 使用者在場（V4）。

## 6. 測試策略
- 單元：純函式（`fittedEmRatio`、`runs(of:)`）與 `plan()` 輸出。整合：真實 `CoreTextMeasurer`＋字型＋墨跡包絡。E2E：UI 測試＋真視窗目視（使用者在場）。測試字串一律自編。

## 7. 影響面、風險與回退
- 影響面：所有含超寬單字的句子（少見）、所有 neonstroke 配方中縮過字的句子、28 團＋曲風抽到 Anton 的歌（字變大、更常縮字）。
- 風險：Anton 放大後每幀變重（字大、點陣大）→ V3 量；斷詞使網址可讀性下降（只在 0.5 倍仍放不下時）。
- 回退：三項各自獨立，可單獨 revert；都在 wip 分支，未經使用者拍板不合 main。

## 8. 待拍板
- 無（使用者已指示三項都做並自主執行；Anton 改動已簽字畫面，事後以 V4 目視確認）。
- **計劃定稿（2026-10-17）**：Codex 三輪，無 P0／P1 開著。使用者已指示自主執行，不另等計劃審閱。

## 9. 紀錄（實作時回填）
### 9.0 基線（T0，2026-10-17）
- 改版前在 main 93dee59 的程式上記下 126 組（7 字型 × 6 句 × 3 畫布）`fittedEmRatio` 的 Double 位元，其中 39 組本來就縮字；寫進 `B2BatchFourLeftoverTests.baseline`。

### 9.1 T1–T3（TDD）
- 先加介面骨架（`FitReport`、`GlyphDraw.stroke`、`runs(of:stroking:)`，行為不變）→ 新測試 13 條：**11 條斷言紅**（沒縮字、沒斷詞、沒描邊、shifted 掉描邊、Anton＝1…）；2 條先天綠：基線回歸（預期）、grapheme 守門（尚無斷詞時本來就成立，留作回歸防線）。
- 實作後第一次跑：2 處紅。①的測試資料選錯（40 字元整行大寫 Marker 在 0.5 倍仍太寬，實際走到斷詞）→ 改為寬窄視窗各用 24／13 字元；`aShortLineKeepsItsSizeExactly` 的 Anton 窄視窗案例縮字＝Anton 放大的預期結果 → 移出清單，改成正面斷言「會縮、縮完在安全區內」（`aShortAntonLineShrinksInANarrowWindowAndStaysInside`）。之後相關 4 suites 33 條綠。
- 全量 1275 條：**只有 `GlyphRasterFidelityTests` 的 thump（唯一用 Anton 的案例）8 斷言紅**；`no_playback_gate.sh` 0；覆蓋率 96.2%；Python 333 OK。wip checkpoint `404df64`。

### 9.2 thump 紅的鑑別（2026-10-17）
- 超標的只有佔圖比例類門檻（2× over16 0.469% > 0.4%、mean 0.00075 > 0.0007；1× over16 0.792% > 0.75%、over2 2.768% > 2.3%、mean 0.00142 > 0.0013）；邊緣帶外 0、最大差 ≤ 71。
- 鑑別實驗（Codex 提議；同 seed、thump@4.6，只改 Anton sizeScale，跑完以 `git checkout` 還原）：
| sizeScale | 2× 墨跡像素 | 2× 差>16 像素 | 2× 差>16／墨跡 | 1× 差>16／墨跡 |
|---|---|---|---|---|
| 1.0 | 121,244 | 3,769 | 3.11% | 5.44% |
| 1.125 | 153,421 | 6,249 | 4.07% | 6.57% |
| 1.25 | 188,928 | 9,756 | 5.16% | 8.57% |
  - 墨跡 ∝ 面積（1 : 1.27 : 1.56），差>16 卻是 1 : 1.66 : 2.59 → **換算後仍隨字級惡化，不是單純「字大邊多」**。
- 根因（推理，Codex 讀碼核對同意）：`GlyphRasterCache` 以 `GlyphPathCache.Entry` 的尺寸（線性字型＝`UnitGlyphMetrics.referenceSize` 100 pt，`TextMeasuring.swift:7-13`）× displayScale 建點陣，繪製時乘 `fontSize / entry.size`，thump 的整屏 zoom 再乘一次 → 有效字級 > 100 pt 就是放大點陣、邊緣變糊。測試畫布 900×560（em 67 pt）幾乎不觸發；實際視窗高約 945 pt：一般字 em 113 pt（放大約 1.13 倍；使用者 2026-10-17 目視 8 份看不出差別），Anton 1.25 倍後 142 pt（約 1.42 倍）。
- 量測（V3，-O，全程前景）：新版 Linkin Park 組合 p50 0.63–0.80／p95 1.14–1.33 ms、Slipknot 組合 0.86–1.45／2.09–2.22、Anton＋neonstroke 0.65–0.86／1.18–1.34，**全部達標**；舊版（main，Anton 未放大）p95 分別 1.20–1.51／1.67–1.90／1.08–1.27。每幀最多 run 數新舊相同（9／267／54）。原始 log 在本 session scratchpad `v3-new/`、`v3-old/`。
- 決策辯論（/thecure，Codex 2 輪）：A（只重核 thump 門檻）不成立——換算後是真的變差；Codex 建議 B（撤回 Anton 放大）＋補一個實際視窗尺寸的 V3 案例（不放寬）；E（有效字級超過 100 pt 時改用更高尺寸建點陣）可行但推翻 2026-10-16 計劃 F5 的實測結論，要另立計劃驗證。**等使用者裁定**；在此之前不進 /simcodex（閘門：代碼測試未全綠）。

### 9.3 根因鑑別與 Anton 決策（/thecure，2026-10-17）
- 我方先前「>100 pt 放大點陣」的根因推測**被自己的實驗推翻**：E1（同 seed，thump 與 none、sizeScale 1.0／1.125／1.25）——thump 在 t=4.6／5.7 的 zoom＝1.000、兩者差異量相同；測試畫布最大有效字級 98.4 pt（沒有放大），2× over16 仍為 10,820／17,936／28,355。
- E4（6 個 Anton 字、不透明、單獨比點陣與向量）：rot 0：100 pt 只有 351，40–80 pt 2,328–7,965，120–200 pt 20,121→75,198、最大差 93–143；rot 0.05：100 pt 13,020，其餘同趨勢。→ 任何縮放比 ≠ 1 都偏離，旋轉是主要來源；> 100 pt 時最大差超過 I-46 的 96。
- Spike（已還原）：點陣改以實際字級建 → V3 10 份全部大幅變差（293 斷言紅）。已排除「只是放大」「照實際字級建點陣」。根因機制 **TBD**，熔斷不再深挖。
- 辯論（Codex 3 輪＋整體確認）收斂：Anton 維持 1.25（使用者決定）、**Anton 的字不走點陣**（`FontFace.rasterizes = false` → `.vectorMerged`，與參考畫法同一路徑）；其他字型照 I-46。我方輸在「Anton 暫維持 1.0」（違反使用者決定）與先前未經證實的根因說法。Codex 最擔心：I-46 在實際全螢幕字級（em≈113 pt）沒有驗證 → ACCEPTANCE I-46 註記覆蓋缺口，另立研究計劃。
- 實作（TDD）：新測試 2 條（5 個斷言紅）→ 綠；V3 thump 改為逐像素相同（差 0）。全量 **1277 條綠**；`no_playback_gate.sh` 0；覆蓋率 96.2%；Python 333 OK。
- V1（-O，向量旁路後，全程前景）：Linkin Park 組合 p50 0.67–0.88／p95 1.30–1.64 ms、Slipknot 組合 0.87–1.39／1.87–2.03、Anton＋neonstroke 0.67–0.94／1.21–1.36，**全部達標**；每幀最多 run 數 10／267／54。log：本 session scratchpad `v3-vec/`。
- ACCEPTANCE：I-45 擴寫（①②）、I-46 加覆蓋缺口註記、新增 I-47（Anton 字級 ⚠️＋暫走向量）。

## 附錄 A　計劃評審記錄
### A.1 R1（Codex，2026-10-17）
| # | 嚴重度／位置 | 處置 | 理由／修改 |
|---|---|---|---|
| 1 | P0 列寬 ≤ 0.86W 不等於墨跡不出框，驗收自相矛盾 | **採納** | 改契約 B：水平保守包絡（含旋轉、散布、停留、外框溢出、半個描邊寬），以基線回歸擋住誤傷 |
| 2 | P0 描邊「等同原型」不成立（原型隨逐字 scale） | **採納** | 需求改為「每句共用描邊寬＝該句 em×0.06」，明記與原型的既有差異不動 |
| 3 | P1 `shifted` 會把 stroke 歸零 | **採納** | `shifted` 明確複製；加並存效果的 plan 測試 |
| 4 | P1 逐位元／逐像素證據不足 | **修改後採納** | 主張降為「固定輸入下 plan 數值＝改前基線」，基線在 main 先記；不宣稱跨 OS 像素相同 |
| 5 | P1 描邊 run 分段的效能沒量 | **採納** | V3 加 Anton＋neonstroke、兩句同時可見，記 run 數 |
| 6 | P1 斷詞後上下放不下的優先序、快取完整決策 | **採納** | `FitResult(ratio, breaksLongWords)`；斷完重跑完整 fits；無解照 0.5 倍畫＋記一次 |
| 7 | P1 不要改 TimedWord.split | **採納**（本來的設計就在 layout 層，寫明） | 保留同一 wordIndex；加 Unicode 回歸 |
| 8 | P2 快取鍵加版本號／量測器身分 | **駁回** | 快取只在記憶體、行程結束即清，沒有跨版本殘留；量測器分型別已有 `theCacheKeepsMeasurersApart`，同型不同設定的量測器在 app 不存在 |
| 9 | P2 Anton 只驗常數不足 | **部分採納** | V3 加 Anton 兩份量測；原型對照圖不做（原型的規則就是一個常數 0.15，畫面對不對交 V4 使用者目視） |
| 10 | P2 「按字元」用語不精確 | **採納** | 改為 extended grapheme cluster（Swift `Character`） |
### A.2 R2（Codex，2026-10-17）
| # | 嚴重度／位置 | 處置 | 理由／修改 |
|---|---|---|---|
| 1 | P1 旋轉要 abs、字高要實測 | **因 #6 改契約 A 而不適用** | 水平包絡公式整個拿掉 |
| 6 | P1 水平包絡對 em 不單調 | **採納（改契約 A）** | 多詞列寬可隨 em 變小而變大 → 包絡不單調且誤縮；改「每列排版寬 ≤ 折行寬」，可證單調、不誤傷 |
| 8 | P1 快取鍵缺詞界簽名 | **駁回（新證據）** | `TimedLine` 唯一 init 由 `TimedWord.split(text)` 產生 words（`LyricsTimeline.swift:21-27`），同 text 必同詞界；寫註解作不變條件 |
| 9 | P2 Anton 整條資料路徑 | **採納** | V1 加 plan 層 fontSize 斷言與縮字時 stroke 斷言 |
| 3 | 補強 shifted 小測試 | **採納** | V1 加 |
| 新 | 基線回歸不足以證明不誤傷 | **因契約 A 而解決** | 條件只在單詞寬 > 上限時才可能失敗（可證），不含超寬詞的句子判定不變；基線回歸作實證 |
### A.3 R3（Codex，2026-10-17；收斂）
- 契約 A 的「不誤傷」成立；R2 #1、#3、#6、#8、#9 與「基線不足」全部關閉。
- 剩 P1：「可證單調」說得過強（非線性字型 0.5 pt 量化）→ **採納**，改寫為近似單調前提，並寫明搜尋只回傳實際通過 `fits` 的候選（現有 `search` 結構即保證），最壞是略小、不會放不下。
