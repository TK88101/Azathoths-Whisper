"""覆蓋率閘門（N-09；sprint-1-detail.md §4.7）：EchoKit 三模組各自、iPad app 的 Features＋Services 合計，行覆蓋 ≥ 80%。

用法（在 YogSothothsEcho/ 下）：
  python3 -I Scripts/echo_coverage.py --echokit              跑 EchoKit 的 swift test 並判定
  python3 -I Scripts/echo_coverage.py --app <xcresult>       判定 iPad app（xcodebuild test 產生的 xcresult）
不過門檻或缺模組 → stderr 列出、退出 1。
"""
import json
import pathlib
import subprocess
import sys
import tempfile

THRESHOLD = 0.80
MODULES = ("RemoteProtocol", "RemoteTransport", "MusicRemoteBridge")
APP_MEASURED = ("Features/", "Services/")
# 不計入的檔案：理由寫在這裡（排除清單只許加、要附理由）
APP_EXCLUDED: dict[str, str] = {}
# 有原始碼但沒有任何可執行行、經核實可放行的 EchoKit 模組（只許加、要附理由）；未列者 0 行＝判失敗（防匯出漏模組的假綠）
DECLARATION_ONLY: dict[str, str] = {}


def ratio(covered, total):
    return covered / total if total else 0.0


def module_totals(report, root):
    prefix = f"{root}/Packages/EchoKit/Sources/"
    totals = {m: [0, 0] for m in MODULES}
    for file in report["data"][0]["files"]:
        name = file["filename"]
        if not name.startswith(prefix):
            continue
        module = name[len(prefix):].split("/", 1)[0]
        if module in totals:
            lines = file["summary"]["lines"]
            totals[module][0] += lines["covered"]
            totals[module][1] += lines["count"]
    return totals


def judge_echokit(report, root, with_sources):
    """with_sources＝Sources/ 下確實有 .swift 的模組；沒有原始碼才算缺模組"""
    failures = []
    for module, (covered, total) in module_totals(report, root).items():
        if module not in with_sources:
            failures.append(f"EchoKit {module}：Sources 下沒有原始碼")
        elif total == 0:
            if module not in DECLARATION_ONLY:
                failures.append(f"EchoKit {module}：有原始碼但報表 0 行（匯出漏了測試 binary？）")
        elif ratio(covered, total) < THRESHOLD:
            failures.append(f"EchoKit {module}：{ratio(covered, total):.1%}（{covered}/{total}）< 80%")
    return failures


def judge_app(report, root):
    covered = total = 0
    for target in report.get("targets", []):
        for file in target.get("files", []):
            rel = file["path"][len(root) + 1:] if file["path"].startswith(root + "/") else ""
            if rel.startswith(APP_MEASURED) and rel not in APP_EXCLUDED:
                covered += file["coveredLines"]
                total += file["executableLines"]
    if total == 0:
        return ["iPad app：Features／Services 沒有可量測的檔案"]
    if ratio(covered, total) < THRESHOLD:
        return [f"iPad app Features＋Services：{ratio(covered, total):.1%}（{covered}/{total}）< 80%"]
    return []


def expected_test_targets(package):
    """Tests/ 下每個目錄就是一個 test target（Package.swift 慣例）"""
    return sorted(d.name for d in (package / "Tests").iterdir() if d.is_dir())


def test_binaries(products, expected):
    """每個 test target 各自一個 xctest bundle；缺任何一個就判失敗（不能只量到一部分）"""
    binaries, failures = [], []
    for name in expected:
        exe = products / f"{name}.xctest" / "Contents" / "MacOS" / name
        if exe.is_file():
            binaries.append(exe)
        else:
            failures.append(f"EchoKit {name}：找不到測試 binary（{exe}）")
    return binaries, failures


def export_command(profdata, binaries):
    command = ["xcrun", "llvm-cov", "export", "-summary-only", "-instr-profile", str(profdata), str(binaries[0])]
    for binary in binaries[1:]:
        command += ["-object", str(binary)]
    return command


def run_echokit(root):
    """`swift test --show-codecov-path` 的 JSON 只匯出一個測試 binary（實測只含 MusicRemoteBridgeTests 的連結範圍），
    RemoteTransport 因而整個缺席、被誤判為「只有宣告」。故自己以 llvm-cov 合併全部測試 binary 再判定。"""
    package = root / "Packages" / "EchoKit"
    with tempfile.TemporaryDirectory() as scratch:
        subprocess.run(["swift", "test", "--enable-code-coverage", "--scratch-path", scratch], cwd=package, check=True,
                       stdout=subprocess.DEVNULL)
        codecov = pathlib.Path(subprocess.run(["swift", "test", "--show-codecov-path", "--scratch-path", scratch],
                                              cwd=package, check=True, capture_output=True, text=True).stdout.strip())
        products = pathlib.Path(subprocess.run(["swift", "build", "--show-bin-path", "--scratch-path", scratch],
                                               cwd=package, check=True, capture_output=True, text=True).stdout.strip())
        binaries, failures = test_binaries(products, expected_test_targets(package))
        if failures:
            return failures
        report = json.loads(subprocess.run(export_command(codecov.parent / "default.profdata", binaries), check=True,
                                           capture_output=True, text=True).stdout)
    sources = root / "Packages" / "EchoKit" / "Sources"
    with_sources = {m for m in MODULES if any((sources / m).glob("**/*.swift"))}
    resolved = str(root.resolve())
    for module, (covered, total) in module_totals(report, resolved).items():
        print(f"EchoKit {module}：{ratio(covered, total):.1%}（{covered}/{total}）")
    return judge_echokit(report, resolved, with_sources)


def main(argv):
    root = pathlib.Path(__file__).resolve().parent.parent
    if argv[:1] == ["--echokit"]:
        failures = run_echokit(root)
    elif argv[:1] == ["--app"] and len(argv) == 2:
        report = json.loads(subprocess.run(["xcrun", "xccov", "view", "--report", "--json", argv[1]], check=True,
                                           capture_output=True, text=True).stdout)
        failures = judge_app(report, str(root.resolve()))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    for line in failures:
        print(line, file=sys.stderr)
    print("coverage: " + ("FAIL" if failures else "OK"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
