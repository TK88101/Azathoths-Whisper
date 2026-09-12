#!/usr/bin/env python3
"""h02_gate_eval.py 的單元測試：判定表建構與 table_valid（拆自 `test_h02_gate_eval.py`）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_gate*.py'
"""
from __future__ import annotations

import unittest

import h02_gate_eval as gate
from test_h02_gate_fixtures import MISSING, load_fixture, make_xcresult, m0_run, repetitions_of


class TableBuildingTests(unittest.TestCase):
    def test_all_pass_run(self):
        log_text, xc_json = load_fixture("all_pass")
        table = gate.build_table(log_text, xc_json, expected_iterations=1)
        infos = table.iterations["T4"]
        self.assertEqual(len(infos), 1)
        info = infos[0]
        self.assertFalse(info.invalid)
        self.assertEqual(info.cells["s1"].kind, "PASS")
        self.assertEqual(info.cells["s2"].kind, "PASS")
        self.assertEqual(table.errors, [])
        self.assertEqual(table.iteration_count_mismatch, {})

    def test_sig_failure_matches_gate_single_code(self):
        log_text, xc_json = load_fixture("sig_fail_single")
        table = gate.build_table(log_text, xc_json, expected_iterations=1)
        info = table.iterations["T4"][0]
        self.assertFalse(info.invalid)
        cell = info.cells["s2"]
        self.assertEqual(cell.kind, "FAIL")
        self.assertEqual(
            cell.sig_set, frozenset({"C1-OFFSET|label=T19|centered=T16|strides=+3"})
        )
        self.assertEqual(table.errors, [])

    def test_two_sigs_at_same_step(self):
        log_text, xc_json = load_fixture("sig_fail_double")
        table = gate.build_table(log_text, xc_json, expected_iterations=1)
        info = table.iterations["T4"][0]
        self.assertFalse(info.invalid)
        cell = info.cells["s2"]
        self.assertEqual(cell.kind, "FAIL")
        self.assertEqual(
            cell.sig_set,
            frozenset(
                {
                    "C1-OFFSET|label=T19|centered=T16|strides=+3",
                    "C2-STACK|G=T16|over=T15|side=L",
                }
            ),
        )
        self.assertEqual(table.errors, [])

    def test_untagged_failure_invalidates_iteration(self):
        log_text, xc_json = load_fixture("untagged_fail")
        table = gate.build_table(log_text, xc_json, expected_iterations=1)
        info = table.iterations["T4"][0]
        self.assertTrue(info.invalid)
        # GATE 兩步都 PASS，不受未標籤失敗牽連改變 cell 狀態本身
        self.assertEqual(info.cells["s1"].kind, "PASS")
        self.assertEqual(info.cells["s2"].kind, "PASS")
        self.assertEqual(len(info.unattributed), 1)
        self.assertEqual(info.unattributed[0].kind, "UNTAGGED")

    def test_unattributed_teardown_probe_trace_invalidates_iteration(self):
        # R5-4 Round 2 P1 ②：tearDown 全檔 audit 以未歸屬的 [PROBE-TRACE] 上報（不印 GATE 行）；
        # 實證（2026-09-12，-test-iterations 2）：XCTFail 掛在該次 Repetition 下、該次 result=Failed
        def fail_only_first(xc_json):
            for rep in repetitions_of(xc_json, gate.TEST_LABELS["T3"])[:1]:
                rep["result"] = "Failed"
                rep.setdefault("children", []).append({
                    "nodeType": "Failure Message",
                    "name": "CoverFlowUITests.swift:42: failed - [PROBE-TRACE] T3.audit write-error:errno=28",
                })
        table = m0_run(xc_mutator=fail_only_first)
        first = table.iterations["T3"][0]
        self.assertTrue(first.invalid)
        self.assertIn("未歸屬的 [PROBE-TRACE]", first.invalid_reasons)
        self.assertEqual(first.cells["s1"].kind, "PASS")
        self.assertFalse(any("GATE 引用未知步驟" in e for e in table.errors), table.errors)
        self.assertFalse(gate.table_valid(table, 10)[0])
        self.assertFalse(table.iterations["T3"][1].invalid)

    def test_probe_invalidates_iteration_and_tags_step(self):
        log_text, xc_json = load_fixture("probe_fail")
        table = gate.build_table(log_text, xc_json, expected_iterations=1)
        info = table.iterations["T4"][0]
        self.assertTrue(info.invalid)
        cell = info.cells["s2"]
        self.assertEqual(cell.kind, "PROBE")
        self.assertEqual(cell.probe_names, ("PROBE-AX",))
        self.assertEqual(info.unattributed, ())  # PROBE 已透過 GATE 行歸屬到 s2
        self.assertEqual(table.errors, [])

    def test_mixed_probe_and_product_code_in_same_gate_line(self):
        log_text, xc_json = load_fixture("mixed_probe_and_sig")
        table = gate.build_table(log_text, xc_json, expected_iterations=1)
        info = table.iterations["T2"][0]
        self.assertTrue(info.invalid)
        cell = info.cells["s1"]
        self.assertEqual(cell.kind, "PROBE")
        self.assertIn("PROBE-OFFCARD", cell.probe_names)
        # 產品碼部分仍要能核對到 SIG
        self.assertEqual(cell.sig_set, frozenset({"C3-TARGET-MISS|want=T01|got=T19"}))
        self.assertEqual(info.cells["s2"].kind, "PASS")
        self.assertEqual(info.cells["s3"].kind, "PASS")
        self.assertEqual(table.errors, [])

    def test_gate_probe_token_without_matching_probe_message_is_an_error(self):
        log_text = (
            "Test Case '-[AzathothsWhisperUITests.CoverFlowUITests "
            "testReenteringTabKeepsCenteredCardCentered]' started.\n"
            "GATE{T4.s1|PASS}\n"
            "GATE{T4.s2|FAIL|PROBE-AX}\n"
            "Test Case '-[AzathothsWhisperUITests.CoverFlowUITests "
            "testReenteringTabKeepsCenteredCardCentered]' failed (1.0 seconds).\n"
        )
        xc_json = make_xcresult({"T4": [("Failed", [])]})  # 沒有任何失敗訊息
        table = gate.build_table(log_text, xc_json, expected_iterations=1)
        self.assertTrue(any("PROBE-AX" in e for e in table.errors))

    def test_gate_sig_mismatch_is_reported_as_error(self):
        log_text, xc_json = load_fixture("gate_sig_mismatch")
        table = gate.build_table(log_text, xc_json, expected_iterations=1)
        info = table.iterations["T4"][0]
        cell = info.cells["s2"]
        self.assertEqual(cell.kind, "FAIL")
        self.assertTrue(
            any("不一致" in e for e in table.errors),
            msg=f"errors={table.errors}",
        )

    def test_iteration_count_mismatch_detected(self):
        log_text, xc_json = load_fixture("all_pass")
        table = gate.build_table(log_text, xc_json, expected_iterations=2)
        self.assertEqual(table.iteration_count_mismatch.get("T4"), (2, 1))


