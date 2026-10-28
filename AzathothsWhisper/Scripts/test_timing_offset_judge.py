"""timing_offset_judge 的單元測試（計劃附錄 C-11 v0.3；全部用合成資料，不含任何歌詞）"""
import random
import unittest

import timing_offset_judge as judge


def timeline(count, start=10.0, step=5.0):
    return [start + step * i for i in range(count)]


def run_for(times, duration, language="de", probability=0.99, whisper="de", low=None):
    return {"text": {"language": language, "probability": probability}, "whisper": whisper,
            "a": list(times), "b": list(times), "low": low or [False] * len(times),
            "duration": duration, "failures": []}


def shifted(run, seconds):
    out = dict(run)
    out["a"] = [None if x is None else x + seconds for x in run["a"]]
    out["b"] = [None if x is None else x + seconds for x in run["b"]]
    out["duration"] = run["duration"] + seconds
    return out


def selfcheck_record(song="s", count=30, offset=0.0, language="de", probability=0.99):
    truth_times = timeline(count)
    duration = truth_times[-1] + 10.0
    base = run_for(truth_times, duration, language, probability)
    return {"song": song, "subset": "de", "lines": count, "human": [t + offset for t in truth_times],
            "selfcheck": True, "failure": None, "base": base, "rerun": dict(base),
            "shiftAfter": shifted(base, 3.0), "shiftBefore": shifted(base, 3.0)}


class ConsensusTests(unittest.TestCase):
    def test_mean_when_methods_agree_within_tolerance(self):
        self.assertEqual(judge.consensus([1.0], [1.2], [False]), [1.1])

    def test_none_when_methods_disagree_missing_or_low_vocal(self):
        self.assertEqual(judge.consensus([1.0, None, 1.0], [1.31, 1.0, 1.0], [False, False, True]), [None, None, None])

    def test_tolerance_boundary_is_inclusive(self):
        self.assertIsNotNone(judge.consensus([1.0], [1.25], [False])[0])


class LanguageTests(unittest.TestCase):
    def test_whitelisted_confident_language_is_usable(self):
        self.assertIsNone(judge.language_cause({"language": "ja", "probability": 0.8}))

    def test_low_probability_is_rejected(self):
        self.assertEqual(judge.language_cause({"language": "en", "probability": 0.79}), "languageLowConfidence")

    def test_language_outside_whitelist_is_rejected(self):
        self.assertEqual(judge.language_cause({"language": "it", "probability": 0.99}), "languageNotSupported")


