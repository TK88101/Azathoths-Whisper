# Lyrics FX — B2「按樂團擴充＋rock 系元件重新設計」實施計劃 v3（B2 順序辯論 R1–R4、計劃評審 R1–R3 已併入，Codex 無異議；使用者 2026-10-07 確認執行）

母計劃：`docs/plans/2026-10-03-lyrics-fx-mode.md`（§2.10）。前一段：`docs/plans/2026-10-06-lyrics-fx-b1-engine-composer.md`（B1 已合入 main d569528）。

## 0. 複述
- 目標＝讓曲庫裡**大多數**歌在歌詞特效裡有合身的組合風格，而不是 mono；做法是按**樂團**擴充覆寫表，每批先在原型裡設計元件與樂團目標值、使用者看探針簽字，再移植進 app。
- 完成標準（本計劃只含 **B2-0＋批 1**）：①主執行緒 89–292 ms 無回應有歸因結論；②批 1 的 8–12 個樂團在真視窗得到使用者簽字的組合風格，每團六槽每槽 ≥ 2 個候選（「同一首每次不一樣」成立；六槽＝字型、背景、進場、退場、第一效果、配色——第二效果是可選的附加層，不在排除範圍，B1 現況 `RecipeHistory.swift:28-32`）；批 1 各團在曲庫中的實際樂團字串命中率 100%（§3.5）；③未簽字的團與曲風行為不變。
- 不做＝見 §2。

## 1. 已核事實（推翻 B1 時的前提；2026-10-07 唯讀統計使用者 Music 曲庫，原始資料只在 session 暫存目錄，不進 repo）
- F1 曲庫 12,252 首、97 個曲風標籤、489 個樂團（母計劃 §2.5 的 9,577 首是 10-03 的採樣）。
- F2 **日文曲風標籤不是日本樂團**：「ロック」788 首、「メタル」1,687、「オルタナティブ」437、「パンク」480 都是日本商店語系的曲風名，裡面是 The Beatles、Slipknot、Nirvana、Blink-182 等；樂團名含假名／漢字的只有 2 團 15 首。→ 母計劃「jrock 3,378 首＝35%」與 B3 日文體系不成立，**B3 撤銷**。
- F3 現行 `GenreStyleResolver` 以 `japaneseTags = ["ロック", "j-pop"]`（`GenreStyleResolver.swift:38,58`）把所有「ロック」判成日本語系 `.jrock`。B1 組合器走 `SongProfileResolver.resolve`（`LyricsFXViewModel.swift:180,183`），**不讀**這個判定，故不影響目前畫面；但 `LyricsFXViewModel.genreStyle`（`:146`）存的是錯值，且 ACCEPTANCE I-08 不能再當「曲庫分類正確」的證據。→ 另案（§2），本計劃不修。
- F4 **曲風標籤在樂團層級不一致**：前 100 團中 31 團有 ≥ 3 種標籤（同一團散在 Rock／Hard Rock／Metal 等）；「Hard Rock」920 首是 4 個風格迥異的團混在一起。按標籤給風格，同一團不同首會互相矛盾。
- F5 **樂團集中**：前 20 團 35%、前 50 團 55%、前 100 團 71%、前 150 團 78%、前 200 團 84%。
- F6 機制已就緒：`SongProfileResolver.resolve` 先查樂團覆寫表（目前 **28 團**，`SongProfileResolver.swift:38,95`），命中即用，否則 genre 關鍵字列，再否則 mono（`:51-52`）。覆寫表以 `Dictionary(uniqueKeysWithValues:)` 建（`:40`）——兩團正規化後同鍵會在啟動時 trap。
- F7 原型 rock／indie 元件單薄：掛 `rock` 的配色只有 `sunsetInk`（夕燒蜜桃底）、效果 0；掛 `indie` 的配色只有 `newsprint`、進退場各一（`composer.js:23-119`）；原型 28 團裡沒有任何 rock／indie／alternative 團（`:124-153`）。→ 批 1 不是移植，是**重新設計**（使用者 2026-10-07：「rock 要多一些，是不是需要重新設計」）。
- F8 每幀 60 fps 上限是設計（`LyricsFXView.swift:153-154`），B1 §8.6「多數幀晚一個 vsync」由此而來，不是字形慢的證據。

## 2. 目標與非目標
- 目標：B2-0 歸因；批 1（8–12 團，rock／brit／indie 一群）從原型設計到 app 交付；擴表的工具與測試（正規化碰撞、六槽候選覆蓋）一次做好，供批 2 以後重用。
- 非目標（明列防膨脹）：
  - 批 2 以後的團（到前 50 團、再到前 150 團）——各自另寫小計劃或在本檔追加，覆蓋目標到 50 團時重量一次再決定。
  - サビ／關鍵字效果（③，最後做）；字形點陣快取（②，條件式 spike，見 §3.1 出口）；Jev（D 段，需 key）；Settings 手調；Cover Flow。
  - F3 的「ロック→日本語系」誤判：另案記錄（改它會動 A1 的 I-08 行為與測試，須使用者另批）。
  - 同團分時期（artist＋album 例外）：先不做；探針明確顯示失真才在後續批次加少量例外。
  - 新加入曲庫的團自動猜測：不做，未知＝mono（刻意的安全退路）。

