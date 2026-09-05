# Azathoth's Whisper 2.0：Python → Swift/SwiftUI 全原生重寫＋Cover Flow 實施計劃

- 日期：2026-08-09（定稿 2026-08-10）
- 狀態：**定稿**（codex 兩輪對抗評審完畢：16 條意見 12 採納/2 修改採納/1 駁回/1 澄清，複審全接受無重提；辯論記錄見附錄 B）
- 批准記錄：用戶已於 2026-08-09 批准 Plan Mode 計劃（`~/.claude/plans/1-python-gleaming-boot.md`）；本檔為其正式落地版＋設計細節全文＋評審修訂。

## 1. 目標與非目標

**目標**
- 將 v1.2.4（Python + pywebview + appscript + PyInstaller）全量重寫為 Swift/SwiftUI 原生 macOS app（v2.0.0）。
- 行為驗收口徑：佈局、功能、文案、交互 **1:1 還原**；視覺盡可能貼近（用戶接受非像素級——SwiftUI 重畫必然存在渲染差異）。
- 新增 Cover Flow：當前專輯封面 3D 可瀏覽（經典 iPod 形態），中心＝當前播放曲目，**純展示不控播**。
- 消滅「Python-on-macOS 稅」：aeosa PYTHONPATH hack、brew python-tk 依賴、補 lproj＋ad-hoc 重簽鏈、NSApp delegate 包裝 hack、.env 寫入 .app 內部破壞簽名。

**非目標**
- 不做播放控制（雙擊播放已議決不加）。
- 不移植死代碼：Tkinter BatchProcessingWindow、DirectoryScanner（目錄掃描）、mutagen 直寫文件、樁方法（batch_fetch / open_batch_directory）、ConfigManager.save_config。
- 不新增歌詞源（Metal Archives / Musixmatch 在現版代碼中本就不存在，README 宣稱有誤）。
- 不做 App Store / 正式 Apple 簽名（維持 ad-hoc + xattr 分發）。
- 驗收通過前不動 Python 舊版任何文件（絞殺者式並存）。

## 2. 已拍板決策（用戶既裁定，評審不重議）

1. **SwiftUI 全原生重寫**（否決 WKWebView 沿用 HTML 方案）。
2. **Cover Flow＝當前專輯可瀏覽**（中心正面、兩側斜角覆疊、倒影、吸附）。
3. **移植＋Cover Flow 一輪做完**。
4. **死代碼不移植；純數據錯修正**：en 語言包補 `batch_fetch`/`batch_import`/`batch_all` 三鍵、`en.status_ready` 日文「準備完了」→ "Ready"；CDN 資源（Tailwind/Google Fonts/canvas-confetti）全部本地化；裝飾性 UI 元素（Data Source 下拉、假指標 `Mem: 64MB`/`Lat: 12ms`、`TXT_MODE: UTF-8` 字樣）照留。
5. **Batch 的 DarkLyrics fallback 修正為傳入 album**（現版 `fetch_single_missing` 未傳 album，直連專輯頁快路徑永遠走不到；兩路徑均以 fixture 鎖行為）。
   **5b（2026-08-10 M2 實施中補充拍板）**：一併修正 **fallback 觸發條件**。M2 移植時查明 py:2232 只判 `startswith("Error")`，Genius 回「Lyrics not found on Genius.」不以 Error 開頭 → 直接返回，**DarkLyrics 實際只在 token 未配置/拋異常時才跑**，決策 5 的 album 修正等同無效。新版改為「Genius 非命中即 fallback」。已落 `LyricsService.fetchForBatch` 並有單測；ACCEPTANCE C-10a 記錄偏差。
6. **Cover Flow 不加雙擊播放**——維持純歌詞工具定位。

**按合理默認處理（已向用戶聲明）**：自動抓取抑制語義＝「僅 Editor tab 激活時觸發」（原版判「batch 隱藏」，三 tab 後語義自然延伸）；Material Symbols 子集打包（7 glyph：graphic_eq/cloud_download/save_alt/arrow_drop_down/save_as/done_all/close，Apache 2.0）；開發期本地自簽證書（穩定簽名身份，避免 ad-hoc 每次重編譯觸發 Keychain 授權彈窗）；版本號 2.0.0。

**評審採納的安全/兼容修正（評審輪新增，見附錄 B）**：曲目身分以 persistentID 為主＋非同步請求世代守衛（防切歌競態把 A 曲歌詞寫進 B 曲）；paused 語義顯式化；HTTPClient 全面超時/取消；一次性遷移旗標；AppleLanguages 精確映射；Cover Flow 穩定排序。這些屬「內部缺陷修正」同類（UI 不可見或僅在競態下可見），與決策 4/5 同口徑。

**依賴**：SwiftSoup（SPM，唯一新依賴，HTML 解析）——已隨計劃批准。

## 3. 現狀盤點摘要（行為真源：lyrics_fetcher.py，2267 行）

