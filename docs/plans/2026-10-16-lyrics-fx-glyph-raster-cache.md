# Lyrics FX — 每幀優化：字形點陣快取（根因實測後定案；計劃評審 R1 已併入）

基線：`main` bef930f（v2.0.2，批 4 T7 已合併並 push）。上游：批 4 計劃 §9.7、T7 修正計劃 §9、ACCEPTANCE I-25／I-40／I-44。

## 0. 複述
- 使用者的口令（2026-10-16）：批 4 T7 有 4 份每幀量測未達標，使用者已接受現狀（I-44 ⚠️），字形點陣快取列為後續工作。目標是 **p50 ≤ 2 ms、p95 ≤ 3 ms**，而且**畫面和現在一致**：不改任何視覺參數，暈開、倒影、縮字照舊。根因必須先實測證實，不能只靠推測。量測沿用 `t7-batch4.sh` 的做法（rain 換成 bluehour，另加 Marker 長句一份），用 -O 建置，每份丟掉第一個 5 秒窗。I-25 Catacombs、批 3 Special Elite 也一起量。全程不碰 Music 播放。改完要使用者在場目視。commit／push 等使用者拍板。
- 模式：**normal**（串行鏈：量測 → 計劃 → 評審 → 拍板 → 實作 → 目視，中間有兩個需要使用者在場的同步閘門，沒有無人值守時段）。
- 任務形狀：**串行**。改動集中在 `LyricsFXView.swift`，加一個新的快取檔與它的測試，書寫集合不能拆開，不派實作子 agent。

## 1. 已核事實（2026-10-16，本機 macOS 27.0、-O 量測建置＝Debug 配置＋`SWIFT_OPTIMIZATION_LEVEL=-O`，DerivedData 放在 scratchpad）
### F1 基線重現（`main` bef930f；7 份配方，每份 6 窗丟第 1 窗，取 5 窗；**全程前景**）
| 配方（dense 預覽） | p50 | p95 | 判定（2／3 ms） |
|---|---|---|---|
| Rock Salt＋藍調時刻＋暈開＋抖動（The Used） | 1.94–3.92 ms | 4.99–5.80 ms | 未達標 |
| IM Fell＋藍調時刻＋暈開＋閃爍（MCR） | 2.07–3.78 | 5.28–5.86 | 未達標 |
| Shadows＋藍調時刻＋暈開＋倒影（MCR） | 1.13–2.55 | 3.61–4.00 | 未達標 |
| Permanent Marker 長句＋暈開＋抖動（The Used） | 1.41–3.34 | 4.34–4.73 | 未達標 |
| Courier＋藍調時刻＋呼吸＋倒影（DCFC） | 0.86–1.47 | 2.29–2.62 | 達標 |
| Catacombs,snow,smoke,dissolve,misreg,shake,ice（I-25） | 2.31–2.81 | 4.51–5.83 | 未達標 |
| Elite,scan,drop,bands,rgbsplit,shake,acid（批 3 Special Elite） | 1.36–2.54 | 3.68–4.15 | 未達標 |
- 和 T7（批 4 §9.7）同一量級，基線可信。螢幕每格最多 8.3 ms；最差的 p95 5.9 ms 約佔一格的 70%。
- 作廢記錄：第一輪有 5 份 `front=NO`（使用者當時在用電腦，前景被別的 app 拿走），整輪作廢重跑。第一輪 Special Elite 用了不存在的 id `SpecialElite`（正確 id 是 `Elite`），配方沒套上，作廢。

### F2 字形外框複雜度（每個字的 CGPath 元素數，48 pt、49 個拉丁字母取平均／最大）
Grimoire 15／23、Anton 20／36、**Courier 45／76**、Shadows 47／88、Cinzel 54／87、Marker 90／129、**Rock Salt 161／352**、Special Elite 194／296、**IM Fell 222／510**、**Catacombs 319／421**。
- 和每幀的快慢大致同序。Shadows 的外框和 Courier 差不多卻仍未達標，是因為它有暈開副本（字數乘 3）、Courier 那份沒有。

