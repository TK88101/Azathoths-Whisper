# Lyrics FX — 署名團補元件（B2 批 5：工業／電子 5 團）實施計劃 v1.0 定稿（Codex 3 輪收斂；使用者 2026-11-01 拍板）

母計劃：`docs/plans/2026-10-03-lyrics-fx-mode.md`（§2.10、附錄 B P1–P16）。流程與測試推進**重用** B2 批 4 計劃 `docs/plans/2026-10-13-lyrics-fx-b2-batch4.md` §2.5–§2.7、§4–§7（下稱「批 4 計劃」），本檔只寫差異。上游：⑧ 曲庫閘門 `docs/plans/2026-10-28-lyrics-library-gate.md` §5 依賴順序（工具完成 → **本計劃** → 更新 `ReadabilityPolicy.audited`、重跑 T2 → ⑧ T10–T11）。

## 0. 複述
- 目標＝樂團表裡**組不出**（播放時素面）的 5 個工業／電子署名團，補上使用者簽字的元件，讓每團都有可播放空間；⑧ 的「署名待補元件」歸零。Cannibal Corpse 移出本批（§2 F6、§8）。
- 完成標準＝§4 V1–V8。
- 不做＝§3 非目標（尤其：不給通用零件、不做署名替換、不改這幾團以外任何團的候選）。
- 模式：normal（每輪收斂要等使用者看探針，loop 換不掉這個等待）。任務形狀：串行（T4–T6 共寫 `LyricsFXCatalog.swift`、`ComposedStyle.swift`／`ComposedBackdrop.swift`／`GlyphTemplates.swift`），不派實作子 agent。

## 1. 使用者決定（既定前提，不重議）
1. 署名 4 團另立補元件計劃並簽字；⑧ 照實另欄列出、計入 G-COMP、擋閘門；**不提供替換署名樣式、不用通用零件**（⑧ §10-1，2026-10-28）。
2. 通用零件只帶新的私有標籤，樂團表的團一個都不給（⑦ §1-1，2026-10-25）。
3. P10：**工業金屬與 Nu-Metal 不共用任何元件**；工業專屬元件＝鋼灰＋火焰紅／純黑＋一種紅、冷鋼板＋頂燈、行首火焰噴發、整詞重砸（行軍節拍）、每詞整屏下沉、字緣灼熱紅光、燒盡退場、紀念碑式大寫／德式 fraktur（2026-10-04）。
4. P9：電子團（Chemical Brothers、Fatboy Slim、Daft Punk）要有各自的變體（2026-10-03）。
5. 讀不到歌詞的效果不可；已拿掉 slam（2026-10-19，adaa1fd；I-54～I-57）。禁止 condense＋cut 組合。
6. P14 勒索信只給指定龐克團；P15 已代表某一群的元件不借給別群。

## 2. 已核事實（2026-11-01，wip/lyrics-library-gate 3f742da 原始碼）
- F1 **組不出的署名團 6 團**（工作樹 3f742da；以 `Composer.isComposable` 的規則讀碼重算，與 ⑦ §2.1 一致，Codex R1 讀碼確認；T0 以程式重核並列出每團各槽實際候選數——「缺槽」＝該槽 0 個合格候選，與 V1 的「每槽 ≥ 2」是兩種不同判準）：

| 團 | 標籤 | 缺的必選槽 | 備註 |
|---|---|---|---|
| Rammstein | industrial | font、enter、exit、palette | 曲庫 78 首 |
| The Chemical Brothers | bigbeat、electro、techno | palette | |
| Fatboy Slim | bigbeat、house、electro | palette | |
| Daft Punk | frenchhouse、house、electro | enter、palette | 曲庫 54 首 |
| Aphex Twin | idm、ambient、techno | palette | |
| Cannibal Corpse | death、grind | enter | 拿掉 slam 後變素面（adaa1fd commit 訊息「Cannibal Corpse 暫時 mono」） |

  曲庫裡有 4 團、178 首（⑧ 附錄 H 真機計數；Rammstein 78、Daft Punk 54 已核，其餘兩團合計 46 首、哪兩團 **TBD**，T0 由報表核）。
