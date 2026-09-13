"""H-02 閘門判定：V3／V4／V5 判定與 R4-C 結論（拆自 `h02_gate_eval.py`）。

輸入格式假設 7（Plan `docs/plans/2026-09-11-coverflow-h02-uitest-gate.md` §3.12）：
  GATE 的 FAIL 碼清單與 SIG／PROBE 訊息不一致（碼集合對不上、或找不到對應訊息）記為 `errors`
  （不中止解析，交由人工核對）。R4 起（計劃 §3.12）任何 errors 都使 `table_valid` 不成立，
  V3／V4／V5 一律視為無效運行。

完整的輸入格式假設清單見 `h02_gate_eval.py` 頂部 docstring 的索引。
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
from typing import Dict, FrozenSet, List, Optional, Tuple

from h02_gate_model import (
    COVERFLOW_DIR,
    COVERFLOW_STRIP_FILE,
    EVIDENCE_OPTIONAL_FILES,
    EVIDENCE_REQUIRED_FILES,
    FROZEN_ALLOWED_CODES,
    FROZEN_REGISTRATION,
    MANIFEST_SCHEMA,
    MANIFEST_SUFFIX,
    MUTANT_NAMES,
    R55_KILL_SIGNATURES,
    REQUIRED_KILL_STEPS,
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


# ---------------------------------------------------------------------------
# F1（計劃 `docs/plans/2026-09-13-coverflow-h02-fix4.md` §5.1／§5.2／§5.7 (7)）：
# C.1 候選閘門、C.2 負對照、證據完整性。全部為純函數（只讀檔，不寫檔），CLI 只負責列印。
# ---------------------------------------------------------------------------


def _md5(path: Path) -> str:
    digest = hashlib.md5()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _file_entry_reasons(root: Path, where: str, kind: str, entry: object) -> List[str]:
    """manifest 內單一檔案條目：欄位齊全、路徑合法（相對、不出目錄）、檔案存在、md5 相符。"""
    if not isinstance(entry, dict):
        return [f"{where}: files.{kind} 不是物件"]
    name, md5 = entry.get("path"), entry.get("md5")
    if not isinstance(name, str) or not name:
        return [f"{where}: files.{kind} 缺 path"]
    if not isinstance(md5, str) or not md5:
        return [f"{where}: files.{kind}（{name}）缺 md5"]
    pure = PurePosixPath(name)
    if pure.is_absolute() or ".." in pure.parts:
        return [f"{where}: files.{kind} 路徑不合法（{name}）"]
    target = root / name
    if not target.is_file():
        return [f"{where}: files.{kind} 檔案不存在（{name}）"]
    actual = _md5(target)
    if actual != md5:
        return [f"{where}: files.{kind}（{name}）md5 不符（manifest {md5}／實得 {actual}）"]
    return []


def _manifest_files_reasons(root: Path, where: str, files: object) -> List[str]:
    if not isinstance(files, dict):
        return [f"{where}: 缺 files"]
    reasons: List[str] = []
    for kind in EVIDENCE_REQUIRED_FILES:
        if files.get(kind) is None:
            reasons.append(f"{where}: files.{kind} 不得為 null")
        else:
            reasons.extend(_file_entry_reasons(root, where, kind, files[kind]))
    for kind in EVIDENCE_OPTIONAL_FILES:
        if kind not in files:
            reasons.append(f"{where}: files 缺 {kind} 鍵（儀器 OFF 時應為 null）")
        elif files[kind] is not None:
            reasons.extend(_file_entry_reasons(root, where, kind, files[kind]))
    return reasons


def _manifest_reasons(root: Path, label: str, ordinal: int) -> List[str]:
    where = f"{label}-{ordinal}"
    try:
        data = json.loads((root / f"{where}{MANIFEST_SUFFIX}").read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return [f"{where}: manifest 無法讀取／解析（{e}）"]
    if not isinstance(data, dict):
        return [f"{where}: manifest 不是物件"]
    reasons: List[str] = []
    if data.get("schema") != MANIFEST_SCHEMA:
        reasons.append(f"{where}: schema 應為 {MANIFEST_SCHEMA}，實得 {data.get('schema')!r}")
    if data.get("test") != label:
        reasons.append(f"{where}: test 欄 {data.get('test')!r} 與檔名不符")
    if data.get("ordinal") != ordinal:
        reasons.append(f"{where}: ordinal 欄 {data.get('ordinal')!r} 與檔名不符")
    for field_name in ("tree_hash", "cdhash"):
        if not isinstance(data.get(field_name), str) or not data.get(field_name):
            reasons.append(f"{where}: 缺 {field_name}")
    return reasons + _manifest_files_reasons(root, where, data.get("files"))


def _manifest_ordinals(root: Path, label: str) -> List[int]:
    ordinals = []
    for path in root.glob(f"{label}-*{MANIFEST_SUFFIX}"):
        text = path.name[len(label) + 1 : -len(MANIFEST_SUFFIX)]
        if text.isdigit():
            ordinals.append(int(text))
    return sorted(ordinals)


def evaluate_evidence(
    evidence_dir: str, expected_iterations: int, test_labels: Optional[List[str]] = None
) -> Tuple[bool, List[str]]:
    """§5.7 (7) 證據完整性：每個測試恰 N 份、序號自 1 連號的 manifest，且引用檔存在、md5 相符。"""
    root = Path(evidence_dir)
    if not root.is_dir():
        return False, [f"證據目錄不存在：{evidence_dir}"]
    reasons: List[str] = []
    expected = list(range(1, expected_iterations + 1))
    for label in list(test_labels or TEST_LABELS):
        found = _manifest_ordinals(root, label)
        if len(found) != expected_iterations:
            reasons.append(f"{label}: 預期 {expected_iterations} 份 manifest，實得 {len(found)}")
        missing = [n for n in expected if n not in found]
        extra = [n for n in found if n not in expected]
        if missing:
            reasons.append(f"{label}: 缺 manifest 序號 {missing}")
        if extra:
            reasons.append(f"{label}: manifest 序號不連號／超出範圍 {extra}")
        for ordinal in found:
            reasons.extend(_manifest_reasons(root, label, ordinal))
    return not reasons, reasons


def candidate_failures(table: GateTable) -> List[Tuple[str, str, int, Tuple[str, ...]]]:
    """FAIL 格清單 (test, step, iteration, 正規化簽名集合)，依 測試 → 迭代 → 步驟 序。"""
    failures = []
    for label in table.tests:
        for info in table.iterations[label]:
            for step in STEPS[label]:
                cell = info.cells.get(step)
                if cell is not None and cell.kind == "FAIL":
                    failures.append((label, step, info.iteration, tuple(sorted(cell.sig_set))))
    return failures


def _failure_counts(
    failures: List[Tuple[str, str, int, Tuple[str, ...]]]
) -> Dict[Tuple[str, Tuple[str, ...]], int]:
    """按 (step, 正規化簽名集合) 計數（§5 護欄 (c) 熔斷判定用）。"""
    counts: Dict[Tuple[str, Tuple[str, ...]], int] = {}
    for label, step, _iteration, signature in failures:
        key = (f"{label}.{step}", signature)
        counts[key] = counts.get(key, 0) + 1
    return counts


def _all_cells_pass(table: GateTable) -> bool:
    return all(
        cell.kind == "PASS"
        for label in table.tests
        for info in table.iterations[label]
        for cell in info.cells.values()
    )


def evaluate_candidate(table: GateTable, iterations: int, evidence: Optional[str] = None) -> dict:
    """C.1（§5.1）單一規則：
    無效 ⇔ table_valid 不成立，或給了 evidence 時證據不完整；
    通過 ⇔ 有效 ∧ 全部格 PASS；不通過 ⇔ 有效 ∧ 任一格 FAIL（任何產品碼）。"""
    run_valid, run_reasons = table_valid(table, iterations)
    if evidence is None:
        evidence_ok, evidence_reasons = None, []  # type: Tuple[Optional[bool], List[str]]
    else:
        evidence_ok, evidence_reasons = evaluate_evidence(evidence, iterations)
    invalid_reasons = list(run_reasons) + ["證據：" + r for r in evidence_reasons]
    failures = candidate_failures(table)
    if invalid_reasons:
        conclusion = "無效"
    elif _all_cells_pass(table):
        conclusion = "通過"
    else:
        conclusion = "不通過"
    return {
        "conclusion": conclusion,
        "run_valid": run_valid,
        "run_invalid_reasons": run_reasons,
        "evidence_ok": evidence_ok,
        "evidence_reasons": evidence_reasons,
        "invalid_reasons": invalid_reasons,
        "failing_cells": failures,
        "failure_counts": _failure_counts(failures),
        "cell_count": sum(len(STEPS[label]) for label in table.tests) * iterations,
        "iterations": iterations,
    }


def kill_signature_has_defect2(sig_set) -> bool:
    """§5.2 新增條款：殺死簽名集合的產品碼投影必須含 C2-STACK（其他碼可併存，但不得單獨構成殺死）。"""
    return DEFECT2_CODE in _codes(frozenset(sig_set))


def kill_outcome_with_defect2(
    key: Tuple[str, str],
    baseline_table: GateTable,
    mutant_table: GateTable,
    excluded: Optional[Tuple[str, str]] = None,
) -> Tuple[bool, object]:
    """既有 `_kill_outcome` 條件 ∧ 產品碼投影含 C2-STACK。"""
    killed, detail = _kill_outcome(key, baseline_table, mutant_table, excluded)
    if not killed:
        return False, detail
    if not kill_signature_has_defect2(detail):
        return False, f"簽名的產品碼投影不含 {DEFECT2_CODE}：{detail}"
    return True, detail


def _signature_deviations(name: str, killed: List[Tuple[str, str, object]]) -> List[str]:
    """殺死步驟的完整簽名集合與 R5-5 凍結簽名逐字比對；不同或未登記 → 偏離。"""
    expected = R55_KILL_SIGNATURES[name]
    deviations = []
    for label, step, signature in killed:
        want = expected.get((label, step))
        got = frozenset(signature)  # type: ignore[arg-type]
        if want is None:
            deviations.append(f"{name} {label}.{step}：R5-5 未登記的殺死步驟，簽名 {sorted(got)}")
        elif got != want:
            deviations.append(f"{name} {label}.{step}：簽名 {sorted(got)} ≠ R5-5 {sorted(want)}")
    return deviations


def mutant_kill_report(name: str, baseline_table: GateTable, mutant_table: GateTable) -> dict:
    """單份變異運行的殺死報告（含 C2 條款）與簽名偏離。"""
    killed: List[Tuple[str, str, object]] = []
    survived: List[Tuple[str, str, object]] = []
    for label in TEST_LABELS:
        for step in STEPS[label]:
            ok, detail = kill_outcome_with_defect2((label, step), baseline_table, mutant_table)
            (killed if ok else survived).append((label, step, detail))
    required = REQUIRED_KILL_STEPS[name]
    killed_keys = [(label, step) for label, step, _ in killed]
    return {
        "name": name,
        "killed": killed,
        "survived": survived,
        "required_steps": list(required),
        "kill_ok": any(key in killed_keys for key in required),
        "deviations": _signature_deviations(name, killed),
    }


def non_strip_coverflow_changes(paths) -> List[str]:
    """候選改動檔中位於 `Features/CoverFlow/` 之下、且不是 `CoverFlowStrip.swift` 的檔（§5.2 分支判定）。"""
    changed = []
    for raw in paths or ():
        path = raw.strip().replace("\\", "/")
        if not path or path.startswith("#"):
            continue
        if COVERFLOW_DIR in path and path.rsplit("/", 1)[-1] != COVERFLOW_STRIP_FILE:
            changed.append(path)
    return changed


def has_non_strip_coverflow_change(paths) -> bool:
    return bool(non_strip_coverflow_changes(paths))


def _baseline_reasons(table: GateTable, iterations: int) -> Tuple[bool, List[str]]:
    """baseline（候選 C.1 那份運行）須有效且全 PASS，否則不得拿來判殺死。"""
    _ok, invalid = table_valid(table, iterations)
    reasons = [f"baseline 運行無效：{r}" for r in invalid]
    failures = candidate_failures(table)
    if failures:
        shown = "; ".join(f"{t}.{s} iter {i}" for t, s, i, _ in failures[:3])
        tail = "…" if len(failures) > 3 else ""
        reasons.append(f"baseline 非全 PASS：{len(failures)} 格 FAIL（{shown}{tail}）")
    return not reasons, reasons


def evaluate_negative_control(
    baseline_table: GateTable,
    m2_table: GateTable,
    m3_table: GateTable,
    baseline_iterations: int = 20,
    mutant_iterations: int = 3,
    product_files=None,
) -> dict:
    """C.2（§5.2）結論按序取第一個成立者：
    無效（變異運行無效）→ baseline不合格 → 回Phase1-變異移植／不通過 → 不可判定-待解釋 → 通過。"""
    tables = {"M2": m2_table, "M3": m3_table}
    mutant_reasons = [
        f"{name}: {reason}"
        for name in MUTANT_NAMES
        for reason in table_valid(tables[name], mutant_iterations)[1]
    ]
    baseline_ok, baseline_reasons = _baseline_reasons(baseline_table, baseline_iterations)
    changed = non_strip_coverflow_changes(product_files)
    base = {
        "baseline_ok": baseline_ok,
        "baseline_reasons": baseline_reasons,
        "mutant_invalid_reasons": mutant_reasons,
        "mutants": {},
        "deviations": [],
        "product_files": changed,
        "migration_trigger": False,
    }
    if mutant_reasons:
        return dict(base, conclusion="無效", reasons=mutant_reasons)
    if not baseline_ok:
        return dict(base, conclusion="baseline不合格", reasons=baseline_reasons)
    reports = {name: mutant_kill_report(name, baseline_table, tables[name]) for name in MUTANT_NAMES}
    deviations = [d for name in MUTANT_NAMES for d in reports[name]["deviations"]]
    unkilled = [name for name in MUTANT_NAMES if not reports[name]["kill_ok"]]
    migration = bool(unkilled) and bool(changed)
    result = dict(base, mutants=reports, deviations=deviations, migration_trigger=migration)
    if migration:
        return dict(
            result,
            conclusion="回Phase1-變異移植",
            reasons=[_unkilled_reason(reports[name]) for name in unkilled]
            + [f"候選改動含 Features/CoverFlow/ 下非 CoverFlowStrip.swift 的檔：{changed}"],
        )
    if unkilled:
        return dict(result, conclusion="不通過", reasons=[_unkilled_reason(reports[name]) for name in unkilled])
    if deviations:
        return dict(result, conclusion="不可判定-待解釋", reasons=deviations)
    return dict(result, conclusion="通過", reasons=[])


def _unkilled_reason(report: dict) -> str:
    steps = "／".join(f"{t}.{s}" for t, s in report["required_steps"])
    return f"{report['name']} 未在 {{{steps}}} 任一步驟殺死（含 C2-STACK）"
