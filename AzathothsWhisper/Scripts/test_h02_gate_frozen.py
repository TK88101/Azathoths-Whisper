#!/usr/bin/env python3
"""h02_gate_eval.py 的單元測試：R4-F 凍結表相符（變體 N′，計劃 §6／§12 R5，2026-09-12）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_gate*.py'
"""
from __future__ import annotations

import contextlib
import io
import unittest

import h02_gate_eval as gate
from test_h02_gate_fixtures import C2, MUTANT_KILLED, T4S2_OFFSET, T4S2_STACK, m0_run, pass_at

C6_T3 = "SIG{T3.s1|C6-NEVER-SETTLES}"
SNAPBACK_T1S3 = "SIG{T1.s3|C4-SNAPBACK|from=T11|to=T12}"


def verdict(m0, mutant=None):
    mutant = mutant or m0_run(n=3, overrides=MUTANT_KILLED)
    return gate.verdict(m0, mutant, mutant, s2_verified=True)


class FrozenConformityTests(unittest.TestCase):
    def test_frozen_run_conforms_with_no_deviations(self):
        v3 = gate.evaluate_v3(m0_run(), 10)
        self.assertTrue(v3["frozen_conformity_ok"])
        self.assertEqual(v3["frozen_conformity_reasons"], [])
        self.assertEqual(v3["frozen_deviations"], [])

    def test_ce1_stable_c6_on_frozen_pass_step_is_undecidable(self):
        v = verdict(m0_run(overrides={("T3", "s1"): [C6_T3]}))
        self.assertEqual(v["conclusion"], "不可判定")
        self.assertTrue(any("R4-F" in r and "T3.s1" in r and "C6-NEVER-SETTLES" in r for r in v["reasons"]), v["reasons"])

    def test_ce2_stable_extra_code_on_frozen_c2_step_is_undecidable(self):
        v = verdict(m0_run(overrides={("T1", "s3"): [C2[("T1", "s3")], SNAPBACK_T1S3]}))
        self.assertEqual(v["conclusion"], "不可判定")
        self.assertTrue(any("C4-SNAPBACK" in r for r in v["reasons"]), v["reasons"])

    def test_single_iteration_with_foreign_code_is_also_undecidable(self):
        # 不是只擋「穩定」的新碼：1/10 出現 F 外碼同樣與預登記矛盾
        once = lambda i: [C2[("T1", "s2")], "SIG{T1.s2|C4-REVERSAL|seq=T11>T12>T11}"] if i == 7 else [C2[("T1", "s2")]]  # noqa: E731
        v = verdict(m0_run(overrides={("T1", "s2"): once}))
        self.assertEqual(v["conclusion"], "不可判定")
        self.assertTrue(any("iter 7" in r for r in v["reasons"]), v["reasons"])

    def test_ce3_c3_instead_of_c1_at_t4s2_conforms(self):
        # §6 V3 明文接受 T4.s2 以 C1／C3／C5 之一抓缺陷 3 → F(T4.s2) 含 DEFECT3_CODES；與登記 {C1,C2} 不同只記偏離
        m0 = m0_run(overrides={("T4", "s2"): ["SIG{T4.s2|C3-TARGET-MISS|want=T19|got=T16}", T4S2_STACK]})
        v = verdict(m0)
        self.assertTrue(v["v3"]["frozen_conformity_ok"])
        self.assertEqual(v["conclusion"], "通過")
        self.assertTrue(any("T4.s2" in d for d in v["v3"]["frozen_deviations"]), v["v3"]["frozen_deviations"])

    def test_ce4_ce5_all_pass_flip_conforms_records_deviation_and_keeps_v5_candidate(self):
        v = verdict(m0_run(overrides={("T2", "s2"): None, ("T1", "s3"): None}))
        v3 = v["v3"]
        self.assertTrue(v3["frozen_conformity_ok"])
        self.assertEqual(v["conclusion"], "通過")
        self.assertTrue(any(d.startswith("T2.s2") and "10/10" in d for d in v3["frozen_deviations"]), v3["frozen_deviations"])
        self.assertTrue(any(d.startswith("T1.s3") for d in v3["frozen_deviations"]))
        self.assertIn(("T2", "s2"), v["v5"]["endpoint_steps_ok"])

    def test_legal_r4x_mix_conforms(self):
        m0 = m0_run(overrides={("T2", "s2"): pass_at(4)([C2[("T2", "s2")]])})
        v = verdict(m0)
        self.assertTrue(v["v3"]["frozen_conformity_ok"])
        self.assertEqual(v["v3"]["excluded"], ("T2", "s2"))
        self.assertEqual(v["conclusion"], "通過")

    def test_all_c2_steps_pass_is_partial_not_undecidable(self):
        overrides = {step: None for step in C2}
        overrides[("T4", "s2")] = [T4S2_OFFSET]
        v = verdict(m0_run(overrides=overrides))
        self.assertTrue(v["v3"]["frozen_conformity_ok"])
        self.assertEqual(v["conclusion"], "部分通過")

    def test_mutant_new_codes_are_not_subject_to_r4f(self):
        mutant = m0_run(n=3, overrides={
            ("T1", "s1"): ["SIG{T1.s1|C4-SNAPBACK|from=T11|to=T12}"],
            ("T2", "s1"): ["SIG{T2.s1|C6-NEVER-SETTLES}"],
            ("T3", "s1"): ["SIG{T3.s1|C0-BLANK-SIDE}"],
        })
        v = gate.verdict(m0_run(), mutant, mutant, s2_verified=True)
        self.assertEqual(v["conclusion"], "通過")
        self.assertTrue(v["v4"]["M2"]["killed"])

    def test_frozen_tables_cover_every_registered_step_and_only_product_codes(self):
        for label, steps in gate.STEPS.items():
            for step in steps:
                self.assertIn((label, step), gate.FROZEN_REGISTRATION)
                self.assertIn((label, step), gate.FROZEN_ALLOWED_CODES)
        self.assertEqual(
            gate.FROZEN_ALLOWED_CODES[("T4", "s2")],
            frozenset({"C1-OFFSET", "C3-TARGET-MISS", "C5-DRIFT", "C2-STACK"}),
        )
        self.assertEqual(gate.FROZEN_ALLOWED_CODES[("T1", "s2")], frozenset({"C2-STACK"}))
        self.assertEqual(gate.FROZEN_ALLOWED_CODES[("T3", "s1")], frozenset())
        self.assertTrue(all(codes <= gate.PRODUCT_CODES for codes in gate.FROZEN_ALLOWED_CODES.values()))


class FrozenConformityCLITests(unittest.TestCase):
    """第三輪辯論補正：三個新欄位必須出現在 v3／verdict 輸出，否則偏離只存在於記憶體裡。"""

    def test_print_v3_shows_conformity_and_deviations(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            gate._print_v3(gate.evaluate_v3(m0_run(overrides={("T2", "s2"): None}), 10))
        out = buf.getvalue()
        self.assertIn("frozen_conformity_ok: True", out)
        self.assertIn("T2.s2", out)

    def test_print_verdict_shows_r4f_reason(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            gate._print_verdict(verdict(m0_run(overrides={("T3", "s1"): [C6_T3]})))
        out = buf.getvalue()
        self.assertIn("不可判定", out)
        self.assertIn("R4-F", out)
        self.assertIn("frozen_conformity_ok: False", out)


if __name__ == "__main__":
    unittest.main()
