#!/bin/zsh
# S4-P1 探針建置：build_s4probe.sh <輸出目錄>。ad-hoc 簽名；與 SpikeCore 同一模組編譯（不 import SpikeCore）。
set -euo pipefail
out=$1
here=${0:A:h}
app=$out/S4Probe.app
mkdir -p $app/Contents/MacOS
swiftc -O -o $app/Contents/MacOS/S4Probe $here/main.swift $here/../Sources/SpikeCore/{FP01,Playback,Verdicts}.swift -lsqlite3
cat > $app/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ibridgezhao.yse.s4probe</string>
<key>CFBundleName</key><string>S4Probe</string>
<key>CFBundleExecutable</key><string>S4Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$(date +%s)</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSAppleMusicUsageDescription</key><string>S4 probe reads your library to pick sample albums (read only).</string>
<key>NSAppleEventsUsageDescription</key><string>S4 probe reads Music's current track and state to time playback.</string>
</dict></plist>
PL
codesign --force --sign - $app
codesign -dv $app 2>&1 | grep -E "CDHash=|Identifier="
