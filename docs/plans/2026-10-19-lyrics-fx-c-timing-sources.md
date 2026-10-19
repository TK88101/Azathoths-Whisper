# 歌詞特效 C 段：外部時間軸來源接進正式流程（2026-10-19）

**狀態：定稿（使用者 2026-10-19「定稿啊」）。**

基線：`main` eb7addd。母計劃 `docs/plans/2026-10-03-lyrics-fx-mode.md` 附錄 C／C.1／C.2／C.3／C.4。
探針結果：`docs/plans/2026-10-19-lyrics-fx-sync-source-probe.json`（腳本在 session scratchpad，不進 repo）。

## 0. 複述

現在 app 播歌時，除非 Music 欄位本身是 LRC，畫面上的時間全是估算的（`LyricsTimelineBuilder.build`，`Services/Lyrics/LyricsTimelineEstimator.swift:107`）。
C 段把外部時間軸來源接進來：寫入歌詞成功後、以及特效層顯示一首還沒時間軸的歌時，自動依序問
LRCLIB → YouTube Music → Deezer → QQ 音樂 → 酷狗 → 網易雲，**哪一層先給出「配對正確且對得上詞」的時間軸就停**，
只把每行開始時間存進既有的 `TimingStore`（I-09），播放時用 Music 欄位的文字配這份時間。全部免登入、對使用者靜默、不給選來源。

## 1. 目標與非目標

**目標**
- G1 統一的 `TimedLyricsProvider` 介面＋6 個來源 adapter，退路順序固定（§3.5）。
- G2 嚴格曲目比對（§3.3）＋既有對齊門檻（`LRCAligner` 0.8／0.7）；兩關都過才算「答案」。
- G3 每個來源：限流、短逾時、熔斷、Retry-After、回應大小上限；任一來源壞掉只跳過它。
- G4 接上 `TimingStore`：存「找到（行號→開始秒數）」或「查過沒有」；7 天重試照 C.4；詞改了立即重找。
- G5 觸發點照 C.2：寫入成功後（Editor、Batch）＋特效層顯示時補做；per-persistentID 去重、可取消、舊結果不蓋新詞。
- G6 本機診斷（OSLog）：每次查找記來源、結果類別、對齊分數、耗時、HTTP 狀態；不記曲名、歌詞、憑證。
- G7 特效層用上存檔：內嵌 LRC → 存檔（指紋相符）→ 估算；外部結果回來時熱替換。

**非目標**
- Musixmatch、Spotify、YouTube 登入、Google OAuth（2026-10-19 探針：補 0 首或不可行；使用者同意不進鏈）。
- Settings 的來源選擇或開關（使用者 2026-10-18：全開、不給選）。
- 把時間軸寫進 Music 欄位（C.1：欄位只放純文字，1.x 寫入行為不變）。
- 存外部來源的歌詞全文（只存行號與秒數）。
- 酷狗 KRC 逐字時間（存檔只有行級；逐字仍按字數分配）。
- 時間軸資料夾改指向 iCloud Drive（C.1 的後續項）。
- 本機音訊對齊（C.3 列為後續 spike）。
- 1.x Python 版不動。

## 2. 事實與推論

### 2.1 已核事實
- **現況程式碼**
  - `TimingSource` 已有 `embeddedLRC, lrclib, youtubeMusic, deezer, qq, kugou, estimated`（`LyricsTimeline.swift:5`）。
  - `StoredTimingSource` 是其中可存檔的子集，沒有網易雲（`TimingStore.swift:5`）。
  - `TimingStore`、`TimingRecord.merged`、`TimingLookupPolicy`（7 天）都已寫好並單測（ACCEPTANCE I-09：「A1 生產路徑不讀寫，C 段接上」），目前**沒有任何呼叫端**。
  - `LRCAligner.align` 已實作「只借時間」與內插；`matchedStarts`、`interpolated` 是 private（`LRCAligner.swift:47,58`）。
  - 特效層同步建時間軸：`LyricsFXViewModel.timeline(for:)`（`LyricsFXViewModel.swift:151-154`）。世代守衛 `identity=(persistentID, revision)` 已預留給 C 段（同檔 :6-7 註解）。
  - 觸發點：`editor.onSaved`、`batch.onLyricsWritten` 都在 `AppModel.swift:140,172` 接線，兩者都只帶 `(persistentID, text)`。
  - `HTTPClient` 只有 `get` 與 form `post`；`HTTPResponse` 沒有 headers（`Infra/HTTPClient.swift:4-22`）。
  - ATS 目前只對 `darklyrics.com` 開 http 例外（`project.yml:58-62`）。
- **探針（2026-10-19，40 首，免登入，嚴格比對）**：合計 12／40 帶時間軸。
  - 鏈上各層邊際：LRCLIB 0、YT +7、Deezer 0、QQ +1、酷狗 +1、網易雲 +3。
  - 10 首可量對齊（Music 欄位有詞）者，5 首達 0.7；2 首 0.684；1 首 0.31（Live 版不同）。
  - 無 429／403。LRCLIB 兩輪開頭都連續回 503（3 次即熔斷），單獨重測正常。
  - 酷狗搜尋只有 `http://mobilecdn.kugou.com` 能連，https 一律連線失敗。
  - Deezer 進階搜尋語法（`artist:"…" track:"…"`）回空，一般關鍵字可用。
  - YT 匿名 ANDROID_MUSIC 對 7 首只回約 9 行無 `cueRange`；登入網頁版回完整文字也無時間；登入 cookie 走 ANDROID_MUSIC＝HTTP 400。
  - 曲名正規化去掉「(Instrumental)」曾把純音樂配到人聲版（Nightwish）。
