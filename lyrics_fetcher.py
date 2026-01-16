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

# Third-party libraries
try:
    import appscript
    import requests
    from bs4 import BeautifulSoup
    import lyricsgenius
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Please install required packages: pip install appscript lyricsgenius requests beautifulsoup4")
    exit(1)

from dotenv import load_dotenv
import os

# Load environment variables
load_dotenv()

# Constants
GENIUS_ACCESS_TOKEN = os.getenv("GENIUS_ACCESS_TOKEN")
if GENIUS_ACCESS_TOKEN:
    print(f"Loaded Token: {GENIUS_ACCESS_TOKEN[:4]}...{GENIUS_ACCESS_TOKEN[-4:]}")
else:
    print("Warning: GENIUS_ACCESS_TOKEN is not set.")

USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36"

class MusicController:
    """Handles interaction with macOS Music.app via appscript."""
    def __init__(self):
        self.music = appscript.app('Music')

    def get_current_track(self):
        """Returns (artist, title) of the currently playing track, or None."""
        try:
            # appscript.k.playing usually works, but sometimes checking state directly is safer
            if self.music.player_state() == appscript.k.playing:
                track = self.music.current_track
                return track.artist(), track.name()
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
            # verbose=False to reduce terminal noise
            genius = lyricsgenius.Genius(token, verbose=False)
            
            # Using search_song is the standard way
            # Try manual request first to debug 401
            headers = {'Authorization': f'Bearer {token}'}
            search_url = 'https://api.genius.com/search'
            params = {'q': f'{title} {artist}'}
            print(f"DEBUG: Attempting manual request to {search_url}")
            resp = requests.get(search_url, params=params, headers=headers)
            print(f"DEBUG: Manual Status: {resp.status_code}")
            
            if resp.status_code == 401:
                return "Error: 401 Unauthorized. Double check your token in .env"
                
            if resp.status_code == 200:
                json_data = resp.json()
                # Simple parse of first hit
                try:
                    hits = json_data['response']['hits']
                    if hits:
                        song_url = hits[0]['result']['url']
                        print(f"Found URL: {song_url}")
                        # If we found it manually, let's just scrape usage page content or let library retry if needed
                        # But since library failed, let's scrape the URL we found
                        page = requests.get(song_url)
                        html = BeautifulSoup(page.text, 'html.parser')
                        # New Genius scraping logic (lyrics are in diverse containers now)
                        # Attempt standard container first
                        lyrics_div = html.find('div', class_=re.compile('Lyrics__Container'))
                        if lyrics_div:
                            return lyrics_div.get_text(separator='\n').strip()
                        # Fallback to older container
                        old_div = html.find('div', class_='lyrics')
                        if old_div:
                             return old_div.get_text().strip()
                        
                        # Just return the URL if scraping fails temporarily
                        return f"Found lyrics at: {song_url} (Auto-scrape failed)"
                except Exception as parse_err:
                    print(f"Manual parse error: {parse_err}")

            if song:
                lyrics = song.lyrics
                
                # Cleanup: lyricsgenius sometimes returns "Lyrics" as the first line or other headers.
                # Requirement: "Remove section headers like [Chorus] if possible"
                
                # 1. Remove [Chorus], [Verse 1], etc.
                lyrics = re.sub(r'\[.*?\]', '', lyrics)
                
                # 2. Clean up "X Lyrics" header often found at start
                # e.g. "Song Title Lyrics"
                lines = lyrics.split('\n')
                if lines and lines[0].strip().endswith('Lyrics'):
                     lines = lines[1:]
                lyrics = '\n'.join(lines)

                # 3. Collapse multiple newlines
                lyrics = re.sub(r'\n{3,}', '\n\n', lyrics)
                
                return lyrics.strip()
            else:
                return None
        except Exception as e:
            return f"Genius Error: {str(e)}"

    @staticmethod
    def fetch_metal_archives(artist, title):
        """Scrapes lyrics from Metal-Archives.com."""
        headers = {'User-Agent': USER_AGENT}
        
        # Step 1: Search for the song
        search_url = "https://www.metal-archives.com/search/ajax-advanced/searching/songs"
        
        # We try to mimic the params the site expects for an advanced song search
        params = {
            'bandName': artist,
            'songTitle': title,
            # 'exactSongMatch': 1, # Use 1 for exact if we are confident, or 0 for loose
            # Let's use loose match (0) to allow for minor differences, then filter results.
            # However, looking at MA URLs, they often use just `?bandName=...&songTitle=...` for simple advanced search
            # But the AJAX endpoint expects DataTables params usually (sEcho, iColumns, etc.)
            # If we don't provide them, it might fail or return a simple JSON.
            # Let's try minimal params first.
            'bandName': artist,
            'songTitle': title,
        }
        
        try:
            print(f"Searching Metal Archives for {artist} - {title}")
            resp = requests.get(search_url, params=params, headers=headers, timeout=10)
            if resp.status_code != 200:
                return f"Error: HTTP {resp.status_code} from Metal Archives search"
            
            try:
                data = resp.json()
            except:
                return "Error: Invalid JSON response from Metal Archives."

            # data['aaData'] contains the rows
            if not data.get('aaData'):
                return "No results found on Metal Archives."
            
            # Step 2: Parse JSON to find Song ID
            # Each row is a list of strings (HTML).
            # We look for `href=".../release/ajax-view-lyrics/id/<ID>"` OR `id="lyrics_link_<ID>"`
            
            song_id = None
            
            # Iterate through results to find the first one that has a lyrics link
            for row in data['aaData']:
                # The lyrics link is usually in the last column
                # Example: <a href="javascript:;" ... id="lyrics_link_123456">View Lyrics</a>
                for col in row:
                    match = re.search(r'id="lyrics_link_(\d+)"', col)
                    if match:
                        song_id = match.group(1)
                        break
                if song_id:
                    break
            
            if not song_id:
                return "Song found, but no lyrics ID detected."

            # Step 3: Fetch Lyrics text
            lyrics_url = f"https://www.metal-archives.com/release/ajax-view-lyrics/id/{song_id}"
            print(f"Fetching lyrics from {lyrics_url}")
            lyric_resp = requests.get(lyrics_url, headers=headers, timeout=10)
            
            if lyric_resp.status_code != 200:
                return f"Error: HTTP {lyric_resp.status_code} fetching lyrics body"
            
            # The response is HTML body of the lyrics
            soup = BeautifulSoup(lyric_resp.text, 'html.parser')
            text = soup.get_text()
            return text.strip()

        except Exception as e:
            return f"Metal Archives Error: {str(e)}"


class LyricsApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Surgical Lyrics Fetcher")
        self.geometry("600x600")
        
        self.music_ctrl = MusicController()
        self.current_track_info = None  # (artist, title)

        self._build_ui()
        
        # Poll for track changes periodically
        self.after(2000, self.auto_refresh_track)
        
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
        self.cbo_source['values'] = ("Genius", "Metal Archives")
        self.cbo_source.pack(side=tk.LEFT, padx=5)
        
        # Manual Check Button
        self.btn_check = ttk.Button(controls_frame, text="Check Track", command=self.check_track)
        self.btn_check.pack(side=tk.LEFT, padx=5)

        # Fetch Button
        self.btn_fetch = ttk.Button(controls_frame, text="Fetch Lyrics", command=self.start_fetch_lyrics)
        self.btn_fetch.pack(side=tk.LEFT, padx=5)
        
        # Center Frame: Text Editor
        center_frame = ttk.Frame(self, padding="10")
        center_frame.pack(fill=tk.BOTH, expand=True)
        
        self.txt_lyrics = scrolledtext.ScrolledText(center_frame, wrap=tk.WORD, font=("Menlo", 12))
        self.txt_lyrics.pack(fill=tk.BOTH, expand=True)
        
        # Bottom Frame: Save
        bottom_frame = ttk.Frame(self, padding="10")
        bottom_frame.pack(fill=tk.X)
        
        self.btn_save = ttk.Button(bottom_frame, text="Write to iTunes", command=self.write_metadata)
        self.btn_save.pack(side=tk.RIGHT)
        
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
            artist, title = info
            if self.current_track_info != (artist, title):
                self.current_track_info = (artist, title)
                self.lbl_info.config(text=f"{artist} - {title}")
                self.lbl_status.config(text="Track detected.")
        else:
            self.current_track_info = None
            self.lbl_info.config(text="Music not playing / paused")
    
    def start_fetch_lyrics(self):
        if not self.current_track_info:
            messagebox.showwarning("No Track", "No track is currently playing in Music.")
            return
        
        artist, title = self.current_track_info
        source = self.source_var.get()
        
        self.toggle_inputs(False)
        self.lbl_status.config(text=f"Fetching from {source}...")
        self.txt_lyrics.delete("1.0", tk.END)
        self.txt_lyrics.insert("1.0", "Fetching...")
        
        # Run in thread to keep GUI alive
        t = threading.Thread(target=self._fetch_thread, args=(artist, title, source))
        t.start()
        
    def _fetch_thread(self, artist, title, source):
        # 1. Sanitize
        clean_title = LyricsFetcher.sanitize_title(title)
        print(f"Original: '{title}' -> Clean: '{clean_title}'")
        
        result = ""
        if source == "Genius":
            result = LyricsFetcher.fetch_genius(artist, clean_title, GENIUS_ACCESS_TOKEN)
        else:
            result = LyricsFetcher.fetch_metal_archives(artist, clean_title)
            
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
            messagebox.showinfo("Success", "Lyrics written to Apple Music track!")
            self.lbl_status.config(text="Saved to metadata.")
        else:
            messagebox.showerror("Error", "Failed to write to Apple Music. Track might be read-only (streaming) or app unreachable.")

    def toggle_inputs(self, enable):
        state = "normal" if enable else "disabled"
        self.btn_fetch.config(state=state)
        self.btn_save.config(state=state)
        self.cbo_source.config(state=state)

if __name__ == "__main__":
    app = LyricsApp()
    app.mainloop()
