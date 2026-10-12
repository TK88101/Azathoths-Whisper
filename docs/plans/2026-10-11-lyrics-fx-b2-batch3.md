# Lyrics FX — B2 批 3「按樂團擴充（第三批）」實施計劃 v3（計劃評審 R1–R2、選群辯論 R1–R2 已併入；結論＝A 群，待使用者確認執行）

母計劃：`docs/plans/2026-10-03-lyrics-fx-mode.md`（§2.10、附錄 B）。批 2：`docs/plans/2026-10-09-lyrics-fx-b2-batch2.md`（下稱「批 2 計劃」）。本檔**重用**批 2 計劃的 F3b（候選兩層）、§4.1 流程、§4.2 可抽空間與連帶團、§4.3 原型約束、§4.5 別名、§2.1 的預檢與「B2 修復例外」，只寫差異。基線：`main` c55b32b（v2.0.2，含批 1、批 2）。

## 0. 複述
- 目標＝再讓一群樂團（連同連帶舊團，簽字對象 ≤ 12 個）在歌詞特效裡得到使用者簽字的組合風格；流程、工具、測試沿用批 2。
- 完成標準＝§5 V1–V7 全過。
- 不做＝§3 非目標。
- 模式（/fatboyslim Phase 0）：**normal**。依據同批 2：每輪收斂靠使用者看探針與在場授權，loop 換不掉這個等待。
- 任務形狀：**串行**（T4–T6 的排他書寫集合重疊：`LyricsFXCatalog.swift`、`ComposedStyle.swift`、`GlyphTemplates.swift`），不派實作子 agent。

## 1. 已核事實（2026-10-11）
- F1 分支：本機 `wip/lyrics-fx-b2-batch3`，自 `main` c55b32b 開出。
- F2 曲庫（iTunesLibrary 唯讀匯出，Music 前後都沒在執行；原始資料只在 session 暫存目錄）：12,234 首、481 個樂團；覆寫表 44 團＋3 個別名＝47 個鍵，涵蓋 3,960 首＝32.4%。播放次數全庫合計 394、近 90 天播過 206 首（樣本小，同批 2 §2.1 的提醒）。
- F3 **基線已在 c55b32b 重產（使用者指定的開工前步驟）**：`TEST_RUNNER_AZW_PRINT_FX_BASELINE=c55b32b xcodebuild test … -derivedDataPath /private/tmp/azw-dd.jCbMvt -only-testing:"AzathothsWhisperTests/ExistingBandCandidatesTests/printTheBaseline()"`，TEST SUCCEEDED；兩個標記之間的原文 sha256 `9ab94b564fee196f01566ee449bea705f43d1f943a78c4277e3a28c1102a6696`（33,460 bytes，暫存在 session 目錄 `baseline-raw.json`）。內容：44 團；mono 6 團（Rammstein、Korn、The Chemical Brothers、Fatboy Slim、Daft Punk、Aphex Twin——Sum 41 已因批 2 變成組合）；與 repo 內 be91ed3 基線比，有差異的正好是批 2 簽「新版」的 6 個連帶團，另多出批 2 的 7 個新團，其餘 31 團零差異——與批 2 §9.5 的記錄一致。**尚未寫進 repo**：換基線會讓現行測試紅（見 F4），所以與測試改動同一步做（T1）。
- F4 測試裡寫死批次的地方（`grep` 已核）：
  - `ExistingBandCandidatesTests.theBaselineCoversEveryBandThatWasInTheTableWhenItWasTaken` 斷言基線團名＝`batchOne + batchTwo`（換基線後要＋`batchThree`）。
  - 同檔 `existingBandsOnlyChangeWhereTheUserSignedIt` 與 :110 的另一條讀 `linkedBands(batches: [2])`。換成 c55b32b 基線後，批 2 的連帶團已不再「與基線不同」，若照舊讀 `[2]` 會紅——要改成讀本批 `[3]`。批 2 的護欄「批 1 九團不得列為連帶」要擴成「批 1 九團＋批 2 七團（`batchTwo`、`batchThree`）不得列為連帶」。
  - `ArtistOverrideTableTests.bandsAddedFromB2On…` 迭代 `batchTwo + batchThree`；`LyricsFXContrastTests.batchThreeNeverFallsBackToAnIncompatiblePalette` 只看 `batchThree`；`B2BatchTwoTests` 讀 `b2-batch2-signed.json`。
  - 對照檔讀取已有共用 helper（`Tests/LyricsFX/SignedBatchFixture.swift` 的 `SignedBatchFile.load(batch:)`／`linkedBands(batches:)`、`SignedBatchChecks`），批 3 直接用。
- F5 工具（`docs/plans/2026-10-03-lyrics-fx-assets/tools/`，未追蹤、還在）：`lib.js`、`check.js`、`need.js`、`precheck.js`、`export_signed.js`、`gen_swift.js`、`build_page.js`、`patch_b2_2.py`、`t7-batch1.sh`，皆吃 `--batch <n>`。`gen_swift.js` 已內建「新元件只帶本批專屬標籤」（批 2 §9.3）。`build_page.js` 的提示文字寫死批 2 的龐克團，要改成吃參數或由預檢結果產生。原型 `composer.js` 目前有 44 個 TARGETS（＝app 覆寫表）。
- F6 原型裡兩群相關標籤的元件現況（每槽帶該標籤的元件數／其中已在 app；`*`＝還不在 app）：

  | 標籤 | 字型 | 背景 | 進場 | 退場 | 效果 | 配色 | 現有團 |
  |---|---|---|---|---|---|---|---|
  | `nu` | 3／1（Anton、BlackOps*、Xizor*） | 2／0（scan*、grid*） | 4／2 | 1／0（bands*） | 2／1（shake、rgbsplit*） | 1／0（acid*） | Korn、Hatebreed |
  | `hardcore` | 3／2 | 3／1 | 6／4 | 2／1 | 4／3 | 2／2 | Hatebreed |
  | `gothic` | 6／5 | 4／4 | 5／5 | 2／2 | 4／3 | 2／2 | Cradle of Filth、Type O Negative |
  | `industrial` | 2／0 | 2／0 | 1／0 | 1／0 | 2／0 | 2／0 | Rammstein |
  | emo／post-hardcore | 0 | 0 | 0 | 0 | 0 | 0 | （無此標籤） |

  Korn 目前在原型的合格集合：退場只有 `bands`*、配色只有 `acid`*——這兩個一移植，Korn 就由 mono 變組合（所以 Korn 一定是連帶）；Hatebreed 會多出 BlackOps／Xizor／scan／grid／strobe／drop／type／bands／rgbsplit／acid 等。
