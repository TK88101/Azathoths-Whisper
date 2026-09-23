# Cover Flow × 找歌詞 —— 實施計劃（v2.1 定稿，2026-09-23）

- 分支：`wip/coverflow-lyrics`（自 `wip/h02-fix4`@`ec3fd4d` 分出；只做本地 wip checkpoint，不 commit 到 `feat/*`／`main`、不 push）
- 設計稿（互動原型）：https://claude.ai/artifact/GZSFdZEvyoshP48owh7c5G
  （01 有歌詞＝Cover Flow／02 缺歌詞＝Editor／03 循序播放；原型下方的虛線列只用來模擬 iTunes 換歌，**不進 app**）
- 模式：fatboyslim **normal**（依據：U4／U7 待使用者裁決、XCUITest 需使用者在場授權 Automation Mode、終點要使用者目視——不適合無人值守 loop）
- 評審：v1 經 Codex（R1，12 條）＋Opus 5 三視角（SA＝spike／AE，SM＝狀態機／接線，ST＝範圍／可測性）對抗評審；v2 經 Codex R2 複審（接受全部裁決、同意 U4／U7 建議、新提 4 條全採納）→ v2.1 定稿；記錄見 §14。

## 0. 複述（slipknot 17）

- **目標**＝讓使用者一眼看出「正在播的歌有沒有歌詞」：有就只看封面（Cover Flow），沒有就直接進 Editor 把詞找到並寫入，寫完自動回到封面。
- **完成標準**＝§4 驗收標準全部可判定通過＋使用者實機目視確認。
- **不做**＝任何播放控制、任何改變 Music.app 狀態的操作（含啟動／重啟 Music、改 UI、改曲庫 metadata）；讀待播佇列；保留 Cover Flow 分頁。

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

- **卡片**：每張卡標 ✓ 有詞／✗ 缺詞／— 已標記無詞。隨機播放：正在播的那張**永遠在最右端**，新歌進來才把它推到左邊（只有歷史，沒有未知佔位卡）。
- **循序播放右側顯示接下來的歌**：原型 03，**U4 待使用者裁決**（§11）。

## 2. 範圍

### 2.1 v1 範圍（U4 的建議答案＝「循序模式另立計劃」；若使用者選「要」，加做 §8.2 的 SEQ 任務）
1. Cover Flow 由獨立分頁改為 Editor 頁內的一層，依當前曲歌詞狀態自動升降（§6）。
2. 卡片＝本 app 觀察到的**聆聽歷史**（隨機與循序播放都一樣），播放中永遠最右。
3. 卡片標出歌詞狀態；「沒有詞」標記持久化在 app 設定、不寫進音樂檔。
4. 當前曲讀取改為**釘住 specifier、同一次 `run` 內讀完屬性與歌詞**（修既有的「A 的曲目＋B 的歌詞」競態；新介面把「出現 Editor＝沒詞」變成強主張，此競態會導致錯寫）。
5. 無播控的執行期白名單閘門（取代 v1 的 grep 黑名單）。

### 2.2 非目標
- 任何播放控制——**使用者既裁定，不重議**。
- 讀 Music.app 待播清單（Up Next）——無 API（§3 事實 1）。
- 聆聽歷史跨重啟持久化（D3）。
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
| AC8 | 歷史：播放中永遠最右；重播同曲移到最右（不重複）；上限 50；空 persistentID 的曲不進歷史、不可標記 | `ListeningHistory` 單元 |
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
| 聆聽歷史 `ListeningHistory` | 本 app 本次執行觀察到的換曲序列（值型別） | 條目＝非空 `persistentID`（去重） | 不是 Music.app 的播放歷史；只在記憶體 |
| 牌組快照 `DeckSnapshot` | 某一刻 Cover Flow 的不可變卡片序列＋播放中卡 ID＋各卡狀態 | 卡 ID＝`persistentID`（歷史已去重，唯一） | 只在換歌／寫入／標記時重建 |
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

