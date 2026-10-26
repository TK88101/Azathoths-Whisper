#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// S4 T4（sprint-4-detail.md §4.3；CR-013(f)）：album.tracks 的 Mac 回應（控制用極簡曲目選擇器）。名稱一律自編

struct AlbumSongsServiceTests {
    private func service(_ songs: [RawTrack]) -> (CatalogService, FakeCatalogSource) {
        let source = FakeCatalogSource(songs: songs)
        return (CatalogService(source: source, clock: FakeCatalogClock(), onChange: { _ in }), source)
    }

    private let album = CatalogIndexBuilder.hex(10)

    @Test func returnsOrderedSongsWithContextFlag() async throws {
        let (service, _) = service([rawTrack(2, album: 10, title: "B side", number: 2, duration: 61),
                                    rawTrack(1, album: 10, title: "A side", number: 1, duration: 60)])
        let response = try await service.albumSongs(AlbumTracksRequest(albumID: album, cursor: nil)).get()
        #expect(response.songs.map(\.title) == ["A side", "B side"])
        #expect(response.songs.map(\.duration) == [60, 61])
        #expect(response.contextPlayable && response.nextCursor == nil && response.albumID == album)
    }

    @Test func refusedAlbumIsNotContextPlayable() async throws {
        let (service, _) = service([rawTrack(1, album: 10, albumTitle: "", number: 1)])
        let response = try await service.albumSongs(AlbumTracksRequest(albumID: album, cursor: nil)).get()
        #expect(!response.contextPlayable)
    }

    @Test func pagesByByteBudgetWithoutLossOrDuplication() async throws {
        let long = String(repeating: "\u{1F3B5}", count: 150)
        let songs = (1...300).map { rawTrack(UInt64($0), album: 10, title: "\($0) \(long)", number: $0) }
        let (service, _) = service(songs)
        var cursor: String?
        var seen: [String] = []
        var pages = 0
        repeat {
            let page = try await service.albumSongs(AlbumTracksRequest(albumID: album, cursor: cursor)).get()
            #expect(Envelope.encode(.albumTracks, page).count <= TransportLimits.responseBudgetBytes)
            #expect(!page.songs.isEmpty)
            seen += page.songs.map(\.id)
            cursor = page.nextCursor
            pages += 1
        } while cursor != nil && pages < 50
        #expect(pages > 1)
        #expect(seen == (1...300).map { CatalogIndexBuilder.hex(UInt64($0)) })
    }

    @Test func unknownAlbumOrMalformedRequestIsInvalid() async {
        let (service, source) = service([rawTrack(1, album: 10)])
        #expect(await service.albumSongs(AlbumTracksRequest(albumID: "bad", cursor: nil)) == .failure(.invalidRequest))
        #expect(await source.loadCount == 0)   // 不合法的請求不觸發載入
        #expect(await service.albumSongs(AlbumTracksRequest(albumID: CatalogIndexBuilder.hex(99), cursor: nil)) == .failure(.invalidRequest))
    }

    @Test func unreadableLibraryIsLibraryUnavailable() async {
        let (service, source) = service([])
        await source.set(failure: .unavailable(code: 4097))
        #expect(await service.albumSongs(AlbumTracksRequest(albumID: album, cursor: nil)) == .failure(.libraryUnavailable))
    }
}
#endif
