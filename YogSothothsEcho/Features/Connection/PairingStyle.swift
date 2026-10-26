import CoreGraphics
import SwiftUI

/// 連線頁的字型與色票（CR-033 方向 E；s6-5-pairing-redesign.md §4.2）。只在 Features/Connection 使用，不改全域樣式
enum PairingStyle {
    /// 左欄字色沿用詳情頁的 `DetailInk`（白字／深字 #16130F；同一語義一處定義）。選法不同：這裡是「對比＋遮罩」搜尋，
    /// 因為淺色主題的漸層也有深色區（例：aurora 淺色左側 #2D396D），不能只看主題
    struct Palette: Equatable {
        let primary: RGBColor
        let warning: RGBColor
        /// 文字區下的遮罩色（白字配黑、深字配白）
        let scrim: RGBColor

        /// 次要文字＝主字色以此不透明度疊在背景上（0.8：在 7 組漸層上加遮罩後仍達 4.5:1）
        static let secondaryAlpha = 0.80

        func secondary(over background: RGBColor) -> RGBColor { background.over(primary, alpha: Self.secondaryAlpha) }
    }

    static func palette(_ ink: DetailInk) -> Palette {
        switch ink {
        case .white: Palette(primary: .white, warning: RGBColor(hex: 0xFFB066), scrim: .black)
        case .dark: Palette(primary: DetailInk.darkInk, warning: RGBColor(hex: 0x8A3800), scrim: .white)
        }
    }

    /// 主要按鈕：藍底白字（#0071E3 對白字 ≥ 4.5；#2997FF 只約 3:1，不用）
    static let cta = RGBColor(hex: 0x0071E3)

    // MARK: 對比（左欄文字疊在漸層上，不足時在左欄下加柔邊遮罩）

    static let minTextContrast = 4.5
    static let maxScrim = 0.8
    private static let scrimStep = 0.02
    private static let sampleSpacing: CGFloat = 40

    struct Treatment: Equatable {
        let ink: DetailInk
        /// 左欄遮罩不透明度；0＝不畫
        let scrim: Double
    }

    /// 左欄文字區的取樣點（每 40 pt 一點；縱向取中間 60%，左欄內容垂直置中）
    static func leftColumnSamples(size: CGSize) -> [CGPoint] {
        let left = PairingLayout.metrics(for: size).leftWidth
        let xs = stride(from: PairingLayout.sideMargin, through: PairingLayout.sideMargin + left, by: sampleSpacing)
        let ys = stride(from: size.height * 0.2, through: size.height * 0.8, by: sampleSpacing)
        return xs.flatMap { x in ys.map { CGPoint(x: x, y: $0) } }
    }

    /// 左欄某點的實際底色：一般＝漸層；「減少透明度」時 `PresetGradientView` 只畫 `baseColor` 純色
    static func backdrop(preset: BackgroundPreset, scheme: ColorScheme, at point: CGPoint, size: CGSize,
                         reduceTransparency: Bool, treatment: Treatment) -> RGBColor {
        background(preset: preset, scheme: scheme, at: point, size: size, reduceTransparency: reduceTransparency)
            .over(palette(treatment.ink).scrim, alpha: treatment.scrim)
    }

    private static func background(preset: BackgroundPreset, scheme: ColorScheme, at point: CGPoint, size: CGSize,
                                   reduceTransparency: Bool) -> RGBColor {
        reduceTransparency ? BackgroundModel.baseColor(preset: preset, scheme: scheme)
            : BackgroundModel.presetColor(preset: preset, scheme: scheme, at: point, in: size)
    }

    static func passes(_ palette: Palette, on background: RGBColor) -> Bool {
        AlbumPalette.contrast(palette.primary, background) >= minTextContrast
            && AlbumPalette.contrast(palette.secondary(over: background), background) >= minTextContrast
            && AlbumPalette.contrast(palette.warning, background) >= minTextContrast
    }

    /// 尺寸取整：浮點抖動不重算
    private struct CacheKey: Hashable {
        let preset: BackgroundPreset
        let scheme: ColorScheme
        let width: Int
        let height: Int
        let reduceTransparency: Bool
    }

    /// 只隨背景組、深淺、視窗尺寸、減少透明度變；淺色最壞情形一次約十多 ms（推測），所以記住結果，不在每次 body 重算
    @MainActor private static var cache: [CacheKey: Treatment] = [:]
    #if DEBUG
    /// 測試用：實際計算的次數（驗快取有命中）
    @MainActor private(set) static var computeCount = 0
    #endif

    @MainActor static func treatment(preset: BackgroundPreset, scheme: ColorScheme, size: CGSize, reduceTransparency: Bool) -> Treatment {
        let key = CacheKey(preset: preset, scheme: scheme, width: Int(size.width.rounded()), height: Int(size.height.rounded()),
                           reduceTransparency: reduceTransparency)
        if let hit = cache[key] { return hit }
        #if DEBUG
        computeCount += 1
        #endif
        let result = computeTreatment(preset: preset, scheme: scheme, size: size, reduceTransparency: reduceTransparency)
        cache[key] = result
        return result
    }

    /// 兩種字色各算出讓左欄每個取樣點都達 4.5:1 的最小遮罩（0 起每 0.02 一階，上限 0.8），取遮罩較小者；
    /// 一樣時深色主題用白字、淺色主題用深字
    static func computeTreatment(preset: BackgroundPreset, scheme: ColorScheme, size: CGSize, reduceTransparency: Bool) -> Treatment {
        let colors = leftColumnSamples(size: size).map {
            background(preset: preset, scheme: scheme, at: $0, size: size, reduceTransparency: reduceTransparency)
        }
        func minimumScrim(_ ink: DetailInk) -> Double {
            let palette = palette(ink)
            for alpha in stride(from: 0.0, through: maxScrim, by: scrimStep)
            where colors.allSatisfy({ passes(palette, on: $0.over(palette.scrim, alpha: alpha)) }) {
                return alpha
            }
            return maxScrim
        }
        let preferred: DetailInk = scheme == .dark ? .white : .dark
        let other: DetailInk = preferred == .white ? .dark : .white
        let (a, b) = (minimumScrim(preferred), minimumScrim(other))
        return b < a ? Treatment(ink: other, scrim: b) : Treatment(ink: preferred, scrim: a)
    }

    // MARK: 字型（Space Grotesk 只用於小標、品牌名、步驟號、4 碼；跟 Dynamic Type 縮放）

    static let displayFamily = "Space Grotesk"

    static var eyebrow: Font { .custom(displayFamily, size: 11, relativeTo: .caption2).weight(.medium) }
    static func brand(compact: Bool) -> Font { .custom(displayFamily, size: compact ? 28 : 32, relativeTo: .largeTitle).weight(.semibold) }
    static var stepNumber: Font { .custom(displayFamily, size: 14, relativeTo: .subheadline).weight(.semibold) }
    static var code: Font { .custom(displayFamily, size: 56, relativeTo: .largeTitle).weight(.bold) }
}
