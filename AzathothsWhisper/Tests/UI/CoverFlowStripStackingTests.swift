import AppKit
import QuartzCore
import SwiftUI
import Testing

@testable import AzathothsWhisper

private let stackItemWidth: CGFloat = 260
private let stackViewSize = CGSize(width: 1192, height: 620)

private struct StackCard: Identifiable, Equatable { let id: Int }

/// H-02 缺陷 2（疊放）：正對觀者的那張——**畫面上**最接近視口中心者——必須畫在兩側鄰張之上，
/// 落定時如此，捲動途中的每一幀也如此。
///
/// **為何讀 CALayer 而不是 AX**：in-process 讀 AX 會讓 LazyHStack 多具現一張卡、改變之後的
/// 捲動落點（fix4 §13 F-AX）；讀層屬性沒有這個效應。
///
/// **不需要卡片身分**（fix4 §13 Z1 第 2 輪實證）：
/// - 卡層都掛在同一個父層下，`sublayers` 由底到頂的次序單調反映 `zIndex`（U1a）；
/// - 卡層的平移全烘在 `transform` 裡，由旋轉軸那條豎邊還原變換前的佈局 midX，誤差 ≤ 1pt（U1c）。
/// 於是「誰在正中」與「誰在上面」都從同一幀的層樹讀出，不經 `centerID`。
@Suite("CoverFlowStripStacking", .serialized)
@MainActor
struct CoverFlowStripStackingTests {

    // MARK: 落定

    /// 初始值路徑（切走再切回 Cover Flow 分頁）在 macOS 27 上會落在與 `centerID` 不同的卡上
    /// （EDGE 4–8 實測），這時疊放若跟著 `centerID` 走，畫面正中那張就被鄰張壓住。
    @Test("落定後，畫面正中那張壓在左右兩張之上", arguments: [1, 4, 6, 7])
    func settledCenterCardIsOnTop(initialCenter: Int) async throws {
        let session = StackSession.open(itemCount: 9, initialCenter: initialCenter)
        defer { session.close() }

        let frame = try #require(await session.settledFrame(), "層樹未穩定或讀不到卡層")
        print("STACK-SETTLED(\(initialCenter))  \(frame.report)")
        #expect(frame.centerIsOnTop, "畫面正中那張被鄰張壓住。\(frame.report)")
    }

    // MARK: 捲動途中（產品的兩條真實路徑）

    /// 觸控板滑動（手指拖動＋放開後的慣性）：這是使用者回報「滑動時互相覆蓋」的路徑。
    /// 疊放若跟 `centerID` 走，途中會一直落後於畫面。
    @Test("觸控板滑動途中每一幀，畫面正中那張都在最上層")
    func centerCardStaysOnTopWhileSwiping() async throws {
        let session = StackSession.open(itemCount: 20, initialCenter: nil)
        defer { session.close() }
        _ = try #require(await session.settledFrame(), "起始狀態未穩定")

        let frames = await session.sampling {
            await StackGesture.swipe(session.window, fingerDeltaX: -24, fingerEvents: 25, momentumEvents: 45)
            try? await Task.sleep(for: .milliseconds(1200))
        }
        Self.expectCenterOnTopThroughout(frames, label: "swipe")
    }

    /// 連按方向鍵（H-09）：VM 直接改 `centerID`，不帶動畫
    @Test("連按方向鍵途中每一幀，畫面正中那張都在最上層")
    func centerCardStaysOnTopWhileStepping() async throws {
        let session = StackSession.open(itemCount: 20, initialCenter: nil)
        defer { session.close() }
        _ = try #require(await session.settledFrame(), "起始狀態未穩定")

        let frames = await session.sampling {
            for step in 1...8 {
                session.center.value = step
                try? await Task.sleep(for: .milliseconds(60))
            }
            try? await Task.sleep(for: .milliseconds(1000))
        }
        Self.expectCenterOnTopThroughout(frames, label: "step")
    }

