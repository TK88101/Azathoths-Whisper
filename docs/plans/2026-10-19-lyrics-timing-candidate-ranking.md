# 時間軸查找：候選排序（借鏡 LyricsX）

分支 `wip/lyrics-timing-ranking`（自 main aa502eb）。2026-10-19 草稿（Codex 4 輪收斂）→ **2026-10-22 定稿**（Codex 評審 2 輪，附錄 §9）。

## 0. 複述
- 目標＝同一個來源搜到多筆對得上的曲目時，不再只拿第一筆（其他 4 來源）或因為「不唯一」直接放棄（LRCLIB），而是依中繼資料排出前 3 筆、逐筆取時間軸並對齊，挑對得最好的那份。
- 完成標準＝見 §6 驗收；單元全量綠、coverage_gate 通過、ACCEPTANCE I-49 更新＋新增 I-63。
- 不做＝見 §2 非目標。

## 1. 事實（已核）
- LRCLIB 符合且帶時間軸的候選不只 1 筆就判 mismatch（`LRCLIBProvider.swift:36` `synced.count == 1`）；其他 4 來源只取前 10 筆中第一個通過 `TrackMatcher` 的（`TimedLyricsProvider.swift:72` `TimingCandidate.pick`）。
- 退路鏈：第一個「對齊通過」（`LRCAligner.Alignment.isAccepted`）的來源就停並存檔（`TimingResolver.swift` `lookup`；ACCEPTANCE I-49）。
- Sum 41〈Walking Disaster〉2026-10-19 當晚失敗主因是 LRCLIB 逾時（6 s），不是排序：本計劃不宣稱修好這首。
- `Alignment` 的直接錨點數＝對上的 Music 行數＝`musicRate × 歌詞行數`（`LRCAligner.swift:54-61`）：同一次查找內行數固定，草稿 pickAccepted 的第三鍵「直接錨點數」與第一鍵等價，刪去（§3.3）。
- 每個來源各自一道 `SourceGate`（間隔 LRCLIB 0.5 s、其他 1 s；`TimingResolver+Live.swift`）；搜尋回應可快取，取歌詞不快取。

推測：多候選時拿第一筆會選到別版本（電台版、重錄版），表現為「時間整體偏早／偏晚」。推理鏈：TrackMatcher 容許 ±3 s 與名稱差 1 字，同名不同錄音都能通過；來源搜尋排序依熱門度不依時長。未量測比例（TBD，收官時以診斷日誌 rank 欄統計）。

## 2. 目標與非目標
目標：上面的「前 3 筆逐筆對齊、挑最好」；LRCLIB 廢除「唯一」規則。

非目標（不做）：
- **時間偏移（每首／全域提早延後）**：使用者 2026-10-22 決定移出本計劃；「聽音訊自動校正時間」另立專案（只做可行性調查，未排期）。草稿 §2 偏移段落作廢。
- 並行查多個來源、逐字時間軸（yrc／KRC）、酷狗（§9-1 已移除）、無正規化搜尋、cookie、純 HTTP、存外部歌詞全文。
- 改 `TrackMatcher` 的配對規則（±3 s、名稱差 ≤1、版本相容）與對齊門檻（0.7／0.6／3）。
- 舊存檔重查：既有 found 不動（排序不改對齊，`LRCAligner.revision` 不升）；既有 notFound 照 7 天自然到期重查（因 LRCLIB「唯一」規則存下的 notFound 最晚 7 天後自動受惠）。
- Python 1.x 不動。

## 3. 設計

