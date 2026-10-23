# 歌詞特效 ⑥a：日文歌 → J-Pop 三變體（計劃 v1.0 定稿）

狀態：**v1.0 定稿**（Codex 3 輪收斂，2026-10-23；範圍與前提經使用者確認）。母計劃 docs/plans/2026-10-19-lyrics-fx-style-coverage.md（⑥分類層）。分支 `wip/lyrics-fx-classify`（自 main e0818da）。

## 0. 複述
- 曲庫裡的日文歌（目前全是素面 mono）改走 J-Pop 樣式；J-Pop 照 2026-10-03 原型 jpop 家族三變體（A アイドルきらきら／B シティポップ／C バラード）的調性，翻成組合器（六槽）的元件。
- 完成標準＝§7 驗收。

## 1. 使用者決定（既定前提，不重議）
1. 曲庫日文歌一律當 J-Pop，不查 MusicBrainz（2026-10-22；本 session 開工口令重申）。
2. MONGOL800 照規則當 J-Pop，不開例外（2026-10-23 開工時問過）。
3. J-Pop 風格照原型三變體調性直接做，不回顧原型（2026-10-22「不用回顧 做就行」）。
4. 日文行字型＝冬青黑體（⑤ I-64，已簽；組合樣式 `HiraginoSans-W6`）。字型槽只影響日文歌裡的拉丁字母行／字。
5. ⑥ 範圍（2026-10-23 /thecure 2 輪收斂、使用者確認）：⑥ 拆兩份計劃；本計劃＝⑥a J-Pop；⑥b MusicBrainz 另立計劃、開工前使用者再確認正式外送。**⑥a 完成不等於分類層完成。**
6. 重建的 app 用新圖示（工作區的 `Resources/AppIcon.icns`，滿版撥片山羊頭；2026-10-23 使用者貼圖確認）。

## 2. 事實（已核）
- 判定：`SongProfileResolver.resolve(artist:genre:)`（`Services/Lyrics/SongProfileResolver.swift:137-141`）＝樂團表 → 曲風兩列 → mono；不吃歌詞。唯一正式呼叫端 `LyricsFXViewModel.settleRecipeIfNeeded`（`Features/LyricsFX/LyricsFXViewModel.swift:217-`）。
- 定格：`isRecipeSettled` 一旦為真，本 session 不再重組；`lyricsUpdated`（:90-95）只呼叫 `apply`，**不**呼叫 `settleRecipeIfNeeded`；`trackChanged` 路徑（:143）會呼叫。
- 「日文」唯一已簽定義：`LyricsScript.language(of:) == .japanese`（歌詞有任一假名，`Services/Lyrics/LyricsScript.swift`），建 timeline 時存進 `LyricsTimeline.cjkLanguage`；全漢字日文歌判成中文是 ⑤ 已記的已知限制（曲庫 0 首）。`GenreStyleResolver.japaneseRatio ≥ 0.3` 是另一個定義，畫面不用，本計劃也不用。
- 曲庫（⑤ 2026-10-22 掃描）：含假名約 133 首——Yorushika 50、back number 38、YOASOBI 23、ATARASHII GAKKO! 7、SKE48 6、米津玄師 2…；全不在樂團表。
- 歷史：`RecipePicks` 只存六個元件 id（`Features/LyricsFX/Composer/RecipeHistory.swift`），`ConfigStore+RecipeHistory.swift:24` 寫 `[track] + 6 ids`；讀回 `RecipePicks(stored:)` 要求恰 6 個。
- 組合器：元件 `tags` 非空且與 profile 標籤不交集＝不合格（`Composer.swift:12`）；untagged 元件只有 backdrop `void` 與 fx `none`。任一必選槽無候選＝整份 mono（`Composer.swift:61-74`）。
- 既有守門：`ExistingBandCandidatesTests`（既有團抽得到的元件只准在簽過處變）、`PlayableSpaceTests`、`LyricsFXContrastTests`（`ReadabilityAudit.profiles`＝樂團表＋曲風列，主字對比 ≥ 4.5，含日文行）、`CatalogValidator`。
- 原型 jpop（`docs/plans/2026-10-03-lyrics-fx-assets/lyrics-fx-preview.html:736-755`）：
  - A きらきら：圓體、配色 bg #EAF6FF／fg #2E3A59／a1 #FF7AB6／a2 #6EC6FF／a3 #FFE066；四芒星閃爍；進場 pop2 fadeUp2 grow1（0.25–0.5 s）；停留 bob3 breathe2；退場 up 0.5 s。
  - B シティポップ：極粗黑體；bg #1B1040／fg #FFF3E0／a1 #FF6AA0／a2 #4FD3FF／a3 #FFB347；下方粉紅漸層＋6 條粉／青霓虹橫線＋半個夕陽；進場 slide3 fadeUp2（0.3–0.6 s）；停留 still；退場 slideOut 0.6 s；字帶粉紅光暈。
  - C バラード：明朝；bg #F7F4EE／fg #3B3A44／a1 #C96A7A；淡顆粒；進場 fadeUp3 smoke1（0.8–1.4 s）；停留 still／float；退場 fade 1.4 s＋殘留。

