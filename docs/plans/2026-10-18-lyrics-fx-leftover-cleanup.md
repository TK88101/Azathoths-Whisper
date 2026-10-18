# Lyrics FX — 遺留收尾（Cenobyte 字距、全螢幕缺口 5 條 P2、批 4 遺留 5 條 P2）

基線：`main` 284e2d1。分支（實作時開）：`wip/lyrics-fx-leftover-cleanup`。上游：批 4 遺留計劃 `docs/plans/2026-10-17-lyrics-fx-batch4-leftovers.md` §1 F4、§3、§9.4；全螢幕缺口計劃 `docs/plans/2026-10-17-lyrics-fx-raster-fullscreen-gap.md` §9.7；ACCEPTANCE I-45、I-46、I-47。
使用者 2026-10-18 口令（摘要）：三項依序做——①Cenobyte 字距；②全螢幕缺口 §9.7 的 5 條 P2；③批 4 遺留 §9.4 的 P2。約束：I-46 門檻不放寬；Rock Salt 主執行緒 V2 目前 0.843（門檻 0.85），任何改動點陣路徑的項目都要重量 V2（xctrace 包 `perl alarm 60`）；Anton 維持向量、不重提。先計劃、定稿後實作；不碰 Music 播放；跑像素比對前先提醒；commit／合 main／push 等使用者拍板。

## 0. 複述
目標＝①讓 Cenobyte 的字距照原型（每字多留 0.2 em，app 現在是共用的 0.08 em）；②③把兩份計劃評審時延後的 10 條 P2 收掉，其中只有 ②c（零寬字元每幀重建點陣）是行為修正，其餘是**行為等價**的重構或小效能改善。
完成標準＝§4 驗收全過；②③不改任何畫面（V3 每張候選影像的原始像素雜湊與改前相同），V2 仍 ≤ 0.85。
不做＝放寬任何門檻、Anton 走點陣、其他字型的字距或字級、改點陣尺寸策略本身（分檔區間、16 MB、LRU 策略）。

## 1. 事實與推測
### 1.1 已核事實（出處）
- F1 原型字距：`composer.js:331` 組合風格預設 `spacing: 0.08`；`composer.js:401` `if(F.id==='Cenobyte')S.spacing=0.2`。用法 `lyrics-fx-preview.html:292,315`：每字寬＝`measureText + style.spacing × em`（em＝該句 em，不乘逐字的 size）。
- F2 app 字距：`ComposedStyle.spacing = 0.08`（`ComposedStyle.swift:57`），兩處使用——折行時每字寬 `+ spacing × em`（`:388`），畫字時以 `advance = glyph.width − spacing × em` 把字置中（`:236`）。兩處必須用同一個值，否則字會偏離格子中心。`FontFace` 沒有字距欄位（`LyricsFXFrame.swift:14-28`）。
- F3 Cenobyte 影響面：`band-candidates-baseline.json` 54 團中，Cenobyte 在 7 團可抽到（Mayhem、Immortal、Darkthrone、Burzum、Emperor、Dimmu Borgir、Type O Negative），Cradle of Filth 合格但不在可抽清單。批 4 遺留的 126 組縮字基線（`B2BatchFourLeftoverTests.baseline`）只含 Marker、ShadowsLight、Bebas、Catacombs、CourierPrime、IMFell、RockSalt，**沒有 Cenobyte** → 基線不受影響。V3 點陣比對的 12 份配方也沒有 Cenobyte。
- F4 zoom 傳遞：`stamp` 以 `context.environment.displayScale × zoom` 算檔位（`LyricsFXView.swift:136-141`），`zoom` 由 `draw` 一路當參數傳進 `fill`／`stamp`（`:89,95,98`）。光暈層 `shaken.drawLayer { lit in … }`、半透明多字 `layer.drawLayer { group in … }` 都在 zoom 之後開新圖層——**新圖層的 `GraphicsContext.transform` 是否保留外層縮放、是否含 displayScale，未實測**（全螢幕缺口 §9.7 延後的原因）。
- F5 `.rasterIgnoringOptOut` 只被 `GlyphRasterFidelityTests.theRasterDrawingHoldsAtTheRealFullScreenSize` 用（`GlyphRasterFidelityTests.swift:224-225`）；正式碼只在 `fill` 的策略判斷讀它（`LyricsFXView.swift:113`）。`FontFace.rasterizes` 是 `var`。
- F6 空外框：`GlyphRasterCache.rasterize` 對 `boundingBoxOfPath.isNull` 回 nil（`GlyphRasterCache.swift:111-112`），與 `CGContext`／`makeImage` 失敗同一個 nil；`entry` 在建圖前已 `misses += 1`、nil 不進快取（`:83-84`）→ 空外框的字**每幀都重試、每幀加一次 miss**。排版只濾掉 `isWhitespace` 的字（`ComposedStyle.swift:383`）。
- F7 逐出：每次超限 `store.filter{…}.sorted{…}` 全表排序，再逐出到放得下（`GlyphRasterCache.swift:95-102`）。16 MB 滿載時每次 miss 都會走一次。
- F8 雜湊：每字 `paths.entry(for:)` 先以 `(text, face, size)` 查外框（`TextMeasuring.swift:136-139`，另有 `scalesLinearly` 以 face 查一次），`rasters.entry` 再以 `(text, face, size, tier)` 查點陣（`GlyphRasterCache.swift:78`）。`FontFace` 的雜湊含 `id`、`family` 兩個字串。
- F9 描邊旗標：`shifted` 複製 stroke（`ComposedStyle.swift:588-593`），殘影層靠 `runs(of:stroking: false)` 遮掉（`LyricsFXView.swift:46-51,89`）；`stroking:` 另有兩處呼叫（`LyricsFXFrameMeter.swift:70`、`GlyphRasterFidelityTests.swift:206`）。主字形經 `shifted` 進 `frame.glyphs` 的只有 negative、ransom 兩處（`ComposedStyle.swift:340,348`）。
- F10 run 鍵：`Run` 鍵＝(色槽, 量化透明度, stroke)；策略以 `members.allSatisfy(\.face.rasterizes)` 每 run 掃一次（`LyricsFXView.swift:113`）。同一配方只有一種字型，實際不會混字型。
- F11 斷詞決策：`FitCache.Result(ratio, breaksLongWords)`（`ComposedStyle.swift:627-633`）；`layout(…, breakLongWords: true)` 只斷「詞寬 > 折行寬」的詞（`:396`），沒有這種詞時與 `false` 的結果逐欄相同；`search` 只在下限（`baseEm × minimumFitRatio`）才可能斷詞（`:461-472`）。
- F12 折行寬：`size.width * maxWidthRatio` 在正式碼兩處（`fitted` `:444`、`rowsFitWidth` `:488`），測試一處（`B2BatchFourLeftoverTests.maxWidth`）。
- F13 測試重複：`B2BatchFourLeftoverTests.inkSpanX` 與 `B2BatchFourT7FixTests.inkSpan` 同一迴圈只取不同軸；`guard case .font(let x)? = LyricsFXCatalog.component(id)?.payload` 至少 4 處；`B2BatchFourT7FixTests.swift:113` 以 `if font != "Anton"` 寫死例外。
- F14 V2 量法（全螢幕缺口 T6，腳本留在該 session scratchpad `t6-measure.sh`）：同一個 -O 二進位、`AZW_LYRICSFX_VECTOR_REFERENCE=0／1` 切點陣／向量基線；Rock Salt、Catacombs × 3 輪（ABBA／BAAB／ABBA）；啟動後等 8 s，`xctrace record --time-limit 15s` 包 `perl alarm 60`；每 0.25 s 核前景，失焦作廢；判定＝3 輪平均（點陣主執行緒樣本 ÷ 向量）≤ 0.85。上次：Rock Salt 0.843（第 2 輪單輪 0.864）、Catacombs 0.775。

