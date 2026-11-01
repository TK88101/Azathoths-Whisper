# Cannibal Corpse 補進場元件：兩條路的影響面（計劃 v0.6：①已拍板、探針已簽；實作段 Codex 3 輪收斂，待使用者審閱）

## 0. 複述
- 目標＝Cannibal Corpse（樂團表署名團，目前組不出、播放素面）補進場槽，讓它可播放。本計劃只量兩條路的影響面、收斂成一個結論交使用者拍板；**拍板後才進原型探針**（元件長什麼樣、動畫怎麼走，在探針上由使用者簽）。
- 完成標準（本計劃）＝影響面量測（受影響 profile 數、配方摘要變動範圍、曲庫首數）＋ /thecure 收斂的單一結論。
- 不做（v0.1–v0.3）＝寫 app 程式、做原型、改其他團。v0.4 起：使用者拍板①、探針簽字後，依 §4c 實作；仍不改其他團。

## 1. 使用者決定與既有約束（不重議）
- 批 5 計劃 F6：death／grind 都不專屬，只有兩條路——①改它的目標值（加私有標籤）；②連帶 death 系多團與 death 列重簽（2026-11-01 開工口令照錄）。
- 契約凍結（批 1 計劃 §3.4，批 2 §3 重申）：槽語意、`FXTag` 匹配規則、十軸、聚合、fit、排除上次、無候選退 mono 不動，只做純加法；已簽字的團**目標值凍結**（批 3 §2、批 4 §2 的 Mayday Parade 先例）。
- `slam` 已由使用者指示拿掉（adaa1fd，「彈片堆」），不得以 slam 回來當解法。

## 2. 事實（2026-11-01，已核）
- F1 Cannibal Corpse 目標值：標籤 `death`、`grind`；十軸 raw .7、theatrical .1、cold .1、aggression 1、speed .8、elegance 0、decay .8、bright 0（`SongProfileResolver.swift:464`，與原型 `composer.js:244` 相同）。
- F2 **為什麼缺進場**：47 個進場元件沒有一個帶 `death` 或 `grind`（`LyricsFXCatalog.swift` 進場段 grep 為空）。原型的 `slam` 原本掛 `horrormetal, black, death, hardcore, thrash, grind`（`composer.js:95`）；拿掉後 Arch Enemy／Slayer／Fleshgod 靠 `thrash`／`melodeath`／`symphonic` 等其他標籤仍有進場，只有 Cannibal 掉成 0 個（adaa1fd：「Cannibal Corpse 暫時 mono」）。
- F3 **死金系標籤分佈**：帶 `death` 的團＝Arch Enemy、Cannibal Corpse、Slayer、Fleshgod Apocalypse（`SongProfileResolver.swift:463,464,469,473`）；帶 `grind` 的團只有 Cannibal Corpse。曲風列的標籤＝代表團標籤聯集扣 `genreRowPrivateTags`（`:431-433`）——death 列（代表團 Cannibal、Fleshgod）因此帶 `death`＋`grind`；melodeath（Arch Enemy）、thrash（Slayer、Arch Enemy）、通用 metal 列（Iron Maiden、Slayer）帶 `death`。
- F4 **曲庫影響**：Cannibal Corpse 在使用者曲庫 0 首（B2 批 5 補件後「署名待補元件」178 首→0，I-70；它是唯一剩下的組不出署名團，若有歌會留在該計數）。
- F5 **影響面量測**（scratchpad `cc/`：app 原始碼唯讀副本，只在副本裡加一個假想進場 `probeEnter`，向量＝Cannibal 的十軸、模板借 stamp；對 `ReadabilityAudit.profiles` 全部 134 個 profile〔樂團表、曲風列、通用列、曲庫 47 種多列組合〕各算進場候選、可否組合、種子 1–20 連抽配方，與基線比對）：

