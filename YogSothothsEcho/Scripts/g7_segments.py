#!/usr/bin/env python3
"""CR-039 A5b（yse-g7-hitch-fix.md §6、附錄 D）：以 G7 signpost 把換片切成 lifting／awaiting／動畫段，分段統計卡頓。

指標來源（§6）：hitch＝`hitches` 主表（YSE、同起點去重）；update＝`hitches-updates`（YSE、每 swap 取 level-0 列）；
render／GPU＝`hitches-renders`／`hitches-gpu`（無行程欄，以 swap-id 對回 YSE 的 update）；幀數＝`displayed-surfaces-per-second`。
歸屬：樣本起點落在 [段起, 段止)（交界歸後者）；G7 interval 外不計。p99＝nearest-rank。

用法（xctrace 一律包 alarm——export／record 可能不返回）：
  python3 -I g7_segments.py g7 --mode warm <trace> [<trace> ...]   # 每組一個 trace；warm 需 ≥30 個完整 interval
  python3 -I g7_segments.py g7 --mode cold <trace>
  python3 -I g7_segments.py steady <trace>                          # §6.1 穩態：暖機 5 s 後 30 個整秒
"""
import argparse
import json
import math
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

# 文件用法是 python3 -I：隔離模式不把腳本目錄放進 sys.path，同目錄模組要自己加
sys.path.insert(0, str(Path(__file__).resolve().parent))
from liquid_hitches import _run, window_stats  # noqa: E402

NS_PER_S = 1_000_000_000
NS_PER_MS = 1_000_000
CATEGORY = "TurntableG7"
PROCESS = "Yog-Sothoth's Echo"
SEGMENTS = ("lifting", "awaiting", "animation")
ANIMATION_PHASES = ("relabeling", "clearing", "crossfading")  # 動畫段的第一個相位（同專輯／換專輯／Reduce Motion）
METRICS = ("update", "render", "gpu", "hitch")
TABLES = ("os-signpost", "hitches", "hitches-updates", "hitches-renders", "hitches-gpu")

# §6.2（動畫段判定）與 §6.1（穩態）門檻，單位 ms；皆含等號
UPDATE_P99_MS = 8.33
FRAME_MS = 16.67
HITCH_MAX_MS = 16.7
COLD_PRE_FIX_HITCH_MS = 75.04  # 修前 rc1 實機觀測最長 hitch（yse-swirl-style.md 附錄 F #3）
WARM_MIN_GROUPS = 3  # §6：3 組（每組一個 trace）共 ≥ 30 個完整 interval
WARM_MIN_INTERVALS = 30
WARM_MIN_UPDATE_SAMPLES = 200
STEADY_WARMUP_S = 5
STEADY_SECONDS = 30
STEADY_MIN_FPS = 116
STEADY_MAX_RATIO_MS_PER_S = 0.5
STEADY_MAX_LONGEST_MS = 8.4
EXPORT_TIMEOUT_S = 600


@dataclass(frozen=True)
class Sample:
    start_ns: int
    duration_ns: int
    swap: str


@dataclass(frozen=True)
class G7Interval:
    transition_id: int
    begin_ns: int
    end_ns: int
    phases: tuple  # ((相位名, 起點 ns), ...)
    end_note: str = ""  # End message 轉場 ID 之後的部分（§11 S2：`misses=<n> reasons=…`）


def load_rows(xml_text):
    """xctrace export 的列 → {欄位: (fmt, raw)}。
    第二個以後的 node 可能沒有 schema（沿用前一個）；id／ref 在整份檔案共用（附錄 D.1，已核）"""
    root = ET.fromstring(xml_text)
    ids, columns, rows = {}, None, []
    for node in root.findall("node"):
        schema = node.find("schema")
        if schema is not None:
            columns = [col.findtext("mnemonic") for col in schema.findall("col")]
        if columns is None:
            raise ValueError("node without schema before any schema")
        for row in node.findall("row"):
            rows.append({column: _cell(element, ids) for column, element in zip(columns, row)})
    return rows


def _cell(element, ids):
    ref = element.get("ref")
    if ref is not None:
        return ids.get(ref, ("", ""))
    value = (element.get("fmt") or "", (element.text or "").strip())
    for node in element.iter():
        if node.get("id") is not None:
            ids[node.get("id")] = value if node is element else (node.get("fmt") or "", (node.text or "").strip())
    return value


def _text(cell):
    return (cell[0] or cell[1]) if cell else ""


def _int(cell):
    return int(cell[1]) if cell and cell[1].lstrip("-").isdigit() else None


