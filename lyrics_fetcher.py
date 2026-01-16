#!/usr/bin/env python3
"""
Mac Music Lyrics Fetcher
A lightweight, surgical tool to fetch lyrics for the currently playing Apple Music track.
Dependencies:
    pip install appscript lyricsgenius requests beautifulsoup4
"""

import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import threading
import queue
import re
import json
import time
import subprocess
import locale

# Third-party libraries
try:
    import appscript
    import requests
    from bs4 import BeautifulSoup
    import lyricsgenius
    import cloudscraper
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Please install required packages: pip install appscript lyricsgenius requests beautifulsoup4 cloudscraper")
    exit(1)

from dotenv import load_dotenv
import os

# Load environment variables
# Priority:
# 1. Standard load_dotenv() (CWD)
# 2. explicit path in ~/Documents/Bjork/.env (For bundled app)

import sys

# Try standard first
loaded = load_dotenv()

if not loaded:
    # Try hardcoded path for the bundled app user
    env_path = os.path.expanduser("~/Documents/Bjork/.env")
    if os.path.exists(env_path):
        load_dotenv(env_path)
    else:
        # Try relative to executable if in dist
        if getattr(sys, 'frozen', False):
            bundle_dir = os.path.dirname(sys.executable)
            load_dotenv(os.path.join(bundle_dir, '.env'))

# Constants
GENIUS_ACCESS_TOKEN = os.getenv("GENIUS_ACCESS_TOKEN")
if GENIUS_ACCESS_TOKEN:
    print(f"Loaded Token: {GENIUS_ACCESS_TOKEN[:4]}...{GENIUS_ACCESS_TOKEN[-4:]}")
else:
    print("Warning: GENIUS_ACCESS_TOKEN is not set.")

USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36"

# Localization Dictionary
TRANSLATIONS = {
    "en": {
        "app_title": "Azathoth's Whisper",
        "source": "Source:",
        "fetch_btn": "Fetch Lyrics",
        "write_btn": "Write to iTunes",
        "settings_menu": "Settings",
        "pref_menu": "Preferences...",
        "menu_token": "Genius Token Settings...",
        "menu_lang": "Language Settings...",
        "status_ready": "Ready",
        "status_saved": "Saved to metadata.",
        "status_limit_msg": "Fetching...",
        "status_fetching": "Fetching from {}...",
        "status_complete": "Fetch complete.",
        "msg_no_track": "No track is currently playing in Music.",
        "msg_success": "Lyrics written to iTunes track!",
        "msg_fail": "Failed to write to iTunes. Track might be read-only (streaming) or app unreachable.",
        "settings_title": "Settings",
        "token_label": "Genius Access Token:",
        "lang_label": "Language / 語言 / 言語 (Restart Required):",
        "save_btn": "Save",
        "saved_title": "Saved",
        "saved_msg": "Settings saved! Please restart the app for language changes to take effect.",
        "saved_token_msg": "Token saved!",
        "warning_token_empty": "Token cannot be empty.",
        "not_playing": "Not Playing",
        "music_not_playing": "Music not playing / paused",
        "track_detected": "Track detected.",
        "err_validation": "Validation Error",
        "err_no_track": "No track playing.",
        "warn_empty_lyrics": "Lyrics are empty. This will clear existing lyrics. Continue?",
        "welcome": "Welcome",
        "welcome_msg": "Please set your Genius Access Token in Settings.",
        "lyrics_not_found": "No lyrics found.",
        "manual_check": "Check Track"
    },
    "zh_TW": {
        "app_title": "Azathoth's Whisper (阿撒托斯之低語)",
        "source": "來源:",
        "fetch_btn": "獲取歌詞",
        "write_btn": "寫入 iTunes",
        "settings_menu": "設置",
        "pref_menu": "偏好設置...",
        "menu_token": "Genius Token 設置...",
        "menu_lang": "語言設置...",
        "status_ready": "就緒",
        "status_saved": "已保存至元數據。",
        "status_limit_msg": "獲取中...",
        "status_fetching": "正在從 {} 獲取...",
        "status_complete": "獲取完成。",
        "msg_no_track": "Music 目前沒有播放曲目。",
        "msg_success": "歌詞已寫入 iTunes 曲目！",
        "msg_fail": "寫入 iTunes 失敗。曲目可能是唯讀的 (串流) 或應用程序無法連接。",
        "settings_title": "設置",
        "token_label": "Genius Access Token:",
        "lang_label": "語言 / Language / 言語 (需重啟生效):",
        "save_btn": "保存",
        "saved_title": "已保存",
        "saved_msg": "設置已保存！請重啟應用程序以應用語言更改。",
        "saved_token_msg": "Token 已保存！",
        "warning_token_empty": "Token 不能為空。",
        "not_playing": "未播放",
        "music_not_playing": "Music 未播放 / 已暫停",
        "track_detected": "檢測到曲目。",
        "err_validation": "驗證錯誤",
        "err_no_track": "沒有播放曲目。",
        "warn_empty_lyrics": "歌詞為空。這將清除現有歌詞。繼續嗎？",
        "welcome": "歡迎",
        "welcome_msg": "請在設置中設置您的 Genius Access Token。",
        "lyrics_not_found": "未找到歌詞。",
        "manual_check": "檢查曲目"
    },
    "ja": {
        "app_title": "Azathoth's Whisper (アザトースの囁き)",
        "source": "ソース:",
        "fetch_btn": "歌詞を取得",
        "write_btn": "iTunesに書き込み",
        "settings_menu": "設定",
        "pref_menu": "環境設定...",
        "menu_token": "Genius Token 設定...",
        "menu_lang": "言語設定...",
        "status_ready": "準備完了",
        "status_saved": "メタデータに保存しました。",
        "status_limit_msg": "取得中...",
        "status_fetching": "{} から取得中...",
        "status_complete": "取得完了。",
        "msg_no_track": "Musicで再生中の曲がありません。",
        "msg_success": "iTunesの曲に歌詞を書き込みました！",
        "msg_fail": "iTunesへの書き込みに失敗しました。トラックが読み取り専用（ストリーミング）か、アプリに接続できません。",
        "settings_title": "設定",
        "token_label": "Genius Access Token:",
        "lang_label": "言語 / Language / 語言 (再起動が必要):",
        "save_btn": "保存",
        "saved_title": "保存しました",
        "saved_msg": "設定を保存しました！言語変更を適用するにはアプリを再起動してください。",
        "saved_token_msg": "トークンを保存しました！",
        "warning_token_empty": "トークンは空にできません。",
        "not_playing": "再生していません",
        "music_not_playing": "Musicは再生されていないか、一時停止中です",
        "track_detected": "トラックを検出しました。",
        "err_validation": "検証エラー",
        "err_no_track": "再生中の曲がありません。",
        "warn_empty_lyrics": "歌詞が空です。既存の歌詞を消去しますか？",
        "welcome": "ようこそ",
        "welcome_msg": "設定でGenius Access Tokenを設定してください。",
        "lyrics_not_found": "歌詞が見つかりませんでした。",
        "manual_check": "トラックを確認"
    }
}