## 3. 目標與非目標
目標：日文歌（不在樂團表）有 J-Pop 組合樣式；三變體互不混搭；每次播放換變體；歌詞晚到不會卡在錯的樣式。

非目標：
- MusicBrainz、英語系素面歌（⑥b）；通用零件（⑦）；曲庫閘門（⑧）。
- 改日文字型（⑤ 已簽）；圓體／明朝的日文字。
- 原型的副歌三色輪替（a1/a2/a3 逐字換色）——組合器的配色只有 bg/fg/acc/dim 四色，加這個要動繪製，不做。
- `GenreStyleResolver` 的 jpop/jrock 家族（畫面沒用）不動、不刪。
- 中文歌、韓文歌的樣式；Python 1.x。

## 4. 設計

### 4.1 判定順序與結果契約（`SongProfileResolver`）
- 新簽名：`resolve(artist:genre:lyrics:)`，`lyrics: LyricsEvidence`：
  - `.unknown`：歌詞還沒讀到（`trackChanged` 帶 nil＝讀取失敗也算）
  - `.none`：讀到了，空白／缺詞
  - `.text(isJapanese: Bool)`：有詞；`isJapanese`＝`LyricsScript.isJapaneseSong`（含假名的行 ≥ 3 成；附錄 E 修訂，原為「歌詞含任一假名」）（`LyricsScript` 新增 `containsKana(_:)`，`language(of:)` 改由它推出——同一語義一處定義）。**不得**拿 `LyricsTimeline.cjkLanguage` 當輸入：它永遠有值，純英文也回 `.chinese`（`LyricsTimeline.swift:44-49`，R1-3）
- 順序：**樂團表**（命中即定，不看歌詞）→ 歌詞 `.unknown` 且不在樂團表＝`.pending` → `.text(.japanese)`＝**J-Pop policy** → genre `nil`＝`.pending` → 曲風列 → `.mono`。
- 結果與來源分開（Codex 範圍辯論 R2）：
  ```swift
  enum ProfileSource { case signedBand, jpopPolicy, genreRow, noMatch }
  enum ProfileResolution { case pending; case resolved(ResolvedProfile) }
  struct ResolvedProfile { let source: ProfileSource; let target: Target }   // Target = .mono | .profile(SongProfile) | .jpop
  ```
  `pending` 沒有來源；已定論才帶來源（VM 用它判斷要不要重組，§4.4）。只有這四個來源，不為 ⑥b 預留 case（R1-6）。
- 「推測」：缺詞歌（`.none`）不會顯示歌詞特效，走曲風列與否不影響畫面；保留現行行為。

### 4.2 三變體（新檔 `Services/Lyrics/JPopPolicy.swift`）
- `enum JPopVariant: String, CaseIterable { case kira, city, ballad }`，各帶一份 `SongProfile`：私有標籤 `FXTag.jpopKira／jpopCity／jpopBallad`（三選一）＋十軸值。
- 十軸值依原型調性手定（**不是**署名代表團平均——J-Pop 是使用者指定的政策列，母計劃 §2「列的軸值＝署名代表團平均」不適用，於 ACCEPTANCE 記 ⚠️）：

| 軸 | kira | city | ballad |
|---|---|---|---|
| raw | 0.1 | 0.15 | 0.05 |
| theatrical | 0.5 | 0.55 | 0.5 |
| cold | 0.1 | 0.35 | 0.3 |
| aggression | 0.1 | 0.15 | 0.05 |
| speed | 0.65 | 0.5 | 0.15 |
| elegance | 0.2 | 0 | 0（附錄 E：由原型 vary 反推；原 0.4／0.65／0.85） |
| decay | 0 | 0.05 | 0.15 |
| bright | 0.9 | 0.7 | 0.55 |
| bounce | 0.85 | 0.45 | 0.05 |
| warm | 0.7 | 0.5 | 0.6 |

