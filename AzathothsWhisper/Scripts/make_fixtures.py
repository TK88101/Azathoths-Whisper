#!/usr/bin/env python3
"""M0 特徵測試採集器：免副作用調用 lyrics_fetcher.py 純函數，生成 Swift 移植用 golden fixtures。

用法（在倉庫根目錄）：
    ./.venv/bin/python3 AzathothsWhisper/Scripts/make_fixtures.py

輸出：AzathothsWhisper/Tests/Fixtures/golden/*.json
紀律（Plan §5 M0 / 評審 H6）：
  - import lyrics_fetcher 前 stub 掉 dotenv/appscript/webview，環境變數清空——不觸發 .env 加載、
    不依賴 aeosa PYTHONPATH、不啟動任何 GUI。
  - golden 一律由「真實 Python 代碼路徑」在受控輸入下生成；唯二例外（darklyrics_normalize 的
    內聯正則、genius search JSON 的合成形狀）在各自 note 欄註明來源行號，屬經審核的手工部分。
  - token 全部使用假值；重跑本腳本應產生逐字節相同的輸出（冪等）。
"""
from __future__ import annotations

import importlib
import json
import os
import subprocess
import sys
import tempfile
import types
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Callable

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "AzathothsWhisper" / "Tests" / "Fixtures"
HTML_DIR = FIXTURES / "html"
GOLD_DIR = FIXTURES / "golden"


def load_lyrics_fetcher() -> Any:
    """Import lyrics_fetcher with side-effect modules stubbed out."""
    fake_dotenv = types.ModuleType("dotenv")
    fake_dotenv.load_dotenv = lambda *a, **k: False  # type: ignore[attr-defined]
    sys.modules["dotenv"] = fake_dotenv

    fake_appscript = types.ModuleType("appscript")
    fake_appscript.k = SimpleNamespace()  # type: ignore[attr-defined]
    fake_appscript.its = None  # type: ignore[attr-defined]
    fake_appscript.app = lambda *a, **k: None  # type: ignore[attr-defined]
    sys.modules["appscript"] = fake_appscript

    sys.modules["webview"] = types.ModuleType("webview")

    for key in ("GENIUS_ACCESS_TOKEN", "LANGUAGE"):
        os.environ.pop(key, None)

    sys.path.insert(0, str(REPO))
    return importlib.import_module("lyrics_fetcher")


lf = load_lyrics_fetcher()


def write_golden(name: str, payload: dict[str, Any]) -> None:
    path = GOLD_DIR / name
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )
    print(f"  wrote {path.relative_to(REPO)} ({len(payload['cases'])} cases)")


def read_html(name: str) -> str:
    return (HTML_DIR / name).read_text(encoding="utf-8", errors="replace")


# ---------------------------------------------------------------------------
# G1 sanitize_title（py:1201-1219，真實調用）
# ---------------------------------------------------------------------------

def gen_sanitize_title() -> None:
    inputs = [
        "Master of Puppets (Remastered 2009)",
        "The Trooper (Live)",
        "Aces High [Live]",
        "Painkiller (Remix)",
        "Battery (Demo)",
        "Creeping Death (Version 2)",
        "Duet (feat. Someone)",
        "Duet [ft. Someone Else]",
        "One - 2015 Remastered",
        "Fuel - Radio Remix",
        "Plain Title",
        "MONOCHROMATIC STAINS",
        "Song (remastered)",
        "Song (LIVE)",
        "Weird (Live) (Remix)",
        "Trailing (Remastered) ",
        "Mötley Song (Live)",
        "曲名 (Remix)",
        "Song (Acoustic)",
        "Song - Live at Wembley",
        "Song (feat. A) - 2021 Remastered",
        "(Live) Opening",
    ]
    cases = [
        {"input": s, "expected": lf.LyricsFetcher.sanitize_title(s)} for s in inputs
    ]
    write_golden(
        "sanitize_title.json",
        {
            "source": "lyrics_fetcher.py:1201-1219 sanitize_title（真實調用）",
            "note": "三條 IGNORECASE 正則依序替換後 strip；含大小寫/多重/Unicode/不匹配保留案例",
            "cases": cases,
        },
    )


# ---------------------------------------------------------------------------
# G2 darklyrics URL normalize（py:1305-1306 內聯正則的逐字拷貝——手工部分，經審核）
# ---------------------------------------------------------------------------

