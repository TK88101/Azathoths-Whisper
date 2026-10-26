import Foundation
import RemoteProtocol
import RemoteTransport

extension PlaybackClient {
    static var maxTrackPages: Int { 50 }

    /// 一張專輯的全部曲目（分頁取完）。防呆：頁數上限、cursor 必須前進、回覆的專輯要對得上——
    /// 不對＝invalidResponse（有問題的 Mac 不能讓 iPad 無限發請求）。
    /// `retry`：給了才對 busy／rateLimited 短重試（只重送失敗的那一頁；F-L1）；nil＝第一次就拋（背景查曲名不在限流時加壓）
    func allTracks(albumID: String, retry: ShortTransientRetry.Options? = nil) async throws(EchoRequestError)
        -> (songs: [TrackSummary], contextPlayable: Bool) {
        var songs: [TrackSummary] = []
        var playable = true
        var cursor: String?
        for _ in 0..<Self.maxTrackPages {
            let page = try await tracksPage(albumID: albumID, cursor: cursor, retry: retry)
            guard page.albumID == albumID, page.nextCursor == nil || page.nextCursor != cursor else { throw .invalidResponse }
            songs += page.songs
            playable = page.contextPlayable
            cursor = page.nextCursor
            if cursor == nil { return (songs, playable) }
        }
        throw .invalidResponse
    }

    /// 發請求前、回覆後（不論成敗）、睡醒後都確認未取消，否則丟 `.cancelled`：不再發請求、不採用回覆（Codex R3-2、R4-2）。清單分頁同一套：`LibraryViewModel.fetchPage`
    private func tracksPage(albumID: String, cursor: String?, retry: ShortTransientRetry.Options?) async throws(EchoRequestError)
        -> AlbumTracksResponse {
        guard let retry else { return try await albumTracks(albumID: albumID, cursor: cursor) }
        var attempt = 1
        while true {
            guard !Task.isCancelled else { throw .cancelled }
            let result: Result<AlbumTracksResponse, EchoRequestError>
            do throws(EchoRequestError) { result = .success(try await albumTracks(albumID: albumID, cursor: cursor)) } catch { result = .failure(error) }
            guard !Task.isCancelled else { throw .cancelled }
            switch result {
            case .success(let page):
                return page
            case .failure(let error):
                guard ShortTransientRetry.shouldRetry(error, afterAttempt: attempt) else { throw error }
                attempt += 1
                try await ShortTransientRetry.wait(beforeAttempt: attempt, after: error, retry)
            }
        }
    }
}