## 3. 設計
### 3.1 B2-0 主執行緒無回應歸因（不阻塞批 1）
- 用 B1 的 -O 量測建置與預覽場景，xctrace `Time Profiler`＋`Animation Hitches` 各錄 15 s、視窗在前景，四組：(a) 升起層＝Cover Flow（特效不可見）；(b) mono；(c) Catacombs 最重組合 dense；(d) 同 (c) 但以 `AZW_LYRICSFX_PREVIEW_AT` 凍結畫面。
- 協定（計劃評審 R1 #4）：每組錄 **3 次**×15 s；每次記前景 pid、預覽同時字數、輸入裝置不動；以 xctrace `potential-hangs` 表為準（不另設門檻），每組報 hang 次數／總時長、hitch 次數，與 hang 區間內主執行緒樣本的分桶比例。
- 對每筆 potential-hang 區間取主執行緒樣本、按頂層呼叫分桶：字形外框（`GlyphPathCache`）、Canvas 組裝／fill、SwiftUI 更新、時間軸／VM、AppModel／Music 事件、量測附著與系統服務。必要時臨時加 `os_signpost`（量完撤回，不進 commit）。
- **閘門（計劃評審 R1 #1，Codex 勝）**：若 (c)／(d) 有 hang 而 (a)／(b) 沒有（＝特效特有），**T3、T4、T5、T6、T7 停手**（凡會改變 app 繪製負載的——新繪製、新字型、新目錄元件——都不在已知卡頓上再加；計劃評審 R2 #1），先交使用者決定：接受、降級元件，或先做②spike。T1、T2（原型與探針，不動 app 繪製）可照常進行。若 (c) 三次都沒錄到 hang → 結論寫「未能重現」，不得寫「與特效無關」。
- 出口（只做判定，不在此修）：hang 主要落在文字繪製 → ②spike 進入 B2 後續（判據沿用 R1：p50 改善 ≥ 30% 且 p95 不變差、視覺容差、hang 下降，三項全過才落地、只對特定 face）；落在別處 → 記錄根因與位置，交使用者決定是否另案；(a)(b) 也出現 → 與特效無關。

### 3.2 批 1 的樂團（草案，使用者拍板）
- 原則：先挑一群**共享視覺語言、曲數多、彼此差異清楚**的團，把 rock 系元件的缺口一次暴露出來。
- 草案：The Beatles、AC/DC、Oasis、Blur、The Killers、Coldplay、Guns N' Roses、Queen、Pink Floyd（9 團，皆在曲庫前段）。對照組：AC/DC vs Oasis（硬搖滾 vs 英倫）、Beatles vs Pink Floyd（早期流行搖滾 vs 迷幻／前衛）、Coldplay vs Blur。
- Linkin Park、Gorillaz、Lana Del Rey、Slipknot 等視覺語言不同，留給後續批次各自成群。

### 3.3 每批的流程（批 1 先走一遍，之後重用）
1. **原型設計**（不寫 Swift）：在 `docs/plans/2026-10-03-lyrics-fx-assets/composer.js`（未追蹤，不進 repo）加批內各團的目標值草案（十軸＋標籤）與缺的元件；每槽至少 2 個能被該團抽到的候選。新元件沿用既有六槽與 kind，**不改 schema**（§3.4）。
2. **探針**：組合模式總覽頁，每團 3 個 nonce 的 6 秒動圖＋定格，並排對照組；附每團一行性格說明（白話，不給十個裸數字）。
3. **使用者反應**：「對／不對＋一句」，每條轉成規則記進母計劃附錄 B（P13 起）；最多三輪，不收斂即熔斷（記事實，交使用者決定）。
4. **簽字後移植**：§3.5。
5. 未簽字的團不進表、維持現狀。

### 3.4 契約凍結（R3 Codex 勝：原型與 Swift 並行時不可回頭改）
- 不變：六槽與各槽 kind 的語意、`FXTag` 匹配規則（元件 tags 空＝任何曲風）、十軸名稱與 0–1 範圍、`SongProfileResolver` 的聚合算法、fit 不平方、同一首每槽排除上次、無候選退 mono。
- 會新增（純加法）：`FXTag` 新值（如 `hardrock`、`britpop`、`psych` 等，依探針定）、`BackdropKind`／`EnterTemplate`／`ExitTemplate`／`FXEffect` 新 case 與其繪製、`FXPalette` 新值、字型。
- **亮底**（原型的 sunset／paper／flat 都是亮底；B1 全為暗底）：顆粒、暈影、殘影透明度在亮底的行為作為**跨曲風的 renderer 測試**一次定好，不做 rock 私有分支。