| 掛法 | 合格集合會改變的 profile（上界：量的是 `Composer.fit > 0`；假想元件沒有 req／forbid，所以等於標籤相交；日後元件若帶 req／forbid 只會更少） | 本次假想元件實際進入前 5 名的 profile（觀測值，隨向量而變） | 配方改變（同一假想元件、種子 1–20） | `RecipeGoldenTests` 涵蓋範圍（樂團表＋B1 兩列）內改變的 | 曲庫首數 |
|---|---|---|---|---|---|
| ① 私有標籤（新標籤加到 Cannibal 目標值，並列入 `genreRowPrivateTags` 使 death 列不繼承） | **1**（Cannibal） | 1 | 1 個、20／20 行（mono→組合） | Cannibal 1 團 | **0** |
| ②a 只掛 `grind` | 14（Cannibal＋death 列＋12 種含 death 列的組合） | 13 | 13 個、179／260 行 | Cannibal 1 團（death 列與組合屬 ⑥b 列，不在摘要內，由 `GenreRowTests`／可讀性稽核把關） | 已知下限 194 首（death+melodeath+metalcore 160、death+metalcore 21、classicrock+death 13，I-68），全數 TBD |
| ②b 掛 `death`（＋`grind`） | 23（4 團＋melodeath／death／thrash／通用 metal 4 列＋15 種組合） | 22 | 22 個、282／440 行 | Arch Enemy、Cannibal、Slayer、Fleshgod 4 團 | 含通用 metal 列（所有落到泛用金屬的曲），遠大於 ②a；TBD |

  - ②a 合格集合會改變的組合：black+death、black+death+melodeath、black+death+symphonic、black+death+thrash、classicrock+death、death+doom、death+doom+melodeath、death+melodeath、death+melodeath+metalcore、death+melodeath+symphonic、death+metalcore、death+symphonic。
  - ②b 另含：Arch Enemy、Slayer、Fleshgod Apocalypse、melodic death、thrash、metal、black+thrash、hardrock+thrash、metalcore+thrash。
  - 「合格集合」才是簽字基線（`ExistingBandCandidatesTests` 比的是每槽所有 `fit > 0` 元件）會看到的連帶改動；前 5 名與 20 種子配方只是這個假想元件的觀測（Codex R1-4、Q2）。V1 要 2 個進場（F6），②兩個元件的聯集仍不超過標籤上界。
  - 涵蓋範圍：`ReadabilityAudit.profiles` 134 個（樂團表、曲風列、通用列、曲庫 47 種組合）；J-Pop 三變體不帶 death／grind／私有標籤，不受影響；使用者樣式與同歌手共識最終都由同一批列／列組合合成，已在範圍內（推測，依實作結構）。
- F6 **V1「每槽 ≥ 2 個合格候選」**（批 5 計劃 V1）：三種掛法若只加一個元件，Cannibal 的進場都只有 1 個候選（因為現在是 0）→ **任何一條路都要給它至少 2 個進場**：新做 2 個，或新做 1 個＋既有 1 個同掛，或既有 2 個同掛。
- F7 **不看標籤時、既有進場對 Cannibal 的貼合度前幾名**（同一副本計算）：jpKiraPop .79〔J-Pop 私有〕、genIndStamp .72〔通用工業私有〕、genExpType .69〔通用實驗私有〕、drop .62（altmetal／hardcore／horrormetal／nu）、punch .57、lurch .55、tumble .50、negative .49（black）、stamp .42（thrash 等）。
- F8 **哪些既有元件不能同掛私有標籤**（Codex R1-5，已核）：J-Pop 元件不行——J-Pop 變體目錄以 `tags == [變體標籤]` 精確比對選取（`JPopPolicy.swift:42`），加標籤會把它從 J-Pop 目錄移除；⑦ 通用元件（`gen*`）不行——設計規則「只帶一個通用標籤」（`LyricsFXCatalog.swift:118,215,322` 註解，⑦ 計劃 §4.4）。可同掛的只有一般元件（保留原標籤、只加私有標籤）。

## 3. 推論（推測，標明推理鏈）
- ① 的影響面恰為「本來就要變的那一團」：Cannibal 由素面變組合是目標本身；其他 133 個 profile 的合格集合機械性不變（別的 profile 不帶這個標籤，標籤相交是合格的必要條件）。預期的政策面變化：`ReadabilityPolicy.auditable` 會多出 Cannibal（組得出的署名團才稽核），要跑它的 G1–G3。
- ① 是對「目標值凍結」的**例外**，不能類比 ⑦ `gen*` 或 ⑥a J-Pop 私有標籤——那兩者不是改已簽字團的目標值（Codex R1-2 修正我原本的類比）。所以決議要寫明：**只對 Cannibal Corpse、具名、一次性**；十軸與原有兩個標籤逐位不變（測試釘住）。
- ② 為了一個曲庫 0 首的團，改動 13–22 個曲庫裡真有歌的 profile 的合格集合（②a 下限 194 首），並要求使用者對已簽字的死金系樣式重簽；②b 還會碰到通用 metal 列。代價與收益不成比例。

