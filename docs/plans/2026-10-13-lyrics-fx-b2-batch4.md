# Lyrics FX — B2 批 4「按樂團擴充（第四批：emo 群）」實施計劃 v2（計劃評審 R1–R2 已併入，定稿）

母計劃：`docs/plans/2026-10-03-lyrics-fx-mode.md`（§2.10、附錄 B）。批 3：`docs/plans/2026-10-11-lyrics-fx-b2-batch3.md`（下稱「批 3 計劃」）。本檔**重用**批 3 計劃的 §2.4（私有子標籤隔離）、§4（流程、批次命名、基線與連帶、工具調整）、§9（紀錄格式），以及它轉引的批 2 計劃 §4.3（原型約束）、§4.5（別名）、§2.1（預檢與「B2 修復例外」），只寫差異。基線：`main` c6e0a53（v2.0.2，含批 1–3）。

## 0. 複述
- 目標＝讓 emo 群（The Used／My Chemical Romance 為核心，簽字對象 ≤ 12 個）在歌詞特效裡得到使用者簽字的組合風格；立 emo 私有子標籤；批 2 已簽的流行龐克團（Fall Out Boy、Mayday Parade 等）零連帶。
- 完成標準＝§5 V1–V7 全過。
- 不做＝§3 非目標。
- 模式（/fatboyslim Phase 0）：**normal**。每輪收斂靠使用者看探針與在場授權，loop 換不掉這個等待。
- 任務形狀：**串行**（T4–T6 的排他書寫集合重疊：`LyricsFXCatalog.swift`、`ComposedStyle.swift`、`GlyphTemplates.swift`），不派實作子 agent。

## 1. 已核事實（2026-10-13）
- F1 分支：本機 `wip/lyrics-fx-b2-batch4`，自 `main` c6e0a53 開出（工作樹只有既有的未追蹤檔）。
- F2 曲庫（iTunesLibrary 框架唯讀匯出；Music 當時由使用者開著，本工作沒有啟動、也沒有對它送任何 Apple Event；原始資料只在 session 暫存目錄）：12,234 首、481 個樂團；覆寫表 54 團＋5 個別名涵蓋 4,882 首＝39.9%（＝批 3 的 3,960＋922）。播放次數全庫合計 394、近 90 天播過 206 首（樣本小）。
- F3 **基線已在 c6e0a53 重產（使用者指定的開工前步驟）**：`TEST_RUNNER_AZW_PRINT_FX_BASELINE=c6e0a53 xcodebuild test … -derivedDataPath /private/tmp/azw-dd.* -only-testing:"AzathothsWhisperTests/ExistingBandCandidatesTests/printTheBaseline()"`，TEST SUCCEEDED；兩個標記之間的原文 sha256 `df366e24a69ee330b005e8c4ef42c1af17563c8d7423c697897e3eb8feb40d5c`（42,147 bytes，暫存在 session 目錄 `baseline-raw.json`）。內容：54 團；mono 5 團（Rammstein、The Chemical Brothers、Fatboy Slim、Daft Punk、Aphex Twin——Korn 已因批 3 變成組合）；與 repo 內 c55b32b 基線比，有差異的正好是批 3 簽「新版」的 Korn、Hatebreed，另多出批 3 的 10 個新團，其餘 42 團零差異——與批 3 §9.5 一致。**尚未寫進 repo**：換基線會讓現行測試紅（`sourceRevision == "c55b32b"`），所以與測試改動同一步做（T1）。
- F4 測試裡寫死批次的地方（`grep` 已核，`ExistingBandCandidatesTests.swift`）：`:78` `sourceRevision == "c55b32b"`；`:79` 基線團名＝`batchOne + batchTwo + batchThree`；`:110` `batchesAfterTheBaseline = [3]`；`:115`「不得列為連帶」＝`batchTwo + batchThree`；`:123` `linked ∩ batchFour = ∅`。另：`ArtistOverrideTableTests:80` 迭代到 `batchFour`；`LyricsFXContrastTests:125` `batchThree + batchFour`。共用 helper `SignedBatchFile.load(batch:)`／`linkedBands(batches:)`／`SignedBatchChecks` 可直接用。
- F5 工具（`docs/plans/2026-10-03-lyrics-fx-assets/tools/`，未追蹤、還在）：`lib.js`、`check.js`、`need.js`、`precheck.js`、`export_signed.js`、`gen_swift.js`、`build_page.js`（已吃 `--precheck`）、`patch_b2_3.py`、`t7-batch1.sh`，皆吃 `--batch <n>`。原型 `composer.js` 有 54 個 TARGETS（＝app 覆寫表）；Korn、Hatebreed 還帶著批 3 的 `linked:true, batch:3`（不影響 `--batch 4`）。
- F6 原型裡沒有任何 `emo`／post-hardcore 標籤的元件或樂團（批 3 計劃 F6 的表，本次重核 TARGETS 清單一致）。與 emo 群視覺上相鄰、可「同掛」本批私有標籤的既有 app 元件（例）：字型 Elite、Marker、Gochi、Grotesk、Rubik、Oswald、CormorantIt；背景 film、xerox、gig、haze、bokeh、paper、tapeLeak；進場 fadeUp、ease、slide、stamp、punch、tumble；退場 up、drift、fade、fall、rip、cut；效果 jitter、wobble、breathe、shake、thump、speedlines、tilt；配色 mono、gigRed、mallPink、polaroid、bloodBlack、parka。
- F7 曲庫裡 emo 群的範圍（實際寫法各 1 種，無大小寫變體）：The Used、Death Cab for Cutie、My Chemical Romance、A Day to Remember、New Found Glory、You Me At Six、The Story So Far，合計 **438 首＝3.6%**、播放 24 次；另有合作寫法 `The Used & My Chemical Romance` 1 首。曲庫裡沒有其他 emo／post-hardcore 團（已用約 100 個團名關鍵字比對；Bullet For My Valentine、Asking Alexandria 屬金屬核，留給那一群）。帶 `emo-rock` 曲風的只有 The Used（部分）與已入表的 Mayday Parade。
- F8 既有硬規則照舊（母計劃附錄 B P1–P15）。與本批最相關：P14「勒索信只給 77 龐克與流行龐克」、P15「已代表某一群的元件不借給別群」（Catacombs／negative 的前例）、批 1「背景只用光與質感，不畫結構性裝飾」、不得撒紅點當血。

