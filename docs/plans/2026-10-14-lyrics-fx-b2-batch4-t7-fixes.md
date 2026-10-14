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
- 起點：`reflectionAlpha` 0.16 → **0.08**（減半）；位移 `reflectionOffset` 不動（使用者要求的是「淡一些」）。
- 範圍有兩個選擇（§8）：A＝全域改（所有用倒影的團一起變淡，含舊團 Guns N' Roses、Queen、Pink Floyd、Flyleaf、Evanescence 與依曲風抽到的歌，ACCEPTANCE 記 ⚠️）；B＝只給本批 emo 團變淡（另立一個私有標籤的淡倒影元件 `reflectSoft`，舊團不變，走原型→重產管線）。

### 2.5 驗證矩陣（評審 #1、#4、#8）
- 單元：用 app 的真實 `CoreTextMeasurer` 與 Rock Salt 字型，在 1200×800 畫布排一句長歌詞，斷言每個字的外框（含變換）落在畫布內、且可見 ≥ 2 列；`sizeScale` 加註解說明是字型固有尺寸補償、與批次無關。
- 截圖（-O 建置、密集預覽、內建螢幕全螢幕視窗）：Rock Salt 字不碰工具列與狀態列。
- 目視固定配方（每份約 20 秒、密集預覽）：① Rock Salt＋暈開＋抖動 ② IM Fell＋暈開 ③ Shadows＋暈開 ④ 任一字型＋倒影；之後 7 團各自組合器自抽約 20 秒看整體。
- 每輪調整後都重跑：邊界單元測試、暈開／倒影單元測試、四份固定配方的每幀量測。第二輪只能調 `weepCopies`／`weepStep`／`weepAlpha`／`reflectionAlpha`，不擴範圍。

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
| T3 | /simcodex 評審 | 無 P0／P1 |
| T4 | 使用者在場：V2–V5 | 結果回填 §9 與批 4 計劃 §9.7 |
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
- 合計 8 條：採納 7、駁回並部分採納 1。倒影（§2.4）是評審後使用者新增的要求，範圍屬價值判斷 → §8 交使用者。
