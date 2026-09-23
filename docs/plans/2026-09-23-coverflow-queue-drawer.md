# Cover Flow × 找歌詞 —— 實施計劃（v3.6，2026-09-23；v3.4 定稿後依 Q3b 使用者拍板①②與 Codex R6 裁決修訂 AC5／AC6／AC8／§6，見 §14 R6；v3.6 依 U#3 前預檢修 D6 可點的實作方式，見 §13、§14 R7）

- 分支：`wip/coverflow-lyrics`（自 `wip/h02-fix4`@`ec3fd4d` 分出；只做本地 wip checkpoint，不 commit 到 `feat/*`／`main`、不 push）
- 設計稿（互動原型）：https://claude.ai/artifact/GZSFdZEvyoshP48owh7c5G
  （01 有歌詞＝Cover Flow／02 缺歌詞＝Editor／03 循序播放；原型下方的虛線列只用來模擬 iTunes 換歌，**不進 app**）
- 模式：fatboyslim **normal**（依據：XCUITest 需使用者在場授權 Automation Mode、Queue.dat 行為需使用者操作 Music 驗證、終點要使用者目視——不適合無人值守 loop）
- **v3 變更摘要**：使用者裁定「播放中永遠置中、右邊＝接下來的歌、左邊＝播過的」（取代「播放中在最右」）；spike 證實 AppleScript 讀不到 Genius Shuffle 佇列，但 Music 自存的 `Queue.dat` 可唯讀取得且與畫面一致（§13）。U4、U7 已裁決。
- 評審：v1 經 Codex（R1，12 條）＋Opus 5 三視角（SA＝spike／AE，SM＝狀態機／接線，ST＝範圍／可測性）對抗評審；v2 經 Codex R2 複審（接受全部裁決、同意 U4／U7 建議、新提 4 條全採納）→ v2.1 定稿；記錄見 §14。

## 0. 複述（slipknot 17）

- **目標**＝讓使用者一眼看出「正在播的歌有沒有歌詞」：有就只看封面（Cover Flow），沒有就直接進 Editor 把詞找到並寫入，寫完自動回到封面。
- **完成標準**＝§4 驗收標準全部可判定通過＋使用者實機目視確認。
- **不做**＝任何播放控制、任何改變 Music.app 狀態的操作（含啟動／重啟 Music、改 UI、改曲庫 metadata、寫入 Music 的任何檔案）；保留 Cover Flow 分頁。

## 1. 需求（2026-09-23 默會知識提取；使用者原話見 memory `lyrics-workflow-coverflow-role`、`lyrics-tool-not-a-player`）

- **產品定位**：找歌詞的工具，**不是播放器**。不做播放／暫停／切歌；任何操作不得改變 Music.app 的播放狀態。
- **主流程**：看當前播放的歌有沒有歌詞 → 有就讓它播 → 沒有就把詞找到並寫入 → 接著看下一首。
- **畫面規則**（取代「Cover Flow 分頁」）：

  | 狀態 | 畫面 |
  |---|---|
  | 當前曲有詞，或已標記「沒有詞」 | Cover Flow（只看，跟著 iTunes） |
  | 當前曲缺詞 | Cover Flow 降下（底部留一條把手），露出 Editor |
  | 點正中那張（正在播的）封面 | 降下露出 Editor，用來改現有的詞；**其他卡不能點** |
  | 寫入成功 | 彩帶撒完後 Cover Flow 自動升回 |
  | 按「No lyrics for this song」 | 記為已處理（純音樂／找不到），升回，下次播不再跳 Editor |

- **卡片**：每張卡標 ✓ 有詞／✗ 缺詞／— 已標記無詞。**正在播的那張永遠置中；左邊＝播過的歌（＝Music 自己的「履歴」：只有播完的歌才會進，跳過的不進——與 Music 畫面一致），右邊＝接下來要播的歌（＝Music 的「キュー」＋「再生を続ける」）**（隨機、Genius Shuffle、循序皆同；使用者 2026-09-23 裁定，取代「播放中在最右」；「左邊一直有東西」亦為使用者確認）。核心訴求：隨機播放時每張封面都不同，Cover Flow 才有看頭（舊版＝整張專輯＝同一封面）。
- **接下來的歌取不到時**（Queue.dat 不存在／格式變了／當前曲不在清單內）：退回「左＝本 app 觀察到的歷史、右＝空」，並以一行小字標明「接下來的歌暫時讀不到」，不捏造。

## 2. 範圍

### 2.1 v1 範圍
1. Cover Flow 由獨立分頁改為 Editor 頁內的一層，依當前曲歌詞狀態自動升降（§6）。
2. 卡片＝**左：`History.dat` 最近 K 筆**（Music 的履歴，由舊到新排到中心）＋**中：當前曲**＋**右：`Queue.dat` 清單中當前曲之後 K 筆**（隨機時讀 `shuffledList`）。兩個來源**各自獨立降級**（R4-1）：History 取不到 → 只有左側改用本 app 觀察到的聆聽歷史；Queue 取不到 → 只有右側依 AC8b 處理（保留最後有效快照或留空＋標明讀不到），互不牽連。
3. 卡片標出歌詞狀態；「沒有詞」標記持久化在 app 設定、不寫進音樂檔。
4. 當前曲讀取改為**釘住 specifier、同一次 `run` 內讀完屬性與歌詞**（修既有的「A 的曲目＋B 的歌詞」競態；新介面把「出現 Editor＝沒詞」變成強主張，此競態會導致錯寫）。
5. 無播控的執行期白名單閘門（取代 v1 的 grep 黑名單）。

### 2.2 非目標
- 任何播放控制——**使用者既裁定，不重議**。
- 以 AppleScript／Accessibility／私有框架讀佇列（§3 事實 17–19：前兩者不可行或不可靠，私有框架違反 AC9）；Music 以外的播放歷史來源（Last.fm 等）。
- 聆聽歷史（退回模式用）跨重啟持久化（D3）。
- 點非播放中的卡、從 Cover Flow 批次補詞（Batch 分頁已涵蓋）。
- 取消標記的專用按鈕（原 D9 撤回：誤標後「點中心卡 → Fetch → Write」寫入成功即清除標記，恢復路徑已存在）。
- 原型頁尾的狀態文案（沿用既有 `STATUS | LINES` 頁尾，B／E 段語義不動）；原型「沒詞時 Write 停用」（既有 B 段允許寫空字串；空寫入經 §6 狀態推導留在 Editor）。
- Python 版 `lyrics_fetcher.py`——不動。

## 3. 已核事實

| # | 事實 | 出處 |
|---|---|---|
| 1 | Music.app 腳本字典有 `current playlist`（唯讀）、`shuffle enabled`（rw）；**沒有**待播清單與播放歷史；`persistent ID` 說明「This id does not change over time」 | `sdef` 導出 `music.sdef:224,256,349` |
| 2 | 字典內會改 Music 狀態／畫面的：playback 命令（play／playpause／pause／next track／previous track／back track／fast forward／rewind／resume／stop）、`search`（「Identical to entering search text in the Search field」）、`reveal`／`select`、`refresh`（以檔案覆寫曲庫資料）、`quit`／`run`／`open`／`print`、`add`／`delete`／`duplicate`／`make`／`move`／`convert`／`download`／`export`；可寫屬性含 `shuffle enabled`、`sound volume`、`player position`、`fixed indexing`、`frontmost`、`current AirPlay devices`、`EQ enabled`、track 的 `enabled`／`start`／`finish`／`played date` 等 | `music.sdef:6-151,160-266,440-482`（SA-C1 實查） |
| 3 | MusicKit `SystemMusicPlayer` 在 macOS 不可用 | SDK `MusicKit.swiftinterface` |
| 4 | 現行 Cover Flow＝獨立分頁（`AppTab.coverFlow`）、內容＝整張專輯（`albumTracks`）；所有 AE 經 `MusicAppleEventsClient` 單一串行佇列；只有封面讀取設 AE timeout（每個 AE 1.5s，非每次呼叫）；`run()` 只在開頭查一次 `isRunning` | `CoverFlowViewModel.swift`、`MusicAppleEventsClient.swift:27-30,144-173` |
| 5 | 輪詢事件 `trackChanged(TrackInfo, existingLyrics:)`；`currentTrack()` 與 `currentLyrics()` 是**兩次獨立 `run`**、各自重新解析 `current track`；歌詞讀取失敗被 `(try? …) ?? ""` 折疊成空字串 | `NowPlayingMonitor.swift:99,114-117`、`MusicAppleEventsClient.swift:39-61` |
| 6 | `forceRefresh()`（點 Now Editing 卡片、B-06）會清 `lastSignature` 並對**同一首**重發 `trackChanged`；notPlaying 後再播同曲亦同 | `NowPlayingMonitor.swift:100-103,125-129`、`EditorView.swift:56` |
| 7 | Editor 的 fetch／save 期間 monitor 為 busy、跳過輪詢；`save()` 在 `withBusy` 的 actor hop **之後**才讀 `boundTrackID`／`lyricsText`；`setLyrics(id,"")` 回傳 true | `EditorViewModel.swift:130,184-200`、`NowPlayingMonitor.swift:95-97`、`MusicAppleEventsClient.swift:84-88` |
| 8 | 彩帶以 `Task.sleep(16ms)` 步進、單發 200 步 → 名義壽命 ≥ 3.2s（實際更長）；原型用 1200ms | `ConfettiView.swift:46`、`ConfettiPhysics.swift:117`、原型 script |
| 9 | 開場畫面期間 shell 未建立、monitor 已發事件；`switch model.tab` 每次切分頁會重建內容 → strip 帶非 nil `centerID` 建立＝**初始值路徑**；fix4 實證初始值路徑落在「請求位置 −3 張」（缺陷 3，本分支未修）；對未生成的卡直接賦值居中會停在相鄰那張（F-JUMP），`withAnimation` 可停準但中途回呼被誤判為使用者接管（K5） | `RootView.swift:11-15,110-121`、`docs/plans/2026-09-13-coverflow-h02-fix4.md:74,97-102,545-548` |
| 10 | 單元測試 host＝完整 app，`live()` 仍建真實 AE client 與 monitor → 測試期間會輪詢使用者的 Music | `project.yml:81`、`AppModel.swift:146-170` |
| 11 | `MockMusicClient.currentLyrics()` 讀的是 `currentTrack()` **消耗後剩下的**腳本頭 → 多曲腳本歌詞錯位 | `Tests/Support/MockMusicClient.swift:98-123` |
| 12 | Cover Flow 分頁引用點：`AppModel.swift`、`RootView.swift`、`AppTab.swift`、`LocalizationTests.swift:44,58-63`、`CoverFlowUITestMusicTests.swift:86-88`、`AppModelTests.swift:88`；UITests：`CoverFlowUITests.swift:115-120,140`、`ShellUITests.swift:65,185,198` | grep 2026-09-23（ST-F7 補） |
| 13 | H-02 閘門 fixture＝**20** 首（T00–T19）；探針只接受 3 字元 ID；需 `TEST_RUNNER_AZW_EXPECTED_APP_DIR`；Python 閘門測試讀 `CoverFlowUITests.swift` 的 `code:` 字面量 | `CoverFlowUITestFixture.swift:26,56-66`、`CoverFlowUITests.swift:174-183`、`Scripts/test_h02_gate_parsing.py:110-128` |
| 14 | 字串目錄由 `Scripts/make_xcstrings.py` 整份重寫（`NEW_KEYS` 與 `lyrics_fetcher.py` 的 TRANSLATIONS 合併）；`LocalizationTests` 用寫死的鍵清單；E-05：運行時狀態文案是硬編碼英文、不進 catalog | `make_xcstrings.py:29-58`、`LocalizationTests.swift:43-49,66-73` |
| 15 | `coverage_gate.sh` 只算 `Services/`＋`Infra/`，不帶參數時自跑 xcodebuild 且不帶 skip／timeout | `coverage_gate.sh:9-33` |
| 16 | 全量單元測試須帶 skip＋超時上界；UITests 需使用者在場（Automation Mode 60s 授權框） | memory `bjork-overlapping-load-test-hangs-alone`、`automation-mode-timeout-needs-user-present` |
| 17 | Genius Shuffle 播放中：`shuffle enabled`=false、`current playlist`＝特殊種類 `kSpZ`（Music，12,252 首＝整個曲庫）、當前曲 index 3969、index+1＝曲庫鄰居（G.I.N.A.S.F.S.），**不是**畫面「再生を続ける」的下一首（I'm Only Sleeping） | spike `queue` 2026-09-23 16:5x（§13） |
| 18 | MusicKit `SystemMusicPlayer`（有 `.queue`）在 macOS SDK 標 `@available(macOS, unavailable)` | `MusicKit.swiftmodule/arm64e-apple-macos.swiftinterface:3251-3254` |
| 19 | Accessibility 讀面板：宿主已受信任，但當時 Music `AXWindows=0`、CG 視窗 onscreen=0 → 讀不到；只在 Music 視窗與面板於當前桌面空間可見時才可能 | spike `upnext_ax_spike`／`ax_windows`（§13） |
| 20 | `~/Music/Music/Music Library.musiclibrary/Preferences/Queue.dat`＝XML plist；`sega[0].items.list.items.iar[]` 每項 `pm.name`、`pm.piObjSpec.tID`；`tID` 以 UInt64 轉 16 位大寫 hex＝AppleScript `persistent ID`（對當前曲雜湊一致）；清單項數約 25 | spike `queuefile`（§13） |
| 21 | Queue.dat 寫入時機：Genius 重建、右鍵「次に再生」插歌時**立即重寫**（插入項排在當前曲之後）；按下一首／自然換歌**不重寫**。以「清單中當前曲位置」推算下一首：3 次按下一首＋Genius 後 1 次＋插歌後，全部與實際一致 | spike `queuefile` 17:12–17:17（§13） |
| 22 | 專輯頁直接點播：約 3 秒內 Queue.dat 重寫為該專輯清單（15 項），當前曲位於第 0 項；重寫前有一次輪詢讀到舊清單、找不到當前曲 | S8 17:33:54–57 |
| 23 | 每個清單項有 `itID`；插入（含同一首重複插入）後，**既有項 `itID` 不變、插入項取得新 `itID`**；Music 畫面的「キュー」與「再生を続ける」在檔案中合為同一條播放順序 | S8 17:24:13、17:35:07（`63407→63462(插入)→63409…`，同曲 `63413` 保留） |
| 24 | 曲庫隨機（`shuffleMode=tracks`）：`items.list`＝原始順序（12,252 項），`items.shuffledList`＝**打亂後的播放順序**（另有 `shuffleTable`）；shuffledList 與畫面「再生を続ける」逐項一致；檔案約 20MB、Python 解析 0.64s。Music ⌘Q 後重開、按播放 → 重新打亂並**立即重寫**，新順序與畫面一致 | S8 17:38–17:41:52 |
| 25 | `History.dat`＝Music 的「履歴」：`items.iar[]` 由舊到新，每項 `pm.name` 與 `pm.contentDesc.identifiers.libraryItemID`（`…-PID:0x<persistentID 小寫>-…`，與 AE 的 persistentID 一致）；**只有播完的歌才追加**（跳過的不進）；歌曲自然結束時立即更新；約 1MB（每項含小縮圖 PNG）；共 128 項 | 17:45:36 實查 |
| 26 | Music 未執行時，觀察程式只記「not-running」、未送 AE、未啟動 Music；Music 重開後 pid 改變、當前曲短暫為空（暫停／停止狀態） | S8 17:40:47–17:41:06 |
| 27 | 以 LaunchServices 啟動的獨立 ad-hoc 簽名 .app 可讀 Queue.dat（26 項），無任何權限提示 | S7 |