### F3 根因（Time Profiler，`xctrace --attach`，每份錄 15 秒，主執行緒樣本 1 ms／筆）
`LyricsFXFrameMeter` 計的區間是「`plan()`＋Canvas 指令編碼」（`LyricsFXView.swift` 的 Canvas 閉包）。區間內樣本的拆分如下：
| 配方 | 區間內樣本 | `CG::Path::append` | RenderBox 算路徑邊界 | `plan()` | 其他 |
|---|---|---|---|---|---|
| Rock Salt | 2952 | **70.4%** | 13.1% | 6.2% | 10.2% |
| IM Fell | 3131 | **64.5%** | 15.5% | 6.7% | 13.4% |
| Marker | 2653 | **67.2%** | 9.5% | 8.6% | 14.7% |
| Catacombs | 2961 | **56.1%** | 18.1% | 6.8% | 19.1% |
| Special Elite | 2274 | **58.7%** | 14.6% | 10.1% | 16.6% |
| Shadows | 1788 | **51.6%** | 10.0% | 13.3% | 25.1% |
| Courier（達標） | 981 | 42.3% | 8.2% | 27.2% | 22.3% |
- `CG::Path::append` 全部來自 `LyricsFXCanvas.fill`：每一幀把每個字的快取外框用 `CGMutablePath.addPath(_:transform:)` 複製、變換後拼進新路徑，成本和外框元素數 × 字數成正比。RenderBox 的邊界計算（`RB::Coverage::Path::bounds` → `path_element_bounding_box`）是對這條新拼出來的路徑逐元素再算一次。
- **修正舊推測**：批 3 §9.7、批 4 §9.7 推測的是「逐字填色貴」。實測顯示，量測區間內最貴的不是填色，而是**每幀重新拼路徑**。光柵化不在量測區間內（見 F5）。
- 量測區間**外**，主執行緒也有 RenderBox 的工作（`CA::Transaction::commit` → `RB::DisplayList::render`：拍平、光柵化、算邊界）。Rock Salt 基線約 2000 筆／15 s，量測器看不到這部分。

### F4 候選畫法 spike（scratchpad 的獨立 worktree，detached bef930f，用 `AZW_SPIKE` 切換；量完即刪，不進 main）
- `vec`：逐字 `concatenate(transform)` 後直接 `fill(Path(entry.path))`，不再拼路徑。
- `vecl`：同 `vec`，但「透明度 < 1 且 ≥ 2 字」的 run 包一層 `drawLayer`（群組透明度，保留原本「整個 run 合成一次」的疊色語義）。
- `bmp`：逐字畫快取點陣圖（外框在快取字級下以 2× 光柵化成 template 圖，`resolve` 後設 `shading`）。
- `bmpl`：`bmp`＋與 `vecl` 相同的群組圖層規則。
- `none`：不畫字（下限參考）。

**每幀（量測器；7 份，全程前景）**
| 配方 | 基線 p95 | vec | vecl | bmp | **bmpl** |
|---|---|---|---|---|---|
| Rock Salt | 4.99–5.80 | 1.42–1.56 | 1.45–1.54 | 1.52–1.70 | 1.67–1.92 |
| IM Fell | 5.28–5.86 | 1.51–1.78 | 1.55–1.68 | 1.58–1.74 | 1.72–2.04 |
| Shadows | 3.61–4.00 | 1.37–1.51 | 1.44–1.56 | 1.95–2.08 | 2.01–2.23 |
| Marker | 4.34–4.73 | 1.33–1.48 | 1.45–1.51 | 1.56–1.74 | 1.52–1.91 |
| Courier | 2.29–2.62 | 1.04–1.11 | 1.00–1.20 | 1.33–1.55 | 1.56–1.64 |
| Catacombs | 4.51–5.83 | 1.42–1.48 | 1.47–1.51 | 1.93–2.03 | 2.08–2.36 |
| Special Elite | 3.68–4.15 | 1.22–1.29 | 1.24–1.31 | 1.13–1.24 | 1.14–1.27 |
| p50 全部配方的最大值 | 3.92 | 1.88 以內 | 1.22 | 2.04 以內 | **1.61** |
（`none`：Rock Salt p95 0.60–0.65、IM Fell 0.64–0.65。）
- 作廢記錄：`vecl` 第一次量測用了加入 vecl **之前**建的二進位，app 不認得這個值、退回原畫法。剖析顯示 `addPath` 仍佔 74.5%，因此發現。重建後重量，上表是重量結果。

**主執行緒總量**（量測區間內＋區間外，15 秒內的毫秒數；這才是使用者畫面真正的負擔）
| 配方 | 基線 | vec | vecl | bmp | **bmpl** |
|---|---|---|---|---|---|
| Rock Salt | 4980 | 4346（−13%） | 4623（−7%） | 3611（−27%） | **3582（−28%）** |
| Catacombs | 5427 | 4557（−16%） | 4950（−9%） | 3993（−26%） | **4199（−23%）** |
- 向量方案在量測區間內省下的時間，大多搬到了區間外：`RB::DisplayList::render` 448 → 1118，因為逐字的繪製項目更多，每一項都要另外拍平、光柵化、算邊界。點陣方案在區間外的成本基本持平（只是貼圖），所以主執行緒真的變輕。

