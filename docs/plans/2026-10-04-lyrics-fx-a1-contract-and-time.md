# Lyrics FX — A1「契約與時間」實施計劃 v5（已實作；評審與實機量測見 §8）

母計劃：`docs/plans/2026-10-03-lyrics-fx-mode.md`（以下稱「母計劃」）。本檔只管 A1，不重開母計劃已定案的決定。
分支：`feature/lyrics-fx`（自 `main` 558aed4 開出）。模式：normal（全程同步、無後台等待）。

## 0. 複述
- **目標**：把歌詞特效需要的「資料契約」與「時間」做出來，畫面一個像素都不動。
- **範圍＝使用者開工口令的 6 項**（不多不少）：
  1. Music 唯讀新增 `genre`／`duration`／`playerPosition` 三個 getter，同步改選擇器白名單與 ACCEPTANCE H-20。
  2. 同曲改詞事件 `lyricsChanged`、未播放事件的處理。
  3. `PlaybackPositionClock`：錨點法、播放中 2 s／暫停 6 s、容差重錨、offset、接 `BusySource`（`BusyLedger` 抽取）。
  4. `LRCParser`、`LyricsTimelineEstimator`、對齊門檻、`lyricsRevision` 世代守衛。
  5. `GenreStyleResolver`（日本語系／英語系＋家族判定）。
  6. 時間軸存放：`Timings/<persistentID>.json`（來源、lyricsHash、7 天重試）。
- **非目標**：任何 View／Canvas（A2）；`RaisedLayerStyle` 偏好與可見性切換 UI（母計劃 §3 原把它列在 A1，使用者本次口令未列 → 延到 A2，見 §9-Q1）；組合器（B）；LRCLIB 等外部來源（C）；Settings；字型；commit 到 main、push。
- **使用者可見的行為變化**：無。唯一的執行期差異是 `nowPlaying()` 每 3 秒多讀 2 個屬性（genre、duration）。時鐘在 A1 沒有任何生產路徑會把它啟動（可見性要 A2 才接），所以 A1 期間零位置讀取。

## 1. 基線（2026-10-04 11:30 實測）
- 全量單元：827 tests／86 suites，**僅 `CoverFlowStripRenderGeometry` 7 斷言紅**（已知基線，與 main 2854c35 的 commit 記錄一致）。命令帶 skip `overlappingLoadSuspendsPollingUntilLastCompletes()` 與 120 s 超時。
- coverage_gate：Services+Infra 95.3%；豁免檔 `MusicAppleEventsClient.swift` **378／400 行預算，剩 22 行**。→ 硬約束：AE 端新增的可執行行數必須 ≤ 22；超過要使用者批准調高預算（§9-Q5）。

## 2. 概念表（31 號方法：定義／身份判據／邊界）
| 概念 | 定義 | 身份判據 | 邊界 |
|---|---|---|---|
| `TrackMetadata` | 當前曲的 genre 與 duration，與歌詞同一次讀取 | 隨 `NowPlayingRead` | `nil`＝讀不到（開放世界），`""`／`0`＝Music 說沒有（封閉世界），不折疊 |
| `PlaybackPosition` | 一次位置讀數 `{persistentID, seconds, state, readAt, roundTrip}` | 單次讀取 | 不是「當前位置」，是過去某時刻的樣本 |
| `LyricsFingerprint` | 歌詞文字的指紋：`LineEndings.normalized` 後 SHA-256 前 16 bytes hex | 字串相等 | **全專案唯一定義**：monitor 判同曲改詞、時間軸存檔的 `lyricsHash`、VM 判「詞變了」都用它（同一語義只留一處） |
| `lyricsRevision` | VM 內單調遞增整數；換曲或歌詞指紋變更時 +1 | — | 與 persistentID 組成 `TimelineIdentity`；非同步結果套用前比對 |
| `LyricsTimeline` | 可顯示的時間軸 `{lines, source, duration}` | `TimelineIdentity` | 不存檔；存檔的是 `TimingRecord` |
| `TimingSource` | 時間從哪來：`embeddedLRC, lrclib, youtubeMusic, deezer, qq, kugou, estimated`（母計劃 C.3 順序） | rawValue | **一個 enum**；`estimated` 永不寫檔（型別層：`TimingRecord` 只收 `StoredTimingSource`＝去掉 estimated／embeddedLRC 的子集，見 §3.6） |
| `TimingRecord` | 一首歌一份的時間軸存檔 | persistentID | 「查過、沒有」也要存（7 天重試靠它）＝`outcome: .notFound` |
| `GenreStyle` | `{system: .japanese/.english, family}` | — | A1 只判家族；§2.10 的標籤集在 B 段 |

## 3. 設計（逐項；錨點已核）

