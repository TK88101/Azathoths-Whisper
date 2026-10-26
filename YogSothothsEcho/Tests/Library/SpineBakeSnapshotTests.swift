import CoreGraphics
import Foundation
import ImageIO
import RemoteProtocol
import SwiftUI
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import YogSothothsEcho

// S6 #6-1 g 版 T0（s6-61-g-perf-wear.md T0）：磨損截圖給使用者挑——只在設了 YSE_SNAPSHOT_DIR 時輸出
// （xcodebuild 以 TEST_RUNNER_YSE_SNAPSHOT_DIR 傳入；YSE_SNAPSHOT_SOURCE＝封面素材資料夾 dark/light/mid.png）
@MainActor
struct SpineBakeSnapshotTests {
    nonisolated static let environment = ProcessInfo.processInfo.environment
    nonisolated static var outputDirectory: URL? { environment["YSE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } }
    static let sources = ["dark", "light", "mid"]

    init() { FaceTextureCache.shared.rendersSynchronously = true }

    static func cover(_ name: String) -> UIImage? {
        guard let folder = environment["YSE_SNAPSHOT_SOURCE"] else { return nil }
        return UIImage(contentsOfFile: folder + "/\(name).png")
    }

    static func album(_ id: String) -> AlbumSummary {
        AlbumSummary(id: id, title: "Seen Through The Veils Of Darkness", artist: "Gehenna", trackCount: 9, artworkToken: "t")
    }

    static func write(_ image: CGImage, _ name: String) throws {
        guard let directory = outputDirectory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name + ".png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    static func baked(_ id: String, cover: UIImage?, side: CarouselSide, metrics: SpineCarouselMetrics) -> CGImage? {
        SpineBake.render(SpineBake.input(album: album(id), image: cover, side: side, thickness: metrics.spine, cover: metrics.cover, scale: 2))
    }

    @Test(.enabled(if: SpineBakeSnapshotTests.outputDirectory != nil))
    func exportSpines() throws {
        let m = SpineCarouselTests.pro13
        for (index, fixture) in SpineBakeTests.fixtures.enumerated() {
            let cover = Self.cover(Self.sources[index % Self.sources.count])
            for side in [CarouselSide.left, .right] {
                let tag = "\(fixture.id)-\(side == .left ? "L" : "R")"
                try Self.write(try #require(Self.baked(fixture.id, cover: cover, side: side, metrics: m)), "new-\(tag)")
                let old = SpineFace(album: Self.album(fixture.id), image: cover, cover: m.cover, thickness: m.spine, side: side)
                let renderer = ImageRenderer(content: old)
                renderer.scale = 2
                try Self.write(try #require(renderer.cgImage), "old-\(tag)")
            }
        }
    }

    /// 接縫：同一盒子在 30°／60°／80°，A＝正面照舊、A′＝正面靠書脊那邊同輪廓挖角
    @Test(.enabled(if: SpineBakeSnapshotTests.outputDirectory != nil))
    func exportSeams() throws {
        let m = SpineCarouselTests.pro13
        for (index, fixture) in SpineBakeTests.fixtures.enumerated() where fixture.grade != .new {
            let cover = Self.cover(Self.sources[index % Self.sources.count])
            let spine = try #require(Self.baked(fixture.id, cover: cover, side: .left, metrics: m))
            for angle in [30.0, 60.0, 80.0] {
                for variant in ["A", "A2"] {
                    let scene = SeamScene(album: Self.album(fixture.id), cover: cover, spine: spine, metrics: m,
                                          pose: BoxPose(x: -m.cover * 0.15, rotationDegrees: angle, side: .left), chipped: variant == "A2")
                    let renderer = ImageRenderer(content: scene)
                    renderer.scale = 2
                    try Self.write(try #require(renderer.cgImage), "seam-\(fixture.id)-\(Int(angle))-\(variant)")
                }
            }
        }
    }
}

/// 截圖用場景：production `BoxProjection`、正面照用 `CoverFace`、書脊貼烘焙圖
private struct SeamScene: View {
    let album: AlbumSummary
    let cover: UIImage?
    let spine: CGImage
    let metrics: SpineCarouselMetrics
    let pose: BoxPose
    let chipped: Bool

    var body: some View {
        let projection = BoxProjection(metrics: metrics)
        ZStack(alignment: .topLeading) {
            Color(red: 0.20, green: 0.24, blue: 0.30)
            if projection.isFacingViewer(.front, pose: pose) {
                CoverFace(album: album, image: cover, length: metrics.cover, side: pose.side)
                    .mask { if chipped { FoldChipMask(albumID: album.id).fill(style: FillStyle(eoFill: true)) } else { Rectangle() } }
                    .projectionEffect(ProjectionTransform(projection.transform(.front, pose: pose)))
            }
            if projection.isFacingViewer(.spine, pose: pose) {
                Image(decorative: spine, scale: 2).resizable()
                    .frame(width: metrics.spine, height: metrics.cover)
                    .projectionEffect(ProjectionTransform(projection.transform(.spine, pose: pose)))
            }
        }
        .frame(width: metrics.browse.width, height: metrics.browse.height)
    }
}

/// A′：正面靠書脊那一邊（左側盒＝leading）的上下角，以書脊同一組角缺尺寸挖掉（只為截圖比較）
private struct FoldChipMask: Shape {
    let albumID: String

    func path(in rect: CGRect) -> Path {
        let u = rect.height / SpineCarouselMetrics.referenceCover
        let shape = SpineWear.shape(albumID: albumID), p = SpineBakeOutline.profile(shape, u: u)
        var jag = SpineWear.Jag(seed: SpineWear.seed(albumID: albumID) ^ 0xC0, spacing: 1.2 * u)
        var path = Path(rect)
        for (index, corner) in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY)].enumerated() {
            let radius = 1.6 * p.cornerRadius * (0.6 + 0.8 * CGFloat(shape.corners[index * 2] / 1.5)) + p.ends[index]
            path.addPath(jag.circle(center: corner, radius: radius, amplitude: 0.35 * radius, step: 0.4 * u))
        }
        return path
    }
}

// 唱機鈕候選（使用者 2026-10-24 問反色）：空心／實心光碟並排，只在設了 YSE_SNAPSHOT_DIR 時輸出
@MainActor
struct DockGlyphSnapshotTests {
    @Test(.enabled(if: SpineBakeSnapshotTests.outputDirectory != nil))
    func exportTurntableGlyphs() throws {
        let row = HStack(spacing: 40) {
            ForEach(["record.circle", "opticaldisc", "opticaldisc.fill"], id: \.self) { name in
                VStack(spacing: 8) {
                    Image(systemName: name).font(.system(size: 22)).foregroundStyle(DockPresentation.frostInk)
                        .frame(width: 44, height: 44)
                        .background(Capsule().fill(Color(white: 0.82)))
                    Text(verbatim: name).font(.caption2).foregroundStyle(.black)
                }
            }
        }
        .padding(24)
        .background(Color(white: 0.9))
        let renderer = ImageRenderer(content: row)
        renderer.scale = 4
        try SpineBakeSnapshotTests.write(try #require(renderer.cgImage), "dock-turntable-glyphs")
        #expect(UIImage(systemName: "opticaldisc.fill") != nil, "opticaldisc.fill 存在")
    }
}
