import CoreGraphics

@testable import AzathothsWhisper

/// mono 回歸網的 fixture 集（B1 計劃 T2 DoD②）：折行、CJK、間奏只剩預覽、換行重疊、末行淡出、reduced。歌詞為編造句
enum MonoGoldenFixtures {
    static func line(_ start: Double, _ end: Double, _ text: String) -> TimedLine {
        TimedLine(start: start, end: end, text: text, isChorus: false)
    }

    static let cases: [(String, LyricsTimeline, CGSize)] = [
        ("basic", LyricsTimeline(lines: [line(1, 4, "Paper boats at dawn"), line(10, 14, "Quiet harbor")], source: .embeddedLRC, duration: 60), CGSize(width: 1000, height: 600)),
        ("wrap", LyricsTimeline(lines: [line(1, 4, String(repeating: "lanterns drift over water ", count: 6)), line(4, 8, "Salt on the rope and the evening bell")], source: .embeddedLRC, duration: 60), CGSize(width: 700, height: 500)),
        ("cjk", LyricsTimeline(lines: [line(1, 4, "灯籠が川を流れてゆく夜"), line(4, 8, "静かな港")], source: .embeddedLRC, duration: 60), CGSize(width: 800, height: 520)),
        ("gap", LyricsTimeline(lines: [line(1, 4, "Paper boats"), line(4, 6, "   "), line(9, 12, "Morning tide")], source: .estimated, duration: 12), CGSize(width: 900, height: 560)),
    ]

    static let times: [Double] = [-0.5, 1.0, 1.1, 1.2, 3.0, 4.05, 4.2, 5.0, 7.5, 8.5, 12.2, 14.1]
}
