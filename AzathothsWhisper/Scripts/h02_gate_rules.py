"""H-02 閘門判定：V3／V4／V5 判定與 R4-C 結論（拆自 `h02_gate_eval.py`）。

輸入格式假設 7（Plan `docs/plans/2026-09-11-coverflow-h02-uitest-gate.md` §3.12）：
  GATE 的 FAIL 碼清單與 SIG／PROBE 訊息不一致（碼集合對不上、或找不到對應訊息）記為 `errors`
  （不中止解析，交由人工核對）。R4 起（計劃 §3.12）任何 errors 都使 `table_valid` 不成立，
  V3／V4／V5 一律視為無效運行。

完整的輸入格式假設清單見 `h02_gate_eval.py` 頂部 docstring 的索引。
"""
from __future__ import annotations

from typing import Dict, FrozenSet, List, Optional, Tuple

from h02_gate_model import (
    FROZEN_ALLOWED_CODES,
    FROZEN_REGISTRATION,
    Cell,
    C2_REGISTERED_STEPS,
    DEFECT2_CODE,
    DEFECT2_EVIDENCE_STEPS,
    DEFECT3_CODES,
    DEFECT3_STEP,
    ENDPOINT_STEPS,
    GateTable,
    IterationInfo,
    POSITIVE_CONTROL_STEP,
    PRODUCT_CODES,
    STEPS,
    TEST_LABELS,
)

# V3／V4／V5 判定與結論（R4 修訂：計劃 §3.12 table_valid、§6 V3／V5／R4-X／R4-C）


def _codes(sig_set) -> FrozenSet[str]:
    return frozenset(s.split("|", 1)[0] for s in sig_set)


def _iteration_problems(info: IterationInfo) -> List[str]:
    where = f"{info.test} iter {info.iteration}"
    problems = [f"{where}: {r}" for r in info.invalid_reasons]
    problems += [f"{where} {s}: MISSING（缺 GATE）" for s, c in info.cells.items() if c.kind == "MISSING"]
    if info.xc_result not in ("Passed", "Failed"):
        problems.append(f"{where}: xcresult 狀態 {info.xc_result!r} 不是 Passed／Failed")
    elif (info.xc_result == "Passed") != all(c.kind == "PASS" for c in info.cells.values()):
        problems.append(f"{where}: xcresult {info.xc_result} 與 GATE 不一致")
    return problems


def table_valid(table: GateTable, expected_iterations: int) -> Tuple[bool, List[str]]:
    """R4-V：V3／V4／V5 共用的唯一有效性判準。回傳 (是否有效, 理由)；理由為空才有效。"""
    reasons = [f"缺測試 {label}" for label in TEST_LABELS if label not in table.tests]
    for label in table.tests:
        infos = table.iterations[label]
        if len(infos) != expected_iterations:
            reasons.append(f"{label}: 預期 {expected_iterations} 次，實得 {len(infos)} 次")
        for info in infos:
            reasons.extend(_iteration_problems(info))
    reasons.extend(f"errors: {e}" for e in table.errors)
    return not reasons, reasons


def _cells(table: GateTable, key: Tuple[str, str]) -> List[Cell]:
    label, step = key
    return [info.cells[step] for info in table.iterations.get(label, [])]


def _step_status(cells: List[Cell]) -> dict:
    kinds = [c.kind for c in cells]
    if kinds and all(k == "PASS" for k in kinds):
        return {"status": "ALL_PASS"}
    if kinds and all(k == "FAIL" for k in kinds) and len({c.sig_set for c in cells}) == 1:
        return {"status": "ALL_FAIL_CONSISTENT", "sig_set": sorted(cells[0].sig_set)}
    return {"status": "INCONSISTENT"}


def _is_c2_only_fail(cell: Cell) -> bool:
    return cell.kind == "FAIL" and _codes(cell.sig_set) == {DEFECT2_CODE}


def _passes_endpoint_subcontract(cell: Cell) -> bool:
    """端點陽性子契約 C0／C1／C3／C6：PASS，或唯一的產品碼是不參與 V5 的 C2-STACK。"""
    return cell.kind == "PASS" or _is_c2_only_fail(cell)


def _excludable(key: Tuple[str, str], cells: List[Cell]) -> bool:
    """R4-X (a)(b)：凍結登記為 FAIL{C2-STACK}，十次只有 PASS 與 FAIL{C2-STACK} 且兩者各至少一次。"""
    return (
        key in C2_REGISTERED_STEPS
        and any(c.kind == "PASS" for c in cells)
        and any(_is_c2_only_fail(c) for c in cells)
        and all(_passes_endpoint_subcontract(c) for c in cells)
    )


def _defect3(per_step: Dict[Tuple[str, str], dict]) -> dict:
    status = per_step.get(DEFECT3_STEP, {}).get("status")
    if status == "INCONSISTENT":
        return {"status": "UNSTABLE"}
    sig_set = per_step.get(DEFECT3_STEP, {}).get("sig_set", [])
    if status == "ALL_FAIL_CONSISTENT" and _codes(sig_set) & DEFECT3_CODES:
        return {"status": "CAUGHT", "sig_set": sig_set}
    return {"status": "NOT_CAUGHT"}


