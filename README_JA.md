# Azathoth's Whisper (アザトースの囁き)

[**English**](README.md) | [**繁體中文**](README_ZH.md) | [**日本語**](README_JA.md)

**Azathoth's Whisper**は、**iTunes**で現在再生中の曲の歌詞を自動的に取得し、オーディオファイルのカスタム歌詞メタデータに直接埋め込むmacOSアプリケーションです。

複数の歌詞ソースをサポートし、ダークテーマと多言語ユーザーインターフェースを備えています。

## 機能

*   🎵 **自動同期:** iTunesを監視し、曲が変わると自動的に歌詞を取得します。
*   📝 **歌詞の埋め込み:** 音楽ファイルに歌詞を直接書き込みます（iTunesやiPhoneなどで歌詞を表示できます）。
*   🌍 **マルチソース対応:**
    *   **Genius** (APIトークンが必要)
    *   **DarkLyrics**（**一括処理モード限定**のフォールバック——下記参照）

    > エディタでの単曲 Fetch は **Genius のみ**を参照します。DarkLyrics が使われるのは
    > 一括処理の *Fetch Missing* で、かつ Genius がその曲を見つけられなかった場合だけです。

    > **2.0 のソース構成についての注釈:** 初期の README では *Metal Archives* と *Musixmatch* も記載されていました。
    > これら 2 つは実装されていません — Python 1.x 版でさえ未実装でした。README の記載が間違っていたのです。2.0 は実装されたソースのみを搭載します。**削除されたものはありません。**
*   🌐 **多言語UI:** **英語**、**繁体字中国語**、**日本語**に完全対応。
*   🌑 **ダークモード:** 洗練されたモダンなダークインターフェース。
*   ⚙️ **スマート設定:** Geniusトークンと言語設定を記憶します。
*   🍎 **macOSネイティブ対応:** Swift 6 / SwiftUI で作成。システム言語設定を尊重し、Music.app と Apple Events で統合。
*   📚 **バッチモード:** アルバム全体を一度に確認し、不足している歌詞を一括取得・インポート。
*   🖼 **Cover Flow:** 現在のアルバムアートワークを 3D カルーセルで閲覧（表示のみ — 再生コントロールなし）。

## 前提条件

**🔑 Genius API Token（必須）**

歌詞を取得するには、無料の Genius API トークンが必要です：

