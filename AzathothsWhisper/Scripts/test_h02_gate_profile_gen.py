#!/usr/bin/env python3
"""`h02_gate_profile_gen.py` 單測（F2b：R27 staging 產生器，
`docs/plans/2026-09-13-coverflow-h02-fix4.md` §13 v5 提案第 5、13 項）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_*.py'
"""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import h02_gate_profile_gen as pgen
import h02_gate_r27_profile as r27
import test_h02_gate_fixtures as fx


write_manifest = fx.write_tree_manifest  # 共用夾具（回傳 (path, data)）


VALID_ENV_TEXT = fx.TREE_MANIFEST_ENV_TEXT
VALID_ENV = {"os_build": "26A428", "xcode_build": "27A266a", "sdk": "macosx27.0"}


class TreeManifestTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def test_valid_manifest_loads(self):
        path, data = write_manifest(self.tmp)
        loaded = pgen.load_tree_manifest(path)
        self.assertEqual(loaded["swift_hashlist_sha256"], data["swift_hashlist_sha256"])

    def test_missing_key_rejected(self):
        path, data = write_manifest(self.tmp)
        del data["cdhash"]
        Path(path).write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaises(pgen.ProfileCliError):
            pgen.load_tree_manifest(path)

    def test_missing_file_rejected(self):
        with self.assertRaises(pgen.ProfileCliError):
            pgen.load_tree_manifest(str(Path(self.tmp) / "nope.json"))

    def test_not_json_rejected(self):
        path = Path(self.tmp) / "bad.json"
        path.write_text("{not json", encoding="utf-8")
        with self.assertRaises(pgen.ProfileCliError):
            pgen.load_tree_manifest(str(path))


class RunEnvFingerprintParseTests(unittest.TestCase):
    def test_valid_parses(self):
        self.assertEqual(pgen.parse_run_env_fingerprint(VALID_ENV_TEXT), VALID_ENV)

    def test_missing_equals_rejected(self):
        with self.assertRaises(pgen.ProfileCliError):
            pgen.parse_run_env_fingerprint("os_build")

    def test_empty_rejected(self):
        with self.assertRaises(pgen.ProfileCliError):
            pgen.parse_run_env_fingerprint("")


class ManifestEnvFingerprintCheckTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def test_matching_is_accepted(self):
        _, manifest = write_manifest(self.tmp)
        pgen.check_manifest_env_fingerprint(manifest, VALID_ENV, "test")  # 不拋錯即通過

    def test_mismatched_sdk_rejected(self):
        _, manifest = write_manifest(self.tmp)
        bad = dict(VALID_ENV, sdk="macosx26.5")
        with self.assertRaises(pgen.ProfileCliError) as ctx:
            pgen.check_manifest_env_fingerprint(manifest, bad, "test")
        self.assertIn("sdk", str(ctx.exception))


class AttemptsTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def test_record_and_count(self):
        pgen.record_invalid_attempt(self.tmp, "M0", "m0", ["reason1"])
        pgen.record_invalid_attempt(self.tmp, "M0", "m0", ["reason2"])
        pgen.record_invalid_attempt(self.tmp, "M2", "m2", ["reason3"])
        self.assertEqual(pgen.count_invalid_attempts(self.tmp, "M0", "m0"), 2)
        self.assertEqual(pgen.count_invalid_attempts(self.tmp, "M2", "m2"), 1)
        self.assertEqual(pgen.count_invalid_attempts(self.tmp, "M3", "m3"), 0)

    def test_summary_groups_by_tree_and_run_kind(self):
        pgen.record_invalid_attempt(self.tmp, "M0", "m0", ["r"])
        pgen.record_invalid_attempt(self.tmp, "M0", "m0", ["r"])
        summary = pgen.attempts_summary(self.tmp)
        self.assertEqual(summary[("M0", "", "m0")], 2)

    def test_distinct_hashes_sharing_a_prefix_are_not_merged(self):
        """桶以**完整 hash** 聚合：前 8 碼相同的兩棵樹各 1 份無效，不得被併成 2 而觸發上限
        （Codex review Round 4）。`@abcd1234` 只是報告文字。"""
        a, b = "aaaaaaaa" + "1" * 24, "aaaaaaaa" + "2" * 24
        pgen.record_invalid_attempt(self.tmp, "M0", "m0", ["r"], tree_hash=a)
        pgen.record_invalid_attempt(self.tmp, "M0", "m0", ["r"], tree_hash=b)
        summary = pgen.attempts_summary(self.tmp)
        self.assertEqual(summary[("M0", a, "m0")], 1)
        self.assertEqual(summary[("M0", b, "m0")], 1)
        self.assertEqual(pgen.count_invalid_attempts(self.tmp, "M0", "m0", tree_hash=a), 1)
        self.assertFalse(pgen.evaluate_scene0_check(self.tmp)["checks"]["attempts_stop_triggered"])

    def test_no_file_yet_counts_zero(self):
        self.assertEqual(pgen.count_invalid_attempts(self.tmp, "M0", "m0"), 0)
        self.assertEqual(pgen.attempts_summary(self.tmp), {})


