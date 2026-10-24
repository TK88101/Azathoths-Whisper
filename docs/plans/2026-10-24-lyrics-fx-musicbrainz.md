# 歌詞特效 ⑥b：MusicBrainz 歌手曲風（計劃 v1.0 定稿）

狀態：**v1.0 定稿**（使用者 2026-10-24「定稿」）（R1、R2 見附錄 B、C；使用者 2026-10-24 選 §9-1 **B**＝本計劃一併擴充曲風列，新增 §4.7；R3 見附錄 D，3 輪後收斂；使用者已審閱）。母計劃 docs/plans/2026-10-19-lyrics-fx-style-coverage.md（⑥ 分類層）；⑥a 已合 main（06fc417、fb7234c）。預定分支 `wip/lyrics-fx-musicbrainz`（自 main fb7234c）。

## 0. 複述
- 曲庫裡不在樂團表、不是日文歌的歌手，向 MusicBrainz（MB）查一次「這位歌手是誰、什麼曲風」，結果存在 app 裡；之後依 MB 曲風決定樣式，Apple 曲風退為下一層。
- 完成標準＝§7 驗收。

## 1. 使用者決定（既定前提，不重議）
1. 日文歌一律 J-Pop，不查 MB（2026-10-22；⑥a）。
2. 外送只有**歌手名＋專輯名**（2026-10-24 確認）；User-Agent＝`AzathothsWhisper/<MARKETING_VERSION> ( https://github.com/TK88101/Azathoths-Whisper )`，不露 email。
3. 每位歌手只查一次；之後只補查新歌手；**不主動重查**（2026-10-24）。
4. 存本機 `~/Library/Application Support/com.ibridgezhao.azathothswhisper/`，不放 Caches；重啟、一般覆蓋安裝不丟（刪除 Application Support 或用清理工具連資料移除時不保證，丟了就再背景查一輪）。iCloud 等路線圖最後一步再一起搬（2026-10-24）。
5. sandbox 不在本計劃（2026-10-24「先不用了」）。
6. 優先順（母計劃 §2，2026-10-19 Codex 3 輪收斂）：署名樂團表 > 專輯指定 > 樂團指定 > 驗證過的自動分類（MB）> 同歌手曲庫共識 > Apple 曲風 > 通用。
7. **範圍 B**（2026-10-24）：本計劃一併擴充曲風列（§4.7）。

## 2. 事實（已核）
- **MB 規則**（官方文件 2026-10-24 讀取：MusicBrainz_API、Rate_Limiting、Search、Genre）：讀取不需 API key；平均每 IP 每秒 1 次，超過一律 503；User-Agent 須含聯絡方式（網址可）；空白或通用 UA 列為 anonymous 另行限流；`fmt=json`；搜尋 `limit` 1–100；`inc=genres`＝標籤中屬於曲風清單者；browse release-group 每頁最多 100。Retry-After：文件未載。**資料授權**（About/Data_License、MusicBrainz_Database，2026-10-24 讀取）：歌手名、別名、MBID、release-group 標題與 ID、曲風清單本身＝core data（CC0）；「哪些曲風／標籤掛在哪位歌手上」＝supplementary data（CC BY-NC-SA 3.0：非商用、須註明 MusicBrainz、衍生物同授權）。本 app 非商用、存檔只在本機不散布；需在 About 註明來源（T8）。
- **曲庫**（2026-10-24 唯讀掃描，osascript）：12,271 首／491 歌手。樂團表命中 5,337 首；日文歌手（有詞的曲中日文歌過半）193 首；**要查 416 位、6,741 首**。
- **探查**（2026-10-24，照 §1-2 外送；規則：名字正規化後與 MB 名或別名完全一致的候選取前 3，逐一比對曲庫專輯名與該歌手的 release-group；恰一個候選比對到專輯＝驗證）：

| 結果 | 歌手 | 曲 | 占要查的曲 |
|---|---|---|---|
| 驗證＋有曲風 | 260 | 5,696 | 84.5 % |
| 驗證＋無曲風無標籤 | 42 | 471 | 7.0 % |
| 驗證＋只有標籤 | 5 | 58 | 0.9 % |
| 唯一候選但專輯對不上 | 48 | 237 | 3.5 % |
| 多個候選、都對不上 | 22 | 91 | 1.3 % |
| 多個候選都對得上 | 1 | 12 | 0.2 % |
| 查無 | 38 | 176 | 2.6 % |

  請求數 ≈ 1,000、耗時約 25 分鐘；逾時 3 次（重試後全數成功）。
