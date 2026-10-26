import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// S4 T11（sprint-4-detail.md §4.8、§4.9）：會判斷的呈現邏輯（純函式）

struct PlaybackPresentationTests {
    @Test func rowStateFollowsCurrentTrackBeforePending() {
        #expect(PlaybackPresentation.rowState(trackID: "a", pending: "a", current: nil) == .preparing)
        #expect(PlaybackPresentation.rowState(trackID: "a", pending: "a", current: "a") == .playing)
        #expect(PlaybackPresentation.rowState(trackID: "a", pending: nil, current: "a") == .playing)
        #expect(PlaybackPresentation.rowState(trackID: "b", pending: "a", current: "c") == .idle)
    }

    @Test func playResultsMapToNotices() {
        #expect(PlaybackPresentation.notice(for: PlayResult(outcome: .verified, reason: nil)) == nil)
        let cases: [(PlayReason, PlaybackPresentation.Notice)] = [
            (.gateEmptyTitle, .playedOnlyThis(.albumOrder)), (.gateInconsistentTitle, .playedOnlyThis(.albumOrder)),
            (.gateAmbiguousTitle, .playedOnlyThis(.albumOrder)), (.gateOrderUndefined, .playedOnlyThis(.albumOrder)),
            (.shortcutMissing, .playedOnlyThis(.missingShortcut)), (.shortcutFailed, .playedOnlyThis(.shortcutFailed)),
            (.queueMismatch, .playedOnlyThis(.queueMismatch)),
        ]
        for (reason, notice) in cases {
            #expect(PlaybackPresentation.notice(for: PlayResult(outcome: .degraded, reason: reason)) == notice)
        }
        for reason in [PlayReason.targetTimeout, .queueTimeout, .lateChange, .manualChange, .fallbackFailed] {
            #expect(PlaybackPresentation.notice(for: PlayResult(outcome: .indeterminate, reason: reason)) == .uncertain)
        }
        // F16（thecure 2026-10-19）：隔離中被擋（或捷徑逾時後開始隔離）＝「暫停接受點歌」，與前一次的「無法確認」分開
        #expect(PlaybackPresentation.notice(for: PlayResult(outcome: .indeterminate, reason: .shortcutUnresponsive)) == .picksPaused)
    }

    @Test func errorsMapToNotices() {
        #expect(PlaybackPresentation.notice(for: .remote(.busy)) == .tooFast)
        #expect(PlaybackPresentation.notice(for: .remote(.superseded)) == nil)
        #expect(PlaybackPresentation.notice(for: .remote(.musicNotRunning)) == .musicNotRunning)
        #expect(PlaybackPresentation.notice(for: .remote(.musicNotAuthorized)) == .musicNotAuthorized)
        #expect(PlaybackPresentation.notice(for: .remote(.libraryUnavailable)) == .libraryUnavailable)
        #expect(PlaybackPresentation.notice(for: .disconnected) == nil)
        #expect(PlaybackPresentation.notice(for: .cancelled) == nil)
        #expect(PlaybackPresentation.notice(for: .timeout) == .failed)
        #expect(PlaybackPresentation.notice(for: .remote(.invalidRequest)) == .failed)
    }

    @Test func noticeActions() {
        #expect(PlaybackPresentation.offersResync(.uncertain))
        #expect(!PlaybackPresentation.offersResync(.playedOnlyThis(.queueMismatch)))
        #expect(PlaybackPresentation.offersRetry(.playedOnlyThis(.shortcutFailed)))
        #expect(PlaybackPresentation.offersRetry(.musicNotRunning))
        #expect(!PlaybackPresentation.offersRetry(.playedOnlyThis(.missingShortcut)))
        #expect(PlaybackPresentation.fades(.playedOnlyThis(.queueMismatch)) && PlaybackPresentation.fades(.tooFast))
        #expect(!PlaybackPresentation.fades(.uncertain) && !PlaybackPresentation.fades(.musicNotAuthorized))
        // F16：可重新同步（逾時那條路 Music 可能已變）、不自動淡出、不給重試（隔離中重試必被擋）
        #expect(PlaybackPresentation.offersResync(.picksPaused))
        #expect(!PlaybackPresentation.fades(.picksPaused) && !PlaybackPresentation.offersRetry(.picksPaused))
    }

