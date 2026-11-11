import Foundation

/// SWIRL 系列的花紋型（CR-037；小樣 swirl-preview.html 7 款定案 → 5 型）
enum SwirlSubtype: Hashable {
    case smokeWater, smoke, pull, flake, chunk
}

/// 煙渦（smoke 型）的墨色取向：深端／淺端／強調色（配色規則見 SwirlPalette）
enum SmokeInk: Hashable {
    case dark, light, accent
}

/// 煙渦的四種變化（第二排的「自動」以外四項）
enum SmokeVariant: CaseIterable, Hashable {
    case water, darkInk, lightInk, accent

    init?(_ choice: SmokeVariantChoice) {
        switch choice {
        case .auto: return nil
        case .water: self = .water
        case .darkInk: self = .darkInk
        case .lightInk: self = .lightInk
        case .accent: self = .accent
        }
    }
}

/// 一首歌的花紋配方（yse-swirl-style.md §4.2）：只看樣式、trackID 與煙渦設定，與顏色無關——
/// 封面由小圖升到原圖時花紋不變、只換色
struct SwirlRecipe: Hashable {
    let subtype: SwirlSubtype
    /// smoke 型才有
    let ink: SmokeInk?
    /// 噪聲種子，[0, 50)
    let noiseSeed: Double
    let body: Double
    /// 盤面整體不透明度（Reduce Transparency 在配色時再改 1）
    let opacity: Double

    /// 命名空間帶版本：日後改抽法就換 v2，不悄悄改舊歌
    static let namespace = "swirl.v1|"

    static func hash(trackID: String?) -> UInt64 { FNV1a64.hash(namespace + (trackID ?? "")) }

    /// 每首歌的固定抽樣。順序寫死、每欄無條件消耗一次（改順序＝改所有歌的外觀）
    struct Draws: Equatable {
        let autoVariant: SmokeVariant
        let noiseSeed: Double
        let smokeBody: Double
        let smokeOpacity: Double

        static let opacityTiers = [0.9, 0.95, 1.0]

        init(trackID: String?) {
            var rng = SeededGenerator(seed: SwirlRecipe.hash(trackID: trackID))
            autoVariant = SmokeVariant.allCases[Int(rng.nextUnit() * Double(SmokeVariant.allCases.count))]
            noiseSeed = (rng.nextUnit() * 5000).rounded(.down) / 100
            smokeBody = 0.28 + rng.nextUnit() * 0.08
            smokeOpacity = Self.opacityTiers[min(2, Int(rng.nextUnit() * 3))]
        }
    }

    /// 非 SWIRL 系列回 nil；煙渦依設定（自動＝依歌曲）決定變化，RANDOM 抽到煙渦時同樣跟隨設定（Q6）
    static func make(style: RecordStyle, trackID: String?, smoke choice: SmokeVariantChoice) -> SwirlRecipe? {
        let draws = Draws(trackID: trackID)
        switch style {
        case .smoke:
            switch SmokeVariant(choice) ?? draws.autoVariant {
            case .water: return recipe(.smokeWater, body: 0.2, opacity: 0.95, draws)
            case .darkInk: return recipe(.smoke, ink: .dark, body: draws.smokeBody, opacity: draws.smokeOpacity, draws)
            case .lightInk: return recipe(.smoke, ink: .light, body: draws.smokeBody, opacity: draws.smokeOpacity, draws)
            case .accent: return recipe(.smoke, ink: .accent, body: draws.smokeBody, opacity: draws.smokeOpacity, draws)
            }
        case .streak: return recipe(.pull, body: 0.4, opacity: 1, draws)
        case .flake: return recipe(.flake, body: 0.5, opacity: 1, draws)
        case .chunk: return recipe(.chunk, body: 0.5, opacity: 0.95, draws)
        case .random, .classic, .transparent, .splash, .marble: return nil
        }
    }

    /// 噪聲種子一律取自同一首歌的抽樣（換樣式保留花紋位置）
    private static func recipe(_ subtype: SwirlSubtype, ink: SmokeInk? = nil, body: Double, opacity: Double, _ draws: Draws) -> SwirlRecipe {
        SwirlRecipe(subtype: subtype, ink: ink, noiseSeed: draws.noiseSeed, body: body, opacity: opacity)
    }
}