- F7 既有硬規則（母計劃附錄 B）：P10「**工業金屬與 Nu-Metal 不共用任何元件**」（`ComposerTests.rammsteinNeverGetsNuMetalComponents`）；P3 高頻顫動被判成 Nu-Metal（黑金屬禁用）；P13／P14 的規則照舊。曲庫裡 Slipknot 有 10 首、Godsmack 12 首標 `Industrial Metal`——genre 不影響覆寫表內的團，但設計時不得替它們借 `industrial` 元件。

## 2. 候選群（結論：批 3＝A 群；B 群留批 4，見 §2.4）
曲數為曲庫實際寫法正規化後合計（含列入的別名）；播放＝播放次數合計。依批 2 的使用者既裁定，repo 只放各群總數，不放每團曲數（每團數字只在 session 暫存與對話裡）。

### 2.1 A 群「Nu-metal／另類金屬」：新 10 團＋連帶 2 團＝12 個簽字對象
- 新 10 團：Linkin Park（別名 `JAY-Z & LINKIN PARK`、`LINKIN PARK & Steve Aoki`；大寫寫法正規化同鍵）、Slipknot、Flyleaf、Stone Sour、Limp Bizkit、P.O.D.、Adema、Evanescence、Ill Niño、Static-X。
- 連帶 2 團：Korn（現為 mono → 會變組合）、Hatebreed（現為組合，候選變多）。
- 曲庫 genre 的注意點：Slipknot 有部分標 `Industrial Metal`（工業≠Nu）；Evanescence 帶哥德味，不得借 `gothic`（會連帶 Cradle of Filth、Type O Negative）；Static-X 工業感最重，最考驗 P10。
- 合計：新團 922 首（7.5%）、播 35；連帶 80 首；共 1,002 首＝8.2%。
- 為了守 12 個上限，批 2 計劃原列的 **Cold（24 首、0 播、genre 只有オルタナティブ）不收**，留後續。其餘曲庫裡的鄰近團（Fort Minor 21、Dead By Sunrise 13、Murderdolls 15、Skillet 15、Breaking Benjamin 13、Godsmack 12、Kittie 11、Lacuna Coil 11）同樣不收。
- 對照組：Linkin Park（乾淨、數位、冷）vs Slipknot（髒、恐怖、面具）；Limp Bizkit（街頭、跳）vs Evanescence（哥德、戲劇）。
- 設計重點（推測，T2 會驗）：只用 `nu` 一個標籤分不出上面四種性格，要另立本批專屬子標籤（暫名 `altmetal`、`rapmetal` 之類，定名在 T2）。新團與 Korn／Hatebreed 的隔離見 §2.4 規則 N1。

### 2.2 B 群「Emo／post-hardcore」：新 7 團，預估連帶 0
- 新 7 團：The Used、Death Cab for Cutie（偏 indie emo，性格最外圍）、My Chemical Romance、A Day to Remember（近 90 天播放最多的未入表團之一）、New Found Glory、You Me At Six、The Story So Far。
- 合計：438 首＝3.6%、播 24。
- 要立 `emo` 標籤（使用者指定），另可能要 `posthardcore`；這兩個目前沒有任何團有。**預期**零連帶——只在新元件只帶這些新標籤、且 `precheck.js --batch 3` 的外溢與連帶都是 0 時成立（選 B 時這是 T2 的硬閘門，不是事前事實）。New Found Glory／The Story So Far／You Me At Six 若標 `poppunk`，它們會抽到既有的流行龐克元件（那是新團本身的組成，不是連帶）；但帶 `poppunk` 的**新**元件會連帶批 2 的 6 個流行龐克團 → 新元件不帶 `poppunk`。
- 合作曲 `The Used & My Chemical Romance`（1 首）照批 2 §4.5：不歸任何一團、記 `unassigned`，除非使用者在探針時指定。
- Mayday Parade 曲庫 genre 有 emo-rock 33 首，但它是批 2 已簽字的團、目標值凍結，**不會**因為本批得到 emo 元件。
- 沒收的：Bullet For My Valentine（15）、Asking Alexandria（12）偏金屬核，留給「旋死／金屬核」那群（批 2 §2 已列 Killswitch Engage 等）；The Smashing Pumpkins（61）不是 emo。
- 對照組：My Chemical Romance（戲劇、黑紅、行進樂隊）vs The Story So Far（快、粗、乾）；The Used（破碎、尖叫）vs Death Cab for Cutie（安靜、細）。

