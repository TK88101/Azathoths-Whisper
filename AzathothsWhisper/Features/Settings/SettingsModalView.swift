import SwiftUI

// Settings modal（py:265-294）：max-w-lg、bg #0a0a0a、border gray-800、p-8
struct SettingsModalView: View {
    @Bindable var model: SettingsViewModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                switch model.group {
                case .token: tokenGroup
                case .language: languageGroup
                case .notifications: notificationsGroup
                case .cloudSync: cloudSyncGroup
                }
            }
            .padding(.top, 24)
        }
        .padding(32)                                   // p-8
        .frame(width: 512)                             // max-w-lg
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.Gray.g800, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Button(action: model.close) {
                MaterialSymbol(.close, size: 24)
                    .foregroundStyle(Theme.Gray.g500)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .alert(model.languageAlert ?? "", isPresented: languageAlertBinding) {
            Button("OK") { model.dismissLanguageAlert() }
        }
        .alert(Text("settings_sync_reset_confirm"), isPresented: resetConfirmBinding) {
            Button(role: .destructive) { Task { await model.confirmCloudSyncReset() } } label: { Text("settings_sync_reset_ok") }
            Button(role: .cancel) { model.cancelCloudSyncReset() } label: { Text("settings_sync_reset_cancel") }
        }
        .onAppear { isFieldFocused = true }            // py:789/794 focus
    }

    private var languageAlertBinding: Binding<Bool> {
        Binding(
            get: { model.languageAlert != nil },
            set: { if !$0 { model.dismissLanguageAlert() } }
        )
    }

    // py:271：標題在開啟時被英文覆寫（D-03）
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: model.title)
                .font(Theme.Fonts.display(20, weight: .bold))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(.white)
                .padding(.bottom, 16)
            Rectangle()
                .fill(Theme.Gray.g800)
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Token（py:275-280）

    private var tokenGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel("token_label")
            // 用 SecureField 而非 TextField（2026-09-05 使用者拍板）：token 是憑證，
            // 明文渲染會經由兩條路外洩——肩窺，以及 XCTest 的**失敗自動截圖**
            // （後者會繞過「不主動截圖此 modal」那條人工紀律，見 memory
            // no-credential-fields-in-ui-screenshots）。SecureField 讓明文不進畫面、
            // 也不進 AX 樹的 value。保存邏輯完全不變，仍綁同一個 `model.tokenInput`。
            SecureField("", text: $model.tokenInput, prompt: Text(verbatim: "Enter your token..."))
                .textFieldStyle(.plain)
                .font(Theme.Fonts.display(14))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black)
                .overlay(Rectangle().strokeBorder(Theme.Gray.g800, lineWidth: 1))
                .focused($isFieldFocused)
                .onSubmit { Task { await model.saveToken() } }

            Text(verbatim: model.tokenStatus.message ?? "")
                .font(Theme.Fonts.display(12))
                .foregroundStyle(statusColor)
                .frame(height: 16, alignment: .leading)
                .padding(.top, 8)

            modalButton(titleKey: "save_btn") {
                Task { await model.saveToken() }
            }
            .padding(.top, 16)
            .disabled(model.isValidating)
        }
    }

    private var statusColor: Color {
        switch model.tokenStatus {
        case .none, .info: return Theme.Gray.g400
        case .success: return Theme.success
        case .failure: return Theme.danger
        }
    }

    // MARK: Language（py:283-291）

    private var languageGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel("lang_label")
            Picker("", selection: $model.language) {
                Text(verbatim: "English").tag(AppLanguage.en)
                Text(verbatim: "Traditional Chinese (繁體中文)").tag(AppLanguage.zhTW)
                Text(verbatim: "Japanese (日本語)").tag(AppLanguage.ja)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black)
            .overlay(Rectangle().strokeBorder(Theme.Gray.g800, lineWidth: 1))

            modalButton(titleKey: "save_btn") { model.saveLanguage() }
                .padding(.top, 16)
        }
    }

    // MARK: Notifications（2.1 新增，計劃 2026-09-26-lyrics-notification §4.4）

    private var notificationsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel("settings_notify_label")
            Toggle(isOn: notificationsBinding) {
                Text("settings_notify_toggle")
                    .font(Theme.Fonts.display(14))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .tint(Theme.success)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black)
            .overlay(Rectangle().strokeBorder(Theme.Gray.g800, lineWidth: 1))
        }
    }

    /// 切換即存：setter 直接交給 ViewModel，不另設 Save 鈕
    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { model.notificationsEnabled },
            set: { model.setNotificationsEnabled($0) }
        )
    }

    // MARK: iCloud 同步（⑨ 計劃 §6.6）

    private var cloudSyncGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel("settings_sync_label")
            Toggle(isOn: cloudSyncBinding) {
                Text("settings_sync_toggle")
                    .font(Theme.Fonts.display(14))
                    .foregroundStyle(.white)
            }
            .toggleStyle(.switch)
            .tint(Theme.success)
            .disabled(model.cloudSync.unavailable)
            .accessibilityIdentifier(AccessibilityID.cloudSyncToggle)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black)
            .overlay(Rectangle().strokeBorder(Theme.Gray.g800, lineWidth: 1))

            Text("settings_sync_what")
                .font(Theme.Fonts.display(12))
                .foregroundStyle(Theme.Gray.g400)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text("settings_sync_new_mac")
                .font(Theme.Fonts.display(12))
                .foregroundStyle(Theme.Gray.g400)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.cloudSync.statusLines) { line in
                    statusText(line)
                        .font(Theme.Fonts.display(12))
                        .foregroundStyle(statusLineColor(line))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.cloudSyncStatus)
            .padding(.top, 12)

            Button(action: model.requestCloudSyncReset) {
                Text("settings_sync_reset")
                    .font(Theme.Fonts.display(12))
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.cloudSyncReset)
            .padding(.top, 16)
        }
    }

    private func statusText(_ line: CloudSyncDisplay.Line) -> Text {
        let when = line.date?.formatted(date: .abbreviated, time: .shortened) ?? ""
        switch line.kind {
        case .lastExport: return Text("settings_sync_last_export \(when)")
        case .lastImport: return Text("settings_sync_last_import \(when)")
        case .otherMacs(let count): return Text("settings_sync_other_macs \(count)")
        case .skipped(let count): return Text("settings_sync_skipped \(count)")
        case .pendingDownloads(let count): return Text("settings_sync_pending \(count)")
        case .error(let kind): return Text("settings_sync_error \(kind)")
        case .unavailable: return Text("settings_sync_unavailable")
        }
    }

    private func statusLineColor(_ line: CloudSyncDisplay.Line) -> Color {
        switch line.kind {
        case .error, .unavailable: return Theme.danger
        default: return Theme.Gray.g400
        }
    }

    private var cloudSyncBinding: Binding<Bool> {
        Binding(get: { model.cloudSync.enabled }, set: { model.setCloudSyncEnabled($0) })
    }

    private var resetConfirmBinding: Binding<Bool> {
        Binding(get: { model.isConfirmingCloudSyncReset }, set: { if !$0 { model.cancelCloudSyncReset() } })
    }

    // MARK: 零件

    private func fieldLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Theme.Fonts.display(10))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Theme.Gray.g500)
            .padding(.bottom, 8)
    }

    private func modalButton(titleKey: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titleKey)
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