    /// 容許：每次換人時最多落後 1 幀（120Hz 下 ≈8ms，肉眼不可辨）
    private static func expectCenterOnTopThroughout(_ sampled: [StackFrame], label: String) {
        let frames = sampled.filter { $0.cards.count >= 3 }
        let verdicts = frames.map(\.centerIsOnTop)
        let violations = verdicts.filter { !$0 }.count
        let longestRun = verdicts.reduce(into: (current: 0, longest: 0)) { acc, ok in
            acc.current = ok ? 0 : acc.current + 1
            acc.longest = max(acc.longest, acc.current)
        }.longest
        // 捲過幾個卡位：讀 NSScrollView 的捲動原點（相鄰卡距＝0.58 itemWidth）
        let stride = stackItemWidth * 0.58
        let scrolledCards: CGFloat = {
            guard let first = frames.first?.scrollX, let last = frames.last?.scrollX else { return 0 }
            return abs(last - first) / stride
        }()
        let summary = "frames=\(frames.count) violations=\(violations) longestRun=\(longestRun) "
            + "scrolledCards=\(String(format: "%.1f", scrolledCards))"
        print("STACK-\(label)  \(summary)")
        for (i, frame) in frames.enumerated() where !frame.centerIsOnTop {
            print("STACK-\(label)-VIOLATION #\(i)  \(frame.report)")
        }

        #expect(frames.count >= 30, "取樣幀數過少，displayLink 可能沒跑。\(summary)")
        #expect(scrolledCards >= 4, "條帶沒有真的捲動（捲過的卡位過少）。\(summary)")
        #expect(longestRun <= 1, "途中正中那張連續 \(longestRun) 幀被鄰張壓住。\(summary)")
        #expect(frames.last?.centerIsOnTop == true, "結束時正中那張不在最上層。\(summary)")
    }
}

// MARK: - 佈景

@MainActor
@Observable
private final class StackCenter {
    var value: Int?
    init(_ value: Int?) { self.value = value }

    func binding() -> Binding<Int?> {
        Binding(
            get: { MainActor.assumeIsolated { self.value } },
            set: { new in MainActor.assumeIsolated { self.value = new } }
        )
    }
}

/// 與產品同構的卡片：`CoverFlowItem`（含 `.drawingGroup()`），每張一個不同純色
@MainActor
private enum StackArt {
    static func images(count: Int) -> [NSImage] {
        (0..<count).map { index in
            let side = Int(stackItemWidth)
            let color = NSColor(calibratedHue: CGFloat(index) / CGFloat(count),
                                saturation: 0.85, brightness: 0.95, alpha: 1)
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            return NSImage(cgImage: context.makeImage()!, size: NSSize(width: side, height: side))
        }
    }
}

private struct StackHarness: View {
    let center: StackCenter
    let cards: [StackCard]
    let images: [NSImage]

    var body: some View {
        CoverFlowStrip(items: cards, itemWidth: stackItemWidth, centerID: center.binding()) { card in
            CoverFlowItem(artwork: images[card.id], size: stackItemWidth)
        }
        .frame(width: stackViewSize.width, height: stackViewSize.height)
        .background(Color.black)
    }
}

@MainActor
private struct StackSession {
    let window: NSWindow
    let center: StackCenter

    static func open(itemCount: Int, initialCenter: Int?) -> StackSession {
        let center = StackCenter(initialCenter)
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: CGRect(x: screen.midX - stackViewSize.width / 2,
                                y: screen.midY - stackViewSize.height / 2,
                                width: stackViewSize.width, height: stackViewSize.height),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        // displayLink 在視窗不上屏時不回呼；不 activate、不搶焦點
        window.level = .floating
        window.contentView = NSHostingView(rootView: StackHarness(
            center: center,
            cards: (0..<itemCount).map(StackCard.init),
            images: StackArt.images(count: itemCount)
        ))
        window.makeKeyAndOrderFront(nil)
        return StackSession(window: window, center: center)
    }

    func close() { window.orderOut(nil) }

