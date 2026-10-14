# Lyrics FX — B2 批 4 T7 回饋修正（Rock Salt 出框、拿掉雨絲、暈開減量、倒影調淡）（計劃評審 R1 已併入）

上游：批 4 計劃 `docs/plans/2026-10-13-lyrics-fx-b2-batch4.md`（下稱「批 4 計劃」）T7。基線：`main` 1c82372（v2.0.2，批 4 已合併）。

## 0. 複述
- T7 實跑時使用者看了每幀量測的真視窗，提出三點（2026-10-14 原話）：
  1. 「那個字體有的超出了上邊框和下邊框，字體被砍掉了、沒有顯示全」
  2. 「雨絲不要了 做的一點都不像 就是一堆細線與其粗製濫造不如不要」
  3. 「字母隨著時間會往下、類似暈開一樣疊了好幾層，再加上抖動，讓人看著眼暈……你把往下暈開、疊在一起的層數減少一些，不要暈開那麼大」
  4. 「這個倒影的字和它本體的字距離有點太遠了……倒影和下一行的正字重疊在一起，看著就非常亂。你讓這個倒影淡一些吧」
- 目標＝四點都修掉，再把 T7 剩下的部分（UI 測試、每幀、目視）在修正後的版本上做完。
- 模式：**normal**；任務形狀：**串行**（三項都動 `LyricsFXCatalog.swift`／`ComposedStyle.swift`／批 4 測試檔，書寫集合重疊），不派實作子 agent。

## 1. 已核事實（2026-10-14）
- F1 UI 測試（修正前的 1c82372）：`LyricsFXUITests`＋`LyricsFlowUITests` 20／20 綠（第二輪；第一輪 2 紅是使用者跑測試時切過輸入法，詳 §9）。
- F2 每幀（-O 量測建置）：Rock Salt＋雨絲＋暈開 p50 2.25–4.37／p95 6.08–7.13 ms；IM Fell＋雨絲＋暈開 2.60–4.86／6.85–8.16；Shadows＋藍調時刻＋暈開 1.59–3.09／4.32–4.76；Courier＋藍調時刻（無暈開）0.99–1.81／2.46–2.72。對照：Rock Salt 拿掉暈開 1.36–2.23／2.98–3.43；換 Courier 保留暈開 1.33–2.49／3.82–4.01。→ 暈開約讓耗時翻倍，Rock Salt 字形本身也比 Courier 重約 1.7 倍。
- F3 出框的字型＝**Rock Salt**（截圖：密集預覽一行只放得下一個詞，字頂貼到工具列邊框，只看得到一行；IM Fell、Shadows、Courier 都完整）。原型對它把字級縮成 0.085／0.12＝0.71 倍（`composer.js:403`），app 沒有逐字型字級（批 4 計劃 §9.5「移植落差」、ACCEPTANCE I-43 已記）。
- F4 暈開＝`ComposedStyle.weepCopies = 3`、`weepStep = 0.1`（每份往下 0.1 字級，最遠 0.3 字級）、`weepAlpha = 0.18`（`ComposedStyle.swift:231-243`）。
- F6 倒影＝效果 `reflect`，`reflectionOffset = 0.95`、`reflectionAlpha = 0.16`（`ComposedStyle.swift:79-80,316-320`）。**不是本批私有**：標籤含 psych／glam／gothic／doom／symphonic／gothmetal，已簽字的舊團 Guns N' Roses、Queen、Pink Floyd（批 1）、Flyleaf、Evanescence（批 3）的候選也含它，另有依曲風抽到它的歌。
- F7 `LayerDraw.streaks`、`Streak`、`rainStreaks`／`rainCount`、`LyricsFXView` 的 `.streaks` 分支只有 rain 在用（grep 已核）。
- F5 雨絲＝背景元件 `rain`（`LyricsFXCatalog.swift:163`，標籤 emo／indieemo），渲染在 `ComposedBackdrop.swift:81`；只有 The Used、My Chemical Romance、Death Cab for Cutie 的候選含 `rain`（`Tests/Fixtures/LyricsFX/b2-batch4-signed.json`）。三團拿掉 rain 後仍各有 ≥ 3 個暗底背景（bluehour、void、spot／bokeh…）。

## 2. 設計
### 2.1 Rock Salt 逐字型字級（只給 Rock Salt）
- `FontFace` 加 `var sizeScale: CGFloat = 1`；目錄裡只有 Rock Salt 設 `0.085 / 0.12`（照原型）。
- 組合畫法每行的 `em` 乘上 `style.face.sizeScale`（原型改的是 `S.size`＝整份樣式的 em，所以字距、散布、殘影等以 em 計的量一起縮，和原型一致）。
- **不**順手補 Anton／Butcherman 的 0.15（原型有、app 沒跟）：那會動到已簽字的舊團畫面，不在本次範圍。

