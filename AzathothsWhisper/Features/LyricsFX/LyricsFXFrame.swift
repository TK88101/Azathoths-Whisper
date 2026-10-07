import CoreGraphics
import Foundation

/// 動態程度：`reduced`＝系統「減少動態效果」，無淡入淡出、無位移（母計劃 §2.6 mono 列；A2 計劃 §3.5）
enum LyricsFXMotion: Sendable {
    case full, reduced
}

enum GlyphWeight: Sendable, Hashable {
    case regular, medium, semibold, bold
}

/// 一枚字型的不可變描述（B1 計劃 §3.1）。`weight` 只給可變字重字型（Space Grotesk）；靜態字型為 nil
struct FontFace: Hashable, Sendable {
    let id: String
    /// CoreText family 名
    let family: String
    let weight: GlyphWeight?
    var italic = false
    /// 原型的 `upper`：整行轉大寫顯示
    var uppercase = false

    static let displayRegular = FontFace(id: "display-regular", family: "Space Grotesk", weight: .regular)
    static let displayMedium = FontFace(id: "display-medium", family: "Space Grotesk", weight: .medium)
}

/// 每份配色恰四色（bg／fg／acc／dim）；繪製指令只帶槽位（分組鍵離散，B1 計劃 §3.2）。
/// `black`／`white` 是與配色無關的固定色（影印錯位的陰影與高光，原型 html:1044）
enum ColorSlot: Sendable, Hashable, CaseIterable {
    case bg, fg, acc, dim, black, white
}

struct RGB: Equatable, Sendable {
    let red, green, blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }
}

struct FXPalette: Equatable, Sendable {
    let bg, fg, acc, dim: RGB

    /// mono：`Theme.background`／`Theme.coldWhite`／（同 fg）／`Theme.Gray.g500`
    static let mono = FXPalette(bg: RGB(hex: 0x000000), fg: RGB(hex: 0xE0E0E0), acc: RGB(hex: 0xE0E0E0), dim: RGB(hex: 0x6B7280))

    subscript(slot: ColorSlot) -> RGB {
        switch slot {
        case .bg: return bg
        case .fg: return fg
        case .acc: return acc
        case .dim: return dim
        case .black: return RGB(hex: 0x000000)
        case .white: return RGB(hex: 0xFFFFFF)
        }
    }
}

/// 一個字（grapheme）的繪製指令。`origin`＝該字行盒的 **top-leading**（未套變換）；旋轉與縮放以字形外框中心為軸（B1 計劃 §3.1）
struct GlyphDraw: Equatable, Sendable {
    let text: String
    let face: FontFace
    let fontSize: CGFloat
    let origin: CGPoint
    /// 弧度
    var rotation: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    let opacity: Double
    let color: ColorSlot

    init(text: String, face: FontFace, fontSize: CGFloat, origin: CGPoint, rotation: CGFloat = 0, scaleX: CGFloat = 1, scaleY: CGFloat = 1, opacity: Double, color: ColorSlot) {
        self.text = text
        self.face = face
        self.fontSize = fontSize
        self.origin = origin
        self.rotation = rotation
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.opacity = opacity
        self.color = color
    }
}

/// 一顆方形粒子（畫布座標；原型以 fillRect 畫）
struct Particle: Equatable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
}

/// 徑向光暈的一個色標
struct GlowStop: Equatable, Sendable {
    let location: CGFloat
    let color: RGB
    let opacity: Double
}

/// 字之外的整層繪製（有序；純資料）。顏色已解析成 RGB（背景元件有自己的固定色，原型 html:1004-1031）
enum LayerDraw: Equatable, Sendable {
    case fill(RGB, opacity: Double)
    case linearGradient(top: RGB, bottom: RGB)
    /// `center` 與 `radius` 以畫布寬為單位
    case radialGlow(center: CGPoint, radius: CGFloat, stops: [GlowStop])
    /// 垂直光柱：`xs` 是左緣（畫布寬為單位），中心最亮、兩側透明
    case lightShafts(xs: [CGFloat], width: CGFloat, color: RGB, opacity: Double)
    case particles([Particle], RGB, opacity: Double)
    case vignette(strength: Double)
    /// 平鋪噪點；`overlay`＝疊加混合（底片顆粒），否則一般混合
    case grain(opacity: Double, frame: Int, overlay: Bool)
    /// 底片刮痕：垂直細線（畫布座標 x）
    case scratches(xs: [CGFloat], opacity: Double)
}

/// 影印負片時字後的一塊色塊（原型 html:1040）
struct GlyphBox: Equatable, Sendable {
    let center: CGPoint
    let size: CGSize
    let rotation: CGFloat
    let color: ColorSlot
    let opacity: Double
}

/// 某一刻要畫的東西（母計劃 §2.7；B1 計劃 §3.1）。純資料；背景色＝`palette.bg`
struct FramePlan: Equatable, Sendable {
    static let empty = FramePlan(palette: .mono)

