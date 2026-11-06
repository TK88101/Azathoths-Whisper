# ⑩ 歌詞對不上唱的時機——對齊器漏判修正

狀態：**v1.2（2026-11-06）**：v1.0 經 Codex 四輪定稿、使用者 2026-11-06 拍板開工；實作時修訂 §4.1 tie-break（附錄 D，Codex 快審成立）、效能驗收（附錄 E，Codex 快審兩輪成立）。分支 `wip/lyrics-timing-fix`（自 main dbc48da）。
前案：`2026-10-25-lyrics-timing-accuracy.md`（C-17 結案「停」）。本案不重啟那條 ML 量測路線。

## 0. 複述
使用者覺得「有時間軸的歌」唱詞對不上，舉例 The Beatles〈Here Comes the Sun〉；歪法「各首不一樣」。使用者不知道哪些歌有真時間軸，不應由他逐首檢查。

## 1. 使用者回答（2026-11-06，既定前提）
- Q1 歪法：「說不準／各首不一樣」。
- Q2 例子：〈Here Comes the Sun〉（The Beatles）。
- 「從哪些歌有時間軸裡挑」是我的工作，不是他的。

## 2. 事實（已核，2026-11-06）
1. 〈Here Comes the Sun〉Abbey Road 版（pid `11BB5BF2B53D303A`）的時間軸存檔是 **notFound**（`fetchedAt 2026-11-05T12:48:29Z`、`alignerRevision 2`、lines 空）；所以播放時顯示的是**估算時間**（`LyricsTimelineEstimator`，按字數均分，角落 `~`）。1967-1970 版（`CAF7E93743321B8F`）Music 沒有歌詞。
2. LRCLIB `/api/get` 對這首有 syncedLyrics（id 237876、186.0 s；Music 185.56 s）。
3. notFound 只在「每個來源都正常回應、沒有一筆候選對齊通過」時寫入（`TimingResolver.lookup` 末段）；有失敗則是 `.unavailable`、不寫。notFound 7 天後才重查（`TimingLookupPolicy.retryInterval`），found 才看 `alignerRevision`。
4. 存檔分佈（195 筆）：lrclib 82、youtubeMusic 49、netease 29、deezer 2、**notFound 33**。Music 帶歌詞 5834 首；其餘沒查過的歌播放時也是估算（查找時機推測＝播過才查，未核）。
5. **離線重跑**（工具 `~/Developer/azw-timing-probe/tools/nf/`，以 app 原始碼原檔編譯 `LRCAligner`／`TrackMatcher`／`CandidateRanking`／`ProviderOutcome`；只拿 LRCLIB 候選；輸出只有數字）：33 首 notFound 中 28 首 LRCLIB 有通過 `TrackMatcher` 的候選（時長差 ≤ 1.2 s），**28 首全被對齊器拒**。

   | 對齊法 | 通過（≥0.7／≥0.6） / 28 |
   |---|---|
   | 現行貪婪前向（app） | 0 |
   | 單調 DP（同轉移：1 Music 行↔1–3 LRC 行） | 5 |
   | DP ＋「2–3 個 Music 行↔1 LRC 行」 | **21** |
   | 同上、相似度門檻降到 0.7 | 22 |

   〈Here Comes the Sun〉：Music 40 行、LRC 27 行；貪婪 0.17／0.26 → DP 0.40／0.59 → DP＋反向串接 **0.90／0.93**。
   其餘 7 首：4 首各法皆 0（推測別語言或別版本歌詞，應拒）；1 首 Music 只有 1 行、1 首 996 行（歌詞欄異常）；1 首最好 0.49／0.64。
   註：上表的 LRC 覆蓋率以「用掉的 LRC 行數」計。改用 §4.2 的保守定義（對上群組數／LRC 非空行，對非反向路徑與現行逐值相同）後為 **19／28**，〈Here Comes the Sun〉0.90／0.93 仍通過。
   **定位**：這是探針 DP（tie-break 未定、未回傳路徑）的**探索訊號**，不是 DoD；DoD 以 T4 用 production 原檔重跑的數字為準（Codex R1-6）。
