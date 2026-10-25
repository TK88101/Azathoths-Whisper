# 去掉啟動過場動畫（計劃 v0.1 草稿）

狀態：**v1.0 定稿**（使用者 2026-10-25「a吧 去開場動畫的這個 你能先build一版嗎」；Codex 3 輪收斂，見附錄 A、A2）。另：本分支一併 commit 2026-10-20 已換進工作樹的滿版圖示 `Resources/AppIcon.icns`（使用者 2026-10-25「順道把 icon也升級更換了」）。分支預定 `wip/remove-splash`（自 main 57453ba）。

## 0. 複述
使用者 2026-10-25：「把 Mac 這個 app 開軟件的過場動畫去掉，不再要了，完全沒有任何用處。」
＝啟動後**直接**顯示主 UI（Editor 外殼），不再先出 3.5 秒的黑底六角形 logo＋「Initializing Core Logic」畫面。

## 1. 使用者決定（既定前提）
- 拿掉 splash（2026-10-25）。這是對 1.2.4 原版（splash.py、py:1896）的**刻意偏離**，記進 ACCEPTANCE A-01／A-02 的 ⚠️（簽字日 2026-10-25，理由＝使用者「完全沒有任何用處」）。

## 2. 事實（已核，2026-10-25 讀碼）
- 畫面：`Features/Splash/SplashView.swift`（88 行；`SplashView`＋`HexagonLogo`）。顯示由 `RootView`（`Features/Shell/RootView.swift:16-22, 43, 141`）依 `AppModel.isSplashVisible` 控制：splash 期間外殼 opacity 0、不可點、不在 AX 樹上；`.animation(.easeInOut(0.2))` 淡出；Editor 頁 `isActive: model.tab == .editor && !model.isSplashVisible`。
- 時長：`AppModel.start()`（`App/AppModel.swift:358-379`）在啟動輪詢、事件迴圈之後 `Task.sleep(splashDuration)`（預設 3.5 s，`py:1896`），再設 `isSplashVisible = false`，**接著才** `startArtistStyles()`。
- ⑥b 依賴：「閃屏結束才開始」MB 背景同步是 ⑥b simcodex R1 的效率修正（⑥b 計劃附錄 F）——整庫掃描與逐歌手讀歌詞佔 AE 序列佇列，不跟啟動時第一輪播放讀取搶。`NowPlayingMonitor.start()` 不等第一個 tick（`Services/Music/NowPlayingMonitor.swift:106-119`），所以若連等待一起拿掉，背景同步會與第一輪讀取同時進 AE 佇列。
- 測試引用：`splashDuration:` 參數出現在 6 個單元測試檔（皆傳 1 ms）；UITests：`ShellUITests.testSplashIsShownBeforeMainUI`（A-01／A-02）、`testLaunchShowsEditorShellAfterSplash`（名稱被 ACCEPTANCE B-17、B-23、H-21 引用）、`AppUITestCase.waitForMainUI` 的註解與失敗訊息。
- 文案：splash 兩段字都是 `Text(verbatim:)`，`Localizable.xcstrings` 沒有 splash 的鍵（grep 無命中）→ 不動 String Catalog。
- `HexagonLogo` 另有引用：`Features/About/AboutModalView.swift:66`（`BundleAssets.aboutLogo` 為 nil 時的備用 logo）→ 不能隨 `SplashView` 一起刪（2026-10-25 grep）。
- 三語 README 沒有提到 splash（2026-10-25 grep：splash／過場／啟動畫面／スプラッシュ／起動画面皆無命中）。
- 單元測試沒有任何一條斷言 `isSplashVisible`，也沒有斷言「等待結束前不啟動 MB 同步」（`LyricsFXArtistGenreTests.swift:84` 是直接呼叫 `startArtistStyles()`）。

## 3. 目標與非目標
目標：啟動即顯示主 UI；同一視窗；MB 背景同步仍在啟動 3.5 s 後才開始（行為不變）。

非目標：改主 UI 的出現方式（不加替代的淡入）；改 iPad（YSE）的啟動畫面；改 Python 1.x；改 MB 同步的排程策略本身。

