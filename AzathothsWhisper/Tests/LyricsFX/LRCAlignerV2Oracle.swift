@testable import AzathothsWhisper

/// ⑩ 計劃 §4.1 不變式 ⓐⓑ 的 oracle：revision 2 的貪婪前向 `matchedIndices`（main dbc48da）原樣保留，只供測試比對。
/// **勿改它來配合新實作**——它的價值就在於凍結舊行為
enum LRCAlignerV2Oracle {
    struct Result: Equatable {
        let anchors: [Double?]
        let musicRate: Double
        let lrcCoverage: Double
        var matched: Int { anchors.compactMap { $0 }.count }
    }

    private struct Hit {
        let index: Int
        let span: Int
    }

    static func alignment(lyrics: String, lrc: [LRCLine]) -> Result? {
        let texts = LyricsLines.lyricTexts(lyrics)
        guard !texts.isEmpty else { return nil }
        let music = texts.map { Array(LRCAligner.normalized($0)) }
        let cues = lrc.map { Array(LRCAligner.normalized($0.text)) }
        let hits = matchedIndices(music, cues: cues)
        let matched = hits.compactMap { $0 }.count
        let comparable = cues.filter { !$0.isEmpty }.count
        return Result(
            anchors: hits.map { $0.map { lrc[$0.index].start } },
            musicRate: Double(matched) / Double(texts.count),
            lrcCoverage: comparable == 0 ? 0 : Double(matched) / Double(comparable)
        )
    }

    private static func matchedIndices(_ music: [[Character]], cues: [[Character]]) -> [Hit?] {
        var cursor = 0
        var hits: [Hit?] = []
        for line in music {
            var hit: Hit?
            search: for index in cues.indices.dropFirst(cursor) {
                var joined: [Character] = []
                for span in 1...LRCAligner.maxMergedCues {
                    let next = index + span - 1
                    guard next < cues.count, !cues[next].isEmpty else { break }
                    joined += cues[next]
                    if LRCAligner.isSimilar(line, joined) {
                        hit = Hit(index: index, span: span)
                        break search
                    }
                }
            }
            if let hit { cursor = hit.index + hit.span }
            hits.append(hit)
        }
        return hits
    }
}
