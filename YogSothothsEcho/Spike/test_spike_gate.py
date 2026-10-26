"""spike_gate.sh 的測試（sprint-0-detail.md §4.4）。執行：cd YogSothothsEcho/Spike && python3 -m unittest test_spike_gate"""
import pathlib
import subprocess
import unittest

GATE = pathlib.Path(__file__).resolve().parent / "spike_gate.sh"


def check(path, source):
    """把 source 當成 path 這個檔案檢查；回傳 (退出碼, stderr)。"""
    result = subprocess.run(["bash", str(GATE), "--stdin", path], input=source,
                            capture_output=True, text=True, check=False)
    return result.returncode, result.stderr


class SpikeGateTests(unittest.TestCase):
    def test_repository_passes_the_gate(self):
        result = subprocess.run(["bash", str(GATE)], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_each_forbidden_pattern_is_caught(self):
        cases = [
            ("other-ae-channel", "Sources/yse-spike/X.swift", "let s = NSAppleScript(source: src)"),
            ("other-ae-channel", "Sources/yse-spike/X.swift", "run(\"osascript\")"),
            ("other-ae-channel", "Sources/yse-spike/X.swift", "import Carbon"),
            ("dynamic-dispatch", "Sources/yse-spike/X.swift", "obj.perform(sel)"),
            ("dynamic-dispatch", "Sources/yse-spike/X.swift", "obj.setValue(1, forKey: k)"),
            ("kvc", "Sources/yse-spike/X.swift", "let v = obj.value(forKey: \"name\")"),
            ("setter-decl", "Sources/yse-spike/MusicBridge.swift", "@objc optional func setName(_ v: String)"),
            ("setter-decl", "Sources/yse-spike/MusicBridge.swift", "@objc optional var name: String { get set }"),
            ("scripting-bridge", "Sources/yse-spike/Other.swift", "import ScriptingBridge"),
            ("music-files", "Sources/yse-spike/Other.swift", "let p = \"Queue.dat\""),
            ("music-files", "Sources/yse-spike/Other.swift", "let p = \"History.dat\""),
            ("file-write", "Sources/yse-spike/Other.swift", "try data.write(to: url)"),
            ("file-write", "Sources/yse-spike/MusicFileReader.swift", "FileManager.default.removeItem(at: u)"),
            ("writer-scope", "Sources/yse-spike/ResultWriter.swift", "let q = queuePath // Queue"),
            ("writer-scope", "Sources/yse-spike/ResultWriter.swift", "let x = musicLibrary"),
            # security review M1 實測過的繞過路徑
            ("bridge-escape", "Sources/yse-spike/MusicBridge.swift", "(o as AnyObject).delete?()"),
            ("bridge-escape", "Sources/yse-spike/MusicBridge.swift", "e.removeAllObjects()"),
            ("bridge-escape", "Sources/yse-spike/MusicBridge.swift", "a.class(forScriptingClass: \"playlist\")"),
            ("bridge-escape", "Sources/yse-spike/MusicBridge.swift", "let f = objc_msgSend"),
            ("music-files", "Sources/yse-spike/Foo.swift", "let p = \"/x/Queue\" + \".dat\""),
            ("file-write", "Sources/yse-spike/Foo.swift", "open(path, 0x0201)"),
            ("file-write", "Sources/yse-spike/Foo.swift", "rename(a, b)"),
            ("file-write", "Sources/yse-spike/Foo.swift", "unlink(p)"),
            ("file-write", "Sources/yse-spike/Foo.swift", "try fm.trashItem(at: u, resultingItemURL: nil)"),
            ("file-write", "Sources/yse-spike/Foo.swift", "let fp = fopen(p, \"w\")"),
            # F-P-01 ③：只有 ShortcutRunner.swift 能叫 shortcuts；它只准寫、刪自己的暫存輸入檔 inputFile
            ("shortcut-runner", "Sources/yse-spike/Foo.swift", "p.executableURL = URL(fileURLWithPath: \"/usr/bin/shortcuts\")"),
            ("shortcut-runner", "Sources/yse-spike/Foo.swift", "let args = [\"shortcuts\", \"run\"]"),
            ("file-write", "Sources/yse-spike/ShortcutRunner.swift", "try data.write(to: url)"),
            ("file-write", "Sources/yse-spike/ShortcutRunner.swift", "try FileManager.default.removeItem(at: url)"),
            ("file-write", "Sources/yse-spike/ShortcutRunner.swift", "try input.write(to: other)"),
        ]
        for label, path, source in cases:
            with self.subTest(label=label, source=source):
                code, err = check(path, source + "\n")
                self.assertEqual(code, 1, f"未抓到：{source}")
                self.assertIn(f"[{label}]", err)

    def test_allowed_patterns_pass(self):
        cases = [
            ("Sources/yse-spike/MusicBridge.swift", "import ScriptingBridge"),
            ("Sources/yse-spike/MusicBridge.swift", "@objc optional func setPlayerPosition(_ v: Double)"),
            ("Sources/yse-spike/MusicBridge.swift", "@objc optional func setCurrentAirPlayDevices(_ v: [Any])"),
            ("Sources/yse-spike/MusicFileReader.swift", "let d = try Data(contentsOf: base.appending(path: \"Queue.dat\"))"),
            ("Sources/yse-spike/ResultWriter.swift", "try handle.write(contentsOf: line)"),
            ("Sources/yse-spike/X.swift", "// osascript 只在註解裡提到"),
            ("Sources/yse-spike/ShortcutRunner.swift", "p.executableURL = URL(fileURLWithPath: \"/usr/bin/shortcuts\")"),
            ("Sources/yse-spike/ShortcutRunner.swift", "try input.write(to: inputFile)"),
            ("Sources/yse-spike/ShortcutRunner.swift", "try? FileManager.default.removeItem(at: inputFile)"),
        ]
        for path, source in cases:
            with self.subTest(source=source):
                code, err = check(path, source + "\n")
                self.assertEqual(code, 0, err)


if __name__ == "__main__":
    unittest.main()
