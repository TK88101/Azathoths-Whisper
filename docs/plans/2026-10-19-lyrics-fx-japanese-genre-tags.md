# 歌詞特效：日文曲風標籤對應英文（計劃）

## 0. 複述
使用者 2026-10-19 真機：The Agonist〈The Escape〉（genre「メタル」）顯示素面 mono；指示「把日語的風格和英文做映射」。

## 1. 事實
- 已核：`GenreStyleResolver.englishRules` 只有英文關鍵字，「メタル」不中任何規則 → `.mono`。
- 已核：`japaneseTags = ["ロック", "j-pop"]`：標籤含「ロック」即判日本語系（母計劃 §2.5 體系判定）。
- 已核（osascript 唯讀）：曲庫標「ロック」的是 The Beatles、Queen、Oasis、Guns N' Roses、HIM、Pessimist 等西洋樂團；標「メタル」的是 Slipknot、In Flames、Stone Sour、Pantera 等。→ 這兩個標籤是 Music 日文介面的曲風名，不代表日本樂團。

## 2. 設計
- 標籤正規化（`GenreStyleResolver` 內單一定義，`resolve` 與 `genre(_:matches:)` 共用）：先把日文曲風名換成英文再套原規則。對照：ロック→rock、ハードロック→hard rock、メタル→metal、ヘヴィメタル→heavy metal、ブラックメタル→black metal、デスメタル→death metal、パンク→punk、ハードコア→hardcore、オルタナティブ→alternative、インディー→indie、ポップ→pop、エレクトロニック／エレクトロニカ→electronic、ダンス→dance、ヒップホップ→hip-hop、ラップ→rap、R&B／ソウル→r&b／soul、クラシック→classical、サウンドトラック→soundtrack、フォーク→folk、カントリー→country、ワールド→world、ゴシック→goth、インダストリアル→industrial。長的先換（ハードロック先於ロック）。
- 「ロック」不再是日本語系訊號；`japaneseTags` 只留 `j-pop`（加 `j-rock`）。日本語系仍由歌詞假名＋漢字比例 ≥ 0.3 判定。
- 偏離母計劃 §2.5「標籤含ロック→日本語系」：使用者 2026-10-19 指示。副作用：日本樂團唱英文、標「ロック」的歌改走英語系 rock。

## 3. 測試
- 「ロック」＋英文詞→`.rock`；「ロック」＋日文詞→`.jrock`；「ポップ」＋日文詞→`.jpop`；各對照項→對應家族；`genre("メタル", matches: "metal")`。既有 69 個標籤表中「ロック」一列改為 `.rock`。
