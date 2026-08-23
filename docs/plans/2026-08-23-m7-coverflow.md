# M7：Cover Flow —— 封面 3D 瀏覽（純展示）

- 日期：2026-08-23
- 狀態：**定稿**（Codex 兩輪對抗評審：16 條意見 13 採納／3 修改採納；我方 2 條駁回，第 1 條 Codex 接受不重提＝我方勝，第 2 條 Codex 重提且論證成立＝Codex 勝並已採納。辯論記錄見附錄）
- 上游規格：`docs/plans/2026-08-09-swift-rewrite.md` §4.8 ＋ 決策 2／6
- 驗收：`AzathothsWhisper/ACCEPTANCE.md` H 段 11 條（H-01…H-11，目前全 ⬜）
- 前置：M6 收尾已完成並 commit（`b1873dc`／`26e9c30`），單元測試 171 全綠、覆蓋率 82.2%

## 0. 勘察事實（已核實，非假設）

| 事實 | 位置 |
|---|---|
| `AppTab` **已含** `case coverFlow`，`nav_coverflow` 三語 i18n 已在 | `Features/Shell/AppTab.swift:8`／`Resources/Localizable.xcstrings:579` |
| `RootView` 目前渲染 placeholder（明注「M7 接手前的暫位，不進驗收表」） | `Features/Shell/RootView.swift:118-119` |
| `artworkData(persistentID:)` 已實作，M1 spike 已驗過 AE 取 raw data 的陷阱 | `Services/Music/MusicAppleEventsClient.swift:92-107` |
| `sortedForDisplay()`（disc → track → AE 序 fallback）**已實作**，H-11 的排序邏輯無需重寫 | `Services/Music/MusicControlling.swift:79-92` |
| **全庫零快取實現**（`NSCache`／`URLCache` 皆無引用）→ `ArtworkCache` 全新建 | grep 確認 |
| 可用佔位資產：`AboutLogo.png`（六角形 logo） | `Resources/`／`UI/BundleAssets.swift:6` |
| Theme token：`background` #000、`surface` #0a0a0a、`border` #333、`cardBackground` #050505 | `UI/Theme.swift:5-30` |
| `NowPlayingMonitor` 已支持多來源 busy（`BusySource` 列舉），新增來源只需擴列舉 | `Services/Music/NowPlayingMonitor.swift:18` |

**Cover Flow 與 `BusySource`（Codex #14 採納後的明確規則，非推測）**：
**不新增第三個 `BusySource`**——規格 §4.8 明寫「純展示不控播」，Cover Flow 沒有需要暫停輪詢的操作。
但這**不等於**「共用 AE queue 沒問題」：新增 BusySource 反而會讓輪詢整段停止、違反 H-04。
改為明定設計約束：

> **Cover Flow 不得改變 monitor 的輪詢語義。artwork 請求必須可取消且有界，
> 中心請求優先，預取低優先級。若發生壅塞，靠取消／降低預取數／交錯排程解決，不靠停輪詢。**

## 1. 目標與非目標

**目標**
- 第三個 nav tab，激活時懶加載（對齊 Batch 的 C-01 先例）。
- 經典 iPod Cover Flow 形態：中心正面／兩側 ±55° 斜角／負間距覆疊／倒影漸變／viewAligned 吸附。
- 與播放聯動：切歌 ≤3s 自動平滑居中；切專輯重建＋預取；使用者手動滑走後不搶控制。
- 封面快取：記憶體 ＋ 磁碟，冷啟動即顯；LRU 上限 200 張／50MB；損毀檔容錯。
- H 段 11 條驗收全綠。

**非目標**
- **不做任何播控**（決策 6：無雙擊播放、無播控動詞）。
- 不做 M8 打包收官。
- 不改 Editor／Batch 既有行為。
- 不新增歌詞源、不動 Python 舊版。

## 2. 架構與檔案佈局

```
Services/Artwork/
  ArtworkCache.swift        ~180 行  磁碟 LRU ＋ 記憶體 NSCache
  ArtworkService.swift      ~120 行  取圖編排、縮圖解碼、預取順序
Features/CoverFlow/
  CoverFlowViewModel.swift  ~200 行  條目狀態、居中邏輯、事件聯動
  CoverFlowView.swift       ~180 行  ScrollView ＋ LazyHStack ＋ 3D 變換
  CoverFlowItem.swift       ~90 行   單張封面＋倒影＋佔位
```

