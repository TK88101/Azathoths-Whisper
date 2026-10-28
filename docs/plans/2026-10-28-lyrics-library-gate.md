# 歌詞特效 ⑧：曲庫閘門（計劃 v1.0 定稿）

狀態：**v1.0 定稿**（使用者 2026-10-28「照這個方案做吧」；Codex 4 輪收斂，見附錄 B；§10 三項經 /thecure 收斂，見附錄 C）。母計劃 docs/plans/2026-10-19-lyrics-fx-style-coverage.md §2「曲庫閘門」。前置：⑥a（06fc417）、⑥b（57453ba）、⑦（835969b）、時間軸準度（96ba9c4）皆已合 main。分支 `wip/lyrics-library-gate`（自 main 96ba9c4）。

## 0. 複述
- 母計劃定義的閘門有四項：①identityUnresolved＝0（由使用者處理）②composed 100 %（每首都組得出樣式，不是素面）③readability（每首實際會抽到的樣式都經過可讀性檢查）④每首列出解決來源。
- 本計劃要做的是：**量得出這四項的工具**（app 內「曲庫檢查」）、**讓使用者把不合格的歌手處理掉的介面**（⑥b §3 非目標裡說「⑧ 前要先有 identityUnresolved 的處理介面」），以及把可讀性檢查補到曲庫實際出現的多列組合。
- 「閘門通過」＝使用者處理完之後，四項的計數同時為 0（範圍見 §4.1、§10）。
- 完成標準＝§7 驗收。

## 1. 使用者決定（既定前提，不重議）
1. 閘門四項（母計劃 §2，2026-10-19 Codex 3 輪收斂）。
2. 優先順（母計劃 §2）：署名樂團表 > 專輯指定 > 樂團指定 > 驗證過的自動分類（MB）> 同歌手曲庫共識 > Apple 曲風 > 通用。
3. 改署名樂團的樣式要經「替換署名樣式」明示操作（母計劃 §2）。
4. 日文歌一律 J-Pop、不開例外（⑥a §1-1、§1-2：MONGOL800 也不例外）。
5. Apple 只標 Rock／Alternative 的曲**不做通用列**（⑦ §9-1 (a)，2026-10-25）。
6. MB 外送只有歌手名＋專輯名；每位歌手只查一次、不主動重查（⑥b §1-2、§1-3）。
7. 樣式存在 app 內，不改 Music 標籤；Music 只讀＋寫 lyrics（CLAUDE.md）。本計劃不寫任何 Music 欄位。
8. 讀不到的效果不可（母計劃 §0）；可讀性＝G1–G3（docs/plans/2026-10-20-lyrics-fx-readability-gate.md §2）。

## 2. 事實

### 2.1 程式現況（2026-10-28 讀碼，已核）
- 判定順序（`Services/Lyrics/SongProfileResolver.swift:265-282`）：樂團表 → 歌詞未知 pending → J-Pop → MB 曲風列 → genre nil pending → Apple 曲風列 → 通用列（先 MB 再 Apple）→ `.noMatch`。各層合成後組不出（`Composer.isComposable` 為否）就落下一層；**署名層不檢查**（第一行直接回 `.signedBand`）。
- `ProfileResolution` 只帶 `SongProfile`，**不帶命中了哪幾列**（:66-95）；`ProfileSource` 的使用者只有 `LyricsFXViewModel`（定格判斷，`LyricsFXViewModel.swift:58、228、252`）。app 內**沒有**任何逐首列出來源的畫面或匯出。
- 專輯指定、樂團指定、同歌手曲庫共識三層**都還沒有**（⑥b §3、⑦ §3 非目標）。
- MB 存檔 `ArtistStyleBook.Record`（`Services/ArtistStyles/ArtistStyleBook.swift:17-27`）欄位：寫法集合、mbid、比對到的 release-group、曲風、unresolved 原因、查詢時間；**沒有「是否手動」**，也不存候選清單。
- 可讀性稽核的涵蓋：`ReadabilityAudit.profiles`（`Tests/LyricsFX/ReadabilityAudit.swift:164-172`）＝樂團表＋各曲風列**單列**＋各通用列**單列**；G2／G3（`ReadabilityGateTests`）與 G1 對比（`LyricsFXContrastTests.swift:99-101、159`）都只走這份。多列組合只驗了組得出（`GenreRowTests.swift:99-105`）與每次換一套（`GenericLayerTests.swift:95-101`）。`GenreRowTests.swift:98` 註解寫「`LyricsFXContrastTests` 用同一份集合」，與程式不符。
- 整庫讀取：現有 `MusicControlling.libraryArtistAlbums()` 只回 artist／album、`artistTracks(artist:)` 只回 album／lyrics（`Services/Music/MusicControlling.swift:188-204`；真 client 的 `readPairs` 只收兩欄，`MusicAppleEventsClient.swift:251-279`）——**逐首報表要新增 protocol 方法**（R1-1）。需要的選擇器 `tracks`／`name`／`artist`／`album`／`persistentID`／`lyrics`／`genre` 全在白名單（`Tests/Services/MusicSelectorAllowListTests.swift:18-22`），**不需新選擇器**。所有 AE 走同一條序列佇列（`MusicAppleEventsClient.swift:33-37`）。
- MB：首次查詢時已對每位歌手做過 1 次搜尋＋最多 8 位同名候選的 lookup（`inc=genres+release-groups`，第一頁 25 筆 release-group，必要時 browse；`MusicBrainzClient.swift:21-60`、`ArtistIdentity.swift:36`），候選與曲風一起回來；但**候選不落盤**。
- 選單：`Settings` 選單寫死英文（`App/AzathothsWhisperApp.swift:22-35`，A-07）。Settings modal 是 token／language／notifications 三組互斥的單欄小窗（`SettingsViewModel.swift:3`）。

