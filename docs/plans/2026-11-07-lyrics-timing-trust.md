# ⑪ 時間軸查到了但不一定準——「不準」標記與離線診斷

狀態：**結案（2026-11-07）**：使用者指示發版 v3.1.1（視同簽 I-74）；T6 在場未做（見 §9）。v1.0 定稿，使用者 2026-11-07 拍板開工（「可以，開工吧」）：Codex R1–R3＋快審收斂，處置見附錄 A–C。分支 `wip/lyrics-timing-trust`（自 main 2368bfb）。
前案：`2026-11-06-lyrics-timing-fix.md`（⑩，I-73 結案；遺留 T5 25 首、§8 R5）。

## 0. 複述
使用者擔心「查到了時間軸」的歌其實不一定準。帶詞約 5834 首，只查過約 195 首。使用者**否決背景批次預查**（未經確認就標成準確，播放時才發現錯更麻煩），維持播到才查。
本案要解決的是：播放時他聽出某首對不上（角落沒有 `~`，app 以為是準的）之後怎麼辦。

## 1. 使用者回答（既定前提，不重議）
- 2026-11-07（上個 session）：不做背景批次預查。
- 2026-11-07 Q1「發現不準怎麼處理」：「反正這是我自己用，不准的就只標記，湊一起 交給你來幫我解決就完了。」
  解讀（假設，寫明）：①app 只負責**記下**「這首不準」，不改顯示、不自動重查、不退回估算；②標記攢起來，由我（Claude）在本機離線查原因並修；③他不需要選修法。

## 2. 事實（已核，2026-11-07，main 2368bfb）
1. 歌詞特效層（`LyricsFXView`，嵌在 `LyricsFlowPageView`）只在時間軸來源＝`.estimated` 時顯示角落 `~`（`LyricsFXTimingMark.isShown`）。外部來源（lrclib／youtubeMusic／deezer／qq／netease）與內嵌 LRC（`.embeddedLRC`）不標。
2. 時間軸存檔：`TimingStore`（actor），每首一檔 `~/Library/Application Support/com.ibridgezhao.azathothswhisper/Timings/`，欄位含 `outcome`（found 來源＋錨點／notFound）、`fetchedAt`、`alignerRevision`、`origin`、`sourceRef`、`match`。
3. found 只在 `alignerRevision < foundCompatibleRevision`（＝2）時重查（`TimingLookupPolicy`、`TimingRecord.hasCompatibleAnchors`）；所以 revision ≥ 2 的 found 查錯了**不會自己修好**（Codex R1-5 更正）。
8. 存檔失敗時（`TimingResolver` 的 `.storeFailed`），resolver 仍回傳 found，`LyricsFXViewModel.applyTiming` 照樣顯示外部時間軸——**畫面所見不保證等於磁碟存檔**（Codex R1-2，已核 `TimingResolver.swift:213-233`）。
4. 既有「這首沒有歌詞」標記：`ConfigStore+NoLyricsMarks`（UserDefaults ledger、⑨ 同步）、`LyricsFlowModel.markNoLyrics`、Editor 按鈕。可當 UI 與存法的參照，但語意不同（那是會改變狀態的標記，本案標記不改任何行為）。
5. 選單文案寫死英文（A-07）；app 目前只有 `LibraryCheckSongsView` 用 `.contextMenu`。
6. ⑩ T5（shadow，不寫入）：lrclib-found 可比 80 首中 25 首新舊對齊器顯示會不同（新版多出直接錨點為主，逐行最大差 0.4–62 s）；哪邊對未知。
7. `alignerRevision` 雙義（⑩ §8 R5）：同時代表「錨點產生版本」與「已重查版本」；**只有在要把 `foundCompatibleRevision` 升級（＝讓 found 重查）時才必須先拆欄位**。

## 3. 目標與非目標
**目標**
- G1 播放中、時間軸來源不是估算時，使用者能用**一個動作**把當前這首標成「時間軸不準」，也能取消；標記後有可見的回饋（不是變淡的按鈕）。
- G2 標記只記證據，不改變任何既有行為：顯示、重查、同步、存檔皆不變。
- G3 標記內容足以讓我離線重現：歌、**畫面當時實際套用的那份時間軸**（來源＋錨點快照，純數字）、對應存檔的身分（若與畫面一致）、他按下時播到哪裡。
- G4 離線診斷工具（repo 外，`~/Developer/azw-timing-probe/tools/flags/`）：讀標記＋存檔＋Music 歌詞，逐首輸出**只有數字**的診斷表，給出修法分類。
- G5 T5 的 25 首併入評估：被標記的歌若在 25 首內，診斷表另列 rev 3 的結果，作為「found 要不要整批改用新對齊器」的證據。

