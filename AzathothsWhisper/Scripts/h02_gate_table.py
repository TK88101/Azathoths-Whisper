"""H-02 閘門判定：(test, iteration, step) 判定表建構與格式化輸出（拆自 `h02_gate_eval.py`）。

輸入格式假設 6（Plan `docs/plans/2026-09-11-coverflow-h02-uitest-gate.md` §3.12）：
  `[PROBE-X]`／「無標籤」（UNTAGGED，非 `SIG{`/`[PROBE-` 開頭）失敗訊息若沒被任何步驟的 GATE 行引用到，
  記為該次迭代「未歸屬」（`IterationInfo.unattributed`），不猜測歸屬到哪個步驟——只要迭代內出現任一
  PROBE 或 UNTAGGED，整次迭代記 invalid（不論是否歸屬到步驟）。

  GATE 的 FAIL 碼清單與 SIG／PROBE 訊息不一致（碼集合對不上、或找不到對應訊息）記為 `errors`
  （不中止解析，交由人工核對）。

完整的輸入格式假設清單見 `h02_gate_eval.py` 頂部 docstring 的索引。
"""
from __future__ import annotations

from typing import Dict, List, Optional, Tuple

from h02_gate_model import (
    Cell,
    FailureEntry,
    GateLine,
    GateTable,
    IterationInfo,
    PRODUCT_CODES,
    STEPS,
    TEST_LABELS,
)
from h02_gate_parse import _classify_gate_token, parse_log, parse_xcresult


def _index_gate_lines(
    label: str, iteration_no: int, steps: List[str], gate_lines: List[GateLine], errors: List[str]
) -> Dict[str, GateLine]:
    gate_by_step: Dict[str, GateLine] = {}
    for g in gate_lines:
        # 前綴必須是本測試：`GATE{T2.s1|…}` 印在 T1 的迭代裡不得頂替 T1.s1（否則 MISSING 被掩蓋）
        if g.test != label:
            errors.append(f"{label} iter {iteration_no}: GATE 前綴 {g.test or '（缺）'!r}.{g.step} 不屬於本測試")
            continue
        if g.step not in steps:
            errors.append(f"{label} iter {iteration_no}: GATE 引用未知步驟 {g.step!r}")
            continue
        if g.step in gate_by_step:
            errors.append(f"{label} iter {iteration_no}: 步驟 {g.step} 出現多於一行 GATE")
        if g.status == "FAIL" and not g.codes:
            errors.append(f"{label} iter {iteration_no}: 步驟 {g.step} 的 GATE 為 FAIL 但未列任何碼")
        gate_by_step[g.step] = g
    return gate_by_step


def _index_failures(
    label: str, iteration_no: int, steps: List[str], failures: List[FailureEntry], errors: List[str]
) -> Tuple[Dict[str, List[FailureEntry]], List[FailureEntry], List[FailureEntry]]:
    sig_by_step: Dict[str, List[FailureEntry]] = {}
    probe_failures: List[FailureEntry] = []
    untagged_failures: List[FailureEntry] = []
    for f in failures:
        if f.kind == "SIG":
            # 與 GATE 同一條規矩：`<test>.` 前綴必須是本測試，否則不得充當本步驟的證據
            if f.test != label:
                errors.append(
                    f"{label} iter {iteration_no}: SIG 前綴 {f.test or '（缺）'}.{f.step} 不屬於本測試（{f.raw!r}）"
                )
                continue
            if f.step not in steps:
                errors.append(f"{label} iter {iteration_no}: SIG 引用未知步驟 {f.step!r}（{f.raw!r}）")
                continue
            sig_by_step.setdefault(f.step, []).append(f)
        elif f.kind == "PROBE":
            probe_failures.append(f)
        else:
            untagged_failures.append(f)

    for sigs in sig_by_step.values():
        for f in sigs:
            if f.code not in PRODUCT_CODES:
                errors.append(f"{label} iter {iteration_no}: SIG 使用非產品碼 {f.code!r}（{f.raw!r}）")

    return sig_by_step, probe_failures, untagged_failures