## 2. 設計
### 2.1 簽字對象：新 7 團＋連帶 0＝7 個（≤ 12）
- 新 7 團：The Used、My Chemical Romance（核心）、Death Cab for Cutie、A Day to Remember、New Found Glory、You Me At Six、The Story So Far。
- 連帶舊團：**計劃為 0**（由規則 E1 與預檢證明；不是 0 就停下回報，不帶著連帶進探針）。
- 合作寫法 `The Used & My Chemical Romance`（1 首）：照批 2 §4.5 預設**不歸任何一團**、記 `unassigned`；探針頁上列出，使用者指定歸屬時才加別名。
- 不為了湊滿 12 個而加團（假設：上限是上限，不是目標）。

### 2.2 規則 E1：本批新團只帶本批私有子標籤（批 3 N1 的同型）
- 7 個新團的標籤與**所有既有團用過的標籤**不相交（尤其不帶 `poppunk`、`poprock`、`punk`、`skatepunk`、`melodichc`、`indie`、`powerpop`、`hardcore`、`gothic`）。
- 新元件只帶本批私有標籤（`gen_swift.js:6` 的 `allowed`＝本批各團標籤扣掉其他團也有的；E1 下＝全部私有標籤，且不含任何既有團的標籤）。既有元件**可以**再補本批私有標籤（同掛）：既有團不帶這些標籤，合格集合不變。
- 效果：既有 54 團的合格集合與可抽空間機械性零差異（含批 2 的 Fall Out Boy、Mayday Parade、Good Charlotte 與連帶過的 Blink-182、Green Day、Sum 41）。Mayday Parade 曲庫雖有 emo-rock，目標值凍結、不補 emo 標籤。
- 為什麼不讓 New Found Glory 等直接帶 `poppunk`：帶了就等於把它們綁在流行龐克群的元件池上——日後任何一批替流行龐克加元件，它們都會變成連帶團；而且會抽到 P14 專給流行龐克的勒索信。用私有標籤逐一挑要共用的既有元件，控制力較好。

### 2.3 私有子標籤（草案，定名與歸屬在 T2；使用者指定要有 `emo`）
| 標籤 | 意思 | 團（草案） |
|---|---|---|
| `emo` | 核心：日記手寫、黑＋一個強調色、破碎與戲劇 | The Used、My Chemical Romance |
| `posthardcore` | 尖叫／斷裂、硬切、髒 | The Used、A Day to Remember |
| `indieemo` | 安靜、細、冷藍灰、慢 | Death Cab for Cutie |
| `emopop` | 快、亮、直接（不含勒索信） | New Found Glory、You Me At Six、The Story So Far、A Day to Remember |
- 對照組（T6 測試用）：My Chemical Romance（戲劇、黑紅）vs The Story So Far（快、粗、乾）；The Used（破碎、尖叫）vs Death Cab for Cutie（安靜、細）。
- 已知風險（批 3「切太粗」的同型）：New Found Glory／You Me At Six／The Story So Far 共用 `emopop`，候選幾乎相同、只靠十軸分——交給探針判斷，必要時像 Ill Niño 那樣另立標籤。My Chemical Romance 的戲劇性靠軸（theatrical 高）與 `req` 門檻，不夠再立標籤。
- Swift：`FXTag` 新增上述 case（純加法）；另立 `FXTag.emoFamily`（本批私有標籤集合）供測試共用。不進 `nuFamily`。`FXTag` 的註解與本檔明示：這幾個是 **B2 批 4 私有**標籤（`posthardcore`、`emopop` 看起來像一般曲風名，但不是公共曲風標籤）；日後的團要重用，得重走連帶預檢、簽字與基線流程（評審 R1 #10）。
- 同標籤團的耦合（評審 R1 #6）：The Used（`emo`＋`posthardcore`）與 A Day to Remember（`posthardcore`＋`emopop`）把兩個池接在一起。T2 要出「同標籤團區分度報表」——每一對團六槽裡前 5 名完全相同的槽數；六槽全同的團對在探針頁明列給使用者判斷（要不要另立專屬標籤）。