### 3.1 provider 契約：候選清單＋逐筆取時間軸
```swift
protocol TimedLyricsProvider: Sendable {
    var source: StoredTimingSource { get }
    /// 搜尋：來源回的原始候選（未比對、未截斷；排序與截斷在 resolver）
    func candidates(for query: TimingQuery) async throws(ProviderFailure) -> [TimingCandidate]
    /// 取一筆候選的時間軸（noTiming 原因：notFound／plainOnly／tooFewLines／oversized）
    func timing(of candidate: TimingCandidate, for query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome
}
```
- `TimingCandidate` 加 `embeddedLRC: String?`（預設 nil）：LRCLIB 的搜尋結果本身就帶 `syncedLyrics`，`timing(of:)` 不再發請求。
- LRCLIB `candidates`：先 `/api/get`；**404，或 200 但該筆沒有 `syncedLyrics`**，才 `/api/search`（Codex R1 #3：精確查只給純文字時，搜尋裡可能有別筆帶時間軸）。**只收 `syncedLyrics` 非空的紀錄**（純文字的佔掉前 3 名額沒有意義）。代價：LRCLIB「有配對但只有純文字」在診斷裡由 plainOnly 變成 notFound／mismatch（只影響日誌，兩者都算明確沒有；R1 #8 駁回理由見附錄）。
- 其他 4 來源：`candidates` ＝ 原本的搜尋＋解析；`timing(of:)` ＝ 原本 pick 之後那段（Deezer GraphQL、YT next→browse、QQ、網易雲取詞）。
- `TimingCandidate.pick` 刪除（唯一呼叫點改走 §3.2）。
- 每個請求仍經各自的 `SourceGate`；逐筆串行，不並行。

### 3.2 rankCandidates（純函式，只看中繼資料）
`TimingCandidate.ranked(_ candidates:, for query:) -> [TimingCandidate]`：
1. 依原始順序以 `id` 去重（留第一次出現），**再**取前 `TimingCandidate.limit`（10）個（Codex R1 #4）。
2. 每筆問 `TrackMatcher.quality(query, candidate) -> MatchQuality?`：nil＝不配對（排除）。`matches` 改為 `quality != nil`，配對與排序共用同一份正規化與歌手拆分（單一定義，Codex R1 #5）。
3. `MatchQuality` 依下列鍵升冪比較，取前 `rankedLimit = 3`：
   1. `exact`：歌手與曲名都「完全一致」＝0，否則 1。完全一致＝`TrackMatcher` 的 folding（小寫、去附加符號、全形→半形，POSIX）後去頭尾空白、連續空白收成一個，字串相等。
   2. `titleDistance`：曲名正規化後的編輯距離（通過配對者只會是 0 或 1）。曲名優先於歌手（Codex R1 #5）。
   3. `artistDistance`：`min(整串歌手正規化後的距離, 拆開後各位歌手距離的最小值)`（0 或 1；Codex R2 #5）。
   4. `durationGap`：`|候選時長 − 查詢時長|`。
   5. 來源原始順序（去重後的 index，唯一，即全序；草稿的「候選 ID」次鍵不再需要）。
- 沒有候選通過＝診斷 `.noTiming(source, .miss(among: 前 10 筆數))`，換下一個來源（同現行）。

### 3.3 pickAccepted（純函式，只在對齊通過者之間）
`[RankedAlignment] -> RankedAlignment?`：`musicRate` 降冪 → `lrcCoverage` 降冪 → 排名（§3.2 的名次）升冪。
- 提早結束：某筆 `musicRate == 1 && lrcCoverage == 1` 時，後面的候選不可能勝出（前兩鍵最多打平，第三鍵輸），不再取後面的，省請求；結果與取完一樣。

### 3.4 resolver 流程（`TimingResolver.lookup`）
時間預算（Codex R1 #2）：第 1 名一律取；**第 2、3 名只在這首的查找已用時間 ≤ `extraCandidateCutoff = 10 s`（20 s 時限的一半）時才開始取**。這是軟截點：避免過了 10 s 還擴大同一來源的嘗試；已在 10 s 前開始的請求仍可能用掉它自己的逾時（6 s），不保證後半段一定留給後面的來源（Codex R2 #3；要保證需讓每個請求逾時取 min(來源逾時, 剩餘時限)，範圍更大，不做）。邊界：恰好 10 s 仍可開始。用時以 resolver 既有的 `MonotonicClock` 量（測試用 `FakeTimingClock` 推進）。