## 4. 驗收標準

| AC | 做 X 應看到 Y | 判定方式 |
|---|---|---|
| AC1 | 真實換歌到有詞曲 → 畫面＝Cover Flow | reducer 單元＋整合（AppModel＋MockMusic＋GatedPollClock）＋XCUITest `presentLyricsShowsCoverFlow` |
| AC2 | 真實換歌到缺詞且未標記曲 → 降下、把手（`lyricsflow-handle`）可見、Editor 自動抓詞（B-05） | 同上＋XCUITest `missingLyricsShowsEditor` |
| AC3 | 點「正中且正在播」的那張 → Editor；點其他卡（含播放中但不在正中）→ 畫面、綁定曲、hydrate 計數皆不變；捲動跨中點途中沒有卡可點 | reducer 單元＋`isCentered` 幾何單元（含跨中點的逐幀取樣，沿用 `StackSession` 滑動手法）＋XCUITest `clickingPlayingCardOpensEditor`／`clickingOtherCardsDoesNothing`（非播放卡元素型別不是 button） |
| AC4 | 寫入成功（寫入後 trim 非空）→ 延遲 `riseDelay` 後升回；期間任何使用者操作（把手、點卡、標記、編輯文字）或真實換歌 → 取消升回；A 寫入→換 B→回 A 不得被舊計時升回（ABA）；寫空字串或失敗 → 不升 | reducer 單元（GatedPollClock）＋整合＋XCUITest `writingLyricsRaisesCoverFlow` |
| AC5 | 按「No lyrics for this song」→ **只接受已知缺詞的當前曲**（非空 ID；有詞或讀不到時整個動作不生效——「沒讀到」不能當成「沒有」，R6-B3）→ 記標記、升回、取消自動抓詞；重啟後同曲不跳 Editor、不自動抓詞；該曲日後寫入成功（非空）清除標記。寫入空白（含只有空格）＝仍缺詞、留在 Editor | 單元（注入 defaults suite）＋XCUITest `markingNoLyricsPersistsAcrossRelaunch`（第一次啟動帶 reset env、重啟不帶） |
| AC6 | 同曲重發（forceRefresh、notPlaying 後再播）→ 只更新狀態與徽章，**不動畫面、不取消待升回**。兩個例外（使用者 2026-09-23 拍板）：① 待升回期間讀回仍缺詞＝寫入沒生效 → 取消升回、留在 Editor、狀態欄提示「寫入沒有生效」；② 由「讀不到」變「缺詞」、且本場次使用者沒親手選過畫面（有效的把手、點正中播放卡）→ 降下露出 Editor | reducer 單元＋整合（`sameTrackRefreshKeepsSurface`） |
| AC7 | 徽章 ✓／✗／—／?（unknown）與 `LyricsStatus` 一致；優先序 present ＞ markedNone ＞ missing；歌詞讀取失敗＝unknown → 不降下、不自動抓詞 | `LyricsStatus.resolve` 全真值表＋整合 |
| AC8 | 佇列模式：牌組＝Queue.dat 清單中當前曲前 K 首＋當前＋後 K 首，播放中置中。換歌（同一份清單）→ **不重讀整份清單、不重置 Cover Flow**，以增量窗口更新：未離窗的卡保留身分、中心平移（R3-4）。Queue.dat 內容變更（Genius／插歌）→ 依新清單重建窗口。**卡 ID 規則（唯一規格；v3.5 起以程式 `DeckSnapshot`／`QueueSession` 為準，R6-P1③）**：佇列項＝`q:<epoch>:<itID>`，**中心與右側共用**（下一首成為中心時 ID 不變，條帶才能平滑平移，S5）；同一快照內重複的 itID 自第 2 次起加 `#<n>`（R6-B7）；中心在未解析（退回）時＝`o:<persistentID>#<真實換歌場次>`，播完移到左側時 ID 不變；左側 History＝`h:<persistentID>#<自最新起第幾次>`（新的一筆追加時其他卡 ID 不動）；History 不可讀而改用本 app 觀察到的歷史時＝`o:<persistentID>#<真實換歌場次>`（同曲重播為不同卡，R5-2）；兩側若出現與中心同 ID 的卡，剔兩側、保中心（R6-B8）。`itID` 只視為「佇列 session 內身分」（R4-4）：新快照中若同一 `itID` 對應到不同 persistentID，該 `itID` 的 epoch 加一；同 itID 同 PID 維持 epoch（保住插歌穩定性）。itID 缺失 → `q:p:<persistentID>#<該快照內第幾次出現>`。左側與中心**不以 persistentID 互相去重**（同曲重播可同時在左與中，R4-7）。**序列種類**（R4-5）：`shuffleMode == tracks` 時只接受完整有效的 `shuffledList`，否則保留最後有效快照或進 AC8b，**絕不改用 `list`**；`shuffleMode` 型別錯、兩處不一致、或兩處都沒寫卻有 `shuffledList` → 不可用（R6-P1①；兩處都沒寫且只有 `list` → 順序，U10）；`QueueSnapshot` 記錄 `sequenceKind` 與所選序列的內容雜湊。**當前出現位置解析**（R3-1，R6-B1／B2 修正）：真實換歌只接受「上次位置的下一項」；不相鄰（往回跳、跳播、專輯點播後檔案尚未重寫）→ 事件當下不猜（右側 pending），下一次輪詢依唯一性定位；無上次位置 → 唯一才採用；清單重寫以 itID 帶回上次位置，帶不回則依唯一性；仍無法唯一 → 退回模式（AC8b），不猜 | `QueueSnapshot`／`DeckSnapshot`／`OccurrenceResolver` 單元（fixture plist：本次三種實測形狀、同曲重複、同曲插入、前進／跳播／窗口邊界） |
| AC8e | 左側＝`History.dat` 最近 K 筆（由舊到新排向中心）；新播完的歌在檔案更新後出現在中心左側；檔案不可讀 → 左側改用本 app 觀察到的歷史 | 單元（fixture：本次實測形狀、壞檔） |
| AC8b | 右側退回模式（**只管右側**；左側由 AC8e 獨立決定，R5-1）：**沒有任何已驗證的有效快照**、或最後一份有效快照中找不到當前曲（連續 2 次輪詢）、或當前出現位置無法唯一解析、或 Music 未執行 → 右＝空＋「接下來的歌暫時讀不到」小字；條件恢復後自動回到佇列模式。**單次讀取失敗或讀到寫入中的檔案 → 保留最後一份有效快照，不切模式**（R3-3）。歷史＝有序集合：真實換歌時把「前一首」移到尾端；當前曲不進左側；同曲重發不更新；上限 50；空 persistentID 不進（R3-7） | 單元（含 A→B→A、半份 plist、同 mtime 內容變化、原子替換）＋整合 |
| AC8c | Queue.dat 只讀：讀取碼只用 `Data(contentsOf:)`；該檔所在模組不得出現任何寫入／移動／刪除／建立檔案或設定屬性的 API；解析失敗不重試寫入、不拋到 UI | 腳本閘門（AC9 ③ 增列）＋單元 |
| AC8d | 卡片詳情（曲名、歌手、專輯、歌詞狀態）以 persistentID 批次讀取（去重後 ≤ 21 首一批）：單一背景 actor、最新者勝（帶快照版本 token，舊任務不得覆蓋新版）、總 deadline、快取（寫入／標記時更新該卡）；部分失敗 → 該卡狀態 `unknown`、只顯示封面；不阻塞事件分發、不餓死輪詢（R3-8） | 單元（`SerialAEQueueMusicClient` 公平性、版本 token）；時間界＝真機 |
| AC9 | **無播控（三層）**：① `MusicControlling` 不含播控方法（類型層）；② 執行期測試以 `protocol_copyMethodDescriptionList` 列出 Music `@objc` 協議的全部選擇器，必須 ⊆ 允許清單、`set*:` 只許 `setLyrics:`、required 方法＝0；`SBObject`／`SBApplication` 上帶 `AZW` 前綴的協議只能是允許的那幾個；負對照協議（`playpause`／`playOnce:`／`{get set}` 的 `shuffleEnabled`／`@objc(nextTrack)` 改名）必須回報 4 個違規；③ `Scripts/no_playback_gate.sh`（grep，stdin 可餵負對照）：`import ScriptingBridge` 只許出現在 `Services/Music/MusicAppleEventsClient.swift` 與 spike 檔；全部 target 目錄（`App Features Services Infra UI`）＋spike 禁 `NSAppleScript|NSUserAppleScriptTask|OSAScript|osascript|AESend|NSAppleEventDescriptor\(eventClass|sendEvent\(options:|MediaRemote|NX_KEYTYPE|import (OSAKit|Carbon)`；SB 檔內禁 `perform\(|NSSelectorFromString|Selector\(\(|setValue\(|makeObjectsPerform|byApplying:[^)]*with:|\.(add|insert|remove|replace)(Object)?\(`，`value(forKey: "…")` 的 key ⊆ {`rawData`} | 執行期測試隨全量單元跑；腳本退出碼；每條禁止模式各一負對照 |
| AC10 | 導覽區恰好兩個按鈕（Editor｜Batch，以 identifier 判定）；新字串三語齊（新鍵加入 `LocalizationTests` 清單） | `LocalizationTests`＋`ShellUITests` |
| AC11 | 每個 Q 結束：全量單元綠（skip 已知 flaky 一條）；Services＋Infra 由 `coverage_gate.sh` 判定 ≥ 80%（只算 app 本體；豁免清單僅 AE client 一檔，理由、批准日、行數上限 400 寫在腳本內，R8）；新檔與改動過的 Features 檔每檔行覆蓋 ≥ 80% 走 §9.3 的 xccov 手順，記錄基準 commit、檔案清單、各檔數字、xcresult 位置；`LiveMusicTests` 在閘門外、為手動 smoke——讀取類隨時可跑，寫入類（`writesLyricsByPersistentIDVerbatim`）只在使用者明示許可時執行，平時加 `"-skip-testing:AzathothsWhisperTests/LiveMusicTests/writesLyricsByPersistentIDVerbatim()"`；UITests 回歸集合（`ShellUITests`＋`BatchUITests`）對分支點基線不新增紅燈（A-10 已知 flaky 除外）；`test_h02_gate_*.py` 綠 | `xcodebuild test`＋`xccov`＋`coverage_gate.sh <xcresult>`＋pytest |
| AC12 | 當前曲的曲目欄位與歌詞只來自同一個 `NowPlayingRead`（單一來源，由同一次 `run` 對釘住的 track 物件讀出）；`NowPlayingRead` 是事件身分的唯一來源；替身回傳不完整讀取（歌詞讀取失敗）→ `unreadable` → 狀態 `unknown` | monitor／Editor 單元（替身逐欄注入失敗）＋S1 實測（釘住物件連讀 20 次屬性一致）＋opt-in `LiveMusicTests` |
| AC13 | Music 未執行時任何路徑都不啟動它；執行中途 Music 退出 → AE 以錯誤返回（不重啟 Music） | 代碼審查＋`SBApplication(processIdentifier:)` 用法測試；中途退出情境＝使用者在場時手動驗 |
| AC14 | 升起時方向鍵步進 Cover Flow、打字不進被遮住的 Editor；降下時 Cover Flow 不持有焦點 | XCUITest `keyboardFocusFollowsSurface` |

## 5. 領域模型（slipknot 31）

### 5.1 Competency Questions
CQ1 當前曲需不需要處理？／CQ2 某張卡顯示哪個徽章？／CQ3 哪張卡可以點？／CQ4 寫入成功後何時升回、何時取消？／CQ5 標記過的曲再播要不要跳 Editor、要不要自動抓詞？／CQ6 同一首被重發時畫面動不動？／CQ7 任何路徑會不會改變 Music.app 狀態？（恆為否）

### 5.2 概念表

| 概念 | 定義（是／不是） | 身分判據 | 邊界 |
|---|---|---|---|
| 當前曲 NowPlaying | monitor 最近一次 `trackChanged` 的曲目；不是中心那張（可滑走） | `NowPlayingIdentity`＝非空 `persistentID`，否則 `TrackInfo.signature`（與 monitor 換曲判據同源）；空 ID 的曲不可標記、不進歷史 | ≠ Editor 綁定曲（B-13） |
| 播放場次 PlayOccurrence | 當前曲的一次「真實換歌」；同曲重發不產生新場次 | 單調遞增 `occurrence` | 升回計時比對場次（防 ABA） |
| 歌詞讀取 `LyricsRead` | `text(String)`／`unreadable`；由事件攜帶 | — | `unreadable` ≠ 空字串 |
| 歌詞狀態 `LyricsStatus` | `present`／`missing`／`markedNone`／`unknown` | 由（`LyricsRead`, 標記）推導，不存 | `unknown` 不折疊成 `missing` |
| 無詞標記 | 使用者斷言「這首沒有詞／找不到」；存 app 設定，不寫音樂檔 | 非空 `persistentID` | 檔內有詞時標記無效 |
| 佇列快照 `QueueSnapshot` | 某一版 Queue.dat 解析出的曲目序列（persistentID＋名稱），附檔案修改時間 | 內容雜湊（mtime 只作「要不要重讀」的提示） | 不是 Music 的即時播放指標：換歌不改檔，當前位置由「當前曲在序列中的位置」推算 |
| 履歴快照 `HistorySnapshot` | 某一版 History.dat 解析出的最近 K 筆（persistentID＋名稱），由舊到新 | 內容雜湊 | 只含播完的歌（Music 語義）；左側主要來源 |
| 聆聽歷史 `ListeningHistory` | 本 app 本次執行觀察到的換曲序列（值型別）；只在履歴不可讀時使用 | 條目＝非空 `persistentID`（去重） | 不是 Music.app 的播放歷史；只在記憶體 |
| 牌組快照 `DeckSnapshot` | 某一刻 Cover Flow 的不可變卡片序列＋播放中卡 ID＋各卡狀態＋左右來源各自的模式 | 卡 ID 規則**唯一以 AC8 為準**（本表不另立規則） | 換歌以增量窗口更新；來源內容變更才重建該側 |
| 畫面 `LyricsSurface` | `coverFlow`／`editor` | — | 與分頁正交 |

