# 歌詞特效：行內逐字出現太慢（計劃草稿，待拍板）

## 0. 複述
使用者 2026-10-19 真機回報（Oasis〈Don't Look Back in Anger (Remastered)〉）：「唱的比詞快，詞出得慢，一眼就看得出」。C 段測完後另議；本檔是與 Codex 辯論收斂後的方案。

## 1. 目標與非目標
- 目標：外部 LRC 與內嵌 LRC 的英文（Latin、空白分詞）行，字不再明顯晚於演唱。
- 非目標：真正的逐字同步（母計劃非目標，網易雲 yrc 只拿來評估）；推估路徑；CJK 與其他空白分詞語言（韓文等）；未直接對上的行的內插（另案）；「間奏時上一行仍是當前行」（既有行為）。

## 2. 事實與推論
- 已核：存檔行起點與 LRCLIB 逐行差 < 0.5 s（資料正確）。
- 已核：`TimedWord.split`（`Services/Lyrics/LyricsTimeline.swift:39-52`）把字攤在「本行起點→行終點」，行終點＝下一行起點（`LRCAligner.swift:92-96`、`LyricsTimelineBuilder.embedded`），停頓與間奏都被算進去。
- 實測（網易雲 yrc 為參考標籤，英文 30 首／22 位歌手，曲目分 train/holdout，可見起點含 `GlyphPersonality` 的 0.9 係數）：
  | holdout 16 首 | 晚 > 1 s | 早 > 1 s | p90 | 最差一首早 > 1 s |
  |---|---|---|---|---|
  | 現行 | 16.7 % | 1 % | 1.69 s | 6 % |
  | 本方案 | 9.2 % | 4 % | 1.21 s | 17 % |
  metal 20.8 %→9.6 %、ballad 17.5 %→7.9 %（早 2 %→7 %）；逐首晚 > 1 s 變差 0/16。
- 被否決：固定上限 0.04/字＋0.2/詞（晚 0.4 %，但抒情歌早 21–23 %）、依整首唱速自適應（晚 1.1 %，但 Ed Sheeran〈Perfect〉早 30 %）——都過不了「最差一首早 ≤ 17 %」。

## 3. 設計
- `TimedLine` 加 `revealEnd`（`lineEnd` 不變）；`split` 攤到 `revealEnd`。
- `revealEnd = start + min(gap, 0.08 × 字數 + 0.40 × 詞數)`，只用在外部 LRC 與內嵌 LRC 兩條路徑、且行為 Latin 字母空白分詞時；其餘照舊。
- 不變式：`revealEnd ∈ [start, lineEnd]`、有限值、gap 0、末行（`lastLineFallback`／曲長）。

## 4. 評估腳本（判斷「對不對得上」的方法）
- `Scripts/`：抓取（獨立命令，存本機 JSON；曲目清單放 repo 外）＋評估（只吃 JSON；分詞與 Swift 相同；輸出晚／早分布、逐首最差、direct/interpolated 分開）＋ `test_*.py`；seed／fixture／期望值固定。
- 出貨門檻：逐首晚 > 1 s 不劣於現行；holdout 晚 > 1 s ≤ 9.2 %；逐首早 > 1 s ≤ 17 %。

## 5. 順序
①評估腳本與單元測試（紅）→②純函式→③兩條路徑接線→④全量單元＋腳本重現數字→⑤真機：快速金屬、抒情歌、日文（確認不變）各 1 首。與 C 段分開分支、分開 commit。

## 5.1 真機紀錄
- 2026-10-19 21:0x　#1 Oasis〈Don't Look Back in Anger (Remastered)〉（YT Music 時間軸）：使用者「這次差不多了」（修前：「唱的比詞快、詞出得慢」）。
- 2026-10-19 21:19　#2 The Story So Far〈High Regard〉（Punk，YT Music 時間軸 music=0.94 lrc=0.92）：使用者「跟得上」。
- 2026-10-19 21:2x　#3 Arch Enemy〈War Eternal〉（LRCLIB）：使用者「整體都對不上」。已核：有錨定的 30 行與網易雲獨立 LRC 差 ≤ 0.3 s；錯的是未錨定的 7 行——Genius 把 LRC 兩行合成一行（第 0–3 行、14–17 行），一對一對齊失敗、改用內插：第 0 行顯示 15.4 s（實際 31.0 s，早 15.6 s），截窗證實 0:20.95 暫停時已整行顯示。屬 C 段對齊（一行對多行）＋內插，非本修改；另案。

## 6. 辯論紀錄（Codex gpt-5.6-terra，medium，5 輪）
| 論點 | 結果 |
|---|---|
| 主因＝攤到下一行起點 | 一致 |
| `revealEnd` 與 `lineEnd` 分開 | Codex 勝 |
| 推估路徑不套用 | Codex 勝 |
| 係數依「晚比早嚴重」選 | Codex 勝 |
| CJK 先不動（樣本 6＋6 不足） | Codex 勝 |
| 只限 Latin 空白分詞（韓文等未評估） | Codex 勝 |
| 自適應方案可出貨 | Codex 勝（最差一首早 30 % 擋下） |
| 「最差一首 ≤ 現行 5.8 %」當門檻 | 我勝（無任何參數可達，等於不修）→ 改 ≤ 17 % |
| 用 yrc 評估、補間另案、yrc 不正式採用 | 一致 |

## 7. 待拍板
- 執行本方案（17 % 這個「最差一首的提早」是否可接受屬體感，真機 ⑤ 確認）。