- **LRCLIB 文件**（T0 2026-10-19 重讀 `https://lrclib.net/docs`，前端 bundle `index-7ca6a2e5.js` 內的 API Documentation）：
  - User-Agent 要寫 app 名、版本、首頁網址。有寫的話，每個 IP 約 90 次／分；沒寫約 45 次／分。數字不屬於 API 契約，隨時可能改。
  - 要求序列送出，每個請求間隔 200–500 ms，批次掃曲庫時尤其要遵守。
  - 429 必須遵守 `Retry-After`，並加最多 30 % 的隨機抖動；不遵守可能被暫時封鎖。網路邊緣的拒絕回應不一定是 JSON，只能看狀態碼與 `Retry-After`。
  - **503＝`ServerOverloaded`**：伺服器暫時忙，照 `Retry-After` 再試，通常 1 秒。→ 探針那幾次 503 屬此類，原本的推測已由文件證實。
  - 另有可選的應用註冊（`Lrclib-App-Id`，約 180 次／分）。本計劃不註冊（非目標）。
- **酷狗 https**（T0，3 個請求）：`songsearch.kugou.com/song_search_v2` 用 https 回 200，但清單是空的（推測要簽名參數）；`mobilecdn.kugou.com` 與 `msearchcdn.kugou.com` 用 https 都連不上。取歌詞的兩個端點（`krcs`、`lyrics.kugou.com`）在探針中是 https 可用的。
- **LRC 側覆蓋率實測**（T0，探針腳本重抓）：
  - 5 首達標歌：Blackmore's Night 0.618、Smashing Pumpkins 0.900、AC/DC Hells Bells (Live) 0.674、Mystic Circle 0.900、Marduk The Black 0.857 → **全部 ≥ 0.6，不誤殺**。最低的 Blackmore 只比門檻高 0.018，餘裕小。
  - 兩首 Music 側 0.684 未達標的，LRC 側也低（Offspring 0.481、Marduk Seven Angels 0.500），結論一致。

### 2.2 推論（標「推測」）
- ~~推測：LRCLIB 開頭的 503 是服務端短暫過載~~ → T0 已由文件證實（見 §2.1）。設計：503 帶 `Retry-After` 時等候後重試一次，不計入熔斷；連續兩次才算失敗。
- 推測：YT 只回 9 行是授權預覽，與我們的請求格式無關（換三個客戶端版本號結果相同）。→ adapter 照常實作；行數過少的結果會被對齊門檻自然擋下。
- 推測：真實流程裡對齊門檻是主要的把關。觸發點都在「欄位已有詞」之後（C.4），探針那 30 首無詞的情況在 app 裡不會發生。

## 3. 設計

### 3.1 HTTP 擴充（`Infra/HTTPClient.swift`）
- 新增 `send(_ request: HTTPRequest) async throws -> HTTPResponse`：method、headers、body（`Data`）、timeout。
- `HTTPResponse` 加 `headers: [String: String]`（只取 `Retry-After` 等需要的鍵，鍵名小寫正規化）。
- 既有 `get`／`post` 改為在 `send` 之上的薄包裝，行為不變。`MockHTTPClient` 同步擴充。
- 時間軸專用一個 `URLSessionHTTPClient` 實例：ephemeral、**不收不送 cookie**，與 Genius／DarkLyrics 的 session 分開。
- 回應大小上限 2 MiB，在接收中強制（Codex R1 #2）：先看 `Content-Length`，超過即不讀；再用 `URLSession.bytes(for:)` 邊收邊累計，超過就中止並當作 `unparsable`。`HTTPResponse` 保留原始 `Data`，需要文字時才依 charset 解碼。
- 轉址：只允許同主機、https→https；任何降級到 http 或換主機的轉址一律中止（Codex R2 #4）。轉址後的實際請求同樣受「只送三欄、無 cookie」約束（V2 檢查）。

### 3.2 介面（`Services/Lyrics/Timing/`，新資料夾）
```swift
struct TimingQuery: Sendable, Equatable { let artist: String; let title: String; let duration: Double }   // 對外只送這三樣
struct MatchedTrack: Sendable, Equatable { let artist: String; let title: String; let duration: Double? }
enum ProviderOutcome: Sendable, Equatable {
    case timed([LRCLine], matched: MatchedTrack)       // 帶時間的行（只在記憶體）
    case noTiming(NoTimingReason)                       // notFound／mismatch／plainOnly／tooFewLines
}
enum ProviderFailure: Error, Sendable, Equatable {     // 「這次問不到」≠「沒有」
    case rateLimited(retryAfter: TimeInterval?), blocked(status: Int), server(status: Int)
    case transport, timedOut, unparsable, cancelled, circuitOpen
}
protocol TimedLyricsProvider: Sendable {
    var source: StoredTimingSource { get }
    func lookup(_ query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome
}
```
- 每個 adapter 拆成兩半：`*Provider`（組請求、走 `SourceGate`）＋`*ResponseParser`（純函式、吃 JSON 字串、可用 fixture 測）。
- 候選比對一律呼叫 §3.3 的 `TrackMatcher`。

### 3.3 嚴格曲目比對 `TrackMatcher`（純函式）
- **正規化**（探針驗證過的規則）：
  1. `Æ→AE`、`Ø→O`；NFKD 去附加符號；小寫。
  2. 去掉 `(…)`／`[…]`／全形括號註記；去 ` - Live…`／` - Remaster…` 尾綴；去 `feat./ft.` 之後的內容。
  3. 去開頭 `the `；只留字母與數字。
