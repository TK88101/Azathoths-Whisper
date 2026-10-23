import Foundation

/// 組合器的六個槽位（母計劃 §2.10）
enum FXSlot: String, CaseIterable, Sendable {
    case font, backdrop, enter, exit, fx, palette
}

/// 背景（B1 子集＋B2 批 1；原型 `styleFromRecipe.draw`，html:1004-1031）
enum BackdropKind: String, Sendable {
    case void, film, snow, ash, crimsonFog, shafts
    case ampGlow, embers, halftone, haze, paper, prism, smokeHaze, spot, stars, sunset, tapeLeak
    /// B2 批 2（龐克系）。flat＝只有配色的底色，什麼都不畫
    case flat, xerox, gig, checker, bokeh, skyGrad
    /// B2 批 3（Nu-metal）
    case scan, grid
    /// B2 批 4（emo 群）：bluehour＝低處冷藍微光＋左上一點暖光（雨絲 rain 2026-10-14 使用者在 T7 撤掉）
    case bluehour
    /// ⑥a J-Pop：sparkle＝淡天藍漸層＋閃爍四芒星（きらきら）；cityNeon＝粉紅漸層＋霓虹橫線＋半個夕陽（シティポップ）
    case sparkle, cityNeon

    /// 這個背景要配暗底還是亮底的配色（nil＝都可以）；組合器在背景之後抽配色時先濾成相容者（B2 計劃 §7.3）。
    /// sunset、shafts 會把整面塗成淺色／深色漸層，等於自帶底色（T3 對比測試抓到：配錯邊時字幾乎看不見）
    var tone: BackdropTone? {
        switch self {
        case .ampGlow, .spot, .smokeHaze, .prism, .stars, .shafts, .gig, .bokeh, .bluehour, .cityNeon: .dark
        case .halftone, .sunset, .sparkle: .light
        case .void, .film, .snow, .ash, .crimsonFog, .embers, .haze, .paper, .tapeLeak, .flat, .xerox, .checker, .skyGrad, .scan, .grid: nil
        }
    }
}

enum BackdropTone: Sendable {
    case dark, light

    func accepts(_ palette: FXPalette) -> Bool { palette.isLight == (self == .light) }
}

/// 效果（B1 子集＋B2 批 1）：不含依サビ或關鍵字觸發者（B1 計劃 §3.8）。
/// bob／wobble／flicker 是停留時的小動作（換停留模板）；glow／neonstroke 是整層的光暈與描邊；thump 是逐詞的整屏縮放
enum FXEffect: String, Sendable {
    case none, shake, misreg, breathe
    case glow, neonstroke, reflect, thump, bob, wobble, flicker
    /// B2 批 2：speedlines＝行首的速度線；ransom＝每個字墊一張歪斜的色紙（勒索信；不叫 paper，那是報紙背景的 id）；jitter／tilt 是停留時的小動作
    case speedlines, ransom, jitter, tilt
    /// B2 批 3：進場前半段字的左右各一份紅、藍副本（RGB 分離）
    case rgbsplit
    /// B2 批 4：字停住後往下拖出 `ComposedStyle.weepCopies` 份漸淡的副本（墨水往下暈開）
    case weep
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
