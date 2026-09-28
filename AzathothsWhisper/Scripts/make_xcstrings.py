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
    # 歌詞寫入通知（docs/plans/2026-09-26-lyrics-notification.md §3.3；版式＝樣式 A）
    "notify_subtitle": {"en": "%1$@ · %2$@", "zh_TW": "%1$@ · 《%2$@》", "ja": "%1$@ · 『%2$@』"},
    "notify_list_separator": {"en": ", ", "zh_TW": "、", "ja": "、"},
    "notify_single_ok": {"en": "Lyrics saved for \"%@\"", "zh_TW": "「%@」歌詞寫入成功", "ja": "「%@」の歌詞を書き込みました"},
    "notify_batch_full": {"en": "Lyrics saved for all %lld tracks", "zh_TW": "整張專輯 %lld 首歌詞寫入成功", "ja": "アルバム全 %lld 曲の歌詞を書き込みました"},
    "notify_batch_some": {"en": "Lyrics saved for %1$lld tracks: %2$@", "zh_TW": "%1$lld 首歌詞寫入成功：%2$@", "ja": "%1$lld 曲の歌詞を書き込みました：%2$@"},
    "notify_batch_partial": {"en": "%1$lld/%2$lld saved, %3$lld failed: %4$@", "zh_TW": "%1$lld / %2$lld 首寫入成功，%3$lld 首失敗：%4$@", "ja": "%1$lld/%2$lld 曲成功、%3$lld 曲失敗：%4$@"},
    "notify_batch_all_failed": {"en": "Failed to save lyrics for %lld tracks", "zh_TW": "%lld 首歌詞全部寫入失敗", "ja": "%lld 曲すべての書き込みに失敗しました"},
    # 參數＝未列出的剩餘首數（三語同義；zh 原稿「等 N 首」為總數，2026-09-27 統一為剩餘數）
    "notify_more": {"en": "and %lld more", "zh_TW": "及另外 %lld 首", "ja": "ほか %lld 曲"},
    "settings_notify_label": {"en": "Notifications", "zh_TW": "通知", "ja": "通知"},
    "settings_notify_toggle": {"en": "Notify when lyrics are saved", "zh_TW": "歌詞寫入後顯示系統通知", "ja": "歌詞の書き込み後に通知する"},
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