class BuildM0StagingTests(unittest.TestCase):
    def setUp(self):
        self.table = fx.m0_run(n=10)  # FROZEN_M0：健康、V5 陽性對照成立、缺陷 2/3 皆重現
        _, self.manifest = write_manifest(tempfile.mkdtemp())

    def test_produces_all_nine_steps(self):
        data = pgen.build_m0_staging(self.table, 10, self.manifest, VALID_ENV, None, "deadbeef" * 8)
        self.assertEqual(len(data["steps"]), 9)
        self.assertIn("T1.s1", data["steps"])
        self.assertIn("T4.s2", data["steps"])

    def test_all_pass_step_has_empty_sig_set_and_stable(self):
        data = pgen.build_m0_staging(self.table, 10, self.manifest, VALID_ENV, None, "h" * 64)
        t1s1 = data["steps"]["T1.s1"]
        self.assertEqual(t1s1["sig_set"], [])
        self.assertEqual(t1s1["allowed_codes"], [])
        self.assertTrue(t1s1["stable"])

    def test_consistent_fail_step_has_allowed_codes_from_observed(self):
        data = pgen.build_m0_staging(self.table, 10, self.manifest, VALID_ENV, None, "h" * 64)
        t1s2 = data["steps"]["T1.s2"]  # FROZEN_M0：恆定 FAIL{C2-STACK}
        self.assertEqual(t1s2["allowed_codes"], ["C2-STACK"])
        self.assertTrue(t1s2["stable"])

    def test_t4s2_allowed_codes_includes_defect3_codes_even_if_unobserved(self):
        """T4.s2 另併入 DEFECT3_CODES，比照 FROZEN_ALLOWED_CODES 由 FROZEN_REGISTRATION 推出的規則。"""
        data = pgen.build_m0_staging(self.table, 10, self.manifest, VALID_ENV, None, "h" * 64)
        t4s2 = data["steps"]["T4.s2"]
        for code in fx.gate.DEFECT3_CODES:
            self.assertIn(code, t4s2["allowed_codes"])

    def test_checks_capture_v3_v5_verdicts(self):
        data = pgen.build_m0_staging(self.table, 10, self.manifest, VALID_ENV, None, "h" * 64)
        checks = data["checks"]
        self.assertTrue(checks["positive_control_ok"])
        self.assertTrue(checks["defect2_reproduced"])
        self.assertEqual(checks["defect3"]["status"], "CAUGHT")

    def test_tree_hash_cdhash_display_from_manifest(self):
        data = pgen.build_m0_staging(self.table, 10, self.manifest, VALID_ENV, None, "h" * 64)
        self.assertEqual(data["tree_hash"], self.manifest["swift_hashlist_sha256"])
        self.assertEqual(data["cdhash"], self.manifest["cdhash"])
        self.assertEqual(data["display"], self.manifest["display"])

    def test_evidence_hash_optional(self):
        data = pgen.build_m0_staging(self.table, 10, self.manifest, VALID_ENV, "ev" * 32, "h" * 64)
        self.assertEqual(data["evidence_hash"], "ev" * 32)
        data_without = pgen.build_m0_staging(self.table, 10, self.manifest, VALID_ENV, None, "h" * 64)
        self.assertNotIn("evidence_hash", data_without)

    def test_result_round_trips_through_stage_component(self):
        """產出的資料必須是 `stage_component("m0", ...)` 會接受的合法 schema。"""
        tmp = tempfile.mkdtemp()
        data = pgen.build_m0_staging(self.table, 10, self.manifest, VALID_ENV, None, "h" * 64)
        r27.stage_component(tmp, "m0", data)
        loaded = r27.load_staging_component(tmp, "m0")
        self.assertEqual(loaded["tree_hash"], self.manifest["swift_hashlist_sha256"])


