# 歌詞特效模式（Lyrics FX）——升起層的第二種畫面——計劃 v10（草案，Codex R1–R4 已併入；探針 P1–P9 回饋已併入；§2.10 改為元件 × 特徵向量模型，待使用者拍板）

狀態：草案。Codex R1–R3 已回並併入（附錄 A.1–A.3；R3 僅兩處文字修正，無新異議）→ 使用者拍板 §9 → 才實作。
版本目標：v2.1.0（Build 2000004，依 memory「下次 2000004」）。

## 0. 複述

- **目標**：Editor 頁的升起層（現在只有 Cover Flow）新增第二種畫面「歌詞特效」：當前播放曲的歌詞隨播放進度以動態字體（kinetic typography）呈現，視覺風格依曲風（metal 子類）自動切換；使用者可在 Cover Flow 與它之間切換，偏好持久。
- **完成標準（驗收草案，每條「做 X 應看到 Y」）**：
  1. 升起層有切換控制；切到「歌詞特效」後整層顯示特效，切回顯示 Cover Flow；重啟後保留。
  2. 播放一首有詞的歌：歌詞逐行（行內逐字）隨進度出現、停留、退場；Music 暫停→畫面停住；Music 內拖進度→典型 ≤ 2 s 跟上（量測值回填 §8）；換歌→換成新歌內容。
  3. 曲風→風格：至少 6 種 metal 風格 ＋ 1 預設；Music `genre` 命中規則表就自動套用，Settings 可固定某一種。
  4. 缺詞、讀不到、已標記：升降行為與現狀完全相同；特效層在 `status != .present` 時只畫背景＋既有狀態字。未播放（`.notPlaying`）：reducer 既有行為是 no-op（`LyricsFlowReducer.swift:84-85`，層不動），特效層自己清掉時間軸、停讀、顯示「未播放」狀態字。
  5. 不送播控、不多寫 Music 任何欄位；`no_playback_gate.sh`、選擇器白名單測試、coverage gate 仍綠；日誌不記歌詞文字。
  6. 系統「減少動態效果」開啟時退化為靜態的當前行＋下一行。
- **不做（非目標）**：音訊分析／節拍偵測／音量；逐字級（word-level）的真實同步（外部來源只到逐行；行內逐字用等比估算）；把 LRC 寫回 Music 的 lyrics 欄位；Cover Flow 本身的任何改動；Batch 分頁；Python 1.x；自訂字型編輯器。

## 1. 參考調研（已核，2026-10-03）

### 1.1 TextAlive（textalive.jp）
- **style 清單實測 21 個**（Safari 讀 DOM）：`[d:2]` エレクトロニカ／キュート／ジャズ、`[d:3]` ベーシック、`[d:g]` グラデーション／フラット／ライン、`[d]` バラード／ポップ／ポップ２／ロック／ロック２、`[t]` おとなしく上品／カラフルキャンバス／コンソール／ノスタルジック／ポップ／元気でポップ／大胆。
- **結論：沒有任何 metal 子類的風格**。曲風類只到 Rock／Jazz／Ballade／Pop／Electronica；`[t]` 系是情緒與質感。本案的六種金屬風格必須自己設計。
- 它的時間資料來自 Songle 的音樂理解（逐字時間、拍、和弦、サビ、valence／arousal）；App API 有 `findBeat`／`findChord`／`findChorus`／`getVocalAmplitude`／`getValenceArousal`（developer.textalive.jp IPlayer）。**我們拿不到這些**：只有 Music 的 `playerPosition`、純文字歌詞、`genre`、`duration`。
- 「風格」在它那裡＝**參數包**（DPop：字型、粗體、色、サビ色、字級、字級振幅、字距、手振れ、縱位置振幅、背景 4 色、サビ演出、乱数シード）＋動效規則。本案照這個思路：風格＝參數包＋規則，不是七套硬寫的動畫。
- 縮圖觀察（scratchpad `style-*.png`）：Rock＝灰底、黑色斜切幾何塊、粗黑體、縱排或散置；Jazz＝白底、細線把散落的字串起來、傾斜灰方塊；Ballade＝粉色波浪帶、細明體、散點；bold＝整屏大字＋紅圓。→ 曲風風格＝「版面＋字型＋幾何背景元素＋動勢」四件套。
- AIST 研究頁（2016-01-25）：確認 TextAlive 以音樂理解技術取得 vocal timing 與 chorus；style／template／programming 三層；**無曲風對應的敘述**。

### 1.2 Music 與本 repo 的事實（勘察 agent ×2，錨點已抽查）
- 升降語意：`LyricsSurface` 只有 `.coverFlow`／`.editor`（`Features/LyricsFlow/LyricsFlowReducer.swift:4-7`）；有詞升、缺詞降（`:146`）、寫入後延遲升回（`:166-181`／`:118-125`）；View 端 Editor 條件掛載、Cover Flow 層常駐以 `offset` 升降（`Features/LyricsFlow/LyricsFlowPageView.swift:27-37`）；升起層＝把手＋`CoverFlowView`（`:76-96`）。
- 可見性：`AppModel.updateCoverFlowVisibility()`＝`tab == .editor && surface == .coverFlow`（`App/AppModel.swift:350-352`）。
- Cover Flow 純 SwiftUI（無 `TimelineView`／`Canvas`／`CALayer`）；動畫共用 `Theme.Motion.layerShift`（0.62 s）；`reduceMotion` 已貫穿（`LyricsFlowPageView.swift:16,35,88`）。
- 讀得到的欄位：`TrackDetails`＝persistentID／artist／title／album／discNumber／trackNumber／lyrics（`Services/Music/MusicControlling.swift:59-68`），批次讀「每欄一個 AE」（`MusicAppleEventsClient.swift:96-103`）。**沒有** `genre`／`duration`／`playerPosition`。
- 選擇器白名單是純集合比對（`Tests/Services/MusicSelectorAllowListTests.swift:19-22`）；新增 getter 必須同步改白名單與 H-20；`{ get set }` 會因隱式 setter 被判違規。`no_playback_gate.sh` R1／R3／R4 對 `@objc` getter 新增無影響。
- 輪詢 3 s、busy 跳過、單飛（`Services/Music/NowPlayingMonitor.swift:50,143-176`）；`MusicPlayerInfoSignal` 收 `com.apple.Music.playerInfo` 只傳「變了」（`Services/Music/PlayerChangeSignal.swift:17-20`）。
- 歌詞來源：`LyricsSource` protocol＋`LyricsService(genius:darkLyrics:)` 寫死兩欄（`Services/Lyrics/LyricsService.swift:12-40`）；`HTTPClient` protocol＋`MockHTTPClient`；Artwork 已有磁碟快取＋失敗退避（`Services/Artwork/ArtworkFailureBackoff.swift`）。
- Genius 歌詞含段落標籤：fixtures 內 `[Chorus]`×10、`[Refrain]`、`[Verse n]`、`[Pre-Chorus]`、`[Guitar Solo]`、`[Instrumental Break]`、`[Bridge]`、`[Outro]`。→ 可當「サビ」與「間奏」的訊號。
- 字型：已內建 `SpaceGrotesk-Variable.ttf`、`MaterialSymbolsOutlined-Subset.ttf`（`ATSApplicationFontsPath: "."`）。
- 設定足跡範本：`notificationsEnabled` 從 `ConfigStore.Key` 到 Settings View、選單、`make_xcstrings.py NEW_KEYS`、三個測試檔、ACCEPTANCE D-14（勘察 §6）。**`make_xcstrings.py` 整份覆蓋、不合併**：新字串必須加進 `NEW_KEYS`，不能只手寫 xcstrings。
- 使用者曲庫 genre 分布（osascript 唯讀，前段）：ロック 3967、Alternative 1431、Metal 1428、Rock 1024、Hard Rock 920、Indie Rock 636、Black Metal 531、Death Metal/Black Metal 288、Symphony Black Metal 111、Melodic Death Metal 103、Industrial Metal 89、Viking/Power Metal 78、Symphony Metal 43、Black/Death Metal 38、「Symphonic Metal 」（尾端空白）35、Gothic Metal 33、Nu-Metal 32、Pagan Black Metal 28、Folk Metal 26、Thrash Metal 17、Gothic/Symphonic Metal 14、Depressive Black Metal 12、Melodic Doom Death Metal 12……。→ 標籤**雜**：斜線複合、尾端空白、日文、大小寫不一；對應表必須是「切詞＋優先序規則」，不是精確比對。
- LRCLIB（lrclib.net）實測：`GET /api/get?artist_name&track_name&album_name&duration` 免 token、JSON 含 `syncedLyrics`（逐行 LRC）／`plainLyrics`／`instrumental`／`duration`；Metallica／Emperor／Dimmu Borgir 命中、Cradle of Filth「Nymphetamine Fix」404；`/api/search` 模糊比對回 20 筆含 `duration` 與 `syncedLyrics` 布林。同步文字可能含雜訊頭行（例：`[00:00.00] Metallica - Master of Puppets`）。

