import Foundation

@testable import AzathothsWhisper

// 可編程的 Music 替身：測試以腳本方式安排每次 currentTrack() 的回應（Plan §7：AE 層走 mock）
actor MockMusicClient: MusicControlling {
    enum Response: Sendable {
        /// `lyrics` 為 nil＝歌詞讀取失敗
        case track(TrackInfo, lyrics: String?)
        case notPlaying
        case failure(MusicError)
    }

    private var script: [Response]
    private var repeatLast: Bool
    private(set) var currentTrackCalls = 0
    /// `nowPlaying()` 的呼叫次數（`currentTrackCalls` 也會加一：兩者都是「查一次當前曲」）
    private(set) var nowPlayingCalls = 0
    private var trackDetailsResult: [TrackDetails] = []
    private var trackDetailsOutcome: Result<[TrackDetails], MusicError>?
    /// 每次 `trackDetails` 請求的 ID（依請求順序）
    private(set) var trackDetailsRequests: [[String]] = []
    /// 已回傳（通過閘門）的 `trackDetails` 次數
    private(set) var trackDetailsCompleted = 0
    private(set) var writes: [String: String] = [:]
    private var albumTracksResult: [AlbumTrack] = []
    private(set) var albumTracksCalls = 0
    /// 最後一次 albumTracks 的查詢參數——驗「用事件的 albumKey 而非重讀 currentTrack」
    private(set) var lastAlbumTracksQuery: (artist: String, album: String)?
    /// 逐次閘門：第 n 次 `trackDetails` 等第 n 個閘門（結果在請求當下取定，較早的請求可以較晚回來）
    private var trackDetailsGateQueue: [LyricsGate] = []
    private var albumTracksGate: LyricsGate?
    /// 按調用序號分派的閘門：第 n 次 albumTracks() 用第 n 個。
    /// 用途：重疊載入場景需要讓兩個載入**分別**完成（單一 broadcast gate 會同時放行兩者，
    /// 觀察不到「第一個已完成、第二個仍在跑」這個 C-18 的關鍵區間）。
    private var albumTracksGateQueue: [LyricsGate] = []
    private var writeGate: LyricsGate?
    private var artwork: [String: Data] = [:]
    private(set) var artworkCalls = 0
    /// 目前在飛的 artwork 請求數——驗「P1 無預取時 ≤ 1」
    private(set) var artworkInFlight = 0
    private var artworkGate: LyricsGate?
    private var artworkGateQueue: [LyricsGate] = []
    /// 覆寫整體結果（優先於 artwork 字典）：用來製造 AE 失敗
    private var artworkOutcome: Result<Data?, MusicError>?
    private var setLyricsOutcome: Result<Bool, MusicError> = .success(true)
    /// 逐首覆寫（優先於 `setLyricsOutcome`）：Import All 部分失敗用
    private var setLyricsOutcomes: [String: Result<Bool, MusicError>] = [:]

    func setSetLyricsOutcome(_ outcome: Result<Bool, MusicError>) {
        setLyricsOutcome = outcome
    }

    func setSetLyricsOutcome(_ outcome: Result<Bool, MusicError>, for persistentID: String) {
        setLyricsOutcomes[persistentID] = outcome
    }

    init(script: [Response] = [], repeatLast: Bool = true) {
        self.script = script
        self.repeatLast = repeatLast
    }

    func setTrackDetails(_ details: [TrackDetails]) {
        trackDetailsResult = details
    }

    /// 覆寫整體結果（優先於 `setTrackDetails`）：製造批次讀取失敗；nil＝取消覆寫
    func setTrackDetailsGateQueue(_ gates: [LyricsGate]) {
        trackDetailsGateQueue = gates
    }

    func setTrackDetailsOutcome(_ outcome: Result<[TrackDetails], MusicError>?) {
        trackDetailsOutcome = outcome
    }

    func setAlbumTracks(_ tracks: [AlbumTrack]) {
        albumTracksResult = tracks
    }

    /// 換掉腳本：製造「事件發布後 currentTrack() 已是別張專輯」的情境
    func setScript(_ responses: [Response]) {
        script = responses
    }

    /// 卡住 albumTracks 的回應，直到測試放行
    func setAlbumTracksGate(_ gate: LyricsGate) {
        albumTracksGate = gate
    }

    /// 逐次分派閘門：第 1 次 albumTracks() 等 gates[0]，第 2 次等 gates[1]，依此類推；
    /// 超出陣列長度的調用不等待。
    func setAlbumTracksGateQueue(_ gates: [LyricsGate]) {
        albumTracksGateQueue = gates
    }

    /// 卡住 setLyrics 的回應：讓串行寫入的逐條進度文案可被斷言（C-27）
    func setWriteGate(_ gate: LyricsGate) {
        writeGate = gate
    }

    func setArtwork(_ data: Data, for persistentID: String) {
        artwork[persistentID] = data
    }

    /// 卡住 artwork 的回應：製造併發／在飛數量可斷言的窗口
    func setArtworkGate(_ gate: LyricsGate) {
        artworkGate = gate
    }

    func setArtworkOutcome(_ outcome: Result<Data?, MusicError>) {
        artworkOutcome = outcome
    }

    /// 依調用序分派閘門：第 n 次 artworkData() 等第 n 個。
    /// 用途：預取排程要能觀察「第 1 張卡住、其餘尚未送出」這個區間
    func setArtworkGateQueue(_ gates: [LyricsGate]) {
        artworkGateQueue = gates
    }

    /// 每次 artworkData() 進來時的在飛峰值——驗「單槽：任一時刻 ≤ 1」
    private(set) var maxArtworkInFlight = 0

    /// artworkData() 的實際調用順序，供「explicit 插隊在預取之前」斷言
    private(set) var artworkOrder: [String] = []

    private func next() -> Response {
        let response: Response
        if script.isEmpty {
            response = .notPlaying
        } else if script.count == 1 && repeatLast {
            response = script[0]
        } else {
            response = script.removeFirst()
        }
        return response
    }

    // MARK: MusicControlling

    func playerState() async throws -> PlayerState { .playing }

    func currentTrack() async throws -> TrackInfo? {
        currentTrackCalls += 1
        switch next() {
        case .track(let info, _): return info
        case .notPlaying: return nil
        case .failure(let error): throw error
        }
    }

    /// 一次回應同時帶曲目與歌詞（取自同一個腳本項，D9）
    func nowPlaying() async throws -> NowPlayingRead? {
        nowPlayingCalls += 1
        currentTrackCalls += 1
        switch next() {
        case .track(let info, let lyrics): return NowPlayingRead(track: info, lyrics: lyrics)
        case .notPlaying: return nil
        case .failure(let error): throw error
        }
    }

    func trackDetails(persistentIDs: [String]) async throws -> [TrackDetails] {
        trackDetailsRequests.append(persistentIDs)
        let call = trackDetailsRequests.count - 1
        let wanted = Set(persistentIDs)
        let outcome = trackDetailsOutcome ?? .success(trackDetailsResult.filter { wanted.contains($0.persistentID) })
        if call < trackDetailsGateQueue.count {
            await trackDetailsGateQueue[call].wait()
        }
        trackDetailsCompleted += 1
        return try outcome.get()
    }

    func albumTracks(artist: String, album: String) async throws -> [AlbumTrack] {
        lastAlbumTracksQuery = (artist, album)
        let call = albumTracksCalls
        albumTracksCalls += 1
        // 逐次閘門優先於單一閘門
        if call < albumTracksGateQueue.count {
            await albumTracksGateQueue[call].wait()
        } else if let albumTracksGate {
            // 可選閘門：讓「載入中」這個一閃而過的狀態能被斷言（C-02）
            await albumTracksGate.wait()
        }
        return albumTracksResult
    }

    func setLyrics(persistentID: String, lyrics: String) async throws -> Bool {
        if let writeGate {
            await writeGate.wait()
        }
        switch setLyricsOutcomes[persistentID] ?? setLyricsOutcome {
        case .success(let didWrite):
            if didWrite { writes[persistentID] = lyrics }
            return didWrite
        case .failure(let error):
            throw error
        }
    }

    func artworkData(persistentID: String) async throws -> Data? {
        let call = artworkCalls
        artworkCalls += 1
        artworkOrder.append(persistentID)
        artworkInFlight += 1
        maxArtworkInFlight = max(maxArtworkInFlight, artworkInFlight)
        defer { artworkInFlight -= 1 }
        if call < artworkGateQueue.count {
            await artworkGateQueue[call].wait()
        } else if let artworkGate {
            await artworkGate.wait()
        }
        if let artworkOutcome {
            return try artworkOutcome.get()
        }
        return artwork[persistentID]
    }
}

// 立即返回的時鐘：讓輪詢迴圈以測試節奏跑，零真實延時
struct ImmediateClock: PollClock {
    func sleep(for interval: Duration) async throws {}
}

extension TrackInfo {
    static func fixture(
        id: String = "PID1",
        artist: String = "Dark Tranquillity",
        title: String = "Monochromatic Stains",
        album: String = "Damage Done",
        disc: Int = 1,
        track: Int = 1
    ) -> TrackInfo {
        TrackInfo(persistentID: id, artist: artist, title: title, album: album, discNumber: disc, trackNumber: track)
    }
}

extension AlbumTrack {
    static func fixture(
        id: String = "PID1",
        artist: String = "Dark Tranquillity",
        title: String = "Monochromatic Stains",
        album: String = "Damage Done",
        disc: Int = 1,
        track: Int = 1,
        lyrics: String = ""
    ) -> AlbumTrack {
        AlbumTrack(
            persistentID: id, artist: artist, title: title, album: album,
            discNumber: disc, trackNumber: track, lyrics: lyrics
        )
    }
}