class BaselineMatchesStagedM0Tests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)
        self.log_path = Path(self.tmp) / "cf-m0-27.log"
        self.log_path.write_text("some log content\n", encoding="utf-8")

    def test_matching_sha256_accepted(self):
        m0_staging = {"log_sha256": pgen.sha256_file(self.log_path)}
        self.assertTrue(pgen.baseline_sha256_matches_staged_m0(m0_staging, pgen.sha256_file(self.log_path)))

    def test_mismatched_sha256_rejected(self):
        m0_staging = {"log_sha256": "0" * 64}
        self.assertFalse(pgen.baseline_sha256_matches_staged_m0(m0_staging, pgen.sha256_file(self.log_path)))

    def test_missing_log_sha256_field_rejected(self):
        self.assertFalse(pgen.baseline_sha256_matches_staged_m0({}, pgen.sha256_file(self.log_path)))


class BuildMutantStagingTests(unittest.TestCase):
    def setUp(self):
        self.baseline = fx.m0_run(n=10)  # FROZEN_M0：T1.s1／T2.s1／T3.s1 皆 PASS
        self.killed_mutant = fx.candidate_run(n=3, overrides=fx.MUTANT_KILLED)
        self.unkilled_mutant = fx.candidate_run(n=3)  # 全 PASS：什麼都沒殺死
        _, self.manifest = write_manifest(tempfile.mkdtemp(), name="M2")

    def test_kill_ok_true_when_required_step_killed(self):
        data = pgen.build_mutant_staging("M2", self.baseline, self.killed_mutant, self.manifest, None)
        self.assertTrue(data["checks"]["kill_ok"])
        self.assertIn("T1.s1", data["kill_signatures"])
        self.assertIn("T2.s1", data["kill_signatures"])

    def test_kill_ok_false_when_nothing_killed(self):
        data = pgen.build_mutant_staging("M2", self.baseline, self.unkilled_mutant, self.manifest, None)
        self.assertFalse(data["checks"]["kill_ok"])
        self.assertEqual(data["kill_signatures"], {})

    def test_required_baseline_pass_ok_true_on_frozen_m0(self):
        data = pgen.build_mutant_staging("M2", self.baseline, self.killed_mutant, self.manifest, None)
        self.assertTrue(data["checks"]["required_baseline_pass_ok"])
        self.assertIn(["T1", "s1"], data["checks"]["required_baseline_pass_steps"])

    def test_required_baseline_pass_ok_false_when_baseline_required_steps_all_fail(self):
        bad_baseline = fx.m0_run(n=10, overrides={("T1", "s1"): fx.MUTANT_KILLED[("T1", "s1")], ("T2", "s1"): fx.MUTANT_KILLED[("T2", "s1")]})
        data = pgen.build_mutant_staging("M2", bad_baseline, self.killed_mutant, self.manifest, None)
        self.assertFalse(data["checks"]["required_baseline_pass_ok"])
        self.assertEqual(data["checks"]["required_baseline_pass_steps"], [])

    def test_m3_required_steps_include_t3s1(self):
        data = pgen.build_mutant_staging("M3", self.baseline, fx.candidate_run(n=3, overrides=fx.M3_KILL), self.manifest, None)
        self.assertIn(["T3", "s1"], data["checks"]["required_steps"])
        self.assertTrue(data["checks"]["kill_ok"])