### 1.3 GitHub 同類專案（調研 agent，shallow clone 到 scratchpad 逐檔核；授權只列事實）
| 專案 | 授權 | 與本案相關的機制 | 可借鑑 |
|---|---|---|---|
| ddddxxx/LyricsX ＋ MusicPlayer ＋ LyricsKit（5.2k★，Swift，macOS） | MPL-2.0（檔案級 copyleft，**只學做法不抄碼**） | ScriptingBridge 讀 `app.playerPosition`（`LXPlayerAppleMusic.m:36-38`）；**不存位置、存「起播時刻」`startTime = now − position`**，取位置時再算（`LXPlayerState.m:39-42,156-157`）；新讀數與舊錨點差 ≤ 1.5 s 視為相同不更新，> 1.5 s 當 seek 重錨（`LXScriptingMusicPlayer.m:88-92`）；LyricsX 每 1 s 讀一次（`SelectedPlayer.swift:25`）；換行用「睡到下一行的 dt」排程，不固定頻率（`AppController.swift:76-95`）；逐字高亮用 CoreText 畫成 mask ＋ `CAKeyframeAnimation`（`KaraokeLabel.swift:145-188`） | 錨點法；1.5 s 容差；下一行排程；全域時間偏移 `adjustedTimeDelay` |
| aviwad/LyricFever（636★，Swift） | MIT | ScriptingBridge `playerPosition`，**讀數加固定補償 +400 ms**（動畫模式再 +400，AirPlay −2000；`AppleMusicPlayer.swift:33-38`）；「讀數＋讀取時刻」內插（`CurrentTimeWithStoredDate.swift:10-22`）；LRCLIB 是來源之一（`LRCLIBLyricProvider.swift`）；karaoke 浮窗純 SwiftUI `Text` 逐行、無逐字；全螢幕非當前行模糊（CA）；背景 Metal 多色漸層（`colorEffect(ShaderLibrary.gradient)`） | 補償偏移；非當前行模糊；專輯色漸層背景 |
| Yudaotor/lyrimuse（169★，Swift） | GPL-3.0（不抄碼） | 用 `osascript` 子行程讀；輪詢**播放中 2 s／暫停 6 s／閒置 10 s**（`LocalPlaybackSource.swift:2198-2201`）＋ 20 Hz 外推 timer；只在換歌、播放暫停切換、或「讀數與（錨點＋牆鐘）預測差太多」時重錨（`:345-360` 註解）；同一註解記錄實測：**AppleScript `player position` 精度約 0.1 s**；12 個來源含 LRCLIB，逐字時間只來自 NetEase／QQ／Kugou／Musixmatch／AMLL／Apple Music | 省電輪詢節奏；長音 swell & glow；背景和聲另起一行；字色跟隨封面 |
| jayfunc/BetterLyrics（2.2k★，C#／Win2D） | GPL-3.0（不抄碼） | 效果設定逐條：WordByWord、Blur、FadeOut、EdgeFeathering、Glow（長音節 ≥ 700 ms）、Shadow、Scale（115%）、Float（8 px／450 ms）、Breathing、3D、Fan（`LyricsEffectSettings.cs:20-167`）；背景 renderer：Fluid／Fog／Snow／Raindrop／Spectrum；**歌詞關鍵字觸發粒子**（love／rain／snow／star／moon → 對應粒子，`SemanticEffectsRenderer.cs:39-65`） | 效果參數命名；關鍵字粒子（金屬版：blood／fire／frost／night／moon／death／grave…） |
| pablostanley/typexperiments（TS，Canvas 2D） | 無 LICENSE | 效果：Morph／Explode／Pour／Wave／Typewriter／Vortex，皆可調 duration／stagger／easing | 進退場動詞目錄 |
| marioecg/codrops-kinetic-typo（WebGL） | MIT | 文字 MSDF 貼到 3D 幾何，shader 捲動／扭轉 | 本案不走 WebGL；只借「字當貼圖在幾何上流動」的意象 |
| TextAliveJp/textalive-app-api | 需同意利用規約 | `.d.ts`：`TimedObject{startTime,endTime}`、`findPhrase/findWord/findChar`、`findBeat/findChorus/findChord`、`getVocalAmplitude`、`getValenceArousal`（v,a ∈ [−1,1]）、`onTimeUpdate` | 資料形狀對照：我們只有 line 級 |
| tomast1337/black-metal-logo-generator（p5.js） | GPL-2.0（不抄碼） | `font.textToPoints()` 取 glyph 點，每點放粒子沿 Perlin flow field 生長、筆畫由粗漸細、可 X／Y 鏡像 | **`frost` 的核心畫法**：CoreText glyph path 取點 → 噪聲場長枝 → 鏡像 |
| Harry-KNIGHT/…Karaoke-POC、bocan/bocan-music（SwiftUI） | 無 LICENSE／Apache-2.0 | 都只有逐行（`Text`＋`.scaleEffect/.blur/.opacity`＋`withAnimation`）；bocan 解析 enhanced LRC `<mm:ss.xx>` 但未用於顯示；其視覺化器用 `TimelineView(.animation(minimumInterval:))`＋`Canvas` | 逐行 SwiftUI 寫法；`minimumInterval` 節流 |
| gh search code `playerPosition` Swift | — | 5 個 repo（Jukebox／NowPlayr／Tuneful／AppleMusicDiscordRPC／AM2D）都以 `@objc optional var playerPosition: Double { get }` 宣告 | 與本案 §2.2 的宣告形式一致 |

未完成（rate limit）：`TimelineView`＋`Canvas`＋`resolve(Text` 的 code search、第 10 項補充專案。
**結論**：① 同類 app 一致採「錨點＋牆鐘外推＋大偏差才重錨」，輪詢 1–2 s；② Music 讀數需固定補償（LyricFever +400 ms），且精度約 0.1 s；③ 沒有任何專案依曲風切換視覺風格——這部分是本案獨有。

## 2. 設計

### 2.1 模式與狀態：不動升降語意，加一個「升起層畫面」偏好
- `LyricsSurface` 不改。新增 `enum RaisedLayerStyle: String { case coverFlow, lyricsFX }`，存 `ConfigStore.Key.raisedLayerStyle = "RaisedLayerStyle"`（預設 `coverFlow`）。
- 升起層內容依它二選一：`CoverFlowView` 或 `LyricsFXView`。升降觸發規則（有詞升、缺詞降、寫入後升回、把手、點播放卡）**完全沿用**——歌詞特效只在「有詞」時有意義，與現有規則天然一致，reducer 不加事件。
- 可見性拆成兩個：`coverFlow.setVisible(raised && style == .coverFlow)`、`lyricsFX.setVisible(raised && style == .lyricsFX)`，都在 `AppModel.updateCoverFlowVisibility()` 同一處接線（改名為 `updateRaisedLayerVisibility`）。不可見時特效層不讀 Music、不繪製。
- **升起 ≠ 有詞**（Codex R1-7①）：reducer 在 `markedNone`（`LyricsFlowReducer.swift:110-117`）與 `unknown`（讀不到，`:146` 只有 `.missing` 才降）時也升到 `.coverFlow`。特效層在 `status != .present` 時**不發明新狀態**：畫風格的背景元素＋共用的 `LyricsStatusLabel`（已標記無詞／讀不到的既有文案），不跑文字動畫、不讀位置。`status` 由 `LyricsFlowModel.state.status` 同源提供。
- 切換控制：把手右端加一個 2 段的圖示切換（封面／歌詞），只換內容不升降（`AccessibilityID.lyricsFlowStyleToggle`）。Settings 改偏好時也必須經 `updateRaisedLayerVisibility()`（Codex R1-1）。Settings 新增「升起層畫面」預設值與「歌詞特效風格：自動（依曲風）／固定某一種」。選單是否加項與快捷鍵→ §9。

### 2.2 從 Music 多讀三個唯讀欄位
- track：`genre: String`、`duration: Double`（秒）；app：`playerPosition: Double`（秒）。都宣告成 `@objc optional var … { get }`，白名單同步加入三個名稱，H-20 條目改寫；負對照測試另加一條「假設宣告 `setPlayerPosition:` 必被判違規」。
- `TrackDetails` 加 `genre`、`duration` 兩欄（`Column` +2 → 每批 +2 AE；S6 預算與 `detailsBudget` 要重量測 p50，記進 §6）。
- 新協議方法 `func playbackPosition() async throws -> PlaybackPosition?`：一次 run 內讀 `playerState`＋釘住的 `currentTrack.persistentID`＋`playerPosition`，回 `{ persistentID, seconds, state, readAt: ContinuousClock.Instant }`。persistentID 一起回，避免「換歌瞬間把舊位置套到新歌」。
- `MockMusicClient` 加對應替身；`InertMusicClient`（UI 測試）回固定值。

### 2.3 位置時鐘 `PlaybackPositionClock`（`Services/Music/`，可測）
- `@MainActor @Observable`。**錨點法**（LyricsX／lyrimuse 同款）：讀到 `(seconds, state, readAt)` 後存 `anchor = readAt − seconds`（playing）或固定 `seconds`（paused／stopped）；`estimate(now) = now − anchor + offset`。`offset` 是 Settings 可調的毫秒補償（預設值由實機量測定，LyricFever 用 +400 ms；§8 回填）。
- 讀取節奏：只在 `isActive`（特效層可見 ∧ `status == .present`）時跑；**播放中每 2 s、暫停／停止時每 6 s**（lyrimuse 節奏；`PollClock` 注入，測試用 `GatedPollClock`）。`playerInfo` 通知 → `resync()` 立即讀（播放／暫停／換歌不等輪詢）。暫停時不能停讀（Codex R2-Q3）：`Stopped` 通知被刻意丟棄（`PlayerChangeSignal.swift:20-26,43-47`），且通知本就「漏了由輪詢保底」（ACCEPTANCE B-01）；暫停→播放的通知若漏，停讀的時鐘永遠不會恢復。
- 重錨規則：`|estimate − read| > tolerance` 才重錨（seek），否則不動（吃 AE 延遲與 0.1 s 精度抖動）；`tolerance` 初值 0.5 s，**以實機 AE 延遲分布量測後定**（Codex R1-3：不得寫成固定的驗收保證）。`persistentID` 與當前曲不符 → 丟棄該次讀值。
- 換行不靠每幀比對：時鐘另提供 `nextBoundary`，`TimelineView` 之外的靜態模式用「睡到下一行」排程（LyricsX `AppController` 做法），減少無效重繪。
- busy：**接 `BusySource`，與輪詢同一旗標**（R2 收斂，Codex 勝）。實體（Codex R3）：`busySources` 現在是 `NowPlayingMonitor` 的 private 狀態（`NowPlayingMonitor.swift:61`，記帳在 `setBusy(_:source:)` `:88-101`）；把這段 Set 記帳抽成值型別 `BusyLedger`（純函數、可測）讓 monitor 與時鐘各持一份，`AppModel` 既有的 `editor.onBusyChange`／`batch.onBusyChange` 扇出同時呼叫 `monitor.setBusy` 與 `positionClock.setBusy`（同一來源枚舉 `BusySource`）。任一來源 busy 時不送 AE、只靠錨點外推；busy 解除後補讀一次。理由：B-02 的實作註解寫的是「抓詞／批處理期間跳過輪詢，避免打斷使用者操作」（`NowPlayingMonitor.swift:80`），不只是防 Editor 被改寫；位置讀取與 `setLyrics` 共用同一序列佇列且 `run` 預設不設 timeout（`MusicAppleEventsClient.swift:33,223-245`），排在前面的讀取會延後寫入。代價近零：`status == .present` 且 busy 的主要路徑只有寫入（自動抓詞從空歌詞開始，`EditorViewModel.swift:106-120`），不會出現長時間假暫停。寫進測試：`PlaybackPositionClockTests.pausesReadsWhileBusyAndCatchesUpAfter`。
- AE 佇列被封面讀取佔住最長 1.5 s（`artworkTimeoutTicks`，`MusicAppleEventsClient.swift:217`）：seek 跟上時間的驗收改為「典型 ≤ 2 s、量測回填」，不寫 ≤ 1 s。

