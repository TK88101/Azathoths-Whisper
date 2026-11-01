"""CR-039 A5b（yse-g7-hitch-fix.md §6、附錄 D）：G7 signpost 分段＋卡頓統計。

fixture＝A5a 第 4 次實機錄製（rc2，3 次完整換片 ID 8／9／10）修剪而來：只留 G7 列與 3 個 interval 前後 0.1 s 的
YSE 樣本列（及其 ref 所需的定義列），node／schema／跨 node ref 結構原樣保留。
"""
import os
import subprocess
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import g7_segments as g7  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "g7")
YSE = "Yog-Sothoth's Echo"
MS = 1_000_000
S = 1_000_000_000


def fixture(name):
    with open(os.path.join(FIXTURES, name), encoding="utf-8") as f:
        return f.read()


def signpost(time_ns, kind, name, message):
    """合成的 os-signpost 列（與 load_rows 的輸出同形：欄位 → (fmt, raw)）"""
    return {"time": ("", str(time_ns)), "event-type": (kind, kind), "name": (name, name),
            "category": ("TurntableG7", "TurntableG7"), "message": (message, message)}


def transition(tid, begin_s, phases, end_s):
    rows = [signpost(int(begin_s * S), "Begin", "G7", str(tid))]
    rows += [signpost(int(t * S), "Event", "phase", f"{tid} {name}") for name, t in phases]
    if end_s is not None:
        rows.append(signpost(int(end_s * S), "End", "G7", str(tid)))
    return rows


NEW_ALBUM = [("lifting", 0.0), ("awaiting", 0.35), ("clearing", 0.6), ("sheathing", 0.75),
             ("exchanging", 0.91), ("drawing", 1.24), ("placing", 1.44)]


def new_album(tid, at_s):
    return transition(tid, at_s, [(n, at_s + t) for n, t in NEW_ALBUM], at_s + 1.6)


class LoadRowsTests(unittest.TestCase):
    def test_second_node_reuses_schema_and_refs_cross_nodes(self):
        rows = g7.load_rows(fixture("os-signpost.xml"))
        g7_rows = [r for r in rows if r.get("category", ("", ""))[0] == "TurntableG7"]
        self.assertEqual(len(g7_rows), 27)
        self.assertTrue(all(r["subsystem"][0] == "com.ibridgezhao.yogsothothsecho" for r in g7_rows))
        self.assertEqual(g7_rows[0]["event-type"][0], "Begin")
        self.assertEqual(g7_rows[0]["message"][0], "8")


class IntervalTests(unittest.TestCase):
    def test_fixture_has_three_complete_new_album_transitions(self):
        intervals, problems = g7.intervals(g7.load_rows(fixture("os-signpost.xml")))
        self.assertEqual(problems, [])
        self.assertEqual([i.transition_id for i in intervals], [8, 9, 10])
        self.assertEqual([name for name, _ in intervals[0].phases],
                         ["lifting", "awaiting", "clearing", "sheathing", "exchanging", "drawing", "placing"])
        self.assertTrue(all(i.begin_ns < i.end_ns for i in intervals))

    def test_unclosed_interval_is_a_problem(self):
        intervals, problems = g7.intervals(transition(1, 1.0, [("lifting", 1.0)], None))
        self.assertEqual(intervals, [])
        self.assertTrue(any("unclosed" in p for p in problems))

    def test_end_without_begin_is_a_problem(self):
        _, problems = g7.intervals([signpost(2 * S, "End", "G7", "5")])
        self.assertTrue(any("without begin" in p for p in problems))

    def test_phase_for_unknown_transition_is_a_problem(self):
        _, problems = g7.intervals([signpost(2 * S, "Event", "phase", "7 lifting")])
        self.assertTrue(any("without begin" in p for p in problems))

    def test_phase_event_without_phase_name_is_a_problem(self):
        rows = new_album(1, 1.0) + [signpost(int(1.1 * S), "Event", "phase", "1")]
        _, problems = g7.intervals(rows)
        self.assertTrue(any("malformed" in p for p in problems))

    def test_other_categories_are_ignored(self):
        foreign = dict(signpost(1 * S, "Begin", "G7", "1"), category=("Other", "Other"))
        intervals, problems = g7.intervals([foreign] + new_album(2, 3.0))
        self.assertEqual(problems, [])
        self.assertEqual([i.transition_id for i in intervals], [2])


