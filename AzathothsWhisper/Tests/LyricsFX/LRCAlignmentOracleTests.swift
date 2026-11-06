import Testing

@testable import AzathothsWhisper

// ⑩ 計劃 §4.1 不變式（R3-1）：以凍結的 revision 2 貪婪對齊為 oracle，固定種子產生自編隨機輸入逐筆比對。
// ⓐ 新版對上的 Music 行數 ≥ v2；ⓑ 新版未用反向群組且對上數＝v2 時，anchors／musicRate／lrcCoverage 逐值相同
@Suite("LRCAligner revision 3 vs revision 2 oracle")
struct LRCAlignmentOracleTests {
    static let caseCount = 600

    /// 編造的短句；含刻意的重複短句（oh、hey）製造貪婪陷阱
    static let phrases = [
        "Lanterns over the river", "Ash in the wind", "Count the silent bells", "Paper boats at dawn",
        "Stones under the old bridge", "Smoke above the hills", "Hold the lantern high", "Engines in the night",
        "Neon on the road", "Static on the radio", "Salt upon the window", "Ravens on the wire",
        "Oh", "Hey", "Oh oh", "Copper skies tonight", "Glass in the garden", "Embers in the snow",
    ]

    struct Case {
        let lyrics: String
        let lrc: [LRCLine]
    }

    static func makeCase(seed: UInt64) -> Case {
        var random = SplitMix64(seed: seed)
        func roll(_ percent: UInt64) -> Bool { random.next() % 100 < percent }
        func pick() -> String { phrases[Int(random.next() % UInt64(phrases.count))] }
        let base = (0..<(5 + Int(random.next() % 14))).map { _ in pick() }

        var music: [String] = []
        var index = 0
        while index < base.count {
            if roll(8) { index += 1; continue }                                   // Music 漏行
            if roll(8) { music.append(pick()) }                                    // Music 多一行
            if roll(12), index + 1 < base.count {                                  // Music 合成一行（正向串接）
                music.append(base[index] + " " + base[index + 1]); index += 2; continue
            }
            music.append(base[index]); index += 1
        }

        var cues: [String] = []
        index = 0
        while index < base.count {
            if roll(8) { index += 1; continue }                                   // LRC 漏行
            if roll(5) { cues.append("") }                                         // 空 cue
            if roll(6) { cues.append(pick()) }                                     // LRC 多一行
            if roll(12), index + 1 < base.count {                                  // LRC 合成一行（Music 拆行＝反向）
                cues.append(base[index] + " " + base[index + 1]); index += 2; continue
            }
            cues.append(base[index])
            if roll(6) { cues.append(base[index]) }                                // 重複
            index += 1
        }
        let lrc = cues.enumerated().map { LRCLine(start: Double($0.offset) * 4 + 5, text: $0.element) }
        return Case(lyrics: music.isEmpty ? base[0] : music.joined(separator: "\n"), lrc: lrc)
    }

    @Test func neverMatchesFewerLinesAndEqualsTheGreedyResultWhenGreedyIsOptimal() throws {
        var sawReverse = 0, sawImprovement = 0, sawIdentical = 0
        for seed in 0..<UInt64(Self.caseCount) {
            let sample = Self.makeCase(seed: seed)
            let lineCount = LyricsLines.lyricTexts(sample.lyrics).count
            let old = try #require(LRCAlignerV2Oracle.alignment(lyrics: sample.lyrics, lrc: sample.lrc))
            let new = try #require(LRCAligner.alignment(lyrics: sample.lyrics, lrc: sample.lrc))
            let matched = Int((new.musicRate * Double(lineCount)).rounded())
            #expect(matched >= old.matched, "ⓐ seed \(seed)")
            let usedReverse = new.groups != matched
            if usedReverse { sawReverse += 1 }
            if matched > old.matched { sawImprovement += 1 }
            if !usedReverse, matched == old.matched {
                sawIdentical += 1
                #expect(new.anchors == old.anchors, "ⓑ anchors seed \(seed)")
                #expect(new.musicRate == old.musicRate, "ⓑ musicRate seed \(seed)")
                #expect(new.lrcCoverage == old.lrcCoverage, "ⓑ lrcCoverage seed \(seed)")
            }
        }
        // 產生器確實涵蓋三種情況（否則這條測試什麼都沒驗）
        #expect(sawReverse > 0)
        #expect(sawImprovement > 0)
        #expect(sawIdentical > Self.caseCount / 4)
    }
}