分層邊界：View 不碰 AE 與檔案系統；ViewModel 只依賴 `ArtworkProviding` 協議（測試注入替身）。

## 3. 分兩階段實施（Codex #16 採納）

**為何分階段**：一次引入兩級快取＋持久化 LRU＋預取編排＋3D 幾何＋事件世代＋AppModel 接線，
失敗時難以判斷是 AE、cache、SwiftUI 還是 VM 的問題。分階段可降低同時在飛的競態數量，
且第一階段就能讓 Cover Flow 跑起來。

| 階段 | 內容 | 驗收 |
|---|---|---|
| **P1** | 記憶體快取 ＋ 中心單張載入 ＋ **無預取** ＋ 完整 3D 視覺 ＋ 事件聯動 | H-01／02／03／04／05／08／09／10／11 |
| **P2** | 磁碟 LRU ＋ metadata 恢復 ＋ 低優先級可取消預取 | H-06／07 ＋ 效能 |

**分階段直接緩解了 Codex #6（AE 餓死 monitor）**：P1 無預取，AE 上最多 1 個 artwork 在飛。
但**「in-flight ≤ 1」不等於「不阻塞 deadline」**（Codex 複審重提且論證成立，已採納）——
單一慢請求同樣會讓後續 `currentTrack()` 排在它後面。故 P1 仍須：
- artwork 請求**有界 timeout ＋ 可取消**
- 切歌／monitor deadline 到達時，中心 artwork 請求**可放棄**，不得阻塞下一次 `currentTrack()`
- 測試：單一慢 artwork 請求進行期間，monitor 仍能在 H-04 deadline 內完成
- 斷言：無預取時 AE 上 artwork 在飛請求數 ≤ 1

AE 優先級佇列**留 P2**（與預取同時落地）——在 P1 就改造 Editor／Batch／monitor 三者共用的
關鍵路徑，是為尚不存在的負載付出風險（Codex 接受此判斷）。

---

## 4. 階段 P1 任務清單（每項帶 DoD）

### P1-0 `.visualEffect` 幾何 spike（**最先，先驗 API 後接資料**）

範圍擴充（Codex #13 採納）：不只驗公式，做一個**最小但可互動**的 harness——
5 張假封面、真實 view size、驗以下全部：
- `.visualEffect` 讀取的 geometry coordinate space 是否如預期
- 負 spacing ＋ `scrollTargetBehavior(.viewAligned)` 的實際吸附行為
- `safeAreaPadding` 在**首尾項**與**視窗 resize** 後是否仍能置中
- `zIndex` 與 3D transform 的實際疊放次序
- 鍵盤焦點能否落在捲動容器上
- macOS deployment target（14.0）下這些 API 是否全部可用

**DoD**：六項逐條記錄實測結果；通過後**刪除 spike**，不得讓臨時視圖變成第二套實作。
spike 失敗 → 停下重評估渲染方案（對齊 M1 的 AE spike 先例）。

### P1-1 `ArtworkMemoryCache`

`NSCache<NSString, NSImage>`，**明確配額**（Codex #5 採納）：`countLimit = 60`、
`totalCostLimit = 40MB`（cost ＝ 解碼後位元組估算）。與 P2 的磁碟配額（200 張／50MB）
是**兩套獨立上限**，不混談。

**DoD**：①命中不重複解碼 ②超過 countLimit 觸發驅逐 ③cost 累計正確。

### P1-2 `ArtworkService`（中心單張，無預取）

**職責**：`ArtworkProviding` 協議——查記憶體 → 未命中走 AE 取 raw data →
`CGImageSourceCreateThumbnailAtIndex` 解碼 ≤512px → 存記憶體 → 回 `NSImage`。

**有界與可取消（Codex #6 複審重提，採納）**：
- 每次 artwork 請求包在 `withThrowingTaskGroup` 的 timeout 競速中（上限 **2 秒**，
  留 1 秒餘裕給 H-04 的 3 秒預算）
- 中心改變 / 切專輯 → 取消尚未完成的舊請求
- 同一 persistentID 併發 miss 只發一次 AE（in-flight 去重，Codex #18 採納）

