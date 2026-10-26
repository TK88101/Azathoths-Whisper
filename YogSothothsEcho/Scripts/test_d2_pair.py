"""d2_pair.py 的測試（S4 #4-1 D2；thecure 收斂：以請求 ID 逐筆對應、3 s 靜穏、5 s 內多筆＝無效、事件要反映操作）。"""
import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import d2_pair  # noqa: E402

TICKS_PER_SECOND = 24_000_000  # machTimestamp：1 tick＝125/3 ns


def mouse(t):
    return {"machTimestamp": int(t * TICKS_PER_SECOND), "subsystem": "yse.d2", "eventMessage": "mouse-down music-front=true"}


def key(t, name="play"):
    return {"machTimestamp": int(t * TICKS_PER_SECOND), "subsystem": "yse.d2", "eventMessage": f"key-down key={name} music-front=false"}


def arrival(t, rid, limit=1, kind="catalog.page"):
    lim = f" limit={limit}" if kind == "catalog.page" else ""
    return {"machTimestamp": int(t * TICKS_PER_SECOND), "subsystem": "com.ibridgezhao.azathothswhisper",
            "category": "relay-measure", "eventMessage": f"arrival kind={kind}{lim} id={rid} conn=C1"}


def receipt(seq, rid, state, track):
    return {"seq": seq, "requestID": rid, "sentAt": seq, "state": state, "trackOrdinal": track}


class PairTests(unittest.TestCase):
    def run_pair(self, entries, receipts):
        return d2_pair.pair(entries, receipts)

    def test_media_keys_are_trials_like_clicks(self):
        # #4-1 實測：使用者以鍵盤 F8（播放／暫停）、F9（下一首）操作，旁聽工具改記媒體鍵
        receipts = [receipt(1, "R1", "playing", 1), receipt(2, "R2", "paused", 1), receipt(3, "R3", "playing", 2)]
        entries = [arrival(1, "R1"), key(10, "play"), arrival(10.8, "R2"), key(20, "next"), arrival(21.5, "R3")]
        trials = self.run_pair(entries, receipts)
        self.assertEqual([(t.category, round(t.latency_ms)) for t in trials], [("pause", 800), ("change", 1500)])

    def test_unchanged_receipts_are_ignored(self):
        # #4-1 實測：中繼每 10 s 定時校正推送（狀態、曲目都沒變）落在按鍵前 3 s 內被判 not-quiet；
        # 這種回條不可能被誤認成操作的反應，不計入靜穏與多筆判定
        receipts = [receipt(1, "R1", "playing", 1), receipt(2, "R2", "playing", 1), receipt(3, "R3", "paused", 1),
                    receipt(4, "R4", "paused", 1)]
        entries = [arrival(1, "R1"), arrival(9, "R2"), key(10, "play"), arrival(10.2, "R3"), arrival(12, "R4")]
        trials = self.run_pair(entries, receipts)
        self.assertEqual([(t.category, round(t.latency_ms)) for t in trials], [("pause", 200)])

    def test_pause_and_change_are_timed_from_mouse_to_receipt(self):
        receipts = [receipt(1, "R1", "playing", 1), receipt(2, "R2", "paused", 1), receipt(3, "R3", "playing", 2)]
        entries = [arrival(1, "R1"), mouse(10), arrival(10.8, "R2"), mouse(20), arrival(21.5, "R3")]
        trials = self.run_pair(entries, receipts)
        self.assertEqual([t.category for t in trials], ["pause", "change"])
        self.assertAlmostEqual(trials[0].latency_ms, 800, places=3)
        self.assertAlmostEqual(trials[1].latency_ms, 1500, places=3)
        self.assertTrue(all(t.valid for t in trials))

    def test_receipt_within_three_seconds_before_click_voids_trial(self):
        receipts = [receipt(1, "R1", "playing", 1), receipt(2, "R2", "paused", 1)]
        entries = [arrival(8.5, "R1"), mouse(10), arrival(10.5, "R2")]
        self.assertEqual(self.run_pair(entries, receipts)[0].reason, "not-quiet")

    def test_two_receipts_within_five_seconds_void_trial(self):
        # 兩筆都有變化（暫停、又播放）＝分不清哪筆是這次操作的反應（沒變化的回條另有規則略過）
        receipts = [receipt(1, "R0", "playing", 1), receipt(2, "R1", "paused", 1), receipt(3, "R2", "playing", 1)]
        entries = [arrival(1, "R0"), mouse(10), arrival(10.5, "R1"), arrival(11, "R2")]
        self.assertEqual(self.run_pair(entries, receipts)[0].reason, "multiple")

    def test_no_receipt_is_void(self):
        self.assertEqual(self.run_pair([mouse(10)], [])[0].reason, "no-receipt")

    def test_requests_that_are_not_our_receipts_are_ignored(self):
        receipts = [receipt(1, "R0", "playing", 1), receipt(2, "R1", "paused", 1)]
        entries = [arrival(1, "R0"), arrival(9.5, "OTHER"), mouse(10), arrival(10.2, "OTHER2"), arrival(10.6, "R1"),
                   arrival(10.7, "R9", limit=200)]
        trial = self.run_pair(entries, receipts)[0]
        self.assertTrue(trial.valid)
        self.assertAlmostEqual(trial.latency_ms, 600, places=3)

    def test_receipt_whose_event_does_not_reflect_an_operation_is_void(self):
        # 有變化但不是「播放→暫停」或換歌（例如暫停→播放）
        receipts = [receipt(1, "R0", "paused", 1), receipt(2, "R1", "playing", 1)]
        entries = [arrival(1, "R0"), mouse(10), arrival(10.4, "R1")]
        self.assertEqual(self.run_pair(entries, receipts)[0].reason, "event-not-reflecting")

    def test_summary_requires_ten_valid_each_and_all_within_two_seconds(self):
        trials = [d2_pair.Trial(category="pause", latency_ms=500.0 + i, valid=True, reason="") for i in range(10)]
        trials += [d2_pair.Trial(category="change", latency_ms=900.0, valid=True, reason="") for _ in range(9)]
        verdict = d2_pair.summarize(trials)
        self.assertFalse(verdict.passed)              # change 只有 9 筆
        trials.append(d2_pair.Trial(category="change", latency_ms=2100.0, valid=True, reason=""))
        self.assertFalse(d2_pair.summarize(trials).passed)   # 一筆超過 2 s
        trials[-1] = d2_pair.Trial(category="change", latency_ms=1900.0, valid=True, reason="")
        verdict = d2_pair.summarize(trials)
        self.assertTrue(verdict.passed)
        self.assertEqual(verdict.p95["pause"], 509.0)  # nearest-rank：10 筆的 p95＝第 10 筆

    def test_loads_ndjson_and_receipts_files(self):
        with tempfile.TemporaryDirectory() as d:
            log = pathlib.Path(d, "d2.ndjson")
            log.write_text("\n".join(json.dumps(e) for e in [arrival(1, "R0"), mouse(10), arrival(10.3, "R1")]) + "\nnot json\n")
            rec = pathlib.Path(d, "control-d2.json")
            rec.write_text(json.dumps({"kind": "d2", "receipts": [receipt(1, "R0", "playing", 1), receipt(2, "R1", "paused", 1)]}))
            trials = d2_pair.pair(d2_pair.load_log(log), d2_pair.load_receipts(rec))
            self.assertEqual(len(trials), 1)
            self.assertTrue(trials[0].valid)


if __name__ == "__main__":
    unittest.main()
