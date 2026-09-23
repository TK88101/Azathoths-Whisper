# Cover Flow × 找歌詞 —— 計劃草案（待下個 session `/fatboyslim` Phase 1 定稿）

設計稿（互動原型）：https://claude.ai/artifact/GZSFdZEvyoshP48owh7c5G
（01 有歌詞＝Cover Flow／02 缺歌詞＝Editor／03 循序播放；原型下方的虛線列只用來模擬 iTunes 換歌）

## 0. 需求（2026-09-23，以默會知識提取取得；使用者原話見 memory `lyrics-workflow-coverflow-role`、`lyrics-tool-not-a-player`）
- **產品定位**：找歌詞的工具，**不是播放器**。不做播放／暫停／切歌；任何操作不得改變 Music.app 的播放狀態。
- **主流程**：看當前播放的歌有沒有歌詞 → 有就讓它播 → 沒有就把詞找到並寫入 → 接著看下一首。
- **畫面狀態機**（取代原「Cover Flow 分頁」）：
  | 狀態 | 畫面 |
  |---|---|
  | 當前曲有詞，或已標記「沒有詞」 | Cover Flow（只看，跟著 iTunes） |
  | 當前曲缺詞 | Cover Flow 降下（底部留一條把手），露出 Editor |
  | 點正中那張（正在播的）封面 | 降下露出 Editor，用來改現有的詞；**其他卡不能點** |
  | 寫入成功 | 彩帶撒完後 Cover Flow 自動升回 |
  | 按「No lyrics for this song」 | 記為已處理（純音樂／找不到），升回，下次播不再跳 Editor |
- **卡片內容**：每張卡標 ✓ 有詞／✗ 缺詞／— 已標記無詞。
  - 隨機播放：正在播的那張**永遠在最右端**，新歌進來才把它推到左邊（只有歷史，沒有未知佔位卡）。
  - 循序播放：左側歷史＋右側接下來的歌（**推測，待使用者看原型確認**）。

## 1. 已核事實（本 session 實查）
| 事實 | 出處 |
|---|---|
| Music.app 腳本字典有 `current playlist`（唯讀）、`shuffle enabled`、`played date` 等；**沒有**待播清單與播放歷史 | `sdef /System/Applications/Music.app` |
| MusicKit `SystemMusicPlayer` 在 macOS 不可用 | SDK `MusicKit.swiftinterface` |
| 可依 persistentID 讀／寫任意一首的歌詞；可依 album＋artist 逐首讀出歌詞狀態 | `AzathothsWhisper/Scripts/spike/FINDINGS.md` |
| 現行 Cover Flow 是獨立分頁、內容＝當前曲整張專輯、「純展示無播控（決策 6）」 | `CoverFlowView.swift`、`AppTab.swift` |
| 疊放修復已完成（依畫面位置疊放） | commit `469a02c`／`5944293` |

**推論**：新設計只讀不控 Music.app（讀當前曲、當前清單、shuffle 狀態、各曲歌詞），不需要任何播放指令 → spike 不會干擾使用者聽歌。

## 2. 任務清單（草案，每項帶 DoD）
| # | 任務 | DoD |
|---|---|---|
| S | Spike（唯讀，不需使用者在場）：S1 讀 `current playlist` 曲數／順序／persistentID 與耗時（含 1000+ 曲清單）；S2 逐首讀歌詞狀態的耗時（歷史 N 首、循序待播 N 首）；S3 `shuffle enabled` 能否可靠讀出；S4 「已標記無詞」存哪裡（app 設定檔 vs 其他），不寫進音樂檔 | 每項有實測數字，寫入本計劃 §13 |
| Q1 | `LyricsQueueModel` 純邏輯（TDD）：歷史紀錄（本 app 觀察到的換曲；去重／上限／持久化）、循序待播、狀態機（flow／editor 切換規則、寫入後升回、標記無詞） | 單測先紅後綠，行覆蓋 ≥ 80% |
| Q2 | Music 服務擴充（**只讀**）：當前清單曲目、shuffle 狀態、批次歌詞狀態 | fake 服務整合測試；程式碼中不得出現 play／pause／next／previous 指令（grep＝0） |
| Q3 | UI：Editor 頁內的 Cover Flow 層（升降動畫、底部把手、中心卡可點、狀態徽章、彩帶後升回），沿用 `CoverFlowStrip` | 單測＋`CoverFlowStripStackingTests` 仍綠；XCUITest：缺詞→Editor、寫入→升回、標記無詞→升回、點中心卡→Editor |
| Q4 | 移除 Cover Flow 分頁（`AppTab.coverFlow`）與三語字串；新增字串三語齊；ACCEPTANCE H 段改寫 | i18n 三語齊；全量測試不新增紅燈 |
| Q5 | 收官：證據包、實施後評審、使用者實機試用 | 使用者目視確認 |

## 3. 風險
- 大清單效能：ScriptingBridge 逐曲讀歌詞／封面慢 → 只讀可見範圍＋預取窗口；數字由 S1／S2 決定。
- 「切回分頁停錯卡」舊 bug（初始值路徑；EDGE 6＋RENDERED 2 紅燈）：Cover Flow 層若以升降（位移）而非重建實作，可能不經初始值路徑。**推測**，Q3 實測。
- 隨機時「當前永遠最右」＝每次換歌都往資料尾端追加一張、捲到最新那張 → 走運行時路徑（已修好疊放）。

## 4. 不做
- 任何播放控制（播放／暫停／切歌）。
- 讀取 Music.app 的待播清單（無 API）；隨機時不顯示未知的「下一首」。
