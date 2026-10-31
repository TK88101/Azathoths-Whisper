import Foundation
#if DEBUG
import Observation
#endif

/// 唱片樣式（F-V-03；sprint-5-detail.md D8、§4.6；spec「唱片样式」）。rawValue 存設定（資料格式，不可改名）。
/// CR-037 新增 SMOKE／STREAK／FLAKE／CHUNK（合稱 SWIRL 系列，程式生成花紋、依封面取色；yse-swirl-style.md）
enum RecordStyle: String, CaseIterable {
    case random, classic, transparent, splash, marble, smoke, streak, flake, chunk

    /// 浮層圖示來源：原版 MD Vinyl 預覽素材（只在本機）／asset catalog 的自製圖／RANDOM 的洗牌箭頭
    enum IconSource: Equatable {
        case vinylAsset(VinylAssets.Name)
        case bundled(String)
        case symbol
    }

    /// 設定讀回：沒有或壞值＝RANDOM（原版全新安裝＝RANDOM）
    static func restore(_ raw: String?) -> RecordStyle { raw.flatMap(RecordStyle.init(rawValue:)) ?? .random }

    /// RANDOM 依 trackID 決定（同一首永遠同一種）；其他照選。沒有自訂唱片（F-V-09 不做），全部走內建
    func resolved(trackID: String?) -> RecordStyle {
        guard self == .random else { return self }
        return Self.builtIn(bucket: JavaHash.string(trackID ?? "").magnitude % 100)
    }

    /// SWIRL 系列：共用配方、配色與烘焙
    var isSwirl: Bool {
        switch self {
        case .smoke, .streak, .flake, .chunk: true
        case .random, .classic, .transparent, .splash, .marble: false
        }
    }

    /// 浮層樣式圖示（#5-1 G6；CR-037 新 4 種為自製灰階圖，公開版也有）
    var icon: IconSource {
        switch self {
        case .random: .symbol
        case .classic: .vinylAsset(.previewClassic)
        case .transparent: .vinylAsset(.previewColoredBase)
        case .splash: .vinylAsset(.previewSplash)
        case .marble: .vinylAsset(.previewMarble)
        case .smoke: .bundled("RecordStyleSmoke")
        case .streak: .bundled("RecordStyleStreak")
        case .flake: .bundled("RecordStyleFlake")
        case .chunk: .bundled("RecordStyleChunk")
        }
    }

    /// 0…84 與原版相同；CR-037 只把 SPLASH 尾段 85…99 切給新 4 種（7／3／2／3），原本其他樣式的歌不變
    static func builtIn(bucket: UInt32) -> RecordStyle {
        switch bucket {
        case ..<15: .classic
        case ..<40: .transparent
        case ..<65: .marble
        case ..<85: .splash
        case ..<92: .smoke
        case ..<95: .streak
        case ..<97: .flake
        default: .chunk
        }
    }
}

/// 煙渦的變化（CR-037 §4.1b）：自動＝每首歌依配方雜湊固定抽一種；其他＝每首都用那一種。
/// RANDOM 抽到煙渦時同樣跟隨這個設定（使用者 2026-10-31 Q6「跟著走」）。rawValue 存設定
enum SmokeVariantChoice: String, CaseIterable {
    case auto, water, darkInk, lightInk, accent

    static func restore(_ raw: String?) -> SmokeVariantChoice { raw.flatMap(SmokeVariantChoice.init(rawValue:)) ?? .auto }
}

/// TRANSPARENT 的質感（#5-1 S5 收尾，使用者實機回饋＋Codex 辯論）：一律磨砂半透明（透出後面的封套與背景）；
/// 降低透明度時一律改不透明的有色盤。v2.1 T9：去掉黑色分支（墨色玻璃在系統材質上做不出 Black Ice，使用者拍板）——
/// 主色近黑時改用輔色上色，輔色也近黑＝無色磨砂
enum TransparentFinish: Equatable {
    case frosted, opaque