**畫面一致性**（離屏 `ImageRenderer` 2×、900×560；7 份配方 × 6 個時刻〔2.4 進場、4.6 停留、5.7 換行、9.3 退場、20.5 CJK、24.0 長句〕；和現行畫法逐像素比 RGB）
| 畫法 | 平均差 | 最大差 | 差 > 2/255 的像素 | 差 > 16/255 的像素 |
|---|---|---|---|---|
| 現行畫法再畫一次 | 0 | 0 | 0 | 0 |
| vec | 0.00102 | 103/255 | 4.38% | 0.51% |
| vecl | 0.00015 | 49/255 | 0.11% | 0.008% |
| bmp | 0.00135 | 103/255 | 4.75% | 0.69% |
| **bmpl** | 0.00054 | 76/255 | 1.39% | 0.245% |
- 同一畫法畫兩次完全相同：離屏渲染是確定性的，比對有效。
- `vec`／`bmp` 的差異主要來自「半透明、互相重疊的字分開畫，重疊處疊深」。加了群組圖層後大幅收斂。
- `bmpl` 剩下的差異（推測）：點陣圖在快取字級光柵化一次，畫的時候再縮放、旋轉，會有重取樣。推理鏈：`vecl` 和 `bmpl` 只差在向量或點陣，兩者的差距（0.11% → 1.39%）就是重取樣造成的。（F5 補驗後修正：原本猜「進場放大造成放大取樣」是主因，但分檔與固定高解析度都更差，主因是「任何重取樣」，見 F5。）

### F5 評審 R1 後補的 spike（同一個 worktree；回應附錄 A 的 #1、#5、#11、#15）
- 新增三個變體，都套用和 `bmpl` 相同的群組圖層規則：
  - `bmpa`：2×、只有 alpha 的遮罩。
  - `bmpf`：固定 6.4×（2×3.2，涵蓋最大的進場放大倍率）、alpha-only。
  - `bmpb`：分檔、只縮不放，所需像素含 `plan.zoom`、alpha-only。
  - `bmpd`：點陣解析度＝`environment.displayScale`、alpha-only。
- 配方：F4 的 7 份，加上 `thump`（Anton,void,fadeUp,sink,thump,jitter,revenge；有整屏縮放）和 mono，共 9 份 × 6 個時刻 × 2 種 scale。表中是逐案的最差值。
| 畫法 | scale | 平均差 | 最大差 | 差 > 2/255 | 差 > 16/255 | 點陣總量 |
|---|---|---|---|---|---|---|
| vecl | 2× | 0.00007 | 61 | 0.150% | 0.034% | — |
| bmpl（RGBA） | 2× | 0.00064 | 88 | 1.394% | 0.379% | 21.6 MB |
| bmpa（alpha-only） | 2× | 0.00064 | 88 | 1.394% | 0.379% | 5.8 MB |
| bmpf（固定 6.4×） | 2× | 0.00177 | 145 | 1.412% | 0.865% | 55.6 MB |
| bmpb（分檔） | 2× | 0.00166 | 210 | 2.081% | 0.919% | 4.0 MB |
| **bmpd（＝displayScale）** | 2× | 0.00064 | 88 | 1.394% | 0.379% | 5.8 MB |
| vecl | 1× | 0.00013 | 129 | 0.284% | 0.065% | — |
| bmpl／bmpa（2× 點陣） | 1× | 0.00277 | 125 | 2.158% | 1.658% | — |
| **bmpd** | 1× | 0.00127 | 86 | 2.234% | 0.706% | 1.6 MB |
- 逐案最差的都是 mono@24.0（長句）、catacombs@4.6／5.7、thump@4.6／5.7。
- 已核事實：
  - `ImageRenderer.scale` 會反映到 `GraphicsContext.environment.displayScale`（2→2、1→1）。
  - alpha-only 遮罩加 template 上色，在 Canvas 最終合成時和 RGBA **逐案完全相同**，記憶體只有 1/4。
  - **分檔與固定高解析度都比「點陣＝螢幕像素」更差**，所以 R1 #1、#15 提出的補救方向不成立。推測的原因：RenderBox 的向量抗鋸齒，和 CG 光柵化後再一對一貼圖最接近，任何重取樣（不論放大或縮小）都會偏離。
- 目視（我方，非使用者）：mono@24.0 1×（「walking」放大 6 倍）、catacombs@5.7 2×（「HARBO」放大 3 倍），原畫法和 bmpd 並排看不出差別。最終以 §6 使用者目視為準。
- **bmpd 的效能**（全程前景）：每幀 p50 0.59–1.44、p95 0.99–2.38 ms（7 份全部達標；最差是 Shadows 的 p95 2.38）。主執行緒總量 Rock Salt 3722 samples（−25%）、Catacombs 4133（−24%）。`footprint` phys_footprint 在 20 s 時：基線 346／363 MB → bmpd 300／300 MB。
- **差異的位置**（回應 R2 #5）：「邊緣帶」＝原畫中 5×5 鄰域內有亮度差 > 16/255 的像素。差 > 16/255 的像素落在邊緣帶**之外**的比例，逐案最差：bmpd 2× 0.0002%（elite@24.0，最大差 30/255），bmpd 1× 0，vecl 0。差異幾乎全在字形邊緣，字內部沒有錯誤。
- 也看過 `vecl` 為何在 mono 上不為 0：不透明的字分開填時，相交處的抗鋸齒和合併填不同（R1 #4 屬實）。

