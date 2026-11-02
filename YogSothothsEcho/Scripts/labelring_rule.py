#!/usr/bin/env python3
"""CR-039 D.8 事先登錄的 LabelRing 分流規則——凍結版（yse-g7-hitch-fix.md §11.5 B6；D.9 r5、D.10 r6-②）。

規則（量測前寫定、看資料後不改）：分母＝YSE 行程主執行緒、時間落在 G7 動畫段的全部取樣；LabelRing＝stack 含
LabelRing Canvas 閉包；app 子樹候選＝離開進入點後第一個 YSE frame（LabelRing 祖先不競爭、子孫併入）；
eligible＝(a) 前 3 次轉場合計 LabelRing ≥ 25% 且 (b) ≥2 次 LabelRing 是最大 app 子樹並 ≥1.5 倍第二大（比原始權重）
且 (c) ≥2 次至少 1 筆 LabelRing 取樣落在 hitches-updates > 8.33 ms 的幀內。
驗證（任一失敗＝判不出，exit 2 並印「無效」）：主執行緒 PID 唯一；signpost 只取 subsystem＋category＋name 相符的列；
時間基準——取樣涵蓋全部登錄轉場、每個登錄動畫段至少 1 筆取樣。

用法（在 YogSothothsEcho/Scripts 下；xctrace 匯出包 alarm）：
  python3 -I labelring_rule.py analyze <trace> <time-profile.xml> <dSYM 內的 DWARF 檔>   # B9：實機 trace 直接判
  python3 -I labelring_rule.py extract <trace> <time-profile.xml> <DWARF> <out.json>     # 產生縮小 fixture
  python3 -I labelring_rule.py fixture <fixture.json>                                    # 從 fixture 重算（測試用）
time-profile.xml＝xctrace export --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'；
YSE 二進位 UUID 以環境變數 YSE_UUID 指定（預設 rc2＝93976A01…）。
"""
import collections
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import g7_segments as g7  # noqa: E402

YSE_UUID = os.environ.get("YSE_UUID", "93976A01-93D8-30DD-96B8-ECF2C8F6C9C5")
SUBSYSTEM = "com.ibridgezhao.yogsothothsecho"
MAIN_THREAD_PREFIX = "Main Thread"
PROCESS = "Yog-Sothoth's Echo"
OVER_BUDGET_MS = 8.33
REGISTERED_TRANSITIONS = 3
SHARE_MIN = 0.25
LEAD_MIN = 1.5
ENTRY_SYMBOLS = ("main", "$main")
PID_PATTERN = re.compile(r"pid: (\d+)\)")
FIXTURE_SIGNPOST_FIELDS = ("time", "event-type", "name", "category", "message", "subsystem")
FIXTURE_UPDATE_FIELDS = ("start", "duration", "containment-level", "swap-id", "process")


@dataclass(frozen=True)
class ProfileSample:
    time_ns: int
    weight_ns: int
    frames: tuple  # 葉端在前；YSE frame＝位址，連續的非 YSE frame 收成一個 None（分類只看 YSE frame 與其相對順序）


def parse_profile(path):
    """→ (samples, load_addr, pids)：只取 YSE 行程主執行緒"""
    ids, samples, load_addr, pids = {}, [], None, set()
    for _, el in ET.iterparse(path, events=("end",)):
        if el.get("id"):
            ids[el.get("id")] = el
        if el.tag != "row":
            continue
        cells = {c.tag: (ids[c.get("ref")] if c.get("ref") else c) for c in el}
        thread = cells.get("thread")
        fmt = thread.get("fmt", "") if thread is not None else ""
        if not fmt.startswith(MAIN_THREAD_PREFIX) or PROCESS not in fmt:
            continue
        backtrace = cells.get("tagged-backtrace") if "tagged-backtrace" in cells else cells.get("backtrace")
        if backtrace is None:
            continue
        match = PID_PATTERN.search(fmt)
        pids.add(int(match.group(1)) if match else None)
        frames = []
        for frame in backtrace.iter("frame"):
            frame = ids[frame.get("ref")] if frame.get("ref") else frame
            binary = frame.find("binary")
            binary = ids[binary.get("ref")] if binary is not None and binary.get("ref") else binary
            if binary is not None and binary.get("UUID") == YSE_UUID:
                load_addr = load_addr or binary.get("load-addr")
                frames.append(int(frame.get("addr"), 16))
            elif not frames or frames[-1] is not None:
                frames.append(None)
        samples.append(ProfileSample(int(cells["sample-time"].text), int(cells["weight"].text), tuple(frames)))
    return samples, load_addr, pids


