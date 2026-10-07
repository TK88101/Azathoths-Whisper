# Lyrics FX — B1「引擎逐字個性＋組合器＋兩個家族」實施計劃 v4（計劃評審 R1–R3、家族辯論 R1–R3 已併入，Codex 無異議；待使用者確認執行）

母計劃：`docs/plans/2026-10-03-lyrics-fx-mode.md`（§2.5–§2.7、§2.10、§4、附錄 B）；前段：`docs/plans/2026-10-06-lyrics-fx-a2-mono-render.md`（以下稱 A2 計劃）。本檔只管 B1，不重開已定案的決定。
分支：`feature/lyrics-fx`（e640d4b）。模式：normal（全程同步；探針要使用者看，沒有可交給 loop 的環節）。

## 0. 複述
- **目標**：升起層的歌詞特效不再只有 mono——依樂團／曲風由組合器抽出一套合身的字型、背景、進退場、效果、配色，逐字各有個性；換曲或停播後再播時重抽，一次播放內固定。B1 先把**引擎與組合器機制做完整**，元件目錄只填**兩個家族**，各出探針給使用者簽字。
- **完成標準**：
  1. 命中這兩個家族的曲目自動得到組合風格；其餘曲目與「減少動態效果」仍是 mono，畫面與 A2 相同。
  2. 換曲／停播後再播重抽；同一次播放內（含拖進度、暫停、同曲改詞、metadata 補讀）不換。
  3. 兩個家族的探針（定格圖＋6 秒動圖）經使用者簽字；每條「不對」已轉成規則＋測試。
  4. 帶效果的 200 字真視窗主執行緒 p50 ≤ 2 ms。
  5. 新增單元測試全綠、原有測試無新紅（基線 `CoverFlowStripRenderGeometry` 7 斷言紅另列）；`no_playback_gate.sh`、選擇器白名單、`coverage_gate.sh <xcresult>` 全過；ACCEPTANCE I 段補條目。
- **非目標**：其餘家族的目錄（B2）；真模糊／光暈／霓虹描邊類濾鏡效果（B2 再量）；外部時間軸（C）；Jev（D）；Settings 介面（含固定風格、手調十軸）；Cover Flow 的改動；サビ演出與關鍵字粒子（B2，見 §3.9）；直書版面；單曲循環時的重抽；commit 到 main、push。
- **使用者可見的變化**：切到歌詞特效後，這兩個家族的歌不再是白字黑底的 mono。預設升起層仍是 Cover Flow，不切就看不到差異。

## 1. 開工前辯論的單一結論（Codex gpt-5.6-terra／medium，2026-10-06，R1＋R2 收斂，帳本無 open）
### 1.1 切段
**B 拆成 B1 與 B2，不一次做完整個目錄。** B1 內按五道閘門依序做、每道可停：

| 閘門 | 內容 | 過關判據 |
|---|---|---|
| G0 | 拋棄式效能 spike（不進 commit）：真視窗、Debug、200 字，用**將來的** Path 合併畫法，疊上殘影、平鋪顆粒、暈影、300 顆粒子 | 得到殘影份數與粒子數的上限常數；p50 ≤ 2 ms 的組合存在 |
| G1 | 引擎：`GlyphDraw` 新欄位、分組鍵、單位字級快取、`Moment` 參數化、模板池、逐字個性、種子 | mono 行為不變（既有測試改型別後全綠） |
| G2 | 組合器機制：profile、目錄 schema＋驗證器、fit、抽樣、session recipe、VM 的 nonce 與定格 | 純函數測試全綠 |
| G3 | 第一個家族的目錄＋背景層＋探針 | 使用者簽字 |
| G4 | 第二個家族＋探針＋帶效果的真視窗量測 | 使用者簽字；p50 ≤ 2 ms |

理由：元件每個都是繪製程式＋審美判斷，審美要三輪收斂（母計劃 §4），未簽字就疊十四個家族等於白做；最易失敗的是「殘影＋顆粒＋粒子＋200 字」的真視窗成本，結果會決定 `GlyphDraw` 的形狀，所以前置；完成標準靠的是機制，不是目錄大小。不取「先做寫死的兩個家族包、組合器留後」：探針簽的就不是最終交付的東西（§2.10 已取代家族包）。

### 1.2 A2 延後的 P2
| 處置 | 項目 | 理由 |
|---|---|---|
| **收** | Mono 常數分兩檔、`MonoStyle.plan` 兩段相似 | 必經：`Moment` 寫死 `Mono.exit`／`previewLead`（`LyricsFXFrame.swift:75-83`），各風格退場時長不同，必須參數化 |
| **收** | 每幀重建 Path、`LyricsFXCanvas.draw` 的分組字典 | B 的效能核心：逐字 opacity 各異時現行分組鍵 `(opacity, tone)`（`LyricsFXView.swift:6-9`）退化成一字一組 |
| **收** | 快取以連續 fontSize 為鍵、整體清快取、縮放抖動 | 個性的字級變異是連續值，現行鍵會爆（`TextMeasuring.swift:7-25,68-85`） |
| 不收 | 按行界排程取代連續動畫 | B 有逐字停留動畫與背景粒子，必須連續 |
| 不收 | `titleKey` 轉呼叫、`LyricsFXFrameSamples` 進 Release、手寫 Duration→秒、兩處百分位公式、utf16 迴圈、monitor 三變數、UITestMusic 兩處判斷、a11y 多算一次 `Moment`、`setVisible` 無同值守衛 | 與 B 無交集，只會擴大 diff |

## 2. 概念表
| 概念 | 定義 | 邊界 |
|---|---|---|
| 軸 `FXAxis` | 十軸：raw／theatrical／cold／aggression／speed／elegance／decay／bright／bounce／warm，值域 0…1 | 向量是**部分的**：沒宣告的軸＝未知，不是 0 |
| 曲風標籤 `FXTag` | §2.10 列的標籤（black、symphonic、punk、poppunk…） | 與 `StyleFamily` 無關；組合器**不讀** family |
| 歌曲目標值 `SongProfile` | `{axes: 部分向量, tags}` | 來源＝樂團覆寫表，否則 genre 關鍵字合成（§3.5） |
| 解析結果 `ProfileResolution` | `pending`（genre 還沒讀到）／`mono`（讀到了但無已知關鍵字）／`profile(SongProfile)` | pending 會等；mono 是定論 |
| 元件 `FXComponent` | 六個槽位（font／backdrop／enter／exit／fx／palette）之一的一個選項：`{id, vector, tags, req, forbid, payload}` | `tags` 空＝任何曲風皆可 |
| 目錄 `LyricsFXCatalog` | 全部元件的靜態表 | 純資料；有驗證器 |
| 配方 `SessionRecipe` | `.mono` 或 `.composed(font, backdrop, enter, exit, fx1, fx2, palette, seed)` | 一次播放內固定；`nil` 不是合法值 |
| session | 從「換到不同 `track.signature`」或「未播放後再播」起，到下一次同類事件止 | 單曲循環不產生新 session（monitor 不發事件，已知限制）；權限被拒後恢復、同一首不會重新出現（既有行為，見 §9 R7） |
| nonce | 每個 session 抽一次的 64 位元數 | 由注入的來源提供；測試給固定值 |
| 逐字個性 `GlyphPersonality` | 一個字的出場時刻、三個模板、字級／高低／傾斜／散落變異、方向、相位 | 由 `(行種子, 字序)` 決定；同 recipe 重畫相同 |
| 殘影 ghost | 一個字多畫幾份低透明、隨機位移的副本（原型的「模糊」就是這個，`lyrics-fx-preview.html:527,579,1041`） | B1 不開任何 filter layer |
| 色槽 `ColorSlot` | `bg／fg／acc／dim` | 每份 recipe 恰四色；分組鍵用槽位，不用連續 RGBA |

## 3. 設計

### 3.0 G0 spike（拋棄式）
- 在 `LyricsFXView` 旁臨時加一個 DEBUG 開關畫：200 個字以 `(色槽, opacity 量化 1/16)` 分組併 Path（每字帶旋轉＋縮放 transform）、每字 0／4／5 份殘影、`Resources/noise.png` 平鋪一層（alpha 0.08–0.2）、一層徑向漸層暈影、0／150／300 顆粒子（併成一條 Path）。沿用 `LyricsFXFrameMeter`，`open --env` 啟動 dense 預覽場景跑 30 秒，`log stream --level debug` 取 p50／p95／max。
- 產出回填 §8：`maxGhosts`、`maxParticles`、顆粒層成本；若 200 字＋4 殘影超預算，殘影只給「進場中」的字（進場結束即 0）。
- 超預算處置順序（Codex R2）：**先減粒子 → 再減殘影份數／顆粒密度 → 不減字**。p50 > 4 ms 且以上皆無效＝母計劃 §6 熔斷點，停手回報。
- spike 程式碼量完即還原；只留數字。