def evaluate_frozen_conformity(table: GateTable) -> Tuple[bool, List[str], List[str]]:
    """R4-F（變體 N′；只對 M0 確認性運行，變異運行不適用）：每次迭代每格 FAIL 的產品碼投影必須 ⊆ F(step)，
    出現 F 外碼（哪怕 1/10）＝與預登記矛盾 → 不可判定（reasons）；仍 ⊆ F 但與登記不同的格（含翻成 PASS）
    只記偏離（deviations，報告用），結論交既有 V3／V5／缺陷 2 分支。PROBE／MISSING／UNTAGGED 由 table_valid 處理。
    回傳 (相符, reasons, deviations)。"""
    reasons: List[str] = []
    deviations: List[str] = []
    for label in table.tests:
        infos = table.iterations[label]
        for step in STEPS[label]:
            allowed = FROZEN_ALLOWED_CODES[(label, step)]
            registered = FROZEN_REGISTRATION[(label, step)]
            differing: List[str] = []
            for info in infos:
                cell = info.cells[step]
                if cell.kind == "FAIL":
                    codes = _codes(cell.sig_set)
                    extra = sorted(codes - allowed)
                    if extra:
                        reasons.append(f"R4-F：{label}.{step} iter {info.iteration} 實得 {extra} ∉ F{sorted(allowed)}")
                    if codes != registered:
                        differing.append(f"iter {info.iteration} FAIL{sorted(codes)}")
                elif cell.kind == "PASS" and registered:
                    differing.append(f"iter {info.iteration} PASS")
            if differing:
                frozen_text = "PASS" if not registered else f"FAIL{sorted(registered)}"
                shown = "; ".join(differing[:3]) + ("…" if len(differing) > 3 else "")
                deviations.append(f"{label}.{step}: {len(differing)}/{len(infos)} 次與凍結登記 {frozen_text} 不同（{shown}）")
    return not reasons, reasons, deviations


def evaluate_v3(table: GateTable, iterations: int) -> dict:
    """V3（R4）：缺陷 3＝T4.s2 穩定帶缺陷 3 碼；缺陷 2＝非 EXCLUDED 的 C2 步驟穩定帶 C2-STACK；一致性含 ≤1 格例外。"""
    run_valid, invalid_reasons = table_valid(table, iterations)
    per_step = {
        (label, step): _step_status(_cells(table, (label, step)))
        for label in table.tests
        for step in STEPS[label]
    }
    inconsistent = [key for key, v in per_step.items() if v["status"] == "INCONSISTENT"]
    only = inconsistent[0] if len(inconsistent) == 1 else None
    excluded = only if only is not None and _excludable(only, _cells(table, only)) else None
    defect2 = [
        (t, s, v["sig_set"])
        for (t, s), v in per_step.items()
        if (t, s) in DEFECT2_EVIDENCE_STEPS
        and (t, s) != excluded
        and v["status"] == "ALL_FAIL_CONSISTENT"
        and DEFECT2_CODE in _codes(v["sig_set"])
    ]
    frozen_ok, frozen_reasons, frozen_deviations = evaluate_frozen_conformity(table)
    return {
        "run_valid": run_valid,
        "invalid_reasons": invalid_reasons,
        "per_step": per_step,
        "inconsistent": inconsistent,
        "excluded": excluded,
        "consistency_ok": not inconsistent or excluded is not None,
        "defect3": _defect3(per_step),
        "defect2_steps": defect2,
        "defect2_reproduced": bool(defect2),
        "frozen_conformity_ok": frozen_ok,
        "frozen_conformity_reasons": frozen_reasons,
        "frozen_deviations": frozen_deviations,
        "errors": list(table.errors),
    }


def evaluate_v5(table: GateTable, v3: dict, s2_verified: bool) -> dict:
    """V5（R4）：T2.s1 十次全契約 PASS；某非 EXCLUDED 端點每次都過端點陽性子契約；S2 由呼叫端依 §11 斷言。"""
    positive_control_ok = v3["per_step"].get(POSITIVE_CONTROL_STEP, {}).get("status") == "ALL_PASS"
    # 端點必須自身十次一致（ALL_PASS 或 ALL_FAIL_CONSISTENT）：時紅時綠的端點不得充當陽性對照，
    # 無論它是否被標為 EXCLUDED（R4-X (c)；否則多一個無關 flake 反而會讓結論變寬鬆）
    endpoints = [
        key
        for key in ENDPOINT_STEPS
        if key != v3["excluded"]
        and v3["per_step"].get(key, {}).get("status") in ("ALL_PASS", "ALL_FAIL_CONSISTENT")
        and _cells(table, key)
        and all(_passes_endpoint_subcontract(c) for c in _cells(table, key))
    ]
    checks = [
        (v3["run_valid"], "table_valid 不成立"),
        (positive_control_ok, "T2.s1 非 10/10 全契約 PASS"),
        (bool(endpoints), "沒有端點步驟十次都過端點陽性子契約"),
        (s2_verified, "S2 已知點命中未斷言（--s2-verified）"),
    ]
    reasons = [message for ok, message in checks if not ok]
    return {
        "ok": not reasons,
        "positive_control_ok": positive_control_ok,
        "endpoint_steps_ok": endpoints,
        "s2_verified": s2_verified,
        "reasons": reasons,
    }