def gen_darklyrics_normalize() -> None:
    import re as _re

    def normalize(s: str) -> str:
        return _re.sub(r"[^a-z0-9]", "", s.lower())  # verbatim py:1305

    inputs = [
        "Dark Tranquillity",
        "Mötley Crüe",
        "Iron Maiden",
        "AC/DC",
        "Blue Öyster Cult",
        "Motörhead",
        "Dr. Feelgood",
        "36 Crazyfists",
        "Sigur Rós",
        "上海 Band 123",
        "Damage Done",
        "Master of Puppets",
    ]
    cases = [{"input": s, "expected": normalize(s)} for s in inputs]
    write_golden(
        "darklyrics_normalize.json",
        {
            "source": "lyrics_fetcher.py:1305-1306（內聯表達式逐字拷貝）",
            "note": "手工部分（評審 H6 允許）：表達式為 re.sub(r'[^a-z0-9]','',x.lower()) 的逐字拷貝；"
            "關鍵語義＝先 lower 再刪除一切非 ASCII 小寫字母數字（變音符號/CJK/標點/空格全刪）。"
            "Swift 側必須用同語義（NSRegularExpression 對 BMP 外字符的處理需對照本表驗證）",
            "cases": cases,
        },
    )


# ---------------------------------------------------------------------------
# G3 _parse_darklyrics_page（py:1371-1432，真實調用，真實專輯頁 fixture）
# ---------------------------------------------------------------------------

def _page_h3_titles(html: str) -> list[str]:
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html, "html.parser")
    div = soup.find("div", class_="lyrics")
    if not div:
        return []
    import re as _re

    return [_re.sub(r"^\d+\.\s*", "", h.get_text().strip()) for h in div.find_all("h3")]