### 3.1 型別（`Features/LyricsFX/LyricsFXFrame.swift` 拆檔，見 §9）
```
struct FontFace: Hashable, Sendable {            // 目錄內的不可變值
    let id: String
    let family: String                           // CoreText family／PostScript 名
    let weight: GlyphWeight?                     // 可變字重字型才有；靜態字型 nil
    let tracking: CGFloat                        // em 比例
    let uppercase: Bool
}
enum ColorSlot: Sendable, Hashable { case bg, fg, acc, dim }
struct FXPalette: Equatable, Sendable { let bg, fg, acc, dim: RGB }   // RGB＝三個 Double，不是 SwiftUI.Color

struct GlyphDraw: Equatable, Sendable {
    let text: String
    let face: FontFace
    let fontSize: CGFloat
    let origin: CGPoint        // 行盒 top-leading（未套 transform）
    let rotation: CGFloat      // 弧度，pivot＝該字行盒中心
    let scaleX, scaleY: CGFloat
    let opacity: Double
    let color: ColorSlot
}
enum LayerDraw: Equatable, Sendable {            // 有序；純資料
    case fill(ColorSlot)
    case grain(opacity: Double, frame: Int)      // noise.png 平鋪，frame 決定位移
    case vignette(strength: Double)
    case dots([Dot], ColorSlot)                  // 粒子：plan 內算好的點（雪、灰燼、紙屑）
    case invert(amount: Double)                  // 負片硬切：difference 白
}
// 實作註記：ShapeDraw 與 LayerDraw 的 fill／invert 在 B1 沒有使用者（家族改為黑金屬＋交響後，附加形狀與負片都屬 B2），依 YAGNI 不先立型別，B2 隨元件加
struct ShapeDraw: Equatable, Sendable {          // 隨字或隨詞的附加形狀（底線、速度線、紙片底、血滴），計劃評審 R1-4
    enum Kind: Equatable, Sendable { case rect(CGRect), line(from: CGPoint, to: CGPoint, width: CGFloat), polygon([CGPoint]) }
    let kind: Kind             // 畫布座標，已套好該字／詞的 transform
    let color: ColorSlot
    let opacity: Double
    let behindGlyphs: Bool     // 紙片底在字下、速度線在字上
}
struct FramePlan: Equatable, Sendable {
    let palette: FXPalette
    let back: [LayerDraw]      // 字之下
    let ghosts: [GlyphDraw]    // 殘影副本，先畫
    let glyphs: [GlyphDraw]    // 一個 grapheme 一筆
    let shapes: [ShapeDraw]
    let front: [LayerDraw]     // 字之上
}
```
- `tone` 移除：mono 的主色＝`fg`、預覽行＝`dim`，mono palette＝`Theme.background／coldWhite／coldWhite／Gray.g500`（值相同，畫面不變）。
- `GlyphWeight` 留作 `FontFace.weight` 的型別；mono 用兩枚 face：`FontFace.displayRegular`／`.displayMedium`。
- `TextMeasuring.advances(of:face:fontSize:)`（取代 `fontSize:weight:`）。
- `LyricsFXFrame.plan(timeline:time:size:motion:recipe:measurer:)`；`motion == .reduced` 時不論 recipe 一律走 mono。

### 3.2 Canvas（`LyricsFXCanvas.draw`）
- 順序：`back` → 字下的 `shapes` → `ghosts` → `glyphs` → 字上的 `shapes` → `front`。
- 字的分組鍵＝`(ColorSlot, opacity 量化成 0.05 一階)`（實作時由 1/16 改 1/20：mono 的 0.55 恰在階上，預覽字亮度不變）；**只合併 painter order 上連續、同鍵的字**（run），以 `addPath(_, transform:)` 併成一條 Path、一次 fill。不跨 run 合併——否則 A(0.2)、B(0.5)、A(0.2) 會變成第三個 A 跑到 B 下方（計劃評審 R1-1，Codex 勝）。plan 輸出的 glyph 順序就是 painter order（行內閱讀序；舊行先於新行）。fill 次數＝run 數，G0 以此量。transform＝先縮放到字級 → 以**字形外框中心**為軸做縮放與旋轉 → 移到 origin（實作時由「行盒中心」改為外框中心：行盒寬度不在 `GlyphDraw` 裡，外框中心才是視覺上的字心）。殘影也走同一套分組（它的實際 alpha 進鍵）。
- **已接受的取捨（Codex R1 提出、R2 收斂）**：① 量化使單字 alpha 最多偏 1/40；② 同一 run 內幾何重疊的半透明字，重疊處少一次累加（alpha＝1 的 run 與逐字繪製完全相同）。繪製順序不受影響（run 合併）。探針與真視窗走同一個 `draw`，使用者簽的就是合併後的結果。
- 粒子 `dots` 同樣併 Path。`grain` 用 `context.fill(矩形, with: .tiledImage)`；`invert` 用 `blendMode = .difference` 填白。

### 3.3 快取（`TextMeasuring.swift`）
- `GlyphPathCache`／`CoreTextMeasurer` 的鍵改 `(text, face)`，以參考字級 100 pt 存，字級併入 transform／乘比例。容量上限保留（鍵數現在與字級無關，正常不會觸頂）。
- **適用條件由程式驗證**（Codex R2）：face 的字型以 `CTFontCopyVariationAxes` 檢查，只允許無變軸或僅 `wght`；否則該 face 退回以字級為鍵（字級量化到 0.5 pt）。目錄完整性測試對每枚打包字型跑一次。
- CJK 的 fallback run 照現況由 CTLine 處理，接受線性縮放近似。

### 3.4 時刻、模板、個性、種子
- `Moment` 改成吃 `MomentTiming{exit, previewLead}`（由風格提供）；`Mono` 的全部常數收回 `MonoStyle.swift`。組合風格沒有「下一行預覽」（`previewLead = nil`）。
- `FXHash.fnv1a64(_ string: String) -> UInt64`（UTF-8 位元組）、`SplitMix64`（`next() -> UInt64`、`unit() -> Double`）。**不用 `Hasher`**。
- 模板＝enum＋`switch` 的純函數（不是閉包表）：
  - `EnterTemplate.transform(progress:context:) -> GlyphTransform`；`HoldTemplate.transform(time:context:)`；`ExitTemplate.transform(progress:context:)`。
  - `GlyphTransform{dx, dy, rotation, scaleX, scaleY, alpha, ghost}`；三段相乘／相加合成。
  - B1 實作的 case＝兩個家族的元件用得到的那些（由原型 `lyrics-fx-preview.html:202-251` 移植）；其餘 case 在 B2 隨家族加。每個 case 都有邊界測試（p＝0／1、alpha∈[0,1]、scale>0）。
- `GlyphPersonality` 由 `LinePersonalities.make(line:lineIndex:style:seed:)` 產生（移植 `html:257-277`）：詞共用飛行方向；`t0`＝詞內等比＋抖動、30% 機率連發（前一字 +30 ms）、不早於詞首；`wordLevel` 元件整詞同時出。行種子＝`fnv1a64(行文字) ^ recipe.seed ^ mix(lineIndex)`。
- plan 每幀重算個性（純函數）；G0 順帶量它的成本，超過 0.1 ms 才在 View 側加「每行一份」的快取。

### 3.5 歌曲目標值（`Services/Lyrics/SongProfileResolver.swift`，純函數）
`resolve(artist:genre:) -> ProfileResolution`，順序：
1. **樂團覆寫表**（27 團，母計劃 §2.10；隨 app 出貨）：artist 正規化後精確比對。正規化＝固定 locale（`en_US_POSIX`）小寫 → 去變音符號 → 去開頭 `the ` → 去非字母數字；有 idempotence 測試。不做別名表（無漏接實證，YAGNI）。命中即回 `profile`，不需 genre。
2. `genre == nil` → `pending`。
3. **關鍵字合成**（實作：每列的軸值由覆寫表中該曲風代表樂團平均而得——黑金屬＝Mayhem、Immortal、Darkthrone；交響＝Nightwish、Epica——不另手填數值）：每個關鍵字一列 `{tags, 部分軸值, isGeneric}`（比對沿用 `GenreStyleResolver` 的切詞＋整詞規則）。
   - generic（metal、rock、pop、alternative…）只在**沒有任何非 generic 命中**時才貢獻。
   - 多列合成：硬軸 {raw, aggression, speed, decay, cold, theatrical} 取 max；軟軸 {elegance, bright, warm, bounce} 取平均；無人宣告的軸＝未知。tags 取聯集。
   - 例：`Symphony Black Metal` → tags{symphonic, black}、aggression 取 black 的高值 → 溫柔交響元件被 `forbid aggression ≥ 0.65` 擋掉（P11）。
