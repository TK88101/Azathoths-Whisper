import AppKit
import SwiftUI
import Testing

@testable import AzathothsWhisper

// 換歌平移的幾何（計劃 docs/plans/2026-09-26-coverflow-follow-playback-slide.md §3.4、§4）。正式測試、進全量。
//
// 開真視窗量 production 的 `CoverFlowView`＋`CoverFlowViewModel`（前六案）與 `CoverFlowStrip`（生命週期兩案）。
// 平移不動捲動位置，位移量由卡層位置還原：最靠近視口中點的卡層之帶號偏移（卡格相位）逐幀累加，
// 跨半個卡距時折返。每一步都斷言——S9 量測碼只印統計，不是回歸證據。

private let viewSize = CGSize(width: 1192, height: 620)

@MainActor
private enum SlideProbe {
    static let stride = CoverFlowGeometry(itemWidth: CoverFlowView.itemWidth).slideOffset(slots: 1)
    static let frames = 50

    struct Sample {
        let phase: CGFloat
        let scrollX: CGFloat
        let isPlayingCardCentered: Bool
    }

    static func openWindow<Content: View>(_ content: Content) -> NSWindow {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: CGRect(x: screen.midX - viewSize.width / 2, y: screen.midY - viewSize.height / 2,
                                width: viewSize.width, height: viewSize.height),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: content)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    /// 連兩次層樹簽名與捲動原點相同才算落定
    static func settled(_ window: NSWindow, timeout: TimeInterval = 10) async -> StackFrame? {
        var previous: StackFrame?
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            let current = StackReader.read(window)
            if let current, let previous, current.cards.count >= 2,
               current.signature == previous.signature, current.scrollX == previous.scrollX {
                return current
            }
            previous = current
        }
        return nil
    }

    static func phase(_ frame: StackFrame?) -> CGFloat {
        frame.flatMap { f in f.cards.map { $0.midX - f.viewportMidX }.min { abs($0) < abs($1) } } ?? .infinity
    }

    /// 逐幀取樣（16ms）。`isCentered` 由呼叫端提供：正式 View 讀 VM，條帶測試自己記
    static func sample(_ window: NSWindow, frames: Int = frames, isCentered: () -> Bool = { false }) async -> [Sample] {
        var samples: [Sample] = []
        for _ in 0..<frames {
            try? await Task.sleep(for: .milliseconds(16))
            guard let frame = StackReader.read(window), let scrollX = frame.scrollX else { continue }
            samples.append(Sample(phase: phase(frame), scrollX: scrollX, isPlayingCardCentered: isCentered()))
        }
        return samples
    }

    /// 由卡格相位還原累計位移（起點相位 0＝舊當前卡在正中）
    static func travel(_ samples: [Sample]) -> [CGFloat] {
        var previous: CGFloat = 0, total: CGFloat = 0
        return samples.map { sample in
            var delta = sample.phase - previous
            if delta > stride / 2 { delta -= stride }
            if delta < -stride / 2 { delta += stride }
            total += delta
            previous = sample.phase
            return total
        }
    }

    static func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

private struct SlideHarness: View {
    let model: CoverFlowViewModel
    let prefersReducedMotion: Bool
    @FocusState private var focused: Bool

    var body: some View {
        CoverFlowView(model: model, isInteractive: false, focus: $focused, upcoming: .available,
                      prefersReducedMotion: prefersReducedMotion, onTapPlayingCard: {})
            .frame(width: viewSize.width, height: viewSize.height)
    }
}

private struct StripCard: Identifiable, Equatable { let id: Int }

@MainActor
@Observable
private final class StripDriver {
    var cards: [StripCard] = []
    var center: Int?
    var slide: CoverFlowSlideRequest?
    @ObservationIgnored var settled: [Int] = []
}

private struct StripHarness: View {
    let driver: StripDriver

    var body: some View {
        CoverFlowStrip(
            items: driver.cards,
            itemWidth: CoverFlowView.itemWidth,
            centerID: Binding(get: { driver.center }, set: { driver.center = $0 }),
            slide: driver.slide,
            onSlideSettled: { driver.settled.append($0) }
        ) { _ in
            CoverFlowItem(artwork: nil, size: CoverFlowView.itemWidth)
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .background(Color.black)
    }
}

enum SlideDirection: String, CaseIterable, Sendable {
    case next
    case previous
}

@Suite("Cover Flow 換歌平移（幾何）", .serialized)
@MainActor
struct CoverFlowSlideGeometryTests {
    private static let window = LyricsFlowModel.window

    private static func queueCard(_ n: Int, _ side: DeckCard.Side) -> DeckCard {
        DeckCard(id: "q:0:\(n)", persistentID: "P\(n)", side: side)
    }

