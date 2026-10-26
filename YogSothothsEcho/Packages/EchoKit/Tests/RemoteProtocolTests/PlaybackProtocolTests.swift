import Foundation
import Testing
@testable import RemoteProtocol

// S4 T2（sprint-4-detail.md §4.3、§4.4、§4.5、§4.8；CR-013 (a)(g)）：播放控制的訊息、驗證與常數

private let trackA = "00000000000000aa"
private let albumB = "00000000000000bb"

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

struct PlaybackErrorCodeTests {
    @Test func musicNotAuthorizedExistsAndIsNotRetryable() {
        #expect(ErrorCode(rawValue: "musicNotAuthorized") == .musicNotAuthorized)
        #expect(!ErrorCode.musicNotAuthorized.isRetryable)
    }
}

struct PlaybackRequestValidationTests {
    @Test func playTrackNeedsLowercaseHexIDs() {
        #expect(PlayTrackRequest(trackID: trackA, albumID: albumB).isValid)
        #expect(!PlayTrackRequest(trackID: trackA.uppercased(), albumID: albumB).isValid)
        #expect(!PlayTrackRequest(trackID: "xyz", albumID: albumB).isValid)
        #expect(!PlayTrackRequest(trackID: trackA, albumID: "").isValid)
    }

    @Test(arguments: [0.0, 0.5, 3600.0])
    func seekAcceptsFiniteNonNegativeSeconds(seconds: Double) {
        #expect(SeekRequest(trackID: trackA, seconds: seconds).isValid)
    }

    @Test(arguments: [-0.001, Double.nan, Double.infinity, -Double.infinity])
    func seekRejectsNegativeOrNonFinite(seconds: Double) {
        #expect(!SeekRequest(trackID: trackA, seconds: seconds).isValid)
    }

    @Test func seekNeedsHexTrackID() {
        #expect(!SeekRequest(trackID: "nope", seconds: 1).isValid)
    }

    @Test func outputSetAcceptsOneToEightUniqueHexIDs() {
        let ids = (1...8).map { String(format: "%016llx", UInt64($0)) }
        #expect(OutputSetRequest(deviceIDs: [ids[0]]).isValid)
        #expect(OutputSetRequest(deviceIDs: ids).isValid)
        #expect(!OutputSetRequest(deviceIDs: []).isValid)
        #expect(!OutputSetRequest(deviceIDs: ids + ["0000000000000009"]).isValid)
        #expect(!OutputSetRequest(deviceIDs: [ids[0], ids[0]]).isValid)
        #expect(!OutputSetRequest(deviceIDs: ["bad"]).isValid)
    }

    @Test func albumTracksNeedsHexAlbumAndDecodableCursor() {
        #expect(AlbumTracksRequest(albumID: albumB, cursor: nil).isValid)
        #expect(AlbumTracksRequest(albumID: albumB, cursor: CatalogCursor(version: albumB, offset: 20).encoded()).isValid)
        #expect(!AlbumTracksRequest(albumID: "bad", cursor: nil).isValid)
        #expect(!AlbumTracksRequest(albumID: albumB, cursor: "@@@").isValid)
    }
}

struct PlayResultTests {
    @Test func verifiedCarriesNoReason() {
        #expect(PlayResult(outcome: .verified, reason: nil).isValid)
        #expect(!PlayResult(outcome: .verified, reason: .queueMismatch).isValid)
    }

    @Test(arguments: PlayReason.allCases)
    func everyReasonPairsWithExactlyItsOwnOutcome(reason: PlayReason) {
        let pairs = [PlayOutcomeKind.degraded, .indeterminate].filter { PlayResult(outcome: $0, reason: reason).isValid }
        #expect(pairs == [reason.outcome])
        #expect(!PlayResult(outcome: reason.outcome, reason: nil).isValid)
    }