## 4. 結論（/thecure 收斂，附錄 B）與後續輪廓
- **選①**，並同時鎖定：
  1. Cannibal Corpse 是唯一、具名、一次性的目標值凍結例外；十軸與 `death`、`grind` 不動，只加一個私有標籤（名稱實作時定）。
  2. 私有標籤加進既有 `genreRowPrivateTags`（語意即「不得由代表團流入曲風列」，與 emo／J-Pop／nu 子標籤相同；Codex 確認不必另立集合）。
  3. V1 的 2 個進場：新做，或同掛**一般**既有元件（保留原標籤）；**不得**同掛 J-Pop 或 `gen*` 元件（F8）；不得用 slam。外觀在原型探針上由使用者簽。
  4. 驗收：最終兩個元件各自驗「除 Cannibal 外全部 band／曲風列／通用列／組合的合格集合不變」（簽字基線 `ExistingBandCandidatesTests` 只有 Cannibal 進場清單改變）；death 列不含私有標籤、Cannibal 含；除 Cannibal 外所有 profile 與私有標籤不相交；`RecipeGoldenTests` 只有 Cannibal 的行改變（還原 mono 恰回 `d99a…`）；Cannibal 的 G1–G3；V1（每槽 ≥ 2、可播放、端到端）；ACCEPTANCE 新條目含凍結例外的簽字。
- 拍板後另寫實作計劃；本計劃到此為止。

## 4b. 原型探針（2026-11-02，scratchpad `cc-probe/cannibal-probe.html`，預覽頁副本、不進 repo）
- 副本內與 app 一致：拿掉 slam、所有進場去掉 death／grind；Cannibal 加私有標籤，只讓候選進場掛上。
- 候選與使用者回饋（一次一項）：① drop「自上砸落壓扁」（原型本來設計給 death／melodeath，B2 批 3 搬進 app 時只帶批 3 專屬標籤）→「沒問題」；② stamp「蓋章砸入」→「對」；③ negative「影印負片瞬現」→「沒問題」。
- 採用三個全收（V1 只要求 ≥ 2；多一個候選讓「每次換一套」變化更多；使用者可隨時說拿掉哪個）。三者都是既有元件、模板與繪製不變，只同掛私有標籤；皆非 J-Pop、非 gen*（F8）。
- **探針第 2 版（同檔）**：第 1 版用的是原型完整元件，Cannibal 會抽到 app 沒有的字型 AmazDooM、Butcherman、MetalMania 與退場 split（B1 只搬了子集；scratchpad `proto/elig.js` 比對）。改成只留 app 目錄有的元件（`LyricsFXCatalog.swift` 的 324 個），預設三個進場混抽＝實裝樣子。使用者看整體樣子（字型、背景、進場、退場、配色）回「對」（2026-11-02）。