- **曲名**：正規化後相等，或編輯距離 ≤ 1；正規化後 ≤ 4 字元的短曲名只認完全相等（Codex R1 #6）。
- **歌手**：先比整串正規化全名；不中才把候選歌手字串以 `, & / 、` 拆開，任一段符合即可（先比全名是為了 `AC/DC`，Codex R2）。
- **時長**：候選時長差 ≤ 3 s 是**必要條件**；候選沒有時長＝不採用。
- **版本護欄**（取代原「純音樂護欄」；Codex R1 #6、R2、R3）：
  - 正規化前先從兩邊曲名取出括號內容與 ` - ` 尾綴，稱為「標記片段」。
  - **版本關鍵詞**：`live|acoustic|unplugged|demo|remix|mix|edit|version|re-record|instrumental|karaoke|cover|session|take|伴奏`。
  - 一方的標記片段含版本關鍵詞、另一方沒有＝不採用（探針 Nightwish 純音樂配到人聲版即此類）。
  - 兩方都含：把兩邊的片段正規化成詞組，一方是另一方的子集才放行。`Live` 對 `Live - 1991` 放行（探針 AC/DC 對齊 0.829），`Live at Glastonbury` 對 `Live at Reading` 不採用。
  - 忽略：`remaster(ed)` 與緊鄰它的年份、`deluxe`、`explicit`、`feat./ft.`。裸年份不忽略，因為可能代表重錄。
  - 其餘不含版本關鍵詞的括號（翻譯、音譯）忽略。例：網易雲 `Русалка (Rusalka)` 對 Music `Русалка` 放行，是探針實例。
- LRCLIB 多筆時只在候選唯一時採用（母計劃 §2.4 R1-4），不再用 album 消歧：對外不送 album（使用者口令「外部只送 artist／title／duration」）。

### 3.4 對齊與存檔格式
- `LRCAligner` 重構：公開 `anchors(lyrics:lrc:) -> [Double?]` 與 `timeline(lyrics:anchors:duration:source:)`；`align` 改為兩者組合，行為與既有測試不變。
- **外部時間值先驗證**（Codex R1 #8），在 provider 邊界處理：
  - 非有限、負值、超過曲長 + 5 s 的 cue 丟掉。
  - 依時間穩定排序；同一時間的多行保留第一行。
  - 驗證後少於 3 行＝`tooFewLines`。
- **答案**（四項全部成立）：
  1. `TrackMatcher` 通過。
  2. Music 側對齊率 ≥ 0.7（`LRCAligner.alignmentRateThreshold`，不改）。
  3. **LRC 側覆蓋率 ≥ 0.6**：可比對的非空 LRC 行被錨到的比例。
  4. 直接錨點至少 3 個。
  - 比例只算直接、單調、一對一的錨點，不算內插（Codex R1 #6、R2、R3）。
  - 第 3 項用來擋重複副歌錯錨：Music 漏了前段、LRC 有兩段相同副歌時，前向第一個命中會整段錨到前一段；此時 LRC 側覆蓋率掉到門檻下而被拒。
  - 0.6 已在 T0 用探針那 5 首達標歌重算：全部通過，最低 0.618（§2.1）。
  - 對齊演算法維持單調前向第一個命中，不改全域 DP：母計劃 R1-4 定案；探針沒有它誤判的實例；完全相同的重複段落 DP 也一樣分不出來。
- **讀回驗證**（Codex R1 #7）：重建前以當前歌詞的 `lyricTexts.count` 驗證每個 index 在範圍內，並驗證 start 有限、單調不減、≤ 曲長 + 5 s；不合＝當作沒有存檔（不顯示、不覆寫成 found），重新查找。
- **存檔只存已對上的錨點**：`TimingRecord.LineStart(index, start)`，index＝`LyricsLines.lyricTexts` 序號（I-09 既有語義）。讀回時用同一個內插重建，與當場對齊得到的時間軸逐行相同（單測鎖住）。
- **格式升版**：`StoredTimingSource` 加 `.netease`，`TimingSource` 同步加；`TimingStore.schemaVersion` 1 → 2。
  - 理由：舊版 app 讀到 `source: "netease"` 會解碼失敗→判成 `.corrupt`→可被它覆寫（`TimingStore.swift:118-121`）。升版後舊版判 `.unrecognized`，不覆寫。
  - 新版照常讀 v1 檔，寫出一律 v2（`record(expecting:)` 改為接受 1…2）。
- **併發語義**：`TimingStore` 是 actor，只保證同一程序內「讀→合併→寫」不互蓋，不保證跨程序或跨機器（Codex R1 #12）。iCloud 同步資料夾（C.1 後續）開放前另案處理檔案協調。

### 3.5 退路鏈與停止規則 `TimingResolver`（actor）
- **順序**（常數陣列，不可設定）：
  1. 內嵌 LRC（同步、本機，維持 `LyricsTimelineBuilder` 既有行為）
  2. 存檔
  3. LRCLIB → YouTube Music → Deezer → QQ 音樂 → 酷狗 → 網易雲
  4. 估算
- **停止**：第一個給出「答案」的來源→存 `.found(source, anchors)`，後面不問。
- **配錯或對不上詞**（`noTiming` 或對齊率 < 0.7）→換下一層。
- **全部明確回「沒有」**→存 `.notFound`（7 天後重試，C.4）。
- **前置條件**（Codex R1 #5）：artist、title 非空，duration 有限且 > 0。不成立就不連網、不存檔，只記一行 `missingMetadata` 診斷。
- **任一層是 `ProviderFailure`**（被擋、逾時、熔斷中）且沒有任何層給出答案→**不存 `.notFound`**，只在記憶體記退避（沿用 `ArtworkFailureBackoff` 的 5 s→300 s 指數）。理由：服務暫時掛掉不得換來 7 天的「沒有」。
- **去重**：in-flight 表以 persistentID 為鍵，值＝(lyricsHash, Task)。
  - 同 pid 同 hash→併入既有工作，不重發。
  - 同 pid 新 hash→取消舊工作、開新工作。
- **舊結果不蓋新詞**：存檔前比對「該 pid 最新請求的 hash」，不同即丟棄。特效層套用前另以 `identity` 與指紋再驗一次（既有守衛）。
- **介面**（Codex R1 #4）：`func resolve(_ request: TimingRequest, priority: Priority) async -> Resolution`。
  - 同 pid、同 hash 的第二個呼叫者 await 同一個 Task 的結果（加入同一份工作），只發一次網路。
  - `Resolution` 帶 `(persistentID, lyricsHash, timeline 或沒有)`。特效層在自己的 Task 裡 await，回到 MainActor 後以 `identity` 與 `fingerprint` 驗證才套用。
  - 寫入觸發點不需要結果，丟一個不等的 Task 呼叫同一個 `resolve` 即可。