### 2.4 新元件方向（草案；實際清單由 T2 的 `need.js` 定，逐項進探針）
- 字型（只收 google/fonts 官方庫 OFL／Apache 2.0、無軸或只有 wght；逐枚查證後才進原型）：手寫／塗鴉一枚（The Used、MCR 的日記感）、舊式襯線一枚（MCR 的喪禮／行進樂隊感）、細的無襯線或等寬一枚（Death Cab for Cutie）。
- 背景（只用光與質感）：雨絲／濕玻璃、單一冷色街燈光暈、褪色相紙。
- 進場／退場：手寫般逐字顯出、墨水暈開後淡掉。
- 效果：刪除線（寫了又劃掉；**不是**サビ／關鍵字觸發型，否則 B2 的團抽不到）、墨暈。
- 配色：黑＋血紅＋白（MCR）、黑＋桃紅（2000 年代 emo；與既有 `mallPink` 重疊時直接同掛、不新做）、灰藍＋奶油（Death Cab for Cutie）、黑白＋一點舊黃。
- 每個新 Swift case 都要有定點測試（T4）；新元件 id 先查不與任何槽既有 id 撞名。P15 的規則反向適用：不拿黑金屬（Catacombs、negative）、工業、77 龐克勒索信的專屬元件來同掛。

### 2.5 流程（使用者指定的順序）
原型補目標值與元件（`tools/patch_b2_4.py`，由 `tools/*.before-b2-4.*` 重建、可重跑）→ `check.js --batch 4 --before tools/composer.before-b2-4.js`（不帶 `--linked`）→ `precheck.js --batch 4 --json tools/precheck-b2-4.json` 預檢連帶 → `build_page.js --precheck …`（工具小改，評審 R1 #2：`precheck.js` 的 JSON 加 `leak`、`batch`、兩個原型檔的 sha256；`build_page.js` 驗 `leak === 0`、批次與雜湊相符才注入；`gen_swift.js` 遇到新元件過濾後標籤為空就失敗）→ 本機探針頁（`open` 本機 HTML，寫清楚看什麼、怎麼回「對／不對＋一句」；每條回饋轉成母計劃附錄 B 的 P16 起；最多三輪不收斂即熔斷）→ 簽字 → `export_signed.js --batch 4` → `gen_swift.js --batch 4`（只帶本批專屬標籤）→ 簽字對照檔測試 → T7。

### 2.6 批次命名（沿用差一的遺留，不改名）
- 原型 TARGETS：本批的團標 `b2:true, batch:4`。
- Swift：新增 `SongProfileResolver.batchFive`（doc 註解寫明＝B2 批 4），`bandTable = batchOne + … + batchFive`。
- 對照檔 `Tests/Fixtures/LyricsFX/b2-batch4-signed.json`（`bands`、`linked: []`、`unassigned`）；測試 `Tests/LyricsFX/B2BatchFourTests.swift`（suite `B2BatchFourSignedFixtureTests`、`B2BatchFourIsolationTests`、`B2BatchFourContrastTests`）。

### 2.7 基線與測試推進（F4 各處就地改，不重構 batchN 清單）
- `band-candidates-baseline.json` 換成 F3 的輸出（同批 3 的排版規則 `json.dumps(indent=1, sort_keys=True, ensure_ascii=False)`；正規化後 sha256 記 §9）。
- `:78` 改 `"c6e0a53"`；`:79` 加 `batchFour`；`:110` 改 `[4]`；`:115` 加 `batchFour`；`:123` 改 `batchFive`。`ArtistOverrideTableTests:80`、`LyricsFXContrastTests:125` 各加 `batchFive`（後者的測試名不改，ACCEPTANCE 有引用）。
- 新增 E1 的機械保證（`B2BatchFourIsolationTests`）：
  1. `batchFive` 每團的標籤 ⊆ `FXTag.emoFamily`。
  2. `batchOne…batchFour` 沒有任何團帶 `emoFamily` 的標籤。
  3. 對照檔 `linked` 為空；且（已由 `existingBandsOnlyChangeWhereTheUserSignedIt` 涵蓋）54 個既有團相對 c6e0a53 基線零差異。
  4. `batchFive` 每團 `Composer.fit > 0` 的候選裡，沒有 id 為 `ransom`／`ransomPop` 的元件（P14），也沒有帶 `.industrial` 標籤的元件。
  5. **新元件只帶私有標籤**（評審 R1 #1）：目錄裡 (槽, id) 不在 c6e0a53 基線 54 團合格集合聯集裡的＝本批新元件（已核：基線聯集正好涵蓋現行目錄全部 148 個，沒有不可達的舊元件），每一個的標籤必須非空且 ⊆ `emoFamily`——擋掉「新元件沒標籤＝人人可抽」與「新元件誤帶舊標籤」。
  6. 每個本批新元件至少出現在一個 `batchFive` 團的合格集合裡（評審 R2 #9；不留抽不到的死元件）。