### 1.2 推測（待驗證）
- P1（②a）：`GraphicsContext.transform` 是「目前座標到圖層根」的仿射、不含 displayScale，`drawLayer` 的子 context 繼承外層 transform。推理鏈：SwiftUI 文件把 `transform` 描述為 current transform matrix，`drawLayer` 的子 context 文件說「新圖層的座標系與父相同」。**未實測，T4 先驗；離屏（ImageRenderer）與上螢幕（Canvas）可能不同。**
- P2（②c）：零寬空白 U+200B 不是 `isWhitespace`（Unicode White_Space 不含它），經 CTLine 排版後外框為空 → 實際可達 F6 的每幀重試。T6 的紅燈測試先驗。
- P3（V2）：②d、②e 只減主執行緒工作，V2 應持平或略降；但 0.843 對 0.85 的餘裕（0.007）小於上次單輪波動（0.843 平均 vs 0.864 單輪），**量測雜訊本身就可能翻盤**，見 §4 V2 的預先登記判讀規則。

## 2. 設計
### 2.1 ① Cenobyte 字距
- `FontFace` 加 `var spacing: CGFloat = ComposedStyle.spacing`（文件註解指 `composer.js:331,401`）；目錄 Cenobyte 設 `spacing: 0.2`。
- `ComposedStyle` 兩處 `spacing * em`（折行 `:388`、置中 `:236`）改讀 `style.face.spacing`（排版函式本來就收 `face`）。`ComposedStyle.spacing` 保留為預設值。
- `FitCache.Key` 已含 `face`（`FontFace` 的雜湊自動含新欄位），不必改鍵。
- 預期效果：Cenobyte 每列變寬 → 更常折行；I-45 縮字可能更常觸發（同 Anton 前例）。
- 真實字型案例（R1 #10）：Cenobyte 一句長句在 1728×945 與 900×945 下的 plan——每列排版寬 ≤ 折行寬、每個主字 origin 依 `width − 0.2 em` 置中、縮字後主字墨跡在安全區內、大寫顯示正確。
- ACCEPTANCE 新增 I-48 ⚠️（改變 7 團已簽字的 app 畫面、往原型靠；附使用者口令與日期）。

### 2.2 ② 全螢幕缺口 5 條 P2（全部動到點陣路徑）
- **②a zoom 改由 context 推**（有放棄條件）：
  1. 先做探針（T4，不進 main）：離屏與上螢幕各一，在 `stamp` 記錄 `context.transform` 與 `displayScale`，涵蓋「無 zoom」「zoom 1.04（thump）」「光暈 drawLayer 內」「半透明多字 drawLayer 內」四種位置。上螢幕用 DEBUG 預覽（`AZW_UITEST_SCENARIO=lyricsFX`，不經 Music），只開 thump＋glow 配方。
  2. **採用條件**（R1 #3 修訂）：在每個實際呼叫 `stamp` 的位置——rasterDirect、rasterGrouped（drawLayer 內）、光暈層（drawLayer 內）、zoom 有／無、離屏 1×／2×、上螢幕 Canvas——記錄完整 `transform`（a、b、c、d、tx、ty）與 displayScale；條件＝`hypot(a,b)` 與 `hypot(c,d)` 都等於外層 zoom（或恆為 zoom × displayScale）、`a·c + b·d == 0`（無 shear）、旋轉為 0，且兩環境一致。滿足 → `stamp` 以推得的值算 deviceScale，刪掉 `zoom` 參數鏈，**並留一條離屏 contract test**：各呼叫位置推得的 deviceScale 與 `displayScale × plan.zoom` 相同（R1 #4）。
  3. **放棄條件**：任一位置不一致、或兩環境不同 → 不改，把探針數據記進 §9 與 `stamp` 註解（說明為何保留參數），本項結案為「實測後不採用」。