活功能面：
- **Editor**：當前曲目卡片（3s 輪詢 `check_track`、簽名比對、卡片點擊手動 hydrate）；Fetch（僅 Genius）；Save（寫回 Music 當前曲目，成功觸發 confetti）；切歌自動載入 Music 已有詞（狀態 "Lyrics loaded from music app"）或清空＋100ms 後自動抓取；行數統計（`\n` split）。
- **Batch**（HTML 內 tab，非 Tkinter）：當前專輯全曲（appscript album+artist 雙條件過濾）；行＝補零序號/artist/title/狀態點（白＝有詞、紅＝缺詞）；預覽面板（readonly）；Fetch Missing（串行逐條，Genius→DarkLyrics）；Import Selected（confetti）；Import All（confirm 文案 "Writes lyrics for ALL tracks in list where lyrics are present. Continue?"，結束 "All saved."＋confetti）；切專輯清空重載。
- **Settings modal**：token（Genius account API 驗證→保存，成功 1.5s 自動關閉）；語言 en/zh_TW/ja（重啟生效）。
- **About modal**：圖標（base64）、版本、作者 iBridge Zhao、mailto 與 GitHub 連結；全 app 唯一圓角例外區。
- **Splash**：黑底六角形 SVG logo 淡入淡出，3.5s 後同窗替換主 UI。
- **退出矩陣**：紅色關閉鈕＝隱藏；Dock 點擊＝重顯；Cmd+Q / Dock 右鍵 Quit＝真退出。
- **菜單**：Settings（Token Settings... / Language Settings...）＋ Help（About），文案硬編碼英文。
- **i18n**：TRANSLATIONS 49 鍵三語；語言設定含 "system"（讀 per-app / 全局 AppleLanguages）；JS 運行時狀態文案硬編碼英文不走 i18n。
- **歌詞源**：
  - Genius：lyricsgenius（remove_section_headers 剝 `[Chorus]` 等；首行 "XXX Lyrics" 標題頭剝除）→ 手動 fallback（API search 首 hit → 抓頁 → `div[class*=Lyrics__Container]` 多容器 `\n` 拼接 → 舊版 `div.lyrics`）。
  - DarkLyrics：cloudscraper（繞 Cloudflare）；有 album 直連 `http://www.darklyrics.com/lyrics/{norm}/{norm}.html`（`[^a-z0-9]` 全刪小寫）；否則 DuckDuckGo Lite POST→GET fallback；專輯頁 `div.lyrics` 內 h3 遍歷（剝 `^\d+\.\s*` 序號）＋雙向 substring 模糊匹配＋sibling 收集到下一 h3、br→`\n`、壓縮 3+ 連續空行。
  - `sanitize_title`：三條 IGNORECASE 正則剝 (Remastered/Live/Remix/Demo/Version/feat./ft.) 括號與 "- Remastered/Remix" 尾綴。
  - 成敗判定慣例＝字符串前綴（"Error:" / "Lyrics not found"）——Swift 改三態 `LyricsResult`，展示文案不變。
- **配置**：.env（GENIUS_ACCESS_TOKEN/LANGUAGE，三級路徑 fallback）＋ `~/.azathoths_whisper_config`（JSON，只讀；損壞時整檔當裸 token 遷移、不回寫）；優先級 env > JSON > 默認；寫入端 `_update_env` frozen 時寫 .app 內部（缺陷）。
- **Apple Events**：`-1743`（errAEEventNotPermitted）→ 哨兵值 → UI 紅字 "Access Denied / Check macOS Permissions"。

### 附錄 A：20 項缺陷/死代碼清單（掃描核實，處置已按決策 4/5 定）

| # | 位置(py 行號) | 問題 | 處置 |
|---|---|---|---|
| 1 | 154–158 | `#source-select` 下拉無任何消費者，永遠走 Genius | 照留（裝飾） |
| 2 | README:15,17 | 宣稱 Metal Archives / Musixmatch 源不存在 | 不移植；README 隨 2.0 修正 |
| 3 | 962 | `en.status_ready` = 日文「準備完了」 | 修正 "Ready" |
| 4 | 951–998 | en 缺 batch_fetch/batch_import/batch_all 三鍵 | 補齊（觀察行為不變） |
| 5 | 1646–1839 | Tkinter BatchProcessingWindow 從未實例化，內含 3 處必崩 bug | 不移植 |
| 6 | 1435–1558 | DirectoryScanner 僅被死窗口引用 | 不移植 |
| 7 | 1611 | ConfigManager.save_config 從未被調用 | 不移植 |
| 8 | 1600–1605 | 舊格式遷移不回寫，每次啟動重複遷移 | 新遷移器冪等落位（一次性旗標，見 §4.9） |
| 9 | 2046/2048 | APP_ICON_PLACEHOLDER 注入為死代碼 | 不移植；圖標走 Assets |
| 10 | 13 | 日誌路徑硬編碼 ~/Documents/Bjork/ | 原生無此需求（Console.app/os_log） |
| 11 | 2158 | frozen 時 .env 寫入 .app 內部破壞簽名 | Keychain+UserDefaults 取代 |
| 12 | 940 | USER_AGENT 常量無引用 | Swift 側作為 HTTPClient UA 實際使用 |
| 13 | 31/55 | splash 重複 import | 不適用 |
| 14 | 133–134/188–189 | HTML 重複 nav/main 標籤 | 不適用（原生重寫） |
| 15 | 341–342 | JS 死引用 btn-batch-album/dir | 不適用 |
| 16 | 236 vs 695 | 預覽 readonly 但 Import 宣稱用預覽文字 | 照現實行為：預覽不可編輯，Import 用預覽內容 |
| 17 | 200–201 | 假指標 Mem/Lat 靜態數據 | 照留 |
| 18 | 2239 | fetch_single_missing 不傳 album | **修正傳入**（決策 5） |
| 19 | 65–68 | 前端依賴 CDN，離線降級 | 資源本地化（決策 4） |
| 20 | 1533+ | write_lyrics_to_file 格式覆蓋不全 | 隨 DirectoryScanner 不移植 |

