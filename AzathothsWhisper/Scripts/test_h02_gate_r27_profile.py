#!/usr/bin/env python3
"""`h02_gate_r27_profile.py` 單測（v5 §13 第 5、13 項）：staging 元件 schema、原子啟用、
active／staging 隔離、`active_profile_deviations` 純函數。全部合成值，非真實場 0 證據。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_*.py'
"""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import h02_gate_r27_profile as r27


def valid_env_fingerprint():
    """v5 §10 R13：合成的環境指紋範例（非真實場 0 證據）。"""
    return {"os_build": "26A428", "xcode_build": "27A266a", "sdk": "MacOSX26.5.sdk"}


def valid_m0(env_fingerprint=None):
    data = {
        "schema": r27.R27_PROFILE_SCHEMA,
        "kind": "m0",
        "tree_hash": "aa" * 20,
        "cdhash": "bb" * 20,
        "steps": {
            "T1.s1": {"sig_set": [], "allowed_codes": [], "stable": True, "observations": []},
            "T4.s2": {
                "sig_set": ["C1-OFFSET|label=T19|centered=T16|strides=+3"],
                "allowed_codes": ["C1-OFFSET", "C2-STACK", "C3-TARGET-MISS", "C5-DRIFT"],
                "stable": False,
                "observations": ["10 次中 6 次 C1-OFFSET、4 次 C2-STACK"],
            },
        },
    }
    if env_fingerprint is not None:
        data["env_fingerprint"] = env_fingerprint
    return data


def valid_m2():
    return {
        "schema": r27.R27_PROFILE_SCHEMA,
        "kind": "m2",
        "kill_signatures": {
            "T1.s1": ["C2-STACK|G=T11|over=T10|side=L"],
            "T2.s1": ["C2-STACK|G=T11|over=T10|side=L"],
        },
    }


def valid_m3():
    return {
        "schema": r27.R27_PROFILE_SCHEMA,
        "kind": "m3",
        "kill_signatures": {
            "T1.s1": ["C2-STACK|G=T11|over=T10|side=L"],
            "T2.s1": ["C2-STACK|G=T11|over=T10|side=L"],
            "T3.s1": ["C2-STACK|G=T10|over=T09|side=L"],
        },
    }


def valid_ui_t0_prime():
    return {
        "schema": r27.R27_PROFILE_SCHEMA,
        "kind": "ui_t0_prime",
        "results": {"ShellUITests.testFoo": "PASS", "ShellUITests.testBatchLive": "SKIP"},
    }


class ParseM0ComponentTests(unittest.TestCase):
    def test_valid_round_trips_into_step_profiles(self):
        parsed = r27.parse_m0_component(valid_m0())
        self.assertEqual(parsed[("T1", "s1")].sig_set, frozenset())
        self.assertTrue(parsed[("T1", "s1")].stable)
        t4s2 = parsed[("T4", "s2")]
        self.assertFalse(t4s2.stable)
        self.assertEqual(t4s2.sig_set, frozenset({"C1-OFFSET|label=T19|centered=T16|strides=+3"}))
        self.assertEqual(t4s2.observations, ("10 次中 6 次 C1-OFFSET、4 次 C2-STACK",))

    def test_wrong_schema_rejected(self):
        with self.assertRaises(r27.ProfileError):
            r27.parse_m0_component({**valid_m0(), "schema": 99})

    def test_wrong_kind_rejected(self):
        with self.assertRaises(r27.ProfileError):
            r27.parse_m0_component({**valid_m0(), "kind": "m2"})

    def test_missing_steps_rejected(self):
        data = valid_m0()
        del data["steps"]
        with self.assertRaises(r27.ProfileError):
            r27.parse_m0_component(data)

    def test_bad_step_key_rejected(self):
        data = valid_m0()
        data["steps"] = {"T1s1": data["steps"]["T1.s1"]}
        with self.assertRaises(r27.ProfileError):
            r27.parse_m0_component(data)

    def test_non_bool_stable_rejected(self):
        data = valid_m0()
        data["steps"]["T1.s1"]["stable"] = "yes"
        with self.assertRaises(r27.ProfileError):
            r27.parse_m0_component(data)

    def test_sig_set_must_be_list(self):
        data = valid_m0()
        data["steps"]["T1.s1"]["sig_set"] = "C2-STACK"
        with self.assertRaises(r27.ProfileError):
            r27.parse_m0_component(data)