### 2.4 歌詞時間軸 `LyricsTimeline`：三層來源，逐層退路
```
struct LyricsTimeline { lines: [TimedLine]; source: Source; duration: Double }
struct TimedLine { start, end: Double; text: String; isChorus: Bool; words: [TimedWord] }
enum Source { embeddedLRC, lrclib, estimated }
```
- **層 1 內嵌 LRC**：Music 的 lyrics 欄位本身含 `[mm:ss.xx]` 標籤（使用者自己貼的 LRC）→ `LRCParser` 直接解析（支援一行多標籤、`[ti:]` 等 ID 標籤略過、CR／LF 都收）。
- **層 2 LRCLIB**（§9-A 拍板要不要進 v1）：`LRCLIBSyncedLyricsSource`（`HTTPClient`，`User-Agent` 帶 app 名與版本）：先 `/api/get`（精確）；404 才 `/api/search`，**只在候選唯一**（正規化後 artist＋title 相等、`duration` 差 ≤ 3 s、`syncedLyrics` 非空；多筆時取 album 相等者，仍多筆則棄用）時採用（Codex R1-4）。磁碟快取 `~/Library/Caches/com.ibridgezhao.azathothswhisper/LyricsSync/<persistentID>.json`，失敗退避沿用 `ArtworkFailureBackoff` 的模式（抽成共用或複製一份，§9）。
  **LRC 只借時間、不借文字**（改自 R1-4）：畫面永遠顯示 Music 欄位的文字（本 app 寫進去的那份）。對齊：兩邊各行正規化（小寫、去標點與空白、`LineEndings.normalized`），Music 每行找 LRC 中相似度 ≥ 0.8 的行（`Levenshtein` 比例），**對齊率 ≥ 0.7 才採用**；未對齊的 Music 行在相鄰已對齊行之間等比內插；對齊率不足＝視為別盤／別曲／別版本 → 棄用、落到層 3。雜訊頭行（`Artist - Title`、`Title (1986)`）自然對不上，不需特判。
  世代守衛：`(persistentID, lyricsRevision)` 二元組；`lyricsRevision` 在每次歌詞文字變更（換曲、`lyricsChanged`、Editor／Batch 寫入）時 +1；回來的 LRC 若二元組不符即丟棄（Codex R1-4：只守 persistentID 會讓舊回應蓋掉寫入後的新詞）。畫面角落標示來源（`synced`／`estimated`，§9-E）。
- **層 3 估算**（永遠可用）：`LyricsTimelineEstimator`：純文字 → `LineEndings.normalized` → 行；`^\[(.+)\]$` 段落標籤不顯示：`Chorus|Refrain|Pre-Chorus|Post-Chorus|Hook` → 後續行 `isChorus = true`；`Instrumental|Solo|Intro|Outro|Break|Interlude` → 配一段無字的間奏（權重＝一行×3）；其餘標籤只當段落分隔。時間窗 `[duration×lead, duration×tail]`（風格參數，預設 0.06／0.94）；行時長 ∝ 字元數（下限 1.2 s），段落間 gap 權重 0.6 行；行內逐字 ∝ 字長。畫面角落小字標示來源（`~`＝估算）→ §9-E。
- 取得順序：層 1 → 層 2（有快取先用快取）→ 層 3；層 2 回來後若當前曲未變（世代守衛：await 前擷取 persistentID）就熱替換時間軸。

### 2.5 曲風 → 家族 `GenreStyleResolver`（依 2026-10-03 曲庫採樣：9,577 首、69 個標籤，原始清單存 `docs/plans/2026-10-03-lyrics-fx-genre-sample.txt`）
- **先分體系，再分家族**（探針 P6：使用者定「日本的單獨獨立出一個體系，英文系的 rock 是另一個」）。體系判定 `LyricsSystemResolver`：歌詞文字中假名／漢字字元比例 ≥ 0.3，或標籤含「ロック」「j-pop」→ **日本語系**（家族 `jrock`、`jpop`）；否則 **英語系**。體系判定用歌詞文字而不只看標籤，因為同一標籤下中英日樂團混雜。
- 正規化：trim、lowercased、以 `/`、`,`、`&`、`+`、空白切詞，再做子字串規則（含日文）。**順序即優先序，首個命中者勝**。16 個家族覆蓋全曲庫（探針 P4：使用者要求「以我曲庫現有的分類去做」）：

| # | 命中詞 | 家族 | 變體 | 曲數 | 曲庫標籤 |
|---|---|---|---|---|---|
| 1 | 【日本語系】ロック，或歌詞含假名 | `jrock` | 4 | 3,378 | ロック |
| 1b | 【日本語系】j-pop，或歌詞含假名且標籤為 pop | `jpop` | 3 | 64 | J-Pop 64 |
| 2 | symphon、neoclassic、classical、religious、soundtrack、score | `cathedral` | 3 | 246 | Symphony Black Metal 84、Neoclassic 44、Symphony Metal 43、Symphonic Metal 26、Gothic/Symphonic 14… |
| 3 | goth、doom | `velvet` | 3 | 45 | Gothic Metal 13、Gothic Rock 12、Melodic Doom Death 12、Atmospheric Doom 8 |
| 4 | black、pagan、depressive、heathen | `frost` | 3 | 792 | Black Metal 412、Death Metal/Black Metal 247、Black/Death 29、Folk Black 21、Pagan Black 20… |
| 5 | death、grind、brutal | `slab` | 3 | 117 | Melodic Death 83、Death Metal 14、Death/Viking 10、Death/Doom 10 |
| 6 | nu、industrial、groove、new wave of american | `stencil` | 3 | 121 | Industrial 79、Nu-Metal 32、NWOAHM 10 |
| 7 | punk、hardcore、emo | `riot` | 3 | 74 | Punk Rock 41、emo-rock 33 |
| 8 | hip-hop、rap、r&b、soul | `block` | 2 | 24 | Hip-Hop/Rap 23、R&B/Soul 1 |
| 9 | electronic、dance、house、techno | `circuit` | 3 | 178 | Electronica 110、Dance & House 54、Electronic 14 |
| 10 | viking、folk、country、world（pagan／heathen 歸 frost，2026-10-04 查證定論，見 A1 計劃附錄 A.3） | `hearth` | 3 | 133 | Viking/Power 44、Folk 23、Worldwide 23、Folk/Viking Metal 21、Country & Folk 11、Viking Metal 11 |
| 11 | pop、afro、tropical（英語系） | `pop` | 3 | 140 | Pop 138、Afro-Pop 1、Tropical 1 |
| 12 | alternative、indie、britpop | `indie` | 3 | 1,738 | Alternative 926、Indie Rock 612、Adult Alternative 82、Britpop 88、Alternative Rock 30 |
| 13 | thrash、heavy、speed、power、progressive、metal | `chrome` | 4 | 1,002 | Metal 970、Thrash 17、Power 8、Progressive 7 |
| 13b | hard rock、rock（英語系，與 Metal 分開） | `rock` | 4 | 1,489 | Hard Rock 892、Rock 591、Hrad Rock 6 |
| 14 | 其餘 | `mono` | 4 | 8 | Music 8 |

- 兩次採樣數字不同（第一次 ロック 3,967／Black Metal 531，第二次 3,378／412）：TBD，疑與 `every track` 在不同時點包含的曲目範圍有關；比例結論不受影響，實作前以 `trackDetails` 的 `genre` 欄位重新統計一次。
- Settings「固定家族／變體」覆蓋自動判定；UI 測試與預覽場景可用環境變數指定。

### 2.6 十四個家族（參數包＋規則；每個家族都要過 §4 探針；原七種金屬表保留，新增六個家族的動作語言見預覽 v6 的 notes，實作時抄進本表）
**逐字獨立原則（探針 P1 回饋，2026-10-03，使用者：「每一個字都有它自己出現的特點」；對照 TextAlive ジャズ風格 embed id=74713 的實測：每字各自落在一條路徑上、各有大小與傾斜、按唱到的時刻一個個出現、細線把字串起來、上一句慢慢淡掉）**：風格不是「整行一起動」，而是每個字從風格專屬的模板池各抽一組：出場時刻（詞內等比＋種子抖動＋偶發連發模擬音節）、出場模板、停留小動作、退場模板、字級／高低／傾斜／散落四個變異量；線條按字出現的順序逐段生長；舊句殘留（trail）後淡出。每行以 `fnv1a64(文字)` 為種子，重播長得一樣。
每種風格由 `LyricsFXStyleSheet` 描述：版面／字型／色／模板池（進場／停留／退場各帶權重）／變異量／殘留／背景元素／脈動／サビ演出。
**不得有「把字串起來的線」**（探針 P3：使用者定為全家族禁止；那條線是抄 TextAlive ジャズ風格的連接線，沒有自己的理由）。**背景也不得有程式畫的「結構性裝飾」**（探針 P5：大教堂的拱線、絲絨角落的藤線都被判醜，全部刪除）。可用的質感只有：底片顆粒（逐像素雜訊、overlay）、暈影、刮痕與亮度閃爍、光柱／漸層、粒子（雪、灰燼、火星、紙屑、四芒星）、閃電（從天頂、不穿字）。**不得撒「散狀彩色點」當血或當強調**（探針 P4）；血＝濃稠暗紅漬滲開＋粗滴慢爬。
**字型（探針 P7 定案：只用開源／免費可商用的字型檔，不用程式畫三角）**：
| 字型 | 用在 | 授權（已核原文） | 狀態 |
|---|---|---|---|
| Catacombs（ToughCrest Studio） | frost A 彈片 | 「Freeware for any personal or commercial use」，再散布需署名 | 可內建，About 署名 |
| Cenobyte（Chad Savage） | frost B 寒霜 | 「Freeware」，未明寫商用 | TBD：向作者確認或改用 Grimoire of Death |
| Grimoire of Death（GGBotNet） | frost 備選 | SIL OFL 1.1 | 可內建 |
| Geizer（Matt Cole Wilson） | chrome A 雷霆 | 「free for personal and commercial use」 | 可內建 |
| Butcherman（Google） | slab | SIL OFL | 可內建（使用者：「一看名字就是死亡金屬」） |
| Metal Mania／UnifrakturMaguntia／Noto Sans JP／Shippori Mincho B1／Dela Gothic One／Zen Maru Gothic／Oswald／Special Elite／Anton／Cinzel／Black Ops One／Cormorant Garamond／Fredoka／Space Mono（Google） | 各家族 | SIL OFL | 可內建；體積要量（JP 字型要子集化） |
| Dark Metal（Brenda Sosa） | frost E 暗鐵 | DaFont「100% Free」，壓縮包無授權檔 | 可用，內建前再核 |
| Mirage Gothic（Carlos Mario Peña Solís） | frost F 幻影 | 字型內嵌「All rights reserved」，DaFont 標 100% Free | TBD 確認 |
| AmazDooM（Amazingmax） | chrome E 毀滅 | DaFont「100% Free」 | 可用，內建前再核 |
| DragonForce（Holitter Studios） | chrome F 龍 | DaFont「100% Free」 | 可用，內建前再核 |
| Megadeth（Shane McFee，粉絲字型） | chrome D 稜角 | 「freely distribute」；logo 屬 Capitol Records | 商標風險，使用者知情後暫留 |
| Haunting Attraction（Sinister Fonts） | velvet D 鬼屋 | DaFont「100% Free」 | 可用 |
| Shadow of Xizor（Boba Fonts） | stencil D 機甲 | DaFont「100% Free」 | 可用 |
| Wolfsfifth | — | 100% Free（DaFont） | 使用者剔除（太細） |
| Gravord | — | DEMO 版 | 不用 |
（探針 P7 後使用者：「剔除 Wolfsfifth，其他全都要，都作為各種變體」→ 以上全部嵌入預覽 v9。）
| Midnight Grave（blackmetalfont.com） | 使用者指定的目標樣式 | 商用 | 要用得買授權 |
原始字型檔與授權檔暫存於 scratchpad `fonts/`，拍板後搬進 `Resources/Fonts/`。
（原 P6 敘述：C 符文用 fraktur（UnifrakturMaguntia，OFL）。日文家族用 Noto Sans JP 900／Shippori Mincho B1／Dela Gothic One／Zen Maru Gothic（皆 OFL，需內建；app 內也可退回系統 Hiragino）。→ §9-D 更新。
**風格＝動作語言，不是換皮**（Muse 的 README §2.6 同一結論）：設計每個家族時先問「這種人聲在聽覺上是什麼質地」，進場速度、停留長短、消失方式、版面密度、可讀性讓步都要跟著變。字型 v1 只用系統與已內建者（`Font.system(design: .serif)`＝New York、`.width(.condensed/.compressed)`、Space Grotesk、等寬）；是否加一枚 OFL 的 fraktur 字型 → §9-D。