- **變體鎖定目錄**（R1-1）：J-Pop 組合時呼叫 `Composer.compose(profile: variant.profile, catalog: JPopPolicy.catalog(variant), …)`——`catalog(variant)`＝只帶該變體私有標籤的元件＋共用 fx `none`。untagged 的 `void` 背景**不在** J-Pop 目錄內，city 一定是霓虹夕陽、kira 一定是星光。既有團仍用整份目錄，行為不變（`compose` 本來就收 `catalog` 參數，`Composer.swift:72`）。
- **選變體**（VM 內，純函式 `JPopPolicy.variant(seed:previous:)`）：以 session 種子算 `FXHash`（與 `Composer.compose` 的亂數串分開，不改 compose 的取樣位置）在三者中均勻抽一，**先排除上一次的變體**（使用者既定「每次都給我感覺變了」）；沒有上一次＝三選一。
- **上一次的變體從上一次的配色 id 推出，不改存檔格式**：配色是必選槽、所有配色都帶標籤，J-Pop 配色只帶單一變體的私有標籤 → `JPopVariant(paletteID:)` 唯一。好處：不動 `RecipePicks`／`ConfigStore` 的 6 欄格式、無遷移、舊資料照讀（同一語義只留一處定義：變體＝它的元件）。測試守住「每個 J-Pop 配色恰屬一個變體」。

### 4.3 元件（`LyricsFXCatalog` 新增，全部**新 id**、只帶單一變體私有標籤；既有元件一個都不改）
| 槽 | kira（jpopKira） | city（jpopCity） | ballad（jpopBallad） |
|---|---|---|---|
| font（拉丁字） | `jpKiraLilita`（Lilita One，沿用 FontFace） | `jpCityArchivo`（Archivo Black） | `jpBalladCormorant`（Cormorant Garamond 斜體 semibold） |
| backdrop | **新** `.sparkle`：上淺下更淺的天藍漸層＋四芒星閃爍（palette.acc 色，亮底）tone `.light` | **新** `.cityNeon`：下方粉紅漸層＋6 條粉／青霓虹橫線＋半個夕陽（a3→a1，35%）tone `.dark` | `jpBalladPaper`（沿用 `.paper` 細紋，近原型淡顆粒） |
| enter | `jpKiraPop`：pop 2、fadeUp 2、grow 1；0.25–0.5 s | `jpCitySlide`：sidle 3、fadeUp 2；0.3–0.6 s（附錄 E：原 slide 3，使用者看比較選 sidle） | `jpBalladFade`：fadeUp 3、smoke 1；0.48–0.84 s（原型 0.8–1.4 依 P12「淡入型縮 40%」） |
| exit | `jpKiraUp`：up；0.5 s | `jpCitySlideOut`：slideOut；0.6 s | `jpBalladFadeOut`：fade；1.4 s、trail |
| fx | `jpKiraBob`（.bob）、`jpKiraBreathe`（.breathe）；＋共用 none | `jpCityGlow`（.glow，代原型粉紅光暈）；＋none | 只有共用 none（原型停留 still／float） |
| palette | `jpKira` bg #EAF6FF fg #2E3A59 acc #FF7AB6 dim #6EC6FF | `jpCity` bg #1B1040 fg #FFF3E0 acc #FF6AA0 dim #4FD3FF | `jpBallad` bg #F7F4EE fg #3B3A44 acc #C96A7A dim #8FA6C9 |

- 因變體鎖定目錄，`void` 不會出現在 J-Pop（R1-1）。
- ballad 的停留不另做（R2-8 修正 v0.2「固定 still」的錯誤敘述）：fx 只有 `none` 時，`ResolvedStyle` 依低 aggression 走既有的 `[still 3, drift 1, float 1]`（`ComposedStyle.swift:36`），近似原型 `still 4／float 1`；偏差＝多 20% drift、still 少 20%，記入 ACCEPTANCE I-65。不新增 hold policy（為一個權重差加一條繪製分支不值得）。測試鎖住 ballad 配方的停留權重就是這組。
- `glow` 既有元件 `forbid` 不適用（新 id 自訂 req/forbid，皆空）。
- dim（預覽行色）若對比不足，以 §6 對比測試的結果為準調整（記入實作記錄）。
- `recipeSchemaVersion` 不加：J-Pop 是新 profile 且用自己的目錄；既有 profile 對整份目錄的 fit 不變（新元件只帶 J-Pop 私有標籤，對既有 profile fit＝0、不進候選），所以同種子抽出的配方不變，沒有理由強迫既有曲目換配方（R1-10 改寫理由）。補一條固定種子的既有團配方回歸測試（實作前先錄下 main 的結果當 golden）。

