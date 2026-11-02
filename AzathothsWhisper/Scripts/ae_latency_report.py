#!/usr/bin/env python3
"""I-68 掃描中 nowPlaying 延遲報表（docs/plans/2026-11-01-i68-nowplaying-latency.md §5.4–§5.5）。

輸入：`/usr/bin/log stream --predicate 'subsystem == "com.ibridgezhao.azathothswhisper" AND category == "latency"'
--level info --style ndjson` 的輸出檔（唯一證據；`log show` 只作診斷）。
規則 fail-closed：任何不完整都判「量測無效」，不出結論。只讀檔，不碰 Music。

執行：/usr/bin/python3 ae_latency_report.py <ndjson 檔>
"""
from __future__ import annotations

import json
import math
import re
import sys
from dataclasses import dataclass, field

SUBSYSTEM = "com.ibridgezhao.azathothswhisper"
CATEGORY = "latency"
HEADER_PREFIX = "Filtering the log data"
THRESHOLD_MS = 1_500
# `MusicAppleEventsClient` 內呼叫 `run` 的函式（`#function`）。新增呼叫點忘了登記 → 量測無效，不會靜默錯分
KNOWN_OPS = {
    "playerState()", "currentTrack()", "nowPlaying()", "trackDetails(persistentIDs:)", "albumTracks(artist:album:)",
    "setLyrics(persistentID:lyrics:)", "artworkData(persistentID:)", "playbackPosition()", "libraryArtistAlbums()",
    "artistTracks(artist:)", "libraryTrackSnapshot()", "artistLyrics(artist:)",
}
SCAN_OPS = {"libraryTrackSnapshot()", "artistLyrics(artist:)"}

FIELD = re.compile(r"^[A-Za-z][A-Za-z0-9]*=[-0-9A-Za-z(),:]+$")
TOKEN_LIST = re.compile(r"^(-|[0-9]+(,[0-9]+)*)$")
REQUEST = re.compile(r"^(-|[0-9]+)$")
INTEGER = re.compile(r"^[0-9]+$")
# 每種事件的必要欄位與格式（同名欄位在不同事件意義不同：`scan=` 在 scan 是 token、在 np 是 token 清單）
SCHEMA: dict[str, dict[str, re.Pattern]] = {
    "boot": {"app": INTEGER, "pid": INTEGER},
    "scan": {"app": INTEGER, "pid": INTEGER, "scan": INTEGER, "t": INTEGER},
    "np": {"app": INTEGER, "pid": INTEGER, "req": INTEGER, "scan": TOKEN_LIST, "start": INTEGER, "end": INTEGER,
           "total": INTEGER},
    "run": {"app": INTEGER, "pid": INTEGER, "run": INTEGER, "req": REQUEST, "op": re.compile(r"^[A-Za-z]+\([A-Za-z:]*\)$"),
            "enq": INTEGER, "start": INTEGER, "end": INTEGER, "wait": INTEGER, "exec": INTEGER,
            "scanAtEnq": TOKEN_LIST, "scanAtStart": TOKEN_LIST},
    "sig": {"app": INTEGER, "pid": INTEGER, "sig": INTEGER, "t": INTEGER},
    "batch": {"app": INTEGER, "pid": INTEGER, "req": INTEGER, "sigs": re.compile(r"^[0-9]+-[0-9]+$"), "n": INTEGER,
              "result": re.compile(r"^(changed|nochange|notplaying|error)$"), "e2e": REQUEST},
}
OUTCOME = re.compile(r"^(complete|incomplete|cancelled|error)$")
EXIT_CODES = {"達標": 0, "未達標": 1, "量測無效": 3}


@dataclass
class Event:
    kind: str
    fields: dict[str, str]
    flags: list[str]

    def int(self, key: str) -> int:
        return int(self.fields[key])


@dataclass
class Run:
    serial: int
    req: str
    op: str
    enq: int
    start: int
    end: int

    @property
    def wait(self) -> int:
        return self.start - self.enq

    @property
    def exec(self) -> int:
        return self.end - self.start


@dataclass
class Segment:
    values: list[int] = field(default_factory=list)

    @property
    def maximum(self) -> int | None:
        return max(self.values) if self.values else None


@dataclass
class Result:
    invalid_reasons: list[str]
    segments: dict[str, Segment]
    worst_run: Run | None
    worst_ahead: list[Run]
    batches: list[dict[str, str]]

    @property
    def valid(self) -> bool:
        return not self.invalid_reasons


