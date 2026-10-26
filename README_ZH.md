# Azathoth's Whisper (阿撒托斯的低語)

[**English**](README.md) | [**繁體中文**](README_ZH.md) | [**日本語**](README_JA.md)

**Azathoth's Whisper** 是一個 macOS 應用程序，可以自動獲取目前在 **iTunes** 中播放歌曲的歌詞，並將其直接嵌入到音頻文件的自定義歌詞元數據中。

它支持多種歌詞來源，並具有深色主題和多語言用戶界面。

**3.0 新增：iPad 遙控器。** 這個 repo 現在會建置出兩個 App：

| App | 平台 | 版本 | 用途 |
|---|---|---|---|
| **Azathoth's Whisper**（阿撒托斯的低語） | macOS | 3.0.0 | 上面的歌詞工具，外加可選的**中繼**，讓 iPad 控制這台 Mac 上的 Music |
| **Yog-Sothoth's Echo**（尤格·索托斯的回響） | iPad | 1.0.0 | 黑膠唱機造型的遙控器：在家裡任何地方瀏覽 Mac 的 Music 曲庫並控制播放 |

iPad App 只會經由家中區網，連到你自己 Mac 上的 Azathoth's Whisper。詳見
[iPad 遙控器：Yog-Sothoth's Echo](#ipad-遙控器yog-sothoths-echo)。

## 功能

*   🎵 **自動同步：** 監控 iTunes 並在切換歌曲時自動獲取歌詞。
*   📝 **歌詞寫入：** 將歌詞直接寫入音樂文件（可在 iTunes、iPhone 等設備上查看）。
*   🌍 **多來源支援：**
    *   **Genius**（需 API Token）
    *   **DarkLyrics**（**僅批量處理模式**的後備來源——見下方說明）

    > 編輯器裡的單曲 Fetch **只查 Genius**。DarkLyrics 只在批量處理的
    > *Fetch Missing* 中、且 Genius 對該曲無命中時才會被查詢。

    > **關於 2.0 的來源清單：** 舊版 README 另外列了 *Metal Archives* 與 *Musixmatch*。
    > 這兩個來源從未被實作過——即使在 1.x 的 Python 版也沒有。（1.x 的來源下拉裡確實有一個
    > "MetalArchives" 項，但那個控件從未接線，選了沒有任何效果。）2.0 只列實際存在的兩個來源。
    > **沒有刪減任何功能。**
*   🌐 **多語言界面：** 完全支持 **英文**、**繁體中文** 和 **日文**。
*   🌑 **深色模式：** 時尚現代的深色界面。
*   ⚙️ **智能配置：** 記住您的 Genius Token 和語言偏好。
*   🍎 **macOS 原生：** 以 Swift 6 / SwiftUI 撰寫，尊重系統語言設定，透過 Apple Events 與 Music.app 整合。
*   📚 **批量處理：** 一次檢視整張專輯——批量補齊缺詞並寫回。
*   🖼 **封面瀏覽：** 以 3D 旋轉木馬瀏覽當前專輯封面（純展示，無播放控制）。
*   📱 **iPad 遙控（3.0）：** 可選的中繼把 Music 曲庫與播放控制提供給配套的 iPad App「Yog-Sothoth's Echo」。預設關閉。

## 前置要求

**🔑 Genius API Token（必需）**

要獲取歌詞，您需要一個免費的 Genius API Token：

1. 訪問 [genius.com/api-clients](https://genius.com/api-clients/)
2. 登錄或創建帳號
3. 點擊 **"New API Client"**
4. 填寫必需信息（應用名稱、網站 URL - 可以隨意填寫）
5. 複製您的 **Client Access Token**
6. 首次啟動時在應用的 Settings 中粘貼

> **注意：** Token 完全免費，申請過程不到 2 分鐘。

## 安裝

### 預編譯應用程序 (DMG)

從 [GitHub Releases](https://github.com/TK88101/Azathoths-Whisper/releases) 下載最新版本。

**⚠️ 重要：macOS 首次安裝說明**

由於此應用未經 Apple Developer ID 簽名，macOS Gatekeeper 會阻止運行。您很可能會看到錯誤提示：**「應用程序已損壞，無法打開」**。這是安全功能，並非真的損壞。

**安裝步驟：**

1. **下載並掛載 DMG**
   - 從 Releases 頁下載最新的 `.dmg`
   - 雙擊掛載

2. **安裝應用**
   - 將 `Azathoth's Whisper.app` 拖動到 DMG 窗口中的 **應用程序 (Applications)** 文件夾快捷方式

3. **移除隔離標記（下載應用必需步驟）**
   
   打開 **終端機 (Terminal)**（應用程序 → 工具程式 → 終端機）並執行：
   ```bash
   xattr -d com.apple.quarantine /Applications/Azathoth\'s\ Whisper.app
   ```
   
   這會移除導致"損壞"錯誤的 macOS 隔離屬性。

4. **打開應用**
   
   現在可以正常打開了：
   - **方式 A**：在應用程序文件夾中雙擊應用
   - **方式 B**：右鍵點擊 → 打開（如果仍有提示）
   
   ✅ 應用將運行。macOS 會記住您的選擇，之後啟動不再提示。

5. **授予自動化權限**
   - 首次啟動時，系統會要求授權控制 iTunes
   - 點擊 **「好 (OK)」** 允許

**為什麼會這樣？**
- macOS 會為所有從網路下載的應用添加"隔離"標記
- 沒有 Apple Developer 簽名的應用帶此標記時會被標為"損壞"
- 移除標記後應用即可正常運行

### 從源碼構建

需求：**macOS 14.0+**、**Xcode 16+**（Swift 6）、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

> 已在 macOS 26.6 / Xcode 26.6 / Swift 6.3 上測試驗證。上述下界來自 `project.yml`
> （`deploymentTarget: 14.0`、`SWIFT_VERSION: 6.0`），但未直接測試過。

1.  **複製倉庫**
    ```bash
    git clone https://github.com/TK88101/Azathoths-Whisper.git
    cd Azathoths-Whisper/AzathothsWhisper
    ```

2.  **安裝 XcodeGen**
    ```bash
    brew install xcodegen
    ```

3.  **生成 Xcode 專案**
    ```bash
    xcodegen generate
    ```
    `.xcodeproj` 由 `project.yml` 生成**並已提交**，所以 clone 後無需 XcodeGen 即可構建。
    您只需在新增或移除原始檔後重跑此步驟——否則 Xcode 會靜默沿用舊的檔案清單繼續建置。
    重新生成的項目需與您的改動一起提交。SwiftSoup 於首次建置時由 SPM 解析。

4.  **執行測試**
    ```bash
    xcodebuild test -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper \
      -destination 'platform=macOS' -only-testing:AzathothsWhisperTests \
      -test-timeouts-enabled YES -default-test-execution-time-allowance 120
    ```
    UI 測試（`-only-testing:AzathothsWhisperUITests`）另需在
    **系統設定 → 隱私權與安全性 → 輔助使用** 中授權 Xcode。

5.  **建置 Release 版**
    ```bash
    WORK="$(mktemp -d)"
    xcodebuild build -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper \
      -configuration Release -destination 'platform=macOS' -derivedDataPath "$WORK/dd"
    ```
    產物為 **ad-hoc 簽名**（`CODE_SIGN_IDENTITY: "-"`），這正是下載後需要執行上方
    *安裝* 段落那道 quarantine 步驟的原因。

6.  **製作 DMG**

    磁碟映像沿用倉庫內的視窗版式範本，版式可重現且不需要 Finder 腳本：

    ```bash
    # $WORK 來自步驟 5；新 shell 裡要重新聲明
    APP="$WORK/dd/Build/Products/Release/Azathoth's Whisper.app"
    STAGING="$WORK/staging"; mkdir -p "$STAGING"

    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    cp ../packaging/dmg-layout.DS_Store "$STAGING/.DS_Store"
    cp ../dmg_background.png "$STAGING/"
    chflags hidden "$STAGING/dmg_background.png"

    hdiutil create -volname "Azathoth's Whisper" -srcfolder "$STAGING" \
      -format UDZO -ov "$WORK/Azathoths-Whisper-v3.0.0.dmg"
    ```

    卷名與各項目的檔名必須與上方完全一致——`.DS_Store` 按**名稱**解析背景圖與圖示位置。
    （`.dmg` 檔案本身跨多次執行並非位元組級可重現；只有**版式**可重現。）

## 使用說明

1.  **啟動應用**：打開 Azathoth's Whisper。
2.  **Genius Token 設置**：
    *   首次運行時，前往 `Settings` -> `Genius Token Settings`。
    *   粘貼您的 **Genius Client Access Token** (可在 [genius.com/api-clients](https://genius.com/api-clients) 獲取)。
    *   點擊保存 (Save)。
3.  **播放音樂**：在 iTunes 中開始播放歌曲。
4.  **獲取歌詞**：
    *   **自動模式 (Auto Mode)**：應用程序會檢測歌曲變化並嘗試自動查找歌詞。
    *   **手動模式**：點擊 "Fetch Lyrics" 強制搜索。
5.  **語言設置**：通過 `Settings` -> `Language Settings` 切換界面語言。

## iPad 遙控器：Yog-Sothoth's Echo

Yog-Sothoth's Echo 把 iPad 變成黑膠唱機造型的遙控器，用來控制 Mac 上的 Music。音樂仍然**從 Mac 播出**
（Mac 喇叭或它接的音響）；iPad 只負責控制。

**在 iPad 上可以做的事**

*   以 3D 側封或封面牆瀏覽 Mac 曲庫的全部專輯，並可搜尋。
*   打開專輯、點一首歌——Mac 會從這首開始播，接著播這張專輯其後的歌。
*   在唱機畫面點唱片暫停／繼續，左右甩動切換上一首／下一首。
*   底部膠囊有上一首／播放暫停／下一首與 **Genius**（Music 自己的 Genius 隨機播放，和上面的 Genius *歌詞* token 無關）。
*   可選唱片樣式（Random、Classic、Transparent、Splash、Marble）與亮色／暗色／跟隨系統的外觀。

**需求**

*   **iPadOS 18 以上**的 iPad，與 Mac 在同一個家用網路（Wi-Fi）。
*   執行 **Azathoth's Whisper 3.0.0**、且開著 Music.app 的 Mac。

### 安裝 iPad App

iPad App 以 `.ipa` 放在 [Releases 頁面](https://github.com/TK88101/Azathoths-Whisper/releases)。
它**沒有簽名**、也不在 App Store 上，所以要用側載工具以你自己的 Apple ID 簽名後安裝，例如 **SideStore**、**AltStore** 或 **iLoader**。

> 用免費 Apple ID 側載的 App **7 天**後會失效，屆時重新簽名／安裝即可（SideStore 可以自動續簽）。覆蓋安裝會保留配對。

### 首次設定

在 **Mac**（Azathoth's Whisper 3.0.0）上：

1.  打開 **Settings → Remote Settings…**，開啟 **Allow Yog-Sothoth's Echo on iPad to control Music**。中繼**預設關閉**。
2.  若跳出鑰匙圈授權框，輸入 Mac 登入密碼並選 **永遠允許**。每次更新後都會再問一次，因為每個建置的 ad-hoc 簽名都不同。
3.  在 **Music Control** 下按 **Install Shortcut**，再到「捷徑」App 按 **加入捷徑**。這會安裝「YSE Play v1」捷徑，讓點的歌能接著播完整張專輯。若捷徑問到分享，選 **永遠允許**。
4.  允許設定頁要求的權限：**自動化 → Music**、**媒體與 Apple Music**（讀取曲庫），以及——只有要用 Genius 鈕時才需要——**輔助使用**。
5.  可選：開啟 **Open Azathoth's Whisper at login**，這樣不必先手動打開 App，iPad 也能連上。

配對：

1.  在 Mac 上按 **Pair new iPad**，會出現一個 60 秒有效的 QR 碼。
2.  在 iPad 打開 Yog-Sothoth's Echo 掃碼。被問到時，允許相機與區域網路存取。
3.  Mac 會顯示 **Unverified device request** 與 4 個字元。確認和 iPad 上的一樣，再按 **Allow**。

之後 iPad 會自動重連，Mac 睡眠或 App 重開後也一樣。要解除配對，在 Mac 的 **Paired iPads** 裡移除該 iPad。

### 已知限制

*   點一首歌會把 Music 的「**接下來**」換成這張專輯從這首起的曲目，原本的佇列不保存、不還原。點下去約 1.5 秒才開播。
*   專輯接續播放靠「YSE Play v1」捷徑。捷徑不在、或專輯名稱有歧義時，只會播這一首，iPad 會提示。
*   連續切歌時，每次都要等前一次生效（每首約 1.5 秒）；排隊超過 3 次會被拒絕。
*   iPad 不能拖進度、不能調音量，只能在家用網路內使用。
*   曲庫變動約一分鐘內反映到 iPad（Mac 每 60 秒重新檢查一次曲庫）。

### 隱私與安全

*   中繼在你打開之前都是關閉的，而且只接受以 QR 碼配對**並且**在 Mac 上按過允許的 iPad。
*   每條連線都是雙向認證、釘選憑證的 TLS，只限區網；請求有防重放，只接受固定的幾種指令。
*   在 Mac 上，中繼只**讀取** Music 曲庫並送出播放指令，不修改曲庫，也不寫 Music 的佇列檔案。輔助使用只用來按下 Music 的 Genius 選單項目。
*   日誌只記 ID 與錯誤類型——不記曲名、歌詞、token 或配對秘密。

### 從源碼建置 iPad App

需求：**Xcode 16+**（Swift 6、iOS 18 SDK）、XcodeGen。實際以 Xcode 27 建置驗證。

```bash
cd Azathoths-Whisper/YogSothothsEcho
xcodegen generate

# 單元測試（任一 iPad 模擬器；名稱改成你有的）
xcodebuild test -project YogSothothsEcho.xcodeproj -scheme YogSothothsEcho \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:YogSothothsEchoTests

# 未簽名的 Release .ipa（再用側載工具簽名）
WORK="$(mktemp -d)"
xcodebuild build -project YogSothothsEcho.xcodeproj -scheme YogSothothsEcho -sdk iphoneos \
  -configuration Release CODE_SIGNING_ALLOWED=NO -derivedDataPath "$WORK/dd"
mkdir -p "$WORK/ipa/Payload"
cp -R "$WORK/dd/Build/Products/Release-iphoneos/Yog-Sothoth's Echo.app" "$WORK/ipa/Payload/"
(cd "$WORK/ipa" && zip -qry ../YogSothothsEcho.ipa Payload)
```

兩邊共用的連線與協定程式碼在 `YogSothothsEcho/Packages/EchoKit`；Mac App 也依賴同一個套件，所以兩個 App 必須留在同一個 repo。

> **唱機圖片：**唱片、唱臂與背景圖片**不在** repo 裡，從源碼建置時會改畫簡單的後備圖形。公開的 `.ipa` 內含這些圖片——見[授權](#授權)。

## 疑難排解

2.0 版本透過統一日誌系統 (OSLog) 記錄，而不再寫入日誌檔案——舊版的 `~/Documents/Bjork/app_debug.log` 已不存在。要收集日誌：

```bash
log show --predicate 'subsystem == "com.ibridgezhao.azathothswhisper"' --last 1h --info
```

分類包括 `batch`、`coverflow` 和 `artwork-disk`；可用 `--predicate 'subsystem == "com.ibridgezhao.azathothswhisper" AND category == "batch"'` 縮小範圍。

這些日誌安全附在 issue 裡：Keychain 與設定程式碼路徑完全沒有日誌語句，因此您的 Genius token 永不涉及日誌。

**常見問題**

| 症狀 | 原因 | 解決方案 |
|---|---|---|
| 「應用程序已損壞，無法打開」 | 下載的 ad-hoc 簽名應用上的隔離標記 | `xattr -dr com.apple.quarantine "/Applications/Azathoth's Whisper.app"`，或系統設定 → 隱私權與安全性 → *仍要打開* |
| 無法檢測到播放曲目 | 未授予 Music 自動化權限 | 系統設定 → 隱私權與安全性 → 自動化 → 為此應用啟用 Music，然後重新啟動 |
| macOS 在更新後再次要求 Music 或 Keychain 存取權限 | Ad-hoc 簽名在每次編譯時改變，TCC 與 Keychain 都以程式碼簽名為鑰匙 | 預期行為——再次授予權限 |
| 永遠找不到歌詞 | 沒有 Genius token，或 token 無效 | 設定 → Genius Token 設定 |
| iPad 找不到 Mac | 中繼沒開、Mac 在別的網路，或 iPad 拒絕了區域網路存取 | 在 Remote Settings 開啟中繼；兩邊連同一個 Wi-Fi；iPad 設定 → 隱私權與安全性 → 區域網路 → Yog-Sothoth's Echo |
| iPad 說 Mac 需要你確認 | App 更新後鑰匙圈要再授權一次 | 在 Mac 的 Remote Settings 按 **Authorize on this Mac**，輸入密碼，選 **永遠允許** |
| 點的歌只播一首、沒接著播專輯 | 「YSE Play v1」捷徑不在 | Remote Settings → **Install Shortcut**（或 **Reinstall Shortcut**） |
| Genius 鈕是灰的 | Mac 上的 Music 沒開，或 iPad 沒連上 | 打開 Mac 上的 Music。（若 Genius 未在輔助使用中允許，按鈕仍可按，但只會說明如何允許） |

## 解除安裝

```bash
rm -rf "/Applications/Azathoth's Whisper.app"
rm -rf ~/Library/Caches/com.ibridgezhao.azathothswhisper      # 封面圖片快取
defaults delete com.ibridgezhao.azathothswhisper              # 語言 / UI 偏好
```

Genius token 存放在登入鑰匙圈中——打開 **鑰匙圈存取**，搜尋 `com.ibridgezhao.azathothswhisper`，然後刪除條目。中繼自己的身分（私鑰與自簽憑證）存在 `com.ibridgezhao.azathothswhisper.relay-identity` 底下。若用過 iPad 遙控，也請在「捷徑」App 刪除「YSE Play v1」，並到 系統設定 → 一般 → 登入項目 關掉登入時啟動。

iPad App 和其他 App 一樣，直接從 iPad 刪除即可。1.x 設定檔案（`~/.azathoths_whisper_config`）應用不會自動刪除；若不再需要請手動移除。

## 技術棧

*   **Swift 6 / SwiftUI**：核心邏輯與原生 UI（部署目標 macOS 14.0）。
*   **ScriptingBridge / Apple Events**：Music.app 自動化（讀當前曲目、讀寫歌詞、取封面）。
*   **SwiftSoup**：歌詞來源的 HTML 解析。
*   **XcodeGen**：`.xcodeproj` 由 `project.yml` 生成並已提交，所以純 clone 即可構建而無需安裝 XcodeGen。
*   **Keychain**：Genius token 儲存（自 1.x 的 `.env` ／設定檔自動遷移），以及中繼／iPad 的裝置身分。
*   **Network.framework**：Mac 中繼與 iPad 之間的 Bonjour 發現，以及雙向釘選憑證的 TLS 1.3（`YogSothothsEcho/Packages/EchoKit`）。
*   **iTunesLibrary**：唯讀讀取 Music 曲庫，供 iPad 的專輯清單使用。
*   **捷徑（Shortcuts）**：以「YSE Play v1」捷徑在專輯脈絡中播放曲目。
*   **VisionKit**：iPad 掃描 QR 碼。

> **2.0 是完整的原生重寫。** 1.x 的 Python／Tkinter／PyInstaller 實作保留在倉庫根目錄供參考；
> 實際出貨的應用程式完全由 `AzathothsWhisper/` 建置而成。

## 授權

MIT —— 見 [LICENSE](LICENSE)。

本應用程式內含以下第三方元件，其授權條款文字隨 App 一起分發
（位於 `Contents/Resources/`）：

| 元件 | 授權 |
|---|---|
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | MIT |
| Space Grotesk | SIL Open Font License 1.1 |
| Grimoire of Death, UnifrakturMaguntia, Cinzel, Cormorant Garamond | SIL Open Font License 1.1 |
| Abril Fatface, Alfa Slab One, Anton, Archivo Black, Bebas Neue, Bungee, Oswald, Playfair Display, Righteous | SIL Open Font License 1.1 |
| Bangers, Dela Gothic One, Gochi Hand, Lilita One, Rubik, Saira Stencil One | SIL Open Font License 1.1 |
| Barrio, Black Ops One, Space Mono | SIL Open Font License 1.1 |
| Courier Prime, IM Fell English SC, Shadows Into Light | SIL Open Font License 1.1 |
| Special Elite, Syncopate, Permanent Marker, Rock Salt | Apache License 2.0 |
| Catacombs（ToughCrest Studio） | 個人與商業用途免費；再散布須署名 ToughCrest Studio |
| Cenobyte（Chad Savage）、Mirage Gothic、Dark Metal | 商用條款未確認（Cenobyte 只寫「Freeware」；Mirage Gothic 內嵌「All rights reserved」；Dark Metal 無授權檔）。維護者自行承擔風險收錄 |
| Material Symbols | Apache License 2.0 |

iPad App（Yog-Sothoth's Echo）內含：

| 元件 | 授權 |
|---|---|
| Space Grotesk | SIL Open Font License 1.1 |
| 取自 **MD Vinyl** App 的唱機圖片（唱片、唱臂、底座、背景） | **不在本 repo 的授權範圍內**，權利屬於原作者。圖片不在 repo 裡，只包含在公開的 `.ipa` 中，由維護者自負風險 |

## 免責聲明

本項目僅供教育用途。獲取的歌詞版權歸其各自所有者所有。在大規模下載前請確認使用權利。

---
Created by [iBridgeZhao]