def symbolicate(addrs, dwarf, load_addr):
    ordered = sorted(addrs)
    out = subprocess.run(["atos", "-o", dwarf, "-arch", "arm64", "-l", load_addr] + [hex(a) for a in ordered],
                         capture_output=True, text=True, check=True).stdout.splitlines()
    if len(out) != len(ordered):
        sys.exit(f"atos returned {len(out)} lines for {len(ordered)} addresses")
    return dict(zip(ordered, out))


def is_labelring_canvas_closure(symbol):
    return "closure" in symbol and "LabelRing.body" in symbol


def function_name(symbol):
    return symbol.split(" (in ")[0]


def classify(sample, symbols):
    """LabelRing＝任一 frame 是 Canvas 閉包；否則從根往下、離開進入點後第一個 YSE frame；都沒有＝framework-only"""
    names = [symbols[addr] if addr is not None else None for addr in sample.frames]
    if any(name and is_labelring_canvas_closure(name) for name in names):
        return "LabelRing"
    left_entry = False
    for name in reversed(names):
        if name is None:
            left_entry = True
        elif left_entry and function_name(name) not in ENTRY_SYMBOLS:
            return function_name(name)
    return "framework-only"


def g7_signposts(rows):
    """只取本 app 的 G7 列（subsystem＋category＋name）"""
    return [r for r in rows if g7._text(r.get("subsystem")) == SUBSYSTEM and g7._text(r.get("category")) == g7.CATEGORY
            and g7._text(r.get("name")) in g7.G7_NAMES]


def animation_windows(g7_intervals):
    windows = []
    for interval in g7_intervals:
        spans = [(start, end) for name, start, end in g7.segments(interval) if name == "animation"]
        windows.append((interval.transition_id, spans[0] if spans else None))
    return windows


def evaluate(samples, symbols, signpost_rows, update_rows, pids, span):
    """→ {problems, per_transition}；problems 非空＝判不出。span＝完整 trace 的 (首, 末) 取樣時間（fixture 只留動畫段內取樣）"""
    intervals, problems = g7.intervals(g7_signposts(signpost_rows))
    problems = list(problems)
    if len(pids) != 1 or None in pids:
        problems.append(f"main-thread PID not unique: {sorted(p for p in pids if p is not None)}")
    windows = animation_windows(intervals)
    registered = [(tid, window) for tid, window in windows if window][:REGISTERED_TRANSITIONS]
    if registered and not (span[0] <= registered[0][1][0] and span[1] >= registered[-1][1][1]):
        problems.append("time base: profile samples do not cover the registered transitions")
    updates = g7.update_samples(update_rows)
    over = [(u.start_ns, u.start_ns + u.duration_ns) for u in updates if u.duration_ns / g7.NS_PER_MS > OVER_BUDGET_MS]
    per = []
    for tid, window in windows:
        if window is None:
            per.append({"id": tid, "animation": False})
            continue
        start, end = window
        inside = [(s, classify(s, symbols)) for s in samples if start <= s.time_ns < end]
        if not inside and (tid, window) in registered:
            problems.append(f"time base: no samples in animation segment of G7 {tid}")
        units = collections.Counter()
        for sample, unit in inside:
            units[unit] += sample.weight_ns
        app_units = [(name, ns) for name, ns in units.most_common() if name != "framework-only"]
        per.append({"id": tid, "animation": True, "window_ms": round((end - start) / g7.NS_PER_MS, 1),
                    "total_ms": sum(s.weight_ns for s, _ in inside) / g7.NS_PER_MS,
                    "labelring_ms": units["LabelRing"] / g7.NS_PER_MS,
                    "framework_only_ms": units["framework-only"] / g7.NS_PER_MS,
                    "top_app_ns": app_units[:6],
                    "labelring_in_over_budget": sum(1 for s, unit in inside if unit == "LabelRing"
                                                    and any(a <= s.time_ns < b for a, b in over))})
    return {"problems": problems, "per_transition": per}


def leads(transition):
    """(b)：LabelRing 是最大 app 子樹且 ≥ 1.5 倍第二大——比原始權重（D.9 r5：不比四捨五入值）"""
    top = transition["top_app_ns"]
    if not top or top[0][0] != "LabelRing":
        return False
    return len(top) == 1 or top[0][1] >= LEAD_MIN * top[1][1]