- F2 **原型早就有這幾團的元件，只是沒搬進 app**：`docs/plans/2026-10-03-lyrics-fx-assets/composer.js` 的 TARGETS 含這 5 個工業／電子團（P9、P10 時使用者看過原型），B1 只移植黑金屬／交響子集，B2 批 1–4 也沒處理電子群。原型對照（`scratchpad/protodiff.py` 唯讀比對）：
  - **app 沒有的原型元件**：字型 OswaldInd、FrakturInd（沿用已內建的 Oswald、UnifrakturMaguntia 字檔）、Fredoka（**新字檔**）；背景 pyro、steel、strobe（頻閃每 0.5 s）、neon；進場 march（整詞重砸，wordLevel）；退場 burnout；效果 stomp、heat；配色 steelFire、blackRed、neonPink。
  - **app 有、但移植時拿掉了電子標籤的元件**（同掛即可，無繪製改動）：字型 SpaceMono（electro、house、idm、techno）、Dela（bigbeat、electro、house）；背景 grid（electro、idm、techno）、flat（bigbeat）；進場 pop（house、frenchhouse）、flip（electro、idm、techno）；退場 tumbleOut（bigbeat）；效果 rgbsplit（bigbeat、electro、techno）、speedlines（bigbeat）；配色 terminal（electro、idm、techno）、mono（bigbeat、techno）、yellowBlack（bigbeat）。
- F3 **標籤隔離（零連帶的前提；profile 層級的不交集命題，R1-5）**：隔離集合 X＝{`industrial`、`bigbeat`、`electro`、`techno`、`house`、`frenchhouse`、`idm`、`ambient`}。讀碼：X 只出現在這 5 個署名團的**目標值**；批 2–5（`batchTwo`…`batchFive`）沒有任何團帶 X；關鍵字列（`row(...)`）沒有以這 5 團為代表團；⑦ 的通用列 industrial／electronic／ambient 只帶私有 `gen*` 標籤（`SongProfileResolver.swift:242-258`）。注意：X 的標籤**早已存在於目錄**（例：`Grotesk`、`haze`、`fadeUp` 帶 ambient／idm／house），隔離成立的理由是「其他 profile 不帶 X」，不是「元件不帶 X」。→ 新元件或同掛只加 X 內的標籤時，其他署名團與所有關鍵字列的候選**機械性不變**。T0 以程式輸出「每個既有 band／關鍵字列／通用列 profile 的標籤 ∩ X」，應全為空（除這 5 團）。
- F4 工具（未追蹤、還在）：`docs/plans/2026-10-03-lyrics-fx-assets/tools/` 的 `check.js`、`need.js`、`precheck.js`、`export_signed.js`、`gen_swift.js`、`build_page.js`、`patch_b2_4.py`，皆吃 `--batch <n>`。對照檔慣例 `Tests/Fixtures/LyricsFX/b2-batchN-signed.json`；基線 `band-candidates-baseline.json` 目前 `sourceRevision` c6e0a53（拿掉 slam 時就地改過）。
- F5 署名層不檢查 `isComposable`（`resolve` 呼叫 `explain`，`explain` 的第一個分支直接回署名結果，`SongProfileResolver.swift:277,292`）：補完後這 178 首會直接變成有特效，**不需改 resolver**；以端到端測試證明（V1）。
- F6 **Cannibal Corpse 不在本批**（R1-3）：它缺進場，標籤是 `death`＋`grind`；`death` 是多團共用，`grind` 也不專屬——death 關鍵字列（`SongProfileResolver.swift:222`，代表團 Cannibal Corpse、Fleshgod Apocalypse）的標籤是代表團聯集，帶 `grind`；`cut` 退場也帶 `grind`。所以給它新進場只有兩條路：改它的目標值（加私有標籤，違反「目標值凍結」）或連帶 death 系多團與 death 列重簽。它不在曲庫、對 ⑧ 閘門無影響 → 另立後續計劃（§8-3）。
- F7 **既有模板夠用的部分**（讀碼 `GlyphTemplates.swift:60-68`）：進場模板已有 `drop`、`stamp`；原型 march＝`{drop:3, stamp:3}`＋`wordLevel:true`。關掉 `wordLevel`（逐字而非整詞）就是純資料元件，不需新繪製程式，也不是 slam 的「整詞一起砸」。
- F8 **背景沒有「目前行」資訊**（R1-2，讀碼 `ComposedBackdrop.swift:11`）：背景繪製只收 backdrop／palette／size／time。原型 pyro（行首噴發）與 strobe（以 `t − 行首` 決定閃光）都要行首時間，照現有 API 無法忠實移植。