class EstimateTests(unittest.TestCase):
    def setUp(self):
        self.c = timeline(30)
        self.duration = self.c[-1] + 10.0

    def test_constant_offset_is_recovered_and_accepted(self):
        result = judge.estimate([t + 0.4 for t in self.c], self.c, self.duration)
        self.assertTrue(result["accepted"])
        self.assertAlmostEqual(result["offset"], 0.4)
        self.assertEqual(result["anchors"], list(range(30)))
        self.assertIsNone(result["cause"])

    def test_offset_is_median_of_differences(self):
        lyric = [t + 0.1 for t in self.c]
        lyric[0] += 9.0
        self.assertAlmostEqual(judge.estimate(lyric, self.c, self.duration)["offset"], 0.1)

    def test_too_few_anchors_is_first_cause(self):
        c = [None] * 30
        for i in range(0, 28, 4):
            c[i] = self.c[i]
        result = judge.estimate(self.c, c, self.duration)
        self.assertFalse(result["accepted"])
        self.assertEqual(result["cause"], "anchors")
        self.assertEqual(result["conditions"]["anchors"], 7)

    def test_no_anchor_has_no_offset(self):
        result = judge.estimate(self.c, [None] * 30, self.duration)
        self.assertIsNone(result["offset"])
        self.assertEqual(result["cause"], "anchors")

    def test_short_span_is_rejected(self):
        c = [t if i < 12 else None for i, t in enumerate(self.c)]   # 10–65 s of 165 s
        result = judge.estimate(self.c, c, self.duration)
        self.assertEqual(result["cause"], "span")

    def test_long_gap_between_adjacent_anchors_is_rejected(self):
        c = [t if i < 10 or i > 22 else None for i, t in enumerate(self.c)]   # 55 s → 125 s
        result = judge.estimate(self.c, c, self.duration)
        self.assertEqual(result["cause"], "gap")
        self.assertAlmostEqual(result["conditions"]["maxGap"], 70.0)

    def test_gap_of_exactly_sixty_seconds_passes(self):
        c = [t if i < 10 or i > 20 else None for i, t in enumerate(self.c)]   # 55 s → 115 s
        self.assertNotEqual(judge.estimate(self.c, c, self.duration)["cause"], "gap")

    def test_anchors_in_only_one_third_are_rejected(self):
        c = [None] * 30
        times = [10, 12, 14, 16, 18, 20, 22, 24, 50, 100]
        for i, t in enumerate(times):
            c[i] = float(t)
        result = judge.estimate([x if x is not None else 0.0 for x in c], c, 150.0)
        self.assertEqual(result["conditions"]["thirds"], [8, 1, 1])
        self.assertEqual(result["cause"], "thirds")

    def test_large_residual_p90_is_rejected(self):
        lyric = [t + (0.4 if i % 3 == 0 else 0.0) for i, t in enumerate(self.c)]
        result = judge.estimate(lyric, self.c, self.duration)
        self.assertEqual(result["cause"], "p90")

    def test_residual_p90_uses_linear_interpolation(self):
        lyric = [t + 0.01 * i for i, t in enumerate(self.c[:10])]
        c = self.c[:10]
        result = judge.estimate(lyric, c, c[-1] - c[0])
        residuals = sorted(abs(r) for r in result["residuals"])
        self.assertAlmostEqual(result["conditions"]["p90"], residuals[8] + 0.1 * (residuals[9] - residuals[8]))

    def test_outlier_ratio_above_ten_percent_is_rejected(self):
        c = timeline(19)                 # 2/19 = 10.5 %；線性內插 P90 只取到第一個離群值的 20 %
        lyric = list(c)
        for i in (4, 13):
            lyric[i] += 0.6
        result = judge.estimate(lyric, c, c[-1] + 10.0)
        self.assertGreater(result["conditions"]["outlierRatio"], 0.10)
        self.assertLessEqual(result["conditions"]["p90"], 0.3)
        self.assertEqual(result["cause"], "outliers")

    def test_excluded_lines_are_not_anchors(self):
        result = judge.estimate(self.c, self.c, self.duration, excluded={0, 1})
        self.assertEqual(result["anchors"], list(range(2, 30)))

    def test_all_failed_conditions_are_listed_in_order(self):
        result = judge.estimate(self.c, [self.c[0]] + [None] * 29, self.duration)
        self.assertEqual(result["failed"][0], "anchors")
        self.assertIn("span", result["failed"])


class RunEstimateTests(unittest.TestCase):
    def test_missing_run_is_failure_rejection(self):
        self.assertEqual(judge.run_estimate(None, [1.0])["cause"], "failure")

    def test_rejected_language_skips_audio(self):
        run = {"text": {"language": "en", "probability": 0.5}}
        result = judge.run_estimate(run, [1.0])
        self.assertFalse(result["accepted"])
        self.assertEqual(result["cause"], "languageLowConfidence")

    def test_lyric_shift_moves_offset(self):
        record = selfcheck_record()
        base = judge.run_estimate(record["base"], record["human"])
        moved = judge.run_estimate(record["base"], record["human"], lyric_shift=2.0)
        self.assertAlmostEqual(moved["offset"] - base["offset"], 2.0)


