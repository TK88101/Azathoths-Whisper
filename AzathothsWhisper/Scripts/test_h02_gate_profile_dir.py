"""`--profile-dir` 的顯式／預設語義（H-02 fix4 v5；第 3 輪對抗覆核 must_fix）。

v3／verdict／negative-control 三個子命令共用 `h02_gate_cli._load_active_profile_arg`：
不給 → 讀預設路徑（缺檔＝尚無 active profile）；顯式給了卻缺 active/profile.json → exit 2。
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

import h02_gate_cli as gate_cli
import h02_gate_eval as gate
import test_h02_gate_fixtures as fx
from test_h02_gate_fixtures import FROZEN_M0, M2_KILL, M3_KILL, MUTANT_KILLED, write_run

C6_T3 = "SIG{T3.s1|C6-NEVER-SETTLES}"


class ProfileDirExplicitnessTests(unittest.TestCase):
    """`--profile-dir` 的顯式／預設語義（第 3 輪覆核 must_fix）：

    - 不給 `--profile-dir` → 讀預設路徑；預設路徑下尚無 active profile ＝「尚無 active profile」
      （場 0 的 cf-m0-27 首跑仰賴這個語義：甲案只出 deviations）；
    - **顯式**給了 `--profile-dir` 但該處沒有 active/profile.json → 輸入錯誤（exit 2）。
      否則打錯路徑會靜默降級成「無 profile」，v3／verdict 的結論會從不可判定翻成通過。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)
        empty_default = Path(self.tmp) / "default-r27-profile"
        patcher = mock.patch.object(gate_cli, "_DEFAULT_R27_PROFILE_DIR", str(empty_default))
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_cli(self, argv):
        return fx.run_gate_cli(argv)

    def _v3_args(self):
        log_path, xc_path = write_run(self.tmp, "m0", n=10, overrides={("T3", "s1"): [C6_T3]}, base=FROZEN_M0)
        return ["v3", "--log", log_path, "--xcresult", xc_path, "--iterations", "10"]

    def _verdict_args(self):
        m0_log, m0_xc = write_run(self.tmp, "m0", n=10, overrides={("T3", "s1"): [C6_T3]}, base=FROZEN_M0)
        m2_log, m2_xc = write_run(self.tmp, "m2", n=3, overrides=MUTANT_KILLED)
        m3_log, m3_xc = write_run(self.tmp, "m3", n=3, overrides=MUTANT_KILLED)
        return [
            "verdict",
            "--m0-log", m0_log, "--m0-xcresult", m0_xc,
            "--m2-log", m2_log, "--m2-xcresult", m2_xc,
            "--m3-log", m3_log, "--m3-xcresult", m3_xc,
            "--s2-verified",
        ]

    def test_v3_default_profile_dir_without_active_only_shows_deviations(self):
        code, out, _ = self.run_cli(self._v3_args())
        self.assertEqual(code, 0)
        self.assertIn("frozen_conformity_ok: True", out)
        self.assertIn("active_profile: 無", out)

    def test_v3_explicit_missing_profile_dir_is_input_error(self):
        code, out, err = self.run_cli(self._v3_args() + ["--profile-dir", str(Path(self.tmp) / "typo")])
        self.assertEqual(code, 2)
        self.assertIn("active/profile.json", err)
        self.assertNotIn("frozen_conformity_ok", out)

    def test_verdict_default_profile_dir_without_active_is_not_undecidable(self):
        code, out, _ = self.run_cli(self._verdict_args())
        self.assertEqual(code, 0)
        self.assertNotIn("不可判定", out)

    def test_verdict_explicit_missing_profile_dir_is_input_error(self):
        code, out, err = self.run_cli(self._verdict_args() + ["--profile-dir", str(Path(self.tmp) / "typo")])
        self.assertEqual(code, 2)
        self.assertIn("active/profile.json", err)
        self.assertNotIn("結論", out)


class NegativeControlProfileDirExplicitnessTests(unittest.TestCase):
    """negative-control 與 v3／verdict 同一語義：顯式給錯 `--profile-dir` ＝ 輸入錯誤（exit 2）；
    不給則讀預設路徑，預設路徑下尚無 active profile ＝「無效：缺 active profile」。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)
        patcher = mock.patch.object(gate_cli, "_DEFAULT_R27_PROFILE_DIR", str(Path(self.tmp) / "default"))
        patcher.start()
        self.addCleanup(patcher.stop)

    def _args(self):
        base_log, base_xc = write_run(self.tmp, "base", n=20)
        m2_log, m2_xc = write_run(self.tmp, "m2", n=3, overrides=M2_KILL)
        m3_log, m3_xc = write_run(self.tmp, "m3", n=3, overrides=M3_KILL)
        return [
            "negative-control",
            "--baseline-log", base_log, "--baseline-xcresult", base_xc, "--baseline-iterations", "20",
            "--m2-log", m2_log, "--m2-xcresult", m2_xc,
            "--m3-log", m3_log, "--m3-xcresult", m3_xc,
            "--mutant-iterations", "3",
        ]

    def run_cli(self, argv):
        return fx.run_gate_cli(argv)

    def test_default_profile_dir_without_active_is_invalid(self):
        code, out, _ = self.run_cli(self._args())
        self.assertEqual(code, 0)
        self.assertIn("結論=無效", out)

    def test_explicit_missing_profile_dir_is_input_error(self):
        code, out, err = self.run_cli(self._args() + ["--profile-dir", str(Path(self.tmp) / "typo")])
        self.assertEqual(code, 2)
        self.assertIn("active/profile.json", err)
        self.assertNotIn("結論", out)


if __name__ == "__main__":
    unittest.main()