### 3.5 移植進 app（每批）
- `SongProfileResolver.bandTargets` 加簽字的團；`LyricsFXCatalog` 加元件；新模板與背景的繪製；字型入 `Resources/Fonts`（授權逐枚確認：OFL 直接收；授權未確認者逐枚問使用者，不沿用 B1 對三枚字型的表態）；`xcodegen generate`；About／三語 README 字型清單。
- **樂團別名（計劃評審 R1 #2，Codex 勝）**：覆寫表每列＝一個正式名＋零或多個別名（如 `Oasis` 不需要；合作名 `JAY-Z & LINKIN PARK` 這類若要歸主團就列為別名），全部經 `normalizedArtist` 後鍵唯一。不做模糊比對：沒列到的字串照舊走曲風／mono。
- **命中率閘門**：簽字前以離線腳本（放 session 暫存目錄，不進 repo；讀的是唯讀匯出的曲庫清單）列出批 1 各團在曲庫中出現過的所有樂團字串、正規化後是否命中，以及「正規化後一對多」的碰撞。批 1 各團命中率須 100%（未命中的字串補別名或明列排除理由），碰撞逐筆處理，不默默選一個。
- **簽字內容的可追溯 fixture（計劃評審 R1 #6）**：簽字時由原型匯出 `Tests/Fixtures/LyricsFX/b2-batch1-signed.json`（`Tests/Fixtures` 才是測試 bundle 的資源目錄，`project.yml:69-75`；讀取沿用 `GoldenFixtures.fixturesRoot()`）（各團十軸與 tags、每槽允許與禁止的元件 id、3 個 nonce 的預期配方）；Swift 測試直接讀它比對，防止手動轉寫漂移。檔內只有樂團名、目標值（十軸與 tags）、元件 id 與 nonce 配方，不含曲庫資料（曲數、曲名、歌詞）。

## 4. 任務清單（TDD：先紅後綠；紅燈摘要回填 §7）
| # | 任務 | DoD |
|---|---|---|
| T0 | B2-0 歸因 | 四組錄製與分桶表回填 §7；出口判定寫明（②做不做） |
| T1 | 擴表工具測試 | `ArtistOverrideTableTests`：所有團的正式名與別名正規化後鍵唯一（也防 `Dictionary(uniqueKeysWithValues:)` 啟動 trap）；別名解析到正式名同一份目標值；每團 tags 非空；軸值 ∈ [0,1]；（新）每團六槽每槽 ≥ 2 個 fit > 0 的候選（fx 槽允許 `none` 算一個）——對 B1 的 28 團先跑，結果記錄（現況若不滿足，列清單交使用者，不為了綠燈改既有團） |
| T2 | 批 1 原型設計＋探針 | 原型可在瀏覽器開；探針總覽頁；命中率報表 100%；使用者簽字（P13…）或熔斷記錄；簽字後匯出 fixture |
| T3 | 亮底 renderer | 離屏渲染（2x）每個亮底配色×每個背景，在主字**停穩時刻**取該字外框內與外框外 4 px 環帶的平均色，以 WCAG 相對亮度公式算的 **renderer 對比指標 ≥ 4.5:1**（主字；這是影像平均色的代理指標，受反鋸齒與紋理影響，不宣稱符合 WCAG；固定畫布 1280×720@2x、自編測試字串、字型、配方種子、取樣時刻與亮底配色清單）；殘影、錯位副本、顆粒、暈影是裝飾層不單獨要求，但疊上後主字仍須 ≥ 4.5:1。暗底配色同測（防亮底修正改壞暗底） |
| T4 | 新模板／背景／效果 | 每個新 case 一條定點測試（時刻→變換／透明度），沿用 B1 `ComposedStyleFrameTests` 的寫法 |
| T5 | 目錄＋字型＋覆寫表 | 目錄驗證器過；`everyCatalogFontIsRegistered`、`eachBundledFontShipsWithItsLicence` 過；T1 對批 1 各團全綠；`B2SignedFixtureTests` 讀 fixture 逐團比對目標值、允許／禁止元件與 3 個 nonce 的配方 |
| T6 | 端到端 | `ComposerTests` 加批 1 對照組斷言（如 AC/DC 抽不到英倫柔色系的指定元件、Oasis 抽不到硬搖滾指定元件——具體元件依 T2 簽字結果填）；UI 測試：預覽以 `AZW_LYRICSFX_PREVIEW_ARTIST` 指定批 1 一團 → recipe 探針為組合風格 |
| T7 | 真視窗量測 | 批 1 新字型在一般與 dense 負載的每幀 p50／p95（-O）記錄；**超出 B1 門檻（p50 2 ms／p95 3 ms）者交使用者裁定**（B1 的「維持現狀」只針對 Catacombs，不延伸到新字型），並觸發 §3.1 的②條件 |
| T8 | 文件 | ACCEPTANCE I 段增修（§6）；母計劃附錄 B；F2／F3 寫進母計劃 §2.5 註記 |

