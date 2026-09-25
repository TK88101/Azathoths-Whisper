# Azathoth's Whisper (阿撒托斯的低語)

[**English**](README.md) | [**繁體中文**](README_ZH.md) | [**日本語**](README_JA.md)

**Azathoth's Whisper** is a macOS application that automatically fetches lyrics for the currently playing song in **iTunes** and embeds them directly into the audio file's custom lyrics metadata.

It supports multiple lyrics sources and features a dark-themed, localized user interface.

## Features

*   🎵 **Auto-Sync:** Monitor iTunes and automatically fetch lyrics when the song changes.
*   📝 **Lyrics Embedding:** Writes lyrics directly to the music file (viewable in iTunes, iPhone, etc.).
*   🌍 **Multi-Source Support:**
    *   **Genius** (Requires API Token)
    *   **DarkLyrics** (fallback in **Batch mode only** — see below)

    > The single-track Fetch in the editor queries **Genius only**. DarkLyrics is consulted
    > solely by Batch mode's *Fetch Missing*, when Genius returns no match for a track.

    > **Note on sources in 2.0:** earlier READMEs also listed *Metal Archives* and *Musixmatch*.
    > Neither was ever implemented — not even in the 1.x Python version. (1.x did show a
    > "MetalArchives" entry in its source dropdown, but that control was never wired to anything:
    > selecting it had no effect.) 2.0 lists the two sources that actually exist.
    > **No functionality was removed.**
*   🌐 **Multi-Language UI:** Fully localized in **English**, **Traditional Chinese**, and **Japanese**.
*   🌑 **Dark Mode:** A sleek, modern dark interface.
*   ⚙️ **Smart Config:** Remembers your Genius Token and Language preferences.
*   🍎 **macOS Native:** Written in Swift 6 / SwiftUI. Respects system language settings and integrates with Music.app via Apple Events.
*   📚 **Batch Mode:** Review a whole album at once — fetch missing lyrics and import them in bulk.
*   🖼 **Cover Flow:** Browse the current album's artwork in a 3D carousel (display only — no playback controls).

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
   - Download the latest `.dmg` from the Releases page
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

Requirements: **macOS 14.0+**, **Xcode 16+** (Swift 6), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

> Built and verified on macOS 26.6 / Xcode 26.6 / Swift 6.3. The lower bounds above follow from
> `project.yml` (`deploymentTarget: 14.0`, `SWIFT_VERSION: 6.0`) and have not been tested directly.

1.  **Clone the repository**
    ```bash
    git clone https://github.com/TK88101/Azathoths-Whisper.git
    cd Azathoths-Whisper/AzathothsWhisper
    ```

2.  **Install XcodeGen**
    ```bash
    brew install xcodegen
    ```

3.  **Generate the Xcode project**
    ```bash
    xcodegen generate
    ```
    The `.xcodeproj` is generated from `project.yml` **and committed**, so a fresh clone builds
    without XcodeGen. You only need this step after adding or removing a source file — Xcode
    otherwise silently keeps building the old file list. Commit the regenerated project along
    with your change. SwiftSoup is resolved by Swift Package Manager on the first build.

4.  **Run the tests**
    ```bash
    xcodebuild test -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper \
      -destination 'platform=macOS' -only-testing:AzathothsWhisperTests \
      -test-timeouts-enabled YES -default-test-execution-time-allowance 120
    ```
    UI tests (`-only-testing:AzathothsWhisperUITests`) additionally require Accessibility
    permission for Xcode in **System Settings → Privacy & Security → Accessibility**.

5.  **Build a Release app**
    ```bash
    WORK="$(mktemp -d)"
    xcodebuild build -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper \
      -configuration Release -destination 'platform=macOS' -derivedDataPath "$WORK/dd"
    ```
    The result is signed **ad-hoc** (`CODE_SIGN_IDENTITY: "-"`), which is why downloaded builds
    need the quarantine step described under *Installation* above.

