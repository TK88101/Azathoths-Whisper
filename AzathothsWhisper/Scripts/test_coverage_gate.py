#!/usr/bin/env python3
"""coverage_gate.sh 的黑箱測試：餵合成的 xccov JSON 報表，驗判定與輸出（計劃 §14 R8）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest test_coverage_gate
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "coverage_gate.sh"
ROOT = os.path.realpath(Path(__file__).resolve().parent.parent)
PRODUCT = "Azathoth's Whisper.app"
UNIT = "AzathothsWhisperTests.xctest"
EXEMPT = "Services/Music/MusicAppleEventsClient.swift"


def entry(rel: str, covered: int, executable: int) -> dict:
    return {
        "path": f"{ROOT}/{rel}",
        "coveredLines": covered,
        "executableLines": executable,
        "lineCoverage": covered / executable if executable else 0.0,
    }


def report(product: list, unit: list | None = None) -> dict:
    targets = [{"name": PRODUCT, "files": product}]
    if unit is not None:
        targets.append({"name": UNIT, "files": unit})
    return {"targets": targets}


def healthy_product(exempt_executable: int = 384) -> list:
    """實測形狀的縮影：豁免檔幾乎沒覆蓋、其餘高覆蓋（豁免前 < 80%、豁免後 ≥ 80%）"""
    return [
        entry(EXEMPT, 10, exempt_executable),
        entry("Services/Music/QueueSnapshot.swift", 900, 1000),
        entry("Infra/HTTPClient.swift", 90, 100),
        entry("Features/Editor/EditorView.swift", 0, 500),   # Features 不進分母
    ]


class CoverageGateTests(unittest.TestCase):
    def run_gate(self, data: dict) -> subprocess.CompletedProcess:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump(data, handle)
            path = handle.name
        self.addCleanup(os.unlink, path)
        return subprocess.run([str(SCRIPT), path], capture_output=True, text=True, timeout=60)

    def assertFails(self, result: subprocess.CompletedProcess, needle: str) -> None:
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(needle, result.stdout + result.stderr)

    def test_passes_after_exemption_and_prints_both_ratios(self) -> None:
        result = self.run_gate(report(healthy_product()))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("before exemptions", result.stdout)
        self.assertIn("(990/1100)", result.stdout)          # 豁免後＝判定值
        self.assertIn("(1000/1484)", result.stdout)         # 豁免前也要印出
        self.assertIn(EXEMPT, result.stdout)
        self.assertIn("approved 2026-09-23", result.stdout)
        self.assertIn("ScriptingBridge", result.stdout)     # 理由

    def test_fails_when_ratio_after_exemption_is_below_threshold(self) -> None:
        product = [entry(EXEMPT, 10, 384), entry("Services/Lyrics/GeniusParser.swift", 70, 100)]
        self.assertFails(self.run_gate(report(product)), "threshold 80%")

    def test_fails_when_exempted_file_is_missing_from_the_product_target(self) -> None:
        product = [entry("Services/Lyrics/GeniusParser.swift", 90, 100)]
        self.assertFails(self.run_gate(report(product)), "exemption not found")

    def test_exempted_file_only_in_a_test_target_counts_as_missing(self) -> None:
        product = [entry("Services/Lyrics/GeniusParser.swift", 90, 100)]
        self.assertFails(self.run_gate(report(product, unit=[entry(EXEMPT, 10, 384)])), "exemption not found")

    def test_fails_when_exempted_file_appears_twice(self) -> None:
        product = healthy_product() + [entry(EXEMPT, 0, 384)]
        self.assertFails(self.run_gate(report(product)), "exemption matched 2 files")

    def test_fails_when_exempted_file_has_no_executable_lines(self) -> None:
        self.assertFails(self.run_gate(report(healthy_product(exempt_executable=0))), "no executable lines")

    def test_fails_when_exemptions_exceed_the_line_budget(self) -> None:
        self.assertFails(self.run_gate(report(healthy_product(exempt_executable=401))), "budget 400")

    def test_services_files_outside_the_product_target_do_not_count(self) -> None:
        unit = [entry("Services/Lyrics/Stub.swift", 0, 5000)]   # 若計入會把比例拉到 80% 以下
        result = self.run_gate(report(healthy_product(), unit=unit))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_only_top_level_services_and_infra_count(self) -> None:
        product = healthy_product() + [entry("Features/Services/Helper.swift", 0, 5000)]
        result = self.run_gate(report(product))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