**非目標**
- 不做背景批次預查、不主動補查曲庫（使用者既裁定）。
- 不加「可信度低也標 `~`」、不改 `~` 的條件。
- 標記後不自動重查、不換來源、不退回估算（使用者：只標記）。
- 標記不經 iCloud 同步（使用者只有一台 Mac，⑨ I-72；YAGNI）。
- 本案**不修**任何一首的時間軸：修法依診斷結果另寫計劃、使用者拍板（見 §4.5）。
- 不拆 `alignerRevision`（R5）——只有當診斷結果決定要讓 found 重查時才做，屆時在修正計劃中處理。
- 不碰 YSE；Python 舊版不動。

## 4. 設計
### 4.1 入口與回饋
- 入口：歌詞特效層的**右鍵選單**（`.contextMenu` 掛在 `LyricsFXView` 的 ZStack），項目寫死英文（A-07 同慣例）：`Mark Timing as Off` ／已標記時 `Unmark Timing`。
  理由：特效層就是他「看到不準」的地方；不在畫面上常駐按鈕（Mac 介面極簡、memory「找歌詞的工具，不是播放器」）。
- 可用條件（simcodex R1 收斂為一處）：VM 的 `canToggleTimingFlag`＝有標記鍵（有詞、pid 非空）且 `appliedTiming != nil`（快照只在時間軸非估算時存在，由 `setTimeline` 單一寫入點保證）。其他情況選單項目不出現（估算本來就標 `~`，標它沒有資訊量）。
- 回饋：標記中的歌，角落（`~` 的同一位置）顯示小字 `!`，同 `~` 的字型與顏色；a11y label `timing_flagged`（三語 xcstrings）。取消標記即消失。
  顯示條件（純函式 `LyricsFXTimingMark.resolve` 回 `.estimated`／`.flagged`／`.none`，Codex R2-3）：`!` 只在「目前時間軸非估算、且 applied 快照屬於當前 identity 與 lyricsHash、且該鍵已標記」時出現；換曲後外部時間軸還沒回來的估算窗口只顯示 `~`。
- `.embeddedLRC` 也可標（他自己的 LRC 也可能歪）；診斷工具對它只報「內嵌」不查外部。

### 4.2 標記記錄（新邊界，照 protocol＋替身慣例）
- `TimingFlagStoring` protocol；正式實作 `TimingFlagStore`（actor），單檔 JSON：`.../Application Support/com.ibridgezhao.azathothswhisper/TimingFlags.json`；測試用 `InMemoryTimingFlagStore`。
- 鍵＝**(persistentID, lyricsHash)**（Codex R1-3）：同一首歌詞改版後再標，舊歌詞的標記保留；UI 只看當前歌詞的那一筆；取消只刪當前那一筆。
- 檔案格式（`schemaVersion: 1`）：`flags: [TimingFlag]`。
  ```
  TimingFlag {
    persistentID: String
    lyricsHash: String
    markedAt: Date                 // 最後一次標記
    positions: [Double]            // 每次按下時的播放秒數（0.1 s），最多 10 筆（新的在後）
    applied: {                     // 畫面當時實際套用的時間軸（VM 保存的不可變快照，Codex R1-1／R1-2）
      source: TimingSource         // 不含 .estimated（可用條件已排除）
      anchors: [LineStart]         // 外部來源＝applyTiming 收到的錨點；embeddedLRC＝當時由內嵌 LRC 建出的各行起點（序號＋秒數，Codex R2-1）
    }
    stored: { source, alignerRevision, fetchedAt, sourceRef?, origin? }?
                                   // 只有在 TimingStore 的存檔與 applied「同 lyricsHash、同來源、錨點逐值相同」時才填；
                                   // 否則 nil，另記 provenance = .storeMismatch／.storeMissing（工具據此明示「存檔與畫面不一致」）
    provenance: matched | storeMissing | storeMismatch | embedded
  }
  ```
  錨點快照只有序號與秒數，不含歌詞文字。不存曲名、歌手、歌詞。
