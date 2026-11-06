# 歌詞 ⑨ v2：iCloud 作為唯一存放位置（**已作廢**）

**作廢（使用者 2026-11-06「改回 v1」）**：iCloud 改回第二存放地（本機為正本、iCloud 為副本），即 `docs/plans/2026-11-03-lyrics-icloud-sync.md` v1.0（程式已在本分支 381e1a2～36bc7b2）。本檔只留作紀錄：S0 實測（§2，含上傳順序不保證、未上傳前回 4355）對 v1 仍有參考價值；S0 在場 ③②、S1 起全部不做；v2 未改任何程式碼。

原狀態：**v1.0 定稿**（使用者 2026-11-03「下個session開工吧」；Codex 2 輪收斂＋整體確認 2 條已入、§1-3 使用者已拍板）。分支 `wip/lyrics-icloud-sync`（接 36bc7b2）。
前身：`docs/plans/2026-11-03-lyrics-icloud-sync.md` v1.0（本機為正本、iCloud 為副本；已實作、在場 #1 通過、未發布）。合併規則、逐筆驗證、writerID、跨 persistentID 規則沿用 v1.0。

## 0. 複述
- 使用者 2026-11-03：「icloud就是替代原本的保存的 所以應該是遷移過來 就沒有以前的保存了。其他用戶也是只有iCloud一個保存位置才對」。
- 目標＝選用 iCloud 的 Mac，這些資料只存在 iCloud Drive；既有本機資料安全搬過去後刪除。
- **如實說明（Codex R2-E）**：v2 的工作量與風險明顯大於 v1。v1 的 iCloud 是可丟的副本，出錯＝同步落後；v2 的 iCloud 是唯一一份，遷移或可用性判斷錯一次＝唯一資料被刪或被空資料蓋掉。所以本稿把「不丟資料」的條件列為硬條件。
- 不做＝改 Music 資料；sandbox；app 專屬 iCloud 容器（ad-hoc 拿不到）；從 iCloud 搬回舊版格式的工具。

## 1. 使用者決定（既定，不重議）
1. 2026-11-03：iCloud 取代原本的存放位置，搬過去、不留舊的。
2. v1.0 的同步範圍、§12-1 跨 persistentID 自動套用沿用。
3. 2026-11-03：**沒用 iCloud 的人，第一次啟動讓使用者選**——從沒用過 iCloud 的 Mac 可選「只存這台 Mac」（那就是它唯一的存放位置，日後可再搬上 iCloud）；**用過 iCloud 的 Mac 連不上時只暫存在記憶體、不寫本機**，連上再存。

## 2. 事實（已核）
- 各存檔可注入資料夾，組裝點只在 `AppModel.live()`（`AppModel.swift:381、398-405、436`）；標記目前在 UserDefaults（ledger 格式）。
- 在場 #1：非沙盒 ad-hoc app 讀寫 iCloud Drive 一般資料夾**沒有授權框**。
- 現有本機資料：時間軸 169 檔、MB 420 位、共識 1 檔、決定 0、標記 0；iCloud 裡只有這台一個 writer 的 v1 信封。
- v1 從未發布：只在本機分支，沒有其他 Mac 或使用者跑過（Codex R2-B 接受 → 不需新舊版雙讀相容）。
- `FileManager.ubiquityIdentityToken` 在無 iCloud entitlement 的 app 不能當 iCloud Drive 可用性的權威訊號（Apple 文件與 QA1935，Codex R2-D）；`com~apple~CloudDocs` 存在也不代表可用（登出後可能殘留）。
- `startDownloadingUbiquitousItem` 只代表開始下載；完成要看下載狀態鍵（Apple 文件）。`ubiquitousItemIsUploaded` 只描述單一檔；不得在 `NSFileCoordinator` 的讀取 accessor 內輪詢（Apple 文件）。
- 現有 `UbiquitousDownloadProbe` 取不到狀態時回「已下載」（`SyncFolder.swift:16`）——v2 必須改成三態。
- **S0 實測（2026-11-03 23:3x，macOS 27.0.1，探針 `~/Developer/azw-s0-probe/probe.swift`，swiftc ad-hoc CLI；探針資料夾 `iCloud Drive/azw-s0-probe/`，S0 結束後刪）**：
  - 環境：本機 `brctl` 無 `evict` 子命令、`fileproviderctl` 亦無；移出本機改用 `FileManager.evictUbiquitousItem(at:)`（非沙盒、無 entitlement 可用，單檔／目錄皆約 0.1–0.6 s 回成功）。
  - ④ 規模：64 片×約 50 KB＋4 檔，協調寫入共 160 ms；列舉 `timings/` 0.8–1.0 ms；68 次 `resourceValues` 每次 ≤ 9.4 ms。
  - 上傳：68 檔 23.9 s 內全部 `isUploaded=true`；**manifest 最後寫卻 5.3 s 先上傳**——上傳順序不保證，讀者必須核 digest（§4.3 已涵蓋，證實必要）。**未上傳前每檔持續回 `uploadingError` 4355「無法存取 iCloud 帳號」，最後全部成功**——§4.5 第 5 步「無上傳錯誤」不能照字面判，4355 要當「仍在等」（待 S5 設計改寫）。
  - 連續改寫 20 個 generation（每 250 ms，含分片）：10.7 s 內全部收斂為已上傳。
  - ① 移出本機：單檔、`timings/`、整個 writer 目錄移出後，列舉仍看得到全部檔名（≤ 1 ms），`resourceValues` 正確回 `NotDownloaded`（≤ 6 ms）——**不會回假資料、查詢不阻塞**。直接讀雲端檔會**同步阻塞到下載完**（單檔 1.2–5.0 s）；協調讀取逐檔讀 68 檔共 **111 s**；先對 68 檔 `startDownloadingUbiquitousItem`（56 ms 返回）再輪詢狀態，**3 s** 全部 `Current`。→ 設計要求：讀取一律背景、先批次要求下載再讀，不逐檔阻塞讀（併入 S3／S4）。
  - 未解：協調讀完後有 5 檔又回 `NotDownloaded`（原因 TBD）。
  - **待使用者在場**：③ 斷網後恢復（記錄腳本 `offline.sh` 已備，靠 Wi-Fi 開關判定；ping 判定在本機網路不可靠已棄用）；② 關閉 iCloud Drive／登出——注意本機 Desktop & Documents 在 iCloud（repo 也在內），做之前要先和使用者確認影響面。
  - 小結（至今）：沒有發現一般 iCloud Drive 資料夾撐不住當唯一存放的跡象。

