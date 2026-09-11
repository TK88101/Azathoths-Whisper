#!/usr/bin/env python3
"""h02_gate_eval.py 的單元測試：R4 三視角對抗核查（拆自 `test_h02_gate_eval.py`）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_gate*.py'
"""
from __future__ import annotations

import unittest

import h02_gate_eval as gate
from test_h02_gate_fixtures import C2, FROZEN_M0, MUTANT_KILLED, T4S2_OFFSET, m0_run, pass_at


class R4RefutationTests(unittest.TestCase):
    """三視角對抗核查（2026-09-11，Opus 5 ×3）抓到的判定器缺陷；每條都能改變閘門結論。"""

    TWO_SIDED_STACK = [
        "SIG{T1.s2|C2-STACK|G=T13|over=T12|side=L}",
        "SIG{T1.s2|C2-STACK|G=T13|over=T14|side=R}",
    ]

    def test_same_product_code_on_both_sides_stays_valid(self):
        # Swift 產出端把 GATE 碼去重、每個 finding 一條 SIG（CoverFlowGateLogicTests.bothSidesAreReportedIndependently）
        table = m0_run(overrides={("T1", "s2"): self.TWO_SIDED_STACK})
        valid, reasons = gate.table_valid(table, 10)
        self.assertTrue(valid, reasons)
        v3 = gate.evaluate_v3(table, 10)
        self.assertIn(("T1", "s2"), [(t, s) for t, s, _ in v3["defect2_steps"]])

    def test_gate_line_from_another_test_does_not_fill_a_missing_step(self):
        table = m0_run(log_mutator=lambda t: t.replace("GATE{T1.s1|", "GATE{T2.s1|"))
        valid, reasons = gate.table_valid(table, 10)
        self.assertFalse(valid)
        self.assertTrue(any("T1" in r and ("MISSING" in r or "T2.s1" in r) for r in reasons), reasons)

    def test_sig_from_another_test_is_not_evidence(self):
        # SIG 的 `<test>.` 前綴同樣必須是本測試；否則別的測試的簽名可頂替本測試的證據
        base = {key: None for key in FROZEN_M0}
        base[("T1", "s2")] = ["SIG{T2.s2|C2-STACK|G=T13|over=T12|side=L}"]
        base[("T4", "s2")] = [T4S2_OFFSET]
        table = m0_run(base=base)
        valid, reasons = gate.table_valid(table, 10)
        self.assertFalse(valid)
        self.assertTrue(any("前綴" in r for r in reasons), reasons)
        mutant = m0_run(n=3, base=base, overrides=MUTANT_KILLED)
        self.assertEqual(gate.verdict(table, mutant, mutant, s2_verified=True)["conclusion"], "不可判定")

    def test_orphan_finish_line_cannot_offset_an_unclosed_start(self):
        method = gate.TEST_LABELS["T3"]
        start = f"Test Case '-[AzathothsWhisperUITests.CoverFlowUITests {method}]' started."
        finish = f"Test Case '-[AzathothsWhisperUITests.CoverFlowUITests {method}]' passed (1.0 seconds)."

        def swap_first_pair(text):  # 收尾行跑到開始行之前：總數仍相等，但配對是壞的
            return text.replace(
                f"{start}\nGATE{{T3.s1|PASS}}\n{finish}", f"{finish}\n{start}\nGATE{{T3.s1|PASS}}", 1
            )

        valid, reasons = gate.table_valid(m0_run(log_mutator=swap_first_pair), 10)
        self.assertFalse(valid)
        self.assertTrue(any("成對" in r or "收尾" in r for r in reasons), reasons)

    def test_started_without_finish_line_is_invalid(self):
        method = gate.TEST_LABELS["T3"]

        def drop_one_finish(text):
            lines = text.splitlines()
            for i, line in enumerate(lines):
                if method in line and "' passed" in line:
                    del lines[i]
                    break
            return "\n".join(lines) + "\n"

        valid, reasons = gate.table_valid(m0_run(log_mutator=drop_one_finish), 10)
        self.assertFalse(valid)
        self.assertTrue(any("成對" in r for r in reasons), reasons)

    def test_inconsistent_endpoint_cannot_be_the_positive_control(self):
        spoiled = lambda label, step: [C2[(label, step)], f"SIG{{{label}.{step}|C3-TARGET-MISS|want=T19|got=T18}}"]  # noqa: E731
        overrides = {
            ("T2", "s2"): pass_at(4)([C2[("T2", "s2")]]),  # 時紅時綠的端點
            ("T2", "s3"): spoiled("T2", "s3"),
            ("T4", "s1"): spoiled("T4", "s1"),
        }
        alone = m0_run(overrides=overrides)
        # 再加一個與 R4-X 無關的不一致格，不得反而讓上面那格變成合格端點（單調性）
        flaky_t3 = lambda i: ["SIG{T3.s1|C2-STACK|G=T10|over=T09|side=L}"] if i == 2 else None  # noqa: E731
        with_extra_flake = m0_run(overrides={**overrides, ("T3", "s1"): flaky_t3})
        for table in (alone, with_extra_flake):
            v5 = gate.evaluate_v5(table, gate.evaluate_v3(table, 10), s2_verified=True)
            self.assertFalse(v5["ok"], v5)
            self.assertNotIn(("T2", "s2"), v5["endpoint_steps_ok"])

    def test_fail_gate_without_codes_cannot_kill(self):
        # GATE 說 FAIL 卻沒有碼、也沒有任何失敗訊息 → 簽名集合為空，不得算作「殺死」
        mutant = m0_run(
            n=3,
            overrides={("T1", "s1"): MUTANT_KILLED[("T1", "s1")]},
            log_mutator=lambda t: t.replace("GATE{T2.s1|PASS}", "GATE{T2.s1|FAIL|}"),
        )
        valid, reasons = gate.table_valid(mutant, 3)
        self.assertFalse(valid, reasons)
        self.assertEqual(gate.evaluate_v4(m0_run(), mutant)["verdict"], "MUTANT_RUN_INVALID")


if __name__ == "__main__":
    unittest.main()