- **身分門檻的影響**（同一份探查）：307 位驗證者中，比對到 ≥ 2 張專輯 74 位（3,668 首）、恰 1 張 233 位（2,557 首）；恰 1 張且 MB 只有這一位同名者 168 位（1,812 首），同名者不只一位 65 位（745 首）。完全同名候選達探查上限 3 個的 63 位（其中 50 位仍驗證，1,221 首）。
- **名字撞鍵**：整庫 491 個寫法正規化後撞鍵 8 組，全是同一歌手的大小寫差異（`LINKIN PARK`／`Linkin Park`、`Blink-182`／`blink-182`…）。
- **曲風分佈**（驗證者每人前 3 個 MB 曲風，按曲數加權）：metal 1,151、black metal 1,052、alternative rock 1,033、melodic death metal 794、death metal 694、gothic metal 682、rock 550、symphonic metal 450、electronic 426、metalcore 372、folk metal 356、heavy metal 346、gothic rock 333……（全表在探查輸出，scratchpad，不進 repo）。
- **只用現有兩條曲風列模擬**（黑金屬、交響；`SongProfileResolver.keywordRows`）：要查的 6,741 首中 素面→有樣式 1,060、維持有樣式 1,185、維持素面 4,391；MB 曲風碰不到這兩列但 Apple 曲風碰得到 105（見 §4.3 落層規則，這 105 首維持原樣）。
- **元件目錄的標籤覆蓋**（`LyricsFXCatalog.swift` 179 個元件，逐槽列標籤）：電子類（electro／techno／house／bigbeat）缺配色或進場、`industrial` 沒有任何元件、`grind`／`melodeath` 只有單一槽——這些標籤單獨成列組不出六槽（`Composer.compose` 任一必選槽無候選＝mono）。folk／viking 在樂團表沒有代表團。
- **擴充後模擬**（§4.7 草案 17 列＋既有 2 列；以子字串近似既有關鍵字規則，未跑 `PlayableSpace`，日文曲風名未翻譯）：要查的 6,741 首中 MB 定樣式 77.2 %、Apple 定樣式 11.7 %、仍素面 11.1 %（experimental 164、electronic 142、ambient 118、industrial 82、art pop 96…）。
- **程式現況**：`SongProfileResolver.resolve(artist:genre:lyrics:)`（`Services/Lyrics/SongProfileResolver.swift:190`）＝樂團表 → 歌詞未知 pending → J-Pop → genre nil pending → 曲風列 → noMatch。唯一呼叫端 `LyricsFXViewModel.reconcileRecipe`（`Features/LyricsFX/LyricsFXViewModel.swift:221`）；定格後只在跨 J-Pop 邊界時重組（`shouldCompose`）。
- **讀曲庫**：`MusicAppleEventsClient` 已有 `tracks`（app）與 `artist`、`album`、`lyrics`、`genre`（track）的唯讀選擇器（`Tests/Services/MusicSelectorAllowListTests.swift:19-23`），不需新選擇器；但 `MusicControlling` **沒有**整庫讀取的公開方法（`tracks` 是 client 私有、`trackDetails` 只吃已知 ID）——要新增（T0，R1-1）。所有 AE 走同一條序列佇列，與 `nowPlaying` 共用（`MusicAppleEventsClient.swift:31-35`）。
- **可重用**：`SourceGate`（`Services/Lyrics/Timing/SourceGate.swift`；最小間隔、逾時、熔斷、Retry-After、503 短重試）；`HTTPClient` protocol；`TimingStore` 的落盤慣例（Application Support 子目錄、schemaVersion、atomic、不讀符號連結與超大檔）。
- **GitHub 調研**（2026-10-24 `gh search`）：同類專案少——`metabrainz/genre-matching`（5★，無授權，外部曲風對應實驗）、`charliec111/beetsplug-musicbrainz-genre`（1★，MIT）、`camilleemig/musicbrainz-swift`（0★，MIT）。beets `lastgenre` 以曲風樹把細分曲風歸大類（`beetsplug/lastgenre`），可作 §9-1 選項 B 的參考。不引入依賴（唯一套件仍是 SwiftSoup）。

## 3. 目標與非目標
目標：416 位要查的歌手各查一次並存檔；驗證過的歌手依 MB 曲風走曲風列；曲風列擴充到曲庫主要系統（§4.7）；新歌手自動補查；離線或 MB 掛掉時照 Apple 曲風顯示。

非目標：
- 為組不出六槽的曲風（電子、industrial、pop、experimental、ambient…）補元件——屬 ⑦ 通用零件。
- 改樂團表、改既有兩列（黑金屬、交響）的關鍵字與軸值。
- 專輯指定／樂團指定（使用者在 app 內指定）與「同歌手曲庫共識」層；identityUnresolved 的處理介面（⑧ 曲庫閘門前要有）。
- 定期或自動重查；手動重查的介面（§9-2）。
- 進度介面（首次批次只在背景跑、只記日誌；§9-3）。
- 通用零件（⑦）；sandbox；iCloud；Python 1.x。

## 4. 設計

### 4.1 誰要查
- 批次來源＝整庫掃描（`tracks` 一次取 artist、album、lyrics 三欄；只讀）。
- 讀法（T0）：`MusicControlling.libraryArtistAlbums()` 回 `[LibraryEntry(artist, album, isJapaneseSong)]`；client 內分批（每批 500 首、各自 AE 逾時、批間讓出佇列給 `nowPlaying`），歌詞只在 client 內判日文、不出 client。批次大小與耗時以 T0 實機量測定（量測前不寫死）。
- 要查＝`normalizedArtist` 不在樂團表，且**至少有一首不是日文歌**（沒有詞的曲算不是日文歌）；逐首播放時仍以該曲歌詞決定 J-Pop（R1-2）。
- 送出的專輯名＝該歌手**含非日文曲**的專輯；去掉 ` - Single`／` - EP` 與括號內的版本字樣（Deluxe、Remaster…）後去重。

