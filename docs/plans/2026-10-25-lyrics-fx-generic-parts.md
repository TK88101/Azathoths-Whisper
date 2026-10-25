# 歌詞特效 ⑦：通用零件（計劃 v0.1 草稿）

狀態：**v1.0 定稿**（使用者 2026-10-25 選 §9-1 (a)；Codex 4 輪收斂，見附錄 A、A2、A3）。實作排在去掉過場動畫之後。母計劃 docs/plans/2026-10-19-lyrics-fx-style-coverage.md §2「通用專用的安全零件（不給署名團）」。前置：⑥a（fb7234c）、⑥b（57453ba）已合 main。預定分支 `wip/lyrics-fx-generic-parts`（自 main 57453ba）。

## 0. 複述
- 曲庫裡有些歌手：MB 曲風與 Apple 曲風都碰不到任何能組出六槽的曲風列，現在只能顯示素面。⑥b 探查時這類主要是 electronic、ambient、industrial、experimental、art pop、pop、new age、gregorian chant、downtempo、neofolk。
- 本計劃為這些曲風補一組**通用元件**，再加上**通用曲風列**，讓它們也能組出樣式。
- 完成標準＝§7 驗收。

## 1. 使用者決定（既定前提，不重議）
1. 通用零件只帶**新的私有標籤**；樂團表的團一個都不給（2026-10-25）。
2. 每條新列都要能組出六槽，並通過可讀性檢查（2026-10-25）。
3. 既有團的配方不變：`RecipeGoldenTests` 摘要 `2f80…` 不變（2026-10-25）。
4. ⑥b 遺留的 P2（⑥b 計劃附錄 F）不在本次範圍（2026-10-25）。
5. 優先順（母計劃 §2）：署名樂團表 > …… > 驗證過的自動分類（MB）> …… > Apple 曲風 > **通用**。
6. 樣式以樂團為準、存在 app 內，不改 Music 的標籤。
7. 讀不到歌詞的效果不可（母計劃 §0）；每次播放都要換一套（`Composer.compose` 的 avoiding 規則照用）。

## 2. 事實
### 2.1 已核（2026-10-25 讀碼）
- **判定順序**（`SongProfileResolver.resolve`，`Services/Lyrics/SongProfileResolver.swift:225-237`）：樂團表 → 歌詞未知 pending → 日文 J-Pop → MB 曲風列（`.artistGenreRow`）→ genre nil pending → Apple 曲風列（`.genreRow`）→ `.noMatch`（素面）。每一層合成後若 `Composer.isComposable` 為否，就當作沒命中、落到下一層（`playable`，:249-251）。
- **組不出＝素面**：`Composer.isComposable` 要求 font、backdrop、enter、exit、palette 五個必選槽都有 `fit > 0` 的元件（`Composer.swift`）。`fit` 的標籤規則是：元件的 `tags` 非空且與目標值的 tags 不相交時 fit＝0；tags 為空的元件對任何曲風都合格。
- **元件目錄的標籤覆蓋**（`LyricsFXCatalog.swift`，179 個元件；2026-10-25 以腳本逐槽統計）：
  - 不帶標籤的元件只有 backdrop `void` 與 fx `none`。
  - 至少缺一個必選槽的標籤：

| 標籤 | 缺的必選槽 |
|---|---|
| `industrial` | 全部（沒有任何元件） |
| `frenchhouse` | font、backdrop、enter、exit、palette |
| `electro`、`techno` | font、backdrop、enter、palette |
| `grind` | font、backdrop、enter、palette |
| `melodeath` | font、backdrop、enter、exit |
| `bigbeat` | backdrop、exit、palette |
| `ambient` | exit、palette |
| `house` | enter、palette |
| `idm`、`heavy`、`thrash` | palette |
| `death` | enter |

  （`death`／`thrash`／`melodeath` 的曲風列已靠代表團其他標籤的聯集組得出，⑥b 已驗；這裡只列單一標籤的缺口。）
  - `pop` 標籤五槽都有元件（Bungee、halftone／sunset、hop、up、popArt），但沒有任何曲風列以 `pop` 為關鍵字。
- **樂團表裡帶電子／工業標籤的團現在全是素面**（T0 2026-10-25 以 `Composer.isComposable` 核實）：Rammstein 缺 font／enter／exit／palette；The Chemical Brothers、Fatboy Slim、Aphex Twin 缺 palette；Daft Punk 缺 enter／palette。樂團表 61 團中組不出的共 6 團；曲庫裡有 4 團、178 首。署名層不檢查 `isComposable`（`resolve` 第一行直接回 `.signedBand`），所以這些曲顯示素面。依 §1-1，本計劃**不**為這些團補元件，見 §9-2。
- **先例**：⑥a J-Pop 的三變體各用一個私有標籤（`jpopKira`／`jpopCity`／`jpopBallad`），每個元件只帶其中一個；十軸照原型調性手定，不是署名代表團平均（`JPopPolicy.swift:3-28`，ACCEPTANCE I-65）。元件沿用既有的字型、背景、進退場模板，沒有新增繪製程式碼。
- **曲風列不得帶的標籤**：`genreRowPrivateTags`＝emo 群 ∪ J-Pop ∪ 批 3 的 Nu 系子標籤（:220）。新列會扣掉這組標籤，所以既有私有元件不會被新列抽到。

