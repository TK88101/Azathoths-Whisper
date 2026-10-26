import Foundation
import RemoteProtocol
import RemoteTransport
import SwiftUI

/// 播放畫面會判斷的邏輯（純函式，單測；sprint-4-detail.md §4.8、§4.9）
enum PlaybackPresentation {
    enum RowState: Equatable { case idle, preparing, playing }

    /// 曲目列：Mac 推來的目前曲＝正在播放（優先）；點了還沒到＝準備中
    static func rowState(trackID: String, pending: String?, current: String?) -> RowState {
        if current == trackID { return .playing }
        return pending == trackID ? .preparing : .idle
    }

    enum Notice: Equatable {
        /// 降級：只播了這首（CR-014 後無「捷徑被改動」一類）
        case playedOnlyThis(Cause)
        /// 不確定：顯示「重新同步」
        case uncertain
        /// Mac 暫停接受點歌（隔離中；F16）：不說原因——手動操作與捷徑逾時都會進隔離
        case picksPaused
        case tooFast
        case notApplied
        case musicNotRunning
        case musicNotAuthorized
        case libraryUnavailable
        case failed
        /// Genius：Mac 上的 Azathoth 還沒被允許輔助使用（CR-030）
        case needsAccessibility

        enum Cause: Equatable { case albumOrder, missingShortcut, shortcutFailed, queueMismatch }
    }

    static func notice(for result: PlayResult) -> Notice? {
        switch result.outcome {
        case .verified: return nil
        case .indeterminate: return result.reason == .shortcutUnresponsive ? .picksPaused : .uncertain
        case .degraded:
            switch result.reason {
            case .shortcutMissing: return .playedOnlyThis(.missingShortcut)
            case .shortcutFailed: return .playedOnlyThis(.shortcutFailed)
            case .queueMismatch: return .playedOnlyThis(.queueMismatch)
            default: return .playedOnlyThis(.albumOrder)
            }
        }
    }

    /// 取代（使用者已點了新的）、斷線、取消都不提示
    static func notice(for error: EchoRequestError) -> Notice? {
        switch error {
        case .remote(.busy): .tooFast
        case .remote(.superseded), .disconnected, .cancelled: nil
        case .remote(.musicNotRunning): .musicNotRunning
        case .remote(.musicNotAuthorized): .musicNotAuthorized
        case .remote(.libraryUnavailable): .libraryUnavailable
        case .remote(.accessibilityDenied): .needsAccessibility
        default: .failed
        }
    }

    static func offersRetry(_ notice: Notice) -> Bool {
        switch notice {
        case .playedOnlyThis(.shortcutFailed), .musicNotRunning, .failed, .libraryUnavailable: true
        default: false
        }
    }

    static func offersResync(_ notice: Notice) -> Bool { notice == .uncertain || notice == .picksPaused }

    /// 會自動淡出的提示（10 s 或下一次操作）；權限與不確定要等使用者處理
    static func fades(_ notice: Notice) -> Bool {
        switch notice {
        case .playedOnlyThis, .tooFast, .notApplied, .needsAccessibility: true
        default: false
        }
    }

    static func text(_ notice: Notice) -> LocalizedStringKey {
        switch notice {
        case .playedOnlyThis(.albumOrder): LocalizedStringKey("Played only this song. This album can't be played in order from here.")
        case .playedOnlyThis(.missingShortcut): LocalizedStringKey("Played only this song. Your Mac is missing the shortcut.")
        case .playedOnlyThis(.shortcutFailed): LocalizedStringKey("Played only this song. The shortcut on your Mac didn't run.")
        case .playedOnlyThis(.queueMismatch): LocalizedStringKey("Played only this song. The rest of the album didn't line up.")
        case .uncertain: LocalizedStringKey("Couldn't confirm what's playing.")
        case .picksPaused: LocalizedStringKey("Song picks are paused on your Mac for now. Try again in a moment.")
        case .tooFast: LocalizedStringKey("Too fast. Wait a moment.")
        case .notApplied: LocalizedStringKey("That didn't take effect.")
        case .musicNotRunning: LocalizedStringKey("Open Music on your Mac.")
        case .musicNotAuthorized: LocalizedStringKey("Your Mac hasn't allowed control of Music.")
        case .libraryUnavailable: LocalizedStringKey("Your Mac can't read the Music library.")
        case .failed: LocalizedStringKey("Something went wrong. Try again.")
        case .needsAccessibility: LocalizedStringKey("Allow Azathoth's Whisper in Accessibility settings on your Mac.")
        }
    }

    // MARK: 可用性

    enum Availability: Equatable { case ready, disconnected, musicNotRunning, musicNotAuthorized }

    static func availability(connected: Bool, event: PlaybackAvailability?) -> Availability {
        guard connected else { return .disconnected }
        switch event {
        case .musicNotRunning: return .musicNotRunning
        case .automationDenied: return .musicNotAuthorized
        case .ok, nil: return .ready
        }
    }

    static func controlsEnabled(_ availability: Availability) -> Bool { availability == .ready }

    static func availabilityText(_ availability: Availability) -> LocalizedStringKey? {
        switch availability {
        case .ready: nil
        case .disconnected: LocalizedStringKey("Can't reach your Mac.")
        case .musicNotRunning: text(.musicNotRunning)
        case .musicNotAuthorized: text(.musicNotAuthorized)
        }
    }

    /// 進度標籤 m:ss（負值視為 0）
    static func time(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// 播放提示列（播放列與曲目清單共用）：文案＋「重新同步」或「重試」
struct PlaybackNoticeRow: View {
    let notice: PlaybackPresentation.Notice
    let id: String
    let onResync: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(PlaybackPresentation.text(notice)).font(.footnote)
            Spacer(minLength: 0)
            if PlaybackPresentation.offersResync(notice) {
                Button("Resync", action: onResync).font(.footnote)
            } else if PlaybackPresentation.offersRetry(notice) {
                Button("Retry", action: onRetry).font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// Genius 鈕（CR-030；s6-61-genius.md §4.2 iPad）：寬膠囊 ◀◀ 前。純函式，單測
enum GeniusPresentation {
    enum Button: Equatable { case hidden, disabled, needsAccessibility, ready }

    /// 舊 Mac（事件不帶 genius）或還沒收到事件＝不顯示；斷線、Music 不可用＝停用。
    /// 可按＝沒歌且停止（CR-031：Music 自選起點，在場 #14 與 G8-0 實測）或有歌且播放／暫停；其餘（有殘留曲卻停止等未驗狀態）停用
    static func button(connected: Bool, event: PlaybackEvent?) -> Button {
        guard let event, let genius = event.genius else { return .hidden }
        let pressable = event.trackID == nil ? event.state == .stopped : event.state != .stopped
        guard connected, event.availability == .ok, pressable else { return .disabled }
        return genius == .ready ? .ready : .needsAccessibility
    }

    /// 未授權仍可按（按了只給提示、不送）
    static func isPressable(_ button: Button) -> Bool { button == .ready || button == .needsAccessibility }
    static func sends(_ button: Button) -> Bool { button == .ready }

    /// Genius 專用：按下後未觀測、逾時、斷線＝無法確認（按下可能已改寫「接下來」）；錯誤碼 notApplied＝沒按
    static func notice(for result: Result<ControlOutcome, EchoRequestError>) -> PlaybackPresentation.Notice? {
        switch result {
        case .success(.applied): nil
        case .success(.notApplied), .failure(.timeout), .failure(.disconnected): .uncertain
        case .failure(.remote(.notApplied)): .notApplied
        case .failure(let error): PlaybackPresentation.notice(for: error)
        }
    }
}