### 3.1 三個 getter＋白名單＋H-20（項 1）
- `MusicTrackProto` 加 `@objc optional var genre: String { get }`、`@objc optional var duration: Double { get }`；`MusicAppProto` 加 `@objc optional var playerPosition: Double { get }`（`MusicAppleEventsClient.swift:9-25`）。
- 白名單 `MusicSelectorAllowListTests.swift:19-22`：app +`playerPosition`，track +`genre`、`duration`。母計劃 A.1#2 已裁：**不另加 setter 負對照**（既有 `shuffleEnabled {get set}` 已蓋）。
- `NowPlayingRead` 加 `metadata: TrackMetadata`（顯式 init，預設 `.unknown`，現有 5 個建構點不必改）。`nowPlaying()` 在讀完歌詞、記下 `lyricsFailed` **之後**再讀 genre、duration；**每次 accessor 之後立刻 snapshot `lastError`**（不得以一個最終 `throwIfFailed` 取代，Codex R1），失敗→該欄 `nil`；不得讓 metadata 失敗連帶讓曲目或歌詞失敗（現行 `:73-75` 的語義不變）。mock 模擬不了 per-selector lastError → `LiveMusicTests` 加實機冒煙。
- `PlaybackEvent.trackChanged` 加第三個關聯值 `metadata: TrackMetadata = .unknown`（Swift 允許關聯值預設值）：45 個建構點不必改；2 個 production 模式匹配點（`EditorViewModel.swift:75`、`LyricsFlowModel.swift:102`）與 1 個測試點改成三綁定（`_` 忽略）。
- **新協議方法** `func playbackPosition() async throws -> PlaybackPosition?`（母計劃 §2.2）：一次 `run` 內依序讀 `playerState` → 釘住 `currentTrack` 的 `persistentID` → `playerPosition`，`readAt`＝讀 position 前後兩個 `ContinuousClock.now` 的中點，`roundTrip`＝兩者之差。
  - **雙讀 ID**（Codex R1 勝）：`persistentID` → `playerPosition` → 再讀 `persistentID`，前後相同才回傳，不同回 `nil`。理由：position 是 app 屬性、不跟釘住的 track 走；時鐘的當前曲也可能還沒收到 monitor 的換歌事件，單讀 ID 無論前後都可能把新歌位置套到舊曲。代價 +1 AE（共 4）。`readAt` 只包住 position 那一次存取。
  - 狀態非 playing／paused → 回 `nil`。
  - **殘餘競態（明記、接受）**：`playerState` 在第一次讀 ID 前讀；若其後換到一首暫停中的新曲，雙讀 ID 一致仍可能把舊的 playing 狀態配上新曲位置。後果是至多一次讀數的狀態錯誤：錯當 playing 時下一次讀在 2 s 內、且 Music 的 playerInfo 通知會觸發 resync，立即修正。不再加第二次讀 state（會變 5 個 AE、吃豁免預算），Codex R2 同意此取捨需明記。
- **`TrackDetails` 照母計劃 §2.2 加 `genre: String?`、`duration: Double?`**（Codex R1 勝：已定案契約不在實作計劃裡改）：`Column` +2（每批 +2 AE），顯式 init 給兩欄預設 nil，37 個建構點不改；`detailsBudget` 與 S6 p50 在 T12 實機重量。
- 22 行預算：AE 端只做「讀屬性＋回傳原始值」，組裝與判斷（狀態過濾、中點計算）移到純函式 `PlaybackPosition.make(...)`（`Services/Music/PlaybackPosition.swift`，在覆蓋率內）。
- 替身：`MockMusicClient` 加可腳本化的 `playbackPosition` 回應＋呼叫計數＋逐次閘門；`InertMusicClient`、`CoverFlowUITestMusic`、`LyricsFlowUITestMusic`、`SerialAEQueueMusicClient` 回 `nil`（後者入佇列以保公平性語義）。
- ACCEPTANCE H-20：白名單文字加三個 getter，證據欄不變（同一組測試）。

### 3.2 `lyricsChanged` 與未播放（項 2）
- `PlaybackEvent` 新增 `case lyricsChanged(persistentID: String, lyrics: String)`，語義＝「同一首的歌詞快照變了，或由讀不到變成讀得到」（文件與註解照此寫，Codex R1）。
- monitor 記 `lastLyricsFingerprint: LyricsFingerprint?`（**只記指紋、不記文字**）：
  - `trackChanged` 時設成該次歌詞的指紋（歌詞讀失敗＝nil）。
  - 同 signature 時：本次歌詞非 nil 且指紋 ≠ 上次 → 更新並 yield `.lyricsChanged`。本次 nil（讀失敗）→ 不動、不 yield（讀失敗不是改詞）。上次 nil、本次讀到 → 也 yield（「這首的詞現在讀得到了」對 VM 是同一件事；見 §9-Q3）。
  - `notPlaying`／`forceRefresh` 清 signature 時一併清指紋。
  - 日誌：沿用 `read N reason changed=… lyricsChanged=…` 布林，不記文字與 ID。
- 既有消費者：`EditorViewModel.handle`、`LyricsFlowModel.handle` 加 `case .lyricsChanged: break`（註明 v1 只給 FX，母計劃 §2.8；修 Cover Flow 同曲改詞徽章另案）。`BatchViewModel` 用 `guard case`，不受影響。**原有行為零變化**。
- 本 app 自己寫入後，monitor 下一輪也會看到指紋變了而 yield `lyricsChanged`；VM 以指紋去重（§3.4），所以 `onSaved` 與 `lyricsChanged` 先後到都只 +1 次 revision。
- **未播放**：`notPlaying`／`permissionDenied` 由 AppModel 事件迴圈轉給 `LyricsFXViewModel.notPlaying()`／`.permissionDenied()`（母計劃 §2.8 R2-Q4）：清時間軸、時鐘 `setTrack(nil)`（停讀）、`statusText` 設 `StatusText.noTrackPlaying`／`StatusText.accessDenied`（既有英文常數，不新增文案）。

