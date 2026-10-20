# 時間軸查找：候選排序（借鏡 LyricsX，Codex 4 輪收斂）

## 0. 複述
使用者 2026-10-19 給 LyricsX 要我看可借鑑處。LyricsX（MPL-2.0，2022 停更）：中文來源並行、無正規化、品質分（歌手×曲名×時長幾何平均）、無文字對齊、存來源全文、全域＋每首 offset。

## 1. 事實（已核）
- LRCLIB 符合且帶時間軸的候選不只 1 筆就判 mismatch（`LRCLIBProvider.swift:36`）；其他來源只取第一個符合的（`TimedLyricsProvider.swift:72`）。
- Sum 41〈Walking Disaster〉當晚失敗主因是 LRCLIB 逾時（6 s），不是排序。

## 2. 設計
- 兩個純函式：rankCandidates（只看中繼資料：完全一致 → 歌手/曲名相似度 → 時長差，取前 3；同分以來源原始順序＋候選 ID 穩定）；pickAccepted（只在通過對齊的候選中：musicRate → lrcCoverage → 直接錨點數 → 來源原始順序）。provider 契約改為「候選清單＋逐筆取歌詞」，對齊與挑選在 resolver。逐筆串行、不繞過 SourceGate；20 s 到期取消未完成，只從已通過者挑，沒有就 unavailable（不存 notFound）。LRCLIB 廢除「唯一」規則。±3 s 維持。
- 每首＋全域時間偏移：[offset:] 只在 LRCParser 套一次；每首（persistentID＋歌詞指紋，指紋不符不套）與全域在建好的時間軸起點加一次：start = max(0, raw + track + global)，再對同一首做累積 max（單調非減）；存檔錨點不動，偏移另存；不混進 PlaybackPositionClock。
- 不做：並行查詢、逐字（yrc/KRC）、酷狗、無正規化搜尋、cookie、HTTP、存外部全文。
- 順序：共通選考 → LRCLIB → 其他 4 來源 → 偏移。