- 冪等：同鍵重複標記＝更新 `markedAt`、append position（上限 10）、以最新 applied／stored 覆蓋（同鍵＝同歌詞，畫面時間軸若已換，取最新——那正是他剛剛又聽到不準的那份）。
- 大小上限（Codex R1-6）：寫入前序列化，若 > 512 KB 就從 `markedAt` 最舊者丟起直到 ≤ 512 KB；讀取上限維持 1 MB。保證任何合法寫出的檔都讀得回來；單筆錨點數上限沿用 `TimingStore.maxLines`（5000，約 100 KB），單筆就超過 512 KB 不可能。測試：塞滿到上限後重讀成功、最舊者先被丟。
- 讀不懂的檔（壞 JSON、版本較新、符號連結、超大）：不讀、**不覆寫**，標記動作回失敗並記 log（錯誤類型），UI 不顯示 `!`。同 `TimingStore` 的「未知不得蓋掉」原則。
- 寫入：暫存檔＋原子替換（沿用 `TimingStore.write` 的作法，實作時核對可否共用）。
- 日誌：OSLog，只記「flag set／cleared／failed」＋錯誤類型與 provenance；不記曲名歌詞。

### 4.3 接線（跨 feature 只經 `AppModel`）
- `LyricsFXViewModel` 在 `applyTiming` 成功時保存 `appliedTiming: AppliedTiming(identity, lyricsHash, source, anchors)`（不可變快照；換曲／歌詞變更時清掉；embeddedLRC 由 `timeline(for:)` 設定時以當時 timeline 的各行起點建快照）。工具以快照為準，現在的 Music 歌詞只用來附報「是否仍同 hash」。
- 新增 observable `timingFlag: TimingFlagState`（`.unflagged`／`.flagged`／`.pending`）與回呼 `onToggleTimingFlag: (TimingFlagRequest) -> Void`。
- 按下時 VM 先擷取 `TimingFlagRequest(identity, lyricsHash, position, appliedTiming, wantsFlagged)`（**同步擷取、在任何 await 之前**），狀態設 `.pending`；`.pending` 期間右鍵選單項目不出現（Codex R1-7：快速連點／set-clear 交錯不會排入兩次相反意圖）。
- `AppModel`：讀 `TimingStore.load(pid)`，與 request 的 applied 比對得出 `stored`／`provenance`（純函式 `TimingFlagProvenance.resolve`，單測），寫入 flag store；完成後以 identity 回呼 VM。VM 以 `isCurrent(identity)` 守衛；換曲後到的結果丟掉（寫入照樣生效——事實事件先於 stale 守衛）。失敗則回到原狀態。
- 換曲／歌詞變更時 VM 以新 identity 向 `AppModel` 查一次是否已標記（`flagStore.isFlagged(pid, lyricsHash)`）。
- 亂序防線（Codex R2-2）：VM 持單調遞增的 `flagEpoch`；初始查詢與 toggle 每次發出都帶 `(identity, epoch)`，回呼必須兩者皆等於最新值才套用；`.pending` 期間初始查詢的結果一律丟棄。測試：初始查詢晚於 toggle 完成才回來、晚於 toggle 發出但早於完成回來，兩種都不得覆蓋。