## 4. 工程與架構

### 4.1 基本盤

- 工程位置：`~/Documents/Bjork/AzathothsWhisper/`（倉庫內新目錄）。
- Target：`AzathothsWhisper`（產品名 `Azathoth's Whisper`，bundle id 沿用 `com.ibridgezhao.azathothswhisper`，MARKETING_VERSION 2.0.0）＋ `AzathothsWhisperTests`（Swift Testing）＋ `AzathothsWhisperUITests`（冒煙級）。
- 最低部署 macOS 14.0（`@Observable`/`.visualEffect`/`.scrollPosition(id:)`/`.scrollTargetBehavior(.viewAligned)`/String Catalog）。
- App Sandbox 關閉（與現版一致，AE 自動化＋非 App Store）。
- 簽名：分發 ad-hoc（維持 xattr 流程）；開發期本地自簽證書。
- 構建產物：默認 DerivedData（iCloud 樹外）；.gitignore 加 xcuserdata。

### 4.2 目錄樹與文件職責（多小文件 200–400 行，上限 800）

```
AzathothsWhisper/
├── App/
│   ├── AzathothsWhisperApp.swift      # @main、Window(1200×800)、Commands 菜單
│   ├── AppDelegate.swift              # applicationShouldHandleReopen→顯示窗口；
│   │                                  # shouldTerminateAfterLastWindowClosed=false
│   ├── WindowConfigurator.swift       # NSWindowDelegate：windowShouldClose→orderOut+false
│   └── AppModel.swift                 # 根 @Observable：tab、splash 狀態、依賴容器
├── Features/
│   ├── Editor/    EditorView.swift / EditorViewModel.swift
│   ├── Batch/     BatchView.swift / BatchRowView.swift / BatchViewModel.swift
│   ├── CoverFlow/ CoverFlowView.swift / CoverFlowItemView.swift / CoverFlowViewModel.swift
│   ├── Settings/  SettingsModalView.swift / SettingsViewModel.swift
│   ├── About/     AboutModalView.swift
│   └── Splash/    SplashView.swift
├── Services/
│   ├── Lyrics/    LyricsSource.swift(protocol+三態 LyricsResult) / TitleSanitizer.swift /
│   │              GeniusSource.swift / GeniusParser.swift /
│   │              DarkLyricsSource.swift / DarkLyricsParser.swift / LyricsService.swift
│   ├── Music/     MusicControlling.swift(protocol+MusicError) / MusicScripting.swift(@objc 聲明) /
│   │              MusicAppleEventsClient.swift(SBApplication+串行隊列) / NowPlayingMonitor.swift(actor)
│   ├── Artwork/   ArtworkService.swift(中心優先預取+降採樣≤512px) / ArtworkCache.swift(NSCache+磁盤 LRU)
│   └── Config/    ConfigService.swift / KeychainStore.swift / LegacyConfigMigrator.swift / LanguageManager.swift
├── Infra/         HTTPClient.swift / CloudflareGateway.swift(實驗性,非門檻) / HTMLText.swift
├── UI/            Theme.swift / Components/{ActionButton,StatusFooter,NoiseOverlay,
│                                            ModalScrim,MaterialSymbol,ConfettiView}.swift
├── Resources/     Localizable.xcstrings(en/zh-Hant/ja) / Assets.xcassets / Fonts/(+LICENSE)
├── Tests/         Fixtures/ Parsing/ Services/ Mocks/
├── Scripts/       make_fixtures.py / coverage_gate.sh
└── ACCEPTANCE.md  # §6 驗收對照總表（M0–M1 期間建全表，先於 UI 實施）
```

**Modal 形態明示（評審 L15 澄清）**：Settings/About 為主窗內 SwiftUI 覆蓋層（ModalScrim），非獨立 NSWindow、非 sheet；hide-on-close delegate 只掛主窗，不存在「關 modal 誤隱藏主窗」路徑（入 AC-D）。

### 4.3 分層與協議邊界

SwiftUI View → `@Observable @MainActor` ViewModel → Service（actor/struct）→ Infra。