### 5.3 約束與執行檔位
- 畫面互斥、狀態四選一 → enum：**類型層**。
- reducer 不接受 `unknown` 以外的非法組合：reducer 的事件攜帶 `LyricsStatus`（含 `unknown`），規則明列；**類型層＋單元測試**。
- 牌內 ID 唯一 → 歷史去重保證：**運行時校驗＋單元測試**。
- 無播控 → `MusicControlling`（類型層）＋`import ScriptingBridge` 限定檔案（腳本）＋選擇器白名單（執行期測試）三層；「類型層」一詞只指第一層，不宣稱整體由類型保證。
- 標記不寫音樂檔 → 標記存取是 `ConfigStore` 的擴充，只依賴 `UserDefaults`：**依賴面**。

## 6. 畫面狀態機（`LyricsFlowModel` 內的純函數 `reduce(state, event) -> (state, [Effect])`）

**State**＝`surface`、`nowPlayingID: NowPlayingIdentity?`、`occurrence`、`status`、`pendingRise: Token?`、`isDenied`、`hasUserChosenSurface`（本場次使用者是否親手選過畫面，真實換歌時清除；v3.5）。事件中的 `id` 一律是 `NowPlayingIdentity`（N1）；`writeSucceeded`／`markedNone` 的 `id` 是非空 persistentID，與當前曲比對時用其 identity。**初始**＝`editor`、無當前曲（啟動時未收到事件 → Editor 顯示 NO ARTIST／NO TRACK，與現行一致）。

| 事件 | 前置 | 結果 | Effect |
|---|---|---|---|
| `nowPlaying(id, status)`，`id ≠ nowPlayingID`（真實換歌） | — | `occurrence += 1`；`status == .missing` → `editor`，其餘（`present`／`markedNone`／`unknown`）→ `coverFlow`；清 `pendingRise`；`isDenied = false` | 取消升回計時 |
| `nowPlaying(id, status)`，`id == nowPlayingID`（同曲重發） | — | 只更新 `status`；畫面與 `pendingRise` 不動；若 `isDenied` 則同真實換歌處理（權限恢復）。例外①：`status == missing ∧ pendingRise ≠ nil` → 清 `pendingRise`；例外②：舊 `status == unknown ∧ status == missing ∧ !hasUserChosenSurface ∧ 畫面＝coverFlow` → `editor` | ①：取消升回計時＋`writeNotConfirmed`（狀態欄提示） |
| `tapPlayingCard` | 有當前曲 ∧ 畫面＝`coverFlow` ∧ 該卡位於幾何正中 | `editor`；清 `pendingRise`；`hasUserChosenSurface = true` | 取消升回計時 |
| `toggleHandle` | — | 翻轉畫面；清 `pendingRise`；`hasUserChosenSurface = true` | 取消升回計時 |
| `editorTextEdited` | `pendingRise ≠ nil` | 清 `pendingRise` | 取消升回計時 |
| `writeSucceeded(id, text)` | trim(`text`) 非空 | 該曲狀態＝`present`、清該曲標記、更新歷史卡徽章；若 `id == nowPlayingID` ∧ 畫面＝`editor` → `pendingRise = Token(occurrence)` | 排程 `riseDue(token)`；觸發 `forceRefresh`（唯讀，補上 busy 期間漏掉的換歌） |
| `writeSucceeded(id, text)` | trim(`text`) 為空（空白判定＝`LyricsText.isBlank`，與 Python `strip()` 同字元集） | 該曲狀態＝`missing`（若未標記）；畫面不動；清 `pendingRise`（R6-P1②：先前寫入排下的升回一併取消） | 取消升回計時；`forceRefresh` |
| `writeFailed(id)` | — | 不動 | `forceRefresh` |
| `riseDue(token)` | `token == pendingRise` ∧ `token.occurrence == occurrence` | `coverFlow`；清 `pendingRise` | — |
| `markedNone(id)` | 非空 `id`；當前曲須 `status == missing`（否則整個動作不生效，R6-B3） | 記標記；若 `id == nowPlayingID` → `coverFlow`、清 `pendingRise` | 取消該曲自動抓詞 |
| `permissionDenied` | `!isDenied` | `editor`；`isDenied = true` | — |
| `permissionDenied` | `isDenied` | 不動（每 tick 重發不覆蓋使用者的把手操作） | — |
| `notPlaying` | — | 不動；`nowPlayingID` 保留（再播同曲＝同曲重發） | — |

`riseDelay`＝`ConfettiBurst.ticks × ConfettiView.frameInterval`（單一來源常數，≈ 3.2s；把 16ms 提成 `static let frameInterval`）；這是**明確的牆鐘延遲**，語義是「約等於彩帶壽命」，U6 使用者試用時調。

## 7. 設計決定

- **D1 牌組**：`DeckSnapshot`（不可變）由 `QueueSnapshot`（優先）或 `ListeningHistory`（退回）＋標記＋播放中 ID＋卡片詳情快取推導；窗口 K＝10（左右各 10 張，實際值 S6 後定）；卡片資料沿用 `AlbumTrack`（事件 `TrackInfo`＋歌詞轉成），`isPlaying` 由 `playingID` 推導、不存在卡上。`CoverFlowCenterLabel`、`CoverFlowPrefetchWindow` 改吃快照（預取送 `persistentID`）。
- **D2 掛載結構**（SM-3-1、SM-3-4、ST-F3）：
  - shell 從啟動起常駐，開場畫面改為**覆蓋層**；Editor 頁層（Editor＋Cover Flow）在分頁 switch **之外**常駐，Batch 以覆蓋層顯示（Editor 頁層此時 `allowsHitTesting(false)`／`accessibilityHidden`）→ strip 一律以 `items=[]`、`centerID=nil` 建立，此後只走運行時路徑，**不再經過初始值路徑**（缺陷 3 的觸發條件在新結構下不存在）。
  - Cover Flow 常駐、以 `offset` 升降；**Editor 條件掛載**（畫面＝`editor` 才存在，狀態都在 VM）→ 一次解決被遮住的 NSTextView 搶焦點、I 形游標、點擊穿透。
  - 升降動畫只作用在 `offset`（`.animation(_:body:)`，key＝`surface`）；牌組變更 `disablesAnimations` → 不把捲動位置捲進動畫（防 K5 誤判接管）。`accessibilityReduceMotion` → 無位移動畫。
  - Cover Flow `.focusable(surface == .coverFlow)`，切換時以 `@FocusState` 搬移焦點。
- **D3 聆聽歷史只在記憶體**（退回模式用）。
- **D13 Queue.dat 讀取**：`QueueFileReader`（Services/Music，純讀檔＋純解析，**不持有 MusicControlling**）；每次輪詢 tick 比對檔案屬性（大小＋mtime）決定是否重讀；一次讀取＝讀前屬性→`Data(contentsOf:)`→讀後屬性，兩次屬性不同即視為寫入中、本 tick 放棄；解析容錯（缺鍵、型別不符、`tID` 缺失 → 本次不可用）；解析成功後以內容雜湊判斷是否實質變更；**保留最後一份有效快照**，只有 AC8b 所列條件才進退回模式。路徑固定為預設曲庫位置（L7，屬產品限制）。
- **D16 履歴讀取**：`HistoryFileReader`（同 D13 的讀取紀律）解析 `History.dat`，由 `libraryItemID` 取出 `PID:0x…` 轉大寫 persistentID；只取最後 K 筆，忽略 `artDat`（封面仍走 `ArtworkService`）；每次真實換歌立即檢查屬性、有變更即重讀。
- **D17 大檔解析**（R4-8）：Queue.dat 可達 20MB（事實 24）→ **單一串行讀取工人**（兩個檔案共用），同時至多一個 plist 解碼；每次讀取帶 generation，解碼前後檢查是否已被更新的請求取代；結果只保留精簡序列（persistentID＋itID＋sequenceKind＋雜湊），不保留原始 `Data`／plist 物件。
- **D15 佇列 session 失效**（R3-5）：區分三種狀態——①單次 transient（當前曲讀到空、下一 tick 恢復）：保留一切；②停止播放（`notPlaying` 連續 2 tick）：保留牌組、不動畫面；③Music 未執行（`NSRunningApplication` 檢查，不送 AE）：使佇列 session 失效、清空當前出現位置，下一次取得有效 `NowPlayingRead` 時重建。
- **D14 卡片詳情讀取**：`CardDetailsReader` actor：以 persistentID 批次讀名稱／歌手／專輯／歌詞（S6 定案：OR 串接的 whose 一次取元素＋`array(byApplying:)` 逐屬性批次取值，20 首約 5 AE／47ms）；單槽最新者勝、總 deadline、每首間讓出 AE 佇列；結果快取於 VM，寫入成功／標記時更新該卡。
- **D4 無詞標記**：`ConfigStore` 擴充（鍵 `NoLyricsMarkedTrackIDs`，字串陣列）；`LyricsFlowModel` 持有其可觀察鏡像供按鈕／徽章讀取。UI 測試組裝用專屬 suite：第一次啟動帶 `AZW_UITEST_RESET_DEFAULTS=1` 清空、需要時以 `AZW_UITEST_SEED_MARKS` 預植標記；**從不碰使用者的 `.standard`**。
- **D5 升回延遲**：§6 `riseDelay`。
- **D6 滑動保留、可點＝播放中 ∧ 幾何正中**：保留拖曳／方向鍵瀏覽（使用者上個 session 剛目視確認「滑動是對了」）；`CoverFlowStrip` 的內容閉包多傳 `isCentered`：在 `CoverFlowStripCell` 的**同一個** `onGeometryChange` 路徑內，以正規化距離 `|d| ≤ 0.2` 判定（帶容差；捲動跨中點途中沒有任何卡可點；不用 `centerID`、不用四捨五入後的 `stackingOrder`）（N2）；~~只有 `isPlaying ∧ isCentered` 的卡包成 `Button(.plain)`~~ **（v3.6 改，§13 U#3 前預檢 E1–E11）卡片純展示、不掛任何手勢——條帶內容帶手勢會讓換牌後的捲動定位失效；可點改在條帶層判定（點擊只認正中播放卡的封面正面），無障礙按鈕為條帶旁不接收滑鼠的並列層，只在播放卡位於正中時存在（AC3 語義不變：它是唯一的按鈕）**。牌組轉場（換歌、清單重寫、首次給牌）一律在同一次更新內換牌並設 `centerID`、不帶動畫（S5：direct 16/16；兩段式在首次給牌 0/5、動畫在換歌 5/6）。
- **D7 事件分發順序**：editor → lyricsFlow（同步）→ batch → coverFlow；事件迴圈內不 await 任何 AE（v1 的 Cover Flow 不需新 AE：歷史卡零額外讀取）。
- **D8 Editor 改動**：① 自動抓詞前查標記（注入唯讀判斷式 `isMarkedNoLyrics`，Editor 不持有 store）；歌詞 `unreadable` → 不自動抓詞；② `markedNone` 取消 `autoFetchTask`；③ `save()` 在 `withBusy` **之前**擷取 `target = boundTrackID`、`text = lyricsText`，與 `confettiTrigger += 1` 同一段同步碼發 `onSaved(target, text)`（修 SM-2-2 的 actor-hop 競態）；④ 升回用 `onSaved`，不用 `AppModel.confettiTrigger`（那是 Editor＋Batch 之和）。
- **D9 當前曲讀取**（SA-D4／D5、Codex-3）：新增 `MusicControlling.nowPlaying() -> NowPlayingRead?`，一次 `run` 內 `currentTrack.get()` 釘住 → 從同一物件讀 6 個屬性＋歌詞；歌詞讀取失敗 → `unreadable`。`PlaybackEvent.trackChanged` 的歌詞改為 `String?`（nil＝unreadable；既有 `existingLyrics: "x"` 呼叫點原樣可編譯）。monitor 改用新方法（`NowPlayingMonitor` 由「不動」改為「最小改動」）。
- **D10 AE 安全**（SA-A2／A5／A6）：`run()` 改為 `NSRunningApplication` 取 pid → `SBApplication(processIdentifier:)`（Music 中途退出時 AE 失敗、不重啟 Music；-600 對應 `.notRunning`）；`sendMode` 加 `kAENeverInteract`；Music `@objc` 協議加明確 ObjC 名（`AZWMusicAppProto`／`AZWMusicTrackProto`）以供 AC9 內省。
- **D11 單元測試 host 不碰真實 Music**（SA-D6）：`isUnitTestHost` 時注入不回應的 Music 替身。
- **D12 i18n**：保留鍵 `nav_coverflow` 作把手標題（撤回 v1 的改名）；新鍵見 §9.5。

## 8. 任務清單（每項 DoD 皆含「§9.3 全量單元綠」；每項完成做 wip checkpoint commit；打破哪個測試檔由打破它的那個 Q 修）

### 8.1 v1 主線

