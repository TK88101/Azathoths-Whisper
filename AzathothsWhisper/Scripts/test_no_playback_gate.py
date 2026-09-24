#!/usr/bin/env python3
"""no_playback_gate.sh 的測試（計劃 AC9 ③、AC8c）：對 repo 退出 0；每條禁止模式各一負對照退出非 0。

原為 Tests/Services/NoPlaybackGateScriptTests.swift，2026-09-23 simcodex R1 移到這裡：單元測試宿主是 app 本身，
每次重建換新簽章，子行程開 ~/Documents 底下的專案檔會卡在系統的存取授權上（bash 停在 getcwd → open，
全量中由 3 秒惡化到逾時）。從終端機跑的這一層沒有這個問題。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest test_no_playback_gate
"""
from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "no_playback_gate.sh"


def run(*arguments: str, stdin: str = "") -> subprocess.CompletedProcess:
    return subprocess.run(["/bin/bash", str(SCRIPT), *arguments], input=stdin, capture_output=True, text=True, timeout=60)


FORBIDDEN = [
    ("UI/Foo.swift", 'let s = NSAppleScript(source: "")'),
    ("Features/Foo.swift", "e.sendEvent(options: [], timeout: 1)"),
    ("App/Foo.swift", "import Carbon"),
    ("Infra/Foo.swift", "MediaRemote.send()"),
    ("UI/Foo.swift", "import ScriptingBridge"),
    ("Services/Music/MusicAppleEventsClient.swift", 'x.perform(Selector(("pause")))'),
    ("Services/Music/MusicAppleEventsClient.swift", 'x.value(forKey: "playpause")'),
    ("Services/Music/MusicAppleEventsClient.swift", 'x.setValue(true, forKey: "shuffleEnabled")'),
    ("Services/Music/MusicAppleEventsClient.swift", "tracks.add(obj)"),
    ("Services/Music/QueueFileSource.swift", "try data.write(to: url)"),
    ("Services/Music/QueueFileSource.swift", "try FileManager.default.removeItem(at: url)"),
]


class NoPlaybackGateTests(unittest.TestCase):
    def test_repository_passes_the_gate(self) -> None:
        result = run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_each_forbidden_pattern_is_caught(self) -> None:
        for path, line in FORBIDDEN:
            with self.subTest(path=path, line=line):
                result = run("--stdin", path, stdin=line + "\n")
                self.assertNotEqual(result.returncode, 0, f"未攔下：{path} ← {line}")

    def test_allowed_patterns_pass(self) -> None:
        allowed = [
            ("Services/Music/MusicAppleEventsClient.swift", 'let reference = artwork.value(forKey: "rawData")'),
            ("Services/Music/MusicAppleEventsClient.swift", "import ScriptingBridge"),
            ("Services/Music/QueueFileSource.swift", "let data = try Data(contentsOf: url)"),
        ]
        for path, line in allowed:
            with self.subTest(path=path, line=line):
                result = run("--stdin", path, stdin=line + "\n")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