## 2. 設計（採 bmpd：點陣＝displayScale、alpha-only、半透明多字 run 包群組圖層）
### 2.1 目標與非目標
- 目標：量測器 p50 ≤ 2、p95 ≤ 3 ms（7 份配方，逐窗皆達標）；主執行緒總量下降；畫面在 §3 V3 的逐案門檻內，並經使用者目視。
- 非目標：
  - 不改任何視覺參數（字級、暈開、倒影、縮字、配色、動作）。
  - 不改 `plan()`。
  - 不改量測器口徑（用戶既裁定，A2 計劃 §3.7）。
  - 不改霓虹描邊的畫法。
  - Python 舊版不動。
  - mono 走同一個 `fill`，會連帶改成點陣，畫面門檻同樣適用（V3 含 mono）。

### 2.2 `GlyphRasterCache`（新檔 `Features/LyricsFX/GlyphRasterCache.swift`）
- **幾何契約**（R1 #2）。`RasterEntry` 包含以下欄位：
  - `image`：template `Image`，`Image(decorative: cgImage, scale: pixelsPerPoint)`。
  - `box`：外框在 `GlyphPathCache.Entry` 座標下的 bounding box，四周外擴 1 pt 後取整（`integral`）。
  - `pixelsPerPoint`：＝`displayScale`。
- 光柵化：`CGContext(width: ceil(box.w×s), height: ceil(box.h×s), alphaOnly)`，`scaleBy(s, −s)`，`translateBy(−box.minX, −box.maxY)`，然後填外框。
- 貼回：`context.concatenate(transform(for: glyph, entry:))` 之後 `draw(resolved, in: box)`。外框和點陣都在同一個 `Entry` 座標系，因此基線、旋轉軸、縮放軸**由構造保證**和現行畫法相同。
- 不變式測試：`box` 經 `transform(for:)` 映射後的矩形，要包含外框經同一 transform 映射後的 bounding box，四邊差 ≤ 1 pt×縮放。
- 鍵：`(text, face, entry.size, pixelsPerPoint)`。不分檔（F5：分檔、固定高解析度都比較差）。動畫中的縮放與 `plan.zoom` 照現行做法由 transform 處理，代價是暫態的重取樣；已有 thump、進場的案例納入 V3。
- `pixelsPerPoint` 取自 `GraphicsContext.environment.displayScale`（F5 已核：離屏的 `ImageRenderer.scale` 也會反映）。
- 容量：以位元組計，上限 **16 MB**。F5：9 份配方 × 6 個時刻累積 278 筆＝5.8 MB（2×）。插入新 entry 前，若加上它會超過上限，就先整批清空（和 `GlyphPathCache` 同一做法）。若單一 entry 本身就超過上限，**只畫這一次、不進快取**，並計入 DEBUG 診斷（R2 #6）。**每幀最多清空一次**（/thecure 整體確認）：同一幀內已經清空過，之後再缺的點陣只畫這一次、不進快取，下一幀才恢復存入。這樣不會在同一幀裡反覆清空、重建，畫面也仍全是點陣，不混入向量，群組透明度的語義不變。清空後第一幀的成本由 V1b 把關。
- 只在主執行緒用（View 以 `@State` 持有，同 `GlyphPathCache`）。
- 診斷（DEBUG）：量測器的 OSLog 摘要加上 `rasterMisses`（本窗建圖次數）與 `rasterBytes`（目前快取位元組）。**時間口徑不變**，只是多兩個欄位。

### 2.3 `LyricsFXCanvas.fill` 改寫
- run 的切分、painter order、量化透明度**全部不變**。
- 純函式 `LyricsFXCanvas.glyphRunStrategy(level:count:stroke:) -> .vectorMerged | .rasterGrouped | .rasterDirect`：
  1. `stroke > 0` → `.vectorMerged`（就是現行畫法，霓虹描邊需要路徑）。
  2. 透明度 < 1 且 run 內 ≥ 2 個字 → `.rasterGrouped`：`drawLayer` 裡逐字以全不透明畫點陣，整層合成時套 run 的透明度。
  3. 其餘 → `.rasterDirect`：逐字畫點陣，套 run 的透明度。
- 已知差異（R1 #4，照實列為風險 R1）：不透明 run 逐字貼圖，和合併路徑一次填色，在字形相交處的抗鋸齒不同。由 V3 的 mono、Catacombs 等案例把關。
- 參考畫法：`draw(_:in:size:paths:rendering:)` 加參數 `GlyphRendering`，`.raster` 為預設，`.vectorReference` 是現行畫法（全部走 `vectorMerged`），只給 V3 比對用。不加環境變數或執行期開關。

