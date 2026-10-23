import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// ⑥a J-Pop 計劃 §6.4：新背景的幾何、三變體以實際配方量讀得到（G1 對比、G2 空白、G3 疊住）

@Suite("J-Pop backdrops")
struct JPopBackdropTests {
    static let canvas = CGSize(width: 640, height: 400)
    static let palette = LyricsFXCatalog.palette("jpKira")!

    @Test func sparkleHasFortyFixedStarsThatTwinkleInTheAccentColor() {
        let layers = ComposedBackdrop.back(.sparkle, palette: Self.palette, size: Self.canvas, time: 1)
        guard case .sparkles(let stars, let color, _)? = layers.last else { Issue.record("最上層不是四芒星：\(layers)"); return }
        #expect(stars.count == 40)
        #expect(color == Self.palette.acc)
        guard case .sparkles(let later, _, _)? = ComposedBackdrop.back(.sparkle, palette: Self.palette, size: Self.canvas, time: 1.7).last else { return }
        #expect(stars.map { CGPoint(x: $0.x, y: $0.y) } == later.map { CGPoint(x: $0.x, y: $0.y) }, "位置不動")
        #expect(stars.map(\.radius) == later.map(\.radius))
        #expect(stars.map(\.alpha) != later.map(\.alpha), "會閃")
        #expect(stars.allSatisfy { (0...Self.canvas.width).contains($0.x) && (0...Self.canvas.height).contains($0.y) && (0...1).contains($0.alpha) })
        #expect(BackdropKind.sparkle.tone == .light)
    }

    @Test func cityNeonHasSixAlternatingLinesAndAHalfSun() {
        let layers = ComposedBackdrop.back(.cityNeon, palette: LyricsFXCatalog.palette("jpCity")!, size: Self.canvas, time: 0)
        let rects = layers.compactMap { if case .rects(let rects, let color, let opacity) = $0 { (rects, color, opacity) } else { nil } }
        #expect(rects.count == 2)
        #expect(rects.map(\.1) == [RGB(hex: 0xFF6AA0), RGB(hex: 0x4FD3FF)])
        #expect(rects.allSatisfy { $0.2 == 0.5 && $0.0.allSatisfy { $0.height == 2 && $0.width == Self.canvas.width } })
        let ys = rects.flatMap { $0.0.map(\.minY) }.sorted()
        #expect(ys == (0..<6).map { Self.canvas.height * (0.62 + 0.06 * CGFloat($0)) })
        #expect(rects[0].0.map(\.minY) == [0, 2, 4].map { Self.canvas.height * (0.62 + 0.06 * CGFloat($0)) }, "偶數條粉紅")
        guard case .semicircle(let center, let radius, let top, let bottom, let opacity)? = layers.last else { Issue.record("最上層不是夕陽"); return }
        #expect(center == CGPoint(x: 0.5, y: 0.55) && radius == 0.28 && opacity == 0.35)
        #expect(top == RGB(hex: 0xFFB347) && bottom == RGB(hex: 0xFF6AA0))
        #expect(BackdropKind.cityNeon.tone == .dark)
    }

    @Test(arguments: [BackdropKind.sparkle, .cityNeon])
    func theNewBackdropsDrawNothingOverTheText(kind: BackdropKind) {
        #expect(ComposedBackdrop.front(kind, size: Self.canvas, time: 1).isEmpty)
        #expect(ComposedBackdrop.underText(kind).isEmpty)
    }
}

// 使用者 2026-10-23 看並排比較選定：シティポップ用短距離滑入 sidle，不用從遠處橫越鄰字的 slide
@Suite("J-Pop city sidle")
struct JPopCitySidleTests {
    @Test func sidleStartsAThirdOfAnEmAsideAndFadesInOverTheFirstHalf() {
        for dir in [CGFloat(1), -1] {
            let context = GlyphContext(em: 40, width: 900, height: 560, radius: 495, dir: dir, side: -1, phase: 0.7, angle: 2.1, bend: 0.4)
            let start = EnterTemplate.sidle.transform(progress: 0, context: context)
            #expect(start.dx == 40 * 0.3 * dir && start.dy == 0 && start.alpha == 0)
            #expect(EnterTemplate.sidle.transform(progress: 0.25, context: context).alpha == 0.5)
            #expect(EnterTemplate.sidle.transform(progress: 0.5, context: context).alpha == 1)
            #expect(EnterTemplate.sidle.transform(progress: 1, context: context) == .identity)
        }
    }