class SelfcheckTests(unittest.TestCase):
    def test_clean_record_passes_every_check(self):
        row = judge.selfcheck_song(selfcheck_record())
        self.assertTrue(row["pass"], row)
        self.assertTrue(row["baseAccepted"])
        self.assertAlmostEqual(row["audioShiftOffsetChange"], -3.0)
        self.assertAlmostEqual(row["lyricShiftOffsetChange"], 2.0)

    def test_row_saves_base_anchor_lines_residuals_and_failed_conditions(self):
        row = judge.selfcheck_song(selfcheck_record(count=6))
        self.assertEqual(row["baseAnchorLines"], list(range(6)))
        self.assertEqual(len(row["baseResiduals"]), 6)
        self.assertEqual(row["baseFailed"][0], "anchors")

    def test_rerun_difference_breaks_determinism(self):
        record = selfcheck_record()
        record["rerun"] = dict(record["base"], a=[x + 0.02 for x in record["base"]["a"]])
        row = judge.selfcheck_song(record)
        self.assertFalse(row["determinism"])
        self.assertFalse(row["pass"])

    def test_rerun_language_change_breaks_determinism(self):
        record = selfcheck_record()
        record["rerun"] = dict(record["base"], text={"language": "en", "probability": 0.99})
        self.assertFalse(judge.selfcheck_song(record)["determinism"])

    def test_audio_shift_outside_tolerance_fails(self):
        record = selfcheck_record()
        record["shiftAfter"] = shifted(record["base"], 3.06)
        record["shiftAfter"]["duration"] = record["base"]["duration"] + 3.0
        self.assertFalse(judge.selfcheck_song(record)["audioShift"])

    def test_audio_shift_losing_too_many_anchors_fails(self):
        record = selfcheck_record()
        after = shifted(record["base"], 3.0)
        after["a"] = [None if i in (3, 7, 11, 15) else x for i, x in enumerate(after["a"])]   # 4/30 > 10 %
        record["shiftAfter"] = after
        row = judge.selfcheck_song(record)
        self.assertGreater(row["anchorChangeRatio"], 0.10)
        self.assertFalse(row["audioShift"])

    def test_rejected_base_must_stay_rejected_for_same_cause(self):
        record = selfcheck_record(count=6)
        record["shiftAfter"] = shifted(record["base"], 3.0)
        row = judge.selfcheck_song(record)
        self.assertFalse(row["baseAccepted"])
        self.assertTrue(row["audioShift"])
        record["shiftAfter"]["a"] = [None] * 6
        self.assertTrue(judge.selfcheck_song(record)["audioShift"])

    def test_rejected_base_with_different_cause_fails_shift(self):
        record = selfcheck_record(count=30)
        record["base"]["a"] = [x if i < 8 else None for i, x in enumerate(record["base"]["a"])]
        record["rerun"] = dict(record["base"])
        record["shiftAfter"] = shifted(record["base"], 3.0)
        record["shiftAfter"]["a"] = [x if i < 7 else None for i, x in enumerate(record["shiftAfter"]["a"])]
        row = judge.selfcheck_song(record)
        self.assertEqual(row["baseCause"], "span")
        self.assertFalse(row["audioShift"])

    def test_non_monotonic_consensus_fails(self):
        record = selfcheck_record()
        for key in ("a", "b"):
            record["base"][key][5], record["base"][key][6] = record["base"][key][6], record["base"][key][5]
        record["rerun"] = dict(record["base"])
        record["shiftAfter"] = shifted(record["base"], 3.0)
        self.assertFalse(judge.selfcheck_song(record)["monotonic"])

    def test_execution_failure_fails_song(self):
        record = selfcheck_record()
        record["failure"] = "RuntimeError"
        row = judge.selfcheck_song(record)
        self.assertFalse(row["pass"])
        self.assertFalse(row["baseAccepted"])

    def test_language_rejected_song_passes_checks_consistently(self):
        record = selfcheck_record(probability=0.5)
        for key in ("base", "rerun", "shiftAfter", "shiftBefore"):
            record[key] = {"text": {"language": "de", "probability": 0.5}}
        row = judge.selfcheck_song(record)
        self.assertEqual(row["baseCause"], "languageLowConfidence")
        self.assertTrue(row["pass"], row)

    def test_verdict_needs_five_songs_all_passing_and_three_accepted(self):
        good = [judge.selfcheck_song(selfcheck_record(song=str(i))) for i in range(5)]
        self.assertTrue(judge.selfcheck_verdict(good)["pass"])
        self.assertFalse(judge.selfcheck_verdict(good[:4])["pass"])
        rejected = judge.selfcheck_song(selfcheck_record(song="r", count=6))
        self.assertTrue(rejected["pass"])
        self.assertTrue(judge.selfcheck_verdict(good[:3] + [rejected, rejected])["pass"])
        self.assertFalse(judge.selfcheck_verdict(good[:2] + [rejected] * 3)["pass"])

    def test_verdict_fails_when_any_song_fails(self):
        rows = [judge.selfcheck_song(selfcheck_record(song=str(i))) for i in range(5)]
        rows[2] = dict(rows[2], **{"pass": False})
        self.assertFalse(judge.selfcheck_verdict(rows)["pass"])


