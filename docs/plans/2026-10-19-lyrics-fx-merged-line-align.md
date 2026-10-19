# 外部時間軸對齊：Genius 一行＝LRC 多行（計劃）

## 0. 複述
使用者 2026-10-19 真機：Arch Enemy〈War Eternal〉「整體都對不上」。已核：有錨定的 30 行與網易雲獨立 LRC 差 ≤ 0.3 s；錯的 7 行是 Genius 把 LRC 的兩行合成一行，`LRCAligner.matchedIndices` 只做一對一，相似度不到 0.8 → 未錨定 → 內插（第 0 行顯示 15.4 s、實際 31.0 s）。截窗證實 0:20.95 已整行顯示。

## 1. 目標與非目標
- 目標：Music 一行對上 LRC 連續 2–3 行（串接後相似度 ≥ 0.8）時，錨定到第一行的起點。
- 非目標：反方向（LRC 一行＝Music 多行，例：網易雲「…change you, crush and break you」）；內插演算法本身；逐字限速（另一份計劃）。

## 2. 設計
- `matchedIndices`：每個候選起點 `index` 先試單行；不中再試 `cues[index..<index+k]`（k = 2, 3，全部非空）串接。命中記 `(index, span)`，`cursor = index + span`。
- `lrcCoverage` 照舊以對上的 Music 行數計（不放寬防錯錨門檻），`musicRate` 不變。
- `LRCAligner.revision = 2`；存檔加可選欄位 `alignerRevision`（缺＝1，不升 schemaVersion）；`TimingLookupPolicy`：found 且版本舊→重查一次（notFound 照 7 天）。重查失敗時合併規則 found 勝 notFound，舊錨點保留。

## 3. 測試
- 合併兩行、三行都能錨到第一行起點；單行優先（單行可中時不取串接）；串接不跨空行；coverage 以用掉的行數計；既有一對一測試全部不變。
- 真機：〈War Eternal〉開頭 3 行與副歌前 4 行和網易雲差 ≤ 0.5 s。

## 4. 評審（Codex gpt-5.6-terra，medium，2026-10-19）
| # | Codex 意見 | 處置 |
|---|---|---|
| Q1 | 前方串接可能搶走後方正確單行；要補反例測試 | 部分採納：補「前面兩行／後面一行取最早」「重複副歌錨第一段」測試；駁回改成「單行優先跨全段」——與既有一對一「取最早」一致，串接需全長 ≥ 0.8 才中 |
| Q2 | 分子改用掉的行數會放寬防錯錨門檻 | 採納：覆蓋率維持舊算法 |
| Q3 | 不跨空行 | 一致 |
| Q4 | 舊 found 永不重查，修正到不了使用者（最擔心） | 採納：`alignerRevision` |
| Q5 | 反方向另案 | 一致 |

## 5. TDD
- 紅：合併兩行／三行 2 條 4 處失敗。綠：LRCAligner＋TimingStore＋LookupPolicy 39 條；全量 1444 條中唯一一紅為本計劃新測試資料寫得不嚴（前三行已達 0.8），修資料後該 suite 綠。

## 6. 真機紀錄
- 2026-10-19 21:4x Arch Enemy〈War Eternal〉：使用者「差不多」。
- 2026-10-19 21:4x 下一首（網易雲時間軸 music=0.78 lrc=0.89）：使用者「差不多」。
- 2026-10-19 21:56 Burzum〈Jesus' Tod〉（Death Metal/Black Metal，LRCLIB 8 行全對上）：使用者「沒問題」（樣式＋時間軸）。
- 2026-10-19 21:5x The Agonist〈The Escape〉（メタル）：仍為 mono——已核：畫面樣式由 SongProfileResolver（34 團覆寫表＋只有黑金屬／交響兩列曲風）決定，一般 metal 本來就是 mono（B1 範圍）；e6f3d65 對它沒有可見效果。GenreStyleResolver 的家族目前沒有被畫面使用。
