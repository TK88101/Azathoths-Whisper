import Foundation

/// 組合器的六個槽位（母計劃 §2.10）
enum FXSlot: String, CaseIterable, Sendable {
    case font, backdrop, enter, exit, fx, palette
}

/// 背景（B1 子集；原型 `styleFromRecipe.draw`，html:1004-1031）
enum BackdropKind: String, Sendable {
    case void, film, snow, ash, crimsonFog, shafts
}

/// 效果（B1 子集）：不含依サビ或關鍵字觸發者（B1 計劃 §3.8）
enum FXEffect: String, Sendable {
    case none, shake, misreg, breathe
}

struct EnterSpec: Sendable {
    let weights: [(EnterTemplate, Double)]
    let duration: ClosedRange<Double>
    /// 整詞同時出場（slam）
    var wordLevel = false
    /// 每個詞自己一個錨點與傾斜、允許重疊（slam 的彈片堆）
    var pile = false
    /// 到壽命硬切（slam）
    var expires = false
}

struct ExitSpec: Sendable {
    let weights: [(ExitTemplate, Double)]
    /// 秒；0＝行結束即消失
    let duration: Double
    /// 殘留：行結束後以低透明度停留再淡掉，不跑退場模板（原型 fade／dissolve，html:999）
    var trail = false
}

/// 一個元件：六槽之一的一個選項（B1 計劃 §2 概念表）
struct FXComponent: Sendable {
    enum Payload: Sendable {
        case font(FontFace)
        case backdrop(BackdropKind)
        case enter(EnterSpec)
        case exit(ExitSpec)
        case fx(FXEffect)
        case palette(FXPalette)
    }

    let id: String
    let slot: FXSlot
    /// 部分向量：只在宣告的軸上算距離
    let vector: [FXAxis: Double]
    /// 空＝任何曲風皆可
    let tags: Set<FXTag>
    /// 目標值該軸未知或低於門檻＝不合格
    let req: [FXAxis: Double]
    /// 目標值該軸已知且 ≥ 門檻＝不合格
    let forbid: [FXAxis: Double]
    let payload: Payload
}