- **②b 刪 `.rasterIgnoringOptOut`**：測試改以改寫 plan 的方式強制點陣——Fidelity 測試的 `image(...)` 加一個 `forceRaster: Bool` 參數，在 Canvas 閉包裡把 `plan.glyphs`／`plan.ghosts` 每個字的 `face.rasterizes` 設 true 後再畫（`GlyphDraw` 的 face 若是 `let` 就以新值重建）。改 face 用結構體複製（`var face = glyph.face; face.rasterizes = true`，不逐欄抄 `FontFace`）；`GlyphDraw` 以 init 重建後，測試輔助自帶斷言「把 rasterizes 改回原值後與原字 `==`」，防止日後 `GlyphDraw` 加欄位時漏抄（R1 #9 駁回後的防線）。正式 enum 只剩 `.raster`、`.vectorReference`。等價性：全螢幕 12 份每張候選影像的像素雜湊與改前相同。
- **②c 空外框分開處理**（行為修正）：`GlyphPathCache.Entry` 加 `isEmpty`（建 entry 時已算 `boundingBoxOfPath`，零成本）；`stamp` 遇空外框直接跳過、不查點陣快取；`rasterize` 的 nil 只剩「配置失敗」一種語義（文件註解改寫；空外框的 guard 保留為防線但不再是正常路徑）。效果：零寬字元不再每幀重試、不再灌 `misses`。畫面不變（空外框本來就畫不出東西）。
- **②d 逐出改最小值掃描**（R1 #6 修訂）：每需要逐出一張，就在「本幀沒用過」的項目裡線性找 (`lastUsedFrame`, 建立序號) 最小者移除，直到放得下或沒有可逐出的；不再全表過濾＋排序。複雜度 O(k·n)（k＝這次要逐出的張數；16 MB 滿載時一張新點陣通常只擠掉 1–3 張），不建 heap。`Slot` 加建立序號當並列的決勝鍵——現行 `sorted` 並列時順序未定義，改後變成確定的「同幀先建的先出」，這是**刻意的小行為變更**（可重現性變好），以單元測試固定。不改 16 MB、不加水位線。
- **②e 外框與點陣共用一次雜湊**（R1 #2 修訂：原「單調 id」方案會在外框快取清空後讓全部點陣變孤兒、重建，不是等價重構，撤回）：`GlyphPathCache.Entry` 帶一個語義鍵 `GlyphKey(text, face, size)`：`init` 以新的 `Hasher` 依序 combine text、face、size 後 finalize 存成 `cachedHash`（不可用 `hashValue`，會遞迴呼叫改寫後的 `hash(into:)`；R2 N1），`hash(into:)` 只 combine `cachedHash`、`==` 照舊逐欄比；`cachedHash` 只在同一行程有效、不得序列化（Swift 雜湊每行程隨機化）。外框快取的鍵也改用它，兩邊同一個定義；點陣鍵改為 `(GlyphKey, tier)`，`rasters.entry` 改收 `(path:, tier:)`。語義鍵不變 → 外框快取清空後同字同檔仍命中原點陣（與現狀相同）。字串只在外框查表時雜湊一次。新增測試：兩個獨立建出的相等 `GlyphKey` 互相命中字典、任一欄位不同即不相等；外框快取容量改為可注入（`init(capacity:)`，預設 4000），填滿→清空→同字同檔仍命中點陣（`misses` 不增）。
- 每一小項各自一個 wip checkpoint，方便 V2 不達標時逐項二分。

### 2.3 ③ 批 4 遺留 5 條 P2
- **③a `shifted(stroke:)` 預設 0**：`shifted(dx:dy:opacity:color:stroke: CGFloat = 0)`；negative、ransom 兩處主字明確傳 `stroke: base.stroke`；殘影天生不描邊。`runs(of:stroking:)` 的 `stroking` 參數刪除（一律讀 glyph.stroke），三處呼叫端跟著改。等價性：主字的 stroke 與現狀相同；殘影的 stroke 由「帶著但不畫」變成 0，畫面相同——以 V3 像素雜湊把關，並新增 neonstroke＋misreg／reflect／weep／rgbsplit 四份只比新舊雜湊的案例（R1 #8）。
- **③b `rasterizes` 進 Run 鍵**：`Run` 加 `rasterizes: Bool`，`runs(of:)` 遇到 `face.rasterizes` 不同就切段；`fill` 的策略改讀 `run.rasterizes`，不再每 run 掃 members。實際配方只有一種字型 → run 切法不變（V3 逐位元組相同把關）；混字型時從「整 run 改走外框」變成「各自走各自的畫法」，painter order 不變（相鄰切段）。
- **③c `breaksLongWords` 不進快取**：依 F11，「在下限以 `breakLongWords: true` 排版」與現行決策逐欄相同（沒有超寬詞時兩者相同；有超寬詞且在下限時現行也會斷）。改為：`LineLayout` 加 `brokeWords: Bool`（實際斷了詞才 true）；`search` 的下限直接 `lay(low, true)`；快取只存比例，命中時以 `layout(em, breakLongWords: em <= 下限)` 重排，斷沒斷由排版結果 `laid.brokeWords` 決定（不由比例宣稱）；`Fitted.breaksLongWords`、`FitReport`、`FitLog` 都讀 `laid.brokeWords`。把關：126 組基線＋① 斷詞測試＋新增冷／命中成對測試（R1 #5）：同一句先冷算再命中，比較 em、rowWidths、每字 (text, wordIndex, row)、brokeWords 全相同；案例含無超寬詞、下限仍上下溢出、超寬詞、Unicode grapheme（emoji ZWJ、組合音標）。改前在 284e2d1 先記下這些案例的完整 FitReport 當基線。
- **③d 折行寬單一化**：`static func wrapWidth(_ size: CGSize) -> CGFloat`，正式碼兩處與測試一處改呼叫它。
- **③e 測試輔助去重**（不放寬任何斷言）：`inkSpan`／`inkSpanX` 合成一個回傳 `CGRect` 的 `inkBox(_:)`（放在 `B2BatchFourT7FixTests`，兩檔共用，不新增檔案、免跑 xcodegen）；`fontFace(_ id:)` 測試輔助取代 4 處 `guard case`；兩條描邊測試（`aShrunkLineStrokesWithItsShrunkEm`、`aShrunkAntonNeonLineStrokesWithTheShrunkEm`）參數化成一條；`if font != "Anton"` 改為「該字型 `sizeScale == 1` 才斷言不縮」（由目錄資料推導）。改前後測試名單與斷言數對照記進 §9。

## 3. 非目標
- 不改 Anton（維持 `rasterizes = false`、sizeScale 1.25），不重提 Anton 走點陣。
- 不改其他字型的字距、字級；不改 I-45 縮字政策、I-46 門檻與點陣尺寸策略（分檔 [1.6,1.87)、LRU、16 MB）。
- 不改 Python 1.x、不碰 Music。

## 4. 驗收標準
- **V1 單元（TDD）**：
  - ① Cenobyte：每字排版寬＝量測 advance＋0.2 em（逐字斷言）；畫出的主字形 origin 以 `advance = width − 0.2 em` 置中（與格子中心差 < 1e-9）；其他字型 `spacing == 0.08`；126 組縮字基線逐位元相同；§2.1 的真實 Cenobyte 長句案例。
  - ②c：含 U+200B 的句子連畫 N 幀，`rasters.misses` 不隨幀數增加（現狀會＋N → 紅）；外框為空的 entry `isEmpty == true`。
  - ②d：逐出順序單元測試（最舊先出、只逐到放得下、本幀用過的不逐出）沿用既有 `GlyphRasterCacheTests` 全綠，另加「需逐出多張時逐出的正是最舊的 k 張」。
  - ②e：外框快取（注入小容量）填滿→清空→同字同檔再畫，`rasters.misses` 不增；不同字、不同 face、不同 size 的鍵不相等（`==` 逐欄比）。
  - ②d：同幀並列時先建的先出（建立序號決勝）。
  - ②a（若採用）：離屏 contract test，各 stamp 位置推得的 deviceScale ＝ displayScale × plan.zoom。
  - ③a：neonstroke＋misreg／reflect／weep／rgbsplit 配方 plan 的 `ghosts.allSatisfy { $0.stroke == 0 }`、主字 stroke 與改前相同；`shifted` 預設 0、明傳時保留。
  - ③b：`runs(of:)` 遇 rasterizes 不同的相鄰字切段；同字型時切法與改前相同。
  - ③c：既有 ① 斷詞測試、126 組基線全綠；冷／命中成對測試與 284e2d1 記下的完整 FitReport 基線逐欄相同。
  - ③e：測試名單與斷言數對照表，無刪減語義。