- **D1 牌組**：`DeckSnapshot`（不可變）由 `ListeningHistory`＋標記＋播放中 ID 推導；卡片資料沿用 `AlbumTrack`（事件 `TrackInfo`＋歌詞轉成），`isPlaying` 由 `playingID` 推導、不存在卡上。`CoverFlowCenterLabel`、`CoverFlowPrefetchWindow` 改吃快照（預取送 `persistentID`）。
- **D2 掛載結構**（SM-3-1、SM-3-4、ST-F3）：
  - shell 從啟動起常駐，開場畫面改為**覆蓋層**；Editor 頁層（Editor＋Cover Flow）在分頁 switch **之外**常駐，Batch 以覆蓋層顯示（Editor 頁層此時 `allowsHitTesting(false)`／`accessibilityHidden`）→ strip 一律以 `items=[]`、`centerID=nil` 建立，此後只走運行時路徑，**不再經過初始值路徑**（缺陷 3 的觸發條件在新結構下不存在）。
  - Cover Flow 常駐、以 `offset` 升降；**Editor 條件掛載**（畫面＝`editor` 才存在，狀態都在 VM）→ 一次解決被遮住的 NSTextView 搶焦點、I 形游標、點擊穿透。
  - 升降動畫只作用在 `offset`（`.animation(_:body:)`，key＝`surface`）；牌組變更 `disablesAnimations` → 不把捲動位置捲進動畫（防 K5 誤判接管）。`accessibilityReduceMotion` → 無位移動畫。
  - Cover Flow `.focusable(surface == .coverFlow)`，切換時以 `@FocusState` 搬移焦點。
