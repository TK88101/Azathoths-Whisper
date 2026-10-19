# 時間軸跨 Mac 搬移（iCloud Drive，Codex 4 輪收斂）

## 0. 複述
使用者 2026-10-19：希望存 iCloud，換 Mac 時找到的時間軸不白費。

## 1. 事實
- ad-hoc 簽名、無 entitlement、無沙盒：用不了 App 專屬 iCloud 容器／CloudKit；可寫 iCloud Drive 一般資料夾（已核）。
- 同一路徑多台 Mac 直寫會產生衝突副本（repo 裡的「 2／ 3.xcodeproj」前例）；persistentID 在曲庫重建時可能改變（Apple 文件）。

## 2. 設計
- 本機 Application Support 仍是正本。
- 開「iCloud Drive 同步」時，每台 Mac 只寫自己的一個檔：iCloud Drive/Azathoth's Whisper/Timings/<writer UUID>.azw-timings（整份、有版本、原子替換、變更時最多一天一次＋結束時盡力）。檔內記硬體 UUID 的 SHA-256；本機記錄的硬體雜湊與現機不同＝被複製的機器 → 發新 writer UUID。
- 啟動與每天一次唯讀匯入其他 Mac 的檔：鍵 (persistentID, lyricsHash)，同鍵全序 fetchedAt → writer UUID → 內容 SHA-256，found 勝 notFound；一律要求與目前歌詞重算的 lyricsHash 一致、錨點落在目前歌詞行數內。persistentID 不同者以 lyricsHash 建索引，播放到該曲且本機無 found 時才查（本機 notFound 不擋），唯一命中才套用。讀不到／未下載／寫失敗保留 dirty、下回重試；開啟後立即匯入一次。
- 手動匯出／匯入：同格式、同驗證、逐筆合併。
- 預設關閉，首次提示可開；設定頁寫明檔案內容（曲目識別碼、歌詞雜湊、時間點、取得日期、來源名）；關閉＝停止讀寫，刪雲端檔另一個明示操作。
- 順序：檔案格式與驗證 → 手動匯出入 → 自動同步 → 設定 UI。