| # | 任務 | DoD |
|---|---|---|
| **S0** | spike 安全殼（無 AE）：`Scripts/spike/queue_spike.swift` 開頭①以 `protocol_copyMethodDescriptionList` 自檢自身 `@objc` 協議＝**只有 getter、零 setter、零命令**，不符即退出；②`NSRunningApplication` 確認 Music 已執行，否則退出；③`AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)` 預檢，非 noErr 即退出（不彈授權框）；④`SBApplication(processIdentifier:)`＋`sendMode = kAEWaitReply｜kAENeverInteract｜kAEDontRecord`；⑤每步新建 SBApplication、timeout 以 `秒×60` ticks、每步後讀 `lastError`；⑥輸出只含計數、耗時、AE 數、ID 雜湊（去識別化）。另附 `no_playback_gate.sh` 的 spike 版（同 AC9-③，spike 專用更嚴清單） | 自檢負對照：暫時在協議加一個 `setShuffleEnabled` → 程式在送任何 AE 前退出（以 `AEDebugSends=1` 無輸出佐證）；gate 腳本負對照各一例非 0 |
| **S1** | 當前曲讀取（無人值守；前置失敗即停、問使用者）：釘住 `currentTrack.get()` 後讀 6 屬性＋歌詞，×20 次記 p50／p95／max 與 AE 數（`AEDebugSends=1`）；比對釘住物件與未釘住讀到的 persistentID；比對 `app.tracks()` 以 persistentID 過濾（`findTrack` 路徑）是否找得到同一首 | 數字與結論寫入 §13；定出 `nowPlaying()` 的 AE timeout |
| **S5** | UI 機制 spike（單元測試 host，不碰 Music）：沿用 `CoverFlowStripStackingTests` 的 `StackSession`（CALayer 量測、無 AX），量「N 張 → 尾端追加 1 張並居中到它」落定後正中是否為新卡：(a) 同一更新內直接賦值 (b) 兩段式（新卡首次 `onGeometryChange` 後賦值）(c) `withAnimation` 賦值並記錄中途回呼；各 ×10 | 三法命中率與中途回呼記入 §13；定出 D6 的居中方式 |
| **S4** | 桌面判定：persistentID 穩定性（字典原文）；`UserDefaults` 容量算術 | 記入 §13 |
| **S6** | 卡片詳情批次讀取成本（唯讀 AE）：對 Queue.dat 取得的 20 個 persistentID，量 (a) 逐首 findTrack＋4 屬性 (b) OR 串接 whose 一次取元素＋`array(byApplying:)` 逐屬性；各 ×10 記 p50／p95／AE 數 | 記入 §13；定 D14 方法與 K |
| **S7** | app 讀 Queue.dat 的權限：以 LaunchServices 啟動的獨立 ad-hoc 簽名 .app（非終端子行程，代表未沙盒 app 的歸屬）讀檔一次，只記可讀與否與項數 | 記入 §13；若被 TCC 擋 → 回 Phase 1 評估 |
| **S8** | Queue.dat 行為矩陣（使用者在場操作 Music，觀察程式每 3 秒記錄：檔案是否重寫、項數、當前曲在清單中的所有出現位置、各項 `itID`）：(i) 專輯頁直接點播 (ii) 一般播放清單循序播放 (iii) 插入清單中已有的同一首 (iv) 關閉 Music 再開 (v) 播到清單尾端／自動續播（可延後到日常使用） | 每個情境記「檔案有無、是否重寫、當前曲是否在清單、應走佇列或退回」入 §13；未驗證的情境在 AC8b 明定為退回 |
| **S6b** | 以實際最大窗口 21 首、及去重後 ID 數重量 S6(b) | 記入 §13 |
| **S9** | Swift 端解析 20MB Queue.dat（`PropertyListSerialization`）與 1MB History.dat 的耗時與峰值記憶體 | 記入 §13；定 D17 是否需串流解析 |
| **U** | **使用者在場 #1**：UITests 基線（分支點 `ec3fd4d`，回歸集合＝`ShellUITests`＋`BatchUITests`）；S7 | 基線結果記入 §13 |
| **Q0** | 測試基建（TDD）：修 `MockMusicClient` 歌詞錯位＋鎖定測試；新增 `GatedPollClock`（可控時鐘）；`AppModel` 拆出 `startEventLoop()`（不啟動輪詢即可驅動事件）；D11 | 新基建各有測試；全量綠 |
| **Q1** | 純邏輯（TDD；**入口條件＝S8 完成**）：`LyricsStatus.resolve`、`QueueSnapshot` 解析（fixture plist：本次三種實測形狀＋S8 形狀＋缺鍵／壞檔／半份；normal↔shuffle 切換、只有一支序列完整）、`HistorySnapshot` 解析（PID parser、縮圖忽略、壞檔）、`OccurrenceResolver`、itID epoch、`ListeningHistory`、`DeckSnapshot`（兩模式、卡 ID 規則、中心移動不重建）、`LyricsFlowModel.reduce`（§6 每列至少一測，含 ABA、同曲重發、空寫入、權限恢復）、`ConfigStore` 標記擴充 | 紅燈摘要記 §13；新檔 ≥ 80% |
| **Q2** | Music 讀取與安全（TDD 能測的部分）：D9 `nowPlaying()`＋monitor 改用＋`trackChanged` 歌詞改 `String?`；D10；D13 `QueueFileReader`＋D16 `HistoryFileReader`（臨時目錄 fixture；讀前讀後屬性一致性、原子替換）；D17 讀取工人（連續 5 次 20MB fixture 重寫壓力測試：同時解碼數 ≤1、峰值 RSS 增量 < 150MB）；D14 `CardDetailsReader`＋`MusicControlling.trackDetails(persistentIDs:)`；AC9 ② 執行期白名單測試＋負對照協議；AC9 ③ `no_playback_gate.sh`＋負對照；opt-in 唯讀 `LiveMusicTests` 補 `nowPlaying()` | AC9、AC12 綠；替身整合測試綠；Editor／Batch 既有測試綠 |
| **Q3a** | `CoverFlowViewModel` 改吃 `DeckSnapshot`（移除 `albumChanged` 消費、分頁懶載入；佇列／退回兩模式；換歌只移中心）；可見性＝Editor 分頁 ∧ 畫面＝`coverFlow`；`CoverFlowViewModelTests` 依 §9.6 處置表重建並拆兩檔；`CoverFlowCenterLabelTests`／`CoverFlowPrefetchWindowTests` 跟進 | 處置表每條落實；全量綠 |
| **Q3b** | `LyricsFlowModel`（@Observable，含 reduce＋升回計時＋標記鏡像）；D8 Editor 改動；`AppModel` 接線（D7、`updateCoverFlowVisibility()` 由 `select` 與畫面變更兩處呼叫）；**移除 `AppTab.coverFlow`**＋`AppModelTests`／`CoverFlowUITestMusicTests` 跟進；ACCEPTANCE 對應條目同步改寫（§9.7） | 整合測試覆蓋 AC1／AC2／AC4／AC5／AC6（含換歌同時畫面翻轉時 override 仍為 false）；全量綠 |
| **Q3.5** | UI 測試組裝（純代碼、無人值守）：在既有 `makeCoverFlowUITestModelIfRequested` 加場景 env `AZW_UITEST_SCENARIO=present|missing|marked|notPlaying`；新 DEBUG 檔 `LyricsFlowUITestMusic`（actor、`setLyrics` 只寫記憶體）、`UITestStubHTTPClient`（恆 404）；D4 的 defaults suite；列入 `project.yml` UITests sources；先寫 `LyricsFlowUITests`（AC1–AC5、AC14）與 `ShellUITests` 改動 | `xcodegen generate` 後 `build-for-testing` 綠（N3）；組裝有單元測試 |
| **U** | **使用者在場 #2**：跑 `LyricsFlowUITests` 出紅燈（TDD 紅） | 紅燈記 §13 |
| **Q4** | UI：D2 掛載結構；把手（升降兩態皆顯示、箭頭方向、狀態刻度）；退回模式時右側「接下來的歌暫時讀不到」小字；卡片徽章（中心卡含軌號）；播放中∧正中卡 `Button`（hover「Edit lyrics」、a11y label、`coverflow-playing-card`）；中心標籤下方狀態字；Now Editing 卡片狀態字＋缺詞紅色色條；Editor「No lyrics for this song」；`make_xcstrings.py` 新鍵；identifiers；`xcodegen generate` | 建置綠；`LocalizationTests` 綠；`CoverFlowStripStackingTests`／`RenderGeometryTests` 綠 |
| **U** | **使用者在場 #3**：`LyricsFlowUITests` 綠；回歸集合對基線不新增紅燈；三態截圖（裁切到視窗、無憑證欄位） | AC1–AC5、AC10、AC11、AC14 |
| **Q6** | 收官：Phase 3 `/simcodex`；全量測試；證據包；使用者實機試用（含 `riseDelay` 手感、AC13 中途退出手動驗） | 使用者目視確認 |

### 8.2 （v3 刪除）
原 SEQ（以 `current playlist` 推測循序下一首）作廢：§3 事實 17 證實該來源在 Genius Shuffle 下不是播放順序；改由 Queue.dat（事實 20–21）；已實測涵蓋 Genius 重建、連續下一首、「次に再生」插入；其他播放方式（專輯直接點播、隊尾、Music 重開等）以 S8 驗證，未驗證者依「有有效快照且找得到當前曲則用，否則退回」處理。

## 9. 測試策略

### 9.1 層次（全局 §9）
- **單元**：Q1 純邏輯；標記擴充用臨時 suite（測後 `removePersistentDomain`）；AC9 執行期白名單。
- **整合**：`AppModel.startEventLoop()`＋`MockMusicClient`（修正後）＋`GatedPollClock`，驅動 `monitor.tick()`；斷言 `LyricsFlowModel` 狀態、`CoverFlowViewModel` 快照、標記。
- **E2E**：XCUITest，全部走假 Music 組裝（場景 env），不碰使用者曲庫、Keychain、`.standard` defaults。

### 9.2 TDD
每個 Q 先寫測試並跑出紅燈（摘要記 §13）再實作；E2E 的紅燈在「使用者在場 #2」取得。

### 9.3 運行命令
```bash
cd AzathothsWhisper && xcodegen generate
# 字串（改 make_xcstrings.py 後）
../.venv/bin/python3 Scripts/make_xcstrings.py
# 全量單元（必帶 skip＋超時上界）
xcodebuild test -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper \
  -destination 'platform=macOS' -only-testing:AzathothsWhisperTests \
  -skip-testing:"AzathothsWhisperTests/BatchOverlappingLoadTests/overlappingLoadSuspendsPollingUntilLastCompletes()" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -enableCodeCoverage YES -resultBundlePath <scratch>/unit.xcresult
./Scripts/coverage_gate.sh <scratch>/unit.xcresult          # Services／Infra 門檻（app 本體、豁免清單見腳本，R8）
(cd Scripts && /usr/bin/python3 -m unittest test_coverage_gate)   # 閘門自身的黑箱測試（不在 test_h02_gate* 探索規則內）
xcrun xccov view --report --files-for-target "Azathoth's Whisper.app" <scratch>/unit.xcresult   # 新檔與改動檔逐檔
./Scripts/no_playback_gate.sh
(cd Scripts && /usr/bin/python3 -m unittest test_no_playback_gate)   # 閘門負對照（原 Swift 版在 app 宿主內會卡在 ~/Documents 存取授權，simcodex R1）
(cd Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_gate*.py')
# UITests（使用者在場；先關 Paste 等會彈窗的常駐 app；輸入法切 ABC——拼音等輸入法會改寫 XCUITest 的鍵入）
xcodebuild test ... -only-testing:AzathothsWhisperUITests/LyricsFlowUITests \
  -only-testing:AzathothsWhisperUITests/ShellUITests -only-testing:AzathothsWhisperUITests/BatchUITests \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 300
```

### 9.4 E2E 觀測點
把手 `lyricsflow-handle`、Cover Flow 層 `lyricsflow-coverflow`、Editor 層 `lyricsflow-editor`、播放中卡 `coverflow-playing-card`、導覽按鈕 `nav-editor`／`nav-batch`、標記按鈕 `editor-mark-no-lyrics`；「未自動抓詞」以 DEBUG 抓詞計數（a11y value）判定。

### 9.5 i18n 新鍵（三語；E-05 的運行時狀態文案不在此列）

| 鍵 | en | zh_TW | ja |
|---|---|---|---|
| `nav_coverflow`（沿用，作把手標題） | Cover Flow | 封面瀏覽 | カバーフロー |
| `mark_no_lyrics` | No lyrics for this song | 這首沒有歌詞 | この曲は歌詞なし |
| `lyrics_status_present` | Lyrics in file | 已有歌詞 | 歌詞あり |
| `lyrics_status_missing` | Missing lyrics | 缺少歌詞 | 歌詞なし |
| `lyrics_status_marked` | Marked: no lyrics | 已標記：沒有歌詞 | 歌詞なしとして記録済み |
| `lyrics_status_unknown` | Lyrics unreadable | 讀不到歌詞 | 歌詞を読み取れません |
| `edit_lyrics_hint` | Edit lyrics | 編輯歌詞 | 歌詞を編集 |
| `upnext_unavailable` | Up next isn't available right now | 接下來的歌暫時讀不到 | 次の曲を読み取れません |
| `coverflow_show` | Show Cover Flow | 顯示封面瀏覽 | カバーフローを表示 |
| `coverflow_hide` | Hide Cover Flow | 隱藏封面瀏覽 | カバーフローを隠す |
| `edit_lyrics_of` | Edit lyrics of %@ | 編輯「%@」的歌詞 | 「%@」の歌詞を編集 |

### 9.6 `CoverFlowViewModelTests` 處置表（31 條；ST-F14 實數）
- **刪除／改寫語義（13）**：H-01 懶載入 2（`activatingTabWithEmptyListLoads`、`activatingTabWithLoadedListDoesNotReload`）→ 刪；H-06 切專輯 7（`albumChangedQueriesUsingEventKeyNotCurrentTrack`、`staleAlbumLoadDoesNotOverwriteNewer`、`albumChangeWhileHiddenClearsWithoutLoading`、`hiddenAlbumChangeLoadsOnReactivation`、`albumChangeResetsOverride`、`albumChangeCancelsPrefetch`、`albumChangeResetsArtworkRevisions`）→ 刪，改寫為歷史追加語義的對應測試；`trackNotInListLeavesCenterAlone` → 反轉為「新曲追加並居中」；H-11 `itemsUseStableDisplayOrder` → 刪（歷史序取代 disc→track）；分頁可見性 2（`tabDeactivationCancelsPrefetch`、`hiddenTabDoesNotPrefetch`）→ 改寫為「畫面降下／Batch 覆蓋時不預取」。
- **只換 fixture（18）**：原檔 `:159,:169,:192,:204,:216,:246,:274,:293,:308,:324,:336,:361,:370,:381,:432,:447,:459,:471`（`:361` 的「載入完成」改為「追加完成」觸發）。
- 檔案拆成 `CoverFlowViewModelDeckTests`（牌組／居中／H-05）與 `CoverFlowViewModelPrefetchTests`（預取／封面版本）。

### 9.7 ACCEPTANCE 變更表（在刪除對應證據的那個 Q 同步改寫）
- **作廢**：H-01（分頁懶載入）；H-06「切專輯重建」部分；H-11（原 ⚠️待簽字——排序改為歷史序，**需告知使用者**）。
- **改寫**：H-10（可點＝播放中∧正中卡只開 Editor；證據改為 AC9 三層；協議方法數更新）；H-03（證據簽名）；H-04（新曲追加到最右並居中；時間界口徑不變）；H-02（依 U7）。
- **只換證據**：H-05、H-09。**不受影響**：H-07、H-08（註明徽章不改變封面尺寸）。
- **H 段以外**：B-05（證據＋D8 抑制規則）、B-06（同曲重發不動畫面）、E-04（鍵數）、E-10、H 段標題條數與總計。
- **新增**：本計劃 AC1–AC14 對應條目（編號 H-12 起）。

## 10. 影響面、風險與回退