### 2.2 ⑥b 時的數字（2026-10-24，僅供參照）
- ⑥b §2「擴充後模擬」：要查的 6,741 首中仍素面 11.1 %（experimental 164、electronic 142、ambient 118、industrial 82、art pop 96…）。
- 這是 17 列草案的模擬；之後使用者拿掉 heavypower、rock*（⑥b 附錄 G），只命中 rock* 的歌回到 Apple 曲風，Apple 寫 Rock 的又變回素面。**所以現況的素面數一定與上面不同。**

### 2.3 T0 唯讀重算（2026-10-25，已完成）
- 方法：JXA 唯讀讀整庫 artist、genre、lyrics（12,271 首；歌詞只在本機判日文，不出檔）＋`ArtistStyles/artists.json`。用 app 自己的 `SongProfileResolver`／`ArtistStyleStore`／`Composer`／`LyricsFXCatalog` 原始碼（`swiftc` 直接編；只替換與判定無關的 `TrackMatcher.exactKey`（照抄）與繪圖層的兩個透明度函式）逐首判定。只印計數，不印歌手名。
- **各來源**：樂團表 5,337（其中 178 首屬組不出的 4 團，實際素面，§2.1）、MB 曲風列 4,543、Apple 曲風列 1,308、J-Pop 132、**素面（noMatch）951 首／99 位歌手（7.8 %）**、pending 0。
- **素面曲的 MB 狀態**：verified 且有曲風 438、verified 無曲風 104、unresolved 409。也就是 513 首只有 Apple 曲風可用。
- **素面曲的 MB 曲風**（每首取前 3，按曲數）：experimental 204、electronic 132、art pop 96、industrial 82、pop 73、rock 73、noise 68、ambient 36、downtempo 36、neofolk 34、folk 31、alternative pop 28、synth-pop 28、hip hop 21、alternative hip hop 21、country（含 gospel、pop）20、folk rock 16、j-pop 16、neo-medieval folk 16、dark wave 15、madrigal 15、dub 14、jungle 14、alternative dance 12、americana 12、heartland rock 12、pop soul 12。
- **素面曲的 Apple 曲風**：alternative 207、ロック 146、オルタナティブ 121、ポップ 107、rock 92、electronica 64、country & folk 31、pop 28、folk 23、ダークウェーブ 23、j-pop 21、singer/songwriter 21、hip-hop/rap 20、electronic 14、レゲエ 14、エレクトロニック 10、hrad rock 6（原文拼錯）、其餘 3。
- **關鍵字缺口（不是元件缺口）**：MB「dark wave」（有空格）與 Apple「ダークウェーブ」碰不到 gothic 列的 `darkwave`；`japaneseGenreNames` 也沒有ダークウェーブ。共 23 首。
- **草案家族試算**（先 MB 曲風、無命中再用 Apple 曲風；`GenreStyleResolver` 同一套比對）：MB 命中 438、Apple 命中 512、都不中 1。各家族覆蓋（可重複計）：rock 305、pop 301、alternative 217、experimental 204、electronic 197、folk 119、industrial 82、ambient 36、sacred 31、darkwave 23、hiphop 21。
- **曲庫出現的家族組合**：rock 單獨 237、alternative 單獨 156、pop 單獨 104、electronic＋experimental＋pop 96、experimental＋industrial 68、folk 56、alternative＋electronic＋pop 40、experimental＋pop＋rock 40、ambient＋electronic 36、alternative＋hiphop 21、folk＋pop 20、folk＋rock＋sacred 16、darkwave＋folk＋sacred 15、electronic＋industrial 14、folk＋rock 12、electronic 單獨 10、darkwave 單獨 8、electronic＋pop 1。
- **結論**：只標 Rock／Alternative（沒有更細曲風）的曲有 **393 首，佔素面 41 %**。不處理這一塊，⑦ 最多只能消掉約 58 % 的素面（§9-1）。

## 3. 目標與非目標
目標：
- 新增若干**通用家族**。每個家族有一個私有標籤、一組只帶該標籤的元件、一條通用曲風列。
- 通用列排在 Apple 曲風**之後**；目前已有樣式的曲（含樂團表、J-Pop、MB 列、Apple 列）配方完全不變。
- 素面曲降到 T0 定出的目標值（§7）。

