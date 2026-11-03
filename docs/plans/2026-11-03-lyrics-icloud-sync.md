# 歌詞 ⑨：iCloud 跨 Mac 同步（計劃 v1.0 定稿）

狀態：**v1.0 定稿**（使用者 2026-11-03「認可 開始吧」；Codex 3 輪收斂＋§12-1 經 /thecure 辯論收斂＋整體確認 3 條已入，見附錄 B）。分支 `wip/lyrics-icloud-sync`（自 main 7efd52d）。
取代 `docs/plans/2026-10-19-lyrics-timing-icloud-sync.md`（只談時間軸、Codex 4 輪；本稿沿用其「每台 Mac 只寫自己的檔」骨架，差異見附錄 A）。

## 0. 複述
- 目標＝在 app 裡花時間或花網路查到的結果、以及使用者親手下的決定，換一台 Mac（或兩台並用）時不必重來。
- 完成標準＝§8 驗收。
- 不做＝同步偏好設定、憑證、快取、可由本機重掃得到的衍生表；改 Music 的任何資料；sandbox。

## 1. 使用者決定（既定，不重議）
1. 2026-10-19：希望存 iCloud，換 Mac 時找到的時間軸不白費。
2. ⑥b §1-4（2026-10-24）：MB 歌手存檔放 Application Support，不放 Caches；「iCloud 等路線圖最後一步再一起搬」。
3. ⑥b §1-3（2026-10-24）：每位歌手只查一次、不主動重查。
4. 2026-10-24：sandbox 先不用。
5. 2026-11-02：⑨ 做完接 ⑩「歌詞對不上唱的時機」。

## 2. 事實（已核，2026-11-03）
- **簽名與權限**：`project.yml:23` `CODE_SIGN_IDENTITY: "-"`（ad-hoc）、`:54` `ENABLE_APP_SANDBOX: "NO"`，repo 內無 `.entitlements`。→ 沒有 app 專屬 iCloud 容器、CloudKit、`NSUbiquitousKeyValueStore`（都要 iCloud entitlement＋描述檔）；只能讀寫 iCloud Drive 的一般資料夾（母計劃 `2026-10-03-lyrics-fx-mode.md:359` 同結論）。
- **本機 iCloud Drive**：`~/Library/Mobile Documents/com~apple~CloudDocs` 存在；`brctl status` 為 caught-up；「桌面與文件」同步為開（repo 所在 `~/Documents` 也在同步中，「 2.xcodeproj」副本即其衝突產物，見記憶）。
- **本機存檔盤點**（實測 `~/Library/Application Support/com.ibridgezhao.azathothswhisper/`、`defaults read` 只列鍵名與筆數）：

| 資料 | 位置 | 現況 | 鍵（身分） | 來源 | 重建成本 |
|---|---|---|---|---|---|
| 時間軸存檔 | `Timings/<persistentID>.json`（`TimingStore`） | 169 檔／680 KB | persistentID＋lyricsHash | 5 個外部來源查得，或「查過沒有」 | 每首重查 1–5 個來源；notFound 7 天內不重查 |
| MB 歌手存檔 | `ArtistStyles/artists.json`（`ArtistStyleStore`） | 418 位／205 KB | `normalizedArtist`（歌手名） | MusicBrainz | 首次約 22 分鐘背景查詢（⑥b 在場 #2） |
| 使用者決定 | `ArtistDecisions/decisions.json`（`ArtistDecisionStore`） | 尚無檔（0 筆；⑧ 處理歌手時才會產生） | 寫法家族 `spellingFamily` | 使用者在曲庫檢查親手指定 | **無法重建** |
| 同歌手共識 | `ArtistConsensus/consensus.json`（`ArtistConsensusStore`） | 99 位／16 KB，`builtAt` 2026-11-01 | 寫法家族 | 最近一次完整曲庫檢查掃描 | 打開曲庫檢查重掃一次（約 51–70 s，I-68） |
| 「這首沒有歌詞」標記 | UserDefaults `NoLyricsMarkedTrackIDs` | 0 筆 | persistentID | 使用者親手標記 | 無法重建（但目前 0 筆） |
| 配方歷史 | UserDefaults `LyricsFXLastPicks` | 500 筆（上限） | persistentID | 播放時自動記 | 不需重建：只用來讓下次換配方 |
| 偏好 | UserDefaults `AppLanguage`／`AppleLanguages`／`LyricsNotificationsEnabled`／`RaisedLayerStyle` | 4 鍵 | — | 使用者設定 | 數秒 |
| 遷移旗標 | UserDefaults `LegacyConfigMigratedVersion` | 1 鍵 | — | 1.x 遷移 | 每台本機各自判斷 |
| Genius token | Keychain | — | — | 使用者輸入 | 重貼一次 |
| 封面快取 | `~/Library/Caches/…/Artwork` | 約 200 檔 | 內容雜湊 | Music | 自動重抓 |

  另有遙控中繼相關的 UserDefaults 鍵，與本計劃無關，不列入、不動。曲庫檢查的報表只在記憶體（`Services/LibraryGate/` 無寫檔）。
- **MB 存檔讀取不逐筆驗證**：`ArtistStyleStore.load()` 只做檔案層防線與 JSON 解碼，不驗 mbid、曲風、票數、寫法（`ArtistStyleStore.swift:50-56`；Codex R1-13 指出，已核）。
- **播放端讀的是 AppModel 的記憶體快照，不是每次讀檔**：`lyricsFX.artistDecision` 讀 `decisionBook`、`artistConsensus` 讀 `consensusTable`、MB 讀 `artistBook`（`AppModel.swift:205-216`）；`LibraryCheckViewModel` 也持有決定。「沒有歌詞」標記則每次換歌、寫入前重讀設定（`LyricsFlowModel.reloadMarks`，`:455`）。
- **寫入路徑分散**：`TimingResolver.save`、`ArtistStyleSync.persist`、`AppModel.saveDecisions`、`AppModel.receiveConsensus`、`ConfigStore.markNoLyrics／clearNoLyricsMark`；store 本身沒有變更回呼。
- **MB 背景查詢在 `start()` 等 3.5 s 後啟動**（`AppModel.swift:89`），佇列與 book 都在 `ArtistStyleSync` actor 內。
- **時間軸查找在打外部來源前會先取得 artist／title／duration**（`TimingResolver.validQuery`，`:455-469`），比對外部候選用 `TrackMatcher`（正規化歌手與曲名、曲長差 ≤ 3 s、版本標記相容，I-49）。
- **「沒有歌詞」標記的清除只發生在寫入非空歌詞時**（`LyricsFlowModel.applyWrittenLyrics`，`:462-468`，AC5）。
- **四個存檔的共同防線**：schemaVersion、不讀符號連結與非一般檔、上限 1 MiB、壞檔視為空或 corrupt、看不懂的新版本不覆寫、`.atomic` 寫（`TimingStore.swift:130-160`、`ArtistDecisionStore.swift:59-85` 等）。遺留 P2「四個存檔防線抽共用」（⑧ 增補計劃 §遺留 P2 ①）尚未做。
- **時間軸合併規則已預留多機語義**：`TimingRecord.merged` 註解寫「多台 Mac 經同步資料夾」；規則＝詞不同取**新來的**、同詞 found 勝 notFound、同類 `fetchedAt` 新者勝（`TimingStore.swift:46-62`）。`TimingLookupPolicy.futureTolerance` 已處理他機時鐘超前（`:76-86`）。
- **使用者決定的「清除」＝刪鍵**（`ArtistDecisionBook.clearing`，`ArtistDecisionBook.swift:56-59`），沒有墓碑。
- **MB 背景查詢只排「存檔裡還沒有」的歌手**（`ArtistStyleSync.prepareQueue`），閃屏後才啟動（`AppModel.start` → `startArtistStyles`）。
- **時間軸存檔不記曲長**：`StoredFile` 欄位＝schemaVersion、persistentID、lyricsHash、source、lines、fetchedAt、alignerRevision（`TimingStore.swift:205-215`）。`alignerRevision` 是可選欄位、加入時未升版——同一手法可加可選欄位。
- **lyricsHash**＝正規化換行後歌詞的 SHA-256 前 16 bytes（`LyricsFingerprint.swift:14-17`）。

