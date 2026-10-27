#!/usr/bin/env python3
"""歌詞時間軸準度量測的純計算部分（計劃 docs/plans/2026-10-25-lyrics-timing-accuracy.md v0.5）。

- §4.3 指標：signed error（顯示起點 − 程式真值）、早／準／晚、邊界、錯行率、逐首彙總、bootstrap。
- §4.7 決策表：閘序互斥＋候選可回收量排序。
- §4.8 欄位檢查：落檔只准允許的鍵。

只用標準庫，相容 Python 3.9（雲端也能跑）。不讀任何檔案；輸入輸出都是 dict／list，由呼叫端序列化。
"""
from __future__ import annotations

import hashlib
import math
import random
from typing import Callable, Dict, Iterable, List, Optional, Sequence, Set, Tuple

TOLERANCE = 0.3              # 準時門檻＝真值互驗容差（§4.3、§4.4）
WIDE_TOLERANCE = 1.0
OBSERVATION_DELAY = 0.5      # 錯行率的觀察點：真值後 0.5 s 或半個行距（取小）
REPEAT_SIMILARITY = 0.8      # 與 LRCAligner.lineSimilarityThreshold 相同
BOOTSTRAP_SAMPLES = 2000
BOOTSTRAP_SEED = 20261027

MIN_TRACKS_PER_SOURCE = 8    # §4.1 最低證據量
MIN_TRACKS_PER_GROUP = 20
TIE_RELATIVE_GAP = 0.2       # §4.7 步驟 1-4

CANDIDATE_ORDER = ["X2", "X3", "X4", "E1-X2", "E1-X3", "S1", "C1"]

SAMPLE_SEED = "20261027"     # §4.1 M1 樣本
LANGUAGE_FLOOR = 50


# ---------- 統計 ----------

def median(values: Sequence[float]) -> Optional[float]:
    return percentile(values, 50)


def percentile(values: Sequence[float], q: float) -> Optional[float]:
    """線性內插（同 numpy 預設）；空序列回 None。"""
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * q / 100.0
    low = math.floor(position)
    high = math.ceil(position)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def mean(values: Sequence[float]) -> Optional[float]:
    return sum(values) / len(values) if values else None


def bootstrap_ci(values: Sequence[float], statistic: Callable[[Sequence[float]], Optional[float]],
                 samples: int = BOOTSTRAP_SAMPLES, seed: int = BOOTSTRAP_SEED,
                 level: float = 0.95) -> Optional[Tuple[float, float]]:
    """以曲為單位重抽（呼叫端傳逐首值）；百分位法區間。"""
    if not values:
        return None
    rng = random.Random(seed)
    estimates = []
    for _ in range(samples):
        resample = [values[rng.randrange(len(values))] for _ in values]
        estimates.append(statistic(resample))
    tail = (1 - level) / 2 * 100
    return percentile(estimates, tail), percentile(estimates, 100 - tail)


# ---------- 真值與文字 ----------

def consensus(method_a: Optional[float], method_b: Optional[float],
              tolerance: float = TOLERANCE) -> Tuple[Optional[float], Optional[float]]:
    """兩法都給出且差 ≤ 容差 → (平均, 半差)；否則無法判定 (None, None)（§4.4 第 5 步）。"""
    if method_a is None or method_b is None or abs(method_a - method_b) > tolerance:
        return None, None
    return (method_a + method_b) / 2, abs(method_a - method_b) / 2


def normalized(text: str) -> str:
    """同 LRCAligner.normalized：小寫、只留字母與數字（Swift 以字素計、這裡以碼位計；只影響組合字元）。"""
    return "".join(ch for ch in text.lower() if ch.isalnum())


def similarity(left: str, right: str) -> float:
    """1 −（編輯距離／較長者長度）；兩邊皆空＝0（同 LRCAligner.similarity）。"""
    a, b = normalized(left), normalized(right)
    longest = max(len(a), len(b))
    if longest == 0:
        return 0.0
    return 1 - _edit_distance(a, b) / longest


def _edit_distance(a: str, b: str) -> int:
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def repeated_flags(texts: Sequence[str]) -> List[bool]:
    """與同首另一行相同或相似度 ≥ 0.8 的行（§4.3 重複行）。"""
    flags = [False] * len(texts)
    for i in range(len(texts)):
        for j in range(i + 1, len(texts)):
            if similarity(texts[i], texts[j]) >= REPEAT_SIMILARITY:
                flags[i] = flags[j] = True
    return flags