6.  **Create the DMG**

    The disk image reuses the window layout shipped in `packaging/`, so the **layout** is
    reproducible and no Finder scripting (and no automation prompt) is involved:

    ```bash
    # $WORK is from step 5; re-declare it if you are in a new shell
    APP="$WORK/dd/Build/Products/Release/Azathoth's Whisper.app"
    STAGING="$WORK/staging"; mkdir -p "$STAGING"

    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    cp ../packaging/dmg-layout.DS_Store "$STAGING/.DS_Store"
    cp ../dmg_background.png "$STAGING/"
    chflags hidden "$STAGING/dmg_background.png"

    hdiutil create -volname "Azathoth's Whisper" -srcfolder "$STAGING" \
      -format UDZO -ov "$WORK/Azathoths-Whisper-v2.0.1.dmg"
    ```

    The volume name and the item names must stay exactly as above — the `.DS_Store` resolves the
    background image and the icon positions **by name**. (The `.dmg` file itself is not
    byte-for-byte reproducible across runs; only the layout is.)

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

## Troubleshooting

Version 2.0 logs through the unified logging system (OSLog) instead of writing a log file — the
1.x `~/Documents/Bjork/app_debug.log` no longer exists. To collect logs:

```bash
log show --predicate 'subsystem == "com.ibridgezhao.azathothswhisper"' --last 1h --info
```

Categories are `batch`, `coverflow`, and `artwork-disk`; narrow down with
`--predicate 'subsystem == "com.ibridgezhao.azathothswhisper" AND category == "batch"'`.

These logs are safe to attach to an issue: the Keychain and configuration code paths emit no log
statements at all, so your Genius token never reaches them.

**Common problems**

| Symptom | Cause | Fix |
|---|---|---|
| "App is damaged and can't be opened" | Quarantine flag on a downloaded, ad-hoc signed app | `xattr -dr com.apple.quarantine "/Applications/Azathoth's Whisper.app"`, or System Settings → Privacy & Security → *Open Anyway* |
| No track is detected | Automation permission for Music was denied | System Settings → Privacy & Security → Automation → enable Music for this app, then relaunch |
| macOS asks for Music or Keychain access again after an update | Ad-hoc signatures change on every build, and both TCC and the Keychain key off the code signature | Expected — grant it again |
| Lyrics are never found | No Genius token, or the token is invalid | Settings → Genius Token Settings |

## Uninstall

```bash
rm -rf "/Applications/Azathoth's Whisper.app"
rm -rf ~/Library/Caches/com.ibridgezhao.azathothswhisper      # artwork disk cache
defaults delete com.ibridgezhao.azathothswhisper              # language / UI preferences
```

The Genius token lives in the login Keychain — open **Keychain Access**, search for
`com.ibridgezhao.azathothswhisper`, and delete the entry. The 1.x configuration file
(`~/.azathoths_whisper_config`) is never deleted by the app; remove it manually if you no longer
need it.

## Technologies

*   **Swift 6 / SwiftUI**: Core logic and native UI (deployment target macOS 14.0).
*   **ScriptingBridge / Apple Events**: Music.app automation (read current track, read & write lyrics, fetch artwork).
*   **SwiftSoup**: HTML parsing for the lyrics sources.
*   **XcodeGen**: the `.xcodeproj` is generated from `project.yml` and committed, so a plain clone builds without XcodeGen installed.
*   **Keychain**: Genius token storage (migrated automatically from the 1.x `.env` / config file).

> **Version 2.0 is a full native rewrite.** The 1.x Python/Tkinter/PyInstaller implementation is
> kept in the repository root for reference; the shipping app is built entirely from `AzathothsWhisper/`.

## License

MIT — see [LICENSE](LICENSE).

The app bundles third-party components, whose license texts ship inside the app
(`Contents/Resources/`):

| Component | License |
|---|---|
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | MIT |
| Space Grotesk | SIL Open Font License 1.1 |
| Material Symbols | Apache License 2.0 |

## Disclaimer

This project is for educational purposes only. Lyrics fetched are property of their respective owners. Please verify usage rights before mass downloading.

---
Created by [iBridgeZhao]