    /// 在 `body` 執行期間逐幀（displayLink）讀層樹
    func sampling(_ body: () async -> Void) async -> [StackFrame] {
        let sampler = StackSampler(window: window)
        sampler.start()
        await body()
        sampler.stop()
        return sampler.frames
    }

    /// 連兩次讀到相同的層樹簽名才算落定（睡固定秒數在機器忙時會讀到中間態）
    func settledFrame(timeout: TimeInterval = 10) async -> StackFrame? {
        var previous: StackFrame?
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            let current = StackReader.read(window)
            if let current, let previous, current.cards.count >= 3, current.signature == previous.signature {
                return current
            }
            previous = current
        }
        return nil
    }
}

// MARK: - 讀層樹

private struct StackFrame {
    /// 佈局 midX（contentView 層座標）與在父層 `sublayers` 中的次序（大＝在上）
    let cards: [(midX: CGFloat, order: Int)]
    let viewportMidX: CGFloat
    /// NSScrollView 的捲動原點 x（只用來確認條帶真的捲動了）
    var scrollX: CGFloat?

    private var byPosition: [(midX: CGFloat, order: Int)] { cards.sorted { $0.midX < $1.midX } }

    private var centerPosition: Int {
        let sorted = byPosition
        return sorted.indices.min {
            abs(sorted[$0].midX - viewportMidX) < abs(sorted[$1].midX - viewportMidX)
        } ?? 0
    }

    /// 正中那張的次序高於左右緊鄰者（首尾只比存在的一側）
    var centerIsOnTop: Bool {
        let sorted = byPosition
        let g = centerPosition
        let neighbours = [g - 1, g + 1].filter(sorted.indices.contains)
        return neighbours.allSatisfy { sorted[$0].order < sorted[g].order }
    }

    var signature: String {
        byPosition.map { "\(Int($0.midX.rounded())):\($0.order)" }.joined(separator: ",")
    }

    var report: String {
        let sorted = byPosition
        let g = centerPosition
        return "vpMidX=\(Int(viewportMidX)) " + sorted.enumerated().map { i, card in
            (i == g ? "[G]" : "") + "x=\(Int(card.midX.rounded()))/z\(card.order)"
        }.joined(separator: " ")
    }
}

@MainActor
private enum StackReader {
    static func read(_ window: NSWindow) -> StackFrame? {
        guard let root = window.contentView?.layer else { return nil }
        var all: [CALayer] = []
        collect(root, depth: 0, into: &all)
        let candidates = all.filter { abs($0.bounds.width - stackItemWidth) < 0.5 && $0.bounds.height > 100 }
        let refs = Set(candidates.map(ObjectIdentifier.init))
        // 卡層＝候選中最外層者（product 卡每張 3 層，只取帶變換的那層）
        let cardLayers = candidates.filter { layer in
            // 看不見的層蓋不住任何東西
            guard !layer.isHidden, (layer.presentation()?.opacity ?? layer.opacity) > 0.01 else { return false }
            var ancestor = layer.superlayer
            while let a = ancestor {
                if refs.contains(ObjectIdentifier(a)) { return false }
                ancestor = a.superlayer
            }
            return true
        }
        let parents = Set(cardLayers.compactMap { $0.superlayer.map(ObjectIdentifier.init) })
        guard parents.count == 1, let siblings = cardLayers.first?.superlayer?.sublayers else { return nil }
        let cards = cardLayers.compactMap { layer -> (midX: CGFloat, order: Int)? in
            guard let order = siblings.firstIndex(where: { $0 === layer }) else { return nil }
            return (layoutMidX(layer, in: root), order)
        }
        var frame = StackFrame(cards: cards, viewportMidX: root.bounds.midX)
        frame.scrollX = window.contentView.flatMap(scrollView(in:))?.contentView.bounds.origin.x
        return frame
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        return view.subviews.lazy.compactMap(scrollView(in:)).first
    }