def intervals(rows, category=CATEGORY):
    """G7 Begin／phase／End（message 首欄＝轉場 ID）配成 interval；配不上的寫進 problems（任何一條＝量測無效）"""
    marks = sorted((r for r in rows if _text(r.get("category")) == category), key=lambda r: _int(r.get("time")) or 0)
    open_, closed, problems = {}, [], []
    for row in marks:
        kind, name, time = _text(row.get("event-type")), _text(row.get("name")), _int(row.get("time"))
        words = _text(row.get("message")).split()
        if not words or not words[0].isdigit() or time is None:
            problems.append(f"malformed G7 row: {kind} {name} {words}")
            continue
        tid = int(words[0])
        if kind == "Begin":
            if tid in open_:
                problems.append(f"duplicate begin G7 {tid}")
            open_[tid] = (time, [])
        elif tid not in open_:
            problems.append(f"{name} {tid} without begin")
        elif kind == "Event":
            if len(words) < 2:
                problems.append(f"malformed phase event for G7 {tid}: {words}")
            else:
                open_[tid][1].append((words[1], time))
        elif kind == "End":
            begin, phases = open_.pop(tid)
            closed.append(G7Interval(tid, begin, time, tuple(phases), " ".join(words[1:])))
    problems.extend(f"unclosed G7 {tid}" for tid in sorted(open_))
    return sorted(closed, key=lambda i: i.begin_ns), problems


def segments(interval):
    """[(段名, 起 ns, 止 ns)]：lifting 起於 lifting 相位（缺則 Begin），各段止於下一段起或 End"""
    starts = {}
    for name, time in interval.phases:
        segment = "animation" if name in ANIMATION_PHASES else name
        if segment in SEGMENTS and segment not in starts:
            starts[segment] = time
    starts.setdefault("lifting", interval.begin_ns)
    ordered = sorted((time, name) for name, time in starts.items())
    ends = [time for time, _ in ordered[1:]] + [interval.end_ns]
    return [(name, start, end) for (start, name), end in zip(ordered, ends)]


def hitch_samples(rows, process=PROCESS):
    """主表、指定行程；同起點（多個 surface 重複）去重取最長"""
    found = {}
    for row in rows:
        start, duration = _int(row.get("start")), _int(row.get("duration"))
        if start is None or duration is None or process not in _text(row.get("process")):
            continue
        found[start] = max(found.get(start, 0), duration)
    return [Sample(start, duration, "") for start, duration in sorted(found.items())]


def _level0(rows):
    for row in rows:
        start, duration = _int(row.get("start")), _int(row.get("duration"))
        if start is not None and duration is not None and (row.get("containment-level") or ("", ""))[1] == "0":
            yield row, start, duration


def _swap_samples(rows, keep):
    """每個 swap 一個樣本（level-0 列；level-1 Red＝同一段超時的標記，時長相同，不重複計）"""
    seen, samples = set(), []
    for row, start, duration in _level0(rows):
        swap = (row.get("swap-id") or ("", ""))[1]
        if swap not in seen and keep(row, swap):
            seen.add(swap)
            samples.append(Sample(start, duration, swap))
    return samples


def update_samples(rows, process=PROCESS):
    return _swap_samples(rows, lambda row, _swap: process in _text(row.get("process")))


def linked_samples(rows, swaps):
    """render／GPU 表沒有行程欄：只認 YSE update 出現過的 swap"""
    return _swap_samples(rows, lambda _row, swap: swap in swaps)


def attribute(g7_intervals, samples):
    """樣本依起點歸入段（半開區間＝交界歸後者），回 {段: [duration ns]}"""
    spans = [span for interval in g7_intervals for span in segments(interval)]
    result = {name: [] for name in SEGMENTS}
    for sample in samples:
        for name, start, end in spans:
            if start <= sample.start_ns < end:
                result[name].append(sample.duration_ns)
                break
    return result


def p99(values):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[math.ceil(0.99 * len(ordered)) - 1]


def _ms(value_ns):
    return None if value_ns is None else value_ns / NS_PER_MS


def stats(values):
    return {"count": len(values), "p99_ms": _ms(p99(values)), "max_ms": _max_ms(values)}


def _max_ms(values):
    return _ms(max(values, default=None))


LABEL_MISS_REASONS = ("absent", "pending", "rendering", "failed")