# ---------- 逐行 ----------

def wrong_line_flags(display_starts: Sequence[float], truth: Sequence[Optional[float]]) -> List[Optional[bool]]:
    """每行是否錯行；None＝不納入（本行或下一行不可判定、末行）（§4.3）。"""
    flags: List[Optional[bool]] = []
    for i, start in enumerate(truth):
        following = truth[i + 1] if i + 1 < len(truth) else None
        if start is None or following is None:
            flags.append(None)
            continue
        observed_at = start + min(OBSERVATION_DELAY, (following - start) / 2)
        flags.append(_shown_line(display_starts, observed_at) != i)
    return flags


def _shown_line(display_starts: Sequence[float], moment: float) -> int:
    shown = -1
    for index, start in enumerate(display_starts):
        if start <= moment:
            shown = index
    return shown


# ---------- 逐首 ----------

def track_metrics(display_starts: Sequence[float], truth: Sequence[Optional[float]],
                  uncertainty: Sequence[Optional[float]], interpolated: Optional[Sequence[bool]] = None,
                  texts: Optional[Sequence[str]] = None) -> Dict[str, object]:
    """一首的 §4.3 指標；只用可判定的行。"""
    decidable = [i for i, t in enumerate(truth) if t is not None]
    errors = {i: display_starts[i] - truth[i] for i in decidable}
    wrong = wrong_line_flags(display_starts, truth)
    interp = list(interpolated) if interpolated is not None else [False] * len(truth)
    repeats = repeated_flags(texts) if texts is not None else [False] * len(truth)
    metrics: Dict[str, object] = {"line_count": len(truth), "decidable_lines": len(decidable)}
    metrics.update(_error_summary(list(errors.values())))
    metrics.update(_classification(errors, uncertainty))
    metrics.update(_wrong_summary(wrong, decidable))
    metrics.update(_shape_summary(errors, len(truth), metrics["offset"]))
    metrics.update(_interpolation_summary(errors, wrong, interp))
    metrics["mae_without_repeats"] = median([abs(e) for i, e in errors.items() if not repeats[i]])
    metrics["wrong_rate_without_repeats"] = _rate([w for i, w in enumerate(wrong) if not repeats[i]])
    return metrics


def _error_summary(errors: List[float]) -> Dict[str, Optional[float]]:
    offset = median(errors)
    residuals = [abs(e - offset) for e in errors] if offset is not None else []
    return {"mae": median([abs(e) for e in errors]), "offset": offset, "resid_p90": percentile(residuals, 90)}


def _classification(errors: Dict[int, float], uncertainty: Sequence[Optional[float]]) -> Dict[str, Optional[float]]:
    count = len(errors)
    if count == 0:
        return {key: None for key in ("early", "on_time", "late", "within_1s", "boundary_share")}
    values = list(errors.values())
    boundary = sum(1 for i, e in errors.items() if abs(abs(e) - TOLERANCE) <= (uncertainty[i] or 0.0))
    return {
        "early": sum(1 for e in values if e < -TOLERANCE) / count,
        "on_time": sum(1 for e in values if abs(e) <= TOLERANCE) / count,
        "late": sum(1 for e in values if e > TOLERANCE) / count,
        "within_1s": sum(1 for e in values if abs(e) <= WIDE_TOLERANCE) / count,
        "boundary_share": boundary / count,
    }


def _wrong_summary(wrong: List[Optional[bool]], decidable: List[int]) -> Dict[str, Optional[float]]:
    evaluated = [w for w in wrong if w is not None]
    excluded = (len(decidable) - len(evaluated)) / len(decidable) if decidable else None
    return {"wrong_rate": _rate(wrong), "wrong_excluded_share": excluded}


def _shape_summary(errors: Dict[int, float], line_count: int, offset: Optional[float]) -> Dict[str, Optional[float]]:
    latter_start = line_count - (2 * line_count) // 3
    latter = [abs(e - offset) for i, e in errors.items() if i >= latter_start] if offset is not None else []
    first = errors.get(0)
    return {"first_abs_error": abs(first) if first is not None else None, "latter_resid_median": median(latter)}