### 2.2 唯讀量測（2026-10-28）
方法：JXA 唯讀讀整庫 persistentID、artist、genre、lyrics（12,271 首；歌詞只在本機判日文與有無，不出檔）＋`ArtistStyles/artists.json`；用 app 自己的原始碼（`swiftc` 直接編 resolver、Composer、目錄、ArtistStyleBook 等，同 ⑦ §2.3 方法）逐首判定，只印計數，不印歌手名、曲名。程式在 scratchpad，不進 repo（附錄 A）。

| 項目 | 全曲庫 | 有詞 | 無詞 |
|---|---|---|---|
| 曲數 | 12,271 | 5,896 | 6,375 |
| **① identityUnresolved**（非樂團表、非 J-Pop、MB 存檔為 unresolved） | **1,173 首／137 位** | 316 | 857 |
| 　其中 ambiguous | 555 首／20 位 | 197 | 358 |
| 　其中 noAlbumMatch | 414 首／78 位 | 78 | 336 |
| 　其中 notFound | 204 首／39 位 | 41 | 163 |
| 　MB 還沒查（unknown） | 0 | 0 | 0 |
| **② 不是 composed（素面）** | **572 首／57 位** | 142 | 430 |
| 　其中 noMatch | 394 | 135 | 259 |
| 　其中署名樂團但組不出（4 團，⑦ §2.1） | 178 | 7 | 171 |
| **③ 實際樣式不在可讀性稽核集合內**（多列組合） | **2,516 首／43 種組合** | 1,192 | 1,324 |
| 　其中組合會抽到單列抽不到的（背景, 配色）＝ G1 也沒量過 | 1,502 首／33 種組合／352 組配對 | — | — |
| **④ 有逐首來源列表** | **0 首**（功能不存在） | | |
| pending | 0 | | |

- 各來源：樂團表 5,337、MB 曲風列 4,543、Apple 曲風列 1,308、通用列 557、J-Pop 132、noMatch 394（與 ⑦ 附錄 D 收尾值 394 相同）。
- noMatch 394 首的 MB 狀態：unresolved 316 首／46 位、verified 無曲風 57 首／6 位、verified 有曲風但碰不到任何列 21 首／1 位。Apple 曲風：ロック 118、オルタナティブ 111、rock 92、alternative 66、hrad rock 6、r&b/soul 1。
- 137 位 unresolved 歌手：91 位的歌**全部**已靠 Apple／通用列組出樣式；7 位部分素面；39 位全部素面。
- 整庫一次讀一欄的耗時（JXA，唯讀）：artist 125 ms、genre 59 ms、persistentID 55 ms、name 68 ms、album 77 ms；lyrics 整庫一次讀 10.3 s（⑥b 附錄 E，超過 AE 預算，不可整庫讀）。

### 2.3 推論（推測，標明推理鏈）
- 「同歌手曲庫共識」層對閘門幫助接近 0：它只採署名／使用者指定／驗證過的 MB 為根據（母計劃 §2），而 noMatch 的 53 位非署名歌手全是 unresolved 或 MB 無曲風／碰不到列（§2.2）——沒有根據可傳。使用者指定本來就是歌手層級，指定後同歌手的歌一起解決。→ 本計劃不做共識層（§3）。
- 1,502 首的 352 組新配對：組合的標籤是各列聯集，所以背景可能來自 A 列、配色來自 B 列，形成單列永遠抽不到的配對。是否真有不及格：**TBD**（T2 量）。

## 3. 目標與非目標
目標：
- app 內「曲庫檢查」：逐首列出來源與四項判定、四項計數、達標／未達標。
- 使用者處理介面：對每位不合格歌手（身分未定或素面）可以 a. 指定樣式（樂團指定）、b. 明確表示「身分不認、照目前樣式」；每個決定都可變更、清除。不提供手動查 MB 候選（§10-3）。
- 可讀性稽核擴到曲庫實際出現的多列組合與使用者可指定的樣式；app 內有一份版本化的「已稽核樣式」清單可判斷每首稽核過沒有。
- 使用者處理完後四項同時為 0（範圍與署名 4 團依 §10）。

非目標：
- 專輯指定層（量測沒有需要它的情形：不合格都是歌手層級；YAGNI）。
- 同歌手曲庫共識層（§2.3）。
- 新元件、新曲風列、改既有列（含 Rock／Alternative，§1-5）；為署名電子團補元件（⑦ §9-2）。
- 自動或背景重查 MB、定期掃描；匯出報表檔（來源列表只在 app 內顯示）。
- 改 Music 標籤；sandbox；iCloud；Python 1.x。

## 4. 設計

### 4.1 閘門定義（每首一列判定，全部是純函式）
- **範圍**：預設＝**全曲庫**（含無詞曲）。理由：樣式決定在歌手層級，無詞曲之後寫入歌詞就會顯示特效（缺詞→寫入後升回的既定流程）；同時報「有詞子集」（§10-2，R1 Codex 同意全曲庫）。
- **G-ID**：歌曲需要 MB 層（`needsArtistGenres` 且不是 J-Pop）、歌手 MB 狀態為 `unresolved` 或 `unknown`、且該寫法家族**沒有使用者決定**（§4.3）→ 不合格。
- **G-COMP**：判定結果是 `.jpop`，或帶 profile 且 `Composer.isComposable` 為真 → 合格；`pending`／`noMatch`／署名組不出 → 不合格。
- **署名待補元件**（§10-1）：署名樂團組不出的曲（現況 4 團 178 首）是 **G-COMP 不合格的子集**，在畫面另欄標示「署名待補元件」，**照樣計入 G-COMP、擋住達標**；名單＝`SongProfileResolver.bandTable` 中 `isComposable` 為否的團（由程式算，不手寫），另立的「署名團補元件」計劃完成後自動歸零。
- **G-READ**：G-COMP 合格的曲，其 `auditKey`（§4.2）在 `ReadabilityPolicy.audited` 內 → 合格。所有可選的 `.style` 列都是單列、必在 `audited` 內（測試守），所以指定樣式一定讓該曲 G-READ 合格。
- **G-SRC**（R1-10）：來源列「可判讀且可追溯」：最終來源＋其根據（命中列 id／指定列／署名團名／J-Pop 政策）＋MB 狀態＋使用者決定（有則列）＋回退鏈（有則列）。`noMatch` 與署名組不出必須帶原因文字（例：「MB 無法確認身分；Apple 曲風 Rock，依既定政策不設通用列」）。MB 狀態對署名與 J-Pop 曲寫「不適用（優先層）」，算合格的狀態值（R3-6）。缺任何一項或為 pending → 不合格。
- 計數單位同時給「首」與「位歌手」；「達標」＝四項皆 0（署名待補元件也要歸零）。