### 4.4 離線診斷工具（repo 外、只出數字）
`~/Developer/azw-timing-probe/tools/flags/`，沿用 `tools/nf` 的作法，**直接編譯 app 原檔**（Codex R1-4）：對齊（`LRCAligner`／`LRCAlignmentPath`／`EditDistance`／`LRCParser`）、選曲（`TrackMatcher`／`CandidateRanking`／`ProviderOutcome`）、**五個 provider 與其 parser、`TimedLyricsProvider`、`SourceGate`、HTTP client 與 `TimingResolver+Live.swift` 的來源組裝（含各來源 `minimumInterval`：LRCLIB 0.5 s、其他 1 s）**。實作時若某檔依賴 app-only 型別無法單獨編譯，就在工具內加最小 shim，不改 app 原檔；改不動時該來源列「unavailable（工具限制）」，不靜默略過。
1. 讀 `TimingFlags.json`、對應的 `Timings/<pid>.json`、Music 歌詞（唯讀 osascript，只讀 lyrics 與曲長；不送播放控制）。
2. 每首（以序號代替曲名）依序查各來源，同一來源請求間隔照 app 的 `SourceGate`、單一請求逾時照 app、429／失敗記 `unavailable` 並照 app 的熔斷規則停用該來源到本次結束。
3. 逐首輸出：provenance；applied 來源／錨點數；現在的存檔與 applied 是否相同；各來源候選的 TrackMatcher 結果、時長差、rev 3 對齊的 musicRate／lrcCoverage／groups、與 applied 錨點的逐行差（中位數、最大、標記位置 ±15 s 內的差）；各來源之間的互比；是否在 T5 25 首內（25 首另列 rev 2 vs rev 3）。T5 名單的權威來源（Codex R2-4）：〔更正：⑩ 其實有存逐首結果，見 §9 T4〕T4 先用 `tools/nf/t45` 重跑一次 shadow，產出 `out/t5-manifest.json`（只含 pid、lyricsHash、舊新錨點摘要雜湊、重跑日期），並核對重跑結果仍為 80 可比／25 不同；數字不符時記實際值、照實值用，不硬湊 25。
4. 分類（推測，供修法計劃用，Codex R1-9）：A 套用的來源疑似錯版本（時長差大或其他來源彼此一致而與它不同）；B **疑似**對齊器錯錨（當時輸出可重現；不是「已證明同一候選」，Codex R3-1／快審）：用 applied 當時的對齊器版本（rev 2＝`tools/nf/t45/V2Oracle.swift`、rev 3＝分支原檔；版本取自 `stored.alignerRevision`，provenance 非 matched 時無版本可用→不判 B）重跑重新取得的候選，錨點與 applied 快照**逐值相同**才進 B（只代表當時輸出可重現，不同候選也可能產生相同錨點），再看另一版本結果是否不同、差是否集中在標記位置附近；重現不了＝候選已變，歸 U 並註明「候選已變」（同 ⑩ T5 的『舊對齊器能重現存檔錨點』驗證法）。不改 resolver、不加候選 ID 欄位；B 只作修法計劃的線索，修法計劃仍需各自的證據；**U 未定**（各來源彼此一致、與 applied 也一致，他仍說不準——可能是來源 LRC、Music 播放位置、整體 offset 或歌詞版本，需要人耳，列 TBD，不預設修法）；D 內嵌 LRC。
5. 輸出只寫到 `~/Developer/azw-timing-probe/out/flags-YYYYMMDD.tsv`，不進 repo，不出曲名歌詞。

### 4.5 之後怎麼修（本案不做，只定流程）
攢到標記後（無固定數量，使用者說「湊一起」；我在他說「可以看了」或下次 session 開工時跑工具），依分類寫修正計劃交他拍板。可能的修法（推測，依證據才選）：A→新增「排除該來源重查單首」的修正路徑；B→若被標記的多落在 T5 25 首且 rev 3 能修好，提出「拆 `alignerRevision`（R5）＋讓 found 用 rev 3 重查」；U→先分清是哪一種再說，不預設修法。

### 4.6 ACCEPTANCE
新增 I-74「時間軸不準標記」：入口、可用條件、回饋、不改任何既有行為、記錄格式與隱私、讀不懂不覆寫。

