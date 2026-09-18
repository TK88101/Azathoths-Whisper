"""H-02 閘門判定：CLI（列印格式化與 argparse 子命令）（拆自 `h02_gate_eval.py`）。

CLI 輸入格式細節見 `h02_gate_eval.py` 頂部 docstring 的輸入格式假設索引。
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional

from h02_gate_model import GateInputError, GateTable
from h02_gate_parse import load_xcresult_json
from h02_gate_r27_profile import ProfileError, R27Profile, load_active_profile
from h02_gate_rules import (
    evaluate_candidate,
    evaluate_negative_control,
    evaluate_v3,
    evaluate_v4,
    verdict,
)
from h02_gate_table import build_table, format_table, table_to_json

_DEFAULT_R27_PROFILE_DIR = str(Path.home() / "Developer" / "bjork-h02-gate" / "fix4" / "r27-profile")


def _print_lines(title: str, lines: List[str], limit: int = 20) -> None:
    if not lines:
        return
    print(f"{title}:")
    for line in lines[:limit]:
        print(f"  - {line}")
    if len(lines) > limit:
        print(f"  … 另 {len(lines) - limit} 條")


def _print_profile_provenance(provenance: Optional[dict]) -> None:
    """把 active R27 profile 的溯源欄位印進報告輸出（v5 §13／§10 R13 配套）。刻意決定：
    只印出，不拿 tree_hash／cdhash 跟受評運行的 tree hash 做相等比對後判無效——見
    `R27Profile.provenance` docstring。"""
    if provenance is None:
        print("active_profile: 無")
        return
    print(
        f"active_profile: version={provenance['version']} tree_hash={provenance['tree_hash']} "
        f"cdhash={provenance['cdhash']} env_fingerprint={provenance['env_fingerprint'] or '未記錄'} "
        f"display={provenance.get('display') or '未記錄'}"
    )


def _print_v3(v3: dict) -> None:
    print("== V3 判定（R4）==")
    print(f"run_valid: {v3['run_valid']}")
    _print_lines("invalid", v3["invalid_reasons"])
    print("per-step:")
    for (t, s), v in v3["per_step"].items():
        extra = f" sig={v['sig_set']}" if "sig_set" in v else ""
        print(f"  - {t}.{s}: {v['status']}{extra}")
    print(f"inconsistent: {v3['inconsistent']}  excluded: {v3['excluded']}  consistency_ok: {v3['consistency_ok']}")
    print(f"frozen_conformity_ok: {v3['frozen_conformity_ok']}")
    _print_lines("R4-F 不相符（→ 不可判定）", v3["frozen_conformity_reasons"])
    _print_lines("frozen_deviations（只記錄，不改結論）", v3["frozen_deviations"])
    print(f"defect3: {v3['defect3']}")
    print(f"defect2_steps: {[(t, s) for t, s, _ in v3['defect2_steps']]}")
    print(f"env_fingerprint: {v3['env_fingerprint']}")
    _print_lines("env_fingerprint 不符／未量測（§10 R13 → 不可判定）", v3["env_fingerprint_reasons"])
    _print_profile_provenance(v3["active_profile_provenance"])


def _print_v5(v5: dict) -> None:
    print("== V5 判定（R4）==")
    print(
        f"ok: {v5['ok']}  T2.s1: {v5['positive_control_ok']}  "
        f"endpoints: {v5['endpoint_steps_ok']}  S2: {v5['s2_verified']}"
    )
    _print_lines("reasons", v5["reasons"])


def _print_v4(v4: dict, name: str = "") -> None:
    print(f"== V4 判定{('（' + name + '）') if name else ''} ==")
    print(f"verdict: {v4['verdict']}")
    _print_lines("invalid", v4["invalid_reasons"])
    _print_lines("KILLED", [f"{t}.{s}: {d}" for t, s, d in v4["killed"]])
    _print_lines("SURVIVED", [f"{t}.{s}: {d}" for t, s, d in v4["survived"]])


def _print_verdict(result: dict) -> None:
    print(f"== 閘門結論（R4-C）：{result['conclusion']} ==")
    _print_lines("理由", result["reasons"])
    _print_v3(result["v3"])
    _print_v5(result["v5"])
    for name, v4 in result["v4"].items():
        _print_v4(v4, name)
    print("（V4 權重由使用者裁決；「不可建」屬 S 階段，不由本命令輸出）")


def _print_candidate(result: dict) -> None:
    """C.1（計劃 `docs/plans/2026-09-13-coverflow-h02-fix4.md` §5.1）候選閘門輸出。"""
    print("== C.1 候選閘門 ==")
    print(f"結論={result['conclusion']}")
    print(f"格數: {result['cell_count']}（{result['iterations']} 次迭代）  run_valid: {result['run_valid']}")
    if result["evidence_ok"] is not None:
        print(f"證據完整: {result['evidence_ok']}")
    _print_lines("理由（無效）", result["invalid_reasons"])
    _print_lines(
        "失敗格 (test, step, iteration, sig_set)",
        [f"{t}.{s} iter {i}: {list(sig)}" for t, s, i, sig in result["failing_cells"]],
        limit=60,
    )
    _print_lines(
        "失敗計數（step, 正規化簽名集合）",
        [f"{step} × {n}: {list(sig)}" for (step, sig), n in sorted(result["failure_counts"].items())],
        limit=60,
    )


def _print_mutant_report(report: dict) -> None:
    print(f"-- {report['name']}（要求殺死步驟：{[f'{t}.{s}' for t, s in report['required_steps']]}）--")
    print(f"kill_ok: {report['kill_ok']}")
    _print_lines("KILLED", [f"{t}.{s}: {d}" for t, s, d in report["killed"]])
    _print_lines("SURVIVED", [f"{t}.{s}: {d}" for t, s, d in report["survived"]])


def _print_negative_control(result: dict) -> None:
    """C.2（§5.2；雙欄偏離見 v5 §13 第 4、5 項；env_fingerprint 見 §10 R13）負對照輸出。
    是否顯示「尚無 active profile」由明確的 `active_profile_present` 布林決定，不再從
    `active_profile_deviation is None` 反推（那欄在 profile 存在但 migration／unkilled 短路時
    仍可能是空陣列，用 `is None` 判斷會印出與事實不符的文案）。"""
    print("== C.2 負對照（M2／M3）==")
    print(f"結論={result['conclusion']}")
    _print_lines("理由", result["reasons"])
    _print_lines("變異運行無效", result["mutant_invalid_reasons"])
    _print_lines("baseline 不合格", result["baseline_reasons"])
    if not result["active_profile_present"]:
        print("active_profile_deviation: 尚無 active profile")
    elif result["active_profile_deviation"]:
        _print_lines("active_profile_deviation（需解釋；參與結論）", result["active_profile_deviation"])
    else:
        print("active_profile_deviation: []（有 active profile，零偏離）")
    _print_lines(
        "historical_R55_deviation（僅報告；R55 唯讀歷史，不參與結論）", result["historical_R55_deviation"]
    )
    print(f"env_fingerprint: {result['env_fingerprint']}")
    _print_profile_provenance(result["active_profile_provenance"])
    _print_lines("候選改動的 CoverFlow 非 Strip 檔", result["product_files"])
    for report in result["mutants"].values():
        _print_mutant_report(report)


# CLI


def _load_text(path: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        raise GateInputError(f"讀取失敗（{path}）：{e}") from e


def _load_product_files(path: Optional[str]) -> Optional[List[str]]:
    """`git diff --name-only` 的輸出檔（每行一個路徑）；未給則回 None。"""
    return None if path is None else _load_text(path).splitlines()


def _add_profile_args(parser: argparse.ArgumentParser) -> None:
    """R27 profile 讀取與 §10 R13 環境指紋——`v3`／`verdict`／`negative-control` 三個子命令共用
    （must_fix：原本只有 `negative-control` 有，`v3`／`verdict` 經 CLI 呼叫時 `active_profile`
    恆為 `None`，甲案的攔阻半邊在 CLI 不可達）。"""
    parser.add_argument(
        "--profile-dir",
        default=None,
        help=(
            "R27 profile 根目錄（讀 <dir>/active/profile.json）。不給＝讀預設路徑 "
            f"{_DEFAULT_R27_PROFILE_DIR}，該處尚未 activate 過則視為無 active profile；"
            "**顯式給了**卻找不到 active/profile.json ＝ 輸入錯誤（exit 2），防打錯路徑靜默降級"
        ),
    )
    parser.add_argument(
        "--run-env-fingerprint",
        default=None,
        help=(
            "本次運行的環境指紋，逗號分隔 key=value（例：os_build=26A428,xcode_build=27A266a,"
            "sdk=macosx27.0）；§10 R13 fail-closed：active profile 已記錄指紋但本參數未給 → "
            "env_fingerprint=unmeasured → 判定無效／不可判定"
        ),
    )


def _build_argparser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="h02_gate_eval.py",
        description="H-02 缺陷 2／3 XCUITest 閘門判定（見本檔頂部 docstring 的輸入格式假設）",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_table = sub.add_parser("table", help="列印 (test, iteration, step) 判定表")
    p_table.add_argument("--log", required=True, help="xcodebuild 日誌檔路徑")
    p_table.add_argument("--xcresult", required=True, help=".xcresult bundle 或預先匯出的 JSON 檔")
    p_table.add_argument("--iterations", type=int, default=None, help="預期的每測試迭代數（可省略）")
    p_table.add_argument("--json", action="store_true")

    p_v3 = sub.add_parser("v3", help="M0 閘門判定：一致性／缺陷3／缺陷2／陽性對照")
    p_v3.add_argument("--log", required=True)
    p_v3.add_argument("--xcresult", required=True)
    p_v3.add_argument("--iterations", type=int, required=True)
    _add_profile_args(p_v3)

    p_v4 = sub.add_parser("v4", help="歷史變異回歸：步驟級差異殺死判定")
    p_v4.add_argument("--baseline-log", required=True)
    p_v4.add_argument("--baseline-xcresult", required=True)
    p_v4.add_argument("--baseline-iterations", type=int, default=10)
    p_v4.add_argument("--log", required=True)
    p_v4.add_argument("--xcresult", required=True)
    p_v4.add_argument("--iterations", type=int, default=3)

    p_verdict = sub.add_parser("verdict", help="R4-C 機械結論：M0 確認性運行＋M2／M3 確認性變異運行")
    for run in ("m0", "m2", "m3"):
        p_verdict.add_argument(f"--{run}-log", required=True)
        p_verdict.add_argument(f"--{run}-xcresult", required=True)
    p_verdict.add_argument("--m0-iterations", type=int, default=10)
    p_verdict.add_argument("--mutant-iterations", type=int, default=3)
    p_verdict.add_argument(
        "--s2-verified", action="store_true", help="斷言 S2 已知點分類命中（計劃 §11 S2 實測）；不給則 V5 不成立"
    )
    _add_profile_args(p_verdict)

    _add_f1_parsers(sub)
    return parser


def _add_f1_parsers(sub) -> None:
    """F1（計劃 `docs/plans/2026-09-13-coverflow-h02-fix4.md` §5.1／§5.2）的兩個子命令。"""
    p_cand = sub.add_parser("candidate", help="C.1 候選閘門：×N 有效且全部格 PASS 才通過")
    p_cand.add_argument("--log", required=True)
    p_cand.add_argument("--xcresult", required=True)
    p_cand.add_argument("--iterations", type=int, default=20)
    p_cand.add_argument("--evidence", default=None, help="證據目錄（§5.7 (7) manifest）；給了就一併判證據完整性")

    p_neg = sub.add_parser("negative-control", help="C.2 負對照：M2／M3 自候選同一 tree 重建 ×3")
    p_neg.add_argument("--baseline-log", required=True)
    p_neg.add_argument("--baseline-xcresult", required=True)
    p_neg.add_argument("--baseline-iterations", type=int, default=20)
    for run in ("m2", "m3"):
        p_neg.add_argument(f"--{run}-log", required=True)
        p_neg.add_argument(f"--{run}-xcresult", required=True)
    p_neg.add_argument("--mutant-iterations", type=int, default=3)
    p_neg.add_argument("--product-files", default=None, help="候選改動的產品源檔清單（殺死點消失分支判定）")
    _add_profile_args(p_neg)


def _load_table(log_path: str, xcresult_path: str, iterations: Optional[int]) -> GateTable:
    return build_table(_load_text(log_path), load_xcresult_json(xcresult_path), expected_iterations=iterations)


def _load_active_profile_arg(profile_dir: Optional[str]) -> Optional[R27Profile]:
    """`--profile-dir` 共用載入邏輯（`v3`／`verdict`／`negative-control` 三個子命令共用）。

    - 未給（`None`）→ 讀 `_DEFAULT_R27_PROFILE_DIR`；尚未 activate ＝ 無 active profile（場 0 的
      cf-m0-27 首跑仰賴此語義：甲案只出 deviations）。
    - **顯式給了**卻沒有 active/profile.json → `GateInputError`（exit 2）。打錯路徑若靜默降級成
      「無 profile」，v3／verdict 的結論會從不可判定翻成通過（第 3 輪覆核實測）。
    `ProfileError` 一律轉譯成 `GateInputError`，由 `main()` 的統一錯誤處理印出、回傳 exit code 2。"""
    explicit = profile_dir is not None
    root = profile_dir if explicit else _DEFAULT_R27_PROFILE_DIR
    try:
        profile = load_active_profile(Path(root))
    except ProfileError as e:
        raise GateInputError(f"R27 profile 讀取失敗（{root}）：{e}") from e
    if profile is None and explicit:
        raise GateInputError(
            f"R27 profile 不存在：顯式指定的 --profile-dir {root} 下沒有 active/profile.json"
            "（不給 --profile-dir 才會以預設路徑缺檔視為「尚無 active profile」）"
        )
    return profile


def _parse_run_env_fingerprint(text: Optional[str]) -> Optional[Dict[str, str]]:
    """`--run-env-fingerprint` 的 `os_build=...,xcode_build=...,sdk=...` 語法解析（§10 R13）。
    未給 → `None`（呼叫端沒量測，交由 `env_fingerprint_check` 依 profile 是否已記錄指紋判斷
    `unknown`／`unmeasured`）。格式錯誤（缺 `=`、鍵或值為空、整串解不出任何鍵值）一律
    `GateInputError`，不得靜默吞掉、生出一份看似合法但是空的指紋。"""
    if text is None:
        return None
    result: Dict[str, str] = {}
    for pair in text.split(","):
        pair = pair.strip()
        if not pair:
            continue
        if "=" not in pair:
            raise GateInputError(f"--run-env-fingerprint 格式錯誤（缺 '='）：{pair!r}")
        key, _, value = pair.partition("=")
        key, value = key.strip(), value.strip()
        if not key or not value:
            raise GateInputError(f"--run-env-fingerprint 格式錯誤（鍵或值為空）：{pair!r}")
        result[key] = value
    if not result:
        raise GateInputError(f"--run-env-fingerprint 未解析出任何鍵值：{text!r}")
    return result


def _run_candidate(args) -> int:
    table = _load_table(args.log, args.xcresult, args.iterations)
    _print_candidate(evaluate_candidate(table, args.iterations, evidence=args.evidence))
    return 0


def _run_v3(args) -> int:
    table = _load_table(args.log, args.xcresult, args.iterations)
    active_profile = _load_active_profile_arg(args.profile_dir)
    run_env_fingerprint = _parse_run_env_fingerprint(args.run_env_fingerprint)
    _print_v3(evaluate_v3(table, args.iterations, active_profile, run_env_fingerprint))
    return 0


def _run_verdict(args) -> int:
    m0 = _load_table(args.m0_log, args.m0_xcresult, args.m0_iterations)
    m2 = _load_table(args.m2_log, args.m2_xcresult, args.mutant_iterations)
    m3 = _load_table(args.m3_log, args.m3_xcresult, args.mutant_iterations)
    active_profile = _load_active_profile_arg(args.profile_dir)
    run_env_fingerprint = _parse_run_env_fingerprint(args.run_env_fingerprint)
    _print_verdict(
        verdict(
            m0,
            m2,
            m3,
            args.s2_verified,
            args.m0_iterations,
            args.mutant_iterations,
            active_profile=active_profile,
            run_env_fingerprint=run_env_fingerprint,
        )
    )
    return 0


def _run_negative_control(args) -> int:
    baseline = _load_table(args.baseline_log, args.baseline_xcresult, args.baseline_iterations)
    m2 = _load_table(args.m2_log, args.m2_xcresult, args.mutant_iterations)
    m3 = _load_table(args.m3_log, args.m3_xcresult, args.mutant_iterations)
    active_profile = _load_active_profile_arg(args.profile_dir)
    run_env_fingerprint = _parse_run_env_fingerprint(args.run_env_fingerprint)
    _print_negative_control(
        evaluate_negative_control(
            baseline,
            m2,
            m3,
            args.baseline_iterations,
            args.mutant_iterations,
            product_files=_load_product_files(args.product_files),
            active_profile=active_profile,
            run_env_fingerprint=run_env_fingerprint,
        )
    )
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = _build_argparser()
    args = parser.parse_args(argv)

    try:
        if args.command == "table":
            log_text = _load_text(args.log)
            xc_json = load_xcresult_json(args.xcresult)
            table = build_table(log_text, xc_json, expected_iterations=args.iterations)
            if args.json:
                print(json.dumps(table_to_json(table), ensure_ascii=False, indent=2))
            else:
                print(format_table(table))
            return 0

        if args.command == "v3":
            return _run_v3(args)

        if args.command == "v4":
            base_table = _load_table(args.baseline_log, args.baseline_xcresult, args.baseline_iterations)
            mut_table = _load_table(args.log, args.xcresult, args.iterations)
            _print_v4(evaluate_v4(base_table, mut_table, args.baseline_iterations, args.iterations))
            return 0

        if args.command == "candidate":
            return _run_candidate(args)

        if args.command == "negative-control":
            return _run_negative_control(args)

        if args.command == "verdict":
            return _run_verdict(args)
    except GateInputError as e:
        print(f"錯誤：{e}", file=sys.stderr)
        return 2

    return 2


if __name__ == "__main__":
    sys.exit(main())