### 4.4 VM 接線（`LyricsFXViewModel`）
- `settleRecipeIfNeeded` 傳入 `LyricsEvidence`（由目前 `status`／`timeline` 推出）。
- `.jpop`：`variant = JPopPolicy.variant(seed:, previous: recipeHistory.lastPicks(...)?.palette)` → `Composer.compose(profile: variant.profile, …, avoiding: 上一次)`。
- **單一入口 `reconcileRecipe()`**（R1-2）：取代 `settleRecipeIfNeeded`，`trackChanged`、`lyricsUpdated`、`metadataUpdated` 三處都呼叫。規則：未定格→照舊第一次可用即定格；已定格→**只在來源改變時**重組（記 `settledSource`；例：`.none`→曲風列／mono，之後寫入日文詞→jpopPolicy）。同來源（genreRow→genreRow 換了曲風、日文詞改成另一段日文詞）不重組，維持 B1 §3.7「定格」的既定行為，不擴大成「profile 一變就重抽」。J-Pop 變體在 session 內一經選定不變。
- `trackChanged` 帶 nil 歌詞（讀取失敗）且不在樂團表＝pending，維持 mono 等下一次快照，不定格。

### 4.5 新背景的繪製（`ComposedBackdrop`）
- 新增兩個 `LayerDraw` case（R1-7，表示法先定死）：`sparkles([Sparkle], RGB, opacity:)`（四芒星：中心與半徑用**畫布座標（點）**，同 `particles`／`rects`；每顆帶算好的透明度）與 `semicircle(center:radius:top:bottom:opacity:)`（上半圓、垂直漸層填色；中心與半徑用畫布寬高為單位，同 `radialGlow`／`axialGlow`）。`LyricsFXView` 各加一段繪製。
- `back(.sparkle)`：垂直漸層（#FFFFFF 20% → 0）＋40 顆決定論四芒星（種子固定、位置不動、透明度依 `time` 正弦閃爍，原型 `sparkles(…, 40*(0.4+density))`），顏色 palette.acc。
- `back(.cityNeon)`：`axialGlow`（y 0.55→1，粉紅 0→35%）＋6 條線分成兩個 `.rects` layer（i＝0,2,4 一個用 #FF6AA0、i＝1,3,5 一個用 #4FD3FF；高 2 pt，alpha 0.5，y＝H·(0.62+0.06i)；`.rects` 一個 case 只帶一種色，R2）＋`semicircle`（中心 (0.5W, 0.55H)、半徑 0.28H，上 #FFB347→下 #FF6AA0，35%）。
- `front` 兩者都不畫；`underText` 不加暈影。
- `tone`：sparkle `.light`、cityNeon `.dark`。

## 5. 任務清單（每項帶 DoD；依序，單人主 session，不並行）
- **T0 固定種子回歸基線**（R3：須在任何實作前）：在未改動的分支（＝main e0818da）錄既有團固定種子配方 golden 並加測試。DoD：測試在改動前綠；之後每步保持綠。
- **T1 判定契約**：`LyricsEvidence`、`ProfileSource`、`ProfileResolution` 新形狀＋順序；改既有呼叫端與測試。DoD：`SongProfileResolverTests` 新增 8 條（§6.1）紅→綠，既有測試照綠。
- **T2 JPopPolicy**：變體、十軸、私有標籤、`variant(seed:previous:)`、`JPopVariant(paletteID:)`。DoD：§6.2 綠。
- **T3 元件＋新背景**：§4.3、§4.5。DoD：`CatalogValidator` 0 問題；三變體 `PlayableSpace` 非 nil；跨變體不混搭；`ExistingBandCandidatesTests` 不變；`ReadabilityAudit.profiles` 加入三變體後對比測試全綠（含日文行與 glow）。
- **T4 VM 接線＋歌詞晚到**：DoD：§6.3 綠。
- **T5 ACCEPTANCE**：新增 I-65（⚠️ J-Pop 政策：日文歌一律 J-Pop、三變體、軸值手定、MONGOL800 不例外；待真機）。DoD：條目有依據、驗證方式、狀態。
- **T6 E2E**：`LyricsFXUITests` 加一條：Mock 日文歌（不在樂團表）顯示組合樣式且配色是 J-Pop 之一（用既有 DEBUG 探針）。DoD：使用者在場跑綠。
- **T7 全量＋圖示**：全量單元＋coverage_gate＋no_playback_gate＋Scripts 測試；Release／Debug 產物 `Contents/Resources/AppIcon.icns` 存在且與工作區 `Resources/AppIcon.icns` 的 sha256 相同（R1-9）。