### 4.2 身分判定（純函式，真值表測試）
- 搜尋 `artist:"<名>"`（`limit 25`）；名字先做 Lucene phrase 逸出（`"`、`\\`），再另做 URL 編碼（R2-4）。正規化後為空的名字（如 `!!!`）不查，記 unresolved。
- 候選＝`normalizedArtist` 與 MB 名或別名一致者。**超過 8 個＝ambiguous**，不查（不靜默丟後面的，R1-5）。
- 請求預算（R2-5）：每位歌手最多 12 個 MB 請求（1 搜尋＋各候選 lookup＋必要的 browse），用完仍未判定＝ambiguous。
- 每個候選 lookup `inc=genres+release-groups`；release-group 滿 25 筆且還沒比對到時 browse（`limit 100`，最多 3 頁）。
- 判定（真值表，R1-4 改寫）：
  - 恰一個候選比對到曲庫專輯，且（它比對到 ≥ 2 張 **或** 它比對到的那張不是泛用標題）→ **verified**（不論同名者幾位；R2-1）。
  - 嚴格名不同（保留標點、只折疊大小寫／寬度／變音，例：`AC/DC` vs `ACDC`）的候選：視同「多位同名」，同上規則（R2-2）。
  - 泛用標題＝正規化後為空、≤ 3 字，或屬 greatest hits／best of／the best／hits／live／collection／anthology／demo，或等於歌手名（同名專輯）。
  - 其餘 → **unresolved**：`notFound`（無同名候選）／`noAlbumMatch`（含唯一命中是泛用標題）／`ambiguous`（多個比對到、候選 > 8、預算用完）。
- 「推測」：唯一候選但專輯對不上的 48 位多半是曲庫專輯名寫法不同（翻譯名、合輯），也可能是同名別團；不當驗證，留給日後的使用者指定。

### 4.3 落層規則（`SongProfileResolver`）
- 新增證據 `artistGenres: ArtistGenres`：`.unknown`（還沒查）／`.unresolved`／`.verified([String])`；`[String]`＝MB 曲風依票數由高到低、同票依名稱排序，取前 3（R1-7）。
- 順序：樂團表 → 歌詞未知 pending → J-Pop → **MB 曲風逐項比對曲風列**（新 case `.artistGenreRow(SongProfile)`，來源 `.verifiedArtistGenre`，R1-8）→ genre nil pending → Apple 曲風列（`.genreRow`）→ noMatch。
- MB 曲風碰不到任何列、無曲風、unresolved、還沒查：都落到 Apple 曲風（只升不降；§2 的 105 首維持原樣）。
- 比對沿用既有關鍵字規則（`GenreStyleResolver.genre(_:matches:)`），`compose` 改收 `[String]`、逐項比對（不拼成一個字串；R1-7）。Apple 曲風照舊是一項。
- 還沒查**不等**（不回 pending）：MB 慢或離線時不能讓畫面卡在素面等待。
- 定格：MB 結果在播放途中才到，本 session 不重組（B1 §3.7），下次播才生效。`shouldCompose` 不變（新來源不依歌詞）。整合測試：Apple 先定格 → 背景查到 MB → 同 session 不變 → 新 session 套 MB（R1-8）。

### 4.4 存檔（`ArtistStyleStore`）
- `Application Support/com.ibridgezhao.azathothswhisper/ArtistStyles/artists.json`：單檔（416 筆約 100 KB），鍵＝`normalizedArtist`（撞鍵只見於同一歌手的大小寫寫法，§2；合併是預期行為，與樂團表同鍵，R1-10 駁回）；欄位：曲庫原始寫法（集合）、狀態（verified／unresolved＋原因，含 `collision`）、mbid、比對到的 release-group id、MB 曲風原始清單（名＋票數）、查詢時間；檔頭 `schemaVersion` 與摘要計數（verified／unresolved／最後一次網路錯誤類型與時間，R1-15）。
- 撞鍵（R2-3）：新寫法對到既有鍵時，若與已存寫法只差大小寫／寬度／變音＝同一歌手，加入寫法集合、共用結果；否則該鍵改記 `unresolved(collision)`，snapshot 對這兩個寫法都回 `.unresolved`，不覆寫 mbid。
- 版本（R1-9）：沿用 `TimingStore`——舊版可讀則讀、比本版新的不讀不覆寫；不存 `matcherRevision`（判定規則改版要不要重判，到時另立計劃）。
- 沿用 `TimingStore` 的防線：不讀符號連結、上限 1 MiB、壞檔視為空、看不懂的新版本不覆寫、atomic 寫。
- 網路失敗（逾時、5xx、熔斷）**不寫**存檔（下次再查）；notFound／noAlbumMatch／ambiguous 寫入（不重查，§1-3）。

### 4.5 查詢與排程（`MusicBrainzClient`＋`ArtistStyleSync`）
- 讀路徑（R1-6）：`AppModel` 在主執行緒持有不可變的 `ArtistGenresSnapshot`（`[normalizedArtist: ArtistGenres]`）；啟動時由 store 載入，sync 每寫一筆就換一份新 snapshot。VM 同步讀 snapshot，不碰 actor。
- 一個 `SourceGate`：`minimumInterval 1.1 s`、逾時 10 s、熔斷沿用預設；所有 MB 請求的唯一入口；帶 §1-2 的 User-Agent 與 `Accept: application/json`。
- 啟動後背景做：掃曲庫 → 扣掉已存的 → 排隊查；**正在播的歌手插到隊首**。
- 佇列語意（R1-11）：每位歌手 queued → inFlight → persisted；以 `normalizedArtist` 去重；只有 queued 可插隊，inFlight 不取消；掃描失敗＝本次不查、下次啟動再掃；app 退出時取消 queued、inFlight 的結果若已寫檔即保留。
- 單一工作者；每筆查完就寫檔（中斷可續）。
- 日誌只記序號、計數、錯誤類型（CLAUDE.md 脫敏規則：不記歌手名、專輯名）。

