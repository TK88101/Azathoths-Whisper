import SwiftUI

/// 左上設定鈕開的設定頁（CR-023 D2）：連線狀態與 Mac 名稱、Forget this Mac（立即＋確認）、外觀、背景
struct SettingsSheet: View {
    @Bindable var appearance: AppearanceViewModel
    @Bindable var background: BackgroundViewModel
    let connection: ConnectionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmingForget = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    connectionRow
                    Button("Forget this Mac", role: .destructive) { confirmingForget = true }
                        .accessibilityIdentifier(AccessibilityID.settingsForget)
                }
                Section {
                    Picker("Appearance", selection: $appearance.setting) {
                        ForEach(AppearanceSetting.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(AccessibilityID.appearancePicker)
                }
                Section("Background") {
                    Picker(selection: $background.preset) {
                        ForEach(BackgroundPreset.allCases, id: \.self) { preset in
                            Label { Text(preset.title) } icon: { Image(uiImage: BackgroundSwatch.image(preset, scheme: colorScheme)) }
                                .tag(preset)
                        }
                    } label: { Text("Background") }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                // ID 掛在區段上：掛在 Picker 上會被每一列繼承，列就無法以名稱找到
                .accessibilityIdentifier(AccessibilityID.backgroundMenu)
                Section("Album Detail") {
                    Picker(selection: $background.detailMode) {
                        ForEach(DetailBackgroundMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    } label: { Text("Album Detail") }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier(AccessibilityID.settingsDone)
                }
            }
            .confirmationDialog(Text("Forget this Mac?"), isPresented: $confirmingForget, titleVisibility: .visible) {
                Button("Forget this Mac", role: .destructive) {
                    dismiss()
                    Task { await connection.forgetMac() }
                }
                .accessibilityIdentifier(AccessibilityID.settingsForgetConfirm)
            }
        }
    }

    @ViewBuilder private var connectionRow: some View {
        switch connection.state {
        case .connected(let name):
            LabeledContent {
                Text(verbatim: name).lineLimit(1).truncationMode(.middle)
            } label: {
                Label { Text("Connected") } icon: { Image(systemName: "checkmark.circle.fill") }
            }
        default:
            Text("Connecting to your Mac…")
        }
    }
}
