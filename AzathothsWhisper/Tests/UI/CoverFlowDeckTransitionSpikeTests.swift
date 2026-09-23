import AppKit
import SwiftUI
import Testing

@testable import AzathothsWhisper

// S5（docs/plans/2026-09-23-coverflow-queue-drawer.md §8）：牌組轉場後，畫面正中是不是目標那張。
//
// 量測碼，預設關閉：只在 `TEST_RUNNER_AZW_SPIKE_S5=1` 時執行，結果印成 `S5 …` 行寫進計劃 §13，
// 定出 D6 的居中方式後改寫為正式測試（Q4）或刪除。
//
// 卡片身分由捲動原點換算：LazyHStack 等距排列，正中卡的索引＝(originX − 起點原點) ÷ 卡距。
// 起點原點在「第 0 張置中」時量一次（校準），不依賴 `centerID`（它與畫面可能不同步）。

private let spikeItemWidth: CGFloat = 260
private let spikeViewSize = CGSize(width: 1192, height: 620)
private let spikeStride = spikeItemWidth * 0.58     // itemWidth + spacing（−0.42 itemWidth）

private struct SpikeCard: Identifiable, Equatable { let id: Int }

@MainActor
@Observable
private final class SpikeDeck {
    var cards: [SpikeCard] = []
    var center: Int?
    /// scrollPosition binding 的每次回寫（含程式化居中途中的中間值）
    @ObservationIgnored var bindingWrites: [Int?] = []
    /// 每張已具現的卡自己回報的佈局 midX（視窗座標）；被動觀測，不影響具現（不同於 AX）
    @ObservationIgnored var midX: [Int: CGFloat] = [:]

    /// 畫面正中那張（只看目前牌組內、已具現的卡）
    func centeredID(viewportMidX: CGFloat) -> Int? {
        let live = Set(cards.map(\.id))
        return midX.filter { live.contains($0.key) }.min { abs($0.value - viewportMidX) < abs($1.value - viewportMidX) }?.key
    }

    func binding() -> Binding<Int?> {
        Binding(
            get: { MainActor.assumeIsolated { self.center } },
            set: { new in MainActor.assumeIsolated {
                self.bindingWrites.append(new)
                self.center = new
            } }
        )
    }
}

@MainActor
private enum SpikeArt {
    private static var cache: [Int: NSImage] = [:]

    static func image(for id: Int) -> NSImage {
        if let cached = cache[id] { return cached }
        let side = Int(spikeItemWidth)
        let color = NSColor(calibratedHue: CGFloat(abs(id) % 23) / 23, saturation: 0.85, brightness: 0.95, alpha: 1)
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = NSImage(cgImage: context.makeImage()!, size: NSSize(width: side, height: side))
        cache[id] = image
        return image
    }
}

private struct SpikeHarness: View {
    let deck: SpikeDeck

    var body: some View {
        CoverFlowStrip(items: deck.cards, itemWidth: spikeItemWidth, centerID: deck.binding()) { card in
            CoverFlowItem(artwork: SpikeArt.image(for: card.id), size: spikeItemWidth)
                .onGeometryChange(for: CGFloat.self) { proxy in proxy.frame(in: .global).midX } action: { x in
                    deck.midX[card.id] = x
                }
                .onDisappear { deck.midX[card.id] = nil }
        }
        .frame(width: spikeViewSize.width, height: spikeViewSize.height)
        .background(Color.black)
    }
}

@MainActor
private struct SpikeSession {
    let window: NSWindow
    let deck: SpikeDeck
    var originAtFirst: CGFloat = 0

    static func open() -> SpikeSession {
        let deck = SpikeDeck()
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: CGRect(x: screen.midX - spikeViewSize.width / 2, y: screen.midY - spikeViewSize.height / 2,
                                width: spikeViewSize.width, height: spikeViewSize.height),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: SpikeHarness(deck: deck))
        window.makeKeyAndOrderFront(nil)
        return SpikeSession(window: window, deck: deck)
    }

    func close() { window.orderOut(nil) }

    /// 連兩次層樹簽名相同才算落定
    func settled(timeout: TimeInterval = 10) async -> StackFrame? {
        var previous: StackFrame?
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            let current = StackReader.read(window, itemWidth: spikeItemWidth)
            if let current, let previous, current.cards.count >= 2,
               current.signature == previous.signature, current.scrollX == previous.scrollX {
                return current
            }
            previous = current
        }
        return nil
    }

    /// 以捲動原點換算畫面正中那張在 `cards` 中的索引
    func centeredIndex(_ frame: StackFrame) -> Int? {
        guard let x = frame.scrollX else { return nil }
        return Int(((x - originAtFirst) / spikeStride).rounded())
    }
}

/// 轉場做法
enum S5Method: String, CaseIterable, Sendable {
    /// 同一次更新內換牌＋設中心
    case direct
    /// 先換牌（中心保持舊值），下一個 runloop 再設中心
    case twoPhase
    /// 同一次更新內換牌，中心用 withAnimation 設
    case animated
}

@Suite("S5 牌組轉場（spike）", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["AZW_SPIKE_S5"] == "1"))
@MainActor
struct CoverFlowDeckTransitionSpikeTests {
    private static let window = 10      // 左右各 K 張

    private static func deck(centeredOn id: Int) -> [SpikeCard] {
        ((id - window)...(id + window)).map(SpikeCard.init)
    }