**DoD**：
- ①逾時回 nil 不崩 ②取消後不寫快取 ③同 ID 併發 miss 只觸發一次 AE
- ④解碼失敗回 nil 且不寫快取 ⑤縮圖 ≤512px
- ⑥**慢請求 deadline 測試**：注入一個 5 秒才回的 artwork 請求，斷言期間
  `NowPlayingMonitor.tick()` 仍能在 3 秒內完成 `currentTrack()`
- ⑦斷言無預取時 in-flight artwork ≤ 1

### P1-3 `CoverFlowViewModel`

**狀態模型（Codex #8 採納——不照搬 Batch 的單一 sessionID）**：
Cover Flow 的競態形狀與 Batch **不同**（Batch 只有「舊專輯載入回寫新列表」；
Cover Flow 另有圖片晚回、同專輯重入、舊中心請求覆蓋新位置）。故分開三個守衛：

| 守衛 | 用途 |
|---|---|
| `albumGeneration` | 每次清單重建遞增；載入回寫前校驗 |
| per-item `artworkToken` | 每張封面的請求令牌；回寫前校驗 token 未過期 |
| `centerTrackID` | 自動居中的目標身分；用 persistentID 而非索引 |

**`.albumChanged` 的輸入來源（Codex #9 採納，用更小的解法）**：
**不重新讀 `currentTrack()`**——事件發布後再讀，可能拿到已切走的下一張專輯。
改為從事件攜帶的 `albumKey` 解析出 (artist, album) 直接查 `albumTracks(artist:album:)`。
（`albumKey` 格式為 `artist\u{1}album`，`NowPlayingMonitor` 既有格式，無需改事件型別。）

**H-05 的狀態語義（Codex #10／#11 採納）**：
單一 `userScrolled: Bool` 不足，拆為：
- `userHasOverriddenAutoCenter: Bool` —— 使用者拖曳或鍵盤步進後設 true
- **「真實切歌」判定＝`persistentID` 變更**（不是收到 `.trackChanged` 就算——
  `forceRefresh()` 也會對同一曲發出該事件）。只有 ID 真的變了才清除 override 並居中。
- **`albumGeneration` 變更時明確重置** override（切專輯應回到新專輯當前曲，
  這是 H-06 與「目前播放曲」的直覺）
- **區分 programmatic scroll 與 user scroll**：程式化居中期間設抑制旗標，
  避免動畫產生的 scroll callback 把 override 誤設回 true

**DoD**（每條對應一個測試）：
- ①空列表才載入 ②切歌居中 ③手動滑走後不搶控制
- ④**同曲 forceRefresh 不解除 override**（區別於真實切歌）
- ⑤**切專輯重置 override 並居中新專輯當前曲**
- ⑥程式化居中不把 override 設回 true
- ⑦`.albumChanged` 用事件的 albumKey 查詢，不讀 currentTrack（注入替身斷言呼叫參數）
- ⑧過期 albumGeneration 不回寫 ⑨過期 artworkToken 不回寫
- ⑩快速連續切歌只居中到最後一首
- 覆蓋率：`CoverFlowViewModel` ≥ 85%

### P1-4 `CoverFlowView` ＋ `CoverFlowItem`

渲染參數同上游 §4.8（負 spacing −0.42×itemWidth、±55° rotation3DEffect、
perspective 0.55、scale 1.0→0.82、zIndex −|d|、viewAligned 吸附、
safeAreaPadding (viewWidth−itemWidth)/2、倒影 scaleEffect(y:−1) ＋ LinearGradient(0.45→0) mask ＋ drawingGroup）。

**驗收口徑（我方勝方裁定）**：H-02 的 3D 五要素、倒影漸變屬**視覺觀感**，
按上游 §1「視覺盡可能貼近（用戶接受非像素級）」與 A-01／B-20 先例，
**M7 只驗幾何參數確實落實，觀感待 M8 並排目視**。不做像素級截圖比對——
與已簽署的驗收口徑衝突，且會產生因 SwiftUI 版本／顯示器差異而失敗的脆弱測試。

**但補上可自動驗證的行為底線（Codex #12 採納部分）**：
- H-03：中心標籤有 accessibility label，格式 `ARTIST // TITLE`
- H-08：無封面佔位與封面**同尺寸固定 frame**（斷言佈局不跳動）
- H-09：鍵盤 handler 的焦點範圍限於捲動容器（窗口內，無全域監聽——紀律同 memory）
- H-10：tap 與 double tap **不呼叫任何播控 API**（以 mock 斷言零呼叫）
- H-11：`sortedForDisplay()` 對 **duplicate disc/track number** 的穩定性（AE 序 fallback）