class UiTestLogParsingTests(unittest.TestCase):
    def _line(self, cls, method, verb, seconds="1.0"):
        return f"Test Case '-[AzathothsWhisperUITests.{cls} {method}]' {verb} ({seconds} seconds)."

    def _started(self, cls, method):
        return f"Test Case '-[AzathothsWhisperUITests.{cls} {method}]' started."

    def test_parses_passed_failed_skipped(self):
        log = "\n".join(
            [
                self._started("ShellUITests", "testFoo"),
                self._line("ShellUITests", "testFoo", "passed"),
                self._started("ShellUITests", "testBar"),
                self._line("ShellUITests", "testBar", "failed"),
                self._started("BatchLiveUITests", "testBaz"),
                self._line("BatchLiveUITests", "testBaz", "skipped", "0.16"),
            ]
        )
        results = pgen.parse_ui_test_log(log)
        self.assertEqual(
            results,
            {
                "ShellUITests.testFoo": "PASS",
                "ShellUITests.testBar": "FAIL",
                "BatchLiveUITests.testBaz": "SKIP",
            },
        )

    def test_real_ui_t0_shape_extracts_seventeen(self):
        """依 F2b 任務規格，使用真實 `ui-T0.log` 的 17 條識別碼組出的最小夾具驗證解析器。"""
        lines = []
        for name in pgen.UI_EXPECTED_TESTS:
            cls, method = name.split(".", 1)
            lines.append(self._started(cls, method))
            lines.append(self._line(cls, method, "passed"))
        results = pgen.parse_ui_test_log("\n".join(lines))
        self.assertEqual(len(results), 17)
        self.assertEqual(set(results), set(pgen.UI_EXPECTED_TESTS))


class CheckUiTestCoverageTests(unittest.TestCase):
    def test_exact_seventeen_is_ok(self):
        results = {name: "PASS" for name in pgen.UI_EXPECTED_TESTS}
        self.assertEqual(pgen.check_ui_test_coverage(results), [])

    def test_missing_one_is_reported(self):
        results = {name: "PASS" for name in pgen.UI_EXPECTED_TESTS[1:]}
        reasons = pgen.check_ui_test_coverage(results)
        self.assertTrue(any(pgen.UI_EXPECTED_TESTS[0] in r for r in reasons))

    def test_extra_test_is_reported(self):
        results = {name: "PASS" for name in pgen.UI_EXPECTED_TESTS}
        results["SomeOtherUITests.testWeird"] = "PASS"
        reasons = pgen.check_ui_test_coverage(results)
        self.assertTrue(any("SomeOtherUITests.testWeird" in r for r in reasons))


def _m0_steps():
    from h02_gate_model import STEPS

    return {
        f"{label}.{step}": {"sig_set": [], "allowed_codes": [], "stable": True, "observations": []}
        for label, steps in STEPS.items()
        for step in steps
    }


def stage_healthy_m0(root, positive_control_ok=True, defect2_reproduced=True, defect3_status="CAUGHT"):
    data = {
        "schema": r27.R27_PROFILE_SCHEMA,
        "kind": "m0",
        "tree_hash": "aa" * 20,
        "cdhash": "bb" * 20,
        "steps": _m0_steps(),
        "checks": {
            "positive_control_ok": positive_control_ok,
            "endpoint_steps_ok": [],
            "defect3": {"status": defect3_status},
            "defect2_reproduced": defect2_reproduced,
            "defect2_steps": [],
        },
    }
    r27.stage_component(root, "m0", data)


def stage_healthy_mutant(root, name, kill_ok=True, required_baseline_pass_ok=True):
    component = name.lower()
    data = {
        "schema": r27.R27_PROFILE_SCHEMA,
        "kind": component,
        "kill_signatures": {"T1.s1": ["C2-STACK|G=T11|over=T10|side=L"]},
        "checks": {
            "kill_ok": kill_ok,
            "required_steps": [["T1", "s1"]],
            "required_baseline_pass_ok": required_baseline_pass_ok,
            "required_baseline_pass_steps": [["T1", "s1"]] if required_baseline_pass_ok else [],
        },
    }
    r27.stage_component(root, component, data)