def _interpolation_summary(errors: Dict[int, float], wrong: List[Optional[bool]],
                           interp: Sequence[bool]) -> Dict[str, object]:
    abs_errors = [abs(e) for i, e in errors.items() if interp[i]]
    return {
        "interp_lines": sum(1 for flag in interp if flag),
        "interp_abs_errors": abs_errors,
        "interp_abs_median": median(abs_errors),
        "interp_wrong_rate": _rate([w for i, w in enumerate(wrong) if interp[i]]),
    }


def _rate(flags: Iterable[Optional[bool]]) -> Optional[float]:
    evaluated = [flag for flag in flags if flag is not None]
    return sum(1 for flag in evaluated if flag) / len(evaluated) if evaluated else None


# ---------- 欄位檢查（§4.8） ----------

def disallowed_keys(record: object, allowed: Set[str], path: str = "") -> List[str]:
    """遞迴列出不在白名單的鍵（含路徑），排序後回傳。"""
    found: List[str] = []
    if isinstance(record, dict):
        for key, value in record.items():
            here = "%s.%s" % (path, key) if path else str(key)
            if key not in allowed:
                found.append(here)
            found.extend(disallowed_keys(value, allowed, here))
    elif isinstance(record, list):
        for index, item in enumerate(record):
            found.extend(disallowed_keys(item, allowed, "%s[%d]" % (path, index)))
    return sorted(found)


# ---------- 抽樣（§4.1） ----------

def sample_key(persistent_id: str, seed: str = SAMPLE_SEED) -> str:
    return hashlib.sha256(("%s:%s" % (seed, persistent_id)).encode("utf-8")).hexdigest()


def tertile_cuts(records: Sequence[dict]) -> Tuple[float, float]:
    rates = [r["linesPerMinute"] for r in records]
    return percentile(rates, 100 / 3), percentile(rates, 200 / 3)


def tertile(rate: float, cuts: Tuple[float, float]) -> int:
    return 0 if rate <= cuts[0] else 1 if rate <= cuts[1] else 2


def largest_remainder(sizes: Sequence[int], total: int) -> List[int]:
    """依 sizes 比例分 total；餘額給小數部分最大者（同值取前面的）。"""
    whole = sum(sizes)
    if whole == 0:
        return [0] * len(sizes)
    quotas = [total * size / whole for size in sizes]
    shares = [math.floor(q) for q in quotas]
    order = sorted(range(len(sizes)), key=lambda i: (-(quotas[i] - shares[i]), i))
    for i in order[:total - sum(shares)]:
        shares[i] += 1
    return shares


def stratified_sample(records: Sequence[dict], size: int, floor: int = LANGUAGE_FLOOR) -> List[dict]:
    """語言 × 每分鐘行數三分位（三分位點以全體算）；語言下限 floor；層內依雜湊鍵遞增取。"""
    cuts = tertile_cuts(records)
    by_language: Dict[str, List[dict]] = {}
    for record in records:
        by_language.setdefault(record["language"], []).append(record)
    languages = sorted(by_language)
    sample: List[dict] = []
    for language, quota in zip(languages, _language_quotas(languages, by_language, size, floor)):
        sample.extend(_sample_language(language, by_language[language], quota, cuts))
    return sample


def _language_quotas(languages: List[str], by_language: Dict[str, List[dict]], size: int, floor: int) -> List[int]:
    """先按比例；比例不到下限的語言提到下限（不超過該語言首數），其餘名額由其他語言按比例分。"""
    available = [len(by_language[name]) for name in languages]
    proportional = largest_remainder(available, size)
    minimum = min(floor, size)
    lifted = {i: min(minimum, available[i]) for i, q in enumerate(proportional) if q < minimum}
    rest = [i for i in range(len(languages)) if i not in lifted]
    shares = largest_remainder([available[i] for i in rest], size - sum(lifted.values()))
    quotas = dict(lifted)
    quotas.update({i: min(share, available[i]) for i, share in zip(rest, shares)})
    return [quotas[i] for i in range(len(languages))]


def _sample_language(language: str, members: List[dict], quota: int, cuts: Tuple[float, float]) -> List[dict]:
    layers: List[List[dict]] = [[], [], []]
    for record in sorted(members, key=lambda r: sample_key(r["persistentID"])):
        layers[tertile(record["linesPerMinute"], cuts)].append(record)
    # 名額按層大小比例分，quota ≤ 該語言首數時不會超過層的首數，所以不需要補額
    picked: List[dict] = []
    for index, (layer, share) in enumerate(zip(layers, largest_remainder([len(l) for l in layers], quota))):
        picked.extend(dict(r, layer="%s/%d" % (language, index)) for r in layer[:share])
    return picked