## 5. 任務清單
| # | 任務 | DoD |
|---|---|---|
| T1 | 紅燈：`TimingFlagStoreTests`（往返、同鍵冪等、**同 pid 不同 lyricsHash 互不覆蓋**、positions 上限 10、**512 KB 寫入裁減＋塞滿後重讀成功**、取消只刪當前鍵、壞檔／新版本／超大／符號連結不讀不寫、空 pid 拒絕、原子寫入）、`TimingFlagProvenanceTests`（matched／storeMissing／storeMismatch／embedded 各分支）、`LyricsFXTimingFlagTests`（VM：applied 快照隨 applyTiming 設定、embeddedLRC 快照、換曲清掉；擷取在 await 前；pending 期間不可再觸發；失敗回復；換曲後回呼被丟；epoch 亂序兩種；歌詞指紋不同＝未標記；**已標記歌曲重新進入、外部查找未回時只顯示 `~`**）、`AppModelTimingFlagTests`（存檔失敗仍可標且 provenance＝storeMissing；**標記前後 TimingStore 檔逐位不變**；resolver 呼叫 0 次） | 新測試紅、既有綠；紅燈摘要記 §9 |
| T2 | 實作 store＋VM＋AppModel 接線＋右鍵選單＋`!` 回饋＋xcstrings 三語＋`AccessibilityID` | T1 全綠；`xcodegen generate` 後產物一起 commit |
| T3 | XCUITest `LyricsFXTimingFlagUITests`：UI 測試替身時間軸（非估算）→右鍵出現 `Mark Timing as Off`→點後 `!` 出現→再右鍵 `Unmark Timing`→消失；估算時選單項目不存在。**T2 一完成就先跑**（Codex R1-10：本 app 無 ZStack 右鍵自動化先例） | 使用者在場跑綠（Automation Mode、ABC 輸入法）。若 XCUITest 無法穩定開出該右鍵選單：記事實、改由單元測試覆蓋選單命令，實機操作驗收併入 T6，不放寬其他斷言 |
| T4 | 離線診斷工具（repo 外）＋自編 fixture 測試（放工具資料夾）：A／B／U／D 各一、來源失敗（逾時、429→熔斷）、provenance 四種；重跑 T5 shadow 產出 manifest | fixture 輸出預期分類與 unavailable；對真機標記檔（使用者標 ≥ 1 首後）跑一次，輸出只有數字 |
| T5 | 全量單元＋`coverage_gate.sh`（傳單元 xcresult）＋`no_playback_gate.sh`＋Scripts 測試 | 全綠（既有偶發掛起 1 條照列，不跳過以外的處置不變） |
| T6 | 使用者在場 #1：他播任一首有外部時間軸的歌，右鍵標記一次、看到 `!`，再取消一次 | 一句話回報；之後他照常使用、自由標記 |

並行候選：無（T1→T2→T3 同一組檔；T4 依賴標記格式）。

## 6. 測試策略
- 單元：Swift Testing，自編字串（不用真歌詞）；store 用暫存目錄；VM 用既有替身與 `PollClock`。
- 集成：`AppModelTimingFlagTests` 走真的 `TimingStore`（暫存目錄）＋ `InMemoryTimingFlagStore`。
- E2E：T3 XCUITest；T6 使用者在場一次。
- 工具：T4 fixture 測試；真資料只出數字。

## 7. 驗收
1. T1–T3 綠；全量單元無新增紅；coverage Services＋Infra ≥ 80 %（`TimingFlagStore` 在 Services 下）。
2. 標記／取消前後：`Timings/` 檔案逐位不變、無網路查找被觸發（測試斷言 resolver 呼叫次數 0）。
3. `TimingFlags.json` 內無曲名、歌手、歌詞字串（測試以自編曲名掃檔斷言）。
4. 使用者在場 #1 回報能標、能取消、看得到回饋。
5. `git diff main --stat` 只含：新 store、VM／View／AppModel 接線、xcstrings、AccessibilityID、測試、`project.yml` 產物、ACCEPTANCE、本計劃。

## 8. 風險與回退
- R1 右鍵選單他找不到 → T6 當場確認；若不好用，改加鍵盤快捷鍵（不另開按鈕）。
- R2 標記檔與 Timings 存檔脫節（存檔失敗、同步或重查改了存檔）→ 標記內存畫面實際套用的錨點快照＋provenance，工具比對「畫面當時 vs 現在存檔」。
- R3 他標了但其實是 Music 播放位置回報延遲造成的觀感 → 工具分類 U／TBD，不硬修。
- R4 標記累積多但我沒去處理 → memory 記「下次 session 開工先跑工具」；標記本身不影響使用。
- 回退：刪除入口與 store；`TimingFlags.json` 留在磁碟無副作用（舊版不讀）。

## 9. 實施紀錄
- **T1 紅燈（2026-11-07）**：新 4 suite（`TimingFlagStoreTests`、`TimingFlagProvenanceTests`、`LyricsFXTimingFlagTests`、`AppModelTimingFlagTests`）以空殼編譯後跑：除「沒有後端／沒有存檔就不提供選單」2 條（回歸守衛，空殼下本來就綠）外全紅；替身在空殼下 `removeFirst` 空陣列致宿主崩潰，改為記 Issue 的安全版。
- **T2 綠（2026-11-07）**：store／provenance／可用條件／角落判定／VM（快照、pending、epoch）／AppModel 接線／右鍵選單／`!`／`timing_flagged` 三語／`AccessibilityID` 完成；相關 7 suite（新 4＋`TimingMarksTests`（三語檢查加 `timing_flagged`）、`LyricsFXViewModelTests`、`AppModelTimingTests`）78 條綠。
  - 偏離 §4.2 字面（筆誤級）：檔案放 `Application Support/.../TimingFlags/flags.json`（資料夾＋檔名，同 `ArtistConsensus/` 慣例），非 `TimingFlags.json`。
  - 實作中觀察（既有行為、非本案引入、未改）：同一首在外部時間軸套用後若再收到 metadata 變更，`apply` 會把時間軸重建為估算，而 `requestedTiming` 擋住同 (pid, 指紋) 重查——該首會回到估算直到換歌。標記狀態依鍵保留不受影響。是否另案交使用者決定。
