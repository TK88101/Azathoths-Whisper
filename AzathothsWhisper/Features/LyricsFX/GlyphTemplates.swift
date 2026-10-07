import CoreGraphics
import Foundation

/// 模板的輸入（原型 `c`）：`angle`／`bend` 整詞共用（一詞一個飛入方向），`dir`／`phase` 逐字
struct GlyphContext: Sendable {
    let em: CGFloat
    let width: CGFloat
    let height: CGFloat
    /// 飛入的起點半徑（原型 `R`＝max(W,H)×0.55）
    let radius: CGFloat
    let dir: CGFloat
    /// 字在列的左半（−1）或右半（+1）
    let side: CGFloat
    let phase: Double
    let angle: Double
    let bend: Double
}

/// 一段模板的輸出；三段（進場、停留、退場）以 `combined(with:)` 合成：位移與旋轉相加、縮放與透明度相乘
struct GlyphTransform: Equatable, Sendable {
    static let identity = GlyphTransform()

    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var rotation: CGFloat = 0
    var scale: CGFloat = 1
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var alpha: Double = 1
    /// 殘影強度 0…1（原型的 `blur`，畫成數份低透明位移副本，不是濾鏡）
    var ghost: Double = 0
    /// 冰屑強度 0…1（字周圍的小點）
    var specks: Double = 0
    /// 影印負片：字畫成底色、外圍填一塊前景色
    var negative = false

    func combined(with other: GlyphTransform) -> GlyphTransform {
        GlyphTransform(
            dx: dx + other.dx, dy: dy + other.dy, rotation: rotation + other.rotation,
            scale: scale * other.scale, scaleX: scaleX * other.scaleX, scaleY: scaleY * other.scaleY,
            alpha: alpha * other.alpha, ghost: max(ghost, other.ghost), specks: max(specks, other.specks),
            negative: negative || other.negative
        )
    }
}

/// 緩動（原型 html:164-169）
enum FXEasing {
    static func clamp01(_ value: Double) -> Double { min(max(value, 0), 1) }
    static func outCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    static func inCubic(_ t: Double) -> Double { t * t * t }
    static func outExpo(_ t: Double) -> Double { t >= 1 ? 1 : 1 - pow(2, -10 * t) }
    static func outBack(_ t: Double) -> Double {
        let overshoot = 1.7
        return 1 + (overshoot + 1) * pow(t - 1, 3) + overshoot * pow(t - 1, 2)
    }
}

/// 進場模板（B1 兩個家族用到的子集，原型 html:202-235）。`progress` 0→1，1＝落定（恆等）
enum EnterTemplate: String, CaseIterable, Sendable {
    case fadeUp, grow, slam, condense, negative, fling, slant, swoop, orbit, smoke, rise

    func transform(progress p: Double, context c: GlyphContext) -> GlyphTransform {
        let em = Double(c.em)
        switch self {
        case .fadeUp:
            return GlyphTransform(dy: CGFloat((1 - FXEasing.outCubic(p)) * em * 0.5), alpha: p)
        case .grow:
            return GlyphTransform(scale: CGFloat(0.2 + 0.8 * FXEasing.outExpo(p)), alpha: p)
        case .slam:
            // 彈片：從畫面邊緣加速直線砸入，硬著陸（無回彈、無柔化）
            let u = 1 - pow(p, 2.2)
            return GlyphTransform(
                dx: CGFloat(cos(c.angle) * Double(c.radius) * 1.2 * u), dy: CGFloat(sin(c.angle) * Double(c.radius) * 1.2 * u),
                rotation: CGFloat(u) * c.dir * 0.8, alpha: p < 0.1 ? p * 10 : 1
            )
        case .condense:
            return GlyphTransform(alpha: p * p, specks: 1 - p)
        case .negative:
            return GlyphTransform(negative: p < 0.3)
        case .fling:
            let u = 1 - FXEasing.outBack(p)
            return GlyphTransform(
                dx: CGFloat(cos(c.angle) * Double(c.radius) * u), dy: CGFloat(sin(c.angle) * Double(c.radius) * u),
                rotation: CGFloat(u) * c.dir * 0.5, alpha: min(1, p * 3)
            )
        case .slant:
            let u = 1 - FXEasing.outCubic(p)
            return GlyphTransform(dx: CGFloat(u * em * 0.8) * c.dir, rotation: CGFloat(u * 0.9) * c.dir, alpha: p)
        case .swoop:
            // 從隨機方向沿一條經過控制點的弧線飛入
            let e = FXEasing.outCubic(p), u = 1 - e
            let radius = Double(c.radius)
            let start = (x: cos(c.angle) * radius, y: sin(c.angle) * radius)
            let control = (x: cos(c.angle + c.bend) * radius * 0.55, y: sin(c.angle + c.bend) * radius * 0.55)
            return GlyphTransform(
                dx: CGFloat(u * u * start.x + 2 * u * e * control.x), dy: CGFloat(u * u * start.y + 2 * u * e * control.y),
                rotation: CGFloat(u * 0.9) * c.dir, alpha: min(1, p * 2.5)
            )
        case .orbit:
            let u = 1 - FXEasing.outCubic(p)
            let angle = c.angle + u * 9.4
            let radius = u * em * 4
            return GlyphTransform(dx: CGFloat(cos(angle) * radius), dy: CGFloat(sin(angle) * radius), rotation: CGFloat(u * 2) * c.dir, alpha: p)
        case .smoke:
            return GlyphTransform(dy: CGFloat((1 - FXEasing.outCubic(p)) * em * 0.2), alpha: p, ghost: 1 - p)
        case .rise:
            // 原型組合模式不畫 glow（styleFromRecipe 的 paint 不讀它，html:1034-1046）
            return GlyphTransform(dy: CGFloat((1 - FXEasing.outCubic(p)) * em * 1.2), alpha: p)
        }
    }
}

/// 停留模板（原型 html:242-251）：`time` 是絕對秒數
enum HoldTemplate: String, CaseIterable, Sendable {
    case still, twitch, drift, float, breathe

    func transform(time t: Double, context c: GlyphContext) -> GlyphTransform {
        let em = Double(c.em)
        switch self {
        case .still:
            return .identity
        case .twitch:
            let k = Int((t * 3 + c.phase).rounded(.down))
            guard k.isMultiple(of: 5) else { return .identity }
            return GlyphTransform(dx: CGFloat((k.isMultiple(of: 2) ? -1 : 1) * em * 0.08), rotation: 0.1)
        case .drift:
            return GlyphTransform(dx: CGFloat(sin(t * 0.5 + c.phase) * em * 0.12), dy: CGFloat(cos(t * 0.4 + c.phase) * em * 0.08))
        case .float:
            return GlyphTransform(dy: CGFloat(sin(t * 0.9 + c.phase) * em * 0.12), rotation: CGFloat(sin(t * 0.7 + c.phase) * 0.05))
        case .breathe:
            return GlyphTransform(scale: CGFloat(1 + 0.04 * sin(t * 4.2 + c.phase)))
        }
    }
}

/// 退場模板（原型 html:237-240）。`progress` 0→1
enum ExitTemplate: String, CaseIterable, Sendable {
    case cut, scatter, fade, dissolve

    func transform(progress x: Double, context c: GlyphContext) -> GlyphTransform {
        switch self {
        case .cut: return GlyphTransform(alpha: 0)
        case .scatter: return GlyphTransform(alpha: (1 - x) * (1 - x))
        case .fade: return GlyphTransform(alpha: 1 - x)
        case .dissolve: return GlyphTransform(alpha: 1 - x, specks: x)
        }
    }
}