    static let blackLuminanceLimit = 0.05
    static let blackChromaLimit = 0.08

    static func resolve(reduceTransparency: Bool) -> TransparentFinish { reduceTransparency ? .opaque : .frosted }

    /// 近黑＝亮度 ≤ 0.05 且彩度（max−min）≤ 0.08（只看亮度會把深藍、深紫判成黑）
    static func isNearBlack(_ color: RGBColor) -> Bool { isNearBlack(luminance: color.luminance, chroma: color.chroma) }

    static func isNearBlack(luminance: Double, chroma: Double) -> Bool {
        luminance <= blackLuminanceLimit && chroma <= blackChromaLimit
    }

    /// 磨砂盤疊色的來源：主色非近黑＝主色；否則封面最多的鮮豔色相（v2.1 T11）；否則真的取自封面的 MUTED；都沒有＝nil（不疊色）
    static func tint(for colors: AlbumColors) -> RGBColor? {
        if !isNearBlack(colors.primary) { return colors.primary }
        if let vivid = colors.vivid, !isNearBlack(vivid) { return vivid }
        return colors.hasMuted && !isNearBlack(colors.secondary) ? colors.secondary : nil
    }

    /// 降低透明度的不透明盤：與磨砂同一顏色來源（v2.1 T10）；沒有可用色＝乳白
    static let opaqueFallback = RGBColor(hex: 0xECECEC)

    static func opaqueFill(for colors: AlbumColors) -> RGBColor { tint(for: colors) ?? opaqueFallback }

    /// 同色系點的不透明度（v1.9 起；v2.0 改程序生成的較大較少點，數值不變）
    static let speckOpacity = 0.5
    /// 原版黑點改同色系深色點；無色磨砂傳白＝中性灰
    static func speckColor(for tint: RGBColor) -> RGBColor {
        RGBColor(r: tint.r * 0.6, g: tint.g * 0.6, b: tint.b * 0.6)
    }

    /// 透出後面的封套與背景（系統材質）；`VinylRecordView` 的材質、外緣白邊、淡投影都只看這一個條件
    var usesMaterial: Bool { self == .frosted }

    /// 透明盤的投影要淡，否則透過盤面看到一團黑
    var shadowOpacity: Double { Self.shadowOpacity(translucent: usesMaterial) }

    /// 唱片投影濃淡的唯一規則：透光的盤（磨砂、SWIRL 半透明款）淡、不透光的深（CR-037 共用）
    static func shadowOpacity(translucent: Bool) -> Double { translucent ? 0.08 : 0.2 }
}

/// 磨砂盤的可調量（v2.1 T8／T10）：主色濃淡、材質（霧）濃淡，分紅色與其他兩組（使用者以調整面板實機定案）；
/// `standard` 是唯一基準，Release 恆用它，DEBUG 由調整面板（`TransparentTuningStore`）覆寫
struct TransparentTuning: Equatable {
    struct Look: Equatable {
        let frostedTint: Double
        let material: Double

        init(frostedTint: Double, material: Double) {
            self.frostedTint = min(max(frostedTint, 0), 1)
            self.material = min(max(material, 0), 1)
        }
    }

    let red: Look
    let other: Look

    static let standard = TransparentTuning(red: Look(frostedTint: 0.7, material: 0.6), other: Look(frostedTint: 0.25, material: 0.65))

    static let redHueWindowDegrees = 20.0
    static let redMinimumChroma = 0.2
    static let redMaximumLightness = 0.6