- **佇列與搶占**（Codex R1 #3）：
  - 同一時間只跑一首。
  - `.visible`（特效層正在顯示的那首）到達時，若正在跑的是 `.background` 工作：立刻取消它、放回佇列最前，等 visible 那首跑完再接著跑。取消不寫存檔。
  - 每首查找總時限 20 s，超過即視為 `timedOut`（屬失敗，不存 notFound）。
  - `.background`（Batch 寫入）排隊，上限 500 首，超過丟最舊的待辦；下次播到時由特效層補做。
- **生命週期**（Codex R1 #9）：resolver 由 `AppModel` 持有，提供 `shutdown()`。
  - `AppModel.stop()` 與 App 結束路徑都呼叫它：取消進行中與排隊的工作、喚醒並取消 gate 的等待、取消 HTTP 請求。
  - 之後不發新請求、不寫檔、不回呼。
  - 取消在每個 await 點都要合作檢查。
- **停用開關**（Codex R1 #10，不是 UI）：`defaults write com.ibridgezhao.azathothswhisper TimingLookupDisabled -bool YES` 停用全部；`TimingSourcesDisabled -array lrclib qq …` 停用個別來源。只在來源失效或隱私事件時由開發者使用，畫面上沒有入口（使用者既裁定：不給選）。

### 3.6 每個來源的護欄 `SourceGate`（actor，每來源一個）
| 項目 | 值 | 依據 |
|---|---|---|
| 最小請求間隔 | LRCLIB 0.5 s（文件 200–500 ms，取上限）；其他 1.0 s | LRCLIB 文件；探針 1.2 s 無 429 |
| 逾時 | 6 s | 探針 p90 ≤ 1.7 s |
| 熔斷 | 連續 3 次失敗（429、403、5xx、連線、逾時）→ 開 10 分鐘；之後放 1 個試探請求，成功即關、失敗再開 | 探針 LRCLIB 503 |
| Retry-After | 照辦，加 0–30 % 隨機抖動，上限 1 h；期間該來源視為熔斷中。503＋Retry-After：等候後重試一次，不計入熔斷 | LRCLIB 文件（T0） |
| 快取 | 存檔本身＝磁碟快取（found／notFound）；搜尋結果在記憶體以 query 為鍵快取 30 分鐘、上限 200 筆 | 同首歌兩個觸發點連發 |
- **唯一入口**（Codex R1 #11）：adapter 的每一個對外請求（搜尋、細節、歌詞、Deezer JWT）都經過該來源的 gate，所以多步驟的來源也受同一個間隔與熔斷約束。
- `Retry-After` 支援秒數與 HTTP-date 兩種格式。
- 半開狀態同時只放一個試探請求；在 gate 等待中被取消會釋放名額。
- 時鐘注入（既有 `MonotonicClock` 模式），單測不 sleep。
- User-Agent：LRCLIB 用 `AzathothsWhisper/<MARKETING_VERSION> (https://github.com/TK88101/Azathoths-Whisper)`（repo 已公開，`gh repo view` 2026-10-19 實測 PUBLIC）；其他來源沿用 `URLSessionHTTPClient.userAgent`。

### 3.7 各 adapter（端點以 2026-10-19 探針實測為準）
| 來源 | 搜尋 | 取時間軸 | 備註 |
|---|---|---|---|
| LRCLIB | `GET /api/get?artist_name&track_name&duration`；404 才 `/api/search` | `syncedLyrics` | 帶 UA；候選唯一才用 |
| YouTube Music | `POST youtubei/v1/search`（WEB_REMIX、songs 篩選） | `next`→`MPLY…` browseId→`browse`（ANDROID_MUSIC 7.21.50）的 `timedLyricsData[].cueRange` | 客戶端版本號是常數，失效時跟 ytmusicapi 更新；無 `cueRange`＝plainOnly |
| Deezer | `GET api.deezer.com/search?q=<artist> <title>` | 匿名 JWT（`auth.deezer.com/login/anonymous`，只放記憶體、401 時重取）→ `pipe.deezer.com/api` GraphQL `synchronizedLines` | 探針 0 首帶時間，仍照鏈保留（使用者：全開） |
| QQ 音樂 | `POST u.y.qq.com/cgi-bin/musicu.fcg`（DoSearchForQQMusicDesktop） | `c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid&nobase64=1`，Referer `y.qq.com` | |
| 酷狗 | **T0 沒找到可用的 https 搜尋端點 → 預設移出鏈**（Codex R1 #1、R2 #4）。`StoredTimingSource.kugou` 保留不刪（避免動存檔格式），只是沒有 provider。要用 `http://mobilecdn.kugou.com` 須使用者在 §9-1 明確授權，那時 T5e 才做 | `krcs.kugou.com/search?hash&duration` → `lyrics.kugou.com/download?fmt=lrc`（base64） | |
| 網易雲 | `POST music.163.com/api/cloudsearch/pc` | `GET music.163.com/api/song/lyric?id&lv=-1` 的 `lrc.lyric` | 明文端點；失效時不改走加密介面（另案） |
- 時間軸少於 3 行一律當 `tooFewLines`（探針 October Falls 只有 3 行的可疑案，交給對齊門檻再擋一次）。

### 3.8 觸發點（C.2）
- **寫入後**：`AppModel` 在 `editor.onSaved`、`batch.onLyricsWritten` 的既有接線裡加一行 `timing.enqueue(…, priority: .background)`。
  - 兩個 callback 只帶 `(persistentID, text)`；artist／title／duration 由 resolver 用 `music.trackDetails(persistentIDs:)` 唯讀補讀。
  - T1 已核：Batch 的 `AlbumTrack` 沒有 duration（`MusicControlling.swift:25-32`），Editor 也沒有持有，所以寫入觸發一律補讀。`TrackDetails` 有 artist、title、duration（同檔 :88-99）。特效層觸發已知 `TrackInfo` 與 `metadata.duration`，直接帶上，不補讀。
  - 與寫入解耦：不在 busy 區間內、不影響寫入成敗。「寫入已經發生」照既有慣例在 stale 守衛之前送出。
