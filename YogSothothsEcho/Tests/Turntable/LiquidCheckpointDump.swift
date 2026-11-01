#if LIQUID_SAMPLE
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import YogSothothsEcho

// CR-038 L-T2 自查產物：設 TEST_RUNNER_LIQUID_DUMP_DIR 時，把三個檢查點（起轉外圈落後、停後反向回彈、外緣聚集）
// 的逐格 PNG 與內／外半徑相位差寫到該資料夾；沒設就跳過（不影響一般測試）
@MainActor
struct LiquidCheckpointDump {
    nonisolated static var directory: URL? {
        ProcessInfo.processInfo.environment["LIQUID_DUMP_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    @Test(.enabled(if: LiquidCheckpointDump.directory != nil))
    func dumpCheckpoints() throws {
        let dir = try #require(Self.directory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines: [String] = ["preset,t,phase,disc,lag,fling,innerPhaseDeg,outerPhaseDeg"]
        // 內／外半徑的液體相位（相對盤）＝ −s·w(u)；著色器的方向與幅度由 LiquidVinylRenderTests 以像素驗過
        func phase(_ lag: Double, r: Double) -> Double { let u = (r - 0.452) / (0.97 - 0.452); return -lag * u * u }
        for preset in LiquidPreset.allCases {
            var motion = LiquidMotion(preset: preset, discAngle: 0, at: 0)
            var disc = 0.0
            var now = 0.0
            // 0–8 s 正常轉、8–14 s 剛停；每 0.25 s 記一點，關鍵時刻存圖
            let keyTimes: Set<Int> = [1, 2, 4, 32, 33, 34, 35, 36, 38, 40]
            for tick in 1...56 {
                let speed = tick <= 32 ? RecordSpin.degreesPerSecond : 0
                for _ in 0..<30 {
                    now += 1.0 / 120
                    disc += speed / 120
                    motion.advance(to: disc, at: now)
                }
                let frame = motion.frame(reduceMotion: false)
                let state = tick <= 32 ? "spin" : "stopped"
                lines.append(String(format: "%@,%.2f,%@,%.2f,%.3f,%.3f,%.2f,%.2f", preset.rawValue, now, state, disc, frame.lag, frame.fling,
                                    phase(frame.lag, r: 0.56), phase(frame.lag, r: 0.92)))
                if keyTimes.contains(tick) {
                    let view = VinylRecordView(side: 600, style: .classic, splash: .style1, colors: .fallback,
                                               label: .init(title: "Sample", artist: "Liquid"), angle: frame.discAngle, liquid: frame)
                    let renderer = ImageRenderer(content: view.frame(width: 600, height: 600).background(Color(white: 0.3)))
                    renderer.scale = 1
                    let image = try #require(renderer.uiImage?.pngData())
                    try image.write(to: dir.appendingPathComponent(String(format: "%@-t%05.2f.png", preset.rawValue, now)))
                }
            }
        }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("phase.csv"), atomically: true, encoding: .utf8)
    }
}
#endif
