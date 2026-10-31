import SwiftUI
import Testing

@testable import YogSothothsEcho

// S5 T3（sprint-5-detail.md D8、§4.6；spec「唱片樣式」）：RANDOM 依 trackID 的 Java hashCode 選樣式、
// SPLASH 子樣式與配色、MARBLE 查表、偏好讀回。預期雜湊值由 Python 以 Java 語意（UTF-16、Int32 溢位）獨立算出

struct RecordStyleTests {
    @Test(arguments: [("abc", Int32(96354)), ("hello", 99_162_322), ("polygenelubricants", Int32.min),
                      ("3f2a9c0d1e4b5a67", 1_562_077_135), ("00000000000000ff", -411_683_136), ("日本", 835_047)])
    func javaHashCode(text: String, expected: Int32) {
        #expect(JavaHash.string(text) == expected)
    }

    /// h％100 的區間與邊界（CR-037：新 4 種只從 SPLASH 尾段切出 15 桶，7／3／2／3）
    @Test func builtInBuckets() {
        let expected: [(UInt32, RecordStyle)] = [(0, .classic), (14, .classic), (15, .transparent), (39, .transparent),
                                                 (40, .marble), (64, .marble), (65, .splash), (84, .splash),
                                                 (85, .smoke), (91, .smoke), (92, .streak), (94, .streak),
                                                 (95, .flake), (96, .flake), (97, .chunk), (99, .chunk)]
        for (bucket, style) in expected { #expect(RecordStyle.builtIn(bucket: bucket) == style, "\(bucket)") }
    }

    /// CR-037：0…84 與改前的分桶逐值相同（原本 CLASSIC／TRANSPARENT／MARBLE 的歌一首都不變），只有 85…99 改成新 4 種
    @Test func bucketsBelow85AreUnchangedFromBeforeCR037() {
        func before(_ bucket: UInt32) -> RecordStyle {
            switch bucket {
            case ..<15: .classic
            case ..<40: .transparent
            case ..<65: .marble
            default: .splash
            }
        }
        for bucket in UInt32(0)..<85 { #expect(RecordStyle.builtIn(bucket: bucket) == before(bucket), "\(bucket)") }
        for bucket in UInt32(85)..<100 { #expect(RecordStyle.builtIn(bucket: bucket).isSwirl, "\(bucket)") }
        let counts = Dictionary(grouping: UInt32(0)..<100, by: RecordStyle.builtIn(bucket:)).mapValues(\.count)
        #expect(counts == [.classic: 15, .transparent: 25, .marble: 25, .splash: 20, .smoke: 7, .streak: 3, .flake: 2, .chunk: 3])
    }

    /// 各新分桶邊界的真實 trackID（雜湊值以 Python 依 Java 語意獨立算出）
    @Test func randomResolvesIntoNewBuckets() {
        #expect(RecordStyle.random.resolved(trackID: "000000000000001a") == .splash) // 84
        #expect(RecordStyle.random.resolved(trackID: "000000000000004a") == .smoke)  // 91
        #expect(RecordStyle.random.resolved(trackID: "0000000000000028") == .streak) // 94
        #expect(RecordStyle.random.resolved(trackID: "0000000000000026") == .flake)  // 96
        #expect(RecordStyle.random.resolved(trackID: "0000000000000023") == .chunk)  // 99
    }

    /// RANDOM：同一首永遠同一種；Int32.min 取絕對值不溢位（2147483648 % 100 = 48 → MARBLE）
    @Test func randomResolvesPerTrack() {
        #expect(RecordStyle.random.resolved(trackID: "abc") == .marble)                 // 54
        #expect(RecordStyle.random.resolved(trackID: "hello") == .transparent)          // 22
        #expect(RecordStyle.random.resolved(trackID: "polygenelubricants") == .marble)  // 48
        #expect(RecordStyle.random.resolved(trackID: "00000000000000ff") == .transparent) // |−411683136| → 36
        #expect(RecordStyle.random.resolved(trackID: nil) == .classic)                  // 0
        #expect(RecordStyle.splash.resolved(trackID: "abc") == .splash)                 // 非 RANDOM 照選
    }

    /// SPLASH 子樣式：hashCode % 3（截斷取餘、可能為負）：1 → 1、2 → 2、其餘 → 3
    @Test func splashStyle() {
        #expect(SplashStyle(remainder: 1) == .style1 && SplashStyle(remainder: 2) == .style2)
        for r: Int32 in [0, -1, -2] { #expect(SplashStyle(remainder: r) == .style3) }
        #expect(SplashStyle.forTrack("hello") == .style1)              // 99162322 % 3 = 1
        #expect(SplashStyle.forTrack("polygenelubricants") == .style3)  // −2
        #expect(SplashStyle.forTrack("abc") == .style3)                 // 0
    }

    @Test func splashColors() {
        let c = AlbumColors(primary: RGBColor(r: 1, g: 0, b: 0), text: RGBColor(r: 1, g: 1, b: 1), secondary: RGBColor(r: 0, g: 0, b: 1))
        #expect(SplashStyle.style1.colors(c) == (top: c.text, bottom: c.primary))
        #expect(SplashStyle.style2.colors(c) == (top: c.primary, bottom: c.text))
        #expect(SplashStyle.style3.colors(c) == (top: c.text, bottom: c.secondary))
    }

    /// MARBLE：背景亮度查 alpha 8 段；亮度 ≥ 0.2 用 colorBurn，否則 hardLight
    @Test func marbleTable() {
        let cases: [(Double, Double)] = [(0.8, 1.0), (0.79, 0.8), (0.6, 0.8), (0.5, 0.7), (0.4, 0.6), (0.2, 0.5),
                                         (0.19, 0.4), (0.1, 0.4), (0.05, 0.3), (0.049, 0.2), (0, 0.2)]
        for (luminance, alpha) in cases { #expect(MarbleLayer(luminance: luminance).alpha == alpha, "\(luminance)") }
        #expect(MarbleLayer(luminance: 0.2).blend == .colorBurn && MarbleLayer(luminance: 0.199).blend == .hardLight)
    }

    /// 相對亮度（sRGB 線性化，同 Compose Color.luminance）
    @Test func relativeLuminance() {
        #expect(RGBColor(r: 1, g: 1, b: 1).luminance == 1 && RGBColor(r: 0, g: 0, b: 0).luminance == 0)
        #expect(abs(RGBColor(r: 0.5, g: 0.5, b: 0.5).luminance - 0.21404) < 1e-4)
    }

    /// 偏好：預設 RANDOM，壞值回 RANDOM，九選一依序（CR-037 新 4 種接在 MARBLE 之後）
    @Test func preference() {
        #expect(RecordStyle.allCases == [.random, .classic, .transparent, .splash, .marble, .smoke, .streak, .flake, .chunk])
        #expect(RecordStyle.restore(nil) == .random && RecordStyle.restore("bogus") == .random)
        #expect(RecordStyle.restore(RecordStyle.marble.rawValue) == .marble)
        // rawValue 是設定的資料格式，寫死；舊版讀到這些值會回 RANDOM（既有 restore 行為）
        #expect([RecordStyle.smoke, .streak, .flake, .chunk].map(\.rawValue) == ["smoke", "streak", "flake", "chunk"])
        for raw in ["smoke", "streak", "flake", "chunk"] { #expect(RecordStyle.restore(raw).rawValue == raw) }
    }

    /// SWIRL 系列＝新 4 種；其他樣式不是
    @Test func swirlFamily() {
        #expect(RecordStyle.allCases.filter(\.isSwirl) == [.smoke, .streak, .flake, .chunk])
    }

    /// 浮層樣式圖示：原版 4 種用 MD Vinyl 預覽素材；新 4 種用 asset catalog 的自製灰階圖；RANDOM 畫洗牌箭頭
    @Test func iconSources() {
        #expect(RecordStyle.random.icon == .symbol)
        #expect(RecordStyle.classic.icon == .vinylAsset(.previewClassic))
        #expect(RecordStyle.transparent.icon == .vinylAsset(.previewColoredBase))
        #expect(RecordStyle.splash.icon == .vinylAsset(.previewSplash))
        #expect(RecordStyle.marble.icon == .vinylAsset(.previewMarble))
        #expect(RecordStyle.smoke.icon == .bundled("RecordStyleSmoke"))
        #expect(RecordStyle.streak.icon == .bundled("RecordStyleStreak"))
        #expect(RecordStyle.flake.icon == .bundled("RecordStyleFlake"))
        #expect(RecordStyle.chunk.icon == .bundled("RecordStyleChunk"))
    }

    /// 煙渦變化設定：預設與壞值＝自動；rawValue 寫死（資料格式）
    @Test func smokeVariantChoicePreference() {
        #expect(SmokeVariantChoice.allCases == [.auto, .water, .darkInk, .lightInk, .accent])
        #expect(SmokeVariantChoice.allCases.map(\.rawValue) == ["auto", "water", "darkInk", "lightInk", "accent"])
        #expect(SmokeVariantChoice.restore(nil) == .auto && SmokeVariantChoice.restore("bogus") == .auto)
        #expect(SmokeVariantChoice.restore("lightInk") == .lightInk)
    }
}

// #5-1 第 2 項：唱片外沿光環在 3 點鐘（漸層起點）不得有白色斷頭——頭尾同色、白光從起點漸亮到 6 點鐘最亮
struct VinylRimTests {
    @Test func rimGradientWrapsWithoutAHardEdge() throws {
        let stops = VinylRecordView.rimStops
        let first = try #require(stops.first), last = try #require(stops.last)
        #expect(first.color == last.color && first.color != Color.white.opacity(0.4))
        // 規格值全數釘住（v1.8）：透明 → 白 0.4 @0.25 → 透明 @0.4 → 黑 0.15 @0.75 → 透明
        #expect(stops.map(\.location) == [0, 0.25, 0.4, 0.75, 1])
        #expect(stops.map(\.color) == [.clear, .white.opacity(0.4), .clear, .black.opacity(0.15), .clear])
    }
}

// #5-1（S5 收尾）：TRANSPARENT 只有「黑」維持原版（主色＋黑點）；有彩度或較亮的主色改磨砂半透明；
// 降低透明度時改不透明的有色盤。黑＝亮度 ≤ 0.05 且彩度（max−min）≤ 0.08（Codex：只看亮度會把深藍判成黑）
struct TransparentFinishTests {
    /// v2.1 T9（使用者拍板去掉黑色 TRANSPARENT）：透明樣式一律磨砂，降低透明度才改不透明（任何主色）
    @Test func everyPrimaryIsFrostedUnlessReduceTransparency() {
        #expect(TransparentFinish.resolve(reduceTransparency: false) == .frosted)
        #expect(TransparentFinish.resolve(reduceTransparency: true) == .opaque)
    }

    /// 近黑＝亮度 ≤ 0.05 且彩度 ≤ 0.08（含臨界；只看亮度會把深藍、深紫判成黑）
    @Test func nearBlackBoundaryIsInclusive() {
        #expect(TransparentFinish.isNearBlack(RGBColor(hex: 0x1E1D1D)) && TransparentFinish.isNearBlack(.black))
        for hex: UInt32 in [0xF2D21B, 0xFFFFFF, 0x808080, 0x0A1440, 0x2A0A3A] {
            #expect(!TransparentFinish.isNearBlack(RGBColor(hex: hex)), "\(hex)")
        }
        #expect(TransparentFinish.isNearBlack(luminance: 0.05, chroma: 0.08))
        #expect(!TransparentFinish.isNearBlack(luminance: 0.050001, chroma: 0))
        #expect(!TransparentFinish.isNearBlack(luminance: 0, chroma: 0.080001))
    }

    /// 盤面疊色的來源：主色非近黑＝主色；主色近黑改用輔色；輔色也近黑＝不疊色（無色磨砂）
    @Test func tintFallsBackFromBlackPrimaryToSecondaryThenClear() {
        let yellow = RGBColor(hex: 0xF2D21B), brown = RGBColor(hex: 0x8A6A3C), black = RGBColor(hex: 0x1E1D1D)
        #expect(TransparentFinish.tint(for: AlbumColors(primary: yellow, text: .black, secondary: brown)) == yellow)
        #expect(TransparentFinish.tint(for: AlbumColors(primary: black, text: .white, secondary: brown)) == brown)
        #expect(TransparentFinish.tint(for: AlbumColors(primary: black, text: .white, secondary: .black)) == nil)
        // 取色沒有 MUTED 時的回退輔色 #46403C 不是封面色（Codex T9 R1 P1）：黑主色＋無 MUTED＝無色磨砂
        let fallback = AlbumColors.fallback.secondary
        #expect(TransparentFinish.tint(for: AlbumColors(primary: black, text: .white, secondary: fallback, hasMuted: false)) == nil)
        #expect(!AlbumColors.fallback.hasMuted)
        #expect(!AlbumPalette.extract(rgba: [UInt8](repeating: 0, count: 64 * 4).enumerated().map { $0.offset % 4 == 3 ? 255 : 0 }).hasMuted)
    }

    /// 黑主色：封面最多的鮮豔色相優先於 MUTED（v2.1 T11）
    @Test func vividBeatsMutedForBlackPrimary() {
        let black = RGBColor(hex: 0x1E1D1D), blood = RGBColor(r: 152 / 255, g: 58 / 255, b: 64 / 255)
        let muted = RGBColor(r: 168 / 255, g: 105 / 255, b: 94 / 255)
        #expect(TransparentFinish.tint(for: AlbumColors(primary: black, text: .white, secondary: muted, vivid: blood)) == blood)
        #expect(TransparentFinish.tint(for: AlbumColors(primary: black, text: .white, secondary: muted, vivid: nil)) == muted)
        let yellow = RGBColor(hex: 0xF2D21B)
        #expect(TransparentFinish.tint(for: AlbumColors(primary: yellow, text: .black, secondary: muted, vivid: blood)) == yellow)
    }

    /// 同色系點（主色 ×0.6）；無色磨砂時點用中性灰（＝白 ×0.6）
    @Test func speckColorFollowsTheTint() {
        let yellow = RGBColor(hex: 0xF2D21B)
        #expect(TransparentFinish.speckColor(for: yellow) == RGBColor(r: yellow.r * 0.6, g: yellow.g * 0.6, b: yellow.b * 0.6))
        #expect(TransparentFinish.speckColor(for: .white) == RGBColor(r: 0.6, g: 0.6, b: 0.6))
    }

    /// 磨砂盤投影要淡、用材質；降低透明度的不透明盤照舊
    @Test func frostedUsesMaterialAndLighterShadow() {
        #expect(TransparentFinish.frosted.usesMaterial && !TransparentFinish.opaque.usesMaterial)
        #expect(TransparentFinish.frosted.shadowOpacity == 0.08 && TransparentFinish.opaque.shadowOpacity == 0.2)
    }
}

/// v2.1 T8／T10：磨砂盤的可調量（主色濃淡、材質＝霧的濃淡）分紅色與其他兩組（使用者實機調定）；`standard` 是唯一基準
struct TransparentTuningTests {
    static let springsteenRed = RGBColor(r: 171 / 255, g: 48 / 255, b: 52 / 255)
    static let oasisWhite = RGBColor(r: 219 / 255, g: 219 / 255, b: 220 / 255)

    @Test func standardIsTheUsersChoice() {
        #expect(TransparentTuning.standard.red == TransparentTuning.Look(frostedTint: 0.7, material: 0.6))
        #expect(TransparentTuning.standard.other == TransparentTuning.Look(frostedTint: 0.25, material: 0.65))
    }

    @Test func valuesAreClampedToUnitRange() {
        let look = TransparentTuning.Look(frostedTint: -0.2, material: 1.4)
        #expect(look.frostedTint == 0 && look.material == 1)
    }

    /// 紅＝色相距正紅 ≤ 20°（含跨 0°／360°）、彩度 ≥ 0.2、HSL 明度 ≤ 0.6（太亮＝粉）；橘、粉、白、灰都不算
    @Test func redIsAHueWindowWithEnoughChroma() {
        #expect(TransparentTuning.isRed(Self.springsteenRed))
        #expect(TransparentTuning.isRed(RGBColor(r: 0.8, g: 0.1, b: 0.25)))   // 偏紫紅、色相約 347°
        #expect(TransparentTuning.isRed(RGBColor(r: 0.8, g: 0.2, b: 0.1)))    // 偏橘紅、色相約 6°
        #expect(!TransparentTuning.isRed(RGBColor(r: 230 / 255, g: 120 / 255, b: 30 / 255)))   // 橘，約 27°
        #expect(!TransparentTuning.isRed(RGBColor(r: 240 / 255, g: 150 / 255, b: 170 / 255)))  // 淡粉：色相約 347°、彩度 0.35，但明度 0.76 太亮
        #expect(!TransparentTuning.isRed(Self.oasisWhite))
        #expect(!TransparentTuning.isRed(RGBColor(r: 0.5, g: 0.5, b: 0.5)))
        #expect(!TransparentTuning.isRed(RGBColor(r: 0.6, g: 0.45, b: 0.45)))  // 灰紅，彩度 0.15
    }

    /// 邊界（Codex T10 R1）：色相 19°／21°、341°；彩度 0.19／0.21；明度 0.59／0.61（避開浮點恰等值）
    @Test func redBoundaries() {
        #expect(TransparentTuning.isRed(RGBColor(r: 0.6, g: 0.2 + 0.4 * 19 / 60, b: 0.2)))
        #expect(!TransparentTuning.isRed(RGBColor(r: 0.6, g: 0.2 + 0.4 * 21 / 60, b: 0.2)))
        #expect(TransparentTuning.isRed(RGBColor(r: 0.6, g: 0.2, b: 0.2 + 0.4 * 19 / 60)))
        #expect(TransparentTuning.isRed(RGBColor(r: 0.51, g: 0.3, b: 0.3)) && !TransparentTuning.isRed(RGBColor(r: 0.49, g: 0.3, b: 0.3)))
        #expect(TransparentTuning.isRed(RGBColor(r: 0.79, g: 0.39, b: 0.39)) && !TransparentTuning.isRed(RGBColor(r: 0.81, g: 0.41, b: 0.41)))
    }

    @Test func lookFollowsTheTint() {
        let tuning = TransparentTuning.standard
        #expect(tuning.look(for: Self.springsteenRed) == tuning.red)
        #expect(tuning.look(for: Self.oasisWhite) == tuning.other)
        #expect(tuning.look(for: nil) == tuning.other)
    }
}

/// v2.1 T10：降低透明度的不透明盤與磨砂盤同一顏色來源；放射紋依填色選黑白（同標籤文字色規則）
struct OpaqueDiscTests {
    @Test func opaqueFillUsesTheSameTintAsFrosted() {
        let red = TransparentTuningTests.springsteenRed, black = RGBColor(hex: 0x1E1D1D)
        #expect(TransparentFinish.opaqueFill(for: AlbumColors(primary: black, text: .white, secondary: red)) == red)
        #expect(TransparentFinish.opaqueFill(for: AlbumColors(primary: black, text: .white, secondary: .black)) == RGBColor(hex: 0xECECEC))
        #expect(TransparentFinish.opaqueFill(for: AlbumColors(primary: .white, text: .black, secondary: .white)) == .white)
    }

    /// 放射紋看的是實際填色，不是依主色算的標籤字色（黑主色＋白輔色：字色白、填色白→線要黑）
    @Test func rayColorIgnoresTheLabelTextColor() {
        let colors = AlbumColors(primary: RGBColor(hex: 0x1E1D1D), text: .white, secondary: TransparentTuningTests.oasisWhite)
        #expect(RotationCue.rayColor(finish: .opaque, colors: colors) == .black)
    }

    @Test func rayColorContrastsWithTheFill() {
        let red = TransparentTuningTests.springsteenRed, black = RGBColor(hex: 0x1E1D1D)
        #expect(RotationCue.rayColor(finish: .opaque, colors: AlbumColors(primary: black, text: .white, secondary: red)) == .white)
        #expect(RotationCue.rayColor(finish: .opaque, colors: AlbumColors(primary: black, text: .white, secondary: .black)) == .black)
        #expect(RotationCue.rayColor(finish: .opaque, colors: AlbumColors(primary: .white, text: .black, secondary: .white)) == .black)
    }

    /// 文字色規則抽出後不變：對比 ≥ 4.5 選白，否則黑
    @Test func textColorRuleIsUnchanged() {
        #expect(AlbumPalette.textColor(on: RGBColor(hex: 0x1B2A4A)) == .white)
        #expect(AlbumPalette.textColor(on: .white) == .black)
        #expect(AlbumPalette.textColor(on: RGBColor(hex: 0xF2D21B)) == .black)
    }
}

#if DEBUG
/// DEBUG 調整面板的儲存：單一真相、寫入即持久化、重設回 standard（獨立 UserDefaults suite）
@MainActor
struct TransparentTuningStoreTests {
    private func defaults() -> UserDefaults {
        let name = "TransparentTuningStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startsAtStandardAndPersistsChanges() {
        let suite = defaults()
        let store = TransparentTuningStore(defaults: suite)
        #expect(store.tuning == .standard)
        let changed = TransparentTuning(red: .init(frostedTint: 0.5, material: 0.4), other: .init(frostedTint: 0.15, material: 0.6))
        store.tuning = changed
        #expect(TransparentTuningStore(defaults: suite).tuning == changed)
    }

    /// 只存了部分鍵：其餘回 standard，不互相覆寫
    @Test func missingKeysFallBackIndividually() {
        let suite = defaults()
        suite.set(0.42, forKey: "debug.transparentTuning.redTint")
        let tuning = TransparentTuningStore(defaults: suite).tuning
        #expect(tuning.red == .init(frostedTint: 0.42, material: TransparentTuning.standard.red.material))
        #expect(tuning.other == TransparentTuning.standard.other)
    }

    @Test func resetReturnsToStandard() {
        let suite = defaults()
        let store = TransparentTuningStore(defaults: suite)
        store.tuning = TransparentTuning(red: .init(frostedTint: 0.1, material: 0.5), other: .init(frostedTint: 0.1, material: 0.5))
        store.reset()
        #expect(store.tuning == .standard)
        #expect(TransparentTuningStore(defaults: suite).tuning == .standard)
    }
}
#endif

// 播完沒有封面時的封套：同 MD 佔位圖最頻色的純色（不再用帶「M」的原版素材）
struct CoverPlaceholderTests {
    @Test func placeholderIsPlainDarkGrey() {
        #expect(TurntableMetrics.coverPlaceholderColor == RGBColor(hex: 0x282828))
    }
}