def nearest_rank(values: list[int], percentile: float) -> int | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(1, math.ceil(percentile * len(ordered))) - 1]


def parse_event(message: object) -> Event | None:
    if not isinstance(message, str):
        return None
    kind, *rest = message.split(" ")
    if kind not in SCHEMA:
        return None
    fields: dict[str, str] = {}
    flags: list[str] = []
    for part in rest:
        if part in ("begin", "end"):
            flags.append(part)
        elif FIELD.match(part):
            key, value = part.split("=", 1)
            fields[key] = value
        else:
            return None
    if kind == "scan" and (len(flags) != 1 or (flags[0] == "end") != bool(OUTCOME.match(fields.get("outcome", "")))):
        return None
    if any(not pattern.match(fields.get(key, "")) for key, pattern in SCHEMA[kind].items()):
        return None
    return Event(kind, fields, flags)


def read_events(lines: list[str]) -> tuple[list[Event], list[str]]:
    events: list[Event] = []
    problems: list[str] = []
    for number, raw in enumerate(lines, start=1):
        line = raw.strip()
        if not line or (number == 1 and line.startswith(HEADER_PREFIX)):
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            problems.append(f"第 {number} 行無法解析（不是 JSON）")
            continue
        if not isinstance(record, dict):
            problems.append(f"第 {number} 行不是 JSON 物件")
            continue
        if record.get("subsystem") != SUBSYSTEM or record.get("category") != CATEGORY:
            continue
        event = parse_event(record.get("eventMessage"))
        if event is None:
            problems.append(f"第 {number} 行事件無法解析")
            continue
        events.append(event)
    return events, problems


def check_session(events: list[Event]) -> list[str]:
    boots = [event for event in events if event.kind == "boot"]
    if len(boots) != 1:
        return [f"boot 應恰好一筆，實際 {len(boots)} 筆"]
    if events[0].kind != "boot":
        return ["boot 不是第一筆事件（log stream 晚於 app 啟動）"]
    identity = (boots[0].fields["app"], boots[0].fields["pid"])
    strangers = [event for event in events if (event.fields["app"], event.fields["pid"]) != identity]
    return [f"有 {len(strangers)} 筆事件的 app=／pid= 與 boot 不同（混到別次啟動）"] if strangers else []


def scan_intervals(events: list[Event]) -> tuple[list[tuple[int, int]], list[str]]:
    begins: dict[int, int] = {}
    ends: dict[int, tuple[int, str]] = {}
    for event in (e for e in events if e.kind == "scan"):
        token = event.int("scan")
        if event.flags[0] == "begin":
            begins[token] = event.int("t")
        else:
            ends[token] = (event.int("t"), event.fields["outcome"])
    problems = [f"scan {token} 缺 begin 或 end" for token in sorted(set(begins) ^ set(ends))]
    intervals = sorted((begins[token], ends[token][0]) for token in begins if token in ends)
    if not any(outcome == "complete" for _, outcome in ends.values()):
        problems.append("沒有 outcome=complete 的掃描")
    if any(later[0] < earlier[1] for earlier, later in zip(intervals, intervals[1:])):
        problems.append("掃描區間重疊（掃描中又按了 Rescan）")
    return intervals, problems


def collect_runs(events: list[Event]) -> tuple[list[Run], list[str]]:
    runs = [Run(e.int("run"), e.fields["req"], e.fields["op"], e.int("enq"), e.int("start"), e.int("end"))
            for e in events if e.kind == "run"]
    problems = [f"未登記的 op：{op}" for op in sorted({run.op for run in runs} - KNOWN_OPS)]
    serials = sorted(run.serial for run in runs)
    if serials != list(range(1, len(serials) + 1)):
        problems.append("run 序號不連續（漏行或 log stream 晚開）")
    return runs, problems


def pair_requests(events: list[Event], runs: list[Run]) -> tuple[dict[str, Event], list[str]]:
    problems: list[str] = []
    nps: dict[str, Event] = {}
    for event in (e for e in events if e.kind == "np"):
        if event.fields["req"] in nps:
            problems.append(f"np req={event.fields['req']} 重複")
        nps[event.fields["req"]] = event
    by_request: dict[str, list[Run]] = {}
    for run in runs:
        if run.req != "-":
            by_request.setdefault(run.req, []).append(run)
    for req in sorted(set(nps) | set(by_request), key=int):
        if req not in nps:
            problems.append(f"run req={req} 沒有對應的 np")
        elif len(by_request.get(req, [])) != 1:
            problems.append(f"np req={req} 對應的 run 有 {len(by_request.get(req, []))} 筆（應恰 1 筆）")
    return nps, problems


