import SwiftUI

/// 左上設定鈕開的設定頁（CR-023 D2）：連線狀態與 Mac 名稱、Forget this Mac（立即＋確認）、外觀、背景
struct SettingsSheet: View {
    @Bindable var appearance: AppearanceViewModel
    @Bindable var background: BackgroundViewModel
    let connection: ConnectionViewModel
    let turntable: TurntableViewModel
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
                // CR-034 增補 A：目前外觀＋小圖（只露支點與底座），點入選擇器；唱機沒開也能換。只有一款時不顯示
                if turntable.canBrowseSkins { turntableSection }
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
            .toolbar { doneButton }
            .confirmationDialog(Text("Forget this Mac?"), isPresented: $confirmingForget, titleVisibility: .visible) {
                Button("Forget this Mac", role: .destructive) {
                    dismiss()
                    Task { await connection.forgetMac() }
                }
                .accessibilityIdentifier(AccessibilityID.settingsForgetConfirm)
            }
        }
    }

    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }.accessibilityIdentifier(AccessibilityID.settingsDone)
        }
    }

    private var turntableSection: some View {
        Section("Turntable") {
            NavigationLink {
                ScrollView {
                    TurntableSkinPicker(model: turntable).padding(20)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(Text("Turntable Skin"))
                // 工具列只掛在首頁：推進來的這頁也要能直接關掉設定
                .toolbar { doneButton }
            } label: {
                HStack(spacing: 12) {
                    SkinPreviewImage(previews: turntable.previews, skin: turntable.skin, crop: .head, size: CGSize(width: 44, height: 44))
                        .padding(4)
                        .background(SkinTileBackground())
                    Text("Turntable Skin")
                    Spacer()
                    SkinTitle(skin: turntable.skin).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier(AccessibilityID.settingsTurntableSkin)
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