非目標：
- 為樂團表的團補元件，或改它們的標籤（§1-1；Rammstein 等見 §9-2）。
- 改既有 17 列（2 舊列＋15 列）的關鍵字、標籤、軸值。
- 新增繪製程式碼（新的背景種類、進退場模板、效果、字型）；本計劃只用既有 payload。新配色只是顏色資料。
- 同歌手曲庫共識、專輯／樂團指定、identityUnresolved 介面（⑧）。
- ⑥b 遺留 P2；sandbox；iCloud；Python 1.x。

## 4. 設計

### 4.1 落層：新增「通用層」
- 順序改為：樂團表 → pending → J-Pop → MB 曲風列 → genre nil pending → Apple 曲風列 → **通用列（先 MB 曲風、再 Apple 曲風）** → noMatch。
- 新 case `ProfileResolution.genericRow(SongProfile)`，來源 `ProfileSource.generic`（`dependsOnLyrics` 為否）。不併進 `.genreRow`：來源要可區分（真值表、日誌、日後重組規則）。
- 比對用同一套 `GenreStyleResolver.genre(_:matches:)` 與 `compose(genres:rows:)`，只是 rows 換成 `genericRows`。合成後一樣過 `playable`，組不出就落到 noMatch。
- 為什麼放在 Apple 之後：這樣只有現在落到 `.noMatch` 的曲會改變。若把通用列併進 MB 層，MB 寫 electronic、Apple 寫 Alternative Rock 的曲會從 Apple 列改成通用列，等於改了現有樣式（違反 §3）。
- 為什麼 MB 先於 Apple：沿用母計劃優先順；MB 比 Apple 細（例：Apple「Electronic」、MB「industrial」）。
- **session 語意（R1-7）**：沿用 ⑥b §4.3 的定格規則——本 session 第一次 resolve 得到的來源決定配方。MB 結果在播放途中才到時，即使能把 Apple 通用列換成更細的 MB 通用列，本 session 也不重組，下次播放才生效。`shouldCompose` 不改。整合測試釘住這條。
- 日文歌永遠停在 J-Pop：通用層排在 J-Pop 之後，日文歌詞＋Apple「ポップ」或 MB「experimental」必為 `.jpop`（真值表，R1-12）。

### 4.2 通用家族（依 T0 數字）
每個家族＝一個私有標籤＋一條列。關鍵字沿用切詞＋子字串規則：≤ 3 字的關鍵字只比整詞，例如 `pop`、`dub`、`rap`。門檻：覆蓋 ≥ 1 % 素面曲（≥ 10 首）才做。

| 家族 | 私有標籤 | 關鍵字 | 素面曲覆蓋（T0，可重複計） |
|---|---|---|---|
| 實驗 | `genExperimental` | experimental、avant、noise | 204 |
| 電子 | `genElectronic` | electronic、electronica、synth、downtempo、trip hop、trip-hop、edm、dance、house、techno、idm、jungle、dub | 197 |
| 流行 | `genPop` | pop（含 art pop、synth-pop、j-pop、ポップ） | 301 |
| 民謠 | `genFolk` | folk、singer/songwriter、singer-songwriter、americana、country | 119 |
| 工業 | `genIndustrial` | industrial、ebm、neue deutsche | 82 |
| 氛圍 | `genAmbient` | ambient、new age、drone、chillout | 36 |
| 古樂／聖詠 | `genSacred` | chant、gregorian、medieval、early music、madrigal | 31 |
| 暗潮 | `genDarkwave` | dark wave、ダークウェーブ | 23 |
| 嘻哈 | `genHipHop` | hip hop、hip-hop、rap | 21 |

- **dark wave（R1-2）**：另立 `genDarkwave` 私有家族，不借用既有 gothic 列（gothic 列的標籤是 gothic／black／doom／symphonic 的聯集，會抽到黑金屬、交響的署名元件）。
  - 也**不**把ダークウェーブ加進 `japaneseGenreNames`：一旦譯成 `darkwave`，Apple 寫ダークウェーブ的曲會在 Apple 層直接命中 gothic 列，抽到署名元件，結果與借用 gothic 列相同（R1-13 駁回理由）。
  - 片假名原字長度 > 3，以子字串比對即可命中 `genDarkwave`。
  - 不放沒有空格的 `darkwave`：這個字在 MB／Apple 層一定先命中 gothic 列，到不了通用層，列了也沒用。
