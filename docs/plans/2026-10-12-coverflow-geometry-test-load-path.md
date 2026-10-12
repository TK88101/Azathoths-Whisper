# Cover Flow 幾何測試改走正式 app 的路徑（2026-10-12）

## 複述
`CoverFlowStripRenderGeometryTests` 長期 7 斷言紅（`:234` 1、`:288` 6）。它在建立卡片條時就帶著中心值（初始值路徑，缺陷 3），條帶停在 #0。正式 app 自 2026-09-23 D2 掛載結構起不走這條路（`docs/plans/2026-09-23-coverflow-queue-drawer.md:158-159`）。使用者 2026-10-12：「改掉吧」。

## 目標與非目標
- 目標：中心正面測試與首尾吸附測試改走正式 app 的載入路徑——條帶先以空牌組、無中心建立，再於同一次更新放進牌組與中心（同 `CoverFlowViewModel.apply` 的 `deck = …` 後 `reconcileCenter`，`Features/CoverFlow/CoverFlowViewModel.swift:98-113`）。
- 非目標：不改產品碼；不修缺陷 3（產品不走）；不放寬任何斷言（門檻、參數陣列照舊）；運行時改中心測試（已綠）不動。

## 根因（已核）
- 2026-10-12 單獨跑：7 issues，EDGE(1…8) 全停在 #0，運行時路徑 3 條綠。
- 2026-10-11 晚的 11 issues 是暫時的「AX 讀到 0 個」，已自行恢復，不在本案。

## 設計
`Harness` 加「載入」模式：`items` 與 `centerID` 都是 `@State`，起始為空／nil，400 ms 後同一次指派放進 9 張卡與目標中心。中心正面測試（目標 #4）與首尾吸附測試（0、1、4、5、6、7、8）改用它。`renderedItems` 的「≥5 張且連兩次相同」條件在空牌組時不成立，不會在載入前提早返回。

## 測試／驗收
- 先紅：現況 7 issues（上面已記）。
- 綠：這個 suite 單獨跑 0 issues；全量單元不新增紅。
- 失效安全仍在：若產品載入路徑真的停錯位置，`:288` 會紅（那會是真缺陷，照實回報、不放寬）。

## 文件
ACCEPTANCE H-22 的「基線紅」描述與 H-02 的驗證欄補一句。

## 記錄（實作時回填）
- 改後單獨跑 `CoverFlowStripRenderGeometryTests`：**3 tests 全綠、0 issues**；EDGE(0…8) 與 RENDERED 的中心卡都是目標卡、長寬比 1.000。
- 改後全量單元（skip 同既有、`-enableCodeCoverage YES`）：1217 tests／148 suites，3 issues，**全部在 `CoverFlowSlideGeometryTests`**（`:153`、`:155`、`:203`），本案未碰這個檔。
  - 單獨重跑 2 次：都是 `:203`「沒有滑離播放卡」3 條（合成觸控板手勢之後中心沒變）。
  - 對照：**未改的 main（2e092f1）匯出副本、獨立 DerivedData** 單獨跑同一 suite，得到逐條相同的 3 條。→ 不是本案造成。
  - 2026-10-11 批 3 的全量裡這個 suite 是綠的，所以是環境在那之後變了；原因 TBD，未另案（同 `CoverFlowStripRenderGeometry` 昨晚暫時讀到 0 個 AX 元素的狀況，都屬於「上螢幕之後才量得到」的測試）。
