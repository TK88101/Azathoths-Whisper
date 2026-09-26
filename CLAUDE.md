# CLAUDE.md

本檔給 Claude Code（本機 CLI 與雲端 claude.ai/code 兩種）在這個 repo 工作時使用。
**請用中文和使用者溝通。** 本檔描述的是 **2.0（Swift／SwiftUI 全原生重寫）**。1.x 的 Python 版只剩行為參考的用途，見文末。

## 專案概況

代號 Bjork，產品名 **Azathoth's Whisper**（阿撒托斯的低語／アザトースの囁き）：macOS 原生 App。
它監聽 Music.app 當前播放的曲目，從 Genius（需要 token）與 DarkLyrics 抓歌詞，寫回音樂檔的 lyrics 欄位。
介面分三塊：**Editor**（單首編輯與寫入）、**Batch**（整張專輯補詞與匯入）、**Cover Flow × 找歌詞**（Editor 頁內的升降層，依 `Queue.dat`／`History.dat` 顯示播放佇列與缺詞徽章）。

- 只支援 macOS 14+，Swift 6（`SWIFT_VERSION: 6.0`，strict concurrency），不用第三方 UI 框架。唯一的套件依賴是 SwiftSoup（SPM）。
- 使用者本機的實測環境是 macOS 26.6、Xcode 26.6、Swift 6.3。

## 目錄結構（`AzathothsWhisper/`）

| 路徑 | 內容 |
|---|---|
| `project.yml` | **XcodeGen 的唯一真源**。`.xcodeproj` 由它產生，**產生後要一起 commit** |
| `App/` | `AzathothsWhisperApp`（Scene、選單）、`AppDelegate`（退出矩陣）、**`AppModel`（組裝根：服務建立、legacy 遷移、事件分發、各 ViewModel 之間的回呼接線）** |
| `App/UITestSupport/` | 只在 DEBUG 下存在的 UI 測試組裝與替身（`*UITestMusic`、`InertMusicClient`、H-02 閘門判定邏輯）。**整檔包在 `#if DEBUG` 內，不得進入 Release** |
| `Features/` | `Editor`、`Batch`、`CoverFlow`、`LyricsFlow`、`Settings`、`About`、`Splash`、`Shell`：每個 feature 都是 `@MainActor @Observable` 的 ViewModel 加 View |
| `Services/Music/` | `MusicControlling`（protocol）、`MusicAppleEventsClient`（ScriptingBridge，**唯一**可以 `import ScriptingBridge` 的檔案）、`NowPlayingMonitor`（3 秒輪詢，busy 時跳過）、`Queue`／`History` 的唯讀解析 |
| `Services/Lyrics/` | `LyricsService`（Editor 只走 Genius；Batch 會 fallback DarkLyrics）、各來源與解析器 |
| `Services/Config/` | `ConfigStore`（token 存 **Keychain**，其餘存 **UserDefaults**）、一次性 legacy 遷移（`.env`、`~/.azathoths_whisper_config`） |
| `Services/Artwork/` | 封面記憶體快取、磁碟快取（`~/Library/Caches/com.ibridgezhao.azathothswhisper/Artwork`）、失敗退避 |
| `Infra/` | HTTP、HTML 文字處理、`LineEndings`（Music 用 CR 分行，一定要正規化）、`PythonCompat` |
| `UI/` | `Theme`、共用元件、`StatusText`（寫死的英文運行時文案）、`AccessibilityID` |
| `Resources/Localizable.xcstrings` | 三語 String Catalog：`en`／`zh-Hant`／`ja` |
| `Tests/`、`UITests/` | XCTest 單元測試（Parsing／Services／Features／UI）、XCUITest |
| `Scripts/` | 閘門腳本與它們的 Python 測試：`coverage_gate.sh`、`no_playback_gate.sh`、`h02_gate_*`、`make_xcstrings.py` |
| `ACCEPTANCE.md` | **行為驗收總表**（A–H 段，每條有 ID、依據、驗證方式、狀態） |

repo 根目錄還有：`docs/plans/`（每個功能的實施計劃）、`packaging/`（DMG 版式模板）、三語 README，以及 1.x 的遺留檔（見文末）。

## 常用命令（在 `AzathothsWhisper/` 下執行，需要 Mac）