### 4.2 解決來源 `Explanation`
- `SongProfileResolver.explain(...) -> Explanation`；`resolve(...)` 改為 `explain(...).resolution`（同一語義一處定義）。
- `Explanation`（不可變值）：
  - `resolution`：既有 `ProfileResolution`（＋§4.3 的 `.userStyle`）。
  - `key`：`.signed(bandName)`／`.jpop`／`.rows(layer, ids)`（layer＝mbGenre／appleGenre／genericMB／genericApple；ids＝合成實際用到的列，排序去重）／`.userStyle(rowID)`／`.none(reason)`／`.pending`。結構化（R2 V02-3）；不做署名替換（§10-1），所以沒有替換 case。
  - `auditKey`（R3-3，v0.4）：由 `key` 投影、**不分層**——`.signed(name)`、`.jpop`、`.rows(ids)`。`.rows(layer, ids)` 與 `.userStyle(rowID)` 都投影成 `.rows(ids)`／`.rows([rowID])`：同一組列不論從哪一層命中，合成出的目標值相同（`compose(rows:)` 只看列，`SongProfileResolver.swift:316-326`），配方空間也相同。列 id 在 `keywordRows ∪ genericRows` 中唯一（測試守）。
  - `trace`（R1-4）：依序記每一層的嘗試：`(layer, 命中列 ids, 結果)`，結果＝採用／組不出／可讀性拒絕（`ReadabilityPolicy.rejected` 的鍵）／無命中。最終 `key` 簡潔，來源列與驗收輸出帶 trace。
- 來源列欄位：曲名、歌手、專輯（只在畫面顯示，不寫日誌）、來源（key 的人話）、根據、MB 狀態、使用者決定（類型＋時間）、回退鏈、G-COMP、G-READ。
- 不變式（R1-3 改）：見 §4.7——沒有使用者決定、且不屬 T2 簽字的「可讀性拒絕組合」的曲，逐首 0 差異。

### 4.3 使用者決定（樂團指定）
- 新存檔 `Application Support/com.ibridgezhao.azathothswhisper/ArtistDecisions/decisions.json`，與 MB 快取分開（快取重建不可帶走使用者決定）。防線沿用 `TimingStore`／`ArtistStyleStore`（schemaVersion、不讀符號連結、上限 1 MiB、壞檔視為空、看不懂的新版本不覆寫、atomic 寫）。
- **鍵＝寫法家族**（`ArtistStyleBook.spellingFamily`＝`TrackMatcher.exactKey`：只折疊大小寫、全半形、變音與空白，保留標點；`ArtistStyleBook.swift:63-66`），不是 `normalizedArtist`（R3-2，v0.4 改）。
- 理由：MB 存檔以 `normalizedArtist` 為鍵，所以 `AC/DC` 與 `ACDC` 撞鍵時分不出 mbid 屬誰，只能整鍵記 collision（⑥b R2-3）。使用者決定是對**畫面上那位歌手**下的，以寫法家族為鍵時，不同寫法家族本來就是不同鍵——決定存檔內**不可能撞鍵**，也不需要掃描時算撞鍵、不需要撞鍵快照或持久化。同一寫法家族（`LINKIN PARK`／`Linkin Park`）共用一筆決定，與 MB 存檔「同一歌手的大小寫寫法合併」一致。
- 結果：resolve 當下只用該曲的 artist 字串算寫法家族查表，報表與播放用同一個查法。v0.3 的「共用 `isVariant` 判斷式」「記憶體內 `reconcilingLibrary`」只在**決定層**拿掉；**MB 存檔的撞鍵偵測（`ArtistStyleSync`＋`reconcilingLibrary`）完全不動**（R4 A-3）。
- **同一位歌手多個寫法家族**（R4 A-1）：`The Beatles`／`Beatles`、`AC/DC`／`ACDC` 這類同 `normalizedArtist`、不同寫法家族的情形，檢查畫面把它們並排並提供明示勾選「一併套用到：…」，使用者勾了才把同一個決定寫進每個家族；不自動合併。現況：⑥b §2 整庫正規化撞鍵 8 組全是大小寫差異（同一寫法家族），所以目前曲庫 0 位受影響；這是防日後的機制。
- **同名異人（已知限制，R4 A-2）**：app 對歌手身分的唯一依據是 Music 的 artist 字串（B1 樂團表、⑥b MB 層都一樣），完全同名或只差大小寫的兩位不同歌手無法分辨，決定會套到兩者的所有歌。防線（僅在日後簽字開放 §4.4 時適用）：若有 ≥ 2 位同名候選各自對到曲庫裡**不同**專輯，判為「曲庫可能混了同名的不同歌手」，**不允許 `.identity`**，只能指定樣式或照目前樣式。真正分開要靠專輯指定層（本計劃非目標）。
- 與 MB 層的關係（僅在日後簽字開放 `.identity` 時適用）：`.identity` 的曲風只取代**這個寫法家族**的 MB 狀態；同 `normalizedArtist` 下的其他寫法家族照 MB 存檔（含 collision）判定。檢查畫面以寫法家族列歌手，同 `normalizedArtist` 的不同家族並排顯示並標「名字正規化後相同」。
- 值（本計劃做兩種；`.identity` 不做）：
  - `.style(rowID)`：只給**非樂團表**歌手（以該曲 artist 判 `needsArtistGenres`）；指定**單一**曲風列或通用列（`keywordRows ∪ genericRows`，`removedRows` 不可選）。只允許單列：單列都在稽核清單內，多選會產生未稽核組合。樂團表歌手的介面不提供樣式選項（§10-1；R2 V02-7：日後若有署名替換，要另一個 case 與另一份可選集合，不得重用 `.style`）。
  - `.keepFallback`：「身分不認、照目前樣式」。只解除 G-ID，不改判定。
  - `.identity(mbid, genres)`（**本計劃不做**，§10-3；保留文字供日後簽字參考）：使用者手動查得候選並選定；曲風取自該候選的 lookup 回應（同一請求已帶 `inc=genres`）。合成時以這份曲風當 `ArtistGenres.verified`。
  - 每筆另存 `decidedAt`。