    /// 紅＝色相距正紅 ≤ 20°（跨 0°／360°）、彩度 ≥ 0.2、HSL 明度 ≤ 0.6（太亮＝粉）
    static func isRed(_ color: RGBColor) -> Bool {
        let high = max(color.r, color.g, color.b), low = min(color.r, color.g, color.b), chroma = high - low
        guard chroma >= redMinimumChroma, (high + low) / 2 <= redMaximumLightness else { return false }
        let hue: Double
        switch high {
        case color.r: hue = 60 * ((color.g - color.b) / chroma)
        case color.g: hue = 60 * ((color.b - color.r) / chroma + 2)
        default: hue = 60 * ((color.r - color.g) / chroma + 4)
        }
        let degrees = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return min(degrees, 360 - degrees) <= redHueWindowDegrees
    }

    /// 依盤面實際的疊色挑一組；無色磨砂（nil）＝其他
    func look(for tint: RGBColor?) -> Look { tint.map(Self.isRed) == true ? red : other }
}

#if DEBUG
/// 調整面板的單一真相：所有唱片讀同一份；寫入即存進 UserDefaults，重開 app 保留
@MainActor
@Observable
final class TransparentTuningStore {
    static let shared = TransparentTuningStore(defaults: .standard)
    private static let prefix = "debug.transparentTuning."

    @ObservationIgnored private let defaults: UserDefaults
    var tuning: TransparentTuning {
        didSet {
            for (key, value) in Self.entries(tuning) { defaults.set(value, forKey: Self.prefix + key) }
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let standard = TransparentTuning.standard
        func read(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: Self.prefix + key) as? Double ?? fallback }
        tuning = TransparentTuning(
            red: .init(frostedTint: read("redTint", standard.red.frostedTint), material: read("redMaterial", standard.red.material)),
            other: .init(frostedTint: read("otherTint", standard.other.frostedTint), material: read("otherMaterial", standard.other.material)))
    }

    func reset() { tuning = .standard }

    private static func entries(_ tuning: TransparentTuning) -> [(String, Double)] {
        [("redTint", tuning.red.frostedTint), ("redMaterial", tuning.red.material),
         ("otherTint", tuning.other.frostedTint), ("otherMaterial", tuning.other.material)]
    }
}
#endif

/// SPLASH 兩層圖案的配色組合；`hashCode % 3` 為截斷取餘（可能為負）：1 → 1、2 → 2、其餘 → 3
enum SplashStyle: Equatable {
    case style1, style2, style3

    init(remainder: Int32) {
        switch remainder {
        case 1: self = .style1
        case 2: self = .style2
        default: self = .style3
        }
    }

    static func forTrack(_ trackID: String?) -> SplashStyle {
        SplashStyle(remainder: JavaHash.string(trackID ?? "") % 3)
    }

    /// top＝pattern1（alpha 1.0），bottom＝pattern2（alpha 0.8）
    func colors(_ c: AlbumColors) -> (top: RGBColor, bottom: RGBColor) {
        switch self {
        case .style1: (c.text, c.primary)
        case .style2: (c.primary, c.text)
        case .style3: (c.text, c.secondary)
        }
    }
}

/// MARBLE 圖案層：依背景色（P）亮度查 alpha；亮度 ≥ 0.2 用 colorBurn，否則 hardLight
struct MarbleLayer: Equatable {
    enum Blend: Equatable { case colorBurn, hardLight }

    let alpha: Double
    let blend: Blend

    private static let table: [(minimum: Double, alpha: Double)] = [
        (0.8, 1.0), (0.6, 0.8), (0.5, 0.7), (0.4, 0.6), (0.2, 0.5), (0.1, 0.4), (0.05, 0.3),
    ]

    init(luminance: Double) {
        alpha = Self.table.first { luminance >= $0.minimum }?.alpha ?? 0.2
        blend = luminance >= 0.2 ? .colorBurn : .hardLight
    }
}

/// Java／Kotlin 的 `String.hashCode()`：UTF-16 碼元逐一 `31 * h + c`，Int32 溢位環繞
enum JavaHash {
    static func string(_ text: String) -> Int32 {
        text.utf16.reduce(Int32(0)) { $0 &* 31 &+ Int32($1) }
    }
}
