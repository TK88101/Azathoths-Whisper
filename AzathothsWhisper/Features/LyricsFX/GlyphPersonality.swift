import CoreGraphics
import Foundation

/// 風格給個性的參數（由組合器的 enter／exit 元件與歌曲目標值推出）
struct PersonalityStyle: Sendable {
    struct Vary: Sendable {
        let size: Double
        let dy: Double
        let rotation: Double
        let scatter: Double
    }

    var enter: [(EnterTemplate, Double)]
    var enterDuration: ClosedRange<Double>
    var hold: [(HoldTemplate, Double)]
    var exit: [(ExitTemplate, Double)]
    var vary: Vary
    /// 整詞同時出場、共用方向與模板（slam、march）
    var wordLevel: Bool
}

/// 一個字的個性（原型 `P`）
struct GlyphPersonality: Equatable, Sendable {
    let wordIndex: Int
    let start: Double
    let duration: Double
    let enter: EnterTemplate
    let hold: HoldTemplate
    let exit: ExitTemplate
    let size: Double
    let dy: Double
    let rotation: Double
    let dir: CGFloat
    let phase: Double
    let scatterX: Double
    let scatterY: Double
    let angle: Double
    let bend: Double
    /// pile 版面用：整詞的錨點與傾斜
    let wordX: Double
    let wordY: Double
    let wordRotation: Double
    /// 字在畫面上停留的壽命（slam：到時硬切）
    let lifetime: Double
}

enum LinePersonalities {
    /// 連發：前一字出場後 30 ms
    static let burstGap = 0.03
    /// 原型的 TONE 預設（raw 0.6、speed 0.6）推出的兩個常數
    static let rawness = 1.08
    static let speed = 0.93

    /// 移植原型 `personalities`（html:257-277）：先抽每個詞的方向與壽命，再逐字抽時刻、模板與變異
    static func make(line: TimedLine, seed: UInt64, style: PersonalityStyle) -> [GlyphPersonality] {
        var random = SplitMix64(seed: seed)
        let words = line.words.map { _ in WordDraw(&random, style: style) }
        var result: [GlyphPersonality] = []
        for (wordIndex, word) in line.words.enumerated() {
            let characters = word.text.filter { !$0.isWhitespace }
            let count = characters.count
            let span = word.end - word.start
            let shared = words[wordIndex]
            for indexInWord in 0..<count {
                var start = word.start + Double(indexInWord) / Double(count) * span * 0.9
                    + (random.unit() - 0.5) * 0.35 * span / Double(count)
                if indexInWord > 0, let previous = result.last, random.unit() < 0.3 {
                    start = previous.start + burstGap
                }
                start = style.wordLevel ? word.start : max(word.start, start)
                let duration = (style.wordLevel ? shared.duration : random.uniform(in: style.enterDuration)) * speed
                let enter = style.wordLevel ? shared.enter : pick(style.enter, &random)
                let hold = pick(style.hold, &random)
                let exit = pick(style.exit, &random)
                let size = 1 + (random.unit() - 0.5) * 2 * style.vary.size * rawness
                let dy = (random.unit() - 0.5) * 2 * style.vary.dy
                let rotation = (random.unit() - 0.5) * 2 * style.vary.rotation
                let dir: CGFloat = style.wordLevel ? shared.dir : (random.unit() < 0.5 ? -1 : 1)
                result.append(GlyphPersonality(
                    wordIndex: wordIndex, start: start, duration: duration, enter: enter, hold: hold, exit: exit,
                    size: size, dy: dy, rotation: rotation, dir: dir, phase: random.unit() * 2 * .pi,
                    scatterX: (random.unit() - 0.5) * 2 * style.vary.scatter, scatterY: (random.unit() - 0.5) * 2 * style.vary.scatter,
                    angle: shared.angle, bend: shared.bend, wordX: shared.x, wordY: shared.y, wordRotation: shared.rotation, lifetime: shared.lifetime
                ))
            }
        }
        return result
    }

    /// 權重抽籤；權重和為 0 或清單空時取第一項（清單不得為空，由目錄驗證器保證）
    static func pick<T>(_ weights: [(T, Double)], _ random: inout SplitMix64) -> T {
        let total = weights.reduce(0) { $0 + $1.1 }
        var x = random.unit() * total
        for (value, weight) in weights {
            x -= weight
            if x <= 0 { return value }
        }
        return weights[weights.count - 1].0
    }

    /// 一個詞共用的抽籤結果
    private struct WordDraw {
        let angle, bend, x, y, rotation, lifetime, duration: Double
        let dir: CGFloat
        let enter: EnterTemplate

        init(_ random: inout SplitMix64, style: PersonalityStyle) {
            angle = random.unit() * 2 * .pi
            bend = (random.unit() - 0.5) * 2.2
            dir = random.unit() < 0.5 ? -1 : 1
            x = (random.unit() - 0.5) * 0.6
            y = (random.unit() - 0.5) * 0.56
            rotation = (random.unit() - 0.5) * 0.5
            lifetime = 2.8 + random.unit()
            enter = LinePersonalities.pick(style.enter, &random)
            duration = random.uniform(in: style.enterDuration)
        }
    }
}