### 2.3 兩群比較（歷史：v2 時標「需使用者拍板」；v3 由 §2.4 收斂）
| | A 群 Nu-metal | B 群 Emo |
|---|---|---|
| 曲數 | 1,002（8.2%） | 438（3.6%） |
| 播放（新團） | 35 | 24 |
| 簽字對象 | 12（剛好頂到上限） | 7 |
| 連帶 | Korn（mono→組合）、Hatebreed | 預估 0 |
| 原型起點 | 有 `nu` 元件但各槽薄、app 幾乎沒有 | 全部從零 |
| 主要成本 | 12 個人要看要簽；Korn／Hatebreed 的連帶要先預檢、只能呈現可行組合；新團內部跨度大（數位／恐怖／街頭／哥德）；P10 工業≠Nu；Xizor、Black Ops One 授權要逐枚確認 | emo 視覺語言全從零設計（字型、背景、動作、配色），探針可能多輪；保留 5 個名額 |
- 傾向 A 的理由（推測）：曲數約 2.3 倍；Linkin Park 是曲庫最大、播放最多的未入表團；Korn 是 B1 簽過目標值卻一直是 mono 的團，A 讓它第一次被使用者看到並簽字。曲數不是線性效益——A 的探針與連帶決策成本不隨曲數縮小，這是覆蓋率換決策量。
- 選 B 的理由：零連帶可由預檢證明、只有 7 個對象、不碰任何已簽字團；從零設計的成本是局部的，由三輪熔斷與外溢 0 閘門控制。
- 覆蓋率 vs 決策風險是價值判斷，證據定不了（Codex R2 同意此收斂）。

### 2.4 結論：批 3＝A 群＋規則 N1（/thecure R1–R2，Codex：「異議：無い」）
- **N1 標籤隔離**：本批 10 個新團的目標值與 `{nu, hardcore}` 不相交，只帶本批新立的私有子標籤。Korn／Hatebreed 需要的新元件才帶 `.nu`。既有元件（Anton、slide、stamp、shake 已帶 `.nu`）**可以**再補新團的子標籤（同掛允許）：預檢的移除只刪連帶團自己的標籤（`precheck.js` 的 `strip`），同元件上的子標籤保留，新團不受影響。
- 效果：Korn／Hatebreed 的「新版／現狀／單色」與 10 個新團解耦；兩個都說不要時，新團照樣成立。Korn 與 Hatebreed 彼此仍可能經 `nu` 耦合——T3 實算，不先假定。
- 機械保證（取代「新元件只帶本批專屬標籤」這句在 A 群下的不足——`gen_swift.js:6` 的 `allowed` 在 Korn／Hatebreed 標為本批連帶時含 `nu`，會把原型上的 `nu` 原樣寫進元件）：
  1. T2 先決閘門：標籤隔離矩陣（新團 × {nu, hardcore} 為空）＋每個新團六槽各 ≥ 2 個經私有子標籤可達的候選。
  2. T5 產生後、探針定稿前：以 app 目錄對 Korn、Hatebreed 各做 current／mono 移除，斷言 `batchFour` 每團六槽的完整合格 ID 集合不變（Swift 測試）。
  3. Nu 系標籤寫成單一常數集合（`nu`＋本批子標籤），validator 的 industrial 互斥與 `batchFour` 無 industrial 元件的測試共用它。
- 主要剩餘風險（Codex 最擔心、我同意）：**T2**——放棄薄的既有 `nu` 元件池後，10 團的私有視覺系統要自己撐起每槽 ≥ 2；子標籤切太細會缺候選，切太粗會失去 Linkin Park／Slipknot／Limp Bizkit／Evanescence 的對比。T2 閘門不過就停下回報，不帶著缺口進探針。
- 為什麼不是 B：B 的優勢是零連帶與低決策量；N1 讓 A 的連帶決策與新團解耦後，A 的決策風險接近 B，而覆蓋率是 1,002 vs 438 首，並讓 B1 簽過目標值卻一直是 mono 的 Korn 第一次被看到。B 群（含 emo 標籤）留批 4。

## 3. 目標與非目標
- 目標：選定的一群從原型設計到 app 交付；基線換成 c55b32b；測試的批次參照由「批 2」推進到「批 3」。
- 非目標（使用者指定＋沿用批 2）：
  - 另一群；**C 段**（外部時間軸）；`GenreStyleResolver` 的「**ロック→日本語系**」誤判；サビ／關鍵字效果（③）；字形點陣快取（②，觸發條件同批 1 §7.1）；Settings 手調；Cover Flow；Python 舊版。
  - **契約凍結**（批 1 計劃 §3.4）不動：六槽與 kind 語意、`FXTag` 匹配規則、十軸、聚合算法、fit 不平方、排除上次、無候選退 mono。只做純加法（新標籤、新 case、新配色、新字型）；唯一例外是批 2 §2.1 的「B2 修復例外」（使用者明示選「單色」時，才允許移除指定元件上的指定標籤）。
  - 不改任何已簽字團（B1、批 1、批 2）的目標值。
  - commit／合併／push：等使用者拍板（wip/ checkpoint 例外，不 push）。

## 4. 設計（只寫與批 2 不同處）
### 4.1 流程（使用者指定的順序）
原型補目標值與元件 → `precheck.js` 預檢連帶 → 本機探針頁（`open` 本機 HTML，寫清楚看什麼、怎麼回「對／不對＋一句」；每條回饋轉成母計劃附錄 B 的 P15 起；最多三輪不收斂即熔斷）→ 簽字 → `gen_swift.js --batch 3` 產生 Swift（只帶本批專屬標籤）→ 簽字對照檔測試。

### 4.2 批次命名
- 原型 TARGETS：本批的團標 `b2:true, batch:3`；連帶團另加 `linked:true`（同批 2）。
- Swift：新增 `SongProfileResolver.batchFour`（doc 註解寫明＝B2 批 3；命名差一沿用批 2 的遺留，不改名），`bandTable = batchOne + batchTwo + batchThree + batchFour`。
- 對照檔 `Tests/Fixtures/LyricsFX/b2-batch3-signed.json`（格式同批 2：`bands`、`linked`、`unassigned`）；測試 `Tests/LyricsFX/B2BatchThreeTests.swift`（suite `B2BatchThreeSignedFixtureTests`＋對照組 `B2BatchThreeContrastTests`）。

