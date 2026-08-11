import AppKit
import SwiftUI

// 紅色關閉鈕＝隱藏窗口而非關閉（py:2052-2060 on_closing 返回 False 的等價）。
// 以代理鏈方式接管：只覆寫 windowShouldClose，其餘選擇器轉發給 SwiftUI 原本的 delegate，
// 避免奪走窗口還原、Scene 生命週期等系統行為。
@MainActor
final class WindowCloseInterceptor: NSObject, NSWindowDelegate {
    private weak var next: NSWindowDelegate?

    func attach(to window: NSWindow) {
        guard window.delegate !== self else { return }
        next = window.delegate
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return next?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        next
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> WindowCloseInterceptor { WindowCloseInterceptor() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let interceptor = context.coordinator
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            interceptor.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        context.coordinator.attach(to: window)
    }
}