## 6. 測試（TDD，先紅後綠；測試字串自編，不用真歌詞）
### 6.1 判定
1. 不在樂團表＋日文詞 → `.resolved(jpopPolicy, .jpop)`
2. 樂團表的團＋日文詞 → signedBand（樂團優先）
3. 不在樂團表＋歌詞 `.unknown` → `.pending`（即使 genre 已知）
4. 英文詞＋black metal genre → genreRow
5. 英文詞＋無命中 genre → `.resolved(noMatch, .mono)`
6. 只有漢字的詞（中文）＋無命中 → noMatch（不誤判 J-Pop）
7. 「MONGOL800」＋日文詞 → jpopPolicy（不例外）
8. 缺詞 `.none`＋genre nil → `.pending`；＋genre 已知 → 照曲風列
### 6.2 變體
- 無上一次：1,000 個種子三變體都出現、決定論（同種子同結果）
- 有上一次：絕不回同一變體
- 每個 J-Pop 配色 `JPopVariant(paletteID:)` 唯一；非 J-Pop 配色＝nil
- `JPopPolicy.catalog(v)` 三份互斥（交集只允許 fx `none`），不含 `void`；`CatalogValidator` 對每份 0 問題；每份六槽都有候選（不會退 mono）
- `LyricsScript.containsKana` 真值表：純英文 false、純韓文 false、全形英數與標點 false、只有漢字 false、日英混排 true
### 6.3 VM
- 日文歌第一次播 → recipe 是 composed、配色屬某變體
- 持久化歷史（`StoredRecipeHistory`＋測試用 UserDefaults）＋固定 nonce：播放→停→重播 3 次，相鄰變體不同（R1-5）；歷史是非 J-Pop 配色、壞掉的配色 id、舊 6 欄資料 → 當作沒有上一次
- `metadataUpdated` 晚到 genre：日文歌已 J-Pop 定格不變；英文歌由 pending→定格
- `reconcileRecipe` 狀態轉移（R2）：`.pending → resolved`（定格、記來源）；`.noMatch → jpopPolicy`（重組）；`jpopPolicy → genreRow`（日文詞改成英文詞→重組）；同來源 metadata 更新（不重組）；換曲／clear 後 `settledSource` 清空；`pending` 不寫入 `settledSource`
- ballad 配方的停留權重＝`[still 3, drift 1, float 1]`
- `trackChanged`(lyrics nil) → mono 未定格 → 再來一次帶日文詞的快照 → J-Pop
- 缺詞歌（曲風無命中）定格 mono → `lyricsUpdated` 寫入日文詞 → 重組為 J-Pop
- 英文詞改成另一段英文詞（來源不變）→ 不重組
- 樂團表的團寫入日文詞 → 不重組
### 6.4 背景與可讀性
- `back(.sparkle)`：恰 40 顆、位置與種子決定論、透明度隨 time 變、顏色＝palette.acc、tone `.light`
- `back(.cityNeon)`：6 條線的 y 與交錯顏色、半圓中心／半徑／兩端色、tone `.dark`
- 每個變體以**實際**配方量對比（R1-4，不沿用測試裡固定 Bebas／fadeUp 的 `recipe(...)`）：`JPopPolicy.catalog(v)` 抽得到的每組（背景, 配色）× 每個 fx（含 `jpCityGlow` 本身）× 該變體實際的 font／enter／exit，日文與英文 fixture 各一；sparkle 取 3 個閃爍時間點
### 6.5 E2E（使用者在場 #1）
- §5 T6

## 7. 驗收
1. §6 全綠；全量單元綠（只允許已知基線紅）；`coverage_gate` ≥ 80%；`no_playback_gate` 綠。
2. 既有 61 團候選基線不變。
3. 使用者在場：真機播 Yorushika／YOASOBI 各一首，連播看到不同變體，字讀得到；寫入日文詞的歌升回後是 J-Pop（一次一項）。
4. 重建的 app 圖示是新圖示。

## 8. 影響面
`Services/Lyrics/SongProfileResolver.swift`、新 `Services/Lyrics/JPopPolicy.swift`、`Features/LyricsFX/Composer/FXComponent.swift`（BackdropKind 兩個 case）、`LyricsFXCatalog.swift`、`ComposedBackdrop.swift`、可能 `LyricsFXView.swift`（新 layer）、`LyricsFXViewModel.swift`、`Tests/LyricsFX/*`、`UITests`、`ACCEPTANCE.md`、`xcodegen generate`（新檔）。不動：字型、Music 寫入、存檔格式。

## 9. 風險與回退
- 新背景亮底＋淺色四芒星蓋字 → 對比測試量；不及格就降星點透明度。
- 變體由配色推導：日後若有人讓 J-Pop 配色帶兩個變體標籤會壞 → 測試守。
- 歌詞晚到重組：重組只在來源改變時發生；回退＝拿掉 lyricsUpdated 的判定呼叫（回到現況）。
- 回退整體：分支未合 main 前丟棄即可。

## 10. 待拍板
- 無（範圍、MONGOL800、字型都已定；三變體調性照原型）。真機看過後若要調色／元件，另記。