def _classify_fail_tokens(
    label: str, iteration_no: int, step: str, gate: GateLine, sigs: List[FailureEntry], errors: List[str]
) -> Tuple[List[str], List[str]]:
    product_tokens: List[str] = []
    probe_tokens: List[str] = []
    for tok in gate.codes:
        kind, val = _classify_gate_token(tok)
        if kind == "product":
            product_tokens.append(val)
        elif kind == "probe":
            probe_tokens.append(val)
        else:
            errors.append(f"{label} iter {iteration_no} {step}: GATE 出現無法辨識的碼 {tok!r}")

    # 比的是**碼集合**（假設 2／7）：產出端 GATE 碼去重，同一步驟可有多條同碼 SIG（例如兩側都 C2-STACK）
    sig_codes = {f.code for f in sigs if f.code is not None}
    if set(product_tokens) != sig_codes:
        errors.append(
            f"{label} iter {iteration_no} {step}: GATE 產品碼 {sorted(set(product_tokens))} "
            f"與 SIG 碼 {sorted(sig_codes)} 不一致"
        )
    return product_tokens, probe_tokens


def _build_cell_for_step(
    label: str,
    iteration_no: int,
    step: str,
    gate: Optional[GateLine],
    sigs: List[FailureEntry],
    probe_failures: List[FailureEntry],
    claimed_probe_ids: set,
    errors: List[str],
) -> Tuple[Cell, Optional[str]]:
    """回傳 (本步驟的 Cell, invalid_reason 或 None)。"""
    if gate is None:
        if sigs:
            errors.append(f"{label} iter {iteration_no} {step}: 有 SIG 訊息但缺對應 GATE 行")
            return Cell(kind="FAIL", sig_set=frozenset(f.sig_key for f in sigs if f.sig_key)), None
        return Cell(kind="MISSING"), None

    if gate.status == "PASS":
        if sigs:
            errors.append(f"{label} iter {iteration_no} {step}: GATE PASS 但存在 SIG 訊息")
        return Cell(kind="PASS"), None

    # FAIL：拆解 token 為產品碼 / 探針 token / 未知
    product_tokens, probe_tokens = _classify_fail_tokens(label, iteration_no, step, gate, sigs, errors)

    for tok in probe_tokens:
        probe_name = tok[len("PROBE-") :]
        match = next(
            (f for f in probe_failures if f.probe_name == probe_name and id(f) not in claimed_probe_ids),
            None,
        )
        if match is None:
            errors.append(
                f"{label} iter {iteration_no} {step}: GATE 引用 {tok} 但找不到對應 "
                f"[PROBE-{probe_name}] 失敗訊息"
            )
        else:
            claimed_probe_ids.add(id(match))

    if probe_tokens:
        cell = Cell(
            kind="PROBE",
            sig_set=frozenset(f.sig_key for f in sigs if f.sig_key),
            probe_names=tuple(probe_tokens),
        )
        return cell, f"{step}: {','.join(probe_tokens)}"

    sig_set = frozenset(f.sig_key for f in sigs if f.sig_key) if sigs else frozenset(product_tokens)
    return Cell(kind="FAIL", sig_set=sig_set), None


def _collect_unattributed(
    probe_failures: List[FailureEntry], claimed_probe_ids: set, untagged_failures: List[FailureEntry]
) -> Tuple[List[FailureEntry], List[str]]:
    unattributed: List[FailureEntry] = []
    reasons: List[str] = []
    for f in probe_failures:
        if id(f) not in claimed_probe_ids:
            reasons.append(f"未歸屬的 [PROBE-{f.probe_name}]")
            unattributed.append(f)
    for f in untagged_failures:
        reasons.append("UNTAGGED: " + f.raw[:120])
        unattributed.append(f)
    return unattributed, reasons


def _build_iteration(
    label: str,
    iteration_no: int,
    steps: List[str],
    xc_result: Optional[str],
    failures: List[FailureEntry],
    gate_lines: List[GateLine],
    errors: List[str],
) -> IterationInfo:
    cells: Dict[str, Cell] = {s: Cell(kind="MISSING") for s in steps}

    gate_by_step = _index_gate_lines(label, iteration_no, steps, gate_lines, errors)
    sig_by_step, probe_failures, untagged_failures = _index_failures(label, iteration_no, steps, failures, errors)

    claimed_probe_ids: set = set()
    invalid_reasons: List[str] = []

    for step in steps:
        gate = gate_by_step.get(step)
        sigs = sig_by_step.get(step, [])
        cell, reason = _build_cell_for_step(
            label, iteration_no, step, gate, sigs, probe_failures, claimed_probe_ids, errors
        )
        cells[step] = cell
        if reason is not None:
            invalid_reasons.append(reason)

    unattributed, extra_reasons = _collect_unattributed(probe_failures, claimed_probe_ids, untagged_failures)
    invalid_reasons.extend(extra_reasons)

    if xc_result == "Failed" and not failures:
        invalid_reasons.append("測試判為 Failed 但未記錄任何失敗訊息")

    return IterationInfo(
        test=label,
        iteration=iteration_no,
        xc_result=xc_result,
        invalid_reasons=invalid_reasons,
        cells=cells,
        unattributed=tuple(unattributed),
    )


