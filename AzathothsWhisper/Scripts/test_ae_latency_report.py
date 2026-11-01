#!/usr/bin/env python3
"""ae_latency_report.py 的測試（I-68 計劃 docs/plans/2026-11-01-i68-nowplaying-latency.md L3）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest test_ae_latency_report
"""
from __future__ import annotations

import json
import unittest

import ae_latency_report as report

APP, PID = 42, 900
HEADER = 'Filtering the log data using "subsystem == "com.ibridgezhao.azathothswhisper" AND category == "latency""'


def record(message: object, category: str = "latency") -> str:
    return json.dumps({"subsystem": "com.ibridgezhao.azathothswhisper", "category": category, "eventMessage": message})


def ndjson(*messages: str, category: str = "latency") -> list[str]:
    return [HEADER] + [record(message, category) for message in messages]


def boot() -> str:
    return f"boot app={APP} pid={PID}"


def scan(token: int, phase: str, t: int, outcome: str = "complete") -> str:
    tail = f"end outcome={outcome}" if phase == "end" else "begin"
    return f"scan app={APP} pid={PID} scan={token} {tail} t={t}"


def np(req: int, start: int, end: int, scans: str = "-") -> str:
    return f"np app={APP} pid={PID} req={req} scan={scans} start={start} end={end} total={end - start}"


def run(serial: int, req, op: str, enq: int, start: int, end: int) -> str:
    request = "-" if req is None else str(req)
    return (f"run app={APP} pid={PID} run={serial} req={request} op={op} enq={enq} start={start} end={end} "
            f"wait={start - enq} exec={end - start} scanAtEnq=- scanAtStart=-")


def valid_session() -> list[str]:
    """掃描前 1 次、掃描中 2 次、掃描後 1 次 nowPlaying；掃描 block 夾在中間"""
    return ndjson(
        boot(),
        run(1, 1, "nowPlaying()", 100, 100, 150), np(1, 100, 160),
        scan(1, "begin", 1_000),
        run(2, None, "libraryTrackSnapshot()", 1_000, 1_000, 2_200),
        run(3, 2, "nowPlaying()", 1_500, 2_200, 2_260), np(2, 1_500, 2_270),
        run(4, None, "artistLyrics(artist:)", 2_270, 2_270, 2_400),
        run(5, 3, "nowPlaying()", 2_300, 2_400, 2_450), np(3, 2_300, 2_460),
        f"sig app={APP} pid={PID} sig=1 t=2290",
        f"batch app={APP} pid={PID} req=3 sigs=1-1 n=1 result=changed e2e=170",
        scan(1, "end", 70_000),
        run(6, 4, "nowPlaying()", 71_000, 71_000, 71_040), np(4, 71_000, 71_050),
    )


class ParsingTests(unittest.TestCase):
    def test_a_valid_session_produces_segments_and_the_worst_during_scan(self):
        result = report.analyze(valid_session())
        self.assertTrue(result.valid, result.invalid_reasons)
        self.assertEqual(result.segments["before"].values, [60])
        self.assertEqual(result.segments["during"].values, [160, 770])
        self.assertEqual(result.segments["after"].values, [50])
        self.assertEqual(result.segments["during"].maximum, 770)

    def test_the_worst_sample_lists_the_blocks_that_were_ahead_of_it(self):
        result = report.analyze(valid_session())
        ahead = [block.op for block in result.worst_ahead]
        self.assertEqual(ahead, ["libraryTrackSnapshot()"])
        self.assertEqual(result.worst_run.op, "nowPlaying()")
        self.assertEqual(result.worst_run.wait, 700)

    def test_batches_are_reported_but_not_judged(self):
        result = report.analyze(valid_session())
        self.assertEqual(len(result.batches), 1)
        self.assertEqual(result.batches[0]["result"], "changed")
        self.assertEqual(result.batches[0]["e2e"], "170")

    def test_verdict_uses_the_maximum_during_scan(self):
        self.assertEqual(report.verdict(report.analyze(valid_session())), "達標")
        slow = valid_session()
        slow[slow.index(record(np(2, 1_500, 2_270)))] = record(np(2, 0, 1_501))
        # 這裡把一筆改到 1,501 ms，但起點早於掃描，仍與掃描區間相交 → 算掃描中
        self.assertEqual(report.verdict(report.analyze(slow)), "未達標")


class PercentileTests(unittest.TestCase):
    def test_nearest_rank(self):
        values = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
        self.assertEqual(report.nearest_rank(values, 0.5), 50)
        self.assertEqual(report.nearest_rank(values, 0.95), 100)
        self.assertEqual(report.nearest_rank([7], 0.95), 7)
        self.assertIsNone(report.nearest_rank([], 0.5))