- **V2 全量回歸**：全量單元綠（skip `AzathothsWhisperTests/BatchOverlappingLoadTests/overlappingLoadSuspendsPollingUntilLastCompletes()` 完整名稱帶括號）；`no_playback_gate.sh` 0；`coverage_gate.sh <單元 xcresult>` ≥ 80%；Scripts Python OK。
- **V3 畫面等價（像素比對，跑前提醒使用者）**（R1 #1 修訂）：統計報告不是等價證據。T0 先在測試端加「每張候選影像（配方 × 時刻 × 倍率）原始 RGBA 位元組的 SHA-256」輸出（只改測試、不改正式碼，所以 wip 起點的正式碼＝284e2d1），再跑一次存基線；另加 neonstroke＋misreg／reflect／weep／rgbsplit 四份只輸出雜湊、不判門檻的案例。②、③ 各做完後再跑：**每張雜湊相同**（②a 若採用、②b、②c、②d、②e、③a、③b 都必須如此；①只改 Cenobyte，不在集合內）。不同 → 停下鑑別，不放寬。統計報告照舊產出、門檻照舊判。
- **V4 效能（-O，全程前景）**：
  - 主執行緒 V2（I-46 口徑，F14 同法；R1 #7 修訂為**每次都配對**）：②做完量一次、③做完量一次；每次同一時段跑兩個 -O 二進位（新＝wip、對照＝284e2d1），每個二進位內各自以點陣／向量基線 ABBA／BAAB／ABBA 交錯 3 輪，新與對照兩二進位也逐輪交錯。
  - 統計量（預先定義）：每輪比值＝該輪點陣臂主執行緒樣本數 ÷ 同輪向量臂樣本數；某二進位的 V2＝3 輪比值的算術平均。
  - 逐輪排程（R2 N2，預先登記）：第 i 輪依序 對照-i → 新-i → 新-i → 對照-i（每個二進位的兩次各是一個臂，臂序依上列 ABBA／BAAB／ABBA），保存每輪 `base_i`、`new_i` 與 `Δi = new_i − base_i`。容差 0.02 是工程取值（上次觀測單輪與平均差 0.864 − 0.843 = 0.021，取略嚴的 0.02），不是觀測值本身。
  - 判定分三類：**達標**＝新版 V2 ≤ 0.85 且 平均 Δ ≤ 0.02；**不可判定（環境漂移）**＝對照 V2 > 0.85（不論新版），照實記錄交使用者裁定，不二分、不宣稱達標；**改動退化**＝對照 ≤ 0.85 而（新版 > 0.85 或 平均 Δ > 0.02）→ 依 checkpoint 逐項二分（每項配對 1 輪初篩，可疑項補滿 3 輪）找出元兇，撤回或改寫。不重跑挑好的那次。
  - 冷首幀（`GlyphRasterColdFrameTests`，-O＋`AZW_PERF=1`）：②做完後，900×560 級與全螢幕都 ≤ 8.3 ms（現 ≤ 4.23／5.15）。
  - 每幀 V1：③做完後 7 份一般字全螢幕＋1 份 Cenobyte（Mayhem 可抽到的最重組合，從簽字對照檔取）p50 ≤ 2、p95 ≤ 3 ms。
- **V5 使用者在場**：UI 測試 `LyricsFXUITests`＋`LyricsFlowUITests` 20 條（跑前確認輸入法 ABC）；全螢幕新舊並排目視 Cenobyte 1–2 團（舊＝main 284e2d1 -O、新＝wip -O，各 25 秒、前景）。②③畫面等價（V3 逐位元組相同）→ 不另做目視。

## 5. 任務清單（串行；每項帶 DoD）
- T0 開 `wip/lyrics-fx-leftover-cleanup`；測試端加像素雜湊輸出與 4 份 neonstroke 組合案例、③c 的完整 FitReport 基線記錄（只改測試）；**提醒使用者後**跑 Fidelity 存基線；建 284e2d1 的 -O 對照二進位（放 `mktemp -d`）。DoD：雜湊清單與報告複製到本 session scratchpad `fid-base/`，清單檔頭寫入 `git rev-parse HEAD`、`git diff 284e2d1 --stat`（只允許 `Tests/` 下的檔案）、測試檔 sha256、renderer scale（R2 N3）；FitReport 基線寫進測試；checkpoint。
- T1 ① 測試紅 → 實作綠。DoD：新測試綠、`B2BatchFourLeftoverTests`／`LongLineFitTests` 全綠、紅燈摘要記 §9；checkpoint。
- T2 ACCEPTANCE I-48 ⚠️（狀態「待使用者在場」）。DoD：條目寫好。
- T3 ②b、②c、②d、②e 依序（每項先紅或先寫等價測試 → 實作 → 相關 suites 綠 → checkpoint）。DoD：各項測試綠。
- T4 ②a 探針 → 依 §2.2 的條件採用或放棄。DoD：探針數據與決定記 §9；採用則相關 suites 綠＋checkpoint；探針程式碼不留。
- T5 ② 收尾：**提醒使用者後**跑 V3 比對、冷首幀、V2（②）。DoD：V3 報告逐位元組相同、冷首幀達標、V2 依 §4 判讀；數據記 §9。
- T6 ③a–③e 依序（同 T3）。DoD：各項測試綠、checkpoint。
- T7 ③ 收尾：**提醒使用者後**跑 V3 比對、V2（③）、每幀 V1 8 份。DoD：同 T5。
- T8 /simcodex。DoD：評審紀錄記 §9。
- T9 全量回歸（§4 V2）。DoD：全部綠，數據記 §9。
- T10 使用者在場（§4 V5）→ I-48 改 ✅。DoD：結果記 §9、ACCEPTANCE 更新。
- 收官：證據包；commit 整理／合 main／push 等使用者拍板。

