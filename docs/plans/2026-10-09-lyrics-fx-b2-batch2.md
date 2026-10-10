# Lyrics FX — B2 批 2「按樂團擴充（第二批）」實施計劃 v5（計劃評審 R1–R3、選群辯論 R1–R3 已併入；2026-10-10 全部任務完成，使用者看真視窗「都沒問題」）

母計劃：`docs/plans/2026-10-03-lyrics-fx-mode.md`（§2.10）。批 1：`docs/plans/2026-10-07-lyrics-fx-b2-artist-profiles.md`（下稱「批 1 計劃」；本檔重用它的 §3.3 每批流程、§3.4 契約凍結、§3.5 移植規則，不重抄）。基線：`feature/lyrics-fx` be91ed3。

## 0. 複述
- 目標＝再讓一群樂團（8–12 團）在歌詞特效裡得到使用者簽字的組合風格，流程與工具沿用批 1。
- 完成標準＝§5 驗收標準 V1–V7 全過。
- 不做＝§2 非目標。
- 模式（/fatboyslim Phase 0）：**normal**。依據：每一輪收斂靠的是使用者看探針的反應與在場授權（UI 測試、真視窗量測），不是可無人值守判定的條件；loop 換不掉這個等待。
- 任務形狀：**串行**（T4–T6 的排他書寫集合重疊：`LyricsFXCatalog.swift`、`ComposedStyle.swift`、`GlyphTemplates.swift`），不派實作子 agent。

## 1. 已核事實（2026-10-09；曲庫以 iTunesLibrary 框架唯讀匯出，不啟動 Music；原始資料只在 session 暫存目錄，不進 repo）
- F1 曲庫 12,234 首、481 個樂團（正規化後）。覆寫表現有 37 團（B1 28＝`bandTargets`，批 1 9＝`batchTwo`；`SongProfileResolver.swift`），涵蓋 3,354 首＝27.4%。
- F2 批 1 的離線工具還在（上一個 session 的暫存目錄，已複製到本次暫存目錄）：`check_b2.js`（原型檢查：既有團候選集合變動、每槽候選數、亮暗相容）、`export_b2.js`（匯出簽字對照檔）、`gen_swift.js`（由原型產生 Swift 元件列）、`need_b2.js`（要新做哪些元件）、`t7.sh`（每幀量測）。暫存目錄重開機會清。
- F3 測試現況（`Tests/LyricsFX/`）：`ArtistOverrideTableTests.bandsAddedFromB2OnHaveAtLeastTwoCandidatesInEverySlot` 只迭代 `batchTwo`；`B2BatchOneTests.swift` 的 suite `B2SignedFixtureTests` 讀死 `b2-batch1-signed.json`，並斷言 `batchTwo` 的團名集合＝對照檔；`theB1BandsNeverGainThinSlots` 只把 B1 的薄槽釘成「只准變少」——**repo 內沒有既有團完整候選集合的基線**。`SongProfileResolver.batchOne`＝B1 的 28 團、`batchTwo`＝B2 批 1 的 9 團（命名與批次編號差一）。
- F3b **「候選」有兩層**（`Composer.swift`）：**合格**＝所有 fit > 0 的元件（`ArtistOverrideTableTests`、批 1 對照檔、`LyricsFXContrastTests.reachablePairs` 用的都是這層）；**可抽**＝畫面上真的會出現的，依 `compose` 的實際路徑是：
  - 字型、背景、進場、退場：合格者 fit 降序前 `shortlist`＝5 名（同分以 id 定序）。
  - 配色：**依抽到的背景而定**——`compatiblePalettes` 先依背景的亮暗濾配色，再取前 5；該背景下沒有任何「相容且合格」的配色時**回退成全部配色**（此時會抽到亮暗不相容的組合）。
  - 效果：第一效果＝前 5 名（沒有候選＝`none`）；第二效果＝拿掉第一效果後重新取前 5（所以原本第 6 名也抽得到）。
  - 任一必選槽（字型、背景、進場、退場、配色）沒有候選＝整份 **mono**，其他槽即使有候選也不會出現。
  - 「排除上一次」不對稱：字型、背景、進場、退場、配色各避開上一次的同槽元件，第一效果只避上一次的第一效果，第二效果**不避**上一次的第二效果、只避當次的第一效果。排除只會在上述集合內再拿掉一個，不會抽到集合外。
- F4 原型（`docs/plans/2026-10-03-lyrics-fx-assets/composer.js`，未追蹤）裡兩群候選各自的元件現況（每槽帶該標籤的元件數／其中已在 app 目錄的）：

  | 標籤 | 字型 | 背景 | 進場 | 退場 | 效果 | 配色 |
  |---|---|---|---|---|---|---|
  | `nu` | 3／1 | 2／0 | 4／2 | 1／0 | 2／1 | 1／0 |
  | `hardcore` | 3／2 | 3／1 | 6／3 | 2／1 | 4／3 | 2／1 |
  | `poppunk` | 3／1 | 2／1 | 1／0 | 2／1 | 2／0 | 2／0 |
  | `skatepunk` | 2／2 | 2／1 | 2／1 | 1／0 | 1／0 | 2／0 |
  | `punk` | 3／3 | 1／1 | 3／2 | 2／1 | 0／0 | 2／1 |

  原型沒有 emo／post-hardcore 的標籤與元件。→ 兩群都不是純移植：A 群的 `nu` 退場、配色各只有 1 個；B 群的 `punk` 沒有效果、emo 整塊沒有。與批 1 的 rock 系同樣要**重新設計**。
- F5 連帶影響（T1 基線跑出來的事實，2026-10-09；取代草案時的推測）：
  - 既有 37 團目前在 app 裡是 mono 的有 7 團：Rammstein、Korn、The Chemical Brothers、Fatboy Slim、Daft Punk、Aphex Twin、Sum 41。
  - **批 1 已經連帶改了龐克團**：The Offspring、Blink-182、Green Day、Ramones（曲庫共 481 首）與 Sex Pistols 現在是組合風格，但很薄——字型 Anton／Special Elite／Oswald、背景 paper／sunset／void、配色只有 newsprint 一個、效果只有 none。這些元件在批 1 之前（d569528）的目錄裡一個都沒有（已核 `git show d569528:…/LyricsFXCatalog.swift`），所以這 5 團在批 1 之前是 mono；批 1 移植帶 `punk`／`rock` 等標籤的元件時把它們翻成了組合風格，使用者沒在 app 裡看過、也沒簽過這個樣子（批 1 計劃完成標準③「未簽字的團行為不變」實際上沒守住，當時沒有能發現它的測試）。
  - 選 A 群且沿用 `nu` 標籤：Korn（現為 mono；合格元件：字型 1、背景 1、進場 2、退場 0、配色 0）會變成組合風格，Hatebreed（現為組合，退場與配色各只有 1 個）會變多。
  - 選 B 群且沿用 `poppunk`／`skatepunk`／`punk` 標籤：上述 5 個龐克團與 Sum 41 會變多／變成組合風格。