```bash
xcodegen generate            # 新增或刪除原始檔後必跑，否則 Xcode 會默默沿用舊的檔案清單；產物一起 commit

# 單元測試（每次都要帶超時，防止掛住）
xcodebuild test -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper \
  -destination 'platform=macOS' -only-testing:AzathothsWhisperTests \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120

# UI 測試：要求 Xcode 有「輔助使用」權限，而且要使用者在場授權（見「工作流程」）
#   -only-testing:AzathothsWhisperUITests

Scripts/coverage_gate.sh     # Services/ + Infra/ 的覆蓋率 ≥ 80%（豁免清單在腳本內，每筆要附理由與使用者批准日）
Scripts/no_playback_gate.sh  # 無播控閘門：禁止送播放控制、禁止寫 Queue.dat／History.dat
cd Scripts && python3 -m unittest discover -p 'test_*.py'   # 閘門腳本自己的測試
```

Release 建置與 DMG 的完整流程見 README「Build from Source」第 5、6 步（`-derivedDataPath` 放到 `mktemp -d`，不要放在 iCloud 同步的 `~/Documents` 裡）。

## 核心約束

### 行為保真與 ACCEPTANCE
- 2.0 是從 1.2.4 **1:1 移植**過來的。原版的可觀察行為（文案、按鈕禁用範圍、輪詢是否暫停……）預設照搬，程式碼註解用 `py:NNN` 指回 `lyrics_fetcher.py` 的行號。**不要**順手「修好」原版的怪行為。
- 要偏離原版，必須是**使用者已經批准**的修正，並記進 `ACCEPTANCE.md` 的 ⚠️ 條目（附理由與簽字日期）。改動影響到某條驗收項時，同步更新該條的「驗證方式／狀態」。
- 註解裡看到「刻意保留」「勿當死碼清理」「規格要求」的程式碼（例如 `BatchViewModel.ListState.failed`），**不要刪**。要刪必須先修訂並重新簽署對應的 ACCEPTANCE 條目。

### 架構慣例
- ViewModel 一律 `@MainActor @Observable`。跨 feature 的溝通**只透過回呼加上 `AppModel` 接線**（例如 `editor.onSaved`、`batch.onLyricsWritten`），feature 之間不互相持有。
- 外部邊界都有 protocol 加替身：`MusicControlling`、`HTTPClient`、`SecretStore`、`TokenValidating`、`PollClock`。新的系統邊界（例如通知中心）也照這個模式做，並提供給測試用的 Noop 或 Spy 版本。
- 競態防線：Editor 用**世代守衛**（`generation`，加上在 `await` 之前擷取目標），Batch 用 **`sessionID`**。「寫入已經發生」這類事實事件（`onLyricsWritten`）**要在 stale 守衛之前送出**。
- busy 區間一律用 `withBusy`／`withLoadingAlbum` 的作用域封裝，不要用 `defer` 加手動釋放。
- 會判斷的 View 邏輯要抽成純函式，並寫單元測試。

### 安全與隱私
- Music 相關：**只讀，外加寫 lyrics**。不送播放控制，不寫、不移動、不刪除 `Queue.dat`／`History.dat`。`no_playback_gate.sh` 和選擇器白名單測試會把關。
- **日誌要脫敏**：只記序號、ID、錯誤類型，**不記曲名、歌詞、token**。Keychain 與設定的程式路徑完全不寫 log。日誌用 OSLog，subsystem 是 `com.ibridgezhao.azathothswhisper`。
- token 是憑證：輸入框用 `SecureField`，UI 測試**不主動截圖含憑證欄位的畫面**。scheme 已關掉失敗自動截圖（`captureScreenshotsAutomatically: false`），需要截圖時裁切到視窗再附上。
- 單元測試 host 用 `AZW_UNIT_TEST_HOST=1` 跳過真實 Keychain 與 legacy 遷移（ad-hoc 重簽後 ACL 會失配，彈出授權框並卡住）。這個旗標**只存在於 DEBUG**，不要把它帶進 Release 路徑。
- 不要 commit `.env`、token 或任何憑證。

### i18n
- 新增的 UI 文案一定要在 `Localizable.xcstrings` 補齊 `en`／`zh-Hant`／`ja` 三語。
- **選單文案寫死英文，不隨語言變**（A-07）。Settings modal 的標題也是英文覆寫（D-03）。運行時狀態文案集中在 `UI/StatusText.swift`，也是英文（E-05），**不要**本地化。
- 語言覆寫寫在 per-app 的 `AppleLanguages`，**重啟後才生效**（E-09）。

