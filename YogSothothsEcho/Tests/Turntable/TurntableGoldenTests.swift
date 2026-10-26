import CoreGraphics
import Foundation
import RemoteProtocol
import Testing

@testable import YogSothothsEcho

// S7 T2（sprint-7-detail.md §4.2「行為不變的證明」）：皮膚重構前，用當時的程式記下唱機的版面、唱臂角度與點擊判定，
// 存成 Tests/Fixtures/turntable-golden-v1.json。之後的重構必須逐值相等。比對只讀 fixture、不重算基準；
// 產生 fixture 只在設了 TURNTABLE_GOLDEN_DIR（xcodebuild 用 TEST_RUNNER_TURNTABLE_GOLDEN_DIR）時跑，寫到該目錄

struct TurntableGolden: Codable, Equatable {
    struct Rect: Codable, Equatable {
        let x, y, w, h: Double
        init(_ r: CGRect) { (x, y, w, h) = (r.minX, r.minY, r.width, r.height) }
    }
    struct Point: Codable, Equatable {
        let x, y: Double
        init(_ p: CGPoint) { (x, y) = (p.x, p.y) }
    }
    struct LayoutCase: Codable, Equatable {
        let width, height: Double
        let fullCover: Bool
        let scale: Double
        let record, cover, arm, armBase: Rect
        let armPivot: Point
        /// 0°、0.5°…33.5° 的唱臂外接框
        let armBoxes: [Rect]
    }
    struct HitCase: Codable, Equatable {
        let width, height: Double
        let sleeve: String
        let angle: Double
        /// 取樣點逐列（y 外圈、x 內圈）的判定，r＝唱片、c＝封套、o＝浮層切換；以「字元＋次數」連續段壓縮
        let runs: String
    }
    struct PlaybackCase: Codable, Equatable {
        let state: String
        let position: Double
        let duration: Double?
        let angle: Double
    }
    let sampling: String
    let layouts: [LayoutCase]
    let angleForProgress: [Double]
    let progressForAngle: [Double]
    let playback: [PlaybackCase]
    let hits: [HitCase]
}

enum TurntableGoldenCapture {
    static let landscapeSizes: [CGSize] = [
        CGSize(width: 1024, height: 768), CGSize(width: 1080, height: 810), CGSize(width: 1180, height: 820),
        CGSize(width: 1194, height: 834), CGSize(width: 1210, height: 834), CGSize(width: 1366, height: 1024),
        CGSize(width: 1376, height: 1032),
    ]
    static let gridStep: CGFloat = 8
    static let armBoxAngles = Array(stride(from: 0.0, through: 33.5, by: 0.5))
    /// 點擊格的唱臂角度：每 2°，另加落針與播完兩個端點
    static let hitAngles = Array(stride(from: 0.0, through: 32.0, by: 2.0)) + [14.1, 33.4]
    static let progresses = Array(stride(from: 0.0, through: 1.0, by: 0.05))
    static let angles = Array(stride(from: -2.0, through: 36.0, by: 0.5))
    static let sampling = "container=(0,24,w,h-44)；點格 x,y＝0,8,16…，末點補上 w／h；"
        + "hit 角度＝0…32 每 2°＋14.1、33.4；sleeve＝resting／midway／full"

    static func safeRect(_ size: CGSize) -> CGRect { CGRect(x: 0, y: 24, width: size.width, height: size.height - 44) }

    static func sleeves() -> [(String, CoverSleeveState)] {
        var midway = CoverSleeveState()
        _ = midway.tap()
        var full = CoverSleeveState()
        _ = full.tap()
        full.midwayFinished()
        return [("resting", CoverSleeveState()), ("midway", midway), ("full", full)]
    }

    static func axis(_ length: CGFloat) -> [CGFloat] {
        Array(stride(from: 0, to: length, by: gridStep)) + [length]
    }

    static func runs(_ symbols: [Character]) -> String {
        var out = "", current: Character?, count = 0
        for symbol in symbols {
            if symbol == current { count += 1; continue }
            if let current { out += "\(current)\(count)" }
            current = symbol
            count = 1
        }
        if let current { out += "\(current)\(count)" }
        return out
    }

    static func symbol(_ target: TurntableHitTest.Target) -> Character {
        switch target {
        case .record: "r"
        case .cover: "c"
        case .overlayToggle: "o"
        }
    }