- F6 別名（離線比對曲庫寫法）：A 群有 `JAY-Z & LINKIN PARK`、`LINKIN PARK & Steve Aoki` 兩種合作寫法；`Cold` 與 `Coldplay` 正規化後不同鍵（`cold`／`coldplay`，覆寫表是整鍵相等不是子字串，不衝突）。B 群有一筆 `The Used & My Chemical Romance`（兩團都在候選內；覆寫表一鍵一值，只能歸一團）。大小寫差異（`Linkin Park`／`LINKIN PARK`、`blink-182`）正規化後同鍵。

## 2. 候選群（使用者選一群；另一群留給批 3）
- **A 群「Nu-metal／另類金屬」（11 團，938 首＝曲庫 7.7%）**：Linkin Park、Slipknot、Stone Sour、Flyleaf、Limp Bizkit、P.O.D.、Adema、Evanescence、Ill Niño、Static-X、Cold。
  - 對照組：Linkin Park（乾淨、數位、冷）vs Slipknot（髒、恐怖、面具）；Limp Bizkit（街頭、跳）vs Evanescence（哥德、戲劇）。
  - 連帶（依標籤重疊的預估，實際名單以 §4.2 的差異為準）：Korn、Hatebreed。
  - 既有硬規則：工業≠Nu-Metal（母計劃附錄 B）——Static-X 的工業感不得借 `industrial` 的元件。
- **B 群「Emo／流行龐克／旋律龐克」（9 團，882 首＝7.2%）**：The Used、Fall Out Boy、Rise Against、My Chemical Romance、NOFX、The Interrupters、Mayday Parade、Good Charlotte、Weezer。
  - 對照組：My Chemical Romance（戲劇、黑紅）vs NOFX（快、粗、玩笑）；The Used（破碎、情緒）vs Weezer（書呆、乾淨）。
  - 連帶（同上，預估）：The Offspring、Blink-182、Sum 41、Green Day、Ramones（共 627 首＝5.1%；其中 4 團現在是 F5 所述的薄風格、Sum 41 是 mono。連同本群 9 團，B 群實際照顧到 1,509 首＝12.3%）。
- 兩群工作量（**推測**，依 F4 的缺口）：相近；A 群要新做的背景／配色／退場較多，B 群要多立一個 emo 標籤並補龐克的效果槽。
- 未列入兩群、留後續批次：Gorillaz、Lana Del Rey、Björk（各自成群）；HIM、Sirenia、Negative、Within Temptation（哥德）；In Flames、Killswitch Engage、Children Of Bodom（旋死／金屬核）。

### 2.1 選群結論（/thecure 辯論 R1–R3，2026-10-09，Codex「無異議」；待使用者確認執行）
- 新增的已核事實——播放統計（iTunesLibrary 唯讀；全庫播放次數合計 385、近 90 天播過 207 首，次數看來近期重置過，樣本小）：A 群 11 團 30 次（7.8%）；B 群 9 團 12 次（3.1%）；**龐克 5 團（The Offspring、Blink-182、Green Day、Ramones、Sum 41）128 次（33.2%）、近 90 天播過 45 首**；Korn、Hatebreed 0 次。也就是 F5 那個沒簽過的薄風格，正落在最常播的團上。
- **批 2＝B 群的切分版，簽字對象 12 個**：
  - 新進表 7 團：Fall Out Boy、Rise Against、NOFX、The Interrupters、Mayday Parade、Good Charlotte、Weezer（606 首）。
  - 連帶重簽 5 個對象：The Offspring、Blink-182、Green Day、Sum 41，以及「Ramones＋Sex Pistols」綁成一個（兩團 tags 同為 `77punk`＋`punk`、基線可抽空間完全相同，只能同選；Sex Pistols 曲庫 0 首，只有目標值層的合成探針，驗收明列它沒有真曲庫／播放的端到端證據）。共 627 首。
  - The Used、My Chemical Romance 留批 3（與 A 群誰先屆時再定）；本批不立 emo 標籤。
- **連帶團的選項**（取代 §4.2「說不對就回到基線」）：基線是 be91ed3 的現況，已含薄風格，所以「回到基線」收不掉批 1 的欠帳。改為每個連帶對象在探針上有三種可選狀態——新版／現狀（薄風格）／單色基本型（批 1 之前）——但**不是逐團自由選**：標籤是全域共用的，T2 先做「標籤相依矩陣＋可滿足性預檢」，探針只呈現能同時落地的組合。簽字後 app 算出的結果與所選不符＝停，不改對照檔。
- **B2 修復例外**（對 §3 契約凍結的窄例外）：「退回單色」只在使用者對該對象明示選擇後啟用；只允許移除指定批 1 元件上的指定龐克系標籤；不改任何團的目標值、十軸、槽語意、匹配規則、繪製。寫進 ACCEPTANCE。
- **測試加嚴**（併入 V4）：非連帶的既有團，合格集合與可抽空間**都**須等於基線；連帶名單與批 1 九團（`batchTwo`）不得有交集，九團逐團等於基線；對照檔 `linked` 擴成 `{name, decision: new|current|mono, eligible, playable, signed, reason}`（選「現狀」的團不算有差異，但留記錄）。
- 順序：T2（原型＋相依矩陣＋預檢）→ T3（受限選項的探針、簽字）→ 對照檔與基線規則先紅 → T4–T8。
- Codex 最擔心的：T3 把三態選擇落到單一目錄時，因標籤共用而無解——所以預檢必須在給使用者看之前做完。

## 3. 目標與非目標
- 目標：選定的一群從原型設計到 app 交付；測試由「寫死批 1」改成「逐批對照檔」，並補上既有團的候選基線。
- 非目標：
  - 另一群與其後的批次；C 段（外部時間軸）；`GenreStyleResolver` 的「ロック→日本語系」誤判；サビ／關鍵字效果（③）；字形點陣快取（②，觸發條件沿用批 1 §7.1：新字型在一般負載超門檻才啟動）；Settings 手調；Cover Flow；Python 舊版。
  - 契約凍結（批 1 計劃 §3.4）不動：六槽與 kind 語意、`FXTag` 匹配規則、十軸、聚合算法、fit 不平方、排除上次、無候選退 mono。只做純加法（新標籤、新 case、新配色、新字型）。
  - 回頭改 B1／批 1 已簽字團的目標值（十軸與 tags）：不改。連帶團只是「候選變多」，處理方式見 §4.2。
  - 把批 1 合進 `main`、push：不在本批（使用者 2026-10-07「不合並」）。

## 4. 設計
### 4.1 流程（批 1 計劃 §3.3 原樣）
原型設計 → 探針 → 使用者「對／不對＋一句」（每條轉成規則記進母計劃附錄 B，P14 起；最多三輪，不收斂即熔斷）→ 簽字 → 由原型**產生** Swift → 對照檔測試。探針用本機 HTML 檔直接開（不走 artifact 連結），並寫清楚看什麼、怎麼回。