- 對照檔測試（`B2BatchFourSignedFixtureTests`，沿用批 3 的五條）：`batchFive` 團名集合與對照檔 `bands` **雙向相等**（不寫死團數，探針可能增減）；每槽合格集合相等；`unassigned` 的寫法不命中覆寫表；簽字對象不重複且 ≤ 12。
- `SignedBatchFile.linkedBands` 對還沒簽的批次會略過缺檔（`SignedBatchFixture.swift:65`，刻意的）：T1–T3 期間 `ExistingBandCandidatesTests` 會綠，對照檔的存在由 `B2BatchFourSignedFixtureTests` 直接 `load` 把關——單獨跑前者不代表對照檔在（評審 R1 #3）。

## 3. 目標與非目標
- 目標：emo 群從原型設計到 app 交付；基線換成 c6e0a53；測試的批次參照由「批 3」推進到「批 4」。
- 非目標（使用者指定＋沿用批 3）：
  - **C 段**（外部時間軸）；`GenreStyleResolver` 的「**ロック→日本語系**」誤判；**Special Elite 點陣快取**（字形點陣快取）；**測試裡 batchN 清單的重構**；サビ／關鍵字效果；Settings 手調；Cover Flow；Python 舊版；金屬核等其他群。
  - **契約凍結**（批 1 計劃 §3.4）不動：六槽與 kind 語意、`FXTag` 匹配規則、十軸、聚合算法、fit 不平方、排除上次、無候選退 mono。只做純加法（新標籤、新 case、新配色、新字型）。本批預期用不到「B2 修復例外」。
  - 不改任何已簽字團（B1、批 1–3）的目標值與合格集合。
  - commit／合併／push：等使用者拍板（wip/ checkpoint 例外，不 push）。

## 4. 驗收標準（每條可判定）
- V1 本批每一團歸屬的所有曲庫寫法 100% 命中覆寫表（離線比對報表記進 §9）；`unassigned` 的寫法不命中；`ArtistOverrideTableTests.everyNameAndAliasNormalizesToAUniqueKey` 綠。
- V2 本批每團六槽每槽 ≥ 2 個合格候選（`bandsAddedFromB2On…` 迭代含 `batchFive`）。
- V3 app 每槽合格集合與 `b2-batch4-signed.json` 完全一致；`batchFive` 團名集合＝對照檔（`B2BatchFourSignedFixtureTests`）。
- V4 既有 54 團相對 c6e0a53 基線零差異（合格集合與可抽空間）；對照檔 `linked` 為空；批 1–3 的 26 個新團不在 `linked`；2,000 種子煙霧測試無漏；§2.7 的 E1 四條綠。
- V5 對比：`mainTextStaysReadableOnEveryReachableBackdrop`、`everyPlayablePairStaysReadable` 照跑（≥ 4.5，crimsonVelvet 例外不擴大）；`batchThreeNeverFallsBack…` 迭代含 `batchFive`。
- V6 全量單元的失敗集合 ⊆ T0 在 c6e0a53 記錄的基線（完整識別名與斷言數），無新增；`CoverFlowSlideGeometryTests` 的 swipeAway 3 條時好時壞（已熔斷，使用者既裁定不算新增的紅；照實記錄每次結果，不跳過、不放寬）；skip 清單同 T0；`no_playback_gate.sh` 0；`coverage_gate.sh <單元 xcresult>` Services+Infra ≥ 80%；`Scripts` Python 測試綠。
- V7 使用者在場：`LyricsFXUITests`＋`LyricsFlowUITests` 全綠（含本批一團的新條）；新字型、新效果、新背景各一份配方的每幀 p50 ≤ 2 ms、p95 ≤ 3 ms（或使用者明示豁免）；真視窗目視表態原話記 §9。