## 4. 設計
1. `HexagonLogo` 原樣搬到 `UI/Components/HexagonLogo.swift`（共用圖形元件放 UI 層；內容不改；R1-8），再刪 `Features/Splash/SplashView.swift`（整個 `Splash` 目錄）。只在 `AzathothsWhisper/` 下跑 `xcodegen generate`；`Features`／`UI` 在 `project.yml` 是目錄遞迴 source，主 `.xcodeproj` 的變動只會是檔案清單。DoD：`git diff --stat` 只含主 `AzathothsWhisper.xcodeproj` 與本計劃列出的原始檔；未追蹤的 `AzathothsWhisper 2/3/4.xcodeproj` 不加入、不刪（R1-6）。
2. `AppModel`：刪 `isSplashVisible`；`splashDuration: Duration` 改為 `artistStylesStartDelay: Duration`（預設仍 3.5 s）＋新注入 `artistStylesClock: any PollClock = SystemPollClock()`（同既有 `batchSwitchClock` 模式）。`start()` 改成 `try? await artistStylesClock.sleep(for: artistStylesStartDelay)` 後呼叫 `startArtistStyles()`。註解寫明：這是暫時節流，不保證第一輪讀取已完成（R1-2、R1-3）。
   - 理由：只改名＋可注入、不改值＝⑥b 的效率修正原樣保留，而且測試可以精確放行。
   - 改成「monitor 第一次讀取完成才開始」屬排程策略變更，列為遺留（附錄 A R1-3），不在本次範圍。
3. `RootView`：拿掉外殼的 opacity／allowsHitTesting／accessibilityHidden 三個修飾、`SplashView` 分支、`.animation(..., value: isSplashVisible)`；`isActive: model.tab == .editor`。檔頭註解「開場畫面是覆蓋層」一句刪去，其餘掛載結構不變。
4. 單元測試：所有 `splashDuration:` 呼叫點改 `artistStylesStartDelay:`（機械改名，斷言不動）。DoD：`rg 'splashDuration' -g '*.swift' AzathothsWhisper` 零命中＋編譯成功（R1-9；文件中的歷史記錄不受限，R2）。
5. UITests：
   - **兩個 UI 測試都不改名**（R2）：`Scripts/h02_gate_profile_gen.py:94-113` 的 `UI_EXPECTED_TESTS` 是 H-02 閘門的凍結契約（與歷史 `ui-T0.log` 逐條同名），改名要重簽基線，超出本計劃範圍。方法上方註解寫明「名稱受 H-02 凍結契約約束，語義已改為 A-01 新版（2026-10-25）」。ACCEPTANCE B-17、B-23、H-21 的引用因此不必改。
   - `testSplashIsShownBeforeMainUI` 的內容改寫（R1-1、R1-7、R2）：
     - **主證據是結構**，不是這條 UI 測試：`SplashView`、`isSplashVisible` 已從程式碼刪除（S4 的識別字檢查＋編譯成功），splash 不可能出現。
     - UI 測試只驗「app 可被觀察之後」：launch 返回後每 0.1 s 輪詢到 Editor 導覽出現（上限 `mainUITimeout`），期間 `INITIALIZING CORE LOGIC` 不得出現。這**不能**證明啟動最初幾秒沒有 splash：新建置首次啟動時 AX 就緒要 18.9 s（`AppUITestCase` 類註解），舊版 3.5 s 的 splash 可能在 launch 返回前就結束了。所以不宣稱它能證偽「從未出現」。
     - 主 UI 出現後立即點 Batch 導覽、再點回 Editor，各自的標誌元素都出現（「提早可操作」的冒煙）。
     - `windows.count == 1` 保留，作為視窗回歸檢查，不當 A-02 的主要證據（R1-4）。
   - `testLaunchShowsEditorShellAfterSplash`：名稱不動、斷言不動（只改註解）。
   - `waitForMainUI` 的註解與失敗訊息去掉「splash 後」。