```swift
protocol MusicControlling: Sendable {
    func playerState() async throws -> PlayerState
    func currentTrack() async throws -> TrackInfo?          // artist,title,album,persistentID(必含)
    func currentLyrics() async throws -> String
    func setCurrentLyrics(_ text: String) async throws -> Bool
    func albumTracks() async throws -> [AlbumTrack]         // 含 lyrics＋disc/track number（Batch/排序）
    func albumTrackSummaries() async throws -> [TrackSummary] // 輕量（CoverFlow）
    func setLyrics(persistentID: String, _ text: String) async throws -> Bool
    func artworkData(persistentID: String) async throws -> Data?
}
// MusicError.permissionDenied（-1743）/ notRunning / scriptingFailure
// 語義（評審 M10 採納，對齊 py:1108-1128）：playing 與 paused 均返回當前曲、可讀寫 lyrics、
// 可載入 album；僅 stopped/無當前曲 → nil（notPlaying）。

protocol LyricsSource: Sendable { func fetchLyrics(for q: LyricsQuery) async -> LyricsResult }
// LyricsResult: .found(String) / .notFound / .error(String)

protocol HTTPClient: Sendable { get/post(form:) }   // UA=py:940 同值、cookie storage、超時見 §4.9
protocol SecretStore { read/write }                  // Keychain + InMemory mock
protocol PollClock { func tick(every: Duration) -> AsyncStream<Void> }
```

編排規則（1:1）：Editor Fetch＝僅 Genius，.error/.notFound 一律呈現 "Lyrics not found"；Batch Fetch Missing＝Genius→DarkLyrics（傳 album，決策 5）→ not found。**Save 寫入目標＝畫面綁定的 persistentID**（非「當前曲目」，見 §4.10 守衛）。

### 4.4 輪詢與事件

`NowPlayingMonitor`（actor）：3s 週期（注入 PollClock 可測）、**persistentID 為主識別**（無 ID 時 fallback `(artist,title,album)` 全簽名；評審 H4 採納——比原版 `(artist,title)` 簽名更嚴，屬碰撞缺陷安全修正，入 AC）、album 變更 key＝`(artist,album)`、isBusy 跳過；`AsyncStream<PlaybackEvent>`：`.trackChanged(TrackInfo, existingLyrics:)` / `.albumChanged` / `.notPlaying` / `.permissionDenied`。AppModel 分發至三 ViewModel。Editor 收 trackChanged：有詞→填入＋"Lyrics loaded from music app"；無詞→清空＋若 Editor tab 激活則 100ms 後自動 fetch。卡片點擊＝強制 hydrate。

### 4.5 退出矩陣（原生）

| 觸發 | 實現 |
|---|---|
| 紅色關閉鈕 | windowShouldClose → orderOut(nil)，return false |
| Dock 點擊 | applicationShouldHandleReopen → makeKeyAndOrderFront |
| Cmd+Q / Dock Quit | 默認 terminate:（Python 版整段 hack 消滅） |
| 最後窗口關閉 | applicationShouldTerminateAfterLastWindowClosed = false |

### 4.6 i18n

String Catalog en/zh-Hant/ja，鍵沿用 TRANSLATIONS；en 修正三處（決策 4）；JS 硬編碼英文的運行時狀態文案 → 集中 `StatusText` 非本地化常量檔並註明「1:1 保持英文，勿本地化」；新增 `nav_coverflow`（en "Cover Flow" / zh-Hant "封面瀏覽" / ja "カバーフロー"）。

**語言覆寫精確映射（評審 M9 採納）**：內部 enum `AppLanguage{system,en,zhTW,ja}`；寫入 `UserDefaults.standard` 的 `AppleLanguages` 陣列值＝`en→["en"]`、`zhTW→["zh-Hant"]`、`ja→["ja"]`、`system→刪鍵`；讀取端兼容 legacy 值（`zh_TW`/`zh-TW`/`zh-Hant` 均映射 zhTW，對齊 py:1621-1644 的 substring 判定）；重啟生效；M0 golden 鎖映射表、M5 冷啟動實測四態。

### 4.7 視覺

Theme：#000000 / #0a0a0a / #333333 / #E0E0E0 / #16439c；全 0 圓角（About modal 圓角例外照搬）；Space Grotesk＋Material Symbols 子集打包（OFL / Apache LICENSE 隨附）；噪點＝預渲染 PNG＋`.blendMode(.overlay)`＋allowsHitTesting(false)；文字 glow（0 0 8px rgba(255,255,255,0.15)）；按鈕 hover 白遮罩 translate-y 滑入＋`.blendMode(.difference)`；confetti＝CAEmitterLayer 復刻 canvas-confetti 五連發參數（spread 26/60/100/120×2、velocity 55/–/–/25/45、decay 0.91/0.92、scalar 0.8/1.2、origin.y 0.7、count 200 按比例分配；評審質疑過度設計經辯論駁回——參數為現成常量表，成本≈自調樣式，複審已接受）。

### 4.8 Cover Flow

