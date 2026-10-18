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