| 風格 | 曲風 | 版面與字型 | 色 | 動勢（進場／停留／退場） | 背景元素與脈動 |
|---|---|---|---|---|---|
| `frost` 霜 | Black | 三個變體＝三種動作語言（P3）：**A 彈片**＝全大寫窄黑體，每個詞從畫面邊緣 140–260 ms 砸向中央堆、允許重疊、到時硬切不淡出、落地抖動、熱詞血紅放大、重顆粒暈影（Mayhem／Darkthrone）；**B 寒霜**＝細窄體寬字距冰白，字由冰屑凝結成形、慢漂、散回冰屑、飄雪（氛圍黑金屬）；**C 符文**＝fraktur 影印負片瞬現、置中、サビ整面反白（90 年代 logo 感） | 近黑底、灰白／冰白、血紅只給熱詞與サビ | 見左 | 顆粒、暈影、閃白；**無線條、無高頻顫動**（顫動被判成 Nu-Metal） |
| `slab` 石板 | Death | 大號極粗壓縮體、左對齊、兩行堆疊 | 黑底、骨白 `#E8E2D6`／乾血紅 `#6E0A0A` 交替 | 逐字自上砸下、落地壓扁回彈（squash 1.15→1.0）；停留時每字下方滴一條細線緩降；退場：行從中間裂成兩半向左右滑出 | 2 Hz 低頻整屏縮放 0.98↔1.0；サビ時字改紅並加粗邊 |
| `cathedral` 大教堂 | Symphonic | 置中、襯線體（New York）、大字距、兩行 | 深藍→酒紅漸層底、金 `#C9A227` 字，柔光暈 | 字自下緩升＋拖尾光點；停留時字級隨 1.5 s 週期呼吸 ±3 %；退場慢溶解（1.2 s） | 金色細弧線（花飾）隨行生長、垂直光柱緩移；サビ：字級 +15 %、光暈加倍 |
| `stencil` 模板 | Nu／Industrial | 粗無襯線、橫向切帶模擬噴漆模板（clip 水平帶）、左右交替對齊 | 炭灰底、酸綠 `#B6FF00` 或橘 `#FF6A00` 強調、硬偏移陰影 | 行從左右交替猛推入並 RGB 分離 2 幀再合攏；停留時隨機 1 字短暫錯位；退場切片抽走 | 掃描線、1.7 Hz 彈跳；サビ：底色反轉為強調色、字黑 |
| `chrome` 鉻 | Heavy／Thrash／Power／Viking／Folk | 置中對稱如專輯 logo、粗斜體、一行大字 | 黑底、銀→鋼漸層填色＋高光掃過 | 行以聚光燈掃入（遮罩自左至右）；停留時高光每 2 s 掃一次；退場字帶微旋下墜 | 字間偶發閃電折線（白、0.1 s）；サビ：底部火線 |
| `velvet` 絲絨 | Gothic／Doom | 置中、襯線斜體、低對比、下方鏡像倒影（呼應 Cover Flow） | 深紫黑 `#140A1A`、緋紅 `#8A1C2B`、灰玫瑰 | 字以模糊 8→0 px 自煙中浮現；停留時燭光式 0.5 Hz 透明度呼吸；退場散成灰燼點 | 荊棘藤曲線沿基線生長、灰燼緩落；サビ：藤蔓開花（圓點） |
| `mono` 單色 | 預設／非金屬 | 左對齊、Space Grotesk、當前行大＋下一行小灰 | `Theme.background`／`Theme.coldWhite`，直角、無圓角 | 當前行淡入上移、舊行淡出；無逐字 | 無；這也是「減少動態效果」時所有風格的退化型 |

### 2.7 繪製引擎（`Features/LyricsFX/`）
- `LyricsFXViewModel`（`@MainActor @Observable`）：`style`（自動或固定）、`timeline`、`positionClock`、`isVisible`、`seed`；輸入來自 `AppModel` 接線（§2.8）。
- 模板池（`Features/LyricsFX/GlyphTemplates.swift`，純函數）：進場 `fadeUp／drop／pop／spin／slide／flip／smoke／type／rise／shake／grow／fallIn`、停留 `still／bob／wobble／drift／breathe／jitter／float／flicker`、退場 `fade／fall／scatter／shrink／slideOut／split／up／bands`；每個模板是 `(progress, context) -> GlyphTransform{dx,dy,rot,sx,sy,alpha,blur,glow}`，風格表只給權重。字的「個性」`GlyphPersonality{t0,dur,enter,hold,exit,size,dy,rot,dir,phase,scatter}` 由 `(line.seed ^ style.key, glyphIndex)` 決定，一行算一次快取。
- `LyricsFXView`：`TimelineView(.animation(paused: !isPlaying || reduceMotion))` 包 `Canvas`，狀態字與來源標示用 SwiftUI overlay 疊在 Canvas 之上（`LyricsStatusLabel` 不能進 Canvas，Codex R2-Q2）；每幀呼叫純函數 `LyricsFXFrame.plan(style:timeline:time:size:seed:) -> FramePlan`，再把 `FramePlan` 畫出來。`FramePlan = { glyphs: [GlyphDraw], shapes: [ShapeDraw], backdrop }`，`GlyphDraw = { char, font, position, rotation, scale, opacity, color, blur, strokeWidth }`。
- 純函數可測：給定 `(style, timeline, t, size, seed)` 輸出固定；每個 glyph 在畫布內（± 邊距）；opacity ∈ [0,1]；t < 第一行 start 無字；t > 最後行 end 無字；`isChorus` 行觸發風格的サビ參數。亂數用 `SplitMix64(seed: fnv1a64(persistentID) ^ lineIndex)`——**不用 Swift `Hasher`**（每次啟動隨機種子，Codex R1-5），同一行重畫長得一樣。
- 關鍵字粒子（借 BetterLyrics 的 semantic effects，金屬版詞表）：行文字命中 `blood|fire|flame|frost|ice|snow|night|moon|death|grave|storm|thunder|hell|abyss` 等（英文＋日文少量）時，該行停留期間多一組風格色的粒子；詞表為純資料、可測。
- 文字繪製：`context.resolve(Text(String(ch)).font(...))` 逐字；描邊／金屬漸層需要 glyph path 時用 `CTFontCreatePathForGlyph`（只在 `frost`／`chrome` 用，v1 可先用 `shadow`＋`opacity` 近似，§9-D）。模糊用 `context.addFilter(.blur(radius:))` 包在 layer。
- 效能預算：200 glyph／幀 ≤ 2 ms（Apple Silicon，Instruments 量），超過先減粒子不減字。
- 減少動態效果：改用 `TimelineView(.periodic(from:by: 1))`（或時鐘的 `nextBoundary` 排程）驅動 `mono` 退化型；**不能靠時鐘的 Observable 值觸發**——重錨規則下讀數在容差內不改值，View 不會失效（Codex R1-5）。
- `context.resolve(Text(ch))` 逐字逐幀是 2 ms 預算的最大風險：`mono` 先實測；需要時依序「只畫當前行＋前後一行 → 減粒子 → glyph 快取 per (char, font)」，最後才動 glyph path。
- 視窗尺寸變化：plan 以 `size` 為輸入，不快取任何按尺寸算的東西。

### 2.8 接線（`AppModel`）
- 建 `lyricsFX = LyricsFXViewModel(positionClock:, timelines:, configStore:)`；`timelines = LyricsTimelineProvider(lrclib: LRCLIBSyncedLyricsSource?, estimator:)`。
- `lyricsFlow.onSurfaceChanged`／分頁切換 → `updateRaisedLayerVisibility()`（兩個 setVisible）。
- `monitor.events` 的 `.trackChanged(track, existingLyrics)` 已進 `lyricsFlow.handle`；在同一分發點加 `lyricsFX.nowPlaying(track, lyrics:)`（不另讀 Music）。
- **同曲改詞不發事件**（Codex R1-7②）：monitor 只在 `signature` 變時 yield（`NowPlayingMonitor.swift:216-218`），使用者在 Music.app 直接改當前曲歌詞時特效不會更新。新增 `PlaybackEvent.lyricsChanged(persistentID:lyrics:)`：同 signature 但 `LineEndings.normalized` 後文字不同時 yield（monitor 記上次文字的 hash，不記文字）。v1 只接到 `lyricsFX`；`lyricsFlow` 是否也吃（修 Cover Flow 徽章同曲改詞不更新）記為後續，不在本案。
- `editor.onSaved(persistentID, text)`／`batch.onLyricsWritten` → `lyricsFX.lyricsUpdated(persistentID, text)`（寫入後升回時顯示新詞）。
- **`.notPlaying`**（Codex R2-Q4）：reducer 對它 no-op（`LyricsFlowReducer.swift:84-85`），特效層必須自己處理：事件迴圈同點呼叫 `lyricsFX.notPlaying()` → 清時間軸、時鐘 inactive、顯示 `StatusText.noTrackPlaying`（`UI/StatusText.swift:14`，既有英文文案）。`.permissionDenied` 同樣清空。
- `PlayerChangeSignal.onChange` → `monitor.playerDidChange()` ＋ `positionClock.resync()`。
- `TrackDetails` 的 `genre` 由 `.trackChanged` 的 `TrackInfo` 帶不到（`TrackInfo` 無 genre）→ 兩案：(a) `NowPlayingRead` 加 `genre`／`duration`（nowPlaying 一次 run 多 2 個 AE）；(b) 由 `coverFlow.updateDetails` 回填。本案取 (a)：當前曲的 genre／duration 與歌詞同一次讀、同一個釘住的 specifier（D9 原則）。