### 4.3 基線與連帶（批 2 §4.2 的規則，基線換成 c55b32b）
- `band-candidates-baseline.json` 換成 F3 的輸出（只重排縮排與鍵序；檔頭 `sourceRevision`＝c55b32b）；`theBaselineCoversEvery…` 加斷言 `sourceRevision == "c55b32b"`，正規化後檔案的 sha256 記進 §9。
- `existingBandsOnlyChangeWhereTheUserSignedIt` 與同檔另一條改讀 `linkedBands(batches: [3])`；「不得列為連帶」的名單擴成 `batchTwo + batchThree`（批 1、批 2 的新團）。B1 的 28 團可以是連帶（Korn、Hatebreed 都屬 B1）。另加（R1 #2）：`linked` 的團名 ⊆ 基線團名；`linked ∩ batchFour = ∅`；`bands ∪ linked` 名稱唯一且 ≤ 12。
- 選 A（R1 #3）：`CatalogValidator` 的「industrial 與 nu 不得同掛」擴成「industrial 與任何 Nu 系標籤（`nu`＋本批新立的子標籤）不得同掛」（只查 `.nu` 的話，新子標籤可繞過）；新增一般化測試「`batchFour` 每團的合格集合不含任何帶 `industrial` 的元件」。Rammstein 不另寫——它不在 `linked`，任何差異已由 `existingBandsOnlyChange…` 抓到。
- 選 A：預檢要回答「Korn、Hatebreed 能不能各自選新版／現狀／單色而不牽動新團」。Korn 現為 mono，所以它的「現狀」＝「單色」，實際只有兩態。
- 選 B：預檢應得到「外溢 0、連帶 0」；若不是 0，照批 2 的做法處理。

### 4.4 工具調整（未追蹤，不進 repo）
- 先把現行原型存成 `tools/composer.before-b2-3.js`、`tools/lyrics-fx-preview.before-b2-3.html`，新寫 `tools/patch_b2_3.py`（由 before 檔重建，可重跑）。
- `build_page.js` 改成 `--precheck <json>` 必填（R1 #5）：讀 `precheck.js --json` 的 `objects`／`coupling`／`group` 產生提示，缺欄位即失敗；T2 產出 JSON，T3 只消費它。不寫死團名。
- 新字型照批 2 §4.3：google/fonts 官方（OFL／Apache 2.0）直接收；其他來源（Xizor、Black Ops One 若不在 google/fonts）逐枚列授權問使用者，未確認＝不進 app、原型也換掉；可變字型只收「無軸或只有 wght」（批 2 Fredoka 的教訓）。
- 元件 id 不得與任何槽的既有 id 撞名（批 2 `paper` 撞名的教訓；`CatalogValidator` 會抓，但在原型階段先查）。

## 5. 驗收標準（每條可判定）
- V1 選定群每一團歸屬的所有曲庫寫法 100% 命中覆寫表（離線比對報表記進 §9）；`ArtistOverrideTableTests.everyNameAndAliasNormalizesToAUniqueKey` 綠。
- V2 本批每團六槽每槽 ≥ 2 個合格候選（`bandsAddedFromB2On…` 迭代含 `batchFour`）。
- V3 app 每槽合格集合與 `b2-batch3-signed.json` 完全一致；`batchFour` 團名集合＝對照檔（`B2BatchThreeSignedFixtureTests`）。
- V4 既有 44 團：可抽空間或合格集合與 c55b32b 基線不同的團＝對照檔 `linked` 中簽「新版／單色」者，且內容相等；其餘零差異；批 1、批 2 的 16 個新團不在 `linked`；2,000 種子煙霧測試無漏。
- V5 對比：`mainTextStaysReadableOnEveryReachableBackdrop`、`everyPlayablePairStaysReadable` 照跑（≥ 4.5，crimsonVelvet 例外不擴大）；新增 `batchFourNeverFallsBackToAnIncompatiblePalette`。
- V6 全量單元的失敗集合＝T0 在 c55b32b 記錄的基線（完整識別名與斷言數；批 2 記錄為 `CoverFlowStripRenderGeometry` 7 斷言，另有負載相依的 `LyricsFXProbeRenderTests/writesStillsGIFsAndManifests()` 超時），無新增；skip 清單同 T0；`no_playback_gate.sh` 0；`coverage_gate.sh <xcresult>` Services+Infra ≥ 80%；`Scripts` Python 測試綠。
- V7 使用者在場（三態，同批 2 V7）：`LyricsFXUITests`＋`LyricsFlowUITests` 全綠（含本批一團的新條）；新字型、新效果各一份配方的每幀 p50 ≤ 2 ms、p95 ≤ 3 ms（或使用者明示豁免）；真視窗目視表態原話記 §9。

