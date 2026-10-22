# 歌詞特效：中日韓文字的字型與排版（⑤ CJK）

狀態：**Codex 評審 3 輪收斂（2026-10-22），待使用者拍板**。母計劃：docs/plans/2026-10-19-lyrics-fx-style-coverage.md §2「CJK：樂團曲風決定樣式限制，字型可否用由歌詞實際文字決定；CoreText 實際字型要驗證」。

## 0. 複述
- 目標＝歌詞含中日韓字的行，用使用者指定的字型整行顯示（不再一行裡英文是樂團字型、中日文是系統隨機替代字），排版與效果仍讀得到。
- 完成標準＝§6 驗收。
- 不做＝§2 非目標。

## 1. 使用者決定（2026-10-22，既定前提，不重議）
1. 中文用**蘋方**，照樂團風格可以有特效。
2. 日文用**冬青黑體**（Hiragino Sans），可以有特效。
3. 韓文字型隨便，**無特效**。
4. **中英混排時整行換成同一款字型**。

## 2. 事實（已核）
- 曲庫（2026-10-22 唯讀掃描，雜訊已由使用者清完）：有歌詞 5,893 首；含假名 ≈ 133 首（Yorushika 50、back number 38、YOASOBI 23、ATARASHII GAKKO! 7、SKE48 6、米津玄師 2…）；只有漢字 1 首（Gorillaz〈Dirty Harry (Schtung Chinese New Year Remix)〉，iTunes 官方歌詞，**繁體**：繁體特有字 44 次、簡體 0 次）；韓文 1 首（Coldplay X BTS〈My Universe〉15／49 行，從第 8 行起）。
- 日本歌手都不在樂團表、曲風列也沒有日系列 → 目前全是素面（mono，Space Grotesk）。
- 每首組合樣式只有一款字型 `ResolvedStyle.face`（`ComposedStyle.swift:6-37`）；素面固定 `displayMedium`／`displayRegular`（`MonoStyle.swift:41-54`）。字型以 `NSFontDescriptor` 的 family 取（`TextMeasuring.swift:34-44`），缺字由 CoreText 自動替代。
- 實測替代結果（`swift` 腳本，AppleLanguages=["en"]）：日文漢字 → `.PingFangUIDisplaySC`（**簡體中文字形**）、假名 → `.CJKSymbolsFallbackSC`、韓文 → `.AppleSDGothicNeoI`。即現在日文歌的漢字是大陸寫法（例：「骨」「直」字形不同）。app 介面語言設為 ja／zh-Hant 時的替代結果未測（TBD；本計劃改為明指字型後不再依賴它）。
- 系統字型可用：Hiragino Sans W0–W9；PingFang TC／SC Ultralight–Semibold；Apple SD Gothic Neo Thin–Heavy。
- 分詞（`LyricsTimeline.swift:57-66`）：有空白按空白分；無空白且含假名或漢字 → **每個字一個詞**；韓文沒有專門處理（韓文本來用空白分詞）。
- 組合排版（`ComposedStyle.swift:410-446`）：逐字量字寬＋`face.spacing`，**詞與詞之間加 0.3 em**（`wordGap`）。所以無空白的日文行，每個字之間都多 0.3 em，比正常中日文字距鬆很多（推測畫面上像「夜 明 け の 空」）。有空白的日文行則整段當一個詞，只有縮字到下限仍放不下時才會逐字斷行（`breakLongWords`）。
- 每行第一個字轉大寫（`display(isLineStart:)`）對中日韓字無作用；`face.uppercase` 只影響拉丁字母。
- `GenreStyleResolver` 已有「日本語系」判定（假名漢字比例 ≥ 0.3 或 j-pop／j-rock 標籤），目前畫面不使用。

## 3. 目標與非目標
目標：§4 的字型選擇、整行換字型、中日文字距與斷行、韓文行無特效，素面與組合兩條畫法都適用。