def _kill_outcome(
    key: Tuple[str, str], baseline_table: GateTable, mutant_table: GateTable, excluded: Optional[Tuple[str, str]]
) -> Tuple[bool, object]:
    """回傳 (是否殺死, 殺死簽名清單或存活理由)。"""
    if key == excluded:
        return False, "EXCLUDED 格不可作殺死步驟"
    if _step_status(_cells(baseline_table, key))["status"] != "ALL_PASS":
        return False, "baseline 不是全部 PASS，不可作殺死步驟"
    cells = _cells(mutant_table, key)
    if not all(c.kind == "FAIL" for c in cells):
        return False, "mutant 未全部 FAIL"
    if len({c.sig_set for c in cells}) != 1:
        return False, "mutant 各次迭代簽名集合不一致"
    extra = _codes(cells[0].sig_set) - PRODUCT_CODES
    if extra:
        return False, f"簽名含非產品碼：{sorted(extra)}"
    return True, sorted(cells[0].sig_set)


def evaluate_v4(
    baseline_table: GateTable,
    mutant_table: GateTable,
    baseline_iterations: int = 10,
    mutant_iterations: int = 3,
    excluded: Optional[Tuple[str, str]] = None,
) -> dict:
    """V4：步驟級差異殺死（§3.11）；baseline 與 mutant 各自須 table_valid。"""
    base_ok, base_reasons = table_valid(baseline_table, baseline_iterations)
    mut_ok, mut_reasons = table_valid(mutant_table, mutant_iterations)
    result: dict = {
        "baseline_invalid": not base_ok,
        "mutant_invalid": not mut_ok,
        "invalid_reasons": [f"baseline: {r}" for r in base_reasons] + [f"mutant: {r}" for r in mut_reasons],
        "killed": [],
        "survived": [],
        "errors": list(baseline_table.errors) + list(mutant_table.errors),
    }
    if not mut_ok:
        return {**result, "verdict": "MUTANT_RUN_INVALID"}
    if not base_ok:
        return {**result, "verdict": "BASELINE_RUN_INVALID"}
    for label in TEST_LABELS:
        for step in STEPS[label]:
            killed, detail = _kill_outcome((label, step), baseline_table, mutant_table, excluded)
            result["killed" if killed else "survived"].append((label, step, detail))
    return {**result, "verdict": "OK"}


def verdict(
    m0: GateTable,
    m2: GateTable,
    m3: GateTable,
    s2_verified: bool,
    m0_iterations: int = 10,
    mutant_iterations: int = 3,
) -> dict:
    """R4-C：按優先序取第一個成立的結論（不可判定 → 不通過 → 部分通過 → 通過）。
    「不可建」屬 S 階段、不由本函數輸出；V4 權重由使用者在看到結果後裁決。"""
    v3 = evaluate_v3(m0, m0_iterations)
    v5 = evaluate_v5(m0, v3, s2_verified)
    v4 = {
        name: evaluate_v4(m0, table, m0_iterations, mutant_iterations, excluded=v3["excluded"])
        for name, table in (("M2", m2), ("M3", m3))
    }
    # 不可判定的獨立觸發（R4-C）：table_valid（經 V5 帶入）、V5、變異運行無效、R4-F 凍結表不相符（只對 M0）
    undecidable = (
        [f"V5：{r}" for r in v5["reasons"]]
        + [f"{name}：{r['verdict']}" for name, r in v4.items() if r["verdict"] != "OK"]
        + list(v3["frozen_conformity_reasons"])
    )
    partial = (
        ([] if v3["defect2_reproduced"] else ["缺陷 2 在 M0 落定態不可重現"])
        + ([] if v3["consistency_ok"] else [f"V3 一致性不成立：{v3['inconsistent']}"])
        + [f"{name} 未被殺" for name, r in v4.items() if not r["killed"]]
    )
    if undecidable:
        conclusion, reasons = "不可判定", undecidable
    elif v3["defect3"]["status"] != "CAUGHT":
        conclusion, reasons = "不通過", [f"缺陷 3：{v3['defect3']['status']}"]
    elif partial:
        conclusion, reasons = "部分通過", partial
    else:
        conclusion, reasons = "通過", []
    return {"conclusion": conclusion, "reasons": reasons, "v3": v3, "v5": v5, "v4": v4}
