#!/usr/bin/env python3
"""F1 判定器單測：C.1 候選閘門、C.2 負對照、§5.7 (7) 證據完整性。

依據 `docs/plans/2026-09-13-coverflow-h02-fix4.md` §5（通用定義）、§5.1、§5.2、§5.7 (5)(7)、§7、§11。
執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_*.py'
"""
from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import h02_gate_eval as gate
from test_h02_gate_fixtures import (
    M2_KILL,
    M3_KILL,
    PROBE_T1S1,
    UNTAGGED_T1S1,
    at_manifest,
    candidate_run,
    write_evidence,
    write_run,
)

C2_T1S2 = "SIG{T1.s2|C2-STACK|G=T13|over=T12|side=L}"
C2_T2S2 = "SIG{T2.s2|C2-STACK|G=T00|over=T01|side=R}"
C1_T4S2 = "SIG{T4.s2|C1-OFFSET|label=T19|centered=T16|strides=+3}"


def only_at(iteration, sigs):
    """指定迭代 FAIL（帶 sigs），其餘 PASS。"""
    return lambda i: sigs if i == iteration else None


def probe_iteration(iteration):
    return lambda i: [PROBE_T1S1] if i == iteration else None


class EvidenceTests(unittest.TestCase):
    """§5.7 (7) 證據完整性：manifest 份數連號、引用檔存在、md5 相符。"""

    def evidence(self, iterations=3, **kwargs):
        root = Path(self.tmp) / "ev"
        return write_evidence(root, iterations, **kwargs)

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def test_complete_evidence_is_ok(self):
        ok, reasons = gate.evaluate_evidence(str(self.evidence(3)), 3)
        self.assertTrue(ok, reasons)
        self.assertEqual(reasons, [])

    def test_sampler_null_is_allowed(self):
        root = self.evidence(2, with_sampler=False)
        manifest = json.loads((root / "T1-1.manifest.json").read_text(encoding="utf-8"))
        self.assertIsNone(manifest["files"]["sampler"])
        ok, reasons = gate.evaluate_evidence(str(root), 2)
        self.assertTrue(ok, reasons)

    def test_sampler_present_is_checked(self):
        root = self.evidence(2, with_sampler=True)
        (root / "T3-2.sampler").unlink()
        ok, reasons = gate.evaluate_evidence(str(root), 2)
        self.assertFalse(ok)
        self.assertTrue(any("T3-2.sampler" in r for r in reasons), reasons)

    def test_missing_manifest_count(self):
        root = self.evidence(3, transform=at_manifest("T1", 3, lambda m: None))
        ok, reasons = gate.evaluate_evidence(str(root), 3)
        self.assertFalse(ok)
        self.assertTrue(any("T1" in r for r in reasons), reasons)

    def test_ordinals_must_be_consecutive_from_one(self):
        # 寫 1..3 後把 T2-2 改名成 T2-7：份數仍 3，但序號不連號
        root = self.evidence(3)
        (root / "T2-2.manifest.json").rename(root / "T2-7.manifest.json")
        ok, reasons = gate.evaluate_evidence(str(root), 3)
        self.assertFalse(ok)
        self.assertTrue(any("T2" in r for r in reasons), reasons)

    def test_referenced_file_missing(self):
        root = self.evidence(2)
        (root / "T4-1.marks").unlink()
        ok, reasons = gate.evaluate_evidence(str(root), 2)
        self.assertFalse(ok)
        self.assertTrue(any("T4-1.marks" in r for r in reasons), reasons)

    def test_md5_mismatch(self):
        bad = lambda m: dict(  # noqa: E731
            m, files=dict(m["files"], trace=dict(m["files"]["trace"], md5="0" * 32))
        )
        root = self.evidence(2, transform=at_manifest("T1", 2, bad))
        ok, reasons = gate.evaluate_evidence(str(root), 2)
        self.assertFalse(ok)
        self.assertTrue(any("T1-2.trace" in r and "md5" in r for r in reasons), reasons)

    def test_missing_directory(self):
        ok, reasons = gate.evaluate_evidence(str(Path(self.tmp) / "nope"), 3)
        self.assertFalse(ok)
        self.assertEqual(len(reasons), 1)

    def test_wrong_schema(self):
        root = self.evidence(1, transform=at_manifest("T1", 1, lambda m: dict(m, schema=2)))
        ok, reasons = gate.evaluate_evidence(str(root), 1)
        self.assertFalse(ok)
        self.assertTrue(any("schema" in r for r in reasons), reasons)

    def test_manifest_test_field_must_match_filename(self):
        root = self.evidence(1, transform=at_manifest("T1", 1, lambda m: dict(m, test="T9")))
        ok, reasons = gate.evaluate_evidence(str(root), 1)
        self.assertFalse(ok)
        self.assertTrue(any("T1-1" in r for r in reasons), reasons)

    def test_broken_json(self):
        root = self.evidence(1)
        (root / "T2-1.manifest.json").write_text("{not json", encoding="utf-8")
        ok, reasons = gate.evaluate_evidence(str(root), 1)
        self.assertFalse(ok)
        self.assertTrue(any("T2-1" in r for r in reasons), reasons)

    def test_escaping_path_is_rejected(self):
        escape = lambda m: dict(  # noqa: E731
            m, files=dict(m["files"], marks=dict(m["files"]["marks"], path="../outside.marks"))
        )
        root = self.evidence(1, transform=at_manifest("T1", 1, escape))
        ok, reasons = gate.evaluate_evidence(str(root), 1)
        self.assertFalse(ok)