    @Test func degradedAndIndeterminateReasonSetsMatchDesign() {
        let degraded = Set(PlayReason.allCases.filter { $0.outcome == .degraded })
        #expect(degraded == [.gateEmptyTitle, .gateInconsistentTitle, .gateAmbiguousTitle, .gateOrderUndefined,
                             .shortcutMissing, .shortcutFailed, .queueMismatch])
        let indeterminate = Set(PlayReason.allCases.filter { $0.outcome == .indeterminate })
        #expect(indeterminate == [.targetTimeout, .queueTimeout, .shortcutUnresponsive, .lateChange, .manualChange, .fallbackFailed])
    }
}

struct PlaybackBodyRoundTripTests {
    @Test func eventControlResultAndOutputsRoundTrip() throws {
        let event = PlaybackEvent(availability: .ok, trackID: trackA, albumID: albumB, state: .playing,
                                  position: 12.5, duration: 200, sampledAt: 1234.5)
        #expect(try roundTrip(event) == event)
        let result = ControlResult(outcome: .notApplied, playback: event)
        #expect(try roundTrip(result) == result)
        let outputs = OutputListResponse(devices: [OutputDeviceSummary(id: trackA, kind: 2, selected: true)])
        #expect(try roundTrip(outputs) == outputs)
        let tracks = AlbumTracksResponse(albumID: albumB, version: albumB,
                                         songs: [TrackSummary(id: trackA, title: "t", disc: 1, number: 1, duration: 10)],
                                         nextCursor: nil, contextPlayable: true)
        #expect(try roundTrip(tracks) == tracks)
    }

    /// CR-017：逐曲歌手。舊 Mac 的回覆沒有 artist 欄位＝空字串（新 iPad 配舊 Mac 不解碼失敗）
    @Test func trackSummaryCarriesArtistAndToleratesMissingField() throws {
        let song = TrackSummary(id: trackA, title: "t", artist: "Made-up Singer", disc: 1, number: 1, duration: 10)
        #expect(try roundTrip(song) == song)
        let legacy = Data(#"{"id":"\#(trackA)","title":"t","disc":1,"number":1,"duration":10}"#.utf8)
        let decoded = try JSONDecoder().decode(TrackSummary.self, from: legacy)
        #expect(decoded.artist == "" && decoded.title == "t" && decoded.duration == 10)
    }

    @Test func playbackEventWithoutTrackEncodesNulls() throws {
        let event = PlaybackEvent(availability: .musicNotRunning, trackID: nil, albumID: nil, state: .stopped,
                                  position: 0, duration: nil, sampledAt: 0)
        #expect(try roundTrip(event) == event)
    }

    /// 最壞的一首（標題與歌手都截到上限、全為需跳脫字元；CR-017）放進完整外層訊息仍在預算內：每頁至少 1 首
    @Test func worstSingleTrackFitsResponseBudget() {
        let worst = TextClamp.clamp(String(repeating: "\"\u{1F600}", count: 400))
        let response = AlbumTracksResponse(albumID: albumB, version: albumB,
                                           songs: [TrackSummary(id: trackA, title: worst, artist: worst, disc: 99, number: 999, duration: 1e6)],
                                           nextCursor: CatalogCursor(version: albumB, offset: 999).encoded(), contextPlayable: false)
        #expect(Envelope.encode(.albumTracks, response).count <= TransportLimits.responseBudgetBytes)
    }
}

struct PlaybackLimitsTests {
    /// §4.4／§4.5：iPad 逾時要留 15 s 餘裕。simcodex R2 security LOW-1：next／previous 最壞改 11 s（含送出前讀回 2 s），
    /// 預算 80 不動（iPad 不重裝；使用者 2026-10-19 同意）＝「執行中＋等待中 play.track＋一筆 next」不再容得下（83 > 80），容量取捨記在 sprint-4-detail 附錄 F F18
    @Test func admissionBudgetAndClientTimeoutsAreConsistent() {
        #expect(PlaybackLimits.worstPlayTrack == 36)
        #expect(PlaybackLimits.worstNextPrevious == 11)
        #expect(PlaybackLimits.managedAdmissionBudget == 80)
        #expect(PlaybackLimits.worstPlayTrack + PlaybackLimits.worstNextPrevious * Double(PlaybackLimits.maxPendingManaged) <= PlaybackLimits.managedAdmissionBudget)
        for kind in [MessageKind.playTrack, .playNext, .playPrevious] {
            #expect(PlaybackLimits.clientTimeout(kind) >= PlaybackLimits.managedAdmissionBudget + 15)
        }
        #expect(PlaybackLimits.clientTimeout(.playToggle) == 10)
        #expect(PlaybackLimits.clientTimeout(.catalogPage) == 10)
    }

