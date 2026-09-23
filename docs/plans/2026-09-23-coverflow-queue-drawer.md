# Cover Flow × 找歌詞 —— 實施計劃（v3.4 定稿，2026-09-23；v3.2 經 Codex R4（8 條：7 採納、1 修改後採納）、R5（接受裁決、2 條矛盾修正）修訂）

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
| AC5 | 按「No lyrics for this song」→ 標記綁定曲（非空 ID）→ 若為當前曲則升回、取消自動抓詞；重啟後同曲不跳 Editor、不自動抓詞；該曲日後寫入成功（非空）清除標記 | 單元（注入 defaults suite）＋XCUITest `markingNoLyricsPersistsAcrossRelaunch`（第一次啟動帶 reset env、重啟不帶） |
| AC6 | 同曲重發（forceRefresh、notPlaying 後再播）→ 只更新狀態與徽章，**不動畫面、不取消待升回** | reducer 單元＋整合（`sameTrackRefreshKeepsSurface`） |
| AC7 | 徽章 ✓／✗／—／?（unknown）與 `LyricsStatus` 一致；優先序 present ＞ markedNone ＞ missing；歌詞讀取失敗＝unknown → 不降下、不自動抓詞 | `LyricsStatus.resolve` 全真值表＋整合 |
| AC8 | 佇列模式：牌組＝Queue.dat 清單中當前曲前 K 首＋當前＋後 K 首，播放中置中。換歌（同一份清單）→ **不重讀整份清單、不重置 Cover Flow**，以增量窗口更新：未離窗的卡保留身分、中心平移（R3-4）。Queue.dat 內容變更（Genius／插歌）→ 依新清單重建窗口。**卡 ID 規則（唯一規格）**：右側＝`q:<epoch>:<itID>`；中心＝`now:<epoch>:<itID>`；左側＝`h:<History 項在檔中的序號>`（History 由舊到新只追加，序號即該次完成的身分）；History 不可讀而改用本 app 觀察到的歷史時＝`hl:<persistentID>#<真實換歌場次>`（每次真實換歌場次唯一，同曲重播為不同卡，R5-2）。`itID` 只視為「佇列 session 內身分」（R4-4）：新快照中若同一 `itID` 對應到不同 persistentID，該 `itID` 的 epoch 加一；同 itID 同 PID 維持 epoch（保住插歌穩定性）。itID 缺失 → `q:pid:<persistentID>#<第幾次出現>`；退回模式中心＝`now:pid:<persistentID>#<真實換歌場次>`。左側與中心**不以 persistentID 互相去重**（同曲重播可同時在左與中，R4-7）。**序列種類**（R4-5）：`shuffleMode == tracks` 時只接受完整有效的 `shuffledList`，否則保留最後有效快照或進 AC8b，**絕不改用 `list`**；`QueueSnapshot` 記錄 `sequenceKind` 與所選序列的內容雜湊。**當前出現位置解析**（R3-1）：真實換歌時取「上次已解析位置之後第一個相符出現」；清單重寫後若相符出現唯一→採用；多個→以上次位置為提示取最近者，仍無法唯一→退回模式（AC8b），不猜 | `QueueSnapshot`／`DeckSnapshot`／`OccurrenceResolver` 單元（fixture plist：本次三種實測形狀、同曲重複、同曲插入、前進／跳播／窗口邊界） |
| AC8e | 左側＝`History.dat` 最近 K 筆（由舊到新排向中心）；新播完的歌在檔案更新後出現在中心左側；檔案不可讀 → 左側改用本 app 觀察到的歷史 | 單元（fixture：本次實測形狀、壞檔） |
| AC8b | 右側退回模式（**只管右側**；左側由 AC8e 獨立決定，R5-1）：**沒有任何已驗證的有效快照**、或最後一份有效快照中找不到當前曲（連續 2 次輪詢）、或當前出現位置無法唯一解析、或 Music 未執行 → 右＝空＋「接下來的歌暫時讀不到」小字；條件恢復後自動回到佇列模式。**單次讀取失敗或讀到寫入中的檔案 → 保留最後一份有效快照，不切模式**（R3-3）。歷史＝有序集合：真實換歌時把「前一首」移到尾端；當前曲不進左側；同曲重發不更新；上限 50；空 persistentID 不進（R3-7） | 單元（含 A→B→A、半份 plist、同 mtime 內容變化、原子替換）＋整合 |
| AC8c | Queue.dat 只讀：讀取碼只用 `Data(contentsOf:)`；該檔所在模組不得出現任何寫入／移動／刪除／建立檔案或設定屬性的 API；解析失敗不重試寫入、不拋到 UI | 腳本閘門（AC9 ③ 增列）＋單元 |
| AC8d | 卡片詳情（曲名、歌手、專輯、歌詞狀態）以 persistentID 批次讀取（去重後 ≤ 21 首一批）：單一背景 actor、最新者勝（帶快照版本 token，舊任務不得覆蓋新版）、總 deadline、快取（寫入／標記時更新該卡）；部分失敗 → 該卡狀態 `unknown`、只顯示封面；不阻塞事件分發、不餓死輪詢（R3-8） | 單元（`SerialAEQueueMusicClient` 公平性、版本 token）；時間界＝真機 |
| AC9 | **無播控（三層）**：① `MusicControlling` 不含播控方法（類型層）；② 執行期測試以 `protocol_copyMethodDescriptionList` 列出 Music `@objc` 協議的全部選擇器，必須 ⊆ 允許清單、`set*:` 只許 `setLyrics:`、required 方法＝0；`SBObject`／`SBApplication` 上帶 `AZW` 前綴的協議只能是允許的那幾個；負對照協議（`playpause`／`playOnce:`／`{get set}` 的 `shuffleEnabled`／`@objc(nextTrack)` 改名）必須回報 4 個違規；③ `Scripts/no_playback_gate.sh`（grep，stdin 可餵負對照）：`import ScriptingBridge` 只許出現在 `Services/Music/MusicAppleEventsClient.swift` 與 spike 檔；全部 target 目錄（`App Features Services Infra UI`）＋spike 禁 `NSAppleScript|NSUserAppleScriptTask|OSAScript|osascript|AESend|NSAppleEventDescriptor\(eventClass|sendEvent\(options:|MediaRemote|NX_KEYTYPE|import (OSAKit|Carbon)`；SB 檔內禁 `perform\(|NSSelectorFromString|Selector\(\(|setValue\(|makeObjectsPerform|byApplying:[^)]*with:|\.(add|insert|remove|replace)(Object)?\(`，`value(forKey: "…")` 的 key ⊆ {`rawData`} | 執行期測試隨全量單元跑；腳本退出碼；每條禁止模式各一負對照 |
| AC10 | 導覽區恰好兩個按鈕（Editor｜Batch，以 identifier 判定）；新字串三語齊（新鍵加入 `LocalizationTests` 清單） | `LocalizationTests`＋`ShellUITests` |
| AC11 | 每個 Q 結束：全量單元綠（skip 已知 flaky 一條）；新檔與改動過的 Features 檔每檔行覆蓋 ≥ 80%（AE client 新方法豁免、另補 opt-in 唯讀 `LiveMusicTests`）；UITests 回歸集合（`ShellUITests`＋`BatchUITests`）對分支點基線不新增紅燈（A-10 已知 flaky 除外）；`test_h02_gate_*.py` 綠 | `xcodebuild test`＋`xccov`＋`coverage_gate.sh <xcresult>`＋pytest |
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