### 3.3 `PlaybackPositionClock`＋`BusyLedger`（項 3）
- `BusyLedger`（`Services/Music/BusyLedger.swift`，值型別）：把 `NowPlayingMonitor.swift:61,88-101` 的 Set 記帳抽出——`mutating func set(_ busy: Bool, source: BusySource) -> Transition`，`becameIdle`＝`wasBusy ∧ isIdle`（是轉移、不是現況；已空閒再送 false 不得觸發補讀，Codex R1），`var isIdle`。monitor 改用它，行為不變（既有 `NowPlayingMonitorSingleFlightTests` 13 條＋`NowPlayingMonitorTests` 守住）。
- `PlaybackPositionClock`（`Services/Music/PlaybackPositionClock.swift`，`@MainActor @Observable final class`）：
  - 注入：`music`、`pollClock: PollClock`、`now: () -> ContinuousClock.Instant`、`tolerance`（預設 0.5 s）、`offset`（預設見 §8；A1 不接 Settings）。
  - 狀態：`private(set) var anchor: Anchor?`，`enum Anchor { case running(origin: Instant), frozen(seconds: Double) }`。**只有 anchor 是 observable**；容差內不改值（母計劃 §2.7 R1-5 的前提）。
  - `position(at now) -> Double?`：running＝`(now − origin).seconds + offset`；frozen＝`seconds + offset`（offset 是顯示時間的固定平移，兩態一致才不會在暫停／恢復時跳動，Codex R1）；nil＝未知。
  - `setTrack(_ persistentID: String?)`：換曲清 anchor；nil＝停讀。`setActive(_:)`：只有 active ∧ 有 track 才跑讀取迴圈。
  - 讀取迴圈：讀一次 → 依最後一次狀態睡 2 s（playing）或 6 s（其他）→ 再讀。單飛（與 monitor 同模式）。
  - **生命週期世代守衛**（Codex R1 勝）：`generation` 在 `setActive(false)`、`setTrack(_:)`（**僅 ID 真的變了**；同 ID 為 no-op、不清 anchor，Codex R2）時 +1；每次讀取前擷取 `(generation, trackID)`，回來後 active ∧ 同 generation ∧ 同 trackID 才套用，否則丟棄（防停讀後舊回應把 anchor 復活）。規則：inactive 時 `resync()` 不讀；`setActive(false)` 取消睡眠中的迴圈 task；active 的 `resync()` 取消當前睡眠、立即讀（讀完重新排下一次睡眠）；進行中讀取時的 `resync` 合併成讀完再讀一次；busy 解除只排一次補讀。
  - 讀數處理：`nil`（沒在播）→ anchor＝nil；persistentID ≠ 當前 track → 丟棄；playing：以**不含 offset 的原始預測** `raw = (readAt − origin).seconds` 比較，`|raw − seconds| > tolerance` 或原 anchor 非 running → 重錨 `origin = readAt − seconds`，否則不動（含 offset 比較會讓 offset > tolerance 時每次都重錨，Codex R2）；paused／其他 → `frozen(seconds)`。錯誤：`notRunning` → anchor nil；其餘（含 permissionDenied）保留 anchor、下輪再試。
  - busy：`setBusy(_:source:)` 用自己那份 `BusyLedger`；非空閒時輪詢 tick 丟棄、`resync` 記下；轉為全部空閒時補讀一次（母計劃 §2.3 R2 Codex 勝）。
  - 日誌：讀數序號、狀態、是否重錨、roundTrip 毫秒；不記曲目。
- AppModel 接線：`editor.onBusyChange`／`batch.onBusyChange` 同時呼叫 `monitor.setBusy` 與 `positionClock.setBusy`；`playerSignal.start` 的回呼同時 `monitor.playerDidChange()` 與 `positionClock.resync()`（母計劃 §2.8）。
- `nextBoundary`（母計劃 §2.3）不在時鐘裡做：它需要時間軸，放在 `LyricsTimeline.nextBoundary(after:)` 純函式，A2 用到再加（A1 不做，YAGNI）。

### 3.4 時間軸：LRC、估算、對齊、世代守衛（項 4）
型別（`Services/Lyrics/LyricsTimeline.swift`）：`LyricsTimeline { lines: [TimedLine]; source: TimingSource; duration: Double }`、`TimedLine { start, end, text, isChorus, words: [TimedWord] }`、`TimedWord { start, end, text }`。
- **共用分行** `LyricsLines.parse(_ text) -> [LyricsLine]`，`LyricsLine.kind ∈ {lyric(String), section(name), blank}`：`LineEndings.normalized` → 逐行 trim；`^\[(.+)\]$` 且不像 LRC 時間戳 → section。估算與對齊共用這一份（一處定義）。
- **`LRCParser`**（`Services/Lyrics/LRCParser.swift`）：`[mm:ss]`、`[mm:ss.x]`、`[mm:ss.xx]`、`[mm:ss.xxx]`、`[mm:ss:xx]`；一行多標籤展開；`[ti:]` 等 ID 標籤略過；`[offset:±ms]` 套用（LRC 標準：正值＝提早）；enhanced `<mm:ss.xx>` 從文字中剝掉（A1 不用逐字時間）；空文字行保留為時間點但不顯示；依時間穩定排序。`isLRC(text)`：非空行中帶時間戳者 ≥ 50% 且 ≥ 1 行。
- **`LyricsTimelineEstimator`**（母計劃 §2.4 層 3 原樣）：時間窗 `[d×0.06, d×0.94]`；行權重∝字元數（去空白），行時長下限 1.2 s；空行／段落標籤＝gap 權重 0.6 行；`Instrumental|Solo|Intro|Outro|Break|Interlude` 標籤＝無字間奏權重 3 行；`Chorus|Refrain|Pre-Chorus|Post-Chorus|Hook` 之後到下一個標籤前 `isChorus = true`（標籤比對不分大小寫、只看冒號前，如 `[Chorus: X]`）；行內逐字∝字長（有空白按詞、無空白的 CJK 按字）。下限總和超過時間窗時整體等比縮放（仍單調）。`duration ≤ 0` 或無歌詞行 → `nil`。
- **`LyricsTimelineBuilder.build(lyrics:duration:) -> LyricsTimeline?`**：`isLRC` → 層 1（`embeddedLRC`，顯示 LRC 行文字；行 end＝下一行 start，末行 end＝duration 或 start+5 s）；否則層 3。
- **對齊門檻** `LRCAligner.align(lyrics:lrc:duration:source:) -> LyricsTimeline?`（母計劃 §2.4，給 C 段外部來源用，A1 先做純函式）：Music 的 lyric 行與 LRC 行各自正規化（小寫、只留字母數字——Unicode letters/digits）；單調向前比對，相似度＝`1 − 編輯距離/較長者長度` ≥ 0.8 才算對上；對齊率＝對上行數／Music lyric 行數 ≥ 0.7 才採用，否則 nil；未對上的行在前後已對上行之間等比內插（首段以 `d×0.06`、末段以 `d×0.94` 為邊界）；顯示文字永遠是 Music 的。
- **世代守衛**：放在 `LyricsFXViewModel`（`Features/LyricsFX/LyricsFXViewModel.swift`，`@MainActor @Observable`，**不含任何 View**）：
  - 狀態：`identity: TimelineIdentity?`（persistentID＋revision）、`fingerprint`、`status: LyricsStatus`、`timeline: LyricsTimeline?`、`genreStyle: GenreStyle?`、`statusText: String?`、`isVisible`。
  - `nowPlaying(track, lyrics, metadata)`：persistentID 變 → revision+1、`clock.setTrack`；同曲但指紋變 → revision+1。`status = LyricsStatus.resolve(lyrics:isMarked:)`，`isMarked` 由 AppModel 注入成 `lyricsFlow.isMarkedNoLyrics`（與 Editor 同源，`AppModel.swift:124`）。`status == .present` 才建時間軸。
  - `lyricsChanged(persistentID:lyrics:)`、`lyricsUpdated(persistentID:text:)`（接 `editor.onSaved`／`batch.onLyricsWritten`）：只認當前曲；指紋相同＝no-op。
  - `isCurrent(_ identity) -> Bool`：C 段非同步結果套用前比對；A1 以測試釘住。
  - `notPlaying()`／`permissionDenied()` 令 `identity = nil`（舊 identity 從此不再 current），下一次 `nowPlaying` 即使是同一首也 revision+1（Codex R2：防停播後舊非同步結果回填）。
  - `setVisible(_:)`：`clock.setActive(visible ∧ status == .present)`。A1 只有測試會呼叫（生產路徑由 A2 的切換接上）。
  - AppModel：建 VM 與時鐘；事件迴圈同點加 `lyricsFX.handle(event)`（D7 順序：editor → lyricsFlow → lyricsFX → batch；VM 的 handle 同步、不 await AE）。