## 6. 測試策略
- 單元：純函式（`layout` 字寬、`runs(of:)`、`GlyphRasterCache` 逐出與鍵）、`plan()` 輸出（stroke、origin）。
- 整合：真實 `CoreTextMeasurer`＋字型＋`GlyphPathCache`／`GlyphRasterCache`；Fidelity 離屏像素比對（等價性的主證據）。
- E2E：UI 測試 20 條＋真視窗目視（使用者在場）。
- 行為等價的重構沒有天然紅燈：以「改前存的 V3 報告逐位元組相同」＋既有單元測試當特徵測試，照實記錄「該項無紅燈」，不偽造紅燈。測試字串一律自編。

## 7. 影響面、風險、回退
- 影響面：① 只影響 Cenobyte 的版面（7 團可抽）；②③ 影響所有走點陣的配方的繪製路徑（預期畫面不變）。
- 風險：R1 V2 餘裕小、雜訊可能翻盤（§4 配對量測與預先登記判讀）；R2 ②a 的 transform 語義在兩環境不同（放棄條件；採用也要留 contract test）；R3 ②d 並列決勝改成確定順序，命中率理論上可能有極小差異（V3 雜湊與 V2 把關）；R4 ①使 Cenobyte 長句更常縮字（預期，V5 目視）。
- 回退：每小項一個 checkpoint，可單獨 revert；未經使用者拍板不合 main。

## 8. 使用者在場／提醒
- 像素比對（T0、T5、T7、T9）：跑前提醒（測試視窗會轉彩虹球、約數分鐘）。
- V2／每幀量測（T5、T7）：會開預覽視窗佔住前景數分鐘，跑前提醒、期間請勿切換視窗。
- T4 上螢幕探針：開 DEBUG 預覽視窗約 1 分鐘，跑前提醒。
- T10：UI 測試授權（Automation Mode、輔助使用）、輸入法 ABC、Cenobyte 目視。

## 9. 紀錄（實作時回填）
### 9.0 T0 基線（2026-10-18）
- 測試端加每張影像 RGBA 的 SHA-256 輸出（`GlyphRasterFidelityTests.digest`／`writeHashes`）、4 份 neonstroke＋殘影組合（只記雜湊）、③c 7 案完整 FitReport 雜湊基線（`B2BatchFourLeftoverTests.fitBaseline`；冷算與命中兩次一致）。正式碼未動。
- Fidelity 全綠（1 分 50 秒）：27 檔、636 張影像雜湊。**同碼重跑雜湊逐檔相同**（渲染可重現，雜湊比對可用來判等價）。基線與 MANIFEST（HEAD 79bb4e4、對 284e2d1 的 diff 只含 Tests/ 與 docs/、測試檔 sha256、倍率與尺寸）存本 session scratchpad `fid-base/`。checkpoint 464026f。

### 9.1 T1–T2 ① Cenobyte 字距（2026-10-18）
- 設計細化：`LaidGlyph` 加 `advance`（排版時算 `width − spacing × em`，與改前畫字端同一算式、同一 em → 其他字型逐位元相同），畫字改讀它；字距只在 `layout` 讀 `face.spacing` 一次（取代計劃原寫的「兩處都改讀 face.spacing」，消除兩處不一致的可能）。`FitReport` 加 `metrics`（排版寬、字寬、字級）供測試。
- 紅燈：骨架後新測試 **31 斷言紅**（目錄字距 1、Cenobyte 30 字的排版寬各少 0.12 em）；真實 Cenobyte 長句守 I-45 的測試先天綠（留作回歸防線）。
- 綠燈：相關 5 suites 62 條綠（含 126 組縮字基線、③c 雜湊基線不變）。
- ACCEPTANCE 新增 I-48 ⚠️（單測 ✅、目視待 T10）。

### 9.2 T3 ②b–②e（2026-10-18）
- ②b：正式 enum 只剩 `.raster`／`.vectorReference`；Fidelity 以 `forceRaster` 在畫前把 plan 字的 face 改成 `rasterizes = true`（結構體複製），`withFace` 防漏抄斷言（`GlyphRunStrategyTests.forcingRasterChangesNothingButTheRasterizesFlag`）。等價重構，無紅燈，等價性待 T5 雜湊。
- ②c：推測 P2 **證實**——U+200B 不是 `isWhitespace`、外框為空；紅燈：連畫 3 幀 `misses` = 4（3 次空外框重試＋A）→ 實作後 1。`GlyphPathCache.Entry.isEmpty`，`stamp` 先擋。
- ②d：紅燈：同幀並列時本行程先逐出後建的 Q（8 迭代 16 斷言紅；字典迭代序隨行程雜湊種子而變，證實現行順序不確定）→ 最小值掃描＋建立序號決勝後綠。
- ②e：`GlyphKey`（init 以獨立 Hasher 算 `cachedHash`）同時當外框與點陣的鍵；外框快取容量可注入。新測試（相等鍵互相命中、各欄位不同即不等；外框清空後點陣仍命中）為回歸防線，舊寫法下也成立，無紅燈。
- checkpoint：add2e5c（②b–②d）、6137325（②e）。

### 9.3 T4 ②a 探針與採用（2026-10-18）
- 離屏（ImageRenderer 1728×945，Marker＋thump×{glow, none}，3 個 zoom>1.02 的時刻＋t=9.3，1×／2×）：一般字與光暈層、直接貼與群組圖層，`transform.a == d == zoom`（逐位元）、b = c = 0，displayScale 另計（1 或 2）。log：scratchpad `spike-transform.txt`。
- 真視窗（DEBUG 預覽 40 s × 2，內建螢幕 2×）：glow 配方 600 筆（215 筆 zoom≠1）全在光暈層 direct／grouped；none 配方 600 筆一般字 direct／grouped（192 筆 zoom>1、408 筆 zoom=1）；全部 a = d = zoom（日誌 6 位小數）、b = c = 0、ds = 2。log：`t4-onscreen*.log`。
- 判定：符合 §2.2 採用條件 → **採用**。`LyricsFXCanvas.deviceScale(of:)`＝displayScale × hypot(a, b)，刪 `zoom` 參數鏈；`LyricsFXDeviceScaleContractTests`（1×／2× × zoom 1／1.0398／1.04，含濾鏡圖層與巢狀 drawLayer）6 組綠。探針碼已還原（以 `git show` 取回 checkpoint 版本）。

