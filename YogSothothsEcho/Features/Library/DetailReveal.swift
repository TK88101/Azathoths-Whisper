import CoreGraphics
import Foundation

/// 詳情文字「從深處浮上來」（s6-61-round1-fixes.md v0.6 §3 F6；使用者 2026-10-22 逐格描述＋小樣 `s6-open-preview.html` 定稿）：
/// 遠處＝略小、模糊、略低；浮上來時變回原大小、變清楚、往上移到定位，到定位時完全清楚、固定
struct DetailRevealPose: Equatable {
    var opacity: Double
    var scale: CGFloat
    var blur: CGFloat
    var offsetY: CGFloat

    static let duration = 0.42
    static let depthScale: CGFloat = 0.90
    static let depthBlur: CGFloat = 10
    static let rise: CGFloat = 16
    /// 透明度在前 1/1.4 段就到 1（小樣同值）
    static let opacityLead = 1.4

    static let settled = DetailRevealPose(opacity: 1, scale: 1, blur: 0, offsetY: 0)
    static let deep = DetailRevealPose(opacity: 0, scale: depthScale, blur: depthBlur, offsetY: rise)

    /// `elapsed`＝文字段開始後的秒數，`delay`＝此元素的出場時刻；關閉倒放時 elapsed 往回走即可
    static func at(elapsed: Double, delay: Double) -> DetailRevealPose {
        let t = (elapsed - delay) / duration
        if t <= 0 { return deep }
        if t >= 1 { return settled }
        let q = 1 - pow(1 - t, 3)
        let left = CGFloat(1 - q)
        return DetailRevealPose(opacity: min(1, q * opacityLead), scale: 1 - (1 - depthScale) * left,
                                blur: depthBlur * left, offsetY: rise * left)
    }

    /// Reduce Motion：只淡入淡出，無縮放、模糊、位移
    static func reduced(progress: Double) -> DetailRevealPose {
        DetailRevealPose(opacity: min(1, max(0, progress)), scale: 1, blur: 0, offsetY: 0)
    }
}

/// 各元素的出場時刻：左欄專輯名 → 藝人 → Play；右欄（Disc 標題、曲目、尾端總長）每項晚 0.06 s。
/// 右欄序號封頂 16：再往下的列一定在畫面外，跟著第 16 列出場即可（看得到的列時序不變；長專輯返回時不必等看不見的列倒放）
struct DetailRevealSchedule: Equatable {
    static let title = 0.0
    static let artist = 0.32
    static let play = 0.62
    static let itemStart = 0.04
    static let itemStep = 0.06
    static let itemCap = 16

    let itemCount: Int

    func item(_ index: Int) -> Double { Self.itemStart + Double(min(index, Self.itemCap)) * Self.itemStep }

    /// 全部出完的時刻＝最後出場者＋一段浮現
    var end: Double { max(item(max(0, itemCount - 1)), Self.play) + DetailRevealPose.duration }
}

/// 詳情封面投影（v0.6 §3 F5；使用者 2026-10-22 在小樣自己調定「深色板往下錯開、濃淡 2.25、大小 1.8」）：
/// 封面後方同尺寸純黑板，往下錯開、模糊，只從下緣露出來＝光從上方照下、封面浮在背景上。以 444 pt 封面為準等比例
struct DetailCoverShadow: Equatable {
    let offsetY: CGFloat
    let blur: CGFloat
    let opacity: Double

    static let referenceSide: CGFloat = 444
    static let offsetAtReference: CGFloat = 18 * 1.8
    static let blurAtReference: CGFloat = 9 * 1.8

    /// 同一組值交給封套面的投影（詳情層：SleeveFace 的 background）
    var sleeve: SleeveShadow { SleeveShadow(radius: blur, offsetY: offsetY, opacity: opacity, innerOpacity: 0) }

    /// `progress`＝飛行進度：不透明度與錯開量隨之從 0 長到定值 `opacity`（由背景亮度決定：CR-022 E.4 取代 F5 依主題規則，
    /// 見 `DetailBackgroundModel.coverShadowOpacity`）
    init(coverSide: CGFloat, opacity full: Double, progress: Double) {
        let unit = coverSide / Self.referenceSide
        let p = min(1, max(0, progress))
        offsetY = Self.offsetAtReference * unit * CGFloat(p)
        blur = Self.blurAtReference * unit
        opacity = full * p
    }
}