## 3. 目標與非目標
- 目標：5 團各有可播放空間（V1）；使用者在探針上簽字；⑧ 曲庫檢查的「署名待補元件」＝0、G-COMP 少 178 首。
- 非目標：
  - 通用零件、署名替換、改任何團的目標值（5 團的目標值凍結於原型＝app 現值）。
  - Cannibal Corpse（F6，另立計劃）。
  - **strobe（頻閃）不搬**（R1-7：整屏閃光的安全性不只看頻率，還要面積、亮暗變化、使用者設定；本批不承擔）。原型保留，日後要做另立計劃先定安全規格。
  - 其他署名團與關鍵字列的候選／可抽空間（V4 機械證明零差異）。
  - ⑧ 的閘門通過判定本身（T10–T11 仍在 ⑧）；`ReadabilityPolicy.audited` 的更新只做到「本批新增的背景×配色組合進稽核」。
  - 契約凍結照批 4 §3（六槽語意、FXTag 匹配規則、十軸、fit 不平方、無候選退 mono），只做純加法。
  - commit／合併／push：等使用者拍板（wip/ checkpoint 例外，不 push）。

## 4. 驗收標準（每條可判定）
- V1 5 團皆 `PlayableSpace.of(profile) != nil`；五個必選槽每槽 ≥ 2 個合格候選；**每個入選背景都至少有 2 個未被 `ReadabilityPolicy.unreadablePairs` 禁止、且亮暗相容的配色候選**（R1-1：`compatiblePalettes` 濾完沒配色仍會 mono）；另有 5 團的「解析＋compose」端到端單元測試：`SongProfileResolver` 解析出署名結果、`Composer.compose` 回非 mono（R1-12）。
- V2 對照檔 `b2-batch5-signed.json` 把 5 團寫成 **`linked`、`decision: "new"`**（`bands: []`；既有署名團補件，沿用批 2 對 B1 龐克團的模型；`SignedBatchFixture.swift:42` 的 `Linked` 已有 `playable`）：`existingBandsOnlyChangeWhereTheUserSignedIt` 逐團比對 `eligible` 與 `playable` 都等於簽字值，且「有變的團」恰＝這 5 團；另加 batch 5 的 `linked` ⊆ 這 5 團（R2-2）。
- V3 隔離：本批**新元件**的標籤非空且 ⊆ X；本批**同掛**只加 X 內的標籤；除這 5 團外，所有 band／關鍵字列／通用列 profile 的標籤 ∩ X＝∅（測試）；P10 機械檢查照舊（`industrial` 元件 ∩ `nu` 元件＝∅）；**歸屬白名單**（R2-6）：測試內寫死本批新增與同掛的（槽, id）與允許的團，Rammstein 的每個合格進場都必須在白名單內，且不帶 `FXTag.nuFamily` 標籤、不是黑金屬專屬元件（Catacombs、negative，P15）。
- V4 其他署名團（**全部 61 團扣這 5 團，含批 4 的 emo 7 團**）＋全部關鍵字列（含 ⑦ 通用列）相對 pre-批 5 基線零差異；`RecipeGoldenTests` 摘要只因這 5 團改變（變動範圍由測試列出、等於 5 團）。現行基線只含 54 團（c6e0a53，無 emo 7 團，R1-4 讀檔確認），所以 T1 先在**不改目錄**的狀態下重產含 `batchFive` 的 pre-批 5 基線。
- V5 可讀性：`LyricsFXContrastTests` 全套（G1 主字逐像素對比 ≥ 4.5、G2／G3 出退場可見）綠；新背景×配色組合全數進稽核。新繪製行為的分工（R1-8、R2-5）：**出場當下的可讀性交 G2／G3**（含逐字 march 的砸入）；**G1（離屏逐像素）量「字已完全顯示、但新效果仍在」的定點**——每種新行為明定 recipe（字型、進退場、效果寫死本批真的抽得到的）、時間、預期可見主字：pyro 的噴發窗要長於 Rammstein 各候選進場的最長時長（T4 定窗長並以測試釘住），G1 取進場結束後、噴發窗內一刻；heat 取停穩時；burnout 取變紅段內、字仍完全不透明的一刻；英／日文長短行各一；`unreadablePairs` 若要新增硬禁止，列出組合並在簽字時說明。
- V6 全量單元失敗集合 ⊆ T0 基線（完整名稱）；`coverage_gate.sh <單元 xcresult>` ≥ 80 %；`no_playback_gate.sh` 0；Scripts 測試綠。
- V7 使用者在場：`LyricsFXUITests` 全綠（新增一條：署名電子團不論 Apple 曲風都拿到組合樣式）；每幀量測沿用 `LyricsFXFrameMeter`（使用者這台 Mac、內建螢幕、畫布 1728×941、量測前查無其他 session 搶前景；warm-up 與樣本數照 B2 批 4 §9.7 的量法並記錄），分別量 steel、pyro 行首、heat、burnout 各一份配方：p50 ≤ 2 ms、p95 ≤ 3 ms；真視窗目視表態原話記 §9。
- V8 ⑧ 曲庫檢查重掃：署名待補元件 0；G-COMP＝補件前減 178（基線曲庫未變時）。