### 3.5 `GenreStyleResolver`（項 5）
- `Services/Lyrics/GenreStyleResolver.swift`，純函式 `resolve(genre: String?, lyrics: String?) -> GenreStyle`。
- 體系：標籤（正規化後）含 `ロック` 或 `j-pop` → 日本語系；否則歌詞中「字母類字元」裡假名＋漢字占比 ≥ 0.3 → 日本語系；否則英語系（母計劃 §2.5）。日本語系：標籤含 `pop` → `jpop`，否則 `jrock`。
- 正規化：trim、lowercased。比對規則（母計劃「切詞＋子字串」的落地）：關鍵字本身含分隔符（`hip-hop`、`r&b`、`hard rock`、`new wave of american`）→ 對整串做子字串；長度 ≤ 3 的關鍵字（`nu`、`rap`、`emo`、`pop`）→ 以 `/ , & + - 空白` 切詞後**整詞**比對（防 `trap`、`democore` 誤中）；其餘 → 子字串。
- 英語系家族依母計劃表的順序，首個命中者勝：`cathedral` → `velvet` → `frost` → `slab` → `stencil` → `riot` → `block` → `circuit` → `hearth` → `pop` → `indie` → `chrome` → `rock` → `mono`。
- **表內矛盾的定論**（母計劃 §2.5 frost 含 `pagan`、`heathen`，hearth 又寫「pagan（非 black）」且永遠到不了）：使用者要求查實後定論（2026-10-04）。曲庫三個不含 black 的標籤實為 Andras《Warlord》、Primordial《Redemption at the Puritan's Hand》、Moonsorrow《Varjoina kuljemme kuolleiden maassa》，三者外部分類都以黑金屬為骨幹（見附錄 A.3）→ **`pagan`、`heathen` 一律 frost**；hearth 只認 `viking`、`folk`、`country`、`world`。Codex 同意。
- 測試以 `docs/plans/2026-10-03-lyrics-fx-genre-sample.txt` 的 69 個真實標籤全數表驅動（每個標籤一個期望家族），外加尾端空白、空字串、nil、`Hrad Rock`（拼錯→rock）。

### 3.6 時間軸存放（項 6）
- `Services/Lyrics/TimingStore.swift`：`actor TimingStore { init(directory: URL) }`（序列化，防同程序兩個 provider 的 load→merge→write 互相蓋掉，Codex R2；多台 Mac 經 iCloud 的衝突仍靠重新 load＋merge，盡力而為）；`load(persistentID) -> TimingRecord?`、`save(_ record) throws`。
  - 生產目錄常數 `TimingStore.defaultDirectory`＝`~/Library/Application Support/com.ibridgezhao.azathothswhisper/Timings/`（母計劃 C.1）；**A1 不在生產路徑建立或讀寫它**（沒有任何外部來源會寫；A1 只交付契約與測試，C 段接上）。日後指向 iCloud Drive 只需換 `directory`。
  - 檔名：persistentID 先 **uppercase 正規化**，再驗 `^[0-9A-F]{16}$`，否則 `save` 丟 `invalidPersistentID`、`load` 回 nil（防路徑穿越；大小寫不同不得產生兩個檔，Codex R1）。
  - JSON：`JSONEncoder`／`JSONDecoder` 明定 `.iso8601` 日期策略（Foundation 預設是數值，Codex R1）。
  - 原子寫入（`Data.write(options: .atomic)`），目錄不存在先建。壞檔、版本不符、欄位不合法 → `load` 回 nil（開放世界：「讀不懂」＝未知，不是「沒有」）。