- **變更／清除（R1-6）**：每位歌手可改成另一種決定或清除（確認提示）；清除後回到 MB 快取／Apple 的判定，計數回升。不需整檔刪除。
- 落層位置：樂團表 → pending → J-Pop → **使用者樣式（`.style`）** → MB 曲風列 → …（其後不變）。使用者樣式排在 J-Pop 之後：日文歌一律 J-Pop 不開例外（§1-4）。新 case `ProfileResolution.userStyle(SongProfile)`、`ProfileSource.userStyle`（`dependsOnLyrics` 為否；VM `shouldCompose` 的 switch 加這個 case，規則不變）。指定的列組不出（目前不會，防日後改目錄）→ 落下一層並記在 trace。
- 署名樂團：本節不可改；處置見 §10-1。
- session 語意：沿用定格規則，決定在下次播放生效；檢查畫面的報表立即重算（§4.5 時間標示）。
- 批次操作：清單可多選「身分不認、照目前樣式」，**只允許**對「所有歌都已 G-COMP 合格」的歌手（現況 91 位）；其餘一位一位處理。

### 4.4 身分處理流程（MB 候選）——**本計劃不做**（§10-3）；以下設計保留供日後使用者另行簽字時參考
- 不在打開歌手時自動查；使用者按「查 MB 候選」才送出（一次按鈕＝一次查詢，R1-2）。外送內容同 ⑥b §1-2（歌手名；專輯比對在本機）。共用既有 `SourceGate`（1.1 s 間隔、熔斷）與 User-Agent。
- **請求預算（R1-7）**：1 次搜尋＋每位同名候選 1 次 lookup（`inc=genres+release-groups`，只取第一頁 25 筆，**不 browse**）；同名候選 > 8（`ArtistIdentity.maximumCandidates`）＝不列候選，顯示「同名太多，請直接指定樣式」。最多 9 請求（< ⑥b 的 12），選定後不必再查（曲風已在 lookup 回應裡）。
- 每個候選顯示：名稱、消歧義、國家、類型、與曲庫專輯比對到哪幾張（≥ 2 位候選各對到不同專輯＝停用 `.identity`，§4.3 同名異人）；release-group 恰滿 25 筆時標「只比對了前 25 張，數字可能偏少」。選定前預覽「將套用的樣式」（key 人話）。
- 網路失敗：顯示錯誤類型、不寫存檔；可再按。MBID 一律驗 UUID 格式（同 ⑥b simcodex）。

### 4.5 曲庫檢查畫面與掃描
- 入口：`Settings` 選單加 `Library Check...`（寫死英文，A-07），開**獨立視窗**（`Window` scene，id `library-check`）——清單長，處理歌手時主視窗照常運作；不塞進三組互斥的 Settings modal。
- 上方：四項計數（首／位，全曲庫與有詞子集並列）＋達標／未達標；**「曲庫掃描時間」與「決定最後套用時間」分開標示**（R1-12）；決定後報表即時重算，但曲庫或 MB 存檔在掃描後有變動時，達標狀態顯示「需重新掃描確認」。
- 分頁「待處理歌手」：不合格歌手清單（以寫法家族列；原因：身分未定＋類別／素面／未稽核）、曲數、曲庫專輯數；點開進 §4.3／§4.4 操作。
- 分頁「逐首來源」：全曲庫表格（§4.2 欄位），可搜尋、可篩選「只看不合格」。
- 掃描（`LibraryGateScanner`，在 `AppModel` 組裝）：
  1. **新 protocol 方法**（R1-1）`MusicControlling.libraryTrackSnapshot() -> [LibraryTrackRow(persistentID, name, artist, album, genre)]`：真 client 在**一次** AE 工作內讀五欄（實測各欄 55–125 ms，合計約 0.4 s），整批共用 1.5 s 預算；替身全部補齊（T0 列出所有 `MusicControlling` 實作者）。
  2. **新 protocol 方法**（R2 V02-1）`MusicControlling.artistLyrics(artist:) -> [(persistentID, lyrics)]`（`whose artist == X` 讀兩欄，沿用 `readPairs`）：歌詞只在本機判「有無詞」「是不是日文歌」，以 persistentID 回填步驟 1 的逐首列，歌詞不出 scanner。以 `normalizedArtist` 分組，組內**每種原始寫法各查一次**（`whose` 對原始字串比對，只查一種寫法可能漏曲；⑥b 附錄 E T4 同一問題），結果以 persistentID 去重；整組寫法集合同時交給 §4.3 的撞鍵判斷（R2 V02-8 部分採納）。
  3. **一致性與取消**（R1-9、R2 V02-5）：同時只有一個掃描，每個掃描帶 generation token；scanner **同一時間只排一個 AE 工作**，上一個回來後先檢查 token 與取消狀態才排下一個（AE 開始後無法中斷，`MusicAppleEventsClient.swift:237`）；舊 token 的結果一律不發布。
  4. **完整性**（R3-4）：兩個新方法回 `Result`（成功／AE 逾時／讀取失敗），不用空陣列表示失敗（現有 `readPairs` 讀取失敗回 `[]`，不能當完整性訊號，新方法另包一層）。逐組結果的 persistentID 聯集必須等於步驟 1 的 persistentID 集合；任何一組失敗、逾時或回填不全＝本次掃描標「未完成」，**不發布為可判定達標的快照**，畫面保留上一份完整快照並註明「掃描未完成，不能判定達標」。新掃描取代舊的、關視窗或退出 app 時取消；顯示進度（第 N／M 組）；快照帶開始／結束時間；結果只在記憶體，換一次掃描換一份不可變快照。