## 5. 任務清單（TDD：先紅後綠；紅燈摘要回填 §9）
| # | 任務 | DoD | 依賴 |
|---|---|---|---|
| T0 | 基線與事實重核 | 全量單元失敗集合＋skip 清單；以程式列出 `bandTable` 中 `isComposable` 為否的團（應＝F1 六團）與 5 團各槽候選數；輸出所有既有 profile 的標籤 ∩ X（應只有 5 團非空）；⑧ 報表列出曲庫裡的 4 團與首數；`check.js --batch 4` 與 `b2-batch4-signed.json` 逐槽差異 0（工具與原型沒走樣） | — |
| T1 | 測試推進到批 5 | **命名**（R1-4）：原型與對照檔叫「批 5」（`batch:5`、`b2-batch5-signed.json`），Swift 不新增 `batchSix`（5 團已在 `batchOne`，是既有團補件，同批 2 對 B1 龐克團的連帶做法）；測試檔 `B2BatchFiveTests.swift`。步驟：①目錄未改時以 `printTheBaseline()` 重產含 `batchFive` 的 pre-批 5 基線（61 團），`sourceRevision` 改為 T0 的 commit，`ExistingBandCandidatesTests` 就地推進（`:78` revision、`:79` 團名加 `batchFive`、`batchesAfterTheBaseline` 改 `[5]`、「不得列為連帶」加 `batchFive`）→ 綠；②**批 4 的兩條「新元件」測試退役改寫**（R2-3，`B2BatchFourTests.swift:65` 註解已預告）：重產基線前從 c6e0a53 基線算出批 4 新元件清單、貼成常數並記 sha256，兩條斷言（只帶 emo 私有標籤、至少一個批 4 團抽得到）改對這份清單跑；③先寫 `B2BatchFiveTests`（對照檔、隔離＋白名單、對比、端到端四個 suite）→ 讀檔／斷言紅 | T0 |
| T2 | 原型設計 | 第一步：把現行 `composer.js` 複製成 `tools/composer.before-b2-5.js`，記 sha256，並以 `check.js --batch 4` 對 `b2-batch4-signed.json` 差異 0 證明它是已驗證版本（R1-11）；之後 `patch_b2_5.py` 由它重建、可重跑。產出：**逐元件表**（元件 id、槽、現有 tags → 追加 tags、原屬哪個簽字群、受影響 profile＝只有 5 團）（R1-10）；march 改逐字版（`wordLevel:false`，F7）；strobe 不進 5 團可抽到的範圍（原型元件本身保留）；5 團每槽 ≥ 2；隔離矩陣；`need.js --batch 5` 清單；Fredoka 授權（google/fonts OFL 原文、來源 commit、版本、PostScript 名） | T1 |
| T3 | 預檢＋探針＋簽字 | `precheck.js --batch 5` 外溢 0、連帶 0；本機探針頁（`open` 本機 HTML；每團多抽幾組；Chemical Brothers／Fatboy Slim／Daft Punk 並排看是否各有變體，P9；Rammstein 標明「進場改成逐字版，不是原型的整詞重砸」）；一次一團請使用者回「對／不對＋一句」；回饋轉 P17 起；三輪不收斂熔斷；匯出 `b2-batch5-signed.json`（含 `playable`） | T2 |
| T4 | 新繪製行為 | **先定資料流**（R1-2、R2-4）：在 `ComposedStyle.plan` 既有的「目前行」判定（`ComposedStyle.swift:225` 的 `current`：可見、未退場、無殘留、`.composed`）取開始時間，以 `currentLineStart: Double?` 傳給背景繪製，背景用 `time − start`；間奏、空白行、只剩退場或殘留的行一律 nil（不噴）；減少動態效果開啟時整體已退 mono（`LyricsFXView.swift:373`），加一條測試釘住。之後每個新 Swift case（背景 pyro／steel／neon、退場 burnout、效果 stomp／heat；只做簽字後確實進目錄的）一條定點測試，先紅後綠；pyro 測行首、窗內、窗外、nil 四種 | T3 |
| T5 | 目錄＋字型 | `gen_swift.js --batch 5` 產生元件列與同掛；app 算出與 pre-批 5 基線不同的團＝這 5 團（多出＝停、回 T2）；Fredoka 入 `Resources/Fonts`＋OFL、`xcodegen generate`（逐檔 `git add`），`everyCatalogFontIsRegistered`／`eachBundledFontShipsWithItsLicence` 綠；About、三語 README 字型清單（照批 4 T5 慣例，R1-14 駁回） | T3、T4 |
| T6 | 可讀性與端到端 | `ReadabilityAudit` 涵蓋新組合；`ReadabilityPolicy.audited` 更新；UI 測試新增一條；建置成功 | T5 |
| T7 | 使用者在場 | UI 測試實跑（ABC 輸入法、先 `open -n` 點完鑰匙圈框）；每幀量測；真視窗目視；⑧ 曲庫檢查重掃（V8） | T6 |
| T8 | 文件 | ACCEPTANCE I 段新條（本批簽字、隔離、每幀；I-68 的署名待補元件改為已補）；母計劃附錄 B P17…；本檔 §9 | T3–T7 |
之後：Phase 3 `/simcodex` → 全量測試 → 證據包；commit／合併等使用者拍板。

