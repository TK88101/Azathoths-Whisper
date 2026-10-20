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
- G3 不得持續疊住：對象行可見主字中，被畫面上其他可見字形（全行 glyphs＋opacity ≥ 0.35 的 ghosts；排除自己、自己的殘影副本、boxes）以字框面積蓋住 > 50% 者超過 10% 的連續時間 ≤ 0.5 s。修法：swoop alpha 改為飛行中不可見，配合上面的 leadIn。**實作值 `clamp01((p−0.45)/0.4)`、leadIn 0.59**（計劃原值 `(p−0.3)/0.5`、0.475 實測 G3 仍有 0.6 s 疊住，延到飛行六成才出現、此時已到 94% 位置）。不靠 forbiddenPairs（它有退回機制、也只管出場×退場兩兩）。
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

## 4. 實作評審（Codex，2026-10-20，6 條 P2、無 P1，全部採納）
| # | 問題 | 處置 |
|---|---|---|
| 1 | G3 只累加命中刻度、沒加末端一刻度，0.59 s 的遮擋可能量成 0.5 s | G2／G3 共用 `longestRun`（末段加一刻度）；G3 也改用 G2 的時刻表（開頭 1 s 每 0.05 s） |
| 2 | G3 對象字只取 glyphs，smoke 進場只有殘影、整段漏測 | 主字定義收成一處 `targets`：本體＋沒有同字本體在 0.5 字級內的煙霧副本群（合成透明度 ≥ 0.35），G2／G3 共用 |
| 3 | 「同字 0.5 字級內」把相鄰的同字（ll）當成自己的副本 | 副本排除只用在殘影層；字層只排除同字同位置（< 0.5 pt，讓位只改透明度） |
| 4 | G1 只走樂團表、漏曲風列；回退組合沒加效果 | 涵蓋改用全部 profile；五種效果也量回退組合 |
| 5 | G1 核心像素多了「接近字色」的篩選，等於在有利子集量 | 改為只看字形：主字單獨畫（不描邊、無光暈與圖層）與空畫面的差異內縮 1 px，效果改了字色也照量 |
| 6 | swoop 參數與計劃不符、簽字動畫改變未記 ACCEPTANCE | 計劃 §2 已同步實作值與理由；ACCEPTANCE 待使用者看改前改後短片後記錄（原定最後一步） |

## 5. 改量法後暴露的兩件事（2026-10-20）
- **G1 定格時句尾仍在淡入**：settled＝5.0 時最後一個字透明度 0.54，半透明像素被算進核心。核心改為只取完全顯示（opacity 1）的主字——依字的狀態、不依顏色。
- **G3 自己蓋住自己**：同一個字在「只有這一行」與「整個畫面」兩份 plan 裡位置差約 9 pt（swagger 的隨機擺動共用亂數流）。字層改為排除 0.5 字級內最近的那一個同字，其他同字照算。
- **crimsonVelvet 在 film（3.85）與 crimsonFog（4.20）未達標**（真問題）：兩背景的暈影 0.95 畫在字上（原型 lyrics-fx-preview.html:1206 也是），兩側的字被壓暗；舊量法的字色篩選把這些像素排除才有 4.92。實測：暈影移到字下 → 5.51／6.24；只拿掉顆粒 → 4.01／4.21。
  - 修法（/thecure 與 Codex 2 輪收斂）：**只有 film、crimsonFog 的暈影改畫在字下**（`FramePlan.underText`，在 back 之後、殘影與字之前，不套 shake／zoom）；顆粒、刮痕、閃爍留在字上；其他 11 個暈影背景照原型。不放寬量法、不再改色、不禁組合。
  - 辯論：全部 13 個暈影背景都移（我）→ Codex 勝（未不合格的已簽字畫面不動）；繪製順序（Codex 初版圖會畫回字上）→ 我勝；顆粒每格不同 → Codex 勝：這兩個背景 × 抽得到的所有配色 × 三個顆粒格（5.0／5.3／5.6）常駐測試。
  - 待使用者：看這兩個背景改前改後並排（crimsonVelvet＋另一個實際抽得到的配色），確認後記 ACCEPTANCE I-59（偏離原型）。