## 6. 任務清單（TDD：先紅後綠；紅燈摘要回填 §9）
| # | 任務 | DoD | 依賴 |
|---|---|---|---|
| T0 | 全量單元基線（c55b32b） | 失敗集合與 skip 清單（完整名稱）記 §9；`check.js --batch 2`：批 2 七團與 `b2-batch2-signed.json` 逐槽差異 0（工具與原型沒走樣） | — |
| T1 | 基線換成 c55b32b＋測試推進到批 3 | 先寫 `B2BatchThreeTests`、`batchFour` 的迭代與 `batchFourNeverFalls…` → 編譯紅（摘要記 §9）；加空的 `batchFour` 後：換基線檔＋`linkedBands(batches: [3])`＋擴大「不得連帶」名單，`ExistingBandCandidatesTests` 綠（此時無連帶）、只剩讀不到 `b2-batch3-signed.json` 的預期紅 | T0 |
| T2 | 原型設計（選定群） | 批 2 §4.3 約束全過（`check.js --batch 3 --before tools/composer.before-b2-3.js --linked …` OK）；`need.js` 清單、字型授權表、本批專屬標籤 | 使用者選群 |
| T3 | 預檢＋探針＋簽字 | `precheck.js --batch 3` 外溢 0，可行組合列出；本機探針頁（每團 3 個 nonce 動圖＋定格、對照組並排、連帶團三態只呈現可行組合）；簽字或熔斷記錄；命中率 100%；匯出 `b2-batch3-signed.json` | T2 |
| T4 | 新模板／背景／效果 | 每個新 case 一條定點測試，先紅後綠 | T3 |
| T5 | 目錄＋字型＋覆寫表 | `gen_swift.js --batch 3` 產生元件列（只帶本批專屬標籤）；app 算出的連帶名單＝探針所列（多出＝停、補探針）；`linked[].playable` 由 app 算出填入；字型與授權入 `Resources/Fonts`、`xcodegen generate`（逐檔 `git add`，「 2／3.xcodeproj」副本不動）；T1 的紅轉綠；About、三語 README 字型清單 | T3、T4 |
| T6 | 端到端 | `B2BatchThreeContrastTests` 依簽字結果填具體元件（A 群另加 §4.3 的 industrial 一般化測試與 validator 擴充）；UI 測試新增一條；建置成功 | T5 |
| T7 | 使用者在場 | UI 測試實跑；每幀量測；真視窗目視 | T6 |
| T8 | 文件 | ACCEPTANCE I 段（I-37 起：本批簽字、動作與效果、每幀；I-35 的基線改指 c55b32b 並涵蓋批 2 新團）；母計劃附錄 B P15…；本檔 §9 | T3–T7 |
之後：Phase 3 `/simcodex` → 全量測試 → 證據包；commit／合併等使用者拍板。

## 7. 測試策略
同批 2 §7：單元（T1、T4、T5、T6）、集成（對照檔、對比離屏渲染）、E2E（UI 測試一條新增＋兩組照跑；使用者在場、ABC 輸入法、只接內建螢幕）、閘門（`no_playback_gate.sh`、選擇器白名單、`coverage_gate.sh <單元 xcresult>`、`Scripts` Python）。測試字串一律自編。

## 8. 影響面、風險、回退
- 改檔：同批 2 §8（`SongProfileResolver.swift`、`LyricsFXCatalog.swift`／`FXComponent.swift`、`ComposedStyle`／`ComposedBackdrop`／`GlyphTemplates`、`Resources/Fonts/*`、`.xcodeproj`、About、三語 README、`ACCEPTANCE.md`、`Tests/LyricsFX/*`、`Tests/Fixtures/LyricsFX/{band-candidates-baseline,b2-batch3-signed}.json`、`UITests/LyricsFXUITests.swift`），加上 `ExistingBandCandidatesTests.swift` 的批次參照。不改 Music 讀取、`NowPlayingMonitor`、`GenreStyleResolver`、Cover Flow、Python 舊版。
- 風險：R1 既有團沒看過就換風格 → 基線＋預檢＋探針（§4.3）；R2 探針不收斂 → 三輪熔斷；R3 字型授權 → 逐枚；R4 個人資料進 repo → 曲庫資料只在暫存目錄，repo 只有樂團名、目標值、元件代號，本檔只寫各群總數（批 2 使用者既裁定）；R5 A 群頂在 12 個上限 → 探針中要加團就得換團；R6 xcodegen 副本 → 逐檔 `git add`。
- 回退：未簽字＝不進表；整批在本機 `wip/lyrics-fx-b2-batch3`，checkpoint 不 push、不併回。

## 9. 紅燈摘要／量測／探針記錄（實作時回填）
### 9.0 開工前（2026-10-11）
- 分支與基線重產：見 F1、F3。

### 9.1 T0（2026-10-11，c55b32b 原始碼）
- 全量單元（`-only-testing:AzathothsWhisperTests`、skip `AzathothsWhisperTests/BatchOverlappingLoadTests/overlappingLoadSuspendsPollingUntilLastCompletes()`、`-test-timeouts-enabled YES -default-test-execution-time-allowance 120`、`-enableCodeCoverage YES`）：**1197 tests／143 suites，7 issues**＝`CoverFlowStripRenderGeometry` 7 斷言（`:234` 1 條、`:288` initialCenter＝1、4、5、6、7、8），與批 2 相同；`LyricsFXProbeRenderTests/writesStillsGIFsAndManifests()` 這次沒超時。
- 工具：`check.js --batch 2` 與 `b2-batch2-signed.json` 逐槽差異 0；`need.js --batch 2` 要新做 0。

### 9.2 T1（2026-10-11）
- 基線檔換成 F3 的輸出（`json.dumps(indent=1, sort_keys=True, ensure_ascii=False)`，與舊檔同一排版規則），正規化後 sha256 `33671f8c5f4cabef7959421babe03fd7ab16c518ec9ea10250fbe4803b7e9890`。
- **紅**：`xcodegen generate` 後 `build-for-testing` 編譯失敗——`type 'SongProfileResolver' has no member 'batchFour'`（`B2BatchThreeTests.swift`、`ArtistOverrideTableTests.swift:80`）。
- **綠**：加空的 `batchFour`、`FXTag.nuFamily = [.nu]`、validator 改用 `nuFamily` 後，跑 `ExistingBandCandidatesTests`、`PlayableSpaceTests`、`ArtistOverrideTableTests`、`LyricsFXContrastTests`、`ComposerTests`、`B2SignedFixtureTests`、`B2BatchTwoSignedFixtureTests`、`B2BatchThreeSignedFixtureTests`、`B2BatchThreeIndustrialBoundaryTests`：40 tests，紅只有 `B2BatchThreeSignedFixtureTests` 的 5 條（`b2-batch3-signed.json` 要簽字後才匯出，預期的紅）。