class MusicController:
    """Handles interaction with macOS Music.app via appscript."""
    def __init__(self):
        self.music = appscript.app('Music')

    def get_current_track(self):
        """Returns (artist, title, album) of the currently playing track, or None."""
        try:
            # appscript.k.playing usually works, but sometimes checking state directly is safer
            if self.music.player_state() == appscript.k.playing:
                track = self.music.current_track
                return track.artist(), track.name(), track.album()
        except Exception as e:
            # If Music app is not running or other error
            pass
        return None

    def set_lyrics(self, lyrics_text):
        """Writes lyrics to the currently playing track's metadata."""
        try:
            if self.music.player_state() == appscript.k.playing:
                self.music.current_track.lyrics.set(lyrics_text)
                return True
        except Exception as e:
            print(f"Error setting lyrics: {e}")
            return False
        return False
        
# ... (skipping to UI section) ...

        # Manual Check Button
        self.btn_check = ttk.Button(controls_frame, text="Check Track", command=self.check_track)
        self.btn_check.pack(side=tk.LEFT, padx=5)

        # Fetch Button
        self.btn_fetch = ttk.Button(controls_frame, text="Fetch Lyrics", command=self.start_fetch_lyrics)
        self.btn_fetch.pack(side=tk.LEFT, padx=5)
        
        # Write/Save Button (Moved here for better visibility)
        self.btn_save = ttk.Button(controls_frame, text="Write to iTunes", command=self.write_metadata)
        self.btn_save.pack(side=tk.LEFT, padx=5)

