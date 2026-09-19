"""H-02 閘門判定：`profile` 子命令群（argparse 介面＋列印，實作見 `h02_gate_profile_gen.py`）。

`docs/plans/2026-09-13-coverflow-h02-fix4.md` §13 v5 提案第 5、13 項（F2b 任務）：場 0 當天不得
手寫 staging JSON，六個子命令：

  - `profile stage-m0`：由 `cf-m0-27` 的 log／xcresult 產出 m0 staging（首份有效即凍結）。
  - `profile stage-mutant --name M2|M3`：由 M2／M3 的 log／xcresult（相對已 staged 的 M0 baseline）
    產出殺死簽名 staging（首份有效即凍結）。
  - `profile stage-ui`：由既有 UITests 的 log 產出 ui-T0′ staging（首份有效即凍結）。
  - `profile check`：§7 場 0 停止分支＋§6 場 0 列停止條件，輸出 PASS／STOP。
  - `profile activate --version V`：只有最近一次 `check` 為 PASS 且 staging 未變動才呼叫
    `activate_r27`。
  - `profile show`：印目前 staging／active 狀態、provenance、attempts 計數。

全部子命令共用 `--profile-dir`（預設與既有 `_add_profile_args` 相同的
`h02_gate_r27_profile._DEFAULT_R27_PROFILE_DIR`）。本檔的錯誤處理策略：`run_profile()` 統一攔截
`h02_gate_profile_gen.ProfileCliError`／`h02_gate_r27_profile.ProfileError`，印到 stderr、回傳
exit code 2，不需要 `h02_gate_cli.main()` 的外層 `except GateInputError` 再處理一次。
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import h02_gate_profile_gen as pgen
from h02_gate_model import GateInputError, MUTANT_NAMES, read_failure_message, read_text_file
from h02_gate_parse import load_xcresult_json
from h02_gate_r27_profile import (
    _DEFAULT_R27_PROFILE_DIR,
    ProfileError,
    format_provenance,
    activate_r27,
    load_active_profile,
    load_staging_component,
    stage_component,
)
from h02_gate_rules import table_valid
from h02_gate_table import build_table


# ---------------------------------------------------------------------------
# argparse 佈線
# ---------------------------------------------------------------------------


def _add_profile_dir_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--profile-dir",
        default=None,
        help=f"R27 profile 根目錄；不給則用預設路徑 {_DEFAULT_R27_PROFILE_DIR}",
    )


# §6 場 0 列的固定採樣次數：cf-m0-27 ×10、M2／M3 各 ×3（baseline 仍是那份 ×10）。
# 首份規則沒有覆蓋開關，故在 stage 端就擋住打錯的 --iterations。
_SCENE0_M0_ITERATIONS = 10
_SCENE0_MUTANT_ITERATIONS = 3

def add_profile_subparsers(sub) -> None:
    p_profile = sub.add_parser("profile", help="R27 staging 產生器與 profile 生命週期管理（F2b）")
    profile_sub = p_profile.add_subparsers(dest="profile_command", required=True)

    p_m0 = profile_sub.add_parser("stage-m0", help="由 cf-m0-27 的 log／xcresult 產出 m0 staging")
    _add_profile_dir_arg(p_m0)
    p_m0.add_argument("--log", required=True)
    p_m0.add_argument("--xcresult", required=True)
    p_m0.add_argument("--iterations", type=int, default=_SCENE0_M0_ITERATIONS)
    p_m0.add_argument("--tree-manifest", required=True)
    p_m0.add_argument("--run-env-fingerprint", required=True)
    p_m0.add_argument("--evidence-hash", default=None)

    p_mutant = profile_sub.add_parser("stage-mutant", help="由 M2／M3 的 log／xcresult 產出殺死簽名 staging")
    _add_profile_dir_arg(p_mutant)
    p_mutant.add_argument("--name", required=True, choices=list(MUTANT_NAMES))
    p_mutant.add_argument("--log", required=True)
    p_mutant.add_argument("--xcresult", required=True)
    p_mutant.add_argument("--iterations", type=int, default=_SCENE0_MUTANT_ITERATIONS)
    p_mutant.add_argument("--baseline-log", required=True)
    p_mutant.add_argument("--baseline-xcresult", required=True)
    p_mutant.add_argument("--baseline-iterations", type=int, default=_SCENE0_M0_ITERATIONS)
    p_mutant.add_argument("--tree-manifest", required=True)
    p_mutant.add_argument("--run-env-fingerprint", required=True)
    p_mutant.add_argument("--evidence-hash", default=None)

    p_ui = profile_sub.add_parser("stage-ui", help="由既有 UITests 的 log 產出 ui-T0′ staging")
    _add_profile_dir_arg(p_ui)
    p_ui.add_argument("--log", required=True)
    p_ui.add_argument("--xcresult", required=True, help="僅存在性檢查，見模組 docstring 的設計取捨")
    p_ui.add_argument("--tree-manifest", required=True)
    p_ui.add_argument("--evidence-hash", default=None)

    p_check = profile_sub.add_parser("check", help="§7 場 0 的停止分支＋§6 場 0 列停止條件")
    _add_profile_dir_arg(p_check)

    p_activate = profile_sub.add_parser("activate", help="只有最近一次 check 為 PASS 且 staging 未變動才啟用")
    _add_profile_dir_arg(p_activate)
    p_activate.add_argument("--version", required=True)

    p_show = profile_sub.add_parser("show", help="印目前 staging／active 狀態")
    _add_profile_dir_arg(p_show)



def _resolve_profile_dir(args) -> Path:
    return Path(args.profile_dir if args.profile_dir is not None else _DEFAULT_R27_PROFILE_DIR)


# ---------------------------------------------------------------------------
# 共用：讀表＋table_valid（沿用既有 `h02_gate_table.build_table`／`h02_gate_rules.table_valid`
# 資料通路，不另寫一套 parser——見 F2b 任務規格）
# ---------------------------------------------------------------------------


def _load_text(path: str) -> str:
    try:
        return read_text_file(path)
    except OSError as e:
        raise pgen.ProfileCliError(read_failure_message(path, e)) from e


def _load_xcresult(path: str) -> dict:
    try:
        return load_xcresult_json(path)
    except GateInputError as e:
        raise pgen.ProfileCliError(str(e)) from e


def _read_log_once(log_path: str):
    """回傳 `(text, sha256)`：log 只讀一次原始 bytes，同一份 bytes 同時算雜湊與 decode 成文字。
    xcodebuild 的 verbose log 可達數 MB，原本「建表讀一次、算雜湊再讀一次」是可省的重複 I/O。"""
    try:
        data = Path(log_path).read_bytes()
    except OSError as e:
        raise pgen.ProfileCliError(read_failure_message(log_path, e)) from e
    return data.decode("utf-8", errors="replace"), pgen.sha256_bytes(data)


def _build_and_validate_table_from_text(log_text: str, xcresult_path: str, iterations: int):
    """回傳 `(table, valid, reasons)`；log 文字由呼叫端提供（已讀過一次，見 `_read_log_once`），
    解析 xcresult 是這裡最貴的一步，所以呼叫端可以先做便宜的檢查（例如 baseline 的 sha256
    比對）再進來。"""
    table = build_table(log_text, _load_xcresult(xcresult_path), expected_iterations=iterations)
    valid, reasons = table_valid(table, iterations)
    return table, valid, reasons


def _build_and_validate_table(log_path: str, xcresult_path: str, iterations: int):
    """`_build_and_validate_table_from_text` 的便利包裝：自己讀 log，另回傳該次讀取算出的
    `log_sha256`（回 4 元組）。"""
    log_text, log_sha256 = _read_log_once(log_path)
    table, valid, reasons = _build_and_validate_table_from_text(log_text, xcresult_path, iterations)
    return table, valid, reasons, log_sha256


def _stage_or_invalid_attempt(root, component: str, tree: str, data: dict, tree_hash: str = "") -> None:
    """呼叫既有 `stage_component`（含它自身的 schema 驗證）；驗證失敗一併算作「無效嘗試」
    （例如變異運行技術上有效但整份 kill_signatures 為空，被 `parse_kill_component` 拒絕）——見
    `h02_gate_profile_gen` 模組 docstring 對「無效」判準的說明。"""
    try:
        stage_component(root, component, data)
    except ProfileError as e:
        pgen.record_invalid_attempt(root, tree, component, [str(e)], tree_hash=tree_hash)
        raise pgen.ProfileCliError(f"staging/{component} 驗證失敗（{e}），已記入 attempts.jsonl") from e
    # 首份規則的絆線：凍結當下的 sha256 進 append-only 帳本，`profile check` 會逐一比對現檔
    pgen.record_frozen_component(root, component)


def _refuse_if_attempt_cap_reached(root, tree: str, component: str, tree_hash: str = "") -> None:
    """§7 場 0 停止分支第 4 條是**終局**的：同一 (tree, run-kind) 累積到上限後不得再 stage
    （否則「跑到有效為止」就能把停止條件抹掉，§10 R10）。場 0 當下該做的是停下上報，不是重跑。"""
    count = pgen.count_invalid_attempts(root, tree, component, tree_hash=tree_hash)
    if count >= pgen.ATTEMPT_CAP:
        raise pgen.ProfileCliError(
            f"stage 拒絕：{tree}／{component} 已累積 {count} 份無效嘗試（≥{pgen.ATTEMPT_CAP} 即停，終局）；"
            "場 0 應在此停止並上報「環境前置未成立／待使用者裁決」，不得繼續重跑"
        )


def _refuse_if_already_staged(root, component: str) -> None:
    if load_staging_component(root, component) is not None:
        raise pgen.ProfileCliError(
            f"staging/{component} 已存在（首份規則，§7 場 0 停止分支第 3 條：首份有效未抓到缺陷即停，"
            "禁止以第二份有效重抽），無覆蓋開關"
        )


# ---------------------------------------------------------------------------
# 子命令實作
# ---------------------------------------------------------------------------


def _cmd_stage_m0(args) -> int:
    root = _resolve_profile_dir(args)
    if args.iterations != _SCENE0_M0_ITERATIONS:
        raise pgen.ProfileCliError(
            f"stage-m0 拒絕：§6 場 0 列要求 cf-m0-27 ×{_SCENE0_M0_ITERATIONS}，實得 --iterations "
            f"{args.iterations}（首份規則無覆蓋開關，欠採樣的基準一旦凍結就改不回來）"
        )
    _refuse_if_already_staged(root, "m0")
    manifest = pgen.load_tree_manifest(args.tree_manifest)
    tree = manifest["tree"]
    _refuse_if_attempt_cap_reached(root, tree, "m0", manifest["swift_hashlist_sha256"])
    run_env = pgen.parse_run_env_fingerprint(args.run_env_fingerprint)
    pgen.check_manifest_env_fingerprint(manifest, run_env, "stage-m0")

    table, valid, reasons, log_sha256 = _build_and_validate_table(args.log, args.xcresult, args.iterations)
    if not valid:
        pgen.record_invalid_attempt(root, tree, "m0", reasons, tree_hash=manifest["swift_hashlist_sha256"])
        print("stage-m0：運行無效，已記入 attempts.jsonl：", file=sys.stderr)
        for r in reasons:
            print(f"  - {r}", file=sys.stderr)
        return 2

    data = pgen.build_m0_staging(table, args.iterations, manifest, run_env, args.evidence_hash, log_sha256)
    _stage_or_invalid_attempt(root, "m0", tree, data, manifest["swift_hashlist_sha256"])
    print(f"已凍結 staging/m0（tree={tree} tree_hash={data['tree_hash']} cdhash={data['cdhash']}）")
    return 0


def _cmd_stage_mutant(args) -> int:
    root = _resolve_profile_dir(args)
    name = args.name
    component = name.lower()
    if args.iterations != _SCENE0_MUTANT_ITERATIONS or args.baseline_iterations != _SCENE0_M0_ITERATIONS:
        raise pgen.ProfileCliError(
            f"stage-mutant 拒絕：§6 場 0 列要求變異 ×{_SCENE0_MUTANT_ITERATIONS}、baseline ×"
            f"{_SCENE0_M0_ITERATIONS}，實得 --iterations {args.iterations}／--baseline-iterations "
            f"{args.baseline_iterations}"
        )
    _refuse_if_already_staged(root, component)

    m0_staging = load_staging_component(root, "m0")
    if m0_staging is None:
        raise pgen.ProfileCliError("stage-mutant 拒絕：staging/m0 尚不存在，必須先 stage-m0")

    manifest = pgen.load_tree_manifest(args.tree_manifest)
    tree = manifest["tree"]
    _refuse_if_attempt_cap_reached(root, tree, component, manifest["swift_hashlist_sha256"])
    run_env = pgen.parse_run_env_fingerprint(args.run_env_fingerprint)
    pgen.check_manifest_env_fingerprint(manifest, run_env, f"stage-mutant --name {name}")

    # baseline log 只讀一次；**先**用該次讀取算出的 sha256 做便宜的身分比對，不符就直接拒絕，
    # 不必先付出解析 xcresult／建表的成本（Round 2 回歸檢查指出的順序問題）
    baseline_text, baseline_log_sha256 = _read_log_once(args.baseline_log)
    if not pgen.baseline_sha256_matches_staged_m0(m0_staging, baseline_log_sha256):
        raise pgen.ProfileCliError(
            "stage-mutant 拒絕：--baseline-log 與 staging/m0 記錄的來源 log sha256 不符"
            "（baseline 必須就是被 staged 的那份 M0）"
        )

    baseline_table, baseline_valid, baseline_reasons = _build_and_validate_table_from_text(
        baseline_text, args.baseline_xcresult, args.baseline_iterations
    )
    if not baseline_valid:
        raise pgen.ProfileCliError(
            "stage-mutant 拒絕：--baseline-log／--baseline-xcresult 本身不是有效運行：" + "；".join(baseline_reasons)
        )

    mutant_table, mutant_valid, mutant_reasons, _ = _build_and_validate_table(args.log, args.xcresult, args.iterations)
    if not mutant_valid:
        pgen.record_invalid_attempt(root, tree, component, mutant_reasons, tree_hash=manifest["swift_hashlist_sha256"])
        print(f"stage-mutant {name}：運行無效，已記入 attempts.jsonl：", file=sys.stderr)
        for r in mutant_reasons:
            print(f"  - {r}", file=sys.stderr)
        return 2

    data = pgen.build_mutant_staging(name, baseline_table, mutant_table, manifest, args.evidence_hash)
    _stage_or_invalid_attempt(root, component, tree, data, manifest["swift_hashlist_sha256"])
    print(f"已凍結 staging/{component}（kill_ok={data['checks']['kill_ok']}）")
    return 0


def _cmd_stage_ui(args) -> int:
    root = _resolve_profile_dir(args)
    _refuse_if_already_staged(root, "ui_t0_prime")
    manifest = pgen.load_tree_manifest(args.tree_manifest)
    tree = manifest["tree"]
    _refuse_if_attempt_cap_reached(root, tree, "ui_t0_prime", manifest["swift_hashlist_sha256"])

    if not (Path(args.xcresult).is_file() or Path(args.xcresult).is_dir()):
        raise pgen.ProfileCliError(f"stage-ui 拒絕：--xcresult 不存在（{args.xcresult}）")

    log_text = _load_text(args.log)
    results = pgen.parse_ui_test_log(log_text)
    reasons = pgen.check_ui_test_coverage(results)
    if reasons:
        pgen.record_invalid_attempt(root, tree, "ui_t0_prime", reasons, tree_hash=manifest["swift_hashlist_sha256"])
        print("stage-ui：條數不是 17，已記入 attempts.jsonl：", file=sys.stderr)
        for r in reasons:
            print(f"  - {r}", file=sys.stderr)
        return 2

    data = pgen.build_ui_staging(results, manifest, args.evidence_hash)
    _stage_or_invalid_attempt(root, "ui_t0_prime", tree, data, manifest["swift_hashlist_sha256"])
    print(f"已凍結 staging/ui_t0_prime（17 條：{sum(1 for v in results.values() if v == 'PASS')} PASS）")
    return 0


def _cmd_check(args) -> int:
    root = _resolve_profile_dir(args)
    payload = pgen.write_scene0_check(root)
    print(f"== 場 0 check：{payload['result']} ==")
    for r in payload["reasons"]:
        print(f"  - {r}")
    print(f"（已寫 staging/{pgen.CHECK_FILENAME}）")
    return 0 if payload["result"] == "PASS" else 1


def _cmd_activate(args) -> int:
    root = _resolve_profile_dir(args)
    ok, reasons = pgen.evaluate_activate_gate(root)
    if not ok:
        print("啟用拒絕：", file=sys.stderr)
        for r in reasons:
            print(f"  - {r}", file=sys.stderr)
        return 2
    try:
        profile = activate_r27(root, version=args.version)
    except ProfileError as e:
        raise pgen.ProfileCliError(f"啟用拒絕：{e}") from e
    print("已啟用 R27 profile " + format_provenance(profile.provenance()))
    return 0


def _cmd_show(args) -> int:
    root = _resolve_profile_dir(args)
    print(f"profile-dir: {root}")

    print("== active ==")
    active = load_active_profile(root)
    if active is None:
        print("  (無)")
    else:
        print("  " + format_provenance(active.provenance(), include_evidence=True))

    print("== staging ==")
    for component in pgen.STAGING_COMPONENTS:
        data = load_staging_component(root, component)
        state = "已凍結" if data is not None else "未 staged"
        print(f"  {component}: {state}")
        if data is not None and data.get("evidence_hash"):
            print(f"    evidence_hash={data['evidence_hash']}")

    check_path = pgen.check_file_path(root)
    if check_path.is_file():
        payload = json.loads(check_path.read_text(encoding="utf-8"))
        print(f"== 最近一次 check：{payload.get('result')} ==")
    else:
        print("== 尚未執行過 profile check ==")

    print("== attempts 計數（(tree@hash, run_kind): 次數）==")
    for (label, tree_hash, run_kind), count in sorted(pgen.attempts_summary(root).items()):
        print(f"  ({pgen.format_attempt_bucket(label, tree_hash)}, {run_kind}): {count}")
    return 0


_HANDLERS = {
    "stage-m0": _cmd_stage_m0,
    "stage-mutant": _cmd_stage_mutant,
    "stage-ui": _cmd_stage_ui,
    "check": _cmd_check,
    "activate": _cmd_activate,
    "show": _cmd_show,
}


def run_profile(args) -> int:
    handler = _HANDLERS[args.profile_command]
    try:
        return handler(args)
    except ProfileError as e:  # ProfileCliError 繼承 ProfileError，一個 except 就夠
        print(f"錯誤：{e}", file=sys.stderr)
        return 2
