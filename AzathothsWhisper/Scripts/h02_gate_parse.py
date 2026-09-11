"""H-02 閘門判定：逐行／逐訊息解析與 xcodebuild 日誌、xcresult 解析（拆自 `h02_gate_eval.py`）。

輸入格式假設 1／3／4／5／8（Plan `docs/plans/2026-09-11-coverflow-h02-uitest-gate.md` §3.12）：
  1. `GATE{<test.step>|PASS}` 或 `GATE{<test.step>|FAIL|<CODE-或-PROBE-token>,...}` 可出現在同一行任何位置
     （其餘文字忽略），用正則在整行搜尋 `GATE{...}` 片段。
  3. 真實 xcresult 的失敗文字＝`<檔名>.swift:<行號>: failed - <XCTFail 訊息>`（2026-09-11 cf-m0 實測）。
     判斷 `SIG{`／`[PROBE-` 前先剝前綴（`^\\S+\\.swift:\\d+:\\s*`），再剝一次 XCTFail 的 `failed - ` 包裝；
     其他斷言巨集的包裝（如 `XCTAssertTrue failed - `）不剝——契約只經 XCTFail 發訊息，其餘一律 UNTAGGED。
  4. xcresulttool `get test-results tests --compact` 節點樹（Xcode 16+ schema 實測）：
     Test Plan > (Unit|UI) test bundle > Test Suite > Test Case > [Repetition] > Failure Message。
     沒有 `-test-iterations` 或未展開 Repetition 時，Test Case 節點本身即唯一（第 1 次）迭代（`result` 與
     失敗訊息直接掛在它自己身上）。Test Case 比對鍵＝`nodeIdentifier`（`CoverFlowUITests/testFoo()`），
     退回比對 `name == "testFoo()"`。
  5. xcodebuild 日誌的 `Test Case '-[Bundle.Class method]' started/passed/failed` 成對出現，據此把介於
     started 與 passed/failed 之間的 GATE 行歸給該次迭代（第幾次 started＝第幾次迭代，1-based）；
     是否帶 `(iteration N)` 尾綴不影響解析（正則只認 verb 三選一，其餘忽略）。
  8. 一個測試方法在同一次 xcodebuild 呼叫中只對應單一 device／test plan configuration（本計劃只用
     `platform=macOS` 單一 destination）；出現多個相符 Test Case 節點時只取第一個。

完整的輸入格式假設清單見 `h02_gate_eval.py` 頂部 docstring 的索引。
"""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from h02_gate_model import (
    FailureEntry,
    GateInputError,
    GateLine,
    INFORMATIONAL_CODES,
    PRODUCT_CODES,
    TEST_LABELS,
    UI_TEST_CLASS,
)

_SWIFT_PREFIX_RE = re.compile(r"^\S+\.swift:\d+:\s*")
_XCTFAIL_WRAPPER = "failed - "
_GATE_TOKEN_RE = re.compile(r"GATE\{([^{}]*)\}")
_SIG_TOKEN_RE = re.compile(r"^SIG\{([^{}]*)\}")
_PROBE_MSG_RE = re.compile(r"^\[PROBE-([A-Za-z0-9_-]+)\]")
_PROBE_GATE_TOKEN_RE = re.compile(r"^PROBE-([A-Za-z0-9_-]+)$")
_TESTCASE_LINE_RE = re.compile(
    r"Test Case '-\[(?P<bundle>\w+)\.(?P<cls>\w+) (?P<method>\w+)\]' (?P<verb>started|passed|failed)\b"
)


def strip_swift_prefix(text: str) -> str:
    """剝除 `<檔名>.swift:<行號>: ` 前綴（只剝一次，Plan §3 假設 3）。"""
    return _SWIFT_PREFIX_RE.sub("", text, count=1)


def failure_message_body(raw_text: str) -> str:
    """xcresult 失敗文字 → XCTFail 訊息本身（假設 3）：剝前綴，再剝一次 XCTFail 的 `failed - ` 包裝。"""
    return strip_swift_prefix(raw_text).removeprefix(_XCTFAIL_WRAPPER)