class LyricsFetcher:
    """Handles fetching lyrics from various sources."""
    
    @staticmethod
    def sanitize_title(title):
        """Removes metadata noise from song titles."""
        # Remove anything in brackets or parentheses that looks like metadata
        # e.g., (Remastered 2009), [Live], (feat. User), - Remastered
        
        # 1. Remove specific keywords with surrounding brackets/parens
        # strict patterns: (Remastered...), [Live], (Live), (feat...), [feat...]
        patterns = [
            r'\s*[\(\[]\s*(?:Remastered|Live|Remix|Demo|Version|feat\.|ft\.).*?[\)\]]',
            r'\s*-\s*.*Remastered.*',
            r'\s*-\s*.*Remix.*',
        ]
        
        cleaned = title
        for pat in patterns:
            cleaned = re.sub(pat, '', cleaned, flags=re.IGNORECASE)
            
        return cleaned.strip()

    @staticmethod
    def fetch_genius(artist, title, token):
        """Fetches lyrics using the Genius API."""
        if token == "INSERT_YOUR_GENIUS_ACCESS_TOKEN_HERE" or not token:
            return "Error: Genius Access Token not configured in script."

        try:
            # 1. 嘗試使用 lyricsgenius 官方庫 (通常最穩定)
            genius = lyricsgenius.Genius(token, verbose=False)
            genius.remove_section_headers = True # 自動移除 [Chorus] 等標籤
            
            try:
                # 讓庫去處理主要的搜索
                song = genius.search_song(title, artist)
                if song:
                    lyrics = song.lyrics
                    # 清洗: 移除奇怪的標題頭 (e.g. "Monochromatic Stains Lyrics")
                    lines = lyrics.split('\n')
                    if lines and lines[0].strip().endswith('Lyrics'):
                        lines = lines[1:]
                    return '\n'.join(lines).strip()
            except Exception as lib_err:
                print(f"Library fetch failed, falling back to manual: {lib_err}")

            # 2. 如果庫失敗，執行手動爬蟲 (Fallback)
            headers = {'Authorization': f'Bearer {token}'}
            search_url = 'https://api.genius.com/search'
            params = {'q': f'{title} {artist}'}
            
            resp = requests.get(search_url, params=params, headers=headers)
            if resp.status_code == 200:
                json_data = resp.json()
                try:
                    hits = json_data['response']['hits']
                    if hits:
                        song_url = hits[0]['result']['url']
                        print(f"Fallback URL: {song_url}")
                        
                        page = requests.get(song_url)
                        html = BeautifulSoup(page.text, 'html.parser')
                        
                        # --- 關鍵修復開始 ---
                        # 改用 find_all 獲取所有歌詞容器
                        lyrics_divs = html.find_all('div', class_=re.compile('Lyrics__Container'))
                        if lyrics_divs:
                            # 將所有容器的文本提取並用換行符連接
                            full_text = "\n".join([div.get_text(separator='\n') for div in lyrics_divs])
                            return full_text.strip()
                        # --- 關鍵修復結束 ---
                        
                        # 舊版容器兼容
                        old_div = html.find('div', class_='lyrics')
                        if old_div:
                             return old_div.get_text().strip()
                        
                        return f"Found lyrics at: {song_url} (Auto-scrape failed)"
                except Exception as parse_err:
                    print(f"Manual parse error: {parse_err}")

            # 如果這裡也沒找到
            return "Lyrics not found on Genius."

        except Exception as e:
            return f"Genius Error: {str(e)}"

    @staticmethod
    def fetch_darklyrics(artist, title, album_name=""):
        """Fetches lyrics from DarkLyrics (Primary) or Search Fallback."""
        try:
            # Init Cloudscraper
            scraper = cloudscraper.create_scraper(browser={'browser': 'chrome', 'platform': 'darwin', 'desktop': True})
        except Exception as e:
            print(f"Cloudscraper init failed: {e}")
            scraper = requests.Session()

        # Strategy 1: Direct URL Construction (Fastest & Most Reliable)
        # URL structure: http://www.darklyrics.com/lyrics/{normalized_artist}/{normalized_album}.html
        
        if album_name:
            print(f"Trying direct DarkLyrics URL for Album: {album_name}")
            try:
                # Normalize: lowercase, remove spaces and punctuation
                # e.g. "Dark Tranquillity" -> "darktranquillity"
                # "Moment" -> "moment"
                norm_artist = re.sub(r'[^a-z0-9]', '', artist.lower())
                norm_album = re.sub(r'[^a-z0-9]', '', album_name.lower())
                
                if norm_artist and norm_album:
                    direct_url = f"http://www.darklyrics.com/lyrics/{norm_artist}/{norm_album}.html"
                    print(f"Direct URL attempt: {direct_url}")
                    
                    resp = scraper.get(direct_url, timeout=10)
                    if resp.status_code == 200:
                        # We found the album page! Now find the song.
                        return LyricsFetcher._parse_darklyrics_page(resp.text, title)
                    else:
                        print(f"Direct URL failed (Status {resp.status_code}). Falling back to search.")
            except Exception as e:
                print(f"Direct URL construction failed: {e}")

        # Strategy 2: Search via DuckDuckGo Lite (Fallback)
        # Query: "DarkLyrics artist title"
        query = f'site:darklyrics.com "{artist}" "{title}"'
        ddg_url = "https://lite.duckduckgo.com/lite/"
        print(f"Searching DarkLyrics via DDG Lite: {query}")
        
        headers = {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': 'https://lite.duckduckgo.com/'
        }
        
        try:
            resp = scraper.post(ddg_url, data={'q': query}, headers=headers, timeout=15)
            # Fallback to GET
            if resp.status_code != 200:
                 resp = scraper.get(ddg_url, params={'q': query}, timeout=15)

            if resp.status_code != 200:
                return "Error: Could not search for song (DDG Lite Blocked)."

            soup_ddg = BeautifulSoup(resp.text, 'html.parser')
            
            # Find lyrics page link
            album_url = None
            links_found = soup_ddg.find_all('a', class_='result-link', href=True)
            for link in links_found:
                href = link['href']
                if 'darklyrics.com/lyrics/' in href:
                    album_url = href
                    # Remove anchor if present #123
                    if '#' in album_url:
                        album_url = album_url.split('#')[0]
                    print(f"Found DarkLyrics Page: {album_url}")
                    break
            
            if not album_url:
                 return "Lyrics not found on DarkLyrics."

            # Visit Page
            page_resp = scraper.get(album_url, timeout=15)
            if page_resp.status_code != 200:
                return f"Error: HTTP {page_resp.status_code} accessing Lyrics page."
            
            return LyricsFetcher._parse_darklyrics_page(page_resp.text, title)

        except Exception as e:
            import traceback
            traceback.print_exc()
            return f"Error fetching from DarkLyrics: {str(e)}"

    @staticmethod
    def _parse_darklyrics_page(html_content, target_title):
        """Parses a DarkLyrics album page to find specific song lyrics."""
        soup = BeautifulSoup(html_content, 'html.parser')
        
        # DarkLyrics format:
        # <div class="lyrics">
        # ...
        # <h3><a name="1">1. Song Title</a></h3><br>
        # Lyrics text...
        # <br><br>
        # <h3>...next song...
        
        lyrics_div = soup.find('div', class_='lyrics')
        if not lyrics_div:
            return "Error: Could not parse lyrics container."
            
        # The content is a mess of text and tags. 
        # Strategy: 
        # 1. Find the <h3> header that matches our song title.
        # 2. Extract text until the next <h3> or end of div.
        
        normalized_target = LyricsFetcher.sanitize_title(target_title).lower().replace(' ', '')
        
        found_header = None
        headers = lyrics_div.find_all('h3')
        
        for h3 in headers:
            # h3 text: "1. Song Title"
            text = h3.get_text().lower()
            # Remove leading number "1. "
            text = re.sub(r'^\d+\.\s*', '', text)
            # Normalize
            text_norm = text.replace(' ', '')
            
            # Fuzzy match? Or substring?
            if normalized_target in text_norm or text_norm in normalized_target:
                found_header = h3
                break
        
        if not found_header:
            return "Song title not found on album page."
            
        # Extract lyrics after the header
        # Iterate siblings
        lyrics_parts = []
        curr = found_header.next_sibling
        while curr:
            if curr.name == 'h3':
                break # Next song
            
            if isinstance(curr, str):
                lyrics_parts.append(curr.strip())
            elif curr.name == 'br':
                lyrics_parts.append('\n')
            
            curr = curr.next_sibling
            
        full_text = "".join(lyrics_parts).strip()
        # Clean up excessive newlines
        full_text = re.sub(r'\n{3,}', '\n\n', full_text)
        return full_text if full_text else "Lyrics parsed empty."