1. [genius.com/api-clients](https://genius.com/api-clients/) にアクセス
2. サインインまたはアカウント作成
3. **"New API Client"** をクリック
4. 必要な情報を入力（アプリ名、ウェブサイト URL - 任意の内容で可）
5. **Client Access Token** をコピー
6. 初回起動時にアプリの Settings で貼り付け

> **注意：** トークンは完全無料で、取得に 2 分もかかりません。

## インストール

### コンパイル済みアプリ (DMG)

[GitHub Releases](https://github.com/TK88101/Azathoths-Whisper/releases)から最新版をダウンロードしてください。

**⚠️ 重要：macOS での初回インストール手順**

このアプリは Apple Developer ID で署名されていないため、macOS Gatekeeper がブロックします。おそらく **「アプリケーションは破損しているため開けません」** というエラーが表示されますが、これはセキュリティ機能であり、実際に破損しているわけではありません。

**インストール手順：**

1. **DMGをダウンロードしてマウント**
   - Releases ページから最新の `.dmg` をダウンロード
   - ダブルクリックしてマウント

2. **アプリをインストール**
   - DMG ウィンドウ内の **アプリケーション (Applications)** フォルダショートカットに `Azathoth's Whisper.app` をドラッグ

3. **隔離フラグを削除（ダウンロードしたアプリに必須）**
   
   **ターミナル** を開き（アプリケーション → ユーティリティ → ターミナル）、以下を実行：
   ```bash
   xattr -d com.apple.quarantine /Applications/Azathoth\'s\ Whisper.app
   ```
   
   これにより「破損」エラーの原因となる macOS 隔離属性が削除されます。

4. **アプリを開く**
   
   これで通常通り開けます：
   - **方法 A**：アプリケーションフォルダでアプリをダブルクリック
   - **方法 B**：右クリック → 開く（まだプロンプトが表示される場合）
   
   ✅ アプリが起動します。macOS は選択を記憶し、次回以降は確認なしで起動できます。

5. **自動化権限の付与**
   - 初回起動時に iTunesの制御許可を求められます
   - **「OK」** をクリックして許可

**なぜこうなるのか？**
- macOS はインターネットからダウンロードしたすべてのアプリに「隔離」フラグを追加します
- Apple Developer 署名のないアプリはこのフラグ付きだと「破損」と表示されます
- フラグを削除すればアプリは正常に動作します

### ソースコードからのビルド

要件: **macOS 14.0+**, **Xcode 16+** (Swift 6), [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

> macOS 26.6 / Xcode 26.6 / Swift 6.3 で動作確認済みです。上記の下限は
> `project.yml` の指定 (`deploymentTarget: 14.0`、`SWIFT_VERSION: 6.0`) に基づいていますが、
> 直接検証されていません。

1.  **リポジトリのクローン**
    ```bash
    git clone https://github.com/TK88101/Azathoths-Whisper.git
    cd Azathoths-Whisper/AzathothsWhisper
    ```

2.  **XcodeGen をインストール**
    ```bash
    brew install xcodegen
    ```

3.  **Xcode プロジェクトを生成**
    ```bash
    xcodegen generate
    ```
    `.xcodeproj` は `project.yml` から生成され**既に commit 済み**なので、通常のクローンではビルドが可能です。
    ソースファイルを追加・削除したあとに再実行する必要があります — そうしないと Xcode が古いファイルリストでビルドし続けます。
    再生成されたプロジェクトはこの変更と一緒に commit してください。SwiftSoup は初回ビルド時に Swift Package Manager で解決されます。

4.  **テストを実行**
    ```bash
    xcodebuild test -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper \
      -destination 'platform=macOS' -only-testing:AzathothsWhisperTests \
      -test-timeouts-enabled YES -default-test-execution-time-allowance 120
    ```
    UI テスト (`-only-testing:AzathothsWhisperUITests`) を実行するには、**システム設定 → プライバシーとセキュリティ → アクセシビリティ** で Xcode にアクセシビリティ権限を付与してください。

5.  **リリースアプリをビルド**
    ```bash
    WORK="$(mktemp -d)"
    xcodebuild build -project AzathothsWhisper.xcodeproj -scheme AzathothsWhisper \
      -configuration Release -destination 'platform=macOS' -derivedDataPath "$WORK/dd"
    ```
    結果は **ad-hoc** で署名されます (`CODE_SIGN_IDENTITY: "-"`)。上記「インストール」で説明する隔離ステップが必要な理由です。

6.  **DMG を作成**

    ディスクイメージはリポジトリに含まれるウィンドウレイアウトを再利用するため、レイアウトは再現可能です。
    Finder スクリプト（と自動化プロンプト）は不要です：

    ```bash
    # $WORK は手順 5 から；新しいシェルの場合は再度宣言してください
    APP="$WORK/dd/Build/Products/Release/Azathoth's Whisper.app"
    STAGING="$WORK/staging"; mkdir -p "$STAGING"

    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    cp ../packaging/dmg-layout.DS_Store "$STAGING/.DS_Store"
    cp ../dmg_background.png "$STAGING/"
    chflags hidden "$STAGING/dmg_background.png"

    hdiutil create -volname "Azathoth's Whisper" -srcfolder "$STAGING" \
      -format UDZO -ov "$WORK/Azathoths-Whisper-v2.0.1.dmg"
    ```

    ボリューム名とアイテム名は上記のままにしてください — `.DS_Store` がバックグラウンドイメージとアイコン位置を名前で解決します。
    (`.dmg` ファイル自体は実行間での完全な byte-for-byte 再現性はありませんが、レイアウトは再現可能です。)

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

## トラブルシューティング

バージョン 2.0 は統合ログシステム (OSLog) を使用してログを出力し、ファイルに書き込みません —
1.x の `~/Documents/Bjork/app_debug.log` はもう存在しません。ログを収集するには：

```bash
log show --predicate 'subsystem == "com.ibridgezhao.azathothswhisper"' --last 1h --info
```

カテゴリは `batch`、`coverflow`、`artwork-disk` です。特定カテゴリに絞り込む場合は
`--predicate 'subsystem == "com.ibridgezhao.azathothswhisper" AND category == "batch"'` を使用してください。

これらのログは issue に安全に添付できます：Keychain と設定関連のコードパスはログ出力を一切行わないため、
Genius トークンはログに記録されません。

**よくある問題**

| 症状 | 原因 | 対処方法 |
|---|---|---|
| 「アプリケーションは破損しているため開けません」 | ダウンロード・ad-hoc 署名アプリの隔離フラグ | `xattr -dr com.apple.quarantine "/Applications/Azathoth's Whisper.app"`、または システム設定 → プライバシーとセキュリティ → *このまま開く* |
| トラック検出されない | Music への自動化権限が拒否された | システム設定 → プライバシーとセキュリティ → 自動化 → このアプリに対して Music を有効化してから再起動 |
| アップデート後、macOS が Music または Keychain アクセスを再度要求 | Ad-hoc 署名は毎回変わり、TCC と Keychain はコード署名で区別する | 予期される動作 — もう一度許可してください |
| 歌詞が見つからない | Genius トークンが無い、または無効 | 設定 → Genius Token Settings |

## アンインストール

```bash
rm -rf "/Applications/Azathoth's Whisper.app"
rm -rf ~/Library/Caches/com.ibridgezhao.azathothswhisper      # アートワークディスクキャッシュ
defaults delete com.ibridgezhao.azathothswhisper              # 言語 / UI 設定
```

Genius トークンはログイン Keychain に保存されています — **Keychain Access** を開き、
`com.ibridgezhao.azathothswhisper` で検索してエントリを削除してください。1.x 設定ファイル
(`~/.azathoths_whisper_config`) はアプリによって削除されません；不要になった場合は手動で削除してください。

## 技術スタック

*   **Swift 6 / SwiftUI**: コアロジックと標準 UI（デプロイ対象 macOS 14.0）。
*   **ScriptingBridge / Apple Events**: Music.app の自動化（現在のトラック読取、歌詞の読取・書込、アートワーク取得）。
*   **SwiftSoup**: 歌詞ソースの HTML 解析。
*   **XcodeGen**: `project.yml` から生成される Xcode プロジェクト — `.xcodeproj` は生成され、既に commit 済みなので、通常のクローンではビルド可能です。
*   **Keychain**: Genius トークンの保管（1.x の `.env` / 設定ファイルから自動移行）。

> **バージョン 2.0 は完全なネイティブリライトです。** 1.x 版の Python/Tkinter/PyInstaller 実装はリポジトリルートに参考用として保持されています。配布版アプリは `AzathothsWhisper/` から完全に構築されます。

## ライセンス

MIT —— [LICENSE](LICENSE) を参照してください。

本アプリには以下のサードパーティコンポーネントが含まれます。
各ライセンス文書は App 内（`Contents/Resources/`）に同梱しています。

| コンポーネント | ライセンス |
|---|---|
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | MIT |
| Space Grotesk | SIL Open Font License 1.1 |
| Material Symbols | Apache License 2.0 |

## 免責事項

このプロジェクトは教育目的でのみ提供されています。取得された歌詞の著作権はそれぞれの所有者に帰属します。大量にダウンロードする前に、使用権を確認してください。

---
Created by [iBridgeZhao]