6. 根因（推理，依 5 的數字）：①Music 側（Genius 等）常把 LRC 的一行拆成 2–3 行，現行只支援反方向（Music 一行↔多個 LRC 行）；②貪婪前向在某行錯配到後面時，游標跳過一大段，後續全滅（DP 單獨就救回 5 首）。兩者在同一首內會疊加。
7. 這也可能影響已 found 的 162 首：現行貪婪錯錨時，若仍過門檻，顯示時間就會局部錯開——「各首不一樣」與此相容（**推測**，§5 T5 量）。

## 3. 目標與非目標
**目標**
- G1 對齊器改為單調最優對齊，並支援「多個 Music 行↔一個 LRC 行」；28 首 notFound 中 ≥ 18 首通過（探針訊號 19）。
- G2 錯配把關（不是證明）：交叉對照組、同團近鄰組、合成 hard negatives 全數拒絕；新接受的每首另有獨立證據（候選已過 `TrackMatcher`：歌手／曲名相符、時長差 ≤ 3 s）。
- G3 **只遷移 notFound**：`LRCAligner.revision = 3`；`alignerRevision < 3` 的 notFound 重查一次。**既有 found 不重查、不覆寫**（Codex R1-2）：found 重查門檻與跨 ID 採用門檻固定在 rev 2（新常數 `LRCAligner.foundCompatibleRevision = 2`）。
- G4 使用者不必自己找歌：真機驗證只由我挑、一次一首。
- 既有 found 是否也受貪婪錯錨影響：本案只做 **shadow evaluation（T5，不寫入）**，結果另案決定。

**非目標**：不碰 YSE；不做 ML／音訊對齊；不改估算器；不改 `~` 標記；不調相似度門檻（0.7 只多 1 首，不值得換錯配風險）；不加新來源；日文不另處理；Python 舊版不動。

## 4. 設計
### 4.1 對齊（`LRCAligner.matchedIndices` → DP）
- 狀態 `(i, j)`＝Music 第 i 行、LRC 第 j 行起；轉移：跳過 Music 行、跳過 LRC 行、`1 Music ↔ s LRC`（s＝1…`maxMergedCues`，不跨空 cue；沿用）、**新增** `t Music ↔ 1 LRC`（t＝2…`maxMergedMusicLines = 3`，Music 行串接後比相似度）。
- 分兩趟（v1.1 修訂，實作時發現，見附錄 D）：①由尾往前算 `score(i, j)`＝從 (i, j) 起的最佳 **(對上的 Music 行數, 群組數)**，字典序比大小（第二鍵只在對上行數相同時起作用：偏好不用反向群組的路徑，也就是覆蓋率較高者；它不偏好串接——正向串接與單行都是 1 群組）；
  ②由 (i, j)＝(0, 0) 重建路徑：找**最早的 cue k ≥ j**，使 Music 行 i 在 k 有一個轉移的值等於 `score(i, j)`，同一 k 依序 `單行 → 串接 s=2 → s=3 → 反向 t=2 → t=3` 取第一個；找不到就跳過 Music 行 i（停在 j）。
  這是路徑的明確字典序（Codex R1-3）：每個 Music 行錨在**最早的最佳可行 cue**、同起點先單行、先正向後反向。同分期望：同分（對上數與群組數都相同）時取最早 cue；對上數相同、群組數不同時取群組多者（v1.0 寫的「在 j 的反向優先於更後 cue 的任何配對」作廢）。刪除 v0.1 的「用掉 LRC 多者」鍵。
  「最早最佳 cue」而非 v1.0 的「先試跳過 cue、再跳過 Music」：後者在 Music 行 i 根本無處可配時，會沿 cue 一路跳到某處才跳過該行，使下一行從較後的 cue 起找，違反不變式 ⓑ。
  不變式（R3-1 修正；v2 的 `matchedIndices` 原樣複製到測試 target 當 oracle `LRCAlignerV2Oracle`，固定種子 ≥ 500 組自編隨機輸入：重複短句、串接、空 cue、可反向的拆行）：
  ⓐ **全部輸入**：新版對上的 Music 行數 ≥ v2；
  ⓑ **新版路徑未用反向、且對上行數＝v2 時**（即貪婪本來就最佳）：anchors、musicRate、lrcCoverage 與 v2 逐值相同——這才是「同分照貪婪」的 tie-break 證據；
  ⓒ 新版對上行數 > v2 時不要求相同（DP 的目的）。另以固定案例鎖住既有 14 條語義。
  衝突案例單測：同覆蓋下單 cue vs 多 cue、早期短路徑 vs 後期長路徑、重複副歌、跳 Music／跳 LRC 平手、正反向同時可行；既有 14 條照舊綠。
