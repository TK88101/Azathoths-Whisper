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
from h02_gate_rules import (
    evaluate_candidate,
    evaluate_negative_control,
    evaluate_v3,
    evaluate_v4,
    verdict,
)
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
    """C.2（§5.2）負對照輸出。"""
    print("== C.2 負對照（M2／M3）==")
    print(f"結論={result['conclusion']}")
    _print_lines("理由", result["reasons"])
    _print_lines("變異運行無效", result["mutant_invalid_reasons"])
    _print_lines("baseline 不合格", result["baseline_reasons"])
    _print_lines("簽名偏離（需解釋）", result["deviations"])
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


def _load_table(log_path: str, xcresult_path: str, iterations: Optional[int]) -> GateTable:
    return build_table(_load_text(log_path), load_xcresult_json(xcresult_path), expected_iterations=iterations)


def _run_candidate(args) -> int:
    table = _load_table(args.log, args.xcresult, args.iterations)
    _print_candidate(evaluate_candidate(table, args.iterations, evidence=args.evidence))
    return 0


def _run_negative_control(args) -> int:
    baseline = _load_table(args.baseline_log, args.baseline_xcresult, args.baseline_iterations)
    m2 = _load_table(args.m2_log, args.m2_xcresult, args.mutant_iterations)
    m3 = _load_table(args.m3_log, args.m3_xcresult, args.mutant_iterations)
    _print_negative_control(
        evaluate_negative_control(
            baseline,
            m2,
            m3,
            args.baseline_iterations,
            args.mutant_iterations,
            product_files=_load_product_files(args.product_files),
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
            table = _load_table(args.log, args.xcresult, args.iterations)
            _print_v3(evaluate_v3(table, args.iterations))
            return 0

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
