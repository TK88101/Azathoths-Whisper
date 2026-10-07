import CoreGraphics
import Testing

@testable import AzathothsWhisper

// B1 計劃 §3.4：模板池（由原型 lyrics-fx-preview.html:202-251 移植）。純函數
@Suite("Glyph templates")
struct GlyphTemplatesTests {
    static let context = GlyphContext(em: 40, width: 900, height: 560, radius: 495, dir: 1, side: -1, phase: 0.7, angle: 2.1, bend: 0.4)

    @Test(arguments: EnterTemplate.allCases)
    func everyEntranceEndsAtRest(template: EnterTemplate) {
        let end = template.transform(progress: 1, context: Self.context)
        #expect(abs(end.dx) < 1e-9 && abs(end.dy) < 1e-9 && abs(end.rotation) < 1e-9, "\(template)")
        #expect(abs(end.scale - 1) < 1e-9 && abs(end.scaleX - 1) < 1e-9 && abs(end.scaleY - 1) < 1e-9, "\(template)")
        #expect(end.alpha == 1 && end.ghost == 0 && end.specks == 0 && !end.negative, "\(template)")
    }

    @Test(arguments: EnterTemplate.allCases)
    func entranceValuesStayInRange(template: EnterTemplate) {
        for step in 0...20 {
            let value = template.transform(progress: Double(step) / 20, context: Self.context)
            #expect((0...1).contains(value.alpha), "\(template)@\(step)")
            #expect(value.scale > 0 && value.scaleX > 0 && value.scaleY > 0, "\(template)@\(step)")
            #expect((0...1).contains(value.ghost) && (0...1).contains(value.specks))
        }
    }

    @Test func slamStartsOffCanvasAndHardLands() {
        let start = EnterTemplate.slam.transform(progress: 0, context: Self.context)
        #expect(hypot(start.dx, start.dy) > Self.context.radius)
        #expect(EnterTemplate.slam.transform(progress: 0.5, context: Self.context).alpha == 1)
    }

    @Test func smokeIsAllGhostAtFirstAndCondenseIsAllSpecks() {
        #expect(EnterTemplate.smoke.transform(progress: 0, context: Self.context).ghost == 1)
        #expect(EnterTemplate.condense.transform(progress: 0, context: Self.context).specks == 1)
        #expect(EnterTemplate.negative.transform(progress: 0.1, context: Self.context).negative)
        #expect(!EnterTemplate.negative.transform(progress: 0.4, context: Self.context).negative)
    }

    @Test(arguments: [ExitTemplate.scatter, .fade, .dissolve])
    func exitsStartAtRestAndEndInvisible(template: ExitTemplate) {
        let start = template.transform(progress: 0, context: Self.context)
        #expect(start.alpha == 1 && start.dx == 0 && start.dy == 0)
        #expect(template.transform(progress: 1, context: Self.context).alpha == 0)
    }

    @Test func cutIsGoneAtOnce() {
        #expect(ExitTemplate.cut.transform(progress: 0, context: Self.context).alpha == 0)
    }

    @Test(arguments: HoldTemplate.allCases)
    func holdsStaySmall(template: HoldTemplate) {
        for step in 0...200 {
            let value = template.transform(time: Double(step) * 0.037, context: Self.context)
            #expect(abs(value.dx) <= Self.context.em * 0.13 && abs(value.dy) <= Self.context.em * 0.13, "\(template)")
            #expect(abs(value.rotation) <= 0.11 && abs(value.scale - 1) <= 0.041 && value.alpha == 1)
        }
    }

    @Test func stillDoesNothing() {
        #expect(HoldTemplate.still.transform(time: 3.3, context: Self.context) == .identity)
    }

    @Test func combiningAddsOffsetsAndMultipliesScaleAndAlpha() {
        let a = GlyphTransform(dx: 1, dy: 2, rotation: 0.1, scale: 2, alpha: 0.5)
        let b = GlyphTransform(dx: 3, dy: -1, rotation: 0.2, scale: 0.5, alpha: 0.5, ghost: 0.3)
        let combined = a.combined(with: b)
        #expect(combined.dx == 4 && combined.dy == 1 && abs(combined.rotation - 0.3) < 1e-12)
        #expect(combined.scale == 1 && combined.alpha == 0.25 && combined.ghost == 0.3)
    }
}