- 錨點與資料分離（Codex R1-5）：`Alignment` 增加 `groups`（直接 cue 群組數）；`anchors` 只放 timeline 行起點。`minimumAnchors` 以 `groups` 計（刻意保守：3 行對 1 cue 只算 1 個錨）。
  反向群組的非首行（R2-5 定規格）：權重＝`LRCAligner.normalized(line).count`，群組權重總和為 0 時等分；首行起點＝cue 起點，後續起點按累積權重比例落在 `[cueStart, nextCueStart)`（nextCueStart＝LRC 中下一個非空 cue 的起點；無下一 cue 時用 `LyricsTimelineBuilder.lastLineEnd(start: cueStart, duration:)` 當上界）；起點單調不減。直接寫入 `anchors`（存檔照樣是 `LineStart`，`areWellFormedAnchors` 要求 index 遞增、時間不減，相容）；**不**依賴內插到遠處錨點。單測：曲首、曲尾、下一 cue 很遠、連續反向群組、群組內某行正規化後為空、權重全 0。
- 取消：與現行相同的粒度——每次相似度比較前查 `Task.isCancelled`（現行 `matchedIndices` 即如此）；相似度保留提早結束版本。
- 複雜度（已核）：現行貪婪最壞也是 O(M·L·3) 次相似度（每行無命中時掃到 LRC 尾），DP 為 O(M·L·5)，同階。記憶體：分數表用 `Int32`（2000×2001×4 B ≈ 16 MB；路徑重建只要分數表），或改 rolling 兩列＋重建時就地重算——T2 量後擇一。
  效能驗收（改寫，Codex R1-1、R2-1）：以**真實 DP 實作**跑合成 2000×2000、每行 500 字的最壞輸入，`TimingResolver` 在 20 s 時限到點後 **≤ 1 s 內實際返回**；配置分數表**之前**也查一次取消；記錄峰值記憶體（目標 < 64 MB）；~~正常曲（≤ 100 行）DP 耗時 < 50 ms（Debug）~~ → **v1.2 改為**：Release（`-O`）建置下，T4 真實曲中 Music ≤ 100 行者每首 < 20 ms；Debug 單元測試不設牆鐘門檻（附錄 E）。只以 Big-O 不結案。

### 4.2 指標
- `musicRate`＝被涵蓋的 Music 行數（群組內每行都算）／Music 行數。
- `lrcCoverage` 改為「對上的**群組數**／LRC 非空行數」。對沒有反向群組的路徑，群組數＝對上的 Music 行數，與現行定義**逐值相同**（保留 Codex M1-Q2「串接不放寬覆蓋門檻」）；反向群組只算 1，故恆 ≤ 1。門檻 0.7／0.6／錨點 ≥ 3 不變。
- 主張收窄（Codex R1-4）：新定義**不比現行寬**，但也不證明能擋所有錯錨。補拒絕測試：漏短前奏、兩段副歌部分重疊、LRC 段落順序錯置——每條先在現行對齊器上確認結果，新版不得由拒轉收。不加首尾覆蓋等新門檻（無證據顯示需要）。
- 現有測試 `belowTheAlignmentRateIsRejected`、`aDifferentSongIsRejected` 必須照舊綠。