## 3. 未知（TBD；T0 實測或問使用者，不寫成結論）
- **U1 persistentID 跨 Mac 是否相同**。Apple 文件：曲庫重建時可能改變。推測：用遷移助理搬的 Mac 相同（整個曲庫資料庫被複製）；全新安裝後經「同步資料庫」下載的 Mac 不同（各自的資料庫各自編號）。需要第二台 Mac 才能驗。
- **U2 iCloud Drive 授權框**：非沙盒、ad-hoc 簽名的 app 第一次讀寫 iCloud Drive 時會不會彈 TCC 框；每次重建（新 CDHash）會不會重問。
- **U3 未下載的他機檔**：「最佳化 Mac 儲存空間」開啟時，他機檔可能只有雲端（dataless）。讀取是阻塞下載、回錯、還是讀到空。推測：macOS 14 起 iCloud Drive 走 File Provider，讀 dataless 檔會觸發下載並阻塞到下載完成。
- **U4 歌詞欄位是否跨 Mac 同步**（經同步資料庫）。決定兩台的 lyricsHash 會不會一致。設計對兩種情況都安全：不一致時時間軸視為不適用、重新查。
- **U5 使用者的實際情境**：兩台並用，還是將來換一台；換機時用遷移助理還是全新安裝。推測：遷移助理會連 `~/Library/Application Support`、UserDefaults、曲庫一起搬，那條路徑**現在就不會白費**，本功能的價值在「全新安裝」與「兩台並用」。

## 4. 逐項：同步與否
原則：**使用者親手的決定、和花網路或時間才得到的結果要同步；本機能自動重建、或只屬於這台機器的不同步；憑證不經 iCloud Drive。**

| 資料 | 同步？ | 理由 |
|---|---|---|
| 時間軸存檔 | **同步** | 使用者 2026-10-19 的原始需求；每首重查要打 1–5 個外部來源；notFound 也同步，避免另一台 7 天內重複白查 |
| MB 歌手存檔 | **同步** | ⑥b 既定「一起搬」；重查 22 分鐘且違反「每位只查一次」；鍵是歌手名，跨 Mac 不受 persistentID 影響 |
| 使用者決定 | **同步** | 無法重建，是本計劃最值錢的資料；鍵是寫法家族，跨 Mac 可用 |
| 同歌手共識 | **不同步** | 它是「這台曲庫最近一次完整掃描」算出的衍生表；指紋只涵蓋列目錄與可讀性政策、不涵蓋曲庫（`ArtistConsensusStore.fingerprint`），別台的表套到這台會違反 I-69 的既有語義（Codex R1-12，採納）。代價：新 Mac 重掃前，共識影響的 186 首（I-69）照逐曲判定；開曲庫檢查重掃一次（約 1 分鐘）即恢復。設定頁與 README 寫明 |
| 「這首沒有歌詞」標記 | **同步（同 persistentID 才套用）** | 使用者親手的決定、無法重建（Codex R1-11，採納；原稿以「0 筆」為理由不成立）。U1 若 persistentID 不同就套不上，跨 ID 不做 |
| 配方歷史 | **不同步** | 只為「下次播放換配方」；新 Mac 第一次播放可能與上次同配方，代價一次 |
| 偏好（語言、通知、升起層） | **不同步** | 屬每台機器；語言覆寫要重啟才生效（E-09），跨機改動反而突兀；重設數秒 |
| 遷移旗標 | **不同步** | 每台本機各自判斷 legacy 檔 |
| Genius token | **不同步** | 產品／風險取捨：憑證不得寫進 iCloud Drive 的一般檔；iCloud 鑰匙圈同步（`kSecAttrSynchronizable`）在 ad-hoc 簽名下能否用未經實測（TBD），本期不試；新 Mac 重貼一次（Codex R1-19，採納改寫） |
| 封面快取 | **不同步** | 快取，自動重抓 |

## 5. 目標與非目標
目標：
1. 開啟同步後，這台 Mac 的時間軸、MB 歌手、使用者決定、「沒有歌詞」標記會出現在 iCloud Drive 這台專屬的資料夾；另一台開啟後能讀進來用，**不必重啟**即在下次播放（時間軸：下次查找）生效。
2. 正常雙機情境下不產生跨寫入者的衝突副本；MB 歌手與使用者決定兩台最終收斂成同一份；清除的決定不會被另一台復活。時間軸是「對本機目前歌詞有效」的快取，不要求兩台逐位相同（§6.5）。
3. 讀不懂、壞掉、版本較新、還沒下載的他機檔，一律跳過，不影響本機。
4. persistentID 不同的兩台（U1），時間軸仍能以歌詞雜湊找回（唯一命中才用）。

非目標：手動匯出／匯入檔案（延後，不是被遷移助理涵蓋；本機 Application Support 檔案本身可當備份，附錄 A-3）；同步共識表；同步 §4 列「不同步」的項目；app 專屬 iCloud 容器／CloudKit；即時（秒級）同步；跨 Apple ID；Python 1.x；YSE。

## 6. 設計

### 6.1 位置與布局
```
iCloud Drive/Azathoth's Whisper/Sync/<writerID>/
    timings.json   artists.json   decisions.json   nolyrics.json
```
- 本機 Application Support（與 UserDefaults 的標記）**仍是正本**；iCloud 是副本與交換區。
- **每台 Mac 只寫自己的 `<writerID>/`**，其他資料夾只讀不寫——正常雙機情境下不會有跨寫入者的衝突副本。同一台機器同時跑兩份 app 時，匯出前取本機 Application Support 下 `sync.lock` 的 `flock`，取不到就本輪不匯出（R1-17）。
- 版面嚴格驗證（R1-18）：根目錄、`Sync/`、各 writer 資料夾必須是真目錄、不是符號連結；writer 資料夾名必須是 16 位小寫 hex，否則略過；只認上面四個確切檔名，其他（含 iCloud 衝突副本「timings 2.json」）一律略過並在狀態列計數。