對每個未停用的來源（順序不變）：
1. `candidates` → `ranked`；空＝記 miss、下一來源。
2. 依名次逐筆 `timing(of:)`：
   - `.timed` → 對齊（`@concurrent`，同現行）→ 診斷 `.answer(source, rank:, alignment:, elapsed:)`；通過者收進本來源的「已通過」清單，也寫進 actor 上的 `provisional`（§3.5）。
   - `.noTiming` → 診斷，下一筆。
   - 拋失敗（非 cancelled）→ `hadFailure = true`、診斷，**下一筆照樣試**（gate 熔斷時會快速失敗，不多耗時）。
   - cancelled → 回 `.cancelled`。
3. 本來源有已通過者 → `pickAccepted` → 存 found、結束；沒有 → 下一來源。
全部來源結束：`hadFailure` ＝ unavailable，否則存 notFound（同現行）。

### 3.5 20 s 時限：只從已通過者挑
- **每次執行**配發新的 `runToken`（`pump` 每啟動一次查找就遞增；被搶占後重跑會拿到新的，Codex R2 #2）。actor 上新增 `provisional: (runToken, source, [RankedAlignment])?` 與 `acceptingRun: UInt64?`。
- 寫入 provisional 的條件：`acceptingRun == runToken` 且 `!Task.isCancelled`；`timing(of:)` 回來後、對齊回來後各檢查一次取消（Codex R2 #1）。
- 時限到：deadline 子工作勝出的那一刻（仍在 actor 上、`group.cancelAll()` 等待子工作之前）**立刻**把 `acceptingRun` 設為 nil 並取出 provisional 快照——之後晚到的結果寫不進來；若快照非空 → `pickAccepted` → 存 found（`save` 既有的「最新指紋」守衛照舊）；否則 unavailable＋記憶體退避（同現行）。
- 清理：`lookupWithinDeadline` 的 `defer` 只在 `provisional?.runToken == 本次 runToken` 時清空，`acceptingRun` 同理，不擦掉別次執行的資料。
- 被搶占：舊執行的 token 作廢，provisional 隨之清掉；重跑時從頭查。
- 取消的傳遞：正式 HTTP client 走 URLSession async API，取消會中止請求（`Infra/HTTPClient.swift:114-183`）；子工作不理會取消時 `withTaskGroup` 會等它，這是現行就有的性質，本計劃不改（Codex R1 #1 駁回，見附錄）。
- 不在時限內完成的不存 notFound（同現行）。被搶占（preempted）的工作丟掉 provisional，重跑時重查。
- `provisional` 只可能來自「目前正在問的那個來源」：前面的來源若有通過者早已存檔結束。

### 3.6 診斷
- `.answer` 加 `rank: Int`（0 起算）；日誌行加 ` rank=N`。
- 新事件 `.picked(source, rank:, tried:)`：存 found 時記一行（勝出名次、該來源實際取了幾筆）；`TimingTally` 累計 `picked rank0=… rank1=… rank2=…`（Codex R1 #9：口徑＝勝出名次，不是被取的名次）。
- 仍不含曲名、歌詞、URL（I-50）。
- 用途：收官後統計「第 2、3 名勝出」的次數，判斷本功能的實際效益（§1 推測的驗證）。