### 10.1 影響面
- **改**：`Services/Music/{MusicControlling,MusicAppleEventsClient,NowPlayingMonitor}.swift`；`Features/CoverFlow/{CoverFlowViewModel,CoverFlowView,CoverFlowItem,CoverFlowCenterLabel,CoverFlowPrefetchWindow,CoverFlowStrip}.swift`（Strip 只加 `isCentered` 參數，疊放幾何不動）；`Features/Editor/{EditorViewModel,EditorView}.swift`；`Features/Shell/{AppTab,RootView}.swift`；`App/AppModel.swift`；`App/UITestSupport/{AppModel+CoverFlowUITest,CoverFlowUITestMusic}.swift`；`Services/Config/ConfigStore.swift`；`UI/Components/ConfettiView.swift`（只提常數）；`Scripts/make_xcstrings.py`→`Resources/Localizable.xcstrings`；`project.yml`；`ACCEPTANCE.md`。
- **新**：`Features/LyricsFlow/{LyricsStatus,ListeningHistory,DeckSnapshot,LyricsFlowModel}.swift`、`Services/Music/{QueueFileReader,QueueSnapshot,CardDetailsReader}.swift`、`Tests/Fixtures/Queue/*.plist`（去識別化 fixture）、`App/UITestSupport/{LyricsFlowUITestMusic,UITestStubHTTPClient}.swift`、`Tests/Features/LyricsFlow*Tests.swift`、`Tests/Services/MusicSelectorAllowListTests.swift`、`Tests/Support/GatedPollClock.swift`、`UITests/LyricsFlowUITests.swift`、`Scripts/no_playback_gate.sh`、`Scripts/spike/queue_spike.swift`。
- **不動**：`ArtworkService`、`CoverFlowGeometry`、Batch 功能、Settings、Python 版。
- **H-02 fix4**：凍結的 R27 profile 綁 `~/Developer/bjork-h02-gate` 下預建的樹，本分支不碰；fix4 若繼續在 `wip/h02-fix4` 上進行。本分支上 `CoverFlowUITests` 的處置見 U7。

### 10.2 風險
| # | 風險 | 緩解 | 回退 |
|---|---|---|---|
| R1 | 歷史追加後居中停錯卡（F-JUMP／K5） | S5 先量；兩段式居中備案；牌組變更不帶動畫 | 退回兩段式 |
| R2 | 降下時 strip 仍佈局 → 可見卡照取封面、佔 AE | 每次換歌只多一張卡；VM 預取受可見性閘 | 接受（L4） |
| R3 | 掛載結構改動（開場覆蓋層、Batch 覆蓋層）影響 A 段外殼行為 | A 段既有 UITests 在回歸集合；開場時序不變 | 回退為分頁 switch＋接受初始值路徑 |
| R4 | 釘住 specifier 的讀法在串流曲／特殊來源不可用 | S1 實測；失敗退回既有兩次 `run`＋歌詞 `unreadable` 判定 | 同左 |
| R5 | pid 定址的 SBApplication 與既有行為差異（Music 重啟後 pid 變） | 每次 `run` 重取 pid | 回退為 bundle ID＋`isRunning` |
| R6 | UI 測試污染使用者設定 | 專屬 suite＋顯式 reset env | — |
| R7 | 已知 flaky（overlapping load 掛起、A-10） | §9.3 skip＋超時；A-10 列為已知 | — |
| R8 | Queue.dat 是 Apple 內部格式，Music 改版可能改路徑或結構 | 防禦式解析；失敗＝退回模式（AC8b），不崩、不捏造 | 退回模式即回退 |
| R9 | app 讀 `~/Music/Music/…` 被 TCC 擋 | S7 先驗 | 退回模式 |
| R10 | 卡片詳情讀取（20 首）佔用 AE 佇列 | S6 定方法；單槽、總 deadline、快取；只在清單重寫或窗口滑入新卡時讀 | 縮小 K |

**整體回退**：全部改動在 `wip/coverflow-lyrics`；放棄＝切回原分支。

### 10.3 已知限制（接受，不修）
- **L1** 歷史卡徽章＝觀察當下的狀態＋本 app Editor 的寫入／標記；Batch 寫入不即時反映到歷史卡。
- **L2** 串流（非本機曲庫）曲目的封面／寫入沿用既有限制。
- **L3** 從 Batch 切回 Editor 時，若期間換到缺詞曲，不補自動抓詞（B-05 既有語義 py:481）；使用者可按 Fetch。
- **L4** 降下時 strip 仍會為可見卡取封面（R2）。
- **L5** 換歌時 Editor 內未存的文字被覆蓋（既有行為）。
- **L6** 執行中撤權後再授權、歌沒換：monitor 不重發事件，Editor 顯示 ACCESS DENIED 直到換歌或點 Now Editing 卡片（既有行為）。
- **L7** 曲庫不在預設位置（`~/Music/Music/Music Library.musiclibrary`）時一律退回模式。
- **L8** 左側只含 Music 視為「播完」的歌（跳過的不出現），與 Music 自己的「履歴」一致。History.dat 於歌曲自然結束時同秒更新（事實 25）；app 端在每次真實換歌與每次輪詢檢查其屬性，最壞晚一次輪詢（3s）才出現在左側——接受，不做暫存交接層（R4-2 修改後採納，理由見 §14 R4）。
- **L9** 從專輯頁點播、且新曲恰好是舊清單中「上次位置的下一項」時，與正常連播無從區分：右側可能短暫顯示舊清單的接下來，直到 Music 重寫 Queue.dat（實測約 3 秒，事實 22）後自我修正（R6-B2）。其餘不相鄰的情況事件當下不猜。

## 11. Unknowns 賬本（slipknot 29）

| # | 未知 | 狀態 | 消解 | 影響 |
|---|---|---|---|---|
| U1 | 釘住 specifier 讀當前曲的延遲與 AE 數 | 已知的未知 | S1 | `nowPlaying()` timeout |
| U3 | `findTrack` 能否以釘住物件的 persistentID 找到同一首 | 已知的未知 | S1 | 寫入／封面路徑 |
| U4 | 右側是否顯示接下來的歌 | **已裁決（2026-09-23）**：要；播放中置中。來源＝Queue.dat（事實 20–21） | — | §2.1、AC8 |
| U5 | 歷史追加後居中的可靠做法 | 已知的未知 | S5 | D6 |
| U6 | `riseDelay` ≈ 3.2s 的手感 | 未知 | Q6 試用 | 常數 |
| U8 | Queue.dat 在清單播到尾、關閉 Music 再開、從專輯頁直接點播、插入同一首時的行為 | **已消解（S8）**：專輯點播、同曲插入、曲庫隨機、重開重洗皆可；清單播到尾／自動續播未測（依 AC8b 退回） | — | AC8／AC8b |
| U9 | app 本身的檔案讀取權限 | **已消解（S7）**：獨立 ad-hoc app 可讀、無提示 | — | R9 |
| U7 | 本分支上 H-02 閘門 `CoverFlowUITests` 的處置 | **已裁決（2026-09-23）：本分支退役＋替代證據**。內容：本分支正式退役（資料模型已由整張專輯變為歷史，20 首 fixture 與探針前提不成立），ACCEPTANCE H-02 改附替代證據：`CoverFlowStripStackingTests`（缺陷 2，CALayer 無 AX）、S5 轉成的追加居中測試、D2 結構消除缺陷 3 的觸發條件、`LyricsFlowUITests` 升降；檔案保留（Python 閘門測試讀它）但移出回歸集合；fix4 在 `wip/h02-fix4` 另行延續與否由使用者定 | 使用者在場 #1 | Q5 回歸集合、H-02 條目 |
| U10 | 順序模式（非隨機）的 Queue.dat 是否寫 `shuffleMode` 鍵 | 已知的未知（目前唯一實檔樣本為整庫隨機；S8 當時未記此鍵） | 使用者在場 #2 時以唯讀方式看一次循序播放時的檔案鍵 | P1① 的「兩處都沒寫」分支（沒寫且只有 `list` → 順序；若實檔一律有寫，該分支只是防禦） |

**Premortem**：① 歷史追加居中停錯卡（→ S5／R1）；② 掛載結構改動打壞外殼（→ R3、回歸集合）；③ 讀取競態讓 Editor 在有詞曲上出現並被使用者覆寫（→ D9／AC12）；④ 同曲重發把使用者踢出 Editor（→ AC6）。

## 12. 流程偏離聲明
- XCUITest 需使用者在場，排為三次「使用者在場」節點（§8.1）；其餘可無人值守。
- S 的前置（授權預檢）失敗即停、不彈框，改到使用者在場 #1 補。
- Phase 1 第 1 輪評審時 Codex 週額度用盡，先以 Opus 5 三視角評審，額度恢復後補跑 Codex（§14）。

## 13. 實測記錄（實施中回填）

### 2026-09-23 S0／S1／佇列來源（使用者在場）
- **S0**：`Scripts/spike/queue_spike.swift`（＋`queue_spike_negative_control.swift`、`spike_gate.sh`）。自檢：正式協議 0 違規；負對照 4/4（`playpause`、`playOnce:`、`setShuffleEnabled:`、改名的 `nextTrack`）；`SPIKE_INJECT_NEGATIVE=1` → exit 2、`AEDebugSends=1` 無任何 AE 輸出。`spike_gate.sh` 對 spike 原始碼 PASS，9 條負對照全數非 0。授權預檢 `AEDeterminePermissionToAutomateTarget(ask:false)`＝noErr（宿主 Ghostty 已授權），全程未彈框。
- **S1**：釘住 `currentTrack.get()` 後讀 6 屬性＋歌詞：p50 64.1ms／p95 64.6ms／max 74.4ms（n=20）；未釘住（現行形狀）p50 55.7ms；兩者 persistentID 20/20 一致。釘住後的 specifier＝`file track id … of user playlist id … of source id …`。`findTrack`（全庫 persistentID 過濾）p50 14.5ms／p95 18.9ms、5/5 命中。
- **AE 成本**：逐列讀 4 屬性約 8ms／AE（±10 窗口 21 列＝84 AE、700ms）。註：`AEDebugSends` 的輸出走 stdout。
- **佇列來源（事實 17–21）**：`current playlist` 路線在 Genius Shuffle 下不成立（index+1＝曲庫鄰居）；Accessibility 路線當時 `AXWindows=0`；`Queue.dat` 第 0 項＝當前曲（雜湊 `2378bf9d` 與 AE 一致）、第 1 項起＝畫面「再生を続ける」順序。使用者操作驗證（`queuefile` 模式，每 3 秒比對）：
  - 17:13:26–17:13:32 按 3 次下一首 → 當前曲依序＝清單第 1、2、3 項；檔案 mtime 不變（16:42:16）。
  - 17:14:02 Genius 重建 → 檔案立即重寫（25 項），第 0 項＝新當前曲；17:14:53 換到下一首＝清單第 1 項。
  - 17:16:43 右鍵「次に再生」插入 → 檔案立即重寫（26 項），插入項位於當前曲之後。
  - 17:16:42 有一次輪詢讀到空的當前曲（插歌瞬間的過渡態）→ monitor 須容忍單次空讀（既有行為：`currentTrack()` 為 nil 時視為 notPlaying，**待評估是否造成畫面閃動**）。
- **被動命中（`watch`，以 `current playlist` index+1 預測）**：12 分鐘內 0 次換歌（Music 當時暫停），無數據；事實 17 的反證改由 `queuefile` 17:13 的 3 次換歌提供（當前曲依序＝Queue.dat 第 1–3 項，而非 `current playlist` 的 index+1）。
- **S6（卡片詳情批次讀取，Queue.dat 前 20 個 persistentID，各 ×10）**：(a) 逐首全庫過濾＋4 屬性：p50 1009.5ms／p95 1057.8ms、20/20；(b) OR 串接 20 個 `persistentID ==` 的 whose 一次取元素（Swift 端 `(matches as NSArray) as? SBElementArray` 成功保留型別）＋`array(byApplying:)` 取 persistentID／名稱／歌手／專輯／歌詞：**p50 46.9ms／p95 56.5ms、20/20**。`AEDebugSends` 計數：單輪 (a)+(b)＝125 AE，(b) 約 5 AE。→ D14 採 (b)；K＝10（左右合計 ≤ 20 首一批）。
- **S6b（21 首）**：(a) 逐首 p50 1053.7ms；(b) 批次 **p50 50.7ms／p95 76.0ms**、21/21。
- **S7**：LaunchServices 啟動的獨立 ad-hoc .app 讀 Queue.dat：`readable=true bytes=23333 items=26`，無提示。
- **S8（使用者在場，17:24–17:45）**：專輯點播（事實 22）、同曲插入（事實 23）、曲庫隨機與 shuffledList（事實 24）、Music ⌘Q 重開與重洗（事實 24、26）全數與畫面一致；History.dat（事實 25）。觀察程式 `matrix` 模式由我手動停止（exit 144，預期）。
- **S9**：Swift `PropertyListSerialization` 解析 Queue.dat（20,385,577 bytes、list 12,252＋shuffledList 12,252）p50 59ms／max 74ms；History.dat（1,040,333 bytes、128 筆）p50 2ms；峰值 RSS 46MB → D17 背景解析即可，不需串流解析。
- **S5（牌組轉場後畫面正中是否為目標；`Tests/UI/CoverFlowDeckTransitionSpikeTests.swift`，`TEST_RUNNER_AZW_SPIKE_S5=1` 才執行；層樹讀取器抽到 `Tests/Support/CoverFlowLayerReader.swift`，`CoverFlowStripStackingTests` 6 條照綠）**：
  - 身分判定：每張卡以 `onGeometryChange` 被動回報佈局 midX（不經 AX、不增具現）。**第一版以捲動原點換算身分，系統性少一張**（兩種量法同輪對照：scroll 恆＝geometry−1），已棄用——該偏差屬量法，不屬產品。
  - 結果（geometry 身分）：換歌（窗口右移一格）direct **6/6**、兩段式 6/6、動畫 5/6（首步滑過頭）；清單重寫 direct／兩段式／動畫皆 **5/5**；空牌掛載後首次給牌 direct **5/5**、動畫 5/5、兩段式 **0/5（恆多一張）**。binding 回寫每次 1 次、無中途雜值。
  - **定案（D6）**：換牌與設 `centerID` 在同一次更新內完成（direct），不帶動畫、不做兩段式。
