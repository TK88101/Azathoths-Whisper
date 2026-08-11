#!/bin/zsh
# 覆蓋率門檻：Services/ + Infra/ 邏輯層 ≥ 80%（Plan §7；UI/App 膠水不進分母）
# 用法：./Scripts/coverage_gate.sh [xcresult 路徑]
#   不帶參數時自動跑 xcodebuild test 並檢查。
set -euo pipefail
cd "$(dirname "$0")/.."

RESULT="${1:-}"
if [[ -z "$RESULT" ]]; then
  RESULT="/tmp/azw_coverage.xcresult"
  rm -rf "$RESULT"
  xcodebuild test \
    -project AzathothsWhisper.xcodeproj \
    -scheme AzathothsWhisper \
    -destination 'platform=macOS' \
    -enableCodeCoverage YES \
    -resultBundlePath "$RESULT" \
    -quiet
fi

xcrun xccov view --report --json "$RESULT" > /tmp/azw_coverage.json

python3 - <<'PY'
import json, sys

THRESHOLD = 0.80
report = json.load(open("/tmp/azw_coverage.json"))
covered = executable = 0
rows = []
for target in report.get("targets", []):
    for f in target.get("files", []):
        path = f.get("path", "")
        if "/Tests/" in path:
            continue  # 測試自身不進分母
        if "/Services/" in path or "/Infra/" in path:
            covered += f.get("coveredLines", 0)
            executable += f.get("executableLines", 0)
            rows.append((f.get("lineCoverage", 0.0), path.split("/AzathothsWhisper/")[-1]))

if executable == 0:
    print("coverage gate: no Services/Infra files yet (M1 skeleton) — PASS (vacuous)")
    sys.exit(0)

ratio = covered / executable
for cov, p in sorted(rows):
    print(f"  {cov*100:6.1f}%  {p}")
print(f"coverage gate: Services+Infra = {ratio*100:.1f}% (threshold {THRESHOLD*100:.0f}%)")
sys.exit(0 if ratio >= THRESHOLD else 1)
PY