class InvalidTests(unittest.TestCase):
    def assertInvalid(self, lines: list[str], fragment: str):
        result = report.analyze(lines)
        self.assertFalse(result.valid)
        self.assertTrue(any(fragment in reason for reason in result.invalid_reasons), result.invalid_reasons)
        self.assertEqual(report.verdict(result), "量測無效")

    def without(self, message: str) -> list[str]:
        return [line for line in valid_session() if message not in line]

    def test_no_boot(self):
        self.assertInvalid(self.without("boot app="), "boot")

    def test_two_boots(self):
        self.assertInvalid(valid_session() + ndjson(boot())[1:], "boot")

    def test_boot_not_first(self):
        lines = valid_session()
        lines[1], lines[2] = lines[2], lines[1]
        self.assertInvalid(lines, "boot")

    def test_another_launch_mixed_in(self):
        self.assertInvalid(valid_session() + [record(f"np app=7 pid={PID} req=9 scan=- start=1 end=2 total=1")], "app=")

    def test_unparseable_line(self):
        self.assertInvalid(valid_session() + ["not json"], "解析")

    def test_unparseable_event(self):
        self.assertInvalid(valid_session() + ndjson("np app=42 pid=900 req=x")[1:], "解析")

    def test_scan_without_end(self):
        self.assertInvalid(self.without("end outcome=complete"), "scan")

    def test_no_complete_scan(self):
        lines = [line.replace("outcome=complete", "outcome=cancelled") for line in valid_session()]
        self.assertInvalid(lines, "complete")

    def test_overlapping_scans(self):
        self.assertInvalid(valid_session() + ndjson(scan(2, "begin", 5_000), scan(2, "end", 80_000))[1:], "重疊")

    def test_np_without_run(self):
        self.assertInvalid(self.without("run=3 "), "run")

    def test_run_request_without_np(self):
        self.assertInvalid(self.without("np app=42 pid=900 req=3 "), "np")

    def test_duplicate_np(self):
        self.assertInvalid(valid_session() + ndjson(np(4, 71_000, 71_050))[1:], "重複")

    def test_run_serial_gap(self):
        self.assertInvalid(self.without("run=4 "), "序號")

    def test_unknown_op(self):
        lines = [line.replace("op=artistLyrics(artist:)", "op=somethingNew()") for line in valid_session()]
        self.assertInvalid(lines, "somethingNew()")

    def test_no_samples_during_scan(self):
        lines = [line for line in valid_session() if "req=2 " not in line and "req=3 " not in line]
        lines = [line for line in lines if "run=3 " not in line and "run=5 " not in line]
        # 拿掉兩筆後序號不連續會先報；這裡把序號補齊再測「掃描中 0 筆」
        lines = [line.replace("run=4 ", "run=3 ").replace("run=6 ", "run=4 ") for line in lines]
        self.assertInvalid(lines, "0 筆")


class MalformedInputTests(unittest.TestCase):
    """畸形輸入一律「量測無效」（退出碼 3），不得崩潰成退出碼 1（＝未達標）"""

    def assertInvalid(self, lines: list[str]):
        result = report.analyze(lines)
        self.assertFalse(result.valid)
        self.assertEqual(report.verdict(result), "量測無效")

    def test_json_that_is_not_an_object(self):
        self.assertInvalid(valid_session() + ["[1, 2]", "7"])

    def test_event_message_that_is_not_a_string(self):
        self.assertInvalid(valid_session() + [record(5)])

    def test_run_request_that_is_not_a_number(self):
        self.assertInvalid(valid_session() + ndjson(run(7, "abc", "nowPlaying()", 1, 2, 3))[1:])

    def test_np_scan_list_that_is_malformed(self):
        self.assertInvalid(valid_session() + ndjson(np(9, 1, 2, scans="3,,x"))[1:])

    def test_main_returns_3_for_a_file_that_is_not_utf8(self):
        import os
        import tempfile
        with tempfile.NamedTemporaryFile("wb", suffix=".ndjson", delete=False) as handle:
            handle.write(b"\xff\xfe not utf-8")
        try:
            self.assertEqual(report.main([handle.name]), 3)
        finally:
            os.unlink(handle.name)

    def test_main_returns_3_for_any_unexpected_failure(self):
        import os
        import tempfile
        from unittest import mock
        with tempfile.NamedTemporaryFile("w", suffix=".ndjson", delete=False, encoding="utf-8") as handle:
            handle.write("\n".join(valid_session()))
        try:
            with mock.patch.object(report, "analyze", side_effect=RuntimeError("boom")):
                self.assertEqual(report.main([handle.name]), 3)
        finally:
            os.unlink(handle.name)

    def test_main_returns_3_for_a_missing_file(self):
        self.assertEqual(report.main(["/nonexistent/ae-latency.ndjson"]), 3)


class FilteringTests(unittest.TestCase):
    def test_other_categories_are_ignored(self):
        lines = valid_session() + ndjson("whatever", category="monitor")[1:]
        self.assertTrue(report.analyze(lines).valid)


if __name__ == "__main__":
    unittest.main()