### 4.3 重查策略與 iCloud（Codex R1-2、R1-8）
- 兩個 revision 概念分開（R2-2、R2-8）：`LRCAligner.revision`＝目前寫入新記錄用的版本；`foundCompatibleRevision`＝「錨點仍可信」的最低版本。所有**比較 found 新舊**的地方改用「有效版本」`effectiveRevision(r) = min(r, foundCompatibleRevision)`：
  - `TimingLookupPolicy`：found 在 `alignerRevision < foundCompatibleRevision` 才重查——本案不觸發任何 found 重查。
  - `TimingRecord.importMerged` 兩邊 found：比有效版本，**相等＝保留本機**（v2 與 v3 都有效＝2，不覆寫本機 found）。
  - `TimingRecord.merged(found, notFound)` 保留錨點時：`alignerRevision = max(existing, min(incoming, foundCompatibleRevision))`——不再把舊錨點標成 rev 3（原意「v1 found 查過一次別再查」仍成立：升到 2；現存 v1 found 13 筆）。
  - 已知限制（R3-2，**現行設計既有、非本案引入**）：「保留舊錨點並把 revision 升到已查版本」是 70936f1（Codex review P2）的既定語意，`alignerRevision` 同時代表「錨點產生版本」與「已重查版本」。未來若出現**破壞性** rev 4 並把 `foundCompatibleRevision` 升到 4，`found v2 + notFound v4` 會被標成 4。本案不拆欄位（需 schema v3 與跨機相容遷移，超出範圍）；**寫入 §8 R5：任何把 `foundCompatibleRevision` 升級的計劃，必須先拆出 `checkedRevision` 欄位**，並在 `foundCompatibleRevision` 宣告處加此註解。
  - `RemoteTimingIndex.pick` 的門檻與 `precedes` 的版本排序都改用有效版本（v2、v3 同級，再比錨點摘要）。
- notFound：`alignerRevision < LRCAligner.revision (3)` → 重查一次；其餘照 7 天。
- `RemoteTimingIndex.pick` 的版本門檻改用 `foundCompatibleRevision`（否則 rev 3 會讓所有現存 rev 2 遠端 found 失去跨 ID 資格）。
- 已核的合併規則（`TimingStore.importMerged`／`merged`）：
  - 本機 notFound v2 ＋ 遠端 notFound v3 → 保留本機（default 分支）→ 本機自己重查一次後寫 v3。
  - 遠端 found v3 ＋ 本機 notFound → 採遠端（既有規則）。本機 found v2 ＋ 遠端 found v3 → **保留本機**（有效版本同為 2）。
  - 舊版 app（revision 2）讀到 v3 遠端記錄：`isAcceptableRemote` 要求 `1...LRCAligner.revision`，v3 被拒——不會誤用（測試已有 `revision + 1` 案例）。
  - 他機舊版持續上傳 v2 notFound：本機已是 v3（found 或 notFound）→ importMerged 保留本機，不循環。
  - 測試：上述四種＋雙機交錯寫入的收斂＋`merged(found v2, notFound v3)` 保留 rev 2 ＋ `precedes` 對 v2／v3 同級，各一條。

### 4.4 ACCEPTANCE
新增 I-73「對齊支援多 Music 行對一 LRC 行、單調最優；revision 3 重查」，驗證方式＝單元測試＋探針重跑數字＋使用者在場 #1。