- 入口：第三個 nav tab（Editor｜Batch｜Cover Flow），激活時懶加載（對齊 Batch 先例）。
- 渲染：`ScrollView(.horizontal)`＋`LazyHStack`（負間距 -0.42×itemWidth 覆疊）＋`.visualEffect` 按「距視口中心歸一化距離 d」驅動 `rotation3DEffect(-55°×clamp(d), axis:(0,1,0), anchor: d<0 ? .trailing : .leading, perspective:0.55)`＋scale 1.0→0.82 插值＋`zIndex(-abs(d))`；`.scrollTargetBehavior(.viewAligned)` 吸附；`.safeAreaPadding(.horizontal, (viewWidth-itemWidth)/2)` 使首尾可達中心。
- 條目：封面＋倒影（`.scaleEffect(y:-1)`＋LinearGradient(0.45→0) mask）＋`.drawingGroup()`。
- 中心標籤：mono 字體 `ARTIST // TITLE`。
- **排序（評審 M12 採納）**：`TrackSummary` 含 disc/track number；穩定排序＝disc → track number → AE 返回序 fallback；標註為兼容性修正（原版 Batch 以 AE 返回序呈現）並入 AC-H。
- 聯動：`.trackChanged` → `withAnimation(.smooth)` 居中（用戶手動滑走不搶控制，等下次真實切歌）；`.albumChanged` → 重建＋預取；左右方向鍵步進（`onKeyPress`，窗口內按鍵）。
- 封面：AE `artworks[1]` raw data → `CGImageSourceCreateThumbnailAtIndex` ≤512px → NSCache（內存）＋磁盤縮圖緩存；**磁盤規則（評審 M11 採納）**：檔名＝persistentID 的 SHA256 前綴（防特殊字符）、臨時檔＋rename 原子寫入、metadata 記大小/訪問時間、啟動與寫入超額時 LRU 清理（200 張/50MB）、損毀檔容錯（讀失敗→刪除重取）；中心向兩側預取；AE 專用串行隊列天然限流；占位＝六角形 logo 暗紋。
- 純展示：無點擊播放、無任何播控動詞（決策 6）。

### 4.9 網路與配置

**HTTPClient 超時與錯誤紀律（評審 H7 採納；per 全局 CLAUDE.md §3 硬需求）**：
- 每請求 timeout：darklyrics 直連 10s、DDG Lite 15s（沿用 py:1310/1330 同值）；Genius API/歌詞頁/token 驗證 15s（Python 未設，取同級默認）。
- 整體操作 deadline：單曲 fetch ≤45s；取消傳播（Task cancellation 貫穿 Service→Infra）；錯誤分類（超時/DNS/4xx/5xx/解析失敗）；429/403 不自動重試（對齊原版無重試行為）；Batch 串行中單曲失敗不中斷整批（對齊 py:648-680）。

**Cloudflare 策略（評審 H2 修改採納）**：
- **主路徑（門檻）**：URLSession＋瀏覽器 UA（py:940 同值）＋cookie jar，帶上述超時；失敗→現版同款錯誤文案優雅降級（"Error: Could not search for song (DDG Lite Blocked)." 等），可觀測（os_log 記錄狀態碼）。
- **實驗 adapter（非門檻）**：`CloudflareGateway` 離屏 WKWebView 跑 JS challenge——隔離為可整體移除的模組，僅在主路徑確認被 CF 攔截時啟用；停損條件＝實測無法穩定過 challenge 即棄用，保留降級文案。M3 DoD 不含此路徑。
- DarkLyrics 為 HTTP：Info.plist ATS 例外 `darklyrics.com`；實施時先試 https，可用則升級並記錄驗收偏差。

**配置（評審 M8-token 採納）**：
- Keychain（token）＋UserDefaults（language）；**一次性遷移**：UserDefaults 旗標 `legacyConfigMigrated`（版本化）；未遷移時讀 legacy（.env 三級路徑＋舊 config 兩格式，優先級 env > JSON，對齊 py:1565-1609）→ 成功寫入 Keychain/UserDefaults 後置旗標；**遷移後 Keychain/UserDefaults 為唯一真源，不再讀 .env**（偏離原版 env 恆優先——原版該行為會讓新存 token 被舊 .env 覆蓋，屬缺陷，記入 AC-F 偏差欄）；不刪舊檔（並存期 Python 版還要用）。
- 測試紀律：遷移測試全部用臨時目錄＋假 token；**禁止測試讀真實 .env**；開發機手動驗證一次真實遷移（日誌脫敏，不落 token）。

### 4.10 併發一致性與守衛（評審 C1/H4/H5 採納後新增）

- **曲目身分**：`TrackInfo.persistentID` 必含；全 app 以 persistentID 為曲目身分，`(artist,title,album)` 僅作無 ID 時的 fallback。
- **請求世代守衛（Editor）**：Fetch 起始時捕捉 `(persistentID, generation)`；返回時僅當「當前綁定曲目仍匹配」才套用到編輯器；切歌事件遞增 generation 並取消進行中的自動抓取。
- **Save 綁定**：Save 寫入 fetch/hydrate 時綁定的 persistentID（走 `setLyrics(persistentID:)`），不寫「當前曲目」；若偵測綁定 ID 已非當前播放曲，照常寫入綁定曲（用戶編輯的就是那首）——此為對原版「A 詞寫入 B 曲」競態的安全修正，入 AC-B。
- **Batch 縱深（H5 修改採納）**：主防線＝1:1 保留 isBusy 語義（批處理期間禁全部按鈕＋輪詢跳過，albumChanged 天然不觸發）；縱深＝每次專輯載入生成 session ID，串行 fetch/import 的每步回寫前校驗 session 仍有效（切 tab 手動重載、監聽恢復後專輯已變等場景）；窗口隱藏不中斷任務（對齊原版）。按鈕重入禁止（isBusy 期間 disabled）。
- **AC 場景**：Fetch 中切歌、Batch fetch 中切專輯/切 tab/隱藏窗口、自動抓取被新切歌搶佔——全部入 ACCEPTANCE.md B/C 區段。

## 5. 任務清單（M0–M8，TDD，特徵測試先行）