6. ACCEPTANCE（R1-10）：A-01、A-02 的原文保留、以刪除線標「已由 2026-10-25 決策取代（M5 時驗的是 splash）」。新文字：
   - A-01 ⚠️「啟動後第一個畫面就是可操作的 Editor 外殼，無 splash（偏離 splash.py；使用者 2026-10-25 批准，理由：無用）」；
   - A-02 ⚠️「單一視窗（原：splash 3.5 s 後同窗切換）」。
   - 兩條的驗證方式寫：結構（`SplashView`／`isSplashVisible` 不存在）＋`ShellUITests.testSplashIsShownBeforeMainUI`（名稱受 H-02 凍結契約約束，內容已改為驗無 splash＋立即可操作）。

## 5. 任務清單（每項先紅後綠）
| # | 任務 | DoD |
|---|---|---|
| S1 | UITest 先改（`testSplashIsShownBeforeMainUI` 的內容） | 使用者在場，在**暖啟動**（第二次以後，AX 就緒約 0.5 s ＜ 3.5 s）跑出紅燈並記錄；若 launch 返回前 splash 已結束、跑不出紅，如實記錄「S1 無法紅」，以 S4 的結構檢查為主證據 |
| S2 | 單元測試先寫：`artistStylesClock` 為 `GatedPollClock`；`start()` 後先 `await clock.waitUntilPending(1)`，斷言 `requested == [.milliseconds(3500)]`（或注入的時長）且 MB 工廠呼叫 0 次；`releaseNext()` 後等待工廠計數到 1，斷言恰 1 次（R2） | 紅（`artistStylesClock` 參數未定義，編譯失敗）並記錄 |
| S3 | 搬 `HexagonLogo`、刪 SplashView、改 AppModel／RootView、單元測試改名、`xcodegen generate` | S2 綠；全量單元綠，但已知 flaky `overlappingLoadSuspendsPollingUntilLastCompletes()` 以完整名稱＋括號 skip，回報時列出這一條、不寫「全量綠」（R1-5）；§4-1 的 diff DoD |
| S4 | ACCEPTANCE A-01／A-02（保留原文＋⚠️）（B-17／B-23／H-21 的測試名不變，不改） | 生產碼與測試碼中 `SplashView`、`isSplashVisible`、`splashDuration`、`INITIALIZING CORE LOGIC` 零引用（除 S1 的反向斷言字串）（R1-11） |
| S5 | 使用者在場：`ShellUITests` 全組 | 全綠（S1 的紅轉綠） |

## 6. 測試策略
- 單元：S2 新測試；既有 `AppModel*Tests`／`LyricsFXArtistGenreTests` 經改名後照跑。
- E2E：S1／S5（XCUITest，需使用者在場授權 Automation Mode 與輔助使用；跑前先 `open -n` 讓鑰匙圈框點完、切 ABC 輸入法）。
- `no_playback_gate.sh`、coverage_gate 照跑確認。

## 7. 驗收
- 冷啟動不再有 3.5 s 的黑屏 logo，第一個畫面就是可操作的 Editor 外殼；`ShellUITests` 全綠。
- MB 背景同步仍在啟動 3.5 s 後才開始（S2 以可控時鐘證明順序；實機以日誌時間戳看一次）。
- 全量單元綠（除列明的已知 flaky 一條）、coverage_gate 綠。

## 8. 風險與回退
- 主 UI 立即可見：第一次 Music 讀取完成前，Editor 顯示空狀態最多一個輪詢（≤ 3 s；F1 換歌通知通常更早）。推測可接受——這段時間原本被 splash 蓋住，內容相同。
- 回退：單一 commit，`git revert` 即可。

## 9. 待拍板
（無；使用者已裁定拿掉。）

