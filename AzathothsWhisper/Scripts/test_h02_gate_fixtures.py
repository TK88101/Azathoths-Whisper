#!/usr/bin/env python3
"""h02_gate_eval 測試共用夾具（拆自 `test_h02_gate_eval.py`；純資料/產生器，無 TestCase）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_gate*.py'

夾具兩類：
  - testdata/h02/*.log + *.xcresult.json：單一測試、單一迭代的具名情境（真實結構的縮影）。
  - 本檔內的 make_xcresult() / make_log()：多測試／多迭代（V3／V4 用）的合成夾具產生器，
    節點形狀對齊 `xcrun xcresulttool get test-results tests` 實測 schema
    （Test Plan > UI test bundle > Test Suite > Test Case >[Repetition]> Failure Message）。
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, List, Tuple

import h02_gate_eval as gate

TESTDATA = Path(__file__).resolve().parent / "testdata" / "h02"


def load_fixture(name: str) -> Tuple[str, dict]:
    log_text = (TESTDATA / f"{name}.log").read_text(encoding="utf-8")
    xc_json = json.loads((TESTDATA / f"{name}.xcresult.json").read_text(encoding="utf-8"))
    return log_text, xc_json


# ---------------------------------------------------------------------------
# 合成多迭代夾具產生器（V3／V4 用）
# ---------------------------------------------------------------------------

def make_xcresult(test_iterations: Dict[str, List[Tuple[str, List[str]]]]) -> dict:
    """test_iterations: {label: [(result, [failure_text,...]), ...]}
    list 長度 1 → 直接掛在 Test Case 節點；>1 → 以 Repetition 包裹逐個掛。
    """
    test_cases = []
    for label, iters in test_iterations.items():
        method = gate.TEST_LABELS[label]
        node: dict = {
            "nodeType": "Test Case",
            "name": f"{method}()",
            "nodeIdentifier": f"CoverFlowUITests/{method}()",
        }
        if len(iters) == 1:
            result, texts = iters[0]
            node["result"] = result
            node["children"] = [
                {"nodeType": "Failure Message", "name": f"CoverFlowUITests.swift:1: failed - {t}"}
                for t in texts
            ]
        else:
            node["result"] = "Failed" if any(r == "Failed" for r, _ in iters) else "Passed"
            reps = []
            for idx, (result, texts) in enumerate(iters, start=1):
                reps.append(
                    {
                        "nodeType": "Repetition",
                        "name": f"Iteration {idx}",
                        "result": result,
                        "children": [
                            {
                                "nodeType": "Failure Message",
                                "name": f"CoverFlowUITests.swift:1: failed - {t}",
                            }
                            for t in texts
                        ],
                    }
                )
            node["children"] = reps
        test_cases.append(node)
    return {
        "devices": [],
        "testPlanConfigurations": [],
        "testNodes": [
            {
                "nodeType": "Test Plan",
                "name": "AzathothsWhisper",
                "result": "unknown",
                "children": [
                    {
                        "nodeType": "UI test bundle",
                        "name": "AzathothsWhisperUITests",
                        "result": "unknown",
                        "children": [
                            {
                                "nodeType": "Test Suite",
                                "name": "CoverFlowUITests",
                                "result": "unknown",
                                "children": test_cases,
                            }
                        ],
                    }
                ],
            }
        ],
    }


def make_log(test_gate_lines: Dict[str, List[List[str]]]) -> str:
    """test_gate_lines: {label: [[gate_line_str, ...], ...]}（外層＝迭代序）。"""
    lines = []
    for label, iters in test_gate_lines.items():
        method = gate.TEST_LABELS[label]
        for gate_lines in iters:
            lines.append(
                f"Test Case '-[AzathothsWhisperUITests.CoverFlowUITests {method}]' started."
            )
            failed = any("FAIL" in g for g in gate_lines)
            lines.extend(gate_lines)
            verb = "failed" if failed else "passed"
            lines.append(
                f"Test Case '-[AzathothsWhisperUITests.CoverFlowUITests {method}]' {verb} (1.0 seconds)."
            )
    return "\n".join(lines) + "\n"


def all_pass_grid(overrides: Dict[str, List[List[str]]] = None, n: int = 10) -> Dict[str, List[List[str]]]:
    """每個測試每個步驟都 PASS，n 次迭代；overrides 可覆蓋個別測試的 GATE 行序列。"""
    grid: Dict[str, List[List[str]]] = {}
    for label, steps in gate.STEPS.items():
        pass_lines = [f"GATE{{{label}.{s}|PASS}}" for s in steps]
        grid[label] = [list(pass_lines) for _ in range(n)]
    if overrides:
        grid.update(overrides)
    return grid


def xcresult_for_grid(grid: Dict[str, List[List[str]]], failure_texts: Dict[Tuple[str, int, str], List[str]] = None) -> dict:
    """依 GATE grid 反推 xcresult：GATE PASS→該次迭代 Passed 無失敗；GATE FAIL 步驟需呼叫方
    以 failure_texts[(label, iter_idx_1based, step)] 提供對應 SIG/PROBE 文字。"""
    failure_texts = failure_texts or {}
    test_iterations: Dict[str, List[Tuple[str, List[str]]]] = {}
    for label, iters in grid.items():
        entries = []
        for i, gate_lines in enumerate(iters, start=1):
            texts: List[str] = []
            failed = False
            for line in gate_lines:
                parsed = gate.parse_gate_token(line)
                if parsed.status == "FAIL":
                    failed = True
                    texts.extend(failure_texts.get((label, i, parsed.step), []))
            entries.append(("Failed" if failed else "Passed", texts))
        test_iterations[label] = entries
    return make_xcresult(test_iterations)


# ---------------------------------------------------------------------------
# R4 修訂（計劃 §6 R4-X／R4-C、§3.12 table_valid）：以凍結預登記表構造「類 M0」運行
# ---------------------------------------------------------------------------

C2 = {
    ("T1", "s2"): "SIG{T1.s2|C2-STACK|G=T13|over=T12|side=L}",
    ("T1", "s3"): "SIG{T1.s3|C2-STACK|G=T11|over=T12|side=R}",
    ("T2", "s2"): "SIG{T2.s2|C2-STACK|G=T00|over=T01|side=R}",
    ("T2", "s3"): "SIG{T2.s3|C2-STACK|G=T19|over=T18|side=L}",
    ("T4", "s1"): "SIG{T4.s1|C2-STACK|G=T19|over=T18|side=L}",
}
T4S2_OFFSET = "SIG{T4.s2|C1-OFFSET|label=T19|centered=T16|strides=+3}"
T4S2_STACK = "SIG{T4.s2|C2-STACK|G=T16|over=T17|side=R}"

# 凍結預登記表（§11 T7）：None＝PASS；list＝FAIL 時的 SIG 訊息
FROZEN_M0 = {
    ("T1", "s1"): None, ("T1", "s2"): [C2[("T1", "s2")]], ("T1", "s3"): [C2[("T1", "s3")]],
    ("T2", "s1"): None, ("T2", "s2"): [C2[("T2", "s2")]], ("T2", "s3"): [C2[("T2", "s3")]],
    ("T3", "s1"): None,
    ("T4", "s1"): [C2[("T4", "s1")]], ("T4", "s2"): [T4S2_OFFSET, T4S2_STACK],
}
MISSING = "MISSING"


def m0_grid(n=10, overrides=None, drop_tests=(), base=None):
    """overrides[(label, step)]＝固定結果或 `f(iteration_1based) -> 結果`；結果為 None（PASS）、SIG 清單（FAIL）或 MISSING（不輸出 GATE）。
    GATE 行的碼清單**去重**，與 Swift 產出端（`CoverFlowGateLogic.gateLine`）一致。"""
    overrides = overrides or {}
    base = base or FROZEN_M0
    grid: Dict[str, List[List[str]]] = {}
    failure_texts: Dict[Tuple[str, int, str], List[str]] = {}
    for label, steps in gate.STEPS.items():
        if label in drop_tests:
            continue
        iters = []
        for i in range(1, n + 1):
            lines = []
            for s in steps:
                outcome = overrides.get((label, s), base[(label, s)])
                if callable(outcome):
                    outcome = outcome(i)
                if outcome == MISSING:
                    continue
                if outcome is None:
                    lines.append(f"GATE{{{label}.{s}|PASS}}")
                    continue
                codes = ",".join(dict.fromkeys(sig.split("|")[1] for sig in outcome))
                lines.append(f"GATE{{{label}.{s}|FAIL|{codes}}}")
                failure_texts[(label, i, s)] = list(outcome)
            iters.append(lines)
        grid[label] = iters
    return grid, failure_texts


def m0_run(n=10, overrides=None, drop_tests=(), xc_mutator=None, base=None, log_mutator=None):
    grid, failure_texts = m0_grid(n, overrides, drop_tests, base)
    xc_json = xcresult_for_grid(grid, failure_texts)
    if xc_mutator:
        xc_mutator(xc_json)
    log_text = make_log(grid)
    if log_mutator:
        log_text = log_mutator(log_text)
    return gate.build_table(log_text, xc_json, expected_iterations=n)


def pass_at(*iterations):
    """指定迭代 PASS，其餘沿用凍結表的 FAIL 簽名（呼叫端以 lambda 綁定步驟）。"""
    return lambda sigs: (lambda i: None if i in iterations else sigs)


def repetitions_of(xc_json, method):
    found = []

    def walk(node):
        if node.get("nodeType") == "Test Case" and node.get("name") == f"{method}()":
            found.extend(c for c in node.get("children", []) if c.get("nodeType") == "Repetition")
        for c in node.get("children", []):
            walk(c)

    for n in xc_json["testNodes"]:
        walk(n)
    return found


# 變異：M0 上全綠的非端點步驟 T1.s1／T2.s1 被舊 Strip 打紅（實測形態）
MUTANT_KILLED = {
    ("T1", "s1"): ["SIG{T1.s1|C2-STACK|G=T11|over=T10|side=L}"],
    ("T2", "s1"): ["SIG{T2.s1|C2-STACK|G=T11|over=T10|side=L}"],
}