- 日誌只記序號、計數、錯誤類型（CLAUDE.md 脫敏）。
- 三語字串進 `Localizable.xcstrings`（選單除外）。

### 4.6 可讀性涵蓋 `ReadabilityPolicy`
- **production 只放小型版本化清單**（R1-11、R2 V02-6）：`ReadabilityPolicy`＝版本號＋`audited: Set<key>`＋`rejected: Set<key>`（兩者互斥）。鍵是 §4.2 的 `auditKey`（`signed(name)`／`rows(ids)`／`jpop`）。resolver 讀 `rejected` 做可讀性拒絕落層，檢查畫面讀 `audited` 判 G-READ。`jpop` 一個鍵代表三變體**全部**已稽核（任何一首日文歌每次播放可能抽到任一變體，`JPopVisualTests` 三變體全跑；R1-8 部分採納：不必記本曲抽到哪個變體）。
- **測試端負責生成與斷言**：fixture（`GenreRowTests.libraryCombinations`＋`GenericLayerTests.libraryCombinations` 合併成一份測試資料）＋單列＋樂團表＋J-Pop 生成「應稽核集合」，斷言 `audited ∪ rejected` 與它完全相等、兩者交集為空、`rejected` 每一筆都有 G1–G3 不及格記錄；`ReadabilityAudit.profiles`、`LyricsFXContrastTests`（G1，含組合的跨列配對）、`ReadabilityGateTests`（G2／G3）都走這份。`GenreRowTests.swift:98` 不實註解改正。
- fixture 要涵蓋 §2.2 的 43 種曲庫組合（T2 以量測程式輸出列 id 組合核對，缺的補進）。
- 組合跑 G1–G3。不及格組合的處置（預先定好）：寫進 `ReadabilityPolicy.rejected`，resolver 把該組合視同「組不出」落下一層，trace 記「可讀性拒絕」；落下一層後若變素面，由使用者 §4.3 指定樣式解決。每一筆記 ACCEPTANCE ⚠️（改了既有曲的樣式），並列進 §4.7 的例外集合。不手調元件。
- 執行期遇到清單以外的新組合（新歌手）：G-READ 不合格、顯示在檢查畫面；開發端補進 fixture、跑稽核、更新清單版本。不在執行期跑 G2／G3（一輪近 30 分鐘）。

### 4.7 驗證工具
- **曲庫不變式（R1-3 改為雙層）**：§2.2 的量測程式改前改後各跑一次，逐首比較（判定 case、key、十軸＋標籤、固定 seed 配方 id）的雜湊：
  1. 沒有使用者決定、且不在「T2 簽字的可讀性拒絕組合」內的曲：**0 差異**。
  2. 例外集合的曲：逐首釘住（匿名曲雜湊、舊 key、新 key、回退鏈），數量＝T2 的 `rejected` 推得的值。
  只出計數與匿名雜湊。
- 交叉核對：app 內檢查畫面的計數 ＝ 量測程式在同一份曲庫上的計數（處理前基線：G-ID 137 位／1,173 首、G-COMP 572 首（其中署名待補元件 178 首）、G-READ 依 T2 結果；G-SRC 現況 12,271 首全缺（功能不存在，R2 V02-4），T1／T6 完成後應為 0 缺）。

## 5. 任務清單（每項先紅後綠；單人主 session 依序，不並行——後項依賴前項的型別）
| # | 任務 | DoD |
|---|---|---|
| T0 | `libraryTrackSnapshot()`、`artistLyrics(artist:)`（protocol＋真 client＋所有替身）；真 client 兩段讀法的耗時 p50／p95／最壞與掃描中 `nowPlaying` 延遲、**全庫掃描總耗時與 artistLyrics 呼叫次數**（DEBUG 量測，使用者在場看日誌） | 契約測試綠；選擇器白名單不變；每次 AE ≤ 1.5 s、掃描中 `nowPlaying` 延遲最壞 ≤ 1.5 s（同 ⑥b 停損線）；全庫掃描總耗時 ≤ 3 分鐘（推估：寫法數約 500 × 每次 ≤ 0.15 s ≈ 75 s，留一倍以上餘裕）；任一項不達標停下改方案 |
| T1 | `Explanation`（key＋auditKey＋trace）＋`explain`；`resolve` 改由它推出 | 真值表（每層各一、generic 抑制、組不出落層的 trace）；同一組列從 MB／Apple／通用／使用者樣式命中時 profile、`isComposable`、auditKey 相同，同 seed／歷史下配方相同（R4 B-1）；列 id 全域唯一；`RecipeGoldenTests` `2f80…` 不變；曲庫不變式第 1 層 0 差異 |
| T2 | `ReadabilityPolicy`（audited／rejected）＋測試端生成斷言；fixture 涵蓋 43 種曲庫組合；組合跑 G1–G3 | `ReadabilityPolicy` 定案；拒絕組合依 §4.6 處置、記錄、使用者簽字；不變式例外集合數量確定 |
| T3 | `ArtistDecisionStore`（鍵＝寫法家族） | 往返、壞檔、符號連結、超大檔、新版本不覆寫、變更、清除；大小寫／全半形寫法共用一筆；`AC/DC` 與 `ACDC`（同 normalizedArtist、不同家族）各自一筆互不影響、勾選「一併套用」才同時寫入；樂團表歌手不接受 `.style` |
| T4 | resolver 使用者層 | 真值表：署名優先、J-Pop 優先於使用者樣式、使用者樣式優先於 MB、`.keepFallback` 不改判定、不同寫法家族各自獨立、同家族大小寫寫法共用、清除回到原判定；VM：同 session 不重組、下次播放生效 |
| T5 | ~~MB 候選查詢~~——**不做**（§10-3） | — |
| T6 | `LibraryGateReport` 純函式（逐首列＋四項計數） | 四項各自真值表（含 G-SRC 原因文字、回退鏈）；全曲庫／有詞子集；批次「照目前樣式」只對全合格歌手 |
| T7 | `LibraryGateScanner`＋`AppModel` 接線 | 替身契約測試；某組逾時／讀取失敗／persistentID 回填不全 → 不發布、標未完成；兩種寫法查回同一 persistentID → 去重後不重複計數（R3-1）；單一掃描、取代、取消、進度；同時最多 1 個 AE 工作、取消後不再排、舊 generation 不發布；逐寫法查詢＋persistentID 去重；掃描失敗顯示錯誤不崩；`no_playback_gate.sh` 綠 |
| T8 | 曲庫檢查視窗＋VM＋三語字串＋選單 | VM 單元測試（篩選、批次限制、決定／變更／清除後重算、過期標示）；UI 測試一條：DEBUG 假曲庫一位 unresolved 歌手 → 指定樣式 → G-ID、G-COMP 計數下降 |
| T9 | ACCEPTANCE I-68 | 條目含依據、驗證方式、使用者簽字欄 |
| T10 | 全量單元＋coverage_gate＋no_playback_gate＋Scripts 測試；曲庫不變式；交叉核對 | 全綠（已知 flaky 以完整名稱＋括號 skip 並列出）；計數一致 |
| T11 | 使用者在場：用曲庫檢查處理歌手（一次一項說明流程）；補元件計劃完成後重掃 | 全曲庫四項皆 0（含署名待補元件）；截圖不含憑證欄位 |