## 3. 未知 → S0 實機 gate（使用者在場，實作前先做）
用實際 ad-hoc 建置量：①自己的檔、父目錄、整個 writer 目錄被 `brctl evict` 移出後，`resourceValues`、列舉、讀取的行為與耗時；②iCloud Drive 關閉、登出（保留／不保留副本）、重新登入；③寫後斷網，`ubiquitousItemIsUploaded` 何時變 true；④64 個分片檔＋manifest 的首次列舉與讀取耗時。結果寫進 §2；任何一項顯示「會阻塞主執行緒或回假資料」就回頭改設計。

## 4. 設計

### 4.1 存放模式（每台 Mac 各自，存在本機 UserDefaults；這是設定，不是資料）
| 模式 | 何時 | 存放 |
|---|---|---|
| 未決定 | v2 第一次啟動 | 啟動時問一次：「存 iCloud（建議）／只存這台 Mac」。iCloud Drive 目錄不存在時，iCloud 選項灰掉並說明 |
| iCloud | 使用者選了 | 唯一存放＝`iCloud Drive/Azathoth's Whisper/Sync/<writerID>/`；本機不落任何這五類資料 |
| 只存這台 Mac | 使用者選了 | 唯一存放＝`Application Support/…`（現狀）；設定頁可「搬到 iCloud」（走 §4.5） |
- **不自動在兩種模式間切換**（Codex R2-D）：iCloud 模式的 Mac 永遠不會因連不上而改寫本機。

### 4.2 iCloud 模式的可用狀態（三態，Codex #2、#4）
- **已驗證**：root manifest 已下載、decode、驗證通過，且曾成功寫入並確認上傳 → 可讀可寫。
- **載入中／未知**：manifest 或需要的分片未下載、下載狀態讀不到、讀取逾時、權限錯誤 → **fail closed**：只在記憶體運作（歌詞特效照常、時間軸可估算或用外部來源但不落盤、MB 背景查詢暫停、曲庫檢查的「下決定」按鈕停用並說明），背景持續要求下載與重試。
- **不可用**：iCloud Drive 目錄不在 → 同上 fail closed，設定頁顯示「iCloud Drive 不可用，資料暫不保存」。
- **遷移準備中**（整體確認 1）：剛選 iCloud、還沒有 manifest 時的唯一可寫狀態——**只允許遷移器**依 §4.3 協議建立目錄與寫入、提交第一份 manifest；一般 store 不得初始化或寫回。遷移完成（§4.5 第 5 步通過）才進「已驗證」。
- 從不把「看不到」當「沒有」：只有「這台從沒建立過 root manifest、且使用者在 §4.1 剛選了 iCloud」時，由遷移器（本機沒資料時寫空內容）建立第一份（Codex #11）。