- **寬關鍵字（R1-10）**：`singer` 只收 `singer/songwriter`、`singer-songwriter`。`country`、`dance`、`pop` 保留；T0b 列出各寬詞在素面曲中的命中類型分佈（只列曲風字串與計數），T8 樣本含寬詞命中的曲。
- **家族重疊（R1-9、V2-3）**：交叉組合照合成規則（硬軸取 max、軟軸平均、標籤聯集）。§9-1 選 (a) 時，曲庫實際出現的通用家族組合共 14 種（由 §2.3 組合表扣掉 rock／alternative 後合併）：pop 104、electronic＋experimental＋pop 96、experimental＋industrial 68、folk 68、electronic＋pop 41、experimental＋pop 40、ambient＋electronic 36、hiphop 21、folk＋pop 20、folk＋sacred 16、darkwave＋folk＋sacred 15、electronic＋industrial 14、electronic 10、darkwave 8。**T8 逐一看全部 14 種**（各一首，一次一項）。
  - 預先定好的「不像」處置（判定者＝使用者）：該組合改成只用其中**最具體**的一族。具體度由高到低：industrial ＞ darkwave ＞ sacred ＞ ambient ＞ hiphop ＞ folk ＞ experimental ＞ electronic ＞ pop。實作方式是 `genericRows` 的合成前先套這個優先規則，**只對使用者判定不像的組合**生效（白名單，記在決策表）。
  - 任何一條優先規則加入後，重跑 §4.5-1／2／5 全部閘門與曲庫不變式。
  - 只命中單一家族的組合被判不像＝**撤列**（整列拿掉，同 ⑥b 附錄 G），適用 §7 撤列凍結表；多家族組合被判不像＝**套具體度規則**（白名單），不撤列（R3）。
- **Rock／Alternative（393 首）**：見 §9-1，預設不做。
- 標籤命名：`gen` 前綴。新增 `FXTag.genericFamily: Set<FXTag>`，作為**唯一定義**。

### 4.3 列的十軸：A 案（手定政策列）
- 每個家族手定十軸，同 `JPopVariant.profile` 的先例（ACCEPTANCE I-65）。每列附一句設計理由與可接受範圍，寫在附錄 B（T2 探針前定初值，T8 後定稿）。
- 不採 B（代表團平均）：通用元件不用代表團的標籤，所以代表團只貢獻軸值，看似可追溯，實為任意代理（Aphex Twin 同時代表電子與氛圍、Rammstein 一團代表工業）。而且日後改署名團的 profile 會連帶改到通用列，形成隱性耦合（Codex R1-3 採納）。
- `genericRows` 用獨立的建構式（不經 `row(_:_:_:)` 的代表團平均），`KeywordRow.representatives` 為空。
- **標籤一律只用家族私有標籤**：抽不到署名團的元件，署名團也抽不到通用元件（§1-1）。

### 4.4 通用元件
- 元件的 `tags` **恰為一個**家族私有標籤（同 J-Pop 規則）。
- 每個家族五個必選槽各至少 2 個元件，fx 至少 1 個（另有共用的 `none`）；palette 對該家族每個背景的 tone（暗／亮）各至少 2 個相容者。
- **「每次換一套」的規格（R1-5、V2-1）**：沿用既有 `ComposerTests.avoidingThePreviousRecipeChangesEverySlotThatHasAnAlternative` 的**相鄰配對**標準：對 seed 0..<256，各自 `first = compose(seed)`、`next = compose(seed &+ 1, avoiding: first)`（每個 seed 獨立一對，不串成鏈；這是 VM 重播實際走的「上一次配方→這一次」關係）。font、backdrop、enter、exit、palette、fx1 六個欄位每一對都必須不同，重複率上限 0；這等於要求 §4.4 的「每槽至少 2 個」在 tone 過濾後仍成立。`fx2` 不在要求內：`Composer` 不避開上一份的 fx2（R3）。對象：單列＋§4.5-2 fixture 內每個組合。
- payload 只用既有種類：字型限 bundle 內已有的 face，背景限既有 `BackdropKind`，進退場限既有模板，效果限既有 `FXEffect`。新配色是純顏色資料，須過 `LyricsFXContrastTests`（字完全顯示時 ≥ 4.5）。
- id 用家族前綴（T2 定名），避免與既有 id 撞。
- 草案方向（T2 以並排探針給使用者看後定，不在此寫死）：
  - 工業：冷硬黑灰＋鏽紅或警示黃；字型 BlackOps／SpaceMono 類；背景 grid／scan／film；進場 stamp／type；退場 cut／bands。若觸發可讀性禁止組合（condense＋cut 等）就換掉。
  - 電子：霓虹與冷色；字型 Grotesk／Syncopate；背景 haze／stars／prism；進場 fadeUp／flip；退場 slideOut／up。
  - 氛圍、古樂、暗潮：慢進慢出、高 elegance；退場 fade／dissolve（trail）。
  - 流行：亮底或暖色；hop／pop 進場；snapOut／up 退場。
- 與 P10 的關係：P10 只禁止 `industrial` 與 Nu 系標籤掛在同一元件上。`genIndustrial` 元件只帶自己的標籤，不違反；但重用 Nu 群的 payload（grid、scan、type）會讓兩邊外觀相近。這一點交使用者在場看（T8）。