### 6.2 writerID
- `writerID`＝SHA-256（`IOPlatformUUID` ‖ 固定字串 `"com.ibridgezhao.azathothswhisper.sync.v1"`）的前 8 bytes 小寫十六進位（16 字）。**不存檔**：同一台機器重裝仍同一個；遷移助理複製出來的機器硬體不同，自然得到新 ID。
- 硬體 UUID 讀取包在 `HardwareIdentity` protocol 後（測試替身固定值）；讀不到＝不能同步，設定頁顯示錯誤類型，不退回隨機 ID。
- 外殼的 writerID 只用來驗「檔在誰的資料夾」；**衝突決勝用每筆記錄自己的 `origin`**（R1-1）。
- 日誌不記 writerID、不記硬體 UUID。

### 6.3 檔案格式（四檔共通外殼）
`{ "schemaVersion": 1, "kind": "timings|artists|decisions|nolyrics", "writerID": "…", "appVersion": "3.x.y", "writtenAt": ISO8601, "payloadSHA256": "…", "payload": … }`
- payload＝該類記錄的陣列，compact JSON；每筆記錄帶 `origin`（第一次產生這個版本的 writerID，轉手不改）。
- **既有資料補 origin**（整體確認 1）：時間軸與 MB 的現有記錄沒有 origin（`TimingStore.swift:32`、`ArtistStyleBook.swift:17`）。兩個存檔加可選欄位 `origin`（同 `alignerRevision` 手法，不升版）；**開啟同步時**（與之後每次啟動時，若同步為開），對缺 origin 的記錄以本機 writerID 補上並寫回本機正本，完成後才匯出。補寫冪等：中斷後下次啟動只補仍缺的。兩台各自有同鍵舊資料時，各蓋自己的 ID，之後照一般合併規則。決定與標記的遷移已在 §6.5 定義（revision 0、origin 本機）。
- **正規形式**（R2-B6）：記錄依主鍵（時間軸 persistentID、MB 與決定的 key、標記 pid）排序；記錄內所有語義無序的陣列都排序：spellings、matchedReleaseGroups 字典序，MB `genres` 依 (name, count) 排序且同名重複＝該筆不合格（R3-5）；時間軸錨點 `lines` 有語義順序，**不排序**；`JSONEncoder` 用 `.sortedKeys`、不加 pretty；日期 ISO 8601 秒精度 UTC。`payloadSHA256`＝這段 payload 的 UTF-8 bytes 的 SHA-256。本機正本以同一函式產生 payload 再比雜湊。
- 讀他機檔的防線＝本機存檔防線（一般檔、非符號連結、大小上限、壞檔跳過、`schemaVersion` 較新＝跳過整檔）＋外殼 writerID＝所在資料夾名、kind＝檔名、`payloadSHA256` 相符。
- **逐筆驗證器**（R1-13，採納）：新寫共用的 record-level sanitizer，本機載入與遠端匯入都走它——時間軸：persistentID 16 hex、lyricsHash 32 hex、錨點合法（既有 `areWellFormedAnchors`）、`fetchedAt` 不晚於現在＋1 天；MB 依狀態分開（R2-B5）：verified＝mbid 為 UUID、reason 為空、曲風名非空且 ≤ 100 字、票數為非負 Int；unresolved＝mbid 為 nil、曲風與 release-group 為空、reason 為已知值（collision 的 mbid 依現有程式可保留，照現有 `adding` 語義放行）；共同：key 非空、寫法 1–50 個；決定：狀態合法、列 id 長度上限、revision 為非負 Int、寫法 1–50 個；標記：pid 16 hex、revision 為非負 Int。不合格的單筆丟掉、其餘照收，日誌記筆數。
- 大小上限：timings 32 MiB（曲庫 12,271 首全有記錄時估約 12 MB：2026-11-03 實測本機 169 檔平均 1,842 bytes（pretty）、compact 980 bytes；加上 §6.5 的比對欄位約再多 100 bytes）；其他三檔 1 MiB。
- 寫入：先寫同資料夾 `.<name>.tmp`（點開頭），再改名替換。

### 6.4 匯出（本機 → 自己的資料夾）
- 每條寫入路徑在**寫入成功後**呼叫 coordinator 的 `markDirty(kind)`（R1-14，採納）：`TimingResolver.save`／`adopt`、`ArtistStyleSync.persist`、`AppModel.saveDecisions`、標記的 `markNoLyrics`／`clearNoLyricsMark`（經 `LyricsFlowModel` 回呼）。每條路徑各一個測試。
- 依類別分開節奏（R1-15，採納）：

| 類別 | 最後一次變更後 | 最長延遲 |
|---|---|---|
| 使用者決定、沒有歌詞標記 | 10 s | 10 s |
| MB 歌手 | 60 s | 10 分 |
| 時間軸 | 5 分 | 30 分 |

- 啟動時：對每一類比對「本機正本內容雜湊」與「自己資料夾那份的 `payloadSHA256`」，不同就匯出——涵蓋強制結束遺失的 dirty（不需持久化 dirty 旗標）。結束 app 時對 dirty 類別盡力匯出一次（限 2 s，不擋退出）。
- 開啟同步當下：四類各匯出一次。
- 失敗（未登入、磁碟滿、授權拒絕）：保留 dirty、下次觸發重試；設定頁顯示錯誤類型。

