# Cover Flow 播放佇列抽屜 —— 計劃草案（待下個 session `/fatboyslim` Phase 1 定稿）

設計稿：https://claude.ai/artifact/GZSFdZEvyoshP48owh7c5G（三個畫板：收合的正在播放條／循序展開／隨機展開；皆可點）

## 0. 需求複述（使用者 2026-09-23）
- Cover Flow 不再是獨立分頁：移到 Editor 頁底部，常駐一條「正在播放」；點擊後抽屜從下方升起。
- 內容由「當前曲所在的整張專輯」改為**播放佇列**：左＝已播歷史，中＝正在播放，右＝待播。點任一張＝讓 Music.app 播那首。
- 目的：直接跳到前後某首，不必逐首切換；隨機播放時相鄰封面可能來自不同專輯。
- 前提：2026-09-23 已修好的疊放修復（`CoverFlowStrip`，commit `469a02c`／`5944293`）照用。

## 1. 已核事實（本 session 實查）
| 事實 | 出處 |
|---|---|
| Music.app 腳本字典有：`current playlist`（唯讀）、`shuffle enabled`、`shuffle mode`、`next track`、`previous track`、`back track`、`play`（可指定曲目）、每曲 `played date`／`played count` | `sdef /System/Applications/Music.app` |
| **沒有**「待播清單（Up Next）」，**沒有**播放歷史 | 同上（全文無 queue／history／up next） |
| MusicKit `SystemMusicPlayer` 標為 `@available(macOS, unavailable)`；`ApplicationMusicPlayer` 只控制 app 自己的播放器 | SDK `MusicKit.swiftinterface` |
| 本 app 已用 ScriptingBridge 手寫 protocol 控制 Music（persistentID 過濾、artwork rawData 三連陷阱） | `AzathothsWhisper/Scripts/spike/FINDINGS.md` |
| 現行 Cover Flow 定位＝「純展示、無播控動詞（決策 6）」；本需求推翻它 | `CoverFlowView.swift:3` |

**推論（推測）**：隨機播放時 Music.app 的真實待播順序不可讀；循序播放時，待播＝`current playlist` 中當前曲之後的曲目（使用者手動「插播」的曲目看不到）。

## 2. 方案（TypeSafe 判斷：分階段 0.50／只做階段 1 0.47／本 app 直接接管 0.03；「必須先告知使用者此限制」0.83）
- **階段 1（預設）**：
  - 歷史＝本 app 觀察到的每次換曲（持久化，設上限）。
  - 循序時右側＝真實待播。
  - 隨機時右側＝一張「下一首由 Music.app 決定」的佔位卡，點它等於「下一首」；播出後即入列。
- **階段 2（可選開關「App shuffle」；待使用者在階段 1 完成後拍板）**：由本 app 產生隨機順序、關閉 Music.app 的 shuffle，並在換曲時指定播放下一首 → 待播封面全部可見。前置 spike：換曲時序是否會閃播錯曲、使用者在 Music.app 內自行切歌時的衝突。

## 3. 任務清單（草案，每項帶 DoD）
| # | 任務 | DoD |
|---|---|---|
| S | Spike（**會實際控制使用者的 Music.app 播放，須使用者在場同意**）：S1 讀 `current playlist` 的曲數／順序／persistentID 與耗時（含 1000+ 曲清單）；S2 `play` 清單內某曲後循序接續是否正確；S3 播放不在當前清單的歷史曲後 context 如何變；S4 `shuffle enabled` 讀寫與切換後的順序 | 每項有實測數字，寫入本計劃 §13 |
| Q1 | `QueueModel` 純邏輯（TDD）：歷史去重／上限／持久化、待播計算（循序／repeat／隨機未知）、點卡→播放指令 | 單測先紅後綠，行覆蓋 ≥ 80% |
| Q2 | Music 服務擴充：讀當前清單曲目、`play(track)`、上一首／下一首、shuffle 狀態 | 以 fake 服務的整合測試；不在測試中真的播放 |
| Q3 | UI：`NowPlayingDock`（Editor 底部）＋`QueueDrawer`（升起動畫、遮罩、Esc 與點遮罩關閉、卡片由中央依序展開）＋沿用 `CoverFlowStrip` | 單測＋`CoverFlowStripStackingTests` 仍綠；XCUITest：開抽屜、點卡→fake 服務收到正確播放指令 |
| Q4 | 移除 Cover Flow 分頁（`AppTab.coverFlow`）與三語字串；ACCEPTANCE H 段依「決策 6 已推翻」改寫 | 三語 i18n 齊；全量測試不新增紅燈 |
| Q5 | 收官：證據包、`/simcodex`（或額度不足時的替代評審）、使用者實機試用 | 使用者目視確認 |

## 4. 風險
- 真實播放是外部副作用：自動化測試一律用 fake Music 服務，不操控使用者正在聽的音樂。
- 大清單效能：ScriptingBridge 逐曲讀封面很慢 → 只讀可見範圍，沿用既有預取窗口。
- Apple Events（TCC）授權：重建後新 CDHash 可能重彈授權框。
- 另一個已知 bug（切回分頁停錯卡、偏約 17pt；EDGE 6＋RENDERED 2 紅燈）：抽屜每次打開都會重建條帶，走的正是這條「初始值路徑」，**階段 1 很可能必須一併處理**（推測，待 Q3 實測）。

## 5. 不做
- 讀取 Music.app 的 Up Next（無 API）。
- 階段 2 在使用者拍板前不做。