### 2.9 i18n／文案／無障礙
- 新字串（Settings 標題、風格名、把手切換的 accessibilityLabel）三語入 `make_xcstrings.py NEW_KEYS`；運行時狀態字（來源標示 `synced`／`estimated`）進 `UI/StatusText.swift` 英文（E-05）。選單若加項，寫死英文（A-07）。
- 特效層 `accessibilityElement(children: .ignore)` ＋ `accessibilityLabel`＝當前行文字（VoiceOver 讀得到當前行，不讀整篇）。

### 2.10 元件 × 特徵向量 × 歌曲目標值：隨機但合身（探針 P8／P9 使用者定案，取代「家族 × 變體 × tone」）
- **使用者的定義（2026-10-03）**：「把字體、背景、進出場模式、整個特效全部做隨機分類的融合；每種組合帶一個特徵值；交給 Jev 評判哪個值適合這首歌。隨機要適當，要符合樂隊的特點：Cradle of Filth 是黑金屬字＋哥德／交響背景，套到 Mayhem／Immortal 就不對；Arch Enemy 的旋死字配硬核效果也不對。」「變體只有三種太少：交響金屬有激流偏交響的；電子樂 Chemical Brothers／Fatboy Slim／Daft Punk 不能只做三個變體；龐克的勒索信風格不適合 The Offspring，Blink-182 勉強，Green Day 一半一半。」
- **模型**：六個維度（字型、背景、進場、退場、效果、配色）各有一組元件；每個元件帶 **十軸特徵向量**（粗糙／戲劇／冰冷／侵略／速度／優雅／腐朽／明亮／彈跳／溫暖，0–1）＋**曲風標籤集**（black、symphonic、gothic、doom、death、melodeath、grind、thrash、heavy、power、hardcore、nu、industrial、techno、idm、electro、house、frenchhouse、bigbeat、ambient、punk、77punk、poppunk、skatepunk、rock、indie、pop…）＋可選 **硬規則**（`req`／`forbid`，例如「光柱」要求戲劇 ≥ 0.45、「邊緣砸入」禁止優雅 ≥ 0.8、「金色光暈」禁止粗糙 ≥ 0.75）。
- **歌曲目標值** `SongProfile{axes: [10], tags: Set}`：由 ① 曲風規則給預設向量與標籤（§2.5）；② Jev（opt-in）以 artist＋album＋genre 回答：十軸各一個 `score`（5 級、級距用具體情境描述）＋ 每個曲風標籤一個 `noul`（是否成立）；③ 使用者可在 Settings 手調。Jev 的 confidence 只用來決定「用 Jev 向量還是規則向量」的混合比例，不決定單一元件。
- **抽樣**：每個維度對所有元件算貼合度 `fit = 0`（標籤不交集或硬規則不過）或 `exp(−‖v_comp − v_song‖² / 2σ²)`（只在元件宣告的軸上算；σ=0.22），以貼合度為權重抽籤；效果維度抽兩個。配方 `recipe = (persistentID, lyricsRevision, schemaVersion, sessionNonce)` 一次播放內固定，下次播放重抽（Codex R4-Q7 的 session recipe 原則不變）。
- **元件目錄（預覽 v11 已實作，正式版抄進 `LyricsFXCatalog.swift`）**：字型 24（含嵌入的 Catacombs／Cenobyte／Grimoire／Dark Metal／Mirage／AmazDooM／Haunting／Xizor／Megadeth／DragonForce／Geizer＋Google OFL 字型）、背景 16（虛空、底片、飄雪、光柱、灰燼、火星、掃描線、網格、頻閃、霓虹、報紙、單色亮底、夕燒、紫霧…）、進場 15、退場 11、效果 14（負片硬切、抖動、影印錯位、血漬滴落、金色光暈、倒影、呼吸、紙片勒索信、RGB 分離、霓虹描邊、低音縮放、速度線、手繪底線）、配色 14。組合數以十萬計，但只有合身的會被抽到——這就是「變體太少」的答案。
- **樂團目標值示意**（手填，等 Jev 探針取代）：Mayhem／Immortal／Darkthrone／Burzum／Emperor／Cradle of Filth／Dimmu Borgir／Arch Enemy／Cannibal Corpse／Hatebreed／Nightwish／Epica／Fleshgod Apocalypse／Type O Negative／Iron Maiden／Slayer／Rammstein／Chemical Brothers／Fatboy Slim／Daft Punk／Aphex Twin／Offspring／Blink-182／Green Day／Sum 41／Ramones／Sex Pistols。Offspring 彈跳 0.3 vs Sum 41 0.85 是使用者給的判據（P9）。
- **Jev 探針**（R4-Q5 不變，改為十軸＋標籤）：20 組 artist＋album 盲標，比 Jev 向量與規則向量誰更接近使用者的盲標；拉不開就不做 Jev，只用規則向量＋手調。
- **測試**：`FitTests`（硬規則歸零、標籤閘門、距離單調）、`ComposerTests`（同 recipe 同配方、每維度至少一個元件通過否則退回預設、Mayhem 抽不到光柱／金色、Offspring 抽不到「彈出回彈」）、目錄完整性測試（每個元件的字型都在 bundle 內、授權檔存在）。

#### 2.10-舊 家族 × 變體 × tone（保留作歷史，已被上面取代）
- **三層結構**：`family`（8 個：frost／slab／cathedral／stencil／chrome／velvet／riot／mono；由 §2.5 的曲風規則決定，**穩定不抽籤**）× `variant`（每家族 3–4 個：模板權重、版面、路徑、配色不同；punk／rock 家族較多）× `tone`（4 個 0–1 旋鈕：rawness／polish／speed／density，驅動顆粒、抖動、光暈、出場時長、字級振幅）。
- **新鮮感與再現性的解法（Codex R4-Q7）**：一次「播放 session」內完全決定論；每次開始播放才抽新的 `recipe = (persistentID, lyricsRevision, styleSchemaVersion, variant, sessionNonce)`。seek、重繪、非同步回應都不改 recipe；測試注入固定 nonce；重啟後仍要新鮮就持久化 play counter。
- **預設（無 Jev，離線）**：family＝規則；variant＝以 recipe 抽籤；tone＝家族預設值（可在 Settings 手調）。
- **Jev 選型層（可選、opt-in、需 API key）**——辯論後的單一結論：
  - **不覆蓋 family**。曲風規則明寫 `Black Metal → frost`，弱分布（7 選 1 時 confidence 0.3 只等於最大機率約 0.4）不足以推翻使用者可辨識的家族識別性。Jev 只輸出 tone 4 軸的 `score`（每軸 5 級，級距用具體情境描述）與 variant 權重的參考；程式再以 recipe 抽籤，不取最大值。
  - **粒度 artist＋album**（track 太碎、artist 抹掉時代差）；album 空白退回 artist＋genre；合輯／現場盤不信任 album。state 只送 `{artist, album, genre}`，**不送歌詞**（著作權、隱私、token；Genius 現在也只送 title＋artist 搜尋，`GeniusSource.swift:48-57`），`year` 目前讀不到、不假設。
  - **快取鍵含模型與題目版本**：`(正規化 artist, album, 實際回傳的 model 版、question-schema 版)`；`jev-latest` 別名會變，不可無期限快取。回應套用時要與當前 recipe 的世代一致，否則丟棄。
  - **先探針後採用**（R4-Q5）：至少 20 組 artist＋album（含同一 artist 的不同時期專輯；必含 Mayhem／Cradle of Filth、Sum 41／The Offspring／Ramones、AC/DC／Van Halen、Metallica／Megadeth 對照組）。使用者先盲標每組期望的 family 與 tone，基線＝本地規則；比較 family 一致率、tone 的順位相關、對照組「朝期望方向拉開」的比率、同輸入重複的穩定性。Jev 沒有顯著贏過規則或拉不開對照組 → 不採用，投資改放模板池與 session recipe。
  - 既有程式的改動點：`HTTPClient.post` 只有 form（`Infra/HTTPClient.swift:19-22,63-69`）→ 加 JSON body 的 `post(_:json:headers:timeout:)`＋Mock；`ConfigStore.Key` 加 `typesafeAPIKey`（Keychain，與 Genius token 同路：`SecretStore.swift:5-9`）＋ Settings 欄位＋刪除；失敗（無 key／離線／timeout 2 s／429／529）一律退回預設層，不阻塞繪製。
  - 成本與事實（docs 2026-10-03）：`POST https://api.typesafe.ai/v1/systemone`、Bearer key、`model: "jev-latest"`、回 `probabilities`＋`confidence`；$0.042／百萬輸入 token，輸出免費；一次請求約 300 token → 整個曲庫約 2,000 張專輯 ≈ 0.6M token ≈ 0.03 美元；英語為主、CJK「可處理但不同等」（曲庫「ロック」3,967 首要實測）。

## 3. 建置順序（分三段，段間可停）
- **A1 契約與時間（不碰繪製）**：§2.2 三欄位＋白名單＋H-20、`lyricsChanged` 事件、§2.3 時鐘（錨點／重錨／offset）、§2.4 層 1＋層 3、`lyricsRevision` 守衛、§2.5 判定、§2.1 偏好與可見性扇出。全部以非繪製的單元測試收口；實機量測 AE 延遲分布與 offset（§8）。
- **A2 `mono` 繪製與實測**：§2.7 引擎＋`mono`、把手切換、DEBUG 預覽場景（§4）、Instruments 量每幀耗時。交付：切換後看到 `mono` 風格隨播放走、暫停停住、seek 跟上。（Codex R1-6：A 是最易失敗的一段，拆成 A1／A2 讓 busy／佇列／世代守衛的問題在無畫面時先發火。）
- **B 風格**：六種金屬風格逐一做，每種先出探針（靜態 1 張＋6 秒錄影）給使用者反應，改到「對」為止再做下一種（§4）。
- **C 同步來源**：層 2 LRCLIB（若 §9-A 拍板進 v1）。
- **D Jev 探針（可選）**：使用者取得 TypeSafe API key 後，先用腳本跑 §2.10 的 20 組盲標探針；過了才做 opt-in 的 Jev 層。

## 4. 探針（審美是默會知識：先做便宜的具體物讓使用者反應）
- DEBUG 預覽場景 `App/UITestSupport/LyricsFXPreviewScenario`：固定歌詞（fixture：Metallica／Emperor／Dimmu Borgir 各一段，含 `[Chorus]`）、假時鐘、環境變數指定風格與時間點；XCUITest `LyricsFXPreviewUITests.testStyleStills` 對每種風格在「進場／停留／サビ／退場」四個 t 各截一張、裁切到視窗、落 xcresult 附件；另錄 6 秒 GIF。
- 使用者只回「對／不對＋一句」；每條「不對」改成一條規則記進風格表（§2.6），三輪內收斂；被全盤否定＝提取成功，不辯護。