### 2.2 拿掉雨絲
- 先改原型 `composer.js`（刪 rain），再走既有管線重產，**不手編簽字對照檔**（評審 #2）：`check.js --batch 4 --before tools/composer.before-b2-4.js`（預期差異只有三團的 backdrop 少 rain）→ `precheck.js --batch 4`（連帶仍 0）→ `distinct.js` → `export_signed.js --batch 4` 重產 `b2-batch4-signed.json`（`note` 記 2026-10-14 撤掉雨絲）→ `gen_swift.js --batch 4` 核對 Swift 目錄。新舊對照檔的 sha256 記 §9。
- Swift：刪 `rain` 目錄項、`BackdropKind.rain`、`rainStreaks`／`rainCount`，以及只為 rain 存在的 `LayerDraw.streaks`、`Streak`、`.streaks` 繪製分支（評審 #5：不留到不了的正式碼）。
- 這屬於修訂已簽字內容 → ACCEPTANCE I-41／I-43 加 ⚠️ 註記（附原話與日期）。
- 刪掉雨絲專屬的單元測試；新增一條「目錄裡沒有 rain、三團候選不含 rain」防回歸。

### 2.3 暈開減量
- `weepCopies` 3 → **2**、`weepStep` 0.1 → **0.06**（最遠位移 0.3 → 0.12 字級，約原本的 2/5）；`weepAlpha` 不動。連帶效果照實記：副本合計不透明度 0.27 → 0.18（少一份）。使用者若說「太淡」，調的是 `weepAlpha`；說「還是暈」，調的是份數與步距（評審 #6：兩個旋鈕分開）。
- 數值是起點，在真視窗給使用者看；說不對就再調一次（最多兩輪，再不收斂就停下交使用者）。
- 既有測試以常數表達，數值改了自動跟上；`B2BatchFourEffectTests` 裡寫死的部分（若有）一起改。

### 2.4 倒影調淡（使用者 2026-10-14 選 A：全域）
- `reflectionAlpha` 0.16 → 0.08（第 1 輪）→ **0.04**（使用者看過 0.08 後「再淺一些」，第 2 輪看過「這次沒問題了」）；位移 `reflectionOffset` 不動。
- 範圍有兩個選擇（§8）：A＝全域改（所有用倒影的團一起變淡，含舊團 Guns N' Roses、Queen、Pink Floyd、Flyleaf、Evanescence 與依曲風抽到的歌，ACCEPTANCE 記 ⚠️）；B＝只給本批 emo 團變淡（另立一個私有標籤的淡倒影元件 `reflectSoft`，舊團不變，走原型→重產管線）。

### 2.5 驗證矩陣（評審 #1、#4、#8）
- 單元：用 app 的真實 `CoreTextMeasurer` 與 Rock Salt 字型，在 1200×800 畫布排一句長歌詞，斷言每個字的外框（含變換）落在畫布內、且可見 ≥ 2 列；`sizeScale` 加註解說明是字型固有尺寸補償、與批次無關。
- 截圖（-O 建置、密集預覽、內建螢幕全螢幕視窗）：Rock Salt 字不碰工具列與狀態列。
- 目視固定配方（每份約 20 秒、密集預覽）：① Rock Salt＋暈開＋抖動 ② IM Fell＋暈開 ③ Shadows＋暈開 ④ 任一字型＋倒影；之後 7 團各自組合器自抽約 20 秒看整體。
- 每輪調整後都重跑：邊界單元測試、暈開／倒影單元測試、四份固定配方的每幀量測。第二輪只能調 `weepCopies`／`weepStep`／`weepAlpha`／`reflectionAlpha`，不擴範圍。