### P1-5 AppModel 接線（Codex #15 採納：列獨立 DoD，不只「三個 tab 切換正常」）

**DoD**：
- ①Cover Flow VM 只建立一次、列表只載入一次（切離再切回不重複載入）
- ②切離 tab 取消在飛的 artwork 請求，但**不取消**播放事件訂閱
- ③`AppModel` 停止時取消 Cover Flow 的所有 Task
- ④Cover Flow 不可見時收到 `.albumChanged` → 清空但不載入（對齊 Batch 的 C-17）
- ⑤Settings 改 token 不重建 music client 或快取
- ⑥`RootView:118-119` 的 placeholder 換掉，`placeholder(_:)` helper 刪除
- ⑦Editor／Batch 既有 UITests 全綠（回歸）

---

## 5. 階段 P2 任務清單（磁碟快取與預取）

### P2-1 `ArtworkDiskCache`

**檔名（Codex #1 採納）**：**完整 SHA-256（64 hex）**，不用前綴——前綴長度未定義會有碰撞，
且碰撞時會回傳**另一首歌的封面**。metadata 另存 `hash → persistentID`，讀取時驗證，
不匹配即視為 miss 並刪除。

**metadata 契約（Codex #2 採納）**：
- 格式：JSON；**臨時檔 ＋ 原子替換**（與 artwork 檔同等對待）
- 解析失敗 → 刪除 metadata，掃描 artwork 目錄**重建**（以檔案 attributes 作 fallback）
- 明定處理：orphan artwork（有檔無 metadata）、metadata 指向不存在的檔、
  異常值（未來時間、負大小）

**LRU 序（Codex #3 採納）**：
用**單調遞增的 access sequence**，不依賴 wall-clock（時鐘會倒退、同毫秒並列無法穩定排序）。
`ArtworkDiskCache` 為 **actor**，串行化「讀取更新 + eviction」，避免併發交錯。

**原子寫入（Codex #4 採納）**：
- temp 檔建在**同一 cache directory 內**（避免跨檔案系統 rename 失敗）
- **首次寫入用 move、覆寫用 `replaceItemAt`**（兩條路徑行為不同，各自測）
- 啟動時清掉殘留 `.tmp`

**配額**：磁碟 **200 張／50MB**（取先達者），與 P1 的記憶體配額獨立。

**DoD**（Codex #18 採納，補併發與重啟）：
- 全部用臨時目錄（`temporaryDirectory` ＋ UUID），**禁碰真實 Caches**
- ①命中磁碟回填記憶體 ②LRU 按張數淘汰 ③LRU 按位元組淘汰
- ④首次寫入 vs 覆寫**兩條路徑** ⑤損毀檔 → 刪除並回 nil
- ⑥**hash 碰撞驗證**：metadata 的 persistentID 不匹配 → 視為 miss
- ⑦**同 ID 併發 miss 只產生一次寫入** ⑧多 ID 併發寫入
- ⑨**write 與 eviction 交錯** ⑩**metadata 損毀後重啟重建** ⑪orphan artwork 處理
- 覆蓋率：`Services/Artwork/` ≥ 90%

### P2-2 預取（低優先級、可取消）

**策略（Codex #7 修改採納）**：**中心同步載入優先，兩側低優先級預取**，
`±5` 是**上限而非固定批次**；依滑動方向增量擴展，允許取消／重排。
不把 `0,+1,-1,…` 當成所有情境的充分策略。

**事件矩陣（Codex #8 採納）**：

| 事件 | 行為 |
|---|---|
| 首次列表完成 | 中心曲同步 ＋ 鄰近低優先級預取 |
| 中心改變 | 增量預取新中心兩側 |
| 切專輯／切 tab | **取消舊批次** |
| cache hit | 不排 AE |
| 同 ID in-flight | 共享 Task |
| 預取失敗 | 可重試但要 backoff，避免每次 render 重打 AE |

**AE 公平性**：此時落地優先級調度——monitor 請求優先於 artwork 預取。

**DoD**：①預取可取消 ②切專輯取消舊批次 ③cache hit 不排 AE ④同 ID 共享 Task
⑤失敗 backoff ⑥**多個慢 artwork 請求期間 monitor 仍能在 deadline 內完成**

