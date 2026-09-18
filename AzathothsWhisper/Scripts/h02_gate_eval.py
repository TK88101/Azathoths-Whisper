#!/usr/bin/env python3
"""H-02 缺陷 2／3 XCUITest 閘門判定腳本（Plan `docs/plans/2026-09-11-coverflow-h02-uitest-gate.md` §3.12）。

只用標準庫；必須能在 /usr/bin/python3（3.9）執行——不用 match 語句、不用 `X | Y` 型別聯集。

本檔為薄 facade：實作拆到同目錄下的
  `h02_gate_model.py`（常量與資料模型）、
  `h02_gate_parse.py`（GATE/SIG/PROBE 逐行解析、xcodebuild 日誌與 xcresult 解析）、
  `h02_gate_table.py`（(test, iteration, step) 判定表建構與格式化）、
  `h02_gate_rules.py`（V3／V4／V5 判定與 R4-C 結論）、
  `h02_gate_cli.py`（CLI 列印與 argparse 子命令），
本檔只 re-export，讓 `import h02_gate_eval as gate` 與
`python3 h02_gate_eval.py <subcommand>` 維持原樣可用。

輸入格式假設（本檔對計劃裡「未凍結細節」做的具體化，供實作與複審核對；細節分散在上述子模組的
docstring 裡，此處只列索引）：
  1. GATE token 語法與同行任意位置搜尋 —— 見 `h02_gate_parse.py`。
  2. FAIL 碼清單混合產品碼與探針 token —— 見 `h02_gate_model.py`。
  3. 真實 xcresult 失敗文字的前綴／XCTFail 包裝剝除規則 —— 見 `h02_gate_parse.py`。
  4. xcresulttool 節點樹 schema 與比對鍵 —— 見 `h02_gate_parse.py`。
  5. xcodebuild 日誌 started/passed/failed 配對與迭代歸屬 —— 見 `h02_gate_parse.py`。
  6. PROBE／UNTAGGED 未歸屬失敗訊息與迭代 invalid 判定 —— 見 `h02_gate_table.py`。
  7. GATE／SIG 交叉核對錯誤與 table_valid 的關係 —— 見 `h02_gate_table.py`／`h02_gate_rules.py`。
  8. 單一 device／test plan configuration、多個相符節點只取第一個 —— 見 `h02_gate_parse.py`。
  9. `C2-NA` 為資訊性代碼，絕不是失敗 —— 見 `h02_gate_model.py`。
  11. F1（`docs/plans/2026-09-13-coverflow-h02-fix4.md` §5.1／§5.2／§5.7 (7)）：`candidate`／`negative-control`
      子命令、R5-5 殺死簽名常量與「殺死須含 C2-STACK」條款、證據包 manifest 完整性 —— 見
      `h02_gate_model.py`／`h02_gate_rules.py`。
  10. R4-F 凍結表相符（只對 M0 確認性運行；F(step) 表與偏離記錄）—— 見 `h02_gate_model.py`／`h02_gate_rules.py`。
  12. R27 profile（`docs/plans/2026-09-13-coverflow-h02-fix4.md` §13 v5 提案第 5、13 項）：
      `R55_KILL_SIGNATURES` 降為唯讀歷史；場 0 實測基準以外部 JSON 檔 staging → 原子啟用為
      active profile；C.2 雙欄偏離報告（`active_profile_deviation` 參與結論、`historical_R55_deviation`
      僅報告）；無 active profile → C.2「無效」 —— 見 `h02_gate_r27_profile.py`／`h02_gate_rules.py`。
"""
from __future__ import annotations

import sys