## 4c. 實作（使用者 2026-11-02 拍板①、探針兩版皆簽；v0.5 依 Codex R1 修訂）
### 已核事實（2026-11-02）
- app 照本節改完後 Cannibal 每槽合格（fit > 0）：font Anton／Catacombs／Grimoire；backdrop film／void；enter drop／negative／stamp；exit cut／fall；fx none／shake；palette ashGrey／boneBlood（scratchpad `cc/` VARIANT=R）。V1 每槽 ≥ 2 成立。
- 原型（副本加同樣改法）多出 font AmazDooM／Butcherman／MetalMania、exit split（app 沒有）；保留 slam 時 enter 也多 slam（`proto/elig.js`）。
- `ExistingBandCandidatesTests.existingBandsOnlyChangeWhereTheUserSignedIt`（`:84-107`）只允許簽字對照檔 `linked` 裡決定 `new` 的團改變，且 `now.eligible == signed.eligible`、`now.playable == signed.playable`；`batchesAfterTheBaseline = [5]`（`:110`）。對照檔由 `tools/export_signed.js --batch n` 從原型匯出，連帶團的 eligible＝原型 fit > 0。
### 設計
1. `FXTag` 新增私有標籤 `cannibal`；加進 `genreRowPrivateTags`。Cannibal 目標值標籤 `[.death, .grind]` → `[.death, .grind, .cannibal]`，十軸逐位不變。`drop`、`stamp`、`negative` 各加 `.cannibal`（原標籤保留）。
2. **簽字對照檔**：新增 `b2-batch6-signed.json`（`bands` 空、`linked` 只有 Cannibal、decision `new`、`playable` 由 app 算出填入），`batchesAfterTheBaseline` → `[5, 6]`。不改已簽的批 5 對照檔、不重錄整份基線。
3. **原型同步**（`tools/patch_b2_6.py`，照批 5 先例，輸入是 `composer.before-b2-6.js` 複本）：Cannibal 標 `linked:true,b2:true,batch:6` 並加 `cannibal`；三個進場加 `cannibal`；`slam` 退役（改掛 `retiredSlam`，同批 5 的 strobe／pyro 寫法；反映使用者 2026-10-19 的決定）。
4. **原型多出的 4 個未搬元件**（AmazDooM、Butcherman、MetalMania、split）：`export_signed.js` 加 `--app-catalog` 選項，連帶團的 eligible 取「原型 fit > 0 ∩ app 目錄」（`lib.appCatalog()` 已有），只在本批使用；不改這 4 個元件的標籤——改標籤會連帶改掉原型裡 Arch Enemy、Slayer、Fleshgod 等死金團的設計，而它們日後可能搬進 app。使用者簽的探針第 2 版正是「只用 app 現有元件」，與此一致。
5. `LibraryGateReport`（Codex R2：Cannibal 補完後不能再當負向案例，報表建構流程也沒有注入點）兩個最小接縫，正式流程不加注入：
   - internal static 純函式 resolution→(是否組合, 無樣式原因)，參數 `isComposable` 預設 `Composer.isComposable`；`verdict` 照舊以預設值呼叫。
   - 計數彙整抽成 internal `init(rows:consensus:)`：正式 `init(tracks:…)` 照舊建列後交給它算 identity／composed／signedPending／readability／source 與 `passed`（`LibraryGateReport.swift:146-162` 的計數段原樣搬入）。測試以人造的一列（`noStyleReason == .signedBandMissingParts`、issues 含 `.composed`）驗證 composed＝1、signedPending＝1、`!passed`。