| # | 內容 | DoD（可判定） |
|---|---|---|
| M0 | `Scripts/make_fixtures.py` **免副作用**取 Python 純函數（sys.modules stub / 函數抽取，不觸發 .env 加載、appscript、GUI import——評審 H6 修改採納）生成 golden：sanitize_title ≥20 條、Genius 解析 ≥4 頁＋search 選 hit JSON、DarkLyrics 解析 ≥4 頁＋normalize 表（含變音符號）、config 遷移 6 組合、語言映射表；允許經審核的手工 expected（附來源理由）；**建 ACCEPTANCE.md 骨架＋G 區段全條目**（評審 L16 採納） | fixture 帶 input/expected 對、可重跑再生比對；抽查 3 組與 Python 版實跑一致；ACCEPTANCE.md 骨架落檔 |
| M1 | **AE spike 先行**（評審 H3 採納）：最小驗證讀當前曲/讀寫 lyrics/by-persistentID 寫入/取 artwork raw data/album 雙條件過濾五項，確定 bridge 技術（ScriptingBridge vs AEDesc）與失敗碼映射；spike 失敗→重評估點（備選：NSAppleScript 封裝）。隨後 Xcode 骨架：三 target、SwiftSoup、Theme、字型、String Catalog（含 en 修正）、noise.png、coverage_gate.sh；**補完 ACCEPTANCE.md A–F/H 全條目**（先於 UI 實施） | spike 五項全通（真機 Music.app）；`xcodebuild test` 綠；黑底窗口啟動；三語 Catalog 過校驗；字型生效；ACCEPTANCE.md 全表落檔（全 ⬜） |
| M2 | 純函數移植：TitleSanitizer→HTMLText→GeniusParser→DarkLyricsParser→LyricsService 編排（stub source 測順序與三態） | M0 golden 全綠；Services/Lyrics/ 行覆蓋 ≥90% |
| M3 | Infra：HTTPClient（超時/取消/錯誤分類 per §4.9）、兩 Source 全鏈路（MockHTTP 餵 fixture，含超時/取消/部分失敗案例）、Keychain/Config/Migrator（6 組合＋冪等＋旗標＋不刪舊檔；臨時目錄＋假 token） | 單測綠；真機 darklyrics 主路徑取頁實測（成敗均記錄，失敗→降級文案驗證）；開發機手動遷移驗證（脫敏） |
| M4 | MusicScripting、MusicAppleEventsClient（串行隊列、-1743 映射、paused 語義）、NowPlayingMonitor（TestClock 場景：切歌/切專輯/暫停仍讀曲/busy 跳過/權限拒/世代守衛） | Monitor 單測綠（含 paused≠notPlaying）；真機讀寫冒煙；TCC 拒絕→permissionDenied |
| M5 | Editor＋外殼：Splash 3.5s、窗口/菜單/退出矩陣、Editor 全功能（含世代守衛與 Save 綁定）、Settings/About（ModalScrim）、i18n（含四態語言冷啟動實測） | ACCEPTANCE.md A/B/D/E 區段並排對照全勾；退出矩陣 4 條全過；競態場景（Fetch 中切歌）通過 |
| M6 | Batch：列表/預覽/三按鈕/串行進度文案/isBusy＋session ID 守衛/confetti 參數對照 | ACCEPTANCE.md C 區段全勾（含切專輯/切 tab/隱藏窗口場景）；真實專輯（≥10 曲含缺詞）全流程跑通 |
| M7 | Cover Flow：ArtworkCache（雜湊檔名/原子寫入/LRU/損毀容錯）→ArtworkService（預取順序 Mock 測）→視圖聯動（穩定排序） | 20 曲滑動無卡頓（Instruments 主線程無 AE 長任務）；切歌 ≤3s 居中；冷啟動緩存即顯；三語 tab 文案 |
| M8 | 打包收官：簽名、Info.plist（AE 文案沿用 spec、ATS、ATSApplicationFontsPath）、圖標、DMG（復用 setup_dmg.applescript）、README 三語更新；**乾淨機 checklist（評審 M14 採納）**：新 macOS 用戶→DMG 拖移→quarantine 確認→xattr→首啟→TCC 首彈→拒絕後重試路徑→Keychain 訪問→舊配置遷移→離線啟動（CDN 已本地化驗證） | checklist 逐項記錄通過；ACCEPTANCE.md 全表無 ⬜、⚠️ 均有用戶簽字；coverage_gate ≥80%（Services+Infra）；Python 版 git status 乾淨 |

## 6. 驗收標準（ACCEPTANCE.md 組織方式）

每行五欄：`| ID | 行為描述（可判定） | Python 依據(行號) | 驗證方式 | 狀態 |`；狀態 `✅/⚠️(附說明+用戶簽字)/⬜`。**全表於 M0–M1 建立完成（先於 UI 實施，評審 L16 採納）**；M8 收口＝無 ⬜ 且 ⚠️ 全簽字。約 95 條，八區段：