## 6. G3 取樣混疊與 swagger（2026-10-20，Codex 2 輪，待使用者決定範圍）
- 全量 1475 條唯一紅：Oasis／swagger／Oswald 第 6 行 G3 0.60 s（確定、重跑 4 次相同）。成因：同一行裡 slide 進場的字橫越已到位的鄰字，每對一瞬、輪流發生。
- 0.01 s 細取樣：最長連續 0.06 s、空隙 0.01–0.03 s → 0.1 s 粗取樣是**相位混疊**，會誤連也會漏判。以「0.01 s、< 0.1 s 空隙算連續」重量 swagger：Weezer 0.66、Oasis 0.56、Blur 0.52（Weezer／Blur 粗取樣只有 0.40，漏判）。
- 修法實驗（只量 swagger）：swagger 時長 0.2–0.35 → 最壞 0.50（卡線，且慢步調少 35%）；slide 改短距離水平 0.6 em → 最壞 0.38。
- Codex 結論（採納）：①G2／G3 全程 0.02 s 取樣，不用「只在粗取樣命中處細看」（粗取樣全沒命中的事件看不到）；②swagger 改用新模板 sidle（水平短距離），位移 0.6 em 太大（剛可見時距落點 0.34 em，相鄰窄字仍可被蓋過半），用 0.3 em 或依實際字寬設上限，並加相鄰字／反方向／窄字的直接測試；③G2 不套用「空隙算連續」（會改變 G2 的意思）；④改量法後全 enter 重跑，新失敗逐一修正／移出候選／使用者簽字例外，最後全量重取綠。
- 使用者 2026-10-20 決定：現在徹底做（接受測試變慢、可能牽出更多進場）。

## 7. 0.02 s 量法實作與牽出的修正（2026-10-20）
- 量法：G2／G3 全程 0.02 s（`ReadabilityAudit.step`，以序號乘刻度）；G3 命中之間 < 0.1 s 的空隙接成一段（`fusionGap`），G2 不接；段長＝段首到最後命中＋兩刻度。紅燈：`shortGapsBridgeIntoOneRun`、`samplesAreEvenlySpacedAtTheFineStep` 2 條 5 斷言（空殼實作）。新閘門 G2＋G3 一輪 1748 s。
- 新量法查出 10 份 G3 不合格、G2 0 份：swagger 4、slide 元件 4、swoop 元件 1、smoke 1。
  - smoke（Type O Negative）是**量測誤判**：上一行倒影（scaleY −1、0.04）被併進下一行的煙霧群，群位置取了倒影、字框又沒處理翻轉而往上翻。修：倒影不算煙霧、字框取 |scaleY|（`reflectionsAreNotSmokeAndFlippedBoxesStayInPlace`）。
  - swagger、slide 元件：滑入的字橫越同一行已到位的鄰字。修：新模板 `sidle`（水平 0.3 em、alpha min(1,2p)，看得見時距落點約 0.17 em），swagger 與 slide 元件改用它；`slide` 模板與 kick／punch／skank（合格）不動。sidle 的測試與實作同一步寫，未先單獨跑紅燈。
  - swoop 元件：延後 swoop 模板可見時點（45%→55／60／70／75%）幾乎無效；逐一拿掉混入的模板找出元兇是 **fling**（衝過頭再彈回）。拿掉 fling 後該元件最壞 0.42 s；拿掉 orbit 反而變差。修：swoop 元件權重 swoop 3／orbit 1；fling 模板與 lash（0.46 s，合格）不動。
- 以上都偏離原型 composer.js（106、116、101 行），待使用者看改前改後後記 ACCEPTANCE。
- Codex 整體確認（b04a45b，無致命矛盾）：P1 基線測試只比對元件 ID，證明不了其他團沒被連帶改到 → 核實：逐字抽模板每次固定用一個亂數（GlyphPersonality.swift:91）、組合器不讀元件內權重，所以不連鎖；影響只限抽得到 swagger（7 團）、slide（28）、swoop（15）的配方，共 54 團中的 44 團，全部要在改前改後裡讓使用者看代表。P2 sidle 缺直接測試 → 補 `SidleReadabilityTests`（窄字、相鄰同字、12 種子、兩字型）；短句版新舊都綠（抓不到，作廢），換長句後新版綠、舊 slide 紅 3 份（swagger seed 8 兩字型、slide seed 4）。Codex 認為最容易出錯的下一步：給使用者看改前改後（在那之前不得併進 main）。
