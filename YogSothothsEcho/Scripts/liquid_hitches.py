#!/usr/bin/env python3
"""CR-038 L-T4（yse-liquid-vinyl-sample.md v0.4 §4.5）：xctrace Animation Hitches 錄製與統計。

主指標＝hitch time ratio（ms/s），≤ 5 ms/s 達標；另報最長單次卡頓。G7 以每次甩動起 2 s 分段。

用法（實機；錄前先喚醒 DDI，xctrace 一律包 alarm——record 可能不返回）：
  python3 -I liquid_hitches.py record --device <UDID> --seconds 30 --label live-spin --out <dir>
  python3 -I liquid_hitches.py analyze <trace> [--swipes 1.2,4.0,...]   # 秒，相對錄製起點
"""
import argparse
import json
import statistics
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS_PER_S = 1_000_000_000
NS_PER_MS = 1_000_000
PASS_MS_PER_S = 5.0
RECORD_GRACE_S = 60
TEMPLATE = "Animation Hitches"


def window_stats(hitches, start_ns, length_ns):
    """視窗 [start, start+length) 內的卡頓時間（跨邊界的截斷）換算成 ms/s"""
    if length_ns <= 0:
        raise ValueError("window length must be positive")
    end_ns = start_ns + length_ns
    total_ns = 0
    longest_ns = 0
    for begin, duration in hitches:
        overlap = min(begin + duration, end_ns) - max(begin, start_ns)
        if overlap > 0:
            total_ns += overlap
            longest_ns = max(longest_ns, duration)
    ratio = (total_ns / NS_PER_MS) / (length_ns / NS_PER_S)
    return {
        "hitch_ratio_ms_per_s": ratio,
        "longest_hitch_ms": longest_ns / NS_PER_MS,
        "passes": ratio <= PASS_MS_PER_S,
    }


def segments(hitches, starts, length_ns):
    """每次甩動起 length 的視窗各算一次，報最差與中位數"""
    parts = [window_stats(hitches, s, length_ns) for s in starts]
    ratios = [p["hitch_ratio_ms_per_s"] for p in parts]
    return {
        "segments": parts,
        "worst_ms_per_s": max(ratios) if ratios else None,
        "median_ms_per_s": statistics.median(ratios) if ratios else None,
        "worst_longest_hitch_ms": max((p["longest_hitch_ms"] for p in parts), default=None),
        "passes": bool(parts) and all(p["passes"] for p in parts),
    }


def _resolve(element, ids):
    """xctrace export 以 id 定義、ref 引用重複值；回傳 (text, fmt)。子元素的 id 也要記下（process 內含 pid）"""
    if element is None:
        return None
    ref = element.get("ref")
    if ref is not None:
        return ids.get(ref)
    value = ((element.text or "").strip(), element.get("fmt") or "")
    for node in element.iter():
        if node.get("id") is not None:
            ids[node.get("id")] = value if node is element else ((node.text or "").strip(), node.get("fmt") or "")
    return value


HITCH_SCHEMA = "hitches"


def hitch_tables(toc_text):
    """只取主表 `hitches`（hitches-gpu／-renders／-updates／-framewait／-frame-lifetimes 是同一批卡頓的細分，重讀會重複計算）"""
    root = ET.fromstring(toc_text)
    return sorted({t.get("schema") for t in root.iter("table") if t.get("schema") == HITCH_SCHEMA})


def parse_hitches(xml_text, process=None):
    """主表的 (start ns, duration ns)；process 給定時只取該行程（fmt 含此字串）。
    同一次卡頓會因多個 surface 重複出現：以起點去重、取最長"""
    root = ET.fromstring(xml_text)
    found = {}
    for node in root.iter("node"):
        schema = node.find("schema")
        if schema is None or schema.get("name") != HITCH_SCHEMA:
            continue
        ids = {}
        for row in node.findall("row"):
            # 每列都要走過全部欄位，id 定義才會被記下
            cells = {child.tag: _resolve(child, ids) for child in row}
            start, duration = cells.get("start-time"), cells.get("duration")
            if not start or not duration or not start[0] or not duration[0]:
                continue
            if process is not None and process not in (cells.get("process") or ("", ""))[1]:
                continue
            begin = int(start[0])
            found[begin] = max(found.get(begin, 0), int(duration[0]))
    return sorted(found.items())


SWIPE_EVENT = "G7 swipe"
TIME_TAGS = ("event-time", "start-time", "time", "sample-time")