- `TimingRecord`（Codable，JSON 欄位對齊母計劃 C.1）：`schemaVersion: 1`、`persistentID`、`lyricsHash`（`LyricsFingerprint`）、`source: StoredTimingSource?`（nil＝查過沒有）、`lines: [{index, start}]`（index＝`LyricsLines.parse` 後**僅 `.lyric` 行**的零起序號；found 時非空、notFound 時空；解碼時驗證 index 嚴格遞增、start 有限且 ≥ 0、記錄內的 persistentID 正規化後與請求 ID 相同——不合者視為壞檔，Codex R2）、`fetchedAt: Date`（ISO-8601）。
  - `StoredTimingSource`＝`lrclib, youtubeMusic, deezer, qq, kugou`：內嵌 LRC 本來就在 Music 欄位、估算隨時可算，兩者都不存檔（型別層強制）。
- `TimingLookupPolicy.shouldLookup(record:currentHash:now:) -> Bool`（母計劃 C.4）：無記錄 → 是；`lyricsHash` ≠ 當前 → 是（詞改了立即重找）；found → 否；notFound 且 `now − fetchedAt ≥ 7 天` → 是；`fetchedAt` 比 now 晚超過 1 天（時鐘錯亂／他機）→ 是；其餘否。用 wall-clock `Date`：要跨重啟、跨機器比較，單調時鐘做不到（與 `MonotonicClock` 的取捨相反，此處註明理由）。
- `TimingRecord.merged(existing:incoming:)`（多台 Mac 同步的衝突規則，母計劃 C.1）：hash 不同→取 incoming（新詞）；同 hash：found 勝 notFound；同為 found 或同為 notFound → `fetchedAt` 較新者勝。`save` 寫入前先 load 再 merge。
- 「寫檔前再驗 lyricsHash」（C.2 Codex R5）屬呼叫端（C 段的 provider），A1 只提供 `merged` 與 `lyricsHash` 欄位。

## 4. 任務清單（每項帶 DoD；全部 TDD：先寫測試跑出紅燈並記錄，再實作）
| # | 任務 | DoD |
|---|---|---|
| T0 | `LyricsFingerprint` ＋測試 | CR／CRLF／LF 同指紋；不同文字不同指紋；長度 32 hex |
| T1 | 項 1：三 getter、白名單、`TrackMetadata`、`NowPlayingRead.metadata`、`trackChanged` 第三值、`PlaybackPosition`＋`make`、`playbackPosition()`、5 個替身 | 白名單 3 測試綠；`PlaybackPositionTests` 綠；全量無新紅；豁免檔 ≤ 400 行 |
| T2 | 項 2 monitor：`lyricsChanged` | `NowPlayingMonitorLyricsChangedTests` 綠（見 §5）；既有 monitor 測試全綠 |
| T3 | 項 3a：`BusyLedger` 抽取 | `BusyLedgerTests` 綠；monitor 既有 busy 測試全綠、無行為差 |
| T4 | 項 3b：`PlaybackPositionClock` | `PlaybackPositionClockTests` 全綠 |
| T5 | 項 4a：`LyricsLines`、`LRCParser` | `LRCParserTests` 綠 |
| T6 | 項 4b：`LyricsTimelineEstimator`、`LyricsTimelineBuilder` | 測試綠 |
| T7 | 項 4c：`LRCAligner` | `LRCAlignmentTests` 綠 |
| T8 | 項 5：`GenreStyleResolver` | 69 標籤表驅動全綠 |
| T9 | 項 6：`TimingStore`／`TimingRecord`／`TimingLookupPolicy` | 測試綠（臨時目錄，不碰使用者的 Application Support） |
| T10 | 項 2＋4d：`LyricsFXViewModel`（無 View）＋AppModel 接線 | `LyricsFXViewModelTests`、`AppModelLyricsFXTests` 綠 |
| T11 | ACCEPTANCE H-20 改寫＋新段 I（A1 契約層條目，狀態「單測 ✅／實機待 A2」） | 文件更新 |
| T12 | 實機量測（**使用者在場 #1**）→ §8 回填 | `playbackPosition` roundTrip 分布、相鄰讀數殘差分布（→ tolerance）、`trackDetails` 9 欄 p50（→ `detailsBudget`）、genre／duration 實機讀值冒煙；offset 固定 0、記為 A2 校準 |
| T13 | 閘門：全量單元、白名單、`no_playback_gate.sh`＋Python 測試、coverage_gate（傳 xcresult） | 全綠（基線 7 斷言紅另列） |

**並行候選：無。** 任務形狀上 T5–T9 互相獨立，但每個都要經同一個 xcodebuild／同一個 app 測試宿主（ad-hoc 簽名、Keychain／TCC 會因重建重新詢問），多 worktree 同時建置在 iCloud 同步的 `~/Documents` 下風險高、收益小 → 主執行緒依序做。