## 6. 測試策略
同批 4 §6：單元（T1、T4、T5、T6）、整合（對照檔、對比離屏渲染）、E2E（UI 測試新增一條＋LyricsFX 全套；使用者在場）、閘門（`no_playback_gate.sh`、選擇器白名單、`coverage_gate.sh <單元 xcresult>`、Scripts Python）。測試字串自編，不用真歌詞。全量單元照例以完整名稱 skip `AzathothsWhisperTests/BatchOverlappingLoadTests/overlappingLoadSuspendsPollingUntilLastCompletes()`。

## 7. 影響面、風險、回退
- 改檔：`LyricsFXCatalog.swift`、`FXComponent.swift`（新 BackdropKind／FXEffect／模板 case）、`ComposedBackdrop`／`ComposedStyle`／`GlyphTemplates`（視新 case）、`ReadabilityPolicy`、`Resources/Fonts/*`、`.xcodeproj`、About、三語 README、`ACCEPTANCE.md`、母計劃附錄 B、`Tests/LyricsFX/*`、`Tests/Fixtures/LyricsFX/{band-candidates-baseline,b2-batch5-signed}.json`、`UITests/LyricsFXUITests.swift`。不改 `SongProfileResolver` 判定順序、目標值、Music 讀取、⑧ 掃描器。
- 風險：R1 工業元件串到 Nu 系（P10）→ V3 機械檢查；R2 新元件讀不清 → V5 G1–G3（含新行為的像素時刻）＋硬禁止；R3 頻閃光敏 → 本批不搬；R4 字型授權 → 只收 google/fonts 官方庫；R5 三個電子團候選太像（P9）→ 探針並排判斷，必要時加私有子標籤（屬改目標值 → 要使用者在探針時同意）；R6 每幀超標 → T7 量測；R7 xcodegen 副本 → 逐檔 `git add`；R8 背景多一個參數影響既有背景 → 既有背景不讀它，`RecipeGoldenTests` 與 G1 既有案例不變。
- 回退：未簽字＝不進目錄；整批在本機 wip 分支。

