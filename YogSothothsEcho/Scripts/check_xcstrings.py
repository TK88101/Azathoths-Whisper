"""iPad 文案三語檢查（N-10；sprint-1-detail.md §4.7）。

① Resources/*.xcstrings 的每個 key 都要有 en／zh-Hant／ja，state＝translated、值非空。
② App／Features／UI 程式碼裡會被本地化的字面量（Text／Picker／Button／Label／String(localized:)／LocalizedStringKey(…)／LocalizedStringResource(…)，
   以及型別為 LocalizedStringKey 的計算屬性裡的字面量）都要在 Localizable.xcstrings 裡。Text(verbatim:) 不算。

用法：python3 -I Scripts/check_xcstrings.py [--root <YogSothothsEcho 目錄>]；有缺 → stderr 列出、退出 1。
"""
import json
import pathlib
import re
import sys

LANGS = ("en", "zh-Hant", "ja")
CODE_DIRS = ("App", "Features", "UI")
CALL = re.compile(r'\b(?:Text|Picker|Button|Label|Toggle|LocalizedStringKey|LocalizedStringResource)\(\s*"((?:[^"\\]|\\.)+)"'
                  r'|String\(localized:\s*"((?:[^"\\]|\\.)+)"')
KEY_PROPERTY = re.compile(r":\s*LocalizedStringKey\s*\{")
LITERAL = re.compile(r'"((?:[^"\\]|\\.)+)"')


def catalog_problems(path):
    problems = []
    data = json.loads(path.read_text(encoding="utf-8"))
    for key, entry in sorted(data.get("strings", {}).items()):
        localizations = entry.get("localizations", {})
        for lang in LANGS:
            localization = localizations.get(lang, {})
            plural = localization.get("variations", {}).get("plural")
            if plural is not None and "other" not in plural:
                problems.append(f"{path.name}: {key!r} 的 {lang} 單複數變化缺 other")
            units = ([(f"{lang}/{case}", case_entry.get("stringUnit")) for case, case_entry in sorted(plural.items())]
                     if plural is not None else [(lang, localization.get("stringUnit"))])
            for label, unit in units:
                if unit is None:
                    problems.append(f"{path.name}: {key!r} 缺 {label}")
                elif unit.get("state") != "translated":
                    problems.append(f"{path.name}: {key!r} 的 {label} 狀態是 {unit.get('state')}")
                elif not unit.get("value", "").strip():
                    problems.append(f"{path.name}: {key!r} 的 {label} 是空值")
    return problems, set(data.get("strings", {}))


def block_after(text, start):
    """從 start 位置的 { 起，回傳配對的大括號區塊內容"""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return text[start:]


def keys_in_code(text):
    keys = {m.group(1) or m.group(2) for m in CALL.finditer(text)}
    for m in KEY_PROPERTY.finditer(text):
        keys |= set(LITERAL.findall(block_after(text, m.end() - 1)))
    return keys


INTERPOLATION = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")
FORMAT_SPEC = r"%(?:\d+\$)?[-#+ 0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?[@dDiuUxXoOfeEgGcCsSpaAF]"


def is_known(key, known):
    """字面量含 \\(…) 插值時，SwiftUI 以格式字串（%lld、%@…）查 key：把每段插值當成一個格式指定子比對"""
    if key in known:
        return True
    parts = INTERPOLATION.split(key)
    if len(parts) == 1:
        return False
    pattern = re.compile(FORMAT_SPEC.join(re.escape(part) for part in parts))
    return any(pattern.fullmatch(candidate) for candidate in known)


def main(argv):
    root = pathlib.Path(argv[argv.index("--root") + 1]) if "--root" in argv else pathlib.Path(__file__).resolve().parent.parent
    problems, known = [], set()
    for catalog in sorted((root / "Resources").glob("*.xcstrings")):
        found, keys = catalog_problems(catalog)
        problems += found
        if catalog.name == "Localizable.xcstrings":
            known = keys
    for folder in CODE_DIRS:
        for file in sorted((root / folder).rglob("*.swift")) if (root / folder).is_dir() else []:
            for key in sorted(k for k in keys_in_code(file.read_text(encoding="utf-8")) if not is_known(k, known)):
                problems.append(f"{file.relative_to(root)}: {key!r} 不在 Localizable.xcstrings")
    for line in problems:
        print(line, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