## 5. 任務清單（TDD：先紅後綠；紅燈摘要回填 §9）
| # | 任務 | DoD | 依賴 |
|---|---|---|---|
| T0 | 全量單元基線（c6e0a53） | 失敗集合與 skip 清單（完整名稱）記 §9；`check.js --batch 3`：批 3 十團與 `b2-batch3-signed.json` 逐槽差異 0（工具與原型沒走樣） | — |
| T1 | 基線換成 c6e0a53＋測試推進到批 4 | 先寫 `B2BatchFourTests`、各處 `batchFive` 迭代、`FXTag.emoFamily` 的引用 → 編譯紅（摘要記 §9）；加空的 `batchFive` 與空的 `emoFamily` 後：換基線檔＋§2.7 各處，`ExistingBandCandidatesTests` 綠，只剩讀不到 `b2-batch4-signed.json` 的預期紅 | T0 |
| T2 | 原型設計 | 批 2 §4.3 約束全過（`check.js --batch 4 --before …` OK、未預期 0）；7 團每槽 ≥ 2；E1 標籤隔離矩陣（新團 × 既有團標籤＝空）；同標籤團區分度報表；`need.js --batch 4` 清單；字型授權表；元件 id 無撞名 | T1 |
| T3 | 預檢＋探針＋簽字 | `precheck.js --batch 4` 外溢 0、簽字對象（連帶）0；本機探針頁（每團多抽幾組、對照組並排、列出合作寫法的歸屬問題）；簽字或熔斷記錄；命中率 100%；匯出 `b2-batch4-signed.json` | T2 |
| T4 | 新模板／背景／效果 | 每個新的繪製行為（新 Swift case）一條定點測試，先紅後綠；不是新 case 的元件（字型、配色、同掛）由對照檔測試、§2.7 第 6 條、`everyCatalogFontIsRegistered`／`eachBundledFontShipsWithItsLicence`、對比測試涵蓋 | T3 |
| T5 | 目錄＋字型＋覆寫表 | `gen_swift.js --batch 4` 產生元件列；app 算出與基線不同的既有團＝空（多出＝停、回 T2）；字型與授權入 `Resources/Fonts`、`xcodegen generate`（逐檔 `git add`，「 2／3.xcodeproj」副本不動）；T1 的紅轉綠；About、三語 README 字型清單 | T3、T4 |
| T6 | 端到端 | `B2BatchFourContrastTests` 依簽字結果填具體元件；UI 測試新增一條（`testASignedEmoBandGetsItsComposedStyleRegardlessOfGenre`）；建置成功 | T5 |
| T7 | 使用者在場 | UI 測試實跑（ABC 輸入法、只接內建螢幕）；每幀量測；真視窗目視 | T6 |
| T8 | 文件 | ACCEPTANCE I 段（I-41 起：本批簽字、動作與效果、E1 隔離、每幀；I-35 的基線改指 c6e0a53）；母計劃附錄 B P16…；本檔 §9 | T3–T7 |
之後：Phase 3 `/simcodex` → 全量測試 → 證據包；commit／合併等使用者拍板。

## 6. 測試策略
同批 3 §7：單元（T1、T4、T5、T6）、集成（對照檔、對比離屏渲染）、E2E（UI 測試一條新增＋兩組照跑；使用者在場）、閘門（`no_playback_gate.sh`、選擇器白名單、`coverage_gate.sh <單元 xcresult>`、`Scripts` Python）。測試字串一律自編。全量單元照例 skip `AzathothsWhisperTests/BatchOverlappingLoadTests/overlappingLoadSuspendsPollingUntilLastCompletes()`（完整名稱＋括號）。

## 7. 影響面、風險、回退
- 改檔：`SongProfileResolver.swift`、`LyricsFXCatalog.swift`／`FXComponent.swift`、`ComposedStyle`／`ComposedBackdrop`／`GlyphTemplates`／`LyricsFXFrame`（視新 case 而定）、`Resources/Fonts/*`、`.xcodeproj`、About、三語 README、`ACCEPTANCE.md`、母計劃附錄 B、`Tests/LyricsFX/*`（新增 `B2BatchFourTests.swift` 等；就地改 `ExistingBandCandidatesTests`、`ArtistOverrideTableTests`、`LyricsFXContrastTests`）、`Tests/Fixtures/LyricsFX/{band-candidates-baseline,b2-batch4-signed}.json`、`UITests/LyricsFXUITests.swift`。不改 Music 讀取、`NowPlayingMonitor`、`GenreStyleResolver`、Cover Flow、Python 舊版。
- 風險：R1 emo 視覺語言全從零，探針不收斂 → 三輪熔斷；R2 既有團被連帶 → E1＋預檢外溢 0＋基線零差異測試（三道）；R3 字型授權 → 只收 google/fonts 官方庫、逐枚查；R4 個人資料進 repo → 曲庫資料只在暫存目錄，repo 只有樂團名、目標值、元件代號，本檔只寫群總數；R5 `emopop` 三團太像 → 探針判斷、必要時另立標籤；R6 xcodegen 副本 → 逐檔 `git add`；R7 新效果每幀超標 → T7 量測，超標先修、修不了請使用者裁定。
- 回退：未簽字＝不進表；整批在本機 `wip/lyrics-fx-b2-batch4`，checkpoint 不 push、不併回。

## 8. 待拍板
無（計劃評審沒有留下要使用者裁定的價值判斷）。合作寫法的歸屬在探針時問。

