"""D2 量測的逐筆對應（S4 #4-1；sprint-4-detail.md §4.12、附錄 E thecure 收斂）。

輸入：
  --log       `log stream --style ndjson` 的錄製檔：旁聽工具（subsystem yse.d2）的 mouse-down／key-down（媒體鍵），
              與 Azathoth DEBUG 的 relay-measure 到達紀錄（kind、limit、請求 ID、連線 ID）
  --receipts  iPad 寫出的 control-d2-*.json（每筆回條的請求 ID、事件狀態、曲目序號）
規則（每次滑鼠按下＝一次試行）：
  ① 只看「請求 ID 在 iPad 回條紀錄裡」的到達（別的請求、一般清單一律不算）；狀態與曲目序號都跟前一筆回條相同者
     （定時校正等無變化的推送）略過
  ② 按下前 3 s 內有回條到達＝無效（not-quiet）
  ③ 按下後 5 s 內：沒有回條＝無效（no-receipt）；兩筆以上＝無效（multiple）
  ④ 該回條的事件要反映操作：由播放變暫停＝pause；曲目序號改變＝change；都不是＝無效（event-not-reflecting）
  ⑤ 延遲＝按下 → 回條到達（同一台 Mac 的單調時間戳），必為「Mac 操作 → iPad 收到」的上界
判定：pause、change 各至少 10 筆有效，且每一筆都 ≤ 2000 ms 才達標；另報 nearest-rank p95。
用法：python3 -I Scripts/d2_pair.py --log d2.ndjson --receipts control-d2-XXXX.json；未達標退出 1。
"""
import json
import math
import pathlib
import re
import sys
from dataclasses import dataclass, field

TICKS_PER_SECOND = 24_000_000  # machTimestamp：1 tick＝125/3 ns（Apple Silicon）
QUIET_SECONDS = 3.0
WINDOW_SECONDS = 5.0
LIMIT_MS = 2000.0
REQUIRED_PER_CATEGORY = 10
ARRIVAL = re.compile(r"arrival kind=catalog\.page limit=1 id=(\S+) conn=(\S+)")


@dataclass(frozen=True)
class Trial:
    category: str
    latency_ms: float
    valid: bool
    reason: str


@dataclass(frozen=True)
class Verdict:
    passed: bool
    counts: dict = field(default_factory=dict)
    p95: dict = field(default_factory=dict)
    worst: dict = field(default_factory=dict)
    invalid: dict = field(default_factory=dict)


def seconds(entry):
    return entry["machTimestamp"] / TICKS_PER_SECOND


def load_log(path):
    entries = []
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue  # log stream 開頭的說明行等
        if isinstance(entry, dict) and "machTimestamp" in entry and "eventMessage" in entry:
            entries.append(entry)
    return entries


def load_receipts(path):
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))["receipts"]


def classify(receipt, previous):
    if previous is None:
        return None
    if previous["state"] == "playing" and receipt["state"] == "paused":
        return "pause"
    if receipt["trackOrdinal"] != previous["trackOrdinal"]:
        return "change"
    return None


def pair(entries, receipts):
    by_id = {r["requestID"]: r for r in receipts}
    by_seq = {r["seq"]: r for r in receipts}
    # 試行起點＝滑鼠左鍵按下，或媒體鍵（F8 播放／暫停、F9 下一首）按下（#4-1 實測：使用者以鍵盤操作）
    clicks = sorted(seconds(e) for e in entries if e.get("subsystem") == "yse.d2"
                    and e["eventMessage"].startswith(("mouse-down", "key-down")))
    arrivals = []
    for e in entries:
        match = ARRIVAL.search(e["eventMessage"])
        if match and match.group(1) in by_id:
            receipt = by_id[match.group(1)]
            previous = by_seq.get(receipt["seq"] - 1)
            # 狀態與曲目都跟前一筆一樣＝定時校正等無變化的推送，不可能是操作的反應：不計入靜穏與多筆判定（#4-1 實測）
            if previous and previous["state"] == receipt["state"] and previous["trackOrdinal"] == receipt["trackOrdinal"]:
                continue
            arrivals.append((seconds(e), receipt))
    arrivals.sort(key=lambda item: item[0])
    trials = []
    for click in clicks:
        if any(click - QUIET_SECONDS < at < click for at, _ in arrivals):
            trials.append(Trial("", math.nan, False, "not-quiet"))
            continue
        after = [(at, r) for at, r in arrivals if click <= at <= click + WINDOW_SECONDS]
        if not after:
            trials.append(Trial("", math.nan, False, "no-receipt"))
            continue
        if len(after) > 1:
            trials.append(Trial("", math.nan, False, "multiple"))
            continue
        at, receipt = after[0]
        category = classify(receipt, by_seq.get(receipt["seq"] - 1))
        if category is None:
            trials.append(Trial("", math.nan, False, "event-not-reflecting"))
            continue
        trials.append(Trial(category, (at - click) * 1000, True, ""))
    return trials


def nearest_rank(values, p):
    ordered = sorted(values)
    rank = max(1, math.ceil(p * len(ordered) - 1e-9))
    return ordered[min(rank, len(ordered)) - 1]


def summarize(trials):
    counts, p95, worst, invalid = {}, {}, {}, {}
    passed = True
    for category in ("pause", "change"):
        values = [t.latency_ms for t in trials if t.valid and t.category == category]
        counts[category] = len(values)
        if values:
            p95[category] = nearest_rank(values, 0.95)
            worst[category] = max(values)
        if len(values) < REQUIRED_PER_CATEGORY or (values and max(values) > LIMIT_MS):
            passed = False
    for t in trials:
        if not t.valid:
            invalid[t.reason] = invalid.get(t.reason, 0) + 1
    return Verdict(passed, counts, p95, worst, invalid)


def main(argv):
    log = argv[argv.index("--log") + 1]
    receipts = argv[argv.index("--receipts") + 1]
    trials = pair(load_log(log), load_receipts(receipts))
    for index, t in enumerate(trials, 1):
        print(f"{index:3d} {t.category or '-':7s} " + (f"{t.latency_ms:8.1f} ms" if t.valid else f"無效（{t.reason}）"))
    verdict = summarize(trials)
    print(f"有效筆數：{verdict.counts}；p95：{verdict.p95}；最慢：{verdict.worst}；無效：{verdict.invalid}")
    print("D2：達標" if verdict.passed else "D2：未達標（每類需 ≥ 10 筆有效且逐筆 ≤ 2000 ms）")
    return 0 if verdict.passed else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
