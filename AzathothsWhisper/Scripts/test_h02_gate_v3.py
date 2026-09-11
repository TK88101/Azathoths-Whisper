#!/usr/bin/env python3
"""h02_gate_eval.py 的單元測試：V3 判定（拆自 `test_h02_gate_eval.py`）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_gate*.py'
"""
from __future__ import annotations

import unittest

import h02_gate_eval as gate
from test_h02_gate_fixtures import (
    C2,
    T4S2_OFFSET,
    T4S2_STACK,
    all_pass_grid,
    m0_run,
    make_log,
    pass_at,
    xcresult_for_grid,
)


class V3Tests(unittest.TestCase):
    def test_defect3_detection_and_positive_control(self):
        grid = all_pass_grid(n=10)
        # T4.s2 在全部 10 次迭代都 FAIL、同一組簽名，帶 C1-OFFSET（缺陷3候選碼）
        grid["T4"] = [
            [
                "GATE{T4.s1|PASS}",
                "GATE{T4.s2|FAIL|C1-OFFSET}",
            ]
            for _ in range(10)
        ]
        failure_texts = {
            ("T4", i, "s2"): ["SIG{T4.s2|C1-OFFSET|label=T19|centered=T16|strides=+3}"]
            for i in range(1, 11)
        }
        xc_json = xcresult_for_grid(grid, failure_texts)
        log_text = make_log(grid)
        table = gate.build_table(log_text, xc_json, expected_iterations=10)
        verdict = gate.evaluate_v3(table, 10)

        self.assertTrue(verdict["run_valid"])
        self.assertEqual(verdict["defect3"]["status"], "CAUGHT")
        self.assertEqual(verdict["defect3"]["sig_set"], ["C1-OFFSET|label=T19|centered=T16|strides=+3"])
        self.assertEqual(verdict["defect2_steps"], [])
        # 端點全 PASS 也滿足 R4 V5（每次結果 ∈ {PASS, FAIL{C2-STACK}}）
        self.assertTrue(gate.evaluate_v5(table, verdict, s2_verified=True)["ok"])

    def test_defect2_settled_symptom_detection(self):
        grid = all_pass_grid(n=10)
        grid["T4"] = [
            [
                "GATE{T4.s1|PASS}",
                "GATE{T4.s2|FAIL|C2-STACK}",
            ]
            for _ in range(10)
        ]
        failure_texts = {
            ("T4", i, "s2"): ["SIG{T4.s2|C2-STACK|G=T16|over=T15|side=L}"] for i in range(1, 11)
        }
        xc_json = xcresult_for_grid(grid, failure_texts)
        log_text = make_log(grid)
        table = gate.build_table(log_text, xc_json, expected_iterations=10)
        verdict = gate.evaluate_v3(table, 10)

        self.assertEqual(verdict["defect3"]["status"], "NOT_CAUGHT")
        self.assertIn(("T4", "s2", ["C2-STACK|G=T16|over=T15|side=L"]), verdict["defect2_steps"])

    def test_inconsistent_step_9_fail_1_pass(self):
        grid = all_pass_grid(n=10)
        step_lines = []
        for i in range(10):
            if i == 4:  # 第 5 次（0-indexed 4）唯一一次 PASS
                step_lines.append(["GATE{T4.s1|PASS}", "GATE{T4.s2|PASS}"])
            else:
                step_lines.append(["GATE{T4.s1|PASS}", "GATE{T4.s2|FAIL|C1-OFFSET}"])
        grid["T4"] = step_lines
        failure_texts = {
            ("T4", i, "s2"): ["SIG{T4.s2|C1-OFFSET|label=T19|centered=T16|strides=+3}"]
            for i in range(1, 11)
            if i != 5
        }
        xc_json = xcresult_for_grid(grid, failure_texts)
        log_text = make_log(grid)
        table = gate.build_table(log_text, xc_json, expected_iterations=10)
        verdict = gate.evaluate_v3(table, 10)

        self.assertEqual(verdict["per_step"][("T4", "s2")]["status"], "INCONSISTENT")
        self.assertEqual(verdict["defect3"]["status"], "UNSTABLE")
        self.assertTrue(verdict["run_valid"])  # 不一致不等於 PROBE/UNTAGGED，run 本身仍有效

    def test_v3_run_invalid_when_probe_present(self):
        grid = all_pass_grid(n=3)
        grid["T4"] = [
            ["GATE{T4.s1|PASS}", "GATE{T4.s2|FAIL|PROBE-AX}"] for _ in range(3)
        ]
        failure_texts = {("T4", i, "s2"): ["[PROBE-AX] 逾時"] for i in range(1, 4)}
        xc_json = xcresult_for_grid(grid, failure_texts)
        log_text = make_log(grid)
        table = gate.build_table(log_text, xc_json, expected_iterations=3)
        verdict = gate.evaluate_v3(table, 3)
        self.assertFalse(verdict["run_valid"])


