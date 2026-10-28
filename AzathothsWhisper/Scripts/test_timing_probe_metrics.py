#!/usr/bin/env python3
"""timing_probe_metrics.py 的單元測試（計劃 docs/plans/2026-10-25-lyrics-timing-accuracy.md §4.3、§4.7、§4.8）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest test_timing_probe_metrics
測試字串一律自編，不用真歌詞。
"""
from __future__ import annotations

import unittest

import timing_probe_metrics as tpm


class StatisticsTests(unittest.TestCase):
    def test_median_of_even_count_averages_middle_pair(self):
        self.assertEqual(tpm.median([4.0, 1.0, 3.0, 2.0]), 2.5)

    def test_percentile_interpolates_linearly(self):
        self.assertAlmostEqual(tpm.percentile([0.0, 10.0], 90), 9.0)
        self.assertEqual(tpm.percentile([5.0], 90), 5.0)

    def test_empty_statistics_are_none(self):
        self.assertIsNone(tpm.median([]))
        self.assertIsNone(tpm.percentile([], 90))

    def test_bootstrap_is_deterministic_and_brackets_the_median(self):
        values = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
        first = tpm.bootstrap_ci(values, tpm.median)
        second = tpm.bootstrap_ci(values, tpm.median)
        self.assertEqual(first, second)
        low, high = first
        self.assertLessEqual(low, tpm.median(values))
        self.assertGreaterEqual(high, tpm.median(values))

    def test_bootstrap_of_empty_is_none(self):
        self.assertIsNone(tpm.bootstrap_ci([], tpm.median))


class ConsensusTests(unittest.TestCase):
    def test_agreeing_methods_give_mean_and_half_spread(self):
        truth, uncertainty = tpm.consensus(10.0, 10.2)
        self.assertAlmostEqual(truth, 10.1)
        self.assertAlmostEqual(uncertainty, 0.1)

    def test_disagreeing_methods_are_undecidable(self):
        self.assertEqual(tpm.consensus(10.0, 10.31), (None, None))

    def test_missing_method_is_undecidable(self):
        self.assertEqual(tpm.consensus(None, 10.0), (None, None))


class SimilarityTests(unittest.TestCase):
    def test_normalized_keeps_only_lowercase_letters_and_digits(self):
        self.assertEqual(tpm.normalized("Paper Boats, 2 Go!"), "paperboats2go")

    def test_similarity_matches_app_definition(self):
        self.assertGreaterEqual(tpm.similarity("Lanterns over the river", "Lanterns over a river"), 0.8)
        self.assertLess(tpm.similarity("Lanterns over the river", "Static on the radio"), 0.8)
        self.assertEqual(tpm.similarity("", ""), 0.0)

    def test_repeated_flags_mark_every_copy(self):
        texts = ["Paper boats at dawn", "A quiet line here", "Paper boats at dawn!"]
        self.assertEqual(tpm.repeated_flags(texts), [True, False, True])


class WrongLineTests(unittest.TestCase):
    def test_display_matching_truth_has_no_wrong_lines(self):
        flags = tpm.wrong_line_flags([0.0, 5.0, 10.0], [0.0, 5.0, 10.0])
        self.assertEqual(flags, [False, False, None])

    def test_late_display_shows_previous_line(self):
        # 第 2 行晚 2 秒才顯示：真值 5.0 + 0.5 時仍顯示第 1 行
        flags = tpm.wrong_line_flags([0.0, 7.0, 10.0], [0.0, 5.0, 10.0])
        self.assertEqual(flags[1], True)

    def test_early_display_skips_ahead(self):
        flags = tpm.wrong_line_flags([0.0, 0.3, 10.0], [0.0, 5.0, 10.0])
        self.assertEqual(flags[0], True)

    def test_observation_point_uses_half_gap_for_short_lines(self):
        # 行距 0.6 s：觀察點＝真值 + 0.3，不是 + 0.5
        flags = tpm.wrong_line_flags([0.0, 0.45, 5.0], [0.0, 0.6, 5.0])
        self.assertEqual(flags[0], False)

    def test_lines_next_to_undecidable_and_last_line_are_excluded(self):
        flags = tpm.wrong_line_flags([0.0, 5.0, 10.0, 15.0], [0.0, None, 10.0, 15.0])
        self.assertEqual(flags, [None, None, False, None])

    def test_nothing_shown_yet_counts_as_wrong(self):
        flags = tpm.wrong_line_flags([3.0, 5.0], [0.0, 5.0])
        self.assertEqual(flags[0], True)