### 2.4 不改的東西
- `plan()`、`GlyphPathCache`、縮字快取、暈開分組、量測器的計時區間與 `fills` 的算法（仍以 run 數計，維持可比）。

## 3. 驗收標準
- **V1 每幀**（R1 #7 寫死判定）：`measure.sh` 跑 7 份配方（`t7-batch4.sh` 的 4 份、rain 換成 bluehour，加上 marker、catacombs、elite），用 -O 建置。每份記 6 個 5 秒窗、丟第 1 窗；**其餘 5 窗每一窗各自的 p50 ≤ 2 ms 且 p95 ≤ 3 ms**（與 T7 的判定方式相同：以窗的範圍呈現，取最差的一窗判定）。任何一份 `front=NO` 就重跑那一份。原始 log 保存在 §9 指定的路徑。
- **V1b 冷快取與清空**（R1 #6、R2 #3）：
  - 首窗不丟，記下首窗的 max 與 `rasterMisses`（只記錄）。
  - 單元測試以 Rock Salt、Catacombs 的 dense 預覽幀，在空快取下量「重建整幀點陣＋繪製」的單幀耗時（-O，取 10 次的最大值），**≤ 8.3 ms**（一格）。這是清空後第一幀的最壞情況：整幀所有字都要重建。
  - 不達標 → 加「每幀最多建 N 張，其餘這一幀先走 `vectorMerged`」的上限再量；仍不達標就停手回報。
- **V2 主執行緒總量**（R1 #8）：
  - 命令：`xcrun xctrace record --template 'Time Profiler' --attach <PID> --time-limit 15s`，在 app 啟動 8 s 後開始錄；錄完核對 `lsappinfo front` 為該 PID。
  - 計數：`time-profile` 表中 thread 名含「Main Thread」的 sample 筆數（單位是 samples，取樣間隔 1 ms）。
  - 前景（R2 #4）：錄製期間背景迴圈每 0.25 秒記一次 `lsappinfo front` 的 PID，**任一次不是該 PID 就作廢該輪**。
  - Rock Salt、Catacombs 各跑 2 輪，基線（main 建置）與新版**交錯**跑；取 2 輪的平均。新版 ≤ 基線 × 0.85。trace 原檔保存。
- **V3 畫面一致性**（單元測試常駐；R1 #3、#9、#14）：
  - 案例：F4 的 7 份＋thump＋mono＋glow（Cinzel,shafts,smoke,fade,breathe,glow,goldNavy）＋neonstroke（Bungee,void,fadeUp,sink,neonstroke,none,revenge）。每份 × 6 個時刻 × {2×, 1×}。
  - 比對：離屏 900×560，sRGB、RGBA8 premultiplied，比 RGB 三通道；`.raster` 對 `.vectorReference`。
  - **每一案各自**達標：
    - 2×：平均差 ≤ 0.0007、差 > 2/255 ≤ 1.5%、差 > 16/255 ≤ 0.4%、最大差 ≤ 96/255。
    - 1×：平均差 ≤ 0.0013、差 > 2/255 ≤ 2.3%、差 > 16/255 ≤ 0.75%、最大差 ≤ 96/255。
    - 兩種 scale 都要：差 > 16/255 而落在邊緣帶（定義見 F5）**之外**的像素 ≤ 0.001%，且**這些邊緣帶外像素**的最大差 ≤ 48/255（R2 #5、R3：擋住字內部的內容錯誤；全圖的最大差仍照上列 96/255）。
  - neonstroke 那份**必須逐像素相同**：它走 `vectorMerged`，和參考畫法同一條路徑。
  - **適用環境**（R2 #1）：門檻綁定本機（Apple Silicon、macOS 27.0.x、Xcode 27）。本專案沒有 CI，雲端（Linux）跑不了 Swift 測試。macOS 主版本升級後若 V3 轉紅，先視為「平台抗鋸齒可能改變」：重量 F5 的 vecl／bmpd 對照，連同差異熱圖交使用者裁決是否重新核准門檻；**不自動放寬，也不直接當成產品回歸**。
  - 門檻來源：F5 `bmpd` 的逐案實測最差值（2×：0.00064／1.394%／0.379%／88；1×：0.00127／2.234%／0.706%／86）略為上取。離屏渲染是確定性的（同畫法畫兩次差 0，F4），所以不會因為不穩定而時紅時綠；若 OS 更新後改變了抗鋸齒而轉紅，那是真訊號，要重新評估，**不得放寬**。glow 這份的 spike 數據還沒有，T2 先量；若超出上列門檻，停下回報，不自行放寬。
  - 診斷（不設門檻）：最差的 4 案輸出原畫／新畫／差異熱圖 PNG 到測試暫存目錄，供 §6 參考。