### 4.2 連帶團（F5；計劃評審 R1 #1–#3 Codex 勝）
- 原則：不讓任何既有團在使用者沒看過的情況下換風格。
- **可抽空間**（計劃評審 R2 #2、#3 Codex 勝）：一個樂團的可抽空間＝`{font, backdrop, enter, exit, fx1, fx2, paletteByBackdrop[背景]}`，依 F3b 的實際路徑**精確列舉**（`fx2`＝對每個可作第一效果者，拿掉它後重取前 5 的聯集）；任一必選槽為空的團，空間就是 `mono`，不列各槽與背景配色（R3 #1）。測試用一個 helper 列舉它，helper **只呼叫** `Composer.candidates`／`compatiblePalettes`／`fit`（不另寫一份排名或亮暗規則）。比對一律用這份精確集合；另加一條防漏的煙霧測試：對同一團跑 2,000 個種子（含帶 `avoiding` 的連抽）的 `Composer.compose`，抽到的每個元件與每組（背景, 配色）都落在列舉的空間內（空間為 `mono` 的團則每次都回 `.mono`）；連抽時一併斷言 F3b 的不對稱排除（R3 #2）。
- **連帶團的定義**：本批移植後，可抽空間與基線有任何差異的既有團——不只是「mono 變組合」；本來就是組合風格、但多了新字型或新背景的也算。只有合格集合變、可抽空間沒變的不算（畫面不會變），但差異照樣列在記錄裡。
- **基線**：T1 在動目錄之前，由 app 自己算出既有 37 團的合格集合與可抽空間，存成 `Tests/Fixtures/LyricsFX/band-candidates-baseline.json`（只有樂團名與元件代號；檔頭記 `schema`、`sourceRevision`＝產生時的 commit、產生它的測試名稱）。產生方式：一條一次性測試把 JSON 印到測試輸出，我從 log 取出存檔（app 宿主測試寫不了 `~/Documents`）；產生命令與輸出的 sha256 記進 §9。存檔後該測試改為「讀基線比對」。基線的可信度來自：空間定義由煙霧測試防漏，存檔內容由「在 be91ed3 的程式上比對為零差異」防抄錯。
- **做法**：T2 原型設計完，先用原型檢查腳本估出連帶名單（預估）；連帶團一起放進探針總覽頁（標「連帶：目標值沒改，多了這些元件」並列出每槽新增／被擠掉的元件），與本批的團一起簽。使用者對某連帶團說「不對」→ 新元件改掛新標籤避開它（批 1 對 `rock` 標籤就是這樣做），該團回到基線。
- **測試**（`ExistingBandCandidatesTests`，新）：對既有 37 團逐團比對可抽空間與基線——有差異的團名集合必須**等於**對照檔 `linked` 的團名集合，且各連帶團的可抽空間等於對照檔 `linked[].playable`；其餘團零差異。`theB1BandsNeverGainThinSlots` 照舊。
- 已知落差（批 1 即存在，不在本批消除）：原型抽籤是 fit²＋mulberry32、同分依陣列順序；app 是 fit＋SplitMix64、同分依 id。所以原型的前 5 名在同分時可能與 app 不同——連帶名單與可抽集合以 **app 算出的為準**，原型只當預估；簽字後若 app 的連帶名單比探針上列的多，停下來補探針，不直接改對照檔。

### 4.3 原型設計的約束
- 每團六槽每槽 ≥ 2 個 fit > 0 的候選（批 1 的硬 DoD；元件先於數字）。
- 既有 37 團扣掉連帶團後，原型裡的合格集合變動 0（`check` 腳本；app 端由 §4.2 的測試把關）。
- 亮暗相容 0 違規（背景 `needs`、配色 `light`）；且本批每一團每個可抽的背景都至少有 1 個「相容且合格」的配色（不得走到 `compatiblePalettes` 的回退路徑；app 端有測試，見 V5）。
- 母計劃附錄 B 的既有硬規則全部適用（不得有串字的線、不得用程式畫的假裝飾代替字型、不得撒紅點當血、工業≠Nu-Metal 等）；原型檢查不了的由探針把關。
- 新字型只取 google/fonts 官方庫（OFL／Apache 2.0）者直接收；其他來源（例如原型裡 `nu` 用的 Xizor、B1 未進 app 的 Black Ops One 要查來源）逐枚列授權問使用者，未確認＝不進 app、原型也換掉。
- 要真模糊的效果沿用批 1 的整層一次 `drawLayer`，不新增每 run 一次的濾鏡。

### 4.4 工具與測試的批次化（計劃評審 R1 #7、#8、#9 Codex 勝：工具不進 repo）
- 工具：四支腳本與 `t7.sh` 放到原型旁邊 `docs/plans/2026-10-03-lyrics-fx-assets/tools/`（與 `composer.js` 同樣未追蹤、不進 repo，但不會隨重開機消失），改成吃 `--batch <n>`。不寫包裝測試、不訂 Node 版本契約——它們的輸入（原型）本來就不在 repo，結果由 repo 內的對照檔測試驗證。曲庫比對腳本與輸出留在 session 暫存目錄。
- 原型 TARGETS：批 1 的 `b2:true`（＝不抽靠サビ／關鍵字觸發的效果）**原樣保留**，本批的團同樣標 `b2:true` 並另加 `batch:2` 供匯出篩選。不改既有旗標的名字與行為，批 1 九團的抽籤不受影響（`check` 仍會比對批 1 九團的合格集合變動＝0 或在連帶名單內）。
- Swift：新增 `SongProfileResolver.batchThree`（doc 註解寫明＝B2 批 2），`bandTable = batchOne + batchTwo + batchThree`。不順手改名既有兩個（會動批 1 的測試與註解，屬範圍外；命名差一記進遺留）。
- 測試：`B2BatchOneTests.swift` 的對照檔讀取抽成共用 helper（檔名參數化；suite `B2SignedFixtureTests` 的 3 條行為不變），新增 `B2BatchTwoTests.swift` 讀 `b2-batch2-signed.json`；`bandsAddedFromB2On…` 改迭代 `batchTwo + batchThree`。對照檔格式沿用批 1（`signed`／`probe`／`note`／`bands[name, aliases, tags, axes, candidates]`，`candidates`＝合格集合，原型與 app 可比），另加 `linked[name, playable]`（由 app 算出、使用者簽過的連帶團可抽空間，結構同基線）與 `unassigned`（明列不歸任何團的合作寫法與理由）。
- 「元件列由 `gen_swift.js` 產生、不手抄」是**做法**不是驗收項（repo 內驗不了來源）；防手抄漂移靠對照檔測試（V3）。

### 4.5 別名（計劃評審 R1 #4 Codex 勝）
- 選 A 群：`JAY-Z & LINKIN PARK`、`LINKIN PARK & Steve Aoki` 列為 Linkin Park 的別名（探針頁上列出，一起簽）。
- 選 B 群：`The Used & My Chemical Romance`（1 首）**不歸任何一團**，照舊走曲風／mono，記進對照檔 `unassigned`——兩團風格不同，歸誰是審美決定，不替使用者定；使用者在探針時指定了再改。
- 命中率的分母＝「簽字時歸給該團的曲庫寫法」（正式名、大小寫變體、列入的別名）；`unassigned` 的寫法不算未命中。簽字前重跑比對，碰撞逐筆處理。