## 5. 測試（TDD：先紅後綠；紅燈摘要回填 §8）
- `GenreStyleResolverTests`：表驅動，用 §1.2 的真實標籤（含尾端空白、斜線複合、ロック、空字串）。
- `LRCParserTests`：單標籤、一行多標籤、ID 標籤略過、CR／CRLF、雜訊頭行、毫秒 2／3 位。
- `LyricsTimelineEstimatorTests`：單調遞增、落在時間窗內、段落標籤不出現在文字、`isChorus` 標記、間奏配時、最短行時長、空歌詞→空時間軸、duration 0 → 空。
- `PlaybackPositionClockTests`（`GatedPollClock`＋`MockMusicClient`）：錨點內插、暫停時時間凍結但 AE 仍每 6 s 讀一次、seek 重錨、容差內不動、offset 生效、persistentID 不符丟棄、不可見或 `status != .present` 不讀、`resync` 立即讀、Editor busy 中照讀且不碰 Editor。
- `PlaybackPositionClockTests` 追加：暫停時 6 s 低頻讀、暫停→播放無通知時由輪詢恢復、busy 中不讀且解除後補讀。
- `LyricsFXViewModelTests`：`.notPlaying` 清空並停讀、`.permissionDenied` 清空、`status != .present` 不建時間軸。
- `NowPlayingMonitorTests.lyricsChangedForSameTrack`：同曲改詞 yield `.lyricsChanged`、文字相同不 yield、日誌不含文字。
- `LRCAlignmentTests`：對齊率門檻、別曲（對齊率低）棄用、雜訊頭行不影響、未對齊行內插單調、`lyricsRevision` 不符丟棄。
- `LRCLIBSyncedLyricsSourceTests`（`MockHTTPClient`）：200／404→search／500／逾時／非 JSON／`instrumental=true`、快取命中、退避期間不打網路。
- `GlyphTemplatesTests`：每個模板在 p=0／1 的邊界值、alpha ∈ [0,1]、scale > 0；`GlyphPersonalityTests`：同種子同個性、t0 單調不早於詞首、連發間距 30 ms。
- `LyricsFXFrameTests`：同 seed 同輸出（跨進程：seed 由 fnv1a64 算，測試用固定字串）、glyph 在畫布內、opacity 範圍、t 在時間軸外無字、サビ參數生效、關鍵字粒子命中、七種風格都跑一遍不崩、`status != .present` 時只有背景與狀態字。
- `ConfigStoreRaisedLayerStyleTests`、`SettingsViewModelTests`（新增 group）、`AppModelLyricsFXTests`（可見性扇出、signal 扇出、寫入後更新、降下時時鐘停）。
- `LyricsFlowReducerTests`：確認 reducer 無新事件、現有 surface 測試全綠（不動）。
- `MusicSelectorAllowListTests`：白名單 +3；負對照 +1（setter）。
- Scripts：`no_playback_gate.sh` 綠；`coverage_gate.sh`（新 `Services/` 檔 ≥ 80 %）；`python3 -m unittest`。
- E2E（**使用者在場 #1**）：`LyricsFXUITests`：把手切換→特效層出現（AccessibilityID）、重啟保留、減少動態效果→靜態。
- 實機（**使用者在場 #2**）：播一首 Black Metal → `frost`；暫停→停住；拖進度→典型 ≤ 2 s 跟上（量測值回填）；換歌→換詞；Editor 寫入→升回時是新詞；在 Music.app 直接改當前曲歌詞→特效更新；已標記無詞的曲→背景＋狀態字；Music 內換歌時 Cover Flow 分支不受影響。

## 6. 驗證項、影響面、風險
- AE：可見且播放中每 2 s 一次 `playbackPosition()`（3 個屬性同一 run）；`trackDetails` 每批 +2 AE（量 p50 回填 §8）；`nowPlaying` +2 AE。
- 隱私：LRCLIB 送 artist／title／album／duration 到第三方（與 Genius／DarkLyrics 同級）；日誌只記 persistentID、來源、行數、毫秒，**不記歌詞文字**。lrclib.net 為 HTTPS，不需 ATS 例外。
- 快取：`~/Library/Caches/...` 可被系統清；不放 Application Support。
- 字型授權：若加 OFL 字型，About 附授權文字。
- 回退：偏好預設 `coverFlow`，使用者不切就看不到任何差異；特效層不可見時零 AE、零繪製。
- 熔斷點：Canvas 每幀 > 4 ms 且減粒子無效 → 停手記錄，改討論 CALayer 路線，不硬撐。

## 7. ACCEPTANCE 增修（實作時落）
- 新段 **I：歌詞特效**（I-01…）：切換與持久、位置跟隨（暫停／seek／換歌）、三層時間軸、曲風判定表、七風格各一條探針簽字、減少動態效果退化、日誌不記歌詞、無播控（白名單 +3 讀取）。
- H-20：白名單文字加 `genre`／`duration`／`playerPosition`。D 段：Settings 新項。

## 8. 紅燈摘要／量測記錄（實作時回填）

## 9. 待拍板（Codex 辯論後只留單一結論；使用者偏好類直接問）
- A. LRCLIB 進 v1 還是 v2？（隱私與範圍，使用者定；技術上「只借時間不借文字＋對齊門檻」已把別曲風險關掉）
- B. 曲風對應表的優先序：black 壓過 death？Rock／ロック／Hard Rock 走 `mono` 還是 `chrome`？Viking／Folk 走 `chrome` 還是 `frost`？（使用者口味）
- C. 已定案（2026-10-04）：切換只用把手右端的兩格圖示按鈕＋Settings 預設；**不加選單項、不加快捷鍵**。
- D. 字型：使用者已指定黑金屬用 Midnight Grave 式字型（商用）；需決定購買授權內建，或改用 OFL 替代（Butcherman／Nosifer／Metal Mania）。日文與其他家族的 OFL 字型內建清單見 §2.6（約 10 枚，體積要量）。
- E. 來源標示 `synced`／`estimated` 要不要顯示（使用者）。
- F. 位置時鐘：錨點法＋播放中 2 s／暫停 6 s＋容差重錨＋offset 設定＋接 BusySource——R2 已收斂（Codex 勝兩條、我讓步），R3 確認。
- G. 引擎路線 `Canvas`＋`TimelineView`＋純函數 plan——Codex R1 方向同意，附帶條件（FNV、periodic、perf 先測）已併入。
- H. `status != .present` 時特效層畫「背景＋狀態字」而不是退回 Cover Flow——R2 Codex 同意（補：狀態字走 overlay）。
- I. 家族加 `riot`（龐克；曲庫 Punk Rock 55＋Punk 21＋emo-rock 42）——使用者看 v3 後定。
- J. Jev 選型層：要不要申請 TypeSafe API key 跑 20 組盲標探針（使用者取得 key；探針不過就不做）。

## 附錄 A　評審記錄
### A.1 Codex R1（gpt-5.6-terra，medium；2026-10-03）
| # | 論點 | 提出方 | 分揀 | 狀態 | 證據 |
|---|---|---|---|---|---|
| 1 | 別軸偏好 `RaisedLayerStyle`，不擴 `LyricsSurface` | 我 | 一手資料 | 我勝（Codex 同意；補「Settings 改值也要扇出可見性」） | `LyricsFlowReducer.swift:98-125,146-181`、`AppModel.swift:137,345-352` |
| 2 | 三個 getter＋白名單＋H-20 足以守住無播控 | 我 | 一手資料 | 我勝；`setPlayerPosition:` 負對照價值小（既有 `shuffleEnabled {get set}` 已蓋）→ 改為不加 | `MusicSelectorAllowListTests.swift:8-37`、`SelectorAllowList.swift:4-37` |
| 3a | 「可見 ⇒ 不 busy」 | 我 | 一手資料 | Codex 勝（自查同發現） | `LyricsFlowReducer.swift:98-102`、`EditorViewModel.swift:106-120,173-191` |
| 3b | 時鐘是否要接 BusySource | 雙方 | 一手資料 | **open → R2**：我主張不接（B-02 目的＝防輪詢換曲改寫 Editor；時鐘不發換曲語意） | `ACCEPTANCE.md:31` B-02、`MusicAppleEventsClient.swift:33` |
| 3c | 1 Hz 不能保證 seek ≤ 1 s | Codex | 一手資料 | Codex 勝 → 驗收改「典型 ≤ 2 s、量測」 | `MusicAppleEventsClient.swift:217` |
| 4a | 顯示 LRC 文字、不比對 | 我 | 一手資料 | Codex 勝 → 改「只借時間、對齊門檻、Music 文字為準」 | 計劃 §2.4 |
| 4b | 世代守衛只用 persistentID | 我 | 一手資料 | Codex 勝 → `(persistentID, lyricsRevision)` | 計劃 §2.4 |
| 5a | `Hasher` 不決定論 | Codex | 一般原則 | Codex 勝 → fnv1a64 | — |
| 5b | reduceMotion 下靠 Observable 1 s 更新 | 我 | 一般原則 | Codex 勝 → `TimelineView(.periodic)` | — |
| 6 | A 段要拆 A1／A2 | Codex | 價值判斷 | 採納 | — |
| 7① | 升起 ≠ 有詞（markedNone／unknown 也升） | Codex | 一手資料 | Codex 勝 → §2.1「背景＋狀態字」（H 項 R2 確認） | `LyricsFlowReducer.swift:110-117,146` |
| 7② | 同曲改詞無事件 | Codex | 一手資料 | Codex 勝 → `lyricsChanged` 事件 | `NowPlayingMonitor.swift:216-218` |
Codex 最擔心的一點：把 `surface == .coverFlow` 誤當「可安全顯示 FX」。→ 已以 §2.1 的 `status` 同源判定處理。

### A.2 Codex R2（2026-10-03）
| # | 論點 | 提出方 | 分揀 | 狀態 | 證據 |
|---|---|---|---|---|---|
| 3b | 時鐘不接 BusySource | 我 | 一手資料 | **Codex 勝**：B-02 註解是「避免打斷使用者操作」；共用序列佇列且 `run` 無預設 timeout，讀取排在寫入前會延後寫入；接上去代價近零 | `NowPlayingMonitor.swift:80`、`MusicAppleEventsClient.swift:33,223-245`、`EditorViewModel.swift:106-120,235-264` |
| H | `status != .present` 畫背景＋狀態字，不退回 Cover Flow | 我 | 一手資料 | 我勝（Codex 同意；補 overlay） | `LyricsStatus.swift:7-19`、`LyricsFlowPresentation.swift:12-27` |
| Q3 | 暫停時不讀 | 我 | 一手資料 | **Codex 勝** → 暫停 6 s 低頻讀 | `PlayerChangeSignal.swift:20-26,43-47`、ACCEPTANCE B-01 |
| Q4 | `.notPlaying` 未定義 | Codex | 一手資料 | Codex 勝 → `lyricsFX.notPlaying()` | `LyricsFlowReducer.swift:84-85` |
| Q5 | A1→A2→B→C | 我 | 價值判斷 | 一致 | — |
Codex 最擔心的一點（R2）：暫停時停讀造成通知漏失後永不恢復。→ 已改為暫停 6 s 低頻讀。最易失敗的一步：A1 的時鐘與 Music 通知／AE 佇列整合（停止、通知漏失、seek、換曲、寫入競爭）。