class ParseKillComponentTests(unittest.TestCase):
    def test_valid_m2_round_trips(self):
        parsed = r27.parse_kill_component(valid_m2(), "M2")
        self.assertEqual(parsed[("T1", "s1")], frozenset({"C2-STACK|G=T11|over=T10|side=L"}))

    def test_kind_must_match_lowercased_name(self):
        with self.assertRaises(r27.ProfileError):
            r27.parse_kill_component({**valid_m2(), "kind": "m3"}, "M2")

    def test_empty_kill_signatures_rejected(self):
        with self.assertRaises(r27.ProfileError):
            r27.parse_kill_component({**valid_m2(), "kill_signatures": {}}, "M2")

    def test_empty_signature_list_for_a_step_rejected(self):
        data = valid_m2()
        data["kill_signatures"]["T1.s1"] = []
        with self.assertRaises(r27.ProfileError):
            r27.parse_kill_component(data, "M2")


class ParseUiT0PrimeComponentTests(unittest.TestCase):
    def test_valid_round_trips(self):
        parsed = r27.parse_ui_t0_prime_component(valid_ui_t0_prime())
        self.assertEqual(parsed["ShellUITests.testFoo"], "PASS")

    def test_bad_outcome_rejected(self):
        data = valid_ui_t0_prime()
        data["results"]["ShellUITests.testFoo"] = "GREEN"
        with self.assertRaises(r27.ProfileError):
            r27.parse_ui_t0_prime_component(data)

    def test_empty_results_rejected(self):
        with self.assertRaises(r27.ProfileError):
            r27.parse_ui_t0_prime_component({**valid_ui_t0_prime(), "results": {}})


class StagingTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def test_stage_then_load_round_trips(self):
        r27.stage_component(self.root, "m0", valid_m0())
        loaded = r27.load_staging_component(self.root, "m0")
        self.assertEqual(loaded["kind"], "m0")

    def test_load_missing_component_returns_none(self):
        self.assertIsNone(r27.load_staging_component(self.root, "m2"))

    def test_stage_rejects_invalid_data_without_writing_file(self):
        bad = {**valid_m2(), "kill_signatures": {}}
        with self.assertRaises(r27.ProfileError):
            r27.stage_component(self.root, "m2", bad)
        self.assertIsNone(r27.load_staging_component(self.root, "m2"))

    def test_stage_unknown_component_name_rejected(self):
        with self.assertRaises(r27.ProfileError):
            r27.stage_component(self.root, "m4", valid_m2())

    def test_load_corrupt_staging_json_raises(self):
        path = self.root / "staging" / "m0.staging.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("{not json", encoding="utf-8")
        with self.assertRaises(r27.ProfileError):
            r27.load_staging_component(self.root, "m0")


class ActivateR27Tests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def stage_all(self, **overrides):
        components = {"m0": valid_m0(), "m2": valid_m2(), "m3": valid_m3(), "ui_t0_prime": valid_ui_t0_prime()}
        components.update(overrides)
        for name, data in components.items():
            r27.stage_component(self.root, name, data)

    def test_activate_before_any_staging_is_refused(self):
        with self.assertRaises(r27.ProfileError):
            r27.activate_r27(self.root, version="v1")
        self.assertIsNone(r27.load_active_profile(self.root))

    def test_staging_alone_never_counts_as_active(self):
        """§13 第 13 項：場 0 全程只寫 staging；建立中的 R27 不得被 `_signature_deviations`
        （即今日的 `_historical_r55_deviations`／`active_profile_deviations` 呼叫端）自比。"""
        self.stage_all()
        self.assertIsNone(r27.load_active_profile(self.root), "四份都 staged 但未 activate，仍不是 active")

    def test_partial_staging_refuses_activation_and_keeps_staging_evidence(self):
        r27.stage_component(self.root, "m0", valid_m0())
        r27.stage_component(self.root, "m2", valid_m2())
        # m3／ui_t0_prime 缺席（模擬場 0 中途停止）
        with self.assertRaises(r27.ProfileError) as ctx:
            r27.activate_r27(self.root, version="v1")
        self.assertIn("m3", str(ctx.exception))
        self.assertIn("ui_t0_prime", str(ctx.exception))
        self.assertIsNone(r27.load_active_profile(self.root))
        # 中途停止保留 staging 證據
        self.assertIsNotNone(r27.load_staging_component(self.root, "m0"))
        self.assertIsNotNone(r27.load_staging_component(self.root, "m2"))
        self.assertFalse((self.root / "active" / "profile.json").exists())

    def test_corrupt_one_staged_component_refuses_whole_activation(self):
        """部分內容即拒絕啟用：三份合法、一份在磁碟上被破壞（繞過 `stage_component` 自身寫入時
        的驗證，模擬 staging 檔案事後損毀），整體拒絕，不得只啟用「大致正確」的部分。"""
        self.stage_all()
        # 繞過 stage_component（它會在寫入前就拒絕），直接在磁碟上寫壞 m3 的 staging 檔。
        corrupt = {**valid_m3(), "kill_signatures": {}}
        (self.root / "staging" / "m3.staging.json").write_text(
            json.dumps(corrupt, ensure_ascii=False), encoding="utf-8"
        )
        with self.assertRaises(r27.ProfileError):
            r27.activate_r27(self.root, version="v1")
        self.assertIsNone(r27.load_active_profile(self.root))

    def test_m0_missing_tree_hash_refuses_activation(self):
        m0 = valid_m0()
        m0["tree_hash"] = ""
        self.stage_all(m0=m0)
        with self.assertRaises(r27.ProfileError):
            r27.activate_r27(self.root, version="v1")

    def test_successful_activation_round_trips_via_load_active_profile(self):
        self.stage_all()
        activated = r27.activate_r27(self.root, version="scene0-run-1")
        loaded = r27.load_active_profile(self.root)
        self.assertEqual(loaded, activated)
        self.assertEqual(loaded.version, "scene0-run-1")
        self.assertEqual(loaded.tree_hash, "aa" * 20)
        self.assertEqual(loaded.m2_kill[("T1", "s1")], frozenset({"C2-STACK|G=T11|over=T10|side=L"}))
        self.assertEqual(loaded.ui_t0_prime["ShellUITests.testFoo"], "PASS")

    def test_activation_manifest_records_four_component_hashes(self):
        self.stage_all()
        r27.activate_r27(self.root, version="v1")
        payload = json.loads((self.root / "active" / "profile.json").read_text(encoding="utf-8"))
        self.assertEqual(payload["active_profile"], "R27")
        self.assertEqual(set(payload["component_hashes"]), {"m0", "m2", "m3", "ui_t0_prime"})
        for digest in payload["component_hashes"].values():
            self.assertEqual(len(digest), 64)  # sha256 hex

    def test_activation_is_a_single_file_write_no_leftover_tmp(self):
        self.stage_all()
        r27.activate_r27(self.root, version="v1")
        active_dir = self.root / "active"
        names = sorted(p.name for p in active_dir.iterdir())
        self.assertEqual(names, ["profile.json"])

    def test_load_active_profile_on_corrupt_file_raises(self):
        self.stage_all()
        r27.activate_r27(self.root, version="v1")
        (self.root / "active" / "profile.json").write_text("{not json", encoding="utf-8")
        with self.assertRaises(r27.ProfileError):
            r27.load_active_profile(self.root)

    # -- must_fix 4：version 不得為空（§13 第 13 項配套修正） -----------------------------

    def test_empty_version_refuses_activation(self):
        """啟用前必須驗 version 為非空字串，否則會寫出一份之後 `load_active_profile` 永遠
        拋 ProfileError（缺 version）的殭屍 active 檔——與「尚未啟用」無法區分。"""
        self.stage_all()
        with self.assertRaises(r27.ProfileError):
            r27.activate_r27(self.root, version="")
        self.assertFalse((self.root / "active" / "profile.json").exists())
        self.assertIsNone(r27.load_active_profile(self.root))

    # -- must_fix 5：首份凍結，重複啟用預設拒絕 ----------------------------------------

    def test_second_activation_is_refused_by_default(self):
        """§7 場 0 停止分支 3「首份規則」：已有 active profile 時，第二次啟用預設拒絕，
        不得悄悄覆蓋第一份凍結。"""
        self.stage_all()
        r27.activate_r27(self.root, version="run-1")
        self.stage_all()  # 模擬又跑了一輪，重新 staging
        with self.assertRaises(r27.ProfileError):
            r27.activate_r27(self.root, version="run-2")
        loaded = r27.load_active_profile(self.root)
        self.assertEqual(loaded.version, "run-1")

    def test_allow_replace_overwrites(self):
        """顯式 `allow_replace=True` 才允許替換既有 active profile。"""
        self.stage_all()
        r27.activate_r27(self.root, version="run-1")
        self.stage_all()
        r27.activate_r27(self.root, version="run-2", allow_replace=True)
        loaded = r27.load_active_profile(self.root)
        self.assertEqual(loaded.version, "run-2")

    # -- must_fix 3：載入時重驗 manifest（缺／錯 component_hashes 必須被拒） -----------

    def test_active_file_missing_component_hashes_is_rejected(self):
        """手寫（未經 staging／activate）一份缺 `component_hashes` 的 active 檔必須被拒，
        不得照單全收（原始漏洞的重現）。"""
        active_dir = self.root / "active"
        active_dir.mkdir(parents=True)
        forged = {
            "schema": r27.R27_PROFILE_SCHEMA,
            "active_profile": "R27",
            "version": "forged",
            "components": {
                "m0": valid_m0(), "m2": valid_m2(), "m3": valid_m3(), "ui_t0_prime": valid_ui_t0_prime(),
            },
            # component_hashes 故意缺席
        }
        (active_dir / "profile.json").write_text(json.dumps(forged, ensure_ascii=False), encoding="utf-8")
        with self.assertRaises(r27.ProfileError):
            r27.load_active_profile(self.root)

    def test_active_file_wrong_component_hash_value_is_rejected(self):
        """`component_hashes` 語法合法（64 字元 hex）但與 `components` 原文重算的 sha256 不符
        時必須被拒——防止事後竄改內容卻保留一個看似合法的舊 hash。"""
        self.stage_all()
        r27.activate_r27(self.root, version="v1")
        target = self.root / "active" / "profile.json"
        payload = json.loads(target.read_text(encoding="utf-8"))
        payload["component_hashes"]["m0"] = "0" * 64
        target.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        with self.assertRaises(r27.ProfileError):
            r27.load_active_profile(self.root)

    # -- 追加項（§10 R13）：M0 的環境指紋 -----------------------------------------------

    def test_m0_without_env_fingerprint_defaults_to_empty_dict(self):
        """未附環境指紋＝該份 profile 未記錄，回空 dict（不是錯誤；比對時報 unknown）。"""
        self.stage_all()
        activated = r27.activate_r27(self.root, version="v1")
        self.assertEqual(activated.env_fingerprint, {})
        loaded = r27.load_active_profile(self.root)
        self.assertEqual(loaded.env_fingerprint, {})

    def test_m0_env_fingerprint_round_trips_through_activation(self):
        fp = valid_env_fingerprint()
        self.stage_all(m0=valid_m0(env_fingerprint=fp))
        activated = r27.activate_r27(self.root, version="v1")
        self.assertEqual(activated.env_fingerprint, fp)
        loaded = r27.load_active_profile(self.root)
        self.assertEqual(loaded.env_fingerprint, fp)

    def test_m0_env_fingerprint_missing_key_is_rejected(self):
        bad_fp = {"os_build": "26A428", "xcode_build": "27A266a"}  # 缺 sdk
        self.stage_all(m0=valid_m0(env_fingerprint=bad_fp))
        with self.assertRaises(r27.ProfileError):
            r27.activate_r27(self.root, version="v1")

    def test_m0_env_fingerprint_empty_value_is_rejected(self):
        bad_fp = {**valid_env_fingerprint(), "os_build": ""}
        self.stage_all(m0=valid_m0(env_fingerprint=bad_fp))
        with self.assertRaises(r27.ProfileError):
            r27.activate_r27(self.root, version="v1")


class ActiveProfileDeviationsTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)
        for name, data in (
            ("m0", valid_m0()),
            ("m2", valid_m2()),
            ("m3", valid_m3()),
            ("ui_t0_prime", valid_ui_t0_prime()),
        ):
            r27.stage_component(self.root, name, data)
        self.profile = r27.activate_r27(self.root, version="v1")

    def test_matching_signature_has_no_deviation(self):
        killed = [("T1", "s1", ["C2-STACK|G=T11|over=T10|side=L"])]
        self.assertEqual(r27.active_profile_deviations("M2", killed, self.profile), [])

    def test_mismatched_signature_is_a_deviation(self):
        killed = [("T1", "s1", ["C2-STACK|G=DIFFERENT"])]
        deviations = r27.active_profile_deviations("M2", killed, self.profile)
        self.assertTrue(any("T1.s1" in d for d in deviations), deviations)

    def test_unregistered_step_is_a_deviation(self):
        killed = [("T4", "s1", ["C2-STACK|G=T19|over=T18|side=L"])]
        deviations = r27.active_profile_deviations("M2", killed, self.profile)
        self.assertTrue(any("未登記" in d for d in deviations), deviations)

    def test_m3_uses_its_own_kill_signatures(self):
        killed = [("T3", "s1", ["C2-STACK|G=T10|over=T09|side=L"])]
        self.assertEqual(r27.active_profile_deviations("M3", killed, self.profile), [])

    def test_unknown_mutant_name_raises(self):
        with self.assertRaises(r27.ProfileError):
            r27.active_profile_deviations("M9", [], self.profile)