class V3R4Tests(unittest.TestCase):
    def test_frozen_m0_is_consistent_and_catches_both_defects(self):
        v3 = gate.evaluate_v3(m0_run(), 10)
        self.assertTrue(v3["run_valid"])
        self.assertTrue(v3["consistency_ok"])
        self.assertIsNone(v3["excluded"])
        self.assertEqual(v3["defect3"]["status"], "CAUGHT")
        self.assertTrue(v3["defect2_reproduced"])
        self.assertEqual(
            {(t, s) for t, s, _ in v3["defect2_steps"]},
            {("T1", "s2"), ("T1", "s3"), ("T2", "s2"), ("T2", "s3"), ("T4", "s1"), ("T4", "s2")},
        )

    def test_single_c2_step_9_fail_1_pass_is_excluded(self):
        v3 = gate.evaluate_v3(m0_run(overrides={("T2", "s2"): pass_at(4)([C2[("T2", "s2")]])}), 10)
        self.assertTrue(v3["consistency_ok"])
        self.assertEqual(v3["excluded"], ("T2", "s2"))
        self.assertNotIn(("T2", "s2"), [(t, s) for t, s, _ in v3["defect2_steps"]])

    def test_single_c2_step_1_fail_9_pass_is_also_excluded(self):
        mostly_pass = lambda i: [C2[("T2", "s2")]] if i == 1 else None  # noqa: E731
        v3 = gate.evaluate_v3(m0_run(overrides={("T2", "s2"): mostly_pass}), 10)
        self.assertEqual(v3["excluded"], ("T2", "s2"))
        self.assertTrue(v3["consistency_ok"])

    def test_registered_c2_step_all_pass_is_consistent_not_excluded(self):
        v3 = gate.evaluate_v3(m0_run(overrides={("T2", "s2"): None}), 10)
        self.assertIsNone(v3["excluded"])
        self.assertTrue(v3["consistency_ok"])
        self.assertEqual(v3["per_step"][("T2", "s2")]["status"], "ALL_PASS")

    def test_two_inconsistent_steps_fail_consistency(self):
        v3 = gate.evaluate_v3(
            m0_run(overrides={
                ("T2", "s2"): pass_at(4)([C2[("T2", "s2")]]),
                ("T1", "s3"): pass_at(1, 2, 3, 4, 5)([C2[("T1", "s3")]]),
            }),
            10,
        )
        self.assertFalse(v3["consistency_ok"])
        self.assertIsNone(v3["excluded"])
        self.assertEqual(set(v3["inconsistent"]), {("T2", "s2"), ("T1", "s3")})

    def test_inconsistency_with_another_code_is_not_excludable(self):
        other = lambda i: ["SIG{T2.s2|C1-OFFSET|label=T00|centered=T01|strides=-1}"] if i == 2 else [C2[("T2", "s2")]]  # noqa: E731
        v3 = gate.evaluate_v3(m0_run(overrides={("T2", "s2"): other}), 10)
        self.assertFalse(v3["consistency_ok"])
        self.assertIsNone(v3["excluded"])

    def test_inconsistent_step_registered_pass_is_not_excludable(self):
        flaky = lambda i: ["SIG{T1.s1|C2-STACK|G=T11|over=T10|side=L}"] if i == 7 else None  # noqa: E731
        v3 = gate.evaluate_v3(m0_run(overrides={("T1", "s1"): flaky}), 10)
        self.assertFalse(v3["consistency_ok"])
        self.assertIsNone(v3["excluded"])

    def test_defect3_unstable_when_t4s2_flips(self):
        v3 = gate.evaluate_v3(m0_run(overrides={("T4", "s2"): pass_at(6)([T4S2_OFFSET, T4S2_STACK])}), 10)
        self.assertEqual(v3["defect3"]["status"], "UNSTABLE")

    def test_defect3_not_caught_without_defect3_code(self):
        v3 = gate.evaluate_v3(m0_run(overrides={("T4", "s2"): [T4S2_STACK]}), 10)
        self.assertEqual(v3["defect3"]["status"], "NOT_CAUGHT")
        self.assertTrue(v3["defect2_reproduced"])

    def test_defect2_not_reproducible_when_every_c2_step_is_green(self):
        overrides = {step: None for step in C2}
        overrides[("T4", "s2")] = [T4S2_OFFSET]
        v3 = gate.evaluate_v3(m0_run(overrides=overrides), 10)
        self.assertFalse(v3["defect2_reproduced"])
        self.assertEqual(v3["defect3"]["status"], "CAUGHT")


if __name__ == "__main__":
    unittest.main()