## 5. 測試（Swift Testing；新檔都在 `Tests/`）
- `LyricsFingerprintTests`：見 T0。
- `PlaybackPositionTests`：`make` 對 playing／paused／stopped／other／空 ID 的輸出；中點與 roundTrip 計算。
- `MusicSelectorAllowListTests`：只改白名單集合，4 條既有測試照跑。
- `NowPlayingMonitorLyricsChangedTests`：同曲改詞 yield 一次；文字相同（含只差 CR/LF）不 yield；讀失敗不 yield 且不覆寫指紋；nil→有詞 yield；換曲只發 `trackChanged` 不發 `lyricsChanged`；forceRefresh 後重發 `trackChanged` 不夾帶 `lyricsChanged`；`trackChanged` 帶 metadata。
- `BusyLedgerTests`：兩來源交錯、重複 set、只有最後一個解除時回 true。
- `PlaybackPositionClockTests`（`GatedPollClock`＋`MockMusicClient`＋可控 now）：錨點內插；容差內不重錨（anchor 值不變）；超出容差重錨（seek）；暫停 → frozen、時間凍結、下一次睡眠請求為 6 s；播放中睡眠請求為 2 s；暫停→播放無通知時由輪詢恢復；offset 只加在 running；persistentID 不符丟棄；`notRunning` 清 anchor、其他錯誤保留；inactive 或無 track 零讀取；`resync` 立即讀且與進行中的讀取合併（在飛峰值 ≤ 1）；`pausesReadsWhileBusyAndCatchesUpAfter`（busy 中輪詢與 resync 都不讀、解除後補讀恰一次）；`setTrack(nil)` 停讀。
- `LRCParserTests`：單標籤、一行多標籤、ID 標籤略過、`[offset:]`、CR／CRLF、雜訊頭行照常解析、毫秒 1／2／3 位、`mm:ss:xx`、enhanced 剝除、亂序排序、`isLRC` 正反例。
- `LyricsTimelineEstimatorTests`：單調遞增、全落在時間窗內、段落標籤不出現在文字、`isChorus` 範圍、間奏留白、行時長下限、下限總和溢出時縮放、空歌詞／duration 0 → nil、CJK 逐字。
- `LyricsTimelineBuilderTests`：LRC 走層 1、純文字走層 3、LRC 末行 end。
- `LRCAlignmentTests`：同文字全對上；別曲（對齊率 < 0.7）→ nil；雜訊頭行不影響；未對上行內插單調；顯示文字取 Music；Genius 段落標籤不參與。
- `GenreStyleResolverTests`：69 標籤表驅動＋邊界例＋體系判定（日文歌詞、英文歌詞、ロック標籤配英文歌詞仍日本語系）。
- `TimingStoreTests`：存讀往返、非法 ID 拒絕、壞 JSON／版本不符／found 卻無 lines → nil、原子寫入後檔案完整、`merged` 四種規則。`TimingLookupPolicyTests`：五條規則各一。
- `LyricsFXViewModelTests`：換曲 revision+1；同曲同指紋 no-op；`lyricsChanged` 與 `lyricsUpdated` 同指紋只 +1；非當前曲的更新忽略；`notPlaying`／`permissionDenied` 清空、停讀、statusText；`status != .present` 不建時間軸且 `setVisible(true)` 不啟動時鐘；`isCurrent` 拒絕舊 identity。
- `AppModelLyricsFXTests`：busy 扇出到時鐘（Editor busy 時 resync 不讀）；player signal 扇出到 `resync`；事件迴圈把 `trackChanged`／`notPlaying` 送到 VM；`editor.onSaved` 送到 VM。
- Scripts：`no_playback_gate.sh`、`python3 -m unittest discover -p 'test_*.py'`、`coverage_gate.sh <xcresult>`。

## 6. 影響面
- 新檔：`Services/Music/{PlaybackPosition,BusyLedger,PlaybackPositionClock}.swift`、`Services/Lyrics/{LyricsFingerprint,LyricsLines,LyricsTimeline,LRCParser,LyricsTimelineEstimator,LRCAligner,GenreStyleResolver,TimingStore}.swift`、`Features/LyricsFX/LyricsFXViewModel.swift`、對應測試。需 `xcodegen generate`，產物一併納入（逐檔 add；不碰既有未追蹤的「 2.xcodeproj」）。
- 改檔：`MusicControlling.swift`、`MusicAppleEventsClient.swift`、`NowPlayingMonitor.swift`、`EditorViewModel.swift`／`LyricsFlowModel.swift`（各 +1 個 no-op case、模式改三綁定）、`AppModel.swift`、5 個 Music 替身、`MusicSelectorAllowListTests.swift`、`ACCEPTANCE.md`。
- AE 量：`nowPlaying` 每 3 s +2 個屬性讀取；`playbackPosition` 在 A1 生產路徑零呼叫。
- 隱私：日誌不記歌詞、曲名、ID；指紋不可逆。

## 7. 風險與回退
- R1 豁免預算 22 行不夠 → 先把邏輯推到純函式；仍不夠才請使用者批准調高（§9-Q5），不得偷偷改腳本。
- R2 `trackChanged` 加關聯值後 `Equatable` 合成把 metadata 納入比較：現有測試比對事件時兩邊都是 `.unknown`，不受影響；若有測試用真 client 的事件做相等比較則會紅 → 那是要修的測試期望（逐條看，不放寬斷言）。
- R3 讀 genre／duration 的 AE 失敗污染 `lastError` → 先記 `lyricsFailed` 再讀，各自判斷；`LiveMusicTests` 加一條實機冒煙。
- R4 時鐘與 monitor 共用 AE 佇列：A1 生產路徑不啟動時鐘，無風險；A2 起由 busy 閘門與 2 s 節奏控制。
- 回退：整條分支未併 main；任一任務紅到熔斷（同一問題 3 輪無進展）→ 停手記錄，交使用者。

## 8. 紅燈摘要／量測記錄（實作時回填）

### 8.1 TDD 紅燈摘要（2026-10-04）
| 批次 | 範圍 | 紅燈（骨架上跑） | 綠燈 |
|---|---|---|---|
| 1 | T0／T3a 記帳／T5–T9（指紋、BusyLedger、LyricsLines、LRCParser、估算、Builder、對齊、曲風、存檔） | 11 suites／70 tests／144 issues 全紅 | 70 tests 全綠（首次實作即綠；途中只修 Swift 6 Regex 非 Sendable 的編譯錯） |
| 2 | T1 契約／T2 lyricsChanged／T4 時鐘 | `PlaybackPosition` 2、`lyricsChanged` 2、`PlaybackPositionClock` 19 issues；契約與白名單測試隨宣告同步綠 | 連同既有 monitor 兩組共 8 suites／75 tests 全綠 |
| 3 | T10 VM＋AppModel 接線 | 2 suites／19 tests／27 issues | 19 tests 全綠 |
| 全量 | — | 首輪多 1 紅：`AEBudgetTests.columnsBecomeDetailsInTrackOrder` 寫死 7 欄形狀 → 依契約改 9 欄（補 genre／duration 兩欄與 NSNull，非放寬） | **956 tests／104 suites，僅基線 `CoverFlowStripRenderGeometry` 7 斷言紅** |