class TrackMetricsTests(unittest.TestCase):
    def test_uniform_offset_has_zero_residual(self):
        truth = [10.0, 20.0, 30.0, 40.0]
        display = [t + 1.0 for t in truth]
        metrics = tpm.track_metrics(display, truth, [0.05] * 4)
        self.assertAlmostEqual(metrics["mae"], 1.0)
        self.assertAlmostEqual(metrics["offset"], 1.0)
        self.assertAlmostEqual(metrics["resid_p90"], 0.0)
        self.assertEqual(metrics["late"], 1.0)
        self.assertEqual(metrics["early"], 0.0)

    def test_early_on_time_late_ratios_and_wide_tolerance(self):
        truth = [10.0, 20.0, 30.0, 40.0]
        display = [9.0, 20.1, 30.5, 42.0]
        metrics = tpm.track_metrics(display, truth, [0.0] * 4)
        self.assertEqual(metrics["early"], 0.25)
        self.assertEqual(metrics["on_time"], 0.25)
        self.assertEqual(metrics["late"], 0.5)
        self.assertEqual(metrics["within_1s"], 0.75)

    def test_boundary_lines_are_within_uncertainty_of_threshold(self):
        truth = [10.0, 20.0]
        display = [10.35, 21.0]
        metrics = tpm.track_metrics(display, truth, [0.1, 0.1])
        self.assertEqual(metrics["boundary_share"], 0.5)

    def test_undecidable_lines_are_skipped(self):
        metrics = tpm.track_metrics([10.0, 25.0, 30.0], [10.0, None, 30.0], [0.0, None, 0.0])
        self.assertEqual(metrics["decidable_lines"], 2)
        self.assertEqual(metrics["mae"], 0.0)
        self.assertEqual(metrics["wrong_excluded_share"], 1.0)
        self.assertIsNone(metrics["wrong_rate"])

    def test_first_line_error_and_latter_residual(self):
        truth = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
        display = [14.0, 20.0, 30.0, 40.0, 50.0, 60.0]
        metrics = tpm.track_metrics(display, truth, [0.0] * 6)
        self.assertEqual(metrics["first_abs_error"], 4.0)
        self.assertEqual(metrics["latter_resid_median"], 0.0)

    def test_interpolated_lines_are_reported_separately(self):
        truth = [10.0, 20.0, 30.0, 40.0]
        display = [10.0, 23.0, 30.0, 40.0]
        metrics = tpm.track_metrics(display, truth, [0.0] * 4, interpolated=[False, True, False, False])
        self.assertEqual(metrics["interp_lines"], 1)
        self.assertEqual(metrics["interp_abs_errors"], [3.0])
        self.assertEqual(metrics["interp_wrong_rate"], 1.0)

    def test_repeated_line_sensitivity(self):
        truth = [10.0, 20.0, 30.0]
        display = [10.0, 25.0, 30.0]
        texts = ["Paper boats at dawn", "A quiet line here", "Paper boats at dawn"]
        metrics = tpm.track_metrics(display, truth, [0.0] * 3, texts=texts)
        self.assertEqual(metrics["mae"], 0.0)
        self.assertEqual(metrics["mae_without_repeats"], 5.0)

    def test_track_without_decidable_lines_has_no_metrics(self):
        metrics = tpm.track_metrics([1.0, 2.0], [None, None], [None, None])
        self.assertEqual(metrics["decidable_lines"], 0)
        self.assertIsNone(metrics["mae"])