### 4.6 接線
- `AppModel` 建 store／sync、持有 snapshot；`LyricsFXViewModel` 只拿一個同步回呼 `artistGenres(normalizedArtist) -> ArtistGenres`（讀 snapshot；feature 不持有服務，架構慣例）。
- About 加來源註明（三語，R2-6）：「曲風資料來自 MusicBrainz，依 CC BY-NC-SA 3.0 授權；本 app 會篩選與排序後使用」，MusicBrainz 與授權條款各附可點擊連結。存檔不分發；日後若有分發此資料的功能，另行確認 NC／SA。

### 4.7 曲風列擴充（範圍 B）
- **規則**（母計劃 §2「列的軸值＝署名代表團平均（記來源）」）：本節**只新增 17 列**；既有黑金屬、交響兩列的關鍵字、標籤、軸值是不變基線（單獨命中時逐位元相同，R3-6）。每列＝關鍵字＋代表團；代表團只從 `bandTable` 以正式名精確查 `BandEntry.profile`，每團恰算一次（`batchOne` 已含原型 28 團，不另加，R3-5）；軸值＝代表團逐軸平均；標籤＝代表團標籤聯集扣掉 `genreRowPrivateTags`＝`emoFamily` ∪ `jpopFamily` ∪ {altmetal, rapmetal, cybermetal, horrormetal, gothmetal, latinmetal}（批 3 私有子標籤；**`.nu` 保留**，R3-1）。不手填任何值。
- 每列的「代表團、軸值、最終標籤」以 snapshot 測試釘住（`GenreRowSnapshotTests`）：日後改樂團表若連帶改到列，測試會紅（例：altindie 帶入 Weezer 的 `.powerpop`、metal* 帶入 Slayer 的 `.death`／`.thrash`，是刻意的）。
- **草案列**（代表團／關鍵字；`*`＝generic，只在沒有其他命中時才用）：

| 列 | 代表團 | 關鍵字 |
|---|---|---|
| melodeath | Arch Enemy | melodic death |
| death | Cannibal Corpse、Fleshgod Apocalypse | death metal、deathcore、grind、brutal death |
| gothic | Type O Negative、Cradle of Filth | gothic、goth rock、darkwave |
| doom | Type O Negative、Burzum | doom、sludge |
| heavypower | Iron Maiden、Nightwish | heavy metal、power metal、speed metal、nwobhm |
| thrash | Slayer、Arch Enemy | thrash、groove metal |
| hardrock | AC/DC、Guns N' Roses | hard rock、glam、heavy rock |
| classicrock | The Beatles、Pink Floyd、Queen | classic rock、blues rock、psychedelic、progressive rock、art rock |
| altindie | Blur、Weezer、Oasis | alternative rock、indie rock、grunge、post-grunge、britpop、indie |
| arena | Coldplay、The Killers | pop rock、piano rock、soft rock、arena rock |
| poppunk | Blink-182、Green Day、Sum 41、Fall Out Boy、Good Charlotte | pop punk、pop-punk |
| punk | Ramones、Sex Pistols、The Offspring、NOFX | punk |
| ska | The Interrupters | ska |
| metalcore | Hatebreed | metalcore、hardcore |
| nu | Korn | nu metal、alternative metal、rap metal、rap rock |
| metal* | Iron Maiden、Slayer | metal |
| rock* | AC/DC、The Beatles | rock |

- **合成規則**（R3-2）：每個 genre 字串各自比對 → 命中的列去重成集合 → 對整個集合一次套 generic 抑制（有任一非 generic 命中就丟掉所有 generic）→ 合成。輸入順序與重複不影響結果。
- **可玩性閘門**（R3-3、R3-4）：
  - 單列：17 列各自 `PlayableSpace` 非 nil、`ReadabilityAudit` 全綠（含日文行）；不過的列刪掉、不手補，交 ⑦。保留／刪除結果寫成版本化決策表（`GenreRowDecisions`，測試讀它）。
  - 組合：以探查輸出產生「曲庫出現過的列組合」fixture（只存列 id，不存 MB 曲風字串或歌手名），另加固定代表組合 black＋death、symphonic＋death、gothic＋doom、altindie＋rock*、metal* 單獨；全部跑 `PlayableSpace`／`ReadabilityAudit`。驗收只保證這份 fixture 內的組合（邊界明寫）。
  - 執行期退路：resolver 在 MB 層合成後若 `PlayableSpace.of(profile)` 為 nil，該層視為沒命中、落到 Apple 層；Apple 層同理落到 noMatch。不會因組合組不出來而卡在素面。
- **影響既有畫面**（記 ACCEPTANCE ⚠️）：①Apple 曲風也走新列——現在因 Apple 曲風而素面的非樂團表歌曲會變成有樣式（不只 MB 驗證的歌手）；②黑金屬／交響歌手若同時命中新列（如 blackened death），合成後的目標值改變。樂團表的團、J-Pop 不受影響（`ExistingBandCandidatesTests` 不變）。
- **使用者在場看**：每個保留的列挑曲庫一首，一次一列，看「像不像」；不像的列可整列拿掉（不調軸值——軸值由代表團決定）。