4. 無任何已知關鍵字 → `mono`（定論，不是 pending）。
- B1 只填兩個家族相關的關鍵字列；其餘 genre 走第 4 步。`GenreStyle.family` 與 `GenreStyleResolver` **不動**。

### 3.6 組合器（`Features/LyricsFX/Composer/`，純函數）
- `fit(component, profile) -> Double`：
  - 元件 `tags` 非空且與 profile.tags 無交集 → 0。
  - `req[axis] = x`：profile 該軸未知或 < x → 0。`forbid[axis] = x`：profile 該軸已知且 ≥ x → 0；未知不觸發。
  - 距離只算「元件與 profile 都有值」的軸：`exp(−Σd² / (2σ²·n))`，σ＝0.22；無共同軸 → 0.35（原型常數，`composer.js:154-160`；母計劃式子少了 `/n`，以使用者看過的原型為準）。
- `sampleSlot`：fit > 0 者依 fit 降序取前 5，以 fit² 為權重抽。同分以 id 排序定序（決定論）。
- `compose(profile, seed) -> SessionRecipe`：六槽各抽一；fx 再抽第二個、**不得與第一個同 id**；排除後無候選 → fx2 固定為 `none`（fx2 不是必選槽；計劃評審 R1-2）。**任一必選槽無候選 → 整份 `.mono`**（修正原型 `composer.js:164` 回 `list[0]`）。亂數＝`SplitMix64(seed)`。
- `ResolvedStyle`：由 recipe 查目錄組出繪製參數（face、palette、進場權重與時長區間、停留權重、退場權重與時長、變異量、`wordLevel`／`pile`、版面、背景層、效果集）。`ComposedStyle.plan(moment, time, size, style, measurer)` 產出 `FramePlan`。
- **驗證器 `CatalogValidator`**（測試呼叫）：軸值域 0…1；req／forbid 不自相矛盾（同軸 req ≥ forbid）；id 槽內唯一；palette 恰四色；face 在 bundle 內且授權檔存在；每個內建 profile（覆寫表中屬 B1 兩家族者＋兩家族的 genre 合成結果）每個必選槽至少一個候選；**掛 `industrial` 的元件與掛 `nu` 的元件交集為空**（P10；B1 目錄尚無這兩類，測試先立著）。

### 3.7 session recipe（`LyricsFXViewModel`）
- 新增 `private(set) var recipe: SessionRecipe = .mono`、`@ObservationIgnored` 的 `sessionNonce`、`recipeIsSettled`；注入 `nonceSource: any FXNonceSource`（生產＝`SystemRandomNumberGenerator`；測試＝固定序列）。
- **開新 session**：`nowPlaying` 收到與目前 `track.signature` 不同的曲目，或在 `clear` 之後再收到 `trackChanged`（未播放分支會清 monitor 的 `lastSignature`，`NowPlayingMonitor.swift:205-212`）→ 抽新 nonce、`recipe = .mono`、`recipeIsSettled = false`，然後嘗試定格。
- **定格（最多一次）**：`SongProfileResolver.resolve(artist:genre:)` 回 `profile` → `compose(profile, seed: fnv1a64(track.signature) ^ nonce ^ schemaVersion)`、settled；回 `mono` → `.mono`、settled；回 `pending` → 維持 `.mono`、未 settled，等 `metadataUpdated` 再試。settled 之後同一 session 內 genre 再變、同曲改詞、寫入、強制重讀**都不重組**。
- `lyricsRevision` **不進鍵**（偏離母計劃 §2.10 的四元組；理由：revision 會因 metadata 補讀與改詞 +1，進鍵等於播放中途換整套風格。Codex R1 同意）。
- 守衛：`metadataChanged` 只在 monitor 的 `track.signature == lastSignature`（同一首）時發出（`NowPlayingMonitor.swift:222-226,249-255`），而事件經單一 `AsyncStream` 依序由 `AppModel` 的 `for await` 消費（`AppModel.swift:331`），VM 的 `nowPlaying` 同步更新 session——所以 metadata 事件必然屬於串流中在它之前最後一個 `trackChanged` 的曲目，「A 的 metadata 晚到 B 之後」不會發生。故不改事件契約，沿用既有比對；空 persistentID 的曲目以 signature（三元組）為種子材料，不會全體撞種子。加一條測試釘住「事件依序消費時 metadata 套到當前 session」。
- VM 需記住當前 `TrackInfo.artist` 與 signature（目前只存 persistentID）。
- View：`LyricsFXView.frame` 把 `model.recipe` 傳進 `plan`。

### 3.8 目錄與字型（B1 兩個家族）
- **兩個家族＝黑金屬＋交響**（2026-10-06 依使用者指示走 /thecure 與 Codex 辯三輪收斂，附錄 A.3）。龐克移到 B2：它的「手繪底線」原型是サビ觸發（`lyrics-fx-preview.html:582`），違反本段「サビ留 B2」；且使用者實際抱怨過的 P11（Cradle 像 Nightwish）只有目錄裡有溫柔交響元件時才測得到。
- 黑金屬子集：font＝Catacombs、Grimoire of Death、UnifrakturMaguntia；backdrop＝void、film、snow、ash、crimsonFog；enter＝slam、condense、negative、lash；exit＝cut、scatter、dissolve；fx＝shake（詞首）、misreg（持續）、none；palette＝boneBlood、ice、bloodBlack、ashGrey。
- 交響子集：font＝UnifrakturMaguntia、Cinzel、Cormorant Garamond 斜體（原型標籤是 gothic／doom，不是 symphonic——照抄，不改）；backdrop＝snow、shafts（漸層＋半透明光柱，原型無 filter，`html:1006,1013`）、ash、crimsonFog；enter＝condense、smoke（原型的 blur＝殘影 ghost，`html:209,527`）、rise（原型的三個上升光點以 `dots` 重現，`html:211,467`；不畫 glow）、swoop、lash；exit＝dissolve、fade；fx＝breathe、none；palette＝goldNavy、crimsonVelvet、bloodBlack。
- **移出 B1**：Geizer、embers、fall、steel（標籤屬 heavy／power／thrash）；reflect（不在使用者 P11 點名的溫柔清單內，算不算溫柔屬審美判斷，B2 做 velvet 時以探針問使用者）；negflash、blood、glow（サビ／熱詞觸發或濾鏡）；Cenobyte、Dark Metal、Mirage Gothic、DragonForce、Haunting（授權未明）。
- 目錄向量、標籤、req／forbid **照原型 `composer.js` 抄，不改值**。Codex 以原型標籤核算：Nightwish、Epica、Emperor、Dimmu Borgir、Cradle of Filth、Mayhem、Burzum 七個 profile 六槽都至少一個候選（附錄 A.3）。
- **字型只內建授權已明確者**：Catacombs（「Freeware for any personal or commercial use」，署名）、Grimoire of Death（OFL）已在 `docs/plans/2026-10-03-lyrics-fx-assets/fonts/`；UnifrakturMaguntia、Cinzel、Cormorant Garamond（皆 Google OFL）需從 google/fonts 取字型檔與 OFL.txt。檔案放 `Resources/Fonts/`＋各自授權檔；About 的授權清單補列。`ATSApplicationFontsPath` 目前是 `"."`（`project.yml:57`），放子資料夾需確認仍能註冊——先以測試確認，不行就平放 `Resources/`。
- 體積：實作時量 `.app` 增量回填 §8（Dela Gothic One 含日文字形，過大則子集化或 B1 先不用）。
- 元件中需要附加形狀者一律輸出 `ShapeDraw`（B1 子集目前沒有；型別先立，B2 的 paper、underline、speedlines、blood 用）（§3.1），由 plan 依該字／詞的 transform 算好座標；G3／G4 內逐一做，做不進預算的先從該家族子集拿掉並記錄。
- **觸發條件**：每個效果宣告 `trigger ∈ {lineStart, wordStart, continuous}`。原型中依サビ或關鍵字觸發的效果（`negflash`：サビ行首或關鍵字詞首，`composer.js:187-188`；`blood`：熱詞；`underline`：サビ，`html:582`）**不進 B1 子集**，隨サビ／關鍵字一起留 B2（計劃評審 R1-4）。驗證器檢查 B1 目錄內效果的 trigger 不含 chorus／keyword。

### 3.9 留給 B2 的（明列以免範圍悄悄膨脹）
サビ（`isChorus`）演出、關鍵字粒子詞表、其餘家族、glow／neon／haze 類真濾鏡、直書、首詞大寫斜出（P2）若 B1 兩家族的元件沒用到。