- **特效層顯示時**：`LyricsFXViewModel.apply` 建完時間軸若為 `.estimated` 且 `status == .present`，透過注入的 closure 請求 `priority: .visible`。
  - 先讀存檔（非同步、本機），符合就直接熱替換，不排網路。
  - `TimingLookupPolicy.shouldLookup` 為真才排網路（詞改了立即、`.notFound` 滿 7 天）。
- **熱替換**：結果回到 MainActor，以 `identity` 與 `fingerprint` 再驗一次才換 `timeline`。
- 沒有 Music 播放控制、不寫 `Queue.dat`／`History.dat`；補讀只用既有白名單內的唯讀選擇器。`no_playback_gate.sh` 與選擇器白名單測試照舊把關。

### 3.9 診斷（OSLog，subsystem 既有，category `timings`）
- 每次查找一行：`pid`（序號 ID，CLAUDE.md 允許）、來源、結果類別（answer／mismatch／alignFail／plainOnly／notFound／failure 種類）、對齊率（兩位小數）、耗時 ms、HTTP 狀態。
- 每 20 次查找另記一行累計：各來源命中數、各失敗種類次數。
- **不記**：artist、title、歌詞任何一行、URL query、JWT、回應內容。

### 3.10 畫面（C.4，使用者 2026-10-19：先保留，審計劃時可拿掉）
- 特效層角落小字 `~`：時間軸 `source == .estimated` 時顯示，`.found` 或內嵌時不顯示。純符號，無文案。
- 「尚無時間軸」（Codex R1 #14：`.notFound` 只代表當時查不到，不是這首歌客觀上沒有）：
  - 只在存檔是 `.notFound` 時顯示：Cover Flow 卡片徽章旁一個小圖示，加無障礙標籤。
  - `.notFound` 只在全部來源都明確回答「沒有」時才會寫入（§3.5）。被擋、逾時、熔斷、metadata 不全都不寫，所以不會顯示。
  - 新文案在 `Localizable.xcstrings` 補三語：`en`「No synced timing yet」、`zh-Hant`「尚無時間軸」、`ja`「タイミング未取得」（使用者看過再定）。
  - Editor 狀態欄不加：狀態欄是英文運行時文案（E-05），也會被寫入後的狀態蓋掉。
- 不跳任何 modal、不給任何人工操作入口。

## 4. 任務清單（每項帶 DoD）

| # | 任務 | DoD |
|---|---|---|
| T0 | 開工核對（連網前先提醒使用者）：①重讀 LRCLIB 文件節流條款；②找酷狗 https 搜尋端點（最多 3 次請求）；③用探針腳本重算那 5 首達標歌的 LRC 側覆蓋率（約 30 次請求），確認 0.6 不誤殺 | 計劃 §3.4、§3.6、§3.7、§9 更新為已核事實；0.6 若誤殺，回報使用者後再定 |
| T1 | HTTP 擴充（§3.1）＋`MockHTTPClient`；核對 Batch／Editor 寫入時能否直接拿到 duration | 既有 HTTP 測試全綠；新增 send、headers、串流大小上限、轉址降級中止的測試紅→綠；duration 來源寫進 §3.8（不再 TBD） |
| T2 | `TrackMatcher`（§3.3） | 探針觀察到的配對案例整理成參數化測試（只用歌手／曲名／時長，不含歌詞）全綠；版本護欄的正反例（Nightwish、Rusalka、Live／Live - 1991、Glastonbury／Reading、短曲名、AC/DC）全綠 |
| T3 | `LRCAligner` 重構、雙向覆蓋、外部時間驗證、存檔 v2 與讀回驗證（§3.4） | 既有 `LRCAlignmentTests`、`TimingStoreTests` 全綠；新增測試全綠：v1 可讀、v2 寫出、netease 往返、錨點重建逐行相同、重複副歌錯錨被拒（Codex 的例子）、倒序／超長／重複 cue、index 越界不顯示 |
| T4 | `SourceGate`（§3.6） | 假時鐘單測：間隔、熔斷開／半開／關、Retry-After、快取到期與上限 |
| T5a–f | 6 個 adapter（§3.7）：Parser＋Provider | 每個 Parser 用自編 fixture（自編句子，不用真歌詞）測：帶時間、純文字、配錯、空、壞 JSON；Provider 用 MockHTTPClient 測請求只含 artist／title／duration |
| T6 | `TimingResolver`（§3.5） | 單測全綠：順序、停止規則、配錯往下、失敗不存 notFound、metadata 不全不連網、加入同一份工作只發一次網路、新 hash 取消舊工作、舊 hash 結果丟棄、visible 搶占卡在逾時的 background、20 s 時限、佇列上限、停用開關、`shutdown()` 後不發請求／不寫檔／不回呼 |
| T7 | 觸發點與特效層（§3.8、G7） | AppModel 整合測試（MockMusic＋假 provider）：Editor 寫入→存檔；Batch 連寫 N 首→N 筆依序；特效層顯示→讀存檔熱替換；詞變更→舊結果不套用 |
| T8 | 診斷（§3.9） | 單測：日誌字串不含 artist／title／歌詞（以假 Logger 收集斷言） |
| T9 | 畫面（§3.10）＋三語文案 | 單元：`~` 顯示判定純函式；`.xcstrings` 三語齊；UI 測試：DEBUG 預覽場景切「有時間軸／估算」 |
| T10 | ATS 例外（若 §9-1 拍板）＋`project.yml`＋`xcodegen generate` | 建置成功；只多 `mobilecdn.kugou.com` 一個例外 |
| T11 | ACCEPTANCE 增修（§7） | 條目落檔、狀態與驗證方式填好 |
| T12 | 全量驗證（§6） | 單元全綠（已知基線紅不算）、coverage_gate、no_playback_gate、Scripts 測試、UI 測試（使用者在場） |