def _parse_label_note(note):
    """`misses=<n> reasons=absent:a,pending:p,rendering:r,failed:f` → (n, {reason: count})；缺、重複、格式錯、合計不符＝None"""
    tokens = note.split()
    misses = [t for t in tokens if t.startswith("misses=")]
    reasons = [t for t in tokens if t.startswith("reasons=")]
    if len(misses) != 1 or len(reasons) != 1 or len(tokens) != 2:
        return None
    count = misses[0][len("misses="):]
    pairs = [part.split(":") for part in reasons[0][len("reasons="):].split(",")]
    if not count.isdigit() or [p[0] for p in pairs] != list(LABEL_MISS_REASONS) \
            or not all(len(p) == 2 and p[1].isdigit() for p in pairs):
        return None
    by_reason = {name: int(value) for name, value in pairs}
    return (int(count), by_reason) if sum(by_reason.values()) == int(count) else None


def label_misses(found):
    """§11.3／B4：每個 interval 的標籤 logical miss（signpost end note）；解析不了的列為 problems"""
    totals = dict.fromkeys(LABEL_MISS_REASONS, 0)
    per_interval, problems = [], []
    for interval in found:
        parsed = _parse_label_note(interval.end_note)
        if parsed is None:
            problems.append(f"G7 {interval.transition_id}: label misses note missing or malformed: {interval.end_note!r}")
            continue
        count, by_reason = parsed
        per_interval.append(count)
        for name, value in by_reason.items():
            totals[name] += value
    return {"total": sum(per_interval), "reasons": totals, "per_interval": per_interval, "problems": problems}


def judge(intervals, problems, by_segment, mode, groups=1, label_misses=None):
    """warm（§6.2）：動畫段 update p99 ≤ 8.33、max ≤ 16.67；render、GPU max ≤ 16.67；hitch max ≤ 16.7（ms，含等號）。
    cold（§6.3）：只判整個 interval（三段）最長 hitch 不劣於修前 75.04 ms（修前未分段量，附錄 F）；其餘照報不判"""
    animation = by_segment["animation"]
    reasons = list(problems)
    if mode == "warm":
        if groups < WARM_MIN_GROUPS:
            reasons.append(f"need >= {WARM_MIN_GROUPS} groups (one trace each; got {groups})")
        if intervals < WARM_MIN_INTERVALS:
            reasons.append(f"need >= {WARM_MIN_INTERVALS} complete intervals (got {intervals})")
        if len(animation["update"]) < WARM_MIN_UPDATE_SAMPLES:
            reasons.append(f"need >= {WARM_MIN_UPDATE_SAMPLES} animation update samples (got {len(animation['update'])})")
        checks = {
            "update_p99": (_ms(p99(animation["update"])), UPDATE_P99_MS),
            "update_max": (_max_ms(animation["update"]), FRAME_MS),
            "render_max": (_max_ms(animation["render"]), FRAME_MS),
            "gpu_max": (_max_ms(animation["gpu"]), FRAME_MS),
            "hitch_max": (_max_ms(animation["hitch"]), HITCH_MAX_MS),
        }
    elif mode == "cold":
        if intervals < 1:
            reasons.append("need >= 1 complete interval")
        every_hitch = [value for name in SEGMENTS for value in by_segment[name]["hitch"]]
        checks = {"hitch_max": (_max_ms(every_hitch), COLD_PRE_FIX_HITCH_MS)}
    else:
        raise ValueError(f"unknown mode {mode!r} (warm or cold)")
    failures = {name: {"value_ms": value, "limit_ms": limit}
                for name, (value, limit) in checks.items() if value is not None and value > limit}
    # §11.1：warm 每個 interval 標籤 miss 必須 0；cold 照報不判
    if mode == "warm" and label_misses is not None and label_misses["total"] > 0:
        failures["label_misses"] = {"value": label_misses["total"], "limit": 0}
    valid = not reasons
    return {"mode": mode, "valid": valid, "reasons": reasons, "passes": valid and not failures, "failures": failures}


def _samples_by_metric(tables, process):
    updates = update_samples(tables["hitches-updates"], process)
    swaps = {sample.swap for sample in updates}
    return {"update": updates, "render": linked_samples(tables["hitches-renders"], swaps),
            "gpu": linked_samples(tables["hitches-gpu"], swaps), "hitch": hitch_samples(tables["hitches"], process)}


