# Azathoth's Whisper (アザトースの囁き)

[**English**](README.md) | [**繁體中文**](README_ZH.md) | [**日本語**](README_JA.md)

**Azathoth's Whisper**は、**iTunes**で現在再生中の曲の歌詞を自動的に取得し、オーディオファイルのカスタム歌詞メタデータに直接埋め込むmacOSアプリケーションです。

複数の歌詞ソースをサポートし、ダークテーマと多言語ユーザーインターフェースを備えています。

**3.0 の新機能：iPad リモコン。** このリポジトリからは、次の 2 つのアプリをビルドします。

| アプリ | プラットフォーム | バージョン | 内容 |
|---|---|---|---|
| **Azathoth's Whisper**（アザトースの囁き） | macOS | 3.0.0 | 上記の歌詞アプリ。iPad から この Mac の Music を操作できるようにする**中継**機能（任意）を追加 |
| **Yog-Sothoth's Echo**（ヨグ＝ソトースの残響） | iPad | 1.0.0 | レコードプレーヤー風のリモコン。家のどこからでも Mac の Music ライブラリを見て、再生を操作できます |

iPad アプリが通信する相手は、自宅のネットワーク内にあるあなた自身の Mac の Azathoth's Whisper だけです。
詳しくは [iPad リモコン：Yog-Sothoth's Echo](#ipad-リモコンyog-sothoths-echo) を参照してください。

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
*   📱 **iPad リモコン（3.0）:** 中継をオンにすると、Music ライブラリと再生操作を iPad アプリ「Yog-Sothoth's Echo」から使えます。初期設定はオフです。

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
      -format UDZO -ov "$WORK/Azathoths-Whisper-v3.0.0.dmg"
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

## iPad リモコン：Yog-Sothoth's Echo

Yog-Sothoth's Echo は、iPad を Mac の Music 用のレコードプレーヤー風リモコンにするアプリです。音は**Mac から**出ます（Mac のスピーカーや、Mac につないだオーディオ機器）。iPad は操作するだけです。

**iPad でできること**

*   Mac のライブラリにある全アルバムを、3D の背表紙かジャケットの一覧で見られます。検索もできます。
*   アルバムを開いて曲を選ぶと、Mac がその曲から再生し、アルバムの続きの曲もそのまま流れます。
*   プレーヤー画面では、レコードをタップすると一時停止／再開、左右にスワイプすると曲送り／曲戻しです。
*   下のカプセルには、前の曲／再生・一時停止／次の曲と **Genius**（Music 本体の Genius シャッフル。上の Genius 歌詞トークンとは別物です）があります。
*   レコードの見た目（Random、Classic、Transparent、Splash、Marble）と、ライト／ダーク／システムに合わせる外観を選べます。

**必要なもの**

*   **iPadOS 18 以降**の iPad。Mac と同じ自宅のネットワーク（Wi-Fi）につないでおきます。
*   **Azathoth's Whisper 3.0.0** を実行していて、Music.app を開いている Mac。

### iPad アプリのインストール

iPad アプリは [Releases ページ](https://github.com/TK88101/Azathoths-Whisper/releases) に `.ipa` として置いています。**署名はしておらず**、App Store にもありません。**SideStore**、**AltStore**、**iLoader** などのサイドロードツールで、自分の Apple ID で署名してインストールしてください。

> 無料の Apple ID でサイドロードしたアプリは **7 日**で使えなくなります。そのときは署名／インストールし直してください（SideStore なら自動で更新できます）。上書きインストールならペアリングは残ります。

### 初回の設定

**Mac**（Azathoth's Whisper 3.0.0）側：

1.  **Settings → Remote Settings…** を開き、**Allow Yog-Sothoth's Echo on iPad to control Music** をオンにします。中継は**初期状態ではオフ**です。
2.  キーチェーンの確認が出たら、Mac のログインパスワードを入力して **常に許可** を選びます。ビルドごとに ad-hoc 署名が変わるので、アップデートのたびにまた聞かれます。
3.  **Music Control** の **Install Shortcut** を押し、ショートカット App で **ショートカットを追加** を押します。これで「YSE Play v1」ショートカットが入り、選んだ曲のあとにアルバムの続きが流れるようになります。共有について聞かれたら **常に許可** を選んでください。
4.  設定画面に出てくる権限を許可します：**オートメーション → Music**、**メディアと Apple Music**（ライブラリの読み取り）、それから Genius ボタンを使う場合だけ **アクセシビリティ**。
5.  任意：**Open Azathoth's Whisper at login** をオンにしておくと、アプリを手で開かなくても iPad からつながります。

ペアリング：

1.  Mac で **Pair new iPad** を押すと、60 秒間だけ有効な QR コードが出ます。
2.  iPad で Yog-Sothoth's Echo を開き、コードを読み取ります。カメラとローカルネットワークへのアクセスを聞かれたら許可してください。
3.  Mac に **Unverified device request** と 4 文字が表示されます。iPad に出ている 4 文字と同じか確かめてから **Allow** を押します。

これ以降、iPad は自動で再接続します。Mac がスリープから戻ったときや、アプリを開き直したときも同じです。ペアリングを解除するには、Mac の **Paired iPads** からその iPad を削除します。

### 既知の制限

*   曲を選ぶと、Music の **次はこちら** がそのアルバムの選んだ曲以降に置き換わります。元のキューは保存も復元もしません。タップしてから再生が始まるまで約 1.5 秒かかります。
*   アルバムの続きを流すには「YSE Play v1」ショートカットが必要です。ショートカットがないときや、アルバム名がほかと紛らわしいときは、選んだ 1 曲だけを再生し、iPad にそう表示します。
*   続けて曲送りすると、前の操作が反映されるまで待ちます（1 曲あたり約 1.5 秒）。4 回目以降の連打は受け付けません。
*   iPad からの再生位置の移動と音量調整はできません。使えるのは自宅のネットワーク内だけです。
*   ライブラリの変更は 1 分ほどで iPad に反映されます（Mac は 60 秒ごとにライブラリを確認します）。

### プライバシーとセキュリティ

*   中継はオンにするまで動きません。受け付けるのは、QR コードでペアリングし、**かつ** Mac で許可した iPad だけです。
*   接続はすべて、証明書をピン留めした相互認証の TLS で、ローカルネットワーク内に限ります。リクエストには再送攻撃への対策があり、決まった種類のコマンドしか受け付けません。
*   Mac 側の中継は Music のライブラリを**読むだけ**で、あとは再生コマンドを送ります。ライブラリの編集や、Music のキューファイルへの書き込みはしません。アクセシビリティは Music の Genius メニュー項目を押すためだけに使います。
*   ログに残すのは ID とエラーの種類だけです。曲名、歌詞、トークン、ペアリング用の秘密情報は残しません。

### iPad アプリをソースからビルドする

必要なもの：**Xcode 16 以降**（Swift 6、iOS 18 SDK）、XcodeGen。Xcode 27 でビルドと動作を確認しています。

```bash
cd Azathoths-Whisper/YogSothothsEcho
xcodegen generate

# 単体テスト（iPad のシミュレーターならどれでも可。名前は手元のものに合わせる）
xcodebuild test -project YogSothothsEcho.xcodeproj -scheme YogSothothsEcho \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -only-testing:YogSothothsEchoTests

# 署名なしの Release .ipa（サイドロードツールで署名する）
WORK="$(mktemp -d)"
xcodebuild build -project YogSothothsEcho.xcodeproj -scheme YogSothothsEcho -sdk iphoneos \
  -configuration Release CODE_SIGNING_ALLOWED=NO -derivedDataPath "$WORK/dd"
mkdir -p "$WORK/ipa/Payload"
cp -R "$WORK/dd/Build/Products/Release-iphoneos/Yog-Sothoth's Echo.app" "$WORK/ipa/Payload/"
(cd "$WORK/ipa" && zip -qry ../YogSothothsEcho.ipa Payload)
```

共通の通信・プロトコルのコードは `YogSothothsEcho/Packages/EchoKit` にあります。Mac アプリも同じパッケージを使ってビルドするので、2 つのアプリは同じリポジトリに置いておく必要があります。

> **プレーヤーの画像：** レコード、トーンアーム、背景の画像はリポジトリに**含めていません**。ソースからビルドすると、代わりに簡単な図形を表示します。公開している `.ipa` にはこれらの画像が入っています。[ライセンス](#ライセンス) を参照してください。

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
| iPad から Mac が見つからない | 中継がオフ、Mac が別のネットワーク、または iPad でローカルネットワークへのアクセスを拒否した | Remote Settings で中継をオンにする；両方を同じ Wi-Fi につなぐ；iPad の 設定 → プライバシーとセキュリティ → ローカルネットワーク → Yog-Sothoth's Echo |
| iPad に「Mac での許可が必要」と出る | アプリを更新したので、キーチェーンがもう一度確認している | Mac の Remote Settings で **Authorize on this Mac** を押し、パスワードを入力して **常に許可** |
| 選んだ曲だけが流れて、アルバムの続きが流れない | 「YSE Play v1」ショートカットがない | Remote Settings → **Install Shortcut**（または **Reinstall Shortcut**） |
| Genius ボタンがグレーになっている | Mac の Music が開いていない、または iPad が未接続 | Mac で Music を開く（アクセシビリティで Genius を許可していない場合でも押せますが、許可の方法を表示するだけです） |

## アンインストール

```bash
rm -rf "/Applications/Azathoth's Whisper.app"
rm -rf ~/Library/Caches/com.ibridgezhao.azathothswhisper      # アートワークディスクキャッシュ
defaults delete com.ibridgezhao.azathothswhisper              # 言語 / UI 設定
```

Genius トークンはログイン Keychain に保存されています — **Keychain Access** を開き、
`com.ibridgezhao.azathothswhisper` で検索してエントリを削除してください。1.x 設定ファイル
(`~/.azathoths_whisper_config`) はアプリによって削除されません；不要になった場合は手動で削除してください。

中継用の ID（秘密鍵と自己署名の証明書）は `com.ibridgezhao.azathothswhisper.relay-identity` に保存されています。iPad リモコンを使っていた場合は、ショートカット App で「YSE Play v1」も削除し、システム設定 → 一般 → ログイン項目 でログイン時の起動もオフにしてください。

iPad アプリは、ほかのアプリと同じように iPad から削除できます。

## 技術スタック

*   **Swift 6 / SwiftUI**: コアロジックと標準 UI（デプロイ対象 macOS 14.0）。
*   **ScriptingBridge / Apple Events**: Music.app の自動化（現在のトラック読取、歌詞の読取・書込、アートワーク取得）。
*   **SwiftSoup**: 歌詞ソースの HTML 解析。
*   **XcodeGen**: `project.yml` から生成される Xcode プロジェクト — `.xcodeproj` は生成され、既に commit 済みなので、通常のクローンではビルド可能です。
*   **Keychain**: Genius トークンの保管（1.x の `.env` / 設定ファイルから自動移行）と、中継／iPad の端末 ID。
*   **Network.framework**: Mac の中継と iPad の間の Bonjour による検出と、証明書を相互にピン留めした TLS 1.3（`YogSothothsEcho/Packages/EchoKit`）。
*   **iTunesLibrary**: iPad のアルバム一覧用に、Music ライブラリを読み取り専用で参照。
*   **ショートカット（Shortcuts）**: 「YSE Play v1」ショートカットで、曲をアルバムの流れのまま再生。
*   **VisionKit**: iPad での QR コード読み取り。

> **バージョン 2.0 は完全なネイティブリライトです。** 1.x 版の Python/Tkinter/PyInstaller 実装はリポジトリルートに参考用として保持されています。配布版アプリは `AzathothsWhisper/` から完全に構築されます。

## ライセンス

MIT —— [LICENSE](LICENSE) を参照してください。

本アプリには以下のサードパーティコンポーネントが含まれます。
各ライセンス文書は App 内（`Contents/Resources/`）に同梱しています。

| コンポーネント | ライセンス |
|---|---|
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | MIT |
| Space Grotesk | SIL Open Font License 1.1 |
| Grimoire of Death, UnifrakturMaguntia, Cinzel, Cormorant Garamond | SIL Open Font License 1.1 |
| Abril Fatface, Alfa Slab One, Anton, Archivo Black, Bebas Neue, Bungee, Oswald, Playfair Display, Righteous | SIL Open Font License 1.1 |
| Bangers, Dela Gothic One, Gochi Hand, Lilita One, Rubik, Saira Stencil One | SIL Open Font License 1.1 |
| Barrio, Black Ops One, Space Mono | SIL Open Font License 1.1 |
| Courier Prime, IM Fell English SC, Shadows Into Light | SIL Open Font License 1.1 |
| Special Elite, Syncopate, Permanent Marker, Rock Salt | Apache License 2.0 |
| Catacombs（ToughCrest Studio） | 個人・商用ともに無料。再配布時は ToughCrest Studio のクレジット表記が必要 |
| Cenobyte（Chad Savage）、Mirage Gothic、Dark Metal | 商用利用条件は未確認（Cenobyte は「Freeware」のみ、Mirage Gothic は「All rights reserved」埋め込み、Dark Metal はライセンスファイルなし）。メンテナーの責任で同梱 |
| Material Symbols | Apache License 2.0 |

iPad アプリ（Yog-Sothoth's Echo）に含まれるもの：

| コンポーネント | ライセンス |
|---|---|
| Space Grotesk | SIL Open Font License 1.1 |
| **MD Vinyl** アプリから取り出したプレーヤー画像（レコード、トーンアーム、台座、背景） | **このリポジトリのライセンスの対象外**です。権利は元の作者にあります。画像はリポジトリには含めておらず、公開している `.ipa` にだけ入っています。メンテナー自身の責任で同梱しています |

## 免責事項

このプロジェクトは教育目的でのみ提供されています。取得された歌詞の著作権はそれぞれの所有者に帰属します。大量にダウンロードする前に、使用権を確認してください。

---
Created by [iBridgeZhao]