**並行候選**（slipknot 33）：T5a–f 互不相依。
- 依賴：T1、T2、T4 完成後。
- 排他書寫集合：各自 `Services/Lyrics/Timing/<Source>*.swift` 與 `Tests/Timing/<Source>*Tests.swift`。
- setup 命令：`xcodegen generate`。
- 單獨測試命令：`xcodebuild test … -only-testing:AzathothsWhisperTests/<Source>ParserTests -only-testing:AzathothsWhisperTests/<Source>ProviderTests`。
- 其餘任務照依賴鏈序列：T0 → T1 → T2／T3／T4 → T5 → T6 → T7 → T8／T9 → T10 → T11 → T12。

## 5. 測試策略
- **TDD**：每個任務先寫測試跑出紅燈，紅燈摘要記進本計劃附錄 B。
- **單元**：Parser（fixture）、TrackMatcher、SourceGate、TimingResolver、TimingStore v2、LRCAligner 重構、`~` 判定、診斷字串。
- **整合**：AppModel 接線（MockMusic＋MockHTTPClient＋假 provider），覆蓋兩個寫入觸發點與特效層觸發。
- **E2E**：既有 DEBUG 預覽場景加假 provider，XCUITest 驗「估算→熱替換成時間軸」時 `~` 消失（使用者在場）。
- **測試不連外網**：所有 provider 測試只用 MockHTTPClient；新增一條測試確認測試組裝下 resolver 拿到的是 Mock。
- **覆蓋率**：`Scripts/coverage_gate.sh` 傳單元測試的 xcresult，`Services/` 加 `Infra/` 至少 80 %。
- **真網路煙測**：不寫成自動測試（外部介面會變，偶發失敗不得進 CI）。改用本次的 Python 探針腳本，在使用者同意後手動重跑一次，對照 app 的診斷日誌。

## 6. 驗證項（使用者在場標 #）
- V1 單元全綠、coverage ≥ 80 %、`no_playback_gate.sh` 綠、`Scripts` Python 測試綠。
- V2 每個 provider 測試斷言完整請求（URL、headers、body，含轉址後）只帶 artist／title／duration，沒有 cookie、沒有 album、沒有 persistentID。
- V3 存檔目錄裡只有 v2 JSON、只含行號與秒數（掃一次實機產生的檔）。
- V4 #1 使用者在場：Editor 寫一首有詞的歌，特效層在數秒內從估算換成時間軸（`~` 消失）；log show 有對應一行診斷且不含曲名。
- V5 #2 使用者在場：Batch 寫一張專輯，寫入速度與 C 段前相同（時間軸在背景補）。
- V6 #3 使用者在場：UI 測試全套（Automation Mode／輔助使用授權）。
- V6 結果（2026-10-19 20:05）：上次 6 紅重跑——Batch `testBatchColumnsLocalizeButStatusStaysEnglishInJapanese` 綠（上次是鑰匙圈框沒點）；CoverFlowUITests 4 條補 `TEST_RUNNER_AZW_EXPECTED_APP_DIR` 後仍紅，原因是點不到「COVER FLOW」分頁按鈕＝v2.0.0 起的已知舊紅（見 2026-09-26-lyrics-notification.md 紅 4，範圍外），與 C 段無關，並非上次推測的「Echo 同時在跑」；A-10 已熔斷不重跑。
- V3／V4 結果（2026-10-19 20:14–20:18，使用者在場，真實網路）：寫入一首冷門歌後 8 秒內問完 5 來源（LRCLIB 503 屬暫時失敗→不存 notFound、網易雲對齊未達標 lrc=0.36 被擋），`~` 保留＝正確；換有名的歌，LRCLIB 0.8 s 給答案（music=0.88 lrc=0.81），截圖右下角無 `~`。另一首在 LRCLIB／YT 各逾時 6 s 後由 Deezer 補上。log 每來源一行，只有來源、結果、比率、毫秒，無曲名。存檔 3 份：兩份只有 {index, start}，一份全部來源明確回答→空 lines（notFound）；無歌詞全文。V3、V4 達標。
- V5 結果（2026-10-19 20:20–20:22，使用者在場）：Batch 7 首，抓詞 20:20:51–20:21:10（約 3 s／首，與 C 段無關的既有路徑）；時間軸查找 20:21:17 才開始、在寫入之後逐首背景跑約 38 s，寫入未被拖住。LRCLIB 連續 503 後斷路器開啟（circuitOpen 0 ms 跳過），由 YouTube Music／網易雲補上，查到的每首都有答案。V5 達標。
- 真機發現（2026-10-19 20:25，使用者回報「唱的比詞快、詞出得慢」，Oasis〈Don't Look Back in Anger (Remastered)〉，YT Music 時間軸）：已核——存檔每行起點與 LRCLIB 逐行差 < 0.5 s，資料正確；字的出現被 `TimedWord.split` 平均攤在「本行起點→下一行起點」整段（含停頓、間奏），所以唱完了字還在跳；次因是未直接錨定的行用內插（例：實際 74.6 s、內插約 76.5 s）。屬母計劃 §2.4 既有顯示行為，非 C 段回歸；使用者決定**C 段測完後另議**修法（方向：限制行內逐字的最慢速度，出完即停）。

## 7. ACCEPTANCE 增修（T11 落檔）
- I-09：狀態改「✅ 單測＋C 段生產路徑接上」，補 v2 格式與 netease。
- 新 I-49：退路鏈與停止規則（§3.5），含「失敗不存 notFound」。
- 新 I-50：隱私（只送三欄、只存時間、日誌不含曲名歌詞）。
- 新 I-51：每來源護欄（§3.6）。
- 新 I-52：觸發點、去重、熱替換、7 天重試（§3.8）。
- 新 I-53：畫面 `~` 與「無時間軸」（§3.10）。