class TableValidTests(unittest.TestCase):
    def test_frozen_m0_like_run_is_valid(self):
        valid, reasons = gate.table_valid(m0_run(), 10)
        self.assertTrue(valid, reasons)
        self.assertEqual(reasons, [])

    def test_missing_whole_test_is_invalid(self):
        valid, reasons = gate.table_valid(m0_run(drop_tests=("T3",)), 10)
        self.assertFalse(valid)
        self.assertTrue(any("T3" in r for r in reasons), reasons)

    def test_missing_gate_line_is_invalid(self):
        table = m0_run(overrides={("T1", "s1"): lambda i: MISSING if i == 3 else None})
        valid, reasons = gate.table_valid(table, 10)
        self.assertFalse(valid)
        self.assertTrue(any("MISSING" in r for r in reasons), reasons)

    def test_iteration_count_mismatch_is_invalid(self):
        self.assertFalse(gate.table_valid(m0_run(n=9), 10)[0])

    def test_passed_result_with_failing_gate_is_invalid(self):
        def mark_first_t4_repetition_passed(xc_json):
            repetitions_of(xc_json, gate.TEST_LABELS["T4"])[0]["result"] = "Passed"

        valid, reasons = gate.table_valid(m0_run(xc_mutator=mark_first_t4_repetition_passed), 10)
        self.assertFalse(valid)
        self.assertTrue(any("Passed" in r for r in reasons), reasons)

    def test_skipped_result_is_invalid(self):
        def mark_first_t3_repetition_skipped(xc_json):
            repetitions_of(xc_json, gate.TEST_LABELS["T3"])[0]["result"] = "Skipped"

        self.assertFalse(gate.table_valid(m0_run(xc_mutator=mark_first_t3_repetition_skipped), 10)[0])

    def test_cross_check_errors_make_the_table_invalid(self):
        # 交叉核對錯誤（GATE 碼與 SIG 碼對不上等）由 build_table 記入 errors；有任何一條即整表無效
        table = m0_run()
        table.errors.append("T1 iter 1 s2: GATE 產品碼 ['C2-STACK'] 與 SIG 碼 ['C1-OFFSET'] 不一致")
        valid, reasons = gate.table_valid(table, 10)
        self.assertFalse(valid)
        self.assertTrue(any("不一致" in r for r in reasons), reasons)


if __name__ == "__main__":
    unittest.main()
