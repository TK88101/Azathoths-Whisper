"""B3-R3 判定：offset-only 音訊校準（計劃 docs/plans/2026-10-25-lyrics-timing-accuracy.md 附錄 C-11 v0.3）。

只讀 runner 寫出的逐行原始值（A、B 起點、lowVocal、曲長、文字語言），只出數字與判定；
門檻全部是本檔的具名常數，看到保留集結果後不得再改（C-11「執行」段）。
"""
import math
import random
import statistics
from typing import Dict, List, Optional, Sequence

from timing_probe_metrics import percentile

# 管線與語言規則
CONSENSUS_TOLERANCE = 0.3
LANGUAGE_WHITELIST = ("en", "de", "es", "fr", "ja")
MIN_LANGUAGE_PROBABILITY = 0.80
# 接受條件 ①–⑥
MIN_ANCHORS = 8
MIN_SPAN_RATIO = 0.5
MAX_GAP_SECONDS = 60.0
THIRD_MIN_ANCHORS = 3
MIN_THIRDS = 2
MAX_RESIDUAL_P90 = 0.3
OUTLIER_SECONDS = 0.5
MAX_OUTLIER_RATIO = 0.10
CONDITION_ORDER = ("anchors", "span", "gap", "thirds", "p90", "outliers")
# G0-1″
SELFCHECK_SONGS = 5
DETERMINISM_TOLERANCE = 0.01
AUDIO_SHIFT = 3.0
AUDIO_SHIFT_TOLERANCE = 0.05
MAX_ANCHOR_CHANGE = 0.10
LYRIC_SHIFT = 2.0
LYRIC_SHIFT_TOLERANCE = 0.001
MIN_SELFCHECK_ACCEPTED = 3
# G0-2″
MISFIX_SECONDS = 0.5
CONFIDENCE = 0.95
MAX_MISFIX_UPPER = 0.10
MIN_ACCEPTED_FOR_SAFETY = 29
MIN_ACCEPT_RATE = 0.5
MAX_ERROR_MEDIAN = 0.10
MAX_ERROR_P90 = 0.25
SEED = 20261027
JITTER_SD = 0.15
MASK_RATIO_TENTHS = 2
MASK_MIN_ANCHORS = 10
DRIFT_SECONDS = 1.0
MAX_DEFECT_ACCEPT_RATE = 0.10

THRESHOLDS = {name: value for name, value in globals().items() if name.isupper()}


def consensus(a: Sequence[Optional[float]], b: Sequence[Optional[float]], low: Sequence[bool]) -> List[Optional[float]]:
    """A、B 都有值、|A−B| ≤ 0.3 s 且非 lowVocal → 平均；否則 None"""
    return [(x + y) / 2 if x is not None and y is not None and abs(x - y) <= CONSENSUS_TOLERANCE and not quiet else None
            for x, y, quiet in zip(a, b, low)]


def language_cause(text: Dict) -> Optional[str]:
    """文字語言規則：機率 < 0.80 或不在白名單 → 拒答主因；可用回 None"""
    if text["probability"] < MIN_LANGUAGE_PROBABILITY:
        return "languageLowConfidence"
    if text["language"] not in LANGUAGE_WHITELIST:
        return "languageNotSupported"
    return None


def rejection(cause: str) -> Dict:
    return {"accepted": False, "offset": None, "anchors": [], "residuals": [], "conditions": {}, "failed": [cause], "cause": cause}