- **V4 使用者在場目視**：§6。
- **V5 回歸**：
  - 全量單元測試綠：skip `AzathothsWhisperTests/BatchOverlappingLoadTests/overlappingLoadSuspendsPollingUntilLastCompletes()`，用完整名稱並帶括號。
  - `no_playback_gate.sh` 0。
  - `coverage_gate.sh <全量 xcresult>` Services+Infra ≥ 80%。
  - `Scripts` 的 Python 測試 OK。
  - `LyricsFXUITests`＋`LyricsFlowUITests` 20 條（使用者在場）。

## 4. 任務清單（每項帶 DoD）
- **T0 清 spike**（R2 #7）：只刪本次建立的這幾個路徑（都在 session scratchpad `/private/tmp/claude-501/-Users-ibridgezhao-Documents-Bjork/b28e59af-c0b5-4c64-b2f7-23346b01e9db/scratchpad/` 之下）：`spike/`（detached worktree，用 `git worktree remove --force` 移除，因為裡面有未提交的 spike 改動）、`dd.BDBz/`（基線 -O 建置）、`dd-spike/`、`dd-spike-test/`。刪之前先唯讀核對：`git worktree list` 的路徑、各 DerivedData 的 `info.plist` 的 WorkspacePath。量測 log、trace 留到收官再一併問使用者。DoD：`git worktree list` 只剩主樹；數據已在 §1。
- **T1 快取（TDD）**：先寫 `GlyphRasterCacheTests`，跑出紅燈。測試內容：
  - 幾何不變式（§2.2）。
  - 同鍵重用。
  - 不同 `pixelsPerPoint` 用不同鍵。
  - 位元組上限一到就清空；同一幀第二次超額時不再清空、只畫不存，下一幀恢復存入。
  - alpha-only 遮罩的覆蓋像素數，和 `CGContext` 直接填外框一致。
  
  再實作到綠。DoD：新測試綠，紅燈摘要記 §9。
- **T2 繪製改寫（TDD，R1 #12）**：
  - 先加 `GlyphRendering`。`.raster` 的**第一版**是「逐字向量填、不包群組圖層」（F4 的 `vec`，已知會超出 V3 門檻），可以編譯。
  - 寫 `glyphRunStrategy` 的純函式測試與 `GlyphRasterFidelityTests`（V3），跑出**斷言紅**（不是編譯紅）。
  - 再換成 §2.3 的完整實作，跑到綠。
  
  DoD：V3 綠，逐案實測值記 §9；既有 LyricsFX 測試全綠。
- **T3 量測**：V1、V1b、V2。未達標時，先看剖析找新熱點、修一次；仍未達標就停手，交使用者裁定（熔斷）。DoD：數據記 §9。
- **T4 文件**：
  - ACCEPTANCE I-44 依 V1 更新。
  - I-25、I-40 附上本次量測；達標就改狀態，附日期。
  - 新增 I-46（點陣快取：V3 門檻與 V2）。
  
  DoD：條目有依據、驗證方式、狀態。
- **T5 Phase 3 評審**：/simcodex。
- **T6 使用者在場**：§6。

## 5. 測試策略
- 單元：`GlyphRasterCacheTests`、`glyphRunStrategy` 的測試。
- 整合：`GlyphRasterFidelityTests`（真實字型＋真實 `plan()`＋離屏渲染）。
  - spike 用 -O 跑 9 份 × 6 時刻 × 2 scale 只要數秒；Debug 下（推測）數十秒。
  - 若會超過 120 s，**只准**把比對迴圈改成 vDSP 或分塊；**不准**抽樣、刪配方、刪時刻或刪 scale（R1 #13）。
- E2E：既有 UI 測試＋V1 真視窗量測＋使用者目視。
- 測試字串一律用自編句子。
- 注意：V3 跑的時候會長時間佔住測試宿主 app 的主執行緒，視窗會轉彩虹球、顯示「沒有回應」，這是正常的。跑之前要先告訴使用者，請他不要關掉那個視窗。

## 6. 使用者在場（計劃核准、實作完成後）
- #1 UI 測試 20 條（開跑前、跑完後各核一次 ABC 輸入法）。
- #2 目視：內建螢幕、全螢幕。
  - 看哪些：4 份固定配方（Rock Salt、IM Fell、Shadows、Marker 長句）＋Catacombs＋Special Elite＋Courier＋mono。
  - 怎麼看：每份**先看現行版（main 建置）、再看新版**，同一份配方、同一段預覽歌詞。
  - 問題只有一個：「看得出差別嗎？」
    - 看得出來 → 記下哪一份、哪個時刻，回 T2 修。
    - 修兩輪仍看得出來 → 停手，交使用者決定是否改採 `vecl`（§8）。