def parse_gate_token(line: str) -> Optional[GateLine]:
    """在任意一行文字中尋找 `GATE{...}` 片段並解析；找不到回 None。"""
    m = _GATE_TOKEN_RE.search(line)
    if not m:
        return None
    body = m.group(1)
    parts = body.split("|")
    if len(parts) < 2:
        raise GateInputError(f"GATE 格式不合法（欄位不足）：{line!r}")
    test_step = parts[0]
    test, _, step = test_step.rpartition(".")
    status = parts[1]
    if status == "PASS":
        codes: Tuple[str, ...] = ()
    elif status == "FAIL":
        codes_str = parts[2] if len(parts) > 2 else ""
        codes = tuple(c for c in codes_str.split(",") if c)
    else:
        raise GateInputError(f"GATE 狀態既非 PASS 亦非 FAIL：{line!r}")
    return GateLine(test=test, step=step, status=status, codes=codes, raw=line.strip())


def parse_failure_message(raw_text: str) -> FailureEntry:
    """解析一則 xcresult Failure Message 節點文字（前綴與 XCTFail 包裝有無皆可）。"""
    text = failure_message_body(raw_text)
    m = _SIG_TOKEN_RE.match(text)
    if m:
        body = m.group(1)
        parts = body.split("|")
        test, _, step = parts[0].rpartition(".")
        code = parts[1] if len(parts) > 1 else ""
        fields: List[Tuple[str, str]] = []
        for kv in parts[2:]:
            if "=" in kv:
                k, v = kv.split("=", 1)
            else:
                k, v = kv, ""
            fields.append((k, v))
        sig_key = code + "".join(f"|{k}={v}" for k, v in fields)
        return FailureEntry(
            kind="SIG",
            test=test,
            step=step,
            code=code,
            fields=tuple(fields),
            probe_name=None,
            raw=raw_text,
            sig_key=sig_key,
        )
    m = _PROBE_MSG_RE.match(text)
    if m:
        return FailureEntry(
            kind="PROBE",
            test=None,
            step=None,
            code=None,
            fields=(),
            probe_name=m.group(1),
            raw=raw_text,
            sig_key=None,
        )
    return FailureEntry(
        kind="UNTAGGED", test=None, step=None, code=None, fields=(), probe_name=None,
        raw=raw_text, sig_key=None,
    )


def _classify_gate_token(token: str) -> Tuple[str, str]:
    """回傳 (種類, 值)；種類 ∈ {"product", "informational", "probe", "unknown"}。"""
    if token in PRODUCT_CODES:
        return "product", token
    if token in INFORMATIONAL_CODES:
        return "informational", token
    m = _PROBE_GATE_TOKEN_RE.match(token)
    if m:
        return "probe", token
    return "unknown", token


# xcodebuild 日誌解析


def parse_log(
    log_text: str, test_labels: Optional[Dict[str, str]] = None
) -> Tuple[Dict[str, List[List[GateLine]]], List[str], Dict[str, int]]:
    """回傳 ({test_label: [[GateLine,...一次迭代內依序], ...]}, 孤兒 GATE 行清單, {test_label: 成對收尾的迭代數})。

    配對以「目前開著的迭代」為準，不只比總數：沒有開始的收尾、開著又再開始、EOF 仍開著，都不算成對。"""
    test_labels = test_labels or TEST_LABELS
    method_to_label = {v: k for k, v in test_labels.items()}
    per_test: Dict[str, List[List[GateLine]]] = {label: [] for label in test_labels}
    closed: Dict[str, int] = {label: 0 for label in test_labels}
    open_label: Optional[str] = None
    open_lines: Optional[List[GateLine]] = None
    orphan_lines: List[str] = []

    for raw_line in log_text.splitlines():
        m = _TESTCASE_LINE_RE.search(raw_line)
        if m:
            method = m.group("method")
            label = method_to_label.get(method)
            verb = m.group("verb")
            if label is None or m.group("cls") != UI_TEST_CLASS:
                continue
            if verb == "started":
                open_label, open_lines = label, []
                per_test[label].append(open_lines)
            elif open_label == label:  # 只有關掉自己開著的那次才算成對
                closed[label] += 1
                open_label, open_lines = None, None
            continue
        gate = parse_gate_token(raw_line)
        if gate is not None:
            if open_lines is None:
                orphan_lines.append(raw_line.strip())
            else:
                open_lines.append(gate)
    return per_test, orphan_lines, closed