## 5. 任務清單（每項先紅後綠）
- T0 整庫讀取：`MusicControlling.libraryArtistAlbums()`＋所有替身；client 分批與讓位；實機 spike 量測（12,271 首的總耗時、每批耗時、期間 `nowPlaying` 延遲）。DoD：契約測試綠；量測寫進計劃；選擇器白名單測試不變。**量測不達標（`nowPlaying` 延遲超過 3 s 輪詢的一半）就停下改方案。**
- T1 身分判定純函式＋專輯名正規化：真值表（§2 七類各至少一例、別名命中、`The` 前綴、符號、泛用標題、候選 > 8）。DoD：測試綠。
- T2 `ArtistStyleStore`：往返、壞檔、符號連結、超大檔、新版本不覆寫、網路失敗不寫、撞鍵（同歌手寫法合併／異名記 collision、重啟後 snapshot 不受污染）。DoD：測試綠。
- T3 `MusicBrainzClient`：以 `ScriptedHTTPClient` 驗 URL（含 `"`、`\\`、`+ - : ( )`、純標點名的逸出）、UA、間隔（`SourceGate` 假時鐘）、503、逾時、JSON 解析、每歌手請求預算（自編樣本，不用真資料）。DoD：測試綠。
- T4 `ArtistStyleSync`：要查清單（樂團表排除、全日文歌手排除、混合歌手只送含非日文曲的專輯）、佇列狀態（去重、只有 queued 插隊、inFlight 不取消）、掃描失敗、續跑、取消；snapshot 換新。DoD：測試綠。
- T5 落層規則：`resolve` 新證據的真值表（含「只升不降」、前 3 排序、逐項比對）；VM 整合：同 session 不重組、新 session 套 MB。DoD：測試綠；既有 resolver 測試不變。
- T6 接線＋DEBUG 預覽注入（UI 測試用假 store）。DoD：`LyricsFXUITests` 新增一條（MB 曲風＝black metal、Apple 曲風＝Rock → 黑金屬樣式）。
- T6b 曲風列（§4.7）：`mean(of:)` 改查 `bandTable`；17 列；`genreRowPrivateTags`；`GenreRowSnapshotTests`（逐列代表團、軸值、標籤）；合成真值表（順序、重複、generic＋specific、一字串多列、Apple 單一 genre）；組合 fixture；`GenreRowPlayableTests` 與 `ReadabilityAudit.profiles` 用同一份「單列＋組合」集合；resolver 的不可玩退路。DoD：`GenreRowDecisions` 定案；黑金屬、交響單獨命中逐位元不變；既有團候選測試不變。
- T7 ACCEPTANCE 新增 I-66；`no_playback_gate.sh` 綠；選擇器白名單測試不變。
- T8 About 來源註明（三語 xcstrings、兩個連結）。DoD：字串齊、About 顯示、連結可點。

## 6. 測試策略
- 單元：T1–T5。整合：sync＋store＋snapshot＋假 MB（`ScriptedHTTPClient`）跑完一份 10 位歌手的小曲庫，並驗下一 session 生效。契約：T0 讀取（替身與真 client 同形）。E2E：T6。實機量測：T0。
- 全量單元＋`coverage_gate.sh`（新檔在 Services/，須 ≥ 80 %）。
- 不在測試裡打真的 MB；真機驗證交使用者在場。

## 7. 驗收
1. 全量單元綠、coverage ≥ 80 %、`no_playback_gate.sh` 綠。
2. `LyricsFXUITests` 全綠（含 T6）。
3. 首次批次總請求數與耗時寫進計劃；超過 60 分鐘就停下檢討預算（R2-5）。
4. I-66 驗收清單（R3-7）：最終保留的每列各一首、至少一首「只有 Apple 曲風命中新列」、一首「只有 generic 命中」、一首「MB 多列合成」、每個被刪的列／組合各一首確認落到預期退路；逐首記曲目、命中列、是否 composed、使用者接受或刪除。
5. 使用者在場：①首次啟動後背景查完（存檔摘要計數）；②挑一位「Apple 曲風是 Rock、MB 是 black metal」的歌手播放，第二次播是黑金屬樣式；③重啟 app 不再查已查過的歌手（日誌）。

## 8. 風險
- MB 改限流規則（文件明言可隨時改）→ 熔斷＋下次啟動續查。
- 首次批次 25 分鐘內同時有 LRCLIB 等請求：各自的 gate，互不影響（不同主機）。
- 寫入存檔與讀取並行：store 為 actor。

## 9. 待拍板
1. ~~範圍~~：使用者 2026-10-24 選 **B**（§1-7）。
2. 手動重查：本計劃不做（預設）／Settings 加一顆「重新查詢曲風」。
3. 首次批次進度：只記日誌（預設）／Settings 顯示「已查 N／M」。

