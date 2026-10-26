import AppKit
import MusicRemoteBridge
import RemoteProtocol
import SwiftUI

/// 中繼設定 modal（S2 詳設 §4.11 v1.1）：開關、狀態、預熱授權、配對 QR 與確認、已配對 iPad 清單。
/// 樣式比照 SettingsModalView；標題英文覆寫（D-03 慣例）。QR 是一次性秘密：不設 accessibility label、不可複製、
/// 顯示期間把視窗設為不可被擷取（縱深防禦）。
struct RelaySettingsView: View {
    let host: RelayHost
    let onClose: () -> Void
    @State private var pendingRevoke: RelayHost.PeerRow?
    /// Genius 的輔助使用權限：開啟時與回到前景時重讀（使用者在系統設定改完切回來）
    @State private var genius: GeniusAvailability = GeniusAccess.availability()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                switch host.pairing {
                case .showingQR(let text, let expiresAt): qrPanel(text: text, expiresAt: expiresAt)
                case .confirming(let name, let suffix): confirmPanel(name: name, suffix: suffix)
                case .finished(let outcome): resultPanel(outcome)
                case .idle: mainPanel
                }
            }
            .padding(.top, 24)
        }
        .padding(32)
        .frame(width: 512)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.Gray.g800, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                MaterialSymbol(.close, size: 24).foregroundStyle(Theme.Gray.g500)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .alert("relay_revoke_confirm_title", isPresented: revokeBinding, presenting: pendingRevoke) { peer in
            Button("relay_revoke_button", role: .destructive) { host.revoke(peer.id) }
            Button("relay_cancel_button", role: .cancel) {}
        } message: { peer in
            Text(verbatim: "\(peer.name) · …\(peer.suffix)")
        }
    }

    private var revokeBinding: Binding<Bool> {
        Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: StatusText.remoteSettingsTitle)
                .font(Theme.Fonts.display(20, weight: .bold))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(.white)
                .padding(.bottom, 16)
            Rectangle().fill(Theme.Gray.g800).frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 主畫面

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldLabel("relay_section_label")
            settingsToggle("relay_toggle", isOn: Binding(get: { host.isEnabled }, set: { value in Task { await host.setEnabled(value) } }))

            Text(verbatim: RelayPresentation.statusText(host.status, connected: host.peers.filter(\.isConnected).count))
                .font(Theme.Fonts.display(12))
                .foregroundStyle(Theme.Gray.g500)
            loginItemRow

            if host.libraryUnavailable {
                Text("relay_library_unavailable").font(Theme.Fonts.display(12)).foregroundStyle(.white)
                modalButton("relay_open_media_privacy") { NSWorkspace.shared.open(RelayPresentation.mediaPrivacySettingsURL) }
            }
            if host.status == .needsKeychainApproval {
                Text("relay_keychain_explanation").font(Theme.Fonts.display(12)).foregroundStyle(.white)
                modalButton("relay_retry_authorization") { Task { await host.retryAuthorization() } }
            }
            if RelayPresentation.canStartPairing(status: host.status, pairing: host.pairing) {
                modalButton("relay_pair_new_ipad") { host.startPairing() }
            }
            if host.status == .running { playbackPanel }
            if !host.peers.isEmpty {
                fieldLabel("relay_paired_devices")
                ForEach(host.peers) { peer in peerRow(peer) }
            }
        }
    }

    /// 登入時啟動（S6 F-R-06、§4.10）：狀態以系統為準；需要批准時引導到系統設定；失敗回原值並顯示錯誤種類
    private var loginItemRow: some View {
        let item = host.loginItem
        return VStack(alignment: .leading, spacing: 8) {
            settingsToggle("login_item_toggle",
                           isOn: Binding(get: { LoginItemPresentation.isOn(item.status) }, set: { on in Task { await item.setEnabled(on) } }))
                .disabled(item.isBusy)
            if let note = LoginItemPresentation.noteKey(item.status) {
                Text(LocalizedStringKey(note)).font(Theme.Fonts.display(12)).foregroundStyle(Theme.Gray.g500)
            }
            if LoginItemPresentation.showsSettingsButton(item.status) {
                modalButton("login_item_open_settings") { item.openSystemSettings() }
            }
            if let failure = item.failure {
                Text("login_item_failed \(failure)").font(Theme.Fonts.display(12)).foregroundStyle(.white)
            }
        }
        .onAppear { item.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in item.refresh() }
    }

    /// Music 控制（S4）：未允許控制 Music 的說明、捷徑狀態與安裝
    private var playbackPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel("relay_playback_section")
            if host.musicNotAuthorized {
                Text("relay_music_not_authorized").font(Theme.Fonts.display(12)).foregroundStyle(.white)
                modalButton("relay_open_automation_privacy") { NSWorkspace.shared.open(RelayPresentation.automationPrivacySettingsURL) }
            }
            Text("relay_shortcut_explanation").font(Theme.Fonts.display(12)).foregroundStyle(Theme.Gray.g500)
            Text(LocalizedStringKey(RelayPresentation.shortcutStatusKey(host.shortcut, stored: host.hasStoredShortcut)))
                .font(Theme.Fonts.display(12))
                .foregroundStyle(.white)
            if RelayPresentation.showsShareHint(stored: host.hasStoredShortcut, panel: host.shortcut) {
                Text("relay_shortcut_share_hint").font(Theme.Fonts.display(12)).foregroundStyle(Theme.Gray.g500)
            }
            let enabled = RelayPresentation.canManageShortcut(status: host.status, panel: host.shortcut)
            HStack(spacing: 12) {
                modalButton("relay_shortcut_recheck") { Task { await host.checkShortcut() } }
                modalButton(LocalizedStringKey(RelayPresentation.shortcutInstallKey(stored: host.hasStoredShortcut))) {
                    Task { await host.installShortcut() }
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
            geniusRow
        }
    }

    /// Genius（CR-030）：只顯示狀態與「開啟輔助使用設定」，不主動彈系統詢問框
    private var geniusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("relay_genius_explanation").font(Theme.Fonts.display(12)).foregroundStyle(Theme.Gray.g500)
            Text(LocalizedStringKey(RelayPresentation.geniusStatusKey(genius))).font(Theme.Fonts.display(12)).foregroundStyle(.white)
            if RelayPresentation.showsAccessibilityButton(genius) {
                modalButton("relay_open_accessibility_privacy") { NSWorkspace.shared.open(RelayPresentation.accessibilityPrivacySettingsURL) }
            }
        }
        .onAppear { genius = GeniusAccess.availability() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            genius = GeniusAccess.availability()
        }
    }

    private func peerRow(_ peer: RelayHost.PeerRow) -> some View {
        HStack {
            Circle().fill(peer.isConnected ? Theme.success : Theme.Gray.g800).frame(width: 8, height: 8)
            Text(verbatim: "\(peer.name) · …\(peer.suffix)").font(Theme.Fonts.display(14)).foregroundStyle(.white)
            Text(peer.pairedAt, style: .date).font(Theme.Fonts.display(11)).foregroundStyle(Theme.Gray.g500)
            Spacer()
            Button("relay_revoke_button") { pendingRevoke = peer }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Gray.g500)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
        .overlay(Rectangle().strokeBorder(Theme.Gray.g800, lineWidth: 1))
    }

    // MARK: 配對

    private func qrPanel(text: String, expiresAt: Date) -> some View {
        VStack(spacing: 16) {
            Text("relay_scan_instruction").font(Theme.Fonts.display(14)).foregroundStyle(.white)
            if let image = QRCodeImage.make(text: text, scale: 8) {
                Image(decorative: image, scale: 2)
                    .interpolation(.none)
                    .accessibilityHidden(true)
                    .background(CaptureShield())
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(verbatim: "\(RelayPresentation.secondsLeft(until: expiresAt, now: context.date))s")
                    .font(Theme.Fonts.display(12))
                    .foregroundStyle(Theme.Gray.g500)
            }
            modalButton("relay_cancel_button") { host.cancelPairing() }
        }
        .frame(maxWidth: .infinity)
    }

    private func confirmPanel(name: String, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("relay_unverified_request_title").font(Theme.Fonts.display(16, weight: .bold)).foregroundStyle(.white)
            Text("relay_unverified_request_body").font(Theme.Fonts.display(12)).foregroundStyle(Theme.Gray.g500)
            Text(verbatim: "\(name) · \(suffix)").font(Theme.Fonts.display(20, weight: .bold)).foregroundStyle(.white)
            HStack(spacing: 12) {
                modalButton("relay_reject_button") { host.rejectPairing() }
                modalButton("relay_allow_button") { host.approvePairing() }
            }
        }
    }

    private func resultPanel(_ outcome: PairOutcome) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(resultKey(outcome)).font(Theme.Fonts.display(14)).foregroundStyle(.white)
            HStack(spacing: 12) {
                if outcome != .approved { modalButton("relay_generate_new_code") { host.startPairing() } }
                modalButton("relay_done_button") { host.dismissPairingResult() }
            }
        }
    }

    private func resultKey(_ outcome: PairOutcome) -> LocalizedStringKey {
        switch outcome {
        case .approved: "relay_result_approved"
        case .rejected: "relay_result_rejected"
        case .expired: "relay_result_expired"
        case .cancelled: "relay_result_cancelled"
        }
    }

    // MARK: 零件（同 SettingsModalView）

    /// 黑底、灰框的一列開關（中繼開關、登入時啟動共用）
    private func settingsToggle(_ key: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(key).font(Theme.Fonts.display(14)).foregroundStyle(.white)
        }
        .toggleStyle(.switch)
        .tint(Theme.success)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
        .overlay(Rectangle().strokeBorder(Theme.Gray.g800, lineWidth: 1))
    }

    private func fieldLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Theme.Fonts.display(10))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Theme.Gray.g500)
    }

    private func modalButton(_ key: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key)
                .font(Theme.Fonts.display(14, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white)
        }
        .buttonStyle(.plain)
    }
}

/// QR 顯示期間把所在視窗設為不可被螢幕擷取，消失時還原（縱深防禦；擋不住也不影響安全模型）
private struct CaptureShield: NSViewRepresentable {
    final class ShieldView: NSView {
        private var previous: NSWindow.SharingType?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                previous = window.sharingType
                window.sharingType = .none
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, let window, let previous { window.sharingType = previous }
            super.viewWillMove(toWindow: newWindow)
        }
    }

    func makeNSView(context: Context) -> ShieldView { ShieldView() }
    func updateNSView(_ nsView: ShieldView, context: Context) {}
}