### 8.2 既有不穩定測試（不在 A1 範圍，未修）
- `LyricsFlowHistoryRecheckTests.anUnchangedOrIdenticalRecheckDoesNotFetchDetails`：全量第 2 輪紅（`:214` `trackDetailsRequests.count == before + 1`）。本分支孤立跑 6/6 紅；**main 558aed4 的臨時 worktree 孤立跑 3 次 1 綠 2 紅** → main 上原本就不穩定，與 A1 改動無關。推測：斷言前沒有等詳情 task 排上（未驗證）。不在本次 6 項內，未調查、未修，交使用者決定是否另案。

### 8.3 閘門
- `no_playback_gate.sh` exit 0；`Scripts` Python 333 tests OK；白名單 4 條綠。
- coverage_gate：Services+Infra 96.1%（門檻 80%）通過；**豁免檔 `MusicAppleEventsClient.swift` 408／400 行，超預算 8 行**（基線 378；新增＝三個 getter 的讀取、雙讀 ID、genre／duration 各自檢查 lastError、兩個 selector case；函式內註解已移到函式外以免被計入）→ §9-Q5 待使用者批准。

### 8.4 Phase 3 實施後評審（/simcodex 3 輪＋security-reviewer 1 次）
| 輪 | 來源 | 採納並修 | 駁回／延後（理由） |
|---|---|---|---|
| R1 | security-reviewer | 讀檔只收一般檔、≤ 1 MiB、不跟符號連結、行數 ≤ 5000；只認 ASCII hex（ID 與指紋）；較新 schema 不覆寫 | index 越界檢查→C 段取用端（現無呼叫端） |
| R1 | simplify ×4 | `GenreStyle.system` 由家族推出（不合法組合不可表示）；時鐘合併相同分支；VM 時間軸 guard；`Duration.inSeconds` 共用；測試改用共用 `waitUntil` | `TrackDetails` 兩欄與每次輪詢 +2 AE＝母計劃已定案；VM 指紋去重是跨來源去重（非重複規則）；其餘 P2 |
| R1 | codex | 同曲只有 genre／曲長變了也要重建 VM 狀態 | 兩條「編譯錯」＝讀到我改到一半的檔，誤報 |
| R2 | simplify ×4 | 使用者標記「無詞」後 VM 狀態不更新→`refreshStatus()` 接 `onSurfaceChanged`；`TimingStore` 改單次讀檔 `inspect`（不存在／目前／壞檔／認不出來），認不出來一律拒絕覆寫 | jpop 的 pop 比對方式、共用 AppModel 測試組裝等＝P2 |
| R2 | codex | — | monitor 不重發「同曲 metadata 補讀成功」＝P2，A2 前與 Codex 辯論 |
| R3 | simplify ×4 | 無 P0／P1 | 專用 `onMarksChanged` 回呼＝P2 |
| R3 | codex | `CardDetailsReader.updateLyrics` 重組時會清掉 genre／曲長→統一走 `TrackDetails.replacingLyrics` | in-flight 讀數在轉 busy 後仍套用：駁回——busy 是不佔 AE 佇列，已完成的讀數在其 readAt 仍準確 |

最終：972 tests／106 suites，僅基線 7 斷言紅；Services+Infra 96.1%；`no_playback_gate.sh` 0；Python 333 OK；豁免檔 408／400（§9-Q5）。

### 8.5 實機量測（使用者在場 #1，2026-10-04；`LiveLyricsFXMeasurementTests`，只讀）
| 項目 | 結果 | 結論 |
|---|---|---|
| genre／曲長實機讀取 | 都讀得到（曲長 264 s） | per-selector lastError 的寫法在真機成立 |
| `playbackPosition()` 往返（4 個 AE，30 次、間隔 0.5 s） | p50 8 ms、p90 9 ms、max 8.7 ms | AE 延遲很小；readAt 取中點的誤差 < 5 ms |
| 相鄰讀數與錨點外推的殘差（29 次，播放中） | p50 0 ms、p90 1 ms、max 0.8 ms | Music 的 playerPosition 與牆鐘幾乎完全一致（遠優於 lyrimuse 註解的 0.1 s 精度）；**tolerance 維持 0.5 s**：正常播放不會誤判 seek，seek 一般是秒級跳動，仍抓得到 |
| `trackDetails` 9 欄（16 首、10 批） | p50 84 ms、p90 100 ms | 遠低於 `detailsBudget` 1.5 s；S6 的 7 欄 p50 51 ms 是 21 首、不同專輯，不可直接相比 |
| offset 初值 | **固定 0**（§9-Q6） | 讀數本身準到毫秒，剩下的是「字與聲音」的感知延遲，只能在 A2 有畫面後目視校準 |

## 9. 待拍板（Codex 辯論後只留單一結論）
- Q1 已收斂（Codex R2 接受）：本次口令的 6 項是較晚且更具體的使用者指示 → 偏好與可見性扇出延到 A2；A1 只交付 `setVisible` API，生產路徑不呼叫。
- Q2 已撤回（Codex R1 勝）：照母計劃加。
- Q3 已收斂：涵蓋，事件語義文字改寫（Codex R1 同意設計）。
- Q4 已定論（使用者授權查證後由我定、Codex 同意）：pagan／heathen 一律 frost。
- Q5 已批准（使用者 2026-10-04）：豁免預算 400→410（實測 408）。`coverage_gate.sh` 與 `test_coverage_gate.py` 同步改。
- Q6 已收斂（Codex R1）：A1 固定 `offset = 0`；T12 只量 AE 延遲與讀數抖動（用來定 tolerance），**不宣稱能推出 offset**；感知校準延到 A2。