- **T3 綠（2026-11-07，使用者在場）**：`LyricsFXUITests.testAFoundTimelineCanBeMarkedAsOffAndUnmarked`（14.6 s）、`testEstimatedTimingOffersNoMarkMenu`（9.0 s）2／2 綠；右鍵自動化可行，不需 fallback。
- **T4（2026-11-07，repo 外 `~/Developer/azw-timing-probe/tools/flags/`）**：`build.sh` 直接編 app 原檔（五個 provider、`SourceGate`、`LRCAligner`／`LRCAlignmentPath`、`TrackMatcher`／`CandidateRanking`、`TimingFlagStore`（同一份 `isWellFormed`）、`TimingStore`）＋ ⑩ 的 `V2Oracle`；SwiftSoup（QQ 來源依賴）從套件原始碼編成 `lib/libSwiftSoup.a`。
  - **shim（依 §4.4 例外條款）**：`TimingResolver.swift` 牽出 iCloud 同步、設定存檔等 app 型別，工具不編它；`LiveProviders.swift` 照抄 `liveProviders` 的順序與間隔——provider 與 `LRCLIBProvider.minimumInterval` 仍是原檔，唯一抄來的常數是非 LRCLIB 間隔 1 s（檔內註明 app 改動時要同步）。
  - `flags selftest`：A／B／U／D、來源失敗熔斷（同來源失敗後本次不再請求）、provenance 四種、標記附近錨點差——**OK**。`run.sh`＝讀標記 → osascript 唯讀讀 Music → 逐首查來源 → `out/flags-YYYYMMDD.tsv`。真資料待使用者標記後跑。
  - **T5 名單（更正 §4.4 的事實）**：⑩ 其實有存逐首結果（`tools/nf/data/t45-report.json` 的 `t5Shadow`，80 筆含 pid）。仍依計劃重跑 `t45`（離線、只讀已存資料）：可比 80、不變 55、會變 **25**，與 ⑩ 一致。名單 `out/t5-manifest.json`：25 筆，只含 pid、歌詞指紋（25／25 皆有）與差異數字。§4.4 原寫的「舊新錨點摘要雜湊」改為存差異數字（`maxLineDiff` 等），比雜湊更能直接用。

- **T5 全量（2026-11-07 19:06–20:32，checkpoint 34f2beb）**：單元 2263 條＝2236 綠、26 跳過（既有）、**1 紅**＝`BatchOverlappingLoadTests.overlappingLoadSuspendsPollingUntilLastCompletes` 超時 120 s——memory 記載的既有偶發掛起（2026-09-27 起；⑩ 全量同一條），本分支對 `Features/Batch` 改動 0 行，未跳過、照列。完整性：2263＝⑩ 的 2221＋本案新增 42（`TimingFlagStore` 13、`Timing flag provenance` 8、`LyricsFX timing flag` 15、`AppModel timing flag` 6，全綠），無因超時而消失的測試。coverage_gate：Services＋Infra **96.6 %**（`TimingFlagStore` 100 %、`TimingFlag` 100 %；`App/AppModel+TimingFlags` 82 %，不在閘門範圍）。no_playback_gate 綠；Scripts Python 471 條 OK。
- **結案（2026-11-07）**：使用者聽完說明（「這個版本的改動就只是手動打標記」，確認無誤）後指示發版 v3.1.1、合併 main、刪分支、發 Release、更新 /Applications。**T6 使用者在場 #1 未做**：使用者直接指示發版；右鍵標記／取消的實機行為由 T3 的 UI 測試（使用者在場、真 app 視窗）覆蓋。遺留另案（待使用者決定）：①外部時間軸套用後同首 metadata 晚到會退回估算（既有行為）；②安全讀檔流程 5 個 store 收斂；③simcodex 延後 P2（附錄 D）。
## 10. 待拍板
無（Q1 已答；其餘取捨照 §4 的假設，評審若有異議再問）。

