// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// H-02 UI 測試閘門的假 Music（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.2）。
///
/// 測試組裝裡**唯一**被替換的依賴：其餘（RootView／AppModel／monitor／VM／ArtworkService）都是真的。
/// 不送任何 Apple Event、不碰使用者曲庫；只讀，`setLyrics` 一律拒絕。
struct CoverFlowUITestMusic: MusicControlling {
    private typealias Fixture = CoverFlowUITestFixture

    /// 見 `CoverFlowUITestFixture.defaultAlbumDelayMilliseconds`
    let albumDelay: Duration

    private static let lyrics = "fixture lyrics"

    func playerState() async throws -> PlayerState { .playing }

    func currentTrack() async throws -> TrackInfo? {
        let index = Fixture.playingIndex
        return TrackInfo(
            persistentID: Fixture.persistentID(at: index), artist: Fixture.artist,
            title: Fixture.title(at: index), album: Fixture.album,
            discNumber: 1, trackNumber: index + 1
        )
    }

    /// 歌詞非空：Editor 在歌詞為空時會自動上網抓詞
    func nowPlaying() async throws -> NowPlayingRead? {
        guard let track = try await currentTrack() else { return nil }
        return NowPlayingRead(track: track, lyrics: Self.lyrics)
    }

    func trackDetails(persistentIDs: [String]) async throws -> [TrackDetails] {
        persistentIDs.compactMap { id in
            guard let index = Fixture.index(of: id) else { return nil }
            return TrackDetails(
                persistentID: id, artist: Fixture.artist, title: Fixture.title(at: index), album: Fixture.album,
                discNumber: 1, trackNumber: index + 1, lyrics: Self.lyrics
            )
        }
    }

    func albumTracks(artist: String, album: String) async throws -> [AlbumTrack] {
        try await Task.sleep(for: albumDelay)
        guard artist == Fixture.artist, album == Fixture.album else { return [] }
        return (0..<Fixture.trackCount).map { index in
            AlbumTrack(
                persistentID: Fixture.persistentID(at: index), artist: Fixture.artist,
                title: Fixture.title(at: index), album: Fixture.album,
                discNumber: 1, trackNumber: index + 1, lyrics: Self.lyrics
            )
        }
    }

    func setLyrics(persistentID: String, lyrics: String) async throws -> Bool { false }

    func artworkData(persistentID: String) async throws -> Data? {
        guard let index = Fixture.index(of: persistentID) else { return nil }
        return Self.solidPNG(Fixture.color(at: index))
    }

    /// 512×512 單色 PNG，sRGB。整面同色：交疊區必落在卡片邊緣，整面同色即邊緣可辨
    private static func solidPNG(_ color: GateRGB, side: Int = 512) -> Data? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let fill = CGColor(colorSpace: space, components: [color.red, color.green, color.blue, 1]),
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.setFillColor(fill)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
#endif