# xcresult 解析


def load_xcresult_json(path: str) -> dict:
    """讀取 xcresult 輸入：`.xcresult` bundle（目錄）→ 呼叫 xcresulttool；
    其餘（例如預先存好的 `--compact` JSON 檔）→ 直接讀檔解析。"""
    p = Path(path)
    if p.is_dir() or str(path).endswith(".xcresult"):
        try:
            proc = subprocess.run(
                [
                    "xcrun",
                    "xcresulttool",
                    "get",
                    "test-results",
                    "tests",
                    "--path",
                    str(p),
                    "--compact",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
        except (OSError, subprocess.CalledProcessError) as e:
            raise GateInputError(f"xcresulttool 調用失敗（{path}）：{e}") from e
        raw = proc.stdout
    else:
        try:
            raw = p.read_text(encoding="utf-8")
        except OSError as e:
            raise GateInputError(f"讀取 xcresult JSON 失敗（{path}）：{e}") from e
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        raise GateInputError(f"xcresult JSON 解析失敗（{path}）：{e}") from e


def _index_test_case_nodes(nodes: List[dict]) -> List[dict]:
    """一次走訪整棵節點樹，蒐集所有 `Test Case` 節點（依走訪順序）；配對交給呼叫端逐一篩選。

    Test Case 節點本身不會巢狀出現另一個 Test Case 節點（假設 4 的 schema），故是否在此提早
    停止往下遞迴不影響蒐集到的節點集合——因此可以安全地對每個節點都繼續遞迴，一次走訪就找齊。"""
    found: List[dict] = []

    def walk(node: dict) -> None:
        if node.get("nodeType") == "Test Case":
            found.append(node)
        for child in node.get("children") or []:
            walk(child)

    for n in nodes:
        walk(n)
    return found


def _match_test_case_node(all_test_case_nodes: List[dict], method_name: str) -> Optional[dict]:
    """在已蒐集好的 Test Case 節點裡，依走訪順序找第一個相符者；找不到回 None（假設 8）。"""
    wanted_ident = f"{UI_TEST_CLASS}/{method_name}()"
    for node in all_test_case_nodes:
        ident = node.get("nodeIdentifier") or ""
        name = node.get("name") or ""
        if ident == wanted_ident or (not ident and name == method_name + "()"):
            return node
    return None


def _collect_failure_texts(node: dict) -> List[str]:
    texts: List[str] = []

    def walk(n: dict) -> None:
        if n.get("nodeType") == "Failure Message":
            texts.append(n.get("name") or "")
            return
        for c in n.get("children") or []:
            walk(c)

    for c in node.get("children") or []:
        walk(c)
    return texts


def _iterations_from_test_case_node(node: dict) -> List[Tuple[Optional[str], List[FailureEntry]]]:
    reps = [c for c in (node.get("children") or []) if c.get("nodeType") == "Repetition"]
    return [
        (n.get("result"), [parse_failure_message(t) for t in _collect_failure_texts(n)])
        for n in (reps if reps else [node])
    ]


def parse_xcresult(
    xc_json: dict, test_labels: Optional[Dict[str, str]] = None
) -> Dict[str, List[Tuple[Optional[str], List[FailureEntry]]]]:
    """回傳 {test_label: [(result, [FailureEntry,...]), ...]}；xcresult 裡找不到的測試不出現在結果中。"""
    test_labels = test_labels or TEST_LABELS
    nodes = xc_json.get("testNodes") or []
    all_test_case_nodes = _index_test_case_nodes(nodes)
    out: Dict[str, List[Tuple[Optional[str], List[FailureEntry]]]] = {}
    for label, method in test_labels.items():
        node = _match_test_case_node(all_test_case_nodes, method)
        if node is None:
            continue
        out[label] = _iterations_from_test_case_node(node)
    return out