### 3.7 影響面
| 檔案 | 改動 |
|---|---|
| `Services/Lyrics/Timing/TimedLyricsProvider.swift` | 契約改兩個方法；`TimingCandidate.embeddedLRC`、`ranked`、`rankedLimit`；刪 `pick` |
| `Services/Lyrics/Timing/{LRCLIB,YouTubeMusic,Deezer,QQMusic,NetEase}Provider.swift` | 拆成 `candidates`／`timing(of:)`；LRCLIB 刪唯一規則 |
| `Services/Lyrics/Timing/TrackMatcher.swift` | 公開 `exactKey`（folding＋空白收斂）與「歌手正規化相等」判斷供排序用（規則不變） |
| `Services/Lyrics/Timing/TimingResolver.swift` | §3.4、§3.5；`pickAccepted` |
| `Services/Lyrics/Timing/TimingDiagnostics.swift` | `.answer` 加 rank |
| `Tests/Timing/*` | 替身改新契約；新增排序、挑選、resolver 多候選測試；LRCLIB「兩筆即放棄」測試改為反向 |
| `ACCEPTANCE.md` | I-49 改寫停止規則；新增 I-63 |
新增檔：`Services/Lyrics/Timing/CandidateRanking.swift`（ranked＋pickAccepted 兩個純函式），`Tests/Timing/CandidateRankingTests.swift` → 要跑 `xcodegen generate`（產物逐檔 git add，「 2／ 3.xcodeproj」舊副本不動）。

## 4. 任務清單（串行：T2 依賴 T1 型別，T3 依賴 T2 契約；不派並行 worker）
| # | 任務 | DoD |
|---|---|---|
| T1 | `TrackMatcher.quality`／`MatchQuality`（`matches` 改由它推出）；`CandidateRanking.swift`：`ranked`、`pickAccepted`、`RankedAlignment` | 既有 `TrackMatcherTests` 不改照綠；`CandidateRankingTests` 先紅後綠：exact 勝曲名距離、曲名距離勝歌手距離、歌手距離勝時長、時長勝原序、合作歌手拆分算距離 0、先去重再取前 10（前 10 筆大量重複時第 11 筆以後的唯一候選仍會被看）、只取前 3、不配對者排除；pick：musicRate＞coverage＞名次、空清單 nil |
| T2 | 契約改寫＋5 個 provider 拆分＋`FakeTimingProvider` 改新契約：搜尋腳本與每個候選的取詞腳本分開、搜尋次數與取詞次數（含候選 id 順序）分開計（Codex R1 #7）；另給單候選便利建構（舊 `Step` 一步＝搜尋回 1 筆＋取這筆），既有 28 處 resolver 測試不改意圖；取詞腳本項可帶「回應前把注入的 `FakeTimingClock` 推進 N 秒」，用來測 10 s 邊界（Codex R2 #4） | 5 個 `*ProviderTests` 改呼叫新方法後綠；LRCLIB：兩筆帶時間軸的候選都列出（原 `twoMatchingSyncedCandidatesAreAmbiguousAndNotUsed` 改為反向）、純文字紀錄不列；請求斷言（I-50 只送三欄）不變 |
| T3 | resolver 多候選＋時間預算＋時限只從已通過者挑＋診斷 rank／picked | 新測試先紅後綠：第 2 名對得較好→存第 2 名；第 1 名完美→不取第 2 名（取詞次數斷言）；第 1 名失敗、第 2 名通過→found；三名都對不上→下一來源；已用恰好 10 s 仍取第 2 名、10.001 s 不取並直接換下一來源且下一來源成功；時限到時已有 1 筆通過→found 存檔；時限到時無通過→unavailable 不存；候選不理會取消、時限後才對齊成功→仍 unavailable 且不存檔；被搶占丟 provisional、重跑後重查；新詞取消舊工作時舊 provisional 不被存；`TimingLiveAssemblyTests` 日誌行含 rank／picked、不含曲名 |
| T4 | ACCEPTANCE I-49 改寫、I-63 新增 | 條目含依據、驗證方式、狀態 |