- **A 外殼與生命週期**（~12）：splash 3.5s、窗口 1200×800、菜單兩組四項、退出矩陣 4 條、Dock 重顯、TCC 拒絕紅字。
- **B Editor**（~23）：3s 輪詢、busy 跳過、切歌載詞文案、自動 fetch（100ms、僅 Editor tab）、卡片點擊、僅 Genius、not found 文案、Saved＋confetti、行數規則、裝飾元素三件、**世代守衛/Save 綁定/Fetch 中切歌**（安全修正標註）。
- **C Batch**（~21）：雙條件過濾、行格式、預覽聯動、串行進度文案、fallback 順序（傳 album）、Import confirm 文案、All saved＋confetti、切專輯重載、**fetch 中切專輯/切 tab/隱藏窗口**。
- **D Settings/About**（~13）：token 驗證四態文案、1.5s 自動關閉、語言三選項＋重啟提示、About 內容兩鏈接、圓角例外、**modal 開啟時主窗關閉行為**。
- **E i18n**（~10）：三語抽查、en 三處修正、運行時文案保持英文、system 跟隨、**四態 AppleLanguages 冷啟動映射**。
- **F 配置遷移**（~9）：6 組合、冪等、旗標、不刪舊檔、Keychain 落位、**遷移後不再讀 .env（偏差標註）**。
- **G 歌詞源保真**（~15）：M0 fixture 每組一條。
- **H Cover Flow（對 spec）**（~11）：3D 形態五要素、3s 內居中、專輯切換重建、緩存冷啟、鍵盤步進、三語文案、無播控、**穩定排序（兼容修正標註）**。

## 7. 測試策略

- **單元（核心）**：兩解析器、sanitize、normalize、fallback、三態判定、遷移、語言映射、LRU、Monitor 事件序列＋世代守衛——Swift Testing＋golden，表驅動。
- **單元（併發）**：TestClock 手動推進，零真實延時；取消傳播測試。
- **集成（離線，門檻）**：MockHTTPClient 按 URL 路由 fixture，Source 全鏈路輸出 == golden；超時/取消/部分失敗案例。
- **集成（在線，非門檻）**：`.tags(.network)` 默認跳過，手動觸發。
- **AE 層**：MockMusicClient 覆蓋 ViewModel；真實 client 手動冒煙＋M1 spike。
- **E2E**：一條冒煙 XCUITest（啟動→accessibilityIdentifier 存在→PID 定界 terminate；禁全局按鍵模擬）＋ACCEPTANCE.md 人工並排對照。
- **覆蓋率**：門檻只計 Services/＋Infra/（xccov 過濾）≥80%；解析層 ≥90%。
- **fixture 紀律**：真實 HTML 存檔入測試目錄（不入分發物）；golden 由 make_fixtures.py 生成或經審核手工撰寫（附來源理由）；生成器作再生比對。

## 8. 影響面

- 新增：`AzathothsWhisper/` 整目錄、`docs/plans/` 本檔。
- 不動：Python 版全部現有文件（驗收通過前 git status 對舊檔保持乾淨）；`.env`、`~/.azathoths_whisper_config` 讀不刪。
- 系統面：TCC 自動化授權將因新二進制重新彈窗（預期）；Keychain 新增一條 generic password；Application Support 新增緩存目錄；UserDefaults 同域共享（AppleLanguages 設定自然延續）。
- 分發面：DMG 流程沿用；README 三語需隨 2.0 更新（Build 步驟改 Xcode、去 lproj hack、修正源清單）——列入 M8。

## 9. 風險與回退

| # | 風險 | 緩解 | 回退 |
|---|---|---|---|
| R1 | DarkLyrics/Cloudflare 無 cloudscraper 對應 | 主路徑＝URLSession+UA+超時+可觀測失敗（門檻）；WKWebView challenge 為隔離實驗 adapter（非門檻，停損＝實測不穩即棄） | 降級後功能面＝「該源暫不可用」同款文案，與現版被封表現一致 |
| R2 | DarkLyrics HTTP/ATS | ATS 例外；先試 https | 保持 http+例外 |
| R3 | Genius 行為漂移（lyricsgenius 私有選歌/清洗邏輯） | golden 鎖「fixture 集最終文本一致」而非實現一致；模糊選擇器＋舊容器 fallback | 驗收口徑已定 fixture 集 |
| R4 | Artwork AE 慢/阻塞 | 串行隊列＋中心優先＋磁盤縮圖＋占位 | 降低預取半徑 |
| R5 | TCC 重彈 | 預期行為；tccutil reset 測試路徑；README 註明 | — |
| R6 | 同 bundle id 雙 app 並存 | 開發期不同時運行；乾淨用戶驗收 | — |
| R7 | ad-hoc×Keychain ACL 彈窗 | 開發期自簽證書；分發用戶最多一次授權 | — |
| R8 | 字型授權 | OFL/Apache 均允許打包，LICENSE 隨附 | — |
| R9 | 正則 Unicode 語義差（[^a-z0-9]、IGNORECASE、\n{3,}） | 全進 M0 fixture 鎖行為 | — |
| R10 | iCloud 同步抖動 | 產物走 DerivedData；.gitignore 收緊 | — |
| R11 | 視覺復刻落差（噪點/glow/blend） | 口徑「盡可能貼近」；M5 並排目測簽字 | ⚠️＋簽字機制 |
| R12 | AE bridge 技術不可行（新增，評審 H3） | M1 spike 五項先行驗證；失敗→NSAppleScript 封裝備選＋重評估點 | spike 階段即暴露，未投入 UI 成本 |
| 總回退 | 任何階段失敗 | Python 版原地未動，隨時可繼續使用/發布 1.2.x | 刪除 AzathothsWhisper/ 目錄即回到現狀 |