    @Test func theCityEntranceSidlesInsteadOfSliding() throws {
        guard case .enter(let spec)? = LyricsFXCatalog.component("jpCitySlide")?.payload else { Issue.record("沒有 jpCitySlide"); return }
        #expect(spec.weights.map(\.0) == [.sidle, .fadeUp])
        #expect(!ReadabilityAudit.coverExemptEnters.contains("jpCitySlide"), "選了 sidle 就不列 G3 豁免")
    }
}

@MainActor
@Suite("J-Pop readability")
struct JPopReadabilityTests {
    /// 該變體目錄裡每個 fx 各一份配方（其餘槽各只有一個元件），停留時刻取三個閃爍相位
    static func recipes(_ variant: JPopVariant) -> [ComposedRecipe] {
        let catalog = JPopPolicy.catalog(variant)
        let only = { (slot: FXSlot) in catalog.first { $0.slot == slot }!.id }
        return catalog.filter { $0.slot == .fx }.map { fx in
            ComposedRecipe(font: only(.font), backdrop: only(.backdrop), enter: only(.enter), exit: only(.exit), fx1: fx.id, fx2: "none",
                           palette: only(.palette), seed: 5, profile: variant.profile)
        }
    }

    @Test(arguments: JPopVariant.allCases)
    func eachSlotHasExactlyOneComponentApartFromEffects(variant: JPopVariant) {
        let catalog = JPopPolicy.catalog(variant)
        for slot in FXSlot.allCases where slot != .fx { #expect(catalog.filter { $0.slot == slot }.count == 1, "\(variant) \(slot)") }
    }

    @Test(arguments: JPopVariant.allCases)
    func mainTextStaysReadableWithTheRealRecipes(variant: JPopVariant) {
        var failures: [String] = []
        for recipe in Self.recipes(variant) {
            for (name, lyrics) in [("en", LyricsFXContrastTests.timeline), ("ja", LyricsFXContrastTests.japanese)] {
                for time in [5.0, 5.4, 5.8] {
                    guard let result = LyricsFXContrastTests.contrast(recipe, at: time, lyrics: lyrics) else { failures.append("\(recipe.fx1) \(name)@\(time)：量不到字"); continue }
                    if result.ratio < LyricsFXContrastTests.minimum { failures.append("\(recipe.fx1) \(name)@\(time)：\(String(format: "%.2f", result.ratio))") }
                }
            }
        }
        #expect(failures.isEmpty, "\(variant)：\(failures.joined(separator: "；"))")
    }

    /// G2／G3 用與 VM 同一條連播規則（排除上一次）在變體目錄上抽
    static func playedRecipes(_ variant: JPopVariant) -> [ComposedRecipe] {
        var previous: ComposedRecipe?
        return (0..<UInt64(ReadabilityAudit.seeds)).compactMap { seed in
            guard case .composed(let recipe) = Composer.compose(profile: variant.profile, seed: FXHash.fnv1a64(variant.rawValue) ^ seed,
                                                                catalog: JPopPolicy.catalog(variant), avoiding: previous) else { return nil }
            previous = recipe
            return recipe
        }
    }

    @Test(arguments: JPopVariant.allCases)
    func nothingGoesBlankAndNothingStaysCovered(variant: JPopVariant) {
        let measurer = CoreTextMeasurer()
        let recipes = Self.playedRecipes(variant)
        #expect(recipes.count == ReadabilityAudit.seeds)
        for recipe in recipes {
            for fixture in ReadabilityAudit.fixtures {
                if let blank = ReadabilityAudit.longestBlank(fixture.timeline, recipe: recipe, measurer: measurer), blank.seconds > ReadabilityAudit.maxBlank + 1e-9 {
                    Issue.record("\(variant) \(fixture.name) \(recipe.fx1)：空白 \(blank)")
                }
                if let covered = ReadabilityAudit.longestCovered(fixture.timeline, recipe: recipe, measurer: measurer), covered.seconds > ReadabilityAudit.maxCovered + 1e-9 {
                    Issue.record("\(variant) \(fixture.name) \(recipe.fx1)：疊住 \(covered)")
                }
            }
        }
    }
}