依賴：T0 → T3–T7（§3.1 閘門；不擋 T1、T2）；T1 → T5；T2 → T4、T5、T6；T3 → T4。不並行實作（排他書寫集合重疊：`LyricsFXCatalog.swift`、`ComposedStyle.swift`）。

## 5. 測試
- 單元：T1、T3、T4、T5、T6 所列；既有全量照跑（skip 同 B1 §8.4）；測試字串一律自編句子。
- E2E：T6 的 UI 測試一條；既有 `LyricsFXUITests`／`LyricsFlowUITests` 照跑（先斷開第二螢幕、切 ABC）。
- 閘門：`no_playback_gate.sh`、選擇器白名單、`coverage_gate.sh <xcresult>`、Python 測試。

## 6. ACCEPTANCE 增修（T8 落）
- 新條：樂團覆寫表的擴充規則（正規化鍵唯一、每團六槽每槽 ≥ 2 候選、未簽字＝不收）；批 1 探針簽字；亮底 renderer。
- I-08 狀態加註 F3（「ロック」判日本語系為已知錯判，另案）；I-18 補「樂團覆寫優先於曲風」已是現行為（B1 實作）。

## 7. 紅燈摘要／量測（實作時回填）
### 7.1 T0 主執行緒無回應歸因（2026-10-07；-O 量測建置，預覽 dense，每次 15 s）
| 組別 | Time Profiler 樣板（各 3 次，12 次全程最前景） | Animation Hitches 樣板（各 1 次） |
|---|---|---|
| (a) 升起層＝Cover Flow | 主執行緒 CPU 1–5 ms；hang 0 | hang 0、hitch 0（前景） |
| (b) mono | 3.57–3.71 s（24%）；hang 0。落點：Canvas 26–30%、SwiftUI／AttributeGraph 29–32%、plan 6–9% | **hang 7（70–444 ms）**、hitch 827（**非前景**） |
| (c) Catacombs 最重組合 | 4.57–5.42 s（30–36%）；hang 0。落點：Canvas 填色／組路徑 47–48%、SwiftUI 21–24%、plan 2–3% | **hang 7（55–540 ms）**、hitch 964（**非前景**）；今早同組前景也是 7（89–292 ms，B1 §8.6） |
| (d) 同 (c) 但凍結畫面 | 2–4 ms；hang 0 | 未錄 |
- 已核事實：①同一負載在 Time Profiler 樣板下 9 次（b、c）皆 0 hang，在 Animation Hitches 樣板下 3 次皆有約 7 筆；②mono（A2 的輕量畫法）與 Catacombs 最重組合在 Animation Hitches 下的 hang 筆數相同；③(a)(d)（沒有逐幀重畫）兩種樣板都是 0；④今早那份錄製的 thread-state 表顯示 hang 區間內主執行緒幾乎全程 Running，但同一份的 time-profile 取樣只有 3% 落在區間內（該樣板下取樣不可靠，故改用 Time Profiler）。
- 判讀（**推測**，推理鏈：①＋②＋③）：hang 與「有逐幀動畫在跑＋Animation Hitches 樣板的追蹤負擔」相關，與字型、組合效果無關——mono 一樣出現。未驗證的部分：(b)(c) 的 Animation Hitches 補錄不在前景；沒有在不附著任何工具時量主執行緒回應時間。
- **閘門判定**：不屬於「(c)(d) 有、(a)(b) 沒有」的特效特有情形；依協定，Time Profiler 下 (c) 三次未重現 → 結論記為「**未能在 Time Profiler 下重現；Animation Hitches 下 mono 亦出現，非字型或組合效果特有**」。T3–T7 不停手。
- ②（字形點陣快取）的出口：hang 不指向文字繪製，這個理由不成立；②只剩「新字型在一般負載超每幀門檻」這個觸發條件（T7）。Canvas 填色佔最重組合主執行緒 48% 是已核的成本落點，留作②若啟動時的基準。
- 更正 B1 §8.6：該節把 hang 列為「B2 字形點陣快取的量測對照項」，依上面結論不再成立。