## 5. 驗收標準（每條可判定）
- V1 選定群每一團歸屬的所有曲庫寫法（§4.5 的分母）100% 命中覆寫表（離線比對報表，記進 §9）；正規化鍵全表唯一（`ArtistOverrideTableTests.everyNameAndAliasNormalizesToAUniqueKey`）。
- V2 本批每一團六槽每槽 ≥ 2 個合格候選（`bandsAddedFromB2On…` 含 `batchThree`）。
- V3 app 每槽合格集合與簽字對照檔完全一致，`batchThree` 的團名集合＝對照檔（`B2BatchTwoTests`）。
- V4 既有團：可抽空間有差異的團＝對照檔 `linked`，內容相等；其餘零差異（`ExistingBandCandidatesTests`，精確集合比對）；煙霧測試（2,000 種子）無漏。
- V5 主字對比（計劃評審 R2 #1 Codex 勝：既有測試不是可抽組合的超集——回退路徑下抽得到的不相容組合不在裡面）：
  - 既有 `mainTextStaysReadableOnEveryReachableBackdrop`（合格且亮暗相容的組合）照跑、不改，≥ 4.5，既有例外 crimsonVelvet 不擴大。
  - 新增 `everyPlayablePairStaysReadable`：全表各團可抽空間裡的每組（背景, 配色）——含回退路徑抽得到的；空間為 `mono` 的團不列——≥ 4.5（crimsonVelvet 同樣的地板），失敗訊息帶團名與元件代號。
  - 新增 `batchThreeNeverFallsBackToAnIncompatiblePalette`：本批各團每個可抽背景都有相容且合格的配色。
  - 若第二條在**既有團**上紅（批 1 以前就存在的回退組合）：這是既有行為的缺陷，不在本批順手改——把團名、組合、比值列給使用者決定（改配色標記／改回退規則／釘為已知），在決定前該條對那幾組以「已知清單」明列並附理由與日期，不得整條跳過。
- V6 全量單元測試的失敗集合＝T0 在 be91ed3 上記錄的基線失敗集合（完整測試識別名與斷言數記進 §9；批 1 記錄為 `CoverFlowStripRenderGeometry` 7 斷言），無新增；skip 清單同樣在 T0 以完整名稱記錄，之後各次全量用同一份；`no_playback_gate.sh` 0；`coverage_gate.sh <xcresult>` Services+Infra ≥ 80%；`Scripts` Python 測試綠。
- V7 使用者在場，三態判定：
  - UI 測試：`LyricsFXUITests`＋`LyricsFlowUITests` 全綠（含本批一團的新條）＝過；否則不過。
  - 每幀（-O 量測建置、真視窗在前景、dense 預覽，`t7.sh`；配方表在 T6 寫進 §9 後才量：每個新字型、每個新效果各一份指定配方，其餘槽固定取「本批新背景中單幀 `LayerDraw` 數最多者」與「本批新效果中副本數最多的兩個」（由 plan 純函數數出來，數字一併記錄）；每份丟掉第一個 5 秒窗當暖機，再取 ≥ 4 個 5 秒窗）：p50 ≤ 2 ms 且 p95 ≤ 3 ms＝**過**；超出但使用者對該元件與量測條件明確表示接受（原話記進 §9）＝**豁免過**；其餘＝**不過**（該元件不進本批）。
  - 量測範圍限制照實記：這個數字是主執行緒的 plan＋Canvas 編碼，模糊類效果在 render server 的成本不在內（批 1 §7.6 同）。本批若新增「要真模糊」的效果種類（不是沿用 `glow`／`neonstroke`），另用 B1 §8.6 的 xctrace 方法錄一次 render server 每幀並記錄，不設門檻。
  - 使用者看真視窗後的表態（原話記進 §9）。

## 6. 任務清單（TDD：先紅後綠；紅燈摘要回填 §9）
| # | 任務 | DoD | 依賴 |
|---|---|---|---|
| T0 | 開 `wip/lyrics-fx-b2-batch2`（自 be91ed3）；跑一次全量單元測試記基線；工具搬到原型旁並加 `--batch` | 基線失敗集合與 skip 清單（完整名稱）記進 §9；對現行原型跑 `check --batch 1`：批 1 九團合格集合與 `b2-batch1-signed.json` 逐槽相同（證明搬動沒改壞） | — |
| T1 | 測試批次化＋基線（Swift） | 可抽空間 helper＋煙霧測試先紅後綠；基線檔由 be91ed3 的 app 產生並存檔（命令與 sha256 記 §9）；`ExistingBandCandidatesTests` 對基線綠（此時無連帶）；`everyPlayablePairStaysReadable` 在既有 37 團上的結果照實記錄（紅＝依 V5 末項處理）；`B2BatchOneTests.swift` 改用共用 helper 後該檔原有測試數不變且全綠；`B2BatchTwoTests`、`batchThree` 迭代先寫——對不存在的 `batchThree`／對照檔**紅**（編譯失敗或讀檔失敗，摘要記 §9） | T0 |
| T2 | 原型設計（選定群） | §4.3 的 `check` 全過；要新做的元件清單（`need`）、字型授權表、預估連帶名單與每槽差異列出 | 使用者選群 |
| T3 | 探針＋簽字 | 本機探針頁（每團 3 個 nonce 的動圖＋定格、對照組並排、連帶團另列、每團一行白話性格）；使用者簽字或熔斷記錄；命中率報表（§4.5 分母）100%；匯出 `b2-batch2-signed.json`（`linked.playable` 待 T5 由 app 算出後填入並與探針所列核對） | T2 |
| T4 | 新模板／背景／效果 | 每個新 case 一條定點測試（時刻→變換／透明度），先紅後綠 | T3 |
| T5 | 目錄＋字型＋覆寫表 | `gen_swift.js` 產生元件列；app 算出的連帶名單與探針所列一致（多出來＝停、補探針）；`ExistingBandCandidatesTests` 綠；字型與授權檔入 `Resources/Fonts`、`xcodegen generate`；`everyCatalogFontIsRegistered`、`eachBundledFontShipsWithItsLicence`、T1 的紅全轉綠；About、三語 README 字型清單 | T3、T4 |
| T6 | 端到端 | `ComposerTests` 對照組斷言（依簽字結果填具體元件）；`LyricsFXContrastTests` 過；UI 測試新增一條（預覽指定本批一團→recipe 探針為組合風格），建置成功 | T5 |
| T7 | 使用者在場 | UI 測試實跑；`t7.sh` 每幀量測；真視窗目視 | T6 |
| T8 | 文件 | ACCEPTANCE I 段增修（本批簽字、連帶團、工具位置）；母計劃附錄 B（P14…）；本檔 §9 回填 | T3–T7 |
之後：Phase 3 `/simcodex` → 全量測試 → 證據包；commit／合併等使用者拍板。