### 6.5 匯入（他機資料夾 → 本機正本）
- 觸發：啟動時（MB 先、其餘後）；開啟同步當下；之後每 10 分鐘比對各他機檔修改時間，有變才讀。
- **讀他機檔前先看下載狀態**（R1-16，採納）：`ubiquitousItemDownloadingStatus` 不是 current → 呼叫 `startDownloadingUbiquitousItem`、本輪跳過、下輪再試；只讀已下載的檔。每次匯入帶 generation，逾時（30 s）或晚到的結果一律丟棄、不採用。T0 先驗這兩個 API 對一般 iCloud Drive 路徑、非沙盒 app 是否有效；無效則退回「背景讀＋逾時＋generation 守衛」。
- 匯入只寫本機正本、從不寫他機檔；匯入造成的本機變更照樣 `markDirty`（聯集轉出；重複匯入結果不變＝冪等）。
- **單一採用入口**（R1-3，採納）：所有匯入經 `AppModel.adoptRemote(_:)`，同一次主執行緒更新：store、`decisionBook`、`LibraryCheckViewModel` 的決定（新增 `decisionsReplaced(_:)`）；MB 經 `ArtistStyleSync` 的 `publish` 換 `artistBook`；時間軸由 resolver 每次讀 store、標記由 `reloadMarks` 每次重讀，不需額外通知。效果：**不重啟**，下次播放（時間軸：下次查找）生效。
- 各類合併規則（純函式，寫在各自型別，真值表測試）：
  - **MB 歌手**（R1-2、R1-4、R2-B2、R2-B3，採納）：唯一擁有者是 `ArtistStyleSync` actor。**actor 改在 `AppModel` 組裝時建立**；book 的載入是 actor 內一次性的 `ensureLoaded()`（背景、不在主執行緒、不在組裝時同步讀檔；R3-3），`adopt` 與 `run` 都先 await 它，`run()` 不再自己 `store.load()`；3.5 s 延遲只延後 `run()`。**查詢途中被匯入＝丟棄查回的結果**（R3-1；實作時改採 Codex R3-1 原建議「只容許白查、不容許白查後寫回」，比「當候選合併」少一條未蓋章記錄的決勝分支；附錄 C-1）：actor 在 `await` 期間可重入，寫回前若該鍵已有記錄就不寫。新增 `adopt(remote:)`：合併進 book、把已有記錄的歌手從佇列移除、`persist`、`publish`；每位歌手查詢前再看一次 book。不需要啟動屏障，最多白查「匯入當下正在查」的那一位。合併：先取兩邊寫法聯集，**照現有撞鍵規則重判**（聯集內不是同一寫法家族＝collision，`ArtistStyleBook.swift:84-86` 的語義），collision 一旦成立就保留；不撞鍵時 verified 勝 unresolved、同狀態取 `origin` 字典序較小者的 mbid／曲風。兩台因此收斂成同一份，且遠端 verified 不會蓋掉本機的撞鍵防線。
  - **共用 LWW 暫存器**（R2-B4 後抽出，決定與標記共用一個定義）：`SyncRegister<Value>`＝{value 或 cleared、revision、origin}；本機改動＝該鍵已見過的最大 revision＋1；合併＝revision 大者勝、同 revision 取 origin 字典序較小者。
  - **使用者決定**（R1-1、R1-9、R1-10，採納）：資料模型改為 `active(choice)`／`cleared` 兩態，每筆帶 `revision`（每鍵 Lamport 計數：本機改動＝該鍵已見過的最大 revision＋1）、`decidedAt`（只供顯示）、`origin`、`spellings`（下決定時畫面上的歌手寫法）。決勝：revision 大者勝，同 revision 取 origin 字典序較小者——可交換、可結合、冪等，三台以上轉手也收斂。`decision(forArtist:)` 對 `cleared` 回 nil；`clearing` 改為寫墓碑。驗證依 choice 分開：`.style` 要列 id 在本版目錄內、且 `spellings` 至少一個 `needsArtistGenres` 為真；`.keepFallback`、`cleared` 不驗樂團表。本版不認得的列 id（他機較新版本）＝這一筆本輪不採用、保留本機，升級後下次匯入自然採用。存檔 schemaVersion 1→2（v1 照讀並補 revision 0、origin 本機；v2 被舊版讀到＝看不懂、不覆寫，既有防線）。
  - **沒有歌詞標記**（R2-B4，採納；原「聯集不做墓碑」撤回）：每個 pid 一個 `SyncRegister<Bool>`；清除（AC5 寫入非空歌詞時）寫成 cleared＋新 revision。本機正本改為 UserDefaults 新鍵 `NoLyricsMarkLedger`（含 revision、origin），首次啟動自舊鍵 `NoLyricsMarkedTrackIDs` 單向遷移（revision 0、origin 本機）；之後 `noLyricsMarks` 只從 ledger 推出，舊鍵凍結不再讀寫。**不支援降版後的標記改動回流**（R3-2；常規判斷：只有使用者本人使用、降版罕見；退回舊版會看到遷移當下的標記，ACCEPTANCE 註明）。理由：Music 裡直接把詞改空、或他機舊標記晚到，無墓碑會讓已清除的標記復活。`lyricsChanged` 不更新標記狀態是既有行為（`LyricsFlowModel.swift:110-112`），不在本計劃。
  - **時間軸，同 persistentID**（R1-5，採納修改；R1-1 對時間軸部分駁回，理由見附錄 B）：不用時鐘決勝。本機沒有→採用；兩邊都有且同 lyricsHash：found 勝 notFound，兩邊都是 found 時 `alignerRevision` 大者勝，其餘保留本機；不同 lyricsHash→保留本機。`fetchedAt` 晚於現在＋1 天的遠端記錄由驗證器丟掉。用到時仍再驗 lyricsHash＝目前歌詞、錨點套得上（既有 `storedOutcome`）。
  - **時間軸，跨 persistentID**（R1-6〔R2 Codex 以新證據勝〕、R1-7、R1-8、R2-B1）：記錄新增可選欄位 `match`＝{artist, title, duration}（取自寫入當下的 `TimingQuery`）與不可變的 `sourceRef`＝`<origin>:<原始 persistentID>`（第一次產生時定、轉存不改）；**生命週期**（整體確認 2）：只有「本機由外部來源新查到」的 found 才產生新的 `sourceRef`（本機 writerID＋本機 pid）與新 origin；跨 ID 採用、匯入、同 ID 合併一律原樣保留；同一 `sourceRef` 出現多個版本（原機後來重查）時，依全序選代表：alignerRevision 大者 → 錨點正規化 JSON 的 SHA-256 字典序小者（R3-4），測試排列不變性；兩者只存在本機正本與自己的 iCloud 檔，不進日誌。查找流程：`storedOutcome` 找不到可用記錄 → `validQuery` 取得本機 artist／title／duration → **在打外部來源之前**查遠端索引（鍵＝lyricsHash，涵蓋所有遠端 found，不論本機有沒有同 pid 檔；**先依 `sourceRef` 去重**，同一份結果被別台轉存只算一個）→ 候選要同時滿足：lyricsHash 相同、歌手與曲名的 `TrackMatcher.exactKey` **完全相同**（不用 `matches` 的一字容差，也不忽略 remaster 標記——R2 證據：`TrackMatcher.swift` 編輯距離上限 1、remaster 不算版本）、曲長差 ≤ 0.5 s（同一檔案在兩台應相同）、錨點套得上、**候選的 `alignerRevision` ≥ 現行 `LRCAligner.revision`**（/thecure：`storedLinesFit` 只驗結構、不重跑文字對齊，舊版對齊器收下、現行規則會拒絕的結果不得跨 ID 帶進來；與同 ID 的 `TimingLookupPolicy` 一致）；`sourceRef` 去重並選出代表後，**恰一個**、或多個但完整有序錨點序列 `[(index, start)]` 逐筆相同（視為一致）時，才以本機 pid 存成本機記錄（`origin`、`sourceRef` 保留）；錨點不同＝不採用。沒有 `match` 的舊記錄不參與跨 ID。notFound 不跨 ID 套用。
- 共識不匯入（§4）。

### 6.6 設定與畫面
- 選單 `Settings ▸ iCloud Sync Settings...`（寫死英文，A-07），Settings modal 新增 `.sync` 群組（modal 標題英文覆寫，D-03）。
- 內容（三語 String Catalog）：開關（**預設關**）；說明同步哪四類、不同步什麼（token、偏好、共識——「新 Mac 請在曲庫檢查重掃一次」），並寫明「**每台 Mac 都要各自打開**」（R1-21，採納其一部分）；狀態列（最後匯出、最後匯入、其他 Mac 各自最後更新時間、略過的檔數、最近錯誤類型）；按鈕「重設這台 Mac 的雲端副本」＝刪除自己的 `<writerID>/` **並關閉同步**（需確認；R1-18）。
- 關閉＝停止讀寫，不刪任何檔；本機正本不受影響。不做「同步關閉時偵測別台資料而提示」：那需要在使用者關閉時讀 iCloud，違反關閉語義（R1-21 後半，駁回，續辯）。
- 開關存 UserDefaults `ICloudSyncEnabled`（每台各自）。
- 已退役的 Mac：資料夾照讀（裡面的結果仍有效），狀態列列出其最後更新時間；不自動清除。

