import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import MusicRemoteBridge
import RemoteProtocol

/// 中繼設定頁會判斷的邏輯（純函式；CLAUDE.md：View 判斷抽純函式並單測）
enum RelayPresentation {
    static func statusText(_ status: RelayHost.Status, connected: Int) -> String {
        switch status {
        case .off: StatusText.relayOff
        case .warmingUp: StatusText.relayWaitingForKeychain
        case .needsKeychainApproval: StatusText.relayNeedsKeychainApproval
        case .running: connected > 0 ? StatusText.relayRunning(connected: connected) : StatusText.relayRunning
        case .paused: StatusText.relayPaused
        case .failed: StatusText.relayFailed
        }
    }

    /// QR 倒數（無條件進位、不為負）
    static func secondsLeft(until expiresAt: Date, now: Date) -> Int {
        max(0, Int(expiresAt.timeIntervalSince(now).rounded(.up)))
    }

    /// 系統設定「隱私權與安全性 → 媒體與 Apple Music」（設計 §5.4 曲庫權限被拒）
    static let mediaPrivacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media")!

    // MARK: Music 控制（S4 §4.6、§4.9 #2）

    /// 系統設定「隱私權與安全性 → 自動化」
    static let automationPrivacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    // MARK: Genius（CR-030）：Azathoth 本身的輔助使用權限

    /// 系統設定「隱私權與安全性 → 輔助使用」
    static let accessibilityPrivacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func geniusStatusKey(_ availability: GeniusAvailability) -> String {
        switch availability {
        case .ready: "relay_genius_status_ready"
        case .needsAccessibility: "relay_genius_status_needs_accessibility"
        }
    }

    static func showsAccessibilityButton(_ availability: GeniusAvailability) -> Bool { availability == .needsAccessibility }

    static func shortcutStatusKey(_ panel: RelayHost.ShortcutPanel, stored: Bool) -> String {
        switch panel {
        case .idle: stored ? "relay_shortcut_status_saved" : "relay_shortcut_status_none"
        case .checking: "relay_shortcut_checking"
        case .checked(let bound): bound ? "relay_shortcut_status_bound" : "relay_shortcut_status_missing"
        case .installing(.waitingForAdd): "relay_shortcut_waiting_for_add"
        case .installing(.confirmingFirstRun): "relay_shortcut_confirming"
        case .installed: "relay_shortcut_installed"
        case .installFailed(let outcome): installFailureKey(outcome)
        }
    }

    private static func installFailureKey(_ outcome: ShortcutInstaller.Outcome) -> String {
        switch outcome {
        case .listUnavailable: "relay_shortcut_failed_list"
        case .signFailed: "relay_shortcut_failed_sign"
        case .openFailed: "relay_shortcut_failed_open"
        case .notDetected: "relay_shortcut_not_detected"
        // 不猜選、不自動刪除：兩者都請使用者先刪掉舊的（CR-014）
        case .nameTaken, .ambiguous: "relay_shortcut_name_taken"
        case .installed: "relay_shortcut_installed"
        }
    }

    /// 已有可用捷徑時常駐「從 iPad 點歌若再問分享，選永遠允許」（#4-1：安裝試跑只授權了辭書，第一次真點歌會再問）。
    /// 安裝中、遺失、失敗時不顯示——各有自己的文案
    static func showsShareHint(stored: Bool, panel: RelayHost.ShortcutPanel) -> Bool {
        guard stored else { return false }
        switch panel {
        case .idle, .installed, .checked(bound: true): return true
        case .checked(bound: false), .checking, .installing, .installFailed: return false
        }
    }

    static func shortcutInstallKey(stored: Bool) -> String { stored ? "relay_shortcut_reinstall" : "relay_shortcut_install" }

    static func canManageShortcut(status: RelayHost.Status, panel: RelayHost.ShortcutPanel) -> Bool {
        guard status == .running else { return false }
        switch panel {
        case .checking, .installing: return false
        case .idle, .checked, .installed, .installFailed: return true
        }
    }

    /// 本區塊用到的全部文案鍵（三語齊備由測試核對）
    static let playbackKeys = [
        "relay_playback_section", "relay_shortcut_explanation", "relay_music_not_authorized", "relay_open_automation_privacy",
        "relay_shortcut_install", "relay_shortcut_reinstall", "relay_shortcut_recheck",
        "relay_shortcut_status_saved", "relay_shortcut_status_none", "relay_shortcut_status_bound", "relay_shortcut_status_missing",
        "relay_shortcut_checking", "relay_shortcut_waiting_for_add", "relay_shortcut_confirming", "relay_shortcut_installed",
        "relay_shortcut_share_hint", "relay_shortcut_failed_list", "relay_shortcut_failed_sign", "relay_shortcut_failed_open", "relay_shortcut_not_detected",
        "relay_shortcut_name_taken",
        "relay_genius_explanation", "relay_genius_status_ready", "relay_genius_status_needs_accessibility", "relay_open_accessibility_privacy",
    ]

    static func canStartPairing(status: RelayHost.Status, pairing: RelayHost.Pairing) -> Bool {
        guard status == .running else { return false }
        switch pairing {
        case .idle, .finished: return true
        case .showingQR, .confirming: return false
        }
    }
}

/// 配對 QR（CR-010 ⑤）：CoreImage 產生、糾錯等級 M、最近鄰放大、四周留 4 模組 quiet zone；碼本體靜態黑白
enum QRCodeImage {
    static let quietZoneModules: CGFloat = 4
    /// CIContext 建構昂貴、可跨執行緒共用（body 每次重算都會呼叫 make）
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func make(text: String, scale: CGFloat) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let padded = code.transformed(by: CGAffineTransform(translationX: quietZoneModules, y: quietZoneModules))
            .composited(over: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: code.extent.width + quietZoneModules * 2,
                                                                        height: code.extent.height + quietZoneModules * 2)))
        let scaled = padded.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}