    static func capture() -> TurntableGolden {
        var layouts: [TurntableGolden.LayoutCase] = []
        var hits: [TurntableGolden.HitCase] = []
        for size in landscapeSizes {
            let container = safeRect(size)
            for fullCover in [false, true] {
                let l = TurntableLayout(container: container, fullCover: fullCover, skin: .classic)
                layouts.append(.init(width: size.width, height: size.height, fullCover: fullCover, scale: l.scale,
                                     record: .init(l.record), cover: .init(l.cover), arm: .init(l.arm), armBase: .init(l.armBase),
                                     armPivot: .init(l.armPivot), armBoxes: armBoxAngles.map { .init(l.armBoundingBox(angle: $0)) }))
            }
            for (name, sleeve) in sleeves() {
                let l = TurntableLayout(container: container, fullCover: sleeve.isFullCover, skin: .classic)
                for angle in hitAngles {
                    var symbols: [Character] = []
                    for y in axis(size.height) {
                        for x in axis(size.width) {
                            symbols.append(symbol(TurntableHitTest.classify(CGPoint(x: x, y: y), layout: l, sleeve: sleeve, armAngle: angle)))
                        }
                    }
                    hits.append(.init(width: size.width, height: size.height, sleeve: name, angle: angle, runs: runs(symbols)))
                }
            }
        }
        let playback: [(PlaybackState, Double, Double?)] = [
            (.playing, 30, 200), (.playing, 0, 200), (.playing, 300, 200), (.playing, 30, nil), (.playing, 30, 0),
            (.paused, 30, 200), (.stopped, 30, 200),
        ]
        return TurntableGolden(
            sampling: sampling, layouts: layouts,
            angleForProgress: progresses.map { ResolvedTurntableSkin.classic.angle(progress: $0) },
            progressForAngle: angles.map { ResolvedTurntableSkin.classic.progress(angle: $0) },
            playback: playback.map { .init(state: $0.0.rawValue, position: $0.1, duration: $0.2,
                                           angle: ResolvedTurntableSkin.classic.playbackAngle(state: $0.0, position: $0.1, duration: $0.2)) },
            hits: hits)
    }
}

struct TurntableGoldenTests {
    static let fixtureName = "turntable-golden-v1"
    static let tolerance = 1e-9

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TURNTABLE_GOLDEN_DIR"]?.isEmpty == false))
    func writeFixture() throws {
        let dir = try #require(ProcessInfo.processInfo.environment["TURNTABLE_GOLDEN_DIR"])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(Self.fixtureName).json")
        try encoder.encode(TurntableGoldenCapture.capture()).write(to: url)
        print("golden fixture written: \(url.path)")
    }

    @Test func currentGeometryMatchesTheFixture() throws {
        let url = try #require(Bundle(for: GoldenBundleToken.self).url(forResource: Self.fixtureName, withExtension: "json"),
                               "缺 \(Self.fixtureName).json")
        let expected = try JSONDecoder().decode(TurntableGolden.self, from: Data(contentsOf: url))
        let actual = TurntableGoldenCapture.capture()
        #expect(actual.sampling == expected.sampling)
        #expect(actual.layouts.count == expected.layouts.count)
        for (a, e) in zip(actual.layouts, expected.layouts) {
            #expect(Self.close(a, e), "layout \(e.width)x\(e.height) fullCover=\(e.fullCover)")
        }
        #expect(Self.close(actual.angleForProgress, expected.angleForProgress))
        #expect(Self.close(actual.progressForAngle, expected.progressForAngle))
        #expect(actual.playback.count == expected.playback.count)
        for (a, e) in zip(actual.playback, expected.playback) {
            #expect(a.state == e.state && a.position == e.position && a.duration == e.duration && abs(a.angle - e.angle) <= Self.tolerance)
        }
        #expect(actual.hits.count == expected.hits.count)
        for (a, e) in zip(actual.hits, expected.hits) {
            #expect(a == e, "hit \(e.width)x\(e.height) \(e.sleeve) \(e.angle)°")
        }
    }

    private static func close(_ a: [Double], _ b: [Double]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }

    private static func close(_ a: TurntableGolden.Rect, _ b: TurntableGolden.Rect) -> Bool {
        close([a.x, a.y, a.w, a.h], [b.x, b.y, b.w, b.h])
    }

    private static func close(_ a: TurntableGolden.LayoutCase, _ b: TurntableGolden.LayoutCase) -> Bool {
        a.width == b.width && a.height == b.height && a.fullCover == b.fullCover && abs(a.scale - b.scale) <= tolerance
            && close(a.record, b.record) && close(a.cover, b.cover) && close(a.arm, b.arm) && close(a.armBase, b.armBase)
            && close([a.armPivot.x, a.armPivot.y], [b.armPivot.x, b.armPivot.y])
            && a.armBoxes.count == b.armBoxes.count && zip(a.armBoxes, b.armBoxes).allSatisfy { close($0, $1) }
    }
}

/// 找測試 bundle 用
private final class GoldenBundleToken {}