class BoundTests(unittest.TestCase):
    def test_zero_errors_upper_bound_crosses_ten_percent_at_29(self):
        self.assertLessEqual(judge.clopper_pearson_upper(0, 29), 0.10)
        self.assertGreater(judge.clopper_pearson_upper(0, 28), 0.10)

    def test_upper_bound_known_value(self):
        self.assertAlmostEqual(judge.clopper_pearson_upper(0, 29), 1 - 0.05 ** (1 / 29), places=6)

    def test_upper_bound_all_errors_is_one(self):
        self.assertEqual(judge.clopper_pearson_upper(5, 5), 1.0)

    def test_lower_bound_known_value(self):
        self.assertAlmostEqual(judge.clopper_pearson_lower(10, 10), 0.05 ** (1 / 10), places=6)
        self.assertEqual(judge.clopper_pearson_lower(0, 10), 0.0)

    def test_upper_bound_matches_binomial_tail(self):
        upper = judge.clopper_pearson_upper(2, 40)
        tail = sum(judge.binomial_pmf(k, 40, upper) for k in range(3))
        self.assertAlmostEqual(tail, 0.05, places=6)


class GateTests(unittest.TestCase):
    def test_safety_gate_needs_29_accepted_with_no_misfix(self):
        self.assertTrue(judge.safety_gate([0.05] * 29)["pass"])
        self.assertFalse(judge.safety_gate([0.05] * 28)["pass"])
        self.assertFalse(judge.safety_gate([0.05] * 28 + [0.51])["pass"])

    def test_safety_gate_counts_misfix_strictly_above_half_second(self):
        self.assertEqual(judge.safety_gate([0.5] * 30)["misfixes"], 0)

    def test_accuracy_gate_thresholds(self):
        self.assertTrue(judge.accuracy_gate([0.05] * 10, 20)["pass"])
        self.assertFalse(judge.accuracy_gate([0.05] * 9, 20)["pass"])
        self.assertFalse(judge.accuracy_gate([0.11] * 10, 10)["pass"])
        self.assertFalse(judge.accuracy_gate([0.0] * 8 + [0.3, 0.3], 10)["pass"])
        self.assertFalse(judge.accuracy_gate([], 0)["pass"])


class PerturbationTests(unittest.TestCase):
    def test_jitter_draws_one_gaussian_per_line(self):
        rng = random.Random(1)
        expected_rng = random.Random(1)
        out = judge.jitter([1.0, 2.0], rng)
        self.assertEqual(out, [1.0 + expected_rng.gauss(0, 0.15), 2.0 + expected_rng.gauss(0, 0.15)])

    def test_mask_count_rounds_half_up(self):
        self.assertEqual(judge.mask_count(10), 2)
        self.assertEqual(judge.mask_count(12), 2)
        self.assertEqual(judge.mask_count(13), 3)   # 2.6
        self.assertEqual(judge.mask_count(22), 4)   # 4.4
        self.assertEqual(judge.mask_count(17), 3)   # 3.4
        self.assertEqual(judge.mask_count(15), 3)   # 3.0
        self.assertEqual(judge.mask_count(25), 5)
        self.assertEqual(judge.mask_count(37), 7)   # 7.4

    def test_drift_is_zero_at_first_anchor_and_one_second_at_last(self):
        lyric = [5.0, 10.0, 20.0, 30.0, 40.0]
        c = [None, 10.0, 20.0, 30.0, None]
        out = judge.drift(lyric, c)
        self.assertAlmostEqual(out[1], 10.0)
        self.assertAlmostEqual(out[3], 31.0)
        self.assertAlmostEqual(out[2], 20.5)
        self.assertAlmostEqual(out[0], 5.0 - 0.25)
        self.assertAlmostEqual(out[4], 40.0 + 1.5)

    def test_drift_without_two_anchors_is_unchanged(self):
        self.assertEqual(judge.drift([1.0, 2.0], [None, 2.0]), [1.0, 2.0])

    def test_swap_halves_rotates_by_line_index(self):
        self.assertEqual(judge.swap_halves([1, 2, 3, 4, 5]), [3, 4, 5, 1, 2])
        self.assertEqual(judge.swap_halves([1, 2, 3, 4]), [3, 4, 1, 2])