class EnvFingerprintCheckTests(unittest.TestCase):
    """§10 R13：profile 與受評運行的環境指紋比對——防止靜默採用為別的 OS 凍結的 profile。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def _activate_with_fingerprint(self, fingerprint):
        for name, data in (
            ("m0", valid_m0(env_fingerprint=fingerprint)),
            ("m2", valid_m2()),
            ("m3", valid_m3()),
            ("ui_t0_prime", valid_ui_t0_prime()),
        ):
            r27.stage_component(self.root, name, data)
        return r27.activate_r27(self.root, version="v1")

    def test_both_missing_is_unknown(self):
        profile = self._activate_with_fingerprint(None)
        status, reasons = r27.env_fingerprint_check(profile, None)
        self.assertEqual(status, "unknown")
        self.assertEqual(reasons, [])

    def test_profile_only_is_unknown(self):
        """§10 R13 落地備註：運行端指紋現行拿不到——只有 profile 有指紋時仍只能報 unknown，
        不得因此判定符合或不符合。"""
        profile = self._activate_with_fingerprint(valid_env_fingerprint())
        status, reasons = r27.env_fingerprint_check(profile, None)
        self.assertEqual(status, "unknown")
        self.assertEqual(reasons, [])

    def test_run_only_is_unknown(self):
        profile = self._activate_with_fingerprint(None)
        status, reasons = r27.env_fingerprint_check(profile, valid_env_fingerprint())
        self.assertEqual(status, "unknown")

    def test_matching_fingerprints_is_match(self):
        fp = valid_env_fingerprint()
        profile = self._activate_with_fingerprint(fp)
        status, reasons = r27.env_fingerprint_check(profile, dict(fp))
        self.assertEqual(status, "match")
        self.assertEqual(reasons, [])

    def test_mismatching_fingerprint_is_mismatch(self):
        fp = valid_env_fingerprint()
        profile = self._activate_with_fingerprint(fp)
        run_fp = dict(fp, os_build="99Z999")
        status, reasons = r27.env_fingerprint_check(profile, run_fp)
        self.assertEqual(status, "mismatch")
        self.assertTrue(any("os_build" in r for r in reasons), reasons)


if __name__ == "__main__":
    unittest.main()