### 任務（單人主 session 依序 C1 → C0 → C2 → C3 → C5 → C4 → C6–C10；每步留下實際紅燈證據）
| # | 任務 | DoD |
|---|---|---|
| C1 | 改前快照（**任何 production source 修改前**） | 只加 print 測試（test 檔），在未改的工作樹錄下全部 `ReadabilityAudit.profiles`＋J-Pop 三變體的逐槽合格集合，存 `Tests/Fixtures/LyricsFX/profile-candidates-pre-cannibal.json`（記 HEAD 與 `LyricsFXCatalog.swift`／`SongProfileResolver.swift` 的 sha256）；先 checkpoint commit 固定 |
| C0 | 標籤可解析（紅） | 測試以 `FXTag(rawValue: "cannibal")` 斷言存在且在 `genreRowPrivateTags`（可編譯的行為紅燈） |
| C2 | 隔離測試（紅） | 新 `CannibalCorpseEntranceTests`：①帶 `cannibal` 的元件恰為 enter 的 drop／negative／stamp，且各自標籤＝改前標籤＋`cannibal`；②除 Cannibal 外所有 band、keywordRows、genericRows、組合 profile 的標籤不含 `cannibal`；death 列不含；③對 C1 快照逐 profile 逐槽比較，**只允許 Cannibal 的 enter 改變**；④J-Pop 三變體目錄的元件 id 集合不變；所有 generic 元件仍恰一個 generic 標籤；⑤Cannibal 十軸與 death、grind 逐位不變、resolver 解析出的署名 profile 含 `cannibal` |
| C3 | 可播放（紅） | ⑥`isComposable`；進場合格集合恰為 {drop, negative, stamp}；⑦V1：`PlayableSpace` 非 nil、五必選槽各 ≥ 2、每個入選背景 ≥ 2 個未禁且亮暗相容的配色；⑧端到端：resolver 得署名結果、`compose` 非 mono |
| C5 | 報表接縫（先於 C4） | 設計 5 的兩個接縫；純函式單測涵蓋 `.pending`／`.noMatch`／`.signedBand`（可組／不可組，注入判斷）／其他 resolution；`init(rows:)` 人造列測 composed、signedPending、reason、`!passed`；原 `anUnfinishedSignedBandIsCountedAsMonoAndBlocksTheGate` 的四個斷言由這兩層承接（不刪不放寬，不再用 Cannibal）；`LibraryGateReportTests` 全綠 |
| C4 | 實作 | 設計 1；C0–C3 全綠 |
| C6 | 原型同步＋對照檔 | `patch_b2_6.py` 先跑在複本；`export_signed.js`：`--app-catalog` 只准配 `--batch 6`（否則拒絕），按（槽, id）取交集，並在匯出時自檢每槽輸出＝`eligible(原型) ∩ appCatalog()`、AmazDooM／Butcherman／MetalMania／split 不在輸出；`--dry` 逐槽比對＝app；寫入 `b2-batch6-signed.json`（`playable` 由 app 算）；`CannibalCorpseEntranceTests` 加 fixture 斷言：linked 只有 Cannibal、decision new、eligible／playable＝app（現有 `SignedBatchChecks` 只查 `bands`，連帶團沒有 tags 欄位，故由本檔負責）；`batchesAfterTheBaseline=[5,6]`；`ExistingBandCandidatesTests` 全綠 |
| C7 | 摘要 | `RecipeGoldenTests` 錄新摘要；加 `onlyCannibalChanged`（Cannibal 還原 mono 恰回 `d99a…`） |
| C8 | 可讀性 | G1：`reachablePairs` 集合不變、`playablePairs` 的配對鍵不變（只允許 Cannibal 加進既有配對的來源名）；`LyricsFXContrastTests`、`ReadabilityGateTests` 全綠；Cannibal 新增為 auditable 是預期變化 |
| C9 | 全量＋閘門 | 全量單元（120 s）0 紅、具名差集無消失；coverage_gate；`no_playback_gate.sh`；Scripts |
| C10 | 文件 | ACCEPTANCE I-71：Cannibal 新目標值與一次性凍結例外、三個進場 id、`b2-batch6-signed.json`、快照差集僅 Cannibal enter、J-Pop／generic 目錄未受影響、原型同步狀態（`patch_b2_6.py`、`--app-catalog`）、G1–G3 結果、曲庫 0 首；使用者簽字 |
- 不做每幀量測：三個進場模板都已在其他團上線並量過，沒有新繪製。
- 不新增 UI 測試：Cannibal 不在使用者曲庫；端到端以 C3-⑧ 證明。

## 5. 影響面（本計劃）
- 只新增本計劃文件；量測程式在 scratchpad。

## 6. 風險
- F5 的假想元件向量不是最終設計：②的前 5 名觀測值會隨向量變，但不會超過標籤上界（14／23）；①的「只有 Cannibal」不受向量影響（隔離靠標籤）。
- 20 種子配方只是觀測；①的零差異以「標籤相交是合格必要條件」演繹，實作時以合格集合基線測試證明。

## 附錄 A 量測程式（scratchpad，不進 repo）
- `cc/`：沿用 `g1count/` 的編譯清單，另放 `LyricsFXCatalog.swift`／`SongProfileResolver.swift` 的副本：`probeEnters` 依環境變數 `VARIANT`（空＝基線、A、G、D）產生；`FXTag` 加 `cannibalPrivate`、`VARIANT=A` 時加進 Cannibal 目標值與 `genreRowPrivateTags`。`main.swift` 輸出逐 profile 進場候選＋20 種子配方，`diff.py` 比對；`fit.swift` 算不看標籤的貼合度。

## 附錄 B /thecure 與 Codex 評審紀錄