## 附錄 A Codex R1（2026-10-25）處置
| # | 嚴重度 | 意見 | 處置 |
|---|---|---|---|
| R1-1 | 高 | 「主 UI 出現後 splash 不存在」無法證明 splash 從未出現 | **採納（修改）**：從 launch 起每 0.1 s 輪詢到主 UI 出現，期間 splash 文字不得出現。不採「N 秒內出現」：首次啟動 AX 就緒 18.9 s，會誤報 |
| R1-2 | 高 | 硬編碼 `Task.sleep` 測不了「延遲前不啟動、延遲後恰一次」 | **採納**：注入 `artistStylesClock: any PollClock`，測試用 `GatedPollClock`（S2） |
| R1-3 | 中 | 3.5 s 是 splash 的殘留魔術數字；較健全是「首次讀取完成」才啟動 | **部分採納**：改名 `artistStylesStartDelay` 並註明暫時節流；事件驅動屬排程策略變更，非目標（§3），列遺留 |
| R1-4 | 中 | `windows.count == 1` 不是新需求的核心證據 | **採納**：保留為回歸檢查；A-02 主證據改為「第一個畫面就是可操作的 Editor 外殼」 |
| R1-5 | 中 | skip flaky 後不能稱「全量綠」 | **部分採納**：措辭改為「除列明的一條外全綠」並列出完整名稱。不在本計劃修該 flaky：它已另案追蹤（memory），與本改動無關 |
| R1-6 | 中 | xcodegen 後未定義如何確認只動主 `.xcodeproj` | **採納**：§4-1 加 diff DoD |
| R1-7 | 中 | 主 UI 提早可操作，沒驗立即互動 | **採納**：新用例加 Batch↔Editor 立即切換。Settings 開啟已有 `testSettingsMenuOpens*` 覆蓋 |
| R1-8 | 低 | `HexagonLogo` 放 `Features/About` 所有權含混 | **採納**：改放 `UI/Components/` |
| R1-9 | 低 | 「6 檔」會過期，改用全庫搜尋為 DoD | **採納** |
| R1-10 | 低 | 直接覆寫 A-01/A-02 會失去歷史 | **採納**：保留原文＋刪除線＋取代說明 |
| R1-11 | 低 | 「零 splash 命中」太寬 | **採納**：改驗具體識別字 |
| R1-12 | 低 | 不必綁 Python 行號 | **駁回**：專案 CLAUDE.md 規定偏離原版要記進 ACCEPTANCE、依據欄用 py 行號；計劃只在 ACCEPTANCE 引用，不限制實作 |

## 附錄 A2 Codex R2（2026-10-25）處置
| # | 意見 | 處置 |
|---|---|---|
| R1-3、R1-5、R1-12 | 認可部分採納／駁回 | 結案 |
| R1-1 | launch 返回前 splash 可能已結束（首次 AX 18.9 s），UI 輪詢不能證偽「從未出現」 | **採納**：主證據改為結構檢查；UI 測試只宣稱「可觀察後無 splash＋立即可操作」；S1 改在暖啟動取紅，取不到如實記錄 |
| R1-2 | S2 沒等 clock 掛起就斷言，會假綠或空放 | **採納**：先 `waitUntilPending(1)`、驗 `requested`，放行後等工廠計數 |
| R1-9 | 「全庫零命中」會被計劃自己的歷史說明違反 | **採納**：範圍限 `*.swift` |
| 新 | 改名會讓 `h02_gate_profile_gen.py` 的 `UI_EXPECTED_TESTS`（凍結契約）失配 | **修改採納**：兩個測試都不改名，只改內容與註解；不動 H-02 凍結契約 |