def stage_healthy_ui(root):
    data = {
        "schema": r27.R27_PROFILE_SCHEMA,
        "kind": "ui_t0_prime",
        "results": {name: "PASS" for name in pgen.UI_EXPECTED_TESTS},
    }
    r27.stage_component(root, "ui_t0_prime", data)


def stage_all_healthy(root):
    stage_healthy_m0(root)
    stage_healthy_mutant(root, "M2")
    stage_healthy_mutant(root, "M3")
    stage_healthy_ui(root)


class Scene0CheckTests(unittest.TestCase):
    """§7 場 0 的停止分支＋§6 場 0 列停止條件——每條停止條件各一個 STOP 測試＋一個全過的 PASS 測試。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def _stage_m0(self, **kwargs):
        stage_healthy_m0(self.root, **kwargs)

    def _stage_mutant(self, name, **kwargs):
        stage_healthy_mutant(self.root, name, **kwargs)

    def _stage_ui(self):
        stage_healthy_ui(self.root)

    def _stage_all_healthy(self):
        stage_all_healthy(self.root)

    def test_all_healthy_is_pass(self):
        self._stage_all_healthy()
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "PASS")
        self.assertEqual(result["reasons"], [])

    def test_m0_not_staged_is_stop(self):
        self._stage_mutant("M2")
        self._stage_mutant("M3")
        self._stage_ui()
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "STOP")
        self.assertTrue(any("m0" in r for r in result["reasons"]))

    def test_positive_control_not_ok_is_stop(self):
        self._stage_m0(positive_control_ok=False)
        self._stage_mutant("M2")
        self._stage_mutant("M3")
        self._stage_ui()
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "STOP")
        self.assertFalse(result["checks"]["positive_control_ok"])

    def test_defect2_not_reproduced_is_stop(self):
        self._stage_m0(defect2_reproduced=False)
        self._stage_mutant("M2")
        self._stage_mutant("M3")
        self._stage_ui()
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "STOP")
        self.assertFalse(result["checks"]["defect2_reproduced"])

    def test_defect3_not_caught_is_stop(self):
        self._stage_m0(defect3_status="NOT_CAUGHT")
        self._stage_mutant("M2")
        self._stage_mutant("M3")
        self._stage_ui()
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "STOP")
        self.assertFalse(result["checks"]["defect3_caught"])

    def test_m2_not_staged_is_stop(self):
        self._stage_m0()
        self._stage_mutant("M3")
        self._stage_ui()
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "STOP")
        self.assertFalse(result["checks"]["m2_staged"])

    def test_m2_required_baseline_pass_not_ok_is_stop(self):
        self._stage_m0()
        self._stage_mutant("M2", required_baseline_pass_ok=False)
        self._stage_mutant("M3")
        self._stage_ui()
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "STOP")
        self.assertFalse(result["checks"]["m2_required_baseline_pass_ok"])

    def test_m2_kill_not_ok_is_stop(self):
        self._stage_m0()
        self._stage_mutant("M2", kill_ok=False)
        self._stage_mutant("M3")
        self._stage_ui()
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "STOP")
        self.assertFalse(result["checks"]["m2_kill_ok"])

    def test_m3_not_staged_is_stop(self):
        self._stage_m0()
        self._stage_mutant("M2")
        self._stage_ui()
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "STOP")
        self.assertFalse(result["checks"]["m3_staged"])

    def test_ui_not_staged_is_stop(self):
        self._stage_m0()
        self._stage_mutant("M2")
        self._stage_mutant("M3")
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "STOP")
        self.assertFalse(result["checks"]["ui_t0_prime_staged"])

    def test_two_invalid_attempts_stay_terminal_even_after_a_later_valid_batch(self):
        """§7 場 0 停止分支第 4 條的「即停」是**終局**的：兩份無效一旦累積，場 0 當下就該結束，
        不得靠之後再跑出一份有效批次把它抹掉——否則無效上限可以用「跑到有效為止」繞過，
        正是 §10 R10 要防的。（Codex review 2026-09-19 指出原實作在此 fail-open。）"""
        self._stage_all_healthy()
        pgen.record_invalid_attempt(self.root, "M2", "m2", ["reason A"])
        pgen.record_invalid_attempt(self.root, "M2", "m2", ["reason B"])
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "STOP")
        self.assertTrue(result["checks"]["attempts_stop_triggered"])

    def test_two_invalid_attempts_for_never_staged_run_kind_is_stop(self):
        self._stage_m0()
        self._stage_mutant("M3")
        self._stage_ui()
        pgen.record_invalid_attempt(self.root, "M2", "m2", ["build failed"])
        pgen.record_invalid_attempt(self.root, "M2", "m2", ["build failed again"])
        result = pgen.evaluate_scene0_check(self.root)
        self.assertEqual(result["result"], "STOP")
        self.assertTrue(result["checks"]["attempts_stop_triggered"])

    def test_single_invalid_attempt_for_never_staged_run_kind_does_not_stop_by_itself(self):
        """1 份無效不足以觸發第 4 條（但 m2 本身仍未 staged，會被「m2 未 staged」條件擋下）。"""
        self._stage_m0()
        self._stage_mutant("M3")
        self._stage_ui()
        pgen.record_invalid_attempt(self.root, "M2", "m2", ["build failed"])
        result = pgen.evaluate_scene0_check(self.root)
        self.assertFalse(result["checks"]["attempts_stop_triggered"])


class WriteScene0CheckTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def test_writes_file_with_staging_sha256_for_present_components(self):
        data = {
            "schema": r27.R27_PROFILE_SCHEMA,
            "kind": "ui_t0_prime",
            "results": {name: "PASS" for name in pgen.UI_EXPECTED_TESTS},
        }
        r27.stage_component(self.root, "ui_t0_prime", data)
        payload = pgen.write_scene0_check(self.root)
        self.assertEqual(payload["result"], "STOP")  # 只有 ui staged，其餘缺
        self.assertIn("ui_t0_prime", payload["staging_sha256"])
        self.assertNotIn("m0", payload["staging_sha256"])
        on_disk = json.loads(pgen.check_file_path(self.root).read_text(encoding="utf-8"))
        self.assertEqual(on_disk, payload)


class EvaluateActivateGateTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def test_no_check_yet_is_refused(self):
        """空 staging 下，第一道（現場重算停止條件）就先攔——不採信 check 檔的那道在其後。
        「缺 check 檔」本身的拒絕見 CLI 層 `ActivateCliTests.test_activate_without_check_is_refused`
        （四份都 staged、現場重算 PASS，只差沒跑過 check）。"""
        ok, reasons = pgen.evaluate_activate_gate(self.root)
        self.assertFalse(ok)
        self.assertTrue(any("現場重算" in r for r in reasons), reasons)
        self.assertTrue(any("m0 尚未 staged" in r for r in reasons), reasons)

    def test_check_stop_is_refused(self):
        stage_healthy_ui(self.root)  # 只 staged 一元件 → STOP
        pgen.write_scene0_check(self.root)
        ok, reasons = pgen.evaluate_activate_gate(self.root)
        self.assertFalse(ok)

    def test_check_pass_but_staging_changed_after_is_refused(self):
        stage_all_healthy(self.root)
        payload = pgen.write_scene0_check(self.root)
        self.assertEqual(payload["result"], "PASS")
        path = pgen.staging_component_path(self.root, "ui_t0_prime")
        original = json.loads(path.read_text(encoding="utf-8"))
        original["results"]["ShellUITests.testFoo"] = "FAIL"  # check 通過後事後竄改
        path.write_text(json.dumps(original), encoding="utf-8")
        ok, reasons = pgen.evaluate_activate_gate(self.root)
        self.assertFalse(ok)
        self.assertTrue(any("已變動" in r for r in reasons))

    def test_check_pass_and_unchanged_is_accepted(self):
        stage_all_healthy(self.root)
        payload = pgen.write_scene0_check(self.root)
        self.assertEqual(payload["result"], "PASS")
        ok, reasons = pgen.evaluate_activate_gate(self.root)
        self.assertTrue(ok, reasons)


if __name__ == "__main__":
    unittest.main()