class ConfigManager:
    """Manages persistent configuration (Token & Language)."""
    _config_path = os.path.expanduser("~/.azathoths_whisper_config")

    @classmethod
    def load_config(cls):
        """Loads full config dict handling JSON migration."""
        defaults = {"token": "", "language": "system"}
        
        if not os.path.exists(cls._config_path):
            # Try legacy env as fallback for token
            defaults["token"] = os.getenv("GENIUS_ACCESS_TOKEN", "")
            return defaults

        try:
            with open(cls._config_path, "r") as f:
                content = f.read().strip()
                
            # Try JSON
            try:
                data = json.loads(content)
                # Merge with defaults to ensure all keys exist
                for k, v in defaults.items():
                    if k not in data:
                        data[k] = v
                return data
            except json.JSONDecodeError:
                # Legacy: Content was just the token string
                print("Migrating legacy config file format...")
                return {"token": content, "language": "system"}
                
        except Exception as e:
            print(f"Error loading config: {e}")
            return defaults

    @classmethod
    def save_config(cls, token, language):
        """Saves config as JSON."""
        data = {"token": token, "language": language}
        try:
            with open(cls._config_path, "w") as f:
                json.dump(data, f)
        except Exception as e:
            print(f"Error saving config: {e}")

    @staticmethod
    def detect_system_language():
        """Detects macOS system language, checking app-specific override first."""
        try:
            # 1. Check App-Specific Defaults (com.ibridgezhao.azathothswhisper)
            # This is set when user changes language in System Settings -> Language & Region -> Applications
            try:
                out = subprocess.check_output("defaults read com.ibridgezhao.azathothswhisper AppleLanguages", shell=True, stderr=subprocess.DEVNULL)
                out_str = out.decode('utf-8').strip()
                # If found, prioritize this
                if 'zh-Hant' in out_str or 'zh-TW' in out_str: return 'zh_TW'
                if 'ja' in out_str: return 'ja'
                if 'en' in out_str: return 'en'
            except:
                pass # No app-specific setting

            # 2. Check Global Defaults
            out = subprocess.check_output("defaults read -g AppleLanguages", shell=True)
            out_str = out.decode('utf-8').strip()
            # Output format: ( "en-US", "ja-JP", ... )
            if 'zh-Hant' in out_str or 'zh-TW' in out_str:
                return 'zh_TW'
            if 'ja' in out_str:
                return 'ja'
        except:
            pass
        return 'en' # Default fallback