    /// 左側固定十張履歴卡；換歌不動它們（履歴還沒追上）
    private static let history = (1...window).map { DeckCard(id: "h:H\($0)#0", persistentID: "H\($0)", side: .played) }

    /// 佇列模式：左＝履歴、中＝第 n 首、右＝其後十首
    private static func queueDeck(playing n: Int) -> DeckSnapshot {
        let right = ((n + 1)...(n + window)).map { queueCard($0, .upcoming) }
        return DeckSnapshot(cards: history + [queueCard(n, .current)] + right, currentCardID: "q:0:\(n)", upcoming: .available)
    }

    /// 往回跳當下：中心是新身分的觀察卡，右側清空
    private static func fallbackDeck(playing n: Int) -> DeckSnapshot {
        let current = DeckCard(id: "o:P\(n)#0", persistentID: "P\(n)", side: .current)
        return DeckSnapshot(cards: history + [current], currentCardID: current.id, upcoming: .pending)
    }

    private struct Stage {
        let model: CoverFlowViewModel
        let window: NSWindow
    }

    /// 先空牌掛載、渲染後才首次給牌（production 的順序；掛載當下就帶牌組會走初值路徑、停在第一張）
    private static func stage(playing n: Int, prefersReducedMotion: Bool = false) async throws -> Stage {
        let model = CoverFlowViewModel(artwork: StubArtworkProvider(), clock: GatedPollClock())
        let window = SlideProbe.openWindow(SlideHarness(model: model, prefersReducedMotion: prefersReducedMotion))
        try? await Task.sleep(for: .milliseconds(300))
        model.apply(queueDeck(playing: n), isRealChange: true)
        _ = try #require(await SlideProbe.settled(window), "起點未穩定")
        try #require(await SlideProbe.waitUntil { model.isPlayingCardCentered }, "條帶沒有回報播放卡在正中")
        #expect(model.prefersReducedMotion == prefersReducedMotion, "View 應把減少動態效果同步給 VM")
        return Stage(model: model, window: window)
    }

    /// 一次換歌之後逐項斷言：有平移、方向對、捲動位置沒動、落定對齊、暫留卡已收掉
    private static func expectSlide(_ stage: Stage, sign: CGFloat, before: CGFloat, step: Int) async {
        let model = stage.model
        let samples = await SlideProbe.sample(stage.window) { model.isPlayingCardCentered }
        let travel = SlideProbe.travel(samples)
        let total = travel.last ?? 0
        let remaining = travel.map { abs($0 - total) }

        #expect(samples.count >= SlideProbe.frames - 5, "第 \(step) 步取樣不足：\(samples.count)")
        #expect(abs(total - sign * SlideProbe.stride) < 2, "第 \(step) 步總位移 \(total)，應為 \(sign * SlideProbe.stride)")
        #expect(remaining.filter { $0 > 4 && $0 < SlideProbe.stride - 4 }.count >= 3, "第 \(step) 步途中不足 3 幀：\(travel.prefix(12))")
        #expect(zip(remaining, remaining.dropFirst()).allSatisfy { $1 <= $0 + 0.5 }, "第 \(step) 步不單調：\(travel.prefix(12))")
        #expect(samples.allSatisfy { abs($0.scrollX - before) < 0.5 }, "第 \(step) 步捲動位置動了")
        #expect(samples.first?.isPlayingCardCentered == false, "第 \(step) 步起滑時目標卡不該已算在正中")

        let landed = await SlideProbe.settled(stage.window)
        #expect(abs(SlideProbe.phase(landed)) < 1, "第 \(step) 步落定未對齊")
        #expect(abs((landed?.scrollX ?? .infinity) - before) < 0.5)
        #expect(await SlideProbe.waitUntil { model.slide == nil }, "第 \(step) 步完成回呼沒有送到 VM")
        #expect(model.cards == model.deck.cards, "第 \(step) 步暫留卡未收掉")
        #expect(await SlideProbe.waitUntil { model.isPlayingCardCentered }, "第 \(step) 步落定後目標卡應在正中")
    }

    @Test("下一首／上一首各三次：每一步都平移一個卡距、捲動位置不動", arguments: SlideDirection.allCases)
    func slidesOneCardPerChange(direction: SlideDirection) async throws {
        var playing = 100
        let stage = try await Self.stage(playing: playing)
        defer { stage.window.orderOut(nil) }
        let before = try #require(StackReader.read(stage.window)?.scrollX)
        var old = Self.queueCard(playing, .current)

        for step in 1...3 {
            let next: DeckSnapshot
            let hint: SlideHint?
            switch direction {
            case .next:
                playing += 1
                next = Self.queueDeck(playing: playing)
                hint = nil
            case .previous:
                playing -= 1
                next = Self.fallbackDeck(playing: playing)
                hint = SlideHint(oldCardID: old.id, oldPersistentID: old.persistentID,
                                 targetPersistentID: "P\(playing)", direction: .previous)
            }
            stage.model.apply(next, isRealChange: true, slideHint: hint)
            try #require(stage.model.slide != nil, "第 \(step) 步沒有發出平移指令")
            // 下一首：內容往左走（位移為負）；上一首反向
            await Self.expectSlide(stage, sign: direction == .next ? -1 : 1, before: before, step: step)
            old = try #require(next.cards.first { $0.id == next.currentCardID })
        }
    }