## 附錄 A Codex R1（2026-11-07，評 v0.1）與處置
| # | 嚴重度 | 要點 | 處置 |
|---|---|---|---|
| 1 | P1 | flag 只存身分、沒有錨點；存檔可被重查／同步改寫，無法重現 | **採納**：存畫面套用的錨點快照（純數字）＋provenance（§4.2） |
| 2 | P1 | 畫面所見≠存檔（`.storeFailed` 仍顯示 found） | **採納**：已核 `TimingResolver.swift:213-233` 成立；VM 保存 applied 快照，AppModel 比對後才填 `stored`，不一致記 provenance（§2-8、§4.3） |
| 3 | P1 | 以 pid 為鍵，歌詞改版後再標會蓋掉舊證據 | **採納**：鍵改 (pid, lyricsHash)，補互不覆蓋測試 |
| 4 | P1 | 工具未定義 provider／SourceGate／HTTP 的復用與節流 | **採納**：直接編譯 production provider＋`SourceGate`＋`TimingResolver+Live` 組裝，間隔／逾時／熔斷照 app；編不了的來源明示 unavailable；fixture 加來源失敗（§4.4、T4） |
| 5 | P2 | 「found 永遠不會自己修好」不精確（rev 1 found 會重查） | **採納**：§2-3 改寫 |
| 6 | P2 | 2000 首與 1 MB 讀取上限未保證相容 | **採納（改法）**：不限首數，寫入時以序列化大小 ≤ 512 KB 裁減最舊者；塞滿重讀測試 |
| 7 | P2 | 非同步 toggle 無 in-flight 狀態 | **採納**：`.pending` 狀態期間不可再觸發、失敗回復、補測試 |
| 8 | P2 | 寫入前未檢查存檔與畫面一致 | **採納**（併入 #2 的 provenance 比對） |
| 9 | P2 | 分類 C 預設成「LRC 錯」，與 R3 矛盾 | **採納**：改為 U 未定，不預設修法 |
| 10 | P2 | 右鍵 XCUITest 無先例，可能晚期才發現不可行 | **修改採納**：不另做 spike（XCUITest 需使用者在場，多一次在場成本高）；T3 在 T2 完成後第一個跑，不可行時改單元測試覆蓋命令＋T6 實機驗收 |

## 附錄 B Codex R2（2026-11-07，評 v0.2）與處置
附錄 A 判定：#2–#6、#8–#10 成立；#1、#7 不完全成立（即下表 1、2）。#6 附註「同一 markedAt 的裁減次序要穩定」：採納，實作時以 (markedAt, persistentID, lyricsHash) 排序。#10 附註：fallback 若發生，§9 寫明「XCUITest 未覆蓋」。

| # | 嚴重度 | 要點 | 處置 |
|---|---|---|---|
| 1 | P1 | embeddedLRC 存 `anchors: nil`，歌詞事後被改就無法重現 | **採納**：embedded 也存當時各行起點（§4.2、§4.3） |
| 2 | P1 | `.pending` 不防初始查詢與 toggle 回呼亂序 | **採納**：`flagEpoch`，回呼須 identity＋epoch 皆最新；pending 時丟棄初始查詢；兩種亂序測試 |
| 3 | P1 | 估算窗口內 `!` 與 `~` 可能同時出現（已核 `LyricsFXViewModel.swift:153-188` 先估算後熱替換） | **採納**：`!` 的條件綁定當前 applied 快照；估算窗口只顯示 `~`；補測試 |
| 4 | P2 | T5 25 首無逐首名單可讀 | **修改採納**：已核 ⑩ 未存逐首輸出；不刪此欄，T4 用既有 `t45` 重跑 shadow 產出 manifest（只含 pid／hash／摘要），數字以重跑實值為準 |

## 附錄 C Codex R3（2026-11-07，評 v0.3）與處置
附錄 B 四條均判成立。