## 5. 測試策略
- 單元（TDD，紅燈摘要記 §10）：T1–T3 所列；既有 `TimingResolverTests`、`TimingHardeningTests`、`SourceGateTests` 不改斷言照綠。
- 整合：`TimingLiveAssemblyTests`（真組裝、腳本 HTTP）跑完整鏈；新增一條「LRCLIB 搜尋兩筆、第 2 筆對得較好 → 存 LRCLIB 第 2 筆的錨點」。
- E2E：本改動不碰畫面；跑 `LyricsFXUITests`（13 條，使用者在場）確認無回歸。
- 真機（使用者在場，一次一項）：#1 播一首 LRCLIB 曾判「不唯一」的歌（從 `log show` 找 `source=lrclib result=mismatch` 的近期紀錄挑；不在對話寫曲名以外的資訊），確認特效層 `~` 消失、時間跟得上。
- 閘門：全量單元（skip 已知 flaky 一條，完整名稱＋括號）、`Scripts/coverage_gate.sh <xcresult>`、`Scripts/no_playback_gate.sh`、`Scripts` Python 測試。

## 6. 驗收（可判定）
1. LRCLIB 搜尋回兩筆符合且帶時間軸的候選 → 不再判 mismatch，兩筆都被取；對得較好者存檔（單元＋整合）。`/api/get` 只給純文字 → 照樣去 `/api/search`（單元）。
2. 其他來源搜尋回多筆符合者 → 最多取前 3 名；第 1 名對不上、第 2 名對得上 → found（單元）。
3. 第 1 名 musicRate＝lrcCoverage＝1 → 不發第 2 名的取詞請求（單元，請求數）。
4. 20 s 到期且已有通過者 → found 存檔；無通過者 → unavailable、不存（單元）。已用 > 10 s 時不取第 2、3 名（單元）。
5. 對外請求仍只送 artist／title／duration；日誌只多 rank 數字（既有 I-50 測試＋日誌行測試）。

## 7. 風險與回退
- 請求量：某來源配對成功但對不上詞時，最多多取 2 筆（YT 每筆 2 請求）。10 s 預算線保證後半段留給後面的來源；觀察：診斷日誌 `ms=`、時限次數、`picked` 名次分布。若常撞時限，可調 `extraCandidateCutoff` 或 `rankedLimit`（皆單一常數）。
- 契約改動面大（5 provider＋替身）：回退＝整支分支不合併。
- 對齊的 CPU：每筆一次對齊，最多 3 倍；已在 actor 外跑（`@concurrent`）。

## 8. 待拍板
無（偏移範圍已由使用者 2026-10-22 決定）。

## 9. 附錄：評審辯論記錄（Phase 1，Codex gpt-5.6-terra／medium，2 輪判明）

