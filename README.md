# Azathoth's Whisper (阿撒托斯的低語)

[**English**](README.md) | [**繁體中文**](README_ZH.md) | [**日本語**](README_JA.md)

**Azathoth's Whisper** is a macOS application that automatically fetches lyrics for the currently playing song in **iTunes** and embeds them directly into the audio file's custom lyrics metadata.

It supports multiple lyrics sources and features a dark-themed, localized user interface.

## Features

*   🎵 **Auto-Sync:** Monitor iTunes and automatically fetch lyrics when the song changes.
*   📝 **Lyrics Embedding:** Writes lyrics directly to the music file (viewable in iTunes, iPhone, etc.).
*   🌍 **Multi-Source Support:**
    *   **Genius** (Requires API Token)
    *   **Metal Archives** (Great for heavy metal)
    *   **DarkLyrics**
    *   **Musixmatch** (Fallback)
*   🌐 **Multi-Language UI:** Fully localized in **English**, **Traditional Chinese**, and **Japanese**.
*   🌑 **Dark Mode:** A sleek, modern dark interface.
*   ⚙️ **Smart Config:** Remembers your Genius Token and Language preferences.
*   🍎 **macOS Native Support:** Respects system language settings and specialized iTunes integration.

## Prerequisites

**🔑 Genius API Token (Required)**

To fetch lyrics, you'll need a free Genius API token:

1. Visit [genius.com/api-clients](https://genius.com/api-clients/)
2. Sign in or create an account
3. Click **"New API Client"**
4. Fill in the required info (App Name, App Website URL - can be anything)
5. Copy your **Client Access Token**
6. Paste it into the app's Settings on first launch

> **Note:** The Token is completely free and takes less than 2 minutes to get.

## Installation

### Pre-built App (DMG)

Download the latest release from [GitHub Releases](https://github.com/TK88101/Azathoths-Whisper/releases).

**⚠️ Important: First-time Installation on macOS**

Since this app is not signed with an Apple Developer ID, macOS Gatekeeper will block it. You'll likely see an error saying **"App is damaged and can't be opened"**. This is a security feature, not actual damage.

**Installation Steps:**

1. **Download and Mount DMG**
   - Download `Azathoths-Whisper-v1.0.1.dmg`
   - Double-click to mount it

2. **Install the App**
   - Drag `Azathoth's Whisper.app` to the **Applications** folder shortcut in the DMG window

3. **Remove Quarantine Flag (Required for Downloaded Apps)**
   
   Open **Terminal** (Applications → Utilities → Terminal) and run:
   ```bash
   xattr -d com.apple.quarantine /Applications/Azathoth\'s\ Whisper.app
   ```
   
   This removes the macOS quarantine attribute that causes the "damaged" error.

4. **Open the App**
   
   Now you can open it normally:
   - **Option A**: Double-click the app in Applications folder
   - **Option B**: Right-click → Open (if still prompted)
   
   ✅ The app will run. macOS will remember your choice for future launches.

5. **Grant Automation Permissions**
   - On first launch, you'll be asked to grant permission to control iTunes
   - Click **"OK"** to allow

**Why does this happen?**
- macOS adds a "quarantine" flag to all apps downloaded from the internet
- Apps without Apple Developer signatures are marked as "damaged" with this flag
- Removing the flag allows the app to run normally

### Build from Source
Requirements: Python 3.10+, macOS.

1.  **Clone the repository**
    ```bash
    git clone https://github.com/TK88101/Azathoths-Whisper.git
    cd Azathoths-Whisper
    ```

2.  **Set up Virtual Environment**
    ```bash
    python3 -m venv venv
    source venv/bin/activate
    ```

3.  **Install Dependencies**
    ```bash
    pip install -r requirements.txt
    # OR manual install:
    pip install requests beautifulsoup4 lyricsgenius appscript pyinstaller pillow
    ```

4.  **Run Locally**
    ```bash
    python lyrics_fetcher.py
    ```

5.  **Build .app Bundle** (Full Release Build)
    ```bash
    # 1. Clear previous builds
    rm -rf build/ dist/

    # 2. Run PyInstaller
    pyinstaller Azathoths_Whisper.spec --clean
    
    # 3. Create localization folders (Crucial for macOS language detection)
    mkdir -p "dist/Azathoth's Whisper.app/Contents/Resources/en.lproj"
    mkdir -p "dist/Azathoth's Whisper.app/Contents/Resources/zh_TW.lproj"
    mkdir -p "dist/Azathoth's Whisper.app/Contents/Resources/ja.lproj"
    
    # 4. Add dummy localization files
    touch "dist/Azathoth's Whisper.app/Contents/Resources/en.lproj/Localizable.strings"
    touch "dist/Azathoth's Whisper.app/Contents/Resources/zh_TW.lproj/Localizable.strings"
    touch "dist/Azathoth's Whisper.app/Contents/Resources/ja.lproj/Localizable.strings"
    ```

## Usage

1.  **Launch the App**: Open Azathoth's Whisper.
2.  **Genius Token**:
    *   On first run, go to `Settings` -> `Genius Token Settings`.
    *   Paste your **Genius Client Access Token** (Get one at [genius.com/api-clients](https://genius.com/api-clients)).
    *   Click Save.
3.  **Play Music**: Start playing a song in iTunes.
4.  **Fetch**:
    *   **Auto Mode**: The app will detect the song and try to find lyrics automatically.
    *   **Manual**: Click "Fetch Lyrics" to force a search.
5.  **Language**: Change interface language via `Settings` -> `Language Settings`.

## Technologies

*   **Python**: Core logic.
*   **Tkinter**: GUI framework.
*   **Appscript**: macOS iTunes automation.
*   **PyInstaller**: Application packaging.

## Disclaimer

This project is for educational purposes only. Lyrics fetched are property of their respective owners. Please verify usage rights before mass downloading.

---
Created by [iBridgeZhao]