## 附錄 B Codex R1（2026-10-24）處置
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| 1 | 阻斷 | 沒有整庫讀取的公開 API | 採納：T0 |
| 2 | 阻斷 | 「日文過半就不查」與逐首 J-Pop 不一致 | 採納：至少一首非日文就查，只送含非日文曲的專輯 |
| 3 | 高 | 整庫讀歌詞的 AE 量與 `nowPlaying` 搶佇列 | 採納：分批讓位＋T0 實機量測＋停損線 |
| 4 | 高 | 一張專輯命中不足以確認；建議 ≥ 2 張或非泛用標題 | 改寫：一律 ≥ 2 張會丟 233 位／2,557 首（要查曲目的 38 %）；只在 MB 有多位同名者時加嚴（≥ 2 張或非泛用標題），唯一同名者 1 張即可 |
| 5 | 高 | 只取前 3 個候選依賴排序 | 採納：limit 25、> 8 個＝ambiguous |
| 6 | 高 | actor 不能穿進同步 resolver | 採納：主執行緒不可變 snapshot |
| 7 | 高 | 拼字串比對會被低票標籤觸發、順序不定 | 採納：票數排序取前 3、逐項比對 |
| 8 | 高 | MB 與 Apple 同為 genreRow，難測 | 採納：新 case／來源＋session 邊界整合測試 |
| 9 | 中 | matcherRevision 語意未定 | 採納：刪除；schema 規則沿用 TimingStore |
| 10 | 中 | 正規化鍵可能讓不同歌手撞鍵 | 駁回：整庫 8 組撞鍵全是同一歌手的大小寫寫法，合併是預期（樂團表同鍵）；回餵 R2 |
| 11 | 中 | 插隊語意未定 | 採納：queued／inFlight／persisted |
| 12 | 中 | 授權 TBD | 採納：已讀；tags 為 CC BY-NC-SA 3.0 → About 註明（T8） |
| 13 | 中 | 測試缺系統邊界 | 採納：契約、整合、實機量測 |
| 14 | 低 | 「重裝不丟」寫太滿 | 採納：§1-4 改寫 |
| 15 | 低 | 無持久狀態可判斷 | 採納：存檔檔頭摘要計數 |
範圍 §9-1：Codex 支持 A（曲風列擴充另立 ⑥c）。

## 附錄 C Codex R2（2026-10-24）處置——R2 後收斂
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| 1 | 高 | 不接受 R1-4 改寫：唯一同名者＋泛用單張不足以確認 | 採納（Codex 勝：「唯一候選」只代表這次沒搜到別人）：單張命中一律要非泛用標題 |
| 2 | 高 | 「同名」用的是寬鬆正規化（`AC/DC`＝`ACDC`、`!!!`＝空鍵） | 採納：嚴格名不同者走加嚴規則；空鍵不查 |
| 3 | 高 | 不接受 R1-10 駁回：一次掃描不能證明以後不撞鍵 | 採納（Codex 勝：我的證據只涵蓋現況）：存原始寫法，異名撞鍵記 collision、不覆寫 |
| 4 | 中 | Lucene 查詢未逸出 | 採納 |
| 5 | 中 | 候選擴到 8 個後最壞每位 32 請求、可超過 4 小時 | 採納：每位 12 請求預算；實測總耗時、> 60 分鐘停下 |
| 6 | 中 | 署名缺授權連結與「經修改」說明 | 採納 |

## 附錄 D Codex R3（2026-10-24，§4.7）處置——3 輪後收斂
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| 1 | 阻斷 | 「扣 nuFamily」會把 Korn 的 `.nu` 扣光 | 採納：明定 `genreRowPrivateTags`，保留 `.nu` |
| 2 | 高 | 多列合成的去重、generic 抑制時機未定 | 採納：逐字串比對→列去重→整體 generic 抑制；順序無關 |
| 3 | 高 | 只審單列，沒審多列組合 | 採納：曲庫組合 fixture（只存列 id）＋固定代表組合 |
| 4 | 高 | 組合失敗不能靠刪列；compose 會靜默 mono | 採納：版本化決策表＋執行期「不可玩就落下一層」 |
| 5 | 中 | `bandTable`＋原型 28 團會重複 | 採納：只查 `bandTable`、每團一次 |
| 6 | 中 | 既有兩列可能被重構連帶改掉 | 採納：既有兩列為不變基線 |
| 7 | 中 | 驗收沒涵蓋 Apple-only、generic、組合、退路 | 採納：I-66 驗收清單 |