## 8. 影響面、風險與回退
- **影響檔案**：`Infra/HTTPClient.swift`、`Services/Lyrics/{LRCAligner,TimingStore,LyricsTimeline}.swift`、新資料夾 `Services/Lyrics/Timing/`、`Features/LyricsFX/LyricsFXViewModel.swift`、`Features/LyricsFX` 的 View（`~`）、`Features/CoverFlow`（徽章）、`App/AppModel.swift`、`project.yml`（ATS、新檔）、`Localizable.xcstrings`、`ACCEPTANCE.md`、測試。
- **風險**
  - 5 個非官方介面隨時會變：每來源熔斷＋診斷日誌可看出哪個壞了；修法是更新該 adapter，不影響其他來源。
  - 條款灰色：使用者 2026-10-18 已知情並決定全開。
  - Batch 大量寫入造成請求暴增：佇列序列化＋每來源限流。最壞情況是 500 首 × 6 源 × 約 2 請求 × 1 s，背景數小時，不影響寫入。
  - 特效層熱替換閃動：替換只換時間、不換文字，畫面上是當前行位置跳一次（推測可接受；V4 使用者看）。
- **回退**：C 段全部在 `feature/lyrics-fx-c` 分支；有問題整支不合。合併後要停用，就在 `AppModel` 不注入 resolver（一行），存檔格式向下相容。

## 9. 待拍板
1. **酷狗**（T0 已確認找不到 https 搜尋端點，此項成立）：預設＝移除酷狗。探針中它多補 1 首、沒有單獨命中。若要保留，就得在 ATS 對 `mobilecdn.kugou.com` 這一個主機開 http 例外：歌手與曲名會以明文經過網路，同網路的人看得到、也改得了。改了的結果會被比對和對齊門檻擋下，但看得到這件事擋不住。

- **§9-1 已拍板（2026-10-19 使用者）：移除酷狗。**程式本來就沒有酷狗 provider；已刪除 `TimingSource`／`StoredTimingSource` 殘留的 `kugou` case（全量單元 1421 條，1 紅為 `CoverFlowStripRenderGeometryTests/runtimeCenterChangeReachesTarget` 參數 4，與本改動無關，單獨重跑 3 次綠，根因 TBD）。

## 9 之二　實作後新增待拍板（/simcodex R3 層級審查提出，2026-10-19）
2. **某個來源長期壞掉時，永遠存不下「沒有」**：§3.5 定案「任一來源失敗且沒有答案＝不存 notFound」。若某來源結構性失效（例如 YouTube 客戶端版本號過期，持續回解析失敗或 403），所有沒有時間軸的歌都會一直是 unavailable：Cover Flow 永遠不出「尚無時間軸」，每次退避到期（5–300 s）整條鏈重打一遍。
   - 選項甲（現況）：照 §3.5，寧可重查也不誤存。
   - 選項乙：把「解析失敗」視為該來源明確回答「沒有」（暫時性的逾時／429／5xx／斷線仍算失敗），可以存 7 天 notFound；來源修好後最晚 7 天自動重查。

- **§9-2 已拍板（2026-10-20 使用者同意 Codex 收斂結論）：維持選項甲**——解析失敗／403 不等於「這首沒有時間軸」，不存 notFound；來源長期壞掉的重複查詢，另以來源層級的長期健康狀態／熔斷處理（未立項）。

## 附錄 A　評審辯論紀錄（Codex gpt-5.6-terra，medium；2026-10-19）

| # | 嚴重度 | Codex 意見 | 處置 | 理由／結果 |
|---|---|---|---|---|
| 1 | P0 | 酷狗 http 明文，不該開 ATS 例外 | 部分採納 | 預設改為找不到 https 就移除；明文風險是否接受屬價值判斷→§9-1 交使用者。R2：Codex 接受，另要求禁止轉址降級、例外只限單一主機→採納。我方舉的 darklyrics 先例不構成安全論據（Codex R2，我方同意） |
| 2 | P1 | 2 MiB 上限在下載後才檢查無效 | 採納 | §3.1 改串流累計中止 |
| 3 | P1 | visible 插隊只影響未開始的工作 | 採納 | §3.5 搶占＋每首 20 s 時限 |
| 4 | P1 | 加入同一份工作與熱替換的介面未定義 | 採納 | §3.5 `resolve(...) async -> Resolution` |
| 5 | P1 | duration 為 TBD，缺時長會系統性誤判 | 採納 | §3.5 前置條件；T1 核對來源 |
| 6 | P1 | 比對抹掉版本差、對齊 greedy | 部分採納（三輪） | 採納：版本護欄、短曲名精確、≥ 3 錨點、LRC 側覆蓋率 ≥ 0.6（R2 反例：重複副歌錯錨）、只算直接錨點（R3）、兩方都有版本詞時比片段（R3 反例：Glastonbury／Reading），子集放行。駁回改全域 DP：R1-4 既定、無誤判實例，且相同段落 DP 也分不出（R2 Codex 同意）。駁回「未知括號一律拒絕」：反例網易雲 `Русалка (Rusalka)`（R3 Codex 同意改用關鍵詞表） |
| 7 | P1 | 存檔 index 未驗證範圍 | 採納 | §3.4 讀回驗證 |
| 8 | P1 | 外部 cue 時間未驗證 | 採納 | §3.4 provider 邊界驗證 |
| 9 | P1 | resolver 生命週期沒接 stop | 採納 | §3.5 `shutdown()` |
| 10 | P1 | 靜默送第三方，要首次同意＋kill switch | 部分採納 | 駁回同意彈窗：使用者 2026-10-18 既裁定「靜默、全開、不給選」（R2 Codex 接受）。採納：隱藏的全域／逐來源停用開關（defaults，非 UI）、V2 檢查完整請求含轉址 |
| 11 | P2 | gate 要涵蓋每一個請求、Retry-After 兩種格式、半開只放一個試探 | 採納 | §3.6 |
| 12 | P2 | actor 不保證跨程序 | 採納 | §3.4 改寫語義 |
| 13 | P2 | 分期導入、0 命中來源延後 | 駁回 | 使用者既裁定全開；LRCLIB 的 0 來自抽樣框（40 首是從「LRCLIB 缺時間軸」清單抽的）；YT 有 8 首帶 cueRange、3 首對齊達標（R2 Codex 接受並更正） |
| 14 | P2 | 「無時間軸」語義過強 | 採納 | §3.10 改「尚無時間軸」，只在全部來源明確回答時寫 notFound |
| R2-a | — | `/` 拆分會拆壞 `AC/DC` | 採納 | §3.3 先比全名 |

