#!/bin/zsh
# 覆蓋率門檻：app 本體的 Services/ + Infra/ 邏輯層 ≥ 80%（Plan §7；UI/App 膠水不進分母）
# 用法：./Scripts/coverage_gate.sh [xcresult 路徑 | xccov JSON 報表路徑]
#   不帶參數時自動跑 xcodebuild test 並檢查；參數以 .json 結尾時直接讀該報表（測試用，見 test_coverage_gate.py）。
# 豁免清單與護欄見下方 EXEMPTIONS（計劃 2026-09-23-coverflow-queue-drawer.md §14 R8）。
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

if [[ "$RESULT" == *.json ]]; then
  REPORT="$RESULT"
else
  REPORT="/tmp/azw_coverage.json"
  xcrun xccov view --report --json "$RESULT" > "$REPORT"
fi

AZW_COVERAGE_REPORT="$REPORT" python3 - <<'PY'
import json, os, sys

THRESHOLD = 0.80
PRODUCT_TARGET = "Azathoth's Whisper.app"
LAYERS = ("Services/", "Infra/")
# 豁免：只收「單元測試刻意碰不到」的外部境界。每筆必附理由與使用者批准日；
# 路徑為相對專案根目錄的完全一致比對，且必須在 app 本體恰好出現一次、有可執行行。
EXEMPTIONS = [
    {
        "path": "Services/Music/MusicAppleEventsClient.swift",
        "reason": "ScriptingBridge boundary; unit host never talks to the real Music (D11). "
                  "Behaviour covered by MusicControlling mocks, AC9 selector allow-list, manual LiveMusicTests smoke",
        "approvedOn": "2026-09-23",
    },
]
EXEMPT_LINE_BUDGET = 400   # 豁免檔可執行行數合計上限（批准時 384）；調高須經評審並記入計劃

root = os.path.realpath(os.getcwd())
report = json.load(open(os.environ["AZW_COVERAGE_REPORT"]))


def relative(path):
    real = os.path.realpath(path)
    return os.path.relpath(real, root) if real.startswith(root + os.sep) else None


product_files = []
for target in report.get("targets", []):
    if target.get("name") != PRODUCT_TARGET:
        continue  # 測試 target 裡的檔案不進分子分母
    for f in target.get("files", []):
        rel = relative(f.get("path", ""))
        if rel and rel.startswith(LAYERS):
            product_files.append((rel, f.get("coveredLines", 0), f.get("executableLines", 0)))

failures = []
exempt_paths = {e["path"] for e in EXEMPTIONS}
exempt_rows = []
for exemption in EXEMPTIONS:
    matches = [row for row in product_files if row[0] == exemption["path"]]
    if not matches:
        failures.append(f"exemption not found in {PRODUCT_TARGET}: {exemption['path']}")
    elif len(matches) > 1:
        failures.append(f"exemption matched {len(matches)} files: {exemption['path']}")
    elif matches[0][2] == 0:
        failures.append(f"exemption has no executable lines: {exemption['path']}")
    exempt_rows += [(row, exemption) for row in matches]

exempt_lines = sum(row[2] for row, _ in exempt_rows)
if exempt_lines > EXEMPT_LINE_BUDGET:
    failures.append(f"exempted executable lines {exempt_lines} exceed budget {EXEMPT_LINE_BUDGET}")


def ratio(rows):
    covered = sum(r[1] for r in rows)
    executable = sum(r[2] for r in rows)
    return covered, executable, (covered / executable if executable else 0.0)


judged = [row for row in product_files if row[0] not in exempt_paths]
for rel, covered, executable in sorted(judged, key=lambda r: (r[1] / r[2] if r[2] else 0.0, r[0])):
    print(f"  {(covered / executable if executable else 0.0) * 100:6.1f}%  {rel}")
for (rel, covered, executable), exemption in exempt_rows:
    pct = covered / executable * 100 if executable else 0.0
    print(f"  EXEMPT {pct:5.1f}% ({covered}/{executable})  {rel} — {exemption['reason']} — approved {exemption['approvedOn']}")

c_all, e_all, r_all = ratio(product_files)
print(f"Services+Infra before exemptions = {r_all * 100:.1f}% ({c_all}/{e_all})")
for message in failures:
    print(f"coverage gate: FAIL — {message}")

c, e, r = ratio(judged)
if e == 0:
    print("coverage gate: no Services/Infra files yet (M1 skeleton) — PASS (vacuous)")
    sys.exit(1 if failures else 0)
print(f"coverage gate: Services+Infra = {r * 100:.1f}% ({c}/{e}) "
      f"(threshold {THRESHOLD * 100:.0f}%; exemptions {len(exempt_rows)} file(s) / {exempt_lines} lines, budget {EXEMPT_LINE_BUDGET})")
sys.exit(0 if r >= THRESHOLD and not failures else 1)
PY