    let palette: FXPalette
    /// 字之下
    var back: [LayerDraw] = []
    /// 殘影與錯位副本，先於字畫
    var ghosts: [GlyphDraw] = []
    var boxes: [GlyphBox] = []
    /// 一個 grapheme 一筆；陣列順序＝painter order
    var glyphs: [GlyphDraw] = []
    /// 字之上
    var front: [LayerDraw] = []
    /// 整屏抖動（套在 back 與字上，不套 front；原型 html:1010）
    var shake: CGSize = .zero
}

/// 字寬量測：回傳 `text` 每個 grapheme 起點的 x 位移，末項＝總寬（共 `text.count + 1` 項）。
/// 依整列排版後取位移；連字、RTL、複雜文字不保證與整列 shaping 完全一致（A2 計劃 §3.4，Codex R2）
protocol TextMeasuring {
    func advances(of text: String, face: FontFace, fontSize: CGFloat) -> [CGFloat]
    /// 行盒 top 到基線的距離
    func ascent(face: FontFace, fontSize: CGFloat) -> CGFloat
}

extension TextMeasuring {
    func ascent(face: FontFace, fontSize: CGFloat) -> CGFloat {
        fontSize * 0.8
    }
}

/// 繪製引擎的純函數 plan（母計劃 §2.7；A2 計劃 §3.4）：同輸入同輸出、不按尺寸快取
enum LyricsFXFrame {
    /// 任一邊小於它就不畫字
    static let minimumSide: CGFloat = 120

    /// `recipe` 決定風格；「減少動態效果」一律走 mono（母計劃 §2.6 mono 列；B1 計劃 §3.1）
    static func plan(
        timeline: LyricsTimeline?, time: Double?, size: CGSize, motion: LyricsFXMotion, recipe: SessionRecipe = .mono, measurer: any TextMeasuring
    ) -> FramePlan {
        guard let timeline, let time, size.width >= minimumSide, size.height >= minimumSide else { return .empty }
        if motion == .full, case .composed(let composed) = recipe {
            if let style = ResolvedStyle(composed) {
                return ComposedStyle.plan(timeline: timeline, time: time, size: size, style: style, measurer: measurer)
            }
            // 配方的元件 id 不在目錄＝程式錯誤（目錄改版沒同步 schema 版本）；Release 退回 mono，不讓畫面空白
            assertionFailure("組合配方含目錄裡沒有的元件：\(composed.componentIDs.sorted())")
        }
        let moment = Moment(lines: timeline.lines, time: time, motion: motion, timing: Mono.timing)
        return Mono.plan(moment, time: time, size: size, motion: motion, measurer: measurer)
    }

    /// 無障礙用：此刻正在唱的那一行（A2 計劃 §3.4）
    static func currentLineText(timeline: LyricsTimeline?, time: Double?) -> String? {
        guard let timeline, let time else { return nil }
        return Moment(lines: timeline.lines, time: time, motion: .reduced, timing: Mono.timing).current?.text
    }

    /// 風格決定的時刻參數：退場多久、要不要（提前多久）出下一行預覽（B1 計劃 §3.4）
    struct MomentTiming: Sendable {
        let exit: Double
        /// nil＝不出預覽
        let previewLead: Double?
    }

    /// 此刻要畫哪幾行。`current` 一律尊重既有 `TimedLine.end`，不重推（間奏空檔由 builder 決定，Codex R1 #10）
    struct Moment {
        let current: TimedLine?
        /// 剛結束、還在淡出的行（只在 full）
        let exiting: TimedLine?
        /// 下一行預覽：有當前行時、或距它開始 ≤ `previewLead` 時才有
        let next: TimedLine?

        init(lines: [TimedLine], time: Double, motion: LyricsFXMotion, timing: MomentTiming) {
            let current = lines.first { $0.start <= time && time < $0.end && !Self.isBlank($0) }
            self.current = current
            exiting = motion == .full
                ? lines.last { $0.end <= time && time < $0.end + timing.exit && !Self.isBlank($0) && $0 != current }
                : nil
            guard let lead = timing.previewLead else {
                next = nil
                return
            }
            let upcoming = lines.first { $0.start > time && !Self.isBlank($0) }
            let isNear = upcoming.map { $0.start - time <= lead } ?? false
            next = (current != nil || isNear) ? upcoming : nil
        }

        private static func isBlank(_ line: TimedLine) -> Bool {
            line.text.allSatisfy(\.isWhitespace)
        }
    }
}

/// `TimelineView` 的排程（A2 計劃 §3.4 排程表，Codex R1 #1／R2）：
/// 不可見或沒在播 → 不建定時器（暫停時以當下位置畫一次靜態畫面）
enum LyricsFXSchedule: Sendable, Equatable {
    case none, animation, periodic

    static func resolve(isVisible: Bool, isRunning: Bool, reduceMotion: Bool) -> LyricsFXSchedule {
        guard isVisible, isRunning else { return .none }
        return reduceMotion ? .periodic : .animation
    }
}
