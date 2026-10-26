"""yse-spike pumpcheck 的測試（s0-offline-2026-10-15.md T1）：在真正的 CLI 程序裡驗 EventPump 的分派語意。
不碰 Music；跨程序通知由本測試以 osascript（JXA，只呼叫 NSDistributedNotificationCenter）發出，不對任何 app 送 Apple Event。
執行：cd YogSothothsEcho/Spike && YSE_SPIKE_BIN=<yse-spike 路徑> python3 -m unittest test_pumpcheck
未設 YSE_SPIKE_BIN 時以 swift build（scratch 放 $TMPDIR，不放 iCloud 同步的 ~/Documents）取得。"""
import os
import pathlib
import subprocess
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
EXTERNAL = "yse-spike.selftest.external"
POST_JXA = ("ObjC.import('Foundation'); $.NSDistributedNotificationCenter.defaultCenter"
            f".postNotificationNameObjectUserInfoDeliverImmediately('{EXTERNAL}', $(), $(), true)")


def spike_binary():
    if os.environ.get("YSE_SPIKE_BIN"):
        return os.environ["YSE_SPIKE_BIN"]
    scratch = os.path.join(tempfile.gettempdir(), "yse-spike-pumpcheck-build")
    subprocess.run(["swift", "build", "--scratch-path", scratch], cwd=HERE, check=True, capture_output=True)
    path = subprocess.run(["swift", "build", "--scratch-path", scratch, "--show-bin-path"], cwd=HERE,
                          check=True, capture_output=True, text=True).stdout.strip()
    return os.path.join(path, "yse-spike")


class PumpCheckTests(unittest.TestCase):
    def test_every_in_process_check_passes_and_external_notification_arrives(self):
        proc = subprocess.Popen([spike_binary(), "pumpcheck"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True)
        lines = []
        try:
            for line in proc.stdout:
                lines.append(line.rstrip())
                if line.startswith("READY external"):
                    subprocess.run(["/usr/bin/osascript", "-l", "JavaScript", "-e", POST_JXA], check=True,
                                   capture_output=True, timeout=10)
            proc.wait(timeout=30)
        finally:
            if proc.poll() is None:
                proc.kill()
        output = "\n".join(lines)
        self.assertIn("READY external", output)
        for check in ("single-event", "all-queued-events", "idle-deadline", "busy-deadline",
                      "self-notification", "external-notification"):
            self.assertIn(f"ok {check}", output, output)
        self.assertNotIn("FAIL", output)
        self.assertEqual(proc.returncode, 0, output + proc.stderr.read())


if __name__ == "__main__":
    unittest.main()