class SegmentTests(unittest.TestCase):
    def test_new_album_segments(self):
        (interval,), _ = g7.intervals(new_album(1, 10.0))
        self.assertEqual(g7.segments(interval), [
            ("lifting", int(10.0 * S), int(10.35 * S)),
            ("awaiting", int(10.35 * S), int(10.6 * S)),
            ("animation", int(10.6 * S), int(11.6 * S)),
        ])

    def test_same_album_animation_starts_at_relabeling(self):
        rows = transition(1, 1.0, [("lifting", 1.0), ("awaiting", 1.35), ("relabeling", 1.77)], 1.97)
        (interval,), _ = g7.intervals(rows)
        self.assertEqual(g7.segments(interval)[-1], ("animation", int(1.77 * S), int(1.97 * S)))

    def test_cancel_after_lifting_has_no_animation(self):
        (interval,), _ = g7.intervals(transition(1, 1.0, [("lifting", 1.0)], 1.2))
        self.assertEqual(g7.segments(interval), [("lifting", 1 * S, int(1.2 * S))])


class SampleTests(unittest.TestCase):
    def test_updates_are_yse_level0_one_per_swap(self):
        rows = g7.load_rows(fixture("hitches-updates.xml"))
        samples = g7.update_samples(rows, YSE)
        swaps = [s.swap for s in samples]
        self.assertEqual(len(swaps), len(set(swaps)))
        yse_swaps = {r["swap-id"][1] for r in rows if YSE in r["process"][0]}
        self.assertEqual(set(swaps), yse_swaps)
        self.assertTrue(any(r["containment-level"][1] == "1" for r in rows), "fixture 應含 level-1 Red 列")

    def test_render_and_gpu_only_count_yse_swaps(self):
        swaps = {s.swap for s in g7.update_samples(g7.load_rows(fixture("hitches-updates.xml")), YSE)}
        for name in ("hitches-renders.xml", "hitches-gpu.xml"):
            rows = g7.load_rows(fixture(name))
            samples = g7.linked_samples(rows, swaps)
            self.assertEqual({s.swap for s in samples}, {r["swap-id"][1] for r in rows} & swaps)
            self.assertNotIn("4240763", {s.swap for s in samples}, "非 YSE 的 swap 不算")

    def test_hitches_dedupe_same_start(self):
        rows = [{"start": ("", "100"), "duration": ("", "8"), "process": (f"{YSE} (1)", "")},
                {"start": ("", "100"), "duration": ("", "9"), "process": (f"{YSE} (1)", "")},
                {"start": ("", "200"), "duration": ("", "5"), "process": ("backboardd (73)", "")}]
        self.assertEqual([(s.start_ns, s.duration_ns) for s in g7.hitch_samples(rows, YSE)], [(100, 9)])


class AttributionTests(unittest.TestCase):
    def test_boundary_goes_to_later_segment_and_outside_is_dropped(self):
        (interval,), _ = g7.intervals(new_album(1, 10.0))
        samples = [g7.Sample(int(9.9 * S), 1 * MS, "a"),     # Begin 之前：不計
                   g7.Sample(int(10.35 * S), 2 * MS, "b"),   # 交界＝awaiting
                   g7.Sample(int(10.6 * S), 3 * MS, "c"),    # 交界＝animation
                   g7.Sample(int(11.6 * S), 4 * MS, "d")]    # End：不計
        self.assertEqual(g7.attribute([interval], samples),
                         {"lifting": [], "awaiting": [2 * MS], "animation": [3 * MS]})


class StatisticTests(unittest.TestCase):
    def test_p99_is_nearest_rank(self):
        self.assertEqual(g7.p99(list(range(1, 201))), 198)
        self.assertEqual(g7.p99([7]), 7)
        self.assertIsNone(g7.p99([]))