### 6.7 架構
- 新 `Services/Sync/`：`SyncLocation`（根目錄注入）、`HardwareIdentity`（protocol＋IOKit 實作＋替身）、`SyncEnvelope`（外殼編解碼、版面與逐筆驗證）、`SyncRecordSanitizer`、`CloudSyncCoordinator`（actor：dirty、各類節奏、啟動比對、匯入排程與 generation；時鐘照 `PollClock` 模式注入）、`RemoteTimingIndex`（跨 ID 索引）。
- 合併純函式：`TimingRecord.importMerged`、`ArtistStyleBook.merging(remote:)`（含撞鍵重判）、`SyncRegister.merged`（決定與標記共用）。
- Store 窄介面：`TimingStore.allRecords()`／`adopt(_:)`（走 `importMerged`，不走 `save`）；`ArtistStyleSync.adopt(remote:)`（actor 提早建立、`run()` 不再載入）；`ArtistDecisionStore` v2；標記改 ledger（`ConfigStore+NoLyricsMarks`）。
- `AppModel`：建 coordinator、接 `markDirty` 與 `adoptRemote`、把遠端索引交給 `TimingResolver`（回呼，不持有 coordinator）。DEBUG 自動化測試不碰真 iCloud（`isAutomatedTest` 時 coordinator 為 nil）。
- 日誌：category `cloud-sync`；只記筆數、類別、錯誤類型；不記歌手名、曲名、persistentID、writerID。

## 7. 任務清單（每項帶 DoD）
**投入順序**（整體確認 3）：T0 → T1 → **T3a 資料模型**（origin、sourceRef、match、`SyncRegister`、決定兩態 v2、標記 ledger、補 origin 與兩種遷移）→ T2（外殼與驗證器，驗的是 T3a 的新模型）→ T3b 合併純函式＋T4 Store 窄介面 → T5（採用端以 protocol／回呼注入，不依賴 `AppModel`）→ T6、T7 → T8 → T9 → T10。下表 T3 拆成 T3a／T3b 兩段照此執行。

並行候選：**無**。全部任務共用同一 xcodebuild 與 app 測試宿主，且 repo 在 iCloud 同步的 `~/Documents`，多 worktree 同時建置風險高、收益小（同 A1 計劃 :130 的判斷）→ 主執行緒依序。

| # | 任務 | DoD |
|---|---|---|
| T0 | 探針（DEBUG-only，量 U2／U3；做不出可重現的 dataless 檔就記「未驗證」並直接採退路，不把探針做不出來誤判為 API 不可用）：Debug 版在 iCloud Drive 建資料夾、寫讀一檔；`brctl evict` 一檔後查 `ubiquitousItemDownloadingStatus`、呼叫 `startDownloadingUbiquitousItem`、計時 | 記錄是否彈授權框、重建後是否重問、下載狀態 API 是否有效、dataless 讀取行為；結果寫進 §2 並據此定 §6.5 讀法；探針只在 `#if DEBUG` |
| T1 | `HardwareIdentity`＋writerID | 同輸入同 ID、不同硬體不同 ID、讀不到回錯；IOKit 實作回 16 字 hex（測試只驗格式） |
| T2 | `SyncEnvelope`＋版面驗證＋`SyncRecordSanitizer`（含本機 MB 載入改走 sanitizer） | 往返；writerID／kind／雜湊不符、符號連結、非 16 hex 資料夾、衝突副本、超大、壞 JSON、較新版本各自跳過；逐筆不合格只丟該筆 |
| T3 | `SyncRegister`＋合併純函式（時間軸、MB 含撞鍵重判）＋決定兩態 v2＋標記 ledger 與遷移 | 真值表全綠；三 writer 任意順序匯入結果相同（性質測試：隨機 50 組排列）；遠端 verified 不蓋本機 collision；v1 決定檔照讀、v2 不被 v1 覆寫；標記舊鍵遷移後集合不變、舊鍵鏡像與 ledger 一致；曲庫檢查清除、AC5 清除後畫面行為不變 |
| T4 | Store 窄介面；`TimingStore.adopt`；`match` 可選欄位寫入路徑 | 既有 Store 測試全綠；新介面往返；舊檔無 `match` 照讀 |
| T5 | `CloudSyncCoordinator`：`markDirty`、各類節奏與最長延遲、啟動雜湊比對、退出盡力、匯入排程、下載狀態、generation、`flock` | 注入時鐘：連續變更只匯出一次且不超過最長延遲；強制結束後下次啟動補匯出；未下載檔本輪跳過；晚到結果丟棄；匯入冪等；不寫他機資料夾；兩實例只一個匯出 |
| T6 | 每條寫入路徑接 `markDirty` | 五條路徑各一測試：寫成功→dirty；寫失敗→不 dirty |
| T7 | `ArtistStyleSync` 提早建立＋`ensureLoaded`＋`adopt(remote:)`＋`AppModel.adoptRemote` | 組裝時不讀檔；`run()` 前後匯入都有效、`run()` 不覆寫已採用的記錄；查詢途中被匯入的歌手，查回結果經合併、不倒退（以可控延遲的替身 client 重現重入）；匯入的歌手從佇列移除、不再查；不重啟即下次播放生效（決定、MB）；`LibraryCheckViewModel` 拿到新決定；既有 `ArtistStyleSyncTests`、`AppModelArtistStylesTests` 全綠 |
| T8 | `RemoteTimingIndex` 接進 `TimingResolver` | 跨 ID 採用後再由外部重查到新結果＝新 sourceRef，不被舊 sourceRef 去重；`sourceRef` 去重後唯一、或多候選錨點完整相同才採用；多候選錨點不同不用；`alignerRevision` 低於現行不用；三台轉存不造成多候選；歌手或曲名差一字不用、remaster 字樣不同不用、曲長差 > 0.5 s 不用、錨點套不上不用、notFound 不跨 ID、本機有同 pid 舊 hash 時仍可命中；採用後存成本機 pid、不打外部來源 |
| T9 | Settings `.sync` 群組＋選單＋三語 | VM 測試（開關、狀態、重設＝刪自己資料夾並關閉）；三語齊；UITest（假根目錄、假硬體 ID，`#if DEBUG` 注入） |
| T10 | ACCEPTANCE I-72、README 三語、`xcodegen generate` | 條目含依據、驗證方式、狀態；README 說明同步內容、「每台都要打開」「token 要重貼」「共識要重掃」 |