### 4.3 iCloud 內版面與提交協議（Codex #7、R2-A #3/#7/#11）
```
Sync/<writerID>/
  manifest.json                  root manifest：schema、writerID、generation、各檔 SHA-256、完成狀態
  timings/shard-00.json … shard-3f.json   時間軸固定 64 片（persistentID 的 SHA-256 首位元組 & 0x3f），每片＝該片所有記錄
  artists.json  decisions.json  marks.json
```
- 寫入：改動的檔以 `NSFileCoordinator` 協調寫入（原子替換、沿用 v1 的 O_EXCL／O_NOFOLLOW 防線）→ 最後寫 manifest（generation＋1、所有檔的 digest）。**manifest 是提交點**。
- 讀取（自己的與他機的）：先讀 manifest；所有列出的檔都下載完成、digest 相符才算一份完整 generation；否則＝載入中。
- 單機多程序：保留 `SyncLock`（process lock）；讀寫另經 `NSFileCoordinator`（兩者不互相取代，Codex #8）。協調 accessor 內不等待上傳或下載。
- 時間軸 store：iCloud 模式改用分片 store（記憶體持有已載入的片；改一首＝改所在片＋manifest）。本機模式沿用現在的每首一檔。
- 共識（ArtistConsensus）：改為可丟快取，放 `~/Library/Caches`，不遷移、不同步；刪掉後由下次完整掃描重建（Codex #14）。

### 4.4 Store 結果語義（Codex #5）
每類 store 讀取回 `absent`／`available`／`unavailableTransient`／`unavailablePermanent`／`corrupt`／`newerSchema`。只有 `absent`（且符合 §4.2 的建立條件）可初始化新檔；其餘一律不寫回（決定、標記尤其如此）。

### 4.5 遷移（本機 → iCloud，單向、一次、可重跑；Codex #3、#6、R2-B）
1. 寫遷移 journal（本機，只記階段與預期 digest，不含資料）。
2. 讀本機五類（時間軸、MB、決定、標記 ledger、v1 信封內容），以 v1.0 合併規則算出「預期內容」，算語義 digest（完整鍵集、值、版本、墓碑）。
3. 寫入 iCloud（§4.3 協議），提交 manifest。
4. 重新開檔讀回、decode、逐鍵比對預期內容；全部相符才進下一步。
5. 等所有檔＋manifest 的 `ubiquitousItemIsUploaded == true` 且無上傳錯誤（不在協調 accessor 內等；有上限，逾時＝本次不刪、下次啟動繼續）。
6. 才刪本機來源：時間軸檔、`artists.json`、`decisions.json`、UserDefaults 的標記 ledger 與舊鍵（最後刪）、自己的 v1 信封（只刪認得的 v1 格式）。
7. journal 記完成。任何一步失敗：本機來源保留，下次啟動從 journal 階段繼續。

### 4.6 他機資料（沿用 v1.0 合併與驗證）
- 啟動時與 app 存活期間最遲每 10 分鐘：讀他機 manifest；generation 變了才讀變動的片／檔（digest 比對）；未下載的要求下載、本輪略過。播放路徑絕不列舉目錄（Codex #10）。
- 合併結果寫進自己的資料夾（§4.3）。跨 persistentID 索引沿用。
- 他機上限 16、只算有 manifest 的、版面防線沿用 v1.0 附錄 D。

### 4.7 設定頁
狀態頁：存放模式、iCloud 狀態（已驗證／載入中／不可用）、遷移狀態、其他 Mac 台數與最後更新、最近錯誤；「只存這台 Mac」模式多一個「搬到 iCloud」。拿掉 v1 的開關與重設。

### 4.8 回退
完成遷移後 v1／v3.0.0 讀不到資料（只看本機）——ACCEPTANCE 註明不可回退；manifest 帶 schema version，舊版不會把它當空資料寫回（舊版根本不讀 iCloud）。Git 回退只回退程式，不回退資料。

