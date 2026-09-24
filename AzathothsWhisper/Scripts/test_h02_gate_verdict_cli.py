#!/usr/bin/env python3
"""h02_gate_eval.py 的單元測試：R4-C 結論與 CLI（拆自 `test_h02_gate_eval.py`）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_gate*.py'
"""
from __future__ import annotations

import unittest

import h02_gate_eval as gate
from test_h02_gate_fixtures import C2, MUTANT_KILLED, T4S2_OFFSET, T4S2_STACK, TESTDATA, m0_run, pass_at


class VerdictR4Tests(unittest.TestCase):
    def _verdict(self, m0=None, m2=None, m3=None, s2_verified=True):
        return gate.verdict(
            m0 or m0_run(),
            m2 or m0_run(n=3, overrides=MUTANT_KILLED),
            m3 or m0_run(n=3, overrides=MUTANT_KILLED),
            s2_verified=s2_verified,
        )

    def test_pass_when_everything_holds(self):
        self.assertEqual(self._verdict()["conclusion"], "通過")

    def test_pass_with_one_excluded_step(self):
        m0 = m0_run(overrides={("T2", "s2"): pass_at(4)([C2[("T2", "s2")]])})
        self.assertEqual(self._verdict(m0=m0)["conclusion"], "通過")

    def test_invalid_mutant_run_is_undecidable(self):
        mutant = m0_run(n=3, overrides=MUTANT_KILLED, drop_tests=("T3",))
        self.assertEqual(self._verdict(m3=mutant)["conclusion"], "不可判定")

    def test_v5_failure_is_undecidable_even_if_defect3_unstable(self):
        m0 = m0_run(overrides={
            ("T2", "s1"): MUTANT_KILLED[("T2", "s1")],
            ("T4", "s2"): pass_at(6)([T4S2_OFFSET, T4S2_STACK]),
        })
        self.assertEqual(self._verdict(m0=m0)["conclusion"], "不可判定")

    def test_unstable_defect3_is_fail(self):
        m0 = m0_run(overrides={("T4", "s2"): pass_at(6)([T4S2_OFFSET, T4S2_STACK])})
        self.assertEqual(self._verdict(m0=m0)["conclusion"], "不通過")

    def test_two_inconsistent_steps_is_partial(self):
        m0 = m0_run(overrides={
            ("T2", "s2"): pass_at(4)([C2[("T2", "s2")]]),
            ("T1", "s3"): pass_at(1, 2, 3, 4, 5)([C2[("T1", "s3")]]),
        })
        self.assertEqual(self._verdict(m0=m0)["conclusion"], "部分通過")

    def test_unkilled_mutant_is_partial(self):
        self.assertEqual(self._verdict(m3=m0_run(n=3))["conclusion"], "部分通過")

    def test_defect2_not_reproducible_is_partial(self):
        overrides = {step: None for step in C2}
        overrides[("T4", "s2")] = [T4S2_OFFSET]
        self.assertEqual(self._verdict(m0=m0_run(overrides=overrides))["conclusion"], "部分通過")


class CLITests(unittest.TestCase):
    def test_main_table_command_exit_zero(self):
        log_path = TESTDATA / "all_pass.log"
        xc_path = TESTDATA / "all_pass.xcresult.json"
        rc = gate.main(["table", "--log", str(log_path), "--xcresult", str(xc_path)])
        self.assertEqual(rc, 0)

    def test_main_missing_file_exits_two(self):
        rc = gate.main(
            ["table", "--log", "/no/such/file.log", "--xcresult", "/no/such/file.json"]
        )
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
