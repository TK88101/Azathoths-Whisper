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
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, FrozenSet, List, Mapping, Optional, Tuple

from h02_gate_model import STEPS

R27_PROFILE_SCHEMA = 1

_STAGING_COMPONENTS: Tuple[str, ...] = ("m0", "m2", "m3", "ui_t0_prime")
_ACTIVE_DIRNAME = "active"
_STAGING_DIRNAME = "staging"
_ACTIVE_FILENAME = "profile.json"
_UI_T0_PRIME_OUTCOMES: FrozenSet[str] = frozenset({"PASS", "FAIL", "SKIP"})

# v5 §10 R13：環境指紋（環境再度漂移時，判定器須能拒絕誤用「別的 OS 凍結的 profile」）。
# 可選——附了就必須三鍵齊全；缺席＝該 profile 未記錄，比對時報 "unknown"（見 `env_fingerprint_check`）。
_ENV_FINGERPRINT_KEYS: Tuple[str, ...] = ("os_build", "xcode_build", "sdk")

# §13 第 5 項「M0 每步登記」：activate_r27 要求 staging/m0 的 steps 鍵集合恰為這 9 個
# （由 STEPS 導出，不寫死），缺一即拒絕啟用——防止一份只登記 1 步的殘缺 profile 讓其餘
# 8 步永遠不被 R4-F 檢查（見 `activate_r27` 與 `test_h02_gate_r27_profile.py` 的
# `test_m0_missing_steps_refuses_activation`）。
_ALL_M0_STEP_KEYS: FrozenSet[Tuple[str, str]] = frozenset(
    (label, step) for label, steps in STEPS.items() for step in steps
)


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
    # v5 §10 R13：{} ＝本份 profile 未記錄環境指紋（見 `env_fingerprint_check`）
    env_fingerprint: Dict[str, str] = field(default_factory=dict)

    def kill_signatures(self, name: str) -> Dict[Tuple[str, str], FrozenSet[str]]:
        if name == "M2":
            return self.m2_kill
        if name == "M3":
            return self.m3_kill
        raise ProfileError(f"未知的變異名稱：{name!r}")

    def provenance(self) -> Dict[str, object]:
        """溯源資訊（version／tree_hash／cdhash／env_fingerprint），供報告輸出用。

        刻意決定（主線程 2026-09-18 拍板，見 `docs/plans/2026-09-13-coverflow-h02-fix4.md`）：
        這些欄位記的是場 0 **基準樹**（M0 運行時的那棵樹）的身分，不是「本次受評運行的 tree
        必須與之相等」的斷言。M2_K／M3_K 依設計是從**候選 tree**（而非這份 profile 的 M0
        基準樹）重建的，樹 hash 本來就會不同——把它們拿來相等比對後判「無效」，會讓 C.2
        對任何候選改動恆為無效。呼叫端只應把這份 dict 印進報告，不得據此比較／判定結論
        （測試見 `test_active_profile_provenance_is_reported_not_cross_checked`）。"""
        return {
            "version": self.version,
            "tree_hash": self.tree_hash,
            "cdhash": self.cdhash,
            "env_fingerprint": dict(self.env_fingerprint),
        }


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


def _parse_env_fingerprint(data: object, where: str) -> Dict[str, str]:
    """v5 §10 R13：環境指紋可選——`None`（欄位缺席）＝本份 profile 未記錄，回空 dict；附了就必須
    恰好含 `os_build`／`xcode_build`／`sdk` 三鍵，值皆非空字串，否則拒絕（不得半殘留）。"""
    if data is None:
        return {}
    if not isinstance(data, dict) or set(data) != set(_ENV_FINGERPRINT_KEYS):
        raise ProfileError(f"{where}: env_fingerprint 須為恰含 {_ENV_FINGERPRINT_KEYS} 三鍵的物件")
    for key in _ENV_FINGERPRINT_KEYS:
        if not isinstance(data[key], str) or not data[key]:
            raise ProfileError(f"{where}: env_fingerprint.{key} 須為非空字串")
    return dict(data)


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