def analyze_tables(traces, mode, process=PROCESS, labels=None, require_label_misses=False):
    """多個 trace（每組一個；時間各自相對錄製起點）：各自歸屬後合併成 {段: {指標: [ns]}}；problems 帶 trace 標籤"""
    per_group, problems, every_interval = [], [], []
    by_segment = {name: {metric: [] for metric in METRICS} for name in SEGMENTS}
    # traces 可以是只能迭代一次的 generator（CLI 逐個匯出、用完即釋放）
    for index, tables in enumerate(traces):
        label = labels[index] if labels else f"trace{index + 1}"
        found, found_problems = intervals(tables["os-signpost"])
        per_group.append({"group": label, "intervals": len(found)})
        problems.extend(f"{label}: {problem}" for problem in found_problems)
        if require_label_misses:
            misses = label_misses(found)
            problems.extend(f"{label}: {problem}" for problem in misses["problems"])
            every_interval.extend(found)
        for metric, samples in _samples_by_metric(tables, process).items():
            for name, values in attribute(found, samples).items():
                by_segment[name][metric].extend(values)
    count = sum(group["intervals"] for group in per_group)
    misses = label_misses(every_interval) if require_label_misses else None
    report = {"intervals": count, "per_group": per_group, "problems": problems,
              "segments": {name: {metric: stats(values) for metric, values in metrics.items()}
                           for name, metrics in by_segment.items()},
              "verdict": judge(count, problems, by_segment, mode, groups=len(per_group), label_misses=misses)}
    if misses is not None:
        report["label_misses"] = {key: misses[key] for key in ("total", "reasons", "per_interval")}
    return report


def steady(frame_rows, hitches, warmup_s=STEADY_WARMUP_S, seconds=STEADY_SECONDS):
    """§6.1：暖機後 seconds 個整秒——每秒幀數 ≥ 116、hitch ≤ 0.5 ms/s、最長 ≤ 8.4 ms"""
    begin, end = warmup_s * NS_PER_S, (warmup_s + seconds) * NS_PER_S
    counts = []
    for row in sorted(frame_rows, key=lambda r: _int(r.get("start")) or 0):
        start, duration, count = _int(row.get("start")), _int(row.get("duration")), _int(row.get("count"))
        if None in (start, duration, count) or duration < NS_PER_S - NS_PER_MS:
            continue
        if begin <= start and start + duration <= end:
            counts.append(count)
    window = window_stats([(h.start_ns, h.duration_ns) for h in hitches], begin, end - begin)
    valid = len(counts) >= seconds
    checks = {"fps_min": (min(counts) if counts else None, STEADY_MIN_FPS, lambda v, l: v >= l),
              "hitch_ratio": (window["hitch_ratio_ms_per_s"], STEADY_MAX_RATIO_MS_PER_S, lambda v, l: v <= l),
              "hitch_longest": (window["longest_hitch_ms"], STEADY_MAX_LONGEST_MS, lambda v, l: v <= l)}
    failures = {name: {"value": value, "limit": limit}
                for name, (value, limit, ok) in checks.items() if value is not None and not ok(value, limit)}
    return {"valid": valid, "seconds": len(counts), "fps_min": checks["fps_min"][0],
            "hitch_ratio_ms_per_s": window["hitch_ratio_ms_per_s"], "longest_hitch_ms": window["longest_hitch_ms"],
            "passes": valid and not failures, "failures": failures,
            "reasons": [] if valid else [f"need {seconds} whole seconds after {warmup_s} s warm-up (got {len(counts)})"]}


def export_table(trace, schema):
    exported = _run(["xcrun", "xctrace", "export", "--input", str(trace), "--xpath",
                     f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'], EXPORT_TIMEOUT_S)
    if exported.returncode != 0:
        sys.exit(f"export {schema} from {trace} failed ({exported.returncode}): {exported.stderr.strip()[-300:]}")
    return load_rows(exported.stdout)


def analyze_traces(traces, mode, process, require_label_misses=False):
    tables = ({schema: export_table(trace, schema) for schema in TABLES} for trace in traces)
    report = analyze_tables(tables, mode, process, labels=[Path(t).name for t in traces], require_label_misses=require_label_misses)
    return dict(report, traces=[str(t) for t in traces])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    g = sub.add_parser("g7")
    g.add_argument("--mode", choices=("warm", "cold"), required=True)
    g.add_argument("--process", default=PROCESS)
    g.add_argument("--label-misses", action="store_true", help="rc3 起：要求 signpost end 帶標籤 miss（§11.3）")
    g.add_argument("traces", nargs="+")
    s = sub.add_parser("steady")
    s.add_argument("--process", default=PROCESS)
    s.add_argument("trace")
    args = parser.parse_args()
    if args.command == "g7":
        result = analyze_traces(args.traces, args.mode, args.process, args.label_misses)
    else:
        result = steady(export_table(args.trace, "displayed-surfaces-per-second"),
                        hitch_samples(export_table(args.trace, "hitches"), args.process))
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