## 5. 任務清單
| # | 任務 | DoD |
|---|---|---|
| T1 | 紅燈：新增單元測試（Music 拆行、貪婪陷阱、tie-break 衝突案例、coverage ≤ 1 且非反向路徑與現行同值、錯錨拒絕三條、反向群組時間四條、取消） | 新測試跑出紅、舊 14＋6 條綠；紅燈摘要記進 §9 |
| T2 | 實作 DP 對齊＋指標＋`revision = 3`／`foundCompatibleRevision = 2` | T1 全綠；`LRCAlignmentTests`、`TimingAlignmentTests`、`TimingResolverTests`、`RemoteTimingIndexTests`、`TimingRecordSyncTests`、`TimingStoreTests` 綠；效能驗收（§4.1） |
| T3 | 重查策略＋有效版本（`TimingStore.swift` 的 policy／`importMerged`／`merged`，`RemoteTimingIndex` 門檻與 `precedes`）＋ iCloud 收斂測試（§4.3） | 對應單測綠 |
| T4 | 探針重跑：`tools/nf` 改為**直接編譯本分支的 `LRCAligner.swift`**（刪探針自寫 DP）；逐首輸出 accepted、groups、musicRate、lrcCoverage、路徑指紋（群組序列雜湊）。對照組：①交叉 28×27；②同團近鄰（曲庫 found＋notFound 中同歌手的其他曲 LRC，取得到者全配）；③合成 hard negatives（共同副歌、重複短句，自編）。另列「舊拒新收」逐首的 TrackMatcher 證據 | notFound ≥ 18 通過；①②③ 全拒；分母寫明；數字寫進 §9 |
| T5 | Shadow evaluation（不寫入）：82 首 lrclib-found，取同一 LRCLIB 候選，先驗證**舊對齊器能重現存檔錨點**（重現不了的列「來源已變」排除），再比新舊直接錨點；直接錨點與內插行分開報 | 報「錨點有變的曲數」與差值分佈；其他來源 80 首列 TBD；結果只供另案決定，不覆寫 |
| T6 | 全量單元測試＋`coverage_gate.sh`＋`no_playback_gate.sh`＋Scripts 測試 | 全綠（已知基線紅另列） |
| T7 | 使用者在場 #1：〈Here Comes the Sun〉（同時是反向串接＋DP 修復的例子） | 打包一次後請他播一次，一句話回報準不準 |

並行候選：無（T1→T2→T3 同檔鏈；T4/T5 依賴 T2）。

## 6. 測試策略
- 單元：Swift Testing，自編句子（**不用真歌詞**，memory 規則）。合成「Music 拆行」「重複短句陷阱」用自編 LRC。
- 集成：`TimingResolverTests` 既有替身流程走一次 revision 3 重查。
- 探針（曲庫實資料、只出數字）：T4、T5。
- E2E：使用者在場 #1（XCUITest 不涵蓋時間軸顯示準度）。

## 7. 驗收
1. T4：28 首 notFound 通過 ≥ 18；三組對照全拒（只作把關，不寫成「不增加錯配」的證明）。
2. 單元＋集成全綠；全量單元無新增紅。
3. `git diff main --stat` 只含 `LRCAligner.swift`、`TimingStore.swift`（policy）、`RemoteTimingIndex.swift`（門檻常數）、對應測試、ACCEPTANCE、本計劃。
5. 既有 found 存檔在本案前後逐位不變：T3 單測（含同步匯入路徑）＋實機比對 Timings 資料夾中 162 個 found 檔的 SHA-256（裝新版後播放與 iCloud 同步各發生一次之後再比）。
4. 使用者在場 #1 回報〈Here Comes the Sun〉跟得上。