## 附錄 E 實作記錄（2026-10-24）
- **T0 量測（JXA／osascript，唯讀，12,271 首）**：整庫一次讀 artist 109 ms（161 KB）、album 35 ms（277 KB）、**lyrics 10,304 ms（9.7 MB）**——單一 AE 占住序列佇列 10 s，超過 §5 T0 停損線（1.5 s）→ 停下改方案。試 `tracks 1 thru N` 範圍讀：AppleScript 可（500 首約 0.3 s），但 ScriptingBridge 沒有範圍 specifier；JXA `whose index` 型別轉換失敗（-1700）。改用既有的 `whose artist == X` 模式：曲數最多的要查歌手（223 首）讀 lyrics 32–111 ms（129 KB）。
- **§4.1 讀法改為（不動驗收）**：`libraryArtistAlbums()`＝整庫 artist、album 兩欄（同一個 run，約 0.15 s）；`artistTracks(artist:)`＝`whose artist == X` 讀 album、lyrics 兩欄，sync 在查該歌手的 MB 前才呼叫、只對還沒存檔的歌手。每次占住佇列 ≤ 約 0.15 s；416 位合計約 20–40 s，分散在 25 分鐘的 MB 查詢之間。真 client 的實機耗時在使用者在場時以日誌核對（單元測試宿主不碰真 Music，D11）。
- **T1**：紅燈＝`ArtistIdentity` 未定義（編譯失敗）→ 綠 15 條（含參數化）。
- **T2 紅燈步驟漏做**：測試與實作寫完才一起跑，第一次即綠（28 條＝T1＋T2）。如實記錄，未補做。`ArtistStyleBook`（不可變值，兼作 snapshot）＋`ArtistStyleStore`（單檔、防線同 TimingStore）。
- **T3**：紅燈＝`MusicBrainzClient` 未定義 → 綠 11 條。修正測試一處：`SourceGate` 換算 Duration 讓間隔量到 1.101 s，期望改為 ±10 ms（測試寫死了浮點值，非放寬行為）。
- **T0 介面**：`MusicControlling` 加 `libraryArtistAlbums()`、`artistTracks(artist:)`（只用既有選擇器 `tracks`／`artist`／`album`／`lyrics`）；真 client 各帶 1.5 s AE 預算；5 個替身補齊。行為由 T4 驗（單元宿主不碰真 Music）。
- **T4**：紅燈＝`ArtistStyleSync` 未定義 → 第一次綠 11／12：大小寫變體只用一種寫法讀歌詞，替身讀不到另一種 → 改為同鍵每種寫法都讀再合併 → 綠 12 條。
- **T5／T6b**：紅燈＝新 API 未定義（`artistGenreRow`、`genreRowPrivateTags`、`isComposable`、`KeywordRow.id／representatives` 等）→ 綠 27 條。17 列各自可玩、曲庫 47 種組合（含固定代表組合）全部可玩 → **`GenreRowDecisions` 無刪除列**（決策表即 `expandedRows` 全部保留）。`Composer.isComposable` 為 production 定義，與測試側 `PlayableSpace` 對全部樂團與列結論一致（`isComposableAgreesWithThePlayableSpace`）。既有 `SongProfileResolverTests` 一處只改 `KeywordRow` 初始化簽名（加 id、representatives），斷言不動。
- **T6 紅燈步驟漏做**：VM `artistGenres` 回呼、`AppModel` 接線（`startArtistStyles`、換歌插隊、`stop` 取消）與其測試一起寫，第一次跑即綠。正式組裝改為**所有自動化測試（單元與 UI，`isAutomatedTest`）都不查 MB**——UI 測試走 `AppUITestCase` 的 "0" 也會進正式組裝。E2E `testAnArtistVerifiedAsBlackMetalGetsBlackMetalEvenIfAppleSaysRock`（DEBUG `AZW_LYRICSFX_PREVIEW_ARTIST_GENRES` 注入），待使用者在場跑。
- **T8**：`about_genre_credit` 三語＋MusicBrainz、授權兩個連結；`AppInfoTests` 驗連結與三語 bundle 字串。
- **全量單元**（skip 已知 flaky `overlappingLoad…()`，-enableCodeCoverage）：1,676 條／207 suite，紅 1＝`RecipeGoldenTests`——它把所有曲風列算進「既有」摘要，新列必然改變摘要。修：範圍改回 `bandTable`＋`originalRows`，**錄好的摘要值 `2f80…` 不動**→ 綠（＝既有 61 團與兩條舊列的配方逐行不變）。其餘 1,675 條綠。
- **coverage_gate**：Services+Infra 96.2 %；但豁免檔 `MusicAppleEventsClient.swift` 可執行行數 408→468 超預算 410 → 失敗。/thecure（Codex 1 輪，支持調預算、反對為過閘門重構既有 AE 程式碼）→ 使用者 2026-10-24 批准 **`EXEMPT_LINE_BUDGET` 410→470**。之後 gate 綠；`Scripts/test_coverage_gate.py` 寫死的 411／410 跟著改成 471／470（仍驗「超預算即失敗」），Scripts 333 條綠。`no_playback_gate.sh` 綠。