    @Test func availabilityGatesControls() {
        #expect(PlaybackPresentation.availability(connected: false, event: .ok) == .disconnected)
        #expect(PlaybackPresentation.availability(connected: true, event: nil) == .ready)
        #expect(PlaybackPresentation.availability(connected: true, event: .musicNotRunning) == .musicNotRunning)
        #expect(PlaybackPresentation.availability(connected: true, event: .automationDenied) == .musicNotAuthorized)
        #expect(PlaybackPresentation.controlsEnabled(.ready))
        for state in [PlaybackPresentation.Availability.disconnected, .musicNotRunning, .musicNotAuthorized] {
            #expect(!PlaybackPresentation.controlsEnabled(state))
        }
    }

    @Test func timeLabelIsMinutesAndSeconds() {
        #expect(PlaybackPresentation.time(0) == "0:00")
        #expect(PlaybackPresentation.time(65.9) == "1:05")
        #expect(PlaybackPresentation.time(3601) == "60:01")
        #expect(PlaybackPresentation.time(-2) == "0:00")
    }
}

/// CR-030 G6：Genius 鈕（寬膠囊 ◀◀ 前）。舊 Mac（genius nil）不顯示；停止中停用（在場驗後可放寬）
struct GeniusPresentationTests {
    private func event(_ genius: GeniusAvailability?, state: PlaybackState = .playing, hasTrack: Bool = true,
                       availability: PlaybackAvailability = .ok) -> PlaybackEvent {
        PlaybackEvent(availability: availability, trackID: hasTrack ? "0000000000000001" : nil, albumID: nil, state: state,
                      position: 1, duration: 100, sampledAt: 1, genius: genius)
    }

    /// CR-031：可按＝（沒歌且停止）或（有歌且播放／暫停）；其餘停用。舊 Mac／沒事件＝不顯示
    @Test(arguments: [GeniusAvailability?.none, .ready, .needsAccessibility])
    func fullMatrix(genius: GeniusAvailability?) {
        for connected in [true, false] {
            for hasEvent in [true, false] {
                for availability in [PlaybackAvailability.ok, .musicNotRunning, .automationDenied] {
                    for state in [PlaybackState.playing, .paused, .stopped] {
                        for hasTrack in [true, false] {
                            let value = hasEvent ? event(genius, state: state, hasTrack: hasTrack, availability: availability) : nil
                            let button = GeniusPresentation.button(connected: connected, event: value)
                            let pressableState = hasTrack ? state != .stopped : state == .stopped
                            let expected: GeniusPresentation.Button
                            if !hasEvent || genius == nil {
                                expected = .hidden
                            } else if !connected || availability != .ok || !pressableState {
                                expected = .disabled
                            } else {
                                expected = genius == .ready ? .ready : .needsAccessibility
                            }
                            #expect(button == expected,
                                    "connected=\(connected) event=\(hasEvent) \(availability) \(state) track=\(hasTrack) \(String(describing: genius))")
                        }
                    }
                }
            }
        }
    }

    @Test func needsAccessibilityStaysPressableButOnlyReadySends() {
        #expect(GeniusPresentation.isPressable(.ready) && GeniusPresentation.isPressable(.needsAccessibility))
        #expect(!GeniusPresentation.isPressable(.disabled))
        #expect(GeniusPresentation.sends(.ready) && !GeniusPresentation.sends(.needsAccessibility))
    }

    @Test func accessibilityNoticeFadesWithoutRetryOrResync() {
        let notice = PlaybackPresentation.Notice.needsAccessibility
        #expect(PlaybackPresentation.fades(notice))
        #expect(!PlaybackPresentation.offersRetry(notice) && !PlaybackPresentation.offersResync(notice))
        #expect(PlaybackPresentation.notice(for: .remote(.accessibilityDenied)) == .needsAccessibility)
    }

    /// Genius 專用結果：按了沒看到換曲、逾時、斷線＝無法確認；錯誤碼 notApplied（沒按）＝沒生效
    @Test func geniusOutcomesMapToNotices() {
        #expect(GeniusPresentation.notice(for: .success(.applied)) == nil)
        #expect(GeniusPresentation.notice(for: .success(.notApplied)) == .uncertain)
        #expect(GeniusPresentation.notice(for: .failure(.timeout)) == .uncertain)
        #expect(GeniusPresentation.notice(for: .failure(.disconnected)) == .uncertain)
        #expect(GeniusPresentation.notice(for: .failure(.remote(.notApplied))) == .notApplied)
        #expect(GeniusPresentation.notice(for: .failure(.remote(.accessibilityDenied))) == .needsAccessibility)
        #expect(GeniusPresentation.notice(for: .failure(.remote(.busy))) == .tooFast)
        #expect(GeniusPresentation.notice(for: .failure(.remote(.musicNotRunning))) == .musicNotRunning)
        #expect(GeniusPresentation.notice(for: .failure(.cancelled)) == nil)
    }
}