## 8. 風險與回退
- R1 錯配上升：反向串接讓更多組合過相似度 → 交叉對照組把關；若 > 0，加嚴（例如反向群組必須整群相似、或限 t ≤ 2）。
- R2 已 found 的歌顯示改變：本案不重查 found（G3），只在之後**新查**的歌用新對齊器；T5 shadow 結果另案。
- R3 效能：DP 比貪婪慢；最壞情況靠 20 s 時限與取消；T2 效能測試。
- R4 重查量：只有 33 筆 notFound 會重查，且只在播放／背景佇列時發生，沿用 SourceGate 限流。
- R5 revision 雙義（附錄 C #2）：升 `foundCompatibleRevision` 前必須先拆 `checkedRevision`；本案以程式註解＋本條留痕。
- 回退：還原 `LRCAligner.swift` 與 policy；rev 3 存檔被舊版讀到時 found 照讀（舊版看 rev 3 ≥ 2 不重查），notFound 照 7 天——無破壞。

## 9. 實施紀錄
（待填）

## 附錄 A Codex R1（2026-11-06，評 v0.1）與處置
| # | 嚴重度 | 要點 | 處置 |
|---|---|---|---|
| 1 | P0 | 2000×2000 DP 成本、取消粒度、20 s 後是否真返回 | **修改採納**：駁回「不可接受」——現行貪婪最壞同為 O(M·L·3) 次比較（`matchedIndices`），DP 為同階 O(M·L·5)；採納取消粒度（每次比較前）、記憶體方案、效能驗收改為「時限後 ≤ 1 s 實際返回」＋正常曲耗時（§4.1）。稀疏篩邊不做（無證據需要） |
| 2 | P0 | 全部 found 重查會被較新來源覆寫、不可回復；T5 比較對象不可比 | **採納**：只遷移 notFound；found 門檻固定 rev 2；T5 改 shadow、同候選且先驗證舊對齊能重現存檔（§3 G3、§4.3、T5） |
| 3 | P1 | tie-break 不等價於貪婪；「用掉 LRC 多者」偏好串接 | **採納**：改兩趟 DP＋固定轉移順序的字典序；刪該鍵；補衝突案例（§4.1） |
| 4 | P1 | 新 coverage 不證明擋錯錨 | **修改採納**：覆蓋率改「群組數／LRC 非空行」，非反向路徑與現行逐值相同；主張收窄為「不比現行寬」；補三條拒絕測試。首尾覆蓋等新門檻駁回（無證據） |
| 5 | P1 | 反向群組錨點語意混用、遠處內插不合理 | **採納**：`groups` 分離；群組非首行在該 cue 與下一 cue 間按字數切分；四條時間測試（§4.1） |
| 6 | P1 | 探針 DP 不是將進 app 的實作，21 不能當 DoD | **採納**：§2.5 數字降為探索訊號；T4 改直接編譯分支原檔、輸出路徑指紋 |
| 7 | P1 | 28×27 交叉太窄、0 通過是弱證據 | **採納**：加同團近鄰、合成 hard negatives；「舊拒新收」逐首附 TrackMatcher 證據；G2 改稱把關非證明 |
| 8 | P1 | 本機 merged 與 iCloud importMerged 混談 | **採納**：逐條核對兩函式後寫入 §4.3；因 found 不遷移，「remote notFound v3 標記 local found」的問題消失；補四種收斂測試 |
| 9 | P2 | 195 筆重查風險不對稱 | **採納**（同 #2）：只 33 筆 |
| 10 | P2 | 驗收太弱；真機應多驗 baseline 等 | **部分採納**：T5 定義比較對象、直接錨與內插分開；驗收加「found 存檔逐位不變」。**駁回**真機加測 baseline／DP-only：found 不遷移＝baseline 依構造不變，以雜湊驗證即可；使用者慣例真機一次一項、測試由我窮盡（memory） |

