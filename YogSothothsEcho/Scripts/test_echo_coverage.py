"""echo_coverage.py 的判定測試（sprint-1-detail.md §4.7）：以假報表驗門檻、缺模組、排除清單。"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import echo_coverage as cov  # noqa: E402

ROOT = "/x/YogSothothsEcho"


def llvm(files):
    return {"data": [{"files": [{"filename": f"{ROOT}/Packages/EchoKit/Sources/{name}",
                                 "summary": {"lines": {"count": total, "covered": covered}}}
                                for name, covered, total in files]}]}


def xccov(files):
    return {"targets": [{"name": "Yog-Sothoth's Echo.app", "files": [
        {"path": f"{ROOT}/{path}", "coveredLines": covered, "executableLines": total}
        for path, covered, total in files]}]}


class EchoKitCoverageTests(unittest.TestCase):
    def modules(self, rp=(80, 100), rt=(8, 10), mb=(80, 100)):
        return llvm([("RemoteProtocol/A.swift", *rp), ("RemoteTransport/B.swift", *rt),
                     ("MusicRemoteBridge/C.swift", *mb)])

    ALL = set(cov.MODULES)

    def test_exactly_eighty_percent_passes(self):
        self.assertEqual(cov.judge_echokit(self.modules(), ROOT, self.ALL), [])

    def test_below_eighty_fails(self):
        failures = cov.judge_echokit(self.modules(rp=(799, 1000)), ROOT, self.ALL)
        self.assertEqual(len(failures), 1)
        self.assertIn("RemoteProtocol", failures[0])

    def test_module_without_sources_fails(self):
        report = llvm([("RemoteProtocol/A.swift", 9, 10), ("RemoteTransport/B.swift", 9, 10)])
        failures = cov.judge_echokit(report, ROOT, {"RemoteProtocol", "RemoteTransport"})
        self.assertTrue(any("MusicRemoteBridge" in f for f in failures))

    def test_module_with_sources_but_no_lines_fails(self):
        """有原始碼、報表卻 0 行＝可能是匯出漏掉（2026-10-15 假綠事故），一律判失敗"""
        report = llvm([("RemoteProtocol/A.swift", 9, 10), ("MusicRemoteBridge/C.swift", 9, 10)])
        failures = cov.judge_echokit(report, ROOT, self.ALL)
        self.assertEqual(len(failures), 1)
        self.assertIn("RemoteTransport", failures[0])

    def test_declaration_only_module_passes_only_when_listed_with_reason(self):
        report = llvm([("RemoteProtocol/A.swift", 9, 10), ("MusicRemoteBridge/C.swift", 9, 10)])
        original = dict(cov.DECLARATION_ONLY)
        cov.DECLARATION_ONLY["RemoteTransport"] = "測試用理由"
        try:
            self.assertEqual(cov.judge_echokit(report, ROOT, self.ALL), [])
        finally:
            cov.DECLARATION_ONLY.clear()
            cov.DECLARATION_ONLY.update(original)

    def test_every_declaration_only_entry_has_a_reason(self):
        self.assertTrue(all(reason.strip() for reason in cov.DECLARATION_ONLY.values()))

    def test_test_files_and_other_packages_are_ignored(self):
        report = self.modules()
        report["data"][0]["files"].append({"filename": f"{ROOT}/Packages/EchoKit/Tests/X/T.swift",
                                           "summary": {"lines": {"count": 100, "covered": 0}}})
        self.assertEqual(cov.judge_echokit(report, ROOT, self.ALL), [])


class TestBinaryDiscoveryTests(unittest.TestCase):
    """每個測試 target 各自一個 xctest；codecov JSON 只匯出其中一個，故閘門要自己合併（2026-10-15 假綠事故）"""

    def make_products(self, root, names):
        for name in names:
            exe = pathlib.Path(root) / f"{name}.xctest" / "Contents" / "MacOS" / name
            exe.parent.mkdir(parents=True)
            exe.write_bytes(b"")

    def test_finds_every_expected_test_binary(self):
        import tempfile
        with tempfile.TemporaryDirectory() as root:
            self.make_products(root, ["ATests", "BTests"])
            binaries, failures = cov.test_binaries(pathlib.Path(root), ["ATests", "BTests"])
            self.assertEqual(failures, [])
            self.assertEqual(sorted(b.name for b in binaries), ["ATests", "BTests"])

    def test_missing_test_binary_fails(self):
        import tempfile
        with tempfile.TemporaryDirectory() as root:
            self.make_products(root, ["ATests"])
            _, failures = cov.test_binaries(pathlib.Path(root), ["ATests", "BTests"])
            self.assertEqual(len(failures), 1)
            self.assertIn("BTests", failures[0])

    def test_export_command_lists_all_binaries_as_objects(self):
        command = cov.export_command(pathlib.Path("/p/default.profdata"),
                                     [pathlib.Path("/b/A"), pathlib.Path("/b/B"), pathlib.Path("/b/C")])
        self.assertEqual(command, ["xcrun", "llvm-cov", "export", "-summary-only", "-instr-profile",
                                   "/p/default.profdata", "/b/A", "-object", "/b/B", "-object", "/b/C"])

    def test_expected_targets_come_from_tests_directory(self):
        import tempfile
        with tempfile.TemporaryDirectory() as package:
            for name in ("RemoteProtocolTests", "RemoteTransportTests"):
                (pathlib.Path(package) / "Tests" / name).mkdir(parents=True)
            self.assertEqual(cov.expected_test_targets(pathlib.Path(package)),
                             ["RemoteProtocolTests", "RemoteTransportTests"])


class AppCoverageTests(unittest.TestCase):
    def test_features_and_services_combined_at_eighty_passes(self):
        report = xccov([("Features/Appearance/AppearanceViewModel.swift", 7, 10), ("Services/SettingsStore.swift", 9, 10)])
        self.assertEqual(cov.judge_app(report, ROOT), [])

    def test_below_eighty_fails(self):
        report = xccov([("Features/Appearance/AppearanceViewModel.swift", 7, 10), ("Services/SettingsStore.swift", 8, 10)])
        self.assertEqual(len(cov.judge_app(report, ROOT)), 1)

    def test_excluded_and_app_files_do_not_count(self):
        report = xccov([("Features/Appearance/AppearanceViewModel.swift", 8, 10),
                        ("Features/Shell/ShellView.swift", 0, 50), ("App/AppModel.swift", 0, 20)])
        original = dict(cov.APP_EXCLUDED)
        cov.APP_EXCLUDED["Features/Shell/ShellView.swift"] = "測試用理由"
        try:
            self.assertEqual(cov.judge_app(report, ROOT), [])
        finally:
            cov.APP_EXCLUDED.clear()
            cov.APP_EXCLUDED.update(original)

    def test_no_measured_files_fails(self):
        self.assertTrue(cov.judge_app(xccov([("App/AppModel.swift", 0, 20)]), ROOT))

    def test_every_exclusion_has_a_reason(self):
        self.assertTrue(all(reason.strip() for reason in cov.APP_EXCLUDED.values()))


if __name__ == "__main__":
    unittest.main()