def activate_r27(root: Path, version: str, *, allow_replace: bool = False) -> R27Profile:
    """M0／M2／M3／ui-T0′ 四者皆有效且格式相符才允許啟用；任一缺失或格式不對 → 整體拒絕，
    不寫任何 active 檔（保留既有 staging 證據）。`version` 不得為空字串（否則寫出後
    `load_active_profile` 永遠讀不回，形成啟用了卻不可讀的殭屍狀態）。已有 active profile 時
    預設拒絕（首份規則，§7 場 0 停止分支 3）；確需替換須顯式 `allow_replace=True`。

    §13 第 5 項「M0 每步登記」：staging/m0 的 `steps` 鍵集合須恰為 `STEPS` 導出的全部 9 個
    `(test, step)`，缺一即拒絕啟用並列出缺哪些——只登記 1 步就能啟用的話，其餘 8 步永遠
    不會被 R4-F 檢查到（一份殘缺 profile 卻被當成「已覆蓋」）。

    成功時把四份 staging **原文**（不只是抽出來的欄位）連同各自的 sha256 一併存進
    `active/profile.json`，以 write-temp + `os.replace` 單次原子寫入。`component_hashes`
    只是**自洽性**檢查（防半成品寫入、事後竄改內容卻忘了同步改 hash）——不是真實性檢查：
    hash 本身是用內容重算出來的，純手寫的偽造檔只要自己按同演算法算好 hash 照樣會通過。
    因此另外把四份 staging **檔案本身**（`staging/<c>.staging.json`，而非重新序列化的內容）
    的 sha256 也存進 `staging_file_hashes`；`load_active_profile` 要求這四份 staging 檔仍在
    磁碟且與紀錄相符，手寫偽造者除了 active 檔本身還得同時偽造四份 staging 檔才能過關，
    抬高了偽造門檻（仍非密碼學意義上的防偽——見 `load_active_profile` docstring）。"""
    if not isinstance(version, str) or not version:
        raise ProfileError("啟用拒絕：version 不得為空")
    root = Path(root)
    active_dir = root / _ACTIVE_DIRNAME
    target = active_dir / _ACTIVE_FILENAME
    if target.is_file() and not allow_replace:
        raise ProfileError(
            "啟用拒絕：active profile 已存在（首份規則），如確需替換請顯式 allow_replace=True"
        )

    missing = [c for c in _STAGING_COMPONENTS if load_staging_component(root, c) is None]
    if missing:
        raise ProfileError(f"啟用拒絕：staging 缺元件 {missing}（M0／M2／M3／ui-T0′ 四者皆須有效）")

    raw: Dict[str, dict] = {}
    parsed: Dict[str, object] = {}
    hashes: Dict[str, str] = {}
    staging_hashes: Dict[str, str] = {}
    for component in _STAGING_COMPONENTS:
        data = load_staging_component(root, component)
        raw[component] = data
        try:
            parsed[component] = _COMPONENT_PARSERS[component](data)
        except ProfileError as e:
            raise ProfileError(f"啟用拒絕：staging/{component} 無效（{e}）") from e
        hashes[component] = _hash_bytes(_canonical_bytes(data))
        staging_hashes[component] = _hash_bytes(_staging_path(root, component).read_bytes())

    m0_keys = set(parsed["m0"])
    if m0_keys != _ALL_M0_STEP_KEYS:
        missing_steps = sorted(f"{l}.{s}" for l, s in _ALL_M0_STEP_KEYS - m0_keys)
        extra_steps = sorted(f"{l}.{s}" for l, s in m0_keys - _ALL_M0_STEP_KEYS)
        detail = "；".join(
            part
            for part in (f"缺 {missing_steps}" if missing_steps else "", f"多餘 {extra_steps}" if extra_steps else "")
            if part
        )
        raise ProfileError(f"啟用拒絕：staging/m0 須登記全部 9 個步驟（{detail}）")

    tree_hash = raw["m0"].get("tree_hash", "")
    cdhash = raw["m0"].get("cdhash", "")
    if not tree_hash or not cdhash:
        raise ProfileError("啟用拒絕：staging/m0 缺 tree_hash／cdhash")
    env_fingerprint = _parse_env_fingerprint(raw["m0"].get("env_fingerprint"), "staging/m0")

    active_payload = {
        "schema": R27_PROFILE_SCHEMA,
        "active_profile": "R27",
        "version": version,
        "component_hashes": hashes,
        "staging_file_hashes": staging_hashes,
        "components": raw,
    }

    active_dir.mkdir(parents=True, exist_ok=True)
    tmp = active_dir / f".{_ACTIVE_FILENAME}.tmp-{os.getpid()}"
    tmp.write_text(json.dumps(active_payload, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    os.replace(tmp, target)  # 同檔系統內原子換檔：中途中斷不會留下半成品 active 檔

    return R27Profile(
        schema=R27_PROFILE_SCHEMA,
        version=version,
        tree_hash=tree_hash,
        cdhash=cdhash,
        env_fingerprint=env_fingerprint,
        m0=parsed["m0"],
        m2_kill=parsed["m2"],
        m3_kill=parsed["m3"],
        ui_t0_prime=parsed["ui_t0_prime"],
    )


def load_active_profile(root: Path) -> Optional[R27Profile]:
    """只讀 `active/profile.json`；不存在＝尚無 active profile（回 None，不是錯誤）。staging
    中的元件無論多完整都不會被這個函式看見——建立中的 R27 永遠不會被誤當成 active（第 13 項）。

    載入時重新驗證 `component_hashes`：須四元件齊全、皆為 64 字元小寫 hex；對 `components` 下
    每份原文重算 sha256，須與宣稱的 hash 逐一相符。**據實澄清**（原 docstring 曾寫「防止手寫
    檔繞過 staging 直接偽造 active profile」，與實測不符，已於覆核中訂正）：這只是**自洽性**
    檢查——防半成品寫入、防事後竄改內容卻忘了同步改 hash——不是**真實性**檢查。hash 本身是
    用內容重算出來的，攻擊者只要用同一演算法（`json.dumps(..., indent=2, sort_keys=True)` →
    sha256）自己算好 hash，一份純手寫、從未經過 `activate_r27`／`stage_component` 的偽造檔照樣
    會通過這一關。

    真正提高偽造門檻的是下一步：另外要求 `staging_file_hashes` 四元件齊全，且對應的
    `staging/<c>.staging.json` 仍在磁碟、其目前位元組內容的 sha256 與記錄相符——偽造者除了
    偽造 active 檔本身，還得同時偽造四份格式相符的 staging 檔並放在正確路徑，才能通過全部
    檢查。這仍不是密碼學意義上的防偽（沒有簽章／不可否認性），只是把「隨手竄改一個欄位」
    的攻擊成本墊高到「同時維護五份互相一致的檔案」。"""
    target = Path(root) / _ACTIVE_DIRNAME / _ACTIVE_FILENAME
    if not target.is_file():
        return None
    try:
        payload = json.loads(target.read_text(encoding="utf-8"))
    except ValueError as e:
        raise ProfileError(f"active/{_ACTIVE_FILENAME}: 無法解析（{e}）") from e
    if not isinstance(payload, dict) or payload.get("active_profile") != "R27":
        raise ProfileError(f"active/{_ACTIVE_FILENAME}: active_profile 應為 'R27'")
    version = payload.get("version")
    if not isinstance(version, str) or not version:
        raise ProfileError(f"active/{_ACTIVE_FILENAME}: 缺必要欄位 version")

    components = payload.get("components")
    if not isinstance(components, dict) or set(components) != set(_STAGING_COMPONENTS):
        raise ProfileError(f"active/{_ACTIVE_FILENAME}: components 缺元件或含未知元件")

    hashes = payload.get("component_hashes")
    if not isinstance(hashes, dict) or set(hashes) != set(_STAGING_COMPONENTS):
        raise ProfileError(f"active/{_ACTIVE_FILENAME}: 缺 component_hashes 或元件不齊")
    for name, digest in hashes.items():
        if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            raise ProfileError(f"active/{_ACTIVE_FILENAME}: component_hashes.{name} 不是合法的 64 字元 sha256 hex")

    staging_hashes = payload.get("staging_file_hashes")
    if not isinstance(staging_hashes, dict) or set(staging_hashes) != set(_STAGING_COMPONENTS):
        raise ProfileError(f"active/{_ACTIVE_FILENAME}: 缺 staging_file_hashes 或元件不齊")
    for name, digest in staging_hashes.items():
        if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            raise ProfileError(
                f"active/{_ACTIVE_FILENAME}: staging_file_hashes.{name} 不是合法的 64 字元 sha256 hex"
            )
        staging_file = _staging_path(Path(root), name)
        if not staging_file.is_file():
            raise ProfileError(
                f"active/{_ACTIVE_FILENAME}: staging/{name}.staging.json 已不在磁碟（無法驗證溯源）"
            )
        actual_staging_hash = _hash_bytes(staging_file.read_bytes())
        if actual_staging_hash != digest:
            raise ProfileError(
                f"active/{_ACTIVE_FILENAME}: staging/{name}.staging.json 內容與 staging_file_hashes 不符"
                f"（manifest {digest}／實得 {actual_staging_hash}）"
            )

    parsed: Dict[str, object] = {}
    for name in _STAGING_COMPONENTS:
        raw = components[name]
        actual = _hash_bytes(_canonical_bytes(raw)) if isinstance(raw, dict) else None
        if actual != hashes[name]:
            raise ProfileError(
                f"active/{_ACTIVE_FILENAME}: components.{name} 與 component_hashes 不符"
                f"（manifest {hashes[name]}／實得 {actual}）"
            )
        parsed[name] = _COMPONENT_PARSERS[name](raw)

    m0_raw = components["m0"]
    tree_hash = _require_str(m0_raw, "tree_hash", "active.components.m0")
    cdhash = _require_str(m0_raw, "cdhash", "active.components.m0")
    env_fingerprint = _parse_env_fingerprint(m0_raw.get("env_fingerprint"), "active.components.m0")

    return R27Profile(
        schema=R27_PROFILE_SCHEMA,
        version=version,
        tree_hash=tree_hash,
        cdhash=cdhash,
        env_fingerprint=env_fingerprint,
        m0=parsed["m0"],
        m2_kill=parsed["m2"],
        m3_kill=parsed["m3"],
        ui_t0_prime=parsed["ui_t0_prime"],
    )


def env_fingerprint_check(
    profile: R27Profile, run_env_fingerprint: Optional[Mapping[str, str]]
) -> Tuple[str, List[str]]:
    """v5 §10 R13：profile 記錄的環境指紋與受評運行的環境指紋比對，下結論前必做。回傳
    `(status, reasons)`。**must_fix（原 fail-open 已訂正）**：舊版把「profile 有指紋但運行端
    沒給」也歸為 `unknown`、不影響結論——CLI 端又從不供應運行端指紋，等於 R13 恆為零效果。
    現行四態：

      - `"unknown"`：profile 本身沒記錄指紋（比 `run_env_fingerprint` 是否給了更優先判斷）——
        沒有基準可比對，不是「沒量測」而是「這份 profile 沒承諾過」，不影響結論；
      - `"unmeasured"`：profile 有指紋，但 `run_env_fingerprint` 未提供（`None` 或 `{}`）——
        **fail-closed**：呼叫端須判「無效」，不得把「沒測」靜默當成「沒事」（§10 R13
        「不靜默比對」）；
      - `"match"`：兩者都有且逐鍵相符；
      - `"mismatch"`：兩者都有但至少一鍵不符（`reasons` 逐條列出）——呼叫端須判「無效」，
        不得靜默採用為別的 OS 凍結的 profile。
    """
    if not profile.env_fingerprint:
        return "unknown", []
    if not run_env_fingerprint:
        return "unmeasured", [
            "env_fingerprint：profile 已記錄環境指紋（"
            f"{sorted(profile.env_fingerprint)}），但本次運行未提供 --run-env-fingerprint"
            "（§10 R13 fail-closed：未量測不得靜默視為相符）"
        ]
    reasons = [
        f"env_fingerprint.{key}：profile={profile.env_fingerprint.get(key)!r} "
        f"≠ 運行={run_env_fingerprint.get(key)!r}"
        for key in sorted(set(profile.env_fingerprint) | set(run_env_fingerprint))
        if profile.env_fingerprint.get(key) != run_env_fingerprint.get(key)
    ]
    if reasons:
        return "mismatch", reasons
    return "match", []


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