## 附錄 B Codex R2（2026-11-06，評 v0.2）與處置
| # | 嚴重度 | 要點 | 處置 |
|---|---|---|---|
| A#1 | P1 | 同階不等於可接受，須以真實 DP 實測；配置前取消點；峰值記憶體 | **採納**（§4.1 效能驗收） |
| A#2／A#8 | P1 | `importMerged` 兩邊 found 取 revision 大者會覆寫本機 v2 found；`merged(found v2, notFound v3)` 把舊錨點標成 rev 3 | **採納**：引入有效版本 `min(r, foundCompatibleRevision)`，套到 policy、`importMerged`、`merged`、`RemoteTimingIndex` 門檻與 `precedes`（§4.3） |
| A#3 | P1 | 加入反向後「只在貪婪變少時才偏離」不再普遍成立；需 oracle | **採納**：改寫不變式為「無可行反向轉移時與 v2 逐值相同」，v2 原樣當測試 oracle、≥ 500 組隨機輸入；明訂同分期望（§4.1） |
| A#4 | — | 已解決 | — |
| A#5 | P1 | 字數比例未定義單位、零權重、單調、上界 | **採納**：規格寫死（§4.1）＋兩條新測試 |
| A#6、A#7、A#9 | — | 已解決 | — |
| A#10 | P1 | 雜湊驗收前提依賴 found 真的不可變 | **採納**：A#2 修正後，驗收 5 改為涵蓋同步匯入路徑與實機同步後的 SHA-256 |

## 附錄 C Codex R3（2026-11-06，評 v0.3）與處置
| # | 嚴重度 | 要點 | 處置 |
|---|---|---|---|
| 1 | P0 | 「無反向時與 v2 逐值相同」與 DP 目的矛盾（DP 單獨救回 5 首即反例） | **採納**：不變式改為 ⓐ 對上數 ≥ v2；ⓑ 未用反向且對上數＝v2 時逐值相同；ⓒ 大於時不要求（§4.1） |
| 2 | P1 | `merged` 有效版本公式在未來破壞性 rev 4 會把 v2 錨點標成 4 | **修改採納**：駁回在本案拆欄位——此雙義是 70936f1 起的既有語意，本案對 rev 3 反而收緊（不再升到 3）；拆欄位需 schema v3 與跨機遷移，超出範圍。採納留痕：§8 R5＋常數註解，規定升 `foundCompatibleRevision` 前必須先拆 `checkedRevision` |

## 附錄 D 實作時修訂（2026-11-06）
- **觸發**：寫衝突測試時發現 v1.0 的 tie-break 有反例——Music「A／B／C」、LRC「A+B 合併行、A、B、C」：反向群組（錨在第 1 個 cue）與正向三行（錨在第 2–4 個 cue）對上數都是 3；v1.0 取前者，群組數 2、覆蓋率 2／4＝0.5 被拒，後者 3／4＝0.75 可採用。另 v1.0「先跳 cue 再跳 Music」在 Music 行無處可配時違反不變式 ⓑ（推理見 §4.1）。
- **修訂**：分數改為 (對上數, 群組數) 字典序；重建改「最早的最佳 cue」。不變式 ⓐⓑⓒ 不變：貪婪路徑不用反向，群組數＝對上數，是給定對上數下群組數的上限，故貪婪最佳時它在新字典序下仍最佳，重建規則逐步重現貪婪的「最早命中、同起點先單行」。
- **Codex 快審（2026-11-06）**：①反例與修訂成立；②不變式 ⓑ 在新規則下成立；③第二鍵只在對上數相同時選群組多者，`lrcCoverage`／`minimumAnchors` 隨之單調變好，不放寬 0.7／0.6／3 的門檻（仍不證明不會錯錨，靠拒絕測試與對照組）。無未決分歧。

