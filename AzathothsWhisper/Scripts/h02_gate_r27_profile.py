"""H-02 閘門判定：R27 profile —— 場 0 實測基準的 staging → 原子啟用
（`docs/plans/2026-09-13-coverflow-h02-fix4.md` §13 v5 提案第 5、13 項）。

`R55_KILL_SIGNATURES`（`h02_gate_model.py`）在 macOS 27 環境漂移後降為唯讀歷史，不再參與 C.2
結論。本檔提供取代它的機制，三份基準分開存放：

  - M0：每步的完整簽名集合與允許碼、哪些步驟 ×10 穩定／不穩定及其觀察集合；
  - M2／M3：各自的殺死簽名；
  - ui-T0′：作為 W10（既有 UITests 17 條）的 active 比較源。

資料來自場 0 實跑，不寫死在原始碼：以外部 JSON 檔（帶 schema／version 欄）載入，路徑由呼叫端
（CLI）決定，本檔對「檔案系統佈局」以外的一切保持純函數，方便單測。

staging → 原子啟用：場 0 全程只寫 staging；`load_active_profile` 只讀 `active/profile.json`，
從不讀 staging，因此建立中的 R27 永遠不會被誤當成 active（第 13 項）。M0／M2／M3／ui-T0′
四者皆有效才允許 `activate_r27` 寫入；任一缺失或格式不對，整體拒絕、不寫任何 active 檔
（partial content 即拒絕啟用）；寫入採「一份含四者 hash 的 manifest」單次寫入（write-temp +
`os.replace`，同檔系統內原子換檔），避免只換成功一半。
"""
from __future__ import annotations

import hashlib
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, FrozenSet, List, Mapping, Optional, Tuple

R27_PROFILE_SCHEMA = 1

_STAGING_COMPONENTS: Tuple[str, ...] = ("m0", "m2", "m3", "ui_t0_prime")
_ACTIVE_DIRNAME = "active"
_STAGING_DIRNAME = "staging"
_ACTIVE_FILENAME = "profile.json"
_UI_T0_PRIME_OUTCOMES: FrozenSet[str] = frozenset({"PASS", "FAIL", "SKIP"})


class ProfileError(Exception):
    """R27 profile 檔格式或啟用條件不成立——呼叫端（CLI）對應無效／拒絕啟用。"""


@dataclass(frozen=True)
class M0StepProfile:
    """M0 單一步驟的登記：×10 完整簽名集合、允許碼、是否穩定、觀察集合（自由文字，供報告）。"""

    sig_set: FrozenSet[str]
    allowed_codes: FrozenSet[str]
    stable: bool
    observations: Tuple[str, ...] = ()


@dataclass(frozen=True)
class R27Profile:
    """已啟用的 R27 profile：三份基準（M0／M2＋M3／ui-T0′）＋來源身分（tree hash／CDHash）。"""

    schema: int
    version: str
    tree_hash: str
    cdhash: str
    m0: Dict[Tuple[str, str], M0StepProfile]
    m2_kill: Dict[Tuple[str, str], FrozenSet[str]]
    m3_kill: Dict[Tuple[str, str], FrozenSet[str]]
    ui_t0_prime: Dict[str, str]

    def kill_signatures(self, name: str) -> Dict[Tuple[str, str], FrozenSet[str]]:
        if name == "M2":
            return self.m2_kill
        if name == "M3":
            return self.m3_kill
        raise ProfileError(f"未知的變異名稱：{name!r}")


def _split_step_key(key: str, where: str) -> Tuple[str, str]:
    if not isinstance(key, str) or "." not in key:
        raise ProfileError(f"{where}: 步驟鍵須為 '<test>.<step>' 形式，實得 {key!r}")
    label, step = key.split(".", 1)
    if not label or not step:
        raise ProfileError(f"{where}: 步驟鍵不合法（{key!r}）")
    return label, step