---

## 6. 驗收標準

| # | 標準 | 判定方式 |
|---|---|---|
| V1 | 單元測試全綠且數量不減 | `xcodebuild test -only-testing:AzathothsWhisperTests` ≥ 171 ＋ 新增 |
| V2 | 覆蓋率閘門 | `./Scripts/coverage_gate.sh <xcresult>` ≥ 80%；另列 `Services/Artwork/` 實測值 |
| V3 | H 段無 ⬜（目視項標「M8 並排對照」並註明理由） | ACCEPTANCE 複查 |
| V4 | 快取單測不碰真實檔案系統 | 全部走臨時目錄，跑完清理 |
| V5 | Editor／Batch 回歸 | 既有用例全綠 |
| V6 | **monitor deadline 不被 artwork 阻塞** | 慢請求測試（P1-2 DoD ⑥、P2-2 DoD ⑥） |
| V7 | 非 live UITests 全綠 | **前提：automation mode 授權可用**（M6 收尾時受阻，見該 Plan 附錄） |

## 7. 測試策略

- **TDD 強制**：每項先 RED 後 GREEN（全局 CLAUDE.md §9）
- 快取與服務層完全離線單測；View 層走 UITests ＋ M8 目視
- **真機驗證留 M8**：真實 Music 取圖、滑動效能、3D 觀感

## 8. 影響面

| 檔案 | 性質 | 風險 |
|---|---|---|
| `Services/Artwork/*`（新增） | 新增 | 低——無既有呼叫點 |
| `Features/CoverFlow/*`（新增） | 新增 | 低 |
| `Features/Shell/RootView.swift` | 替換 placeholder ＋ 刪 helper | 低——UITests 覆蓋 |
| `App/AppModel.swift` | 新增 VM 持有、事件分發、tab 生命週期、取消 | **中**——剛重構過 busy 語義，勿破壞 |
| `ACCEPTANCE.md` | H 段狀態 | 低 |

**不觸碰**：`Services/Lyrics`、`Services/Config`、`Features/Editor`、`Features/Batch`、
`MusicAppleEventsClient`（P1 不改，P2 才加優先級調度）、Python 舊版。

## 9. 風險與回退

| 風險 | 徵兆 | 對策 |
|---|---|---|
| artwork 阻塞 monitor deadline | 切歌偵測變慢、H-04 失敗 | 有界 timeout（2s）＋ 可取消；慢請求 deadline 測試把關 |
| `.visualEffect` API 行為不符 | 3D 觀感不對 | P1-0 spike 先驗六項；失敗即停下重評估 |
| 事件世代模型過複雜 | 測試難寫、行為難推理 | 三個守衛各有單一職責且各有測試；不合併 |
| 磁碟快取併發損毀 | 半寫檔／metadata 不一致 | actor 串行化 ＋ 原子替換 ＋ 啟動重建 |
| 大專輯記憶體 | 佔用飆升 | `LazyHStack` 僅渲染可見項；NSCache 配額明確 |

**回退單位**：P1／P2 各自獨立 commit；五個新檔互不依賴既有代碼，可單獨回退；
`RootView` 的 placeholder 在 git 歷史中可還原。

## 10. 執行順序

**階段 P1**：P1-0 spike → P1-1 記憶體快取 → P1-2 服務（含 timeout/取消）→
P1-3 ViewModel（三守衛）→ P1-4 View → P1-5 接線 → 全量測試 → `/simcodex` → commit

**階段 P2**：P2-1 磁碟快取（actor）→ P2-2 預取（低優先級可取消）→
全量測試 → `/simcodex` → commit

## 附錄：Codex 對抗評審辯論記錄（2026-08-23）

### 採納（13 條）

