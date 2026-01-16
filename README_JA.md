# Azathoth's Whisper (アザトースの囁き)

[**English**](README.md) | [**繁體中文**](README_ZH.md) | [**日本語**](README_JA.md)

**Azathoth's Whisper**は、**iTunes**で現在再生中の曲の歌詞を自動的に取得し、オーディオファイルのカスタム歌詞メタデータに直接埋め込むmacOSアプリケーションです。

複数の歌詞ソースをサポートし、ダークテーマと多言語ユーザーインターフェースを備えています。

## 機能

*   🎵 **自動同期:** iTunesを監視し、曲が変わると自動的に歌詞を取得します。
*   📝 **歌詞の埋め込み:** 音楽ファイルに歌詞を直接書き込みます（iTunesやiPhoneなどで歌詞を表示できます）。
*   🌍 **マルチソース対応:**
    *   **Genius** (APIトークンが必要)
    *   **Metal Archives** (ヘヴィメタル音楽に最適)
    *   **DarkLyrics**
    *   **Musixmatch** (フォールバック用)
*   🌐 **多言語UI:** **英語**、**繁体字中国語**、**日本語**に完全対応。
*   🌑 **ダークモード:** 洗練されたモダンなダークインターフェース。
*   ⚙️ **スマート設定:** Geniusトークンと言語設定を記憶します。
*   🍎 **macOSネイティブ対応:** システム言語設定を尊重し、iTunesと高度に統合されています。

## インストール

### コンパイル済みアプリ (App Bundle)
`.app`ファイルをお持ちの場合：
1. `Azathoth's Whisper.app`を**アプリケーション (Applications)**フォルダにドラッグします。
2. アプリを開きます。iTunesを制御するために、**自動化の許可 (Automation Permissions)**を承認する必要がある場合があります。

### ソースコードからのビルド
要件: Python 3.10以降, macOS。

1.  **リポジトリのクローン**
    ```bash
    git clone https://github.com/TK88101/Azathoths-Whisper.git
    cd Azathoths-Whisper
    ```

2.  **仮想環境のセットアップ**
    ```bash
    python3 -m venv venv
    source venv/bin/activate
    ```

3.  **依存関係のインストール**
    ```bash
    pip install -r requirements.txt
    # または手動インストール:
    pip install requests beautifulsoup4 lyricsgenius appscript pyinstaller pillow
    ```

4.  **ローカルでの実行**
    ```bash
    python lyrics_fetcher.py
    ```

5.  **アプリバンドルのビルド** (完全なリリースビルド)
    ```bash
    # 1. 以前のビルドをクリア
    rm -rf build/ dist/

    # 2. PyInstallerを実行
    pyinstaller Azathoths_Whisper.spec --clean
    
    # 3. ローカリゼーションフォルダの作成 (macOSの言語検出に重要)
    mkdir -p "dist/Azathoth's Whisper.app/Contents/Resources/en.lproj"
    mkdir -p "dist/Azathoth's Whisper.app/Contents/Resources/zh_TW.lproj"
    mkdir -p "dist/Azathoth's Whisper.app/Contents/Resources/ja.lproj"
    
    # 4. ダミーのローカライズファイルを追加
    touch "dist/Azathoth's Whisper.app/Contents/Resources/en.lproj/Localizable.strings"
    touch "dist/Azathoth's Whisper.app/Contents/Resources/zh_TW.lproj/Localizable.strings"
    touch "dist/Azathoth's Whisper.app/Contents/Resources/ja.lproj/Localizable.strings"
    ```

## 使い方

1.  **アプリの起動**: Azathoth's Whisperを開きます。
2.  **Geniusトークン設定**:
    *   初回実行時に `Settings` -> `Genius Token Settings` に移動します。
    *   **Genius Client Access Token**を貼り付けます ([genius.com/api-clients](https://genius.com/api-clients) で取得可能)。
    *   保存 (Save) をクリックします。
3.  **音楽の再生**: iTunesで曲の再生を開始します。
4.  **歌詞の取得**:
    *   **自動モード (Auto Mode)**: アプリは曲の変化を検出し、自動的に歌詞を検索します。
    *   **手動モード**: "Fetch Lyrics"をクリックして強制的に検索します。
5.  **言語**: `Settings` -> `Language Settings` からインターフェース言語を切り替えます。

## 技術スタック

*   **Python**: コアロジック。
*   **Tkinter**: GUIフレームワーク。
*   **Appscript**: macOS iTunesの自動操作。
*   **PyInstaller**: アプリケーションのパッケージ化。

## 免責事項

このプロジェクトは教育目的でのみ提供されています。取得された歌詞の著作権はそれぞれの所有者に帰属します。大量にダウンロードする前に、使用権を確認してください。

---
Created by [iBridgeZhao]