## 7. 測試策略
- 單元：T1、T4、T5、T6 所列；測試字串一律自編句子；全量照跑並帶超時（`-test-timeouts-enabled YES -default-test-execution-time-allowance 120`；skip 清單用 T0 記錄的完整名稱）。
- 集成：對照檔測試（原型↔app）、對比測試（離屏渲染）。
- E2E：UI 測試一條新增＋既有兩組照跑（使用者在場；先切 ABC 輸入法、只接內建螢幕）。
- 閘門：`no_playback_gate.sh`、選擇器白名單測試、`coverage_gate.sh <單元測試的 xcresult>`、`Scripts` Python 測試。

## 8. 影響面、風險、回退
- 改檔：`Services/Lyrics/SongProfileResolver.swift`、`Features/LyricsFX/Composer/{LyricsFXCatalog,FXComponent}.swift`、`Features/LyricsFX/{ComposedStyle,ComposedBackdrop,GlyphTemplates}.swift`、`Resources/Fonts/*`、`project.yml`（若字型清單要列）、`.xcodeproj`（xcodegen 產物）、About、三語 README、`ACCEPTANCE.md`、`Tests/LyricsFX/*`、`Tests/Fixtures/LyricsFX/b2-batch2-signed.json`、`UITests/LyricsFXUITests.swift`、`Tests/Fixtures/LyricsFX/band-candidates-baseline.json`（新）。未追蹤、不進 repo：`docs/plans/2026-10-03-lyrics-fx-assets/{composer.js,lyrics-fx-preview.html,tools/*}`。**不改** Music 讀取、`NowPlayingMonitor`、`GenreStyleResolver`、Cover Flow、Python 舊版。
- 風險：
  - R1 既有團在沒人看過的情況下換風格 → §4.2（基線＋可抽集合逐團比對＋進探針簽字）。
  - R2 探針不收斂 → 三輪熔斷。
  - R3 新字型授權 → §4.3 逐枚。
  - R4 個人資料進 repo → 曲庫匯出與比對只在暫存目錄；對照檔與基線只有樂團名、目標值、元件代號（批 1 的使用者既裁定：樂團名可進 repo、不放每團曲數——本檔只寫各群總數）。
  - R5 xcodegen 在 iCloud 同步目錄留下「 2.xcodeproj」副本（現況已有兩個未追蹤副本）→ 逐檔 `git add`，副本不動、不刪（刪除要問）。
- 回退：未簽字＝不進表；整批在本機 `wip/lyrics-fx-b2-batch2`，checkpoint 不 push、不併回。

## 9. 紅燈摘要／量測／探針記錄（實作時回填）
### 9.1 T0（2026-10-09，`wip/lyrics-fx-b2-batch2`＝be91ed3）
- 全量單元基線（be91ed3 原始碼；`-only-testing:AzathothsWhisperTests`、`-test-timeouts-enabled YES -default-test-execution-time-allowance 120`、`-enableCodeCoverage YES`）：**1169 tests／137 suites，8 issues**。
  - skip 清單（1 條）：`AzathothsWhisperTests/BatchOverlappingLoadTests/overlappingLoadSuspendsPollingUntilLastCompletes()`。
  - 固定紅（7 斷言，同批 1 記錄）：suite `CoverFlowStripRenderGeometry`——「視口中心的封面正面朝人，兩側依距離漸次側轉」1 條（`CoverFlowStripRenderGeometryTests.swift:234`）、「首項與末項吸附後同樣正面朝人」initialCenter＝1、4、5、6、7、8 共 6 條（`:288`）。
  - **新觀察到的不穩定紅（1 條）**：`LyricsFXProbeRenderTests/writesStillsGIFsAndManifests()` 超過 120 秒時限。同一份建置單獨重跑兩次：一次 59.4 秒通過、一次再度超時。已核：當時機器 load average 約 18，另一個專案的 session 正在跑 node 測試。**推測**（推理鏈：同一份建置、同一條測試，耗時 59 秒到超過 120 秒不等；它要離屏渲染數千張圖，純吃 CPU）：是負載相依的超時，不是程式錯。批 1 記錄的基線沒有這一條（當時是否曾超時：TBD，沒有記錄）。不跳過、不放寬時限；本批各次全量若它紅，照實列為「基線已知的不穩定紅」，並另案交使用者決定（縮小渲染量／單獨給時限／移出預設全量）。
- 工具：五支腳本放在 `docs/plans/2026-10-03-lyrics-fx-assets/tools/`（`lib.js`、`check.js`、`need.js`、`export_signed.js`、`gen_swift.js`，另留批 1 的 `t7-batch1.sh` 與 `composer.before-b2.js`）。驗證：`check.js --batch 1 --before composer.before-b2.js` 結束碼 0，「與 b2-batch1-signed.json 逐槽差異數 0」；`need.js --batch 1`＝合格元件 63、app 已有 63、要新做 0；`export_signed.js --batch 1 --dry` 的 `bands` 與 repo 內對照檔相等（補上 Coldplay 的 3 個別名後）。

### 9.2 T1（2026-10-09）
- **紅**：新測試先寫，`build-for-testing` 編譯失敗——`type 'SongProfileResolver' has no member 'batchThree'`（`B2BatchTwoTests.swift:17`、`ArtistOverrideTableTests`、`LyricsFXContrastTests`）。
- **綠**：加入空的 `SongProfileResolver.batchThree` 後，跑 `PlayableSpaceTests`、`ExistingBandCandidatesTests`、`B2SignedFixtureTests`、`BackdropPaletteToneTests`、`B2EffectTests`、`ArtistOverrideTableTests`、`LyricsFXContrastTests`、`B2BatchTwoSignedFixtureTests`：29 tests，紅只有 `B2BatchTwoSignedFixtureTests` 的 4 條（`b2-batch2-signed.json` 還不存在——要等簽字後由 T3 匯出，屬預期的紅）。
- 基線檔：`TEST_RUNNER_AZW_PRINT_FX_BASELINE=be91ed3 xcodebuild test … -only-testing:"AzathothsWhisperTests/ExistingBandCandidatesTests/printTheBaseline()"`，測試輸出原文 sha256 `24e8134ca2577400730a45d96e27a81d09b7da7f0ab59578834d45e505729f54`；存檔時只重排縮排與鍵序。37 團、其中 mono 7 團（F5）。
- `everyPlayablePairStaysReadable` 在既有 37 團上**綠**——現有的表沒有任何一團會走到「回退成不相容配色」而低於對比門檻，V5 末項的處置目前用不到。
- 可抽空間的列舉經 37 團 × 2,000 種子連抽驗證無漏；「排除上一次」的不對稱（第二效果不避上一次的第二效果）有測試釘住。
- 未跑：這一步之後的全量單元（只動了測試與一個空陣列；全量留到 Phase 3）。