class KeyCheckTests(unittest.TestCase):
    def test_nested_disallowed_keys_are_reported_with_path(self):
        record = {"persistentID": "AB12", "lines": [{"start": 1.0, "text": "x"}], "title": "y"}
        allowed = {"persistentID", "lines", "start"}
        self.assertEqual(tpm.disallowed_keys(record, allowed), ["lines[0].text", "title"])

    def test_clean_record_passes(self):
        self.assertEqual(tpm.disallowed_keys({"a": 1, "b": {"a": 2}}, {"a", "b"}), [])


def _population(counts):
    """counts：{(language, linesPerMinute): 首數}；pid 依序編號。"""
    records = []
    for (language, rate), count in sorted(counts.items()):
        for _ in range(count):
            records.append({"persistentID": "P%05d" % len(records), "language": language, "linesPerMinute": rate})
    return records


class SamplingTests(unittest.TestCase):
    def test_tertile_cuts_split_rates_into_three_layers(self):
        records = _population({("other", 1.0): 3, ("other", 5.0): 3, ("other", 9.0): 3})
        self.assertEqual([tpm.tertile(r["linesPerMinute"], tpm.tertile_cuts(records)) for r in records[::3]], [0, 1, 2])

    def test_language_floor_lifts_small_language(self):
        records = _population({("ja", 5.0): 60, ("other", 5.0): 940})
        sample = tpm.stratified_sample(records, size=200)
        languages = [s["language"] for s in sample]
        self.assertEqual(languages.count("ja"), 50)
        self.assertEqual(languages.count("other"), 150)

    def test_proportional_allocation_when_floor_not_binding(self):
        records = _population({("ja", 5.0): 500, ("other", 5.0): 500})
        sample = tpm.stratified_sample(records, size=200)
        self.assertEqual([s["language"] for s in sample].count("ja"), 100)

    def test_short_language_takes_all_and_rest_go_to_other_language(self):
        records = _population({("ja", 5.0): 30, ("other", 5.0): 970})
        sample = tpm.stratified_sample(records, size=200)
        languages = [s["language"] for s in sample]
        self.assertEqual(languages.count("ja"), 30)
        self.assertEqual(len(sample), 200)

    def test_layer_quota_never_exceeds_layer_size(self):
        records = _population({("other", 1.0): 2, ("other", 5.0): 50, ("other", 9.0): 50})
        sample = tpm.stratified_sample(records, size=30)
        self.assertEqual(len({s["persistentID"] for s in sample}), 30)
        for share, size in zip(tpm.largest_remainder([2, 50, 50], 30), [2, 50, 50]):
            self.assertLessEqual(share, size)

    def test_sampling_is_deterministic_and_keyed_by_hash(self):
        records = _population({("ja", 5.0): 100, ("other", 5.0): 900})
        first = tpm.stratified_sample(records, size=200)
        second = tpm.stratified_sample(list(reversed(records)), size=200)
        self.assertEqual([s["persistentID"] for s in first], [s["persistentID"] for s in second])
        self.assertEqual(tpm.sample_key("ABC"), tpm.sample_key("ABC"))
        self.assertNotEqual(tpm.sample_key("ABC"), tpm.sample_key("ABD"))

    def test_sample_records_carry_layer_label(self):
        records = _population({("other", 1.0): 10, ("other", 5.0): 10, ("other", 9.0): 10})
        sample = tpm.stratified_sample(records, size=9)
        self.assertEqual(sorted({s["layer"] for s in sample}), ["other/0", "other/1", "other/2"])

    def test_largest_remainder_keeps_total(self):
        self.assertEqual(tpm.largest_remainder([1, 1, 1], 10), [4, 3, 3])
        self.assertEqual(sum(tpm.largest_remainder([5, 3, 2], 7)), 7)
        self.assertEqual(tpm.largest_remainder([0, 0], 5), [0, 0])


def _track(track_id, group, mae=0.1, offset=0.0, resid=0.1, wrong=0.0, weight=0.01, source=None, **extra):
    record = {
        "id": track_id, "group": group, "source": source, "weight": weight, "calibrated": True,
        "mae": mae, "offset": offset, "resid_p90": resid, "wrong_rate": wrong,
        "first_abs_error": 0.1, "latter_resid_median": 0.1,
        "interp_lines": 0, "line_count": 10, "interp_abs_errors": [], "interp_abs_median": None, "interp_wrong_rate": None,
        "near_miss": False,
    }
    record.update(extra)
    return record


