# Azathoth's Whisper (阿撒托斯的低語)

[**English**](README.md) | [**繁體中文**](README_ZH.md) | [**日本語**](README_JA.md)

**Azathoth's Whisper** 是一個 macOS 應用程序，可以自動獲取目前在 **iTunes** 中播放歌曲的歌詞，並將其直接嵌入到音頻文件的自定義歌詞元數據中。

它支持多種歌詞來源，並具有深色主題和多語言用戶界面。

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
      -format UDZO -ov "$WORK/Azathoths-Whisper-v2.0.0.dmg"
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

## 解除安裝

```bash
rm -rf "/Applications/Azathoth's Whisper.app"
rm -rf ~/Library/Caches/com.ibridgezhao.azathothswhisper      # 封面圖片快取
defaults delete com.ibridgezhao.azathothswhisper              # 語言 / UI 偏好
```

Genius token 存放在登入鑰匙圈中——打開 **鑰匙圈存取**，搜尋 `com.ibridgezhao.azathothswhisper`，然後刪除條目。1.x 設定檔案（`~/.azathoths_whisper_config`）應用不會自動刪除；若不再需要請手動移除。

## 技術棧

*   **Swift 6 / SwiftUI**：核心邏輯與原生 UI（部署目標 macOS 14.0）。
*   **ScriptingBridge / Apple Events**：Music.app 自動化（讀當前曲目、讀寫歌詞、取封面）。
*   **SwiftSoup**：歌詞來源的 HTML 解析。
*   **XcodeGen**：`.xcodeproj` 由 `project.yml` 生成並已提交，所以純 clone 即可構建而無需安裝 XcodeGen。
*   **Keychain**：Genius token 儲存（自 1.x 的 `.env` ／設定檔自動遷移）。

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
| Material Symbols | Apache License 2.0 |

## 免責聲明

本項目僅供教育用途。獲取的歌詞版權歸其各自所有者所有。在大規模下載前請確認使用權利。

---
Created by [iBridgeZhao]
