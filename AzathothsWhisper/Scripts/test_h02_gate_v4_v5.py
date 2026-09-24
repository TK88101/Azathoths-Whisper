#!/usr/bin/env python3
"""h02_gate_eval.py 的單元測試：V4／V5 判定（拆自 `test_h02_gate_eval.py`）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_gate*.py'
"""
from __future__ import annotations

import unittest

import h02_gate_eval as gate
from test_h02_gate_fixtures import (
    C2,
    MUTANT_KILLED,
    all_pass_grid,
    m0_run,
    make_log,
    pass_at,
    xcresult_for_grid,
)


class V4Tests(unittest.TestCase):
    def test_kill_step(self):
        base_grid = all_pass_grid(n=10)
        base_xc = xcresult_for_grid(base_grid)
        base_log = make_log(base_grid)
        baseline = gate.build_table(base_log, base_xc, expected_iterations=10)

        mut_grid = all_pass_grid(n=3)
        mut_grid["T4"] = [
            ["GATE{T4.s1|PASS}", "GATE{T4.s2|FAIL|C1-OFFSET}"] for _ in range(3)
        ]
        mut_failures = {
            ("T4", i, "s2"): ["SIG{T4.s2|C1-OFFSET|label=T19|centered=T16|strides=+3}"]
            for i in range(1, 4)
        }
        mut_xc = xcresult_for_grid(mut_grid, mut_failures)
        mut_log = make_log(mut_grid)
        mutant = gate.build_table(mut_log, mut_xc, expected_iterations=3)

        verdict = gate.evaluate_v4(baseline, mutant)
        self.assertEqual(verdict["verdict"], "OK")
        killed_keys = [(t, s) for t, s, _ in verdict["killed"]]
        self.assertIn(("T4", "s2"), killed_keys)

    def test_no_kill_because_baseline_already_failing(self):
        base_grid = all_pass_grid(n=10)
        base_grid["T1"] = [
            ["GATE{T1.s1|PASS}", "GATE{T1.s2|FAIL|C4-NO-WRITEBACK}", "GATE{T1.s3|PASS}"]
            for _ in range(10)
        ]
        base_failures = {
            ("T1", i, "s2"): ["SIG{T1.s2|C4-NO-WRITEBACK}"] for i in range(1, 11)
        }
        base_xc = xcresult_for_grid(base_grid, base_failures)
        base_log = make_log(base_grid)
        baseline = gate.build_table(base_log, base_xc, expected_iterations=10)

        mut_grid = all_pass_grid(n=3)
        mut_grid["T1"] = [
            ["GATE{T1.s1|PASS}", "GATE{T1.s2|FAIL|C4-NO-WRITEBACK}", "GATE{T1.s3|PASS}"]
            for _ in range(3)
        ]
        mut_failures = {("T1", i, "s2"): ["SIG{T1.s2|C4-NO-WRITEBACK}"] for i in range(1, 4)}
        mut_xc = xcresult_for_grid(mut_grid, mut_failures)
        mut_log = make_log(mut_grid)
        mutant = gate.build_table(mut_log, mut_xc, expected_iterations=3)

        verdict = gate.evaluate_v4(baseline, mutant)
        survived_keys = [(t, s) for t, s, _ in verdict["survived"]]
        self.assertIn(("T1", "s2"), survived_keys)
        killed_keys = [(t, s) for t, s, _ in verdict["killed"]]
        self.assertNotIn(("T1", "s2"), killed_keys)

    def test_v4_invalid_mutant_run(self):
        base_grid = all_pass_grid(n=10)
        base_xc = xcresult_for_grid(base_grid)
        base_log = make_log(base_grid)
        baseline = gate.build_table(base_log, base_xc, expected_iterations=10)

        mut_grid = all_pass_grid(n=3)
        mut_grid["T4"] = [
            ["GATE{T4.s1|PASS}", "GATE{T4.s2|FAIL|PROBE-AX}"] for _ in range(3)
        ]
        mut_failures = {("T4", i, "s2"): ["[PROBE-AX] 逾時"] for i in range(1, 4)}
        mut_xc = xcresult_for_grid(mut_grid, mut_failures)
        mut_log = make_log(mut_grid)
        mutant = gate.build_table(mut_log, mut_xc, expected_iterations=3)

        verdict = gate.evaluate_v4(baseline, mutant)
        self.assertEqual(verdict["verdict"], "MUTANT_RUN_INVALID")
        self.assertEqual(verdict["killed"], [])
        self.assertEqual(verdict["survived"], [])


