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