# ---------- 決策表（§4.7） ----------

def decide(inputs: Dict[str, object]) -> Dict[str, object]:
    """inputs：g0_passed、embedded_population、chain_found_rate、near_miss_share、tracks。

    tracks 每筆＝track_metrics 的輸出加上 id、group（external／embedded／estimated）、source、
    weight（該曲代表的曲庫佔比；不是 app 實際顯示的組別時由呼叫端給 0）、calibrated、near_miss。
    未校準語言的曲不參與任何判定（§4.4）。
    """
    tracks = [t for t in inputs["tracks"] if t["calibrated"]]
    groups = {name: [t for t in tracks if t["group"] == name] for name in ("external", "embedded", "estimated")}
    if not inputs["g0_passed"]:
        return _result("stop", [], [], groups)
    if not _enough_evidence(groups, inputs["embedded_population"]):
        return _result("insufficient", [], [], groups)
    candidates = _candidates(groups, inputs)
    return _rank(candidates, groups)


def _enough_evidence(groups: Dict[str, List[dict]], embedded_population: int) -> bool:
    needed = ["external", "estimated"] + (["embedded"] if embedded_population >= MIN_TRACKS_PER_GROUP else [])
    return all(len(groups[name]) >= MIN_TRACKS_PER_GROUP for name in needed)


def _candidates(groups: Dict[str, List[dict]], inputs: Dict[str, object]) -> List[dict]:
    external, embedded, estimated = groups["external"], groups["embedded"], groups["estimated"]
    found = [
        _offset_candidate("X2", external),
        _jitter_candidate("X3", external),
        _interpolation_candidate(external),
        _offset_candidate("E1-X2", embedded) if len(embedded) >= MIN_TRACKS_PER_GROUP else None,
        _jitter_candidate("E1-X3", embedded) if len(embedded) >= MIN_TRACKS_PER_GROUP else None,
        _estimate_candidate(estimated),
        _coverage_candidate(external, estimated, inputs),
    ]
    return [c for c in found if c is not None]


def _offset_candidate(candidate_id: str, group: List[dict]) -> Optional[dict]:
    if not group:
        return None
    members = [t for t in group if _is_set(t["offset"]) and abs(t["offset"]) > TOLERANCE
               and _is_set(t["resid_p90"]) and t["resid_p90"] <= 0.5]
    triggered = len(members) / len(group) >= 0.25
    return _candidate(candidate_id, "offset_correction", triggered, members)


def _jitter_candidate(candidate_id: str, group: List[dict]) -> Optional[dict]:
    if not group:
        return None
    members = [t for t in group if _is_set(t["resid_p90"]) and t["resid_p90"] > 1.0]
    triggered = len(members) / len(group) >= 0.25
    direction, members = _jitter_direction(group, members)
    return _candidate(candidate_id, direction, triggered, members)


def _jitter_direction(group: List[dict], members: List[dict]) -> Tuple[str, List[dict]]:
    """某來源佔這些曲 ≥ 60 % 且該來源證據足 → 降級該來源（集合只取該來源）；否則逐行對齊。"""
    for source in sorted({t["source"] for t in members if t["source"]}):
        own = [t for t in members if t["source"] == source]
        evidence = sum(1 for t in group if t["source"] == source)
        if len(own) / len(members) >= 0.6 and evidence >= MIN_TRACKS_PER_SOURCE:
            return "demote:%s" % source, own
    return "per_line_alignment", members


def _interpolation_candidate(external: List[dict]) -> Optional[dict]:
    if not external:
        return None
    pooled = [e for t in external for e in t["interp_abs_errors"]]
    total_lines = sum(t["line_count"] for t in external)
    share = sum(t["interp_lines"] for t in external) / total_lines if total_lines else 0.0
    p90 = percentile(pooled, 90)
    triggered = p90 is not None and p90 > 2.0 and share >= 0.2
    members = [t for t in external if _is_set(t["interp_abs_median"]) and t["interp_abs_median"] > 2.0]
    return _candidate("X4", "interpolation_strategy", triggered, members, rate_key="interp_wrong_rate")


