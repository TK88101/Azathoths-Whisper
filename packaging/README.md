# packaging

DMG 版式模板。`dmg-layout.DS_Store` 抽自已發行的 `Azathoths-Whisper-v1.2.4.dmg`，
用途是讓新版 DMG 沿用同一套視窗版式（圖示位置、視窗尺寸、背景圖引用），
**不需要 Finder 自動化，也就不需要授權彈窗**——出貨結果的版式與 1.x 逐像素一致。

| 檔案 | 說明 |
|---|---|
| `dmg-layout.DS_Store` | Finder 版式資料。打包時複製到 staging 根目錄並改名為 `.DS_Store` |
| （背景圖） | 用倉庫根的 `dmg_background.png`，兩者逐位元組相同，不重複入庫 |

**約束**：`.DS_Store` 是**按名稱**解析背景圖與圖示位置的，因此打包時
卷名必須是 `Azathoth's Whisper`，卷內項目必須恰為
`Azathoth's Whisper.app`、`Applications`（軟連結）、`dmg_background.png`（需 `chflags hidden`）。
改動任何一個名稱，版式就會失效。

用法見三語 README 的 Build from Source 第 6 步。
