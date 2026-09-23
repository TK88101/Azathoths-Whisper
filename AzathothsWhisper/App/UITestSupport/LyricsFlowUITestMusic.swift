// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import Foundation

/// 「Cover Flow × 找歌詞」UI 測試的假 Music（計劃 Q3.5）。
///
/// 不送任何 Apple Event、不碰使用者曲庫。`setLyrics` 只寫進記憶體：寫入後的補讀讀得到它，
/// AC4「寫入成功 → 彩帶撒完後升回」才走得通。
actor LyricsFlowUITestMusic: MusicControlling {
    private typealias Fixture = LyricsFlowUITestScenario

    private let scenario: LyricsFlowUITestScenario
    private var lyrics: [String: String]

    init(scenario: LyricsFlowUITestScenario) {
        self.scenario = scenario
        let playing = Fixture.playingIndex
        self.lyrics = Dictionary(uniqueKeysWithValues: (0..<Fixture.trackCount).map { index in
            let text = index == playing ? (scenario == .present ? "fixture lyrics" : "") : Fixture.fixtureLyrics(at: index)
            return (Fixture.persistentID(at: index), text)
        })
    }

    func playerState() async throws -> PlayerState {
        scenario == .notPlaying ? .stopped : .playing
    }

    func currentTrack() async throws -> TrackInfo? {
        scenario == .notPlaying ? nil : Self.track(at: Fixture.playingIndex)
    }

    func nowPlaying() async throws -> NowPlayingRead? {
        guard let track = try await currentTrack() else { return nil }
        return NowPlayingRead(track: track, lyrics: lyrics[track.persistentID] ?? "")
    }

    func trackDetails(persistentIDs: [String]) async throws -> [TrackDetails] {
        persistentIDs.compactMap { id in
            guard let index = Fixture.index(of: id) else { return nil }
            let track = Self.track(at: index)
            return TrackDetails(
                persistentID: id, artist: track.artist, title: track.title, album: track.album,
                discNumber: track.discNumber, trackNumber: track.trackNumber, lyrics: lyrics[id]
            )
        }
    }

    func albumTracks(artist: String, album: String) async throws -> [AlbumTrack] { [] }

    func setLyrics(persistentID: String, lyrics newLyrics: String) async throws -> Bool {
        guard lyrics[persistentID] != nil else { return false }
        lyrics[persistentID] = newLyrics
        return true
    }

    /// 無封面＝佔位（H-08）；封面不是本組 UITests 的觀察對象
    func artworkData(persistentID: String) async throws -> Data? { nil }

    private static func track(at index: Int) -> TrackInfo {
        TrackInfo(
            persistentID: Fixture.persistentID(at: index), artist: Fixture.artist,
            title: Fixture.title(at: index), album: Fixture.album,
            discNumber: 1, trackNumber: index + 1
        )
    }
}

/// 恆回 404 的 HTTP：UI 測試的自動抓詞不上網，結果固定為「找不到」
struct UITestStubHTTPClient: HTTPClient {
    func get(_ url: URL, headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse {
        HTTPResponse(statusCode: 404, body: "")
    }

    func post(_ url: URL, form: [String: String], headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse {
        HTTPResponse(statusCode: 404, body: "")
    }
}

/// 與 Music 同形狀的假 `Queue.dat`／`History.dat`（事實 20、25），寫在 app 自己的暫存目錄——
/// **不是** Music 的檔案。牌組因此有左右鄰張，AC3「點其他卡無效」才測得到
enum LyricsFlowUITestQueueFiles {
    static let directoryName = "AzathothsWhisperUITest-LyricsFlow"

    static func write() throws -> URL {
        typealias Fixture = LyricsFlowUITestScenario
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let queueItems: [[String: Any]] = (0..<Fixture.trackCount).map { index in
            ["pm": ["name": Fixture.title(at: index), "piObjSpec": ["tID": Fixture.trackID(at: index)]],
             "itID": Fixture.itemID(at: index)]
        }
        let queue: [String: Any] = [
            "sega": [["items": ["list": ["items": ["iar": queueItems]], "shuffleMode": "off"]]],
            "shuffleMode": "off",
            "version": 1,
        ]
        let historyItems: [[String: Any]] = (0..<Fixture.playingIndex).map { index in
            let hex = String(format: "%llx", UInt64(bitPattern: Fixture.trackID(at: index)))
            let identifier = "DBID:0x1-PID:0x\(hex)-PPID:0x0-IKIND:eSong"
            return ["pm": ["contentDesc": ["identifiers": ["libraryItemID": identifier]], "name": Fixture.title(at: index)]]
        }
        let history: [String: Any] = ["items": ["iar": historyItems], "version": 1]

        for (name, root) in [(QueueFileSource.queueFileName, queue), (QueueFileSource.historyFileName, history)] {
            let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        return directory
    }
}
#endif
