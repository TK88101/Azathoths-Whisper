#!/bin/zsh
# S6.5 T8：重錄連線頁渲染基準圖。用法：Scripts/record_snapshots.sh
# 測試把新圖寫到腳本自建的暫存目錄（app 宿主測試寫不進 repo；不接受外部路徑，避免誤刪），再複製進 Tests/Snapshots/。
# xcodebuild 會把 TEST_RUNNER_ 前綴去掉後傳給測試行程，測試讀的是 PAIRING_SNAPSHOT_DIR。入庫前先給使用者看。
set -eu
out=$(mktemp -d "${TMPDIR:-/tmp}/pairing-snapshots.XXXXXX")
cd "${0:A:h}/.."
TEST_RUNNER_PAIRING_SNAPSHOT_DIR="$out" xcodebuild test -project YogSothothsEcho.xcodeproj -scheme YogSothothsEcho \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:YogSothothsEchoTests/PairingSnapshotTests \
  -resultBundlePath "$out/record.xcresult" > "$out/record.log" 2>&1 || true
count=$(ls "$out"/*.png 2>/dev/null | wc -l | tr -d ' ')
[[ $count -gt 0 ]] || { echo "沒有產生新圖（看 $out/record.log）" >&2; exit 1; }
cp "$out"/*.png Tests/Snapshots/
echo "已複製 $count 張到 Tests/Snapshots/（暫存：$out）"