### 9.4 T5 ② 收尾量測（2026-10-18）
- **V3**：Fidelity 全綠（100 s）；636 張影像雜湊與 T0 基線**逐張相同**（`diff -r` 無差異）→ ②a–②e 未改任何畫面。
- **冷首幀**（-O，AZW_PERF）：Catacombs 1200×650 3.98／1728×945 5.14 ms、Marker 1.76／2.66、Rock Salt 2.15／2.48 ms，全 ≤ 8.3 ms（上次 ≤ 4.23／5.15）。
- **V2 配對**（新＝850d2fa、對照＝284e2d1，各 -O；24 次全前景、xctrace 未掛；log scratchpad `v2-t5/`）：
| 配方 | 對照每輪 | 對照 V2 | 新版每輪 | 新版 V2 | Δ 每輪 | 平均 Δ | 判定 |
|---|---|---|---|---|---|---|---|
| Rock Salt | 0.702／0.562／0.617 | 0.627 | 0.631／0.628／0.571 | 0.610 | −0.071／+0.066／−0.046 | −0.017 | 達標 |
| Catacombs | 0.612／0.604／0.641 | 0.619 | 0.713／0.739／0.670 | 0.708 | +0.102／+0.134／+0.029 | **+0.088** | **改動退化（未通過）** |
- 歸因（主執行緒含式樣本，3 輪合計）：`LyricsFXCanvas.draw` 2154→2135、`fill` 1944→1936、點陣 `entry` 214→205；增量 +854 中 +845 在 AppKit `NSWindow updateConstraintsIfNeeded`（Catacombs 新版 R 臂 472／247／131 對對照 66／24／33；它在兩個二進位都會整段持續出現，例對照 rocksalt R-1 467，每秒 15–40 筆、非啟動暫態）。扣除後新版仍多 1.4%（9117→9244；Codex 以各臂 main−constraints 重算 V2：0.618→0.652，+0.034，仍超 0.02）。
- /thecure（Codex 1 輪）：我方主張「延後到 ③ 再判、不二分」**被駁回**——偏離預先登記規則、扣約束後仍 +0.034、③ 的結果不得倒灌 ②。依規則：T5 Catacombs 記未通過，二分 ② 的 checkpoint（①d38e0a3、②b–d add2e5c、②e 6137325；新版 850d2fa 已量），每點先配對 1 輪初篩、可疑者補滿 3 輪；從此起每次量測附輔助統計（約束更新、畫字樣本、畫布尺寸），只作歸因，不取代主判定。

### 9.5 二分初篩發現協定缺陷 → V2.1（2026-10-18，在看新數據前登記）
- 初篩（log `v2-bisect/`）每跑都記了畫布：**全部 1200×625（視窗模式）**，不是 I-46 V2 的全螢幕 1728×941。預覽視窗沿用上次關閉時的狀態，T5 的 24 次沒有記錄畫布 → **無法證明 T5 對照與新版在同一畫布上量**（T5 Catacombs R 臂畫字樣本 ~718／15 s，這次 ~1034，條件明顯不同）。另腳本 2 個 bug：對照臂 trace 檔名重複（xctrace rc=42）、新版經 symlink 啟動 `pgrep` 找不到（rc=34）→ 16 跑只有 7 跑有效。唯一有效配對（① d38e0a3，1200×625）：對照 0.832、① 0.800，Δ −0.032（探索性）。
- /thecure（Codex，第 2 輪）：T5 Catacombs 改記 **「不可判定（量測協定未受控）」**——不是通過，也不再稱退化；T5 原始數據與當時判定保留不刪，只撤銷其作為判定依據的資格。須先登記受控協定，再重做 T5 的父比較（新版 vs 對照）；父比較再判退化才二分。AX 自動全螢幕不採用（權限與 UI 自動化風險）。
- **V2.1 協定（預先登記，之後不得依數據改）**：
  1. 畫布：使用者手動把預覽視窗切全螢幕一次；之後每一臂以 `lyricsFXFrame` log 讀實際畫布，**全程必須是 1728×941 且只有這一種**，否則該臂作廢重跑（每臂最多重跑 2 次；仍不符 → 該輪無效，照實記錄）。若全螢幕狀態無法保持，改用「視窗 1200×625 協定」：配對 Δ 為主要終點，0.85 絕對門檻只作探索性，並明記口徑變更。
  2. 干擾：任一臂的 AppKit `updateConstraintsIfNeeded` 樣本 > 該臂主執行緒樣本的 5% → 該臂作廢重跑（同上限）。對兩個二進位對稱套用。
  3. 腳本 fail-closed：每臂唯一 run ID；輸出已存在即中止；以實際路徑啟動（不經 symlink），PID 由該路徑解析並核對；xctrace 非 0 即作廢重跑（同上限）。
  4. 排程、統計量、判定同 §4（每輪 對照→新→新→對照、臂序 ABBA／BAAB／ABBA、每輪比值平均、達標＝新版 ≤ 0.85 且平均 Δ ≤ 0.02；對照 > 0.85＝不可判定）。另報每輪 Δ 方向與輔助統計（畫字樣本、約束更新樣本、畫布）。
  5. 範圍：先重做 ② 的父比較（850d2fa vs 284e2d1，Rock Salt＋Catacombs，3 輪）；③ 做完後同協定再量一次（③ 的結果不倒灌 ②）。

### 9.6 V2.1 ② 父比較（2026-10-18；log scratchpad `v21-t5/`）
- 使用者手動把預覽切全螢幕一次；重開驗證畫布 1728×941 保持（`verify-fs.log`）。初篩 bug 遺留的 2 個測試實例（新版經 symlink 啟動、未被關掉）以 PID 關閉。
- 32 跑：28 有效、4 跑因約束更新 > 5% 作廢重跑（新版 2、對照 2，對稱）；有效跑全部 1728×941、全程前景、xctrace 無失敗。
| 配方 | 對照每輪 | 對照 V2 | 新版每輪 | 新版 V2 | Δ 每輪 | 平均 Δ | 判定 |
|---|---|---|---|---|---|---|---|
| Rock Salt | 0.711／0.852／0.713 | 0.759 | 0.733／0.799／0.785 | 0.772 | +0.021／−0.053／+0.072 | +0.013 | **達標** |
| Catacombs | 0.641／0.668／0.654 | 0.654 | 0.662／0.683／0.669 | 0.672 | +0.021／+0.015／+0.015 | +0.017 | **達標** |
- 照實：Catacombs 三輪 Δ 同為小幅正值，平均 +0.017 貼近容差 0.02；畫字樣本 R 臂對照 981／新版 1014、V 臂 2045／2089（3 輪平均）。依登記規則達標 → 不二分。
- 對照 Rock Salt V2 0.759（上個計劃 T6 為 0.843）：本次同協定配對量測，跨 session 的絕對值不可直接比。