def _healthy_inputs():
    tracks = [_track("x%d" % i, "external", source="lrclib") for i in range(20)]
    tracks += [_track("s%d" % i, "estimated") for i in range(20)]
    return {"g0_passed": True, "embedded_population": 5, "chain_found_rate": 0.8, "near_miss_share": 0.0, "tracks": tracks}


class DecisionGateTests(unittest.TestCase):
    def test_g0_failure_stops(self):
        inputs = _healthy_inputs()
        inputs["g0_passed"] = False
        self.assertEqual(tpm.decide(inputs)["outcome"], "stop")

    def test_too_few_external_tracks_is_insufficient(self):
        inputs = _healthy_inputs()
        inputs["tracks"] = [t for t in inputs["tracks"] if t["id"] not in {"x0", "x1"}]
        self.assertEqual(tpm.decide(inputs)["outcome"], "insufficient")

    def test_embedded_evidence_only_required_when_population_is_large(self):
        inputs = _healthy_inputs()
        inputs["embedded_population"] = 30
        self.assertEqual(tpm.decide(inputs)["outcome"], "insufficient")

    def test_uncalibrated_tracks_do_not_count(self):
        inputs = _healthy_inputs()
        inputs["tracks"][0]["calibrated"] = False
        self.assertEqual(tpm.decide(inputs)["outcome"], "insufficient")

    def test_nothing_triggered_is_no_action(self):
        result = tpm.decide(_healthy_inputs())
        self.assertEqual(result["outcome"], "no_action")
        self.assertTrue(result["external_accurate"])


