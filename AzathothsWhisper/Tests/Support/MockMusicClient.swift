import Foundation

@testable import AzathothsWhisper

// 可編程的 Music 替身：測試以腳本方式安排每次 currentTrack() 的回應（Plan §7：AE 層走 mock）
actor MockMusicClient: MusicControlling {
    enum Response: Sendable {
        case track(TrackInfo, lyrics: String)
        case notPlaying
        case failure(MusicError)
    }

    private var script: [Response]
    private var repeatLast: Bool
    private(set) var currentTrackCalls = 0
    private(set) var lyricsCalls = 0
    private(set) var writes: [String: String] = [:]
    private var albumTracksResult: [AlbumTrack] = []
    private var albumTracksGate: LyricsGate?
    private var writeGate: LyricsGate?
    private var artwork: [String: Data] = [:]
    private var setLyricsOutcome: Result<Bool, MusicError> = .success(true)

    func setSetLyricsOutcome(_ outcome: Result<Bool, MusicError>) {
        setLyricsOutcome = outcome
    }

    init(script: [Response] = [], repeatLast: Bool = true) {
        self.script = script
        self.repeatLast = repeatLast
    }

    func setAlbumTracks(_ tracks: [AlbumTrack]) {
        albumTracksResult = tracks
    }

    /// 卡住 albumTracks 的回應，直到測試放行
    func setAlbumTracksGate(_ gate: LyricsGate) {
        albumTracksGate = gate
    }

    /// 卡住 setLyrics 的回應：讓串行寫入的逐條進度文案可被斷言（C-27）
    func setWriteGate(_ gate: LyricsGate) {
        writeGate = gate
    }

    func setArtwork(_ data: Data, for persistentID: String) {
        artwork[persistentID] = data
    }

    private func next() -> Response {
        guard !script.isEmpty else { return .notPlaying }
        if script.count == 1 && repeatLast { return script[0] }
        return script.removeFirst()
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

    func currentLyrics() async throws -> String {
        lyricsCalls += 1
        // 不消耗腳本：讀當前曲歌詞與 currentTrack() 同屬一輪
        guard let first = script.first, case .track(_, let lyrics) = first else { return "" }
        return lyrics
    }

    func albumTracks(artist: String, album: String) async throws -> [AlbumTrack] {
        // 可選閘門：讓「載入中」這個一閃而過的狀態能被斷言（C-02）
        if let albumTracksGate {
            await albumTracksGate.wait()
        }
        return albumTracksResult
    }

    func setLyrics(persistentID: String, lyrics: String) async throws -> Bool {
        if let writeGate {
            await writeGate.wait()
        }
        switch setLyricsOutcome {
        case .success(let didWrite):
            if didWrite { writes[persistentID] = lyrics }
            return didWrite
        case .failure(let error):
            throw error
        }
    }

    func artworkData(persistentID: String) async throws -> Data? {
        artwork[persistentID]
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