def estimate(lyric: Sequence[float], c: Sequence[Optional[float]], duration: float, excluded=frozenset()) -> Dict:
    """offset＝median(Lᵢ − Cᵢ)，rᵢ＝(Lᵢ − Cᵢ) − offset；①–⑥ 全成立才接受，拒答主因＝依序第一個不成立的條件"""
    anchors = [i for i, x in enumerate(c) if x is not None and i not in excluded]
    if not anchors:
        result = rejection("anchors")
        result["conditions"] = {"anchors": 0}
        result["failed"] = list(CONDITION_ORDER)
        return result
    diffs = [lyric[i] - c[i] for i in anchors]
    offset = statistics.median(diffs)
    residuals = [d - offset for d in diffs]
    times = sorted(c[i] for i in anchors)
    third = duration / 3
    thirds = [sum(1 for t in times if t < third), sum(1 for t in times if third <= t < 2 * third),
              sum(1 for t in times if t >= 2 * third)]
    magnitudes = [abs(r) for r in residuals]
    conditions = {
        "anchors": len(anchors),
        "span": times[-1] - times[0],
        "spanRatio": (times[-1] - times[0]) / duration if duration > 0 else 0.0,
        "maxGap": max((q - p for p, q in zip(times, times[1:])), default=0.0),
        "thirds": thirds,
        "p90": percentile(magnitudes, 90),
        "outlierRatio": sum(1 for m in magnitudes if m > OUTLIER_SECONDS) / len(magnitudes),
    }
    checks = {
        "anchors": conditions["anchors"] >= MIN_ANCHORS,
        "span": conditions["spanRatio"] >= MIN_SPAN_RATIO,
        "gap": conditions["maxGap"] <= MAX_GAP_SECONDS,
        "thirds": sum(1 for n in thirds if n >= THIRD_MIN_ANCHORS) >= MIN_THIRDS,
        "p90": conditions["p90"] <= MAX_RESIDUAL_P90,
        "outliers": conditions["outlierRatio"] <= MAX_OUTLIER_RATIO,
    }
    failed = [name for name in CONDITION_ORDER if not checks[name]]
    return {"accepted": not failed, "offset": offset, "anchors": anchors, "residuals": residuals,
            "conditions": conditions, "failed": failed, "cause": failed[0] if failed else None}


def run_estimate(run: Optional[Dict], human: Sequence[float], lyric_shift: float = 0.0, excluded=frozenset(), lyric=None) -> Dict:
    """一次執行（base／rerun／shiftAfter／shiftBefore）的估計；lyric 給定時取代人工標記（擾動用）"""
    if run is None or "text" not in run:
        return rejection("failure")
    cause = language_cause(run["text"])
    if cause:
        return rejection(cause)
    if "a" not in run:
        return rejection("failure")
    timeline = lyric if lyric is not None else [h + lyric_shift for h in human]
    return estimate(timeline, consensus(run["a"], run["b"], run["low"]), run["duration"], excluded)


def same_value(x: Optional[float], y: Optional[float], tolerance: float) -> bool:
    return (x is None and y is None) or (x is not None and y is not None and abs(x - y) <= tolerance)


def run_consensus(run: Optional[Dict]) -> List[Optional[float]]:
    if run is None or "a" not in run:
        return []
    return consensus(run["a"], run["b"], run["low"])


def determinism(base: Dict, rerun: Dict, e0: Dict, e1: Dict) -> bool:
    if base["text"]["language"] != rerun["text"]["language"] or e0["accepted"] != e1["accepted"] or e0["cause"] != e1["cause"]:
        return False
    if not same_value(e0["offset"], e1["offset"], DETERMINISM_TOLERANCE):
        return False
    if ("a" in base) != ("a" in rerun):
        return False
    if "a" not in base:
        return True
    lines_same = all(same_value(x, y, DETERMINISM_TOLERANCE)
                     for key in ("a", "b") for x, y in zip(base[key], rerun[key]))
    sets_same = [x is None for x in run_consensus(base)] == [x is None for x in run_consensus(rerun)]
    return lines_same and sets_same and len(base["a"]) == len(rerun["a"])


def audio_shift(e0: Dict, after: Dict):
    """基線接受 → 平移後仍接受、offset 變化 −3.000 ± 0.05、錨點數變動 ≤ 10 %；基線拒答 → 仍拒答且主因相同"""
    change = None if e0["offset"] is None or after["offset"] is None else after["offset"] - e0["offset"]
    ratio = abs(len(after["anchors"]) - len(e0["anchors"])) / len(e0["anchors"]) if e0["anchors"] else None
    if not e0["accepted"]:
        return (not after["accepted"] and after["cause"] == e0["cause"]), change, ratio
    ok = (after["accepted"] and change is not None and abs(change + AUDIO_SHIFT) <= AUDIO_SHIFT_TOLERANCE
          and ratio is not None and ratio <= MAX_ANCHOR_CHANGE)
    return ok, change, ratio


