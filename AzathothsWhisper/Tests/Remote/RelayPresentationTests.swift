import CoreImage
import Foundation
import RemoteProtocol
import Testing

@testable import AzathothsWhisper
import MusicRemoteBridge

// S2 T9：中繼設定頁會判斷的邏輯（純函式）

@Suite("RelayPresentation")
struct RelayPresentationTests {
    @Test func statusTextIsEnglishRuntimeStatus() {
        #expect(RelayPresentation.statusText(.off, connected: 0) == StatusText.relayOff)
        #expect(RelayPresentation.statusText(.warmingUp, connected: 0) == StatusText.relayWaitingForKeychain)
        #expect(RelayPresentation.statusText(.needsKeychainApproval, connected: 0) == StatusText.relayNeedsKeychainApproval)
        #expect(RelayPresentation.statusText(.running, connected: 0) == StatusText.relayRunning)
        #expect(RelayPresentation.statusText(.running, connected: 2) == "Running · 2 connected")
        #expect(RelayPresentation.statusText(.paused, connected: 0) == StatusText.relayPaused)
        #expect(RelayPresentation.statusText(.failed, connected: 0) == StatusText.relayFailed)
    }

    @Test func countdownNeverNegativeAndRoundsUp() {
        let t = Date(timeIntervalSince1970: 1_000)
        #expect(RelayPresentation.secondsLeft(until: t.addingTimeInterval(59.2), now: t) == 60)
        #expect(RelayPresentation.secondsLeft(until: t, now: t) == 0)
        #expect(RelayPresentation.secondsLeft(until: t, now: t.addingTimeInterval(5)) == 0)
    }

    @Test func pairButtonOnlyWhenRunningAndIdle() {
        #expect(RelayPresentation.canStartPairing(status: .running, pairing: .idle))
        #expect(!RelayPresentation.canStartPairing(status: .running, pairing: .confirming(name: "x", suffix: "0000")))
        #expect(!RelayPresentation.canStartPairing(status: .paused, pairing: .idle))
        #expect(RelayPresentation.canStartPairing(status: .running, pairing: .finished(.expired)))
    }

    @Test func qrImageDecodesBackToPayloadText() throws {
        let text = "YSE1:" + String(repeating: "Ab-_", count: 48)
        let image = try #require(QRCodeImage.make(text: text, scale: 6))
        #expect(image.width == image.height)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil))
        let features = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(features == [text])
    }
}

// S4 T9（sprint-4-detail.md §4.2、§4.6、§4.9 #2）：設定頁的捷徑與 Music 控制權限
@Suite("RelayPresentation.Playback")
struct RelayPlaybackPresentationTests {
    private let id = ShortcutIdentifier("8CF4FBAD-400E-412D-A7BA-D3BC9D2939CF")!

    @Test func idleStatusReflectsStoredBindingWithoutCheckingNow() {
        #expect(RelayPresentation.shortcutStatusKey(.idle, stored: true) == "relay_shortcut_status_saved")
        #expect(RelayPresentation.shortcutStatusKey(.idle, stored: false) == "relay_shortcut_status_none")
    }

    @Test func checkAndInstallStatesHaveTheirOwnText() {
        #expect(RelayPresentation.shortcutStatusKey(.checking, stored: true) == "relay_shortcut_checking")
        #expect(RelayPresentation.shortcutStatusKey(.checked(bound: true), stored: true) == "relay_shortcut_status_bound")
        #expect(RelayPresentation.shortcutStatusKey(.checked(bound: false), stored: true) == "relay_shortcut_status_missing")
        #expect(RelayPresentation.shortcutStatusKey(.installing(.waitingForAdd), stored: false) == "relay_shortcut_waiting_for_add")
        #expect(RelayPresentation.shortcutStatusKey(.installing(.confirmingFirstRun), stored: false) == "relay_shortcut_confirming")
        #expect(RelayPresentation.shortcutStatusKey(.installed, stored: true) == "relay_shortcut_installed")
    }