**結論**：三輪後已無未決的技術爭議。剩下的 §9-1、§9-2 屬價值判斷，交使用者。

## 附錄 B　TDD 紅燈紀錄（2026-10-19）

| 任務 | 紅燈 | 綠燈 |
|---|---|---|
| T1 HTTP | 8 處失敗（send 不帶 body／headers、沒有回應標頭、兩種大小上限未擋、cookie 設定）；轉址測試起初假綠——替身 URLProtocol 不會自己轉址，改成真的發出轉址後 4 處紅 | 31 條綠；另加「同主機 https 轉址要跟」反向對照，證明不跟不是替身造成 |
| T2 TrackMatcher | 17 處失敗（空殼） | 27 個案例＋正規化綠 |
| T3 對齊／存檔 v2 | 7 條 10 處失敗；舊測試以「版本 2」代表「較新格式」→ 照升版改成 3（語義不變） | 50 條綠 |
| T4 SourceGate | 9 條失敗 | 16 條綠；與 T6 合併連跑 20 次 0 失敗 |
| T5 五個 adapter | 每個 adapter 先空殼紅（LRCLIB 7、YT 5、Deezer 6、QQ 4、網易雲 6 條） | 36 條綠；作詞作曲行過濾放進所有來源共用出口 |
| T6 TimingResolver | 14 條直接失敗、其餘並發測試掛住 | 25 條綠，連跑 20 次 0 失敗 |
| T7 接線 | 5 條 7 處失敗；「舊結果不套用」一條因 MockMusic 寫入不影響重讀而假紅 → 改送同曲改詞事件 | 6 條綠，連跑 10 次 |
| T8 診斷／正式組裝 | 3 條 9 處失敗 | 綠；另補「正式組裝讀停用開關」 |
| T9 標記 | 4 條 10 處失敗；實作後抓到競態（存檔讀取比查找結果早開始、晚回來，會清掉標記）→ 加每首世代號並補測 | 22 條綠，連跑 5 次 |

## 附錄 C　/simcodex 三輪（2026-10-19）

| 輪 | simplify（4 角度） | codex review | 安全評審（opus，只 R1） | 驗證 |
|---|---|---|---|---|
| R1 | 修 9、跳過 6（TimingResolver 改持有 Job 參照、provider 樣板收斂、編輯距離單一定義、特效層防重鍵改 (pid, 指紋)、Cover Flow 世代號與空寫、快取只存小回應） | 只有 P2：「 2／ 3.xcodeproj」舊副本（開工前就存在，不動、不 commit） | 3 HIGH＋2 MEDIUM＋5 LOW 全修：LRC offset 溢位閃退（修法本身的 `abs(Int.min)` 也溢位，由回歸測試抓到改 `magnitude`）、YT 全形數字強制解包閃退、曲名 regex 二次方回溯（名稱上限 300）、外部 LRC 行數／行長上限、快取位元組預算、Retry-After nan、visible 堆積、曲長上限、JWT 格式、轉址比對 port | 單元 1413 綠 |
| R2 | 修 14、跳過 8（對齊長度預篩並移出 actor、候選上限、非有限數值、錨點合法性單一定義、POSIX＋寬度不敏感 folding、JSON 取值 helper…） | 2 條 P1 皆誤判（enum 無關聯值自動 Equatable；`.timed(…)` 不帶 duration 是 case 本身）：駁回，證據＝全量照常編譯通過。但誤判證明 case 與靜態工廠同名易混 → 工廠改名 `validatedTiming` | — | 單元 1413 綠 |
| R3 | 修 7：對齊可取消（每次比對前檢查）、編輯距離帶狀＋提早結束並獨立成 `EditDistance`、候選上限只留一處、過時 visible 改降級不取消（寫入後補查不得消失）、註解錯置；第 4 條（來源長期壞掉）轉 §9-2 待拍板 | 2 條 P2 全修：空白歌詞不查不存、全部來源停用不存 notFound | — | 單元 **1420** 綠、coverage 95.7 %、no_playback 綠、Scripts 333 OK、Release 建置成功且不含 UI 測試假退路鏈 |

**未解事件（根因 TBD）**：R1 中途一次全量，`GlyphRasterFidelityTests`（與本次改動無關的點陣測試）跑到一半時測試宿主以**結束碼 0**退出（xcresult：「The test runner exited with code 0 before finishing running tests」），沒有 crash 報告。diff 中沒有任何 `exit`／`terminate`。同時段有另一個 Claude session（YSE「Echo」）在操作同一 bundle id 的 Azathoth's Whisper——推測它重啟 app 時連帶結束了測試宿主，但系統日誌在該時段查不到記錄，無法證實。之後同一條命令連跑三次全量皆完整綠。

**全量**：單元 1401 條全綠（跳過已知偶發掛起的 `overlappingLoadSuspendsPollingUntilLastCompletes()`）；`coverage_gate` Services＋Infra 95.2 %；`no_playback_gate` 綠；Scripts 333 條 OK；Release 建置成功，執行檔不含 UI 測試假退路鏈。UI 測試待使用者在場。