def lyric_shift(e0: Dict, moved: Dict):
    change = None if e0["offset"] is None or moved["offset"] is None else moved["offset"] - e0["offset"]
    offset_ok = same_value(e0["offset"], moved["offset"], math.inf) and (change is None or abs(change - LYRIC_SHIFT) <= LYRIC_SHIFT_TOLERANCE)
    return offset_ok and moved["accepted"] == e0["accepted"], change


def non_decreasing(values: Sequence[Optional[float]]) -> bool:
    kept = [v for v in values if v is not None]
    return all(q >= p for p, q in zip(kept, kept[1:]))


def selfcheck_song(record: Dict) -> Dict:
    """G0-1″ 每首：決定性、音訊平移（分離後補 3 s）、L 平移 +2 s、共識非遞減；另報分離前平移（不設閘）"""
    human = record["human"]
    if record.get("failure") is not None:
        return {"song": record["song"], "failure": record["failure"], "pass": False, "baseAccepted": False, "baseCause": "failure"}
    e0 = run_estimate(record["base"], human)
    e1 = run_estimate(record["rerun"], human)
    ea = run_estimate(record["shiftAfter"], human)
    eb = run_estimate(record["shiftBefore"], human)
    el = run_estimate(record["base"], human, lyric_shift=LYRIC_SHIFT)
    det = determinism(record["base"], record["rerun"], e0, e1)
    shift_ok, shift_change, anchor_ratio = audio_shift(e0, ea)
    before_ok, before_change, before_ratio = audio_shift(e0, eb)
    lyric_ok, lyric_change = lyric_shift(e0, el)
    mono = non_decreasing(run_consensus(record["base"]))
    whisper = [record[k].get("whisper") for k in ("base", "rerun", "shiftAfter", "shiftBefore")]
    return {"song": record["song"], "subset": record.get("subset"), "lines": len(human),
            "textLanguage": record["base"]["text"], "whisperLanguages": whisper,
            "baseAccepted": e0["accepted"], "baseCause": e0["cause"], "baseOffset": e0["offset"],
            "baseAnchors": len(e0["anchors"]), "baseConditions": e0["conditions"],
            "baseAnchorLines": e0["anchors"], "baseResiduals": e0["residuals"], "baseFailed": e0["failed"],
            "determinism": det, "rerunOffset": e1["offset"],
            "audioShift": shift_ok, "audioShiftOffsetChange": shift_change, "anchorChangeRatio": anchor_ratio,
            "shiftAfterCause": ea["cause"],
            "lyricShift": lyric_ok, "lyricShiftOffsetChange": lyric_change,
            "monotonic": mono,
            "shiftBefore": {"ok": before_ok, "offsetChange": before_change, "anchorChangeRatio": before_ratio, "cause": eb["cause"]},
            "failures": [record[k].get("failures", []) for k in ("base", "rerun", "shiftAfter", "shiftBefore")],
            "failure": None, "pass": det and shift_ok and lyric_ok and mono}


def selfcheck_verdict(rows: Sequence[Dict]) -> Dict:
    accepted = sum(1 for r in rows if r["baseAccepted"])
    passed = len(rows) == SELFCHECK_SONGS and all(r["pass"] for r in rows) and accepted >= MIN_SELFCHECK_ACCEPTED
    return {"songs": len(rows), "allSongsPass": all(r["pass"] for r in rows), "baseAccepted": accepted, "pass": passed}


def binomial_pmf(k: int, n: int, p: float) -> float:
    return math.comb(n, k) * p ** k * (1 - p) ** (n - k)


def binomial_cdf(k: int, n: int, p: float) -> float:
    return sum(binomial_pmf(i, n, p) for i in range(k + 1))


def bisect(f, low: float = 0.0, high: float = 1.0) -> float:
    """f 在 [low, high] 單調遞減且跨過 0"""
    for _ in range(200):
        mid = (low + high) / 2
        if f(mid) > 0:
            low = mid
        else:
            high = mid
    return (low + high) / 2


def clopper_pearson_upper(x: int, n: int, confidence: float = CONFIDENCE) -> float:
    """單側上界：P(X ≤ x; n, p) = 1 − confidence 的 p"""
    if x >= n:
        return 1.0
    alpha = 1 - confidence
    return bisect(lambda p: binomial_cdf(x, n, p) - alpha)