**依賴順序**（/thecure 整體確認）：⑧ T0–T9（工具完成）→ 另立「署名團補元件」計劃（簽字；DoD 含四團 `isComposable`、每次換一套、G1–G3、回歸後署名待補元件＝0）→ 更新 `ReadabilityPolicy.audited`、重跑 T2 → ⑧ T10–T11（閘門通過判定）。

## 6. 測試策略
- 單元：T1–T7、T8 的 VM。測試字串自編（不用真歌詞、真歌手名）。
- 整合：store＋resolver＋report 用替身 Music 跑 10 位歌手的小曲庫（含 unresolved、署名組不出、組合、日文、同 normalizedArtist 的兩個寫法家族）；決定後下一 session 生效。
- E2E：T8 一條 UI 測試（DEBUG 注入假曲庫），使用者在場跑。
- 一次性唯讀驗證：曲庫不變式、交叉核對（不進測試 target：app 宿主測試開不了 ~/Documents、測試不得讀使用者曲庫）。

## 7. 驗收
1. §5 各 DoD 綠；全量單元（除列明 flaky）綠；coverage_gate ≥ 80 %；`no_playback_gate.sh` 綠。
2. `RecipeGoldenTests` `2f80…` 不變；曲庫不變式第 1 層 0 差異、第 2 層數量＝T2 的 `rejected` 推得值。
3. 處理前：app 內計數＝量測程式計數（G-ID 137 位／1,173 首、G-COMP 572 首（其中署名待補元件 178 首）、G-SRC 0 缺（功能裝上後）；G-READ 以 T2 補完 fixture 後的值）。
4. 閘門通過＝使用者處理完、且「署名團補元件」計劃完成後，全曲庫四項皆 0（含署名待補元件歸零；有詞子集並列）。⑧ 本身完成 T0–T9 只算「工具完成」，不算閘門通過（§5 依賴順序）。
5. I-68 簽字。

## 8. 影響面
`SongProfileResolver.swift`（explain、Explanation、使用者層）、`MusicControlling`＋真 client＋全部替身（`libraryTrackSnapshot`、`artistLyrics`）、`ArtistStyleBook`（寫法家族判斷式改 internal 共用）、新 `Services/ArtistStyles/ArtistDecisionStore.swift`、新 `Services/LibraryGate/`（Report、Scanner、ReadabilityPolicy）、新 `Features/LibraryCheck/`（VM＋View）、`AppModel`、`AzathothsWhisperApp`（選單＋Window）、`LyricsFXViewModel`（新 source 的 switch）、`Localizable.xcstrings`、`Tests/LyricsFX/*`、`Tests/ArtistStyles/*`、`UITests`、`ACCEPTANCE.md`、`xcodegen generate`。不動：元件目錄、既有列、Music 寫入、MB 快取格式。

## 9. 風險與回退
- 可讀性組合不及格→既有曲樣式改變：預先定好的落層、ACCEPTANCE ⚠️、不變式例外集合；不及格多到無法接受時停下 /thecure。
- G2／G3 測試時間增加（組合約 +43 個 profile；推測 +50 % 左右）：接受；量測寫進附錄。
- 署名待補元件 178 首在補元件計劃完成前一直擋住閘門：這是刻意的（母計劃 composed 100 %），不以例外繞過。
- 使用者處理量：137＋7 位歌手，預估逐位 0.5–2 分鐘（推測）；批次只開給全合格的 91 位。
- 回退：使用者層是獨立 case；決定可逐位清除；檢查畫面是獨立視窗。