### R1（2026-11-01，審 v0.1）
| # | 論點 | 判定 | 處置（v0.2） |
|---|---|---|---|
| 1 | 選① | 一致；措辭補「auditable 多出 Cannibal 是預期政策面變化」 | §3 |
| 2 | ①與 ⑦ gen*／⑥a J-Pop 同性質 | **Codex 勝**：那兩者不是改已簽字團的目標值 | §3、§4-1：唯一、具名、一次性例外 |
| 3 | 必入 `genreRowPrivateTags` | 一致（不必另立集合） | §4-2 |
| 4 | 13／22 是上界 | **Codex 勝**：那是前 5 名觀測；簽字基線看全部 `fit > 0` | 我方補測標籤上界 14／23（`cc/` 加 `L|` 輸出），§2 表格改兩欄 |
| 5 | 元件全留探針 | **Codex 勝**一處：J-Pop／gen* 不能同掛（已核 `JPopPolicy.swift:42`、`LyricsFXCatalog.swift:118` 註解） | F8、§4-3 |
| Q4 | 第三條路 | 一致：框架內沒有；`row()` 特判等都是①的變體且更隱蔽 | — |
- Codex 最擔心：探針階段把「同掛既有元件」當無害捷徑——同掛 jpKiraPop（貼合度第一）會直接破壞 J-Pop 目錄，讓「①只影響 Cannibal」失真。

### 整體確認（/thecure 第 7 步，2026-11-01）
- Codex 直接執行 `cc/run` 確認 ②a 14、②b 23、① 1；異議一項（證據可追溯性）：上界成立的條件是假想元件無 req／forbid → 已寫進 §2 表頭；`out-*.txt` 已重產並含 `L|` 行。
- 致命缺漏：無。順序（拍板 → 原型探針簽核 → 實作計劃）：妥當。
- 最容易失敗的一步：探針時把既有元件同掛私有標籤，尤其誤掛 J-Pop／`gen*`（§4-3 已禁止）。

## 附錄 C 使用者拍板
- 2026-11-02：「照①做」。下一步原型探針（≥ 2 個進場候選，不得同掛 J-Pop／gen*，不得用 slam），使用者簽字後另寫實作計劃。

### R1（2026-11-02，審 v0.4 實作段）處置
| 嚴重度 | 意見 | 處置（v0.5） |
|---|---|---|
| 嚴重 | 沒有簽字授權，`existingBandsOnlyChangeWhereTheUserSignedIt` 會擋 | **採納**：批 6 對照檔、`[5, 6]`（設計 2、C6） |
| 嚴重 | 原型是活來源，未同步會讓工具把 death 進場帶回 | **採納**：`patch_b2_6.py`（slam 退役）＋`--app-catalog`；另發現原型多 4 個未搬元件（已核），選擇以匯出時取交集處理、不改它們的標籤（設計 4，待 R2 判） |
| 高 | 報表注入點不足 | **採納**：只抽 resolution→verdict 純函式（設計 5、C5） |
| 高 | 直接引用 `.cannibal` 是編譯紅、C1 太大包 | **採納**：C0 用 rawValue；拆成 C0–C3 |
| 高 | 隔離只證明「不帶標籤」，沒證明合格集合不變 | **採納**：C1 改前快照＋C2-③逐槽差集 |
| 中 | J-Pop／generic 目錄未直接斷言 | **採納**：C2-④ |
| 中 | G1 不變式不精確 | **採納**：C8 |
| 中 | fixture 會靜默丟掉未知標籤 | **採納**：C6 round-trip 斷言 |
| 中 | I-71 內容不足 | **採納**：C10 |

### R2（2026-11-02，審 v0.5）處置
| 嚴重度 | 意見 | 處置（v0.6） |
|---|---|---|
| — | 設計 4（匯出取交集、不改 4 個未搬元件的標籤） | **Codex 判正確**（不污染未搬元件將來服務的其他死金團；與 app-only 探針一致） |
| 嚴重 | 報表計數層無法重建「署名團組不出」 | **採納**：計數彙整抽 `init(rows:consensus:)`，人造列測試（設計 5、C5） |
| 高 | C1 快照在 C0 之後，不是真正的改前 | **採納**：C1 移到最前、production source 修改前、先 checkpoint |
| 中 | 連帶團 fixture 沒有 tags，現有檢查查不到 `cannibal` round-trip | **採納**：由 `CannibalCorpseEntranceTests` 驗 resolver profile 與 fixture（C2-⑤、C6） |
| 中 | 匯出交集沒有自動證明 | **採納**：`--app-catalog` 限批 6、匯出自檢（C6） |
| 順序 | C1 → C0–C3 → C5 → C4 → C6–C10 | **採納** |

### R3（2026-11-02，審 v0.6）
- Codex：「無異議。R2 處置已完整納入 v0.6，且與 `LibraryGateReport.swift:100–215` 的現況相符。」