    private static func collect(_ layer: CALayer, depth: Int, into out: inout [CALayer]) {
        guard depth < 40 else { return }
        out.append(layer)
        for sub in layer.sublayers ?? [] { collect(sub, depth: depth + 1, into: &out) }
    }

    /// 卡層 position／anchor 皆為 (0,0)，平移烘進 transform。旋轉軸那條豎邊 z＝0 → 齊次 w＝1、
    /// 不受透視影響；其長度＝scale×h（scale 以卡中心為錨）→ 佈局 midX＝軸邊 x＋scale×(w/2 − 軸 x)。
    private static func layoutMidX(_ layer: CALayer, in root: CALayer) -> CGFloat {
        let t = layer.transform
        let b = layer.bounds
        let yMid = b.height / 2
        let wLeading = yMid * t.m24 + t.m44
        let wTrailing = b.width * t.m14 + yMid * t.m24 + t.m44
        let axisX: CGFloat = abs(wLeading - 1) <= abs(wTrailing - 1) ? 0 : b.width
        let top = root.convert(CGPoint(x: b.minX + axisX, y: b.minY), from: layer)
        let bottom = root.convert(CGPoint(x: b.minX + axisX, y: b.maxY), from: layer)
        let scale = abs(bottom.y - top.y) / b.height
        return (top.x + bottom.x) / 2 + scale * (b.width / 2 - axisX)
    }
}

/// 合成觸控板水平捲動事件，直接送進測試視窗（in-process，不需輔助使用權限、不動使用者的游標）
@MainActor
private enum StackGesture {
    private static let phaseBegan: Int64 = 1      // kCGScrollPhaseBegan
    private static let phaseChanged: Int64 = 2    // kCGScrollPhaseChanged
    private static let phaseEnded: Int64 = 4      // kCGScrollPhaseEnded
    private static let momentumBegin: Int64 = 1   // kCGMomentumScrollPhaseBegin
    private static let momentumContinue: Int64 = 2
    private static let momentumEnd: Int64 = 3

    /// 手指拖動 `fingerEvents` 次、每次 `fingerDeltaX`pt，放開後慣性 `momentumEvents` 次（逐次衰減）
    static func swipe(_ window: NSWindow, fingerDeltaX: CGFloat, fingerEvents: Int, momentumEvents: Int) async {
        guard let content = window.contentView else { return }
        let inWindow = content.convert(CGPoint(x: content.bounds.midX, y: content.bounds.midY), to: nil)
        let onScreen = window.convertPoint(toScreen: inWindow)
        // CGEvent 用「主螢幕左上角為原點、y 向下」的全域座標
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let location = CGPoint(x: onScreen.x, y: primaryHeight - onScreen.y)

        func send(_ dx: CGFloat, phase: Int64, momentum: Int64) async {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                   wheel1: 0, wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
            cg.location = location
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
            cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
                                    value: Int64(window.windowNumber))
            if let event = NSEvent(cgEvent: cg) { window.sendEvent(event) }
            try? await Task.sleep(for: .milliseconds(8))
        }

        await send(0, phase: phaseBegan, momentum: 0)
        for _ in 0..<fingerEvents { await send(fingerDeltaX, phase: phaseChanged, momentum: 0) }
        await send(0, phase: phaseEnded, momentum: 0)
        var velocity = fingerDeltaX
        await send(velocity, phase: 0, momentum: momentumBegin)
        for _ in 0..<momentumEvents {
            velocity *= 0.93
            await send(velocity, phase: 0, momentum: momentumContinue)
        }
        await send(0, phase: 0, momentum: momentumEnd)
    }
}

/// 每個 displayLink 週期讀一次層樹（model 層；Z1 實測 model＝presentation，272 樣 0 差）
@MainActor
private final class StackSampler: NSObject {
    private weak var window: NSWindow?
    private var link: CADisplayLink?
    private(set) var frames: [StackFrame] = []

    init(window: NSWindow) { self.window = window }

    func start() {
        guard let view = window?.contentView else { return }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let window, let frame = StackReader.read(window) else { return }
        frames.append(frame)
    }
}