def _estimate_candidate(estimated: List[dict]) -> Optional[dict]:
    if not estimated:
        return None
    slow = [t for t in estimated if _is_set(t["mae"]) and t["mae"] > 2.0]
    wrong_mean = mean([t["wrong_rate"] for t in estimated if _is_set(t["wrong_rate"])])
    triggered = len(slow) / len(estimated) >= 0.5 or (wrong_mean is not None and wrong_mean >= 0.3)
    members = [t for t in estimated if (_is_set(t["mae"]) and t["mae"] > 2.0)
               or (_is_set(t["wrong_rate"]) and t["wrong_rate"] >= 0.3)]
    first = median([t["first_abs_error"] for t in estimated if _is_set(t["first_abs_error"])])
    latter = median([t["latter_resid_median"] for t in estimated if _is_set(t["latter_resid_median"])])
    floor = first is not None and first > 3.0 and latter is not None and latter <= 2.0
    return _candidate("S1", "estimate_floor" if floor else "per_line_alignment", triggered, members)


def _coverage_candidate(external: List[dict], estimated: List[dict], inputs: Dict[str, object]) -> dict:
    triggered = inputs["chain_found_rate"] < 0.5 and inputs["near_miss_share"] >= 0.2
    members = [t for t in estimated if t["near_miss"]]
    candidate = _candidate("C1", "relax_matching", triggered, members)
    near_rate = mean([t["wrong_rate"] for t in members if _is_set(t["wrong_rate"])])
    external_rate = mean([t["wrong_rate"] for t in external if _is_set(t["wrong_rate"])])
    gain = (near_rate - external_rate) if near_rate is not None and external_rate is not None else 0.0
    candidate["recoverable"] = candidate["weight"] * gain
    return candidate


def _candidate(candidate_id: str, direction: str, triggered: bool, members: List[dict],
               rate_key: str = "wrong_rate") -> dict:
    """可回收量＝w(T) × T 的錯行率平均（目標錯行率取 0；§4.7）。"""
    weight = sum(t["weight"] for t in members)
    rate = mean([t[rate_key] for t in members if _is_set(t[rate_key])])
    return {
        "id": candidate_id, "direction": direction, "triggered": triggered,
        "track_set": sorted(t["id"] for t in members), "weight": weight,
        "recoverable": weight * rate if rate is not None else 0.0, "rank": None,
    }


def _rank(candidates: List[dict], groups: Dict[str, List[dict]]) -> Dict[str, object]:
    triggered = [c for c in candidates if c["triggered"]]
    if not triggered:
        return _result("no_action", [], candidates, groups)
    positive = sorted((c for c in triggered if c["recoverable"] > 0), key=lambda c: -c["recoverable"])
    if not positive:
        return _result("unrecoverable", [], candidates, groups)
    for rank, candidate in enumerate(positive, 1):
        candidate["rank"] = rank
    best = positive[0]
    if len(positive) > 1 and (best["recoverable"] - positive[1]["recoverable"]) / best["recoverable"] < TIE_RELATIVE_GAP:
        return _result("tie", [best["id"], positive[1]["id"]], candidates, groups)
    return _result("single", [best["id"]], candidates, groups)


def _result(outcome: str, chosen: List[str], candidates: List[dict], groups: Dict[str, List[dict]]) -> Dict[str, object]:
    external = groups["external"]
    accurate = bool(external) and sum(1 for t in external if _is_set(t["mae"]) and t["mae"] <= TOLERANCE) / len(external) >= 0.8
    return {
        "outcome": outcome, "chosen": chosen,
        "candidates": sorted(candidates, key=lambda c: CANDIDATE_ORDER.index(c["id"])),
        "overlaps": _overlaps(candidates), "external_accurate": accurate,
    }


def _overlaps(candidates: List[dict]) -> Dict[str, int]:
    triggered = sorted((c for c in candidates if c["triggered"]), key=lambda c: CANDIDATE_ORDER.index(c["id"]))
    pairs: Dict[str, int] = {}
    for i, left in enumerate(triggered):
        for right in triggered[i + 1:]:
            pairs["%s&%s" % (left["id"], right["id"])] = len(set(left["track_set"]) & set(right["track_set"]))
    return pairs


def _is_set(value: Optional[float]) -> bool:
    return value is not None