### 4.5 閘門（機器驗證）
1. **單列可玩**：每條通用列各自 `Composer.isComposable`＝真、`PlayableSpace.of` 非 nil；`ReadabilityAudit` 全綠（G1–G3），英文行＋中文行都測。
2. **組合可玩**：以 T0 產生的「曲庫出現過的通用家族組合」fixture（只存家族 id）全部跑 1；驗收只保證 fixture 內的組合。
3. **比對正確（R1-4）**：table-driven matcher 測試逐條驗證每個關鍵字與實際字串形態（`trip-hop`、`singer/songwriter`、`ダークウェーブ`、`ポップ`→pop、MB 三曲風與 Apple 單一 genre 的命中路徑），包括「不該命中」的反例（例：`singer` 單字不命中民謠、`trap` 不命中 `rap`、Apple「ダークウェーブ」不命中既有 gothic 列）。
4. **不汙染既有**：
   - `RecipeGoldenTests` 摘要 `2f80…` 不變（範圍＝`bandTable`＋`originalRows`，⑥b 附錄 E）。
   - `ExistingBandCandidatesTests` 不變：署名團與既有 17 列的每槽候選集合不變。新元件只帶 gen 標籤，對它們 fit 必為 0。
   - 新增結構檢查（`CatalogValidator`）：帶 gen 標籤的元件 tags 恰為一個 gen 標籤；`bandTable` 與 `keywordRows` 的標籤和 `FXTag.genericFamily` 不相交。
5. **曲庫不變式（R1-1）**：T0 小程式改前改後各跑一次，逐首比較 `(resolution case, source, profile 的十軸與標籤)`。改前不是 `.noMatch` 的曲必須逐首相同。另以固定 nonce 比較 `Composer.compose` 的配方 id，確認畫面配方也不變。輸出只有計數與差異的匿名雜湊（曲序號＋欄位名），不出歌手名、曲名。
6. **通用列 snapshot**：`GenericRowSnapshotTests` 釘住每列的關鍵字、軸值、標籤與一份配方摘要。

## 5. 任務清單（每項先紅後綠）
| # | 任務 | DoD |
|---|---|---|
| T0 | 唯讀重算（§2.3）、核實署名電子團、家族組合 fixture | **已完成 2026-10-25**（§2.3）；fixture 於 T5 寫入測試資源（只含家族 id） |
| T0b | 寬詞命中分佈（§4.2）＋改前的逐首基線雜湊（§4.5-5） | **已完成 2026-10-25**（附錄 C）；基線雜湊存 scratchpad（不進 repo） |
| T1 | `FXTag` 加 gen 家族標籤與 `genericFamily`；`CatalogValidator` 新規則 | 紅：規則測試；綠：既有目錄零 problem |
| T2 | 先做**工業**一個家族的元件草案＋並排探針（本機 HTML，`open` 給使用者看，不用 artifact 連結）（R1-14 vertical slice） | 使用者看過記「像／不像」 |
| T3 | 工業家族端到端：元件寫進目錄＋`genericRows`（只含工業）＋resolver 通用層＋閘門 1、3、4、6；閘門 2、5 只跑「已安裝家族可構成」的 fixture 子集（工業單獨）（R3） | 上述全綠；RecipeGolden、ExistingBandCandidates 不變；流程跑通後才進 T3b |
| T3b | 其餘 8 個家族逐一：草案→探針→寫入→閘門（同 T3，fixture 只取已安裝家族可構成的子集）；最後一族完成後跑**完整**閘門 1–6（14 種組合全部）（R3） | 每家族閘門綠＋最後的完整閘門綠；不過的列整列刪、不手補，記決策表 |
| T4 | resolver 與所有 consumer（R1-8）：`ProfileResolution.genericRow`／`.profile`、`ProfileSource.generic`、VM `reconcileRecipe` 的 switch、`shouldCompose`、日誌來源字串 | 真值表：通用層只在 Apple 之後；MB 先於 Apple；日文停在 J-Pop；組不出落 noMatch；session 定格（MB 晚到不重組）。編譯無 exhaustive 警告 |
| T5 | 「每次換一套」量測（§4.4）＋組合 fixture | 規格全過，結果寫進決策表 |
| T6 | 曲庫不變式（§4.5-5）＋改後素面計數 | 既有非素面逐首相同、配方 id 相同；素面計數符合 §7 |
| T7 | ACCEPTANCE 新條目（I-67：通用層、通用元件、手定政策列） | 條目含依據、驗證方式、使用者簽字欄 |
| T8 | 使用者在場：14 種實際組合各一首（有詞、非日文）＋寬詞樣本，一次一項 | 「像」才保留；單一家族不像＝撤列，多家族組合不像＝套具體度規則（§4.2）；記錄 |

