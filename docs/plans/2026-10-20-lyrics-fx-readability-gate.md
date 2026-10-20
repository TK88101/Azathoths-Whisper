# 歌詞特效：讀得到的檢查（曲風覆蓋計劃 第一段）

## 0. 複述
使用者 2026-10-19／20：讀不到歌詞的效果不可（已拿掉 slam、禁止 condense＋cut、crimsonVelvet 重簽）。本段建立可機器驗證的「讀得到」閘門，之後所有新樣式都要過。使用者授權：計劃與 Codex 收斂後直接實作（2026-10-20）。

## 1. 事實（已核，探索性量測，臨時測試未 commit）
- 範圍：樂團表 61 團＋曲風兩列，每個 profile 6 個連續種子（avoiding 鏈），共 342 份配方；預覽固定歌詞（英文 60 s）；每行從 start＋0.2 s 到 revealEnd，每 0.1 s 取一幀 `LyricsFXFrame.plan`（純資料，不繪製）。字框用 CoreText 實際字寬（advance）× 0.8 字高，左右內縮 8%。
- 「可見字」＝opacity ≥ 0.35。
- **唱歌中全空白最長**：p50 0、p90 0.2 s、max 0.5 s；> 0.3 s 的配方 29 份，全部是出場 condense（15）或 smoke（14），退場無關（scatter／fade／dissolve／cut／fall 都有）。原因推測：這兩種出場從 opacity 0 慢慢淡入（condense 0.54–1.02 s、smoke 同級；P12 已縮短 40%），首字要到 ~0.4–0.5 s 才達 0.35。
- **嚴重重疊**（一個字被另一個可見字蓋住 > 50%）影響 > 10% 可見字的連續時間：p50 0.1 s、p90 0.3 s、max 0.6 s；> 0.5 s 只有 1 份（My Chemical Romance：swoop＋sink＋Shadows Into Light）。畫出最壞幀確認：是 swoop「字飛入時從別的字上方經過」的暫態，不是 slam 那種疊住不動。
- 既有：`LyricsFXContrastTests`（主字對比，實際繪製，Bebas、無效果，所有抽得到的（背景, 配色）≥ 4.5，crimsonVelvet 例外已拿掉）、`LongLineFitTests`（長句放得下）。

## 2. 設計（Codex 2 輪收斂，2026-10-20）
- 量測單位：**對象行的主字**＝只含那一行的時間軸做出的 plan glyphs（前後行不算）。本番不加行 ID。
- G2 唱歌中不得空白：對象行 [start, revealEnd] 內，主字無任何 opacity ≥ 0.35 的連續時間＋取樣刻度 ≤ 0.3 s（開頭 1 s 每 0.05 s、之後每 0.1 s）。修法：`EnterTemplate.visibleLeadIn`（alpha 達 0.35 的進度：condense √0.35≈0.592、smoke 0.35、swoop 0.475、其他 0），`enterProgress = leadIn + (1−leadIn)×(t−start)/duration`；所有派生（splitOffset 等）都讀同一個 progress。
- G3 不得持續疊住：對象行可見主字中，被畫面上其他可見字形（全行 glyphs＋opacity ≥ 0.35 的 ghosts；排除自己、自己的殘影副本、boxes）以字框面積蓋住 > 50% 者超過 10% 的連續時間 ≤ 0.5 s。修法：swoop alpha 改 `clamp01((p−0.3)/0.5)`（飛行中不可見），配合上面的 leadIn。不靠 forbiddenPairs（它有退回機制、也只管出場×退場兩兩）。
- G1 定常對比：同一 plan、同一時刻，分別畫「全部」「去掉主字」「去掉全部字（glyphs／ghosts／boxes）」；主字 core pixel＝全部 vs 去主字差異大的畫素；對比＝全部畫面該畫素 vs 純背景畫面同座標，5 百分位 ≥ 4.5。範圍：抽得到的（背景, 配色）× fx 無，及加 glow／neonstroke／rgbsplit／misreg／reflect 各一。
- 涵蓋：全 profile × 6 連續種子 × 英文預覽／自編日文／自編長句。
- 順序：量測函式 → G2 修正 → G3 修正 → G1 改寫 → 全量單元＋Codex review → 使用者看 condense／smoke／swoop 改前改後短片確認（ACCEPTANCE 記錄，確認後才定案）。

## 3. 辯論紀錄
| 論點 | 結果 |
|---|---|
| G2 用「提前開始淡入」 | Codex 勝：一行要到 start 才畫（ComposedStyle.swift:148），提前無效；改 leadIn 進度 |
| 量全畫面任何字 | Codex 勝：前一行讀得到不代表新一行讀得到，改量對象行主字 |
| G3 用 forbiddenPairs | Codex 勝：有退回機制、只管兩兩；改修 swoop 本身 |
| G1 平均色、只消 glyphs | Codex 勝：ghosts／boxes 留在「背景」裡、平均會掩蓋局部讀不到；改局部畫素 |
| swoop 需要 leadIn | Codex R2 補：否則 G2 破 |
| 改簽字動畫 | 可以先做，實機前後並排給使用者確認才定案 |