### 7.2 T1 擴表工具（2026-10-07）
- 紅：`ArtistOverrideTableTests` 先寫，對不存在的 `BandEntry`／`bandTable`／`duplicateKeys`／`overrides(from:)` **編譯失敗**。
- 綠：覆寫表改成「正式名＋別名＋批次」；撞鍵改為 DEBUG 斷言、Release 先列者勝（不在啟動時 trap）。連同 `SongProfileResolverTests`／`ArtistNormalizationTests`／`ComposerTests`／`LyricsFXRecipeTests` 共 39 tests 綠。
- **B1 的 28 團現況**（第一次跑出來的事實）：19 團有候選不足 2 個的槽——其中 11 團六槽全不足（Rammstein、Chemical Brothers、Fatboy Slim、Daft Punk、Aphex Twin、Offspring、Blink-182、Green Day、Sum 41、Ramones、Sex Pistols），Korn 五槽不足；這些團的元件不在 B1 子集內（**推測**在 app 裡多半是 mono——候選是 0 還是 1 沒有逐團核）；已簽字的交響團 Nightwish、Epica 的**退場**也只有 1 個候選（同一首的退場換不了）。不回頭改，釘成「只准變少」（`theB1BandsNeverGainThinSlots`）；B2 起的團必須全空（`bandsAddedFromB2OnHaveAtLeastTwoCandidatesInEverySlot`，目前無 B2 團＝尚未實際檢驗）。

### 7.3 T2 批 1 原型草案（2026-10-07，待使用者反應）
- 原型（未追蹤的 `composer.js`／`lyrics-fx-preview.html`，已更新到同一份 artifact）：9 團目標值；新字型 9、背景 7、進場 5、退場 3、效果 3（停留小動作）、配色 14；既有 16 個元件只加新標籤。Node 檢查：原 28 團各槽候選集合變動 0；9 團每槽候選 ≥ 3；背景與配色的亮暗相容 0 違規。
- 新增的組合規則（§3.4 的「亮／暗底能力標記」落實）：背景可宣告 `needs: dark|light`，配色宣告 `light`；配色在背景之後抽，候選先濾成相容者（濾完沒有合格者才不濾）。取樣順序與亂數次數不變。
- 刻意不掛既有的 `rock` 標籤（它的元件是替龐克團做的，蜜桃色配色會落到 AC/DC）；新標籤 `hardrock`／`classicrock`／`glam`／`psych`／`britpop`／`arena`。
- **P13（2026-10-07，使用者看本機預覽）**：「AC/DC 不應該有這個西部木刻；Guns N' Roses 也不應該有西部木刻；The Killers 這個裝飾藝術圓角不太合適」。→ 規則：Rye（西部木刻）整個移除（只有這兩團會抽到）；Righteous（裝飾藝術圓角）拿掉 `arena` 標籤（連帶 Coldplay 也不再抽到；Queen、Guns N' Roses 經 `glam` 仍可能抽到）。改後字型候選：AC/DC 4、GNR 5、Killers 4、Coldplay 4。其餘 6 團尚未表態。
- **簽字（2026-10-07）**：使用者看 P13 修改後的版本：「其他的都沒問題」→ 9 團全數簽字（AC/DC、Guns N' Roses、The Killers 的字型依 P13 改；其餘維持草案）。
- **命中率閘門**：離線比對曲庫，9 團正規化後命中 1,785 首；含團名但未命中的寫法只有 Coldplay 的 3 首合作曲（`Coldplay X BTS` 等）→ 列為 Coldplay 的別名；曲庫內無「正規化後一對多」的碰撞。命中率 100%。
- **對照檔（與 §3.5 原寫法的偏離）**：`Tests/Fixtures/LyricsFX/b2-batch1-signed.json` 存 9 團的十軸、tags、別名，以及每槽 fit > 0 的候選元件 id（不含サビ／關鍵字觸發的效果）。原計劃寫的「3 個 nonce 的預期配方」不收：原型抽籤用 fit²＋mulberry32，app 用 fit＋SplitMix64（B1 定案），兩邊配方本來就不同，比不了；候選集合在兩邊的 fit 定義下相同（9 團十軸皆有值，app 的「未知軸」規則不起作用），是可比的對照。
- **移植範圍（事實）**：9 團會抽到的元件共 63 個，app 目錄已有 4 個，**要新做 59 個**：字型 12（Abril、Alfa Slab One、Anton、Archivo Black、Bebas Neue、Bungee、Special Elite、Space Grotesk、Oswald、Playfair 斜體、Righteous、Syncopate）、背景 11（ampGlow、embers、halftone、haze、paper、prism、smokeHaze、spot、stars、sunset、tapeLeak）、進場 8、退場 6、效果 7（含 `glow`、`neonstroke` 兩個要真模糊的）、配色 15。新模板：進場 stamp／pop／fallIn／slide，退場 fall／shrink／up／slideOut，停留 bob／wobble／flicker。
- 未驗證：沒有在瀏覽器裡看過畫面（只做語法檢查與抽籤統計）；9 套 Google Fonts 字型的授權未逐枚查；`glow`／`neonstroke` 在原型用 shadowBlur（真濾鏡），B1 刻意未做，進 app 前要另量。

