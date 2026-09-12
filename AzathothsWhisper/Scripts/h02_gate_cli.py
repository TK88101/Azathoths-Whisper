"""H-02 閘門判定：CLI（列印格式化與 argparse 子命令）（拆自 `h02_gate_eval.py`）。

CLI 輸入格式細節見 `h02_gate_eval.py` 頂部 docstring 的輸入格式假設索引。
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import List, Optional

from h02_gate_model import GateInputError, GateTable
from h02_gate_parse import load_xcresult_json
from h02_gate_rules import evaluate_v3, evaluate_v4, verdict
from h02_gate_table import build_table, format_table, table_to_json


def _print_lines(title: str, lines: List[str], limit: int = 20) -> None:
    if not lines:
        return
    print(f"{title}:")
    for line in lines[:limit]:
        print(f"  - {line}")
    if len(lines) > limit:
        print(f"  … 另 {len(lines) - limit} 條")


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


# CLI


def _load_text(path: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        raise GateInputError(f"讀取失敗（{path}）：{e}") from e


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

    return parser


def _load_table(log_path: str, xcresult_path: str, iterations: Optional[int]) -> GateTable:
    return build_table(_load_text(log_path), load_xcresult_json(xcresult_path), expected_iterations=iterations)


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
            table = _load_table(args.log, args.xcresult, args.iterations)
            _print_v3(evaluate_v3(table, args.iterations))
            return 0

        if args.command == "v4":
            base_table = _load_table(args.baseline_log, args.baseline_xcresult, args.baseline_iterations)
            mut_table = _load_table(args.log, args.xcresult, args.iterations)
            _print_v4(evaluate_v4(base_table, mut_table, args.baseline_iterations, args.iterations))
            return 0

        if args.command == "verdict":
            m0 = _load_table(args.m0_log, args.m0_xcresult, args.m0_iterations)
            m2 = _load_table(args.m2_log, args.m2_xcresult, args.mutant_iterations)
            m3 = _load_table(args.m3_log, args.m3_xcresult, args.mutant_iterations)
            _print_verdict(verdict(m0, m2, m3, args.s2_verified, args.m0_iterations, args.mutant_iterations))
            return 0
    except GateInputError as e:
        print(f"錯誤：{e}", file=sys.stderr)
        return 2

    return 2


if __name__ == "__main__":
    sys.exit(main())