## 附錄 A 辯論記錄
- 範圍辯論（/thecure，2026-10-23，2 輪）：A 只做 J-Pop vs B J-Pop＋MB → B 的解讀成立，但拆兩份計劃；Codex 補三條件（結果／來源分開＋pending 無來源、歌詞晚到定格規則、變體歷史）→ 已入 §4。變體歷史本稿改用「由配色 id 推出」取代 Codex 建議的存檔加欄；R1 未反對（R1-5 稱「palette 足以推 variant 是合理的」），只要求整合測試 → 已入 §6.3。

## 附錄 B 計劃評審 R1（Codex，2026-10-23）
| # | 嚴重度 | 摘要 | 處置 |
|---|---|---|---|
| 1 | P1 | untagged `void` 讓三變體可能沒有各自背景 | 採納：變體鎖定目錄 `JPopPolicy.catalog(v)` |
| 2 | P1 | 只看 source 判重組，metadataUpdated 沒涵蓋 | 部分採納：三入口統一 `reconcileRecipe()`；駁回「profile 指紋變就重組」——會改變既有團的 B1 §3.7 定格行為，屬擴大範圍；只在來源改變時重組 |
| 3 | P1 | `cjkLanguage` 純英文也回 chinese | 採納：`.text(isJapanese:)`＋`containsKana`＋真值表 |
| 4 | P1 | 對比測試固定 Bebas/fadeUp、不測新 glow id | 採納：以實際變體配方量 |
| 5 | P1 | 變體輪替缺整合測試 | 採納：持久化歷史重播 3 次＋壞資料 |
| 6 | P2 | 為 ⑥b 預留抽象 | 採納：只留四個來源，刪預留敘述 |
| 7 | P2 | 背景表示法未定、測試可蒙混 | 採納：新增 sparkles／semicircle 兩個 layer，測幾何 |
| 8 | P2 | ballad still／float 不一致 | 採納：固定 still |
| 9 | P2 | 圖示無自動驗證 | 採納：T7 比對產物 sha256 |
| 10 | P2 | schema version 理由錯 | 採納：改寫理由＋固定種子回歸 golden |

## 附錄 C 計劃評審 R2（Codex，2026-10-23）
- R1 處置：1–7、9、10 判成立；#2 駁回判正確（Codex 撤回「profile 指紋變即重組」，並舉反例：genre 從 rock 改 black metal 時中途換風格違反 B1 定格）。
- #8 不成立：v0.2「ballad 固定 still」與實作不符——只放 `none` 時走 `[still 3, drift 1, float 1]`。→ 處置：改寫敘述、接受既有權重（近似原型 still 4／float 1），記 ACCEPTANCE，不新增 hold policy；待 R3 確認。
- kira 星色 acc／dim 敘述不一致 → 統一 palette.acc。
- city 六條雙色線 → 兩個 `.rects` layer。
- sparkles 座標系 → 畫布座標（點）；semicircle 用畫布單位。
- 最容易失敗：T4 `reconcileRecipe` 狀態 → §6.3 加四條轉移測試。

## 附錄 D 計劃評審 R3（整體確認）
- #8 處置（沿用 `[still 3, drift 1, float 1]`、記 ACCEPTANCE、測試鎖權重）判正確。
- 異議一項：固定種子 golden 要在實作前錄 → 採納，移為 T0。
- 其餘無致命欠落或矛盾；最容易失敗＝T4。清單無未決項 → 定稿。

