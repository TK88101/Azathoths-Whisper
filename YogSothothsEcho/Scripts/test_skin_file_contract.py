"""CR-034 交件檔名契約的跨語言一致（simcodex 第 2 輪）：App `SpriteSkinAssets` 的檔名常數與 Python checker／匯入器的必須相同。
App 不從 skin.json 取檔名（安全評審 M-1／M-2），兩邊各寫一份常數，靠本測試守住不漂移。"""
import pathlib
import re
import runpy
import unittest

HERE = pathlib.Path(__file__).resolve().parent
SWIFT = HERE.parent / "Features" / "Turntable" / "SpriteSkin.swift"
CHECKER = runpy.run_path(str(HERE / "check_tonearm_skin.py"))
IMPORTER = runpy.run_path(str(HERE / "import_tonearm_skin.py"))


def swift_constant(name):
    match = re.search(rf'static let {name} = ("[^"]*"|\d+)', SWIFT.read_text(encoding="utf-8"))
    if match is None:
        raise AssertionError(f"SpriteSkin.swift 找不到 static let {name}")
    value = match.group(1)
    return value.strip('"') if value.startswith('"') else int(value)


class SkinFileContractTests(unittest.TestCase):
    def test_file_names_agree_across_swift_and_python(self):
        self.assertEqual(swift_constant("armPattern"), CHECKER["ARM_PATTERN"])
        self.assertEqual(swift_constant("shadowPattern"), CHECKER["SHADOW_PATTERN"])
        self.assertEqual(swift_constant("baseFile"), IMPORTER["UNDERLAY"])
        self.assertEqual(swift_constant("overlayFile"), IMPORTER["OVERLAY"])
        self.assertEqual(swift_constant("middleFile"), CHECKER["MIDDLE"])
        self.assertEqual(IMPORTER["MIDDLE"], CHECKER["MIDDLE"])

    def test_frame_count_agrees_with_the_contract_angles(self):
        self.assertEqual(swift_constant("frameCount"), len(CHECKER["ANGLES"]))


if __name__ == "__main__":
    unittest.main()