- **D3 聆聽歷史只在記憶體**。
- **D4 無詞標記**：`ConfigStore` 擴充（鍵 `NoLyricsMarkedTrackIDs`，字串陣列）；`LyricsFlowModel` 持有其可觀察鏡像供按鈕／徽章讀取。UI 測試組裝用專屬 suite：第一次啟動帶 `AZW_UITEST_RESET_DEFAULTS=1` 清空、需要時以 `AZW_UITEST_SEED_MARKS` 預植標記；**從不碰使用者的 `.standard`**。
- **D5 升回延遲**：§6 `riseDelay`。
- **D6 滑動保留、可點＝播放中 ∧ 幾何正中**：保留拖曳／方向鍵瀏覽（使用者上個 session 剛目視確認「滑動是對了」）；`CoverFlowStrip` 的內容閉包多傳 `isCentered`：在 `CoverFlowStripCell` 的**同一個** `onGeometryChange` 路徑內，以正規化距離 `|d| ≤ 0.2` 判定（帶容差；捲動跨中點途中沒有任何卡可點；不用 `centerID`、不用四捨五入後的 `stackingOrder`）（N2）；只有 `isPlaying ∧ isCentered` 的卡包成 `Button(.plain)`。歷史追加後的居中方式依 S5 結果定（直接賦值／兩段式：新卡首次 `onGeometryChange` 後才居中）。
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
| **U** | **使用者在場 #1**：裁決 U4、U7；UITests 基線（分支點 `ec3fd4d`，回歸集合＝`ShellUITests`＋`BatchUITests`）；S1 若需授權在此補 | 基線結果記入 §13 |
| **Q0** | 測試基建（TDD）：修 `MockMusicClient` 歌詞錯位＋鎖定測試；新增 `GatedPollClock`（可控時鐘）；`AppModel` 拆出 `startEventLoop()`（不啟動輪詢即可驅動事件）；D11 | 新基建各有測試；全量綠 |
| **Q1** | 純邏輯（TDD）：`LyricsStatus.resolve`、`ListeningHistory`、`DeckSnapshot`、`LyricsFlowModel.reduce`（§6 每列至少一測，含 ABA、同曲重發、空寫入、權限恢復）、`ConfigStore` 標記擴充 | 紅燈摘要記 §13；新檔 ≥ 80% |
| **Q2** | Music 讀取與安全（TDD 能測的部分）：D9 `nowPlaying()`＋monitor 改用＋`trackChanged` 歌詞改 `String?`；D10；AC9 ② 執行期白名單測試＋負對照協議；AC9 ③ `no_playback_gate.sh`＋負對照；opt-in 唯讀 `LiveMusicTests` 補 `nowPlaying()` | AC9、AC12 綠；替身整合測試綠；Editor／Batch 既有測試綠 |
| **Q3a** | `CoverFlowViewModel` 改吃 `DeckSnapshot`（移除 `albumChanged` 消費、分頁懶載入）；可見性＝Editor 分頁 ∧ 畫面＝`coverFlow`；`CoverFlowViewModelTests` 依 §9.6 處置表重建並拆兩檔；`CoverFlowCenterLabelTests`／`CoverFlowPrefetchWindowTests` 跟進 | 處置表每條落實；全量綠 |
| **Q3b** | `LyricsFlowModel`（@Observable，含 reduce＋升回計時＋標記鏡像）；D8 Editor 改動；`AppModel` 接線（D7、`updateCoverFlowVisibility()` 由 `select` 與畫面變更兩處呼叫）；**移除 `AppTab.coverFlow`**＋`AppModelTests`／`CoverFlowUITestMusicTests` 跟進；ACCEPTANCE 對應條目同步改寫（§9.7） | 整合測試覆蓋 AC1／AC2／AC4／AC5／AC6（含換歌同時畫面翻轉時 override 仍為 false）；全量綠 |
| **Q3.5** | UI 測試組裝（純代碼、無人值守）：在既有 `makeCoverFlowUITestModelIfRequested` 加場景 env `AZW_UITEST_SCENARIO=present|missing|marked|notPlaying`；新 DEBUG 檔 `LyricsFlowUITestMusic`（actor、`setLyrics` 只寫記憶體）、`UITestStubHTTPClient`（恆 404）；D4 的 defaults suite；列入 `project.yml` UITests sources；先寫 `LyricsFlowUITests`（AC1–AC5、AC14）與 `ShellUITests` 改動 | `xcodegen generate` 後 `build-for-testing` 綠（N3）；組裝有單元測試 |
| **U** | **使用者在場 #2**：跑 `LyricsFlowUITests` 出紅燈（TDD 紅） | 紅燈記 §13 |
| **Q4** | UI：D2 掛載結構；把手（升降兩態皆顯示、箭頭方向、狀態刻度、「最新在最右」標籤）；卡片徽章（中心卡含軌號）；播放中∧正中卡 `Button`（hover「Edit lyrics」、a11y label、`coverflow-playing-card`）；中心標籤下方狀態字；Now Editing 卡片狀態字＋缺詞紅色色條；Editor「No lyrics for this song」；`make_xcstrings.py` 新鍵；identifiers；`xcodegen generate` | 建置綠；`LocalizationTests` 綠；`CoverFlowStripStackingTests`／`RenderGeometryTests` 綠 |
| **U** | **使用者在場 #3**：`LyricsFlowUITests` 綠；回歸集合對基線不新增紅燈；三態截圖（裁切到視窗、無憑證欄位） | AC1–AC5、AC10、AC11、AC14 |
| **Q6** | 收官：Phase 3 `/simcodex`；全量測試；證據包；使用者實機試用（含 `riseDelay` 手感、AC13 中途退出手動驗） | 使用者目視確認 |

### 8.2 SEQ（僅當 U4＝「要」；否則另立計劃）
SEQ-S（使用者在場）：清單讀取成本（`count` 超過 2000 首跳過 library 級量測）、批次取值是否單一 AE（`AEDebugSends`；`array(byApplying:)` vs `value(forKey:)` vs 逐首）、窗口讀法（`index` 範圍／OR 串 persistentID）、**被動命中率**（記下預測的下一首、不動播放、等自然換歌比對；按播放來源分：自訂清單／Library 歌曲頁／專輯頁／串流／Up Next 插隊）、逾時後遺症；→ 通過門檻才做 SEQ-Q：`ListeningContextReader` actor（單槽、最新者勝、總 deadline、shuffle 併入同一 `run`）、`DeckSnapshot` 循序分支（卡 ID＝`persistentID#位置`、全路徑改用卡 ID）、AC 公平性測試（快速切歌、與封面預取併發）。

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
| `history_order_label` | Newest on the right | 最新的在最右邊 | 新しい曲ほど右 |
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
- **新**：`Features/LyricsFlow/{LyricsStatus,ListeningHistory,DeckSnapshot,LyricsFlowModel}.swift`、`App/UITestSupport/{LyricsFlowUITestMusic,UITestStubHTTPClient}.swift`、`Tests/Features/LyricsFlow*Tests.swift`、`Tests/Services/MusicSelectorAllowListTests.swift`、`Tests/Support/GatedPollClock.swift`、`UITests/LyricsFlowUITests.swift`、`Scripts/no_playback_gate.sh`、`Scripts/spike/queue_spike.swift`。
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