def _require_str(data: Mapping, key: str, where: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value:
        raise ProfileError(f"{where}: 缺必要欄位 {key}")
    return value


def _require_schema(data: Mapping, where: str) -> None:
    if not isinstance(data, dict):
        raise ProfileError(f"{where}: 不是物件")
    if data.get("schema") != R27_PROFILE_SCHEMA:
        raise ProfileError(f"{where}: schema 應為 {R27_PROFILE_SCHEMA}，實得 {data.get('schema')!r}")


# ---------------------------------------------------------------------------
# staging component 解析：每份獨立 schema，寫入前與讀出後都跑，防止半成品騙過 hash 比對。
# ---------------------------------------------------------------------------


def parse_m0_component(data: Mapping) -> Dict[Tuple[str, str], M0StepProfile]:
    where = "m0"
    _require_schema(data, where)
    if data.get("kind") != "m0":
        raise ProfileError(f"{where}: kind 應為 'm0'")
    steps = data.get("steps")
    if not isinstance(steps, dict) or not steps:
        raise ProfileError(f"{where}: 缺 steps")
    result: Dict[Tuple[str, str], M0StepProfile] = {}
    for key, entry in steps.items():
        step_key = _split_step_key(key, where)
        if not isinstance(entry, dict):
            raise ProfileError(f"{where}.{key}: 條目不是物件")
        sig_set, allowed = entry.get("sig_set"), entry.get("allowed_codes")
        stable, observations = entry.get("stable"), entry.get("observations", [])
        if not isinstance(sig_set, list):
            raise ProfileError(f"{where}.{key}: 缺 sig_set（須為陣列）")
        if not isinstance(allowed, list):
            raise ProfileError(f"{where}.{key}: 缺 allowed_codes（須為陣列）")
        if not isinstance(stable, bool):
            raise ProfileError(f"{where}.{key}: stable 須為 bool")
        if not isinstance(observations, list):
            raise ProfileError(f"{where}.{key}: observations 須為陣列")
        result[step_key] = M0StepProfile(
            sig_set=frozenset(sig_set),
            allowed_codes=frozenset(allowed),
            stable=stable,
            observations=tuple(observations),
        )
    return result


def parse_kill_component(data: Mapping, name: str) -> Dict[Tuple[str, str], FrozenSet[str]]:
    kind = name.lower()
    _require_schema(data, kind)
    if data.get("kind") != kind:
        raise ProfileError(f"{kind}: kind 應為 {kind!r}")
    sigs = data.get("kill_signatures")
    if not isinstance(sigs, dict) or not sigs:
        raise ProfileError(f"{kind}: 缺 kill_signatures")
    result: Dict[Tuple[str, str], FrozenSet[str]] = {}
    for key, values in sigs.items():
        step_key = _split_step_key(key, kind)
        if not isinstance(values, list) or not values:
            raise ProfileError(f"{kind}.{key}: 簽名須為非空陣列")
        result[step_key] = frozenset(values)
    return result


def parse_ui_t0_prime_component(data: Mapping) -> Dict[str, str]:
    where = "ui_t0_prime"
    _require_schema(data, where)
    if data.get("kind") != where:
        raise ProfileError(f"{where}: kind 應為 'ui_t0_prime'")
    results = data.get("results")
    if not isinstance(results, dict) or not results:
        raise ProfileError(f"{where}: 缺 results")
    for test_name, outcome in results.items():
        if not isinstance(test_name, str) or not test_name:
            raise ProfileError(f"{where}: 測試名稱不合法（{test_name!r}）")
        if outcome not in _UI_T0_PRIME_OUTCOMES:
            raise ProfileError(f"{where}.{test_name}: outcome 須為 PASS／FAIL／SKIP，實得 {outcome!r}")
    return dict(results)


_COMPONENT_PARSERS = {
    "m0": parse_m0_component,
    "m2": lambda data: parse_kill_component(data, "M2"),
    "m3": lambda data: parse_kill_component(data, "M3"),
    "ui_t0_prime": parse_ui_t0_prime_component,
}


# ---------------------------------------------------------------------------
# staging 讀寫（§13 第 13 項：場 0 全程只寫 staging）
# ---------------------------------------------------------------------------


def _staging_path(root: Path, component: str) -> Path:
    if component not in _STAGING_COMPONENTS:
        raise ProfileError(f"未知的 staging 元件：{component!r}")
    return Path(root) / _STAGING_DIRNAME / f"{component}.staging.json"


def stage_component(root: Path, component: str, data: Mapping) -> Path:
    """寫入單一 staging 元件；先跑該元件自身 schema 驗證，格式不對就拒寫（不留半成品檔）。"""
    if component not in _COMPONENT_PARSERS:
        raise ProfileError(f"未知的 staging 元件：{component!r}")
    _COMPONENT_PARSERS[component](data)
    path = _staging_path(root, component)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(dict(data), ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    return path


def load_staging_component(root: Path, component: str) -> Optional[dict]:
    path = _staging_path(root, component)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except ValueError as e:
        raise ProfileError(f"staging/{component}: 無法解析（{e}）") from e


def _hash_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _canonical_bytes(data: Mapping) -> bytes:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8")


# ---------------------------------------------------------------------------
# 原子啟用（§13 第 13 項）
# ---------------------------------------------------------------------------


def activate_r27(root: Path, version: str) -> R27Profile:
    """M0／M2／M3／ui-T0′ 四者皆有效且格式相符才允許啟用；任一缺失或格式不對 → 整體拒絕，
    不寫任何 active 檔（保留既有 staging 證據）。成功時把四者 hash 與合併後的 profile 併進
    「一份 manifest」，以 write-temp + `os.replace` 單次原子寫入 `active/profile.json`。"""
    root = Path(root)
    staged: Dict[str, dict] = {}
    missing = [c for c in _STAGING_COMPONENTS if load_staging_component(root, c) is None]
    if missing:
        raise ProfileError(f"啟用拒絕：staging 缺元件 {missing}（M0／M2／M3／ui-T0′ 四者皆須有效）")

    parsed: Dict[str, object] = {}
    hashes: Dict[str, str] = {}
    for component in _STAGING_COMPONENTS:
        raw = load_staging_component(root, component)
        staged[component] = raw
        try:
            parsed[component] = _COMPONENT_PARSERS[component](raw)
        except ProfileError as e:
            raise ProfileError(f"啟用拒絕：staging/{component} 無效（{e}）") from e
        hashes[component] = _hash_bytes(_canonical_bytes(raw))

    tree_hash = staged["m0"].get("tree_hash", "")
    cdhash = staged["m0"].get("cdhash", "")
    if not tree_hash or not cdhash:
        raise ProfileError("啟用拒絕：staging/m0 缺 tree_hash／cdhash")

    profile_payload = {
        "schema": R27_PROFILE_SCHEMA,
        "version": version,
        "tree_hash": tree_hash,
        "cdhash": cdhash,
        "m0": staged["m0"]["steps"],
        "m2": staged["m2"]["kill_signatures"],
        "m3": staged["m3"]["kill_signatures"],
        "ui_t0_prime": staged["ui_t0_prime"]["results"],
    }
    active_payload = {
        "schema": R27_PROFILE_SCHEMA,
        "active_profile": "R27",
        "component_hashes": hashes,
        "profile": profile_payload,
    }

    active_dir = root / _ACTIVE_DIRNAME
    active_dir.mkdir(parents=True, exist_ok=True)
    target = active_dir / _ACTIVE_FILENAME
    tmp = active_dir / f".{_ACTIVE_FILENAME}.tmp-{os.getpid()}"
    tmp.write_text(json.dumps(active_payload, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    os.replace(tmp, target)  # 同檔系統內原子換檔：中途中斷不會留下半成品 active 檔

    return R27Profile(
        schema=R27_PROFILE_SCHEMA,
        version=version,
        tree_hash=tree_hash,
        cdhash=cdhash,
        m0=parsed["m0"],
        m2_kill=parsed["m2"],
        m3_kill=parsed["m3"],
        ui_t0_prime=parsed["ui_t0_prime"],
    )


def load_active_profile(root: Path) -> Optional[R27Profile]:
    """只讀 `active/profile.json`；不存在＝尚無 active profile（回 None，不是錯誤）。staging
    中的元件無論多完整都不會被這個函式看見——建立中的 R27 永遠不會被誤當成 active（第 13 項）。"""
    target = Path(root) / _ACTIVE_DIRNAME / _ACTIVE_FILENAME
    if not target.is_file():
        return None
    try:
        payload = json.loads(target.read_text(encoding="utf-8"))
    except ValueError as e:
        raise ProfileError(f"active/{_ACTIVE_FILENAME}: 無法解析（{e}）") from e
    if not isinstance(payload, dict) or payload.get("active_profile") != "R27":
        raise ProfileError(f"active/{_ACTIVE_FILENAME}: active_profile 應為 'R27'")
    profile = payload.get("profile")
    if not isinstance(profile, dict):
        raise ProfileError(f"active/{_ACTIVE_FILENAME}: 缺 profile")
    _require_schema(profile, "active.profile")
    m0 = parse_m0_component({"schema": R27_PROFILE_SCHEMA, "kind": "m0", "steps": profile.get("m0")})
    m2 = parse_kill_component(
        {"schema": R27_PROFILE_SCHEMA, "kind": "m2", "kill_signatures": profile.get("m2")}, "M2"
    )
    m3 = parse_kill_component(
        {"schema": R27_PROFILE_SCHEMA, "kind": "m3", "kill_signatures": profile.get("m3")}, "M3"
    )
    ui_t0_prime = parse_ui_t0_prime_component(
        {"schema": R27_PROFILE_SCHEMA, "kind": "ui_t0_prime", "results": profile.get("ui_t0_prime")}
    )
    return R27Profile(
        schema=profile["schema"],
        version=_require_str(profile, "version", "active.profile"),
        tree_hash=_require_str(profile, "tree_hash", "active.profile"),
        cdhash=_require_str(profile, "cdhash", "active.profile"),
        m0=m0,
        m2_kill=m2,
        m3_kill=m3,
        ui_t0_prime=ui_t0_prime,
    )


# ---------------------------------------------------------------------------
# C.2 用：active profile 對殺死簽名的偏離比對（雙欄報告的 active 半；歷史半見
# `h02_gate_rules._historical_r55_deviations`，第 4、5 項）
# ---------------------------------------------------------------------------


def active_profile_deviations(name: str, killed: List[Tuple[str, str, object]], profile: R27Profile) -> List[str]:
    """殺死步驟的完整簽名集合與 active R27 profile 逐字比對；不同或未登記 → 偏離。"""
    expected = profile.kill_signatures(name)
    deviations: List[str] = []
    for label, step, signature in killed:
        want = expected.get((label, step))
        got = frozenset(signature)  # type: ignore[arg-type]
        if want is None:
            deviations.append(f"{name} {label}.{step}：active R27 未登記的殺死步驟，簽名 {sorted(got)}")
        elif got != want:
            deviations.append(f"{name} {label}.{step}：簽名 {sorted(got)} ≠ active R27 {sorted(want)}")
    return deviations