from h02_gate_model import (
    C2_REGISTERED_STEPS,
    COVERFLOW_DIR,
    COVERFLOW_STRIP_FILE,
    Cell,
    DEFECT2_CODE,
    DEFECT2_EVIDENCE_STEPS,
    DEFECT3_CODES,
    DEFECT3_STEP,
    ENDPOINT_STEPS,
    FROZEN_ALLOWED_CODES,
    FROZEN_REGISTRATION,
    FailureEntry,
    GateInputError,
    GateLine,
    GateTable,
    INFORMATIONAL_CODES,
    IterationInfo,
    MANIFEST_SCHEMA,
    MANIFEST_SUFFIX,
    MUTANT_NAMES,
    POSITIVE_CONTROL_STEP,
    PRODUCT_CODES,
    R55_KILL_SIGNATURES,
    REQUIRED_KILL_STEPS,
    STEPS,
    TEST_LABELS,
    UI_TEST_CLASS,
)
from h02_gate_r27_profile import (
    ProfileError,
    R27_PROFILE_SCHEMA,
    R27Profile,
    active_profile_deviations,
    activate_r27,
    env_fingerprint_check,
    load_active_profile,
)
from h02_gate_parse import (
    _classify_gate_token,
    _collect_failure_texts,
    _GATE_TOKEN_RE,
    _index_test_case_nodes,
    _iterations_from_test_case_node,
    _match_test_case_node,
    _PROBE_GATE_TOKEN_RE,
    _PROBE_MSG_RE,
    _SIG_TOKEN_RE,
    _SWIFT_PREFIX_RE,
    _TESTCASE_LINE_RE,
    _XCTFAIL_WRAPPER,
    failure_message_body,
    load_xcresult_json,
    parse_failure_message,
    parse_gate_token,
    parse_log,
    parse_xcresult,
    strip_swift_prefix,
)
from h02_gate_table import (
    _build_iteration,
    _cell_repr,
    _cell_to_json,
    _iteration_to_json,
    build_table,
    format_table,
    table_to_json,
)
from h02_gate_rules import (
    _baseline_reasons,
    _cells,
    _codes,
    _defect3,
    _excludable,
    _is_c2_only_fail,
    _iteration_problems,
    _kill_outcome,
    _passes_endpoint_subcontract,
    _step_status,
    candidate_failures,
    evaluate_candidate,
    evaluate_evidence,
    evaluate_frozen_conformity,
    evaluate_negative_control,
    evaluate_v3,
    evaluate_v4,
    evaluate_v5,
    has_non_strip_coverflow_change,
    kill_outcome_with_defect2,
    kill_signature_has_defect2,
    mutant_kill_report,
    non_strip_coverflow_changes,
    table_valid,
    verdict,
)
from h02_gate_cli import (
    _build_argparser,
    _load_product_files,
    _print_candidate,
    _print_negative_control,
    _load_table,
    _load_text,
    _print_lines,
    _print_v3,
    _print_v4,
    _print_v5,
    _print_verdict,
    main,
)

__all__ = [
    "TEST_LABELS", "STEPS", "UI_TEST_CLASS", "PRODUCT_CODES", "INFORMATIONAL_CODES",
    "DEFECT3_CODES", "DEFECT2_CODE", "C2_REGISTERED_STEPS", "DEFECT2_EVIDENCE_STEPS",
    "DEFECT3_STEP", "POSITIVE_CONTROL_STEP", "ENDPOINT_STEPS", "FROZEN_REGISTRATION", "FROZEN_ALLOWED_CODES",
    "R55_KILL_SIGNATURES", "REQUIRED_KILL_STEPS", "MUTANT_NAMES", "MANIFEST_SCHEMA", "MANIFEST_SUFFIX",
    "COVERFLOW_DIR", "COVERFLOW_STRIP_FILE",
    "GateInputError", "GateLine", "FailureEntry", "Cell", "IterationInfo", "GateTable",
    "strip_swift_prefix", "failure_message_body", "parse_gate_token", "parse_failure_message",
    "parse_log", "load_xcresult_json", "parse_xcresult",
    "build_table", "format_table", "table_to_json",
    "table_valid", "evaluate_v3", "evaluate_v5", "evaluate_v4", "evaluate_frozen_conformity", "verdict",
    "evaluate_candidate", "evaluate_evidence", "evaluate_negative_control", "candidate_failures",
    "kill_outcome_with_defect2", "kill_signature_has_defect2", "mutant_kill_report",
    "has_non_strip_coverflow_change", "non_strip_coverflow_changes",
    "R27Profile", "ProfileError", "R27_PROFILE_SCHEMA",
    "activate_r27", "load_active_profile", "active_profile_deviations", "env_fingerprint_check",
    "main",
]

if __name__ == "__main__":
    sys.exit(main())