## 10. 執行紀律

- TDD：每里程碑先 RED 後 GREEN；fixture 先行（M0 是整鏈起點）。
- 不 commit 主分支；checkpoint 允許本地 `wip/` 分支（禁 push、禁併回）；正式提交等用戶拍板。
- 實施中發現 Plan 有錯：筆誤直改留痕；動到驗收標準的錯回 Phase 1 快速複審。
- 代碼測試全綠 → /simcodex → 裁決 → 全量測試 → 收官證據包（測試輸出、git diff --stat、兩輪評審辯論摘要、ACCEPTANCE 對照、遺留 P2 清單）。

## 附錄 B：codex 對抗評審辯論記錄（2026-08-09/10，codex-cli 0.145.0）

第一輪 16 條意見逐條裁決：

| # | codex 意見（嚴重度/要旨） | 裁決 | 理由摘要 | 落點 |
|---|---|---|---|---|
| 1 | CRITICAL 非同步抓取無曲目身分/世代守衛，A 詞可寫入 B 曲 | **採納** | 資料毀損風險；原版雖同病但重寫不應制度化；與已批准安全修正同類 | §4.10、M4/M5、AC-B |
| 2 | HIGH WKWebView 解 CF challenge 不可靠、過度工程 | **修改採納** | 主路徑降為普通 HTTP＋超時＋降級文案（門檻）；WKWebView 隔離為實驗 adapter＋停損（非門檻） | §4.9、R1、M3 |
| 3 | HIGH AE bridge 可行性未驗證，需 spike 先行 | **採納** | album filter/persistentID/artwork 為最高不確定點，前置驗證成本低收益大 | M1、R12 |
| 4 | HIGH (artist,title) 簽名不足識別曲目 | **採納** | persistentID 為主識別；album key=(artist,album)；標安全修正 | §4.4、AC |
| 5 | HIGH Batch 需 job/session 取消重入保護 | **修改採納** | isBusy（1:1）為主防線——按鈕禁用＋輪詢停即天然無 albumChanged；外加低成本 session ID 縱深；不採納完整 job 生命週期管理 | §4.10、M6、AC-C |
| 6 | HIGH make_fixtures 受環境副作用影響、CI 難重現 | **修改採納** | 本專案無 CI，fixture 為一次採集入庫，重現性非需求；但 import 副作用屬實→免副作用取函數；允許審核過的手工 expected | M0、§7 |
| 7 | HIGH 網路超時/取消/錯誤分類未全面定義 | **採納** | 全局 CLAUDE.md §3 本就列為硬需求；補每請求超時（沿用 py 同值）＋deadline＋取消傳播＋錯誤分類 | §4.9、M3/M6 |
| 8 | MEDIUM token 遷移邊界不清，env 恆優先會覆蓋新 token；測試讀真 .env 洩密風險 | **採納** | 一次性版本化旗標；遷移後 Keychain 唯一真源（偏差標註）；測試禁真 .env | §4.9、AC-F |
| 9 | MEDIUM AppleLanguages 映射未明確 | **採納** | enum＋精確寫入值＋legacy 兼容讀取＋冷啟動測試 | §4.6、M0/M5 |
| 10 | MEDIUM paused 語義未定義 | **採納** | 顯式：playing/paused 均可讀寫；僅 stopped＝notPlaying（對齊 py:1108-1128） | §4.3、M4、AC |
| 11 | MEDIUM artwork cache 檔名/原子性/LRU 觸發未定義 | **採納** | SHA256 檔名、臨時檔+rename、啟動/寫入清理、損毀容錯 | §4.8、M7 |
| 12 | MEDIUM Cover Flow 排序未規定 | **採納** | disc→track number→AE 返回序；標兼容修正 | §4.8、AC-H |
| 13 | MEDIUM confetti/hover 逐參數復刻＝過度設計 | **駁回** | 參數為現成常量表，直譯成本≈自調樣式；視覺保真是用戶明確優先級；驗收本為目視簽核 | — |
| 14 | MEDIUM M8「乾淨用戶驗證」過於籠統 | **採納** | 展開為可重複 checklist（DMG/quarantine/TCC/Keychain/離線十步） | M8 |
| 15 | LOW modal 形態未明（sheet vs 獨立窗） | **澄清** | §4.2 已定 ModalScrim 窗內覆蓋層，風險路徑結構上不存在；補明示＋AC | §4.2、AC-D |
| 16 | LOW ACCEPTANCE.md 延後到收尾不可審計 | **採納** | 提前：M0 建骨架＋G 段，M1 補全 A–F/H | M0/M1、§6 |

第二輪複審（駁回/修改/澄清 4 條回餵）：codex 對 #13 駁回、#5 修改、#6 修改、#15 澄清**全部明示接受，無重提**。按勝負判據（不再提＝接受），辯論收束。整體有輸有贏：codex 在 #1/#3/#4/#7 等主體條目勝出，裁決方在 #13 勝出，#5/#6 折中。