## 8. 待拍板（R1 後）
1. **Rammstein 的進場**：原型 march（整詞重砸）與 2026-10-19 拿掉 slam 同型，本批改為**逐字版 march**（同樣的砸入＋蓋章模板，一個字一個字來，F7）＋另一個候選（T2 的逐元件表給出；不得是 Nu 系或其他群的專屬元件，P10／P15）。在探針上給使用者看，他說不像就熔斷回報，不擅自改回整詞。
2. **Fredoka（新字檔，Fatboy Slim／house 用）**：OFL，照既有字型慣例搬。
3. **Cannibal Corpse**：本批不做（F6）。另立計劃時要使用者先決定：改它的目標值（加私有標籤）或連帶 death 系重簽。
4. **分支**：⑧ 的 `wip/lyrics-library-gate` 還沒合 main。⑧ 合 main 後從 main 開 `wip/lyrics-fx-b2-batch5`；若 ⑧ 暫不合，從 `wip/lyrics-library-gate` 疊上去開（V8 要 ⑧ 的報表）。

## 9. 紅燈摘要／量測／探針記錄（實作時回填）

## 附錄 A　計劃評審記錄

### A.1 R1（gpt-5.6-terra／medium，2026-11-01；3 阻擋、5 高、5 中、1 低）
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| 1 | 阻擋 | V1 只驗單槽，背景濾完配色仍可能 mono | **採納**：V1 改 `PlayableSpace`＋每背景 ≥ 2 可讀配色；對照檔鎖 `playable` |
| 2 | 阻擋 | pyro／strobe 要行首時間，背景 API 沒有 | **採納**：T4 先加「目前行開始時間」參數；strobe 不搬（見 7） |
| 3 | 阻擋 | Cannibal 備案＝改凍結目標值；grind 不專屬 | **採納**（讀碼確認 death 列帶 grind）：移出本批，F6、§8-3 |
| 4 | 高 | 批號與 Swift 名稱；基線不含 emo 7 團 | **採納**（讀檔確認基線 54 團）：T1 先重產 pre-批 5 基線；Swift 不新增 batchSix（5 團在 batchOne，屬既有團補件） |
| 5 | 高 | F3 敘述過寬（X 早在目錄裡） | **採納**：改 profile 層級命題＋T0 輸出交集 |
| 6 | 高 | march 改同掛沒保證兩個候選、可能碰 P15 | **採納並改方案**：逐字版 march（既有 drop／stamp 模板）＋T2 逐元件表列第二候選 |
| 7 | 高 | strobe 安全性不只頻率 | **採納**：本批不搬 |
| 8 | 高 | 幀資料稽核抓不到新效果的像素問題 | **部分採納**：不另起測試框架，擴大既有 G1 逐像素對比（③ 已是離屏渲染）到新行為的特定時刻 |
| 9 | 中 | F1 補 revision 與各槽候選數 | **採納** |
| 10 | 中 | 同掛要逐元件表 | **採納**：T2 產出 |
| 11 | 中 | `composer.before-b2-5.js` 不存在 | **採納**：T2 第一步建立並以 check.js 驗證 |
| 12 | 中 | F5 字面不精確；要端到端測試 | **採納** |
| 13 | 中 | 每幀量測條件不可重現 | **採納**：固定機器、畫布、量法 |
| 14 | 低 | About／README 字型清單是範圍外 churn | **駁回**：專案慣例（批 4 T5 同列），字型致謝與授權一致性；成本為每檔一行 |