### 3.10 探針（母計劃 §4；審美直接問使用者，不拿去和 Codex 辯）
- `Tests/LyricsFX/LyricsFXProbeRenderTests`（app 宿主，沿用 A2 的 `ImageRenderer` 路徑）：每個家族 × 3 個固定 nonce × {進場中、停留、換行、退場} 定格 PNG（2x）＋每個 nonce 一支 6 秒 GIF（**30 fps**、1x、180 幀——20 fps 會漏掉 140 ms 的砸入）＋`manifest.json`（nonce、profile、每槽 component id、face id）。歌詞用自編句子。輸出到 `NSTemporaryDirectory()/azw-lyricsfx-probe/<家族>/`。
- 我先自己看過（對照附錄 B 的 P1–P11 逐條自查）再給使用者。使用者只回「對／不對＋一句」；每條「不對」→ 一條規則（改目錄的向量／標籤／req／forbid，或改模板）＋一條測試，記進母計劃附錄 B（P12 起）。三輪內收斂；被全盤否定不辯護。
- 離屏只當審美簽字；真視窗觀感與效能另在「使用者在場」看（DEBUG 預覽場景加 `AZW_LYRICSFX_PREVIEW_ARTIST`／`_GENRE`／`_NONCE` 三個環境變數，整檔 `#if DEBUG`）。

## 4. 任務清單（TDD：先紅後綠；紅燈摘要回填 §8）
| # | 閘門 | 任務 | DoD |
|---|---|---|---|
| T0 | G0 | spike 量測 | §8.2 有 p50／p95／max 表與上限常數；spike 程式碼已還原（`git status` 乾淨） |
| T1 | G1 | `FXHash`／`SplitMix64` | `FXSeedTests` 綠（已知向量：fnv1a64 空字串＝`0xcbf29ce484222325`、`"a"`＝`0xaf63dc4c8601ec8c`；SplitMix64 seed 0 前三個輸出） |
| T2 | G1 | 型別換形（`FontFace`／`ColorSlot`／`FXPalette`／`GlyphDraw`／`LayerDraw`／`ShapeDraw`／`FramePlan`）、`TextMeasuring` 改簽名、Canvas run 合併與 transform、單位字級快取、`Moment` 參數化、Mono 常數歸檔 | ① 既有 `LyricsFXFrameTests`／`MonoLayoutTests`／`LyricsFXPreviewRenderTests` 改型別後全綠；② **mono plan 等價**：改動前先把 mono fixture 集（長行折行、CJK、間奏只剩預覽、換行重疊、末行淡出、reduced）在若干時刻的 `(text, fontSize, weight, origin, opacity, tone)` 錄成 golden JSON，改後逐欄相等（座標容差 0.01 pt）；③ 同一 fixture 集的定格圖與改動前的平均絕對像素差 ≤ 1/255、最大差的像素占比 ≤ 0.5%（抗鋸齒餘裕；超出則看圖判斷並記錄） |
| T3 | G1 | 模板 enum＋`GlyphTransform`、`GlyphPersonality`／`LinePersonalities` | `GlyphTemplatesTests`、`GlyphPersonalityTests` 綠 |
| T4 | G2 | `FXAxis`／`FXTag`／`SongProfile`／`SongProfileResolver`＋覆寫表 | `SongProfileResolverTests`、`ArtistNormalizationTests` 綠 |
| T5 | G2 | `FXComponent`／`LyricsFXCatalog` schema、`CatalogValidator`、`fit`、`sampleSlot`、`compose`、`ResolvedStyle` | `FitTests`、`ComposerTests`、`CatalogValidatorTests` 綠 |
| T6 | G2 | VM：nonce、session、定格規則；View 傳 recipe | `LyricsFXViewModelTests` 新增條目綠；既有 16 條無新紅 |
| T7 | G3 | 第一個家族：字型入 bundle、目錄列、`ComposedStyle.plan`、背景層與效果、探針測試、DEBUG 環境變數 | `ComposedStyleFrameTests`、`LyricsFXProbeRenderTests`、目錄完整性測試綠；探針產物我看過 |
| T8 | G3 | **使用者在場 #1**：看第一個家族探針 | 簽字；「不對」已轉規則＋測試 |
| T9 | G4 | 第二個家族（同 T7） | 同 T7 |
| T10 | G4 | 帶效果 200 字真視窗量測：固定一份最重的組合 recipe（以 `AZW_LYRICSFX_PREVIEW_NONCE` 指定）＋恰 200 個非空白 grapheme 的 dense fixture；`LyricsFXFrameMeter` 擴充記錄 recipe id、glyph／ghost／shape／dot 數與 fill 次數 | §8.2 回填 p50／p95／max 與各計數；計數與 G0 上限吻合（不是 mono、粒子非零）；p50 ≤ 2 ms |
| T11 | G4 | **使用者在場 #2**（看的是通過效能閘門後的最終組合；Codex R2）（與 #1 之後的回合合併成一次問完）：第二個家族探針；真視窗觀感；UI 測試授權 | 簽字；`LyricsFXUITests` 新增條目與既有 16 條實跑全綠 |
| T12 | 收尾 | ACCEPTANCE I 段、三語字串（若有新字串）、`xcodegen generate`、閘門 | 全量單元（skip `overlappingLoadSuspendsPollingUntilLastCompletes()`）僅基線 7 斷言紅；`no_playback_gate.sh` 0；白名單綠；Python 綠；`coverage_gate.sh <xcresult>` 過 |

**並行候選：無。** 任務形狀是串行鏈（T2→T3→T5→T7→T9 逐層依賴型別），且全部經同一個 xcodebuild 與同一個 ad-hoc 簽名的測試宿主。主執行緒依序做，不派子 agent。

## 5. 測試（Swift Testing；歌詞與範例一律自編句子）
- `FXSeedTests`：見 T1；同種子同序列；`unit()` ∈ [0,1)。
- `GlyphTemplatesTests`：每個 case 在 p＝0／1 的邊界值、alpha ∈ [0,1]、scale > 0、進場 p＝1 時回到恆等（位移 0、旋轉 0、縮放 1）。
- `GlyphPersonalityTests`：同種子同個性；不同行種子不同；`t0` 不早於詞首、同詞內連發間距 30 ms；`wordLevel` 整詞同 `t0`；詞內共用方向。
- `LyricsFXFrameTests`（既有，改型別）＋新增：`recipe == .mono` 與 A2 輸出等價；`.reduced` 時組合 recipe 也走 mono。
- `ComposedStyleFrameTests`：同 `(recipe, timeline, t, size)` 兩次輸出相等；`glyphs.count`＝當前可見行的非空白 grapheme 數；所有 glyph 的 opacity ∈ [0,1]、scale > 0；停留中的字落在畫布內（進退場飛行中不要求）；`t` 在時間軸外無字；殘影數 ≤ `maxGhosts × glyphs`；粒子數 ≤ `maxParticles`；尺寸過小無字。
- `LyricsFXCanvasGroupingTests`（把 run 切分抽成純函式）：連續同鍵併一個 run；**A(0.2)、B(0.5)、A(0.2) 切成三個 run**；量化誤差 ≤ 1/32；opacity 0 不產生 run。
- `LyricsFXCanvasOrderRenderTests`（app 宿主）：混合 opacity、旋轉、重疊的小 fixture，以 run 合併畫法與逐字畫法各畫一張，平均絕對像素差 ≤ 1/255——證明合併不改繪製順序（只容許量化與重疊累加的已知差，fixture 選不落在同 run 內重疊的配置）。
- 各效果的定點測試：每個 B1 效果在觸發時刻前後的 plan 輸出差異（例：shake 在詞首 0–70 ms 內 dx／dy 非零、之外為零；underline 產出對應詞寬的 `ShapeDraw`；speedlines 的 shape 數＝宣告值），不靠「圖上有非背景像素」證明效果生效。
- `SongProfileResolverTests`：覆寫表命中不需 genre；`genre == nil` 且未命中 → pending；無已知關鍵字 → mono；generic 被 specific 壓過；硬軸 max、軟軸平均；`Symphony Black Metal` 的 tags 與 aggression；尾端空白、斜線複合、大小寫。
- `ArtistNormalizationTests`：`The Offspring`、不同連字號的 `Blink‐182`、變音符號、idempotence、不受系統 locale 影響。
- `FitTests`：標籤閘門；req 未知即 0；forbid 未知不觸發、已知 ≥ 門檻即 0；距離單調；無共同軸＝0.35。
- `ComposerTests`：fx 候選「只有 none」「只有一個實效 fx」「兩個以上」三種表驅動（fx2 分別為 none、none、≠fx1）；同 `(profile, seed)` 同配方；不同 seed 在候選 > 1 的槽會出現不同結果（跑 64 個 seed 至少 2 種）；fx2 ≠ fx1；任一槽無候選 → `.mono`；**P11：Cradle of Filth 256 個 seed 都抽不到 Cinzel、Cormorant 斜體、shafts、rise、goldNavy、breathe**（B1 內仍存在的使用者點名溫柔元件，各自 `forbid aggression ≥ 0.65`），且每份都至少一個 black 群元件；**Nightwish 256 個 seed 抽得到其中至少 3 種**（證明它們不是因為不存在才抽不到）；Mayhem 抽不到任何交響標籤元件；七個 profile（Nightwish、Epica、Emperor、Dimmu Borgir、Cradle、Mayhem、Burzum）每槽至少一候選。P9（Offspring／Sum 41、paper 只給 77punk）隨龐克移到 B2。
- `CatalogValidatorTests`：真目錄通過；對每條規則各造一筆壞資料確認被抓到。
- 目錄完整性（app 宿主）：每枚 face 的字型註冊成功、變軸檢查、授權檔在 bundle。
- `LyricsFXViewModelTests` 追加：換曲抽新 nonce；同曲強制重讀、同曲改詞、寫入後 recipe 不變；genre 晚到 → 定格一次；定格後 genre 再變不重組；未知 genre → mono 且 settled；`notPlaying` 後同一首再播 → 新 nonce；`permissionDenied` 後不會有新事件（不測恢復，見 §9 R7）；空 persistentID 的兩首不同曲種子不同；覆寫表命中時不等 genre。
- `LyricsFXProbeRenderTests`：檔案存在、尺寸正確、定格圖有非背景像素、manifest 可解碼且 component id 都在目錄內。
- E2E `LyricsFXUITests` 追加（使用者在場）：預覽場景指定 artist → 特效層出現且探針值（DEBUG 1 pt 透明文字 `lyricsFXRecipeProbe`）＝預期的 font id；同場景重啟、nonce 不同 → 探針值可不同但仍屬該家族；減少動態效果 → 探針值＝`mono`。
- Scripts：`no_playback_gate.sh`、`python3 -m unittest discover -p 'test_*.py'`、`coverage_gate.sh <單元測試 xcresult>`。