## 附錄 E 實作記錄（2026-10-23）
- **T0**：`RecipeGoldenTests`。錄基線時發現既有問題：同一份 main 程式碼錄出兩種摘要（41f7… ×2、2f80… ×6）。臨時探針找到 21 組數學上相等、只差 1 ulp 的貼合度（例：Green Day 字型 Oswald／Dela、The Used 配色 gigRed／revenge），`Composer.fit` 以字典走訪順序加總，順序每次啟動不同 → 同分排序翻轉 → 配方不同。修：`fit` 依 `FXAxis.allCases` 固定順序加總（一行）。基線改在「e0818da＋此修正」的乾淨 worktree 錄（2f80…，連跑 3 次一致），並以 `printTheLines()` 逐行比對本分支輸出：1,260 行完全相同。記入 ACCEPTANCE I-65「附帶」。
- **T1**：紅燈＝新 API 未定義的編譯失敗（6 處）；綠。全量單元（T1 狀態）：唯一新增紅＝`LyricsFlowUITestAssemblyTests.aPreviewNonceFixesTheRecipe`（預覽場景先送無詞曲目、詞後到；T1 讓「詞未知＝pending」但 `lyricsUpdated` 尚未重判）→ T4 後綠。另一條＝已知 flaky 掛起 `BatchOverlappingLoadTests.overlappingLoad…`（120 s 逾時）。
- **T2／T3 紅燈步驟漏做**：`JPopPolicy`、元件、背景的實作在跑紅燈前就寫了；第一次跑即綠。如實記錄，未補做。
- **與計劃的差異（筆誤級，已改碼不改驗收）**：①`JPopPolicy.swift` 放在 `Features/LyricsFX/Composer/`（要讀 `LyricsFXCatalog`；Services 不依賴 Features），計劃寫 Services。②重組規則細化：「來源改變即重組」會讓 noMatch↔genreRow（曲風晚到或改變）也重組，違反 B1 §3.7 與既有測試 `anUnknownGenreSettlesAsMonoAndStaysMono`；改為「已定格只在來源跨過 J-Pop 邊界時重組」（`LyricsFXViewModel.shouldCompose`，測試 `LyricsFXRecomposeRuleTests` 11 組）。§6.3 各條行為不變。
- **T4**：紅燈 6 條（J-Pop 接線）→ 綠；VM 相關 7 個 suite 80 條綠。
- **日文歌判準修訂（動到驗收標準 → 回 Phase 1 快速複審，Codex 1 輪）**：實作中跑 UI 預覽歌詞（10 行 1 行日文）時發現「任一假名」會把它判成 J-Pop；osascript 唯讀掃描曲庫：含假名的歌依歌手最小行占比 Gorillaz 0.10、My Chemical Romance 0.19（在樂團表）、Nogizaka46 0.44、其餘 0.71–1.00。改為 `LyricsScript.isJapaneseSong`：畫面上的歌詞行（LRC 走 `LRCParser`、否則 `LyricsLines`，略過段落標題與 ID 標籤）中，有字母的行裡含假名的 ≥ 3 成（整數比較 `kana*10 >= lettered*3`）。Codex 採納並補：只有漢字的行進分母不進分子、符號數字行不算、LRC metadata 不算、1–2 行短詞照比例（已知限制：英文歌只有一句日文客串、而全曲只有 1–2 行時會誤判）、`language(of:)` 維持任一假名（選字型是另一語義）。真值表 12 例，先紅（未定義）後綠。
- **G3 不合格兩項（J-Pop 實際配方 6 種子 × 3 歌詞）**：①ballad 0.62 s——換進場、退場都不變，是字位移（elegance 0.85 → dy 0.165、scatter 0.071，約原型兩倍）；elegance 0.85／0.6／0.4／0.2／0 → 0.62／0.62／0.62／0.50／0.28 s。改為由原型 vary 反推 elegance（kira 0.2、city 0、ballad 0；原型 ballad dy 0.08、scatter 0.02 恰為公式在 0 的值），§4.2 的軸值表依此更新。②city 0.64 s——進場換 fadeUp 降到 0.20 s，成因是 slide 模板（同 I-60）。/thecure 1 輪：Codex 反對直接延伸 I-60 豁免（簽字是逐元件 id、新元件與日文寬字形未經使用者看過），建議並排比較；做了本機比較頁（原型 slide vs 短距離 sidle 0.3 em，sidle G3 0.20 s），使用者選 2 → 正式加回 `EnterTemplate.sidle`（ffb055a 曾移除），`jpCitySlide` 改 sidle 3／fadeUp 2，豁免名單不變。`JPopCitySidleTests` 2 條是實作後才寫（未先跑紅燈）。
- **T6**：DEBUG 預覽加 `AZW_LYRICSFX_PREVIEW_JAPANESE`（8 行 7 行日文，自編）；`LyricsFXUITests.testAJapaneseSongByAnUnknownArtistGetsJPop`（曲風 Black Metal 仍得 J-Pop 字型）——建置通過，待使用者在場跑。