class LyricsApp(tk.Tk):
    def __init__(self, config):
        super().__init__()
        self.config_data = config
        self.token = config.get("token", "")
        self.lang_code = config.get("language", "system")
        
        # Determine actual language
        if self.lang_code == "system":
            self.current_lang = ConfigManager.detect_system_language()
        else:
            self.current_lang = self.lang_code
            
        # Fallback to en if not found
        if self.current_lang not in TRANSLATIONS:
            self.current_lang = "en"
            
        self.title(self._get_text("app_title"))
        self.geometry("700x600")
        
        self.music_ctrl = MusicController()
        self.current_track_info = None  # (artist, title)

        self._build_menu()
        self._build_ui()
        
        # Handle window close button (red X) -> Hide instead of Exit
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        
        # Handle Dock icon click (ReopenApplication)
        try:
            self.createcommand('::tk::mac::ReopenApplication', self.on_reopen)
        except AttributeError:
            pass

        # Poll for track changes periodically
        self.after(2000, self.auto_refresh_track)
        
    def _get_text(self, key):
        """Retrieves localized text."""
        # Safety
        return TRANSLATIONS.get(self.current_lang, TRANSLATIONS["en"]).get(key, key)

    def _build_menu(self):
        menubar = tk.Menu(self)
        
        settings_menu = tk.Menu(menubar, tearoff=0)
        # Split Token and Language
        settings_menu.add_command(label=self._get_text("menu_token"), command=self.open_token_settings)
        settings_menu.add_command(label=self._get_text("menu_lang"), command=self.open_language_settings)
        
        menubar.add_cascade(label=self._get_text("settings_menu"), menu=settings_menu)
        
        self.config(menu=menubar)
        
    def _build_ui(self):
        # Top Frame: Track Info and Controls
        top_frame = ttk.Frame(self, padding="10")
        top_frame.pack(fill=tk.X)
        
        self.lbl_info = ttk.Label(top_frame, text=self._get_text("not_playing"), font=("Helvetica", 14, "bold"))
        self.lbl_info.pack(side=tk.TOP, pady=5)
        
        controls_frame = ttk.Frame(top_frame)
        controls_frame.pack(fill=tk.X, pady=5)
        
        # Source Selection
        ttk.Label(controls_frame, text=self._get_text("source")).pack(side=tk.LEFT, padx=5)
        self.source_var = tk.StringVar(value="Genius")
        self.cbo_source = ttk.Combobox(controls_frame, textvariable=self.source_var, state="readonly")
        self.cbo_source['values'] = ("Genius", "DarkLyrics / Metal")
        self.cbo_source.pack(side=tk.LEFT, padx=5)
        
        # Fetch Button
        self.btn_fetch = ttk.Button(controls_frame, text=self._get_text("fetch_btn"), command=self.start_fetch_lyrics)
        self.btn_fetch.pack(side=tk.LEFT, padx=5)

        # Write/Save Button
        self.btn_write = ttk.Button(controls_frame, text=self._get_text("write_btn"), command=self.write_metadata)
        self.btn_write.pack(side=tk.LEFT, padx=5)
        
        # Center Frame: Text Editor
        center_frame = ttk.Frame(self, padding="10")
        center_frame.pack(fill=tk.BOTH, expand=True)
        
        self.txt_lyrics = scrolledtext.ScrolledText(center_frame, wrap=tk.WORD, font=("Menlo", 12))
        self.txt_lyrics.pack(fill=tk.BOTH, expand=True)
        
        # Bottom Frame: Save
        bottom_frame = ttk.Frame(self, padding="10")
        bottom_frame.pack(fill=tk.X)
        
        self.lbl_status = ttk.Label(bottom_frame, text=self._get_text("status_ready"), foreground="gray")
        self.lbl_status.pack(side=tk.LEFT)
        
        # Initial check
        self.check_track()

    def auto_refresh_track(self):
        """Periodically checks specifically for track changes if connection is happy."""
        self.check_track()
        self.after(5000, self.auto_refresh_track)

    def check_track(self):
        """Polls the Music app for the current track."""
        info = self.music_ctrl.get_current_track()
        if info:
            artist, title, album = info
            if self.current_track_info != (artist, title):
                self.current_track_info = (artist, title)
                self.lbl_info.config(text=f"{artist} - {title}")
                self.lbl_status.config(text=self._get_text("track_detected"))
        else:
            self.current_track_info = None
            self.lbl_info.config(text=self._get_text("music_not_playing"))
    
    def start_fetch_lyrics(self):
        """Starts the fetching process in a separate thread."""
        if not self.current_track_info:
            messagebox.showwarning(self._get_text("err_validation"), self._get_text("msg_no_track"))
            return
        
        # Determine album info
        info = self.music_ctrl.get_current_track()
        if info:
            artist, title, album = info
        else:
            if len(self.current_track_info) == 2:
                artist, title = self.current_track_info
                album = ""
            else:
                 artist, title, album = self.current_track_info

        source = self.source_var.get()
        
        self.toggle_inputs(False)
        self.lbl_status.config(text=self._get_text("status_fetching").format(source))
        self.txt_lyrics.delete("1.0", tk.END)
        self.txt_lyrics.insert("1.0", self._get_text("status_limit_msg"))
        
        # Run in thread to keep GUI alive
        t = threading.Thread(target=self._fetch_thread, args=(artist, title, album, source))
        t.start()
        
    def _fetch_thread(self, artist, title, album, source):
        # 1. Sanitize
        clean_title = LyricsFetcher.sanitize_title(title)
        print(f"Original: '{title}' -> Clean: '{clean_title}'")
        
        result = ""
        if source == "Genius":
            # Use stored token, or empty string if None which fetch_genius handles
            token_to_use = self.token if self.token else ""
            result = LyricsFetcher.fetch_genius(artist, clean_title, token_to_use)
        else:
            result = LyricsFetcher.fetch_darklyrics(artist, clean_title, album)
            
        # Update UI safely
        self.after(0, self._fetch_complete, result)

    def _fetch_complete(self, lyrics_text):
        self.toggle_inputs(True)
        self.lbl_status.config(text=self._get_text("status_complete"))
        
        if lyrics_text and not lyrics_text.startswith("Error"):
            self.txt_lyrics.delete("1.0", tk.END)
            self.txt_lyrics.insert("1.0", lyrics_text)
        else:
            # If error or empty
            self.txt_lyrics.delete("1.0", tk.END)
            if lyrics_text and "Lyrics not found" in lyrics_text:
                 self.txt_lyrics.insert("1.0", self._get_text("lyrics_not_found"))
            else:
                 self.txt_lyrics.insert("1.0", lyrics_text if lyrics_text else self._get_text("lyrics_not_found"))
            
            if lyrics_text and lyrics_text.startswith("Error"):
                messagebox.showerror(self._get_text("err_validation"), lyrics_text)

    def write_metadata(self):
        """Writes the current text content to the song."""
        if not self.current_track_info:
             messagebox.showerror("Error", self._get_text("err_no_track"))
             return

        lyrics = self.txt_lyrics.get("1.0", tk.END).strip()
        if not lyrics:
            if not messagebox.askyesno("Warning", self._get_text("warn_empty_lyrics")):
                return
        
        success = self.music_ctrl.set_lyrics(lyrics)
        if success:
            messagebox.showinfo("Success", self._get_text("msg_success"))
            self.lbl_status.config(text=self._get_text("status_saved"))
        else:
            messagebox.showerror("Error", self._get_text("msg_fail"))

    def toggle_inputs(self, enable):
        state = "normal" if enable else "disabled"
        self.btn_fetch.config(state=state)
        self.btn_write.config(state=state)
        self.cbo_source.config(state=state)

    def open_token_settings(self):
        """Opens the Token settings dialog."""
        dialog = tk.Toplevel(self)
        dialog.title(self._get_text("menu_token").replace("...", ""))
        dialog.geometry("450x150")
        
        tk.Label(dialog, text=self._get_text("token_label")).pack(pady=(10, 5))
        entry_token = tk.Entry(dialog, width=40)
        entry_token.pack(pady=5)
        if self.token:
            entry_token.insert(0, self.token)
            
        def save():
            new_token = entry_token.get().strip()
            if new_token:
                ConfigManager.save_config(new_token, self.lang_code)
                self.token = new_token
                messagebox.showinfo(self._get_text("saved_title"), self._get_text("saved_token_msg"))
                dialog.destroy()
            else:
                messagebox.showwarning("Warning", self._get_text("warning_token_empty"))

        tk.Button(dialog, text=self._get_text("save_btn"), command=save).pack(pady=20)

    def open_language_settings(self):
        """Opens the Language settings dialog."""
        dialog = tk.Toplevel(self)
        dialog.title(self._get_text("menu_lang").replace("...", ""))
        dialog.geometry("350x200")
        
        
        tk.Label(dialog, text=self._get_text("lang_label")).pack(pady=(15, 5))
        
        LANG_OPTIONS = [
            ("System Default / 默認 / デフォルト", "system"),
            ("English", "en"),
            ("Traditional Chinese (繁體中文)", "zh_TW"),
            ("Japanese (日本語)", "ja")
        ]
        
        # Calculate current index based on code
        current_index = 0
        for i, (d, c) in enumerate(LANG_OPTIONS):
            if c == self.lang_code:
                current_index = i
                break

        cbo_lang = ttk.Combobox(dialog, state="readonly", width=30)
        cbo_lang['values'] = [x[0] for x in LANG_OPTIONS]
        cbo_lang.current(current_index)
        cbo_lang.pack(pady=5)
            
        def save():
            selected_display = cbo_lang.get()
            new_lang_code = "system"
            for d, c in LANG_OPTIONS:
                if d == selected_display:
                    new_lang_code = c
                    break
            
            ConfigManager.save_config(self.token, new_lang_code)
            self.lang_code = new_lang_code
            self.current_lang = new_lang_code # Update slightly for THIS session if easy, but restart handles it best.
            
            messagebox.showinfo(self._get_text("saved_title"), self._get_text("saved_msg"))
            dialog.destroy()

        tk.Button(dialog, text=self._get_text("save_btn"), command=save).pack(pady=20)

    def on_close(self):
        """Hides the window instead of quitting."""
        self.withdraw()

    def on_reopen(self):
        """Shows the window again (invoked by clicking Dock icon)."""
        self.deiconify()