非目標：
- 給日本歌手配風格（⑥分類層／⑦通用零件）：本計劃做完，Yorushika 等仍是素面，只是字型換成冬青黑體、字距正確。
- 簡體中文自動改用蘋方-簡（目前曲庫 0 首；出現時另案）。
- 直排、注音假名（ruby）、完整的日文禁則（行首不放「、。」等）——只做 §4.4 的最小規則。
- 韓文特效；中日韓專用的新效果。
- 改歌詞內容、改 Music 標籤。Python 1.x 不動。

## 4. 設計

### 4.1 文字種類判定（純函式，`Services/Lyrics/LyricsScript.swift`）
- **每行**：`lineScript(text)` 依優先序 → `.hangul`（行內有任一諺文，韓文優先，Codex R1 #5）／`.cjk`（有假名或漢字）／`.latin`。
- **整首**的中日之分（只在 `.cjk` 行要選字型時用）：歌詞含任一假名 → 日文；否則 → 中文。只看歌詞，不引入曲風標籤（R2：注入曲風要把 metadata 一路傳進 timeline，為曲庫 0 首的情況不值得）。已知限制：全漢字的日文歌會判成中文；中文歌裡引用一句日文會讓整首判成日文——兩者曲庫目前 0 首，接受（Codex R1 #6）。
- 判定在建 `LyricsTimeline` 時做一次並存進去（`LyricsTimeline.script`、`TimedLine.script`），繪製時不重掃全文（Codex R1 #2）。
- 字元範圍：平假名、片假名、片假名擴充、CJK 基本漢字、擴充 A、相容漢字、全形標點（U+3000–303F、U+FF00–FFEF）；諺文音節與字母。`JapaneseText.isKanaOrKanji` 改為呼叫這裡的單一定義。

### 4.2 整行字型（使用者決定 1、2、4）
- `.cjk` 行整行改用這首的中日文字型：日文 → 冬青黑體；中文 → 蘋方-繁。行內英文、數字也用它。
- **固定粗細、以 PostScript 名指定**（Codex R1 #9：不逐款標樂團字型的粗細級；R1' #6：family＋trait 不保證解析到指定字重）：

| 用途 | 日文 | 中文 | 韓文（4.3） |
|---|---|---|---|
| 組合樣式 | `HiraginoSans-W6` | `PingFangTC-Semibold` | `AppleSDGothicNeo-SemiBold` |
| 素面目前行 | `HiraginoSans-W5` | `PingFangTC-Medium` | `AppleSDGothicNeo-Medium` |
| 素面預覽行 | `HiraginoSans-W4` | `PingFangTC-Regular` | `AppleSDGothicNeo-Regular` |

- `FontFace` 增加可選的 `postScriptName`；`FaceFonts.font` 有它就用 `CTFontCreateWithName`，否則照舊用 family。中日韓字型 `sizeScale` 1、`spacing` 0.02 em、`uppercase` 照該首的樂團字型（只影響行內拉丁字母）、`rasterizes` 照 §7 量測結果。
- 由 `ResolvedStyle.face(for: TimedLine)`／素面同名函式回傳；量測、排版、點陣、外框都吃「這一行的字型」。
- **快取鍵**：`FitCache.Key`、`FitLog.Key` 等目前以 `style.face` 為身分，改為這一行完整的排版身分 `LineTypography`（實際字型 id、uppercase、spacing、sizeScale、render policy、排版規則版本）＋正規化後的顯示文字＋可用寬度（Codex R1' #14、R2；原稿「不需改鍵」是錯的）。

### 4.3 韓文行：逐行繪製規則（使用者決定 3）
- 只有韓文行無特效，同一首的英文行照原 recipe（Codex R1 #1：「整首素面」違反使用者「只指韓文」的回答，刪除該替代案）。
- 新增逐行 `LineRenderPolicy`：`.composed`（現行）／`.plain`。`.hangul` 行一律 `.plain`。**在建 `FramePlan` 之前就分流**：`.plain` 行只走一個專用的「只有透明度」builder，不先跑組合畫法再過濾（R2）。
- `.plain` 行：用同一份版面（字型改 Apple SD Gothic Neo）、同配色與背景；**只產生整行透明度**的字形（進場 0.35 s 淡入、離場照讓位規則 0.35 s 淡出、停留靜止）。不產生：逐字位移／旋轉／縮放、ghost、trail、smoke、粒子、box、描邊、光暈、錯位、RGB 分離、倒影（Codex R1 #4、R1' #8–9）。
- 整格效果（shake、zoom、speedlines、全畫面光暈）：`.plain` 行成為目前行的那一刻，進行中的整格狀態**立即結束**（不淡出、不覆蓋韓文淡入）；上一句字形自己的退場與 0.35 s 讓位照舊。`.plain`→`.composed` 時，下一句照原規則觸發（R2）。T4 測兩個方向的交界。
- 測試看整份 `FramePlan`（不只看有沒有逐字進退場）。