def judge(per, problems):
    if problems:
        return {"verdict": "inconclusive", "why": problems}
    registered = [t for t in per if t["animation"]][:REGISTERED_TRANSITIONS]
    if len(registered) < REGISTERED_TRANSITIONS:
        return {"verdict": "inconclusive", "why": [f"only {len(registered)} transitions with animation"]}
    total = sum(t["total_ms"] for t in registered)
    share = sum(t["labelring_ms"] for t in registered) / total if total else 0.0
    a = share >= SHARE_MIN
    b = sum(leads(t) for t in registered) >= 2
    c = sum(t["labelring_in_over_budget"] >= 1 for t in registered) >= 2
    return {"registered_ids": [t["id"] for t in registered], "share": round(share, 3), "a_share": a,
            "b_largest_and_lead": b, "c_overlap": c, "verdict": "eligible" if a and b and c else "not-eligible"}


def report(samples, symbols, signpost_rows, update_rows, pids, header):
    result = evaluate(samples, symbols, signpost_rows, update_rows, pids, header["sample_span_ns"])
    return dict(header, problems=result["problems"], per_transition=result["per_transition"],
                judgement=judge(result["per_transition"], result["problems"]))


def _load_trace(trace, profile_xml, dwarf):
    samples, load_addr, pids = parse_profile(profile_xml)
    if not samples or load_addr is None:
        sys.exit("無效：no YSE main-thread samples or YSE binary not found")
    addrs = {addr for s in samples for addr in s.frames if addr is not None}
    symbols = symbolicate(addrs, dwarf, load_addr)
    signposts = g7.export_table(trace, "os-signpost")
    updates = g7.export_table(trace, "hitches-updates")
    times = [s.time_ns for s in samples]
    header = {"sample_span_ns": [min(times), max(times)], "main_thread_samples": len(samples), "yse_addrs": len(addrs), "load_addr": load_addr, "pids": sorted(
        p for p in pids if p is not None), "unresolved": sum(1 for s in symbols.values() if s.startswith("0x"))}
    return samples, symbols, signposts, updates, pids, header


def extract(samples, symbols, signposts, updates, pids, header):
    """縮小 fixture：只留動畫段內的取樣、其 YSE frame 的符號、G7 signpost 列、與動畫段重疊的 YSE level-0 update 列"""
    rows = g7_signposts(signposts)
    intervals, _ = g7.intervals(rows)
    spans = [w for _, w in animation_windows(intervals) if w]
    kept = [s for s in samples if any(a <= s.time_ns < b for a, b in spans)]
    used = {addr for s in kept for addr in s.frames if addr is not None}
    yse_updates = [r for r in updates if g7.PROCESS in g7._text(r.get("process"))
                   and (r.get("containment-level") or ("", ""))[1] == "0"]
    near = [r for r in yse_updates if any(g7._int(r.get("start")) < b and g7._int(r.get("start")) + g7._int(r.get("duration")) > a
                                          for a, b in spans)]
    pick = lambda row, fields: {f: list(row[f]) for f in fields if f in row}  # noqa: E731
    return {"header": header, "pids": sorted(p for p in pids if p is not None),
            "samples": [[s.time_ns, s.weight_ns, [hex(a) if a is not None else None for a in s.frames]] for s in kept],
            "symbols": {hex(a): symbols[a] for a in sorted(used)},
            "signposts": [pick(r, FIXTURE_SIGNPOST_FIELDS) for r in rows],
            "updates": [pick(r, FIXTURE_UPDATE_FIELDS) for r in near]}


def load_fixture(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    samples = [ProfileSample(t, w, tuple(int(a, 16) if a else None for a in frames)) for t, w, frames in data["samples"]]
    symbols = {int(a, 16): name for a, name in data["symbols"].items()}
    tuples = lambda rows: [{k: tuple(v) for k, v in row.items()} for row in rows]  # noqa: E731
    return samples, symbols, tuples(data["signposts"]), tuples(data["updates"]), set(data["pids"]), data["header"]


def main():
    args = sys.argv[1:]
    if args[:1] == ["analyze"] and len(args) == 4:
        result = report(*_load_trace(*args[1:4]))
    elif args[:1] == ["extract"] and len(args) == 5:
        Path(args[4]).write_text(json.dumps(extract(*_load_trace(*args[1:4])), ensure_ascii=False, indent=0) + "\n",
                                 encoding="utf-8")
        return
    elif args[:1] == ["fixture"] and len(args) == 2:
        result = report(*load_fixture(args[1]))
    else:
        sys.exit(__doc__)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if result["problems"]:
        print("無效：" + "；".join(result["problems"]), file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