## 附錄 F simcodex（2026-10-23，2 輪，第 2 輪提前結束）
| 輪 | 來源 | 意見 | 處置 |
|---|---|---|---|
| 1 | Codex review --base main | 無可動作問題 | — |
| 1 | simplify 簡化 P1 | `LyricsEvidence.none` 與 `.text(isJapanese: false)` 行為相同 | 採納：刪除；空白歌詞經 `isJapaneseSong` 為 false |
| 1 | simplify 簡化 P1 | 刪 `ProfileSource`，VM 只存「是不是 J-Pop」 | 駁回：計劃 R2 要求結果與來源分開，⑧ 要逐首列來源 |
| 1 | simplify 層級 P1-1 | J-Pop 選變體與加鹽種子寫在 VM；重組規則點名 `.jpopPolicy` | 採納：`JPopPolicy.target(signature:nonce:previousPalette:)`；`ProfileSource.dependsOnLyrics`；VM 拆出 `sessionRecipe(for:signature:)`（行為不變） |
| 1 | simplify 層級 P1-2 | `isJapaneseSong` 另解析一次行，應改由 `LyricsTimeline` 算 | 駁回（附證據）：曲長未知時 `LyricsTimelineEstimator.estimate` 回 nil（`guard duration > 0`），日文純文字歌會先被判非日文、依曲風定格，曲長到後中途換成 J-Pop |
| 1 | simplify 層級 P1-3 | 收成 `resolved(source, target)` | 駁回：現行列舉讓不合法組合（如署名樂團＋素面）寫不出來 |
| 1 | simplify 效率／重用 | 全 P2（見下） | 延後 |
| 2 | simplify 四角度 | 無 P1 | — |
| 2 | Codex review --uncommitted | [P1] 未追蹤的 `.claude/`（1.1 GB，本機 worktree 與設定）不得進提交、建議加 ignore | 非本次改動（一直逐檔 add，從未納入）；加 `.gitignore` 屬設定改動，交使用者決定 |

遺留 P2：①signed band 短路時仍先算歌詞證據（每次事件約 0.1–1 ms）；②`sessionRecipe` 在 pending／noMatch 也先查歷史與算種子；③sparkle 每幀重算 40 顆位置（可依尺寸快取）、每顆一次 context 複製與 Path；④`neonLines` 兩次 enumerated().filter；⑤`JPopPolicy.catalog` 每次過濾整份目錄、`tags == [tag]` 建 Set；⑥測試重複：`playedRecipes` 可併入 `ReadabilityAudit.recipes(catalog:)`、`existingProfiles` 與 `ReadabilityAudit.profiles` 同式、VM 測試的 `model`／`composed` 與 `LyricsFXRecipeTests` 重複、`lyrics: .text(isJapanese: false)` 散在約 10 處；⑦兩個「日文」定義並存（`GenreStyleResolver.japaneseRatio` 字元比例、畫面不用；`isJapaneseSong` 行比例），可加互指註解；⑧elegance 被當作 vary 旋鈕（變體目錄元件的 elegance 與 profile 不一致；根本修法是讓變體直接提供 vary，動共用基礎，延後）；⑨`.sparkles` 的 opacity 參數恆為 1；⑩`previousPalette` 以字串傳入再反推變體，可在 `RecipePicks` 提供型別化的上次變體。

## 附錄 G 全量單元（2026-10-23）
- 第 1 次（`-skip-testing` 已知 flaky 的 `BatchOverlappingLoadTests.overlappingLoad…()`）：紅 3 條。
  - `B2BatchFourIsolationTests` 2 條：它把「基線（c6e0a53）之後新增的元件」一律當批 4（emo 群）檢查，⑥a 的 J-Pop 元件也落在這裡。改為依標籤分屬兩批：emo 照舊須屬 emo 私有標籤、本批團抽得到；J-Pop 須恰帶一個變體私有標籤、且在該變體目錄內抽得到（斷言未放寬，只多認一批）。綠。
  - `SourceGateTests.whileTheProbeIsInFlightOthersAreTurnedAway` 300 s 逾時：本分支未動 `Services/Lyrics/Timing`、`Tests/Timing`（diff 空）；單獨連跑 5 次全綠。推測：測試以 `while client.requests.count < 4 { await Task.yield() }` 空轉等待，全量平行＋同機另一 session 跑 iOS 模擬器測試時被餓住。**未證實，不當結案理由**；看第 2 次全量是否重現。
- 第 2 次（同上 skip，`-enableCodeCoverage`）：**1601 條／199 suite 全綠**（3050 s）；`whileTheProbeIsInFlightOthersAreTurnedAway` 0.001 s 綠，**未重現**。coverage_gate（傳該 xcresult）：Services+Infra 96.0 %。
- 根因（未重現仍不靠重跑結案）：讀碼發現 `ScriptedHTTPClient` 的 `.hold` 先在鎖內記帳（`requests.count` 變 4），之後才在另一次加鎖登記 continuation；測試看到 count==4 就往下走並 `release()`，若落在這段空窗，`release()` 拿到空陣列、之後登記的 continuation 永遠沒人 resume → `probe.value` 永掛。已核事實：新測試 `aReleaseThatArrivesBeforeTheHoldParksStillLetsItThrough`（先 release 再送 hold）紅＝60 s 時限觸發。修（只動替身）：`release()` 之後一直放行，判斷與登記在同一次加鎖內。修後 SourceGate 17 條 × 5 次綠。第 1 次的 300 s 逾時是否正是此空窗：**推測**（機制吻合「只在全量平行負載下、單獨跑必綠」），無法事後證實。