### 9.3 T2 原型＋預檢（2026-10-11）
- 原型由 `tools/patch_b2_3.py` 從 `tools/*.before-b2-3.*` 重建；本機探針頁 `lyrics-fx-preview-local.html`（v16）。
- 私有子標籤 5 個：`altmetal`（Stone Sour、Adema、Ill Niño；Slipknot、Flyleaf、Static-X 兼掛）、`rapmetal`（Linkin Park、Limp Bizkit、P.O.D.）、`cybermetal`（Linkin Park、Static-X）、`horrormetal`（Slipknot）、`gothmetal`（Evanescence、Flyleaf）。新團都不帶 `nu`／`hardcore`。
- 不進本批：Shadow of Xizor（不在 google/fonts，原型改掛無人使用的標籤）；頻閃背景拿掉 `hardcore`（否則 Hatebreed 連帶會把它搬進 app）。
- Korn 另補：`slideOut`、`mono` 加 `nu`（原本退場、配色各只有 1 個）。
- 新配色 2 個：`hybridGrey`（灰黑＋白＋訊號紅）、`rust`（鏽黑＋骨白＋鏽紅）。
- `check.js --batch 3 --before tools/composer.before-b2-3.js --linked Korn,Hatebreed`：**OK**。10 團每槽合格數最少 2（Stone Sour、Adema、Ill Niño、Evanescence 的退場各 2）；既有團變動只在 Korn、Hatebreed（7 槽），未預期 0；400 次實抽 0 筆亮暗違規，全部暗底。
- `precheck.js --batch 3`：本批專屬標籤＝hardcore、nu＋5 個子標籤；外溢到其他既有團 0；連帶 2 對象 × 三態＝9 種，可行 6；**每一種可行組合下 10 個新團都「少 0 個」**（N1 成立）。Korn 與 Hatebreed 彼此耦合：Hatebreed 選現狀或單色時，Korn 要一起選現狀；Korn 可單獨選單色。
- `need.js --batch 3`：合格元件 65，app 已有 52，**要新做 13**：字型 BlackOps、SpaceMono（google/fonts OFL 靜態檔，已查）；背景 scan、grid；進場 drop、type、flip；退場 bands；效果 rgbsplit；配色 acid、terminal、hybridGrey、rust。其中動作基元 drop／type／flip／bands 與背景 scan／grid、效果 rgbsplit 要新增 Swift case。
- 已知風險（Codex 預警的 T2「切太粗」）：Stone Sour、Adema、Ill Niño 共用 `altmetal`，三團的候選幾乎相同，只靠十軸分前 5 名——交給探針判斷。
- 探針頁自測（Chrome 開本機檔、腳本逐一點 12 個對象、各抽 12 組、切三態）：繪製錯誤 0；8 套字型都有載入；Korn「現狀」顯示為單色（app 現況）。未做：人眼看動態。

### 9.4 T3 探針回饋
- **P15（2026-10-11，本機探針頁 v16）**：使用者：「slipknot不太應該用Catacombs 鋸齒碎屑 這個字體（因為這個已經給黑金屬用了）；其他沒什麼問題，但是 Stone Sour 主唱和slipknot相同 但比slipknot要克制一些；Adema 是標準商業流行新金屬，沒什麼特點我覺得也沒事。Ill Niño 是拉丁風格的所以現在的字體和效果不太合適」。
  - 規則（記進母計劃附錄 B）：**已經代表黑金屬的元件不借給 Nu 系**。除了點名的 Catacombs，同理也拿掉黑金屬專屬的進場 `negative`；與硬核共用的 film／slam／misreg／ashGrey 保留。
  - Stone Sour：加 `horrormetal`，目標值往 Slipknot 靠但收斂（raw .6、aggression .75、decay .5、elegance .2）。前 5 名與 Slipknot 共享 Elite／BlackOps／xerox／shake，但硬切與砸入的比重低得多（Slipknot 退場 cut 84%，Stone Sour fall 57%、cut 25%）。
  - Ill Niño：改用私有標籤 `latinmetal`，不再共用 `altmetal`。新字型 Barrio（拉丁街頭手繪，google/fonts OFL；Sancreek、Rye 屬西部木刻風，P13 已出局，不用）、新配色 `sangre`（黑＋暖紅＋金橙）；另把既有的 AlfaSlab、embers、smokeHaze、kick、stamp、swagger、fall、slideOut、thump、flicker、whiskey、ampRed 加上 `latinmetal`。
  - Adema：不改。
  - 重跑：`check.js` OK（未預期 0）；預檢外溢 0、6／9 可行、新團在各組合下都少 0 個；要新做的元件 13 → 15（多了 Barrio、sangre）。
  - 探針頁 v17 自測：繪製錯誤 0、Barrio 有載入；Slipknot 抽不到 Catacombs；Ill Niño 的字型只會是 Barrio、AlfaSlab。
- **簽字（2026-10-11）**：使用者看 v17 後：「OK 沒問題了」→ 10 個新團簽字。Korn、Hatebreed 沒有另外表態；**我方解讀**為採用探針預設呈現的「新版」，並在回覆裡明說、請使用者有異議時指出（對照檔 `linked[].reason` 照實記下這個解讀）。命中率：10 團的曲庫寫法全部命中（Linkin Park 4 種含 2 個合作寫法，其餘各 1 種；922 首），無 `unassigned`。

### 9.5 T4–T6、T8（2026-10-11）
- 紅：T4 定點測試先寫，編譯失敗——`EnterTemplate` 無 `drop`／`flip`／`type`、`ExitTemplate` 無 `bands`、`BackdropKind` 無 `grid`、`FXTag` 無 `cybermetal`（另有一處測試運算式太複雜，已拆開）。
- 實作：
  - 6 個 FXTag（`FXTag.nuFamily` 同步擴充）；進場 drop／type／flip、退場 bands；背景 scan、grid；效果 rgbsplit（固定色 `splitRed`／`splitBlue`）。
  - 照實記下兩處移植落差：bands 在原型組合模式不畫切帶，app 照搬成 identity；rgbsplit 原型用 lighter 混色疊在字上，app 畫成字下方的半透明副本、不加亮。
  - `gen_swift.js --batch 3` 產生 15 個元件列，另替既有元件補 77 個本批標籤（`tools` 外的套用腳本在 session 暫存目錄 `apply_b2_3.py`）。
  - 字型 Barrio、Black Ops One、Space Mono（google/fonts 靜態檔，CoreText 讀到可變軸數 0）與 OFL 授權檔進 `Resources/Fonts`。
  - `batchFour` 10 團由原型 TARGETS 產生。