| # | Codex 意見 | 處置 | 理由 |
|---|---|---|---|
| R1-1 高 | 20 s 不是硬時限：子工作不理會取消時 group 會等 | 駁回→R2 部分反駁成立→**改** | 等待是現行性質（URLSession 取消會傳下去，`Infra/HTTPClient.swift:108-183`），不改；但 provisional 讓晚到結果可能改寫答案，故加「時限勝出即凍結快照＋取消檢查」（§3.5） |
| R1-2 高 | 前 3 名串行會吃掉 20 s，餓死後面來源 | 修改採納 | 10 s 軟截點（§3.4）；R2-3 指出不能說「保證」，文字已改 |
| R1-3 中 | `/api/get` 200 只有純文字時應再搜尋 | 採納 | §3.1 |
| R1-4 中 | 先截前 10 再去重會浪費名額 | 採納 | 先去重再取前 10（§3.2） |
| R1-5 中 | nameDistance 分桶混淆曲名與歌手；排序與配對雙重實作 | 採納 | `TrackMatcher.quality` 單一定義，曲名優先；R2-5 補 artistDistance＝min(整串, 拆開) |
| R1-6 中 | actor 全域 provisional 的歸屬 | 採納→R2-2 修正 | 每次執行配發 runToken，清理只清自己的 |
| R1-7 中 | fake 一步模擬兩操作會掩蓋差異 | 採納 | 搜尋／取詞分開腳本與計數；R2-4 補可推進時鐘 |
| R1-8 低 | LRCLIB 過濾純文字會失去 plainOnly 診斷 | 駁回（R2 同意） | 只影響日誌，存檔與控制流相同；不為日誌擴大 API |
| R1-9 低 | rank 口徑不足以統計效益 | 採納 | `.picked(source, rank, tried)`＋tally（§3.6） |
| R1 較簡方案 | 保留舊 `lookup` 快速路徑，只部分來源走候選 | 駁回（R2 同意） | 5 個來源同形狀，雙路徑＝兩份定義；預算與 provisional 需要 resolver 逐筆控制 |
| R2-1 高 | 時限後晚到的對齊會寫進 provisional | 採納 | §3.5 凍結快照、寫入前檢查取消 |
| R2-2 高 | Job 固定 token 分不出搶占前後的執行 | 採納 | runToken |
| R2-3 中 | 10 s 預算線不是保證 | 採納 | §3.4 改寫 |
| R2-4 中 | 測 10 s 邊界缺時間控制點 | 採納 | fake 可推進時鐘；測恰好 10 s 與 10.001 s |
| R2-5 低 | artistDistance 定義需明確 | 採納 | §3.2 |

R2 結論：主幹無其他阻塞問題；駁回條目雙方一致。

## 10. 實作記錄（2026-10-22，未在真機驗證）
- T1 紅：`CandidateRankingTests` 編譯失敗（`ranked`／`RankedAlignment` 不存在）→ 綠 17 條；過程中修正一條測試資料（folding 含小寫，`LANTERN BAND` 本來就算完全一致）。
- T2：契約重構先保持行為不變（resolver 只取第 1 名），timing 16 suite 140 條綠。兩個測試替身問題：LRCLIB 假資料 id 重複被去重合併（改不同 id）；舊單步替身的掛起點從搜尋移到取詞造成放行落空、2 條掛 120 s（改回在搜尋掛住）。
- T3 紅：新測試 8 條失敗或掛住（舊流程只取第 1 名）→ 綠；另補「新詞取消舊工作」與真 LRCLIB 整合各 1 條。
- 已知工具限制：一次帶 16 個 `-only-testing` 時 Swift Testing 跑 0 條（原因 TBD），分兩組跑。
- /simcodex 2 輪提前結束：R1 Reuse P1（時限替身改用既有 `GatedPollClock`）採納；收集狀態收斂為單一 `collecting`、`commit` 抽取、判空移出 do/catch；Codex R1 P1「Provisional 非 Sendable 編不過」與事實不符（已編譯通過，非 public struct 隱式 Sendable），仍補明確標註。安全評審無 CRITICAL／HIGH；LOW-1（去重掃全陣列）修。R2：Codex 無問題、simplify 無 P1。
- 全量單元 1515 條綠（2231 s，略過已知 flaky 一條）；coverage_gate Services＋Infra 95.9 %（CandidateRanking 100 %、TimingResolver 96.7 %、LRCLIBProvider 89.7 %）；no_playback_gate 通過；Scripts Python 333 條綠。
- 遺留 P2：Deezer／QQ／網易雲請求只拿 10 筆，去重後碰不到第 11 筆（Codex）；`quality` 每筆重算查詢側正規化（微秒級）；`FakeTimingProvider` 舊單步翻譯層；`matches` 只剩測試呼叫；`exactKey` 與 GenreStyleResolver 同寫法；時限快照的 tried 不含進行中那筆；時限與存檔同時發生時同內容存兩次（無害）；對齊不理會取消（現行性質，TBD）。
- 待使用者拍板：安全評審 MEDIUM——第 1 名通過但不完美時仍取第 2、3 名，背景補查總請求量可能增加（每秒速率受 gate 限制不變）。
