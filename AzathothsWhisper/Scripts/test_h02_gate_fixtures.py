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

import hashlib
import json
from pathlib import Path
from typing import Dict, List, Tuple

import h02_gate_eval as gate
import h02_gate_r27_profile as r27profile

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


def _gate_code(sig):
    """由失敗訊息反推 GATE 行的碼 token：`SIG{T1.s2|C2-STACK|…}` → `C2-STACK`；
    `[PROBE-AX] …` → `PROBE-AX`（探針 token 與產品碼在 GATE 行同一位置，見 `h02_gate_parse`）。"""
    if sig.startswith("[PROBE-"):
        return sig[1 : sig.index("]")]
    return sig.split("|")[1]


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
                codes = ",".join(dict.fromkeys(_gate_code(sig) for sig in outcome))
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


# ---------------------------------------------------------------------------
# F1（計劃 `docs/plans/2026-09-13-coverflow-h02-fix4.md` §5.1／§5.2／§5.7 (7)）：
# 候選閘門／負對照／證據包夾具
# ---------------------------------------------------------------------------

ALL_PASS_BASE = {(label, s): None for label, steps in gate.STEPS.items() for s in steps}

# R5-5 確認性殺死簽名（計劃 §2 事實基線）：M2 於 T1.s1／T2.s1；M3 另加 T3.s1
M2_KILL = dict(MUTANT_KILLED)
M3_KILL = {**MUTANT_KILLED, ("T3", "s1"): ["SIG{T3.s1|C2-STACK|G=T10|over=T09|side=L}"]}

PROBE_T1S1 = "[PROBE-CONTRACT] 契約報告不可讀"
UNTAGGED_T1S1 = "XCTAssertTrue failed"

EVIDENCE_TESTS = tuple(gate.TEST_LABELS)
EVIDENCE_TREE_HASH = "9f" * 20
EVIDENCE_CDHASH = "3c" * 20


def run_inputs(n=20, overrides=None, drop_tests=(), base=None):
    """回傳 (log_text, xcresult_json)——CLI 測試需要的是檔案內容而非已建好的 GateTable。"""
    grid, failure_texts = m0_grid(n, overrides, drop_tests, base or ALL_PASS_BASE)
    return make_log(grid), xcresult_for_grid(grid, failure_texts)


def candidate_run(n=20, overrides=None, drop_tests=(), xc_mutator=None, log_mutator=None):
    """候選／變異運行：以「全 PASS」為底（不是 M0 凍結表），overrides 注入個別失敗格。"""
    return m0_run(
        n=n,
        overrides=overrides,
        drop_tests=drop_tests,
        xc_mutator=xc_mutator,
        base=ALL_PASS_BASE,
        log_mutator=log_mutator,
    )


def write_run(directory, name, n=20, overrides=None, drop_tests=(), base=None):
    """把一份合成運行寫成 `<name>.log` ＋ `<name>.xcresult.json`，回傳 (log_path, xcresult_path)。"""
    log_text, xc_json = run_inputs(n, overrides, drop_tests, base)
    log_path = Path(directory) / f"{name}.log"
    xc_path = Path(directory) / f"{name}.xcresult.json"
    log_path.write_text(log_text, encoding="utf-8")
    xc_path.write_text(json.dumps(xc_json, ensure_ascii=False), encoding="utf-8")
    return str(log_path), str(xc_path)


def _write_evidence_file(root, name, body):
    (root / name).write_text(body, encoding="utf-8")
    return {"path": name, "md5": hashlib.md5(body.encode("utf-8")).hexdigest()}


