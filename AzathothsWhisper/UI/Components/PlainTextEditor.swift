import AppKit
import SwiftUI

// 歌詞編輯框（py:185）：font-mono、p-6、透明底、拼寫檢查關閉、選取＝白底黑字。
// 走 NSTextView 而非 SwiftUI TextEditor —— 後者無法關閉連續拼寫檢查，也無法設定選取配色。
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let textColor: NSColor
    let insets: NSSize

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = .white
        textView.textContainerInset = insets
        // py:185 spellcheck="false"
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        // selection:bg-white selection:text-black
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.white,
            .foregroundColor: NSColor.black,
        ]
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = font
        textView.textColor = textColor
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}