class CandidateTests(unittest.TestCase):
    """§5.1 C.1：通過／不通過／無效三分。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def test_all_pass_is_pass(self):
        result = gate.evaluate_candidate(candidate_run(n=20), 20)
        self.assertEqual(result["conclusion"], "通過")
        self.assertEqual(result["failing_cells"], [])
        self.assertEqual(result["invalid_reasons"], [])
        self.assertIsNone(result["evidence_ok"])

    def test_all_pass_with_complete_evidence_is_pass(self):
        root = write_evidence(Path(self.tmp) / "ev", 20)
        result = gate.evaluate_candidate(candidate_run(n=20), 20, evidence=str(root))
        self.assertEqual(result["conclusion"], "通過")
        self.assertTrue(result["evidence_ok"])

    def test_all_pass_with_incomplete_evidence_is_invalid(self):
        root = write_evidence(Path(self.tmp) / "ev", 20, transform=at_manifest("T2", 5, lambda m: None))
        result = gate.evaluate_candidate(candidate_run(n=20), 20, evidence=str(root))
        self.assertEqual(result["conclusion"], "無效")
        self.assertFalse(result["evidence_ok"])
        self.assertTrue(result["run_valid"])
        self.assertTrue(any("T2" in r for r in result["invalid_reasons"]), result["invalid_reasons"])

    def test_single_c2_cell_is_fail(self):
        table = candidate_run(n=20, overrides={("T1", "s2"): only_at(7, [C2_T1S2])})
        result = gate.evaluate_candidate(table, 20)
        self.assertEqual(result["conclusion"], "不通過")
        self.assertEqual(
            result["failing_cells"],
            [("T1", "s2", 7, ("C2-STACK|G=T13|over=T12|side=L",))],
        )
        self.assertEqual(result["cell_count"], 180)

    def test_failure_counts_group_by_step_and_signature(self):
        table = candidate_run(
            n=20,
            overrides={
                ("T1", "s2"): lambda i: [C2_T1S2] if i in (3, 9) else None,
                ("T2", "s2"): only_at(4, [C2_T2S2]),
            },
        )
        result = gate.evaluate_candidate(table, 20)
        self.assertEqual(result["conclusion"], "不通過")
        self.assertEqual(result["failure_counts"][("T1.s2", ("C2-STACK|G=T13|over=T12|side=L",))], 2)
        self.assertEqual(result["failure_counts"][("T2.s2", ("C2-STACK|G=T00|over=T01|side=R",))], 1)
        self.assertEqual(len(result["failing_cells"]), 3)

    def test_defect3_code_also_fails(self):
        table = candidate_run(n=20, overrides={("T4", "s2"): only_at(1, [C1_T4S2])})
        result = gate.evaluate_candidate(table, 20)
        self.assertEqual(result["conclusion"], "不通過")
        self.assertTrue(any(cell[0:2] == ("T4", "s2") for cell in result["failing_cells"]))

    def test_probe_makes_run_invalid(self):
        table = candidate_run(n=20, overrides={("T1", "s1"): probe_iteration(2)})
        result = gate.evaluate_candidate(table, 20)
        self.assertEqual(result["conclusion"], "無效")
        self.assertFalse(result["run_valid"])
        self.assertTrue(any("PROBE" in r for r in result["invalid_reasons"]), result["invalid_reasons"])

    def test_untagged_makes_run_invalid(self):
        table = candidate_run(
            n=20,
            xc_mutator=lambda xc: _append_failure(xc, "T1", 1, UNTAGGED_T1S1),
        )
        result = gate.evaluate_candidate(table, 20)
        self.assertEqual(result["conclusion"], "無效")

    def test_nineteen_iterations_is_invalid(self):
        result = gate.evaluate_candidate(candidate_run(n=19), 20)
        self.assertEqual(result["conclusion"], "無效")
        self.assertTrue(any("19" in r for r in result["invalid_reasons"]), result["invalid_reasons"])

    def test_missing_test_is_invalid(self):
        result = gate.evaluate_candidate(candidate_run(n=20, drop_tests=("T3",)), 20)
        self.assertEqual(result["conclusion"], "無效")
        self.assertTrue(any("T3" in r for r in result["invalid_reasons"]), result["invalid_reasons"])

    def test_invalid_run_never_reports_pass_or_fail(self):
        table = candidate_run(n=20, overrides={("T1", "s2"): probe_iteration(5)})
        result = gate.evaluate_candidate(table, 20)
        self.assertEqual(result["conclusion"], "無效")
        self.assertNotIn(result["conclusion"], ("通過", "不通過"))


def _append_failure(xc_json, label, iteration, text):
    """把一條未標籤失敗訊息塞進指定測試的第 N 次迭代（構造 UNTAGGED）。"""
    from test_h02_gate_fixtures import repetitions_of

    reps = repetitions_of(xc_json, gate.TEST_LABELS[label])
    node = reps[iteration - 1]
    node["result"] = "Failed"
    node["children"] = list(node.get("children", [])) + [
        {"nodeType": "Failure Message", "name": f"CoverFlowUITests.swift:1: failed - {text}"}
    ]


class KillPredicateTests(unittest.TestCase):
    """§5.2：殺死謂詞新增「產品碼投影含 C2-STACK」的獨立條款。"""

    def test_signature_with_c2_qualifies(self):
        self.assertTrue(gate.kill_signature_has_defect2(["C2-STACK|G=T11|over=T10|side=L"]))

    def test_signature_without_c2_does_not_qualify(self):
        self.assertFalse(gate.kill_signature_has_defect2(["C1-OFFSET|label=T19|centered=T16|strides=+3"]))

    def test_kill_outcome_requires_c2(self):
        baseline = candidate_run(n=20)
        mutant = candidate_run(
            n=3, overrides={("T1", "s1"): ["SIG{T1.s1|C6-NEVER-SETTLES}"]}
        )
        killed, detail = gate.kill_outcome_with_defect2(("T1", "s1"), baseline, mutant)
        self.assertFalse(killed)
        self.assertIn("C2-STACK", str(detail))

    def test_kill_outcome_accepts_c2(self):
        baseline = candidate_run(n=20)
        mutant = candidate_run(n=3, overrides=M2_KILL)
        killed, detail = gate.kill_outcome_with_defect2(("T1", "s1"), baseline, mutant)
        self.assertTrue(killed)
        self.assertEqual(detail, ["C2-STACK|G=T11|over=T10|side=L"])


class ProductFilesTests(unittest.TestCase):
    """§5.2 殺死點消失分支的機械判定。"""

    def test_strip_only_diff_does_not_trigger(self):
        self.assertFalse(gate.has_non_strip_coverflow_change(["Features/CoverFlow/CoverFlowStrip.swift"]))

    def test_viewmodel_diff_triggers(self):
        self.assertTrue(
            gate.has_non_strip_coverflow_change(
                ["Features/CoverFlow/CoverFlowStrip.swift", "Features/CoverFlow/CoverFlowViewModel.swift"]
            )
        )

    def test_path_outside_coverflow_does_not_trigger(self):
        self.assertFalse(gate.has_non_strip_coverflow_change(["Features/Editor/EditorView.swift"]))

    def test_blank_and_comment_lines_ignored(self):
        self.assertFalse(gate.has_non_strip_coverflow_change(["", "  ", "# note"]))

    def test_repo_prefixed_path_still_matches(self):
        self.assertTrue(
            gate.has_non_strip_coverflow_change(["AzathothsWhisper/Features/CoverFlow/CoverFlowGeometry.swift"])
        )


class NegativeControlTests(unittest.TestCase):
    """§5.2 C.2：通過／不通過／無效／不可判定-待解釋／回Phase1-變異移植。"""

    def evaluate(self, baseline=None, m2=None, m3=None, product_files=None):
        return gate.evaluate_negative_control(
            baseline if baseline is not None else candidate_run(n=20),
            m2 if m2 is not None else candidate_run(n=3, overrides=M2_KILL),
            m3 if m3 is not None else candidate_run(n=3, overrides=M3_KILL),
            baseline_iterations=20,
            mutant_iterations=3,
            product_files=product_files,
        )

    def test_consistent_kills_pass(self):
        result = self.evaluate()
        self.assertEqual(result["conclusion"], "通過")
        self.assertEqual(result["deviations"], [])
        self.assertTrue(result["mutants"]["M2"]["kill_ok"])
        self.assertTrue(result["mutants"]["M3"]["kill_ok"])

    def test_m3_killed_only_at_t3s1_passes(self):
        m3 = candidate_run(n=3, overrides={("T3", "s1"): M3_KILL[("T3", "s1")]})
        result = self.evaluate(m3=m3)
        self.assertEqual(result["conclusion"], "通過")

    def test_mutant_with_non_c2_code_only_is_not_killed(self):
        m2 = candidate_run(
            n=3,
            overrides={("T1", "s1"): ["SIG{T1.s1|C4-NO-WRITEBACK}"], ("T2", "s1"): ["SIG{T2.s1|C4-NO-WRITEBACK}"]},
        )
        result = self.evaluate(m2=m2)
        self.assertEqual(result["conclusion"], "不通過")
        self.assertFalse(result["mutants"]["M2"]["kill_ok"])

    def test_signature_deviation_is_undecidable(self):
        m2 = candidate_run(n=3, overrides={("T1", "s1"): ["SIG{T1.s1|C2-STACK|G=T12|over=T11|side=R}"]})
        result = self.evaluate(m2=m2)
        self.assertEqual(result["conclusion"], "不可判定-待解釋")
        self.assertTrue(any("T1.s1" in d for d in result["deviations"]), result["deviations"])

    def test_kill_at_unregistered_step_is_deviation(self):
        m2 = candidate_run(
            n=3,
            overrides={**M2_KILL, ("T4", "s1"): ["SIG{T4.s1|C2-STACK|G=T19|over=T18|side=L}"]},
        )
        result = self.evaluate(m2=m2)
        self.assertEqual(result["conclusion"], "不可判定-待解釋")
        self.assertTrue(any("T4.s1" in d for d in result["deviations"]), result["deviations"])

    def test_baseline_not_all_pass_is_rejected(self):
        baseline = candidate_run(n=20, overrides={("T1", "s2"): only_at(3, [C2_T1S2])})
        result = self.evaluate(baseline=baseline)
        self.assertEqual(result["conclusion"], "baseline不合格")
        self.assertTrue(any("PASS" in r for r in result["reasons"]), result["reasons"])
        self.assertEqual(result["mutants"], {})

    def test_baseline_invalid_is_rejected(self):
        result = self.evaluate(baseline=candidate_run(n=19))
        self.assertEqual(result["conclusion"], "baseline不合格")

    def test_mutant_run_invalid_is_invalid(self):
        m3 = candidate_run(n=3, overrides={("T3", "s1"): probe_iteration(1)})
        result = self.evaluate(m3=m3)
        self.assertEqual(result["conclusion"], "無效")
        self.assertTrue(any("M3" in r for r in result["reasons"]), result["reasons"])

    def test_mutant_iteration_count_mismatch_is_invalid(self):
        result = self.evaluate(m2=candidate_run(n=2, overrides=M2_KILL))
        self.assertEqual(result["conclusion"], "無效")

    def test_kill_point_gone_with_vm_change_returns_to_phase1(self):
        clean = candidate_run(n=3)
        result = self.evaluate(
            m2=clean,
            m3=clean,
            product_files=["Features/CoverFlow/CoverFlowStrip.swift", "Features/CoverFlow/CoverFlowViewModel.swift"],
        )
        self.assertEqual(result["conclusion"], "回Phase1-變異移植")
        self.assertTrue(result["migration_trigger"])

    def test_kill_point_gone_with_strip_only_change_is_fail(self):
        clean = candidate_run(n=3)
        result = self.evaluate(m2=clean, m3=clean, product_files=["Features/CoverFlow/CoverFlowStrip.swift"])
        self.assertEqual(result["conclusion"], "不通過")
        self.assertFalse(result["migration_trigger"])

    def test_kill_point_gone_without_product_files_is_fail(self):
        clean = candidate_run(n=3)
        result = self.evaluate(m2=clean, m3=clean)
        self.assertEqual(result["conclusion"], "不通過")

    def test_r55_signature_constant_matches_plan(self):
        self.assertEqual(
            gate.R55_KILL_SIGNATURES["M2"],
            {
                ("T1", "s1"): frozenset({"C2-STACK|G=T11|over=T10|side=L"}),
                ("T2", "s1"): frozenset({"C2-STACK|G=T11|over=T10|side=L"}),
            },
        )
        self.assertEqual(
            gate.R55_KILL_SIGNATURES["M3"][("T3", "s1")],
            frozenset({"C2-STACK|G=T10|over=T09|side=L"}),
        )


class CandidateCliTests(unittest.TestCase):
    """§5.7 (5)：CLI 兩個子命令與 facade 匯出。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def run_cli(self, argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = gate.main(argv)
        return code, out.getvalue()

    def test_candidate_help(self):
        with self.assertRaises(SystemExit) as ctx:
            with contextlib.redirect_stdout(io.StringIO()):
                gate.main(["candidate", "--help"])
        self.assertEqual(ctx.exception.code, 0)

    def test_candidate_cli_prints_pass(self):
        log, xc = write_run(self.tmp, "cand", n=3)
        code, text = self.run_cli(["candidate", "--log", log, "--xcresult", xc, "--iterations", "3"])
        self.assertEqual(code, 0)
        self.assertIn("結論=通過", text)

    def test_candidate_cli_prints_failing_cells(self):
        log, xc = write_run(self.tmp, "cand", n=3, overrides={("T1", "s2"): only_at(2, [C2_T1S2])})
        code, text = self.run_cli(["candidate", "--log", log, "--xcresult", xc, "--iterations", "3"])
        self.assertEqual(code, 0)
        self.assertIn("結論=不通過", text)
        self.assertIn("T1.s2", text)
        self.assertIn("iter 2", text)

    def test_candidate_cli_evidence_flag(self):
        log, xc = write_run(self.tmp, "cand", n=2)
        root = write_evidence(Path(self.tmp) / "ev", 2, transform=at_manifest("T1", 2, lambda m: None))
        code, text = self.run_cli(
            ["candidate", "--log", log, "--xcresult", xc, "--iterations", "2", "--evidence", str(root)]
        )
        self.assertEqual(code, 0)
        self.assertIn("結論=無效", text)

    def test_negative_control_cli(self):
        base_log, base_xc = write_run(self.tmp, "base", n=20)
        m2_log, m2_xc = write_run(self.tmp, "m2", n=3, overrides=M2_KILL)
        m3_log, m3_xc = write_run(self.tmp, "m3", n=3, overrides=M3_KILL)
        code, text = self.run_cli(
            [
                "negative-control",
                "--baseline-log", base_log, "--baseline-xcresult", base_xc, "--baseline-iterations", "20",
                "--m2-log", m2_log, "--m2-xcresult", m2_xc,
                "--m3-log", m3_log, "--m3-xcresult", m3_xc,
                "--mutant-iterations", "3",
            ]
        )
        self.assertEqual(code, 0)
        self.assertIn("結論=通過", text)

    def test_negative_control_cli_product_files(self):
        base_log, base_xc = write_run(self.tmp, "base", n=20)
        m2_log, m2_xc = write_run(self.tmp, "m2", n=3)
        m3_log, m3_xc = write_run(self.tmp, "m3", n=3)
        files = Path(self.tmp) / "product-files.txt"
        files.write_text("Features/CoverFlow/CoverFlowViewModel.swift\n", encoding="utf-8")
        code, text = self.run_cli(
            [
                "negative-control",
                "--baseline-log", base_log, "--baseline-xcresult", base_xc, "--baseline-iterations", "20",
                "--m2-log", m2_log, "--m2-xcresult", m2_xc,
                "--m3-log", m3_log, "--m3-xcresult", m3_xc,
                "--product-files", str(files),
            ]
        )
        self.assertEqual(code, 0)
        self.assertIn("結論=回Phase1-變異移植", text)

    def test_facade_exports_new_symbols(self):
        for name in (
            "evaluate_candidate",
            "evaluate_evidence",
            "evaluate_negative_control",
            "kill_outcome_with_defect2",
            "kill_signature_has_defect2",
            "has_non_strip_coverflow_change",
            "R55_KILL_SIGNATURES",
        ):
            self.assertIn(name, gate.__all__, name)
            self.assertTrue(hasattr(gate, name), name)


if __name__ == "__main__":
    unittest.main()