### 9.3 T2 原型設計＋預檢（2026-10-09，使用者同日確認執行 §2.1 之後）
- 原型（未追蹤的 `composer.js`／`lyrics-fx-preview.html`，由 `tools/patch_b2_2.py` 從 `tools/*.before-b2-2.*` 重建；本機探針頁 `lyrics-fx-preview-local.html`＝加上編碼宣告的同一份）：
  - 新團 7 個目標值；新標籤 4 個：`melodichc`（Rise Against）、`ska`（The Interrupters）、`powerpop`（Weezer）、`poprock`（Fall Out Boy、Mayday Parade）。Fall Out Boy 另掛既有的 `arena`、Weezer 另掛既有的 `indie`（只是讓它們抽得到批 1 的元件；新元件一律不掛批 1 九團有的標籤）。
  - 新元件 29 個：字型 6（Bangers、Permanent Marker、Saira Stencil One、Rubik、Lilita One、Gochi Hand）、背景 5（xerox、gig、checker、bokeh、skyGrad）、進場 3（skank、punch、ease）、退場 3（snapOut、rip、drift）、效果 2（jitter、tilt，都是停留時的小動作）、配色 9（gigRed、skateTeal、twoTone、twoToneLight、mallPink、weezBlue、chalk、polaroid、daydream）。既有 22 個元件只加新標籤。新動作全部用既有的動作基元組合，不新增基元（tilt 除外：一個固定小角度）。
  - 連帶 6 團的目標值原樣，只標進本批（不抽靠サビ／關鍵字觸發的效果，與 app 一致）。
- `check.js --batch 2 --before tools/composer.before-b2-2.js --linked <6 團>`：**OK**——13 團每槽合格數最少 3；沒有任何可抽背景缺相容配色；400 次實抽 0 筆亮暗違規；其餘 31 個既有團合格集合變動 0。批 1 九團與 `b2-batch1-signed.json` 逐槽差異 0。
- `need.js --batch 2`：本批合格元件 82 個，app 已有 43，**要新做 39**（以 need 輸出為準：字型 8、背景 6、進場 5、退場 4、效果 4、配色 12；其中原型早有但還沒進 app 的是字型 Dela Gothic One／Fredoka、背景 flat、進場 pop／tumble、退場 tumbleOut、效果 speedlines／paper、配色 mono／sunsetInk／yellowBlack）。
- 新配色的純色字底對比（WCAG 公式）：9 個新配色主字 5.70–19.68，全部 ≥ 4.5（weezBlue 最低 5.70）。含背景質感的實測留給 app 端 `LyricsFXContrastTests`。
- **預檢結果（`precheck.js`，推翻 §2.1「逐對象三選一」的可行性）**：
  - 移植時新元件只帶「本批專屬標籤」（punk、skatepunk、rock、poppunk、77punk、poprock、melodichc、ska、powerpop——即本批各團的標籤扣掉其他既有團也有的），外溢到其他既有團的槽數＝0。→ 做法改變：**app 目錄的標籤不再整份照抄原型**，新移植的元件只收本批專屬標籤，其餘標籤等它們的團進批次時再補（批 1 照抄正是龐克團被連帶翻掉的原因）。
  - 5 個連帶對象 × 三態＝243 種組合，零副作用可落地的只有 **1 種：全部新版**。原因（已核）：新團與舊龐克團共用 punk／skatepunk／poppunk 標籤，替任何一個舊團拿掉標籤，都會連帶拿掉新團或其他舊團的元件。
  - 整組退路（放寬為「新團可以跟著變」）：全部舊團留現狀或退回單色都做得到，其他既有團不受影響，但 NOFX、Good Charlotte 會有槽剩 0 個元件（它們只有舊標籤），必須另給它們新標籤、重排後再看一輪。
  - 結論：探針上舊團的「現狀」「單色」只供對照；實際可選的是**整組新版**，或**整組不要**（→ 再一輪）。對使用者如實說明，不呈現逐團任選。
- 探針頁自測（Chrome 開本機檔，腳本逐一點 12 個對象、各抽 30 組、拖動時間軸、切三種狀態）：繪製錯誤 0；11 種背景都實際畫過；8 套要用的網路字型都載入；舊團三態切換正常。未做：人眼看動態（這是使用者的部分）。

### 9.4 T3 探針回饋（進行中）
- **P14（2026-10-09，本機探針頁 v15）**：使用者：「整體上還差不多，沒什麼問題」；「Blink-182、Sum 41 和 Green Day……可以把勒索信的這個效果加進去」。
  - 查證：當時這三團抽不到勒索信——原型的 `paper` 只掛 `77punk`（Ramones、Sex Pistols）。這是 2026-10-03 的規則（母計劃 §2.10：「勒索信風格不適合 The Offspring，Blink-182 勉強，Green Day 一半一半」），本次由使用者改為三團都給；The Offspring 維持不給。
  - 第一次嘗試（已撤回）：直接替 `paper` 加 `poppunk` 標籤 → 三團合格但排不進前 5 名（`paper` 的向量照 77 龐克定，粗糙 .8），實際抽到 0 次。
  - 做法：新增元件 `paperPop`（畫法與 `paper` 相同、向量照流行龐克定、標籤 `poppunk`、戲劇 ≥ .4 禁用）。1,000 次組合裡兩個效果槽任一抽到勒索信的次數：Blink-182 446、Green Day 388、Sum 41 607、Ramones 730、Sex Pistols 787；The Offspring 與 7 個新團皆 0（Good Charlotte、Fall Out Boy、Mayday Parade 雖有 `poppunk`，被戲劇門檻擋掉——使用者只點名三團，不擴大）。
  - 重跑：`check.js` OK、預檢外溢 0、要新做的元件 39 → 40。
  - 其餘 9 個對象：使用者以「整體沒什麼問題」概括，**尚未逐團簽字**。

- **簽字（2026-10-09）**：使用者看 P14 修改後：「嗯，這回對了。行，就這樣」→ 12 個對象全數簽字；連帶團整組採用新版。命中率：7 個新團在曲庫各只有一種寫法，正規化後全中，無別名、無碰撞、無 `unassigned`。

### 9.5 T4–T6、T8（2026-10-09）
- 簽字後的偏離（照實告知使用者）：
  - **Fredoka 不進本批**：google/fonts 只剩 wdth＋wght 兩軸的可變字型（靜態 Fredoka One 已 404），`everyCatalogFontIsRegistered` 只收「無可變軸或只有 wght」的字型。原型拿掉它的 poppunk 標籤，Lilita One 頂替；`check` 重跑 OK。
  - **勒索信效果改名 `ransom`／`ransomPop`**：原 id `paper` 與報紙背景撞名，app 目錄以 id 查元件會查到背景（`CatalogValidator`「paper：id 重複」抓到；連帶造成紙片不出現、The Offspring 等團「抽到 paper」的假象）。
  - **Weezer 的正藍配色調深**（#0E6BA8 → #0A5A8F）：真實渲染（暈影＋顆粒）下主字對比 3.99–4.44，未達 4.5。
  - Dela Gothic One 字型檔 2.5 MB（含日文字形），app 體積隨之增加。
