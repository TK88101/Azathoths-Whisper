#!/usr/bin/env python3
"""從 lyrics_fetcher.py 的 TRANSLATIONS 生成 Localizable.xcstrings（三語 String Catalog）。

用法（倉庫根目錄）：./.venv/bin/python3 AzathothsWhisper/Scripts/make_xcstrings.py
修正項（Plan 決策 4，附錄 A #3/#4）：
  - en.status_ready "準備完了" → "Ready"
  - en 補 batch_fetch/batch_import/batch_all（值＝HTML 內建默認文本，觀察行為不變）
新增鍵（Plan §4.6）：nav_coverflow 三語。
語言映射：zh_TW → zh-Hant。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "AzathothsWhisper" / "Scripts"))
from make_fixtures import lf  # 復用免副作用加載（stub dotenv/appscript/webview）

OUT = REPO / "AzathothsWhisper" / "Resources" / "Localizable.xcstrings"

EN_FIXES = {
    "status_ready": "Ready",
    "batch_fetch": "Fetch Missing",
    "batch_import": "Import Selected",
    "batch_all": "Import All",
}
NEW_KEYS = {
    "nav_coverflow": {"en": "Cover Flow", "zh_TW": "封面瀏覽", "ja": "カバーフロー"},
    # Cover Flow × 找歌詞（docs/plans/2026-09-23-coverflow-queue-drawer.md §9.5）
    "mark_no_lyrics": {"en": "No lyrics for this song", "zh_TW": "這首沒有歌詞", "ja": "この曲は歌詞なし"},
    "lyrics_status_present": {"en": "Lyrics in file", "zh_TW": "已有歌詞", "ja": "歌詞あり"},
    "lyrics_status_missing": {"en": "Missing lyrics", "zh_TW": "缺少歌詞", "ja": "歌詞なし"},
    "lyrics_status_marked": {"en": "Marked: no lyrics", "zh_TW": "已標記：沒有歌詞", "ja": "歌詞なしとして記録済み"},
    "lyrics_status_unknown": {"en": "Lyrics unreadable", "zh_TW": "讀不到歌詞", "ja": "歌詞を読み取れません"},
    "edit_lyrics_hint": {"en": "Edit lyrics", "zh_TW": "編輯歌詞", "ja": "歌詞を編集"},
    "upnext_unavailable": {"en": "Up next isn't available right now", "zh_TW": "接下來的歌暫時讀不到", "ja": "次の曲を読み取れません"},
    "coverflow_show": {"en": "Show Cover Flow", "zh_TW": "顯示封面瀏覽", "ja": "カバーフローを表示"},
    "coverflow_hide": {"en": "Hide Cover Flow", "zh_TW": "隱藏封面瀏覽", "ja": "カバーフローを隠す"},
    # 鍵名帶 %@：SwiftUI 的 Text("edit_lyrics_of \(title)") 以插值後的格式字串當鍵查找
    "edit_lyrics_of %@": {"en": "Edit lyrics of %@", "zh_TW": "編輯「%@」的歌詞", "ja": "「%@」の歌詞を編集"},
}
LANG_MAP = {"en": "en", "zh_TW": "zh-Hant", "ja": "ja"}


def main() -> None:
    translations: dict[str, dict[str, str]] = {
        lang: dict(table) for lang, table in lf.TRANSLATIONS.items()
    }
    translations["en"].update(EN_FIXES)
    for key, values in NEW_KEYS.items():
        for lang, value in values.items():
            translations[lang][key] = value

    all_keys = sorted(set().union(*(t.keys() for t in translations.values())))
    strings: dict[str, dict] = {}
    for key in all_keys:
        localizations = {}
        for lang, table in translations.items():
            if key in table:
                localizations[LANG_MAP[lang]] = {
                    "stringUnit": {"state": "translated", "value": table[key]}
                }
        strings[key] = {"extractionState": "manual", "localizations": localizations}

    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {OUT.relative_to(REPO)}: {len(all_keys)} keys × {len(translations)} langs")


if __name__ == "__main__":
    main()