### 7.4 T3–T6、T8（2026-10-07）
| 任務 | 紅燈 | 綠燈 |
|---|---|---|
| T4 模板 | `GlyphTemplatesB2Tests` 對不存在的 11 個模板 case **編譯失敗**；實作後既有 `holdsStaySmall` 紅在 flicker（「停留不改透明度」）→ 規格變更：燭火閃爍是使用者簽字的元件、本來就調透明度，該斷言改為「除 flicker 外 alpha＝1」，flicker 的範圍 0.6–1 由新測試把關（不是放寬，是新元件的既定行為） | 模板與組合風格 43 tests 綠 |
| T5 移植 | `B2BatchOneTests`（簽字對照、亮暗相容、新效果）對不存在的 `isLight`／`tone`／`zoom`／`glow`／`stroke`／新標籤 **編譯失敗** | 10 tests 綠：app 每槽候選與簽字對照**完全一致**（59 個元件由原型 `composer.js` 產生 Swift，不手抄）。全量時既有 `aProfileOutsideTheCatalogFallsBackToMono` 紅：它拿 `pop` 當「目錄外曲風」，批 1 移植的元件原型就掛 pop → 前提不再成立；改用字型槽確實沒有候選的 `industrial`，並加斷言釘住該前提（斷言本身「必選槽無候選＝mono」不變） |
| T3 對比 | 第一次跑：37 組不及格——①夕燒配任何暗底配色 1.2–1.9（夕燒把整面塗成淺色）②光柱配亮底配色量不到字（光柱塗滿深色）③B1 簽字的 crimsonVelvet 配任何背景 1.6–2.0 ④goldNavy＋prism 3.42（實際不會一起抽到） | 修：夕燒標「只配亮底」、光柱標「只配暗底」（原型同步，另補既有亮底配色的 light 標記）；測試範圍收斂為「同一團實際抽得到的組合」；crimsonVelvet 是 B1 已簽字的審美，釘為已知例外並另測它仍抽得到（改它要使用者重簽）。6 tests 綠 |
| T6 | 新增 `LyricsFXUITests.testASignedRockBandGetsItsComposedStyleRegardlessOfGenre`（AC/DC＋曲風 Pop → 硬搖滾群字型）；測試建置成功，**未實跑**（需使用者在場） | — |
| T8 | ACCEPTANCE I-26 字型清單、新增 I-28–I-31；三語 README 字型授權表 | — |
- 字型：11 套取自 google/fonts 官方庫（OFL 9、Apache 2.0 2），授權檔隨 app 出貨，`eachBundledFontShipsWithItsLicence` 擴到新檔；`everyCatalogFontIsRegistered` 綠（實際載入，不退回系統字）。
- 全量單元：**1169 tests／137 suites**，紅＝基線 `CoverFlowStripRenderGeometry` 7 斷言；`no_playback_gate.sh` 0；coverage Services+Infra 96.2%。
- 簽字後的行為修正（要告知使用者）：夕燒背景只配亮底配色——Blur 抽到夕燒時不再配軍綠等暗底配色。
- 未做：T7 真視窗每幀量測（新字型、光暈濾鏡、網點約 2,500 個圓點），需視窗在前景；UI 測試實跑。

### 7.5 Phase 3 評審（/simcodex，2026-10-07；R2 提前結束）
| 輪 | 來源 | 採納並修 | 駁回／延後（理由） |
|---|---|---|---|
| R1 | codex review（--base d569528） | 無正確性問題 | — |
| R1 | simplify：重用 | 對比測試改用正式的 `RGB.relativeLuminance`（加 `init(red:green:blue:)`），不再自帶一份 WCAG 公式 | 像素讀回與渲染設定和 `LyricsFXPreviewRenderTests` 重複：P2 延後 |
| R1 | simplify：簡化 | 拿掉只給測試用的 `BandEntry.batch`（改 `batchOne`／`batchTwo` 兩段）；背景合成單一 switch（刪掉永遠到不了的重複分支）；`LayerDraw.linearGradient` 併入 `axialGlow`；漸層轉換共用 `gradient(_:)` | 停留優先序改查表、`BackdropTone` 改 Bool、`zoom` 守衛：P2 延後 |
| R1 | simplify：效率 | 網點改成參數式 `.halftone`，Canvas 依畫布尺寸快取路徑（原本每幀重建約 2,500 個圓）；光暈改成整層 `drawLayer` 一次模糊（原本每個透明度 run 各一次）；對比測試的可達組合改 `static let` | 對比測試降解析度、倒影改畫一次翻轉路徑：P2 延後（待 T7 實測再定） |
| R1 | simplify：深度 | 「目錄外曲風退 mono」測試改為拿掉整個字型槽（不再依賴「哪個曲風剛好還沒有字型」）；緋紅例外加 1.5 地板（不是全豁免）；`BackdropKind.tone` 改窮舉、亮暗規則集中到 `BackdropTone.accepts` | `overrides(from:)` 回傳撞鍵清單以測 Release 路徑、停留優先序的組合測試：P2 延後 |
| R2 | simplify（四角度合併，只看 R1 修正） | 無 P0／P1 | 3 條 P2 延後（網點生成可併入快取、`RGB` 初始化可移到 extension、crimsonFog 仍手寫光暈） |
| R2 | codex review（--uncommitted） | 無 | — |
- 無安全敏感改動（無認證、無網路、無新的檔案寫入路徑；字型是一次性下載進 repo），未派 security-reviewer。
- 評審後全量：**1169 tests／137 suites**，紅＝基線 7 斷言。