## 9. 紅燈摘要／量測／探針記錄（實作時回填）
### 9.0 開工前（2026-10-13）
- 分支與基線重產：見 F1、F3。曲庫統計：見 F2、F7。

### 9.1 T0（2026-10-13，c6e0a53 原始碼）
- 全量單元（`-only-testing:AzathothsWhisperTests`、skip `AzathothsWhisperTests/BatchOverlappingLoadTests/overlappingLoadSuspendsPollingUntilLastCompletes()`、超時 120、`-enableCodeCoverage YES`）：**1217 tests／148 suites，0 issues**（`CoverFlowSlideGeometryTests` 的 swipeAway 3 條這次是綠的；它們時好時壞，已熔斷）。
- 工具：`check.js --batch 3` 與 `b2-batch3-signed.json` 逐槽差異 0；`need.js --batch 3` 要新做 0。

### 9.2 T1（2026-10-13）
- **紅**：新增 `B2BatchFourTests.swift`、推進 F4 各處後 `xcodegen generate`＋`build-for-testing` 編譯失敗——`type 'SongProfileResolver' has no member 'batchFive'`、`type 'FXTag' has no member 'emoFamily'`。
- 基線檔換成 F3 的輸出（先驗證 `json.dumps(indent=1, sort_keys=True, ensure_ascii=False)` 能逐位元重現舊檔，再用同規則寫新檔），正規化後 sha256 `fe43945a0207f944cc9908f70b33802eb1ed42f968013d457144934703ce7158`（74,514 bytes）。
- **綠**：加空的 `batchFive`、空的 `FXTag.emoFamily` 後，跑 `ExistingBandCandidatesTests`、`PlayableSpaceTests`、`ArtistOverrideTableTests`、`LyricsFXContrastTests`、`ComposerTests`、`B2SignedFixtureTests`、`B2BatchTwoSignedFixtureTests`、`B2BatchThreeSignedFixtureTests`、`B2BatchThreeIndustrialBoundaryTests`、`B2BatchFourSignedFixtureTests`、`B2BatchFourIsolationTests`：51 tests，紅只有 `B2BatchFourSignedFixtureTests` 的 5 條（`b2-batch4-signed.json` 簽字後才匯出，預期的紅）。

### 9.3 T2 原型＋預檢（2026-10-13）
- 原型由 `tools/patch_b2_4.py` 從 `tools/*.before-b2-4.*` 重建；本機探針頁 `lyrics-fx-preview-local.html`（v18）。
- 私有標籤 4 個：`emo`（The Used、My Chemical Romance）、`posthardcore`（The Used、A Day to Remember）、`indieemo`（Death Cab for Cutie）、`emopop`（A Day to Remember、New Found Glory、You Me At Six、The Story So Far）。7 團與既有 54 團的標籤交集全空。
- `check.js --batch 4 --before tools/composer.before-b2-4.js`：**OK**。既有 54 團合格集合變動 0；7 團每槽合格數最少 2（My Chemical Romance 的退場）；400 次實抽 0 筆亮暗違規。
- `precheck.js --batch 4`：本批專屬標籤＝上述 4 個；外溢到既有團 0；簽字對象（連帶）0。工具已照評審 R1 #1、#2 小改（預檢 JSON 帶 `batch`／`leak`／兩個原型檔雜湊，`build_page.js` 驗證；`gen_swift.js` 新元件空標籤即失敗）。
- `need.js --batch 4`：合格元件 71，app 已有 56，**要新做 15**：字型 RockSalt（Rock Salt，Apache 2.0）、IMFell（IM Fell English SC，OFL）、CourierPrime（OFL）、ShadowsLight（Shadows Into Light，OFL）——四枚都在 google/fonts 官方庫、靜態檔（`gh api` 已查目錄）；背景 rain、bluehour；進場 scrawl、lurch；退場 sink、wither；效果 weep；配色 revenge、parade、bruise、overcast。其中只有背景 rain／bluehour 與效果 weep 要新增 Swift case（進退場是既有動作基元的新配比）。
- 沒採用的草案：刪除線效果（P3「禁止串字線」的精神，不冒險）；Special Elite 不同掛（T7 量到它慢，不再擴大使用面）；Reenie Beanie（筆畫太細，對比風險）。
- 區分度報表（`tools/distinct.js --batch 4`）：沒有任何一對團六槽前 5 名全同。最像的是 New Found Glory × You Me At Six（進場、效果兩槽前 5 名相同，其餘各槽重疊 4／5）；`emopop` 三團彼此各槽重疊約 4／5——探針頁請使用者特別比這三團。
- 元件 id 撞名：無新增（既有的 `steel` 背景／配色同名不在 app 內）。
- 探針頁自測（無頭 Chrome 開本機檔；Chrome 擴充當時沒連上）：7 個團各抽 14 組、每組 7 個時刻重繪，繪製錯誤 0、必選槽無候選 0；4 枚新字型都有載入；連帶按鈕 0 個。另截了 4 張定格自己看過（IM Fell＋雨絲＋暈開、Rock Salt＋雨絲、Courier Prime＋藍調時刻）。未做：人眼看動態。