### 4.4 排版 token 與中日文斷行
- 新增共用的「排版 token」（`LayoutToken`），由行原文產生、保留原本的空白邊界；組合與素面都吃它，不從 `TimedWord` 反推（Codex R1 #3）。
  - 切法以 `Character`（字素叢集）為單位，不拆 emoji 與變體選擇符（R2）：含任一中日韓字元（4.1 範圍，含全形標點、全形英數）的字 → 一字一個 `cjk` token；其餘連續非空白字 → 一個 `latin` token；emoji 夾在中日文之間時自成一個 `latin` token。
  - 每個 token 存原文範圍與 `timedWordIndex`（它屬於哪個 `TimedWord`）；斷行不改變時間歸屬（R2）。對照：無空白的中日文行，`TimedWord` 本來就一字一詞 → 一對一；有空白的行，一個 `TimedWord` 可含多個 token，共用該詞的時間。
- 間距：相鄰兩個中日文 token 之間不加 `wordGap`（只留字型 spacing）；中日文與拉丁詞之間、原文有空白處照舊 0.3 em。
- 斷點：拉丁詞之間、中日文字之間都是候選斷點（不必等縮字到下限）。
- 最小禁則（候選斷點的允許規則，Codex R1 #7）：收尾類「、。，．！？」』）〕】・ー」不能在列首；開頭類「「『（〔【」不能在列尾。貪婪排版時跳過不允許的斷點；**一整列找不到允許的斷點時，退回允許違例**（照寬度硬斷），保證不產生空列、不無限迴圈。測試含最窄寬度、連續標點、標點超寬。
- 縮字（`I-45`）照舊：逐字斷行後仍放不下才縮。

### 4.5 效果相容性
- `ReadabilityAudit` 加一份編造的日文歌詞（漢字、假名、混排英文、全形標點；不用真歌詞）。中文與日文共用同一套效果與字重，不再另加中文樣本（gate 時長，Codex R1' #12）。
- 不合格處置（Codex R1 #10、R1' #11、R2）：不用 `Composer.forbiddenPairs`（它只表達整首的 enter×exit）。在 `EnterTemplate`、`ExitTemplate`、`FXEffect` 三個 enum 上各加 `supportsCJKLines`，**以窮舉 `switch` 寫，沒有預設值**——新增模板時編譯器強制明確宣告。初值全部 true（現有模板未經日文 gate 前的宣告，由 T5 驗證）；跑出不合格者改 false。中日文行遇到 false 的元件：進場固定退回 `fadeUp`、退場固定退回 `fade`、效果不畫；退回是固定對應，不重新抽籤，種子行為不變。`fadeUp`、`fade` 本身必須是 true（測試斷言）。
- **實作中修正（2026-10-22，待 Phase 3 回送 Codex）**：讀得到的檢查（G2／G3 的 `ReadabilityAudit` 既有 `ja` 樣本＋G1 新增日文行）本來就跑過每個 profile 抽得到的全部元件；新增模板也會被同一道檢查自動量到，不會靜默宣稱相容。所以能力標記與固定退回**只在檢查出現不合格時才加**；全綠就不加（避免沒有呼叫者的機制）。
- T5 的 DoD＝gate 全綠（含中日文樣本）。若需要關掉的元件，在本計劃記下清單並在真機驗證 #1 給使用者看改前改後；這不阻擋實作完成，但阻擋合併。