## 附錄 E 效能驗收修訂（2026-11-06，實作時）
- **觸發**：`aTypicalSongAlignsInUnderFiftyMilliseconds`（合成 100×100、Debug）實測 180 ms，未達 50 ms。
- **已試（皆以取樣實測定位熱點，不是猜）**：①每格比對只算一次（遮罩快取）＋串接過長提早停：180→163 ms；②SIMD 字元直方圖下界預篩：→ 75 ms（取樣：-Onone 下 SIMD 走泛型 metadata 查詢成最大熱點）；③加字元集合遮罩：→ 61 ms；④手寫打包直方圖：65 ms；⑤雙字元組遮罩：96 ms。⑤後取樣：86 % 時間在 `EditDistance`——合成輸入每句有 5 個只差一個數字的近似重複，預篩依定義擋不掉。
- **真實資料量測**（`tools/nf/timing`，28 首 notFound 的 Music 歌詞＋LRCLIB 首位候選，每首 5 次平均）：

  | 建置 | 一般曲最慢（64×44 行） | 996 行異常歌詞欄 | 合成 100×100 |
  |---|---|---|---|
  | `-Onone`，含預篩 | 109 ms | 597 ms | 96 ms |
  | `-Onone`，無預篩 | 116 ms | 612 ms | — |
  | `-O`，含預篩 | 8.2 ms | 128 ms | 9.5 ms |
  | `-O`，無預篩 | 8.3 ms | 128 ms | — |
- **判斷**：①Debug 牆鐘不代表出貨的 Release；Release 下真實一般曲 ≤ 8.3 ms，對 20 s 時限與背景執行（`@concurrent`，不佔 resolver）都無實質影響。②預篩在 Release 下沒有可量的收益 → 依 YAGNI **全部移除**，只留①。③Debug 單元測試的牆鐘門檻在 CI／負載下也不穩，改由 Release 探針量測把關。
- **修訂**：刪 `aTypicalSongAlignsInUnderFiftyMilliseconds`；效能驗收＝(a) 最壞輸入取消後 ≤ 1 s 返回（單元測試，保留，已綠）；(b) Release 下 T4 真實曲 Music ≤ 100 行每首 < 20 ms（探針，數字記入 §9）；(c) 記憶體：分數表 8 B＋遮罩 1 B／格，2000×2000 ≈ 36 MB < 64 MB（計算值）。
- **Codex 快審 R1（2026-11-06）：不成立**，四條要求與處置：
  | # | 要求 | 處置 |
  |---|---|---|
  | 1 | 平均不能證明「每首」；要最大值／冷態 | **採納**：探針改報每首 5 次中的冷態與最大值（本機＝目標機型，無其他負載；首輪量測曾與背景最壞輸入探針爭用 CPU，已停掉後重量）。Release：Music ≤ 100 行者最大 **9.4 ms**（冷態 9.1） |
  | 2 | 996 行異常輸入被排除，需上限／降級 | **採納**：分級列出——異常 996 行 Release 冷態 **241 ms**（無預篩；先前 128 ms 是含預篩組與平均值，以本次為準）；2000×2000×500 字最壞輸入 Release 完整跑完 **> 5 分鐘**（量測中途手動停止）。降級策略＝既有 20 s 時限取消→`unavailable`、不寫檔、記憶體退避，不新增機制 |
  | 3 | ≤ 1 s 要以真實 `TimingResolver` 時限＋最壞輸入證明 | **採納**：新增 `TimingResolverTests.theDeadlineCancelsAWorstCaseAlignmentWithinOneSecond`（GatedPollClock 放行時限、最壞輸入 2000×2000×500 字）：返回 `unavailable`、不存檔、到點後 ≤ 1 s——已綠 |
  | 4 | 單首上限不限制多候選×多來源累積 | **駁回（附既有程式證據）**：累積已有三道上限——每首總時限 20 s（`TimingResolver.deadline`）、同一時間只跑一首、第 2／3 名候選只在已用 ≤ 10 s 時才取（`extraCandidateCutoff`），每來源最多 3 名（`rankedLimit`）。最壞累積估計：來源數 × 3 × 單次；正常曲 ≤ 9.4 ms／次，異常 996 行 241 ms／次，皆遠低於 20 s；對齊在 `@concurrent` 背景執行、不佔 resolver。不另加 CPU 預算 |
- **Codex 快審 R2（2026-11-06）：成立**——四項處置均成立，#4 駁回成立（無本案範圍內的反例），效能驗收修訂整體可接受。