### A.2 R2（2026-11-01；3 阻擋、3 高，其餘確認 R1 處置成立，含 #14 駁回）
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| 1 | 阻擋 | `SignedBatchFile.Band` 只解碼 `candidates`，鎖不住 `playable` | **由 2 一併解決**：5 團寫成 `linked`，`Linked` 已解碼並比對 `playable` |
| 2 | 阻擋 | 要另建「既有團補件」模型，不要偽裝成 linked | **部分駁回**：linked＋`decision: new` 就是既有語意——批 2 對照檔把 B1 的 The Offspring 等寫成 linked／new（`b2-batch2-signed.json:482-485`）。採納要點：逐團比對 eligible 與 playable、有變的團恰＝5 團、linked ⊆ 5 團（V2） |
| 3 | 阻擋 | 重產基線後批 4 的 `newComponents()` 變空 | **採納**：T1 ② 改成寫死的批 4 清單 |
| 4 | 高 | 目前行應由 `ComposedStyle.plan` 的 `current` 供給 | **採納**：T4 |
| 5 | 高 | G1 只量完全顯示的字，行首時刻量不到 | **採納**：V5 分工 |
| 6 | 高 | 第二進場候選沒有機械限制 | **採納**：V3 歸屬白名單 |

### A.3 R3（2026-11-01）
- A.2 #2 部分駁回：Codex 讀 `b2-batch2-signed.json`（The Offspring 為 linked／new，含 eligible 與 playable）與 `existingBandsOnlyChangeWhereTheUserSignedIt` 後**接受**——證據方（既有語意）勝。
- A.2 其餘 5 條：確認已落實。無新阻擋／高 → **收斂**。剩 §8 的價值判斷交使用者。

## 附錄 B　使用者拍板（2026-11-01）
- §8-1 逐字版 march：使用者「做吧」（說明：整詞砸下改一個字一個字砸下，做好先給他看，不像就停下回報）。
- §8-2 Fredoka、§8-3 Cannibal Corpse 另案：照草案。
- §8-4 分支：⑧ 未合 main → 從 `wip/lyrics-library-gate` 疊開 `wip/lyrics-fx-b2-batch5`。

