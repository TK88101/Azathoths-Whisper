# Azathoth's Whisper (阿撒托斯的低語)

[**English**](README.md) | [**繁體中文**](README_ZH.md) | [**日本語**](README_JA.md)

**Azathoth's Whisper** 是一個 macOS 應用程序，可以自動獲取目前在 **iTunes** 中播放歌曲的歌詞，並將其直接嵌入到音頻文件的自定義歌詞元數據中。

它支持多種歌詞來源，並具有深色主題和多語言用戶界面。

## 功能

*   🎵 **自動同步：** 監控 iTunes 並在切換歌曲時自動獲取歌詞。
*   📝 **歌詞寫入：** 將歌詞直接寫入音樂文件（可在 iTunes、iPhone 等設備上查看）。
*   🌍 **多來源支持：**
    *   **Genius** (需要 API Token)
    *   **Metal Archives** (非常適合重金屬音樂)
    *   **DarkLyrics**
    *   **Musixmatch** (備用)
*   🌐 **多語言界面：** 完全支持 **英文**、**繁體中文** 和 **日文**。
*   🌑 **深色模式：** 時尚現代的深色界面。
*   ⚙️ **智能配置：** 記住您的 Genius Token 和語言偏好。
*   🍎 **macOS 原生支持：** 遵循系統語言設置，專為 iTunes 優化。

## 安裝

### 預編譯應用程序 (DMG)

從 [GitHub Releases](https://github.com/TK88101/Azathoths-Whisper/releases) 下載最新版本。

**⚠️ 重要：macOS 首次安裝說明**

由於此應用未經 Apple Developer ID 簽名，macOS Gatekeeper 會阻止運行。您很可能會看到錯誤提示：**「應用程序已損壞，無法打開」**。這是安全功能，並非真的損壞。

**安裝步驟：**

1. **下載並掛載 DMG**
   - 下載 `Azathoths-Whisper-v1.0.1.dmg`
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
要求：Python 3.10+, macOS。

1.  **克隆倉庫**
    ```bash
    git clone https://github.com/TK88101/Azathoths-Whisper.git
    cd Azathoths-Whisper
    ```

2.  **設置虛擬環境**
    ```bash
    python3 -m venv venv
    source venv/bin/activate
    ```

3.  **安裝依賴**
    ```bash
    pip install -r requirements.txt
    # 或者手動安裝：
    pip install requests beautifulsoup4 lyricsgenius appscript pyinstaller pillow
    ```

4.  **本地運行**
    ```bash
    python lyrics_fetcher.py
    ```

5.  **構建 .app 應用包** (完整發布版)
    ```bash
    # 1. 清理舊的構建文件
    rm -rf build/ dist/

    # 2. 運行 PyInstaller
    pyinstaller Azathoths_Whisper.spec --clean
    
    # 3. 創建本地化文件夾 (對於 macOS 語言檢測至關重要)
    mkdir -p "dist/Azathoth's Whisper.app/Contents/Resources/en.lproj"
    mkdir -p "dist/Azathoth's Whisper.app/Contents/Resources/zh_TW.lproj"
    mkdir -p "dist/Azathoth's Whisper.app/Contents/Resources/ja.lproj"
    
    # 4. 添加虛擬本地化文件
    touch "dist/Azathoth's Whisper.app/Contents/Resources/en.lproj/Localizable.strings"
    touch "dist/Azathoth's Whisper.app/Contents/Resources/zh_TW.lproj/Localizable.strings"
    touch "dist/Azathoth's Whisper.app/Contents/Resources/ja.lproj/Localizable.strings"
    ```

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

## 技術棧

*   **Python**: 核心邏輯。
*   **Tkinter**: GUI 框架。
*   **Appscript**: macOS iTunes 自動化控制。
*   **PyInstaller**: 應用程序打包。

## 免責聲明

本項目僅供教育用途。獲取的歌詞版權歸其各自所有者所有。在大規模下載前請確認使用權利。

---
Created by [iBridgeZhao]