### 9.4 T3 探針回饋與簽字
- **P16（2026-10-13，本機探針頁 v18）**：使用者：「沒問題」→ 7 個新團簽字，一輪收斂、沒有修改意見。
- 合作寫法 `The Used & My Chemical Romance`（1 首）：探針頁與回覆裡都問了歸屬，使用者沒有指定；**我方解讀**為採用事先說明的預設「不指定＝不歸任何一團、照舊走曲風」，對照檔 `unassigned[].reason` 照實記下。使用者之後要指定，再加別名。
- `emopop` 三團（New Found Glory、You Me At Six、The Story So Far）很像這件事已在回覆裡點名請使用者比，沒有收到要另立標籤的意見。
- 命中率：7 團的曲庫寫法各 1 種、全部命中（438 首）；相關字樣但未命中的只有上述合作寫法（已列 `unassigned`）。
- 匯出 `b2-batch4-signed.json`（`bands` 7、`linked` 0、`unassigned` 1）；`check.js --batch 4` 與對照檔逐槽差異 0。

### 9.5 T4–T6、T8（2026-10-13）
- **紅**：T4／T6 測試先寫（`B2BatchFourEffectTests.swift`），編譯失敗——`BackdropKind` 無 `rain`／`bluehour`、`LayerDraw` 無 `streaks`、`ComposedStyle` 無 `weepAmount`／`weepCopies`／`weepStep`、`FXTag` 無 `emo`。
- 實作：
  - 4 個 FXTag＋`FXTag.emoFamily`；背景 rain（新圖層型別 `LayerDraw.streaks`：一批 1 點寬的斜線）、bluehour；效果 weep（副本另收成三層、行尾一次接上，繪製端每層只填一次）。
  - `gen_swift.js --batch 4` 產生 15 個元件列，另替 54 個既有元件補本批私有標籤（套用腳本在 session 暫存目錄 `apply_b2_4.py`）。
  - 字型 Rock Salt（Apache 2.0）、IM Fell English SC、Courier Prime Bold、Shadows Into Light（OFL）與授權檔進 `Resources/Fonts`（google/fonts 官方庫的靜態檔，`fc-scan` 讀到非可變字型）。CoreText 的家族名是 `IM FELL English SC`（FELL 全大寫），目錄照實寫。
  - `batchFive` 7 團由對照檔（＝原型 TARGETS）產生。
- 移植落差（照實記）：原型對 Rock Salt 把字級縮成 0.085／0.12；app 沒有逐字型字級（既有的 Anton、Butcherman 在原型裡放大，app 也沒跟），Rock Salt 在 app 裡照統一字級畫、會比探針頁大並多折行——T7 真視窗請使用者看。
- 測試修正（不是放寬）：`weepTrailsThreeFadingCopiesBelowEachSettledGlyph` 第一版假設取樣時每個字都已停滿，實際上字照行長分散出現（最後一個字到行尾前才出來，量到它只拉開 0.75）；改成逐字驗「三份等距、越下越淡、第一份不超過 0.1 字級」，另驗過半的字已拉到最開。實作沒有因此改動。
- 連帶：app 算出與 c6e0a53 基線不同的既有團＝空（`existingBandsOnlyChangeWhereTheUserSignedIt` 綠）。
- 新增測試：`B2BatchFourSignedFixtureTests`（5）、`B2BatchFourIsolationTests`（5）、`B2BatchFourEffectTests`（5）、`B2BatchFourContrastTests`（3）；UI 測試 `testASignedEmoBandGetsItsComposedStyleRegardlessOfGenre`（未跑，T7）。相關 16 個 suite 69 條綠。
- T8：ACCEPTANCE I-26（字型）、I-35（基線改為 c6e0a53）、新增 I-41–I-44；三語 README 字型授權表；母計劃附錄 B P16。

