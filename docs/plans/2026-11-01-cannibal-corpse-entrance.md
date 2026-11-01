# Cannibal Corpse 補進場元件：兩條路的影響面（計劃 v0.3，/thecure 收斂；待使用者拍板）

## 0. 複述
- 目標＝Cannibal Corpse（樂團表署名團，目前組不出、播放素面）補進場槽，讓它可播放。本計劃只量兩條路的影響面、收斂成一個結論交使用者拍板；**拍板後才進原型探針**（元件長什麼樣、動畫怎麼走，在探針上由使用者簽）。
- 完成標準（本計劃）＝影響面量測（受影響 profile 數、配方摘要變動範圍、曲庫首數）＋ /thecure 收斂的單一結論。
- 不做＝寫任何 app 程式、做原型、改其他團。

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