- **使用者在場 #1：UITests 基線（2026-09-23 18:00–18:06，HEAD `94123ac`；app 原始碼與分支點 `ec3fd4d` 相同，僅測試／腳本／文件變動）**：Paste 已退出；暖身 `ShellUITests/testWindowGeometryAndTitle` 通過（26.4s）；正式輪 `ShellUITests`＋`BatchUITests` 16 條：**14 過／2 敗**——`ShellUITests/testQuitMenuItemTerminatesApp`（A-10，既知不穩定：`XCUIApplicationState 3≠1`）、`BatchUITests/testBatchShellInEnglish`（`C-21 col_artist`）；後者單獨重跑 2/2 通過 → 判定為與執行順序有關的偶發，非基線回歸。回歸判準：之後同集合不得出現此兩條以外的失敗；此兩條若失敗需單獨重跑 2 次再判。產物：scratchpad `ui-baseline.xcresult`／`.log`。
- **決策**：thecure 辯論（Codex gpt-5.6-terra medium）原結論為「只顯示歷史」；Queue.dat 發現後前提改變，改依使用者裁定走佇列模式（本版 v3）。
- **Q3b（2026-09-23 19:5x–20:2x，`c50213a` 起）**：
  - 紅燈：`LyricsFlowModelTests` 17 條＋`AppModelTests` 整合 4 條（上一 session 已寫）；本 session 補 AppModel 整合 AC4／AC5／AC6／「換歌同時畫面翻轉時接管解除」4 條、monitor 2 條、R6 修正 20 餘條，先紅（編譯失敗或斷言失敗）後綠。
  - 實作：`LyricsFlowModel`（換歌當下同步推進佇列位置並重建牌組，讀檔排進串行工作鏈、讀回後以最新當前曲重建；卡片詳情最新者勝）；`AppModel` 接線（editor → lyricsFlow → batch）、可見性＝Editor 分頁 ∧ 畫面＝Cover Flow、來源輪詢（`start()` 才啟動）；移除 `AppTab.coverFlow`。**過渡**：Editor 分頁暫以「畫面＝Cover Flow 就整頁顯示它」切換，升降層、把手、可點的中心卡在 Q4（D2）。
  - **新發現並修正的缺陷**：寫入成功後的補讀（`forceRefresh`）發生在 Editor 解除 busy 之前，monitor 會因 busy 直接跳過——補讀被靜默吞掉。改為 busy 期間記下、全部來源空閒時補做一次（`NowPlayingMonitor.pendingForceRefresh`；`forceRefreshWhileBusyRunsOnceIdle`／`pendingForceRefreshWaitsForEveryBusySource`）。
  - **變異驗證（實際執行）**：把 R6 各修正改回舊邏輯（保留接口）後跑 9 組測試：新測試 19 條紅（含 window 溢位直接崩潰重啟、時鐘取消競態逾時），`git checkout` 復原後全綠。唯一未被抓到的是 AppModel 層 AC4 對 monitor 修正的依賴（時序競態不必然觸發），由 monitor 單元測試兜住。
  - 全量單元：571 條，只剩基線紅（RenderGeometry 2 條／8 斷言）；「運行時變更 centerID」一條在全量中偶紅一次，單獨重跑 2/2 綠（與 Q3a 同一條負載偶發）。
- **Q3.5（2026-09-23 20:2x）**：UI 測試組裝＝場景 env `AZW_UITEST_SCENARIO=present|missing|marked|notPlaying`（`App/UITestSupport/LyricsFlowUITestScenario.swift`：場景、旗標、假資料 ID、a11y identifier 的單一來源，app 與 UITests 同編）；假 Music `LyricsFlowUITestMusic`（actor、`setLyrics` 只寫記憶體）、恆 404 的 `UITestStubHTTPClient`、測試專屬設定 suite（reset／seed env，從不碰 `.standard`）、app 暫存目錄裡的假 Queue.dat／History.dat（牌組 5 張：左 2、中 1、右 2）。組裝單元測試 9 條綠；`LyricsFlowUITests` 7 條（AC1–AC5、AC14）與 `ShellUITests` 改動（改走 `notPlaying` 場景、AC10 以 identifier 判定導覽只剩兩個、E-10 鍵改驗把手標題）已寫；`xcodegen generate` 後 `build-for-testing` 綠（N3）。這些 UITests 在 Q4 前必紅（identifier、把手、標記按鈕、抓詞計數都還不存在），紅燈於使用者在場 #2 取得。
  - 全量單元 582 條只剩基線紅；`no_playback_gate.sh` 通過；H-02 Python 閘門 321 條 OK（實際命令為 `cd Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_gate*.py'`，§9.3 原寫 pytest，已更正）。
  - 新檔與改動檔逐檔行覆蓋全部 ≥ 90%。**`coverage_gate.sh`（Services＋Infra 整體 ≥ 80%）＝77.6% 不過**：非本 session 造成——Q1 為 81.4%，Q2 起 77.2%，原因是 AE client（`MusicAppleEventsClient`，AC11 明文豁免）Q2 新增方法擴大分母（覆蓋 10／384 行）；閘門腳本不認得豁免。處置（加豁免清單或補 opt-in `LiveMusicTests`）留 Q6 交使用者定。
- **使用者在場 #2（2026-09-23 20:31–20:45，HEAD `10d8b40`）**：xctestrun 的 `SystemAttachmentLifetime=keepNever`（失敗不錄全螢幕，本分支 scheme 原狀即如此）。預檢 `BatchUITests/testPreviewPaneIsReadOnly` 綠（12.8s，未被鑰匙串框卡住）。正式輪 23 條、11 紅：`LyricsFlowUITests` **7/7 紅**（全部停在畫面元素尚不存在——TDD 紅燈）；`ShellUITests` 預期紅 3 條（AC10 導覽 identifier、ja／zh-Hant 把手標題）；`BatchUITests` 5/5 綠（無新增紅）；A-10 `testQuitMenuItemTerminatesApp` 紅（`XCUIApplicationState 3≠1`，與基線同一簽名），單獨重跑 2 次＝1 紅 1 綠 → 判定為既知不穩定，使用者在場 #3 再觀察。產物：scratchpad `u2-*.xcresult`／`.log`。
- **Q4（2026-09-23 20:3x–20:4x，`08cf9dd` 起）**：D2 掛載結構（外殼常駐、開場畫面改覆蓋層並在開場期間 `accessibilityHidden`；Editor 頁常駐於分頁切換之外、Batch 以覆蓋層顯示）；`LyricsFlowPageView`（Cover Flow 以 offset 升降，動畫以 `.animation(_:body:)` 只包 offset——換歌時「畫面翻轉＋換牌」同一次更新，value 版動畫會把捲動位置捲進去、觸發 K5 誤判；焦點隨畫面；減少動態效果時無位移動畫；Editor 條件掛載）；把手（設計稿 64pt、兩態、刻度）；徽章 ✓／✗／—／?（中心卡附軌號）；中心狀態字；退回模式右側「接下來的歌暫時讀不到」；可點＝播放中 ∧ 幾何正中（`CoverFlowGeometry.isCentered`，容差 ±0.2 卡寬，與疊放同一 `onGeometryChange` 路徑）；Editor 的 Now Editing 狀態字＋缺詞紅條、「No lyrics for this song」（只接受已知缺詞的當前曲）、控件 identifier、DEBUG 抓詞計數（頁層 1pt 透明文字，Editor 升起時也在）；`AccessibilityID` 單一來源（app 與 UITests 同編，Release 也需要）；UITests 改以 `lyricsflow-coverflow` 的 value（`raised`／`lowered`）判定升降（該層常駐，只看「存在」會假綠）；§9.5 新鍵三語（`make_xcstrings.py` 重生，只新增）。
  - 測試：`LyricsFlowPresentationTests`（容差、徽章、狀態鍵、把手刻度）、`LocalizationTests` 新鍵三語、`EditorViewModelTests.fetchCountTracksEveryFetch`、`CoverFlowStripStackingTests.atMostOneCardIsCentredWhileSwiping`（觸控板滑動途中至多一張判為正中、落定恰好一張；**變異**：容差改 0.35 → `maxConcurrent=2` 紅，已復原）。全量單元 591 條只剩基線紅；`no_playback_gate.sh` 通過。一次全量中 `repositoryPassesTheGate` 耗時 40s（腳本單跑 0.9s、前兩輪 2.5–3.6s）——疑與同時跑的滑動測試搶資源，記錄待觀察。
  - U#3 前預檢：界面樹實機預檢（假 Music 場景、無障礙動作，不經 XCUITest）＋Codex 評審 Q3.5／Q4 差異，結果見下一條。
- **U#3 前預檢（2026-09-23 20:5x–21:2x）**：
  - **界面樹實機預檢**（Opus agent＋我，假 Music 場景、只用元素定界的 AXPress，不經 XCUITest、不碰 Music）：抓到兩個會讓 7 條 `LyricsFlowUITests` 全紅的問題——① `children: .contain` 容器上的 AXValue 被 SwiftUI 吞掉 → 改由 DEBUG 1pt 透明文字探針 `lyricsflow-surface` 承載升降值；② **產品缺陷：有歌在播時條帶停在第一張履歴卡、沒捲到播放卡**（VM 的中心已是播放卡，畫面卻停在第 0 張，不回寫——初始值路徑的症狀）。對照實驗：E1 Cover Flow 恆可聚焦 → 仍錯；E2 播放卡不變 Button → **正確**；E3 固定結構＋點擊手勢＋無障礙按鈕特徵 → 仍錯；E4 只留點擊手勢與懸停 → 仍錯；E5 卡片不掛任何手勢 → **正確 2/2**。結論：**條帶內容一帶手勢（Button、點擊、懸停），換牌後的捲動定位就失效**。改為卡片純展示、互動全在條帶層：條帶層的點擊手勢只認「正中播放卡的封面正面」；無障礙按鈕與懸停提示是條帶旁的並列層（掛在條帶 `.overlay` 上會被併進捲動區、不出現在 AX 樹——E7／E9 實測），`allowsHitTesting(false)` 讓觸控板捲動照常落到條帶；「播放卡是否在正中」由條帶的佈局幾何回報 VM（`CoverFlowViewModel.isPlayingCardCentered`）。E11 實測：播放卡置中、唯一按鈕、AX 框＝封面正面 260×260、按下降下；missing／重啟／marked／notPlaying 皆符合。另修 `edit_lyrics_of %@` 鍵名（SwiftUI 以插值格式字串查找）。
  - **Codex R7**（評審修復前版本，3 P1＋1 推測）裁決見 §14 R7。
  - 全量單元 595 條只剩基線紅；`no_playback_gate.sh` 通過；UITests `build-for-testing` 綠。
- **暫停點（2026-09-23 21:3x，HEAD `2d6c903`）**：剩使用者在場 #3、Q6 收官、使用者實機試用。下一個 session 的開工口令（整段複製貼上）：

```
/fatboyslim 繼續「Cover Flow × 找歌詞」。
【最終目標】Editor 頁內的 Cover Flow：播放中那張永遠置中，左＝Music 的「履歴」（History.dat），右＝接下來的歌（Queue.dat，隨機時讀 shuffledList）。有詞＝Cover Flow 升起；缺詞＝降下露出 Editor；寫入成功、彩帶撒完後升回（讀回仍缺詞＝寫入沒生效→留在 Editor 並提示）；「No lyrics for this song」標記後升回，下次不跳 Editor；只有正中且正在播的那張可點（點了進 Editor）；每張卡標 ✓／✗／—；Cover Flow 分頁已移除。
【本 session 目標】依序：① 使用者在場 #3（先問我）：跑 LyricsFlowUITests（8 條）＋ShellUITests＋BatchUITests，目標全綠；回歸集合對基線不新增紅（A-10、C-21 既知偶發，失敗就單獨重跑 2 次再判）；三態截圖（裁切到視窗、不拍憑證欄位）。紅了先定位，必要時用「界面樹實機預檢」手法（§13 U#3 前預檢，假 Music 場景＋元素定界 AXPress）。② Q6 收官：Phase 3 /simcodex（把 R7-③ 的駁回理由回餵複審）、全量測試、ACCEPTANCE 補 H-12 起（AC1–AC14）、證據包；③ 我實機試用：riseDelay 手感（U6）、AC13 中途退出 Music、U10（循序播放時唯讀看一次 Queue.dat 有沒有 shuffleMode 鍵）。
【先讀】docs/plans/2026-09-23-coverflow-queue-drawer.md（v3.6；§13 最後幾條＝Q3b／Q3.5／在場 #2／Q4／U#3 前預檢；§14 R6、R7＝辯論記錄）。分支 wip/coverflow-lyrics，HEAD 2d6c903。
【待我拍板】coverage_gate.sh（Services＋Infra ≥80%）目前 77.6% 不過：Q2 起 AE client（AC11 豁免）擴大分母所致——給閘門加豁免清單，還是補 opt-in LiveMusicTests？先與 Codex 辯論，再給我單一結論。
【紅線】絕不加任何播放控制，不改變 Music.app 的任何狀態（含啟動 Music、改 UI、寫它的檔案）；每段 TDD、每段全量單元只容許基線紅（RenderGeometry 2 條／8 斷言）；條帶內的卡片不得掛任何手勢（會打亂捲動定位，§13 E1–E11）；只在 wip/coverflow-lyrics 做 checkpoint，不 commit 到 feat／main，不 push；對我講結論用白話和我畫面上看得到的東西。
```

- **使用者在場 #3（2026-09-23 21:2x–22:0x，HEAD `4601bb9`＋UITests 修正；只動 UITests target，產品碼未改）**：
  - 暖身 `BatchUITests/testPreviewPaneIsReadOnly` 紅：Q4 給導覽按鈕加 identifier 後，XCUITest 讀到的 label 由「EDITOR」變「Editor」（界面樹探針：同一版 app 的 AXDescription 在真實啟動與假 Music 場景皆仍是「EDITOR」→ 產品無退化；與 `ActionButton` 既有註解「identifier 會改變 XCUITest 的比對」同源），以字樣定位的 `waitForMainUI` 全數找不到 → 改以 identifier 定位、字樣不分大小寫比對（`AppUITestCase.navButton`／`assertNavLabel`；Batch、Shell、BatchLive 跟進）。
  - 正式輪 24 條 19 綠。新紅 3 條皆為測試的點擊手法：① 兩側的卡畫在條帶捲動框（寬＝一張卡）之外，`element.click()` 找不到命中點 → 點**左側卡**露出的左上四分之一（步進後先等 AX 框穩定）；② 歌詞框是 NSTextView（AX 無 enabled，`waitUntilHittable` 恆假）且 NSScrollView 容器無 hit point → 沿用 C-07 的歸一化座標點入；③ Write 的 AX 框含位移的懸停白遮罩（未懸停 84pt、實際 42pt），全視窗噪點層又讓 XCUITest 驗不了命中點、退回點框正中＝按鈕下緣而落空 → 點上四分之一處。另：使用者當時的輸入法（繁體拼音）把鍵入的 "the " 轉成漢字、Write 未生效 → 加鍵入核對斷言；**UITests 前提新增「輸入法切 ABC」**（§9.3）。
  - 結果：`LyricsFlowUITests` **8/8 綠**（同一輪 `u3-lf8.xcresult`）；`BatchUITests` 5/5——C-21 家族兩輪各紅一條（英文版於正式輪、繁中版於證據輪），單獨各重跑 2/2 綠 → 順序相關偶發，同基線；`ShellUITests` 10/11，A-10 紅（正式輪＋證據輪＋單獨 3 次）。**A-10 定性**：旁掛進程監看，點 Quit（21:47:47.2）後進程於 21:47:48.5 前消失，XCUITest 仍回報 runningBackground 10 秒、收尾還去結束已不存在的 pid（`Unable to monitor event loop`，#2 紅那次同簽名）；另以 PID 定界 `NSRunningApplication.terminate()` 兩場景各 0.08–0.09s 退出 → 產品會退出，是 XCUITest 狀態回報卡住，非本分支回歸。**回歸判準（基線兩條以外不新增紅）：達成**。
  - 三態截圖（XCUITest 內只拍 app 視窗、假 Music、無憑證欄位）：scratchpad `u3-shots/lyricsflow-{present-raised,missing-lowered,marked-raised}.png`；目視與 AC1／AC2／AC5 一致。
  - **觀察（未修）**：① 左側（播過的）卡的徽章在右上角，被較靠中心的卡蓋住看不到（右側卡可見）——交使用者定；② M5 起既有的無障礙瑕疵：噪點層是全視窗無標籤 AXImage、`ActionButton` 的 AX 框含懸停遮罩（高 2 倍）——範圍外，記 P2。