### 9.6 Phase 3 評審（/simcodex，2026-10-13；R2 提前結束）
- 評審前全量單元：1235 tests／152 suites，0 issues；`no_playback_gate.sh` 0；`coverage_gate.sh <全量 xcresult>` Services+Infra 96.2%；`Scripts` Python 333 條 OK。
| 輪 | 來源 | 採納並修 | 駁回／延後（理由） |
|---|---|---|---|
| R1 | simplify：高度／簡化／重用（三個視角都點到） | 暈開的副本原本在 `emit` 外面產生、手抄了 `emit` 的分支條件（還夾一個會跳過迴圈尾的 `continue`）→ 併進 `emit` 的本體分支，條件只留一處；逐層透明度收成 `weepOpacity(level:)`，測試共用 | — |
| R1 | simplify：效率 | 暈開＋燭火閃爍同抽時（My Chemical Romance 抽得到），每字透明度各自擺動，副本的量化階逐字交錯、填色次數會隨字數增加 → 整行副本照量化階排在一起（`groupedByOpacityLevel`），填色次數＝出現的階數；新增測試 `weepStaysAFewFillsEvenWhenEveryGlyphFlickersOnItsOwn` | 雨絲每幀重建 70 段、藍調時刻的漸層填滿全畫布、每行多配置一個陣列：量級在微秒以下，P2 不改 |
| R1 | simplify：高度 | 隔離測試用「不在基線聯集」認新元件，下一批換基線後會變空集合而空轉仍綠 → 加「找不到新元件即紅」與退役說明 | `.scratches` 併成 `.streaks` 的特例：會動到 film 既有測試期望，P2 延後；`FXTag.emoFamily` 只有測試在用：留在正式碼當規格宣告（與 `nuFamily` 並列），P2 不改 |
| R1 | simplify：簡化／重用 | — | `drawn(_:)`、`plan()` 與批 2／批 3 測試檔各有一份：要收斂得動舊批的測試檔，沿用批 3 的延後決定（P2）；對照檔 `load(batch: 4)` 重複 5 次、雨絲一條測試驗四件事：P2 |
| R1 | codex review（--uncommitted） | 無正確性問題 | P2「`.claude/` 本機設定與『 2／3.xcodeproj』舊副本不要 commit」：本來就不 add；刪除要先問使用者（既有慣例） |
| R2 | 自評（只看 R1 的修正，約 40 行）＋codex review | 無（Codex：「No discrete correctness issues」） | — |
- 無安全敏感改動（無認證、無網路、無新的執行期檔案寫入；字型是一次性下載進 repo），未派 security-reviewer。
- 評審後全量：**1236 tests／152 suites，0 issues**（比 T0 多 19 條＝本批新增）；`no_playback_gate.sh` 0；覆蓋率 96.2%；Python 333 條 OK。

### 9.7 使用者在場
（待做：UI 測試實跑、每幀量測、真視窗目視）

## 附錄 A　計劃評審記錄
### A.1 R1（gpt-5.6-terra／medium，2026-10-13；無 P0）
| # | Codex 意見 | 裁決 | 落點 |
|---|---|---|---|
| 1 | P1 新元件若沒標籤＝人人可抽，繞過 E1；建議建新元件 ID 清單 | **修改採納** | 不建清單：用基線聯集認出新元件（已核聯集＝目錄全部 148 個）→ §2.7 第 5 條；`gen_swift.js` 空標籤即失敗 |
| 2 | P1 連帶 0 時預檢「形式上通過」，探針頁可能吃到過期的預檢 JSON | **採納** | §2.5：JSON 加 `leak`／`batch`／雜湊，`build_page.js` 驗證 |
| 3 | P1 `linkedBands` 缺檔略過→ `ExistingBandCandidatesTests` 假綠 | **駁回**（Codex R2 同意） | 刻意設計（`SignedBatchFixture.swift:65`）；存在性由 `B2BatchFourSignedFixtureTests` 把關。Codex 補充「單獨跑前者會綠」屬實，已寫進 §2.7 |
| 4 | P1 表與對照檔的雙向完整性沒寫死 | **採納** | §2.7（不寫死 7 團） |
| 5 | P1 沒驗證目錄的新增／同掛操作；建議 tag-delta fixture | **駁回**（Codex R2 同意） | 既有 54 團的完整合格集合＋可抽空間比對已抓到所有可觀察變化；靜態面由 #1 的測試補上；再加 fixture＝同一語義兩處定義 |
| 6 | P2 The Used／ADTR 把兩個池接在一起 | **修改採納** | §2.3：T2 出區分度報表，六槽全同的團對在探針明列 |
| 7 | P2 不帶 `poppunk` 的取捨合理，但缺防回歸測試 | **採納（Codex 勝）** | 標籤不相交已由 §2.7 第 1、2 條蘊含；我原稿漏了 `ransomPop`，已補進第 4 條 |
| 8 | P2 「industrial 元件」「P10 的一般化」措辭不精確 | **採納** | §2.7 第 4 條改成可判定的定義 |
| 9 | P2 只測新 Swift case 不夠；建議每個新元件一條定點可達測試 | **修改採納** | 不逐元件寫；加一條聚合測試（§2.7 第 6 條，Codex R2 提的形式）；T4 說明其餘由哪些既有測試涵蓋 |
| 10 | P2 `posthardcore`／`emopop` 名稱像公共曲風 | **採納** | §2.3 與 `FXTag` 註解標明批 4 私有 |
### A.2 R2（2026-10-13；確認輪）
- #1、#3、#5、#6：Codex 同意。#7：Codex 指出 `ransomPop` 沒列 → 補上。#9：Codex 同意不逐元件，但 V3 不能證明每個新元件可達 → 加聚合測試。
- 合計 10 條：採納 5、修改採納 3、駁回 2。無需使用者拍板的價值判斷。