## 6. 使用者在場（集中）
- **#1**（G3 後）：看第一個家族的探針圖與動圖，回「對／不對＋一句」。
- **#2**（G4 後，一次做完）：第二個家族探針；真視窗看兩個家族（預覽場景，不必操作 Music）；授權並實跑 UI 測試（先切 ABC 輸入法、先 preflight 放行鑰匙串）；真 Music 播一首黑金屬與一首交響各確認「換曲換風格、暫停／拖進度不換」。
- 開發版反覆跳「媒體與 Apple Music」權限框＝既有現象，不查。

## 7. ACCEPTANCE I 段增修（T12 落；條號接在現有最後一條之後）
- 風格自動選：依樂團覆寫表、否則 genre 關鍵字合成的目標值，由組合器抽六槽元件；未知曲風與未涵蓋的家族＝mono。
- 重抽與固定：換曲或停播後再播時重抽；同一次播放內（拖進度、暫停、改詞、寫入、metadata 補讀）不變；單曲循環不重抽（已知限制）。
- 硬規則：req／forbid 生效（列 P9–P11 對應測試名）；任一槽無候選退 mono。
- 逐字個性：每字各有出場時刻與模板；同 recipe 重畫相同（種子 fnv1a64＋SplitMix64）。
- 減少動態效果：一律 mono 退化型（I-14 補一句）。
- 兩個家族各一條探針簽字（日期、使用者原話、轉成的規則）。
- 每幀：帶效果 200 字主執行緒 p50 ≤ 2 ms（量測值）。
- 字型：內建清單與授權；About 署名。
- 日誌：新增的只有數字與 component id，不記歌詞、不記樂團名。

## 8. 紅燈摘要／量測記錄（實作時回填）
### 8.1 TDD 紅燈摘要
| 任務 | 紅燈 | 綠燈 |
|---|---|---|
| T1 種子 | 2 tests／6 issues（空殼回 0；另 3 條首跑即綠：同種子同序列、unit 值域、uniform 值域——空殼回 0 恰在範圍內） | 5 tests 綠 |
| T3 模板與個性 | 7 tests／11 issues（空殼回恆等與空陣列；另 9 條首跑即綠：對空集合或恆等值的斷言恰好成立） | 16 tests 綠 |
| T4 歌曲目標值 | 新增 2 suites 的大部分條目紅（空殼：覆寫表空、resolve 一律 mono、正規化原樣）；`GenreStyleResolverTests` 照舊綠 | 連同 `GenreStyleResolverTests` 21 tests 綠 |
| T5 組合器 | 空殼（fit 恆 0、compose 恆 mono、驗證器恆過）：Fit 5 條、Composer 8 條紅；空集合斷言與驗證器的「真目錄通過」首跑即綠 | 18 tests 綠，含 P11（Cradle 256 seed 抽不到 6 個點名溫柔元件）與反向（Nightwish 抽得到 ≥ 3 種） |
| T6 session recipe | 9 tests 中 7 紅（VM 尚未組配方）；修一次：兩首都沒有 persistentID 時既有判定視為同一首、快照相同就提早 return，新 session 沒定格 → 快照相同也嘗試定格 | 連同既有 VM／AppModel 43 tests 綠 |
| T7 組合風格繪製 | `ComposedStyleFrameTests` 先寫，對未實作的型別**編譯失敗**＝紅；實作後 2 條紅是測試的時序假設錯（condense 長達 1.7 s，行尾時末字可能還在凝結；負片時刻有抖動）→ 改測試的取樣時刻，不放寬斷言 | 組合 18、探針與字型 3、組裝 +3、mono／幀耗時既有，共 66 tests 綠 |
| T2 型別換形 | 新測試（golden 等價 3、run 切分 6）對舊型別**編譯失敗**＝紅（新型別不存在） | golden 2374 列逐欄相等；連同既有 mono／版面／排程／離屏渲染共 30 tests 綠 |

### 8.2 每幀耗時（G0 spike；G4 帶效果）
**G0（2026-10-06；真視窗、dense 預覽場景 200–305 字、主執行緒 plan＋Canvas 指令編碼、每窗 600 幀，列穩態各窗範圍）。** spike 用將來的畫法（每字 transform 併 Path、連續同鍵才合併），量完已刪。
| 組合 | Debug -Onone p50 | -O p50 | -O p95 |
|---|---|---|---|
| mono 原樣 | 0.8–1.4 ms | 0.8–1.1 ms | 1.3 ms |
| 逐字旋轉縮放＋20% 字透明度在變 | 1.4–1.8 ms | 0.7–0.8 ms | 1.1 ms |
| 同上＋殘影 4 份（20% 字）＋顆粒＋暈影＋300 粒子（殘影跨鍵合併） | 2.9–3.5 ms | 1.1–1.5 ms | 1.7–1.9 ms |
| 40% 字在進或退場、各 4 份殘影（**保序**）＋顆粒＋暈影＋300 粒子 | — | **0.89–1.11 ms** | **1.69–2.03 ms** |
| 最壞：200 字全部 4 份殘影（保序）＋顆粒＋暈影＋300 粒子 | 3.7–5.2 ms（逐 run 填） | **1.34–1.47 ms** | **1.95–2.53 ms** |
- 拆分：顆粒＋暈影＋300 粒子在 Debug 只多約 0.3 ms；成本在殘影的 path 組裝與「透明度不同 → run 斷開 → fill 次數增加」。
- **判定口徑（與 Codex 辯論後定案）**：以「DEBUG 旗標保留、最佳化旗標與 Release 對齊（`SWIFT_OPTIMIZATION_LEVEL=-O`）的量測建置」判定：p50 ≤ 2 ms、p95 ≤ 3 ms。Debug -Onone 照列為診斷參考，不稱上界。每筆記建置設定、glyph 數、活躍殘影字數、份數、fill 數。熔斷＝-O p50 > 4 ms，且依序減粒子、殘影／顆粒密度後仍無效。
- **定案常數**：每字最多 4 份殘影；只給進場中與退場中的字；殘影與主字同樣保 painter order（不跨鍵合併——Codex：跨鍵會改疊色語意）；不限活躍比例（最壞也過門檻）；粒子上限 300。
- 實作時發現（T3）：原型**組合模式**的 `rise` 本來就不畫光點——`styleFromRecipe` 的 paint（`html:1034-1046`）不讀 `glow`；Codex 家族辯論 F6 引用的 `html:467` 是舊的 cathedral 家族 paint。故 B1 的 `rise` 照組合模式移植＝只有位移與透明度，不加 dots（比 F6 的處置更忠於使用者看過的組合器）。同理 `smoke` 在組合模式畫 5 份殘影、alpha×0.25、不畫本體（`html:1041`），G0 的上限 4 份改為 5 份，於 G4 以正式 renderer 重量確認。
- 未量：render server 光柵化（整幀）。G4 以正式 renderer 重量時補一次 xctrace 或實機 FPS 證據，量不到就明記未量。
- 量測腳本事故（已處置）：第一次腳本中 zsh 內建 `log` 遮蔽 `/usr/bin/log`，且找行程的 `pgrep` 未限定路徑、可能誤殺使用者正在用的 `/Applications` 版 app；在動手前停掉，改用 `/usr/bin/log` 與限定開發版路徑。使用者的 app 未受影響。
**T2 像素比對（DoD③）**：32 張定格（4 fixture × 4 時刻 × full／reduced，2x）。平均絕對差最大 0.00115（門檻 1/255＝0.0039）全過。「差異像素占比 ≤ 0.5%」在 8 張**淡入淡出中**的 full 定格超出（0.6–6.9%，最大差 4–6/255）：成因是透明度量化到 0.05 一階（§3.2 已接受的取捨），靜止與 reduced 定格占比 ≤ 0.005%、最大差 1/255（抗鋸齒）；唯一例外 wrap-4.05-reduced 有幾個像素差到 20/255（占 0.0011%，推測為參考字級縮放後外框的次像素位置差）。判定：符合預期，記錄在案。