    @Test func installFailuresAreDistinguished() {
        let cases: [(ShortcutInstaller.Outcome, String)] = [
            (.listUnavailable, "relay_shortcut_failed_list"), (.signFailed, "relay_shortcut_failed_sign"),
            (.openFailed, "relay_shortcut_failed_open"), (.notDetected, "relay_shortcut_not_detected"),
            (.nameTaken, "relay_shortcut_name_taken"), (.ambiguous, "relay_shortcut_name_taken"),
        ]
        for (outcome, key) in cases {
            #expect(RelayPresentation.shortcutStatusKey(.installFailed(outcome), stored: false) == key)
        }
    }

    /// s4-followups T5：已有捷徑時常駐提示「從 iPad 點歌時若再問分享，選永遠允許」；安裝中、遺失、失敗時不顯示（各有自己的文案）
    @Test func shareHintShowsOnlyWithAWorkingStoredShortcut() {
        #expect(RelayPresentation.showsShareHint(stored: true, panel: .idle))
        #expect(RelayPresentation.showsShareHint(stored: true, panel: .checked(bound: true)))
        #expect(RelayPresentation.showsShareHint(stored: true, panel: .installed))
        #expect(!RelayPresentation.showsShareHint(stored: false, panel: .idle))
        #expect(!RelayPresentation.showsShareHint(stored: true, panel: .checked(bound: false)))
        #expect(!RelayPresentation.showsShareHint(stored: true, panel: .checking))
        #expect(!RelayPresentation.showsShareHint(stored: true, panel: .installing(.confirmingFirstRun)))
        #expect(!RelayPresentation.showsShareHint(stored: true, panel: .installFailed(.notDetected)))
        #expect(RelayPresentation.playbackKeys.contains("relay_shortcut_share_hint"))
    }

    @Test func installButtonSaysReinstallOnceABindingExists() {
        #expect(RelayPresentation.shortcutInstallKey(stored: false) == "relay_shortcut_install")
        #expect(RelayPresentation.shortcutInstallKey(stored: true) == "relay_shortcut_reinstall")
    }

    /// 只在中繼開著、且沒有進行中的檢查或安裝時可按（D13：中繼關閉不跑 shortcuts 指令）
    @Test func shortcutActionsOnlyWhileRunningAndIdle() {
        #expect(RelayPresentation.canManageShortcut(status: .running, panel: .idle))
        #expect(RelayPresentation.canManageShortcut(status: .running, panel: .installFailed(.notDetected)))
        #expect(!RelayPresentation.canManageShortcut(status: .off, panel: .idle))
        #expect(!RelayPresentation.canManageShortcut(status: .paused, panel: .idle))
        #expect(!RelayPresentation.canManageShortcut(status: .running, panel: .checking))
        #expect(!RelayPresentation.canManageShortcut(status: .running, panel: .installing(.waitingForAdd)))
    }

    @Test func automationSettingsURLPointsAtAutomationPrivacy() {
        #expect(RelayPresentation.automationPrivacySettingsURL.absoluteString.hasSuffix("Privacy_Automation"))
    }

    /// CR-030 G5：Genius 需要 Azathoth 本身的輔助使用權限；未允許才給「開啟輔助使用設定」鈕（不自動彈系統詢問框）
    @Test func geniusRowFollowsAccessibilityAvailability() {
        #expect(RelayPresentation.geniusStatusKey(.ready) == "relay_genius_status_ready")
        #expect(RelayPresentation.geniusStatusKey(.needsAccessibility) == "relay_genius_status_needs_accessibility")
        #expect(!RelayPresentation.showsAccessibilityButton(.ready))
        #expect(RelayPresentation.showsAccessibilityButton(.needsAccessibility))
        #expect(RelayPresentation.accessibilityPrivacySettingsURL.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        for key in ["relay_genius_explanation", "relay_genius_status_ready", "relay_genius_status_needs_accessibility",
                    "relay_open_accessibility_privacy"] {
            #expect(RelayPresentation.playbackKeys.contains(key), "\(key) 要列進三語核對")
        }
    }

    /// 新文案三語齊備（N-10）：以編譯後的 .lproj 逐鍵核對
    @Test(arguments: ["en", "zh-Hant", "ja"])
    func playbackKeysExistInAllLanguages(language: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        for key in RelayPresentation.playbackKeys {
            #expect(bundle.localizedString(forKey: key, value: "<<missing>>", table: nil) != "<<missing>>", "\(language) 缺 \(key)")
        }
    }
}