## 10. 已收斂（/thecure，2026-10-28，見附錄 C；使用者 2026-10-28 確認）
1. **署名 4 團（178 首）**：另立並簽字「署名團補元件」計劃；⑧ 照實另欄列出「署名待補元件」，**計入 G-COMP、擋住閘門通過**，補件完成後自動歸零。不提供替換署名樣式、不用通用零件。
2. **範圍**：全曲庫為準，並列有詞子集。
3. **手動查 MB 候選**：**本計劃不提供**（⑥b §3 非目標、§9-2 預設不做是既定事項）。ambiguous／noAlbumMatch 的歌手用「指定樣式」或「身分不認、照目前樣式」處理。使用者若要改變 ⑥b 既定，須另行明確簽字；簽字後才加「只限 ambiguous 與 noAlbumMatch、按一次查一次、≤ 9 請求、不 browse、不背景」的例外（§4.4 設計保留），並同步修訂 ⑥b §1-3、§3、§9-2。notFound 即使開放也不給按鈕（同名同查法重送仍無候選）。

## 附錄 A 量測程式
- scratchpad `gate/`：`readlib2.js`（JXA 唯讀讀 persistentID、artist、genre、lyrics）、`main.swift`＋`extra.swift`（逐首判定、計數、組合配對）、`stubs.swift`（`TrackMatcher.exactKey` 照抄、兩個透明度函式）、`files12.txt`（編進來的 app 原始碼清單）。`swiftc -O -swift-version 6`。輸出只有計數。曲庫 JSON（含歌詞）用完即刪。

## 附錄 B Codex 評審與辯論紀錄

### R1（2026-10-28）處置
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| 1 | 阻斷 | 白名單有選擇器不等於有 API；現有兩個方法都只回兩欄 | **採納**：新 `libraryTrackSnapshot()`，T0 列出全部替身；§2.1 改寫 |
| 2 | 阻斷 | 打開歌手時重查 MB 違反「每位只查一次」 | **部分採納**：⑥b §1-3 原文是「不主動重查」，我解讀為「不自動」；但 ⑥b §9-2 把「手動重查」列為未決且預設不做 → 改為按鈕才查、列 §10-3 待拍板；不開放時只剩指定樣式／照目前（回餵 R2） |
| 3 | 阻斷 | 「0 差異」與可讀性拒絕落層矛盾 | **採納**：§4.7 雙層不變式 |
| 4 | 高 | 拒絕組合沒有可追溯原因 | **採納**：`Explanation.trace` |
| 5 | 高 | 決定的撞鍵沒有生命週期，resolver 只拿單一字串 | **修改採納**：決定存寫法集合，resolve 當下用既有寫法家族規則＋MB 存檔 collision 判斷，單一字串即可判；不另建 reconciliation 流程 |
| 6 | 高 | 沒有變更／清除 | **採納** |
| 7 | 高 | 候選請求預算可超過 12 | **採納**：不 browse、> 8 不列、最多 9 請求；選定後不再查（lookup 已帶 genres，計劃原寫「再 lookup genres」是錯的） |
| 8 | 中 | `.jpop` 無法說明以哪個變體合格 | **部分採納**：`jpop` 稽核鍵定義為三變體全部已稽核（每次播放可抽任一變體），不記本曲變體；寫進 §4.6（回餵 R2） |
| 9 | 中 | 掃描缺取消、一致性；「讓出佇列」無機制 | **修改採納**：單一掃描、取代、取消、進度、時間戳、T0 量 p95／最壞；「讓出」的機制＝每次呼叫是序列佇列上獨立工作，`nowPlaying` 最多等一個工作（⑥b 同模式已在場核對），不另建排程 |
| 10 | 中 | G-SRC 只驗表格有列 | **採納**：可判讀＋可追溯，noMatch 要原因文字 |
| 11 | 中 | fixture 放 production 太重、會漂移 | **採納**：production 只放版本化 `AuditedStyleKeys`，測試端生成並斷言相等 |
| 12 | 低 | 掃描時間與即時重算語意 | **採納**：兩個時間分開＋「需重新掃描確認」 |
| §10-1 | — | Codex 選 (b) 替換署名樣式 | 待 R2：與 ⑦ §1-1「通用零件樂團表的團一個都不給」可能衝突（回餵 R2） |
| §10-2 | — | Codex 選全曲庫 | 與預設一致 |

### R2（2026-10-28）——R1 爭議條目的判定
| R1 | Codex R2 判定 | 處置 |
|---|---|---|
| 2 | 部分成立：解讀可成立，但 ⑥b §3 也把手動重查介面列為非目標，拍板「可」前不得當已授權 | **採納**：§10-3 維持待拍板；拍板「可」時在 ⑥b §1-3 加註例外（按鈕觸發、一次按＝一次查） |
| 5 | 部分成立：`isVariant` 是 private，不能直接重用 | **採納**：抽共用判斷式；撞鍵在記憶體內用 `reconcilingLibrary` 算（同 V02-2） |
| 8 | 成立 | 結案 |
| 9 | 部分成立：「不預排多個工作、取消後不再排」要寫成可測 DoD | **採納**：§4.5-3、T7（同 V02-5） |
| 其餘 | 成立 | 結案 |

### R2 新意見
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| V02-1 | 阻斷 | `artistTracks` 只回 album／lyrics，無法逐首回填歌詞判定 | **採納**：新 `artistLyrics(artist:)` 回 persistentID＋lyrics，以 persistentID join |
| V02-2 | 高 | 寫法家族判斷式不可共用 | **採納**（同 R1-5） |
| V02-3 | 高 | 稽核鍵用裸列 id，與帶 layer 的 key 對不上 | **採納**：key 結構化並兼作稽核鍵 |
| V02-4 | 高 | 基線「G-SRC 0 缺」與「功能不存在」矛盾 | **採納**：現況 12,271 首全缺，功能裝上後應為 0 |
| V02-5 | 中 | 取代掃描不等於停止 AE，舊結果可能覆蓋 | **採納**：generation token、一次一個工作 |
| V02-6 | 中 | 拒絕決策表的 production 格式未定 | **採納**：`ReadabilityPolicy` audited／rejected 互斥、版本化 |
| V02-7 | 中 | 署名替換若重用 `.style` 會帶回通用元件 | **採納**：`.style` 只給非樂團表歌手；不做署名替換 |
| V02-8 | 低 | 逐原始寫法讀會重複，與正規化鍵不一致 | **部分採納**：以正規化鍵分組，但組內每種原始寫法仍各查一次——`whose artist == X` 是原始字串比對，只查一種會漏曲（⑥b 附錄 E T4 實例）；以 persistentID 去重解決重複（回餵 R3） |