    @Test func reducedMotionSwitchesWithoutMoving() async throws {
        let stage = try await Self.stage(playing: 100, prefersReducedMotion: true)
        defer { stage.window.orderOut(nil) }

        stage.model.apply(Self.queueDeck(playing: 101), isRealChange: true)

        #expect(stage.model.slide == nil)
        let samples = await SlideProbe.sample(stage.window, frames: 20)
        #expect(samples.allSatisfy { abs($0.phase) < 1 }, "不該有位移：\(samples.map(\.phase).prefix(8))")
        #expect(stage.model.centerID == "q:0:101")
    }

    /// 履歴在動畫途中追上：暫留卡原位留著，照常滑完
    @Test func historyCatchingUpMidSlideDoesNotInterruptIt() async throws {
        let stage = try await Self.stage(playing: 100)
        defer { stage.window.orderOut(nil) }
        let before = try #require(StackReader.read(stage.window)?.scrollX)

        stage.model.apply(Self.queueDeck(playing: 101), isRealChange: true)
        try #require(stage.model.slide != nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            let caughtUp = Self.queueDeck(playing: 101)
            let left = Array(Self.history.dropFirst()) + [DeckCard(id: "h:P100#0", persistentID: "P100", side: .played)]
            stage.model.apply(DeckSnapshot(cards: left + Array(caughtUp.cards.dropFirst(Self.window)),
                                           currentCardID: caughtUp.currentCardID, upcoming: .available), isRealChange: false)
        }

        await Self.expectSlide(stage, sign: -1, before: before, step: 1)
        #expect(stage.model.cards.contains { $0.id == "h:P100#0" })
    }

    /// 過渡中又換歌：位移當場歸零、直接定位到最後那首
    @Test func aSecondChangeMidSlideLandsDirectly() async throws {
        let stage = try await Self.stage(playing: 100)
        defer { stage.window.orderOut(nil) }

        stage.model.apply(Self.queueDeck(playing: 101), isRealChange: true)
        try #require(stage.model.slide != nil)
        try? await Task.sleep(for: .milliseconds(100))
        stage.model.apply(Self.queueDeck(playing: 102), isRealChange: true)

        #expect(stage.model.slide == nil)
        let landed = await SlideProbe.settled(stage.window)
        #expect(abs(SlideProbe.phase(landed)) < 1)
        #expect(stage.model.centerID == "q:0:102")
        #expect(await SlideProbe.waitUntil { stage.model.isPlayingCardCentered })
    }

    // MARK: 條帶的生命週期（§3.4：指令只在一個地方被消費）

    /// 條帶出現時就帶著還沒開始的指令（被重建）：不滑、位移為 0、回報一次落定
    @Test func aStripMountedWithAPendingRequestSettlesAtOnce() async throws {
        let driver = StripDriver()
        driver.cards = (0...20).map(StripCard.init)
        driver.center = 10
        driver.slide = CoverFlowSlideRequest(generation: 7, slots: 1)
        let window = SlideProbe.openWindow(StripHarness(driver: driver))
        defer { window.orderOut(nil) }

        let landed = try #require(await SlideProbe.settled(window))

        #expect(driver.settled == [7])
        #expect(abs(SlideProbe.phase(landed)) < 1, "位移應為 0")
    }

    /// 動畫途中條帶被移出視窗再放回（沒被重建）：照常由動畫自己落定，只回報一次
    @Test func reappearingMidSlideDoesNotSettleEarly() async throws {
        let driver = StripDriver()
        let window = SlideProbe.openWindow(StripHarness(driver: driver))
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(300))
        driver.cards = (0...20).map(StripCard.init)
        driver.center = 10
        _ = try #require(await SlideProbe.settled(window))

        driver.cards = (1...21).map(StripCard.init)
        driver.center = 11
        driver.slide = CoverFlowSlideRequest(generation: 1, slots: 1)
        let first = await SlideProbe.sample(window, frames: 4)
        #expect(abs(SlideProbe.travel(first).last ?? 0) > 4, "正常起滑不該被初值補救切掉")
        let hosting = window.contentView
        window.contentView = nil
        window.contentView = hosting

        _ = await SlideProbe.settled(window)
        try? await Task.sleep(for: .milliseconds(Int(Theme.Motion.layerShiftDuration * 1000)))
        #expect(driver.settled == [1])
    }
}