def segment_of(start: int, end: int, intervals: list[tuple[int, int]]) -> str:
    if any(start <= scan_end and end >= scan_begin for scan_begin, scan_end in intervals):
        return "during"
    if end < intervals[0][0]:
        return "before"
    if start > intervals[-1][1]:
        return "after"
    return "between"


def analyze(lines: list[str]) -> Result:
    events, problems = read_events(lines)
    segments = {name: Segment() for name in ("before", "during", "between", "after")}
    batches = [event.fields for event in events if event.kind == "batch"]
    if not problems:
        problems += check_session(events)
    intervals, scan_problems = scan_intervals(events)
    runs, run_problems = collect_runs(events)
    nps, pair_problems = pair_requests(events, runs)
    problems += scan_problems + run_problems + pair_problems
    worst_run, ahead = None, []
    if intervals:
        worst: tuple[int, str] | None = None
        for req, event in nps.items():
            name = segment_of(event.int("start"), event.int("end"), intervals)
            segments[name].values.append(event.int("total"))
            if name == "during" and (worst is None or event.int("total") > worst[0]):
                worst = (event.int("total"), req)
        if not segments["during"].values:
            problems.append("掃描期間 nowPlaying 0 筆")
        if worst is not None:
            worst_run = next((run for run in runs if run.req == worst[1]), None)
        if worst_run is not None:
            ahead = sorted((run for run in runs if run.serial != worst_run.serial
                            and run.start < worst_run.start and run.end > worst_run.enq), key=lambda run: run.start)
    for segment in segments.values():
        segment.values.sort()
    return Result(problems, segments, worst_run, ahead, batches)


def verdict(result: Result) -> str:
    if not result.valid:
        return "量測無效"
    return "達標" if (result.segments["during"].maximum or 0) <= THRESHOLD_MS else "未達標"


def render(result: Result) -> str:
    out = [f"判定：{verdict(result)}（簽字依據＝本次掃描觀測最大值 ≤ {THRESHOLD_MS} ms）"]
    if not result.valid:
        out += [f"  無效原因：{reason}" for reason in result.invalid_reasons]
        return "\n".join(out)
    names = {"before": "掃描前", "during": "掃描中", "between": "兩次掃描之間", "after": "掃描後"}
    for key, label in names.items():
        values = result.segments[key].values
        if values:
            out.append(f"{label}：{len(values)} 筆，最大 {max(values)} ms，p50 {nearest_rank(values, 0.5)}，"
                       f"p95 {nearest_rank(values, 0.95)}；排序值 {values}")
    if result.worst_run:
        run = result.worst_run
        out.append(f"掃描中最慢一筆：run={run.serial} 等待 {run.wait} ms、執行 {run.exec} ms")
        out += [f"  前面排的：{block.op} 等待 {block.wait} ms、執行 {block.exec} ms"
                + ("（掃描）" if block.op in SCAN_OPS else "") for block in result.worst_ahead]
    out.append(f"換歌通知批次（非驗收）：{len(result.batches)} 批")
    out += [f"  req={b['req']} 通知 {b['sigs']}（{b['n']} 則）結果 {b['result']} 端到端 {b['e2e']} ms" for b in result.batches]
    return "\n".join(out)


def main(arguments: list[str]) -> int:
    if len(arguments) != 1:
        print("用法：ae_latency_report.py <ndjson 檔>", file=sys.stderr)
        return 2
    # 邊界統一攔截：任何讀檔或分析中的例外都是「量測無效」（退出碼 3）。
    # 未捕捉例外的預設退出碼是 1，會被讀成「未達標」＝假結論
    try:
        with open(arguments[0], encoding="utf-8") as handle:
            result = analyze(handle.read().splitlines())
        text, code = render(result), EXIT_CODES[verdict(result)]
    except Exception as error:  # noqa: BLE001 — fail-closed 邊界
        print(f"判定：量測無效\n  無效原因：讀檔或分析失敗（{type(error).__name__}）")
        return EXIT_CODES["量測無效"]
    print(text)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
