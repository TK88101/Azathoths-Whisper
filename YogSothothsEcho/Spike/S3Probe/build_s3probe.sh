#!/bin/zsh
# S3-P1 探針建置：build_s3probe.sh <輸出目錄> <變體 nokey|key|deny>
# 變體各用不同 bundle id，互不污染 TCC 紀錄；key／deny 帶 NSAppleMusicUsageDescription。ad-hoc 簽名（同 Azathoth）。
# 同一路徑重建時直接覆寫（每次 CFBundleVersion 不同，CDHash 必變，用於 P1-b）。
set -euo pipefail
out=$1; variant=$2
here=${0:A:h}
app=$out/S3Probe-$variant.app
mkdir -p $app/Contents/MacOS
swiftc -O -o $app/Contents/MacOS/S3Probe $here/S3Probe.swift
usage=""
if [[ $variant != nokey ]]; then
  usage="<key>NSAppleMusicUsageDescription</key><string>S3 probe reads your music library to count albums (read only).</string>"
fi
cat > $app/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ibridgezhao.yse.s3probe.$variant</string>
<key>CFBundleName</key><string>S3Probe-$variant</string>
<key>CFBundleExecutable</key><string>S3Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$(date +%s)</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
$usage
</dict></plist>
PL
codesign --force --sign - $app
codesign -dv $app 2>&1 | grep -E "CDHash=|Identifier="