def metrics(update=1.0, render=1.0, gpu=1.0, hitch=1.0, update_count=200, lifting_hitch=None):
    """各段樣本（ms → ns）：動畫段照參數；lifting／awaiting 預設空（lifting_hitch 給定時放一筆 hitch）"""
    empty = {name: [] for name in g7.METRICS}
    lifting = dict(empty, hitch=[] if lifting_hitch is None else [int(lifting_hitch * MS)])
    animation = {"update": [int(update * MS)] * update_count, "render": [int(render * MS)],
                 "gpu": [int(gpu * MS)], "hitch": [int(hitch * MS)]}
    return {"lifting": lifting, "awaiting": dict(empty), "animation": animation}


class JudgeTests(unittest.TestCase):
    def test_warm_needs_thirty_intervals(self):
        report = g7.judge(intervals=29, problems=[], by_segment=metrics(), mode="warm", groups=3)
        self.assertFalse(report["valid"])
        self.assertTrue(any("intervals" in r for r in report["reasons"]))

    def test_warm_needs_two_hundred_update_samples(self):
        report = g7.judge(intervals=30, problems=[], by_segment=metrics(update_count=199), mode="warm", groups=3)
        self.assertFalse(report["valid"])

    def test_warm_needs_three_groups(self):
        """§6：warm＝3 組共 ≥ 30 個完整 interval——單一份錄 30 次或只有 2 組都無效（codex A5b r2）"""
        report = g7.judge(intervals=30, problems=[], by_segment=metrics(), mode="warm", groups=2)
        self.assertFalse(report["valid"])
        self.assertTrue(any("groups" in r for r in report["reasons"]))

    def test_problems_make_it_invalid_in_any_mode(self):
        report = g7.judge(intervals=1, problems=["unclosed G7 3"], by_segment=metrics(), mode="cold")
        self.assertFalse(report["valid"])

    def test_thresholds_inclusive_pass(self):
        report = g7.judge(intervals=30, problems=[], by_segment=metrics(update=8.33, render=16.67, gpu=16.67, hitch=16.7),
                          mode="warm", groups=3)
        self.assertTrue(report["valid"])
        self.assertTrue(report["passes"], report)

    def test_each_threshold_can_fail(self):
        for kwargs, metric in (({"update": 8.34}, "update_p99"), ({"render": 16.68}, "render_max"),
                               ({"gpu": 16.68}, "gpu_max"), ({"hitch": 16.71}, "hitch_max")):
            report = g7.judge(intervals=30, problems=[], by_segment=metrics(**kwargs), mode="warm", groups=3)
            self.assertFalse(report["passes"], metric)
            self.assertIn(metric, report["failures"])

    def test_update_max_above_frame_fails_even_if_p99_ok(self):
        by_segment = metrics()
        by_segment["animation"]["update"] = by_segment["animation"]["update"] + [int(16.68 * MS)]
        report = g7.judge(intervals=30, problems=[], by_segment=by_segment, mode="warm", groups=3)
        self.assertIn("update_max", report["failures"])

    def test_unknown_mode_is_rejected(self):
        with self.assertRaises(ValueError):
            g7.judge(intervals=30, problems=[], by_segment=metrics(), mode="wram", groups=3)

    def test_cold_accepts_a_single_interval(self):
        report = g7.judge(intervals=1, problems=[], by_segment=metrics(update_count=10), mode="cold")
        self.assertTrue(report["valid"])

    def test_cold_only_gates_longest_hitch_against_pre_fix_75ms(self):
        """§6.3：cold 只判「最長 hitch 不劣於修前 75.04 ms（附錄 F）」，update／render／GPU 照報不判"""
        slow = metrics(update=30, render=30, gpu=30, hitch=30, update_count=10)
        self.assertTrue(g7.judge(intervals=1, problems=[], by_segment=slow, mode="cold")["passes"])
        at_limit = metrics(hitch=75.04, update_count=10)
        self.assertTrue(g7.judge(intervals=1, problems=[], by_segment=at_limit, mode="cold")["passes"])

    def test_cold_longest_hitch_counts_every_segment(self):
        """修前 75 ms 是未分段量的：cold 取整個 interval（三段）的最長 hitch"""
        report = g7.judge(intervals=1, problems=[], by_segment=metrics(update_count=10, lifting_hitch=75.05), mode="cold")
        self.assertFalse(report["passes"])
        self.assertIn("hitch_max", report["failures"])


