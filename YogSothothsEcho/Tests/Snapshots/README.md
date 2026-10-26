# 連線頁渲染基準圖（S6.5 T8）

`PairingSnapshotTests` 的基準 PNG。只放測試 bundle，不進 App。重錄：
`Scripts/record_snapshots.sh`（腳本自建暫存目錄，以 `TEST_RUNNER_PAIRING_SNAPSHOT_DIR` 讓測試把新圖寫出，再複製到這裡）。
入庫前使用者看過一次（CR-033）。比對容差：逐像素 RGB 最大差 ≤ 8 的像素占比 ≥ 99.5%。