| # | 嚴重度 | 要點 | 處置 |
|---|---|---|---|
| 1 | P1 | resolver 只存 source＋錨點，工具重查到的候選無法證明是當時那份，可能把候選改版誤判成對齊器錯錨 | **修改採納**：B 只在「用當時版本重跑重查到的候選、錨點與 applied 快照逐值相同」時成立，否則歸 U（候選已變）。不採「resolver 傳 candidate ID＋LRC 雜湊」：逐值重現已足以認定同一份（⑩ T5 已用此法，80／82 重現），加欄位要改 resolver、存檔與同步格式，超出「只標記」範圍 |

**快審（2026-11-07，評 v0.4）**：不成立——逐值相同只證明「當時版本的輸出相同」，不同候選（只差未對上的行或文字）也可能產生相同錨點。**採納其修正**：B 降為「疑似對齊器錯錨（當時輸出可重現）」，不宣稱同一候選；需要確證時另案在套用當時保存候選內容雜湊。分歧收斂，定稿 v1.0。

## 附錄 D simcodex（2026-11-07，三輪；checkpoint 5d37573／c887cfb → 421401e → b834ba1 → 本次，皆 wip、未 push）
codex 一律 `codex review --base main`。安全評審只在 R1 派一次（Opus）。

| 輪 | 來源 | 處置 |
|---|---|---|
| R1 | codex P2＋安全 MEDIUM-1（同一件） | **採納（紅→綠）**：單筆標記單獨超過 512 KB 時，裁減迴圈會把舊標記連同新的一起丟光、寫空檔並回報成功。改為先量單筆，放不下拋 `flagTooLarge`、不動檔；裁減時新的那筆不丟（`aSingleFlagTooLargeToFitIsRejectedWithoutTouchingTheFile`、`theNewFlagIsNeverTheOneTrimmed`） |
| R1 | 安全 LOW-1／2（檢查後讀取的 TOCTOU、資料夾是符號連結） | **不改**：需同使用者權限，`TimingStore`／`ArtistConsensusStore` 同寫法、同一已接受風險；要收斂應三個 store 一起改（另案） |
| R1 | 安全 LOW-3（A→B→A 切歌時查詢可能早於寫入、畫面暫時未標） | **不改**：檔案正確、下次換回會重查修正；不值得為此加狀態 |
| R1 | simplify altitude／simplification P1（可標記判斷兩處定義、`applied.source == timeline.source` 事後對帳） | **採納**：`timeline` 與 `appliedTiming` 改由 `setTimeline` 單一寫入點設定（估算＝nil），可標記＝有鍵且有快照，`!` 用同一判斷；刪 `TimingFlagAvailability`。不採「`LyricsTimeline` 自帶快照」：要改 `LRCAligner`／builder 共用基礎設施，單一寫入點已達同效 |
| R1 | simplify P1（守衛裡與 epoch 等價的條件） | **採納**：兩個回呼只留 `flagEpoch == epoch` |
| R1 | reuse P1（安全讀檔流程第 5 份手抄） | **延後（需使用者決定）**：收斂要動 4 個既有 store，多檔重構超出本案 |
| R1 | 其餘 P2 | 採納：`InMemoryTimingFlagStore` 限 DEBUG、0.1 s 量化移到 `TimingFlag.quantized`、`LyricsTimeline.lineStarts`。延後：`with*` 手抄欄位、兩個同 category Logger、測試 fixture／替身重複、裁減迴圈 O(n²)、`isFlagged` 每次重讀檔、`TimingFlagRecorder` 抽層 |
| R2 | codex P2 | **採納（紅→綠）**：語法合法但內容不合規格的檔（非正規 pid、估算來源、positions 超量）被當正常讀入、寫入時覆寫。讀檔逐條 `isWellFormed`，不合整檔當未知 |
| R2 | simplify（增量） | 無 P1。採納：寫入也用 `isWellFormed` 把關（`malformedFlag`），讀寫同一謂詞；計劃殘留舊名更新。不採：前置大小檢查多一次 encode（毫秒級，換來不先裁舊標記）、UI 測試替身的 lineStarts 重複 |
| R3 | codex P2 | **採納（紅→綠）**：錨點只驗數量，負數／非有限／亂序也收。`isWellFormed` 加 `areWellFormedAnchors`（與 `TimingStore` 同一不變式）與 positions 有限非負。已核內嵌 LRC 起點由 `LRCParser` 依時間排序，不會被誤拒 |

修正後：相關 7 suite 79 條綠。simcodex 三輪用完，R3 的唯一一條已修；是否再加一輪由使用者決定。
