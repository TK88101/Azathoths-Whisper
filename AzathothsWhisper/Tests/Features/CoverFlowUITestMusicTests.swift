import AppKit
import Foundation
import Testing

@testable import AzathothsWhisper

// H-02 UI 測試閘門的假 Music 與測試組裝（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.1–3.2）。
//
// 閘門的像素判定靠「每張卡一個辨識色」：若假 Music 產的圖經 `ArtworkService.thumbnail`
// 解碼後顏色走樣，UITest 的疊放判定就不再可信——所以這一段在單元層先釘住。
@Suite("CoverFlowUITestMusic")
struct CoverFlowUITestMusicTests {
    private typealias Fixture = CoverFlowUITestFixture

    private let music = CoverFlowUITestMusic(albumDelay: .zero)

    @Test func albumIsTwentyTracksInDisplayOrder() async throws {
        let tracks = try await music.albumTracks(artist: Fixture.artist, album: Fixture.album)
        #expect(tracks.map(\.persistentID) == (0..<Fixture.trackCount).map(Fixture.persistentID(at:)))
        #expect(tracks == tracks.sortedForDisplay())
        #expect(tracks.allSatisfy { $0.hasLyrics })
    }

    @Test func foreignAlbumIsEmpty() async throws {
        #expect(try await music.albumTracks(artist: "Someone Else", album: Fixture.album).isEmpty)
        #expect(try await music.albumTracks(artist: Fixture.artist, album: "Other").isEmpty)
    }

    /// 當前曲固定為播放索引：自動居中的目標是已知的，C3 才有絕對目標可比
    @Test func nowPlayingIsTheFixedInteriorTrack() async throws {
        let current = try #require(try await music.currentTrack())
        #expect(current.persistentID == Fixture.persistentID(at: Fixture.playingIndex))
        #expect(current.albumKey == "\(Fixture.artist)\u{1}\(Fixture.album)")
        #expect(try await music.playerState() == .playing)
    }

    /// 歌詞必須非空：Editor 在歌詞為空時會自動上網抓詞（EditorViewModel.swift:82-88）
    @Test func lyricsAreNonEmptySoEditorNeverFetches() async throws {
        let lyrics = try #require(try await music.nowPlaying()?.lyrics)
        #expect(!lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// 卡片詳情：已知 ID 回傳 fixture 資料（歌詞非空＝有詞），未知 ID 不回傳
    @Test func trackDetailsCoverKnownIDsOnly() async throws {
        let known = Fixture.persistentID(at: 3)
        let details = try await music.trackDetails(persistentIDs: [known, "NOT-A-FIXTURE"])
        #expect(details.map(\.persistentID) == [known])
        #expect(details.first?.title == Fixture.title(at: 3))
        #expect(details.first?.trackNumber == 4)
        #expect(details.first?.lyrics?.isEmpty == false)
    }

    @Test func nowPlayingPairsTheFixedTrackWithItsLyrics() async throws {
        let read = try #require(try await music.nowPlaying())
        #expect(read.track.persistentID == Fixture.persistentID(at: Fixture.playingIndex))
    }

    @Test func writesAreRefused() async throws {
        #expect(try await music.setLyrics(persistentID: "T01", lyrics: "x") == false)
    }

    @Test func artworkDecodesToTheCardsIdentityColour() async throws {
        for index in [0, 7, 8, 19] {
            let data = try #require(try await music.artworkData(persistentID: Fixture.persistentID(at: index)))
            let image = try #require(ArtworkService.thumbnail(from: data))
            let sample = try #require(centrePixel(of: image))
            let expected = Fixture.color(at: index)
            #expect(
                CoverFlowGateLogic.distance(sample, expected) < 0.02,
                "T\(index) 解碼後中心色 \(sample) 偏離色板 \(expected)"
            )
        }
    }

    @Test func unknownArtworkIsNil() async throws {
        #expect(try await music.artworkData(persistentID: "ABCDEF0123") == nil)
        #expect(try await music.artworkData(persistentID: "") == nil)
    }

    /// 延遲保住「先掛空視圖、後填資料」的次序；只驗下界（上界取決於機器負載，驗了會 flaky）
    @Test func albumLoadHonoursConfiguredDelay() async throws {
        let slow = CoverFlowUITestMusic(albumDelay: .milliseconds(60))
        let clock = ContinuousClock()
        let start = clock.now
        _ = try await slow.albumTracks(artist: Fixture.artist, album: Fixture.album)
        #expect(clock.now - start >= .milliseconds(60))
    }

    // MARK: 組裝

    @Test @MainActor func assemblyIsOffWithoutTheFlag() {
        #expect(AppModel.makeCoverFlowUITestModelIfRequested(environment: [:]) == nil)
        #expect(AppModel.makeCoverFlowUITestModelIfRequested(environment: [Fixture.launchFlag: "0"]) == nil)
    }

    /// 旗標名的單一來源接線：AppModel 讀的就是共用檔裡的常數，而且組裝出來的 VM 真的吃假 Music
    @Test @MainActor func assemblyWiresTheFakeMusicIntoCoverFlow() async throws {
        let model = try #require(AppModel.makeCoverFlowUITestModelIfRequested(
            environment: [Fixture.launchFlag: "1", Fixture.albumDelayVariable: "0"]
        ))
        model.select(.coverFlow)
        await model.coverFlow.loadTask?.value
        #expect(model.coverFlow.items.count == Fixture.trackCount)
        #expect(model.token.isEmpty, "測試組裝不得讀到任何真實 token")
    }

    // MARK: 取樣

    /// 用閘門同一個取樣函數讀中心 5×5——這條測試因此同時釘住 UITest 的讀色路徑
    private func centrePixel(of image: NSImage) -> GateRGB? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rect = CGRect(x: cgImage.width / 2 - 2, y: cgImage.height / 2 - 2, width: 5, height: 5)
        return CoverFlowGateLogic.averageSRGB(of: cgImage, pixelRect: rect)
    }
}