## 8. 驗收標準
1. 開啟同步後，`Azathoth's Whisper/Sync/<writerID>/` 有四個檔，筆數等於本機正本（腳本可判）。
2. 放入他機 fixture（本機沒有的歌手、時間軸、決定、標記）→ **不重啟**：該歌手不進 MB 佇列（日誌 `queued` 減少）、決定在下次播放生效、時間軸可用、標記在 Cover Flow 出現；本機正本含這些記錄。
3. 他機檔壞掉、版本較新、writerID／kind／雜湊不符、超大、未下載、讀取逾時、iCloud 衝突副本：各自跳過，本機正本逐位不變（測試比對前後雜湊）。
4. 清除一個決定後，另一台 revision 較小的同鍵決定不會復活；revision 較大者覆蓋本機。「沒有歌詞」標記同理（含 Music 裡直接把詞改空後的舊標記）；遠端 verified 不會蓋掉本機的撞鍵記錄。
5. 三個 writer 在同一根目錄以任意順序交錯匯出匯入：MB 與決定三方收斂成同一份（逐位相同）；時間軸三方都不出現「套到不同詞」的記錄。
6. 升版：既有 169 份時間軸、418 位 MB 記錄開啟同步後全部帶 origin、筆數不變；中斷後再啟動只補缺的。
7. 錯時鐘：遠端 `fetchedAt` 超前 2 天的時間軸記錄被丟棄；決定與 MB 決勝不受時鐘影響。
8. 時間軸持續寫入時，匯出不晚於最長延遲 30 分；強制結束後下次啟動補匯出。
9. 關閉同步：之後不再讀寫 iCloud 資料夾（替身檔案系統計數 0 次）；本機功能照常。
10. 全量單元測試無新增紅；`coverage_gate.sh`（傳 xcresult）Services+Infra ≥ 80 %、`Services/Sync/` 新檔 ≥ 80 %；`no_playback_gate.sh` 綠。
11. 使用者在場（一次一項）：①開啟同步、確認 iCloud Drive 出現資料夾與四檔、授權框行為；②（若有第二台 Mac）第二台開啟後播放一首第一台查過時間軸的歌，不出現 `~`。沒有第二台＝②以 fixture 代替，ACCEPTANCE 標明未經真雙機驗證。

## 9. 測試策略
- TDD：T1–T8 每項先寫測試跑紅、再實作；紅燈摘要記本計劃附錄。
- 單元：合併真值表（時間軸：本機有／無 × 同詞／異詞 × found／notFound × alignerRevision；MB：verified／unresolved × origin 先後；決定：revision 大小 × active／cleared × origin 決勝 × 不認得的列；標記：聯集）；三 writer 隨機排列的收斂性質測試；錯時鐘；外殼、版面、逐筆驗證；writerID；coordinator 時序（注入時鐘：節奏、最長延遲、啟動比對、generation）；跨 ID 索引（唯一、多筆、配對、版本標記、錨點、notFound、同 pid 舊 hash）。
- 整合：`AppModel` 以暫存根目錄＋三個假 writer 跑匯入匯出；MB 背景查詢與匯入同時進行（匯入早於、晚於 3.5 s 兩種）；不重啟生效；每條寫入路徑觸發匯出。
- E2E：Settings 同步群組 UITest（假根目錄、假硬體 ID，經 `UITestSupport` 注入，`#if DEBUG`）。
- 不碰真 iCloud：自動化測試一律注入暫存資料夾；真 iCloud 只在 T0 與使用者在場。

## 10. 影響面
新 `Services/Sync/*`、`Features/Settings/*`（群組）、`App/AzathothsWhisperApp.swift`（選單）、`App/AppModel.swift`（接線、`adoptRemote`）、`Features/LibraryCheck/LibraryCheckViewModel.swift`（`decisionsReplaced`）、`Features/LyricsFlow/LyricsFlowModel.swift`（標記變更回呼）、`App/AppDelegate.swift`（退出時匯出）、`Services/Lyrics/TimingStore.swift`（adopt、allRecords、`match`）、`Services/Lyrics/Timing/TimingResolver*.swift`（索引）、`Services/ArtistStyles/*Store.swift`／`*Book.swift`／`ArtistStyleSync.swift`（adopt、合併、決定兩態 v2、MB 載入走 sanitizer）、`Resources/Localizable.xcstrings`、`Tests/*`、`UITests/*`、`ACCEPTANCE.md`、README 三語、`project.yml` 不變（IOKit 為系統框架，若需顯式連結則加 `IOKit.framework`）、`xcodegen generate`。
不動：Music 讀寫與選擇器、播放判定順序、元件目錄、偏好與 token 的存放、共識存檔、Python 1.x、YSE。

## 11. 風險與回退
- **R1 授權框卡住 UI 測試**（U2）：自動化測試不碰真 iCloud；真機授權框由使用者點（同 Keychain 慣例）。
- **R2 dataless 讀取阻塞**（U3）：背景＋逾時；不在主執行緒讀他機檔。
- **R3 匯入錯套時間軸**：用到時重驗 lyricsHash 與錨點；跨 ID 要 lyricsHash、歌手、曲名完全相同、曲長差 ≤ 0.5 s、去重後唯一。殘餘風險：詞、歌手、曲名、曲長都相同的不同錄音（推測極少）；錯套時與外部來源錯套同一種後果，使用者可看出歌詞時機不對（⑩ 的範圍）。
- **R6 MB 背景查詢與匯入搶寫**：唯一擁有者是 `ArtistStyleSync` actor（§6.5）。
- **R4 版本不一的兩台**：較新格式整檔跳過；舊版讀到 v2 決定檔不覆寫（既有防線）。
- **R5 iCloud 根目錄被使用者改名或刪除**：下次匯出重建自己的資料夾；本機正本不受影響。
- **回退**：關開關即停；本機正本格式只多了時間軸可選欄位 `match`／`sourceRef`（舊版忽略）、決定檔 v2、標記 ledger；回到舊版 app 時決定檔看不懂＝不覆寫、照樣不讀（舊版看不到決定），標記停在遷移當下——ACCEPTANCE 註明。

## 12. 待拍板（一次一件，Codex 收斂後才問）
1. **跨 persistentID 的時間軸自動套用**——/thecure（2026-11-03）收斂為單一方案：**自動套用**，條件＝歌詞雜湊、歌手、曲名完全相同、曲長差 ≤ 0.5 s、錨點套得上、對齊器版本不低於現行、去重後唯一或錨點完全一致（§6.5）。依據：本曲庫實測 12,301 首中 688 首（296 組）有「歌手曲名相同、長度差 ≤ 0.5 s」的另一首，相鄰差多數 ≤ 0.05 s；外部來源鏈的配對條件更寬（容一字、≤ 3 s），同樣分不出同名同長的錄音，所以自動套用不新增錯誤類別；「先上網查」讓每首都重查、違背「不白費」；「不沿用」讓全新安裝的 Mac 時間軸同步失效。——待使用者確認執行。

## 附錄 A：與 2026-10-19 草稿的差異
1. 範圍由「只有時間軸」擴到四類（使用者 2026-11-03 開工口令）。
2. writerID 由「存 UUID＋比對硬體雜湊」改為「由硬體 UUID 直接導出、不存檔」。
3. 手動匯出／匯入**延後**（R1-20 後改寫）：不是「被遷移助理涵蓋」（那只是 U5 推測），而是本期範圍取捨；本機 Application Support 檔可直接當備份。
4. 匯出頻率由「最多一天一次」改為依類別的節奏與最長延遲（§6.4；R1-15）。
5. 拿掉「首次提示可開」，改為設定頁寫明「每台都要各自打開」（R1-21 部分採納）。
6. 時間軸跨 ID 匹配改為 lyricsHash＋歌手曲名完全相同＋曲長 ≤ 0.5 s＋`sourceRef` 去重（R1-6、R2）。
7. 範圍調整：「沒有歌詞」標記加入同步並帶墓碑（R1-11、R2-B4）；共識不同步（R1-12）。
8. writerID 只驗資料夾歸屬，決勝改用每筆 `origin`；決定改兩態＋Lamport revision（R1-1、R1-9）。