## 附錄 C　實作記錄（2026-11-01，`wip/lyrics-fx-b2-batch5`，自 fcb1c3e）
- **T0**：程式重產基線確認 mono 署名團＝Aphex Twin、Cannibal Corpse、Daft Punk、Fatboy Slim、Rammstein、The Chemical Brothers（F1 屬實）。全量單元基線沿用 2271b8e（2026-10-29，增補計劃附錄 F：1,978 條 1,946 綠、7 紅）——其後 app／單元 target 只改了 UI 測試讀法（推測不影響，未重跑）。
- **T1①②**：基線以 fcb1c3e 重產（61 團；舊 54 團零差異——Cannibal Corpse 只是 `"playable": null` 與省略欄位的寫法差，解碼皆 nil），sha256 `d472d724…`；`ExistingBandCandidatesTests` 推進到批 5；批 4 新元件凍結為 `b2-batch4-new-components.json`（164 個＝emo＋J-Pop＋⑦ 通用，由 c6e0a53 基線算出，sha256 `cf1d3c04…`）。相關 4 suite 17 條綠。
- **T2**：`composer.before-b2-5.js` sha256 `83d8e715…`，`check.js --batch 4` 對批 4 對照檔差異 0。`patch_b2_5.py`：5 團標 linked／batch 5；march 改逐字；strobe、pyro 退役（改掛無人使用的標籤）；Rammstein 加 `forge`（drop＋type 逐字）、`shutdown`（shrink＋fall）只帶 industrial；**Fredoka 不搬**（google/fonts 只剩 wdth＋wght 兩軸可變字檔，`everyCatalogFontIsRegistered` 不收——批 2 §9 同一先例；計劃 §8-2 的前提不成立，依先例處置）。`check.js --batch 5`：61 團只有 5 團變、未預期 0；`precheck` 外溢 0。
- **T3 探針（本機 v19）**：P17——Rammstein 第一輪使用者：「你管這個背景叫噴火？不要這個噴火了」→ pyro 退役（連帶 T4 不再需要「目前行開始時間」資料流，該項取消）；第二輪「這次沒問題了」。The Chemical Brothers、Fatboy Slim、Daft Punk、Aphex Twin 各「沒問題」。匯出 `b2-batch5-signed.json`（linked／new；`playable` 待 T5 由 app 算出補入）。
- 要新做（`need.js`）：背景 steel、neon；進場 march、forge；退場 burnout、shutdown；字型 OswaldInd、FrakturInd；效果 stomp、heat；配色 steelFire、blackRed、neonPink。新繪製行為只剩 steel、neon、stomp、heat 四個。
- **T4–T5**（43bcd88）：steel／neon、stomp／heat 先紅後綠；目錄由 `gen_swift.js --batch 5` 產生 13 個新元件＋同掛 15 個既有元件（只補缺的 X 標籤）；app 合格集合與簽字對照逐槽一致、相對基線只有 5 團變；可讀性閘門三組 4,022 s 綠。Fredoka 未搬，故 About／README 字型清單不需改。

## 附錄 D　simcodex（2026-11-01，2 輪，第 2 輪提前結束；審 `fcb1c3e..HEAD`）
| 輪 | 來源 | 意見 | 處置 |
|---|---|---|---|
| 1 | simplify 簡化／層級／重用＋codex review [P2] | heat 走光暈層，但 `drawPlain` 只排除 glow／neonstroke → 韓文行帶紅光，違反 ⑤「韓文行無特效」 | **採納**：先紅（`PlainLinePolicyTests` 參數化 heat 案例）後綠；光暈判斷收斂 |
| 1 | 驗證時發現 | `RecipeGoldenTests` 摘要變（2f80…→d99a…）| **採納**（V4 預期）：證明把 5 團還原為 mono 恰回 2f80…；新增 `onlyTheBatchFiveBandsChanged` 永久守住其餘 profile |
| 2 | codex review [P1] | stomp 測試第 60 行「矛盾的零位移斷言」 | **駁回（誤判）**：該行是未帶 stomp 的 `plan(t)`（fx1 預設 none），且該測試實跑綠 |
| 2 | simplify 層級／簡化／重用（三方同指，P2） | 讓位規則仍手寫 `glow‖heat`、只靠註解；`haloRadius > 0` 當布林用 | **採納**（記憶：同一語義兩輪被找到不同處＝定義散落，改收斂）：`usesHalo`／`haloRadius`／`movesYieldingLinesOutOfHalo` 三個判斷集中定義，行為不變 |
- 遺留 P2：①`.neon` 與 `.cityNeon` 近似、`neonLines` 的 pink／cyan 欄名對 neon 已不貼切；②stomp 測試內聯 wordHit 公式（刻意作獨立預言，未改）；③heat 半徑斷言重述公式；④steel 測試以 haze 的前景層為預期；⑤G1 配對以字串參數；⑥`theAppOffersTheSignedEligibleAndPlayableSpace` 與基線差異測試部分重疊；⑦配方摘要每批多一個 pre 常數（可改逐團雜湊）。
- 安全評審：未派（無認證／個資／檔案／外部 API 改動）。