def parse_swipes(xml_text):
    """含「G7 swipe」字樣的列，取其時間欄（ns → s，相對錄製起點）"""
    root = ET.fromstring(xml_text)
    result = []
    for node in root.iter("node"):
        ids = {}
        for row in node.findall("row"):
            values = [(child.tag, (_resolve(child, ids) or ("", ""))[0]) for child in row]
            if not any(v == SWIPE_EVENT for _, v in values):
                continue
            time = next((v for tag, v in values if tag in TIME_TAGS and v), None)
            if time:
                result.append(int(time) / NS_PER_S)
    return result


def _run(args, timeout_s):
    """xctrace 會卡住不返回（[[xctrace-record-can-hang]]）：以 perl alarm 強制逾時"""
    return subprocess.run(["perl", "-e", f"alarm {timeout_s}; exec @ARGV", *args], capture_output=True, text=True)


def record(device, seconds, label, out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    trace = out_dir / f"{label}.trace"
    wake = _run(["xcrun", "devicectl", "device", "info", "ddiServices", "--device", device, "-q"], 60)
    if wake.returncode != 0:
        sys.exit(f"ddiServices failed ({wake.returncode}): {wake.stderr.strip()[-300:]}")
    rec = _run(["xcrun", "xctrace", "record", "--template", TEMPLATE, "--instrument", "Points of Interest",
                "--device", device, "--all-processes",
                "--time-limit", f"{seconds}s", "--output", str(trace)], seconds + RECORD_GRACE_S)
    if rec.returncode != 0 or not trace.exists():
        sys.exit(f"xctrace record failed ({rec.returncode}): {rec.stderr.strip()[-300:]}")
    print(trace)


def analyze(trace, swipes, process):
    toc = _run(["xcrun", "xctrace", "export", "--input", str(trace), "--toc"], 120)
    if toc.returncode != 0:
        sys.exit(f"export toc failed: {toc.stderr.strip()[-300:]}")
    toc_root = ET.fromstring(toc.stdout)
    tables = hitch_tables(toc.stdout)
    if not tables:
        sys.exit("no hitch table in trace (schemas: %s)" % sorted({t.get("schema") for t in toc_root.iter("table")}))
    summary = toc_root.find(".//summary")
    duration_s = float(summary.findtext("duration")) if summary is not None and summary.findtext("duration") else None
    hitches = []
    for schema in sorted(set(tables)):
        exported = _run(["xcrun", "xctrace", "export", "--input", str(trace), "--xpath",
                         f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'], 300)
        if exported.returncode != 0:
            sys.exit(f"export {schema} failed: {exported.stderr.strip()[-300:]}")
        hitches.extend(parse_hitches(exported.stdout, process=process))
    report = {"template": TEMPLATE, "tables": tables, "process": process, "hitch_count": len(hitches),
              "xctrace": _run(["xcrun", "xctrace", "version"], 30).stdout.strip()}
    if duration_s:
        report["whole"] = window_stats(hitches, 0, int(duration_s * NS_PER_S))
    if not swipes:
        # 沒給 --swipes：從 Points of Interest 的「G7 swipe」事件取（schema 名待實機確認＝TBD，先找含 signpost／point 的表）
        for schema in sorted({t.get("schema") for t in toc_root.iter("table")
                              if any(k in (t.get("schema") or "").lower() for k in ("signpost", "point"))}):
            exported = _run(["xcrun", "xctrace", "export", "--input", str(trace), "--xpath",
                             f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'], 300)
            if exported.returncode == 0:
                swipes.extend(parse_swipes(exported.stdout))
        swipes = sorted(set(swipes))
        report["swipes_from_signposts"] = swipes
    if swipes:
        report["g7"] = segments(hitches, [int(s * NS_PER_S) for s in swipes], 2 * NS_PER_S)
    print(json.dumps(report, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    r = sub.add_parser("record")
    r.add_argument("--device", required=True)
    r.add_argument("--seconds", type=int, required=True)
    r.add_argument("--label", required=True)
    r.add_argument("--out", required=True)
    a = sub.add_parser("analyze")
    a.add_argument("trace")
    a.add_argument("--swipes", default="", help="comma-separated seconds from recording start")
    a.add_argument("--process", default="Yog-Sothoth's Echo", help="only count hitches of this process (substring)")
    args = parser.parse_args()
    if args.command == "record":
        record(args.device, args.seconds, args.label, args.out)
    else:
        swipes = [float(x) for x in args.swipes.split(",") if x.strip()]
        analyze(Path(args.trace), swipes, args.process)


if __name__ == "__main__":
    main()
