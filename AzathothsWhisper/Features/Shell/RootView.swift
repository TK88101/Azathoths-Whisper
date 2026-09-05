import SwiftUI

// 外殼：頁首導航 → 內容 → 頁尾狀態列，外加噪點層／modal／confetti（py:126-263）
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            Theme.background

            if model.isSplashVisible {
                SplashView()
            } else {
                shell
            }

            NoiseOverlay()

            if let modal = model.activeModal {
                ModalScrim(onDismiss: model.closeModal) {
                    switch modal {
                    case .settings:
                        SettingsModalView(model: model.settings)
                    case .about:
                        AboutModalView(onClose: model.closeModal)
                    }
                }
            }

            ConfettiView(trigger: model.confettiTrigger)
        }
        .background(WindowConfigurator())
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: model.isSplashVisible)
        .task { await model.start() }
    }

    private var shell: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }

    // MARK: 頁首（py:128-138）

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    MaterialSymbol(.graphicEq, size: 20)
                        .foregroundStyle(Theme.Gray.g400)
                    HStack(spacing: 0) {
                        Text(verbatim: AppInfo.title)
                            .font(Theme.Fonts.display(14, weight: .bold))
                            .textCase(.uppercase)
                            .tracking(2.1)                    // 0.15em @14px
                            .foregroundStyle(.white)
                            .textGlow()
                        Text(verbatim: "v\(AppInfo.version)")
                            .font(Theme.Fonts.display(14))
                            .foregroundStyle(Theme.Gray.g600)
                            .padding(.leading, 8)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 32) {                          // gap-8
                    ForEach(AppTab.allCases) { tab in
                        navLink(tab)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
        .background(Theme.background)
    }

    private func navLink(_ tab: AppTab) -> some View {
        let isActive = model.tab == tab
        return Button {
            model.select(tab)
        } label: {
            Text(tab.titleKey)
                .font(Theme.Fonts.display(14, weight: isActive ? .bold : .medium))
                .textCase(.uppercase)
                .tracking(1.4)                                 // tracking-widest
                .foregroundStyle(isActive ? Color.white : Theme.Gray.g500)
                .padding(.bottom, 4)                           // pb-1
                // 底線走 overlay：放進 VStack 會讓整個導航項撐滿剩餘寬度
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? Color.white : Color.clear)
                        .frame(height: 1)
                }
                .shadow(color: isActive ? Color.white.opacity(0.5) : .clear, radius: 10, y: 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 內容

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .editor:
            EditorView(model: model.editor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        case .batch:
            // Batch 自帶狀態欄與按鈕列，不套 Editor 的 footer（py:240-262）
            BatchView(model: model.batch)
        case .coverFlow:
            CoverFlowView(model: model.coverFlow)
        }
    }

    // MARK: 頁尾（py:190-203）

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            HStack(spacing: 0) {
                HStack(spacing: 24) {
                    HStack(spacing: 8) {
                        Text("status_label")
                        Text(verbatim: model.editor.statusText ?? String(localized: "status_ready"))
                    }
                    Text(verbatim: "|")
                        .foregroundStyle(Theme.Gray.g700)
                    HStack(spacing: 8) {
                        Text("lines_label")
                        Text(verbatim: "\(model.editor.lineCount)")
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 16) {
                    Text(verbatim: StatusText.fakeMemory)
                    Text(verbatim: StatusText.fakeLatency)
                }
                .opacity(0.5)
            }
            .font(Theme.Fonts.mono(10))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .background(Theme.background)
    }
}