- 外接 1× 螢幕：使用者只接內建螢幕（memory），真視窗 1× 無法驗證。V3 的離屏 1× 只證明 `displayScale` 的傳遞與 1× 點陣品質，**不代替**真視窗（R2 #2）。列為發版風險，下次有外接螢幕時補 smoke test：視窗移到 1× 螢幕後快取鍵會切換、畫面與每幀正常。
- 全程不碰 Music 播放（預覽走 `LyricsFlowUITestMusic` 替身）。

## 7. 影響面、風險與回退
- 影響面：所有組合配方與 mono 的字形繪製、離屏探針與預覽定格。
- R1 畫面差異：主要在字形邊緣與相交處（F5）。由 V3 逐案門檻＋目視把關。
- R2 記憶體：alpha-only＋16 MB 上限。實測行程總量反而下降（F5）。
- R3 外接 1× 螢幕：**未驗，發版風險**（見 §6）；離屏 1× 已驗。
- R4 量測器口徑偏樂觀：已知，由 V2 補上主執行緒總量。
- R5 快取清空尖峰：V1b 照實量。
- 回退：參考畫法常駐，`.raster` 改回 `.vectorReference` 只需一行。所有改動都在 wip 分支，未經使用者拍板不合進 main。

## 8. 決定（D1 經 /thecure 與 Codex 辯論收斂，2026-10-16；待使用者確認執行）
- **D1＝採 bmpd**，不採 vecl。
  - Codex R1 原判「現在選 bmpd 過早」，理由是按字面「一致＝像素相同」。我方反證三點：
    1. vecl 也不是像素相同（1× 最大差 129，比 bmpd 的 86 還大），所以這個標準分不出兩案。
    2. 使用者的原話把「一致」說明為「不改任何視覺參數」，並指定以在場目視驗收。
    3. 有 B1 T2 的前例：像素有差、判定符合預期。
  - Codex R2 撤回該論點，改選 bmpd。理由是主執行緒總量（−24–25% 對 −7–9%）；vecl 在量測區間內省下的時間，主要轉移到了 `RB::DisplayList::render`。
- 我方輸掉的：原本說「複雜度增加很小」並不成立。它改變了所有非描邊字形的繪製語義，屬於中等複雜度；「一行回退」也只是原始碼層級的回退，不是執行期的開關。另外 V1b 與 glow 的數據都還沒有實測。
- Codex 最擔心的：快取清空或 `displayScale` 切換時，第一幀要大量重建點陣而卡頓。→ **V1b 的「空快取整幀重建 ≤ 8.3 ms」是硬性放行條件**。`displayScale` 切換等於換一組快取鍵，最壞情況和空快取相同，由同一個測試涵蓋。
- 退路：使用者目視看得出差別、且修兩輪仍看得出來 → 停手，交使用者決定是否改採 vecl（§6）。改採時，V2 不適用，本計劃要另修。

## 9. 紀錄（實作時回填）

