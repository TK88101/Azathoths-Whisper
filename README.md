# Azathoth's Whisper (阿撒托斯的低語)

[**English**](README.md) | [**繁體中文**](README_ZH.md) | [**日本語**](README_JA.md)

**Azathoth's Whisper** is a macOS application that automatically fetches lyrics for the currently playing song in **iTunes** and embeds them directly into the audio file's custom lyrics metadata.

It supports multiple lyrics sources and features a dark-themed, localized user interface.

**New in 3.0 — an iPad remote.** This repository now builds two apps:

| App | Platform | Version | What it does |
|---|---|---|---|
| **Azathoth's Whisper** | macOS | 3.0.0 | The lyrics app above, plus an optional **relay** that lets the iPad control Music on this Mac |
| **Yog-Sothoth's Echo** (尤格·索托斯的回響) | iPad | 1.0.0 (pre-release) | A vinyl-turntable remote: browse your Mac's Music library and control playback from anywhere in the house |

The iPad app talks only to Azathoth's Whisper on your own Mac, over your home network. See
[iPad Remote: Yog-Sothoth's Echo](#ipad-remote-yog-sothoths-echo).

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
*   📱 **iPad Remote (3.0):** An optional relay serves your Music library and playback controls to the companion iPad app, Yog-Sothoth's Echo. Off by default.

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
      -format UDZO -ov "$WORK/Azathoths-Whisper-v3.0.0.dmg"
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

## iPad Remote: Yog-Sothoth's Echo

Yog-Sothoth's Echo turns an iPad into a turntable-style remote for Music on your Mac. The music
still plays **from the Mac** (its speakers, or whatever it outputs to); the iPad is only the
controller.

**What you can do on the iPad**

*   Browse every album in your Mac's Music library as 3D spines, or as a cover wall, with search.
*   Open an album and pick a track — the Mac plays it and continues with the rest of that album.
*   On the turntable screen, tap the record to pause or resume, and swipe left or right to skip.
*   Use the bottom capsule for previous / play-pause / next and **Genius** (Music's own Genius
    shuffle — unrelated to the Genius *lyrics* token above).
*   Choose a record style (Random, Classic, Transparent, Splash, Marble) and a light, dark or
    system appearance.

**Requirements**

*   An iPad on **iPadOS 18 or later**, on the same home network (Wi-Fi) as the Mac.
*   A Mac running **Azathoth's Whisper 3.0.0** with Music.app open.

### Installing the iPad app

The iPad app is published as a **pre-release** `.ipa` on the
[Releases page](https://github.com/TK88101/Azathoths-Whisper/releases). It is **not signed** and
not on the App Store, so you install it with a sideloading tool that signs it with your own
Apple ID, for example **SideStore**, **AltStore** or **iLoader**.

> With a free Apple ID, sideloaded apps expire after **7 days**. Re-sign / re-install it then
> (SideStore can do this automatically). Re-installing over the old copy keeps your pairing.

### First-time setup

On the **Mac** (Azathoth's Whisper 3.0.0):

1.  Open **Settings → Remote Settings…** and turn on
    **Allow Yog-Sothoth's Echo on iPad to control Music**. The relay is **off by default**.
2.  If you see a Keychain prompt, enter your Mac login password and choose **Always Allow**.
    This happens again after every update, because each build has a new ad-hoc signature.
3.  Under **Music Control**, click **Install Shortcut**, then **Add Shortcut** in the Shortcuts
    app. This installs the “YSE Play v1” shortcut that lets a picked track continue with the rest
    of its album. If Shortcuts asks about sharing, choose **Always Allow**.
4.  Allow the permissions the settings page asks for: **Automation → Music**, **Media & Apple
    Music** (to read the library), and — only if you want the Genius button — **Accessibility**.
5.  Optional: turn on **Open Azathoth's Whisper at login**, so the iPad can connect without you
    opening the app first.

Pairing:

1.  On the Mac, click **Pair new iPad**. A QR code appears for 60 seconds.
2.  Open Yog-Sothoth's Echo on the iPad and scan the code. Allow camera and local-network access
    when asked.
3.  The Mac shows an **Unverified device request** with 4 characters. Check that they match the
    ones on the iPad, then click **Allow**.

From then on the iPad reconnects automatically, also after the Mac sleeps or the app restarts.
To unpair, remove the iPad under **Paired iPads** on the Mac.

### Known limitations

*   Picking a track replaces Music's **Up Next** with that album from the chosen track onward.
    The previous queue is not saved or restored. Playback starts about 1.5 s after the tap.
*   Album playback relies on the “YSE Play v1” shortcut. If it is missing, or the album name is
    ambiguous, only the chosen track plays and the iPad tells you so.
*   Skipping quickly: each skip waits until the previous one has taken effect (about 1.5 s per
    track); more than 3 queued skips are refused.
*   No seeking and no volume control on the iPad. It works only on your home network.
*   Library changes reach the iPad within about a minute (the Mac re-checks the library every
    60 seconds).

### Privacy and security

*   The relay is off until you turn it on, and only accepts iPads you paired with a QR code
    **and** approved on the Mac.
*   Every connection is mutually authenticated TLS with pinned certificates, limited to the local
    network; requests are replay-protected and only a fixed set of commands is accepted.
*   On the Mac, the relay only **reads** the Music library and sends playback commands. It never
    edits the library and never writes Music's queue files. Accessibility is used solely to press
    Music's Genius menu item.
*   Logs contain IDs and error types only — no song titles, lyrics, tokens or pairing secrets.

### Building the iPad app from source

Requirements: **Xcode 16+** (Swift 6, iOS 18 SDK), XcodeGen. Built and verified with Xcode 27.

```bash
cd Azathoths-Whisper/YogSothothsEcho
xcodegen generate

# unit tests (any iPad simulator; adjust the name to one you have)
xcodebuild test -project YogSothothsEcho.xcodeproj -scheme YogSothothsEcho \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:YogSothothsEchoTests

# unsigned Release .ipa (sign it with your sideloading tool)
WORK="$(mktemp -d)"
xcodebuild build -project YogSothothsEcho.xcodeproj -scheme YogSothothsEcho -sdk iphoneos \
  -configuration Release CODE_SIGNING_ALLOWED=NO -derivedDataPath "$WORK/dd"
mkdir -p "$WORK/ipa/Payload"
cp -R "$WORK/dd/Build/Products/Release-iphoneos/Yog-Sothoth's Echo.app" "$WORK/ipa/Payload/"
(cd "$WORK/ipa" && zip -qry ../YogSothothsEcho.ipa Payload)
```

The shared networking and protocol code lives in `YogSothothsEcho/Packages/EchoKit`; the Mac app
builds against the same package, so both apps must stay in this repository together.

> **Turntable artwork:** the record, tonearm and background images are **not** in the repository.
> Builds from source draw simple fallback shapes instead. The published pre-release `.ipa`
> includes those images — see [License](#license).

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
| The iPad can't find the Mac | Relay off, Mac on a different network, or local-network access denied on the iPad | Turn the relay on in Remote Settings; put both on the same Wi-Fi; iPad Settings → Privacy & Security → Local Network → Yog-Sothoth's Echo |
| The iPad says the Mac needs your approval | The app was updated, so the Keychain asks again | On the Mac, Remote Settings → **Authorize on this Mac**, enter your password, **Always Allow** |
| A picked track plays alone instead of the whole album | The “YSE Play v1” shortcut is missing | Remote Settings → **Install Shortcut** (or **Reinstall Shortcut**) |
| The Genius button is greyed out | Music isn't open on the Mac, or the iPad is disconnected | Open Music on the Mac. (If Genius is not allowed in Accessibility, the button still works but only shows how to allow it) |

## Uninstall

```bash
rm -rf "/Applications/Azathoth's Whisper.app"
rm -rf ~/Library/Caches/com.ibridgezhao.azathothswhisper      # artwork disk cache
defaults delete com.ibridgezhao.azathothswhisper              # language / UI preferences
```

The Genius token lives in the login Keychain — open **Keychain Access**, search for
`com.ibridgezhao.azathothswhisper`, and delete the entry. The relay's own identity (a private key
and a self-signed certificate) is stored under `com.ibridgezhao.azathothswhisper.relay-identity`.
If you used the iPad remote, also delete the “YSE Play v1” shortcut in the Shortcuts app and turn
off the login item in System Settings → General → Login Items.

To remove the iPad app, delete it from the iPad like any other app. The 1.x configuration file
(`~/.azathoths_whisper_config`) is never deleted by the app; remove it manually if you no longer
need it.

## Technologies

*   **Swift 6 / SwiftUI**: Core logic and native UI (deployment target macOS 14.0).
*   **ScriptingBridge / Apple Events**: Music.app automation (read current track, read & write lyrics, fetch artwork).
*   **SwiftSoup**: HTML parsing for the lyrics sources.
*   **XcodeGen**: the `.xcodeproj` is generated from `project.yml` and committed, so a plain clone builds without XcodeGen installed.
*   **Keychain**: Genius token storage (migrated automatically from the 1.x `.env` / config file), and the relay / iPad device identities.
*   **Network.framework**: Bonjour discovery and TLS 1.3 with mutual certificate pinning between the Mac relay and the iPad (`YogSothothsEcho/Packages/EchoKit`).
*   **iTunesLibrary**: read-only access to the Music library for the iPad's album list.
*   **Shortcuts**: the “YSE Play v1” shortcut plays a track in its album context.
*   **VisionKit**: QR-code scanning on the iPad.

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
| Grimoire of Death, UnifrakturMaguntia, Cinzel, Cormorant Garamond | SIL Open Font License 1.1 |
| Abril Fatface, Alfa Slab One, Anton, Archivo Black, Bebas Neue, Bungee, Oswald, Playfair Display, Righteous | SIL Open Font License 1.1 |
| Bangers, Dela Gothic One, Gochi Hand, Lilita One, Rubik, Saira Stencil One | SIL Open Font License 1.1 |
| Barrio, Black Ops One, Space Mono | SIL Open Font License 1.1 |
| Courier Prime, IM Fell English SC, Shadows Into Light | SIL Open Font License 1.1 |
| Special Elite, Syncopate, Permanent Marker, Rock Salt | Apache License 2.0 |
| Catacombs (ToughCrest Studio) | Freeware for personal and commercial use; redistribution requires crediting ToughCrest Studio |
| Cenobyte (Chad Savage), Mirage Gothic, Dark Metal | Commercial-use terms not confirmed (Cenobyte: "Freeware"; Mirage Gothic: "All rights reserved" embedded; Dark Metal: no license file). Included at the maintainer's own risk |
| Material Symbols | Apache License 2.0 |

The iPad app (Yog-Sothoth's Echo) bundles:

| Component | License |
|---|---|
| Space Grotesk | SIL Open Font License 1.1 |
| Turntable images (record, tonearm, base, background) taken from the **MD Vinyl** app | **Not covered by this repository's license.** All rights belong to their owner. They are not in the repository; they are included only in the published pre-release `.ipa`, at the maintainer's own risk |

## Disclaimer

This project is for educational purposes only. Lyrics fetched are property of their respective owners. Please verify usage rights before mass downloading.

---
Created by [iBridgeZhao]