**G4（2026-10-06；正式 renderer、-O 量測建置、真視窗）**
| 組合 | 負載 | p50 | p95 | 判定 |
|---|---|---|---|---|
| Catacombs,snow,smoke,dissolve,misreg,shake,ice | dense（≤138 字＋≤331 副本） | 3.8–5.3 ms | 6.8–7.5 ms | **未過** |
| Catacombs,void,condense,cut,none,none,ice（無副本） | dense（≤105 字） | 0.73–0.97 ms | 2.6–3.4 ms | p50 過、p95 擦門檻（最差 3.4 ms＝未過） |
| Grimoire,snow,smoke,dissolve,misreg,shake,ice | dense（≤136 字＋≤335 副本） | 0.95–1.39 ms | 2.08–2.26 ms | 過 |
| Cinzel,shafts,smoke,fade,breathe,none,goldNavy | dense（≤138 字＋≤75 副本） | 1.0–1.7 ms | 2.4–2.7 ms | 過 |
| Catacombs 最重組合，P12 後 | 一般預覽歌詞（≤88 字），使用者在看 | 0.7–1.6 ms | 1.8–2.8 ms；長句換行窗 5.4 ms | p50 過；p95 一窗超 |
- 定位（有證據）：plan 0.07 ms／幀，成本全在繪製；繪製成本 ∝（主字＋副本）×字型外框元素數（Catacombs 324／字、Cinzel 55、Grimoire 16；離屏 2x 每實例 ~12／3／1 µs）。已排除：填色次數（分組後 200→25 次，沒變快）、逐幀重抄外框（跨幀路徑快取，沒變快）；兩個實驗皆已撤回。
- 不採：Canvas 背景光柵化（只把成本換位置，Codex 同意 J1）。
- 「200 字」：組合風格字級＝畫面高 12%，dense 預覽同時最多約 138 字，畫布塞不下 200 個；以上數字報的是實際同時字數。
- **使用者裁定（2026-10-06，看過 Catacombs 最重組合的真視窗後，觀感順）：維持現狀、照實記錄**——不減副本、不換字、不放寬上限。Catacombs 在壓力負載與長句換行時超出 2 ms／3 ms 列為已知；字形點陣（alpha-mask）快取列為 B2 候選。
- 整幀（render server）：2026-10-07 已量，見 §8.6。

### 8.3 探針記錄（同步寫進母計劃附錄 B）
- **黑金屬、交響兩家族探針簽字（2026-10-06）**：總覽頁（各 3 個 nonce，6 秒動圖＋4 張定格；P12 後重出）。使用者：「都是對的，沒問題」。
- P12（2026-10-06）：真視窗看 Catacombs 最重組合，「漸入漸出稍長、字發虛」→ 淡入型進場與殘留淡出縮短 40%；複看「這回可以了」。
### 8.4 閘門（Phase 3 前；評審若引出修改需重跑）
- 全量單元（skip `BatchOverlappingLoadTests/overlappingLoadSuspendsPollingUntilLastCompletes()`）：**1130 tests／129 suites**；紅＝基線 `CoverFlowStripRenderGeometry` 7 斷言＋`CoverFlowSlideGeometryTests` 3 斷言＋`CoverFlowStripStackingTests` 3 斷言。後兩組**不是 B1 引入**：同一時間在 A2 基線 e640d4b 的 worktree 單跑，恰好同樣 6 斷言紅（A2 收尾時同版本是綠的）→ 今日環境相依（觸控板捲動模擬；根因 TBD，非 B 範圍，交使用者決定是否另案）。
- `no_playback_gate.sh` exit 0；Python 333 OK；`MusicSelectorAllowList` 綠；`coverage_gate.sh <xcresult>`：Services+Infra 96.2%（門檻 80%），豁免 408／410 未動。
- xctrace（Animation Hitches，15 s，附著預覽視窗）：這次錄得到也匯出得了；hitches 表 0 筆，但每秒換幀只有 0–21（含無字空檔 0–1）→ 推測視窗不在前景被節流，**不作結論**；使用者在場時把視窗放前景重錄。
### 8.4b UI 測試（使用者在場，2026-10-06 晚）
- 實跑 `LyricsFXUITests`（7）＋`LyricsFlowUITests`（9）：**7 過、9 紅**。過的含 B1 新增 3 條（黑金屬自動選風格、未知曲風 mono、減少動態效果 mono）。
- 9 紅全是「元件 not hittable」（座標為負，如 x＝−158／−836／−1306）或「Failed to create screenshot」→ app 視窗開在主螢幕左側的第二螢幕（2732×2048，推測為 iPad Sidecar，未驗證）。推測今日 `CoverFlowSlideGeometryTests`／`CoverFlowStripStackingTests` 的環境相依紅也同因（未驗證）。
- **待辦（下個 session）**：使用者斷開第二螢幕後只重跑這 9 條；仍紅即熔斷記錄，不重試。→ 2026-10-07 已重跑，9／9 綠（§8.6）。

### 8.5 Phase 3 評審（/simcodex）
| 輪 | 來源 | 採納並修 | 駁回／延後（理由） |
|---|---|---|---|
| R1 | simplify：層級 | VM 的「同一首」只剩一個定義（signature）：沒有 persistentID 的新曲不再沿用前一首的 genre，拿掉快照相同時的定格特例（補測試 `aNewTrackWithoutAnIDDoesNotInheritThePreviousGenre`；修正先於測試，已以暫換回舊判定確認該測試會紅）；配方含目錄外 id 時 `assertionFailure`（Release 退 mono） | 每幀重新解析配方（plan 整體 0.07 ms）、`ascent` 預設值、DEBUG 覆寫改注入式、genre 每關鍵字重切詞：P2 延後 |
| R1 | simplify：重用 | `Mono.eased` 改呼叫 `FXEasing.outCubic`；6 處手寫夾取收成 `FXEasing.clamp01` | `RGB(hex:)` 與 `Color(hex:)` 共用解碼、探針出圖共用離屏函式：P2 延後 |
| R1 | simplify：簡化 | 刪死碼 `FXEffect.trigger`、`GlyphPersonality.indexInWord`、`FontFace.tracking`；兩處粒子分桶共用 `ComposedBackdrop.particleLayers`；70 行的 `draw` 拆成 `glyphTransform`／`emit`／`layout` 純函式；DEBUG 指定配方改在組合前判斷 | 其餘 P2 延後 |
| R1 | simplify：效率 | 彈片堆改用每詞（起點, 寬）表，免每字重掃整行（原 O(n²)）；可見行先比時間再判空白 | 逐行快取版面與個性、量測 API 改寫：駁回——plan 實測 0.07 ms／幀，低於 §3.4 的 0.1 ms 門檻；其餘 P2 延後 |
| R1 | codex review（--base e640d4b） | 無可指出的回歸 | — |
| R2 | simplify（四角度合併，只看 R1 修正） | 無 P0／P1 | 5 條 P2 延後；「註解別寫評審出處」駁回——專案既有慣例（如 `Codex R1 #11`） |
| R2 | codex review（--uncommitted） | 無正確性問題 | — |
- 無安全敏感改動（無認證、無外部 API、無檔案寫入的新路徑），未派 security-reviewer。
- 評審後全量：**1131 tests／129 suites**，紅＝基線 7＋環境相依 6（同 §8.4，A2 基線同樣紅）；B1 無新紅。coverage 96.2%；no_playback 0。

