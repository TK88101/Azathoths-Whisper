import SwiftUI

// Modal 背板（py:266-267 / 297）：fixed inset-0 z-50 bg-black/80 backdrop-blur-sm，內容置中。
// Plan §4.2：Settings/About 為主窗內覆蓋層，非獨立 NSWindow、非 sheet。
struct ModalScrim<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            VisualEffectView(material: .fullScreenUI)
            Color.black.opacity(0.8)
            content
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .onExitCommand(perform: onDismiss)
    }
}
