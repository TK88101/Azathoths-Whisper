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

## Installation

### Pre-built App
If you have the `.app` bundle:
1. Drag `Azathoth's Whisper.app` to your **Applications** folder.
2. Open the app. You may need to grant **Automation Permissions** for it to control iTunes.

### Build from Source
Requirements: Python 3.10+, macOS.

1.  **Clone the repository**
    ```bash
    git clone https://github.com/yourusername/azathoths-whisper.git
    cd azathoths-whisper
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