def clopper_pearson_lower(x: int, n: int, confidence: float = CONFIDENCE) -> float:
    """單側下界：P(X ≥ x; n, p) = 1 − confidence 的 p"""
    if x <= 0:
        return 0.0
    alpha = 1 - confidence
    return bisect(lambda p: alpha - (1 - binomial_cdf(x - 1, n, p)))


def safety_gate(offsets: Sequence[float]) -> Dict:
    """接受曲的誤修（|offset 誤差| > 0.5 s）比例，CP 95 % 單側上界 ≤ 10 %；接受 < 29 首即失敗"""
    misfixes = sum(1 for o in offsets if abs(o) > MISFIX_SECONDS)
    upper = clopper_pearson_upper(misfixes, len(offsets)) if offsets else 1.0
    return {"accepted": len(offsets), "misfixes": misfixes, "upper": upper,
            "pass": len(offsets) >= MIN_ACCEPTED_FOR_SAFETY and upper <= MAX_MISFIX_UPPER}


def accuracy_gate(offsets: Sequence[float], total: int) -> Dict:
    """接受率 ≥ 50 %；接受曲 |offset 誤差| 中位 ≤ 0.10 s、P90 ≤ 0.25 s；另報接受率 95 % 下界"""
    errors = [abs(o) for o in offsets]
    rate = len(offsets) / total if total else 0.0
    median = statistics.median(errors) if errors else None
    p90 = percentile(errors, 90)
    ok = bool(errors) and rate >= MIN_ACCEPT_RATE and median <= MAX_ERROR_MEDIAN and p90 <= MAX_ERROR_P90
    return {"songs": total, "accepted": len(offsets), "acceptRate": rate,
            "acceptRateLower": clopper_pearson_lower(len(offsets), total) if total else 0.0,
            "median": median, "p90": p90, "pass": ok}


def jitter(lyric: Sequence[float], rng: random.Random) -> List[float]:
    return [t + rng.gauss(0, JITTER_SD) for t in lyric]


def mask_count(anchors: int) -> int:
    """可用錨點的 20 %，四捨五入（整數運算，避免浮點誤差）"""
    return (anchors * MASK_RATIO_TENTHS * 10 + 50) // 100


def drift(lyric: Sequence[float], c: Sequence[Optional[float]]) -> List[float]:
    """以首可用錨點為 0、線性（依 L 時間）遞增，首末可用錨點之間累積漂移恰為 1.0 s"""
    anchors = [i for i, x in enumerate(c) if x is not None]
    if len(anchors) < 2 or lyric[anchors[-1]] == lyric[anchors[0]]:
        return list(lyric)
    start, end = lyric[anchors[0]], lyric[anchors[-1]]
    return [t + DRIFT_SECONDS * (t - start) / (end - start) for t in lyric]


def swap_halves(lyric: Sequence[float]) -> List[float]:
    """依行號對半，前後兩半的時間互換（奇數行時前半 n//2 行）"""
    half = len(lyric) // 2
    return list(lyric[half:]) + list(lyric[:half])


def base_estimate(record: Dict, **kwargs) -> Dict:
    if record.get("failure") is not None:
        return rejection("failure")
    return run_estimate(record.get("base"), record["human"], **kwargs)


def accepted_offsets(estimates: Sequence[Dict]) -> List[float]:
    return [e["offset"] for e in estimates if e["accepted"]]


def by_language(records: Sequence[Dict], estimates: Sequence[Dict]) -> Dict[str, Dict]:
    out = {}
    for language in sorted({r["subset"] for r in records}):
        picked = [e for r, e in zip(records, estimates) if r["subset"] == language]
        out[language] = accuracy_gate(accepted_offsets(picked), len(picked))
    return out


def defect_rate(estimates: Sequence[Dict], total: int) -> Dict:
    accepted = sum(1 for e in estimates if e["accepted"])
    rate = accepted / total if total else 0.0
    return {"accepted": accepted, "songs": total, "acceptRate": rate, "pass": rate <= MAX_DEFECT_ACCEPT_RATE}


