"""CR-039 §11.5 B6：凍結的 LabelRing 分流規則（labelring_rule.py）。

fixture＝rc2 Time Profiler trace 縮小匯出（manifest.json 記抽取命令與 SHA-256）；預期輸出＝計劃附錄 D.9 表。
腳本或 fixture 改動＝本測試紅：規則凍結，改動須重走評審並更新 manifest。
"""
import dataclasses
import hashlib
import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import labelring_rule as rule  # noqa: E402

FIXTURE_DIR = os.path.join(HERE, "fixtures", "labelring")
FIXTURE = os.path.join(FIXTURE_DIR, "rc2-d9.json")
MS = 1_000_000


def manifest():
    with open(os.path.join(FIXTURE_DIR, "manifest.json"), encoding="utf-8") as f:
        return json.load(f)


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


class FreezeTests(unittest.TestCase):
    def test_script_and_fixture_match_manifest(self):
        m = manifest()
        self.assertEqual(sha256(os.path.join(HERE, "labelring_rule.py")), m["script_sha256"], "規則已改：重走評審並更新 manifest")
        self.assertEqual(sha256(FIXTURE), m["fixture_sha256"])


class FixtureReproducesD9Tests(unittest.TestCase):
    def setUp(self):
        self.loaded = rule.load_fixture(FIXTURE)
        self.result = rule.report(*self.loaded)

    def test_no_problems_and_unique_pid(self):
        self.assertEqual(self.result["problems"], [])
        self.assertEqual(len(self.loaded[4]), 1)

    def test_per_transition_matches_d9(self):
        expected = manifest()["expected"]["per_transition"]
        got = [{k: t[k] for k in ("id", "total_ms", "labelring_ms", "framework_only_ms", "labelring_in_over_budget")}
               for t in self.result["per_transition"]]
        self.assertEqual(got, expected)

    def test_judgement_matches_d9(self):
        self.assertEqual(self.result["judgement"], manifest()["expected"]["judgement"])


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.samples, self.symbols, self.signposts, self.updates, self.pids, self.header = rule.load_fixture(FIXTURE)

    def judge(self, samples=None, signposts=None, pids=None):
        result = rule.report(samples if samples is not None else self.samples, self.symbols,
                             signposts if signposts is not None else self.signposts, self.updates,
                             pids if pids is not None else self.pids, self.header)
        return result

    def test_more_than_one_pid_is_inconclusive(self):
        result = self.judge(pids=self.pids | {1})
        self.assertEqual(result["judgement"]["verdict"], "inconclusive")
        self.assertTrue(any("PID" in p for p in result["problems"]))

    def test_signposts_from_other_subsystem_are_ignored(self):
        foreign = [dict(row, subsystem=("other", "other")) for row in self.signposts]
        result = self.judge(signposts=foreign)
        self.assertEqual(result["per_transition"], [])
        self.assertEqual(result["judgement"]["verdict"], "inconclusive")

    def test_shifted_time_base_is_inconclusive(self):
        shifted = [dataclasses.replace(s, time_ns=s.time_ns + 3600 * 1_000 * MS) for s in self.samples]
        result = self.judge(samples=shifted)
        self.assertEqual(result["judgement"]["verdict"], "inconclusive")
        self.assertTrue(any("time base" in p for p in result["problems"]))


class LeadTests(unittest.TestCase):
    def test_compares_raw_weights_not_rounded(self):
        # 1.4999995 ms 對 1.0 ms：四捨五入到 0.1 ms 會變 1.5 倍（誤判 True）；原始權重 < 1.5 倍
        self.assertFalse(rule.leads({"top_app_ns": [("LabelRing", 1_499_999), ("Other", 1_000_000)]}))
        self.assertTrue(rule.leads({"top_app_ns": [("LabelRing", 1_500_000), ("Other", 1_000_000)]}))
        self.assertTrue(rule.leads({"top_app_ns": [("LabelRing", 1)]}))
        self.assertFalse(rule.leads({"top_app_ns": [("Other", 5), ("LabelRing", 1)]}))


class ClassifyTests(unittest.TestCase):
    symbols = {1: "main (in Yog-Sothoth's Echo)", 2: "closure #1 in closure #1 in LabelRing.body.getter (in Yog-Sothoth's Echo)",
               3: "BottomDock.body.getter (in Yog-Sothoth's Echo)", 4: "LabelLayout.ringAngles (in Yog-Sothoth's Echo)"}

    def sample(self, *frames):
        return rule.ProfileSample(0, MS, frames)  # 葉端在前

    def test_labelring_descendants_merge_and_ancestors_yield(self):
        self.assertEqual(rule.classify(self.sample(4, None, 2, None, 1), self.symbols), "LabelRing")

    def test_first_app_frame_after_entry(self):
        self.assertEqual(rule.classify(self.sample(None, 3, None, 1), self.symbols), "BottomDock.body.getter")

    def test_entry_only_is_framework(self):
        self.assertEqual(rule.classify(self.sample(None, 1), self.symbols), "framework-only")


class CommandLineTests(unittest.TestCase):
    def test_fixture_command_in_isolated_mode(self):
        result = subprocess.run([sys.executable, "-I", os.path.join(HERE, "labelring_rule.py"), "fixture", FIXTURE],
                                capture_output=True, text=True, cwd="/")
        self.assertEqual(result.returncode, 0, result.stderr[-300:])
        self.assertEqual(json.loads(result.stdout)["judgement"]["verdict"], "eligible")


if __name__ == "__main__":
    unittest.main()