    private static func apply(_ session: SpikeSession, cards: [SpikeCard], center: Int, method: S5Method) async {
        switch method {
        case .direct:
            session.deck.cards = cards
            session.deck.center = center
        case .twoPhase:
            session.deck.cards = cards
            // 等目標卡已具現並回報位置（最多 500ms），再設中心
            for _ in 0..<30 where session.deck.midX[center] == nil {
                try? await Task.sleep(for: .milliseconds(16))
            }
            session.deck.center = center
        case .animated:
            session.deck.cards = cards
            withAnimation(.easeInOut(duration: 0.35)) { session.deck.center = center }
        }
    }

    /// 起點：以 [0…20] 建牌、第 0 張置中量原點，再移到正中（id 10）
    private static func prepared() async throws -> SpikeSession {
        var session = SpikeSession.open()
        session.deck.cards = (0...20).map(SpikeCard.init)
        session.deck.center = 0
        let first = try #require(await session.settled(), "校準：層樹未穩定")
        session.originAtFirst = try #require(first.scrollX, "校準：讀不到捲動原點")
        session.deck.center = 10
        _ = try #require(await session.settled(), "起點未穩定")
        return session
    }

    @Test("換歌：窗口右移一格（最左掉一張、最右補一張），中心移到下一首", arguments: S5Method.allCases)
    func advanceByOne(method: S5Method) async throws {
        let session = try await Self.prepared()
        defer { session.close() }
        var hits = 0, results: [String] = []
        for step in 1...6 {
            let target = 10 + step
            session.deck.bindingWrites = []
            await Self.apply(session, cards: Self.deck(centeredOn: target), center: target, method: method)
            let frame = try #require(await session.settled(), "第 \(step) 次未穩定")
            let shownID = session.deck.centeredID(viewportMidX: frame.viewportMidX)
            let byScroll = session.centeredIndex(frame).flatMap { session.deck.cards.indices.contains($0) ? session.deck.cards[$0].id : nil }
            if shownID == target { hits += 1 }
            let stray = session.deck.bindingWrites.compactMap { $0 }.filter { $0 != target }
            results.append("\(step):shown=\(shownID.map(String.init) ?? "nil")(scroll=\(byScroll.map(String.init) ?? "nil"))/want=\(target) writes=\(session.deck.bindingWrites.count) stray=\(stray)")
        }
        print("S5 advance[\(method.rawValue)] hits=\(hits)/6 " + results.joined(separator: " "))
    }

    @Test("清單重寫：整副牌換成新身分，中心設在第 K 張", arguments: S5Method.allCases)
    func rebuild(method: S5Method) async throws {
        let session = try await Self.prepared()
        defer { session.close() }
        var hits = 0, results: [String] = []
        for round in 1...5 {
            let target = 1000 * round + 10
            session.deck.bindingWrites = []
            await Self.apply(session, cards: Self.deck(centeredOn: target), center: target, method: method)
            let frame = try #require(await session.settled(), "第 \(round) 次未穩定")
            let shownID = session.deck.centeredID(viewportMidX: frame.viewportMidX)
            let byScroll = session.centeredIndex(frame).flatMap { session.deck.cards.indices.contains($0) ? session.deck.cards[$0].id : nil }
            if shownID == target { hits += 1 }
            let stray = session.deck.bindingWrites.compactMap { $0 }.filter { $0 != target }
            results.append("\(round):shown=\(shownID.map(String.init) ?? "nil")(scroll=\(byScroll.map(String.init) ?? "nil"))/want=\(target) writes=\(session.deck.bindingWrites.count) stray=\(stray.count)")
        }
        print("S5 rebuild[\(method.rawValue)] hits=\(hits)/5 " + results.joined(separator: " "))
    }

    @Test("首次：空牌掛載後才第一次給牌與中心", arguments: S5Method.allCases)
    func firstDeckAfterEmptyMount(method: S5Method) async throws {
        var hits = 0, results: [String] = []
        for round in 1...5 {
            var session = SpikeSession.open()
            defer { session.close() }
            try? await Task.sleep(for: .milliseconds(300))      // 空牌狀態先渲染
            // 校準原點：同尺寸的牌、第 0 張置中
            session.deck.cards = (0...20).map(SpikeCard.init)
            session.deck.center = 0
            let first = try #require(await session.settled(), "校準未穩定")
            session.originAtFirst = try #require(first.scrollX)
            session.deck.cards = []
            session.deck.center = nil
            try? await Task.sleep(for: .milliseconds(300))
            let target = 500 + round
            await Self.apply(session, cards: Self.deck(centeredOn: target), center: target, method: method)
            let frame = try #require(await session.settled(), "第 \(round) 次未穩定")
            let shownID = session.deck.centeredID(viewportMidX: frame.viewportMidX)
            let byScroll = session.centeredIndex(frame).flatMap { session.deck.cards.indices.contains($0) ? session.deck.cards[$0].id : nil }
            if shownID == target { hits += 1 }
            results.append("\(round):shown=\(shownID.map(String.init) ?? "nil")(scroll=\(byScroll.map(String.init) ?? "nil"))/want=\(target)")
        }
        print("S5 first[\(method.rawValue)] hits=\(hits)/5 " + results.joined(separator: " "))
    }
}