def write_evidence(root, iterations, tests=EVIDENCE_TESTS, with_sampler=False, transform=None):
    """產生 §5.7 (7) 的證據目錄：每個 test／iteration 一份 trace＋marks（可選 sampler）與 manifest。

    `transform(manifest) -> manifest | None`：回傳新 manifest（不就地改）以構造欄位錯誤；
    回傳 None 則不寫該份 manifest（構造缺份數／不連號）。
    """
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    for test in tests:
        for ordinal in range(1, iterations + 1):
            stem = f"{test}-{ordinal}"
            files = {
                "trace": _write_evidence_file(root, f"{stem}.trace", f"epoch-us=1000\n{stem}\n"),
                "marks": _write_evidence_file(root, f"{stem}.marks", f"step-begin|{stem}\n"),
                "sampler": (
                    _write_evidence_file(root, f"{stem}.sampler", f"frame|{stem}\n") if with_sampler else None
                ),
            }
            manifest = {
                "schema": 1,
                "test": test,
                "ordinal": ordinal,
                "tree_hash": EVIDENCE_TREE_HASH,
                "cdhash": EVIDENCE_CDHASH,
                "files": files,
            }
            if transform is not None:
                manifest = transform(manifest)
            if manifest is not None:
                (root / f"{stem}.manifest.json").write_text(
                    json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
                )
    return Path(root)


def at_manifest(test, ordinal, change):
    """只對指定 (test, ordinal) 的 manifest 套用 `change`（純函數，回傳新 dict 或 None）。"""
    return lambda m: change(m) if (m["test"] == test and m["ordinal"] == ordinal) else m


# ---------------------------------------------------------------------------
# v5 §13 第 5、13 項：R27 profile 夾具（合成值，非真實場 0 證據）
# ---------------------------------------------------------------------------

R27_TREE_HASH = "ab" * 20
R27_CDHASH = "cd" * 20


def r27_profile(m2_kill=None, m3_kill=None, version="synthetic-r27", m0=None, ui_t0_prime=None):
    """直接建構一份 `R27Profile`（測試用，繞過 staging／activate 的檔案 I/O）。
    `m2_kill`／`m3_kill`：`{(test, step): [簽名字串, ...]}`（與 `R55_KILL_SIGNATURES` 同形狀）。"""
    return gate.R27Profile(
        schema=gate.R27_PROFILE_SCHEMA,
        version=version,
        tree_hash=R27_TREE_HASH,
        cdhash=R27_CDHASH,
        m0=dict(m0 or {}),
        m2_kill={key: frozenset(v) for key, v in (m2_kill or {}).items()},
        m3_kill={key: frozenset(v) for key, v in (m3_kill or {}).items()},
        ui_t0_prime=dict(ui_t0_prime or {}),
    )


# 與 R5-5／M2_KILL／M3_KILL 完全相符的 active profile（用於保留既有「通過」測試意圖）
R27_PROFILE_MATCHING_R55 = r27_profile(
    m2_kill=gate.R55_KILL_SIGNATURES["M2"], m3_kill=gate.R55_KILL_SIGNATURES["M3"]
)


def write_active_r27_profile(root, m2_kill=None, m3_kill=None, version="synthetic-r27"):
    """走完整 staging → activate 流程，把一份 active R27 profile 寫進 `root`（CLI 測試用；
    `--profile-dir root` 讀得到）。M0／ui-T0′ 用最小合成值填滿（activate 要求四者皆有效）。"""
    root = Path(root)
    r27profile.stage_component(
        root,
        "m0",
        {
            "schema": gate.R27_PROFILE_SCHEMA,
            "kind": "m0",
            "tree_hash": R27_TREE_HASH,
            "cdhash": R27_CDHASH,
            "steps": {
                "T1.s1": {"sig_set": [], "allowed_codes": [], "stable": True, "observations": []},
            },
        },
    )
    r27profile.stage_component(
        root,
        "m2",
        {
            "schema": gate.R27_PROFILE_SCHEMA,
            "kind": "m2",
            "kill_signatures": {
                f"{t}.{s}": sorted(sig) for (t, s), sig in (m2_kill or gate.R55_KILL_SIGNATURES["M2"]).items()
            },
        },
    )
    r27profile.stage_component(
        root,
        "m3",
        {
            "schema": gate.R27_PROFILE_SCHEMA,
            "kind": "m3",
            "kill_signatures": {
                f"{t}.{s}": sorted(sig) for (t, s), sig in (m3_kill or gate.R55_KILL_SIGNATURES["M3"]).items()
            },
        },
    )
    r27profile.stage_component(
        root,
        "ui_t0_prime",
        {"schema": gate.R27_PROFILE_SCHEMA, "kind": "ui_t0_prime", "results": {"ShellUITests.testFoo": "PASS"}},
    )
    return gate.activate_r27(root, version=version)