T3 是 T4 的子集先行（工業家族用到的 resolver 改動在 T3 一起做）；T4 的 DoD 在 T3b 完成後整體再驗一次。

## 6. 測試策略
- 單元（Swift Testing）：T1、T3、T4、T5 的新測試。全量單元照 ⑥b 慣例跑，已知 flaky `overlappingLoadSuspendsPollingUntilLastCompletes()` 以完整名稱＋括號 skip，回報時列出、不寫「全量綠」；`-enableCodeCoverage`，coverage_gate 綠。
- 整合：`LyricsFXArtistGenreTests` 增兩條：「MB 無列、Apple 無列、MB 寫 industrial → 通用列」；「Apple 通用列先定格 → MB 晚到 → 同 session 不變 → 新 session 套 MB 通用列」（替身 Music，不連網）。
- E2E：`LyricsFXUITests` 增一條 DEBUG 注入（沿用 `AZW_LYRICSFX_PREVIEW_ARTIST_GENRES`）的通用家族用例；使用者在場跑。
- 曲庫不變式（T6）屬一次性唯讀驗證，不進測試 target（app 宿主測試開不了 ~/Documents，且測試不得讀使用者曲庫）。

## 7. 驗收（R1-11：開工前寫死基線）
- 基線（2026-10-25）：素面 951 首。
- 9 個家族全數保留、§9-1 選 (a) 時：素面 ≤ 394 首（951 − 九族覆蓋 557；未覆蓋＝只標 Rock 237、只標 Alternative 156、其他 1；§2.3）。
- **撤列凍結表**（V2-2；由 §2.3 組合表扣掉 rock／alternative 精確推得，開工前鎖定）：撤掉某族時，素面上限＝394＋該族「唯一覆蓋」曲數。

| 撤掉的家族 | 唯一覆蓋（只命中它） | 撤後素面上限 |
|---|---|---|
| pop | 104 | 498 |
| folk | 68 | 462 |
| hiphop | 21 | 415 |
| electronic | 10 | 404 |
| darkwave | 8 | 402 |
| experimental、industrial、ambient、sacred | 0（都與其他族同現） | 394（但同現組合的目標值會變，需重跑 T8 該組合） |

  撤多族時上限＝394＋各族唯一覆蓋之和＋「撤掉後組合內已無剩餘家族」的曲數（同表推算，T6 以小程式核對）。實際值與撤列原因記附錄。
- §4.5 全部綠；RecipeGolden `2f80…` 不變；改前非素面的曲逐首相同。
- 使用者在場 T8 逐項「像」；不像的已依 §4.2 處置（單族撤列／組合套具體度規則）並記錄。
- 單元（除列明的一條 flaky）全綠、coverage_gate 綠、`no_playback_gate.sh` 綠。

## 8. 風險與回退
- **關鍵字太寬**：`pop`、`dance`、`country` 只在通用層生效，不會搶既有列；但 Apple 寫「Pop」的西洋搖滾團也會被套上流行樣式。T0b 分佈＋T8 寬詞樣本；不像就縮關鍵字或拿掉列。
- **外觀與既有群相近**（§4.4 P10 段）：在場看；必要時換 payload。
- **元件數增加**：目錄 179 → 約 179＋9 × 11。`Composer` 每槽先過濾再排序，成本為線性，推測可忽略（T5 順手量一次 `compose` 耗時）。
- **工作量**：先做工業一族跑通流程（T2–T3），再逐族加，撤列成本低。
- 回退：通用層是獨立 case，拿掉 `genericRows` 即回到 ⑥b 行為。

## 9. 待拍板
1. **Apple「Rock」「Alternative」（393 首，素面的 41 %）**——**使用者 2026-10-25 選 (a) 不做**：rock* 已被使用者拿掉（⑥b 附錄 G，Blackmore's Night 的 folk rock 套 AC/DC＋The Beatles「不像」）。
   - (a) 不做（Codex 與本計劃都建議；⑦ 後素面約剩 394 首）；
   - (b) 另立 `genRock`、`genAlt` 兩個分開的家族，用新私有元件、手定軸值；要先把曲庫分層、多首在場驗收，並允許整列撤回。覆蓋量（393 首）本身不足以證明這兩類風格夠一致。
2. **署名電子／工業團**（T0 已核：4 團 178 首現在是素面）：依 §1-1 本計劃不處理。要不要另立「署名團補元件」計劃（需走簽字流程）？

（R1 前的「軸值 A／B」已依 Codex R1-3 收斂為 A 案；「dark wave 別名列」已依 R1-2 收斂為 `genDarkwave`。使用者可否決。）