### 2.6 長句自動縮字（T7 目視第 2 項；/thecure 與 Codex 辯論 2 輪後的單一方案）
- 起因：使用者看 The Used（Permanent Marker、整行大寫）：「歌詞有超出顯示範圍的問題」。密集預覽 126 字元的一句折成 7–8 列，上下兩列被切。
- 根因（已核）：`ComposedStyle.draw` 的 em 只跟高度成正比、`layout` 只按寬度折行，**沒有任何高度限制**（`ComposedStyle.swift:175-181,339-368`）；原型 `lyrics-fx-preview.html:288-299` 也一樣（app 是忠實移植）。實際歌詞也有長句：repo 內 golden fixture 923 句，p50 28／p90 43／p99 58／最長 207 字元，超過 100 字元的 3 句；視窗越窄，越短的句子就會出框（折行看寬度、字級看高度）。
- 設計：
  1. 每句先照原 em 排版；**放得下就完全不變**（與現狀逐位元相同）。
  2. 放不下時，在 [0.5×原 em, 原 em] 之間二分搜尋（8 次），每個候選 em 重新排版，取「放得下的最大 em」。不用一次比例換算（折行列數是離散的，會縮過頭）。
  3. 「放得下」的判定對象＝**主字形**，由純函式 `inkEnvelope` 算出，要落在歌詞區上下各 2% 內的「主字形安全區」。規則（全部取上限、只放大不縮小）：第一列頂＝第一列基線 − ascent×em×(1＋`vary.size`)；最後一列底＝最後一列基線＋descent×em×(1＋`vary.size`)；兩端再各加 (|`vary.dy`|＋|`vary.scatter`|)×em、旋轉餘量 0.5×該句最寬單字寬×sin(`vary.rotation`＋停留模板最大旋轉)、停留模板（`GlyphTemplates` 的 hold：drift／float／breathe／jitter／bob／wobble）的最大位移與 (最大縮放−1)×字高。不碰 GlyphPathCache（plan 端沒有它，且要能用 FixedWidthMeasurer 測）。
  3b. **彈片堆**（`pile`，只有 enter `slam`，標籤 black／death／hardcore／thrash／grind／horrormetal）：詞的錨點按畫布比例散布、不隨 em 走，縮字救不了 → 不縮、照現狀，記為不保證。
  4. 不保證、照實記錄的：淡裝飾（暈開、倒影、影印錯位、RGB 分離、光暈／描邊、勒索信紙片）在最下列之下被切可以接受；進退場的飛入飛出、整屏 shake／thump 不在保證內；比歌詞區還寬的單一長字（例：網址）水平出框不在本次範圍，記為後續。
  5. 縮到下限 0.5 倍仍放不下：就用 0.5 倍畫（不改用單色，演出中途換風格更突兀），OSLog 記一次（同一句、同一字級、同一配方只記一次；只記行號與列數，不記歌詞）。
  6. 不加快取：只有放不下的句子才多排版最多 8 次；layout 只查已快取的字寬、不填字形。是否真的夠輕以 T7 每幀量測為準，超標再議快取。
- 這是**原型逸脱** → ACCEPTANCE 新增一條 ⚠️（I-45），舊團只有原本會出框的長句會變。
- 任務：併入 §5 的 T1b／T2b（見下）。
- 測試：① 放得下的句子 plan 與修正前逐位元相同（含舊團代表配方）；② 長句（含 Permanent Marker 整行大寫、Rock Salt、反射＋暈開配方）在 1728×945 與窄視窗 900×945 下，**用與繪製端相同的仿射變換（旋轉、scaleX／Y）套到真實字形路徑**後，主字形墨跡全在安全區內；③ 207 字元級的極端句縮到下限時的行為；④ 修正既有 `inkSpan` 沒套旋轉的缺口（Codex R2 指出）。

## 3. 非目標
- 不動抖動（jitter）本身：使用者說的是「暈開＋抖動」的疊加，要求只改暈開。
- 不補其他字型的逐字型字級；不處理 Special Elite（批 3 已裁定維持現狀）。
- 不改其他 6 個背景、不另做新背景替代雨絲。

## 4. 驗收標準
- V1 單元測試全綠（全量），`no_playback_gate.sh` 0，覆蓋率閘門過。
- V2 Rock Salt 密集預覽截圖：字不碰工具列與狀態列邊框、可見多行。
- V3 `LyricsFXUITests`＋`LyricsFlowUITests` 全綠（ABC、只接內建螢幕）。
- V4 每幀：`t7-batch4.sh` 的配方去掉 rain（換 bluehour）後重量；門檻 p50 ≤ 2 ms、p95 ≤ 3 ms（使用者既定，評審 #3 不改門檻），超出者停下交使用者裁定；同時列出修正前後的對照（同機、同配方、同視窗），記建置設定、機型、解析度。
- V5 真視窗目視 7 團＋暈開，使用者「對」。

## 5. 任務清單
| # | 內容 | DoD |
|---|---|---|
| T1 | 紅：Rock Salt 邊界測試、目錄無 rain 測試、暈開新常數的份數與位移上限測試、倒影透明度測試 | 跑出紅、摘要記 §9 |
| T2 | 綠：§2.1–§2.4 實作；對照檔與原型同步；`xcodegen generate`（若增刪檔） | T1 轉綠、全量單測綠 |
| T1b | 紅：§2.6 測試 ①–③（真實字形路徑＋繪製端仿射變換）；先修 `inkSpan` 套旋轉（④），確認新判定量得到旋轉 | 跑出紅、摘要記 §9 |
| T2b | 綠：`inkEnvelope`＋二分搜尋；下限記錄；ACCEPTANCE I-45 ⚠️ | T1b 轉綠、全量單測綠 |
| T3 | /simcodex 評審 | 無 P0／P1 |
| T4 | 使用者在場：V2–V5；T2b 後重量四份固定配方的每幀，並請使用者重看 The Used | 結果回填 §9 與批 4 計劃 §9.7 |
| T5 | 文件：ACCEPTANCE I-41（E2E）、I-43（⚠️ 修訂）、I-44 | 狀態改成實際值 |