## 附錄 B：Codex 評審與辯論記錄

### R1（2026-11-03，`codex exec` gpt-5.6-terra medium；22 條：阻斷 4、高 9、中 8、低 1）

| # | 嚴重度 | 要點 | 處置 |
|---|---|---|---|
| 1 | 阻斷 | 外殼 writerID 是最後匯出者，當決勝鍵會因轉手順序不同而不收斂 | **採納**（決定、MB）：每筆 `origin`＋決定 Lamport revision。**時間軸部分駁回**：時間軸是對本機目前歌詞有效的快取，改為不用時鐘、不需跨機全序的規則（同詞 found＞notFound、alignerRevision 大者，其餘保留本機）；不要求兩台逐位相同，§5-2 改寫。待 R2 反駁 |
| 2 | 阻斷 | MB「本機有→保留本機」不收斂；`ArtistStyleSync` 會把舊 book 寫回 | **採納修改**：全序決勝（verified＞unresolved、origin 小者）；匯入經 `ArtistStyleSync.adopt`，同一 actor 擁有 book 與佇列 |
| 3 | 阻斷 | 播放端讀記憶體快照，只寫 store 要重啟才生效 | **採納**（已核 `AppModel.swift:205-216`）：`AppModel.adoptRemote` 單一入口 |
| 4 | 阻斷 | 啟動匯入與 3.5 s 後的 MB 查詢沒有先後保證 | **採納修改**：不用屏障；`ArtistStyleSync` 擁有佇列，匯入即移除、查詢前再看 book |
| 5 | 高 | 異詞取 `fetchedAt` 較新＝信任 wall clock | **採納修改**：時間軸改不用時鐘的規則；驗證器丟掉超前 1 天以上的記錄 |
| 6 | 高 | 同詞＋曲長不足以辨識錄音版本；建議 v1 不做跨 ID 或只作候選 | **部分採納**：加 `TrackMatcher`（歌手、曲名、版本標記、曲長，與外部來源同一規則）。**「不可自動寫回」駁回**：外部來源以同一配對規則、且不要求同詞就自動套用（I-49），遠端記錄另要求同詞，條件更嚴；若 U1 證實 persistentID 不同，不做跨 ID 會讓全新安裝的 Mac 時間軸同步失效、違背使用者原始需求。待 R2 反駁 |
| 7 | 高 | 索引不應以「本機有沒有同 pid 檔」決定 | **採納** |
| 8 | 高 | duration 何時取得未定義 | **採納**：`match` 在寫入時存；跨 ID 查詢放在 `validQuery` 之後、外部來源之前 |
| 9 | 高 | 墓碑資料模型未定義 | **採納**：`active`／`cleared` 兩態＋revision |
| 10 | 高 | `.keepFallback` 可用於樂團表；正規化鍵無法還原歌手名 | **採納**（已核 `ArtistDecisionBook.swift:44-47`）：依 choice 分開驗證；記錄帶 `spellings` |
| 11 | 高 | 「沒有歌詞」標記是使用者決定，以 0 筆為由不同步不成立 | **採納**：同 pid 同步、聯集（不做墓碑的理由見 §6.5） |
| 12 | 高 | 共識是本機曲庫的衍生表，指紋不含曲庫 | **採納**（已核 `ArtistConsensusStore.fingerprint`）：不同步 |
| 13 | 高 | `ArtistStyleStore.load` 沒有逐筆驗證，「照本機驗證」不實 | **採納**（已核 `:50-56`）：新增共用 sanitizer，本機載入也走 |
| 14 | 高 | store 沒有變更回呼 | **採納**：每條寫入路徑呼叫 `markDirty`，各一測試 |
| 15 | 中 | 一律 5 分鐘 debounce 不經濟、會被連續寫入無限延後 | **採納修改**：依類別節奏＋最長延遲；啟動比對雜湊補匯出。**「時間軸改每 pid 一檔」不採**：他機要讀上萬個小檔、每個都可能未下載，整份單檔較好處理 |
| 16 | 中 | Task 逾時取消不了阻塞讀取 | **採納**：先查下載狀態＋generation 守衛；T0 驗 API |
| 17 | 中 | 「不會產生衝突副本」承諾過度 | **採納**：改寫承諾；`flock`；衝突副本略過並計數 |
| 18 | 中 | 子目錄與檔名驗證不足；刪除後會被重建 | **採納**：嚴格版面驗證；「重設」＝刪除並關閉。退役 Mac 不自動清（資料仍有效），狀態列列出 |
| 19 | 中 | iCloud 鑰匙圈需要 entitlement 寫成事實 | **採納**：改為產品／風險取捨、TBD |
| 20 | 中 | 「遷移助理已涵蓋」只是推測 | **採納**：改為延後 |
| 21 | 中 | 預設關、沒有首次提示，第二台可能不知道要開 | **部分採納**：設定頁與 README 寫明每台都要開。**非侵入提示駁回**：要在同步關閉時讀 iCloud，違反關閉語義。待 R2 反駁 |
| 22 | 低 | 驗收缺競態、不重啟生效、錯時鐘、三台轉手、最長延遲、遠端共識 | **採納**：§8-2、5、6、7；共識已不同步 |

### R2（2026-11-03，同模型；回應駁回 4 條＋新意見 6 條）

| # | 嚴重度 | 要點 | 處置 |
|---|---|---|---|
| R1-1 | — | 時間軸不要求跨機收斂 | Codex **接受**我方理由，結案 |
| R1-6 | 高 | `TrackMatcher` 容許一字差、忽略 remaster，不足以證明同一錄音 | **Codex 勝**（新證據已核：`TrackMatcher.swift` `EditDistance … limit: 1`、`isVersionFragment` 排除 remaster）：改為歌手曲名 `exactKey` 完全相同、曲長 ≤ 0.5 s；仍自動採用（Codex 給的「至少極嚴格」選項） |
| R1-15 後半 | — | 時間軸不改每 pid 一檔 | Codex **接受**，結案 |
| R1-21 後半 | — | 不做同步關閉時的提示 | Codex **接受**，結案 |
| B1 | 高 | 跨 ID 採用後轉存，第三台看到兩個候選，「恰一個」失效 | **採納**：`sourceRef` 不可變、索引先去重 |
| B2 | 高 | 遠端 verified 整筆蓋掉本機 collision | **採納**（已核 `ArtistStyleBook.swift:84-86`、`adding`）：寫法聯集後重判撞鍵，collision 保留 |
| B3 | 高 | `ArtistStyleSync` 3.5 s 後才建立，啟動匯入沒有採用者 | **採納**（已核 `AppModel.start`、`ArtistStyleSync.run:42`）：actor 提早建立、`run()` 不再載入 |
| B4 | 高 | 標記無墓碑，Music 直接改空或舊標記晚到會復活 | **採納**：與決定共用 `SyncRegister`，標記改 ledger＋一次遷移；我方 v0.2「聯集不做墓碑」撤回 |
| B5 | 中 | unresolved 的 mbid 合法為 nil，「mbid 為 UUID」會丟掉全部 unresolved | **採納**：依狀態分開驗證 |
| B6 | 中 | 雜湊比對未定義正規形式 | **採納**：§6.3 正規形式 |