### 8.6 收尾（2026-10-07；b11bc98，工作區無程式改動；只剩內建螢幕 3456×2234、輸入法 ABC）
- **Codex review**（`codex review --commit b11bc98`，gpt-5.6-terra／medium；涵蓋六槽推廣＋配方歷史＋三枚字型）：「No discrete correctness regressions」。無條目可裁決，未改碼。
- **環境相依 6 斷言**：單跑 `CoverFlowSlideGeometryTests`＋`CoverFlowStripStackingTests` 13 tests／2 suites **全綠**；全量裡也不再紅。事實＝接第二螢幕時紅（B1 與 A2 基線皆然）、斷開後綠；「第二螢幕是成因」仍屬推測（未做接回重現），機制 TBD，非 B 範圍。
- **UI 測試**：只重跑 §8.4b 的 9 條（`LyricsFXUITests` 4：StyleButtons／Relaunch／ArrowKeys／FrozenPreview；`LyricsFlowUITests` 5：PresentLyrics／MissingLyrics／ClickingPlayingCard／MarkingNoLyrics／KeyboardFocus）→ **9／9 綠**（124 s，一次過，未重試）。連同昨晚已過的 7 條，16 條皆有綠的紀錄（分兩次跑，非同一輪）。`SystemAttachmentLifetime=keepNever`。
- **整幀（已量）**：-O 量測建置、預覽 dense＋`Catacombs,snow,smoke,dissolve,misreg,shake,ice`（I-25 已知未過的壓力負載）、視窗錄製前後皆為最前景（`lsappinfo front`＝該 pid）、`xctrace record --template 'Animation Hitches' --attach` 15 s、120 Hz 內建螢幕。
  | 表 | 結果 |
  |---|---|
  | `hitches-renders`（render server 每幀） | 1430 筆：p50 2.36 ms、p95 4.88 ms、最大 15.32 ms；離屏 pass 全為 0 |
  | `hitches`（本 app） | 804 筆：8.33 ms×671、16.67 ms×127、12.5 ms×2、20.83 ms×1、25 ms×3；標註 `Potentially expensive app update(s)` 32、GPU 1、render 1 |
  | `hitches-updates`（app 更新段） | 1062 筆：p50 16.78 ms、p95 17.08 ms、最大 18.77 ms |
  | `displayed-surfaces-per-second` | 17 秒窗：0–95，合計 766（平均約 45／s；含無字空檔） |
  | `potential-hangs`（主執行緒） | 7 筆：89、102、105、174、245、271、292 ms |
  - 判讀：render server 光柵化不是瓶頸（p50 2.4 ms，無離屏 pass）——已核。多數幀晚一個 120 Hz vsync，**推測**是 app 端大約每兩個 vsync 才交一幀（依據：更新段 p50 16.8 ms≈2×8.33 ms；`hitches-updates` 的 duration 是否含等待未查證）。主執行緒 7 次 89–292 ms 無回應的成因 **TBD**（未對 time-profile 取樣歸因；可能與長句換行窗、xctrace 附著開銷有關，皆未驗證）。
  - 處置：不設新門檻、不重開 G4 裁定（同一組合、同一負載，使用者已裁定維持現狀）；主執行緒無回應列入 B2 字形點陣快取的量測對照項。本次未量一般歌詞負載與其他字型的整幀。
- **閘門**：全量單元（同 §8.4 的 skip）**1144 tests／131 suites**，紅＝基線 `CoverFlowStripRenderGeometry` 7 斷言，別無其他；`MusicSelectorAllowList` 綠；`no_playback_gate.sh` exit 0；`coverage_gate.sh <unit.xcresult>` Services+Infra 96.2%（2731／2839；豁免 1 檔 408／410）；Python 333 OK。
- ACCEPTANCE：I-18（fit 不平方）、I-25（整幀）、I-27（改寫為六槽＋現行測試名）同步。


## 9. 影響面、風險、回退
- 新檔（`Features/LyricsFX/`）：`FXSeed.swift`、`GlyphTemplates.swift`、`GlyphPersonality.swift`、`ComposedStyle.swift`、`LayerDraw.swift`（或併入 Frame）、`Composer/{FXAxis,FXComponent,LyricsFXCatalog,CatalogValidator,Composer,SessionRecipe}.swift`；`Services/Lyrics/SongProfileResolver.swift`；`Resources/Fonts/*`＋授權檔；對應測試。需 `xcodegen generate`（逐檔 add；不碰既有未追蹤的「 2.xcodeproj」）。
- 改檔：`LyricsFXFrame.swift`、`MonoStyle.swift`、`TextMeasuring.swift`、`LyricsFXView.swift`、`LyricsFXViewModel.swift`、`AppModel.swift`（注入 nonce 來源，若建構子需要）、`App/UITestSupport/LyricsFXPreviewFixture.swift`／`LyricsFlowUITestMusic.swift`（三個環境變數）、`AccessibilityID.swift`（recipe 探針）、About 的授權清單、`project.yml`（若字型路徑要動）、`ACCEPTANCE.md`、母計劃附錄 B。**不改** `MusicAppleEventsClient.swift`、`NowPlayingMonitor.swift`、`GenreStyleResolver.swift`、Cover Flow 任何檔。
- AE 量：不變（artist 已在 `TrackInfo`，不多讀欄位）。
- 風險：
  - R1 G0 超預算 → §3.0 的處置順序與熔斷點。
  - R2 型別換形波及面大（T2）→ 以「mono 定格圖逐像素相同」當回歸網。
  - R3 靜態字型在 `ATSApplicationFontsPath` 下未註冊或 family 名對不上 → 目錄完整性測試先行；fallback 到系統字會讓探針失真，所以該測試是 T7 的前置。
  - R4 探針三輪不收斂 → 熔斷：把事實與已排除的方向記進 §8.3，交使用者決定換家族或換做法。
  - R5 隱私：manifest 與日誌不含歌詞；覆寫表內是公開樂團名（非使用者資料）。
  - R6 字型授權：只內建已明確者；清單進 About。
  - R7 既有行為、B1 範圍外：權限被拒時 monitor 不清 `lastSignature`（`NowPlayingMonitor.swift:232-233`），權限恢復後若仍是同一首，Editor、Cover Flow 分支與特效都停在拒絕／清空狀態，直到換曲或停播再播。改它會改 Editor／LyricsFlow 的可觀察行為（1:1 移植規則），交使用者決定是否另案。
- 回退：偏好預設 `coverFlow`；組合器對未涵蓋曲風回 mono；整條分支未併 main。checkpoint 只在本機 `wip/` 分支，不 push。

## 10. 待拍板
- 已定：兩個家族＝黑金屬＋交響（§3.8，/thecure 收斂）。待使用者確認「執行計劃 v4」。
- 其餘技術取捨已在 §1、§3 定案。

## 附錄 A　Codex 辯論記錄
### A.0 開工前辯論 R1＋R2（gpt-5.6-terra，medium；2026-10-06）
| # | 論點 | 提出方 | 狀態 | 證據／處置 |
|---|---|---|---|---|
| J1 | B 拆 B1／B2；B1＝引擎＋完整機制＋兩家族＋探針 | 我 | 我勝（Codex 同意方向；補「再切兩道可交付閘門」→ 採納成 G0–G4） | 母計劃 `:185-193,214-216,321-322` |
| O1 | 風險最高的壓測前置成 G0；B1 的模糊＝殘影、不開 filter | 我 | 我勝；Codex 勝一處：G0 不比較真 blur，只比殘影參數，且必須用將來的畫法 | `lyrics-fx-preview.html:527,579,1041` |
| J2-1 | 不收按行界排程 | 我 | 一致 | 母計劃 `:161-167` |
| J2-2 | 收 Mono 常數與 Moment 參數化 | 我 | 一致 | `LyricsFXFrame.swift:75-83` |
| J2-3 | 量化分組＋transform 併 Path | 我 | 部分：Codex 勝四處細節（pivot、色要離散、殘影 alpha 進鍵、量化誤差要寫明）；「不可合併標記」Codex R2 撤回 | `LyricsFXView.swift:6-27`；A2 計劃 `:199-203` |
| J2-4 | 單位字級快取 | 我 | 部分：Codex 勝（以 `CTFontCopyVariationAxes` 驗證、`FontFace` 要帶字重） | `TextMeasuring.swift:7-25,68-106`、`MonoStyle.swift:35,48` |
| J2-5 | 其餘九條不收 | 我 | 一致 | A2 計劃 `:223` |
| J3 | profile 由關鍵字合成，不由 family 查表；覆寫表出貨 | 我 | 我勝；Codex 補：逐軸算子、generic 規則、req／forbid 對未知軸的語意 | `GenreStyleResolver.swift:40-67,78-84`、`composer.js:142-160` |
| O4 | 不做別名表 | 我 | 我勝（Codex：無漏接實證；補固定 locale 與 idempotence） | — |
| J4 | `lyricsRevision` 不進鍵 | 我 | 我勝 | `LyricsFXViewModel.swift:68-73,111-119` |
| J4′ | genre 晚到時同 nonce 重算 | 我 | **Codex 勝** → 改「第一次取得可用 profile 時定格，最多一次」；未知 genre＝已解析的 mono；定格時比 session | 母計劃 `:189` |
| J4″ | 種子材料 | Codex | Codex 勝 → 用 `track.signature` | `MusicControlling.swift:16-19` |
| J5 | 型別形狀 | 我 | 部分：Codex 勝（`SessionRecipe.mono` 取代 nil、背景要有序多層、pivot 明定） | 母計劃 `:157`、`composer.js:169-183` |
| J6 | 探針離屏出圖 | 我 | 部分：Codex 勝（不宣稱離屏＝真視窗、GIF 20→30 fps、附 manifest） | `LyricsFXPreviewRenderTests.swift:19-31,87-104` |
| Q7 | 遺漏 | Codex | 採納：目錄驗證器、industrial∩nu＝空的測試、字型授權是交付阻塞項；原型無候選回 `list[0]` 是錯的 | `composer.js:162-174`、母計劃 `:125-145,321` |
- R2 整體確認：修正兩項後「無異議」（`FontFace` 帶字重；G0 不量真 blur）；閘門順序妥當。
- **Codex 最擔心的一點**：把「量化後併 Path」當成純效能優化——它在半透明重疊時會改畫面（已列為明示取捨，§3.2）。
- **最易失敗的一步**：G0——真視窗 200 字＋殘影＋顆粒＋漸層＋300 粒子仍要 p50 ≤ 2 ms；最可能被迫調的是粒子與殘影上限，不是字數。
- 不是全採納／全駁回：16 條中我勝 7、Codex 勝或補正 9。