class DecisionCandidateTests(unittest.TestCase):
    def test_offset_dominated_external_triggers_x2(self):
        inputs = _healthy_inputs()
        for track in inputs["tracks"][:5]:
            track.update(offset=1.0, mae=1.0, resid_p90=0.2, wrong_rate=0.4)
        result = tpm.decide(inputs)
        self.assertEqual(result["outcome"], "single")
        self.assertEqual(result["chosen"], ["X2"])
        x2 = _candidate(result, "X2")
        self.assertAlmostEqual(x2["recoverable"], 0.05 * 0.4)

    def test_x3_demotes_a_dominant_source_with_enough_evidence(self):
        inputs = _healthy_inputs()
        for i in range(8):
            inputs["tracks"].append(_track("q%d" % i, "external", source="qq", resid_p90=2.0, mae=2.0, wrong_rate=0.5))
        result = tpm.decide(inputs)
        self.assertEqual(_candidate(result, "X3")["direction"], "demote:qq")

    def test_x3_without_dominant_source_needs_per_line_alignment(self):
        inputs = _healthy_inputs()
        for track in inputs["tracks"][:5]:
            track.update(resid_p90=2.0, wrong_rate=0.5)
        for i in range(5):
            inputs["tracks"].append(_track("d%d" % i, "external", source="deezer", resid_p90=2.0, wrong_rate=0.5))
        result = tpm.decide(inputs)
        self.assertEqual(_candidate(result, "X3")["direction"], "per_line_alignment")

    def test_x4_uses_interpolated_wrong_rate(self):
        inputs = _healthy_inputs()
        for track in inputs["tracks"][:10]:
            track.update(interp_lines=5, interp_abs_errors=[3.0, 4.0, 5.0, 4.0, 4.0], interp_abs_median=4.0, interp_wrong_rate=1.0)
        result = tpm.decide(inputs)
        x4 = _candidate(result, "X4")
        self.assertTrue(x4["triggered"])
        self.assertAlmostEqual(x4["recoverable"], 0.10 * 1.0)

    def test_s1_prefers_floor_improvement_when_intro_dominates(self):
        inputs = _healthy_inputs()
        for track in inputs["tracks"]:
            if track["group"] == "estimated":
                track.update(mae=4.0, wrong_rate=0.5, first_abs_error=8.0, latter_resid_median=1.0)
        result = tpm.decide(inputs)
        self.assertEqual(_candidate(result, "S1")["direction"], "estimate_floor")

    def test_s1_triggers_on_wrong_rate_alone(self):
        inputs = _healthy_inputs()
        for track in inputs["tracks"]:
            if track["group"] == "estimated":
                track.update(mae=1.0, wrong_rate=0.35, latter_resid_median=3.0)
        result = tpm.decide(inputs)
        self.assertEqual(_candidate(result, "S1")["direction"], "per_line_alignment")

    def test_negative_c1_is_unrecoverable(self):
        inputs = _healthy_inputs()
        inputs.update(chain_found_rate=0.3, near_miss_share=0.5)
        for track in inputs["tracks"]:
            if track["group"] == "external":
                track["wrong_rate"] = 0.5
            else:
                track.update(near_miss=True, wrong_rate=0.1)
        result = tpm.decide(inputs)
        self.assertTrue(_candidate(result, "C1")["triggered"])
        self.assertLess(_candidate(result, "C1")["recoverable"], 0)
        self.assertEqual(result["outcome"], "unrecoverable")

    def test_zero_recoverable_is_not_ranked(self):
        inputs = _healthy_inputs()
        for track in inputs["tracks"][:5]:
            track.update(offset=1.0, resid_p90=0.2, wrong_rate=0.0)
        result = tpm.decide(inputs)
        self.assertEqual(result["outcome"], "unrecoverable")
        self.assertIsNone(_candidate(result, "X2")["rank"])

    def test_close_candidates_tie_for_user_decision(self):
        inputs = _healthy_inputs()
        for track in inputs["tracks"][:5]:
            track.update(offset=1.0, resid_p90=0.2, wrong_rate=0.4)
        for track in inputs["tracks"]:
            if track["group"] == "estimated":
                track.update(mae=3.0, wrong_rate=0.11)
        result = tpm.decide(inputs)
        self.assertEqual(result["outcome"], "tie")
        self.assertEqual(sorted(result["chosen"]), ["S1", "X2"])

    def test_embedded_group_produces_e1_candidates(self):
        inputs = _healthy_inputs()
        inputs["embedded_population"] = 25
        for i in range(20):
            inputs["tracks"].append(_track("e%d" % i, "embedded", offset=1.0, resid_p90=0.2, wrong_rate=0.3))
        result = tpm.decide(inputs)
        self.assertTrue(_candidate(result, "E1-X2")["triggered"])
        self.assertEqual(result["chosen"], ["E1-X2"])

    def test_small_embedded_group_cannot_trigger_e1(self):
        inputs = _healthy_inputs()
        inputs["embedded_population"] = 10
        for i in range(10):
            inputs["tracks"].append(_track("e%d" % i, "embedded", offset=1.0, resid_p90=0.2, wrong_rate=0.3))
        result = tpm.decide(inputs)
        self.assertNotIn("E1-X2", [c["id"] for c in result["candidates"]])
        self.assertEqual(result["outcome"], "no_action")

    def test_overlaps_are_counted_pairwise(self):
        inputs = _healthy_inputs()
        for track in inputs["tracks"][:5]:
            track.update(offset=1.0, resid_p90=0.2, wrong_rate=0.4,
                         interp_lines=5, interp_abs_errors=[3.0, 4.0, 5.0, 4.0, 4.0], interp_abs_median=4.0, interp_wrong_rate=1.0)
        for track in inputs["tracks"][5:10]:
            track.update(interp_lines=5, interp_abs_errors=[3.0, 4.0, 5.0, 4.0, 4.0], interp_abs_median=4.0, interp_wrong_rate=1.0)
        result = tpm.decide(inputs)
        self.assertEqual(result["overlaps"]["X2&X4"], 5)

    def test_candidates_are_serialized_with_required_fields(self):
        result = tpm.decide(_healthy_inputs())
        for candidate in result["candidates"]:
            self.assertEqual(set(candidate), {"id", "direction", "triggered", "track_set", "weight", "recoverable", "rank"})


def _candidate(result, candidate_id):
    return next(c for c in result["candidates"] if c["id"] == candidate_id)


if __name__ == "__main__":
    unittest.main()