- **Phase 3 /simcodex（2026-09-23 22:2x–09-24，自 `ddb07c3`，範圍＝分岔點 `ec3fd4d` 起的整個分支）**：3 輪 simplify（每輪 4 視角：重用／簡化／效率／高度）＋ Codex（`codex exec` 唯讀，讀凍結快照；`codex review --base` 不能帶自訂提示，改用 exec 才能回餵 R7-③）。第 3 輪 simplify 0 P1、Codex 0／0／0 → 提前結束。辯論見 §14 R9。
  - **修正（產品）**：① Queue.dat 任一項缺 tID → 整份不可用（D13 原文；原碼「略過」的理由未驗證，會把後面的歌當成下一首）；② Queue.dat 消失 → 右側退回＋提示（§1），檔案「在但讀不出」改回報 `.failed`（沿用上一份，AC8b），檔案消失時來源忘掉屬性戳（回來時即使屬性相同也重讀；履歴同）；③ 卡片詳情一批 1.5 秒總時限（AC8d）：`AEBudget.spend` 為送任何 AE 前的唯一扣預算步驟（篩選與逐欄共用），用完整批放棄；④ `LyricsStatusLabel` 取代 Editor 與 Cover Flow 兩份相同的狀態字；⑤ 佇列位置先比對上次位置（O(1)，仍經 `pick` 同一條規則），免得每 3 秒在主執行緒掃整份清單（整庫隨機可達 1.2 萬項）。
  - **覆蓋率閘門擋下了我方**：接上總時限後 AE client 由 384 增到 404 行，超過豁免上限 400 → 把可測的純邏輯搬出（`AEBudget.readColumns`、`TrackDetails.fromColumns`，皆有單元測試），豁免檔降為 378 行。上限如設計地擋住「邏輯往豁免檔裡長」。
  - **`NoPlaybackGateScriptTests` 逾時的真因**：全量中由 3 秒惡化到 40、87 秒、終至 120 秒逾時；單獨跑也逾時。當場取樣：9 支孤兒 `no_playback_gate.sh`（最久 25 分鐘）全停在 `getcwd → open()`——app 宿主的子行程打開 `~/Documents` 下的專案目錄時被系統擋住等待（推測為每次重建換新簽章後的「文件」資料夾存取授權，無人按就一直卡）。先試「子行程用乾淨環境」→ 無效（推測被推翻，已撤回該改動）。處置：測試移到 `Scripts/test_no_playback_gate.py`（終端機跑 1 秒；變異 2 組各被抓到），§9.3 列入必跑；Swift 版以 `.disabled` 停用，**刪除待使用者批准**；孤兒行程以 PID 清除。副作用：全量單元由 107 秒降到 20 秒。
  - 最終：全量單元 609 條只剩基線紅（RenderGeometry 2 條／8 斷言）；`coverage_gate.sh` 豁免前 78.3%、豁免後 95.5%（豁免檔 378／400）；`no_playback_gate.sh`、`test_no_playback_gate`、`test_coverage_gate`、H-02 Python 閘門全過。
  - **既存缺口（未修，待定）**：本分支改過的 View 檔逐檔覆蓋有 3 個低於 AC11 的 80%——`CoverFlowView` 35%、`CoverFlowItem` 73%、`LyricsFlowHandleView` 75%（另 `UI/ConfettiView` 44%）；Q4 結束時即如此、當時未記錄，主要由 UITests 驗證。
  - **P2（延後）**：串行任務鏈兩處重複（`LyricsFlowModel.enqueue` 與分支前既有的 `CoverFlowViewModel.dispatchPrefetch`）；`CoverFlowItem.reflectionRatio` 的 private 包裝；把手兩個配色函式同名易混；`spike_gate.sh` 與 `no_playback_gate.sh` 正則重複；Python 測試的 `run` 形狀重複。

## 14. 附錄：評審辯論記錄

### R1（2026-09-23）：Codex（12 條：2 P0／7 P1／3 P2）＋Opus 5 三視角（SA 約 25 條、SM 約 30 條、ST 23 條）

**採納**（→ v2 位置）：
- spike 安全閘門須先於 spike（Codex-1、SA-A1）→ S0；白名單取代黑名單、執行期內省＋負對照（Codex-2、SA-C1／C3／C4）→ AC9；spike 需授權預檢、不彈框（Codex-1、SA-A4）→ S0③；pid 定址防重啟 Music（SA-A2）→ D10、AC13；`kAENeverInteract`、timeout 單位、去識別化（SA-A5／A6／E2）→ S0。
- 同曲重發踢出 Editor（SM-1-1、ST-F4 皆 P0）→ §6 拆兩列、AC6。
- 升回計時可取消＋ABA 場次比對（SM-1-2、Codex-5）→ §6 `pendingRise`／`occurrence`、AC4。
- 空字串寫入誤升回、誤清標記（SM-1-3、ST-F5）→ `writeSucceeded` 依 trim 分列。
- 寫入期間換歌觀察不到（Codex-4、SM-1-4）→ 寫入後 `forceRefresh` effect。
- `unknown` 與讀取失敗（Codex-3、SM-1-8）＋讀取競態（SA-D4／D5）→ D9、AC7、AC12。
- 空 persistentID（Codex-6、SM-5-3）→ 不可標記、不進歷史（AC8）。
- `onSaved` 擷取時點（SM-2-2）→ D8③；標記清除歸 `LyricsFlowModel`（SM-2-3）；標記可觀察（SM-2-4）→ D4。
- 掛載結構：開場／切分頁都會走初始值路徑（SM-3-1）→ D2；歷史追加居中不可靠（SM-3-2）→ S5；動畫範圍（SM-3-3）、焦點（SM-3-4）→ D2、AC14；可點限正中（SM-3-5）→ D6。
- 事件分發不得 await AE（Codex-8、SM-4-3、SA-D1）→ D7；v1 不新增 Cover Flow AE。
- 初始狀態、ShellUITests 依賴真實 Music（ST-F1 P0）→ §6 初始＝editor、場景 `notPlaying`。
- AC5 與 D4「啟動清空」矛盾（ST-F2 P0）→ 顯式 reset env。
- H-02 閘門連 setup 都過不了、fixture 20 首（ST-F3 P0、Codex-9）→ U7。
- 基建缺口：Mock 歌詞錯位、可控時鐘、事件迴圈拆分（ST-F15）→ Q0；UI 測試組裝（ST-F16）→ Q3.5；E2E 先於 UI（ST-F11）→ 使用者在場 #2 取紅燈。
- 每 Q 全量綠、Q3 拆分、打破者修（ST-F12）；處置表（ST-F14）→ §9.6；覆蓋率量法（ST-F9）→ AC11；基線時點與回歸集合（ST-F8）→ 使用者在場 #1；Python 閘門回歸（ST-F17）；ACCEPTANCE 變更表（ST-F20）→ §9.7；i18n 鍵表（ST-F7／F23）→ §9.5；AC3 改 E2E（Codex-10、ST-F6）。
- U4 先裁決再做循序（Codex-7、SA-B7、SM-4-5、ST-F10，四方一致）→ §2.1、§8.2。
- 單元測試 host 碰真實 Music（SA-D6）→ D11。D9 取消標記按鈕撤回、D10 改鍵名撤回（ST-F21）。原型漏項（SM-5-1）→ Q4 補把手雙態、中心卡軌號、Now Editing 狀態字與紅色色條。

**修改後採納**：
- Codex-11（以 completion 定義「撒完」）→ 改為明確牆鐘常數 `riseDelay = ticks × frameInterval`：view 層 completion 受渲染與視窗前後台影響、難以單元驗證；牆鐘語義寫明、U6 試用調整。
- Codex-9（不要把 H-02 降成只驗可達）→ 不降級；改提「正式退役＋替代證據」交使用者裁決（U7）。
- SM-1-6（權限恢復）→ reducer 層處理重發與恢復；monitor 撤權恢復不重發屬既有行為（L6）。

**駁回**（理由回餵 Codex R2 複審）：
- Codex-12「滑動延到第二階段」：使用者上個 session 剛目視確認「現在滑動是對了」，移除屬產品決定、未被要求；以 D6「可點＝播放中∧幾何正中」＋不可變快照＋D2 結構控制複雜度。
- SM-1-7「切回 Editor 補抓詞」：B-05 既有語義（py:481），未被要求；列 L3。
- ST-F21「把手刻度／順序標籤／中心狀態字／hover 屬範圍膨脹」：這些在使用者被指向的設計稿內，屬需求；只撤回設計稿以外的 D9、D10。
- SM-5-2「當前曲單一持有（Editor 綁定曲也從 LyricsFlowModel 推導）」：Editor 綁定曲是 B-13 的獨立概念（寫入目標），合併屬重構、超出範圍。
- 原型「沒詞時 Write 停用」：既有 B 段允許寫空字串（清除錯詞的正當用途）；空寫入經 §6 留在 Editor。

### R2（2026-09-23）：Codex 複審 v2
- (A) §14 R1 的駁回 5 條與修改後採納 3 條：**全部「接受裁決」**，無重提（勝負判據：對抗者不再提＝維持）。
- (B) U4「v1 不做循序、另立計劃」：**同意**（無 Up Next／播放歷史 API，預測下一首非可觀測事實，插隊必錯）。U7「本分支正式退役 `CoverFlowUITests`、H-02 改附替代證據」：**同意**，前提＝ACCEPTANCE 明記舊證據退役並逐一連結替代測試。
- (C) 新問題 4 條，全部採納：N1（P1，空 ID 的同曲判定）→ §5.2、§6 `NowPlayingIdentity`；N2（P1，`stackingOrder` 非同步且四捨五入）→ D6 容差判定＋AC3 跨中點測試；N3（P1，Q3.5 缺 `xcodegen generate`）→ Q3.5 DoD；N4（P2，AC12 無第二比較來源）→ AC12 改為單一來源不變式。
- 結論：v2.1 定稿，進入 Phase 2（S0 起）。

### thecure（2026-09-23）：「接下來的歌」讀不到時的方向
- 議題：A 只顯示歷史／B 讀 Music 面板（Accessibility）／C 以 `current playlist` 推測並自我校驗。Codex 判定 A 正確；B 的不採用理由須改為「實測當時 `AXWindows=0`」而非一般化；C 在 Genius Shuffle 下價值為零。最擔心：右側空白被誤認為故障 → 須明示。
- 後續：使用者不接受「右側空白」，指出 Music 畫面上看得到下一首；再查發現 `Queue.dat`（事實 20–21），前提改變 → v3 以 Queue.dat 為主、A 作退回模式，並保留「明示讀不到」的設計（`upnext_unavailable`）。

### R3（2026-09-23）：Codex 複審 v3（9 條：2 P0／4 P1／3 P2），全部採納 → v3.1
- R3-1（P0）同曲重複時當前出現位置無法唯一定位 → AC8「當前出現位置解析」＋`OccurrenceResolver`，無法唯一即退回。
- R3-2（P0）「插歌不改變其他卡 ID」與序數 ID 矛盾 → 選擇接受序數 ID 在「同曲插在其前」時改變（不依賴未驗證的 `itID` 語義；S8 順帶觀察 `itID`）。
- R3-3（P1）只看 mtime、讀到寫入中 → D13 讀前讀後屬性比對、內容雜湊、保留最後有效快照。
- R3-4（P1）「換歌不重建」與滑動窗口矛盾 → AC8 改為增量窗口更新。
- R3-5（P1）transient nil／停止／Music 未執行未分界 → D15。
- R3-6（P1）U8 無前置關卡 → S8 置於 Q1 前，Q1 入口條件。
- R3-7（P2）退回模式歷史規則 → AC8b 有序集合規則。
- R3-8（P2）S6 樣本與部分失敗 → S6b、AC8d 版本 token 與 unknown 卡。
- R3-9（P2）「統一涵蓋所有播放方式」過度承諾 → §8.2 改寫。
- Codex 評：最易失敗的一步＝把 AE 的單一 persistentID 對齊 Queue.dat 中可重複的實例、並在重寫與換歌競態下維持正確窗口。

### 使用者裁定（2026-09-23 17:4x）
- 左側「一直有東西」＝歷史記錄：採用 Music 的「履歴」（History.dat），與 Music 畫面一致；跳過的歌不進履歴為 Music 語義，使用者已知悉。

### R4（2026-09-23）：Codex 複審 v3.2（8 條：6 P1／2 P2，無 P0）→ v3.3
- 採納：R4-1 左右來源獨立降級；R4-3 ID 規則單一來源（§5.2 改指 AC8）；R4-4 itID 只作 session 內身分＋epoch；R4-5 `shuffleMode=tracks` 不得改用 `list`；R4-6 History reader 排入 Q1／Q2；R4-7 左與中不以 persistentID 去重；R4-8 單一串行讀取工人、精簡結果、壓力測試。
- **修改後採納 R4-2（History 交接）**：不做「前一首先放暫存、等 History 確認」的交接層。理由：Music 的履歴只收播完的歌（事實 25），app 端無法區分「播完」與「跳過」（不讀播放位置），暫存項會把跳過的歌短暫放進左側、違反「與 Music 履歴一致」；且實測 History.dat 在歌曲結束同秒更新，缺口最多一次輪詢（3s）。改為：修正 L8 與事實 25 的矛盾敘述、每次真實換歌立即檢查 History 屬性（D16）。→ 回餵 Codex R5 複審。

### R5（2026-09-23）：Codex 複審 R4-2 裁決與 v3.3
- R4-2：**接受裁決，不重提**（以 Music 履歴語義為唯一真相；同秒更新＋換歌即查，3 秒空窗可接受）。
- 新矛盾 2 條，採納：R5-1 AC8b 改為只管右側；R5-2 補退回模式左卡 ID `hl:<persistentID>#<場次>`。
- 結論：v3.4 定稿，繼續 Phase 2（S5 → Q0）。