- 連帶：app 算出與 c55b32b 基線不同的既有團正好是 Korn、Hatebreed，合格集合與原型逐槽相同；可抽空間由 app 算出寫進對照檔 `linked[].playable`。
- 新增測試：`B2BatchThreeSignedFixtureTests`（5）、`B2BatchThreeIndustrialBoundaryTests`（3，含「拿掉連帶團標籤後新團不變」）、`B2BatchThreeContrastTests`（4）、`GlyphTemplatesB2BatchThreeTests`（4）、`B2BatchThreeEffectTests`（3）；UI 測試 `testASignedNuMetalBandGetsItsComposedStyleRegardlessOfGenre`（未跑，T7）。相關 14 個 suite 69 條綠。
- **全量單元（實作後）**：1217 tests／148 suites，11 issues，**全部在 `CoverFlowStripRenderGeometry`**，與 T0 的 7 條不同：
  - 這次 3 條測試全卡在前置斷言 `items.count >= 5`（`:179` 1、`:276` 7、`:311` 3），每個案例約 10 秒。
  - 已核：同一時段、**完全沒改過的 c55b32b**（暫存工作樹、獨立 DerivedData）單獨跑這個 suite，得到逐條相同的 11 條；本分支單獨重跑也一樣。→ 不是本批造成的，是環境在 T0（22:30）之後變了。
  - 已排除：螢幕鎖定（未鎖）、螢幕休眠（醒著）、外接螢幕（只有內建螢幕）、負載（load average 約 7）。
  - 原因：TBD。這個 suite 讀的是畫上螢幕之後的 AX 幾何。
  - 不跳過、不放寬；交使用者決定要不要另案查（Cover Flow 不在本批範圍）。
  - 其餘 1214 條（扣掉這 3 條）全綠。
- 閘門：`no_playback_gate.sh` 0；`coverage_gate.sh <全量 xcresult>` Services+Infra 96.2%；`Scripts` Python 測試 333 條 OK。
- T8：
  - ACCEPTANCE：I-26 字型清單；I-35 基線改為 c55b32b；新增 I-37–I-40（I-37 E2E 與 I-40 每幀待使用者在場）。
  - 三語 README 字型授權表。
  - 母計劃附錄 B P15。
- 未做：T7（UI 測試實跑、每幀量測、真視窗目視，需使用者在場）。

### 9.6 Phase 3 評審（/simcodex，2026-10-11；R2 提前結束）
| 輪 | 來源 | 採納並修 | 駁回／延後（理由） |
|---|---|---|---|
| R1 | codex review（--uncommitted） | 無正確性問題 | — |
| R1 | simplify：效率 | RGB 分離的紅藍副本逐字交錯，繪製端只合併相鄰同色 → 每份副本各填一次；改成本行「其他殘影 → 全部紅 → 全部藍」（`groupSplitCopies`） | 掃描線每幀重建路徑、網格每幀配置陣列：量級在微秒，P2 延後 |
| R1 | simplify：重用 | 網格偏移改用檔內既有 `wrap`（負時間也得到正偏移） | 測試 helper 收斂（`drawn`、`plan`、`rects` 三批各一份）、隔離測試改用 `PlayableSpace`：P2 延後（會動到批 1／批 2 的測試檔） |
| R1 | simplify：簡化／層次 | — | `enterProgress` 每字多算一次（約 5 ns）、`emit` 參數漸多、常數可改 private、`linked ∩ batchFour` 斷言被子集斷言蘊含：P2 延後。各批硬寫的 `batchN` 清單改成 `batches` 陣列、`nuFamily` 改成 exhaustive switch：P2 延後（每批要改 5 處的成本記為遺留）；`batchThreeNeverFallsBack…` 名稱已較實際範圍寬，不改名（ACCEPTANCE 引用） |
| R2 | 自評（只看 R1 的兩處修正） | 無 | — |
| R2 | codex review（--uncommitted） | 無 P0／P1 | P2「 2／3.xcodeproj 舊副本不要 commit」：本來就不 add；刪除要先問使用者（既有慣例） |
- 無安全敏感改動（無認證、無網路、無新的執行期檔案寫入；字型是一次性下載進 repo），未派 security-reviewer。
- 評審後全量：**1217 tests／148 suites，11 issues，全部是 `CoverFlowStripRenderGeometry` 的 `items.count >= 5`**，與同一環境下 c55b32b 的結果逐條相同（§9.5）；其餘全綠。`coverage_gate.sh` Services+Infra 96.2%。