## 附錄 B 實作記錄（2026-10-25，分支 `wip/remove-splash`）
- **S2**：紅＝`extra argument 'artistStylesClock' in call`（編譯失敗）→ 實作後綠（`AppModelArtistStylesTests` 2 條＋`AppInfoTests` 5 條）。
- **S1 紅燈步驟未在改碼前跑**：UI 測試需要使用者在場，本次先改碼、先 build 給使用者試用。如實記錄；依 §4-5，本用例本來就不是主證據，主證據是結構檢查。
- **S3**：`HexagonLogo` 搬到 `UI/Components/HexagonLogo.swift`（內容不改）；`git rm Features/Splash/SplashView.swift`；`AppModel` 的 `splashDuration` 改為 `artistStylesStartDelay`＋`artistStylesClock`；`RootView` 拿掉覆蓋層；6 個測試檔機械改名。`xcodegen generate` 後只有主 `AzathothsWhisper.xcodeproj/project.pbxproj` 變動，沒有新的「 N.xcodeproj」副本。
- **S4**：`rg 'splashDuration|isSplashVisible|SplashView' -g '*.swift'` 零命中；`INITIALIZING CORE LOGIC` 只剩 UI 測試的反向斷言。ACCEPTANCE A-01／A-02 改為修正⚠️，保留原文刪除線。
- **圖示**：一併納入 2026-10-20 已換進工作樹的滿版 `Resources/AppIcon.icns`（邊緣像素：舊版 (0,0,0) 純黑框、新版 (40,36,27) 鐵牌暗褐）。
- **試用版**：Release 建置（derivedData 在 `mktemp -d`）→ `/Users/Shared/AzathothsWhisper-nosplash/Azathoth's Whisper.app`，2.0.2（2000003，未升版號，僅試用），ad-hoc 簽名；執行檔中 `Initializing Core Logic` 0 筆，圖示與 `Resources/AppIcon.icns` 逐位元相同。
- **使用者在場試用（2026-10-25）**：開啟試用版「沒有過場了，圖示也對」——A-01 新版行為與滿版圖示目視通過。`ShellUITests`（S5）仍待使用者在場跑。

## 附錄 C simcodex（2026-10-25，第 1 輪即提前結束）
| 來源 | 意見 | 處置 |
|---|---|---|
| codex review --uncommitted | 無 finding | — |
| simplify 4 角度（重用／簡化／效率／層級，Sonnet） | 0 個 P0／P1；P2 共 11 條 | 見下 |
| 4 角度共同 P2 | UI 測試的 0.1 s 輪詢迴圈與 `waitForMainUI()` 重複、最多約 400 次 AX 快照、斷言重複報 | **採納**：改為 `waitForMainUI()` 後檢查一次（§4-5 的輪詢描述作廢；主證據本來就是結構檢查，Codex R2 已認可） |
| 簡化 P2 | `AppModel` 的節流理由在屬性與 `start()` 各寫一次 | **採納**：刪 `start()` 那句 |
| 層級 P2 | 改用 `artistStylesClock.schedule(after:)`＋`stop()` 取消：`start()` 不再掛 3.5 s，`stop()` 後也不會再啟動 MB 同步 | **延後**：`stop()` 後仍會啟動是改前就有的行為（`try? Task.sleep`），非本次引入；改排程語意另案 |
| 簡化 P2 | 兩個旋鈕（延遲＋時鐘）可收成一個：延遲改 `static let`、其他測試注入 `ImmediateClock` | **延後**：要再改 5 個測試檔；不影響行為 |
| 層級 P2 | 5 個測試檔的 `artistStylesStartDelay: .milliseconds(1)` 是死參數 | **駁回**：不是死參數——拿掉後 `await model.start()` 會真的等預設 3.5 s，測試變慢 |
| 簡化 P2 | `HexagonLogo` 可能是死碼（`AboutLogo.png` 已打包，備用分支不會跑） | **延後**：刪備用 logo 超出本計劃範圍（§4-1 決定保留） |
| 重用／簡化 P2 | 新測試複製了上一條的 `AppModel(...)` 組裝；`FactoryCalls` 又一個計數盒 | **延後** |
| 簡化 P2 | 註解寫了日期與歷史 | **駁回**：專案慣例就是在註解記日期與 ACCEPTANCE 編號（例：`LyricsFXCatalog` 的 crimsonVelvet 註解） |
| 簡化 P2 | Batch↔Editor 切換與其他 UI 測試重複 | **駁回**：計劃 R1-7（Codex 建議）要求在這條用例驗「主 UI 一出現就能操作」 |
- 驗證：`build-for-testing` 成功（含 UITests）；`AppModel*` 6 個 suite 61 條綠。修正前的全量單元：1,683 條綠（已知 flaky 一條 skip）；coverage 96.2 %；`no_playback_gate.sh` exit 0。