### A.3 Codex R3（2026-10-03，最終確認）
- Q1 異議兩處，皆為文字層：§5 測試描述「暫停不讀」與 §2.3 矛盾 → 已改；「同一 busy 旗標」實體未定義（`busySources` 為 monitor private，`NowPlayingMonitor.swift:61`）→ 已明記 `BusyLedger` 抽取與 `AppModel` 雙扇出。
- Q2 投入順序：無異議。Q3 最易失敗：A1 時鐘與 Music 通知／AE 佇列整合（含 busy 解除補讀）。Q4 最擔心：busy 閘門實體（已補）。
- 帳本無 `open` 項，收斂。

## 附錄 B　探針記錄（審美回饋，每條都轉成規則）
- **P0（2026-10-03，artifact v1）**：整行一起出現、下一行再一起出現。使用者：「相當於把整句歌詞當成一個整體突然跳出來……太生硬了」「希望可以做到每一個字都有它自己出現的特點」。→ 規則：逐字獨立原則（§2.6 前言）；引擎改為模板池＋個性（§2.7）。
- **P1（2026-10-03，artifact v2）**：七風格全部改為逐字獨立（各自時刻／模板／停留／變異／線條串連／殘留淡出）。待使用者反應。

### A.4 Codex R4（Jev 選型層，2026-10-03）
| # | 論點 | 提出方 | 分揀 | 狀態 | 證據 |
|---|---|---|---|---|---|
| Q1 | Jev 當預設決定系 | 我 | 一手資料 | Codex 勝 → 規則為真決定系，Jev 只做家族內補正且先過探針 | TypeSafe docs（System One＝型付き判定，非世界知識基準） |
| Q2 | artist＋album 粒度 | 我 | 一手資料 | 我勝（條件：album 空白／合輯退避；`year` 現讀不到不得假設） | 計劃 §2.2 |
| Q3 | 不送歌詞 | 我 | 一手資料 | 我勝（補：「與 Genius 同級」只在不送本文時成立） | `GeniusSource.swift:48-57` |
| Q4 | family 用弱分布混合 | 我 | 一般原則 | Codex 勝 → family 固定，Jev 只動 tone／variant 權重；variant 抽籤我勝 | — |
| Q5 | 20 bands 探針 | 我 | 價值判斷 | Codex 補強 → 20 組 artist＋album、盲標、對照組、基線比較、重複穩定性 | — |
| Q6 | 與既有程式無衝突 | 我 | 一手資料 | Codex 勝 → `HTTPClient.post` 只有 form；需 API key 的 ConfigStore／Settings；快取鍵含模型版；套用時世代一致 | `HTTPClient.swift:19-22,63-69`、`SecretStore.swift:5-9`、`ConfigStore.swift:8-13` |
| Q7 | 每次新鮮 vs 同曲同貌 | 雙方 | 一般原則 | Codex 勝 → session recipe（§2.10） | 計劃 §2.7 fnv1a64 與「再生回數 seed」自相矛盾 |
Codex 最擔心的一點：把 Jev 的 confidence 誤讀成「樂團審美判斷正確的機率」，用弱根據蓋掉明確的曲風規則。→ 已以「family 固定、先探針、只動 tone／variant」處理。

## 附錄 B　探針記錄（續）
- **P3（2026-10-03，artifact v4）**：使用者對 v3：「每個文字都連著一條線……像納豆拉黏絲……太寒酸」「Mayhem 原始金屬裡抖動的那個樣子看起來像 Nu-Metal」。另附 Muse 整理的 README（Black Parade／Nargaroth lyric app）：風格＝動作語言，不是換皮；Nargaroth 的 shrapnel 引擎（詞從邊緣 140–260 ms 砸入中央堆、硬切、鼓點抖動＋白閃、全大寫、熱詞血紅）。→ 規則：全家族禁止串字線（§2.6）；黑金屬三變體改為彈片／寒霜／符文三種動作語言；其他家族裝飾改背景元素。注意：README 的鼓點來自 Web Audio 即時分析，本 app 讀不到 Music 的音訊，抖動與閃白只能綁在行首與詞首（估算時刻），這點要在 §0 非目標裡保持。
- **P2（2026-10-03，artifact v3）**：使用者對 v2：「還是太規律了……首字母大寫、第一個單詞斜著出現；後續單詞從四面八方任意方向、任意軌跡滑入；多做幾個模板，每次新鮮；同是黑金屬下一首換變體；龐克變體更多；樂團之間差異（Mayhem／Cradle／Immortal、Sum 41／Offspring／Ramones、AC/DC／Van Halen、Metallica／Megadeth）」。→ 規則：§2.10 三層結構（family × variant × tone）＋ session recipe；模板池加 swoop／fling／orbit／stamp／tumble／slant，詞共用隨機飛行方向；首詞大寫＋斜出；新增 riot（龐克）家族 3 變體；chrome／mono 各 4 變體。v3 另附「樂團示意預設」（手填的預期值，非 Jev 輸出）讓使用者感受 tone 旋鈕。
- **P4（2026-10-03，artifact v5）**：使用者：「血飛濺太假，散狀紅點太次」「要有 Black Metal 的冰冷、原始與侵略感」；並要求「查我的曲庫風格分類，按現有分類覆蓋全部，含 J-Pop」。→ 規則：禁撒點；血＝暗紅漬＋粗滴；黑金屬質感＝底片顆粒、暈影、刮痕、閃爍、負片硬切；家族改為依曲庫採樣的 14 個（§2.5）。
- **P5（2026-10-03，artifact v6）**：使用者：符文變體可以；A 彈片與 B 寒霜字體換成 Midnight Grave 那種尖刺滴血字；大教堂背景拱線、絲絨角落藤線「太醜，直接去掉」。→ 規則：背景不得有程式畫的結構性裝飾（§2.6）；黑金屬 A／B 字型改尖刺滴血字（預覽用 Butcherman 代）。
- **P6（2026-10-03，artifact v7）**：使用者：「jrock／rock 分成一類，日本的單獨獨立出一個體系，英文系的 rock 是另一個」「黑金的字體還是差點，偏圓潤了，要見棱見角的；Butcherman 那種我感覺死亡金屬比較合適」。→ 規則：兩體系（§2.5）；英語 `rock` 家族從 `chrome` 拆出（Metal 單獨）；`jpop` 從 `pop` 拆出；黑金屬 A／B 字型改 Metal Mania＋程式尖刺滴落（`graveSpikes`），Butcherman 給 `slab`。
- **P7（2026-10-03，artifact v8／v9）**：使用者：「加幾個細長的三角誰不會」「去找開源、免費、允許商用的類似字體」「Wolfsfifth 不要，其他都還可以」「Butcherman 一看名字就是死亡金屬」。→ 規則：不得用程式畫的假裝飾代替字型；字型清單見 §2.6 表（Catacombs／Cenobyte／Geizer 嵌入預覽）。
- **P8（2026-10-03，artifact v10）**：使用者定架構：「字體、背景、進出場、特效全部隨機融合，每種組合帶特徵值，交給 Jev 評判；隨機要適當、符合樂隊特點（Cradle of Filth≠Mayhem；旋死字≠硬核效果）」。→ §2.10 改為元件 × 特徵向量 × 歌曲目標值模型；預覽加組合模式。
- **P9（2026-10-03，artifact v11）**：使用者：「變體只有三種太少」，舉交響金屬／電子（Chemical Brothers、Fatboy Slim、Daft Punk）／龐克（Offspring 不跳、Blink-182 微跳、Green Day 一半、Sum 41 跳、Ramones、Sex Pistols）。→ 元件目錄擴到電子與龐克；加彈跳、溫暖兩軸；新增上述樂團目標值。
- **P10（2026-10-04，artifact v12）**：使用者：「Rammstein 明明是工業金屬，為什麼這麼 Nu-Metal？顏色鬧的」。根因：Rammstein 目標值標了 `industrial＋nu`，而酸綠配色、掃描線、網格、打字機、切帶、RGB 分離、機甲字都同時掛 `industrial` 與 `nu` 標籤。→ 規則：**工業金屬與 Nu-Metal 不共用任何元件**；工業金屬專屬元件＝鋼灰＋火焰紅／純黑＋一種紅、冷鋼板＋頂燈、行首火焰噴發、整詞重砸（行軍節拍）、每詞整屏下沉、字緣灼熱紅光、燒盡退場、紀念碑式大寫／德式 fraktur；Rammstein 目標值＝冷 0.8、戲劇 0.85、速度 0.35、彈跳 0。測試加 `ComposerTests.rammsteinNeverGetsNuMetalComponents`。教訓：標籤共用是串味的根源，新增元件時每個標籤都要問「這個樂團會不會被它帶歪」。
- **P11（2026-10-04，artifact v13）**：使用者：「Cradle of Filth 的交響黑金屬字體和風格太溫柔，整體像 Nightwish」。根因：Cradle 目標值侵略只有 0.6、優雅 0.8、明亮 0.3，且光柱／金色光暈／緩升／金＋深藍／Cinzel 這些溫柔交響元件沒有任何對侵略的限制。→ 規則：**溫柔交響元件一律 `forbid aggression ≥ 0.65`**（光柱、金色光暈、緩升、金＋深藍、Cinzel、Cormorant 斜體、Haunting、字級呼吸）；交響黑金屬專屬元件＝深紅濃霧＋重暈影、鞭劈進場、墨黑＋鮮血紅＋骨白。Cradle＝侵略 0.88、腐朽 0.7、明亮 0.05、優雅 0.45；Dimmu＝侵略 0.8、冷 0.6。測試加 `ComposerTests.cradleNeverGetsNightwishComponents`。

- **P12（2026-10-06，B1 真視窗預覽：Catacombs＋飄雪＋煙霧進場＋溶解退場＋影印錯位＋抖動）**：使用者：「從無到有的漸入漸出效果，持續時間稍微長了一點點，導致字有點發虛」。→ 規則：淡入型進場（condense、smoke、rise）時長縮短 40%；殘留淡出（fade／dissolve）降暗 0.7→0.4 s、淡掉 2.4→1.4 s；砸入、鞭劈等快速進場不動。測試 `ComposedStyleFrameTests.fadeInEntrancesAndTrailsAreShortenedP12`。改後使用者：「這回可以了」。

- **B1 探針簽字（2026-10-06）**：黑金屬（genre＝Black Metal）與交響（genre＝Symphonic Metal）各 3 次重抽的組合配方，使用者：「都是對的，沒問題」。