### 7.6 使用者在場（2026-10-07 傍晚；只接內建螢幕、ABC 輸入法）
- **UI 測試**：`LyricsFXUITests`（8，含新增的 AC/DC 一條）＋`LyricsFlowUITests`（9）**17／17 綠**，同一輪、一次過（217 s）。前一次嘗試在 Automation Mode 授權框逾時中止（0 個 Test Case，不計）。
- **T7 每幀**（-O 量測建置、真視窗在前景、dense 預覽、主執行緒 plan＋Canvas 編碼；各 4–5 個 5 秒窗）：
  | 組合（指定配方） | p50 | p95 | 判定（2 ms／3 ms） |
  |---|---|---|---|
  | AC/DC：Alfa Slab＋舞台暖光＋蓋章＋墜落＋整屏縮放＋微晃 | 0.37–0.61 ms | 0.71–1.04 ms | 過 |
  | Queen：Abril＋聚光燈＋斜出＋光暈＋霓虹描邊 | 0.44–0.80 ms | 0.99–1.50 ms | 過 |
  | The Beatles：Bungee＋網點＋輕跳＋擺動＋亮黃 | 0.37–0.65 ms | 0.65–1.20 ms | 過 |
  | Pink Floyd：Syncopate＋稜鏡＋綻開＋倒影（119 份）＋呼吸 | 0.52–0.92 ms | 1.04–1.65 ms | 過 |
  | Coldplay：Playfair 斜體＋星空＋光暈＋呼吸 | 0.79–1.02 ms | 1.44–1.58 ms | 過 |
  | Oasis：Archivo＋類比漏光＋側滑＋微晃＋軍綠 | 0.45–0.80 ms | 0.81–1.19 ms | 過 |
  - 新字型都比 Catacombs 輕，②（字形點陣快取）的觸發條件未成立，B2 批 1 不做②。
  - 未量：光暈與描邊的模糊發生在 render server，不在這個數字內（整幀未量）。
- 真視窗預覽：依序開 AC/DC、Queen、Pink Floyd、Blur 各約 20 秒（組合器自抽）。使用者：「沒問題，收尾吧」。

## 8. 影響面、風險、回退
- 改檔：`SongProfileResolver.swift`（表）、`Composer/LyricsFXCatalog.swift`、`Composer/FXComponent.swift`（新 case）、`ComposedStyle.swift`、`GlyphTemplates.swift`、`Resources/Fonts/*`、`project.yml`（若字型路徑變）、About、三語 README、ACCEPTANCE、測試。**不改** Music 讀取、`NowPlayingMonitor`、`GenreStyleResolver`、Cover Flow。
- 風險：R1 把樂團審美硬翻成十個數字而元件不足（R4 Codex 最擔心）→ 每團六槽每槽 ≥ 2 候選是硬 DoD，元件先於數字；R2 探針不收斂 → 三輪熔斷；R3 新字型授權 → 逐枚問；R4 亮底讓既有暗底效果走樣 → T3 跨曲風測試；R5 隱私 → 曲庫清單只在暫存目錄，計劃與 repo 只放樂團名與總數，不放每團曲數。
- 回退：未簽字＝不進表；整批在 `wip/lyrics-fx-b2`，未併 main；checkpoint 只在本機 wip 分支。

## 9. 待拍板（2026-10-07 使用者兩項皆「確認」：批 1 照草案 9 團；樂團名可進 repo、不放每團曲數）
1. 批 1 的團（§3.2 草案 9 團）要不要換。
2. 計劃與程式裡列出曲庫中的樂團名（覆寫表本來就是樂團名）可否進 repo——我的預設是可以，但不放每團曲數。