    /// 期限圖（§4.5）：最長路徑＝前置 7 s＋到達後到降級 28 s ≤ worst
    @Test func deadlineGraphLongestPathFitsWorst() {
        let prelude = PlaybackLimits.bindingTimeout + 3 * PlaybackLimits.appleEventTimeout
        let longest = PlaybackLimits.shortcutExitDeadline + PlaybackLimits.queueSettleDeadline
            + PlaybackLimits.targetArrivalDeadline + PlaybackLimits.appleEventTimeout
        #expect(prelude + longest <= PlaybackLimits.worstPlayTrack)
    }
}

struct ReplyKindTests {
    @Test func onlyPlayTrackRepliesWithADifferentKind() {
        for kind in MessageKind.allCases {
            #expect(kind.replyKind == (kind == .playTrack ? .playResult : kind))
        }
    }
}

/// CR-030（s6-61-genius.md §4.2、G2）：Genius 的 kind、錯誤碼、事件上的可用性
struct GeniusProtocolTests {
    @Test func accessibilityDeniedExistsAndIsNotRetryable() {
        #expect(ErrorCode(rawValue: "accessibilityDenied") == .accessibilityDenied)
        #expect(!ErrorCode.accessibilityDenied.isRetryable)
    }

    @Test func playGeniusIsAManagedControlTheIPadMaySend() {
        #expect(MessageKind(rawValue: "play.genius") == .playGenius)
        #expect(MessageKind.playGenius.replyKind == .playGenius)
        #expect(!EnvelopeRules.readKinds.contains(.playGenius))
        #expect(EnvelopeRules.allowed(.playGenius, direction: .fromIPad, path: .normal))
        #expect(!EnvelopeRules.allowed(.playGenius, direction: .fromIPad, path: .pairing))
        #expect(PlaybackLimits.clientTimeout(.playGenius) == PlaybackLimits.clientTimeout(.playNext))
    }

    @Test(arguments: [GeniusAvailability.ready, .needsAccessibility])
    func eventCarriesGeniusAvailability(value: GeniusAvailability) throws {
        let event = PlaybackEvent(availability: .ok, trackID: trackA, albumID: albumB, state: .paused, position: 1, duration: 10,
                                  sampledAt: 2, genius: value)
        #expect(try roundTrip(event) == event)
        #expect(try roundTrip(event).genius == value)
    }

    /// 舊 Mac 沒有 genius 欄位＝nil（iPad 不顯示 Genius 鈕）；未知值拒收
    @Test func legacyEventDecodesAsNilAndUnknownValueIsRejected() throws {
        let base = #""availability":"ok","trackID":"\#(trackA)","albumID":null,"state":"playing","position":1,"duration":10,"sampledAt":2"#
        let legacy = try JSONDecoder().decode(PlaybackEvent.self, from: Data("{\(base)}".utf8))
        #expect(legacy.genius == nil && legacy.trackID == trackA)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PlaybackEvent.self, from: Data(#"{\#(base),"genius":"maybe"}"#.utf8))
        }
        #expect(GeniusAvailability(rawValue: "ready") == .ready && GeniusAvailability(rawValue: "needsAccessibility") == .needsAccessibility)
    }
}