## 附錄 F simcodex（2026-10-24，2 輪，第 2 輪提前結束）
| 輪 | 來源 | 意見 | 處置 |
|---|---|---|---|
| 1 | security-reviewer | 無 CRITICAL／HIGH；LOW：搜尋回的 id 進下一個路徑、TOCTOU、`outgoingAlbums` 命名誤導（專輯名其實只在本機比對、不送出）、票數 1e300 會 trap | 採納 3 條（UUID 驗證、改名 `albumsToCompare`／`distinctAlbums`、`Int(exactly:)`）；TOCTOU 延後（與 `TimingStore` 同級，需本機寫入權） |
| 1 | simplify 效率 P1 | 曲風比對每個關鍵字重做正規化（~3 ms／次、換歌約 10 ms 主執行緒） | 採納：`GenreStyleResolver.NormalizedGenre`，每個 genre 只正規化一次 |
| 1 | simplify 效率 P1 | 背景同步與啟動第一輪播放讀取搶 AE 佇列 | 採納：閃屏結束才 `startArtistStyles()` |
| 1 | simplify 簡化／層級 P1 | 撞鍵規則分散在 Sync 與 Book 四處 | 採納：`ArtistStyleBook.reconcilingLibrary` 為唯一入口；Record 兩個複製函式合一 |
| 1 | simplify 簡化／層級 P1 | 同名篩選與候選上限在 client 與 `judge` 各寫一次；兩個迴圈 | 採納：`ArtistIdentity.namesakes` 唯一定義；client 單趟＋`spend()` |
| 1 | simplify 簡化／重用 P1 | AE 兩欄讀取樣板重複 | 採納：`readPairs` |
| 1 | simplify 重用 P1 | `spellingFamily` 與 `TrackMatcher.exactKey` 同式 | 採納：直接用 `exactKey`（去掉 private） |
| 1 | simplify 層級 P1 | 樂團表排除、日文過濾寫在 Sync | 採納：`SongProfileResolver.needsArtistGenres`、`ArtistIdentity.albumsToCompare` |
| 1 | simplify 簡化 P1 | 刪 `matchedReleaseGroups` | 駁回：計劃 §4.4 指定存（日後使用者指定歌手用） |
| 1 | simplify 簡化 P1 | 刪 `compose(genre:rows:)` | 駁回：仍有 4 處呼叫（ReadabilityAudit、RecipeGolden、ComposerTests、GenreRowTests） |
| 1 | simplify 重用 P1 | 與 `TimingStore` 共用檔案安全邏輯 | 延後：要改已驗證的 `TimingStore`，超出本 diff |
| 1 | Codex review --base main [P2] | 掃描時發現的撞鍵沒發布到 snapshot | 採納：`prepareQueue` 有變就 publish；新測試 `aCollisionFoundDuringTheScanIsPublishedRightAway` |
| 1 | Codex review [P2] | 存檔上限 `4 << 20` 不是計劃的 1 MiB（它說是 16 MiB，實為 4 MiB） | 採納：改 `1 << 20` |
| 2 | simplify 四角度 | 無 P1；P2：樂團表查詢兩處寫、`prepareQueue` 未先去重、第一個請求的預算寫法 | 採納這 3 條（便宜）；其餘 P2 延後 |
| 2 | Codex review --uncommitted [P2] | 單趟 lookup→browse 可能在看到後面的候選前用光預算 | 駁回（附證據）：要判「已驗證」必須看完每位同名者，兩種順序需要的請求總數相同；新測試 `aLaterNamesakeIsStillInspectedAfterEarlierOnesAreBrowsed`（4 位、前 3 位第一頁滿未中、第 4 位中）＝verified、8 個請求 |

遺留 P2：①`ArtistStyleStore` 與 `TimingStore` 的檔案安全邏輯可抽共用；②讀檔 TOCTOU（`O_NOFOLLOW`＋`fstat`）；③每查完一位就整檔重寫（背景、約 2 s CPU／416 位）；④`ExternalServices` 把 timing 與 artistStyles 的 live／none 收成一處；⑤新增列的第二份配方摘要；⑥`hasRecord`、`genre(_: String?, matches:)` 只剩測試在用；⑦`readPairs` 的 identity closure；⑧`TimingJSON.integer` 可上移；⑨`spellingFamily` 依賴 `TrackMatcher.exactKey`（若時間軸改規則會連帶）。
- **simcodex 後全量單元**（同上 skip，-enableCodeCoverage）：**1,681 條／207 suite 全綠**（3,687 s）；coverage_gate Services+Infra 96.2 %（豁免 453／470 行——`readPairs` 抽出後由 468 降為 453）。

## 附錄 G 使用者在場（2026-10-24）
- #1 `LyricsFXUITests` 17／17 綠（含 `testAnArtistVerifiedAsBlackMetalGetsBlackMetalEvenIfAppleSaysRock` 9.3 s）。
- #2 首次背景查詢（Debug 建置、真連 MB）：15:23 啟動、15:44:54 `remaining=0`，約 22 分鐘（停損 60 分鐘內）；存檔 414 位（278 確認、136 無法確認），3 次 `server503` 未寫、下次補查。曲多的先查，後段 60 位多為 noAlbumMatch／notFound（曲庫只有一兩首、多來自合輯）。重啟：`queued=9`（3 位 503 補查＋全日文歌手只在本機讀歌詞後跳過）、18 s 結束，存檔 418 位（281 確認、137 無法確認），已查者不重查。附帶發現：監看腳本用 zsh 的 `log`（內建指令）讀不到日誌，要用 `/usr/bin/log`。
- #3 逐列看（每列曲庫一首，只命中該列、有詞、非日文、MB 已確認）：death、gothic、doom、hardrock、classicrock、altindie、punk、metalcore、nu、metal*「沒問題」；**heavypower「不像」**（Iron Maiden＋Nightwish 的聯集帶進 symphonic，抽到哥德黑體金字與暗紅光柱，與 gothic 相近）、**rock*「不像」**（Blackmore's Night 的 folk rock 套 AC/DC＋The Beatles）。依 §4.7 整列拿掉、不調軸值：heavy／power metal 改走 metal*；只命中 rock* 的歌回到 Apple 曲風（Apple 寫 Rock 者回到素面，同 ⑥b 前）。melodeath（只與 death 同現）、thrash、arena、poppunk、ska 在曲庫中沒有只命中它們的歌，未單看。
- 拿掉兩列：`expandedRows` 17→15；`GenreRowTests.removedRows` 釘住、組合 fixture 去掉含這兩列的組合；`LyricsFXArtistGenreTests` 的 Apple 曲風由 Rock 改 Alternative Rock（Rock 現在不命中任何列）。
- 拿掉兩列後全量單元（同上 skip）：**1,682 條／207 suite 全綠**（3,641 s）；coverage_gate 96.2 %（豁免 453／470）。