def perturbations(records: Sequence[Dict], base: Sequence[Dict], passed_languages: Sequence[str]) -> Dict:
    """(a)–(d)：同一份音訊結果，只改 L；每種擾動各用一個 Random(20261027)，依檔名排序逐首抽"""
    rng = random.Random(SEED)
    jittered = [base_estimate(r, lyric=jitter(r["human"], rng)) for r in records]
    jitter_safety = safety_gate(accepted_offsets(jittered))

    rng = random.Random(SEED)
    eligible, masked = [], []
    for record, e0 in zip(records, base):
        c = run_consensus(record.get("base")) if record.get("failure") is None else []
        anchors = [i for i, x in enumerate(c) if x is not None]
        if e0["cause"] in ("failure", "languageLowConfidence", "languageNotSupported") or len(anchors) < MASK_MIN_ANCHORS:
            continue
        excluded = frozenset(rng.sample(anchors, mask_count(len(anchors))))
        eligible.append((record, e0))
        masked.append(base_estimate(record, excluded=excluded))
    mask_safety = safety_gate(accepted_offsets(masked))
    mask_languages = by_language([r for r, _ in eligible], masked)
    lost = sum(1 for (_, e0), em in zip(eligible, masked) if e0["accepted"] and not em["accepted"])
    was = sum(1 for _, e0 in eligible if e0["accepted"])
    mask_ok = mask_safety["pass"] and all(mask_languages.get(lang, {"pass": False})["pass"] for lang in passed_languages)

    drifted = [base_estimate(r, lyric=drift(r["human"], run_consensus(r.get("base")) if r.get("failure") is None else []))
               for r in records]
    swapped = [base_estimate(r, lyric=swap_halves(r["human"])) for r in records]
    return {
        "jitter": {"safety": jitter_safety, "languages": by_language(records, jittered), "pass": jitter_safety["pass"]},
        "mask": {"eligible": len(eligible), "safety": mask_safety, "languages": mask_languages,
                 "rejectedAfterMask": lost, "acceptedBeforeMask": was, "pass": mask_ok},
        "drift": defect_rate(drifted, len(records)),
        "swap": defect_rate(swapped, len(records)),
    }


def song_row(record: Dict, e: Dict) -> Dict:
    """C-11：每首保存 offset、錨點行號、rᵢ、各條件值與拒答主因"""
    base = record.get("base") or {}
    return {"song": record["song"], "subset": record["subset"], "failure": record.get("failure"),
            "textLanguage": base.get("text"), "whisper": base.get("whisper"), **e}


def calibration_report(records: Sequence[Dict]) -> Dict:
    """G0-2″：安全閘（四語合併）→ 擾動 (a)–(d) → 準度閘（每種語言）；判定順序同 C-11"""
    records = sorted(records, key=lambda r: r["song"])
    base = [base_estimate(r) for r in records]
    offsets = accepted_offsets(base)
    languages = by_language(records, base)
    passed = [lang for lang, row in languages.items() if row["pass"]]
    safety = safety_gate(offsets)
    perturbed = perturbations(records, base, passed)
    causes: Dict[str, int] = {}
    for e in base:
        if not e["accepted"]:
            causes[e["cause"]] = causes.get(e["cause"], 0) + 1
    disagree = [(r, e) for r, e in zip(records, base)
                if r.get("failure") is None and "whisper" in r.get("base", {}) and r["base"]["whisper"] != r["base"]["text"]["language"]]
    if not safety["pass"]:
        verdict = "stop:safety"
    elif not all(perturbed[k]["pass"] for k in ("jitter", "mask", "drift", "swap")):
        verdict = "stop:perturbation"
    elif not passed:
        verdict = "stop:noLanguage"
    else:
        verdict = "pass"
    return {"songs": len(records), "accepted": len(offsets), "safety": safety,
            "overall": accuracy_gate(offsets, len(records)), "languages": languages, "passedLanguages": passed,
            "perturbations": perturbed, "rejectCauses": causes,
            "whisperDisagree": {"songs": len(disagree), "accepted": accepted_offsets([e for _, e in disagree])},
            "verdict": verdict, "perSong": [song_row(r, e) for r, e in zip(records, base)]}