## 5. 任務（每項帶 DoD；並行候選：無）
| # | 任務 | DoD |
|---|---|---|
| S0 | 實機 gate（§3，使用者在場）；上傳確認另測三種情境：斷網後恢復、連續改寫 generation、manifest 最後上傳（整體確認：最容易失敗的一步） | 結果寫進 §2；必要時改設計 |
| S1 | 存放模式＋第一次啟動選擇＋原始可用性與下載探測三態 | 單元：各模式、unknown 不讀不寫；UI：首次選擇 |
| S2 | root manifest＋提交協議＋`NSFileCoordinator`＋process lock；補完「已驗證」與「遷移準備中」判定（整體確認 2：依賴 manifest，故排在 S1 之後） | 半寫入（片寫了、manifest 沒寫）讀者視為舊 generation；digest 不符＝載入中；遷移準備中只有遷移器可寫 |
| S3 | Store 結果五態；iCloud 模式的分片時間軸 store；MB／決定／標記改用 iCloud 檔；標記搬出 UserDefaults；共識移到 Caches | 既有 store 測試全綠；`unavailable`／`corrupt` 不寫回 |
| S4 | fail closed 行為：記憶體運作、MB 背景查詢暫停、下決定停用、下載完成後同一執行期重新載入 | VM／整合測試 |
| S5 | 遷移器（journal、語義 digest、讀回比對、上傳確認、最後刪本機） | 每階段中斷後重跑冪等；任何不符不刪；只刪認得的 v1 信封 |
| S6 | 他機讀取改讀 manifest＋分片 | v1.0 合併／驗證／惡意檔測試沿用 |
| S7 | 拿掉 v1 匯出、開關、重設；設定頁改狀態頁＋三語 | 編譯無殘留；VM 與 UI 測試 |
| S8 | ACCEPTANCE I-72 改寫（不可回退）、README 三語、v1.0 計劃標註被取代 | — |

## 6. 驗收
1. 你的 Mac（選 iCloud）：遷移完成後本機 Application Support 不再有時間軸、MB、決定；UserDefaults 無標記鍵；iCloud 自己的資料夾語義內容＝遷移前（時間軸 169、MB 420），且全部已上傳。
2. 遷移任一步中斷或驗證不符：本機來源完整保留；重跑冪等。
3. iCloud 載入中／不可用：不寫本機、不寫回、不初始化空資料；播放照常；下載完成後不重啟即恢復。
4. 選「只存這台 Mac」：行為同現在；之後「搬到 iCloud」走同一遷移。
5. 他機資料：啟動時與最遲 10 分鐘內生效；惡意檔防線沿用 v1.0。
6. 全量單元無新增紅、coverage ≥ 80 %、no_playback_gate 綠。
7. 使用者在場：S0 四項；你的機器實際遷移一次並核對。

## 7. 風險
- **R-1 唯一資料遺失**：§4.5 的語義驗證＋上傳確認＋最後才刪；§4.2 fail closed。
- **R-2 iCloud 延遲**：fail closed＋背景下載；播放不阻塞。
- **R-3 規模**：明顯大於 v1；S0 若顯示一般 iCloud Drive 資料夾無法可靠當主存放，回報使用者再決定。

## 附錄 A：Codex 評審與辯論
### R1（15 條）與 R2（逐條回應）
| # | 要點 | 結果 |
|---|---|---|
| 1 | 不可用時改寫本機＝第二正本 | 價值判斷 → **使用者拍板**（§1-3）：首次選擇；用過 iCloud 的 Mac 只 fail closed |
| 2 | 目錄存在≠可用 | 採納：三態 |
| 3 | 讀回≠已上傳 | 採納＋R2：manifest 為提交點、上傳確認後才刪 |
| 4 | 取不到下載狀態不得當已下載 | 採納：三態探測 |
| 5 | Store 語義不適合主存放 | 採納＋R2：拆暫時／永久不可用 |
| 6 | 筆數不能驗證 ledger | 採納：語義 digest、UserDefaults 鍵最後刪 |
| 7 | 上萬小檔不適合 File Provider | 採納：64 片＋manifest |
| 8 | 少了併發協調 | 採納：process lock＋NSFileCoordinator |
| 9 | v1 混合版本相容 | **我方勝**：v1 未發布、只有一個 writer；只做受控遷移 |
| 10 | 一致性承諾未定義 | 採納：啟動＋最遲 10 分鐘，播放不掃目錄 |
| 11 | 看不到檔就重建空資料 | 採納：root manifest |
| 12 | 限時後空集合會改變行為 | 採納：顯式載入中、暫停改資料的操作 |
| 13 | 回退工具 | **我方勝**：未發布；ACCEPTANCE 註明不可回退 |
| 14 | 共識定位 | 採納：可丟快取，移到 Caches |
| 15 | 未知要轉成 gate | 採納：S0 |
| R2-E | 規模與風險 | 採納：§0 如實說明 |
### 整體確認（2026-11-03）
| 項 | 要點 | 處置 |
|---|---|---|
| 1 | §4.2 fail closed 與 §4.5 遷移入口互卡（沒有 manifest 前無法寫） | 採納：新增「遷移準備中」狀態，只允許遷移器寫 |
| 2 | S1 的「已驗證」依賴 S2 的 manifest | 採納：S1 只做模式與原始探測，「已驗證」移到 S2 |
| 最易失敗 | §4.5 第 5 步上傳確認 | 採納：S0 加三種情境 |