### 4.6 CoreText 實際字型驗證
- 單元測試：代表字集（常用漢字 50、平假名、片假名、全形標點、拉丁）用 4.2 的字型排一行，每個 run 的 `CTFontCopyPostScriptName` 必須等於指定名稱（Codex R1 #8）。
- 刻意缺字（例：擴充 B 漢字、emoji）另測：可正常替代顯示、不中斷；不在日誌記任何文字。
- 執行期不另加診斷（YAGNI；缺字由 CoreText 替代，畫面照常）。

## 5. 任務清單（串行：T2 依賴 T1，T3–T5 依賴 T2；不派並行 worker）
| # | 任務 | DoD |
|---|---|---|
| T1 | `LyricsScript`（每行優先序、整首中日只看歌詞）、存進 `LyricsTimeline`／`TimedLine`；`JapaneseText` 合併 | 單元先紅後綠：純日文、只有漢字的日文行（整首有假名）、全漢字歌→中文（已知限制）、繁中、純英、韓英混、韓文＋漢字（判韓文）、全形英數、emoji、空行；既有分詞與曲風判定測試照綠 |
| T2 | 字型：`FontFace.postScriptName`、4.2 對照表、`face(for:)`、素面依行選字、快取鍵改用行字型 | 單元：各情境回正確 PostScript 名；CoreText 驗證（4.6）全綠；同一句在日文歌與中文歌的縮字快取不互相命中 |
| T3 | 排版 token（字素叢集、原文範圍、`timedWordIndex`）、中日文間距、逐字斷點、最小禁則與退路；組合與素面共用 | 單元：emoji／變體選擇符不被拆；token 時間歸屬在斷行後不變；無空白日文行沒有 0.3 em 間隔；超寬時在中日文字間斷；禁則；最窄寬度不產生空列；**純 ASCII 行的換行、每個字的位置與字距與現在完全相同**（新增改前改後對照測試，R2） |
| T4 | `LineRenderPolicy.plain`：韓文行（4.3），建 plan 前分流 | 單元：韓文行的 `FramePlan` 只有整行透明度變化，沒有 §4.3 列出的任何輸出；composed→plain 時進行中的整格狀態立即結束、plain→composed 照常觸發；同首英文行照常 |
| T5 | 讀得到的檢查加日文樣本；三個 enum 的 `supportsCJKLines`（窮舉、無預設）與固定退回 | G1／G2／G3 全綠（含日文樣本）；`fadeUp`／`fade` 為 true；退回不改變種子行為 |
| T6 | ACCEPTANCE 新增條目；DMG 無關 | 條目含依據（使用者 2026-10-22 決定）、驗證、狀態 |

## 6. 驗收
1. 日文歌（素面）每個中日文字的實際字型都是 Hiragino Sans；同一行的英文也是（單元＋CoreText 驗證）。
2. 繁中歌（Gorillaz 那首）用 PingFang TC（單元）。
3. 無空白的日文行沒有每字 0.3 em 的空隙；長句在字間折行（單元）。
4. 韓文行無逐字特效（單元）。
5. 純英文歌的畫面與現在逐像素相同（既有快照／版面回歸測試照綠）。
6. 讀得到的檢查含中日文樣本全綠。
7. 真機（使用者在場，一次一項）：#1 播 Yorushika 一首，看改前改後；#2 播 Coldplay X BTS〈My Universe〉，看韓文段落。