### 2026-09-23 18:4x 暫停點（使用者要求盤點剩餘工作）
- **已完成並存檔**：Phase 1 計劃 v3.4；spike S0–S9、UITests 基線（14/16，2 條既知偶發）、單元基線（分支點 407 條，RenderGeometry 2 條／8 斷言既紅）；Q0、Q1（`211926d`）、Q2（`f6d3f0e`）、Q3a（`c5c8c04`），每段全量單元只剩基線紅（Q3a 另有 1 條負載偶發，單獨重跑 2/2 綠）。
- **Q3b 進行中（本 commit，測試紅）**：已寫紅燈測試（`LyricsFlowModelTests`、Editor D8 三處、AppModel 整合 4 條）；已實作 Editor D8（標記判斷、取消自動抓詞、寫入前擷取目標、寫入回報、使用者輸入回報）、`ConfettiTiming` 單一來源、`StatusText` 兩條。**未做**：`LyricsFlowModel` 本體、`AppModel` 接線（事件分發、可見性、輪詢）、移除 `AppTab.coverFlow`。
- **Q0＋Q1 對抗覆核（Opus 5，實際執行 10 支 harness）**：無 P0；**P1 三條待修**——① `QueueSnapshot` 缺 `shuffleMode` 時預設 `off` 會改讀未打亂的 `list`（違反 R4-5）；② 寫入後讀回仍缺詞／再寫空字串時，待升回未取消，到期把缺詞曲升回（違反「缺詞＝Editor」）；③ 卡 ID 規格與 AC8 文字不一致（程式較合理，改 AC8）。P2 十二條（上一首／跳播時的位置推算、重複 itID、GatedPollClock 取消競態、標記陣列混入非字串等）。**兩條需使用者拍板**：同曲重發讀回缺詞時要不要取消升回（牽動 AC6 措辭）；同曲重發由「讀不到」變「缺詞」要不要降下 Editor。
- **未開始**：Q3.5（UI 測試組裝）、使用者在場 #2（新畫面測試紅燈）、Q4（畫面：Editor 內的 Cover Flow 層、升降動畫、把手、徽章、可點的中心卡、無詞按鈕、三語字串）、使用者在場 #3、Q6（/simcodex 評審、全量測試、ACCEPTANCE 改寫、證據包、實機試用）。

### R6（2026-09-23 Q3b）：待拍板兩題＋Q0／Q1 對抗覆核 P2 裁決（Codex 2 輪）
- **使用者拍板①**（寫入後讀回仍缺詞）：Codex 與我方同為「要」。使用者補充：這就是「寫入沒生效」→ 留在 Editor **並提示寫入沒有生效**；另確認「寫一個空格不算有詞」（空白寫入留在 Editor、不升回），純音樂曲用「No lyrics for this song」。→ AC6 例外①、§6、狀態欄文案 `writeNotConfirmed`。
- **使用者拍板②**（讀不到 → 缺詞）：有條件降下（Codex 精化：以本場次「使用者是否親手選過畫面」旗標判定；無效的點擊不算選擇）。→ AC6 例外②、§6 `hasUserChosenSurface`。
- **P1**：① shuffleMode 不明不得讀 `list`——採納，但實檔未證實順序模式是否寫此鍵，故「兩處都沒寫且只有 `list`」照讀為順序（U10）；② 空白寫入取消待升回——採納；③ 卡 ID 規格——以程式為準改寫 AC8（Codex 亦指出此為 P1，同向）。
- **P2 逐條**：B1 往回跳位置——採納（真實換歌只接受下一項）；B2 專輯點播短暫錯的右側——**Codex 部分勝**：不相鄰一律事件當下不猜，只剩「新曲恰好是舊清單下一項」不可辨識 → L9；B3 標記有詞曲——**Codex 勝**：只接受已知缺詞的當前曲，有詞／讀不到整個動作不生效（防潛伏標記）；B4＝拍板②；B5 測試時鐘取消競態——採納（鎖記錄取消、release 跳過）；B6 標記壞項——採納；B7 重複 itID——採納（中心與右側一致加序號，epoch 只看第一次出現）；B8 中心卡保護——採納（兩側皆剔除同 ID）；B9 window 溢位——**Codex 修正版**（先算剩餘容量再相加）。
- **B10**（只含 BOM 的歌詞）：第 1 輪 Codex 反對我方駁回；第 2 輪我方補證 Python 版 `bool(lyrics.strip())`（py:2254）同樣判為有詞、本版以 Python 為對照 → Codex **接受駁回**，但要求三處空白判定收斂為一處、且改用既有 `PythonCompat`（與 CPython `strip()` 逐字元一致）→ 採納：`LyricsText.isBlank`（`LyricsStatus`、Editor 自動抓詞、`AlbumTrack.hasLyrics` 共用；只含 U+200B 者改判有詞、U+001C–1F 改判空白，皆與 Python 一致）。
- **Codex 新提**：P0「取消升回須驗計時真的被取消、不只驗狀態」→ 採納（`readBackMissingAfterAWriteStaysInTheEditor` 以可控時鐘驗等待者歸零、放行後不升回）；P2 `NowPlayingIdentity` 註解與實作雙重定義 → 註解改指 `TrackInfo.signature` 單一來源。
- 全採納／全駁回檢查：B2、B3、B9、B10 為修改或對方勝，B10 經第 2 輪收斂；非一面倒。
### R7（2026-09-23 Q4 後、U#3 前）：Codex 評審 Q3.5＋Q4
- **P1-① 升降測試可假綠**（value 隨 reducer 立即變、offset 還在動畫）→ **修改後採納**：UITests 改為「升起＝升降值 raised ∧ 正中播放卡按鈕出現 ∧ Editor 不存在」「降下＝lowered ∧ Editor 歌詞框與 Write 出現」。正中播放卡按鈕只在條帶真的捲到播放卡時存在，恰好也守住 U#3 前預檢抓到的置中缺陷。位移動畫本身的觀感留給 U#3 截圖目視。
- **P1-② AC3 反向測試不完整** → **採納**：新增 `testPlayingCardAwayFromTheCentreIsNotClickable`（方向鍵把中心移走後，播放卡不再是按鈕、點了不進 Editor）；新增 DEBUG 重讀請求計數探針 `editor-hydrate-count`，點非播放卡前後不變。
- **P1-③ 幾何回報與畫面有一幀落差、動作寫死 `isCentered: true`** → **修改後採納**：改傳實際判定值（`coverFlow.isPlayingCardCentered`）。「捲動中整體停用」**駁回**：deployment target macOS 14 無捲動階段 API（`onScrollPhaseChange` 需 macOS 15）；落差約一幀（120Hz ≈8ms），可點狀態與畫面出自同一條幾何路徑；自製「最近 N ms 有位移」判定屬過度設計。→ Phase 3（/simcodex）回餵複審。
- **推測：開場淡出 0.2s 與 A-01 斷言競態** → **採納**：A-01 改為等 splash 消失（`waitForNonExistence`），語義不變。
- Codex 確認：Q3.5 組裝未碰 `.standard`、Keychain、Music，支援碼全在 `#if DEBUG`。
### R8（2026-09-23 在場 #3 期間）：thecure——`coverage_gate.sh` 77.6% 的處置（Codex gpt-5.6-terra medium，3 輪）
- 事實：Services＋Infra＝1546／1992＝77.6%；`MusicAppleEventsClient` 10／384（2.6%，只有 `mapError` 有覆蓋）；排除它＝1536／1608＝95.5%；其餘各檔 ≥75%。xccov 報表 3 個 target，Services／Infra 的非測試檔只在 app 本體、無重複計數。`LiveMusicTests` 已存在（opt-in，Q2 已補 `nowPlaying`／`trackDetails`），其中 `writesLyricsByPersistentIDVerbatim` 會對使用者正在播的曲送 `set lyrics`。
- 第 1 輪：我方主張「閘門加豁免清單（改良版）、不把 opt-in 實機結果併入閘門」→ Codex **判定正確**，但 B 應保留為閘門外的手動 smoke；護欄須強化（完全一致的相對路徑、只在 app 本體且唯一、executable>0；行數預算由 450 收緊到 400；免除前後數字並列）；`decodeState` 抽出今次不做（同意）。
- 第 2 輪（我方反駁 3 條，Codex **全部接受**）：不設到期自動失敗（同一輸入不因時間變紅）；Features 新檔／改動檔逐檔 ≥80% 不進閘門（閘門只定義 Services／Infra，逐檔檢查走 §9.3 xccov 手順並記錄基準 commit、檔案清單、各檔數字、xcresult 位置）；寫入測試不改碼（範圍外），改為文件明定「只在使用者明示許可時執行，平時 `-skip-testing` 且整個參數加引號」。
- 第 3 輪（整體確認）：Codex 補兩處，**皆採納**——分子分母限定 app 本體（實測數字不變：1546／1992）；新測試檔 `test_coverage_gate.py` 不會被 `test_h02_gate*.py` 的探索規則找到 → §9.3 另列執行命令。`approvedOn` 以使用者批准當日填實。
- Codex 最擔心：豁免清單變成藏未測邏輯的永久箱子——以「僅 1 檔、行數上限 400、報表必印理由與批准日」防範。
- 收斂結論（待使用者拍板）：閘門加豁免清單（僅 `Services/Music/MusicAppleEventsClient.swift`）＋上述護欄＋合成 JSON 的黑箱測試（先紅）；AC11 文字同步；`LiveMusicTests` 與 AE client 程式碼不動。
### 使用者裁定（2026-09-23 22:0x，在場 #3 後）
- R8 收斂結論：**照做**（`approvedOn` 2026-09-23）。實作：`coverage_gate.sh` 讀 JSON 報表模式＋豁免清單與護欄；`Scripts/test_coverage_gate.py` 9 條（先紅 9/9，後綠）；變異 4 組（關預算、放寬 target、子字串比對、關重複檢查）各被抓到；真實報表：豁免前 77.6%（1546／1992）、豁免後 95.5%（1536／1608）通過。
- 左側卡徽章被蓋住：**改到露出的一角**——以「相對當下正中」判定：正中左側的卡放左上、其餘右上（方向鍵瀏覽時跟著換邊）；`LyricsBadge.corner(of:in:centerID:)` 純函數＋3 條單元測試（先紅：編譯失敗）。
### R9（2026-09-23～24 Phase 3 /simcodex）：Codex 3 輪＋simplify 3 輪
- **R7-P1-③（回餵）**：Codex 第 1 輪即**撤回**，第 2、3 輪再確認不堅持（可點值出自同一條幾何路徑、macOS 14 無捲動階段 API）→ 我方勝，維持。
- **第 1 輪 Codex 3 條 P1 全採納**（各自讀碼驗證屬實）：缺 tID 應整份不可用（D13 原文）；Queue.dat 消失不得沿用舊清單（§1）、讀取出錯不是「不存在」；卡片詳情缺總時限（AC8d）。simplify 另採 2 條（狀態字重複、每 tick 全清單掃描）；**暫緩** 1 條（串行任務鏈重複：另一處是分支前既有碼，超出本次 diff）。
- **第 2 輪 Codex 2 條 P1**：① 篩選步驟不在預算內——S6 實測篩選不另送 AE（5 欄≈5 AE），但 Round 1 拿掉了原本的單一 AE 上限，這一步反而無上限 → 採納（高度視角獨立指出同一點）；② Python 版閘門測試未被必跑命令呼叫 → **部分採納**：§9.3 列入；其餘駁回（本專案無 CI，必跑清單即 §9.3；第三層防線 `no_playback_gate.sh` 掃 repo 一直在 §9.3，搬走的只是自我測試；Swift 版在 app 宿主內必卡）。第 3 輪 Codex **撤回** → 我方勝。
- **第 3 輪**：Codex 0／0／0；simplify 無 P1。重用與高度兩個視角各自指出「篩選前扣預算」與逐欄那段是同一語義的第二份實作、且用完時的處理不一致（1 tick 硬送 vs 整批放棄）→ 雖為 P2，依「同一語義只留一處定義」收斂為 `AEBudget.spend`；簡化視角建議刪掉篩選前的扣預算（P2）→ **駁回**（Codex 與高度視角上一輪都要求此防線，刪掉等於退回無上限）。
- 全採納／全駁回檢查：Codex 共 5 條 P1——4 條採納（含 1 條部分）、1 條部分駁回並經對方撤回；simplify 共 9 條（P1 3 條採納、1 條暫緩；P2 1 條駁回、2 條收斂、其餘延後）。非一面倒。
### R10（2026-09-24）：thecure——AC11「改動過的 Features 檔每檔 ≥80%」與 SwiftUI View 檔（Codex gpt-5.6-terra medium，2 輪）
- 事實：本分支新增／改動的 View 檔逐檔覆蓋——`CoverFlowView` 37%、`LyricsStatusLabel` 0%、`LyricsFlowHandleView` 78%、`CoverFlowItem` 73%（只動一個常數）、`UI/ConfettiView` 44%（只動一行常數）；`EditorView` 96%／`RootView` 93%／`LyricsFlowPageView` 93% 並非有測試在驗，而是單元測試宿主就是 app、啟動時畫出主畫面「順帶」通過。View 的行為由 `LyricsFlowUITests`（U#3 8/8）與三態截圖驗證。
- 第 1 輪：我方「View 宣告檔不適用逐檔 80%、埋在 View 裡的判斷抽成純函數」→ Codex：方向對，但**不可一律豁免**（會把 AC3 的核心判定一起免掉）；指出需抽出並全分支測試：點擊許可（正中 × 正面矩形，含邊界）、`playingTitle` 三種落空、把手刻度外觀；`reflectionRatio` 已是「點擊矩形」與「無障礙層倒影空白」的共同契約、`ConfettiView` 改用的影格間隔與升回延遲共用 → 須測；改寫條文須可追蹤。**全數採納**（讀碼驗證屬實）。
- 第 2 輪（整體確認）：Codex 再補 2 點，**採納**——① 既有 UITests 只點無障礙按鈕的中心，證明不了四邊對齊 → 新增 `LyricsFlowUITests.testOnlyTheFrontFaceOfThePlayingCardIsClickable`（按鈕框＝播放卡上方正方形；點倒影不開、點正面角落開），待使用者在場跑；② 徽章的 `LyricsBadge.Tone.color`：`Tone` 本身即意義層代號（已測），其顏色對應是設計常數 → 在證據表寫明不測理由。
- 已做（TDD，先紅後綠）：`CoverFlowGeometry.centreFace(in:reflectionRatio:)`／`acceptsPlayingCardTap(isCentered:location:face:)`、`CoverFlowViewModel.playingCardTitle`、`HandleTick.appearance`（`TickAppearance` 意義代號）、`riseDelay == 影格間隔 × 步數 == 3.2s`；全量單元 614 條只剩基線紅。
- Codex 最擔心：AC3 的實際可點＝VM 的「正中」狀態 × View 的正面命中 × 無障礙層位置，三者座標系接縫一歪，純函數與截圖都照綠、實際點擊卻壞 → 以上述新 UITest 兜住。
- **AC11 改寫提案（待使用者批准；批准前不得視為已符合）**：「SwiftUI View 宣告檔的逐檔行覆蓋不作為合否標準。新增／改動 View 內的狀態判定、輸入許可、座標／尺寸計算、顯示內容與意義外觀的對應，一律抽成純函數或值型別並全分支單元測試；抽不出的 SwiftUI 接縫以註明對應 AC 的 XCUITest 或核准的截圖／AX 證據驗證。每個改動的 View 在證據包列出 (a) xccov 實測 (b) 抽出的邏輯與測試名 (c) UI 證據 (d) 未測分支的理由。View 以外（模型、VM、純函數、服務）照舊逐檔 ≥80%。」
