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
from unittest import mock
from pathlib import Path

import h02_gate_eval as gate
import h02_gate_cli as gate_cli
from test_h02_gate_fixtures import (
    M2_KILL,
    M3_KILL,
    PROBE_T1S1,
    R27_CDHASH,
    R27_PROFILE_MATCHING_R55,
    R27_TREE_HASH,
    UNTAGGED_T1S1,
    at_manifest,
    candidate_run,
    r27_profile,
    write_active_r27_profile,
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
    """§5.2 C.2：通過／不通過／無效／不可判定-待解釋／回Phase1-變異移植。
    v5 §13 第 4、5、13 項起：R55 降為唯讀歷史，C.2 結論改讀 active R27 profile；沒有 active
    profile 時到達簽名比對這一步就是「無效」，不得默默落回 R55（見 `test_no_active_profile_*`）。"""

    def evaluate(self, baseline=None, m2=None, m3=None, product_files=None, active_profile=None):
        return gate.evaluate_negative_control(
            baseline if baseline is not None else candidate_run(n=20),
            m2 if m2 is not None else candidate_run(n=3, overrides=M2_KILL),
            m3 if m3 is not None else candidate_run(n=3, overrides=M3_KILL),
            baseline_iterations=20,
            mutant_iterations=3,
            product_files=product_files,
            active_profile=active_profile,
        )

    def test_consistent_kills_pass(self):
        result = self.evaluate(active_profile=R27_PROFILE_MATCHING_R55)
        self.assertEqual(result["conclusion"], "通過")
        self.assertEqual(result["active_profile_deviation"], [])
        self.assertEqual(result["historical_R55_deviation"], [])
        self.assertTrue(result["mutants"]["M2"]["kill_ok"])
        self.assertTrue(result["mutants"]["M3"]["kill_ok"])

    def test_m3_killed_only_at_t3s1_passes(self):
        m3 = candidate_run(n=3, overrides={("T3", "s1"): M3_KILL[("T3", "s1")]})
        result = self.evaluate(m3=m3, active_profile=R27_PROFILE_MATCHING_R55)
        self.assertEqual(result["conclusion"], "通過")

    def test_no_active_profile_is_invalid_even_when_kills_would_match_r55(self):
        """§13 第 5 項：沒有 active profile 時不得用 R55 下結論——即使殺死簽名與 R55 完全相符，
        到達簽名比對這一步仍須判「無效」，而不是悄悄借用歷史 R55 判「通過」。"""
        result = self.evaluate()  # active_profile 預設 None
        self.assertEqual(result["conclusion"], "無效")
        self.assertTrue(any("active profile" in r for r in result["reasons"]), result["reasons"])
        self.assertIsNone(result["active_profile_deviation"])
        # historical 欄位仍照算，供人工參考；只是不參與結論
        self.assertEqual(result["historical_R55_deviation"], [])
        self.assertTrue(result["mutants"]["M2"]["kill_ok"])

    def test_no_active_profile_with_unkilled_mutant_is_invalid_not_fail(self):
        """must_fix 1：§7 結論程序「2 無效」優先於「4 不通過」——沒有 active profile 時，
        即使某個變異確實沒被殺死，也不得判「不通過」，必須先判「無效：缺 active profile」。"""
        m2 = candidate_run(
            n=3,
            overrides={("T1", "s1"): ["SIG{T1.s1|C4-NO-WRITEBACK}"], ("T2", "s1"): ["SIG{T2.s1|C4-NO-WRITEBACK}"]},
        )
        result = self.evaluate(m2=m2)  # active_profile 預設 None
        self.assertEqual(result["conclusion"], "無效")
        self.assertTrue(any("active profile" in r for r in result["reasons"]), result["reasons"])

    def test_no_active_profile_with_migration_trigger_is_invalid_not_migration(self):
        """must_fix 1：§7 結論程序「2 無效」優先於「3 不可判定」——沒有 active profile 時，
        即使殺死點消失且候選改了非 Strip 檔（原本會觸發「回Phase1-變異移植」），也必須先判
        「無效：缺 active profile」，不得跳過 profile 檢查直接進移植分支。"""
        clean = candidate_run(n=3)
        result = self.evaluate(
            m2=clean,
            m3=clean,
            product_files=["Features/CoverFlow/CoverFlowStrip.swift", "Features/CoverFlow/CoverFlowViewModel.swift"],
        )  # active_profile 預設 None
        self.assertEqual(result["conclusion"], "無效")
        self.assertTrue(any("active profile" in r for r in result["reasons"]), result["reasons"])
        self.assertFalse(result["migration_trigger"] and result["conclusion"] == "回Phase1-變異移植")

    def test_active_profile_deviation_is_populated_when_unkilled_short_circuits(self):
        """must_fix 2：有 active profile 時，即使結論短路成「不通過」，`active_profile_deviation`
        欄仍須是空陣列而非 `None`——CLI 才不會誤印「尚無 active profile」。"""
        m2 = candidate_run(
            n=3,
            overrides={("T1", "s1"): ["SIG{T1.s1|C4-NO-WRITEBACK}"], ("T2", "s1"): ["SIG{T2.s1|C4-NO-WRITEBACK}"]},
        )
        result = self.evaluate(m2=m2, active_profile=R27_PROFILE_MATCHING_R55)
        self.assertEqual(result["conclusion"], "不通過")
        self.assertEqual(result["active_profile_deviation"], [])

    def test_active_profile_deviation_is_populated_when_migration_short_circuits(self):
        """must_fix 2：migration 短路分支同樣不得漏帶 active_profile_deviation。"""
        clean = candidate_run(n=3)
        result = self.evaluate(
            m2=clean,
            m3=clean,
            product_files=["Features/CoverFlow/CoverFlowStrip.swift", "Features/CoverFlow/CoverFlowViewModel.swift"],
            active_profile=R27_PROFILE_MATCHING_R55,
        )
        self.assertEqual(result["conclusion"], "回Phase1-變異移植")
        self.assertEqual(result["active_profile_deviation"], [])

    def test_no_active_profile_per_mutant_deviation_is_none_not_empty_list(self):
        """`active_profile_deviation` 用 `None` 區分「尚無 active profile」與「有 profile 但零偏離」，
        不得用空陣列混淆兩者（呼叫端才能分辨要不要顯示「尚無 active profile」）。"""
        result = self.evaluate()
        self.assertIsNone(result["mutants"]["M2"]["active_profile_deviation"])
        self.assertIsNone(result["mutants"]["M3"]["active_profile_deviation"])

    def test_active_profile_deviation_alone_decides_conclusion_not_historical(self):
        """§13 第 4 項：雙欄報告只有 active 參與結論——即使 historical_R55_deviation 非空，
        只要 active_profile_deviation 為空仍判「通過」。"""
        # M2 的 T1.s1 用一個與 R55 不同、但與本測試建構的 active profile相符的簽名。
        custom_sig = "C2-STACK|G=T99|over=T98|side=R"
        m2 = candidate_run(n=3, overrides={**M2_KILL, ("T1", "s1"): [f"SIG{{T1.s1|{custom_sig}}}"]})
        profile = r27_profile(
            m2_kill={("T1", "s1"): [custom_sig], ("T2", "s1"): sorted(gate.R55_KILL_SIGNATURES["M2"][("T2", "s1")])},
            m3_kill=gate.R55_KILL_SIGNATURES["M3"],
        )
        result = self.evaluate(m2=m2, active_profile=profile)
        self.assertEqual(result["conclusion"], "通過", result["reasons"])
        self.assertEqual(result["active_profile_deviation"], [])
        self.assertTrue(
            any("T1.s1" in d for d in result["historical_R55_deviation"]), result["historical_R55_deviation"]
        )

    def test_mutant_with_non_c2_code_only_is_not_killed(self):
        # must_fix 1：「2 無效」優先於「4 不通過」，須給有效 active profile 才能評到殺死判定本身。
        m2 = candidate_run(
            n=3,
            overrides={("T1", "s1"): ["SIG{T1.s1|C4-NO-WRITEBACK}"], ("T2", "s1"): ["SIG{T2.s1|C4-NO-WRITEBACK}"]},
        )
        result = self.evaluate(m2=m2, active_profile=R27_PROFILE_MATCHING_R55)
        self.assertEqual(result["conclusion"], "不通過")
        self.assertFalse(result["mutants"]["M2"]["kill_ok"])

    def test_signature_deviation_is_undecidable(self):
        m2 = candidate_run(n=3, overrides={("T1", "s1"): ["SIG{T1.s1|C2-STACK|G=T12|over=T11|side=R}"]})
        result = self.evaluate(m2=m2, active_profile=R27_PROFILE_MATCHING_R55)
        self.assertEqual(result["conclusion"], "不可判定-待解釋")
        self.assertTrue(any("T1.s1" in d for d in result["active_profile_deviation"]), result["active_profile_deviation"])

    def test_kill_at_unregistered_step_is_deviation(self):
        m2 = candidate_run(
            n=3,
            overrides={**M2_KILL, ("T4", "s1"): ["SIG{T4.s1|C2-STACK|G=T19|over=T18|side=L}"]},
        )
        result = self.evaluate(m2=m2, active_profile=R27_PROFILE_MATCHING_R55)
        self.assertEqual(result["conclusion"], "不可判定-待解釋")
        self.assertTrue(any("T4.s1" in d for d in result["active_profile_deviation"]), result["active_profile_deviation"])

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
        # must_fix 1：同上，須給有效 active profile 才能評到 migration 分支本身。
        clean = candidate_run(n=3)
        result = self.evaluate(
            m2=clean,
            m3=clean,
            product_files=["Features/CoverFlow/CoverFlowStrip.swift", "Features/CoverFlow/CoverFlowViewModel.swift"],
            active_profile=R27_PROFILE_MATCHING_R55,
        )
        self.assertEqual(result["conclusion"], "回Phase1-變異移植")
        self.assertTrue(result["migration_trigger"])

    def test_kill_point_gone_with_strip_only_change_is_fail(self):
        clean = candidate_run(n=3)
        result = self.evaluate(
            m2=clean, m3=clean, product_files=["Features/CoverFlow/CoverFlowStrip.swift"],
            active_profile=R27_PROFILE_MATCHING_R55,
        )
        self.assertEqual(result["conclusion"], "不通過")
        self.assertFalse(result["migration_trigger"])

    def test_kill_point_gone_without_product_files_is_fail(self):
        clean = candidate_run(n=3)
        result = self.evaluate(m2=clean, m3=clean, active_profile=R27_PROFILE_MATCHING_R55)
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

    def test_active_profile_provenance_is_reported_not_cross_checked(self):
        """刻意決定（主線程 2026-09-18 拍板，見 `docs/plans/2026-09-13-coverflow-h02-fix4.md`）：
        profile 的 tree_hash／cdhash 是場 0 **基準樹**（M0 運行時那棵樹）的溯源記錄，不得拿來
        跟受評運行的 tree hash 做相等比對後判「無效」——M2_K／M3_K 依設計是從**候選 tree**
        （不是 profile 的 M0 基準樹）重建的，樹 hash 本來就會不同；若交叉核對，C.2 對任何
        候選改動都會恆為無效。正確做法：只把 `active_profile_provenance` 印進報告輸出。

        本測試釘住這個決定：`evaluate_negative_control` 完全不接受、也不使用任何「受評運行
        的 tree hash」參數（函式簽名裡沒有），profile 的 tree_hash／cdhash 因此不可能被拿去
        跟什麼比較——`active_profile_provenance` 只是把 profile 自己的溯源欄位原樣列出，
        結論不受影響（見 `R27Profile.provenance` docstring）。下一輪覆核者若又提議加交叉
        核對，先讀這裡。"""
        result = self.evaluate(active_profile=R27_PROFILE_MATCHING_R55)
        self.assertEqual(result["conclusion"], "通過")
        self.assertEqual(
            result["active_profile_provenance"],
            {
                "version": "synthetic-r27",
                "tree_hash": R27_TREE_HASH,
                "cdhash": R27_CDHASH,
                "env_fingerprint": {},
                "display": "",
            },
        )

    def test_active_profile_provenance_is_none_without_active_profile(self):
        result = self.evaluate()  # active_profile 預設 None
        self.assertIsNone(result["active_profile_provenance"])


class CandidateCliTests(unittest.TestCase):
    """§5.7 (5)：CLI 兩個子命令與 facade 匯出。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)
        # 預設 profile 路徑指向空的臨時目錄：測試不得依賴本機 ~/Developer 下是否已有 active profile
        patcher = mock.patch.object(gate_cli, "_DEFAULT_R27_PROFILE_DIR", str(Path(self.tmp) / "default-r27-profile"))
        patcher.start()
        self.addCleanup(patcher.stop)

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

    def test_negative_control_cli_without_profile_dir_is_invalid(self):
        """v5 §13 第 5 項：CLI 不給 `--profile-dir`（或指向空目錄）時無 active profile，
        即使殺死簽名齊全，也不得悄悄借用 R55 判「通過」——須是「無效：缺 active profile」。"""
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
        self.assertIn("結論=無效", text)
        self.assertIn("active profile", text)

    def test_negative_control_cli(self):
        base_log, base_xc = write_run(self.tmp, "base", n=20)
        m2_log, m2_xc = write_run(self.tmp, "m2", n=3, overrides=M2_KILL)
        m3_log, m3_xc = write_run(self.tmp, "m3", n=3, overrides=M3_KILL)
        profile_dir = Path(self.tmp) / "r27-profile"
        write_active_r27_profile(profile_dir)
        code, text = self.run_cli(
            [
                "negative-control",
                "--baseline-log", base_log, "--baseline-xcresult", base_xc, "--baseline-iterations", "20",
                "--m2-log", m2_log, "--m2-xcresult", m2_xc,
                "--m3-log", m3_log, "--m3-xcresult", m3_xc,
                "--mutant-iterations", "3",
                "--profile-dir", str(profile_dir),
            ]
        )
        self.assertEqual(code, 0)
        self.assertIn("結論=通過", text)
        # 第 5 項：profile 溯源（version／tree_hash／cdhash）須印進報告輸出。
        self.assertIn("active_profile: version=synthetic-r27", text)
        self.assertIn(f"tree_hash={R27_TREE_HASH}", text)

    # -- must_fix：§10 R13 環境指紋 --run-env-fingerprint（CLI 解析＋fail-closed）-----------

    def _negative_control_argv(self, profile_dir, extra=()):
        base_log, base_xc = write_run(self.tmp, "base", n=20)
        m2_log, m2_xc = write_run(self.tmp, "m2", n=3, overrides=M2_KILL)
        m3_log, m3_xc = write_run(self.tmp, "m3", n=3, overrides=M3_KILL)
        return [
            "negative-control",
            "--baseline-log", base_log, "--baseline-xcresult", base_xc, "--baseline-iterations", "20",
            "--m2-log", m2_log, "--m2-xcresult", m2_xc,
            "--m3-log", m3_log, "--m3-xcresult", m3_xc,
            "--mutant-iterations", "3",
            "--profile-dir", str(profile_dir),
            *extra,
        ]

    def test_negative_control_cli_run_env_fingerprint_bad_format_is_error(self):
        """`--run-env-fingerprint` 格式錯誤（缺 `=`）須是 CLI 錯誤（exit 2），不得靜默生出一份
        看似合法但缺鍵少值的指紋。"""
        profile_dir = Path(self.tmp) / "r27-profile"
        write_active_r27_profile(profile_dir)
        code, _ = self.run_cli(
            self._negative_control_argv(profile_dir, extra=["--run-env-fingerprint", "os_build"])
        )
        self.assertEqual(code, 2)

    def test_negative_control_cli_run_env_fingerprint_matching_passes(self):
        fp = {"os_build": "26A428", "xcode_build": "27A266a", "sdk": "macosx27.0"}
        profile_dir = Path(self.tmp) / "r27-profile"
        write_active_r27_profile(profile_dir, env_fingerprint=fp)
        code, text = self.run_cli(
            self._negative_control_argv(
                profile_dir,
                extra=["--run-env-fingerprint", "os_build=26A428,xcode_build=27A266a,sdk=macosx27.0"],
            )
        )
        self.assertEqual(code, 0)
        self.assertIn("結論=通過", text)
        self.assertIn("env_fingerprint: match", text)

    def test_negative_control_cli_run_env_fingerprint_mismatch_is_invalid(self):
        fp = {"os_build": "26A428", "xcode_build": "27A266a", "sdk": "macosx27.0"}
        profile_dir = Path(self.tmp) / "r27-profile"
        write_active_r27_profile(profile_dir, env_fingerprint=fp)
        code, text = self.run_cli(
            self._negative_control_argv(
                profile_dir,
                extra=["--run-env-fingerprint", "os_build=99Z999,xcode_build=27A266a,sdk=macosx27.0"],
            )
        )
        self.assertEqual(code, 0)
        self.assertIn("結論=無效", text)
        self.assertIn("env_fingerprint: mismatch", text)
        self.assertIn("os_build", text)

    def test_negative_control_cli_without_run_env_fingerprint_but_profile_has_one_is_invalid(self):
        """must_fix（fail-closed）：profile 已記錄環境指紋，CLI 完全不給 `--run-env-fingerprint`
        （場 0 前 CLI 呼叫的現況）——不得再悄悄通過，須判「無效」。這正是修前的漏洞：R13
        對任何 CLI 呼叫恆為 unknown、零效果。"""
        fp = {"os_build": "26A428", "xcode_build": "27A266a", "sdk": "macosx27.0"}
        profile_dir = Path(self.tmp) / "r27-profile"
        write_active_r27_profile(profile_dir, env_fingerprint=fp)
        code, text = self.run_cli(self._negative_control_argv(profile_dir))
        self.assertEqual(code, 0)
        self.assertIn("結論=無效", text)
        self.assertIn("env_fingerprint: unmeasured", text)

    def test_negative_control_cli_product_files_without_profile_is_invalid(self):
        """must_fix 1 配套：§7「2 無效」優先於「3 不可判定」——即使殺死點消失且候選改了非 Strip
        檔（單獨看會觸發「回Phase1-變異移植」），沒有 active profile 時仍須先判「無效」，不得
        繞過 profile 檢查直接進移植分支（舊版本測試在此指向空目錄卻斷言「回Phase1-變異移植」，
        鎖死了與 §7 結論程序矛盾的行為，已改正）。"""
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
        self.assertIn("結論=無效", text)
        self.assertIn("active profile", text)

    def test_negative_control_cli_product_files_with_profile_still_migrates(self):
        """回Phase1-變異移植分支在有 active profile 時仍可正常觸發（確認 must_fix 1 沒有
        意外關掉這條分支，只是把「無 profile」的優先序糾正過來）。"""
        base_log, base_xc = write_run(self.tmp, "base", n=20)
        m2_log, m2_xc = write_run(self.tmp, "m2", n=3)
        m3_log, m3_xc = write_run(self.tmp, "m3", n=3)
        files = Path(self.tmp) / "product-files.txt"
        files.write_text("Features/CoverFlow/CoverFlowViewModel.swift\n", encoding="utf-8")
        profile_dir = Path(self.tmp) / "r27-profile"
        write_active_r27_profile(profile_dir)
        code, text = self.run_cli(
            [
                "negative-control",
                "--baseline-log", base_log, "--baseline-xcresult", base_xc, "--baseline-iterations", "20",
                "--m2-log", m2_log, "--m2-xcresult", m2_xc,
                "--m3-log", m3_log, "--m3-xcresult", m3_xc,
                "--product-files", str(files),
                "--profile-dir", str(profile_dir),
            ]
        )
        self.assertEqual(code, 0)
        self.assertIn("結論=回Phase1-變異移植", text)

    def test_negative_control_cli_does_not_falsely_claim_no_profile_when_unkilled(self):
        """must_fix 2：有 active profile 但結論短路成「不通過」時，CLI 不得誤印
        「尚無 active profile」（舊版只憑 `active_profile_deviation is None` 判斷，短路分支
        沒補這欄，會印出與事實不符的文案）。"""
        base_log, base_xc = write_run(self.tmp, "base", n=20)
        m2_log, m2_xc = write_run(
            self.tmp, "m2", n=3,
            overrides={("T1", "s1"): ["SIG{T1.s1|C4-NO-WRITEBACK}"], ("T2", "s1"): ["SIG{T2.s1|C4-NO-WRITEBACK}"]},
        )
        m3_log, m3_xc = write_run(self.tmp, "m3", n=3, overrides=M3_KILL)
        profile_dir = Path(self.tmp) / "r27-profile"
        write_active_r27_profile(profile_dir)
        code, text = self.run_cli(
            [
                "negative-control",
                "--baseline-log", base_log, "--baseline-xcresult", base_xc, "--baseline-iterations", "20",
                "--m2-log", m2_log, "--m2-xcresult", m2_xc,
                "--m3-log", m3_log, "--m3-xcresult", m3_xc,
                "--mutant-iterations", "3",
                "--profile-dir", str(profile_dir),
            ]
        )
        self.assertEqual(code, 0)
        self.assertIn("結論=不通過", text)
        self.assertNotIn("尚無 active profile", text)

    def test_facade_exports_new_symbols(self):
        for name in (
            "evaluate_candidate",
            "evaluate_evidence",
            "evaluate_negative_control",
            "kill_outcome_with_defect2",
            "kill_signature_has_defect2",
            "has_non_strip_coverflow_change",
            "R55_KILL_SIGNATURES",
            # v5 §13 第 5、13 項：R27 profile（見 h02_gate_r27_profile.py）
            "R27Profile",
            "ProfileError",
            "R27_PROFILE_SCHEMA",
            "activate_r27",
            "load_active_profile",
            "active_profile_deviations",
        ):
            self.assertIn(name, gate.__all__, name)
            self.assertTrue(hasattr(gate, name), name)


if __name__ == "__main__":
    unittest.main()