- **P13（2026-10-07，B2 批 1 rock 系 9 團）**：記錄在 `docs/plans/2026-10-07-lyrics-fx-b2-artist-profiles.md` §7.3（移除西部木刻；裝飾藝術圓角不給 The Killers）。
- **P14（2026-10-09，B2 批 2 龐克系 12 個對象，本機探針頁 v15）**：使用者：「整體上還差不多，沒什麼問題」；「Blink-182、Sum 41 和 Green Day……可以把勒索信的這個效果加進去」；看過修改後：「這回對了。行，就這樣」。→ 規則：**勒索信（每字一張歪斜色紙）給 Ramones、Sex Pistols、Blink-182、Sum 41、Green Day；The Offspring 與其他流行龐克團不給**（修訂 2026-10-03 的「Blink-182 勉強、Green Day 一半一半」）。同批確立的做法：新元件搬進 app 時只帶該批專屬的標籤；舊團被新元件連帶改到時要一起進探針簽字。細節與預檢結果見 `docs/plans/2026-10-09-lyrics-fx-b2-batch2.md` §9.3–§9.4。

## 附錄 C　LRCLIB 缺歌時的備用來源（2026-10-04）
- **使用者提供的對比**（`~/Downloads/lrclib-missing-synced-lyrics.txt`）：曲庫中 LRCLIB 拿不到時間軸的共 3,990 首。①完全找不到 1,682 首（289 個樂團，地下黑金屬為主：Rossomahaar 54、Marduk 48、Avathar 41、Gehenna 31…）；②有歌詞但無時間軸 1,888 首（AC/DC 79、HIM 68、Oasis 63、Marduk 43、Immortal 37、The Offspring 36…）；③純音樂 385 首（Nightwish 50、LINKIN PARK 44、Daft Punk 17…）。
- **實測**（從①②隨機抽 40 首，seed 20261004，原始結果 `docs/plans/2026-10-04-lyrics-fx-sync-source-probe.json`）：

| 來源 | 有時間軸 | 備註 |
|---|---|---|
| QQ 音樂 | 9／40 | 非官方 API；②類（主流樂團、Live 版、Remaster）命中多 |
| 酷狗 | 4／40 | 非官方 API；KRC 格式有**逐字**時間 |
| 網易雲 | 0／40 | 舊 search 端點全數 notfound，疑已改加密介面；TBD |
| 三者合計 | 10／40（25 %） | ①類地下黑金屬幾乎全滅，只有 QQ 有純文字 |

- **決定的退路順序**（每首歌只要一層命中就停）：①Music 欄位內嵌 LRC → ②LRCLIB → ③QQ 音樂 → ④酷狗（有 KRC 時取逐字時間）→ ⑤**使用者打軸**（見下）→ ⑥估算。所有外部來源都「只借時間、不借文字」並走 §2.4 的對齊門檻；③④是中國服務的非官方 API，可能失效且條款灰色，**預設關、Settings opt-in**，送出內容只有 artist／title／duration。
- **⑤使用者打軸**（解決剩下約 75 %）：Editor 加「打軸」模式，播放時每唱到一行按一次空白鍵，產生行級 LRC；存在 app 自己的快取（以 persistentID 為鍵），**不寫回 Music 的 lyrics 欄位**（保持 1.x 寫入行為不變）；上傳 LRCLIB：使用者定案（2026-10-04）**先不做**。
- **⑥估算**照舊；畫面角落標 `~`。
- **③純音樂 385 首**：使用者定案（2026-10-04）：**預設退回 Cover Flow**，特效層不接手。
- **評估過但不採用（現階段）**：本機語音辨識對齊（macOS SpeechAnalyzer 可給逐字時間，但黑／死金屬嘶吼辨識率低，且需讀取音訊檔；列為後續 spike，TBD）；Musixmatch／Spotify／Apple Music 歌詞（需帳號憑證或開發者 token，不碰）。
- **非中國來源實測**（同一批 40 首）：
  - Musixmatch（匿名 desktop token）：表面 40／40「有時間軸」，**實為反爬蟲誘餌**——每首都配對成 `Drake – NOKIA`、內容是亂碼假歌詞（`Wob gopini den…`）。匿名用法不可用；正式 API 需付費授權。
  - Megalobiz：40／40 回 HTTP 403（擋爬蟲）。
  - Apple Music／Spotify／Deezer：歌詞都要使用者帳號憑證（訂閱 token 或 cookie）才能取，且是非公開介面；Music.app 的 AppleScript `lyrics` 只給純文字，讀不到它的時間軸。
  - YouTube Music（LyricFind 時間軸，lyrimuse 有用）：未測，TBD spike。
  - 結論：目前**沒有可用的非中國免費時間軸來源**；非中國的路只剩「付費 Musixmatch API」或「使用者自己的帳號憑證」兩種，都需要使用者另外拍板。

### C.1 時間軸的存放位置（使用者定案，2026-10-04）
- **全部存在同一個資料夾**，不分「抓來的」和「自己打軸的」：預設 `~/Library/Application Support/com.ibridgezhao.azathothswhisper/Timings/<persistentID>.json`。每個檔內記 `source`（embedded／lrclib／qq／kugou／user）、`lyricsHash`、`lines:[{index,start}]`、`fetchedAt`。（取代 §2.4 原寫的 Caches 位置。）
- **之後要 iCloud 同步**：Settings 加「時間軸資料夾」選項，可改指向 iCloud Drive 的普通資料夾（例如 `~/Library/Mobile Documents/com~apple~CloudDocs/Azathoth's Whisper/Timings/`），換位置時把現有檔案搬過去。用的是 iCloud Drive 的一般檔案同步，不是 app 專屬的 iCloud 容器——後者需要付費開發者帳號的簽名權限，本 app 是 ad-hoc 簽名，拿不到。
- 多台 Mac 同時改同一首：以 `fetchedAt` 較新者為準；`source=user` 永遠勝過下載來源。

### C.2 時間軸取得的時機（2026-10-04，Codex R5 同意）
- **寫入歌詞成功後自動接著做**（`editor.onSaved`／`batch.onLyricsWritten` 觸發），另外在特效層顯示時對尚無時間軸的歌補做一次（曲庫裡本來就有詞的歌）。兩個觸發點共用一個 `TimelineProvider`。
- 與寫入解耦：取得不在 busy 區間內、不影響寫入成敗與速度、失敗也不回滾寫入。
- 找不到時**不跳 modal**（Batch 連寫幾十首會轟炸、也會打斷寫入後升回）：Cover Flow 徽章／Editor 狀態欄靜靜標「無時間軸」，旁邊給「打軸」入口；特效層正在顯示且這首沒有時間軸時，畫面上給一次性的非模態提示。
- Codex R5 最擔心：兩個觸發點並發 → `TimelineProvider` 必須 per-persistentID 去重、可取消、寫檔前再驗一次 `lyricsHash`，避免舊結果蓋新。

### C.3 國外來源實測與退路定案（2026-10-04，取代 C 的退路順序與 C.2 的「打軸」入口）
- **使用者定案**：**不做任何人工打軸**（「我就是要徹底避開人工去打時間軸這件繁瑣的事，絕對不想加」）。C 的第⑤層與 C.2 的「打軸」按鈕全部刪除。
- **同一批 40 首實測**（原始結果 `docs/plans/2026-10-04-lyrics-fx-sync-source-probe.json`，逐首核對了配對到的歌手與曲名）：

| 來源 | 有時間軸 | 備註 |
|---|---|---|
| YouTube Music（InnerTube，ANDROID_MUSIC 身份取 timedLyricsData） | 16／40 | 免帳號；時間軸實際出自 LyricFind 或 Musixmatch（回應裡的 sourceMessage）；含地下黑金屬（Averse Sefira、Marduk、Retribution、Black Abyss、Mystic Circle）。另有 10 首是配對失敗（曲庫拼字 `Watehers`、`The` 前綴、`Æ`），改進比對後可再多收幾首 |
| Deezer（匿名 JWT＋GraphQL） | 2／40 | 免帳號；只有主流樂團 |
| QQ 音樂／酷狗 | 10／40 | 中國平台，見 C |
| Amazon Music | 不可行 | 沒有公開或匿名的歌詞介面；lyrimuse 是讀本機 Amazon Music app 已快取的歌詞，前提是你裝了它並播過該曲 |
| 國外合計 | 16／40 | 國外＋中國合計 17／40（約 42 %） |

- **定案退路順序**：①Music 欄位內嵌 LRC → ②LRCLIB → ③YouTube Music → ④Deezer → ⑤QQ 音樂 → ⑥酷狗 → ⑦估算（角落標 `~`）。③④⑤⑥都是非公開介面，可能失效、條款灰色；③④預設開，⑤⑥預設關（使用者偏好國外）。每層都「只借時間、不借文字」並過 §2.4 對齊門檻。YouTube Music 的 Android 客戶端版本號是寫死的常數，失效時要跟著 ytmusicapi 更新（lyrimuse 註解同樣警告）。
- 比對改進（實作時做）：曲名去括號註記、去 `The`、`Æ→AE`、容許 1 字元編輯距離，以 `duration` 差 ≤ 3 秒當必要條件。
- 剩下約 58 % 由估算接手。若之後仍想提高，唯一不需人工的路是「本機音訊對齊」（讀曲目檔案、用 macOS 語音辨識給逐字時間）；黑／死金屬嘶吼辨識率是最大風險，列為後續 spike，TBD。

### C.4 「沒有時間軸」的定義與重試（2026-10-04 定案）
- 定義：第 1–6 層全部試完都沒拿到。某層只有純文字、或時間軸對不上 Music 欄位文字（對齊率未達門檻）也算沒拿到。與歌詞寫入成敗無關：寫入失敗不找；寫入成功後才找；找不到不影響已寫入的歌詞。
- 沒有時：走估算、角落標 `~`；Cover Flow 徽章／Editor 狀態欄標「無時間軸」，不跳提示、不給任何人工操作入口。
- 自動重試：歌詞被改（lyricsHash 變）時立即重找；播放到且距上次查找 ≥ 7 天時重找（外部資料庫會陸續補資料）。

## 實作交接（2026-10-04）
- 使用者：「下個 session 開始實作，實作時新開分支」。分支名建議 `feature/lyrics-fx`，從 `main` 開；走 `/fatboyslim`，投入順序 A1 → A2 → B → C（§3）。
- 預覽頁與組合器原始碼、嵌入用字型檔與授權檔：`docs/plans/2026-10-03-lyrics-fx-assets/`（未 commit；拍板後字型搬 `Resources/Fonts/`，授權文字進 About）。最新預覽 artifact：https://claude.ai/artifact/JnudgYuy2NLSrQVqHt65BK
- 尚待確認：Cenobyte、Mirage Gothic 的商用授權；Megadeth 字型商標風險。
