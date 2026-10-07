import CoreGraphics
import CoreText
import Foundation
import SwiftUI
import Testing

@testable import AzathothsWhisper

// B1 計劃 §3.10：兩個家族的探針（離屏定格＋6 秒 30 fps 動圖＋manifest）給使用者看「對／不對」。歌詞為編造句
@MainActor
@Suite("LyricsFX probes")
struct LyricsFXProbeRenderTests {
    static let canvas = CGSize(width: 960, height: 600)
    static let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("azw-lyricsfx-probe")
    static let families: [(name: String, genre: String)] = [("black", "Black Metal"), ("symphonic", "Symphonic Metal")]
    /// 同一首歌連播 10 次（每次每槽排除上一次）：讓使用者看到各元件輪流出現
    static let nonces: [UInt64] = Array(stride(from: 101, through: 1010, by: 101))
    /// 定格的時刻：進場中、停留、換行（前一行退場＋下一行進場）、行尾後的退場
    static let moments: [(name: String, time: Double)] = [("1-entering", 2.4), ("2-holding", 4.6), ("3-line-change", 5.7), ("4-exiting", 9.3)]

    static var timeline: LyricsTimeline {
        LyricsTimelineBuilder.build(lyrics: LyricsFXPreviewFixture.lyrics, duration: LyricsFXPreviewFixture.duration)!
    }

    /// 同一首歌連播：每次排除上一次的字型（與 VM 的字型歷史同一條規則）
    static func recipe(genre: String, nonce: UInt64, avoiding previous: ComposedRecipe?) throws -> ComposedRecipe {
        guard case .profile(let profile) = SongProfileResolver.resolve(artist: "Paper Lantern Ensemble", genre: genre),
              case .composed(let recipe) = Composer.compose(profile: profile, seed: FXHash.fnv1a64("probe") ^ nonce, avoiding: previous) else {
            Issue.record("\(genre) 沒有組合配方")
            throw CancellationError()
        }
        return recipe
    }

    static func image(time: Double, recipe: SessionRecipe, scale: CGFloat) -> CGImage? {
        let measurer = CoreTextMeasurer()
        let paths = GlyphPathCache()
        let timeline = timeline
        let view = Canvas { context, size in
            let plan = LyricsFXFrame.plan(timeline: timeline, time: time, size: size, motion: .full, recipe: recipe, measurer: measurer)
            LyricsFXCanvas.draw(plan, in: context, size: size, paths: paths)
        }
        .frame(width: canvas.width, height: canvas.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// 每個元件的字型都真的載入了（不是退回系統字）——探針才不會失真
    @Test func everyCatalogFontIsRegistered() {
        let fonts = FaceFonts()
        for component in LyricsFXCatalog.components(in: .font) {
            guard case .font(let face) = component.payload else { continue }
            let family = CTFontCopyFamilyName(fonts.font(face, size: 40)) as String
            #expect(family == face.family, "\(component.id) 實得 \(family)")
            #expect(fonts.scalesLinearly(face), "\(component.id) 有 wght 以外的可變軸")
        }
    }

    @Test func eachBundledFontShipsWithItsLicence() {
        for name in ["LICENSE-Catacombs", "OFL-GrimoireOfDeath", "OFL-UnifrakturMaguntia", "OFL-Cinzel", "OFL-CormorantGaramond", "README-Cenobyte"] {
            #expect(Bundle.main.url(forResource: name, withExtension: "txt") != nil, "\(name)")
        }
    }

    @Test func writesStillsGIFsAndManifests() throws {
        var manifest: [[String: Any]] = []
        for family in Self.families {
            var previous: ComposedRecipe?
            for nonce in Self.nonces {
                let recipe = try Self.recipe(genre: family.genre, nonce: nonce, avoiding: previous)
                previous = recipe
                let folder = Self.directory.appendingPathComponent("\(family.name)/nonce-\(nonce)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for moment in Self.moments {
                    let still = try #require(Self.image(time: moment.time, recipe: .composed(recipe), scale: 2))
                    #expect(still.width == Int(Self.canvas.width * 2))
                    #expect(LyricsFXPreviewRenderTests.litPixels(still) > 1000, "\(family.name) \(nonce) \(moment.name)")
                    _ = try PreviewImageWriter.png(still, to: folder.appendingPathComponent("\(moment.name).png"))
                }
                let frames = try (0..<180).map { index in
                    try #require(Self.image(time: 1.8 + Double(index) / 30, recipe: .composed(recipe), scale: 1))
                }
                _ = try PreviewImageWriter.gif(frames, delay: 1.0 / 30, to: folder.appendingPathComponent("6s.gif"))
                manifest.append([
                    "family": family.name, "genre": family.genre, "nonce": nonce,
                    "font": recipe.font, "backdrop": recipe.backdrop, "enter": recipe.enter, "exit": recipe.exit,
                    "fx": [recipe.fx1, recipe.fx2], "palette": recipe.palette, "folder": folder.path,
                ])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Self.directory.appendingPathComponent("manifest.json"))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(decoded.count == Self.families.count * Self.nonces.count)
        for entry in decoded {
            for key in ["font", "backdrop", "enter", "exit", "palette"] {
                #expect(LyricsFXCatalog.component(entry[key] as? String ?? "") != nil, "\(key)")
            }
        }
    }
}