def calibration_records(count=67, offset_of=lambda i: 0.0, subsets=("de", "en", "es", "fr")):
    records = []
    for i in range(count):
        record = selfcheck_record(song=f"song{i:02d}", offset=offset_of(i))
        record["selfcheck"] = False
        record["subset"] = subsets[i % len(subsets)]
        for key in ("rerun", "shiftAfter", "shiftBefore"):
            del record[key]
        records.append(record)
    return records


class CalibrationTests(unittest.TestCase):
    def test_clean_data_passes_all_gates(self):
        report = judge.calibration_report(calibration_records())
        self.assertTrue(report["safety"]["pass"])
        self.assertTrue(all(report["perturbations"][k]["pass"] for k in ("jitter", "mask", "drift", "swap")), report["perturbations"])
        self.assertEqual(sorted(report["passedLanguages"]), ["de", "en", "es", "fr"])
        self.assertEqual(report["verdict"], "pass")

    def test_misfix_fails_safety_gate_and_stops(self):
        report = judge.calibration_report(calibration_records(offset_of=lambda i: 0.6 if i < 3 else 0.0))
        self.assertEqual(report["safety"]["misfixes"], 3)
        self.assertGreater(judge.clopper_pearson_upper(3, 67), 0.10)
        self.assertEqual(report["verdict"], "stop:safety")

    def test_two_misfixes_in_67_still_pass_upper_bound(self):
        report = judge.calibration_report(calibration_records(offset_of=lambda i: 0.6 if i < 2 else 0.0))
        self.assertEqual(report["safety"]["misfixes"], 2)
        self.assertTrue(report["safety"]["pass"])

    def test_safe_but_inaccurate_offsets_stop_with_no_language(self):
        report = judge.calibration_report(calibration_records(offset_of=lambda i: 0.2))
        self.assertTrue(report["safety"]["pass"])
        self.assertEqual(report["passedLanguages"], [])
        self.assertEqual(report["verdict"], "stop:noLanguage")

    def test_failures_count_as_rejections_in_denominator(self):
        records = calibration_records()
        for record in records[:40]:
            record["failure"] = "RuntimeError"
        report = judge.calibration_report(records)
        self.assertEqual(report["accepted"], 27)
        self.assertFalse(report["safety"]["pass"])

    def test_language_with_low_acceptance_does_not_pass(self):
        records = calibration_records()
        for record in records:
            if record["subset"] == "fr":
                record["base"]["a"] = [None] * len(record["base"]["a"])
        report = judge.calibration_report(records)
        self.assertNotIn("fr", report["passedLanguages"])
        self.assertIn("de", report["passedLanguages"])

    def test_perturbation_draws_are_reproducible(self):
        first = judge.calibration_report(calibration_records())
        second = judge.calibration_report(calibration_records())
        self.assertEqual(first, second)

    def test_per_song_estimates_are_saved(self):
        records = calibration_records(count=3)
        records[1]["failure"] = "RuntimeError"
        report = judge.calibration_report(records)
        rows = {row["song"]: row for row in report["perSong"]}
        self.assertEqual(len(rows), 3)
        self.assertTrue(rows["song00"]["accepted"])
        self.assertEqual(rows["song00"]["anchors"], list(range(30)))
        self.assertEqual(len(rows["song00"]["residuals"]), 30)
        self.assertIn("p90", rows["song00"]["conditions"])
        self.assertEqual(rows["song01"]["cause"], "failure")

    def test_whisper_disagreement_is_reported_separately(self):
        records = calibration_records()
        records[0]["base"]["whisper"] = "nn"
        report = judge.calibration_report(records)
        self.assertEqual(report["whisperDisagree"]["songs"], 1)


if __name__ == "__main__":
    unittest.main()