### A.1 計劃評審 R1（2026-10-06）
| # | 論點 | 嚴重度 | 狀態 | 處置／證據 |
|---|---|---|---|---|
| 1 | 跨 run 分組會改 painter order | P1 | Codex 勝 | 只合併連續同鍵（§3.2）；加 run 切分與順序渲染測試 |
| 2 | fx2 排除後無候選未定義 | P1 | Codex 勝 | fx2 非必選、無候選＝none；三種表驅動測試 |
| 3 | metadata 事件只帶 persistentID，空 ID 曲目會套錯 session，應改事件契約 | P1 | **我勝（待 R2 反駁）** | `metadataChanged` 只在同 signature 時發（`NowPlayingMonitor.swift:222-226,249-255`），單一串流依序消費（`AppModel.swift:331`）——不會晚到下一首之後；不改契約 |
| 4 | `FramePlan` 表達不了逐字附加形狀；部分效果依賴サビ／關鍵字 | P1 | Codex 勝 | 加 `ShapeDraw`；效果宣告 trigger；negflash、blood 移出 B1；逐效果定點測試 |
| 5 | T11 DoD 判定不了「帶效果」 | P2 | Codex 勝 | 固定最重 recipe＋計數記錄 |
| 6 | T2 逐像素 DoD 脆弱且覆蓋不全 | P2 | Codex 勝 | 改 golden plan 等價＋fixture 集＋寬鬆像素 diff |
- Codex 最擔心：合併 path 改掉半透明字的繪製順序（已改 run 合併）。最易失敗：T7／T9 用背景近似或靜默省略效果讓探針「有圖」——已以逐效果定點測試與 manifest 封口。

### A.2 計劃評審 R2＋R3（2026-10-06）
| # | 論點 | 狀態 | 處置／證據 |
|---|---|---|---|
| R1-3 | metadata 不會套錯 session | **我勝（Codex R2 核實撤回）** | `NowPlayingMonitor.swift:223,249`（actor＋單飛）、`AppModel.swift:331`（FIFO、無 await） |
| R1-1,2,4,5,6 | 修改是否封口 | 封口 | — |
| R2-a | T10／T11 對調：先量最重 recipe 再簽字 | Codex 勝 | 已對調 |
| R2-b | 權限被拒後恢復不會開新 session，應在 B1 改 monitor | 事實 Codex 對；處置**我勝（R3）** | 不改 monitor：Editor（`EditorViewModel.swift:79-80`）、LyricsFlow（`LyricsFlowReducer.swift:86-91`）同樣依賴下一個 trackChanged，改了會動既有可觀察行為；從 session 定義與驗收移除該說法，記 §9 R7 |
- R3：「就這些文字修訂後的 B1 計劃，無異議。」最易失敗的一步：G0／T0。

### A.3 家族辯論 R1–R3（/thecure，使用者指示；2026-10-06）
| # | 論點 | 提出方 | 狀態 | 證據 |
|---|---|---|---|---|
| F1 | 第二家族＝龐克（零元件被 B1 排除） | 我 | **Codex 勝**：前提錯，underline 是サビ觸發，且 v3 把它列進子集＝內部矛盾 | `html:582`、`composer.js:100` |
| F2 | P11 在無交響元件時是空測 | Codex | Codex 勝（我承認的弱點 b 不足以抵銷） | 母計劃 `:322` |
| F3 | FitTests 已證 forbid 機制 | 我 | 成立但只證機制，不證真目錄的向量與門檻 | `html:974-979` |
| F4 | 改交響則 P9 空測 | 我 | 成立；P9 主要靠標籤閘門、使用者未抱怨過，P11 是實際抱怨 → 優先 P11 | `composer.js:66-67` |
| F5 | Geizer、embers、fall、steel 不屬兩家族 | Codex | Codex 勝 | `composer.js:16,41,76,108` |
| F6 | rise 去 glow 是否同一元件 | Codex | Codex 勝 → 以 dots 重現三個光點 | `html:211,467` |
| F7 | reflect：Codex 提「加 forbid」；我提「移出 B1」 | 雙方 | **我勝（R3 Codex 明言對）**：是否溫柔屬使用者審美，不替他加規則 | 母計劃 `:322` |
| F8 | 七個 profile 六槽皆有候選 | Codex 核算 | 一致 | 附表見 Codex R3 |
- R3：「對最終 B1 子集：無異議。」Codex 最擔心：讓 P11 測試綠燈但證的是較弱命題（已改為只斷言 B1 內實際存在的點名元件，並加 Nightwish 反向斷言）。

### A.4 字型抽籤（使用者指示 /thecure＋Jev；2026-10-06）
- 起因：使用者看探針發現黑金屬三次都是 Catacombs；原因＝探針只用曲風（沒用樂團名）＋fit² 加權讓最合身者一家獨大（名單外 Black Metal 90%）＋原型的 Cenobyte／Dark Metal／Mirage 因授權未確認沒放。使用者裁定三字型「放進去，風險我承擔」，並要「每次都給我感覺變了」。
- Jev（jev-1.13.0，noul「該樂團樂迷會覺得此字型合身」，state 只送樂團名與字型描述）：黑金屬樂團對 6 套黑金屬字型多為 .63–.93、對 Cinzel／Cormorant .11–.33 → 不支持 Catacombs 一家獨大。依 thecure，模型機率只當參考訊號、不判勝負。
| # | 論點 | 提出方 | 狀態 | 證據 |
|---|---|---|---|---|
| F1 | 字型槽改前 5 名均等 | 我 | **Codex 勝**→改 fit（不平方）：均等把 Mirage 對一般黑金屬由 1% 拉到 20%，違反「隨機要適當」；「每次感覺變了」由 F2 保證 | 實測分布表 |
| F2 | 同一首排除上次字型、持久化 | 我 | 我勝（不是 YAGNI：使用者要「每次」） | — |
| F2′ | 鍵＝fnv1a64(signature) | 我 | Codex 勝：無 ID 時 signature＝三元組，可字典還原 → 改**只以 persistentID 為鍵、無 ID 只記憶體**（R2 我提、Codex 同意：既有「沒有歌詞」標記與時間軸存檔同樣以 persistentID 存；Keychain 在 ad-hoc 簽名下會跳框） | `ConfigStore+NoLyricsMarks.swift:12-21` |
| F3 | 決定論契約 | Codex | 採納：Composer 純函式照舊；VM 在相同歷史下可重現；字型排除**同一次 RNG 取樣**，其餘五槽與配方種子不動（測試釘住） | `ComposerFontTests.avoidanceLeavesTheOtherSlotsUntouched` |
- 結果（名單外 Black Metal）：Catacombs 36%、Dark Metal 25%、Cenobyte 22%、Grimoire 11%、Mirage 6%；同一首相鄰重複 0%。配方 schema 版本 1→2。
- **推廣到六槽（使用者 2026-10-06：「全部都要隨機起來」）**：每槽都改 fit（不平方）＋同一首歌每槽排除上一次的元件（只剩一個候選才允許重複）；歷史改存整份配方的六個元件代號（`LyricsFXLastPicks`，persistentID 鍵、500 筆 LRU）；schema 2→3。Codex 審字型改動時抓到 UI 測試允許清單過舊（P1），已修。此推廣的 Codex review 已於 2026-10-07 補跑（`--commit b11bc98`）：無回歸，見 §8.6。
- 字型清點（回答使用者）：原型組合器共 26 套字型；掛黑金屬標籤的 6 套全數在 app（Catacombs、Cenobyte、Grimoire、Dark Metal、Mirage、Fraktur），交響另有 Cinzel、Cormorant；其餘 18 套屬其他曲風家族，B2 加。