### §10-1 辯論
- R1：Codex 選 (b)；我方新證據（⑦ §1-1）回餵 R2。
- R2：Codex 讀 ⑦ §1-1 後改判 (a)：通用列會讓署名團播通用元件、繞過該決定；曲風列對四團無語義相符者（Rammstein 最多 generic metal；Chemical Brothers／Fatboy Slim 無 big beat／electro；Aphex Twin 無 IDM／ambient）。證據方（⑦ §1-1＋現有列清單）勝 → **建議 (a)**；仍屬使用者拍板（範圍與例外的價值判斷）。

### R3（2026-10-28）處置
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| 1 | 低 | V02-8 部分採納成立（client 以 `NSPredicate(\"artist == %@\")` 比原始字串） | 結案；T7 加「兩種寫法查回同一 persistentID」去重測試 |
| 2 | 阻斷 | 掃描在記憶體算撞鍵、播放沿用 MB 存檔 collision → 報表與播放可不一致 | **改設計（我方新方案，回餵 R4）**：決定存檔鍵改為寫法家族（`spellingFamily`），異名寫法不同鍵、決定存檔內不可能撞鍵；拿掉記憶體撞鍵與 collision 判斷，報表與播放用同一查法 |
| 3 | 阻斷 | `.userStyle(rowID)` 不會被測試端生成進 audited，指定樣式後 G-READ 仍不合格 | **修改採納**：新增不分層的 `auditKey` 投影，`.userStyle(r)` 與單列命中都投影成 `.rows([r])`；測試守「每個可選 `.style` 必在 audited」 |
| 4 | 高 | 掃描失敗／不完整可能被當成完整結果而誤報達標 | **採納**：新方法回 `Result`、persistentID 聯集核對、未完成不發布 |
| 5 | 高 | §10 未拍板卻寫進最終驗收 | **採納**：§7-4 改條件式，拍板前不得宣告通過 |
| 6 | 中 | 署名／J-Pop 沒有 MB 狀態會讓 G-SRC 永遠不合格 | **採納**：「不適用（優先層）」為合格狀態值 |

### R4（2026-10-28）處置——收斂
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| A-1 | 阻斷 | 鍵不撞≠一位歌手只處理一次：`The Beatles`／`Beatles` 是兩個寫法家族、同一 MB 鍵 | **採納**：同 normalizedArtist 的家族並排、明示勾選「一併套用」；現況曲庫 0 位受影響（⑥b §2） |
| A-2 | 高 | 同名異人連寫法家族都相同，`.identity` 會錯套 | **修改採納**：寫成已知限制（artist 字串是全 app 唯一身分依據）；≥ 2 位候選各對到不同曲庫專輯時停用 `.identity`；真正分開屬專輯指定層（非目標） |
| A-3 | 高 | 拿掉撞鍵判斷會改變 MB 防誤套語意 | **採納（澄清）**：只在決定層拿掉；MB 存檔撞鍵偵測完全不動；同鍵其他家族照 MB 狀態判定 |
| B-1 | — | auditKey 不分層投影：讀碼確認 `compose(rows:)`、`isComposable`、VM `sessionRecipe` 都與層無關 | **結案**；T1 加跨層等價測試 |

收斂判定：R4 剩餘意見全數採納 Codex 建議，無我方新證據需再回餵；未決只剩 §10 三項（價值判斷／範圍，交使用者拍板）。

### 辯論摘要（供後續評審防輪回）
- 4 輪共 30 條＋§10 兩個立場：採納 21、修改採納 5、部分採納 3（R1-2 → §10-3 待拍板；R1-8 J-Pop 鍵與 V02-8 逐寫法查詢，下一輪 Codex 判我方成立）、無問題結案 1（B-1）。
- 我方勝（證據）：R1-8（三變體每次都可能抽到）、V02-8（`whose` 原始字串比對）。Codex 勝：§10-1 由 (b) 改 (a)（⑦ §1-1 是 Codex 讀後改判，但證據由我方提出）、R3-2→R4 A-1（我方「鍵不撞」只證明字典唯一，不證明一位歌手只處理一次）。

## 附錄 C /thecure §10 收斂（2026-10-28，Codex 2 輪）
| # | 我方原判斷 | Codex | 勝方 | 依據 |
|---|---|---|---|---|
| 1 | (a)，例外另欄、不擋達標 | (a) 對，但「不擋達標」違反母計劃 composed 100 % | Codex | 母計劃 §2 閘門定義是使用者已拍板，例外不得稀釋 |
| 2 | 全曲庫＋並列有詞 | 正確 | 一致 | 無詞曲寫詞後即顯示特效；430 首素面無詞曲不能延後 |
| 3 | 開放限定版手動查 MB（ambiguous＋noAlbumMatch 98 位／969 首，其中素面 268 首／27 位受益） | 推翻 ⑥b 既定，須使用者另行簽字 | Codex | ⑥b `2026-10-24-lyrics-fx-musicbrainz.md:52` §3 非目標「手動重查的介面」＋§9-2 預設不做 |
- 整體確認（第 2 輪）：異議 3 條全採納——G-COMP 基線改 572 首（含署名待補 178 首子集）、寫明依賴順序（工具完成≠閘門通過）、手動 MB 相關段落全部標不做；另加 T0 全庫掃描總耗時停損線。
- Codex 最擔心：為了讓畫面顯示「達標」而把尚未解決的缺口列成不擋的例外；以及以閘門壓力默默擴張 MB 網路行為。最容易失敗的一步：T0／T7 逐歌手歌詞回填掃描（單次合格但累積太慢、掃描一直未完成）。