def build_table(
    log_text: str,
    xc_json: dict,
    expected_iterations: Optional[int] = None,
    test_labels: Optional[Dict[str, str]] = None,
) -> GateTable:
    test_labels = test_labels or TEST_LABELS
    log_data, orphan_gate_lines, closed_counts = parse_log(log_text, test_labels)
    xc_data = parse_xcresult(xc_json, test_labels)

    errors: List[str] = [f"GATE 行出現在任何測試案例範圍之外：{l}" for l in orphan_gate_lines]
    iteration_count_mismatch: Dict[str, Tuple[int, int]] = {}
    iterations_by_test: Dict[str, List[IterationInfo]] = {}

    present_tests = [t for t in test_labels if t in xc_data or log_data.get(t)]
    for label in present_tests:
        steps = STEPS[label]
        xc_iters = xc_data.get(label, [])
        log_iters = log_data.get(label, [])
        n_xc = len(xc_iters)
        n_log = len(log_iters)
        n_closed = closed_counts.get(label, 0)
        if n_log != n_closed:
            errors.append(
                f"{label}: 日誌 started（{n_log}）與成對收尾（{n_closed}）不符——運行可能被截斷或行序錯亂"
            )
        if n_xc != n_log:
            errors.append(
                f"{label}: xcresult 迭代數（{n_xc}）與日誌 started 數（{n_log}）不一致"
            )
        actual_n = max(n_xc, n_log)
        if expected_iterations is not None and actual_n != expected_iterations:
            iteration_count_mismatch[label] = (expected_iterations, actual_n)

        infos: List[IterationInfo] = []
        for i in range(actual_n):
            iteration_no = i + 1
            if i < n_xc:
                xc_result, failures = xc_iters[i]
            else:
                xc_result, failures = None, []
            gate_lines = log_iters[i] if i < n_log else []
            info = _build_iteration(label, iteration_no, steps, xc_result, failures, gate_lines, errors)
            infos.append(info)
        iterations_by_test[label] = infos

    return GateTable(
        tests=present_tests,
        iterations=iterations_by_test,
        errors=errors,
        iteration_count_mismatch=iteration_count_mismatch,
    )


# 輸出格式化


def _cell_repr(cell: Cell) -> str:
    if cell.kind == "PASS":
        return "PASS"
    if cell.kind == "FAIL":
        return "FAIL " + str(sorted(cell.sig_set))
    if cell.kind == "PROBE":
        return "PROBE " + str(cell.probe_names)
    if cell.kind == "UNTAGGED":
        return "UNTAGGED"
    return "MISSING"


def format_table(table: GateTable) -> str:
    lines: List[str] = []
    for label in table.tests:
        lines.append(f"== {label} ({TEST_LABELS[label]}) ==")
        for info in table.iterations[label]:
            tag = ""
            if info.invalid:
                tag = " [INVALID: " + "; ".join(info.invalid_reasons) + "]"
            lines.append(f"  iter {info.iteration} (xcresult={info.xc_result}){tag}")
            for step in STEPS[label]:
                lines.append(f"    {step}: {_cell_repr(info.cells[step])}")
        if label in table.iteration_count_mismatch:
            exp, act = table.iteration_count_mismatch[label]
            lines.append(f"  !! 迭代數不符：預期 {exp}，實得 {act}")
    if table.errors:
        lines.append("== errors ==")
        for e in table.errors:
            lines.append(f"  - {e}")
    return "\n".join(lines)


def _cell_to_json(cell: Cell) -> dict:
    return {"kind": cell.kind, "sig_set": sorted(cell.sig_set), "probe_names": list(cell.probe_names)}


def _iteration_to_json(info: IterationInfo, steps: List[str]) -> dict:
    return {
        "iteration": info.iteration,
        "xc_result": info.xc_result,
        "invalid": info.invalid,
        "invalid_reasons": info.invalid_reasons,
        "cells": {step: _cell_to_json(info.cells[step]) for step in steps},
    }


def table_to_json(table: GateTable) -> dict:
    return {
        "tests": {
            label: [_iteration_to_json(info, STEPS[label]) for info in table.iterations[label]]
            for label in table.tests
        },
        "errors": list(table.errors),
        "iteration_count_mismatch": {
            label: {"expected": exp, "actual": act}
            for label, (exp, act) in table.iteration_count_mismatch.items()
        },
    }