### R3（2026-11-03，同模型；確認 R2 處置＋v0.3 新問題）

| # | 嚴重度 | 要點 | 處置 |
|---|---|---|---|
| B2、B5 | — | 撞鍵重判、依狀態驗證 | Codex 確認**已解決** |
| 1（B3） | 高 | actor 可重入，正在查的歌手查回來會覆寫剛匯入的記錄 | **採納**（已核 `ArtistStyleSync.swift:86-97`）：寫回走同一合併函式 |
| 2（B4） | 高 | 舊鍵單向鏡像下，降版後的改動不回流、清除會復活 | **採納其第一個選項**：單向遷移、舊鍵凍結、不支援降版回流並明示。Codex 列為需拍板（C2），本方判為常規判斷（單一使用者、降版罕見），在回退一節明示，不另問 |
| 3 | 中 | actor 提早建立若同步讀檔，I/O 前移到主執行緒 | **採納**：`ensureLoaded()` 背景一次性載入 |
| 4（B1） | 高 | 同一 `sourceRef` 多版本時代表未定義 | **採納**：全序選代表＋排列不變性測試 |
| 5（B6） | 中 | 正規形式漏了 `genres` | **採納**：列明所有陣列欄位的排序；錨點不排序 |
| R1-6 | 高 | 條件收緊後仍不能證明同一錄音 | **證據定不了的價值判斷**（Codex C1，本方同意）→ §12-1 交使用者 |

收斂判定：3 輪後除 §12-1 外無未結條目，不再開第 4 輪。

### §12-1 /thecure（2026-11-03，使用者要求先辯再拍板）

| 論點 | 提出方 | 結果 | 證據 |
|---|---|---|---|
| 自動套用不新增錯誤類別（配對條件嚴格包含於外部鏈） | 我 | **Codex 勝（部分）**：身分門檻成立，但遠端結果可能出自舊版對齊器、現行規則會拒絕，外部鏈此時不會套用 | `TimingStore.swift:80`（found 版本落後要重查）、`LRCAligner.swift:29-32`（現行門檻）、`:84-87`（`storedLinesFit` 只驗結構）、`LRCAligner.revision = 2` → 加 `alignerRevision ≥ 現行` |
| 「先上網查」不降低錯套、違背不白費 | 我 | **我勝（收窄）**：Codex 同意結論，指出 B 能排除過期結果——已由上一條的版本防線涵蓋 | — |
| 多候選錨點完全相同視為一致 | 我 | **我勝，附 Codex 三個限制**：比完整有序序列、先 sourceRef 去重再比、不取代其他條件 | — |
| 選 A | 我 | Codex 明言**正確**（A＋版本防線＋錨點一致規則） | 曲庫實測 688／12,301 |

Codex 最擔心：錯誤一旦被跨機採用就會被再匯出擴散；`sourceRef` 只能防止被算成多份，防不了同一份錯時間軸被多台採用。對策：`sourceRef` 不可變、跨 ID 採用保留原始來源、拒絕低版本對齊結果（皆已入 §6.5）。

### 整體確認（thecure 第 7 步，2026-11-03）

| 項 | 要點 | 處置 |
|---|---|---|
| 1 | 既有時間軸與 MB 記錄沒有 origin，遷移未定義 | **採納**（已核 `TimingStore.swift:32`、`ArtistStyleBook.swift:17`）：§6.3 補 origin 規則、§8-6 驗收 |
| 2 | 跨 ID 採用後再重查時 sourceRef 的生命週期未定義 | **採納**：只有本機外部新查到的 found 產生新 sourceRef；T8 驗收 |
| 3 | T2 驗證器依賴 T3 的模型，順序反了 | **採納**：T3 拆 T3a（模型、遷移）先於 T2 |
| 最易失敗 | T0 探針（File Provider、TCC 不易重現） | **採納**：T0 DoD 加「做不出就記未驗證、直接採退路」 |
| §4、§5、§8、§11 一致性 | — | Codex：無 |

## 附錄 C：實作紀錄（2026-11-03，分支 wip/lyrics-icloud-sync）

| commit | 內容 | 測試 |
|---|---|---|
| 163fae9 | T3a-1：`SyncRegister`、決定兩態 v2、標記 ledger | 9 suite 76 條綠（測試與實作同批，未單獨跑紅） |
| 04eeb6b | T3a-2：MB origin＋逐筆驗證＋撞鍵重判合併；時間軸 origin／sourceRef／match、`importMerged`、`adopt`、`stampAll` | **紅**：112 個編譯錯誤（欄位與方法未定義）→ 綠：12 suite 154 條 |
| 7c77382 | T1＋T2：writerID、外殼與正規形式雜湊、資料夾版面與下載狀態 | 5 suite 56 條綠（同批寫） |
| 9d6fd2d | T5：`CloudSyncCoordinator`、`CloudSyncChannel`、`SyncLock` | 11 條綠；連跑 10 次 10/10 |
| 777c10b | T7＋T8：`ArtistStyleSync` 一次性載入／stamp／adopt／查詢途中丟棄；`RemoteTimingIndex` 接進查找 | 時間軸 101 條、MB 44 條綠 |
| 381e1a2 | AppModel 接線、單一採用入口、各寫入路徑 markDirty、重設 | `AppModelCloudSyncTests` 7 條（連跑 5 次）、app-model 61 條綠 |
| 6cbaf9c | T9：Settings 群組＋選單＋三語 15 鍵；退出前限時匯出；UI 測試 | 52 條綠；UITest 未跑（需在場） |

與定稿的差異（皆不動驗收標準）：
1. **C-1** MB 查詢途中被匯入：丟棄查回結果（見 §6.5），不當候選合併。
2. **C-2** T0 探針併入使用者在場 #1：讀取路徑已同時實作「先查下載狀態＋要求下載」與「背景讀＋30 s 逾時＋晚到丟棄」兩條，T0 結果不改程式形狀；在場時觀察授權框與下載狀態即可。
3. **C-3** 新增防線：iCloud Drive 本身（根目錄的上層）不存在時不自建資料夾（`SyncFolder.Failure.iCloudDriveUnavailable`），避免在未登入 iCloud 的機器上造出假的 `Mobile Documents`。
4. **C-4** 讀不到硬體身分時，開關不存成「開」，設定頁顯示無法開啟。
5. **C-5** 舊測試的假 mbid（`"mb-1"`）改為 UUID 格式：新驗證器要求 verified 必須是 UUID（真 client 本來就只收 UUID），斷言未動。`NoLyricsMarksTests.markingTwiceKeepsASingleEntry` 原本讀舊鍵，改讀 ledger（舊鍵依定稿凍結）。
6. **C-6** UI 測試組裝（DEBUG）可經 `AZW_UITEST_SYNC_ROOT` 指定臨時同步根目錄與假硬體身分；未設＝不同步。
7. **C-7** 已知取捨（定稿 §6.5「聯集轉出」的推論）：同 persistentID 的匯入會把他機的每一筆時間軸都存成本機檔；若 U1 證實兩台 persistentID 不同，這些檔在本機永遠用不到（只佔空間，數 MB 級），並隨匯出回到 iCloud。待 U1 有結論再評估是否只收本機曲庫有的 pid。