## 附錄 A　Codex 評審記錄
### A.1 Codex R1（gpt-5.6-terra，medium；2026-10-04）
| # | 論點 | 提出方 | 狀態 | 證據／理由 |
|---|---|---|---|---|
| 1 | Q1 偏好與可見性扇出延到 A2 違反母計劃 §3 A1 | Codex（阻擋） | **需使用者拍板**：母計劃 §3 的 A1 確實含 §2.1；但使用者本次口令只列 6 項並明說「不屬於 6 項先停下來問我」。範圍以使用者為準，不由辯論決定 | 母計劃 §3、本次口令 |
| 2 | 單讀 ID 擋不住跨歌污染（時鐘當前曲可能落後） | Codex | Codex 勝 → 雙讀 ID | §3.1 |
| 3 | 時鐘缺生命週期世代守衛、resync／取消優先序未定 | Codex | Codex 勝 → §3.3 規則 | §3.3 |
| 4 | frozen 不加 offset 會在暫停／恢復時跳 | Codex | Codex 勝 → 兩態都加 | §3.3 |
| 5 | `StoredTimingSource` 漏 `.user`（C.1） | Codex | **我勝（用戶既裁定）**：C.3「不做任何人工打軸……C 的第⑤層與 C.2 的打軸按鈕全部刪除」取代 C.1 的 user 來源 | 母計劃 C.3 |
| 6 | Q2 `TrackDetails` 延後＝改已定案契約 | Codex | Codex 勝 → 照母計劃加（顯式 init 預設 nil，建構點零改動） | 母計劃 §2.2 |
| 7 | metadata 每次 accessor 後立刻 snapshot lastError；mock 測不到 | Codex | 採納（我原設計同向，補成硬規則＋實機冒煙） | `MusicAppleEventsClient.swift:57-76` |
| 8 | `nil→可讀` 用 lyricsChanged 名稱易誤用 | Codex | 採納：保留事件、改語義文字 | §3.2 |
| 9 | ISO-8601 需明定、ID 大小寫正規化 | Codex | Codex 勝 | §3.6 |
| 10 | BusyLedger 回傳須是轉移 | Codex | Codex 勝 | `NowPlayingMonitor.swift:88-101` |
| 11 | Q4 是母計劃勘誤，需使用者確認 | Codex | 採納 → 使用者拍板 | 母計劃 §2.5 |
| 12 | 378／400 不是腳本固定事實 | Codex | **部分駁回**：378 是今天以 `coverage_gate.sh <baseline xcresult>` 實測輸出（`exemptions 1 file(s) / 378 lines, budget 400`），不是推算；採納「T1 前後各存一次摘要」 | §1 |
| 13 | A1 推不出 offset | Codex | Codex 勝 → Q6 降級 | §9-Q6 |
| 14 | 白名單位置、不加 setter 負對照、5 替身 | Codex | 一致 | — |

### A.2 Codex R2（2026-10-04）
- 接受 #5（`.user` 移除，C.3 使用者定案）、#12（378 是帶日期的實測快照）、#1（交使用者範圍判斷成立，延 A2 合理）。
| # | 論點 | 狀態 |
|---|---|---|
| R2-1 | 重錨比較誤含 offset | Codex 勝 → 用原始預測比較 |
| R2-2 | notPlaying／permissionDenied 未使 identity 失效 | Codex 勝 → `identity = nil` |
| R2-3 | 雙讀 ID 仍有 state 競態 | 雙方同意：保留 4 AE、明記為殘餘競態（Codex 提供的選項之一），理由見 §3.1 |
| R2-4 | setTrack 同 ID 不應遞增世代 | Codex 勝 |
| R2-5 | 存檔 index 定義與驗證 | Codex 勝 |
| R2-6 | TimingStore 需序列化 | Codex 勝 → actor |
- Codex：其餘已收斂。帳本無 open 項（Q4 屬使用者政策，不由辯論決定）。

### A.3 Q4 曲風查證與辯論（2026-10-04）
- 使用者：「你去查這些樂隊的分類是不是正確的，這些專輯到底是什麼風格；和 Codex 研究，最後由你給出定論。」
- 曲庫（osascript 唯讀）：Epic Pagan Metal＝Andras《Warlord》；Pagan Metal＝Primordial《Redemption at the Puritan's Hand》；Epic heathen Metal＝Moonsorrow《Varjoina kuljemme kuolleiden maassa》。
- 外部：Andras＝德國 Black/Pagan Metal，metal1.info 評《Warlord》「hartes Black Metal Riffing … zwischen heftigem Gekeife und pathetischem Klargesang」（https://www.metal1.info/metal-reviews/andras-warlord/）；Primordial 樂團 genre＝Pagan／black／folk metal（Wikipedia），No Clean Singing 評「a black metal record that transcends folk metal」（https://www.nocleansinging.com/2011/05/04/primordial-a-critique/）；Moonsorrow 樂團 genre＝Folk／pagan／black／progressive metal（Wikipedia），評論述 atmospheric black metal、嘶吼＋viking chant。Metal Archives 回 403，未取得。
- 結論：標籤本身沒錯（pagan 是對的），只是沒標出 black；三者都歸 frost。民謠／維京成分在 B 段以十軸數值（侵略↓、溫暖↑）體現，不換家族。Codex：同意，並建議把母計劃表直接改掉以免日後重排優先序時回歸 → 已改母計劃 §2.5 第 10 列。