**State**＝`surface`、`nowPlayingID: NowPlayingIdentity?`、`occurrence`、`status`、`pendingRise: Token?`、`isDenied`。事件中的 `id` 一律是 `NowPlayingIdentity`（N1）；`writeSucceeded`／`markedNone` 的 `id` 是非空 persistentID，與當前曲比對時用其 identity。**初始**＝`editor`、無當前曲（啟動時未收到事件 → Editor 顯示 NO ARTIST／NO TRACK，與現行一致）。

| 事件 | 前置 | 結果 | Effect |
|---|---|---|---|
| `nowPlaying(id, status)`，`id ≠ nowPlayingID`（真實換歌） | — | `occurrence += 1`；`status == .missing` → `editor`，其餘（`present`／`markedNone`／`unknown`）→ `coverFlow`；清 `pendingRise`；`isDenied = false` | 取消升回計時 |
| `nowPlaying(id, status)`，`id == nowPlayingID`（同曲重發） | — | 只更新 `status`；畫面與 `pendingRise` 不動；若 `isDenied` 則同真實換歌處理（權限恢復） | — |
| `tapPlayingCard` | 有當前曲 ∧ 畫面＝`coverFlow` ∧ 該卡位於幾何正中 | `editor`；清 `pendingRise` | 取消升回計時 |
| `toggleHandle` | — | 翻轉畫面；清 `pendingRise` | 取消升回計時 |
| `editorTextEdited` | `pendingRise ≠ nil` | 清 `pendingRise` | 取消升回計時 |
| `writeSucceeded(id, text)` | trim(`text`) 非空 | 該曲狀態＝`present`、清該曲標記、更新歷史卡徽章；若 `id == nowPlayingID` ∧ 畫面＝`editor` → `pendingRise = Token(occurrence)` | 排程 `riseDue(token)`；觸發 `forceRefresh`（唯讀，補上 busy 期間漏掉的換歌） |
| `writeSucceeded(id, text)` | trim(`text`) 為空 | 該曲狀態＝`missing`（若未標記）；畫面不動 | `forceRefresh` |
| `writeFailed(id)` | — | 不動 | `forceRefresh` |
| `riseDue(token)` | `token == pendingRise` ∧ `token.occurrence == occurrence` | `coverFlow`；清 `pendingRise` | — |
| `markedNone(id)` | 非空 `id` | 記標記；若 `id == nowPlayingID` → `coverFlow`、清 `pendingRise` | 取消該曲自動抓詞 |
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
- **D6 滑動保留、可點＝播放中 ∧ 幾何正中**：保留拖曳／方向鍵瀏覽（使用者上個 session 剛目視確認「滑動是對了」）；`CoverFlowStrip` 的內容閉包多傳 `isCentered`：在 `CoverFlowStripCell` 的**同一個** `onGeometryChange` 路徑內，以正規化距離 `|d| ≤ 0.2` 判定（帶容差；捲動跨中點途中沒有任何卡可點；不用 `centerID`、不用四捨五入後的 `stackingOrder`）（N2）；只有 `isPlaying ∧ isCentered` 的卡包成 `Button(.plain)`。牌組轉場（換歌、清單重寫、首次給牌）一律在同一次更新內換牌並設 `centerID`、不帶動畫（S5：direct 16/16；兩段式在首次給牌 0/5、動畫在換歌 5/6）。
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
./Scripts/coverage_gate.sh <scratch>/unit.xcresult          # Services／Infra 既有門檻
xcrun xccov view --report --files-for-target "Azathoth's Whisper.app" <scratch>/unit.xcresult   # 新檔與改動檔逐檔
./Scripts/no_playback_gate.sh
python3 -m pytest Scripts/test_h02_gate_*.py -q
# UITests（使用者在場；先關 Paste 等會彈窗的常駐 app）
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
- **決策**：thecure 辯論（Codex gpt-5.6-terra medium）原結論為「只顯示歷史」；Queue.dat 發現後前提改變，改依使用者裁定走佇列模式（本版 v3）。

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
