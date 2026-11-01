"""CR-038 L-T4：xctrace Animation Hitches 的統計（hitch time ratio、最長卡頓、G7 分段）。"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import liquid_hitches as lh  # noqa: E402

NS = 1_000_000_000
MS = 1_000_000


class HitchRatioTests(unittest.TestCase):
    def test_no_hitches_is_zero(self):
        stats = lh.window_stats([], start_ns=0, length_ns=10 * NS)
        self.assertEqual(stats["hitch_ratio_ms_per_s"], 0)
        self.assertEqual(stats["longest_hitch_ms"], 0)
        self.assertTrue(stats["passes"])

    def test_ratio_is_hitch_ms_per_second(self):
        hitches = [(1 * NS, 20 * MS), (5 * NS, 30 * MS)]
        stats = lh.window_stats(hitches, start_ns=0, length_ns=10 * NS)
        self.assertAlmostEqual(stats["hitch_ratio_ms_per_s"], 5.0)
        self.assertAlmostEqual(stats["longest_hitch_ms"], 30.0)
        self.assertTrue(stats["passes"])  # ≤ 5 ms/s 達標（含等號）

    def test_above_threshold_fails(self):
        stats = lh.window_stats([(1 * NS, 51 * MS)], start_ns=0, length_ns=10 * NS)
        self.assertFalse(stats["passes"])

    def test_hitch_straddling_window_is_clipped(self):
        # 視窗 [1 s, 3 s)：0.99 s 起 20 ms 的卡頓只算 10 ms；2.995 s 起的只算 5 ms
        hitches = [(int(0.99 * NS), 20 * MS), (int(2.995 * NS), 20 * MS), (4 * NS, 50 * MS)]
        stats = lh.window_stats(hitches, start_ns=1 * NS, length_ns=2 * NS)
        self.assertAlmostEqual(stats["hitch_ratio_ms_per_s"], 7.5, places=3)

    def test_zero_length_window_is_rejected(self):
        with self.assertRaises(ValueError):
            lh.window_stats([], start_ns=0, length_ns=0)


class SegmentTests(unittest.TestCase):
    def test_each_swipe_gets_a_two_second_window_and_summary(self):
        starts = [1 * NS, 4 * NS, 7 * NS, 10 * NS, 13 * NS]
        hitches = [(int(1.5 * NS), 10 * MS), (int(7.2 * NS), 40 * MS)]
        result = lh.segments(hitches, starts, length_ns=2 * NS)
        ratios = [s["hitch_ratio_ms_per_s"] for s in result["segments"]]
        self.assertEqual(ratios, [5.0, 0.0, 20.0, 0.0, 0.0])
        self.assertEqual(result["worst_ms_per_s"], 20.0)
        self.assertEqual(result["median_ms_per_s"], 0.0)
        self.assertEqual(result["worst_longest_hitch_ms"], 40.0)
        self.assertFalse(result["passes"])

    def test_empty_segments_cannot_pass(self):
        self.assertFalse(lh.segments([], [], length_ns=2 * NS)["passes"])


class ParseTests(unittest.TestCase):
    """xctrace export 的表格：以 schema 名含 hitch 的表，取 start 與 duration 欄（以 id/ref 去重）"""

    XML = """<?xml version="1.0"?>
<trace-query-result>
<node xpath='//trace-toc[1]/run[1]/data[1]/table[5]'>
<schema name="hitches"><col><mnemonic>start</mnemonic></col><col><mnemonic>duration</mnemonic></col><col><mnemonic>process</mnemonic></col></schema>
<row><start-time id="1" fmt="00:01.000">1000000000</start-time><duration id="2" fmt="20 ms">20000000</duration><process id="3" fmt="App"/></row>
<row><start-time id="4" fmt="00:02.000">2000000000</start-time><duration ref="2"/><process ref="3"/></row>
</node>
</trace-query-result>"""

    def test_parses_rows_with_refs(self):
        self.assertEqual(lh.parse_hitches(self.XML), [(1 * NS, 20 * MS), (2 * NS, 20 * MS)])


class SwipeParseTests(unittest.TestCase):
    """Points of Interest 的「G7 swipe」事件時間（實際 schema 待實機 trace 確認＝TBD；解析器只認含該名稱的列與時間欄）"""

    XML = """<?xml version="1.0"?>
<trace-query-result>
<node><schema name="os-signpost"><col><mnemonic>time</mnemonic></col><col><mnemonic>name</mnemonic></col></schema>
<row><event-time id="1" fmt="00:01.500">1500000000</event-time><string id="2" fmt="G7 swipe">G7 swipe</string></row>
<row><event-time id="3" fmt="00:02.000">2000000000</event-time><string id="4" fmt="other">other</string></row>
<row><event-time id="5" fmt="00:04.250">4250000000</event-time><string ref="2"/></row>
</node>
</trace-query-result>"""

    def test_finds_named_events_including_refs(self):
        self.assertEqual(lh.parse_swipes(self.XML), [1.5, 4.25])


if __name__ == "__main__":
    unittest.main()