## 6. 影響面、風險、回退
- 影響面：rain、weep、Rock Salt 只有本批 7 團（emo 私有標籤）；倒影全域變淡（使用者選 A，舊團 Guns N' Roses、Queen、Pink Floyd、Flyleaf、Evanescence 與依曲風抽到的歌一起變），ACCEPTANCE 記 ⚠️；舊 54 團零差異由 `ExistingBandCandidatesTests` 把關。
- 風險：Rock Salt 縮了仍出框 → 截圖驗證，不過就停下報告。暈開減量後使用者仍覺得暈 → 兩輪熔斷。
- 回退：在 `wip/lyrics-fx-b2-batch4-t7` 分支做，`main` 不動直到使用者拍板合併。

## 8. 待拍板
1. ~~倒影調淡的範圍~~ → 使用者 2026-10-14：「A 可以」＝全域變淡（含舊團），其餘三點同意。

## 9. 紀錄（實作時回填）

## 附錄 A　計劃評審記錄
### A.1 R1（gpt-5.6-terra／medium，2026-10-14；無 P0）
| # | Codex 意見 | 裁決 | 落點 |
|---|---|---|---|
| 1 | P1 只驗 `sizeScale` 常數不足以證明不出框；V2 單張截圖不可重跑 | **採納** | §2.5 真實字型的邊界單元測試＋截圖條件寫死 |
| 2 | P1 手編簽字對照檔會掩蓋原型／app／簽字三者漂移 | **採納** | §2.2 改走原型→`check`／`precheck`／`distinct`／`export_signed`／`gen_swift` 重產 |
| 3 | P1 p95 ≤ 3 ms 可能把修正卡住，建議改相對改善幅度 | **駁回（用戶既裁定門檻）、部分採納** | 門檻不改；超標照舊交使用者裁定；加修正前後對照與量測條件記錄 |
| 4 | P1 7 團自抽不保證抽到暈開 | **採納** | §2.5 固定配方矩陣，7 團自抽改為補充 |
| 5 | P2 `.streaks` 等只為 rain 存在，刪了 rain 會留死碼 | **採納** | §2.2 一併刪除（grep 已核只有 rain 用，F7） |
| 6 | P2 透明度連帶下降沒寫明，兩個旋鈕混在一起 | **採納** | §2.3 |
| 7 | P2 `sizeScale` 是字型全域屬性，影響面敘述只是時間點 | **採納** | §2.5 加註解，寫明是字型固有補償 |
| 8 | P2 調參輪次沒定義每輪重跑什麼、能調什麼 | **採納** | §2.5 |
- 合計 8 條：採納 7、駁回並部分採納 1。
### A.2 長句自動縮字辯論（/thecure，2026-10-14）
| # | 論點 | 提出方 | 狀態 | 證據 |
|---|---|---|---|---|
| 1 | 選 A（通用修正）而非 B（只記錄） | 我 | 一致 | golden fixture 長句統計；em 看高、折行看寬 |
| 2 | 一次比例換算會縮過頭，改二分搜尋 | Codex | Codex 勝 | 折行列數離散 |
| 3 | 不加快取，以實測為準 | 我 | 我勝（Codex R2：正しい，附「以 T7 p50／p95 為通過條件」） | layout 不填字形 |
| 4 | 安全區只看主字形，淡裝飾不算 | 我 | 我勝（Codex R2：正しい，要求明文化） | 倒影 0.04、算進去會讓放得下的句子也縮 |
| 5 | 判定只用 ascent／descent 不夠，要加旋轉／停留動作的保守餘量；測試要用繪製端的仿射變換 | Codex | Codex 勝 | 既有 `inkSpan` 沒套 rotation |
| 6 | 下限 0.5、不退單色、OSLog 只記一次 | 我＋Codex | 一致（Codex 補「不可每幀記」） | — |
| 7 | 單一長字水平出框、進退場飛入不保證 | 雙方 | 一致 | — |
| 8 | 整體確認：§2.6 沒接進任務；`inkSpan` 要先修；餘量規則要落到可實作；彈片堆未定義；計劃倒影值過期 | Codex | Codex 勝（全採納） | 已改 §2.4、§2.6、§5 |倒影（§2.4）是評審後使用者新增的要求，範圍屬價值判斷 → §8 交使用者。