- 紅：新測試先寫，編譯失敗 14 類（`EnterTemplate.tumble`、`ExitTemplate.tumbleOut`、`HoldTemplate.jitter／tilt`、`LayerDraw.rects`、`ColorSlot.paperRed／paperYellow`、`BackdropKind.flat／gig／bokeh` 等不存在）。
- 第一次全量（實作後）：1197 條，紅 = 基線 7 斷言＋新紅 9 條——撞名（4 條）、Weezer 對比（2 條）、測試把新團數寫成 8–12（1 條，測試寫錯；實為 7）、探針渲染超時（基線已知不穩定，見 §9.1）。修正後第二次全量：**1197 tests／143 suites，紅＝基線 `CoverFlowStripRenderGeometry` 7 斷言**（探針渲染這次未超時）。
- 閘門：`no_playback_gate.sh` 0；`coverage_gate.sh <xcresult>` Services+Infra 96.2%；`Scripts` Python 測試 333 條 OK。
- 連帶團資料：與 be91ed3 基線不同的既有團正好是 6 個簽字連帶團（其餘 31 團合格集合與可抽空間零差異）；它們的可抽空間由 app 算出寫進對照檔 `linked[].playable`。
- 移植方式：`gen_swift.js --batch 2` 由原型產生 39 個元件列（標籤只收本批專屬的 9 個），另替 16 個既有元件補 30 個本批標籤；`tools/apply` 腳本套用（中途一次因 shell 引號錯誤只套了一半，已從 checkpoint 內容重新套用，半成品備份在 session 暫存區）。
- T8：ACCEPTANCE I-26 字型清單、新增 I-33–I-36；三語 README 字型授權表；母計劃附錄 B 補 P13 指引與 P14。
- 未做：T7 真視窗每幀量測與 UI 測試實跑（需使用者在場）；Phase 3 評審。

### 9.6 Phase 3 評審（/simcodex，2026-10-09；R2 提前結束）
| 輪 | 來源 | 採納並修 | 駁回／延後（理由） |
|---|---|---|---|
| R1 | codex review（--base be91ed3） | 無正確性問題 | — |
| R1 | simplify：效率 | 失焦光斑每幀 14 次全畫布漸層填色 → `.radialGlow` 在最外圈透明時只填光圈外接方框（畫面相同；既有光暈一併受惠）；兩條對比測試不重量同一組合（新那條 25 s → 0.02 s） | 2,000 種子降到 400：駁回——實測 16 s，遠低於 120 s 時限，且 V4 明定 2,000 |
| R1 | simplify：重用／深度 | 兩條對比測試共用 `readabilityFailure`；「不得走回退」改用可抽空間判定（不再手寫亮暗規則，且更嚴）；勒索信紙色與字色成對（`paperStock`）；每字種子只算一次；基線比對改整筆相等 | 刪除舊對比測試 `mainTextStaysReadableOnEveryReachableBackdrop`：駁回——它涵蓋「合格但目前排不進前 5」的配色，比新的嚴，V5 與 Codex 已議定保留。合併批 1／批 2 對照測試：駁回——會改掉 ACCEPTANCE 引用的測試名。停留模板優先序改資料表、id 改按槽查詢、`ColorSlot` 固定色拆型別、`Composer` 抽出可抽空間：P2 延後 |
| R2 | simplify（四角度合併，只看 R1 修正） | 無 P0／P1；採納一條 P2：光圈裁切加上「最外圈位置 ≤ 1」的條件，讓畫面相同由條件保證 | 其餘 P2 延後（`PaperScrap` 可直接存 tuple；`everyPlayablePairStaysReadable` 名稱已較實際範圍寬，註解已說明） |
| R2 | codex review（--uncommitted） | 無 | — |
- 無安全敏感改動（無認證、無網路、無新的檔案寫入路徑；字型是一次性下載進 repo），未派 security-reviewer。
- 評審後全量：**1197 tests／143 suites，紅＝基線 `CoverFlowStripRenderGeometry` 7 斷言**；`no_playback_gate.sh` 0；coverage Services+Infra 96.2%。

### 9.7 使用者在場（2026-10-10；只接內建螢幕、ABC 輸入法）
- **UI 測試**：`LyricsFXUITests`（9，含新增的 Weezer 一條）＋`LyricsFlowUITests`（9）**18／18 綠**，同一輪、一次過（328 s）。
- **T7 每幀**（-O 量測建置、真視窗在前景、dense 預覽、主執行緒 plan＋Canvas 編碼；每份 6 個 5 秒窗，丟第一個當暖機，取 5 個；12 份皆全程最前景）。配方：其餘槽固定取最重者——背景 bokeh（一幀 14 個光圈，本批 LayerDraw 最多）、效果 ransom＋speedlines（每字一張紙、24 道線）、進退場 tumble／tumbleOut、配色 polaroid；另各測一次 xerox、gig、checker 背景：
  | 配方 | p50 | p95 | 判定（2 ms／3 ms） |
  |---|---|---|---|
  | 字型 Bangers | 0.59–0.73 ms | 1.16–1.28 ms | 過 |
  | 字型 Permanent Marker | 0.73–0.98 ms | 1.42–1.54 ms | 過（本批最重） |
  | 字型 Saira Stencil One | 0.55–0.68 ms | 1.00–1.18 ms | 過 |
  | 字型 Rubik | 0.64–0.75 ms | 1.15–1.28 ms | 過 |
  | 字型 Lilita One | 0.66–0.78 ms | 1.15–1.28 ms | 過 |
  | 字型 Gochi Hand | 0.65–0.84 ms | 1.30–1.41 ms | 過 |
  | 字型 Dela Gothic One | 0.53–0.66 ms | 0.99–1.21 ms | 過 |
  | 效果 jitter（＋ransom） | 0.59–0.64 ms | 1.02–1.23 ms | 過 |
  | 效果 tilt（＋ransom） | 0.49–0.71 ms | 0.72–1.20 ms | 過 |
  | 背景 xerox | 0.54–0.69 ms | 1.10–1.31 ms | 過 |
  | 背景 gig | 0.59–0.70 ms | 1.08–1.28 ms | 過 |
  | 背景 checker | 0.46–0.62 ms | 1.08–1.25 ms | 過 |
  - 全數「過」，不需豁免；②（字形點陣快取）的觸發條件仍未成立。
  - 未量：光圈與暈影的漸層在 render server 合成，不在這個數字內（批 1 §7.6 同）；本批沒有新增要真模糊的效果種類，故不另錄 render server。
- **真視窗預覽**：依序開 Weezer、The Interrupters、Rise Against、Blink-182、Mayday Parade 各約 20 秒（組合器自抽）。使用者：「都沒問題」（2026-10-10）。

## 10. 待拍板
1. **確認執行 §2.1**（批 2＝B 群切分版 12 個簽字對象；連帶團三態選項＋B2 修復例外）。
2. （預設照做，不對請說）連帶團進探針一起簽；說「不對」的回到基線。

