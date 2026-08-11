# Fixtures 來源與紀律

## html/（真實頁面存檔，2026-08-10 curl 抓取）

| 檔案 | 來源 URL | 備註 |
|---|---|---|
| darklyrics_metallica_masterofpuppets.html | http://www.darklyrics.com/lyrics/metallica/masterofpuppets.html | 200 |
| darklyrics_ironmaiden_pieceofmind.html | http://www.darklyrics.com/lyrics/ironmaiden/pieceofmind.html | 200 |
| darklyrics_motleycrue_drfeelgood.html | http://www.darklyrics.com/lyrics/motleycrue/drfeelgood.html | 200（變音符號藝人 normalize 案例） |
| darklyrics_darktranquillity_moment.html | http://www.darklyrics.com/lyrics/darktranquillity/moment.html | 200 |
| darklyrics_darktranquillity_damagedone.html | http://www.darklyrics.com/lyrics/darktranquillity/damagedone.html | 200；DDG 流程目標頁 |
| genius_*.html | https://genius.com/{slug}-lyrics | 4 頁均 200 |
| ddg_lite_darktranquillity.html | POST https://lite.duckduckgo.com/lite/ q=site:darklyrics.com "Dark Tranquillity" "Monochromatic Stains" | 真實返回，含指向 damagedone.html 的 result-link |

UA＝`Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36`（lyrics_fetcher.py:940 同值）。

**R1/R2 實測證據（2026-08-10）**：darklyrics.com **443 端口拒絕連接**（無 https）→ 維持 http＋ATS 例外；http 直連普通 curl 全部 200，**無 Cloudflare challenge** → URLSession 主路徑可行，WKWebView 實驗 adapter 目前不需要（保留停損設計）。

## golden/（make_fixtures.py 生成）

重跑冪等（已驗證 diff 為空）。各檔 `source`/`note` 欄記錄來源行號與語義要點。手工部分僅二：darklyrics_normalize 的內聯正則逐字拷貝（py:1305）、genius search JSON 合成形狀（py:1252-1256）——均在 note 標註。

**G4 vs G5a 重要差異（M0 真發現）**：現代 Genius 頁的第一個 `Lyrics__Container` 含貢獻者/翻譯頭與註釋文本，Python **手動 fallback**（G4）輸出帶此雜訊且無首行剝除；**庫路徑**（G5a，lyricsgenius 3.7.5：`data-lyrics-container` 選擇器＋LyricsHeader 刪除＋段頭/空行清洗）輸出乾淨。生產中 lyricsgenius 正常工作時用戶看到的是 G5a 行為。**Swift 單管線一致性口徑＝G5a**（Plan R3）；G4 作為 legacy 手動路徑參照保留，不作為 Swift 實現的符合性目標。
