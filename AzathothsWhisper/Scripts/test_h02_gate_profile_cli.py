#!/usr/bin/env python3
"""`h02_gate_eval.py profile <子命令>` CLI 單測（F2b：R27 staging 產生器與 profile CLI，
`docs/plans/2026-09-13-coverflow-h02-fix4.md` §13 v5 提案第 5、13 項）。

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
import h02_gate_profile_gen as pgen
import test_h02_gate_fixtures as fx

RUN_ENV_TEXT = "os_build=26A428,xcode_build=27A266a,sdk=macosx27.0"


def write_manifest(directory, name, tree=None, **overrides):
    data = {
        "tree": tree or name,
        "swift_hashlist_sha256": f"{name.lower()}" * 8,
        "cdhash": f"{name.lower()}cd" * 8,
        "os_build": "26A428",
        "xcode_build": "27A266a",
        "sdk": "macosx27.0",
        "display": "Built-in Liquid Retina XDR Display",
    }
    data.update(overrides)
    path = Path(directory) / f"{name}.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return str(path)


def ui_log_text(overrides=None, drop=(), extra=()):
    """依 `ui-T0.log` 真實格式（見 `h02_gate_profile_gen` 模組 docstring）組出最小夾具。"""
    overrides = overrides or {}
    lines = []
    for full_name in pgen.UI_EXPECTED_TESTS:
        if full_name in drop:
            continue
        cls, method = full_name.split(".", 1)
        verb = overrides.get(full_name, "passed")
        lines.append(f"Test Case '-[AzathothsWhisperUITests.{cls} {method}]' started.")
        lines.append(f"Test Case '-[AzathothsWhisperUITests.{cls} {method}]' {verb} (1.0 seconds).")
    for full_name in extra:
        cls, method = full_name.split(".", 1)
        lines.append(f"Test Case '-[AzathothsWhisperUITests.{cls} {method}]' started.")
        lines.append(f"Test Case '-[AzathothsWhisperUITests.{cls} {method}]' passed (1.0 seconds).")
    return "\n".join(lines) + "\n"


class ProfileCliTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.root = str(Path(self.tmp) / "r27-profile")
        self.addCleanup(self._tmp.cleanup)

    def run_cli(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = gate.main(argv)
        return code, out.getvalue(), err.getvalue()

    def stage_m0(self, base=None, n=10, extra_args=()):
        log_path, xc_path = fx.write_run(self.tmp, "cf-m0-27", n=n, base=base or fx.FROZEN_M0)
        manifest = write_manifest(self.tmp, "M0")
        argv = [
            "profile", "stage-m0",
            "--profile-dir", self.root,
            "--log", log_path, "--xcresult", xc_path, "--iterations", str(n),
            "--tree-manifest", manifest,
            "--run-env-fingerprint", RUN_ENV_TEXT,
        ] + list(extra_args)
        return self.run_cli(argv), log_path, xc_path

    def stage_all_four(self):
        """四份健康運行走完整 `profile stage-*` CLI 流程（`EndToEndSceneZeroTests`／
        `ActivateCliTests` 共用）。"""
        (code0, _, err0), m0_log, m0_xc = self.stage_m0()
        self.assertEqual(code0, 0, err0)

        for name, overrides in (("M2", fx.MUTANT_KILLED), ("M3", fx.M3_KILL)):
            log_path, xc_path = fx.write_run(self.tmp, f"cf-{name}-27", n=3, overrides=overrides)
            manifest = write_manifest(self.tmp, name)
            code, out, err = self.run_cli(
                [
                    "profile", "stage-mutant", "--profile-dir", self.root, "--name", name,
                    "--log", log_path, "--xcresult", xc_path, "--iterations", "3",
                    "--baseline-log", m0_log, "--baseline-xcresult", m0_xc, "--baseline-iterations", "10",
                    "--tree-manifest", manifest, "--run-env-fingerprint", RUN_ENV_TEXT,
                ]
            )
            self.assertEqual(code, 0, err)

        ui_log = Path(self.tmp) / "ui-T0p.log"
        ui_log.write_text(ui_log_text(), encoding="utf-8")
        ui_xc = Path(self.tmp) / "ui-T0p.xcresult"
        ui_xc.mkdir()
        ui_manifest = write_manifest(self.tmp, "uiT0p", tree="ui-T0p")
        code, out, err = self.run_cli(
            [
                "profile", "stage-ui", "--profile-dir", self.root,
                "--log", str(ui_log), "--xcresult", str(ui_xc),
                "--tree-manifest", ui_manifest,
            ]
        )
        self.assertEqual(code, 0, err)


class StageM0Tests(ProfileCliTestCase):
    def test_valid_run_freezes_staging(self):
        (code, out, err), _, _ = self.stage_m0()
        self.assertEqual(code, 0, err)
        self.assertTrue((Path(self.root) / "staging" / "m0.staging.json").is_file())

    def test_invalid_run_records_attempt_and_does_not_stage(self):
        # 用「缺測試」造無效（`table_valid` 的「缺測試」判據）：drop_tests 讓某測試完全不出現
        log_path, xc_path = fx.write_run(self.tmp, "cf-m0-bad", n=10, drop_tests=("T3",), base=fx.FROZEN_M0)
        manifest = write_manifest(self.tmp, "M0")
        code, out, err = self.run_cli(
            [
                "profile", "stage-m0", "--profile-dir", self.root,
                "--log", log_path, "--xcresult", xc_path, "--iterations", "10",
                "--tree-manifest", manifest, "--run-env-fingerprint", RUN_ENV_TEXT,
            ]
        )
        self.assertEqual(code, 2)
        self.assertFalse((Path(self.root) / "staging" / "m0.staging.json").is_file())
        attempts = (Path(self.root) / "staging" / "attempts.jsonl").read_text(encoding="utf-8")
        self.assertIn('"tree": "M0"', attempts)
        self.assertIn('"run_kind": "m0"', attempts)

    def test_first_freeze_refuses_second_stage(self):
        (code1, _, _), _, _ = self.stage_m0()
        self.assertEqual(code1, 0)
        (code2, out2, err2), _, _ = self.stage_m0()
        self.assertEqual(code2, 2)
        self.assertIn("首份規則", err2)

    def test_manifest_env_fingerprint_mismatch_is_rejected(self):
        log_path, xc_path = fx.write_run(self.tmp, "cf-m0-27", n=10, base=fx.FROZEN_M0)
        manifest = write_manifest(self.tmp, "M0", sdk="macosx26.5")  # 與 RUN_ENV_TEXT 的 sdk 不符
        code, out, err = self.run_cli(
            [
                "profile", "stage-m0", "--profile-dir", self.root,
                "--log", log_path, "--xcresult", xc_path, "--iterations", "10",
                "--tree-manifest", manifest, "--run-env-fingerprint", RUN_ENV_TEXT,
            ]
        )
        self.assertEqual(code, 2)
        self.assertIn("sdk", err)
        self.assertFalse((Path(self.root) / "staging" / "m0.staging.json").is_file())
        # 環境指紋不符屬輸入錯誤，不算「運行無效」，不進 attempts.jsonl
        self.assertFalse((Path(self.root) / "staging" / "attempts.jsonl").is_file())


class StageMutantTests(ProfileCliTestCase):
    def _stage_m2(self, baseline_log, baseline_xc, overrides=fx.MUTANT_KILLED, n=3, name="M2"):
        log_path, xc_path = fx.write_run(self.tmp, f"cf-{name}-27", n=n, overrides=overrides)
        manifest = write_manifest(self.tmp, name)
        argv = [
            "profile", "stage-mutant", "--profile-dir", self.root,
            "--name", name,
            "--log", log_path, "--xcresult", xc_path, "--iterations", str(n),
            "--baseline-log", baseline_log, "--baseline-xcresult", baseline_xc, "--baseline-iterations", "10",
            "--tree-manifest", manifest, "--run-env-fingerprint", RUN_ENV_TEXT,
        ]
        return self.run_cli(argv)

    def test_requires_m0_staged_first(self):
        log_path, xc_path = fx.write_run(self.tmp, "m0-unstaged", n=10, base=fx.FROZEN_M0)
        code, out, err = self._stage_m2(log_path, xc_path)
        self.assertEqual(code, 2)
        self.assertIn("必須先 stage-m0", err)

    def test_baseline_not_the_staged_m0_is_rejected(self):
        (code0, _, _), m0_log, m0_xc = self.stage_m0()
        self.assertEqual(code0, 0)
        # 內容必須真的不同（`write_run` 的輸出只由 grid 內容決定，跟檔名無關，同樣的
        # `base=FROZEN_M0, n=10, 無 overrides` 會產出逐位元組相同的 log，不足以測出 sha256 不符）
        different_log, different_xc = fx.write_run(
            self.tmp, "not-the-same-m0", n=10, base=fx.FROZEN_M0,
            overrides={("T3", "s1"): ["SIG{T3.s1|C6-NEVER-SETTLES}"]},
        )
        code, out, err = self._stage_m2(different_log, different_xc)
        self.assertEqual(code, 2)
        self.assertIn("baseline 必須就是被 staged 的那份 M0", err)

    def test_valid_stage_mutant_freezes_kill_signatures(self):
        (code0, _, _), m0_log, m0_xc = self.stage_m0()
        self.assertEqual(code0, 0)
        code, out, err = self._stage_m2(m0_log, m0_xc)
        self.assertEqual(code, 0, err)
        data = json.loads((Path(self.root) / "staging" / "m2.staging.json").read_text(encoding="utf-8"))
        self.assertIn("T1.s1", data["kill_signatures"])

    def test_first_freeze_refuses_second_stage(self):
        (code0, _, _), m0_log, m0_xc = self.stage_m0()
        self.assertEqual(code0, 0)
        code1, _, _ = self._stage_m2(m0_log, m0_xc)
        self.assertEqual(code1, 0)
        code2, out2, err2 = self._stage_m2(m0_log, m0_xc)
        self.assertEqual(code2, 2)
        self.assertIn("首份規則", err2)

    def test_m3_covers_t3s1(self):
        (code0, _, _), m0_log, m0_xc = self.stage_m0()
        self.assertEqual(code0, 0)
        code, out, err = self._stage_m2(m0_log, m0_xc, overrides=fx.M3_KILL, name="M3")
        self.assertEqual(code, 0, err)
        data = json.loads((Path(self.root) / "staging" / "m3.staging.json").read_text(encoding="utf-8"))
        self.assertIn("T3.s1", data["kill_signatures"])


class StageUiTests(ProfileCliTestCase):
    def _run(self, log_text, xcresult_exists=True):
        log_path = Path(self.tmp) / "ui-T0p.log"
        log_path.write_text(log_text, encoding="utf-8")
        xc_path = Path(self.tmp) / "ui-T0p.xcresult"
        if xcresult_exists:
            xc_path.mkdir(exist_ok=True)
        manifest = write_manifest(self.tmp, "uiT0p", tree="ui-T0p")
        return self.run_cli(
            [
                "profile", "stage-ui", "--profile-dir", self.root,
                "--log", str(log_path), "--xcresult", str(xc_path),
                "--tree-manifest", manifest,
            ]
        )

    def test_exact_seventeen_freezes_staging(self):
        code, out, err = self._run(ui_log_text())
        self.assertEqual(code, 0, err)
        data = json.loads((Path(self.root) / "staging" / "ui_t0_prime.staging.json").read_text(encoding="utf-8"))
        self.assertEqual(len(data["results"]), 17)

    def test_missing_one_is_rejected(self):
        code, out, err = self._run(ui_log_text(drop=(pgen.UI_EXPECTED_TESTS[0],)))
        self.assertEqual(code, 2)
        self.assertIn(pgen.UI_EXPECTED_TESTS[0], err)
        self.assertFalse((Path(self.root) / "staging" / "ui_t0_prime.staging.json").is_file())

    def test_extra_test_is_rejected(self):
        code, out, err = self._run(ui_log_text(extra=("SomeOtherUITests.testWeird",)))
        self.assertEqual(code, 2)
        self.assertIn("testWeird", err)

    def test_missing_xcresult_path_is_rejected(self):
        code, out, err = self._run(ui_log_text(), xcresult_exists=False)
        self.assertEqual(code, 2)


class EndToEndSceneZeroTests(ProfileCliTestCase):
    """F2b 規格：合成的四份運行 → stage ×4 → check → activate → negative-control --profile-dir
    讀到 active 並以 active 偏離下結論。"""

    def test_full_pipeline_and_negative_control_reads_active_with_deviation(self):
        self.stage_all_four()

        code, out, err = self.run_cli(["profile", "check", "--profile-dir", self.root])
        self.assertEqual(code, 0, out + err)
        self.assertIn("PASS", out)

        code, out, err = self.run_cli(["profile", "activate", "--profile-dir", self.root, "--version", "scene0-v1"])
        self.assertEqual(code, 0, out + err)
        self.assertTrue((Path(self.root) / "active" / "profile.json").is_file())

        # negative-control 的候選基準（K<n> 自己的 ×20 全 PASS 運行，與 R27 profile 的 M0 是不同概念）
        baseline_log, baseline_xc = fx.write_run(self.tmp, "candidate-baseline", n=20)
        # M2 評估運行：T1.s1 用不同 G/over 標籤（仍是 C2-STACK，仍算殺死）製造與 active profile 的簽名偏離；
        # T2.s1 沿用與 staged 時完全相同的簽名，驗證雙欄輸出能逐步分辨「偏離」與「未偏離」。
        deviating_m2 = {
            ("T1", "s1"): ["SIG{T1.s1|C2-STACK|G=T99|over=T88|side=L}"],
            ("T2", "s1"): list(fx.MUTANT_KILLED[("T2", "s1")]),
        }
        m2_log, m2_xc = fx.write_run(self.tmp, "eval-m2", n=3, overrides=deviating_m2)
        m3_log, m3_xc = fx.write_run(self.tmp, "eval-m3", n=3, overrides=fx.M3_KILL)

        code, out, err = self.run_cli(
            [
                "negative-control", "--profile-dir", self.root,
                "--baseline-log", baseline_log, "--baseline-xcresult", baseline_xc, "--baseline-iterations", "20",
                "--m2-log", m2_log, "--m2-xcresult", m2_xc,
                "--m3-log", m3_log, "--m3-xcresult", m3_xc, "--mutant-iterations", "3",
                "--run-env-fingerprint", RUN_ENV_TEXT,
            ]
        )
        self.assertEqual(code, 0, err)
        self.assertIn("結論=不可判定-待解釋", out)
        self.assertIn("active_profile_deviation", out)
        self.assertIn("G=T99", out)
        self.assertNotIn("尚無 active profile", out)


class CheckCliTests(ProfileCliTestCase):
    def test_check_before_any_staging_reports_stop(self):
        code, out, err = self.run_cli(["profile", "check", "--profile-dir", self.root])
        self.assertEqual(code, 1)
        self.assertIn("STOP", out)
        self.assertTrue((Path(self.root) / "staging" / "scene0-check.json").is_file())


class ActivateCliTests(ProfileCliTestCase):
    def test_activate_without_check_is_refused(self):
        """四份都 staged、現場重算亦為 PASS，但沒跑過 `profile check` → 仍拒絕（保留人工流程留痕）。"""
        self.stage_all_four()
        code, out, err = self.run_cli(["profile", "activate", "--profile-dir", self.root, "--version", "v1"])
        self.assertEqual(code, 2)
        self.assertIn("尚未執行過", err)

    def test_activate_after_stop_check_is_refused(self):
        self.run_cli(["profile", "check", "--profile-dir", self.root])  # 尚無 staging → STOP
        code, out, err = self.run_cli(["profile", "activate", "--profile-dir", self.root, "--version", "v1"])
        self.assertEqual(code, 2)

    def test_activate_after_staging_modified_post_check_is_refused(self):
        self.stage_all_four()
        code, out, err = self.run_cli(["profile", "check", "--profile-dir", self.root])
        self.assertEqual(code, 0, out + err)
        self.assertIn("PASS", out)

        # check 通過後手動竄改一份 staging 檔（不重跑 check）
        path = Path(self.root) / "staging" / "ui_t0_prime.staging.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["results"][pgen.UI_EXPECTED_TESTS[0]] = "FAIL"
        path.write_text(json.dumps(data), encoding="utf-8")

        code, out, err = self.run_cli(["profile", "activate", "--profile-dir", self.root, "--version", "v1"])
        self.assertEqual(code, 2)
        # 凍結帳本會在現場重算階段先抓到（訊息說「自凍結後被改動」）；即使帳本被一併刪除，
        # check 記錄的 sha256 比對仍會抓到（訊息說「已變動」）——兩條防線任一即可。
        self.assertIn("ui_t0_prime", err)
        self.assertTrue(("改動" in err) or ("變動" in err), err)
        self.assertFalse((Path(self.root) / "active" / "profile.json").is_file())

    def test_activate_after_check_pass_and_unchanged_succeeds(self):
        self.stage_all_four()
        code, out, err = self.run_cli(["profile", "check", "--profile-dir", self.root])
        self.assertEqual(code, 0, out + err)
        code, out, err = self.run_cli(["profile", "activate", "--profile-dir", self.root, "--version", "v1"])
        self.assertEqual(code, 0, err)
        self.assertTrue((Path(self.root) / "active" / "profile.json").is_file())


class ShowCliTests(ProfileCliTestCase):
    def test_show_before_anything_staged(self):
        code, out, err = self.run_cli(["profile", "show", "--profile-dir", self.root])
        self.assertEqual(code, 0, err)
        self.assertIn("(無)", out)
        self.assertIn("未 staged", out)


class ActivateTrustBoundaryTests(ProfileCliTestCase):
    """第 4 輪對抗覆核（2026-09-19）實測繞過成功的兩條信任邊界。"""

    def _forge_check_pass(self):
        """手寫一份聲稱 PASS 的 scene0-check.json（staging_sha256 照現檔正確計算）。"""
        import h02_gate_profile_gen as pgen
        payload = {
            "schema": 1,
            "result": "PASS",
            "reasons": [],
            "checks": {},
            "staging_sha256": {
                c: pgen.sha256_file(pgen.staging_component_path(self.root, c))
                for c in pgen.STAGING_COMPONENTS
                if pgen.staging_component_path(self.root, c).is_file()
            },
        }
        path = Path(self.root) / "staging" / "scene0-check.json"
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")

    def _stage_four_with_unkilling_m2(self):
        """四份都 staged，但 M2 的運行與 baseline 無差異＝未殺死 → 真實 check 必為 STOP。"""
        (code0, _, err0), m0_log, m0_xc = self.stage_m0()
        self.assertEqual(code0, 0, err0)
        # M2 只在非 required 的 T3.s1 殺死 → kill_signatures 非空（可 stage），但 kill_ok=False → check STOP
        weak_m2 = {("T3", "s1"): ["SIG{T3.s1|C2-STACK|G=T10|over=T09|side=L}"]}
        for name, overrides in (("M2", weak_m2), ("M3", fx.M3_KILL)):
            log_path, xc_path = fx.write_run(self.tmp, f"cf-{name}-27", n=3, overrides=overrides)
            manifest = write_manifest(self.tmp, name)
            code, out, err = self.run_cli(
                [
                    "profile", "stage-mutant", "--profile-dir", self.root, "--name", name,
                    "--log", log_path, "--xcresult", xc_path, "--iterations", "3",
                    "--baseline-log", m0_log, "--baseline-xcresult", m0_xc, "--baseline-iterations", "10",
                    "--tree-manifest", manifest, "--run-env-fingerprint", RUN_ENV_TEXT,
                ]
            )
            self.assertEqual(code, 0, err)
        ui_log = Path(self.tmp) / "ui-T0p.log"
        ui_log.write_text(ui_log_text(), encoding="utf-8")
        ui_xc = Path(self.tmp) / "ui-T0p.xcresult"
        ui_xc.mkdir()
        ui_manifest = write_manifest(self.tmp, "uiT0p", tree="ui-T0p")
        code, out, err = self.run_cli(
            [
                "profile", "stage-ui", "--profile-dir", self.root,
                "--log", str(ui_log), "--xcresult", str(ui_xc), "--tree-manifest", ui_manifest,
            ]
        )
        self.assertEqual(code, 0, err)

    def test_forged_check_file_cannot_activate(self):
        """activate 必須**現場重算**停止條件，不得採信 scene0-check.json 的記載——
        否則手寫一份 PASS（sha256 照算）就能啟用一份真實 check 為 STOP 的 profile。"""
        self._stage_four_with_unkilling_m2()
        code, out, err = self.run_cli(["profile", "check", "--profile-dir", self.root])
        self.assertEqual(code, 1, out + err)  # 真實 check ＝ STOP（1＝停止條件觸發，2 保留給輸入錯誤）
        self._forge_check_pass()
        code, out, err = self.run_cli(["profile", "activate", "--profile-dir", self.root, "--version", "forged"])
        self.assertEqual(code, 2, out + err)
        self.assertFalse((Path(self.root) / "active" / "profile.json").is_file())

    def test_edited_staging_cannot_be_re_blessed_by_rerunning_check(self):
        """手改 staging 後重跑 check 不得「重新祝福」：凍結帳本比對須讓 check 落 STOP
        （§7 首份規則、§10 R10「不得跑到綠為止」）。"""
        self.stage_all_four()
        code, out, err = self.run_cli(["profile", "check", "--profile-dir", self.root])
        self.assertEqual(code, 0, out + err)
        self.assertIn("PASS", out)

        m0_path = Path(self.root) / "staging" / "m0.staging.json"
        data = json.loads(m0_path.read_text(encoding="utf-8"))
        data["steps"]["T4.s2"]["allowed_codes"] = sorted(set(data["steps"]["T4.s2"]["allowed_codes"]) | {"C6-NEVER-SETTLES"})
        m0_path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")

        code, out, err = self.run_cli(["profile", "check", "--profile-dir", self.root])
        self.assertEqual(code, 1, out + err)
        self.assertIn("凍結", out + err)

        code, out, err = self.run_cli(["profile", "activate", "--profile-dir", self.root, "--version", "edited"])
        self.assertEqual(code, 2, out + err)
        self.assertFalse((Path(self.root) / "active" / "profile.json").is_file())


class IterationsGuardTests(ProfileCliTestCase):
    """§6 場 0 列：cf-m0-27 ×10、M2／M3 各 ×3。首份規則沒有覆蓋開關，一次打錯 --iterations
    就會把欠採樣的基準永久凍結，故在 stage 端就擋。"""

    def test_stage_m0_refuses_non_ten_iterations(self):
        (code, out, err), _, _ = self.stage_m0(n=3)
        self.assertEqual(code, 2, out + err)
        self.assertIn("10", out + err)
        self.assertFalse((Path(self.root) / "staging" / "m0.staging.json").is_file())

    def test_stage_mutant_refuses_non_three_iterations(self):
        (code0, _, err0), m0_log, m0_xc = self.stage_m0()
        self.assertEqual(code0, 0, err0)
        log_path, xc_path = fx.write_run(self.tmp, "cf-M2-27", n=10, overrides=fx.MUTANT_KILLED)
        manifest = write_manifest(self.tmp, "M2")
        code, out, err = self.run_cli(
            [
                "profile", "stage-mutant", "--profile-dir", self.root, "--name", "M2",
                "--log", log_path, "--xcresult", xc_path, "--iterations", "10",
                "--baseline-log", m0_log, "--baseline-xcresult", m0_xc, "--baseline-iterations", "10",
                "--tree-manifest", manifest, "--run-env-fingerprint", RUN_ENV_TEXT,
            ]
        )
        self.assertEqual(code, 2, out + err)
        self.assertFalse((Path(self.root) / "staging" / "m2.staging.json").is_file())


class CrossComponentEnvFingerprintTests(ProfileCliTestCase):
    """四份元件必須在同一環境凍結（§10 R13 的跨元件面）：m2／m3／ui 的 manifest 指紋
    與 m0 不一致時，check 落 STOP。"""

    def test_mutant_staged_in_other_environment_stops_check(self):
        (code0, _, err0), m0_log, m0_xc = self.stage_m0()
        self.assertEqual(code0, 0, err0)
        other_env = "os_build=99Z999,xcode_build=99A999,sdk=macosx99.0"
        log_path, xc_path = fx.write_run(self.tmp, "cf-M2-27", n=3, overrides=fx.MUTANT_KILLED)
        manifest = write_manifest(self.tmp, "M2", os_build="99Z999", xcode_build="99A999", sdk="macosx99.0")
        code, out, err = self.run_cli(
            [
                "profile", "stage-mutant", "--profile-dir", self.root, "--name", "M2",
                "--log", log_path, "--xcresult", xc_path, "--iterations", "3",
                "--baseline-log", m0_log, "--baseline-xcresult", m0_xc, "--baseline-iterations", "10",
                "--tree-manifest", manifest, "--run-env-fingerprint", other_env,
            ]
        )
        self.assertEqual(code, 0, err)
        code, out, err = self.run_cli(["profile", "check", "--profile-dir", self.root])
        self.assertEqual(code, 1, out + err)
        self.assertIn("環境指紋", out + err)


if __name__ == "__main__":
    unittest.main()