## 附錄 A　計劃評審記錄
### A.1 R1（gpt-5.6-terra／medium，2026-10-16；4 個 P0）
| # | Codex 意見 | 裁決 | 證據／落點 |
|---|---|---|---|
| 1 | P0 分檔漏了 `plan.zoom`，違反只縮不放 | **修改採納** | 指出的漏洞屬實；但補救方向（分檔含 zoom）被證據否定：F5 的 `bmpb` 比不分檔更差（差 > 16/255：0.919% 對 0.379%）→ 改成不分檔，thump 案例納入 V3 |
| 2 | P0 缺點陣幾何契約 | **採納** | §2.2 `RasterEntry`＋不變式測試 |
| 3 | P0 V3 門檻來自 aggregate、沒有 1× 證據、可能不穩定 | **採納（逐案、補 1×）；駁回「不穩定」** | F5 補了 1× 與逐案數據；離屏渲染確定性（同畫法差 0）→ 不會時紅時綠；門檻取逐案最差略上取 |
| 4 | P0 不透明 run 逐字貼圖也不等同合併填色 | **採納** | F5 已證實（vecl 的 mono 不為 0）；§2.3 列為已知差異，V3 加 mono／thump／reflect／glow |
| 5 | P1 alpha-only 是未驗證的平台行為 | **採納並已驗證** | F5：`bmpa` 和 RGBA 逐案完全相同 |
| 6 | P1 整批清空的尖峰、記憶體計算不全 | **採納** | V1b；`rasterMisses`／`rasterBytes` 診斷；`footprint` 實測行程總量 |
| 7 | P1 V1 的聚合方式沒寫死 | **採納** | V1：5 窗每一窗都要達標 |
| 8 | P1 V2 混用 samples 與毫秒、方法不嚴謹 | **採納** | V2 寫死命令、計數、交錯 2 輪 |
| 9 | P1 驗收覆蓋面小於影響面 | **採納**；外接螢幕**駁回** | V3 加 mono／thump／glow／neonstroke；使用者只有內建螢幕 → 離屏 1× 代替，記為未驗 |
| 10 | P1 D1 選 vecl 和 V2 矛盾 | **採納** | §8 明寫：選 vecl 則 V2 不適用、另修計劃 |
| 11 | P2 displayScale 來源應在核准前確認 | **採納並已驗證** | F5：`ImageRenderer.scale` 2→2、1→1 |
| 12 | P2 編譯失敗不算 TDD 紅燈 | **採納** | T2：第一版 `.raster`＝逐字向量填 → 斷言紅 |
| 13 | P2 超時不得抽樣 | **採納** | §5 |
| 14 | P2 缺最大差上限、高差像素位置 | **部分採納** | 加最大差 ≤ 96/255；位置判定改為輸出熱圖供目視（自動判定邊緣膨脹區屬過度設計，不做） |
| 15 | P2 改用固定高解析度單張更簡單 | **駁回（證據）** | F5 `bmpf`：差 > 16/255 0.865%、55.6 MB，畫面和記憶體都比 bmpd 差；bmpd 本身已是最簡（不分檔） |
### A.2 R2（2026-10-16；確認輪）
- Codex 確認 R1 #1 的補救方向與 #15 固定高解析度已被 F5 否定，無保留。
| # | Codex 意見 | 裁決 | 落點 |
|---|---|---|---|
| 1 | P1 V3 的確定性只在本機成立，OS 升級後轉紅不能一律當產品回歸 | **採納** | V3「適用環境」：綁定本機；升級後轉紅交使用者重新核准，不自動放寬 |
| 2 | P1 離屏 1× 不能代替外接螢幕 | **採納** | §6、R3 改為發版風險，未閉環 |
| 3 | P1 V1b 只記錄，證明不了清空不會卡 | **採納** | V1b 加「空快取整幀重建 ≤ 8.3 ms」，以及不達標時的每幀建圖上限 |
| 4 | P1 V2 只在錄完核對前景 | **採納** | 錄製期間每秒核對 |
| 5 | P2 熱圖不是位置判定 | **採納（先補證據再定門檻）** | F5 補了邊緣帶外的比例（bmpd 2× 最多 0.0002%，1× 為 0）→ V3 加門檻 ≤ 0.001%、最大差 ≤ 48/255 |
| 6 | P2 單一超大 entry 的規則未定義 | **採納** | §2.2 |
| 7 | P2 T0 刪除目標過寬 | **採納** | T0 列出絕對路徑＋先唯讀核對 |
- 合計 R1 15 條（採納 9、修改／部分採納 4、駁回 2，駁回都有證據且 Codex R2 同意）；R2 7 條全部採納。
### A.3 R3（2026-10-16；收斂）
- P1：「最大差 ≤ 48/255」的作用範圍有歧義，可能被讀成全圖門檻，而全圖實測是 88／86 → **採納**，V3 明寫只適用於邊緣帶外的像素。
- 殘留 P2（不改，照實記錄）：
  - V1b 要等實作後才有實測，而且只用兩個 dense 案例代表清空的尖峰。
  - 外接 1× 真視窗未驗（發版風險，§6）。
  - 前景核對仍是抽查：已從每秒加密到每 0.25 s，不做事件式監聽。
- 修正後無 P0／P1 開著。§8 D1 隨後經 /thecure 收斂為 bmpd。
### A.4 D1 辯論（/thecure，2026-10-16）
| # | 論點 | 提出方 | 狀態 | 證據 |
|---|---|---|---|---|
| 1 | 按字面，「一致＝像素相同」→ bmpd 違反需求 | Codex | **我勝**（Codex R2 撤回） | vecl 也不為 0（1× 最大差 129）；使用者原話的括號說明＋目視驗收；B1 T2 前例 |
| 2 | 主執行緒 samples 低 ≠ 體感更快 | Codex | 部分成立 | 門檻口徑是量測器，兩案都達標；總量是附加證據。Codex R2 以總量為由改選 bmpd |
| 3 | 複雜度被低估、回退不是執行期的 | Codex | **Codex 勝** | §2.2–2.3；§8 已修正說法 |
| 4 | V1b、glow 還沒有實測 | Codex | **Codex 勝**（屬實） | V1b 定為硬性放行條件；glow 在 T2 先量 |
| 5 | 真視窗 1× 未驗 | Codex | 兩案相同，保留為發版風險 | vecl 同樣未驗 |
| 6 | 同一幀內反覆清空 | Codex（整體確認） | **Codex 勝**，已採納 | §2.2「每幀最多清空一次」 |
- 結論：bmpd。Codex 最擔心的是快取清空或切換時第一幀的尖峰（V1b）；整體確認時認為最容易失敗的是 T2（glow 與 1× 的 V3）。