**整體回退**：全部改動在 `wip/coverflow-lyrics`；放棄＝切回原分支。

### 10.3 已知限制（接受，不修）
- **L1** 歷史卡徽章＝觀察當下的狀態＋本 app Editor 的寫入／標記；Batch 寫入不即時反映到歷史卡。
- **L2** 串流（非本機曲庫）曲目的封面／寫入沿用既有限制。
- **L3** 從 Batch 切回 Editor 時，若期間換到缺詞曲，不補自動抓詞（B-05 既有語義 py:481）；使用者可按 Fetch。
- **L4** 降下時 strip 仍會為可見卡取封面（R2）。
- **L5** 換歌時 Editor 內未存的文字被覆蓋（既有行為）。
- **L6** 執行中撤權後再授權、歌沒換：monitor 不重發事件，Editor 顯示 ACCESS DENIED 直到換歌或點 Now Editing 卡片（既有行為）。

## 11. Unknowns 賬本（slipknot 29）

| # | 未知 | 狀態 | 消解 | 影響 |
|---|---|---|---|---|
| U1 | 釘住 specifier 讀當前曲的延遲與 AE 數 | 已知的未知 | S1 | `nowPlaying()` timeout |
| U3 | `findTrack` 能否以釘住物件的 persistentID 找到同一首 | 已知的未知 | S1 | 寫入／封面路徑 |
| U4 | 循序模式是否顯示接下來的歌（原型 03） | **待使用者裁決**；評審四方一致建議「v1 不做，另立計劃」（理由：成本與風險集中在此、預測下一首可能錯而違反「只顯示事實」、Up Next 插隊無 API） | 使用者在場 #1 | §8.2 SEQ 做不做 |
| U5 | 歷史追加後居中的可靠做法 | 已知的未知 | S5 | D6 |
| U6 | `riseDelay` ≈ 3.2s 的手感 | 未知 | Q6 試用 | 常數 |
| U7 | 本分支上 H-02 閘門 `CoverFlowUITests` 的處置 | **待使用者裁決**；建議：本分支正式退役（資料模型已由整張專輯變為歷史，20 首 fixture 與探針前提不成立），ACCEPTANCE H-02 改附替代證據：`CoverFlowStripStackingTests`（缺陷 2，CALayer 無 AX）、S5 轉成的追加居中測試、D2 結構消除缺陷 3 的觸發條件、`LyricsFlowUITests` 升降；檔案保留（Python 閘門測試讀它）但移出回歸集合；fix4 在 `wip/h02-fix4` 另行延續與否由使用者定 | 使用者在場 #1 | Q5 回歸集合、H-02 條目 |

**Premortem**：① 歷史追加居中停錯卡（→ S5／R1）；② 掛載結構改動打壞外殼（→ R3、回歸集合）；③ 讀取競態讓 Editor 在有詞曲上出現並被使用者覆寫（→ D9／AC12）；④ 同曲重發把使用者踢出 Editor（→ AC6）。

## 12. 流程偏離聲明
- XCUITest 需使用者在場，排為三次「使用者在場」節點（§8.1）；其餘可無人值守。
- S 的前置（授權預檢）失敗即停、不彈框，改到使用者在場 #1 補。
- Phase 1 第 1 輪評審時 Codex 週額度用盡，先以 Opus 5 三視角評審，額度恢復後補跑 Codex（§14）。

## 13. 實測記錄（實施中回填）

（待 S 開始）

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