## 附錄 A　計劃評審記錄
### A.1 R1（gpt-5.6-terra／medium，2026-10-09；無 P0；引用已逐條核對程式碼）
| # | Codex 意見 | 裁決 | 理由／落點 |
|---|---|---|---|
| 1 | P1 既有團沒有可比基線，V4 驗不了 | **採納**（Codex 勝） | 已核：`theB1BandsNeverGainThinSlots` 只釘薄槽、批 1 對照檔只有 9 團 → §4.2 基線檔＋`ExistingBandCandidatesTests` |
| 2 | P1 只查 mono→組合 漏掉「本來就是組合、多了新元件」 | **採納**（Codex 勝） | 連帶團改定義為「可抽集合有任何差異」→ §4.2、V4 |
| 3 | P1 「候選」混用兩層（fit>0 與前 5 名） | **修改採納** | 已核 `Composer.candidates` 取前 `shortlist`=5。分成合格／可抽兩詞（F3b）；既有團保護鎖**可抽**（由 app 算）。對照檔的 `candidates` 仍存合格集合：原型與 app 的同分定序不同，可抽集合跨兩邊不可比，合格集合才可比（批 1 §7.3 同理） |
| 4 | P1 合作曲只能歸一團，V1 分母矛盾；「先列者」是未簽字的審美決定 | **採納**（Codex 勝） | §4.5：不歸任何一團、記 `unassigned`；V1 分母改為「歸給該團的寫法」 |
| 5 | P1 對比測試測的是 fit>0 的組合，不是實際可抽；應改成逐團可抽並帶團名 | **部分駁回** | 已核 `reachablePairs` 用 fit>0＋亮暗相容——是可抽組合的**超集**，通過即蘊含可抽者通過，方向保守；改寫既有測試屬範圍外。採納的部分：V5 文字改成照實描述，並訂「紅在無人可抽的組合上＝停下報告，不自行縮範圍」 |
| 6 | P1 V7 的通過條件自相矛盾 | **採納**（Codex 勝） | V7 改三態（過／豁免過／不過）並寫明配方與量測範圍限制 |
| 7 | P1 產生器進 repo 但輸入不在 repo，無法重現 | **採納**（Codex 勝，取其較簡方案） | 工具不進 repo，放原型旁；「由產生器產生」降為做法，不當驗收項 |
| 8 | P2 四支 JS＋Python 包裝偏重、無 Node 契約 | **採納** | 隨 #7 一併取消 |
| 9 | P2 「抽籤位元相同」沒有可執行定義 | **採納（改採更簡）** | 不改名 `b2:true`，就沒有要證明等價的東西；T0 的 DoD 改為與批 1 對照檔逐槽相同 |
| 10 | P2 V3 驗不了「由產生器產生」 | **採納** | 同 #7 |
| 11 | P2 行號與 suite 名不精確 | **採納** | 改以符號名引用；suite 名更正為 `B2SignedFixtureTests` |

### A.2 R2（2026-10-09；R1 #3 我的修改 Codex 同意）
| # | Codex 意見 | 裁決 | 理由／落點 |
|---|---|---|---|
| 1 | P1 駁回我對 R1 #5 的理由：`compatiblePalettes` 無相容合格配色時回退成全部配色，這時抽得到的不相容組合不在 `reachablePairs` 裡——不是超集 | **採納（Codex 勝，我在 R1 #5 的論點不成立）** | 已核 `Composer.swift` `compatiblePalettes` 末行的回退與 `reachablePairs` 的無條件排除 → V5 新增兩條測試；既有團若紅交使用者決定 |
| 2 | P1 配色的可抽集合取決於背景，「每槽前 5 名」會漏 | **採納**（Codex 勝） | F3b、§4.2 改成可抽空間（`paletteByBackdrop`） |
| 3 | P1 第二效果是排除第一效果後重取前 5，第 6 名也抽得到 | **採納**（Codex 勝） | 同上（`fx1`、`fx2` 分開列，精確列舉；種子測試只當防漏的煙霧測試） |
| 4 | P2 基線由人手存檔，來源與正確性無從驗證 | **採納** | 檔頭記 schema／sourceRevision／產生測試；命令與 sha256 記 §9 |
| 5 | P2 V5「無人可抽的組合」分支不可能觸發 | **採納** | 已核 `reachablePairs` 逐團建立；該句刪除 |
| 6 | P2 「紅＝基線」「依記憶 skip」不可重現 | **採納** | T0 在 be91ed3 記完整失敗識別名與 skip 名 |
| 7 | P2 V7 配方選法不可判定 | **採納** | 選法規則與暖機窗寫進 V7，配方表先記 §9 再量 |
- 兩輪合計 Codex 提 18 條：採納 15、修改採納 2（R1 #3、#9）、R1 #5 我部分駁回後在 R2 被推翻。逐條核過程式碼；R1 #3 我保留「對照檔存合格集合」獲 Codex 同意。

### A.3 R3（2026-10-09；確認輪，**無 P0／P1**，提前結束）
| # | Codex 意見 | 裁決 | 落點 |
|---|---|---|---|
| 1 | P2 可抽空間沒先處理整體退 mono，會多報連帶團與對比紅燈 | **採納** | 已核 `compose` 的 guard；F3b、§4.2、V5 |
| 2 | P2 「排除上一次」對第二效果不對稱，描述不足 | **採納** | 已核 `pickEffects`；F3b、煙霧測試加斷言 |

### A.4 選群辯論（/thecure，gpt-5.6-terra／medium，2026-10-09）
| # | 論點 | 提出方 | 狀態 | 證據 |
|---|---|---|---|---|
| R1-1 | 批 2 做 B 群 | 我 | 一致（結論成立，理由要修） | 播放統計；F5 |
| R1-2 | B 會「順手收掉」批 1 的欠帳 | 我 | **Codex 勝**：否決時回到的是 be91ed3 基線＝薄風格，不是單色 | §4.2 基線產生時點 |
| R1-3 | 9 新團＋5 連帶＝14 團仍算一批 | 我（自列弱點） | **Codex 勝**：連帶團一樣要看要簽，超過 8–12 | 批 1 計劃附錄 A R4-3 |
| R1-4 | 另開小修把龐克團退回單色、批 2 做 A | 我（自列備案） | **Codex 勝**（否決該備案）：一樣要簽字，沒省決策成本 | — |
| R2-1 | 連帶團逐團自由三選一 | 我 | **Codex 勝**：Ramones／Sex Pistols 標籤與空間相同，逐團選會無解 → 相依矩陣＋預檢 | `SongProfileResolver.swift` bandTargets；基線檔 |
| R2-2 | Sex Pistols 放第 13 格 | 我 | **Codex 勝**：仍是簽字對象 → 與 Ramones 綁成一個 | 曲庫 0 首 |
| R2-3 | 退回單色算不算違反純加法 | Codex | 採納 → 明列為窄例外 | §3 |
| R2-4 | V4 只比可抽空間不夠；要護住批 1 九團；對照檔要記決定 | Codex | 採納 | `ExistingBandCandidatesTests` |
| R3 | 整體確認 | — | Codex：「無異議」 | — |
- 我方立場只有「選 B」這個結論站住，支撐它的做法幾乎全被改寫；最深的一個錯是以為「把連帶團放進探針」就等於處理了批 1 的未簽字變更。
