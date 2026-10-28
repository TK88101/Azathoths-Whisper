"""check_xcstrings.py 的測試（sprint-1-detail.md §4.7）。"""
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

TOOL = pathlib.Path(__file__).with_name("check_xcstrings.py")
LANGS = ("en", "zh-Hant", "ja")


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def catalog(strings):
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def full(key):
    return {"localizations": {lang: unit(f"{key}-{lang}") for lang in LANGS}}


class CheckXcstringsTests(unittest.TestCase):
    def run_tool(self, strings, sources):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "Resources").mkdir()
            (root / "Resources" / "Localizable.xcstrings").write_text(json.dumps(catalog(strings)), encoding="utf-8")
            for rel, text in sources.items():
                path = root / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            result = subprocess.run([sys.executable, "-I", str(TOOL), "--root", str(root)], capture_output=True, text=True)
            return result.returncode, result.stderr

    def test_repository_passes(self):
        result = subprocess.run([sys.executable, "-I", str(TOOL)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_complete_catalog_and_code_pass(self):
        code, err = self.run_tool({"Dark": full("Dark")}, {"Features/A.swift": 'Text("Dark")\n'})
        self.assertEqual(code, 0, err)

    def test_missing_language_is_caught(self):
        entry = {"localizations": {"en": unit("Dark"), "ja": unit("ダーク")}}
        code, err = self.run_tool({"Dark": entry}, {})
        self.assertEqual(code, 1)
        self.assertIn("zh-Hant", err)

    def test_empty_value_is_caught(self):
        entry = full("Dark")
        entry["localizations"]["ja"] = unit("")
        code, err = self.run_tool({"Dark": entry}, {})
        self.assertEqual(code, 1)

    def test_plural_variation_passes(self):
        entry = full("%lld songs")
        entry["localizations"]["en"] = {"variations": {"plural": {"one": unit("%lld song"), "other": unit("%lld songs")}}}
        code, err = self.run_tool({"%lld songs": entry}, {})
        self.assertEqual(code, 0, err)

    def test_plural_without_other_is_caught(self):
        entry = full("%lld songs")
        entry["localizations"]["en"] = {"variations": {"plural": {"one": unit("%lld song")}}}
        code, err = self.run_tool({"%lld songs": entry}, {})
        self.assertEqual(code, 1)
        self.assertIn("other", err)

    def test_untranslated_plural_case_is_caught(self):
        entry = full("%lld songs")
        entry["localizations"]["en"] = {"variations": {"plural": {"one": unit("", ), "other": unit("%lld songs")}}}
        code, err = self.run_tool({"%lld songs": entry}, {})
        self.assertEqual(code, 1)

    def test_needs_review_is_caught(self):
        entry = full("Dark")
        entry["localizations"]["zh-Hant"] = unit("暗色", state="needs_review")
        code, err = self.run_tool({"Dark": entry}, {})
        self.assertEqual(code, 1)
        self.assertIn("needs_review", err)

    def test_key_used_in_code_but_missing_from_catalog_is_caught(self):
        for snippet in ['Text("Light")', 'Picker("Light", selection: $x) {}', 'String(localized: "Light")',
                        'Button("Light") {}', 'var title: LocalizedStringKey {\n  switch self { case .a: "Light" }\n}',
                        'let title = LocalizedStringResource("Light")']:
            with self.subTest(snippet=snippet):
                code, err = self.run_tool({"Dark": full("Dark")}, {"Features/A.swift": snippet + "\n"})
                self.assertEqual(code, 1)
                self.assertIn("Light", err)

    def test_interpolation_matches_format_key(self):
        code, err = self.run_tool({"Waiting: %lld": full("Waiting: %lld")},
                                  {"Features/A.swift": 'Text("Waiting: \\(count)")\n'})
        self.assertEqual(code, 0, err)

    def test_interpolation_without_format_key_is_caught(self):
        code, err = self.run_tool({"Waiting": full("Waiting")},
                                  {"Features/A.swift": 'Text("Waiting: \\(count)")\n'})
        self.assertEqual(code, 1)
        self.assertIn("Waiting: \\\\(count)", err)

    def test_verbatim_text_is_not_a_key(self):
        code, err = self.run_tool({}, {"Features/A.swift": 'Text(verbatim: "landscape")\n'})
        self.assertEqual(code, 0, err)


if __name__ == "__main__":
    unittest.main()