class V4R4Tests(unittest.TestCase):
    def test_kill_on_m0_green_steps(self):
        v4 = gate.evaluate_v4(m0_run(), m0_run(n=3, overrides=MUTANT_KILLED))
        self.assertEqual(v4["verdict"], "OK")
        self.assertEqual({(t, s) for t, s, _ in v4["killed"]}, {("T1", "s1"), ("T2", "s1")})

    def test_baseline_with_errors_is_invalid(self):
        baseline = m0_run()
        baseline.errors.append("forced cross-check error")
        self.assertEqual(gate.evaluate_v4(baseline, m0_run(n=3, overrides=MUTANT_KILLED))["verdict"], "BASELINE_RUN_INVALID")

    def test_mutant_missing_a_test_is_invalid(self):
        mutant = m0_run(n=3, overrides=MUTANT_KILLED, drop_tests=("T3",))
        self.assertEqual(gate.evaluate_v4(m0_run(), mutant)["verdict"], "MUTANT_RUN_INVALID")

    def test_mutant_identical_to_baseline_is_not_killed(self):
        v4 = gate.evaluate_v4(m0_run(), m0_run(n=3))
        self.assertEqual(v4["verdict"], "OK")
        self.assertEqual(v4["killed"], [])


class V5R4Tests(unittest.TestCase):
    def _v5(self, table, s2_verified=True):
        return gate.evaluate_v5(table, gate.evaluate_v3(table, 10), s2_verified=s2_verified)

    def test_frozen_m0_satisfies_v5_via_c2_only_endpoints(self):
        v5 = self._v5(m0_run())
        self.assertTrue(v5["ok"], v5)
        self.assertIn(("T2", "s3"), v5["endpoint_steps_ok"])

    def test_other_product_code_at_endpoints_fails_v5(self):
        def with_target_miss(label, step):
            sig = C2[(label, step)]
            miss = f"SIG{{{label}.{step}|C3-TARGET-MISS|want=T19|got=T18}}"
            return lambda i: [sig, miss] if i == 1 else [sig]

        overrides = {step: with_target_miss(*step) for step in gate.ENDPOINT_STEPS}
        self.assertFalse(self._v5(m0_run(overrides=overrides))["ok"])

    def test_excluded_endpoint_cannot_serve_v5(self):
        def spoiled(label, step):
            return lambda i: [C2[(label, step)], f"SIG{{{label}.{step}|C3-TARGET-MISS|want=T19|got=T18}}"]

        table = m0_run(overrides={
            ("T2", "s2"): pass_at(4)([C2[("T2", "s2")]]),  # 唯一可豁免的不一致格
            ("T2", "s3"): spoiled("T2", "s3"),
            ("T4", "s1"): spoiled("T4", "s1"),
        })
        v5 = self._v5(table)
        self.assertFalse(v5["ok"])
        self.assertNotIn(("T2", "s2"), v5["endpoint_steps_ok"])

    def test_positive_control_t2s1_must_be_all_pass(self):
        table = m0_run(overrides={("T2", "s1"): MUTANT_KILLED[("T2", "s1")]})
        self.assertFalse(self._v5(table)["ok"])

    def test_s2_must_be_asserted(self):
        self.assertFalse(self._v5(m0_run(), s2_verified=False)["ok"])

    def test_invalid_table_fails_v5(self):
        self.assertFalse(self._v5(m0_run(drop_tests=("T3",)))["ok"])


if __name__ == "__main__":
    unittest.main()