### 版本與打包
- 版本號只改 `project.yml`：`MARKETING_VERSION`（例如 `2.0.1`）與 `CURRENT_PROJECT_VERSION`（**只增不減的整數**建置號，每次打包加 1，例如 `2000002`）。改完跑 `xcodegen generate`。`AppInfo.version` 的 fallback 字串也要同步。
- 簽名是 **ad-hoc**（`CODE_SIGN_IDENTITY: "-"`）。每次建置簽名都會變，所以 TCC（自動化權限）和 Keychain 可能重新詢問，這是預期行為。
- DMG 沿用 `packaging/dmg-layout.DS_Store`，這個檔案**按名稱**解析版式：卷名必須是 `Azathoth's Whisper`，卷內只能有 `Azathoth's Whisper.app`、`Applications` 連結、`dmg_background.png`（要 `chflags hidden`）。
- 排查問題用 `log show --predicate 'subsystem == "com.ibridgezhao.azathothswhisper"' --last 1h --info`。2.0 已經沒有 `app_debug.log`。

## 工作流程（使用者的慣例）

- **先寫計劃，再開工**：每個功能或 bug 都在 `docs/plans/YYYY-MM-DD-<slug>.md` 寫計劃。慣用章節：複述／目標與非目標／根因（已核事實與推理分開寫）／設計／測試／驗證項／待拍板。
  **計劃經使用者審閱、拍板之後才實作。** 使用者只要計劃時，寫完計劃就停手。
- **TDD**：先寫測試並跑出紅燈，再實作。紅燈摘要記進計劃。commit 訊息習慣附上測試狀態，例如「618 條僅基線 8 斷言紅」（已知的基線紅不算新增的紅）。
- **使用者在場**：XCUITest 需要使用者授權 Automation Mode 和輔助使用，真機驗證也要使用者操作 Music。這些步驟列成「使用者在場 #N」，**不要**假設可以無人值守跑完。
- **熔斷紀律**：同一個問題連續幾輪沒有進展，就停手，把事實和已被排除的假設記進計劃，改換方向或交給使用者決定，不要一直重試。已經熔斷的項目（例如 A-10 的 XCUITest 時序問題）不要重新開始調查。
- **偶發失敗不能當根因**：失敗的測試不能靠「重跑幾次會過」結案。任何測試都不准為了變綠而跳過、停用或放寬斷言。
- **評審**：重要的計劃與實作要經過 Codex（`/simcodex`）或多視角評審，逐條記錄處置（採納／駁回與理由）。
- **Git**：commit 訊息用中文，格式是 `type: 摘要——補充`（type 是 feat／fix／docs／test／refactor／chore／wip）。功能完成後用 `Merge: <功能> —— Azathoth's Whisper vX.Y.Z` 合進 `main`。不要改寫別人分支的歷史。

## 雲端（claude.ai/code）工作須知

- 雲端容器是 **Linux**，**沒有 Xcode 與 macOS SDK**，所以 Swift **無法建置、無法跑 XCTest／XCUITest**，也沒有 Music.app。
- 雲端**能**做的：讀寫程式碼、寫計劃與文件、跑 `Scripts/no_playback_gate.sh`、跑 `Scripts/` 的 Python 測試。
  其中 `test_coverage_gate` 的 9 條會因為容器沒有 `zsh` 而 error，這屬於環境限制，不是程式問題。
- 所以在雲端改 Swift 時：commit 訊息與回報都要**明確寫出「未在 Mac 上建置或測試」**，並列出使用者需要在本機跑的命令與驗證項。**不要**宣稱測試通過。
- 雲端**看不到**使用者本機的全域 `~/.claude/CLAUDE.md` 與 memory。需要兩邊都遵守的規則，要寫進本檔。

## 1.x 遺留（只當行為參考，不要修改）

repo 根目錄的 `lyrics_fetcher.py`（v1.2.4，約 2250 行，Python + pywebview + appscript）、`splash.py`、`Azathoths_Whisper.spec`、`run.sh`、`requirements.txt`、`setup_dmg.applescript` 和圖示生成腳本，都是 1.x 的產物。
它們現在的用途：①程式碼註解 `py:NNN` 與 ACCEPTANCE「依據」欄的行號真源；②`Scripts/make_fixtures.py`／`make_xcstrings.py` 會從這裡抽 golden fixture 與翻譯。
**新功能不要寫進 Python 版**（歷次計劃都把「Python 舊版不動」列為非目標）。