## 7. 測試策略、影響面、風險
- 單元（TDD）：T1–T5 所列；全量單元、coverage_gate、no_playback_gate。
- E2E：`LyricsFXUITests` 加一條日文預覽固定資料（只斷言無障礙文字與畫面存在，不截憑證畫面）；使用者在場跑。
- 影響面：`Services/Lyrics/LyricsScript.swift`（新）、`LyricsTimeline.swift`（JapaneseText 合併）、`GenreStyleResolver.swift`（同）、`Features/LyricsFX/LyricsFXFrame.swift`（FontFace）、`Composer/LyricsFXCatalog.swift`（粗細級標註）、`ComposedStyle.swift`（依行字型、排版）、`MonoStyle.swift`、`TextMeasuring.swift`（不改介面）、`GlyphRasterCache`（不改，字形數變多）、測試、`ACCEPTANCE.md`、`project.yml`（新檔→xcodegen）。
- 風險：①點陣快取（Codex R1 #11、R1' #16）：以 I-46 的量測方法與門檻，跑一首編造的日文長歌（不重複字 ≥ 400）：記每首不重複字數、點陣未命中數、每幀 p95／p99／max、第一次出現新字那幾幀。**門檻＝I-46 現行門檻；未達標的處置先定為「中日韓字型 `rasterizes = false`（走向量，與 Anton 同）」，切換後重跑同一基準且須達標**（R2）；仍不達標 → 熔斷回報使用者。不另做預熱（YAGNI）。②冬青黑體 W6 對描邊、錯位類效果可能太擠——由 4.5 的讀得到檢查判。③既有簽字畫面：只影響含中日韓字的行；純英文歌不變（驗收 5）。
- 回退：分支不合併；或把 `face(forLine:)` 改回一律回樂團字型（單點）。

## 8. 待拍板
無（韓文已依使用者「只指韓文」定為逐行無特效）。T5 若關掉任何元件，合併前給使用者看改前改後（4.5）。

## 9. 附錄：評審辯論記錄（Codex gpt-5.6-terra／medium）

R1（同一份草稿評審兩次，輸出合併；第一次的第 1–4 條被截斷未取得）：
| 意見 | 處置 | 理由 |
|---|---|---|
| 韓文「整首素面」替代案違反使用者回答 | 採納 | 使用者明說「只指韓文」；刪替代案與待拍板 |
| 整首 script 沒有載體 | 採納 | 存進 `LyricsTimeline`／`TimedLine` |
| `line.words` 已丟失邊界，需排版 token | 採納 | §4.4 |
| 韓文行需逐行 render policy、列出禁止輸出、整格效果規則 | 採納 | §4.3 |
| `.hangul` 定義讓韓漢混行套到特效 | 採納 | 韓文優先 |
| 整首中日判定會誤判 | 修改 | 先加曲風退路，R2 後改為只看歌詞並接受限制 |
| 禁則需候選斷點規則與退路 | 採納 | §4.4 |
| CoreText 驗證與 fallback 矛盾、只比 family 不夠 | 採納 | PostScript 名＋代表字集；缺字另測 |
| 33 款逐一標粗細級主觀難維護；family＋trait 不保證字重 | 採納 | 固定對照表＋PostScript 名 |
| 濫用 `forbiddenPairs`、T5 DoD 不可完成 | 採納 | 元件能力標記；DoD＝gate 全綠 |
| 快取鍵需含行字型（原稿錯） | 採納 | §4.2 |
| 純 ASCII／emoji／全形／混排四組視覺 golden | 部分駁回（R2 同意） | 無 golden 基礎設施；改純 ASCII 對照測試＋分類單元 |
| 冷幀預熱 | 駁回（R2 同意） | 先量；未達標處置＝走向量 |
| 執行期替代診斷加 rate limit | 駁回（R2 同意） | 不做診斷，避免擴大記錄面 |
| 效能需門檻與處置 | 採納 | 沿用 I-46，未達標走向量 |

R2：
| 意見 | 處置 | 理由 |
|---|---|---|
| token 需原文範圍與 `timedWordIndex` | 採納 | §4.4 |
| token 以字素叢集切、定義標點／全形／emoji | 採納 | §4.4 |
| 快取鍵要含完整排版身分 | 採納 | `LineTypography` |
| `.plain` 要在建 plan 前分流 | 採納 | §4.3 |
| composed↔plain 交界優先序 | 採納 | 整格狀態立即結束 |
| 能力標記粒度與固定退回 | 採納 | 三個 enum、固定 `fadeUp`／`fade` |
| 能力標記預設 true 會靜默宣稱相容 | 採納 | 窮舉 switch、無預設 |
| 曲風標籤注入路徑未定 | 修改 | 不注入，只看歌詞；R3 Codex 同意，並指出 T1 殘留舊寫法（已修） |
| 切向量後需重跑基準 | 採納 | §7 |