| # | 意見 | 處置 |
|---|---|---|
| 1 | SHA256「前綴」未定義長度 → 碰撞會回傳**另一首歌的封面** | 改用完整 64 hex ＋ metadata 存 hash→persistentID 驗證 |
| 2 | metadata 的格式／原子性／損毀恢復未規定 | 定 JSON ＋ 原子替換 ＋ 解析失敗掃描重建 ＋ orphan／異常值處理 |
| 3 | LRU 依賴 wall-clock 會倒退、同毫秒並列無法排序 | 改用單調遞增 access sequence；cache 設為 actor 串行化 |
| 4 | `replaceItemAt` 對「destination 不存在」與「已存在」行為不同 | 首次 move／覆寫 replace，temp 建在同目錄，啟動清殘留 |
| 5 | 記憶體與磁碟配額混談 | 分開明定：memory countLimit 60／40MB；disk 200 張／50MB |
| 6 | **AE 單一 FIFO 會餓死 monitor**——串行化是互斥不是公平調度 | 問題全採納。解法分階段（見駁回 2 的辯論） |
| 8 | 單一 sessionID 不足——Cover Flow 競態形狀與 Batch 不同 | 拆為 `albumGeneration` ＋ per-item `artworkToken` ＋ `centerTrackID` |
| 10 | `userScrolled` 單一 Bool 語義有四個漏洞 | 拆為 `userHasOverriddenAutoCenter` ＋ 真實切歌判定 ＋ album 變更重置 ＋ 區分程式化 scroll |
| 12 | 部分 DoD 未真正覆蓋 | 補 H-03 label／H-08 固定 frame／H-09 焦點／H-10 零播控呼叫／H-11 duplicate 穩定性（H-02 見駁回 1） |
| 13 | spike 範圍太窄 | 擴為可互動的 5 張假封面 harness，驗六項；通過後刪除，不留第二套實作 |
| 14 | 「不需要第三個 BusySource」只對了一半 | 保留結論，但刪掉「壅塞再評估」的 fallback，改為明確設計約束 |
| 15 | AppModel 接線風險低估 | 列 7 條獨立 DoD（生命週期、取消、重複載入、不可見時行為…） |
| 16 | 一次引入全部機制，失敗難定位 | **分兩階段**：P1 記憶體＋中心單張＋無預取；P2 磁碟 LRU＋預取 |

### 修改採納（3 條）

| # | 主張 | 我方修改 |
|---|---|---|
| 7 | `±5` 固定批次沒有依 view width／滑動方向推導 | 改為「中心同步、兩側低優先級預取，±5 是上限而非固定批次」，依方向增量擴展 |
| 9 | `.albumChanged` 只帶 albumKey，VM 再讀 `currentTrack()` 可能拿到已切走的專輯 → 建議改事件型別帶完整 identity | **問題採納，解法更小**：不改事件型別（會波及 Editor／Batch），改為從 `albumKey`（格式 `artist\u{1}album`）解析出 (artist, album) 直接查詢 |
| 11 | `.trackChanged` 沒有 reason／generation，無法區分真實切歌與 forceRefresh → 建議拆分 monitor 事件 | **問題採納，解法更小**：不改 monitor（三方共用），改為 VM 比對 `persistentID`，只有 ID 變更才算真實切歌 |

### 駁回與辯論

**駁回 1｜#12 要求 H-02 建立可重現的截圖／尺寸／視口基準 —— 我方勝**

理由：上游 §1 已裁定驗收口徑「視覺盡可能貼近（用戶接受非像素級——SwiftUI 重畫必然存在渲染差異）」，
且 A-01（splash 時序）、B-20（hover 動畫）先例一致：參數 1:1 實作、觀感待 M8 並排目視。
3D 旋轉／透視／倒影屬同類；像素級比對既與已簽署口徑衝突，也會產生因 SwiftUI 版本／顯示器差異
而失敗的脆弱測試。**Codex 複審：「接受，不重提」**。其「補可自動驗證底線」的部分已全數採納。

**駁回 2｜#6 要求第一階段就改造 AE client 加優先級佇列 —— Codex 勝（部分）**

我方主張：採納 #16 分階段後，P1 無預取，AE 上最多 1 個 artwork 在飛，不存在 11 個排隊的情境；
在 P1 就改造 Editor／Batch／monitor 三者共用的關鍵路徑，是為尚不存在的負載付出風險。

**Codex 複審：接受延後優先級佇列，但重提一項——「in-flight ≤ 1」不等於「不阻塞 deadline」**：
即使只有一個 artwork 請求，只要它耗時超過 3 秒，後續 `currentTrack()` 仍排在它後面。
**該論證成立，我方採納**：P1 補上有界 timeout（2s）＋ 可取消 ＋ 慢請求 deadline 測試。

有輸有贏（13 採納／3 修改／1 條我方勝／1 條 Codex 勝）符合裁決有效性判準。