## 附錄 A　B2 順序辯論（/thecure，gpt-5.6-terra／medium，2026-10-07）
| # | 論點 | 提出方 | 狀態 | 證據 |
|---|---|---|---|---|
| R1-1 | 字形點陣快取先做 | 我 | **Codex 勝**：收益未驗證、使用者感覺不到，覆蓋率價值更高；降為條件式 spike | B1 §8.2:277-280 |
| R1-2 | 換繪製路徑會讓已簽探針全部失效 | 我 | Codex 勝：可只對特定 face 啟用 | `TextMeasuring.swift:137-157`、`LyricsFXView.swift:39-77` |
| R1-3 | hitch 多為晚一個 vsync＝字形慢 | 我（B1 §8.6 推測） | Codex 勝：60 fps 上限是設計 | `LyricsFXView.swift:153-154` |
| R2-1 | ①前先補 trigger schema | Codex | 我勝：B1 才刪該死碼；目錄是程式常數、存檔只存 id | B1 計劃:300、`RecipeHistory.swift:11-25` |
| R2-2 | jrock 第一 | Codex | 我勝（R2）；R4 前提整個被曲庫統計推翻 | F2 |
| R2-3 | 「批 1 純移植」會漏 profile rows | Codex | Codex 勝 → 每批 DoD 含目標值與候選覆蓋 | `SongProfileResolver.swift:42-51` |
| R3-1 | rock／indie 是純移植 | 我（R2） | 我自己推翻：元件與目標值都不足 | F7 |
| R3-2 | generic「Metal」併入金屬批 | 我 | Codex 勝：未簽字前不計入 | — |
| R3-3 | 原型與 Swift 並行需凍結契約 | Codex | 採納 → §3.4 | — |
| R4-1 | 主軸改為按樂團分批 | 我 | 一致 | F4、F5、F6 |
| R4-2 | 「依代表團起草」仍叫不另行手填 | 我 | Codex 勝：是人工策展，原則改為「系統起草、每團使用者簽字」 | — |
| R4-3 | 50 團一次審 | 我 | Codex 勝：改 8–12 團一批、按視覺語言聚類 | — |
| R4-4 | B3 撤銷、ロック誤判另案 | 我 | 一致；Codex 補：B1 組合器不受影響（已核） | F3 |
- Codex 最擔心：在元件不足時把樂團審美硬翻成十個數字（→ §8 R1 的硬 DoD）。

### A.1 計劃評審 R1（gpt-5.6-terra／medium，2026-10-07；無 P0，引用全數核對相符）
| # | 嚴重度 | 論點 | 狀態 | 處置 |
|---|---|---|---|---|
| 1 | P1 | B2-0 只歸因不阻塞，可能在已知卡頓上擴大繪製複雜度 | Codex 勝（部分） | §3.1 加閘門：特效特有 hang → T3、T4 停手交使用者；原型與探針（不動 app 繪製）照常；T7 新字型超門檻交使用者，不沿用 Catacombs 的裁定 |
| 2 | P1 | 只有精確鍵比對，合作名／別名會讓簽字團的歌退回 mono | Codex 勝（部分） | 覆寫表加別名；命中率 100% 閘門。命中率檢查放離線腳本而非 repo 測試：曲庫清單不進 repo，且 app 宿主測試開不了 `~/Documents` |
| 3 | P2 | 「每槽排除上次」與 fx2 不入歷史不一致 | Codex 勝（措辭） | 完成標準明定六槽＝含第一效果、不含第二效果；不改 B1 行為 |
| 4 | P2 | 歸因協定無次數、無「沒錄到」的處置 | Codex 勝 | 每組 3 次；以 potential-hangs 表為準；沒錄到＝「未能重現」 |
| 5 | P2 | 亮底對比門檻太晚定、無量測定義 | Codex 勝 | T3 現在定：主字 WCAG ≥ 4.5:1、取樣時刻與區域、裝飾層規則、暗底同測 |
| 6 | P2 | 簽的原型與移植結果無可追溯對照 | Codex 勝 | 簽字時匯出 fixture，Swift 測試直接讀 |

### A.2 計劃評審 R2（2026-10-07）
- R1 #1、#2 的部分採納：Codex 明言接受。
| # | 嚴重度 | 論點 | 狀態 | 處置 |
|---|---|---|---|---|
| 1 | P1 | 閘門只擋 T3／T4，T5 的新字型與目錄仍會加重繪製 | Codex 勝 | 特效特有 hang → T3–T7 全停，T1、T2 照常 |
| 2 | P2 | fixture 路徑不在測試 bundle 資源內 | Codex 勝（已核 `project.yml:69-75`、`GoldenFixtures.swift:27-39`） | 改 `Tests/Fixtures/LyricsFX/` |
| 3 | P2 | fixture 欄位前後矛盾 | Codex 勝 | 統一為樂團名＋目標值＋元件 id＋配方 |
| 4 | — | 對比是代理指標，不能稱 WCAG | Codex 勝 | 改稱 renderer 對比指標，固定量測條件 |
- 投入順序：Codex 認為妥當。最容易失敗的一步：T2——三輪內讓九團各有辨識度，同時每槽維持 ≥ 2 個候選（已是 §8 R1）。