if __name__ == '__main__':
    # Load config
    config = ConfigManager.load_config()
    
    app = LyricsApp(config)
    
    # Check if token is missing and prompt user
    if not app.token:
        # Use simple english for fallback if not initialized in app yet? 
        # Actually app is initialized so it can use get_text but maybe not fully ready?
        # It's fine.
        app.after(500, lambda: messagebox.showinfo(app._get_text("welcome"), app._get_text("welcome_msg")))
    
    app.mainloop()

    def _build_menu(self):
        menubar = tk.Menu(self)
        
        settings_menu = tk.Menu(menubar, tearoff=0)
        settings_menu.add_command(label="Preferences...", command=self.open_settings)
        menubar.add_cascade(label="Settings", menu=settings_menu)
        
        self.config(menu=menubar)
        
    def _build_ui(self):
        # Top Frame: Track Info and Controls
        top_frame = ttk.Frame(self, padding="10")
        top_frame.pack(fill=tk.X)
        
        self.lbl_info = ttk.Label(top_frame, text="Not Playing", font=("Helvetica", 14, "bold"))
        self.lbl_info.pack(side=tk.TOP, pady=5)
        
        controls_frame = ttk.Frame(top_frame)
        controls_frame.pack(fill=tk.X, pady=5)
        
        # Source Selection
        ttk.Label(controls_frame, text="Source:").pack(side=tk.LEFT, padx=5)
        self.source_var = tk.StringVar(value="Genius")
        self.cbo_source = ttk.Combobox(controls_frame, textvariable=self.source_var, state="readonly")
        self.cbo_source['values'] = ("Genius", "DarkLyrics / Metal")
        self.cbo_source.pack(side=tk.LEFT, padx=5)
        
        # Fetch Button
        self.btn_fetch = ttk.Button(controls_frame, text="Fetch Lyrics", command=self.start_fetch_lyrics)
        self.btn_fetch.pack(side=tk.LEFT, padx=5)

        # Write/Save Button
        self.btn_write = ttk.Button(controls_frame, text="Write to iTunes", command=self.write_metadata)
        self.btn_write.pack(side=tk.LEFT, padx=5)
        
        # Center Frame: Text Editor
        center_frame = ttk.Frame(self, padding="10")
        center_frame.pack(fill=tk.BOTH, expand=True)
        
        self.txt_lyrics = scrolledtext.ScrolledText(center_frame, wrap=tk.WORD, font=("Menlo", 12))
        self.txt_lyrics.pack(fill=tk.BOTH, expand=True)
        
        # Bottom Frame: Save
        bottom_frame = ttk.Frame(self, padding="10")
        bottom_frame.pack(fill=tk.X)
        

        
        self.lbl_status = ttk.Label(bottom_frame, text="Ready", foreground="gray")
        self.lbl_status.pack(side=tk.LEFT)
        
        # Initial check
        self.check_track()

    def auto_refresh_track(self):
        """Periodically checks specifically for track changes if connection is happy."""
        self.check_track()
        self.after(5000, self.auto_refresh_track)

    def check_track(self):
        """Polls the Music app for the current track."""
        info = self.music_ctrl.get_current_track()
        if info:
            artist, title, album = info
            # We ignore album for equality check to keep simple, or use it?
            # Let's keep equality check on artist/title primarily or full info?
            # If album changes but song same? Rare.
            if self.current_track_info != (artist, title):
                self.current_track_info = (artist, title)
                self.lbl_info.config(text=f"{artist} - {title}")
                self.lbl_status.config(text="Track detected.")
        else:
            self.current_track_info = None
            self.lbl_info.config(text="Music not playing / paused")
    
    def start_fetch_lyrics(self):
        """Starts the fetching process in a separate thread."""
        if not self.current_track_info:
            messagebox.showwarning("No Track", "No track is currently playing in Music.")
            return
        
        # Determine album info
        # If check_track hasn't updated album into self.current_track_info (depending on logic), re-fetch
        info = self.music_ctrl.get_current_track()
        if info:
            artist, title, album = info
        else:
            # Should not happen if current_track_info is set, but just in case
            if len(self.current_track_info) == 2:
                artist, title = self.current_track_info
                album = ""
            else:
                 artist, title, album = self.current_track_info

        source = self.source_var.get()
        
        self.toggle_inputs(False)
        self.lbl_status.config(text=f"Fetching from {source}...")
        self.txt_lyrics.delete("1.0", tk.END)
        self.txt_lyrics.insert("1.0", "Fetching...")
        
        # Run in thread to keep GUI alive
        t = threading.Thread(target=self._fetch_thread, args=(artist, title, album, source))
        t.start()
        
    def _fetch_thread(self, artist, title, album, source):
        # 1. Sanitize
        clean_title = LyricsFetcher.sanitize_title(title)
        print(f"Original: '{title}' -> Clean: '{clean_title}'")
        
        result = ""
        if source == "Genius":
            # Use stored token, or empty string if None which fetch_genius handles
            token_to_use = self.token if self.token else ""
            result = LyricsFetcher.fetch_genius(artist, clean_title, token_to_use)
        else:
            # DarkLyrics / Metal Source (Replaced old Metal Archives call)
            # We implemented fetch_darklyrics as a static method logic internally
            # or we need to add the method.
            # Wait, I haven't added `fetch_darklyrics` method yet!
            # I should call `fetch_metal_archives` but I will RENAME/REWRITE that method in next step
            # to be `fetch_darklyrics`. 
            # Or I'll call it `fetch_darklyrics` here and ensure I add it.
            result = LyricsFetcher.fetch_darklyrics(artist, clean_title, album)
            
        # Update UI safely
        self.after(0, self._fetch_complete, result)

    def _fetch_complete(self, lyrics_text):
        self.toggle_inputs(True)
        self.lbl_status.config(text="Fetch complete.")
        
        if lyrics_text and not lyrics_text.startswith("Error"):
            self.txt_lyrics.delete("1.0", tk.END)
            self.txt_lyrics.insert("1.0", lyrics_text)
        else:
            # If error or empty
            self.txt_lyrics.delete("1.0", tk.END)
            self.txt_lyrics.insert("1.0", lyrics_text if lyrics_text else "No lyrics found.")
            if lyrics_text and lyrics_text.startswith("Error"):
                messagebox.showerror("Validation Error", lyrics_text)

    def write_metadata(self):
        """Writes the current text content to the song."""
        if not self.current_track_info:
             messagebox.showerror("Error", "No track playing.")
             return

        lyrics = self.txt_lyrics.get("1.0", tk.END).strip()
        if not lyrics:
            if not messagebox.askyesno("Warning", "Lyrics are empty. This will clear existing lyrics. Continue?"):
                return
        
        success = self.music_ctrl.set_lyrics(lyrics)
        if success:
            messagebox.showinfo("Success", "Lyrics written to iTunes track!")
            self.lbl_status.config(text="Saved to metadata.")
        else:
            messagebox.showerror("Error", "Failed to write to iTunes. Track might be read-only (streaming) or app unreachable.")

    def toggle_inputs(self, enable):
        state = "normal" if enable else "disabled"
        self.btn_fetch.config(state=state)
        self.btn_write.config(state=state)
        self.cbo_source.config(state=state)

    def open_settings(self):
        """Opens the settings dialog to configure the Token."""
        dialog = tk.Toplevel(self)
        dialog.title("Settings")
        dialog.geometry("400x150")
        
        tk.Label(dialog, text="Genius Access Token:").pack(pady=10)
        
        entry_token = tk.Entry(dialog, width=40)
        entry_token.pack(pady=5)
        # Pre-fill with current token
        if self.token:
            entry_token.insert(0, self.token)
            
        def save():
            new_token = entry_token.get().strip()
            if new_token:
                ConfigManager.save_token(new_token)
                self.token = new_token
                messagebox.showinfo("Saved", "Token saved successfully!")
                dialog.destroy()
            else:
                messagebox.showwarning("Warning", "Token cannot be empty.")

        tk.Button(dialog, text="Save Token", command=save).pack(pady=10)

    def on_close(self):
        """Hides the window instead of quitting."""
        self.withdraw()

    def on_reopen(self):
        """Shows the window again (invoked by clicking Dock icon)."""
        self.deiconify()


class ConfigManager:
    """Manages persistent configuration."""
    _config_path = os.path.expanduser("~/.azathoths_whisper_config")

    @classmethod
    def load_token(cls):
        """Loads token from config file or legacy locations."""
        # 1. Try persistent user config first
        if os.path.exists(cls._config_path):
            try:
                with open(cls._config_path, "r") as f:
                    return f.read().strip()
            except:
                pass
        
        # 2. Fallback to environment variables (.env file)
        return os.getenv("GENIUS_ACCESS_TOKEN")

    @classmethod
    def save_token(cls, token):
        """Saves token to user config file."""
        with open(cls._config_path, "w") as f:
            f.write(token)

if __name__ == '__main__':
    # Try to load token but don't crash if missing
    initial_token = ConfigManager.load_token()
    
    app = LyricsApp()
    app.token = initial_token # Inject token into app instance
    
    # Check if token is missing and prompt user
    if not app.token:
        app.after(500, lambda: messagebox.showinfo("Welcome", "Please set your Genius Access Token in Settings."))
    
    app.mainloop()
