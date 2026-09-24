"""H-02 閘門判定：R27 staging 產生器（`docs/plans/2026-09-13-coverflow-h02-fix4.md` §13 v5 提案
第 5、13 項；本檔為 F2b 任務新增，場 0 前必做——見 PREBUILD.md 「未定之處」最後一條）。

`h02_gate_r27_profile.py` 只提供 `stage_component`／`activate_r27` 兩個低階函式（純檔案 I/O＋
schema 驗證），場 0 當天沒有工具能把 `cf-m0-27`／M2／M3／`ui-T0′` 的運行產物（xcodebuild log＋
xcresult）轉成 staging JSON——照現況只能手寫，是全流程最容易出錯的一步。本檔提供純函數（無
argparse、無 print，方便單測）：

  - `build_m0_staging`：由已建好的 `GateTable`（沿用既有 `h02_gate_table.build_table`／
    `h02_gate_rules.table_valid` 的資料通路，不另寫一套 parser）逐步產出 sig_set／allowed_codes／
    stable／observations，並把 `evaluate_v3`／`evaluate_v5` 算出的 V5 陽性對照、缺陷 2、缺陷 3
    判定快取進 `checks`（§13 第 4 項「V5 陽性對照、缺陷 2、缺陷 3…不停」的機械化）——`profile check`
    只讀這份快取，不重算，滿足「沿用既有 evaluate_v3 的 V5 判定，不要另寫」。
  - `build_mutant_staging`：沿用既有 `kill_outcome_with_defect2`（含 C2-STACK 條款），另外把
    「`REQUIRED_KILL_STEPS` 在 baseline（M0）上是否有 PASS」（§13 第 4 項「required 集合已無
    baseline PASS，跑變異前就停」）也快取進 `checks`，供 `profile check` 讀。
  - `parse_ui_test_log`／`check_ui_test_coverage`：既有 UITests 的 xcodebuild 逐行輸出解析與
    17 條覆蓋率檢查（見模組下方對 `ui-T0.log` 真實格式的說明）。
  - `evaluate_scene0_check`／`write_scene0_check`：§7「場 0 的停止分支」與 §6 場 0 列的停止條件
    機械化，PASS／STOP 與逐條理由。
  - `evaluate_activate_gate`：§13 第 13 項「只有 scene0-check.json 為 PASS 且其記錄的 staging
    sha256 與磁碟現狀逐一相符才允許啟用」。
  - attempts 追蹤（`record_invalid_attempt`／`count_invalid_attempts`／`attempts_summary`）：
    §7 場 0 停止分支第 4 條「尚無有效批次時，同一 (tree, run-kind) 累積兩份無效即停；其他
    run-kind 插入不重置計數」。

ui-T0.log 真實格式（`~/Developer/bjork-h02-gate/ui-T0.log`，唯讀歷史運行，本檔解析器依此實測
撰寫）：`Test Case '-[AzathothsWhisperUITests.<Class> <method>]' started.` 起，
`... (passed|failed|skipped) (N seconds).` 收；三個 suite（`ShellUITests` 11＋`BatchUITests` 5＋
`BatchLiveUITests` 1，`BatchLiveUITests` 是獨立 class）共 17 條，與 §6「既有 UITests 不帶閘門
參數」條款相符。**設計取捨**：`stage-ui` 子命令雖也收 `--xcresult`（與其他 `stage-*` 子命令介面
一致、為未來擴充留口），但本檔目前**只解析 `--log`**——`.xcresult` 對 XCTSkip 的呈現在既有
`h02_gate_parse.py` 裡未覆蓋 SKIP 狀態，而 xcodebuild 逐行輸出的 started/passed/failed/skipped
記錄已足夠可靠地重建 17 條的 PASS／FAIL／SKIP 映射；`--xcresult` 只做存在性檢查。這是本檔的
設計決定（非計劃逐字明文），若日後需要交叉核對再擴充。
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Dict, FrozenSet, List, Mapping, Optional, Tuple

from h02_gate_model import (
    DEFECT3_CODES,
    DEFECT3_STEP,
    MUTANT_NAMES,
    REQUIRED_KILL_STEPS,
    STEPS,
    TEST_LABELS,
    GateTable,
)
from h02_gate_r27_profile import (
    ENV_FINGERPRINT_KEYS,
    ProfileError,
    R27_PROFILE_SCHEMA,
    _STAGING_COMPONENTS,
    load_staging_component,
    parse_env_fingerprint_text,
    sha256_bytes,  # re-export：CLI 以 pgen.sha256_bytes 取用（雜湊單一來源在 r27_profile）
    sha256_file,
)
from h02_gate_rules import (
    _cells,
    _codes,
    _step_status,
    evaluate_v3,
    evaluate_v5,
    kill_outcome_with_defect2,
)

STAGING_COMPONENTS: Tuple[str, ...] = _STAGING_COMPONENTS
_ATTEMPTS_FILENAME = "attempts.jsonl"
_FROZEN_LEDGER_FILENAME = "frozen.jsonl"

# §7 場 0 停止分支第 4 條：同一 (tree, run-kind) 累積兩份無效即停（終局）
ATTEMPT_CAP = 2
CHECK_FILENAME = "scene0-check.json"

_MANIFEST_REQUIRED_KEYS: Tuple[str, ...] = (
    "tree",
    "swift_hashlist_sha256",
    "cdhash",
    "os_build",
    "xcode_build",
    "sdk",
)
# 三鍵的單一來源在 h02_gate_r27_profile（§10 R13 的凍結契約，staging 期與 activate 期須同集合）
_ENV_FINGERPRINT_KEYS: Tuple[str, ...] = ENV_FINGERPRINT_KEYS

# 17 條（ShellUITests 11＋BatchUITests 5＋BatchLiveUITests 1）：逐一讀自真實歷史
# `~/Developer/bjork-h02-gate/ui-T0.log`（唯讀，本次任務只讀不改），非臆造。ui-T0′ 的唯一用途
# 是 W10／V6「與 ui-T0 逐條相同」的 active 比較源（§7、§6 場次人工守則），故須與 ui-T0 逐條同名。
UI_EXPECTED_TESTS: Tuple[str, ...] = (
    "BatchLiveUITests.testHiddenWindowDoesNotInterruptBatchFetch",
    "BatchUITests.testBatchColumnsLocalizeButStatusStaysEnglishInJapanese",
    "BatchUITests.testBatchColumnsLocalizeInTraditionalChinese",
    "BatchUITests.testBatchShellInEnglish",
    "BatchUITests.testImportAllShowsConfirmationWithExactWording",
    "BatchUITests.testPreviewPaneIsReadOnly",
    "ShellUITests.testColdStartInJapaneseLocalizesUIButNotMenus",
    "ShellUITests.testColdStartInTraditionalChinese",
    "ShellUITests.testHelpMenuOpensAboutModal",
    "ShellUITests.testLaunchShowsEditorShellAfterSplash",
    "ShellUITests.testQuitMenuItemTerminatesApp",
    "ShellUITests.testRedCloseButtonHidesWindowWithoutTerminating",
    "ShellUITests.testSettingsMenuOpensLanguageModal",
    "ShellUITests.testSettingsMenuOpensTokenModal",
    "ShellUITests.testSplashIsShownBeforeMainUI",
    "ShellUITests.testTokenFieldIsMasked",
    "ShellUITests.testWindowGeometryAndTitle",
)
assert len(UI_EXPECTED_TESTS) == 17, "ui-T0.log 實測為 17 條（Shell 11＋Batch 5＋BatchLive 1）"


class ProfileCliError(ProfileError):
    """`profile stage-*`／`check`／`activate`／`show` 的輸入或運行錯誤——CLI 對應 exit code 2。"""


# ---------------------------------------------------------------------------
# 雜湊／檔案路徑小工具
# ---------------------------------------------------------------------------


# 檔案雜湊的單一來源同樣在 h02_gate_r27_profile（本模組只 re-export，見 import 區）


def _staging_dir(root) -> Path:
    return Path(root) / "staging"


def staging_component_path(root, component: str) -> Path:
    return _staging_dir(root) / f"{component}.staging.json"


def check_file_path(root) -> Path:
    return _staging_dir(root) / CHECK_FILENAME


def _attempts_path(root) -> Path:
    return _staging_dir(root) / _ATTEMPTS_FILENAME


def _frozen_ledger_path(root) -> Path:
    return _staging_dir(root) / _FROZEN_LEDGER_FILENAME


def record_frozen_component(root, component: str) -> None:
    """凍結帳本（append-only）：staging 成功後記下該元件當下的 sha256。

    用途＝擋住「用文字編輯器改完 staging 再跑一次 `profile check` 重新祝福」這條路徑
    （§7 場 0 停止分支第 3 條的首份規則、§10 R10「不得跑到綠為止」）。**誠實標明**：帳本本身
    也可被一併竄改，與 `load_active_profile` 的既有口徑一致——作用是把成本墊高並留下可見絆線，
    不是密碼學防偽。"""
    path = _frozen_ledger_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = {"component": component, "sha256": sha256_file(staging_component_path(root, component))}
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n")


def read_frozen_ledger(root) -> Dict[str, str]:
    """回傳 {component: 凍結當下的 sha256}；同一元件重複出現時取第一筆（首份規則）。"""
    path = _frozen_ledger_path(root)
    result: Dict[str, str] = {}
    if not path.is_file():
        return result
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        component, digest = entry.get("component"), entry.get("sha256")
        if isinstance(component, str) and isinstance(digest, str) and component not in result:
            result[component] = digest
    return result


def frozen_ledger_mismatches(root) -> List[str]:
    """帳本與磁碟現檔逐一比對；不符或檔案消失即回一條理由。"""
    reasons: List[str] = []
    for component, digest in sorted(read_frozen_ledger(root).items()):
        path = staging_component_path(root, component)
        if not path.is_file():
            reasons.append(f"staging/{component}.staging.json 已不在磁碟（凍結帳本有記錄）")
            continue
        actual = sha256_file(path)
        if actual != digest:
            reasons.append(
                f"staging/{component}.staging.json 自凍結後被改動（違反首份規則；"
                f"凍結時 {digest}／目前 {actual}）"
            )
    return reasons


# ---------------------------------------------------------------------------
# tree-manifest／環境指紋
# ---------------------------------------------------------------------------


def load_tree_manifest(path) -> dict:
    """讀 `trees/manifests/<tree>.json`（§13 第 4 項「tree hash／CDHash／顯示設定從 manifest
    讀，不要讓人手打」）；缺必要欄位即拒絕。"""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError as e:
        raise ProfileCliError(f"讀取 tree-manifest 失敗（{path}）：{e}") from e
    try:
        data = json.loads(text)
    except ValueError as e:
        raise ProfileCliError(f"tree-manifest 不是合法 JSON（{path}）：{e}") from e
    if not isinstance(data, dict):
        raise ProfileCliError(f"tree-manifest 不是物件（{path}）")
    missing = [k for k in _MANIFEST_REQUIRED_KEYS if not isinstance(data.get(k), str) or not data[k]]
    if missing:
        raise ProfileCliError(f"tree-manifest 缺必要欄位 {missing}（{path}）")
    return data


def parse_run_env_fingerprint(text: str) -> Dict[str, str]:
    """`profile stage-*` 的 `--run-env-fingerprint`：語法解析共用
    `h02_gate_r27_profile.parse_env_fingerprint_text`（單一來源），本層只把 `ValueError`
    轉成 `ProfileCliError`。與既有 `v3`／`verdict` 的差別只在這裡是必要參數，不接受 None。"""
    try:
        return parse_env_fingerprint_text(text)
    except ValueError as e:
        raise ProfileCliError(str(e)) from e


def check_manifest_env_fingerprint(manifest: Mapping, run_env_fingerprint: Mapping[str, str], where: str) -> None:
    """§13 第 4 項：`--run-env-fingerprint` 三鍵須與 tree-manifest 記錄的 os_build／xcode_build／sdk
    逐字相符，不一致即拒絕（fail-closed，R13 的同一精神：環境漂移不得被靜默放行）。"""
    mismatches = [
        f"{key}：--run-env-fingerprint={run_env_fingerprint.get(key)!r} ≠ tree-manifest={manifest.get(key)!r}"
        for key in _ENV_FINGERPRINT_KEYS
        if run_env_fingerprint.get(key) != manifest.get(key)
    ]
    if mismatches:
        raise ProfileCliError(f"{where}: --run-env-fingerprint 與 --tree-manifest 不符：" + "；".join(mismatches))


# ---------------------------------------------------------------------------
# attempts.jsonl（§7 場 0 停止分支第 4 條）
# ---------------------------------------------------------------------------


def record_invalid_attempt(root, tree: str, run_kind: str, reasons: List[str], tree_hash: str = "") -> None:
    """記一筆無效嘗試。`tree` 是人給的標籤（"M0"），`tree_hash` 才是該次建置的唯一身分——
    §7 第 4 條的上限是**終局**的，若只按標籤分桶，重建同名樹後舊樹的殘留計數會把新樹永久鎖死
    （場 0 沒有覆蓋開關）。舊格式（無 `tree_hash`）的紀錄一律歸到標籤桶，保守計入。"""
    path = _attempts_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = {"tree": tree, "tree_hash": tree_hash, "run_kind": run_kind, "reasons": list(reasons)}
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n")


def _read_attempts(root) -> List[dict]:
    path = _attempts_path(root)
    if not path.is_file():
        return []
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            entries.append(json.loads(line))
    return entries


def attempt_bucket_key(tree: str, tree_hash: str) -> str:
    """無效嘗試的**桶鍵單一定義**（報告與聚合用）：有 tree_hash 就只看 hash（標籤純顯示，
    同一棵樹換個標籤仍同桶）；舊格式沒有 hash 時才退回標籤。"""
    return tree_hash if tree_hash else f"label:{tree or ''}"


def _entry_bucket_key(entry: Mapping) -> str:
    return attempt_bucket_key(entry.get("tree") or "", entry.get("tree_hash") or "")


def _entry_matches(entry: Mapping, tree: str, tree_hash: str) -> bool:
    """一筆紀錄是否屬於 `(tree, tree_hash)` 這棵樹。**保守**：只要任一端沒有 hash 就退回標籤
    比對——舊格式紀錄（無 hash）仍應擋住同標籤的 stage，寧可多擋不可少擋。"""
    entry_hash = entry.get("tree_hash") or ""
    if entry_hash and tree_hash:
        return entry_hash == tree_hash
    return (entry.get("tree") or "") == tree


def count_invalid_attempts(root, tree: str, run_kind: str, tree_hash: str = "") -> int:
    """同一棵樹、同一 run_kind 的無效次數（比對規則見 `_entry_matches`）。"""
    return sum(
        1
        for e in _read_attempts(root)
        if e.get("run_kind") == run_kind and _entry_matches(e, tree, tree_hash)
    )


def attempt_cap_reached(root, tree: str, run_kind: str, tree_hash: str = "") -> bool:
    """§7 第 4 條的**唯一**判定：該棵樹的該 run_kind 是否已達終局上限。CLI 的 stage 封頂與
    `profile check` 的停止理由都經過這裡，不得各自實作（前綴碰撞與標籤不同各讓兩端不一致過一次）。"""
    return count_invalid_attempts(root, tree, run_kind, tree_hash=tree_hash) >= ATTEMPT_CAP


def attempts_summary(root) -> Dict[Tuple[str, str], int]:
    """`{(桶鍵, run_kind): 次數}`；桶鍵見 `attempt_bucket_key`。"""
    counts: Dict[Tuple[str, str], int] = {}
    for entry in _read_attempts(root):
        key = (_entry_bucket_key(entry), entry.get("run_kind") or "")
        counts[key] = counts.get(key, 0) + 1
    return counts


def attempts_labels(root) -> Dict[str, List[str]]:
    """`{桶鍵: [出現過的 tree 標籤…]}`，只供報告文字用。"""
    labels: Dict[str, List[str]] = {}
    for entry in _read_attempts(root):
        key = _entry_bucket_key(entry)
        label = entry.get("tree") or ""
        seen = labels.setdefault(key, [])
        if label and label not in seen:
            seen.append(label)
    return labels


def format_attempt_bucket(bucket_key: str, labels: Optional[List[str]] = None) -> str:
    """報告用桶名：`M0@cccccccc`（hash 桶）或 `M0`（舊格式標籤桶）。比對一律用完整桶鍵。"""
    if bucket_key.startswith("label:"):
        return bucket_key[len("label:"):]
    shown = "／".join(labels or []) or "?"
    return f"{shown}@{bucket_key[:8]}"


# ---------------------------------------------------------------------------
# m0 staging（§13 第 4 項 (ii)）
# ---------------------------------------------------------------------------


def build_m0_staging(
    table: GateTable,
    iterations: int,
    manifest: Mapping,
    env_fingerprint: Mapping[str, str],
    evidence_hash: Optional[str],
    log_sha256: str,
) -> dict:
    """由已通過 `table_valid` 的 `GateTable` 產出 m0 staging 元件 JSON（呼叫端先驗有效性——本函式
    不重驗）。每步：`sig_set`＝該步觀察到的完整簽名集合（FAIL 格的 `cell.sig_set` 聯集，PASS
    只貢獻空集合）；`allowed_codes`＝各迭代產品碼投影的聯集，T4.s2 另併入 `DEFECT3_CODES`
    （比照 `FROZEN_ALLOWED_CODES` 由 `FROZEN_REGISTRATION` 推出的同一規則，只是底data換成
    「觀察到的」而非「凍結登記的」）；`stable`＝10 次結果一致（`_step_status` 非 INCONSISTENT）；
    `observations`＝逐迭代摘要（自由文字）。

    另把 `evaluate_v3`／`evaluate_v5`（`active_profile=None`：場 0 建立基準期間本就無 active
    profile）算出的 V5 陽性對照、缺陷 2、缺陷 3 判定快取進 `checks`——`profile check` 只讀這份
    快取，滿足「沿用既有 evaluate_v3 的 V5 判定，不要另寫」（`s2_verified=True` 只是為了讓
    `evaluate_v5` 跑完拿到 `positive_control_ok`／`endpoint_steps_ok`；本函式不消費它的
    `ok`／`reasons`，S2 已知點命中是場 0 (i) 段的獨立人工斷言，不在 (ii) 的 ×10 判內）。"""
    v3 = evaluate_v3(table, iterations)
    v5 = evaluate_v5(table, v3, s2_verified=True)

    steps: Dict[str, dict] = {}
    for label in table.tests:
        for step in STEPS[label]:
            key = (label, step)
            cells = _cells(table, key)
            status = _step_status(cells)
            fail_sig_set: FrozenSet[str] = frozenset()
            for cell in cells:
                if cell.kind == "FAIL":
                    fail_sig_set |= cell.sig_set
            allowed = _codes(fail_sig_set)
            if key == DEFECT3_STEP:
                allowed = allowed | DEFECT3_CODES
            observations = [
                f"iter {info.iteration}: "
                + ("PASS" if info.cells[step].kind == "PASS" else f"{info.cells[step].kind} {sorted(info.cells[step].sig_set)}")
                for info in table.iterations[label]
            ]
            steps[f"{label}.{step}"] = {
                "sig_set": sorted(fail_sig_set),
                "allowed_codes": sorted(allowed),
                "stable": status["status"] != "INCONSISTENT",
                "observations": observations,
            }

    data: Dict[str, object] = {
        "schema": R27_PROFILE_SCHEMA,
        "kind": "m0",
        "tree_hash": manifest["swift_hashlist_sha256"],
        "cdhash": manifest["cdhash"],
        # §10 R13 跨元件面：四份元件須在同一環境凍結（`_cross_component_env_reasons` 逐一比對）
        "tree": manifest["tree"],  # 人給的標籤；身分以 tree_hash 為準，標籤供報告與舊格式 attempts 比對
        "environment": {k: manifest[k] for k in ("os_build", "xcode_build", "sdk")},
        "steps": steps,
        "log_sha256": log_sha256,
        "checks": {
            "positive_control_ok": v5["positive_control_ok"],
            "endpoint_steps_ok": [list(k) for k in v5["endpoint_steps_ok"]],
            "defect3": dict(v3["defect3"]),
            "defect2_reproduced": v3["defect2_reproduced"],
            "defect2_steps": [[t, s] for t, s, _ in v3["defect2_steps"]],
        },
    }
    if env_fingerprint:
        data["env_fingerprint"] = dict(env_fingerprint)
    if manifest.get("display"):
        data["display"] = manifest["display"]
    if evidence_hash:
        data["evidence_hash"] = evidence_hash
    return data


# ---------------------------------------------------------------------------
# M2／M3 staging（§13 第 4 項 (iii)）
# ---------------------------------------------------------------------------


def baseline_sha256_matches_staged_m0(m0_staging: Mapping, baseline_log_sha256: str) -> bool:
    """§F2b：`--baseline-log` 必須就是被 staged 的那份 M0——以 m0 staging 記錄的 `log_sha256`
    比對呼叫端算好的 sha256（log 只讀一次即可同時比對與建表，見
    `h02_gate_profile_cli._read_log_once`）；不符即拒絕。

    （`evidence_hash` 是選用溯源欄位、不是每次都有，log 的 sha256 恆可算，故取它為唯一自動化
    比對依據；`evidence_hash` 只作人工旁證。）"""
    want = m0_staging.get("log_sha256")
    return bool(want) and baseline_log_sha256 == want


def build_mutant_staging(
    name: str,
    baseline_table: GateTable,
    mutant_table: GateTable,
    manifest: Mapping,
    evidence_hash: Optional[str],
) -> dict:
    """殺死判定沿用既有 `kill_outcome_with_defect2`（含 C2-STACK 條款）；另把「`REQUIRED_KILL_STEPS`
    在 baseline（M0）上是否有 PASS」（§13 第 4 項「required 集合已無 baseline PASS，跑變異前就
    停」）快取進 `checks`，供 `profile check` 讀（不在本函式內下「停止」結論——那是 `check` 的
    職責，本函式只負責誠實記錄觀察）。"""
    required = REQUIRED_KILL_STEPS[name]
    baseline_pass_steps = [key for key in required if _step_status(_cells(baseline_table, key))["status"] == "ALL_PASS"]

    killed: List[Tuple[str, str, object]] = []
    for label in TEST_LABELS:
        for step in STEPS[label]:
            ok, detail = kill_outcome_with_defect2((label, step), baseline_table, mutant_table)
            if ok:
                killed.append((label, step, detail))
    killed_keys = [(t, s) for t, s, _ in killed]
    kill_ok = any(key in killed_keys for key in required)

    data: Dict[str, object] = {
        "schema": R27_PROFILE_SCHEMA,
        "kind": name.lower(),
        "tree": manifest["tree"],  # 人給的標籤；身分以 tree_hash 為準，標籤供報告與舊格式 attempts 比對
        "environment": {k: manifest[k] for k in ("os_build", "xcode_build", "sdk")},
        "kill_signatures": {f"{t}.{s}": list(sig) for t, s, sig in killed},
        "tree_hash": manifest["swift_hashlist_sha256"],
        "cdhash": manifest["cdhash"],
        "checks": {
            "kill_ok": kill_ok,
            "required_steps": [list(k) for k in required],
            "required_baseline_pass_ok": bool(baseline_pass_steps),
            "required_baseline_pass_steps": [list(k) for k in baseline_pass_steps],
        },
    }
    if manifest.get("display"):
        data["display"] = manifest["display"]
    if evidence_hash:
        data["evidence_hash"] = evidence_hash
    return data


# ---------------------------------------------------------------------------
# ui-T0′ staging（§13 第 4 項 (iv)）
# ---------------------------------------------------------------------------

_UI_TEST_LINE_RE = re.compile(
    r"Test Case '-\[AzathothsWhisperUITests\.(?P<cls>[A-Za-z0-9_]+) (?P<method>[A-Za-z0-9_]+)\]' "
    r"(?P<verb>started|passed|failed|skipped)\b"
)
_UI_VERB_TO_OUTCOME = {"passed": "PASS", "failed": "FAIL", "skipped": "SKIP"}


def parse_ui_test_log(log_text: str) -> Dict[str, str]:
    """解析既有 UITests 的 xcodebuild 逐行輸出（見模組 docstring 對 `ui-T0.log` 真實格式的說明）；
    回傳 `{"<Class>.<method>": "PASS"|"FAIL"|"SKIP"}`。以最後一次終止行為準（`started` 本身不產出
    結果；沒有 `-test-iterations` 時每個識別碼只會出現一次終止行，後者覆蓋前者對單次運行無影響，
    對多次運行則保留「最後一次」語義，與既有 GATE 表格解析的「以終為準」精神一致）。"""
    results: Dict[str, str] = {}
    for match in _UI_TEST_LINE_RE.finditer(log_text):
        verb = match.group("verb")
        if verb == "started":
            continue
        results[f"{match.group('cls')}.{match.group('method')}"] = _UI_VERB_TO_OUTCOME[verb]
    return results


def check_ui_test_coverage(results: Mapping[str, str]) -> List[str]:
    """恰 17 條（Shell 11＋Batch 5＋BatchLive 1）否則列出缺／多；回傳空清單＝合格。"""
    found = set(results)
    expected = set(UI_EXPECTED_TESTS)
    missing = sorted(expected - found)
    extra = sorted(found - expected)
    reasons: List[str] = []
    if missing:
        reasons.append(f"缺 {len(missing)} 條：{missing}")
    if extra:
        reasons.append(f"多 {len(extra)} 條（非既有 17 條之一）：{extra}")
    if not missing and not extra and len(results) != 17:
        reasons.append(f"總數 {len(results)} ≠ 17（含重複識別碼）")
    return reasons


def build_ui_staging(results: Mapping[str, str], manifest: Mapping, evidence_hash: Optional[str]) -> dict:
    data: Dict[str, object] = {
        "schema": R27_PROFILE_SCHEMA,
        "kind": "ui_t0_prime",
        "results": dict(results),
        "tree": manifest["tree"],  # 人給的標籤；身分以 tree_hash 為準，標籤供報告與舊格式 attempts 比對
        "environment": {k: manifest[k] for k in ("os_build", "xcode_build", "sdk")},
        "tree_hash": manifest["swift_hashlist_sha256"],
        "cdhash": manifest["cdhash"],
    }
    if manifest.get("display"):
        data["display"] = manifest["display"]
    if evidence_hash:
        data["evidence_hash"] = evidence_hash
    return data


# ---------------------------------------------------------------------------
# profile check（§7 場 0 的停止分支 ＋ §6 場 0 列停止條件）
# ---------------------------------------------------------------------------


def _cross_component_env_reasons(root) -> List[str]:
    """§10 R13 的跨元件面：四份元件必須在同一環境凍結。各元件 staging 記錄的 `environment`
    （os_build／xcode_build／sdk，來自各自 tree-manifest）與 m0 的不一致即 STOP——場 0 是同一台
    機器同一場次，不一致代表其中一份是別的環境或別的時間點跑的。m0 未 staged 時不判（另有條件）。"""
    m0 = load_staging_component(root, "m0")
    if m0 is None:
        return []
    baseline = m0.get("environment")
    if not isinstance(baseline, dict) or not baseline:
        return []
    reasons: List[str] = []
    for component in STAGING_COMPONENTS:
        if component == "m0":
            continue
        data = load_staging_component(root, component)
        if data is None:
            continue
        env = data.get("environment")
        if not isinstance(env, dict) or not env:
            continue
        if env != baseline:
            reasons.append(
                f"staging/{component} 的環境指紋與 m0 不一致（m0 {baseline}／{component} {env}）"
            )
    return reasons


def _attempts_stop_reasons(root) -> List[str]:
    """§7 場 0 停止分支第 4 條（終局）：達 `ATTEMPT_CAP` 即停。

    兩條互補的判定，取聯集（去重）：
    1. **已 staged 的元件**用 `attempt_cap_reached` 對它自己那棵樹判（與 CLI 的 stage 封頂同一
       函式；其 `_entry_matches` 會把舊格式的無 hash 紀錄按標籤一併算進來）；
    2. **逐桶掃描**：任一桶達上限即報，只略過「明確屬於別棵樹」的 hash 桶（該 run_kind 已 staged
       且 hash 不同）。標籤桶（舊格式、身分不全）一律不略過——寧可多擋。
    重建同名樹（hash 已變）時 1 不會觸發、2 也會因 hash 不同而略過，新樹不被舊樹鎖死。"""
    reasons: List[str] = []
    seen = set()
    labels = attempts_labels(root)

    def add(bucket_key: str, run_kind: str, count: int) -> None:
        if (bucket_key, run_kind) in seen:
            return
        seen.add((bucket_key, run_kind))
        bucket = format_attempt_bucket(bucket_key, labels.get(bucket_key))
        reasons.append(f"{bucket}／{run_kind}：已累積 {count} 份無效嘗試（≥{ATTEMPT_CAP} 即停，終局）")

    for component in STAGING_COMPONENTS:
        staged = load_staging_component(root, component)
        if staged is None:
            continue
        tree, tree_hash = staged.get("tree") or "", staged.get("tree_hash") or ""
        if not tree and not tree_hash:
            continue  # 身分不全：留給下面的逐桶掃描保守處理
        if attempt_cap_reached(root, tree, component, tree_hash=tree_hash):
            count = count_invalid_attempts(root, tree, component, tree_hash=tree_hash)
            add(attempt_bucket_key(tree, tree_hash), component, count)

    for (bucket_key, run_kind), count in sorted(attempts_summary(root).items()):
        if count < ATTEMPT_CAP:
            continue
        staged = load_staging_component(root, run_kind) if run_kind in STAGING_COMPONENTS else None
        staged_hash = (staged or {}).get("tree_hash") or ""
        is_hash_bucket = not bucket_key.startswith("label:")
        if staged is not None and is_hash_bucket and staged_hash and bucket_key != staged_hash:
            continue  # 明確屬於別棵樹的桶
        add(bucket_key, run_kind, count)
    return reasons


def evaluate_scene0_check(root) -> dict:
    """§7 場 0 的停止分支＋§6 場 0 列停止條件；回傳 `{"result": "PASS"|"STOP", "reasons": [...],
    "checks": {...}}`。`checks` 的每個布林鍵都是各條停止條件的獨立觀察，供 `profile show`／人工
    逐條核對，也方便單測針對單一條件個別驗證。"""
    reasons: List[str] = []
    checks: Dict[str, object] = {}

    m0 = load_staging_component(root, "m0")
    checks["m0_staged"] = m0 is not None
    if m0 is None:
        reasons.append("m0 尚未 staged（無有效 R27 基準）")
    else:
        m0_checks = m0.get("checks", {}) if isinstance(m0.get("checks"), dict) else {}
        pc_ok = bool(m0_checks.get("positive_control_ok"))
        checks["positive_control_ok"] = pc_ok
        if not pc_ok:
            reasons.append("V5 陽性對照不成立（T2.s1 非 10/10 全契約 PASS）")

        defect2_ok = bool(m0_checks.get("defect2_reproduced"))
        checks["defect2_reproduced"] = defect2_ok
        if not defect2_ok:
            reasons.append("缺陷 2 在 M0 落定態未穩定重現（無步驟穩定出現 C2-STACK）")

        defect3 = m0_checks.get("defect3", {}) if isinstance(m0_checks.get("defect3"), dict) else {}
        defect3_ok = defect3.get("status") == "CAUGHT"
        checks["defect3_caught"] = defect3_ok
        if not defect3_ok:
            reasons.append(f"缺陷 3 未穩定抓到（T4.s2 狀態＝{defect3.get('status')}；需 C1／C3／C5 之一穩定出現）")

    for name in MUTANT_NAMES:
        component = name.lower()
        data = load_staging_component(root, component)
        checks[f"{component}_staged"] = data is not None
        if data is None:
            reasons.append(f"{name} 尚未 staged")
            continue
        mutant_checks = data.get("checks", {}) if isinstance(data.get("checks"), dict) else {}
        baseline_pass_ok = bool(mutant_checks.get("required_baseline_pass_ok"))
        checks[f"{component}_required_baseline_pass_ok"] = baseline_pass_ok
        if not baseline_pass_ok:
            reasons.append(f"{name}：required 集合在 M0 baseline 上皆無 PASS（跑變異前就該停）")
        kill_ok = bool(mutant_checks.get("kill_ok"))
        checks[f"{component}_kill_ok"] = kill_ok
        if not kill_ok:
            reasons.append(f"{name}：未在 required 集合內殺死（含 C2-STACK）")

    ui = load_staging_component(root, "ui_t0_prime")
    checks["ui_t0_prime_staged"] = ui is not None
    if ui is None:
        reasons.append("ui-T0′ 尚未 staged（17 條既有 UITests 未齊全凍結）")

    frozen_reasons = frozen_ledger_mismatches(root)
    checks["staging_unmodified_since_freeze"] = not frozen_reasons
    reasons.extend(frozen_reasons)

    env_reasons = _cross_component_env_reasons(root)
    checks["components_same_environment"] = not env_reasons
    reasons.extend(env_reasons)

    attempts_reasons = _attempts_stop_reasons(root)
    checks["attempts_stop_triggered"] = bool(attempts_reasons)
    reasons.extend(attempts_reasons)

    return {"result": "PASS" if not reasons else "STOP", "reasons": reasons, "checks": checks}


def write_scene0_check(root) -> dict:
    """寫 `staging/scene0-check.json`（含各 staging 檔目前的 sha256，供 `profile activate` 的
    「事後未被改動」比對）。"""
    result = evaluate_scene0_check(root)
    staging_sha256: Dict[str, str] = {}
    for component in STAGING_COMPONENTS:
        path = staging_component_path(root, component)
        if path.is_file():
            staging_sha256[component] = sha256_file(path)
    payload = {
        "schema": R27_PROFILE_SCHEMA,
        "result": result["result"],
        "reasons": result["reasons"],
        "checks": result["checks"],
        "staging_sha256": staging_sha256,
    }
    path = check_file_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    return payload


# ---------------------------------------------------------------------------
# profile activate 閘門（§13 第 13 項）
# ---------------------------------------------------------------------------


def evaluate_activate_gate(root) -> Tuple[bool, List[str]]:
    """啟用閘門，三道全過才准 `activate_r27`：

    1. **現場重算**場 0 停止條件（`evaluate_scene0_check`）必須 PASS——**不採信**
       `scene0-check.json` 記載的 result。第 4 輪對抗覆核實測：手寫一份 `result: "PASS"`＋
       照算的 `staging_sha256` 即可啟用一份真實停止條件為 STOP 的 profile；
    2. `profile check` 跑過且當時結論為 PASS（保留人工流程的留痕）；
    3. check 當時記錄的 staging sha256 與磁碟現檔逐一相符（擋「check 過後、activate 前」的手改）。
    """
    live = evaluate_scene0_check(root)
    if live["result"] != "PASS":
        return False, ["現場重算的場 0 停止條件不是 PASS（不採信 scene0-check.json 的記載）"] + [
            str(r) for r in live["reasons"]
        ]
    path = check_file_path(root)
    if not path.is_file():
        return False, ["尚未執行過 `profile check`（缺 staging/scene0-check.json）"]
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except ValueError as e:
        return False, [f"staging/{CHECK_FILENAME} 無法解析：{e}"]
    if payload.get("result") != "PASS":
        return False, [f"最近一次 `profile check` 結論＝{payload.get('result')!r}（須 PASS 才可啟用）"] + [
            str(r) for r in payload.get("reasons", [])
        ]
    recorded = payload.get("staging_sha256", {})
    if not isinstance(recorded, dict):
        return False, [f"staging/{CHECK_FILENAME} 的 staging_sha256 欄格式不對"]
    reasons: List[str] = []
    for component in STAGING_COMPONENTS:
        file_path = staging_component_path(root, component)
        if not file_path.is_file():
            reasons.append(f"staging/{component}.staging.json 已不在磁碟（check 通過後被移除？）")
            continue
        actual = sha256_file(file_path)
        want = recorded.get(component)
        if actual != want:
            reasons.append(
                f"staging/{component}.staging.json 自 `profile check` 後已變動"
                f"（check 時 {want}／目前 {actual}）"
            )
    return (not reasons), reasons