### 9.7 T6 ③a–③e（2026-10-18）
- ③a：`shifted(…, stroke: CGFloat = 0)`，negative／ransom 主字明傳 `base.stroke`；刪 `runs(of:stroking:)` 旗標（View、Meter、Fidelity 摘要三處呼叫端）。紅燈 5 斷言（`shifted` 預設、misreg／reflect／weep／rgbsplit 四種殘影帶描邊）→ 綠。測試資料修正一次：rgbsplit 只在進場前半段有副本，原取 t=20 沒有殘影 → 改為掃整句每 0.05 s、檢查所有有殘影的幀（較單一時刻更嚴）。checkpoint 40f43f8。
- ③b：`Run.rasterizes` 進分段鍵、`fill` 讀 `run.rasterizes`。紅燈 3 斷言 → 綠。checkpoint b3aac15。
- ③c：`FitCache` 只存比例；`LineLayout.brokeWords` 由排版記錄；`search` 下限直接以斷詞排（斷了詞或放不下即停在下限，與改前的分支逐案等價）；命中時 `ratio <= minimumFitRatio` 才斷詞排。無紅燈（等價重構）；把關：7 案完整 FitReport 雜湊（冷算＋命中）、126 組基線、① 斷詞測試全綠。checkpoint 3c48d40。
- ③d：`ComposedStyle.wrapWidth(_:)`（算式不變），正式碼 2 處＋測試 1 處改用。
- ③e：`inkSpan`／`inkSpanX` → `B2BatchFourT7FixTests.inkBox(_:) -> CGRect`；`fontFace(_:)` 取代 8 處 `guard case .font`；兩條縮字描邊測試參數化為 `aShrunkLineStrokesWithItsShrunkEm(font:)`（Anton 多驗「縮後描邊 < 未縮描邊」）；`if font != "Anton"` 改為 `sizeScale <= 1`。對照：測試名單只少被併入的那條；`#expect`／`#require` 63→64、24→25，無刪減。相關 3 suites 34 條綠。

### 9.8 T7 ③ 收尾量測（2026-10-18；新版 bf0e286 -O）
- **V3**：Fidelity 全綠（96 s）；636 張雜湊與 T0 基線**逐張相同** → ③a–③e 未改任何畫面。
- **每幀 V1**（全螢幕 1728×941、全程前景；捨第一個 5 s 視窗（含啟動），其餘 7 窗；log `v1-t7/`）：Rock Salt p50 0.91–1.25／p95 1.77–2.27 ms、IM Fell 1.00–1.38／1.85–2.27、Courier 0.79–1.08／1.58–1.93、Shadows 1.07–1.72／2.26–2.77、Marker 1.02–1.48／2.49–2.69、Catacombs 1.14–1.59／2.14–2.33、Elite 0.86–1.03／1.81–2.06、**Cenobyte（Mayhem 可抽的最重組合 snow／condense／dissolve／misreg／shake／ice）1.02–1.62／1.73–2.37**；單幀最慢 6.2 ms（Elite，< 一格 8.3 ms）。**全部達標**（p50 ≤ 2、p95 ≤ 3）。
- **V2.1 中止（未得結果）**：第 2 跑失焦、第 3 跑約束更新超標皆作廢；第 4 跑前 fail-closed 守衛偵測到「仍有 app 在跑」而中止——查證為**另一個 Claude session（569cdfd0）同時在本機跑 Azathoth's Whisper 的 UI 測試**（12:18 另起實例，`-ApplePersistenceIgnoreState`）。失焦即其搶前景所致。V2 需獨佔機器 → 等使用者協調後補跑；不動該 session 的行程。V1 期間是否有並行負載未能排除，但並行只會使數字變差，「達標」結論不受影響。

### 9.9 T8 /simcodex（2026-10-18；R2 提前結束）
- 前置：發現 40f43f8（③a checkpoint）以 `git add AzathothsWhisper` 誤加「 2／ 3.xcodeproj」舊副本 8 檔 → 8be1741 以 `update-index --force-remove` 取消追蹤（磁碟不動）。歷史中仍有，合 main 時要整理。
| 輪 | 來源 | 採納並修 | 駁回／延後（理由） |
|---|---|---|---|
| R1 | simplify 4 角度（Sonnet；0 個 P1，23 條 P2） | ①空外框判斷搬進 `GlyphRasterCache.entry`（nil 被定義處、不計 miss；②c 的根本位置）；②快取命中一律斷詞排（快取只有 `search` 結果：停下限或每列放得下→斷不斷相同；免浮點比例比下限）；③刪 `Fitted.breaksLongWords`；④內聯 `rowsFitWidth`；⑤測試 `maxWidth` 別名改用 `wrapWidth`；⑥`fitDigest` 共用 `digest`；⑦`LyricsFXCatalog.font(_:)`（與 `palette(_:)` 並列），正式碼與測試共用、刪測試端 `fontFace` | `GlyphDraw.face` 改 var（為測試改正式型別、違反不可變慣例；R1 #9 已辯）；advance 改由量測值直出（會使畫字 origin 差 1 ulp，破壞像素逐張相同）；contract test 改走真 draw（真 draw 的縮放已由 V3 雜湊與 thump 案例把關，契約測試的目的是框架語義本身）；`GlyphKey` 退回普通 Hashable（②e 即本項目標，已辯）；FontFace 雜湊整體優化（diff 外、既有）；neon 殘影組合改斷言點陣＝向量（誤判：殘影走點陣，不會逐像素相同）；FitReport 基線合併後刪除（收官時交使用者）；`removeAll` 僅測試用、測試 helper 合併、`FitReport.metrics`、預設字距常數歸屬（P2 延後） |
| R1 | codex review --base 284e2d1 | — | **P1 駁回（誤判）**：稱元組 `<=` 不能編譯——Swift 標準庫自 SE-0015 起為元素皆 Comparable、≤ 6 元的元組提供比較運算子；該碼已編譯、決勝測試已綠 |
| R2 | 自評（R1 的 27＋／39− 行）＋codex review --uncommitted | 無（「behavior-preserving cleanup … No actionable regressions」） | — |
- 驗證：相關 8 suites 82 條綠。無安全敏感改動（無認證、網路、檔案寫入、使用者資料），未派 security-reviewer。

