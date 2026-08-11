# M1 AE Spike 結論（2026-08-10，Xcode 26.6 / Swift 6.3.3 / macOS 26）

五項全通（`./music_spike` 實測輸出）：

| # | 操作 | 結果 |
|---|---|---|
| 1 | playerState＋currentTrack 全字段 | kPSp（paused）下可讀；persistentID/disc/track number 齊全 |
| 2 | 讀當前曲 lyrics | 589 字符正常 |
| 3 | by-persistentID 過濾＋setLyrics | `filtered(using: NSPredicate("persistentID == %@"))`＋原值回寫 ok=true |
| 4 | artwork raw data | 見下述陷阱 3；descType=tdta，510KB，magic ffd8＝JPEG |
| 5 | album+artist 雙條件過濾 | `NSPredicate("album == %@ AND artist == %@")` → 15 曲，含逐曲 lyrics 狀態 |

**技術定案（M4 實現依據）**：bridge＝ScriptingBridge＋手寫 `@objc protocol`（無需 sdp 生成頭文件）；`extension SBApplication: MusicAppProto {}` / `extension SBObject: MusicTrackProto {}`。

**陷阱（M4 必讀）**：
1. `SBElementArray.filtered(using:)` 在 Swift 中返回 `[Any]`——用 `.first as! SBObject`，不是 `.object(at:)`。
2. paused 狀態 currentTrack 可讀——印證 Plan §4.3 M10 語義（僅 stopped/無曲＝notPlaying）。
3. **artwork rawData 三連陷阱**：聲明為 `Data`/`NSData` 屬性直接訪問都會炸（返回未求值 SBObject 代理，`-[SBObject length]` unrecognized selector）。正解＝`artObj.value(forKey: "rawData")` → `(ref as? SBObject)?.get()` → 得 `NSAppleEventDescriptor`（descType `tdta`），`.data` 即圖像字節（實測 JPEG ffd8ffe0）。
4. TCC：本開發機的宿主進程已有 Music 自動化授權，無 -1743；乾淨機首彈路徑留 M8 checklist 驗證。

工件：`music_spike.swift`（可重編譯複驗）；spike 代碼用完即棄，不併入正式 target（slipknot 18 紀律）。
