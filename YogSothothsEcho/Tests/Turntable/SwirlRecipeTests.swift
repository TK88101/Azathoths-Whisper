import Foundation
import Testing

@testable import YogSothothsEcho

// CR-037 T2（yse-swirl-style.md §4.2）：配方的雜湊與抽法是資料格式——改了就是改所有歌的外觀。
// 預期值由 Python 依規格獨立算出（FNV-1a 64 ＋ SplitMix64，UTF-8，命名空間 "swirl.v1|"）
struct SwirlRecipeTests {
    /// FNV-1a 64 的公開測試向量
    @Test func fnv1aKnownVectors() {
        #expect(FNV1a64.hash("") == 0xCBF2_9CE4_8422_2325)
        #expect(FNV1a64.hash("a") == 0xAF63_DC4C_8601_EC8C)
        #expect(FNV1a64.hash("foobar") == 0x8594_4171_F739_67E8)
    }

    /// SplitMix64 種子 0 的第一個輸出（公開參考值）
    @Test func splitMixKnownVector() {
        var rng = SeededGenerator(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
    }

    /// 5 個 ID 的完整抽樣（煙渦自動變化、種子、body、不透明度層）；涵蓋空字串、ASCII、真實 ID 形狀、日文、emoji
    @Test(arguments: [
        ("", UInt64(0xACA2_D8EA_A389_D7F5), SmokeVariant.water, 5.16, 0.28729264145410466, 1.0),
        ("abc", UInt64(0x744F_B2BD_D673_C9FB), .darkInk, 3.52, 0.33382561330402566, 0.95),
        ("3f2a9c0d1e4b5a67", UInt64(0x5D07_81D3_63D2_72D0), .water, 6.5, 0.33321987470426007, 0.9),
        ("日本の歌", UInt64(0x6B64_143B_0A05_B20C), .darkInk, 44.07, 0.30444121743625774, 0.9),
        ("🎵", UInt64(0x306A_0EEE_E7A2_932D), .darkInk, 40.63, 0.2925026755965957, 0.95),
    ])
    func goldenDraws(id: String, hash: UInt64, variant: SmokeVariant, seed: Double, body: Double, tier: Double) {
        #expect(SwirlRecipe.hash(trackID: id) == hash)
        let draws = SwirlRecipe.Draws(trackID: id)
        #expect(draws.autoVariant == variant)
        #expect(draws.noiseSeed == seed)
        #expect(abs(draws.smokeBody - body) < 1e-12)
        #expect(draws.smokeOpacity == tier)
    }

    /// 沒有 trackID＝空字串的暫定種子
    @Test func nilTrackIDUsesEmptySeed() {
        #expect(SwirlRecipe.Draws(trackID: nil) == SwirlRecipe.Draws(trackID: ""))
    }

    /// 各樣式的子型與固定參數；煙渦依設定（自動＝依歌曲）決定變化；換樣式保留噪聲種子
    @Test func recipePerStyle() throws {
        let id = "abc" // 自動＝深墨、種子 3.52、body 0.3338…、不透明度 0.95
        let auto = try #require(SwirlRecipe.make(style: .smoke, trackID: id, smoke: .auto))
        #expect(auto.subtype == .smoke && auto.ink == .dark && auto.noiseSeed == 3.52 && auto.opacity == 0.95)
        let water = try #require(SwirlRecipe.make(style: .smoke, trackID: id, smoke: .water))
        #expect(water.subtype == .smokeWater && water.ink == nil && water.body == 0.25 && water.opacity == 0.95)
        #expect(SwirlRecipe.make(style: .smoke, trackID: id, smoke: .lightInk)?.ink == .light)
        #expect(SwirlRecipe.make(style: .smoke, trackID: id, smoke: .accent)?.ink == .accent)
        let streak = try #require(SwirlRecipe.make(style: .streak, trackID: id, smoke: .accent))
        #expect(streak.subtype == .pull && streak.ink == nil && streak.body == 0.4 && streak.opacity == 1 && streak.noiseSeed == 3.52)
        #expect(SwirlRecipe.make(style: .flake, trackID: id, smoke: .auto) == SwirlRecipe(subtype: .flake, ink: nil, noiseSeed: 3.52, body: 0.5, opacity: 1))
        #expect(SwirlRecipe.make(style: .chunk, trackID: id, smoke: .auto) == SwirlRecipe(subtype: .chunk, ink: nil, noiseSeed: 3.52, body: 0.5, opacity: 0.95))
        for style in [RecordStyle.random, .classic, .transparent, .splash, .marble] {
            #expect(SwirlRecipe.make(style: style, trackID: id, smoke: .auto) == nil, "\(style)")
        }
    }

    /// 自動變化各 1/4；只取 RANDOM 落在 SWIRL 分桶的歌仍各 1/4（與 RANDOM 的 JavaHash 無關）；不透明度三層各 1/3
    @Test func distributionsAndIndependenceFromRandom() {
        let ids = (0..<20_000).map { String(format: "%016llx", UInt64($0) &* 0x9E37_79B9_7F4A_7C15) }
        func shares<T: Hashable>(_ values: [T]) -> [T: Double] {
            Dictionary(grouping: values, by: { $0 }).mapValues { Double($0.count) / Double(values.count) }
        }
        let draws = ids.map { SwirlRecipe.Draws(trackID: $0) }
        for (_, share) in shares(draws.map(\.autoVariant)) { #expect(abs(share - 0.25) < 0.02) }
        for (_, share) in shares(draws.map(\.smokeOpacity)) { #expect(abs(share - 1.0 / 3) < 0.02) }
        let swirlBucket = ids.filter { RecordStyle.random.resolved(trackID: $0).isSwirl }.map { SwirlRecipe.Draws(trackID: $0).autoVariant }
        #expect(swirlBucket.count > 2_000)
        for (_, share) in shares(swirlBucket) { #expect(abs(share - 0.25) < 0.03) }
    }
}