class FixtureEndToEndTests(unittest.TestCase):
    def setUp(self):
        self.tables = {name: g7.load_rows(fixture(f"{name}.xml")) for name in g7.TABLES}

    def test_cold_report_over_fixture(self):
        report = g7.analyze_tables([self.tables], mode="cold", process=YSE)
        self.assertEqual(report["intervals"], 3)
        self.assertTrue(report["verdict"]["valid"])
        animation = report["segments"]["animation"]
        self.assertGreater(animation["update"]["count"], 100)
        self.assertGreater(animation["render"]["count"], 100)
        self.assertGreater(animation["gpu"]["count"], 100)
        self.assertEqual(set(report["segments"]), {"lifting", "awaiting", "animation"})

    def test_multiple_traces_are_merged(self):
        report = g7.analyze_tables([self.tables, self.tables], mode="cold", process=YSE)
        single = g7.analyze_tables([self.tables], mode="cold", process=YSE)
        self.assertEqual(report["intervals"], 6)
        self.assertEqual(report["segments"]["animation"]["update"]["count"],
                         2 * single["segments"]["animation"]["update"]["count"])

    def test_traces_may_be_a_one_shot_generator(self):
        """CLI 逐個 trace 匯出、用完即釋放：analyze_tables 只能迭代一次"""
        report = g7.analyze_tables((t for t in [self.tables, self.tables, self.tables]), mode="warm", process=YSE)
        self.assertEqual([g["group"] for g in report["per_group"]], ["trace1", "trace2", "trace3"])
        self.assertNotIn("need >= 3 groups", " ".join(report["verdict"]["reasons"]))

    def test_report_lists_intervals_per_group(self):
        report = g7.analyze_tables([self.tables, self.tables], mode="cold", process=YSE, labels=["g1", "g2"])
        self.assertEqual(report["per_group"], [{"group": "g1", "intervals": 3}, {"group": "g2", "intervals": 3}])

    def test_warm_over_fixture_is_invalid_for_too_few_intervals(self):
        report = g7.analyze_tables([self.tables], mode="warm", process=YSE)
        self.assertFalse(report["verdict"]["valid"])


def frame_rows(counts, start_s=0):
    return [{"start": ("", str((start_s + i) * S)), "duration": ("", str(S)), "count": (str(c), str(c))}
            for i, c in enumerate(counts)]


class SteadyTests(unittest.TestCase):
    def test_fixture_frame_rows_decode(self):
        rows = g7.load_rows(fixture("displayed-surfaces-per-second.xml"))
        self.assertEqual(len(rows), 10)
        self.assertTrue(all(int(r["count"][1]) >= 0 for r in rows))

    def test_steady_passes(self):
        report = g7.steady(frame_rows([120] * 36), hitches=[g7.Sample(10 * S, int(8.34 * MS), "")])
        self.assertTrue(report["valid"])
        self.assertTrue(report["passes"], report)
        self.assertEqual(report["seconds"], 30)

    def test_warmup_seconds_are_excluded(self):
        report = g7.steady(frame_rows([60] * 5 + [120] * 31), hitches=[])
        self.assertTrue(report["passes"], report)

    def test_one_slow_second_fails(self):
        report = g7.steady(frame_rows([120] * 10 + [115] + [120] * 25), hitches=[])
        self.assertIn("fps_min", report["failures"])

    def test_too_few_seconds_is_invalid(self):
        report = g7.steady(frame_rows([120] * 34), hitches=[])
        self.assertFalse(report["valid"])

    def test_hitch_ratio_and_longest(self):
        report = g7.steady(frame_rows([120] * 36), hitches=[g7.Sample(10 * S, 16 * MS, "")])
        self.assertIn("hitch_ratio", report["failures"])   # 16 ms / 30 s ＝ 0.53 ms/s
        self.assertIn("hitch_longest", report["failures"])


class CommandLineTests(unittest.TestCase):
    def test_runs_in_isolated_mode(self):
        """文件用法是 python3 -I（不把腳本目錄放進 sys.path）：同目錄的 liquid_hitches 仍要 import 得到"""
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "g7_segments.py")
        result = subprocess.run([sys.executable, "-I", script, "--help"], capture_output=True, text=True, cwd="/")
        self.assertEqual(result.returncode, 0, result.stderr[-300:])


if __name__ == "__main__":
    unittest.main()
