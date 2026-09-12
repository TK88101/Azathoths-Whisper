"""H-02 閘門判定：凍結常量與資料模型（拆自 `h02_gate_eval.py`，行為不變）。

輸入格式假設 2／9（Plan `docs/plans/2026-09-11-coverflow-h02-uitest-gate.md` §3.12）：
  - FAIL 碼清單可混合「產品碼」（凍結集合 `PRODUCT_CODES`）與「探針 token」（裸 `PROBE-<NAME>`）。
  - `C2-NA` 為資訊性代碼（`INFORMATIONAL_CODES`），規格明言「絕不是失敗」——不應出現在 GATE FAIL
    清單或 SIG 訊息裡；若出現視為 unknown token 記錯誤，不特殊放行。

完整的輸入格式假設清單見 `h02_gate_eval.py` 頂部 docstring 的索引。
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, FrozenSet, List, Optional, Tuple

# 常量（凍結格式，Plan §3.7／§3.8）

TEST_LABELS = {
    "T1": "testExternalScrollWritesBackAndDoesNotSnapBack",
    "T2": "testKeyboardCommandsCanCenterBothEndpoints",
    "T3": "testCenteredCardPaintsAboveBothNeighbours",
    "T4": "testReenteringTabKeepsCenteredCardCentered",
}

STEPS: Dict[str, List[str]] = {
    "T1": ["s1", "s2", "s3"],
    "T2": ["s1", "s2", "s3"],
    "T3": ["s1"],
    "T4": ["s1", "s2"],
}

UI_TEST_CLASS = "CoverFlowUITests"

PRODUCT_CODES: FrozenSet[str] = frozenset(
    {
        "C0-BLANK-SIDE", "C0-BLANK-CARD",
        "C1-OFFSET", "C1-NOT-FACING", "C1-LABEL-CARD-MISSING",
        "C2-STACK", "C2-GAP",
        "C3-TARGET-MISS",
        "C4-NO-WRITEBACK", "C4-REVERSAL", "C4-SNAPBACK",
        "C5-DRIFT",
        "C6-NEVER-SETTLES",
    }
)

INFORMATIONAL_CODES: FrozenSet[str] = frozenset({"C2-NA"})  # 從不作為失敗碼，出現即視為 unknown token

DEFECT3_CODES: FrozenSet[str] = frozenset({"C1-OFFSET", "C3-TARGET-MISS", "C5-DRIFT"})
DEFECT2_CODE = "C2-STACK"

# R4（計劃 §6）：凍結預登記表（§11 T7）的步驟分組
C2_REGISTERED_STEPS: Tuple[Tuple[str, str], ...] = (
    ("T1", "s2"), ("T1", "s3"), ("T2", "s2"), ("T2", "s3"), ("T4", "s1"),
)  # 凍結登記為 FAIL{C2-STACK}，R4-X 唯一可豁免的候選
DEFECT2_EVIDENCE_STEPS: Tuple[Tuple[str, str], ...] = C2_REGISTERED_STEPS + (("T4", "s2"),)
DEFECT3_STEP = ("T4", "s2")
POSITIVE_CONTROL_STEP = ("T2", "s1")
ENDPOINT_STEPS: Tuple[Tuple[str, str], ...] = (("T2", "s2"), ("T2", "s3"), ("T4", "s1"))

# R4-F（計劃 §6，2026-09-12 R5 辯論定案，變體 N′）：§11 凍結預登記表（M0，T7 首跑後凍結）
# → 每個登記步驟的登記碼集合（報告偏離用）與允許碼集合 F(step)（判定用）。
# T4.s2 的 F 另含 DEFECT3_CODES：§6 V3 明文接受以 C1／C3／C5 之一抓缺陷 3，凍結表相符不得縮掉它。
FROZEN_REGISTRATION: Dict[Tuple[str, str], FrozenSet[str]] = {
    ("T1", "s1"): frozenset(),
    ("T1", "s2"): frozenset({DEFECT2_CODE}),
    ("T1", "s3"): frozenset({DEFECT2_CODE}),
    ("T2", "s1"): frozenset(),
    ("T2", "s2"): frozenset({DEFECT2_CODE}),
    ("T2", "s3"): frozenset({DEFECT2_CODE}),
    ("T3", "s1"): frozenset(),
    ("T4", "s1"): frozenset({DEFECT2_CODE}),
    ("T4", "s2"): frozenset({"C1-OFFSET", DEFECT2_CODE}),
}
FROZEN_ALLOWED_CODES: Dict[Tuple[str, str], FrozenSet[str]] = {
    key: (codes | DEFECT3_CODES) if key == DEFECT3_STEP else codes
    for key, codes in FROZEN_REGISTRATION.items()
}


class GateInputError(Exception):
    """輸入格式或解析錯誤——CLI 對應 exit code 2。"""


@dataclass(frozen=True)
class GateLine:
    test: str  # `<test>.<step>` 的測試部分；空字串＝該行沒帶前綴（不合法）
    step: str
    status: str  # "PASS" | "FAIL"
    codes: Tuple[str, ...]
    raw: str


@dataclass(frozen=True)
class FailureEntry:
    kind: str  # "SIG" | "PROBE" | "UNTAGGED"
    test: Optional[str]  # SIG 的 `<test>.<step>` 測試部分；空字串＝沒帶前綴（不合法）
    step: Optional[str]
    code: Optional[str]
    fields: Tuple[Tuple[str, str], ...]
    probe_name: Optional[str]
    raw: str
    sig_key: Optional[str]


@dataclass
class Cell:
    kind: str  # "PASS" | "FAIL" | "PROBE" | "UNTAGGED" | "MISSING"
    sig_set: FrozenSet[str] = field(default_factory=frozenset)
    probe_names: Tuple[str, ...] = ()


@dataclass
class IterationInfo:
    test: str
    iteration: int
    xc_result: Optional[str]
    invalid_reasons: List[str]
    cells: Dict[str, Cell]
    unattributed: Tuple[FailureEntry, ...] = ()

    @property
    def invalid(self) -> bool:
        return bool(self.invalid_reasons)


@dataclass
class GateTable:
    tests: List[str]
    iterations: Dict[str, List[IterationInfo]]
    errors: List[str]
    iteration_count_mismatch: Dict[str, Tuple[int, int]]