def gen_darklyrics_parse() -> None:
    pages = [
        "darklyrics_metallica_masterofpuppets.html",
        "darklyrics_ironmaiden_pieceofmind.html",
        "darklyrics_motleycrue_drfeelgood.html",
        "darklyrics_darktranquillity_moment.html",
        "darklyrics_darktranquillity_damagedone.html",
    ]
    cases: list[dict[str, Any]] = []
    for page in pages:
        html = read_html(page)
        titles = _page_h3_titles(html)
        # 每頁取首曲＋中段一曲（真實命中），外加逐頁一個場景變體
        picks = [t for t in (titles[:1] + titles[len(titles) // 2 : len(titles) // 2 + 1]) if t]
        for t in picks:
            cases.append(
                {
                    "page": page,
                    "target_title": t,
                    "expected": lf.LyricsFetcher._parse_darklyrics_page(html, t),
                }
            )
        if titles:
            # 模糊匹配場景：帶 (Remastered) 尾綴仍應命中（sanitize 後雙向 substring）
            fuzzy = f"{titles[0]} (Remastered 2009)"
            cases.append(
                {
                    "page": page,
                    "target_title": fuzzy,
                    "expected": lf.LyricsFetcher._parse_darklyrics_page(html, fuzzy),
                }
            )
    # 未命中與空容器場景
    html0 = read_html(pages[0])
    cases.append(
        {
            "page": pages[0],
            "target_title": "Nonexistent Song Title XYZ",
            "expected": lf.LyricsFetcher._parse_darklyrics_page(
                html0, "Nonexistent Song Title XYZ"
            ),
        }
    )
    cases.append(
        {
            "page": "(inline) <html><body>no lyrics div</body></html>",
            "target_title": "Anything",
            "expected": lf.LyricsFetcher._parse_darklyrics_page(
                "<html><body>no lyrics div</body></html>", "Anything"
            ),
        }
    )
    write_golden(
        "darklyrics_parse.json",
        {
            "source": "lyrics_fetcher.py:1371-1432 _parse_darklyrics_page（真實調用，真實頁面）",
            "note": "expected 為完整解析輸出；page 欄指向 Tests/Fixtures/html/ 下的原始頁面",
            "cases": cases,
        },
    )


# ---------------------------------------------------------------------------
# G4 fetch_genius 手動 fallback（py:1245-1276，真實調用；lyricsgenius 強制失敗、requests 路由 fixture）
# ---------------------------------------------------------------------------

class _FakeResp:
    def __init__(self, status: int = 200, text: str = "", json_data: Any = None) -> None:
        self.status_code = status
        self.text = text
        self._json = json_data

    def json(self) -> Any:
        return self._json


def _run_fetch_genius_manual(page_html: str, artist: str, title: str) -> str:
    class BoomGenius:
        def __init__(self, *a: Any, **k: Any) -> None:
            self.remove_section_headers = False

        def search_song(self, *a: Any, **k: Any) -> Any:
            raise RuntimeError("forced fallback for fixture capture")

    song_url = "https://genius.local/fixture-page"
    search_json = {  # 合成形狀（手工部分）：對齊 py:1252-1256 讀取的字段
        "response": {"hits": [{"result": {"url": song_url}}]}
    }

    def fake_get(url: str, params: Any = None, headers: Any = None, timeout: Any = None) -> _FakeResp:
        if url == "https://api.genius.com/search":
            return _FakeResp(200, "", search_json)
        if url == song_url:
            return _FakeResp(200, page_html)
        raise AssertionError(f"unexpected URL {url}")

    orig_genius = lf.lyricsgenius.Genius
    orig_get = lf.requests.get
    try:
        lf.lyricsgenius.Genius = BoomGenius  # type: ignore[assignment]
        lf.requests.get = fake_get  # type: ignore[assignment]
        return lf.LyricsFetcher.fetch_genius(artist, title, "fake-token")
    finally:
        lf.lyricsgenius.Genius = orig_genius
        lf.requests.get = orig_get


def gen_genius_manual_parse() -> None:
    pages = [
        ("genius_Metallica-master-of-puppets.html", "Metallica", "Master of Puppets"),
        ("genius_Iron-maiden-the-trooper.html", "Iron Maiden", "The Trooper"),
        (
            "genius_Dark-tranquillity-monochromatic-stains.html",
            "Dark Tranquillity",
            "Monochromatic Stains",
        ),
        ("genius_Judas-priest-painkiller.html", "Judas Priest", "Painkiller"),
    ]
    cases = []
    for page, artist, title in pages:
        cases.append(
            {
                "page": page,
                "artist": artist,
                "title": title,
                "expected": _run_fetch_genius_manual(read_html(page), artist, title),
            }
        )
    # 無容器頁：走到 "(Auto-scrape failed)" 分支
    cases.append(
        {
            "page": "(inline) <html><body><p>nothing here</p></body></html>",
            "artist": "X",
            "title": "Y",
            "expected": _run_fetch_genius_manual(
                "<html><body><p>nothing here</p></body></html>", "X", "Y"
            ),
        }
    )
    write_golden(
        "genius_manual_parse.json",
        {
            "source": "lyrics_fetcher.py:1245-1276 手動 fallback（真實調用；search JSON 為合成形狀，"
            "對齊 py:1252-1256；頁面為真實 Genius 存檔）",
            "note": "選擇器＝div[class*=Lyrics__Container]，多容器 get_text('\\n') 後 '\\n' join 再 strip；"
            "無容器→舊版 div.lyrics→'Found lyrics at: {url} (Auto-scrape failed)'",
            "cases": cases,
        },
    )


# ---------------------------------------------------------------------------
# G5a lyricsgenius 庫解析＋清洗（venv lyricsgenius 3.7.5 genius.py:126-206，真實調用，
#     _make_request 打樁餵真實頁面）
# ---------------------------------------------------------------------------

def gen_genius_library_clean() -> None:
    import lyricsgenius

    pages = [
        "genius_Metallica-master-of-puppets.html",
        "genius_Iron-maiden-the-trooper.html",
        "genius_Dark-tranquillity-monochromatic-stains.html",
        "genius_Judas-priest-painkiller.html",
    ]
    orig_make_request = lyricsgenius.Genius._make_request
    cases = []
    try:
        for page in pages:
            html = read_html(page)
            lyricsgenius.Genius._make_request = (  # type: ignore[method-assign]
                lambda self, path, web=False, _h=html: {"html": _h}
            )
            g = lyricsgenius.Genius("fake-token", verbose=False)
            g.remove_section_headers = True
            out = g.lyrics(song_url="https://genius.com/fixture")
            cases.append({"page": page, "remove_section_headers": True, "expected": out})
    finally:
        lyricsgenius.Genius._make_request = orig_make_request  # type: ignore[method-assign]
    write_golden(
        "genius_library_clean.json",
        {
            "source": ".venv lyricsgenius 3.7.5 genius.py:126-206 lyrics()（真實調用，_make_request 打樁）",
            "note": "庫路徑選擇器＝div[data-lyrics-container=true]（與手動 fallback 的 Lyrics__Container 不同！）；"
            "先刪 LyricsHeader div；br→\\n、Tag get_text('\\n')、排除 data-exclude-from-selection；"
            "段頭剝除 re.sub(r'(\\[.*?\\])*','')＋re.sub('\\n{2}','\\n')；最後 strip('\\n')。"
            "Swift 單管線的驗收口徑＝本表最終文本一致（Plan R3）",
            "cases": cases,
        },
    )


# ---------------------------------------------------------------------------
# G5b fetch_genius 庫路徑首行清洗（py:1236-1241，真實調用；search_song 打樁）
# ---------------------------------------------------------------------------

def _run_fetch_genius_library(stub_lyrics: str) -> str:
    class StubGenius:
        def __init__(self, *a: Any, **k: Any) -> None:
            self.remove_section_headers = False

        def search_song(self, *a: Any, **k: Any) -> Any:
            return SimpleNamespace(lyrics=stub_lyrics)

    orig_genius = lf.lyricsgenius.Genius
    try:
        lf.lyricsgenius.Genius = StubGenius  # type: ignore[assignment]
        return lf.LyricsFetcher.fetch_genius("A", "T", "fake-token")
    finally:
        lf.lyricsgenius.Genius = orig_genius


def gen_genius_library_firstline() -> None:
    inputs = [
        "Master of Puppets Lyrics\nEnd of passion play\nCrumbling away",
        "No header here\nJust lyrics",
        "Something Lyrics\n\nBody after blank line\n",
        "  Padded Lyrics\nBody",  # 首行 strip 後以 Lyrics 結尾 → 剝除
        "Lyrics\nOnly-header-word line dropped",
        "Body without trailing newline",
    ]
    cases = [{"input": s, "expected": _run_fetch_genius_library(s)} for s in inputs]
    write_golden(
        "genius_library_firstline.json",
        {
            "source": "lyrics_fetcher.py:1236-1241（真實調用，search_song 打樁返回 input）",
            "note": "首行 strip 後 endswith('Lyrics') 則整行剝除，其後 '\\n'.join 再 strip",
            "cases": cases,
        },
    )


# ---------------------------------------------------------------------------
# G6 fetch_darklyrics 流程（py:1286-1369，真實調用；session 打樁記錄請求，鎖 URL/查詢構造與錯誤文案）
# ---------------------------------------------------------------------------

class _FakeSession:
    def __init__(self, get_routes: dict[str, _FakeResp], post_resp: _FakeResp | None) -> None:
        self.get_routes = get_routes
        self.post_resp = post_resp
        self.get_urls: list[str] = []
        self.post_data: list[dict[str, Any]] = []

    def get(self, url: str, timeout: Any = None, params: Any = None, headers: Any = None) -> _FakeResp:
        self.get_urls.append(url)
        return self.get_routes.get(url, _FakeResp(404, "not found"))

    def post(self, url: str, data: Any = None, headers: Any = None, timeout: Any = None) -> _FakeResp:
        self.post_data.append(dict(data or {}))
        return self.post_resp if self.post_resp is not None else _FakeResp(500, "")


def _run_darklyrics_flow(
    artist: str,
    title: str,
    album: str,
    get_routes: dict[str, _FakeResp],
    post_resp: _FakeResp | None,
) -> dict[str, Any]:
    session = _FakeSession(get_routes, post_resp)
    orig_create = lf.cloudscraper.create_scraper
    try:
        lf.cloudscraper.create_scraper = lambda **k: session  # type: ignore[assignment]
        result = lf.LyricsFetcher.fetch_darklyrics(artist, title, album)
    finally:
        lf.cloudscraper.create_scraper = orig_create
    return {
        "artist": artist,
        "title": title,
        "album": album,
        "requested_get_urls": session.get_urls,
        "posted_queries": [d.get("q", "") for d in session.post_data],
        "expected": result,
    }


def gen_darklyrics_flow() -> None:
    damage_html = read_html("darklyrics_darktranquillity_damagedone.html")
    ddg_html = read_html("ddg_lite_darktranquillity.html")
    direct_url = "http://www.darklyrics.com/lyrics/darktranquillity/damagedone.html"
    ddg_url = "https://lite.duckduckgo.com/lite/"

    cases = [
        # 1. 直連命中（決策 5 的快路徑）
        _run_darklyrics_flow(
            "Dark Tranquillity",
            "Monochromatic Stains",
            "Damage Done",
            {direct_url: _FakeResp(200, damage_html)},
            None,
        ),
        # 2. 直連 404 → DDG POST → 追鏈接到專輯頁
        _run_darklyrics_flow(
            "Dark Tranquillity",
            "Monochromatic Stains",
            "Wrong Album Name",
            {
                "http://www.darklyrics.com/lyrics/darktranquillity/wrongalbumname.html": _FakeResp(404, ""),
                direct_url: _FakeResp(200, damage_html),
            },
            _FakeResp(200, ddg_html),
        ),
        # 3. 無 album（原版批處理路徑）→ 直接 DDG
        _run_darklyrics_flow(
            "Dark Tranquillity",
            "Monochromatic Stains",
            "",
            {direct_url: _FakeResp(200, damage_html)},
            _FakeResp(200, ddg_html),
        ),
        # 4. DDG POST/GET 全部非 200 → 封鎖文案
        _run_darklyrics_flow(
            "Dark Tranquillity",
            "Monochromatic Stains",
            "",
            {ddg_url: _FakeResp(403, "")},
            _FakeResp(403, ""),
        ),
        # 5. DDG 200 但無 darklyrics 鏈接 → not found 文案
        _run_darklyrics_flow(
            "Dark Tranquillity",
            "Monochromatic Stains",
            "",
            {},
            _FakeResp(200, "<html><body><a class='result-link' href='https://example.com/x'>x</a></body></html>"),
        ),
    ]
    write_golden(
        "darklyrics_flow.json",
        {
            "source": "lyrics_fetcher.py:1286-1369 fetch_darklyrics（真實調用，session 打樁）",
            "note": "requested_get_urls 鎖 URL 構造；posted_queries 鎖 DDG 查詢串 "
            "site:darklyrics.com \"artist\" \"title\"；expected 鎖成功文本與三種錯誤文案。"
            "案例 2/3 的 DDG 頁為真實存檔（指向 damagedone.html）",
            "cases": cases,
        },
    )


# ---------------------------------------------------------------------------
# G7 config 遷移（py:1565-1609，真實調用；_config_path 指向臨時目錄，token 全假值）
# ---------------------------------------------------------------------------

def _run_load_config(
    file_content: str | None, env_token: str | None, env_lang: str | None
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory() as tmp:
        cfg = Path(tmp) / "config"
        if file_content is not None:
            cfg.write_text(file_content, encoding="utf-8")
        orig_path = lf.ConfigManager._config_path
        orig_env = {
            k: os.environ.get(k) for k in ("GENIUS_ACCESS_TOKEN", "LANGUAGE")
        }
        try:
            lf.ConfigManager._config_path = str(cfg)
            for k, v in (("GENIUS_ACCESS_TOKEN", env_token), ("LANGUAGE", env_lang)):
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
            return lf.ConfigManager.load_config()
        finally:
            lf.ConfigManager._config_path = orig_path
            for k, v in orig_env.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v


def gen_config_migration() -> None:
    combos: list[dict[str, Any]] = [
        {"desc": "無檔無 env", "file": None, "env_token": None, "env_lang": None},
        {"desc": "無檔，env 雙鍵", "file": None, "env_token": "fake-token-env", "env_lang": "ja"},
        {
            "desc": "JSON 檔無 env",
            "file": '{"token": "fake-token-file", "language": "zh_TW"}',
            "env_token": None,
            "env_lang": None,
        },
        {
            "desc": "JSON 檔＋env token（env 應覆蓋 token、保留檔內 language）",
            "file": '{"token": "fake-token-file", "language": "zh_TW"}',
            "env_token": "fake-token-env",
            "env_lang": None,
        },
        {
            "desc": "舊格式裸 token 檔（JSONDecodeError 遷移路徑）",
            "file": "fake-legacy-raw-token",
            "env_token": None,
            "env_lang": None,
        },
        {
            "desc": "舊格式裸 token＋env LANGUAGE",
            "file": "fake-legacy-raw-token",
            "env_token": None,
            "env_lang": "ja",
        },
        {
            "desc": "JSON 檔缺 language 鍵（defaults 補齊）",
            "file": '{"token": "fake-token-file"}',
            "env_token": None,
            "env_lang": None,
        },
    ]
    cases = []
    for c in combos:
        cases.append(
            {
                **c,
                "expected": _run_load_config(c["file"], c["env_token"], c["env_lang"]),
            }
        )
    write_golden(
        "config_migration.json",
        {
            "source": "lyrics_fetcher.py:1565-1609 load_config（真實調用，臨時目錄＋假 token）",
            "note": "優先級 env > JSON > defaults；裸 token 檔走 JSONDecodeError 遷移且 language=system；"
            "Swift LegacyConfigMigrator 首次遷移的讀取語義以本表為準（遷移後改 Keychain 真源，Plan §4.9）",
            "cases": cases,
        },
    )


# ---------------------------------------------------------------------------
# G8 語言檢測映射（py:1621-1644，真實調用；subprocess.check_output 打樁）
# ---------------------------------------------------------------------------

def _run_detect(app_out: str | None, global_out: str | None) -> str:
    def fake_check_output(cmd: str, shell: bool = False, stderr: Any = None) -> bytes:
        is_app = "com.ibridgezhao.azathothswhisper" in cmd
        out = app_out if is_app else global_out
        if out is None:
            raise subprocess.CalledProcessError(1, cmd)
        return out.encode("utf-8")

    orig = lf.subprocess.check_output
    try:
        lf.subprocess.check_output = fake_check_output  # type: ignore[assignment]
        return lf.ConfigManager.detect_system_language()
    finally:
        lf.subprocess.check_output = orig


def gen_language_mapping() -> None:
    combos = [
        {"app": '(\n    "zh-Hant-TW",\n    "en"\n)', "global": None},
        {"app": '(\n    "ja-JP"\n)', "global": None},
        {"app": '(\n    "en-US"\n)', "global": None},
        {"app": '(\n    "zh-TW"\n)', "global": None},
        {"app": None, "global": '(\n    "zh-Hant-TW",\n    "en"\n)'},
        {"app": None, "global": '(\n    "ja-JP",\n    "en"\n)'},
        {"app": None, "global": '(\n    "en-US"\n)'},
        {"app": None, "global": None},
        # app 域無匹配值時繼續查全局（隱性行為，必鎖）
        {"app": '(\n    "fr-FR"\n)', "global": '(\n    "ja-JP"\n)'},
        # app 域 en 判定在 zh/ja 之後（優先序）
        {"app": '(\n    "zh-Hant-TW",\n    "en-US"\n)', "global": None},
    ]
    cases = [
        {
            "app_defaults": c["app"],
            "global_defaults": c["global"],
            "expected": _run_detect(c["app"], c["global"]),
        }
        for c in combos
    ]
    write_golden(
        "language_mapping.json",
        {
            "source": "lyrics_fetcher.py:1621-1644 detect_system_language（真實調用，defaults 輸出打樁）",
            "note": "app 域判定順序 zh→ja→en；app 域無匹配則落到全局域（zh→ja，無 en 分支→默認 en）；"
            "Swift LanguageManager 的 legacy 兼容讀取以本表為準（Plan §4.6）",
            "cases": cases,
        },
    )


# ---------------------------------------------------------------------------

def main() -> None:
    GOLD_DIR.mkdir(parents=True, exist_ok=True)
    generators: list[tuple[str, Callable[[], None]]] = [
        ("G1 sanitize_title", gen_sanitize_title),
        ("G2 darklyrics_normalize", gen_darklyrics_normalize),
        ("G3 darklyrics_parse", gen_darklyrics_parse),
        ("G4 genius_manual_parse", gen_genius_manual_parse),
        ("G5a genius_library_clean", gen_genius_library_clean),
        ("G5b genius_library_firstline", gen_genius_library_firstline),
        ("G6 darklyrics_flow", gen_darklyrics_flow),
        ("G7 config_migration", gen_config_migration),
        ("G8 language_mapping", gen_language_mapping),
    ]
    for name, fn in generators:
        print(name)
        fn()
    print("done.")


if __name__ == "__main__":
    main()