### 9.7 使用者在場（2026-10-12；只接內建螢幕、ABC 輸入法）
- **UI 測試**：`LyricsFXUITests`（10，含新增的 Linkin Park 一條）＋`LyricsFlowUITests`（9）**19／19 綠**，同一輪、一次過（232 s）。
- **T7 每幀**（-O 量測建置、真視窗在前景、dense 預覽、主執行緒 plan＋Canvas 編碼；每份 6 個 5 秒窗，丟第一個當暖機，取 5 個；全部全程最前景）。配方：背景 scan（本批新背景；與 grid 同為 2 個 LayerDraw，grid 另測）、進退場 drop／bands、配色 acid；效果原定 rgbsplit＋ransom（既有最重），但 **ransom 會讓 rgbsplit 不畫**（`emit` 的紙片分支先走，照原型 ransom 提前 return；兩者實際不會同團出現，ransom 只掛 punk77），所以字型三份的 ghosts＝0，rgbsplit 另用 Black Ops One 量：
  | 配方 | p50 | p95 | 判定（2 ms／3 ms） |
  |---|---|---|---|
  | 字型 Barrio（＋ransom） | 0.51–0.79 ms | 0.96–1.41 ms | 過 |
  | 字型 Black Ops One（＋ransom） | 0.61–0.72 ms | 1.09–1.25 ms | 過 |
  | 字型 Space Mono（＋ransom） | 0.64–0.76 ms | 1.17–1.33 ms | 過 |
  | 效果 rgbsplit＋speedlines（Black Ops One） | 0.59–0.69 ms | 0.99–1.16 ms | 過 |
  | 效果 rgbsplit＋shake（Black Ops One） | 0.58–0.71 ms | 1.01–1.13 ms | 過 |
  | 背景 grid（Black Ops One、flip、rgbsplit＋ransom、terminal） | 0.55–0.67 ms | 1.10–1.23 ms | 過 |
  - I-40 的範圍（新字型、新效果）全數「過」。
  - **範圍外發現**：第一份 rgbsplit 配方用了既有字型 Special Elite（批 1 移植，從沒量過），p50 1.27–2.78 ms、p95 3.83–4.12 ms（重跑相同）。對照：同配方拿掉 rgbsplit 換 shake 仍是 p50 1.27–2.78、p95 3.83–4.10；換成 Black Ops One 就降到 0.6／1.1 ms。→ 慢的是 Special Elite 字形本身，不是 rgbsplit。推測：Special Elite 是做舊打字機字，輪廓節點多，每字填色成本高（推理鏈：同配方只換字型就差 3–4 倍，副本數不變）。
  - 影響面：Special Elite 從批 1 起就給 punk／punk77／indie 團用（已在 main）；本批替它加了 `horrormetal`，Slipknot、Stone Sour 也會抽到。
  - 使用者裁定（2026-10-12，同 I-25 Catacombs 前例）：「Special Elite 維持現狀」——照實記錄、不改；字形點陣快取仍列後續。
- **真視窗預覽**：依序開 Linkin Park、Slipknot、Stone Sour、Ill Niño、Evanescence、Korn 各約 20 秒（組合器自抽）。使用者：「都沒問題」（2026-10-12）。

## 10. 待拍板
1. **確認執行 §2.4**（批 3＝A 群 12 個簽字對象＋N1）。

## 附錄 A　計劃評審記錄
### A.1 R1（gpt-5.6-terra／medium，2026-10-11；無 P0）
| # | Codex 意見 | 裁決 | 落點 |
|---|---|---|---|
| 1 | P1 基線來源沒被測試鎖死（只驗非空） | **採納** | §4.3：斷言 `sourceRevision == "c55b32b"`，正規化檔 sha256 記 §9 |
| 2 | P1 本批新團可被偽列為「連帶」而不被抓到 | **採納** | §4.3：`linked ⊆ 基線`、`linked ∩ batchFour = ∅`、`bands ∪ linked` 唯一且 ≤ 12 |
| 3 | P1 P10 只靠兩個藝人代表；Rammstein 只驗新元件 | **修改採納** | Rammstein 零差異已由 `existingBandsOnlyChange…` 涵蓋，不另寫；我方補出 Codex 漏看的繞過：validator 只查 `.nu`，新子標籤可繞過 → 擴成 Nu 系全部標籤；加一般化測試 |
| 4 | P2 B 群「零連帶」寫成事前事實 | **採納** | §2.2 改為預檢通過才成立，列為選 B 的 T2 硬閘門 |
| 5 | P2 `build_page.js` 改法不可執行 | **採納** | §4.4 `--precheck <json>` 必填 |
| 6 | P2 推薦 A 證據不足，曲數不是線性效益 | **採納** | §2.3 改寫為「偏覆蓋率」、成本並列 |
| 7 | P2 選 B 的反方論點更強 → 改推 B | **回辯** | 見 R2 |
### A.2 R2（2026-10-11；確認輪）
- 1–5：Codex 同意裁決（#3 同意 validator 擴充與不重複寫 Rammstein）。
- 6–7：我方回辯——使用者在口令裡已點名「Korn／Hatebreed 會連帶」並給了 12 的上限，連帶不是隱藏成本；批 2 的預檢＋三態機制已在 6 個連帶對象上跑通；Korn 是 B1 欠帳。覆蓋率 vs 決策風險屬價值判斷 → 兩群並列、標「需使用者拍板」。Codex：「同意……不堅持改推 B：B 較低決策風險是合理判斷，但沒有足以推翻 A 的客觀證據」。
- 合計 7 條：採納 5、修改採納 1、回辯後收斂為使用者拍板 1。
### A.3 選群辯論（/thecure，2026-10-11）
| # | 論點 | 提出方 | 狀態 | 證據 |
|---|---|---|---|---|
| 1 | 批 3 做 A＋N1（新團不帶 nu，解耦連帶決策） | 我 | 一致 | `Composer.swift:13` 任一標籤相交才合格；`precheck.js` 可行判定 |
| 2 | N1 會被 `gen_swift.js:6` 的整批 `allowed` 悄悄破壞 | Codex | **Codex 勝** | `allowed` 在連帶團入批時含 `nu`；→ §2.4 三條機械保證 |
| 3 | 禁止私有子標籤與 `.nu` 同掛、重用設計要換 id | Codex | **我勝**（Codex R2：「對。禁止……並非必要」） | `precheck.js:25` `strip` 只刪連帶團自己的標籤；`LyricsFXCatalog.swift:56,166,168,222` 既有元件已帶 `.nu`，禁止同掛會逼出重複定義 |
| 4 | §2.1「＋必要時的 nu」與 N1 矛盾 | Codex | **Codex 勝** | 已刪 |
| 5 | 整體確認 | — | Codex：「異議：無い」；最易失敗＝T2 | — |