// B1 計劃 §3.4：逐字個性（移植 html:257-277）
@Suite("Glyph personality")
struct GlyphPersonalityTests {
    static let line = TimedLine(start: 10, end: 14, text: "Lanterns drift over water", isChorus: false)
    static let style = PersonalityStyle(
        enter: [(.slam, 1), (.fadeUp, 1)], enterDuration: 0.2...0.4, hold: [(.still, 3), (.drift, 1)], exit: [(.fade, 1)],
        vary: .init(size: 0.15, dy: 0.1, rotation: 0.05, scatter: 0.04), wordLevel: false
    )

    @Test func oneEntryPerNonBlankCharacter() {
        #expect(LinePersonalities.make(line: Self.line, seed: 1, style: Self.style).count == "Lanternsdriftoverwater".count)
    }

    @Test func theSameSeedGivesTheSamePersonalities() {
        #expect(LinePersonalities.make(line: Self.line, seed: 77, style: Self.style) == LinePersonalities.make(line: Self.line, seed: 77, style: Self.style))
        #expect(LinePersonalities.make(line: Self.line, seed: 77, style: Self.style) != LinePersonalities.make(line: Self.line, seed: 78, style: Self.style))
    }

    @Test func noCharacterStartsBeforeItsWord() {
        for seed in UInt64(0)..<64 {
            let personalities = LinePersonalities.make(line: Self.line, seed: seed, style: Self.style)
            for entry in personalities {
                #expect(entry.start >= Self.line.words[entry.wordIndex].start - 1e-9)
            }
        }
    }

    @Test func someCharactersFireInQuickSuccession() {
        let gaps = (UInt64(0)..<64).flatMap { seed -> [Double] in
            let personalities = LinePersonalities.make(line: Self.line, seed: seed, style: Self.style)
            return zip(personalities, personalities.dropFirst()).filter { $0.wordIndex == $1.wordIndex }.map { $1.start - $0.start }
        }
        #expect(gaps.contains { abs($0 - LinePersonalities.burstGap) < 1e-9 })
    }

    @Test func wordLevelEntrancesShareTheWordStartAndDirection() {
        var style = Self.style
        style.wordLevel = true
        let personalities = LinePersonalities.make(line: Self.line, seed: 5, style: style)
        for word in Dictionary(grouping: personalities, by: \.wordIndex).values {
            #expect(Set(word.map(\.start)).count == 1 && Set(word.map(\.dir)).count == 1 && Set(word.map(\.enter)).count == 1)
            #expect(word.first?.start == Self.line.words[word[0].wordIndex].start)
        }
    }

    @Test func variationStaysWithinTheStyleBounds() {
        let personalities = LinePersonalities.make(line: Self.line, seed: 9, style: Self.style)
        let sizeSpread = Self.style.vary.size * LinePersonalities.rawness
        for entry in personalities {
            #expect(abs(entry.size - 1) <= sizeSpread + 1e-9)
            #expect(abs(entry.dy) <= Self.style.vary.dy && abs(entry.rotation) <= Self.style.vary.rotation)
            #expect(entry.duration >= 0.2 * LinePersonalities.speed - 1e-9 && entry.duration <= 0.4 * LinePersonalities.speed + 1e-9)
            #expect([EnterTemplate.slam, .fadeUp].contains(entry.enter) && [HoldTemplate.still, .drift].contains(entry.hold))
        }
    }

    @Test func charactersInAWordShareTheFlightPath() {
        let personalities = LinePersonalities.make(line: Self.line, seed: 11, style: Self.style)
        for word in Dictionary(grouping: personalities, by: \.wordIndex).values {
            #expect(Set(word.map(\.angle)).count == 1 && Set(word.map(\.bend)).count == 1)
        }
    }
}