### 9.10 T9 全量回歸與 V2.1 定稿（2026-10-18）
- 使用者協調另一 session 停止後開跑（先以 ps 確認無其他 xcodebuild／App 實例）。
- 全量（e88ee0f）：**1293 條／160 suites 綠**（skip `overlappingLoadSuspendsPollingUntilLastCompletes()`）；`no_playback_gate.sh` 0；`coverage_gate.sh` Services+Infra 96.2%；Scripts Python OK。
- **全量情境下光暈 2 張雜湊與基線不同**（glow@4.6、@20.5 的 2× 點陣候選；參考圖相同；門檻判定仍綠）。鑑別：
| 條件 | 光暈 2 張 |
|---|---|
| e88ee0f 只跑 Fidelity | 與基線相同 |
| e88ee0f 全量（2 次） | 不同（2 次雜湊相同＝確定性） |
| 464026f（正式碼＝284e2d1）全量 | 與基線相同 |
| d38e0a3（①）全量 | 相同 |
| add2e5c（②b–d）、6137325（②e）全量 | 不同 |
| e88ee0f 只跑 GlyphRasterCacheTests＋Fidelity | 不同 |
| 同上但跳過 ②c、②e 兩條以 ImageRenderer 離屏畫圖的新測試 | **相同** |
  - 結論：**正式碼的改動不改畫面**；差異來自兩條新測試先在同一行程離屏畫圖（同字型、同字、2×），影響之後光暈點陣的雜湊。機制 TBD（推測為 SwiftUI／RenderBox 內部快取狀態），熔斷不深挖。
  - 修正：兩條測試改為在快取層模擬幀（`beginFrame`＋`rasters.entry`，②c 的判斷本就已在 `entry` 內），不再用 ImageRenderer；斷言語義不變。改後「快取測試＋contract＋Fidelity」與**全量**（1293 條綠）雜湊皆**逐張相同**。正式碼未變（仍＝e88ee0f），V2.1 定稿量測有效。
- **V2.1 定稿**（新版 e88ee0f -O vs 284e2d1；log `v21-final/`；有效跑全部 1728×941、前景）：
| 配方 | 有效輪 | 對照 V2 | 新版 V2 | 平均 Δ | 判定 |
|---|---|---|---|---|---|
| Rock Salt | 2／3（第 3 輪對照 R 臂連 3 次約束更新 > 5%，依協定該輪無效） | 0.805 | 0.792 | −0.012 | 達標 |
| Catacombs | 3／3 | 0.798 | 0.750 | −0.048 | 達標 |
  - 作廢 9 臂皆因約束更新（新版 5、對照 4）。對照絕對值較 T5 V2.1 高（0.759→0.805），同協定配對下 Δ 仍 ≤ 0。

### 9.11 T10 使用者在場（2026-10-18）
- Cenobyte 全螢幕新舊並排（Mayhem 最重組合；舊＝284e2d1 -O、新＝e88ee0f -O，各 25 s、1728×941、前景；使用者要求重播一次）：使用者「沒問題」。
- UI 測試：跑前輸入法為繁體拼音，請使用者切 ABC（未用模擬按鍵）；`LyricsFXUITests`＋`LyricsFlowUITests` **20／20 綠**（247 s）；跑後仍為 ABC。
- ACCEPTANCE I-48 改 ✅。

## 附錄 A　計劃評審記錄
### A.1 R1（Codex，2026-10-18）
| # | 嚴重度／位置 | 處置 | 理由／修改 |
|---|---|---|---|
| 1 | P1 V3「報告逐位元組相同」不等於像素相同 | **採納** | 改為每張候選影像原始 RGBA 的 SHA-256 新舊相同；T0 先加雜湊輸出 |
| 2 | P1 ②e 單調 id 在外框快取清空後讓點陣全變孤兒，非等價 | **採納**（我方前提錯） | 改為 entry 帶預算雜湊的語義鍵 `GlyphKey`；加「清空後仍命中」回歸測試 |
| 3 | P2 ②a 條件只看 X 軸 | **採納** | 完整 a,b,c,d、shear、各 stamp 位置 × 1×／2× × 離屏／上螢幕 |
| 4 | P2 ②a 依賴框架隱含語義 | **修改後採納** | 採用時必留離屏 contract test；上螢幕只能一次性探針（離屏測不到）——兩者不一致即放棄 |
| 5 | P2 ③c 以比例代理斷詞決策；基線只鎖比例 | **採納** | 斷沒斷由排版結果決定；加冷／命中成對測試與 284e2d1 完整 FitReport 基線 |
| 6 | P2 ②d 是 O(k·n)、並列順序會變 | **修改後採納** | 保留最小值掃描（k 通常 1–3，免每次全表排序與配置）；加建立序號決勝並以測試固定，明記為刻意的小行為變更；不建 heap（過度設計） |
| 7 | P2 V2 只在失敗時量對照不足；統計量未定義 | **採納** | 每次配對量 284e2d1；預先定義每輪比值平均與「≤0.85 且 ≤ 對照+0.02」 |
| 8 | P2 ③a 缺 neonstroke＋殘影效果的畫面證據 | **採納** | 加 4 份 neonstroke 組合只比新舊雜湊 |
| 9 | P3 ②b 重建 GlyphDraw 可能漏抄 FontFace 新欄位 | **駁回（附防線）** | `FontFace` 用結構體複製後只改 `rasterizes`，不逐欄抄；真正要逐欄的是 `GlyphDraw` 的 init，以「改回原值後 `==` 原字」斷言防漏抄。Codex 建議的「策略覆寫參數」等於把測試鉤子留在正式 API，正是本項要移除的東西 |
| 10 | P3 ①只驗算術 | **採納** | 加真實 Cenobyte 長句 plan 案例 |
### A.2 R2（Codex，2026-10-18）
- A.1 #1–#10 全部關閉（含駁回的 #9：Codex 同意結構體複製＋「改回原值後 == 原字」能防漏抄）。
| # | 嚴重度／位置 | 處置 | 理由／修改 |
|---|---|---|---|
| N1 | P2 ②e 以 `hashValue` 預算會遞迴；未寫生命週期 | **採納** | 改以獨立 `Hasher` 算 `cachedHash`；註明只限同行程；外框鍵共用同一定義；補相等／不等測試 |
| N2 | P2 V2「配對」未定義逐輪排程；0.02 與 0.021 不符；基線也劣化時不該二分 | **採納** | 逐輪 對照→新→新→對照、記 Δi；判定分達標／不可判定／改動退化三類；0.02 明記為工程取值 |
| N3 | P3 雜湊基線的正式碼來源不可稽核 | **採納** | 清單檔頭記 HEAD、對 284e2d1 的 diff 只含 Tests/、測試檔雜湊、scale |
- R2 後無 P0／P1 開著，剩餘三條已依建議修改且無爭議 → 提前結束，不跑 R3。**計劃定稿（2026-10-18），待使用者審閱拍板。**