## 附錄 A Codex R1（2026-10-25）處置
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| R1-1 | 阻斷 | 曲庫不變式「只比計數」證明不了逐首不變 | **採納**：逐首比 case／source／profile＋固定 nonce 比配方 id，只出匿名雜湊（§4.5-5） |
| R1-2 | 高 | dark wave 借 gothic 列會抽到黑金屬／交響署名元件 | **採納**：另立 `genDarkwave` |
| R1-3 | 高 | B 案代表團平均是任意代理且造成隱性耦合 | **採納**：A 案手定政策列（§4.3） |
| R1-4 | 高 | 只存家族 id 的 fixture 測不到實際字串命中路徑 | **採納**：table-driven matcher 測試（§4.5-3） |
| R1-5 | 高 | 「每槽 2 個＝每次換一套」不成立 | **採納**：改成可量測規格＋palette 按 tone 各 2 個（§4.4） |
| R1-6 | 高 | Rock／Alt 393 首不足以證明風格一致 | **採納**：§9-1 維持建議 (a)，(b) 須分開兩族＋分層驗收 |
| R1-7 | 中 | 沒寫 MB 晚到時本 session 的語意 | **採納**：沿用定格規則並加整合測試（§4.1） |
| R1-8 | 中 | 新 case 的 consumer 沒列進 DoD | **採納**：T4 DoD 明列 |
| R1-9 | 中 | 家族重疊沒有「合成後仍像」的驗證 | **採納（修改）**：T8 加前 4 大組合；不像才訂優先規則，不預先設計 |
| R1-10 | 中 | `singer`、`country` 等寬詞 | **採納**：`singer` 改 `singer/songwriter`；T0b 分佈＋T8 寬詞樣本 |
| R1-11 | 中 | 驗收目標可事後移動 | **採納**：§7 寫死基線 951 與 ≤ 394 的條件式目標 |
| R1-12 | 中 | 沒測日文歌不會被通用層越過 | **採納**：真值表（§4.1、T4） |
| R1-13 | 低 | 把ダークウェーブ加進 `japaneseGenreNames` | **駁回**：譯成 `darkwave` 後，Apple 層會直接命中 gothic 列並抽到署名元件，與 R1-2 的採納結論衝突；片假名原字已能以子字串命中 `genDarkwave`（R2 回餵） |
| R1-14 | 低 | 一次建 9 族太重，先做一族 vertical slice | **採納**：T2–T3 先做工業 |

## 附錄 A2 Codex R2（2026-10-25）處置
| # | 意見 | 處置 |
|---|---|---|
| R1-13 | 認可駁回；建議加「日文 darkwave 不得命中既有 gothic 列」反例測試 | **採納**：列入 §4.5-3 反例 |
| R1-5／V2-1 | 「3 槽／100 seed」量到的是存在性，不是重播體驗 | **採納**：改用既有 `ComposerTests` 的同一標準（有替代候選的槽每次都換，256 次 `seed &+ 1` 重播路徑） |
| R1-11／V2-2 | 撤列門檻引用尚未存在的試算表 | **採納**：§7 撤列凍結表（由 T0 組合表精確推得） |
| R1-9／V2-3 | T8 只看前 4 大組合；「不像才訂規則」無判準 | **採納**：T8 看全部 14 種組合；預先定具體度順序與白名單式優先規則、判定者、重跑範圍 |

## 附錄 A3 Codex R3（2026-10-25）處置
| # | 意見 | 處置 |
|---|---|---|
| R1-11／V2-2 | 驗算凍結表數字正確 | 結案 |
| R1-5／V2-1 | 既有測試是相鄰配對、不是鏈；`fx2` 不被避開 | **採納**：§4.4 改為相鄰配對、明列六欄位、排除 fx2 |
| R1-9／V2-3 | §4.2 組合不像＝具體度規則，但 T8／§7 寫成撤列 | **採納**：單族不像撤列、組合不像套規則，三處一致 |
| 新（阻斷） | T3／T3b 只有部分家族時跑全 14 組合必失敗 | **採納**：逐族時只跑已安裝家族可構成的子集；最後一族完成後跑完整閘門 |

## 附錄 B 通用列十軸（T2 前定初值）
（待填。）

## 附錄 C 寬詞命中分佈（T0b，2026-10-25）
素面 951 首中，寬關鍵字實際命中的曲風字串（MB 前三或 Apple，按曲數；同一首可重複計）：
- **pop**：ポップ 107、pop 101、art pop 96、j-pop 37、synth-pop 28、alternative pop 28、country pop 20、pop soul 12、dance-pop 1、tropical/grit/pop 1
- **dance**：alternative dance 12、dance-pop 1
- **country**：country & folk 31、country 21、country pop 20、country gospel 20
- **folk**：folk 54、neofolk 34、country & folk 31、neo-medieval folk 16、folk rock 16
- 觀察：寬詞命中的都是名副其實的同類曲風，沒有明顯誤命中（例如沒有 `pop punk` 落到這裡，因為 poppunk 列在 MB／Apple 層就先命中了）。`j-pop` 37 首是歌詞非日文的日本歌手（日文歌已在 J-Pop 層攔下），會套通用流行；T8 樣本含一首。
- 改前逐首基線：12,271 行（persistentID＋素面／有樣式＋判定與固定 seed 配方的 SHA-256 前 16 位），存 scratchpad `baseline-before.tsv`，不進 repo；T6 改後同法重算比對。

## 附錄 D 實作記錄（2026-10-25，分支 `wip/lyrics-fx-generic-parts`，自 main 924e68e）
- **T1**：紅＝`FXTag` 無 gen 家族成員、無 `genericFamily`（編譯失敗）→ 綠（`GenericFamilyTests` 6 條＋`CatalogValidatorTests` 2 條）。`CatalogValidator` 新規則「通用標籤混用」。`FXTag.allCases` 無遍歷者，新增 case 不影響既有測試。
- **T2 流程調整**：不做網頁探針，改為直接做進 app、讓使用者在曲庫實曲上看（使用者要求加快；實曲比網頁模擬更準）。
- **T3（工業）**：紅＝`genericRow`／`generic`／`genericRows` 未定義（編譯失敗）→ 綠（`GenericLayerTests` 全過）。resolver 新增通用層（Apple 之後、先 MB 再 Apple）、`ProfileResolution.genericRow`、`ProfileSource.generic`；VM `sessionRecipe` 接上；`ReadabilityAudit.profiles` 納入通用列（`generic:<id>`），可讀性與對比閘門自動涵蓋。元件 14 個（字型 2、背景 3、進場 2、退場 2、效果 2、配色 3），payload 全沿用既有種類。`recipeSchemaVersion` 不加（新元件對既有目標值 fit＝0，加了反而會改到既有配方）。`RecipeGoldenTests`（`2f80…`）、`ExistingBandCandidates`（`PlayableSpaceTests`）綠。
- **曲庫實曲**：只命中工業的有詞曲 48 首，全屬 1 位歌手；「實驗＋工業」68 首待實驗族。
- **T8 #1（工業單獨）**：使用者 2026-10-25 在試看版播放後回「特效沒問題」→ 保留。
- **T8 在場（2026-10-25）**：有詞的通用組合實際 10 種（另 5 種曲庫裡沒有有詞曲，看不到特效）。#1 electronic＋experimental＋pop（85 首）：使用者「沒什麼大問題」→ 保留。
  - #2 experimental＋industrial（48 首）：「沒問題」→ 保留。
  - #3 folk（30 首／4 位）：「這個挺好 挺民謠的」→ 保留。
  - #4 hiphop（21 首）：「沒問題」→ 保留。
  - #5 experimental＋pop（20 首）：「沒問題」→ 保留。
  - #6 folk＋pop（20 首）：「相當可以」→ 保留。
  - #7 folk＋sacred（15 首；⑥b 時 rock* 被判不像的同一樂團）：「沒問題」→ 保留。
  - #8 pop（12 首／3 位）：「沒問題」→ 保留。
  - #9 electronic＋pop（4 首／2 位）：「算是沒什麼大問題吧」→ 保留。
  - #10 ambient＋electronic（1 首）：「沒問題」→ 保留。**T8 全數 10／10 保留，無撤列、無具體度規則。**
- **T3b（其餘 8 族）**：一次寫入 118 個元件（產生腳本，payload 全沿用；id 撞名 `genExpXerox` 背景／配色 → 配色改 `genExpPhotocopy`）＋8 條手定通用列。`GenericLayerTests` 擴充：每族關鍵字與反例、片假名ダークウェーブ不命中 gothic、MB 先於 Apple、曲庫 15 種組合可組且相鄰兩次每槽都換。38 條綠；可讀性＋對比 23 條綠（3,922 s）。
- **T6 曲庫不變式**：改前有樣式 11,320 首，改後逐首（判定＋十軸＋標籤＋固定 seed 配方 id）0 首改變；素面 951 → 394（＝§7 凍結目標）。
- **T7**：ACCEPTANCE I-67（待使用者簽字）。
- **全量單元（第 1 次）**：1,706 條，紅 4 條，全屬 ⑦ 連帶：①`B2BatchFourIsolationTests` 兩條（基線之後的新元件只認批 4／J-Pop 兩批）→ 依 ⑥a 先例加「⑦ 通用族」分支（恰一個通用標籤＋其通用列抽得到），檢查強度不變；②`SongProfileResolverTests`／`JPopResolutionTests` 3 處以「Experimental Foo」當未知曲風，experimental 已成實驗族關鍵字 → 改為「Glimmerwave Foo」，斷言不動。修後 3 suite 25 條綠；其餘 1,702 條該輪已綠。coverage 96.2 %（豁免 453／470）；`no_playback_gate.sh` exit 0。
