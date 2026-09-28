import AppKit
import SwiftUI
import Testing

@testable import AzathothsWhisper

// S9（docs/plans/2026-09-26-coverflow-follow-playback-slide.md §8.3）：條帶內兩段——量測本體
//
// 量測碼，預設關閉：只在 `TEST_RUNNER_AZW_SPIKE_S9=1` 時執行，結果印成 `S9 …` 行寫進該計劃 §8.3。
// 條帶／View 複本、矩陣列舉與記錄器在 `CoverFlowSlideSpikeS9Support.swift`。
// 縮小矩陣：`TEST_RUNNER_AZW_SPIKE_S9_ONLY=movingWindow,reader`（逗號分隔，全部命中才跑）；
// 步數：`TEST_RUNNER_AZW_SPIKE_S9_STEPS=3`（預設 20）。

// MARK: - 量測

/// 量測用的一張卡。`isObserved`＝觀察卡（`o:`），用來做出「同一首歌、不同卡 ID」
private struct S9Spec: Equatable {
    let n: Int
    var isObserved = false

    var id: String { isObserved ? "o:P\(n)#0" : "q:0:\(n)" }
}

/// 一次換歌：過渡牌組、目標卡、落定後要換上的正式牌組（nil＝過渡牌組即正式牌組）
private struct S9Plan {
    let staged: [S9Spec]
    let target: S9Spec
    let canonical: [S9Spec]?
}

@Suite("S9 條帶內兩段換歌平移（spike）", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["AZW_SPIKE_S9"] == "1"))
@MainActor
struct CoverFlowSlideSpikeS9Tests {
    /// 計劃 §7-1：0.62s，曲線同升降
    private static let slide = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.62)
    private static let halfWindow = 10
    private static let steps = Int(ProcessInfo.processInfo.environment["AZW_SPIKE_S9_STEPS"] ?? "") ?? 20
    private static let slideFrames = 50
    private static let swapFrames = 20

    // MARK: 牌組

    /// 以 `centre` 為中心的窗口；中心沿用 `centre` 的身分，其餘為佇列卡
    private static func window(around centre: S9Spec) -> [S9Spec] {
        ((centre.n - halfWindow)...(centre.n + halfWindow)).map { $0 == centre.n ? centre : S9Spec(n: $0) }
    }

    /// 只有左側與中心（右側為空：退回模式）
    private static func leftOnly(endingAt centre: S9Spec) -> [S9Spec] {
        ((centre.n - halfWindow)...centre.n).map { S9Spec(n: $0, isObserved: true) }
    }

    private static func initialDeck(_ testCase: S9Case, centre: S9Spec) -> [S9Spec] {
        if testCase.shape == .keptIndex, testCase.direction == .previous {
            // 往回走每步左側少一張：起點先多留 steps 張，走完仍有左側
            return ((centre.n - halfWindow - steps)...(centre.n + halfWindow)).map { S9Spec(n: $0) }
        }
        let isLeftOnly = (testCase.shape == .insertedTarget || testCase.shape == .flipInserted) && testCase.direction == .next
        return isLeftOnly ? leftOnly(endingAt: centre) : window(around: centre)
    }

    private static func plan(_ testCase: S9Case, display: [S9Spec], centre: S9Spec) -> S9Plan {
        let isNext = testCase.direction == .next
        let n = isNext ? centre.n + 1 : centre.n - 1
        switch testCase.shape {
        case .movingWindow:
            let target = S9Spec(n: n)
            return S9Plan(staged: window(around: target).map { $0.n == centre.n ? centre : $0 }, target: target, canonical: nil)
        case .heldWindow:
            let target = display.first { $0.n == n } ?? S9Spec(n: n)
            return S9Plan(staged: display, target: target, canonical: window(around: target))
        case .flipInserted:
            let target = S9Spec(n: n, isObserved: true)
            if isNext {
                return S9Plan(staged: leftOnly(endingAt: target), target: target, canonical: nil)
            }
            let left = ((n - halfWindow)...(n - 1)).map { S9Spec(n: $0) }
            return S9Plan(staged: left + [target, centre], target: target, canonical: nil)
        case .keptIndex:
            let target = display.first { $0.n == n } ?? S9Spec(n: n)
            // 最左那張不動、右端跟著新窗口：目標卡左邊的張數與過渡牌組相同
            let lowest = display.first?.n ?? (n - halfWindow)
            return S9Plan(staged: display, target: target, canonical: (lowest...(n + halfWindow)).map { S9Spec(n: $0) })
        case .direct, .flip:
            let target = S9Spec(n: n)
            return S9Plan(staged: window(around: target).map { $0.n == centre.n ? centre : $0 }, target: target, canonical: nil)
        case .insertedTarget:
            let target = S9Spec(n: n, isObserved: true)
            if isNext {
                return S9Plan(staged: display + [target], target: target, canonical: leftOnly(endingAt: target))
            }
            return S9Plan(staged: display.map { $0.n == n ? target : $0 }, target: target, canonical: window(around: target))
        }
    }

    /// - Parameters:
    ///   - playing: 新的正在播（決定各卡的左右）
    ///   - centredOn: VM 當下要居中的卡（過渡時＝舊中心）
    private static func deck(_ specs: [S9Spec], playing: Int, centredOn: S9Spec) -> DeckSnapshot {
        let cards = specs.map { spec in
            DeckCard(id: spec.id, persistentID: "P\(spec.n)",
                     side: spec.n < playing ? .played : (spec.n == playing ? .current : .upcoming))
        }
        return DeckSnapshot(cards: cards, currentCardID: centredOn.id, upcoming: .available)
    }

    // MARK: 讀取

    private static func settled(_ window: NSWindow, timeout: TimeInterval = 10) async -> StackFrame? {
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

    /// 條帶幾何判定在正中的卡，只算目前牌組內的（離開牌組的卡不會再回報，記錄會殘留）
    private static func centred(_ driver: S9Driver) -> Set<String> {
        driver.recorder.centredIDs.intersection(driver.model.cards.map(\.id))
    }

    /// 最靠近視口中點的卡層離中點多遠
    private static func nearestOffset(_ frame: StackFrame?) -> CGFloat {
        frame.flatMap { f in f.cards.map { abs($0.midX - f.viewportMidX) }.min() } ?? .infinity
    }

    /// 最靠近視口中點的卡層之帶號偏移（卡格相位）
    private static func signedNearestOffset(_ frame: StackFrame?) -> CGFloat {
        frame.flatMap { f in f.cards.map { $0.midX - f.viewportMidX }.min { abs($0) < abs($1) } } ?? 0
    }

    /// 最靠近視口中點的卡層繞 Y 軸轉了多少（|m14|×1000；0＝正面朝前）。只看卡層本身的變換，不看位置身分
    private static func nearestTilt(_ window: NSWindow) -> CGFloat? {
        guard let root = window.contentView?.layer else { return nil }
        var all: [CALayer] = []
        func collect(_ layer: CALayer, depth: Int) {
            guard depth < 40 else { return }
            all.append(layer)
            layer.sublayers?.forEach { collect($0, depth: depth + 1) }
        }
        collect(root, depth: 0)
        let candidates = all.filter { abs($0.bounds.width - s9ItemWidth) < 0.5 && $0.bounds.height > 100 }
        let refs = Set(candidates.map(ObjectIdentifier.init))
        let cards = candidates.filter { layer in
            guard !layer.isHidden, layer.opacity > 0.01 else { return false }
            var ancestor = layer.superlayer
            while let current = ancestor {
                if refs.contains(ObjectIdentifier(current)) { return false }
                ancestor = current.superlayer
            }
            return true
        }
        let midX = root.bounds.midX
        let nearest = cards.min { lhs, rhs in
            abs(root.convert(CGPoint(x: lhs.bounds.midX, y: lhs.bounds.midY), from: lhs).x - midX)
                < abs(root.convert(CGPoint(x: rhs.bounds.midX, y: rhs.bounds.midY), from: rhs).x - midX)
        }
        // SwiftUI 把 3D 旋轉烘成投影矩陣：傾斜反映在 m14（透視項），m13 恆為 0（冒煙實測）
        return nearest.map { abs($0.transform.m14) * 1000 }
    }

    /// 由卡格相位還原累計位移：相鄰兩幀的差折返到 ±半個卡距內再累加
    private static func unwrapped(_ phases: [CGFloat], from start: CGFloat) -> [CGFloat] {
        var previous = start, total: CGFloat = 0
        return phases.map { phase in
            var delta = phase - previous
            if delta > s9Stride / 2 { delta -= s9Stride }
            if delta < -s9Stride / 2 { delta += s9Stride }
            total += delta
            previous = phase
            return total
        }
    }

    private static func describe(_ events: [S9CentringEvent]) -> String {
        guard let first = events.first?.tick else { return "" }
        return events.map { "\($0.id)\($0.isCentred ? "+" : "-")@\($0.tick - first)" }.joined(separator: ",")
    }

    /// 每次畫面提交時「誰在正中」的序列（相鄰重複已合併）。`initial`＝這一段開始前在正中的卡
    private static func committedStates(_ events: [S9CentringEvent], initial: Set<String>, live: Set<String>) -> [Set<String>] {
        var state = initial.intersection(live)
        var states = [state]
        var index = 0
        while index < events.count {
            let tick = events[index].tick
            while index < events.count, events[index].tick == tick {
                if events[index].isCentred { state.insert(events[index].id) } else { state.remove(events[index].id) }
                index += 1
            }
            state.formIntersection(live)
            if states.last != state { states.append(state) }
        }
        return states
    }

    private static func describe(_ states: [Set<String>]) -> String {
        states.map { $0.isEmpty ? "∅" : $0.sorted().joined(separator: "&") }.joined(separator: "→")
    }

    /// 平移途中畫面提交的正中序列只能是 old → ∅ → target 的子序列，且以 target 結尾
    private static func isCleanSlide(_ states: [Set<String>], old: String, target: String) -> Bool {
        let allowed: [Set<String>] = [[old], [], [target]]
        var cursor = 0
        for state in states {
            guard let found = allowed[cursor...].firstIndex(of: state) else { return false }
            cursor = found
        }
        return states.last == [target]
    }

    // MARK: 量測

    @Test("條帶內兩段換歌：平移、落定、非目標回寫、換上正式牌組", arguments: S9Case.selected)
    func slide(_ testCase: S9Case) async throws {
        try #require(s9ItemWidth == CoverFlowView.itemWidth, "卡距常數與 production 不同源")
        let driver = S9Driver(model: CoverFlowViewModel(artwork: StubArtworkProvider()))
        let model = driver.model
        let recorder = driver.recorder
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: CGRect(x: screen.midX - s9ViewSize.width / 2, y: screen.midY - s9ViewSize.height / 2,
                                width: s9ViewSize.width, height: s9ViewSize.height),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: S9Harness(driver: driver, testCase: testCase, animation: Self.slide))
        window.makeKeyAndOrderFront(nil)
        recorder.startTicking()
        defer {
            recorder.stopTicking()
            window.orderOut(nil)
        }

        var centre = S9Spec(n: 100, isObserved: (testCase.shape == .insertedTarget || testCase.shape == .flipInserted)
            && testCase.direction == .next)
        var display = Self.initialDeck(testCase, centre: centre)
        // 先以空牌掛載並渲染，再首次給牌（production 的路徑）。掛載當下就帶牌組走的是 scrollPosition 的
        // 「初始值路徑」，畫面停在第一張（冒煙運行實測：原點 −466、正中＝最左那張；S8「第 1 步起點未穩」同因）
        try? await Task.sleep(for: .milliseconds(300))
        model.apply(Self.deck(display, playing: centre.n, centredOn: centre), isRealChange: true)
        _ = try #require(await Self.settled(window), "起點未穩定（讀不到卡層？）")
        let start = try #require(await Self.settled(window), "起點二次確認未穩定")
        let startOrigin = try #require(start.scrollX, "讀不到捲動原點")
        let startLine = String(format: "start origin=%.1f geo=%@", startOrigin, "\(Self.centred(driver).sorted())")
        try #require(Self.centred(driver) == [centre.id], "起點不在 VM 的中心卡上，量測無效：\(startLine)")
        // 第 0 張置中時的原點：之後每一步的預期原點＝它＋目標卡位次×卡距
        let originAtFirst = startOrigin - CGFloat(display.firstIndex(of: centre) ?? 0) * s9Stride
        func origin(of spec: S9Spec, in specs: [S9Spec]) -> CGFloat {
            originAtFirst + CGFloat(specs.firstIndex(of: spec) ?? 0) * s9Stride
        }

        var slid = 0, landed = 0, synced = 0, strayRuns = 0, cleanSlides = 0
        var swapLanded = 0, swapClean = 0, swaps = 0
        var completed = 0, completionDelays: [Double] = [], remainingAtCompletion: CGFloat = 0
        // 正中那張的傾斜：起滑第一幀、途中最大值、落定後
        var tiltAtStart: [CGFloat] = [], tiltPeak: [CGFloat] = [], tiltAtEnd: [CGFloat] = []
        var results: [String] = []
        for step in 1...Self.steps {
            let plan = Self.plan(testCase, display: display, centre: centre)
            let old = centre.id, target = plan.target.id
            recorder.rawWrites = []
            recorder.centringEvents = []
            let centredBefore = recorder.centredIDs

            if testCase.shape == .direct {
                model.apply(Self.deck(plan.staged, playing: plan.target.n, centredOn: plan.target), isRealChange: true)
            } else if testCase.shape.isFlip {
                // 同一次更新：直接換牌＋設中心（production 的換歌）＋平移指令
                model.apply(Self.deck(plan.staged, playing: plan.target.n, centredOn: plan.target), isRealChange: true)
                driver.slide = S9SlideRequest(generation: step, from: old, to: target)
            } else {
                // 同一次更新：過渡牌組（VM 中心仍為 old）＋平移指令。之後測試端不再碰條帶
                model.apply(Self.deck(plan.staged, playing: plan.target.n, centredOn: centre), isRealChange: false)
                driver.slide = S9SlideRequest(generation: step, from: old, to: target)
            }

            let startedAt = ContinuousClock.now
            var scrolls: [CGFloat] = []
            var phases: [CGFloat] = []
            var sampledAt: [ContinuousClock.Instant] = []
            var tilts: [CGFloat] = []
            for _ in 0..<Self.slideFrames {
                try? await Task.sleep(for: .milliseconds(16))
                if let tilt = Self.nearestTilt(window) { tilts.append(tilt) }
                let sample = StackReader.read(window)
                if let x = sample?.scrollX {
                    scrolls.append(x)
                    phases.append(Self.signedNearestOffset(sample))
                    sampledAt.append(.now)
                }
            }
            let frame = await Self.settled(window)
            let after = frame?.scrollX ?? scrolls.last ?? .nan
            // 平移＝軌跡由「距終點約一個卡距」逐幀單調收斂到終點，且 ≥3 幀落在兩者之間。
            // 內容位移不動捲動原點：改由卡格相位（逐幀累加、跨半個卡距時折返）還原位移量
            let distance: [CGFloat]
            if testCase.mechanism.isTranslation {
                let travelled = Self.unwrapped(phases, from: 0)
                let total = travelled.last ?? 0
                distance = abs(abs(total) - s9Stride) < 2 ? travelled.map { abs($0 - total) } : travelled.map { _ in 0 }
            } else {
                distance = scrolls.map { abs($0 - after) }
            }
            let inBetween = distance.filter { $0 > 4 && $0 < s9Stride - 4 }.count
            let monotonic = zip(distance, distance.dropFirst()).allSatisfy { $1 <= $0 + 0.5 }
            let didSlide = inBetween >= 3 && monotonic
            // 落定＝幾何正中只有目標卡、有卡層對齊視口中點、原點在目標卡的位次上
            let didLand = Self.centred(driver) == [target] && Self.nearestOffset(frame) < 1
                && abs(after - origin(of: plan.target, in: plan.staged)) < 2
            let didSync = model.centerID == target
            let writes = recorder.rawWrites
            let stray = writes.compactMap { $0 }.filter { $0 != old && $0 != target }
            // 畫面提交過的正中序列：不得出現「先閃到別張再回來」
            let live = Set(model.cards.map(\.id))
            let slideEvents = recorder.centringEvents
            let slideStates = Self.committedStates(slideEvents, initial: centredBefore, live: live)
            let centredOnce = Self.isCleanSlide(slideStates, old: old, target: target)
            // 完成回呼：離指令多久、當時離終點還有多遠（取回呼之後第一個取樣）
            if let completion = recorder.completions.last(where: { $0.generation == step }) {
                completed += 1
                let delay = completion.at - startedAt
                completionDelays.append(Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18)
                if let index = sampledAt.firstIndex(where: { $0 >= completion.at }) {
                    remainingAtCompletion = max(remainingAtCompletion, distance[index])
                }
            }
            if let first = tilts.first { tiltAtStart.append(first) }
            if let last = Self.nearestTilt(window) { tiltAtEnd.append(last) }
            tiltPeak.append(tilts.max() ?? 0)
            if didSlide { slid += 1 }
            if didLand { landed += 1 }
            if didSync { synced += 1 }
            if !stray.isEmpty { strayRuns += 1 }
            if centredOnce { cleanSlides += 1 }

            var notes: [String] = []
            if !didSlide || !didLand || !centredOnce || !stray.isEmpty || step == 1 {
                notes.append("slide=\(didSlide) land=\(didLand) mid=\(inBetween) mono=\(monotonic) vm=\(didSync) "
                    + "writes=\(writes.map { $0 ?? "nil" }) commits=[\(Self.describe(slideStates))] "
                    + "events=[\(Self.describe(slideEvents.filter { $0.isCentred || $0.id == old || $0.id == target }))] "
                    + "dx=" + (testCase.mechanism.isTranslation
                        ? Self.unwrapped(phases, from: 0).prefix(16).map { String(format: "%.0f", $0) }
                        : scrolls.prefix(16).map { String(format: "%.0f", $0 - after) }).joined(separator: ","))
            }

            if let canonical = plan.canonical {
                swaps += 1
                recorder.centringEvents = []
                model.apply(Self.deck(canonical, playing: plan.target.n, centredOn: plan.target), isRealChange: false)
                var crooked = 0, offTarget = 0
                for _ in 0..<Self.swapFrames {
                    try? await Task.sleep(for: .milliseconds(16))
                    if Self.nearestOffset(StackReader.read(window)) >= 1 { crooked += 1 }
                    if Self.centred(driver) != [target] { offTarget += 1 }
                }
                let swapped = await Self.settled(window)
                let didSwapLand = Self.centred(driver) == [target] && Self.nearestOffset(swapped) < 1
                    && abs((swapped?.scrollX ?? .nan) - origin(of: plan.target, in: canonical)) < 2
                    && model.centerID == target
                let swapEvents = recorder.centringEvents
                let swapStates = Self.committedStates(swapEvents, initial: [target], live: Set(model.cards.map(\.id)))
                let isClean = swapStates == [[target]] && crooked == 0
                if didSwapLand { swapLanded += 1 }
                if isClean { swapClean += 1 }
                if !didSwapLand || !isClean {
                    notes.append("swap land=\(didSwapLand) crooked=\(crooked) offTarget=\(offTarget) commits=[\(Self.describe(swapStates))] "
                        + "events=[\(Self.describe(swapEvents.filter { $0.isCentred || $0.id == target }))]")
                }
            }
            if !notes.isEmpty { results.append("\(step):" + notes.joined(separator: " ; ")) }
            display = plan.canonical ?? plan.staged
            centre = plan.target
        }
        let n = Self.steps
        print("S9 \(testCase.name) slid=\(slid)/\(n) landed=\(landed)/\(n) cleanSlide=\(cleanSlides)/\(n) vmSynced=\(synced)/\(n) "
              + "strayRuns=\(strayRuns)/\(n) swapLanded=\(swapLanded)/\(swaps) swapClean=\(swapClean)/\(swaps) "
              + "gate(immediate/waited/timedOut)=\(recorder.gateImmediate)/\(recorder.gateWaited)/\(recorder.gateTimedOut) "
              + String(format: "completion=%d/%d delay(min/max)=%.3f/%.3f remainingMax=%.1f ", completed, n,
                       completionDelays.min() ?? .nan, completionDelays.max() ?? .nan, remainingAtCompletion)
              + String(format: "tilt start(min/max)=%.2f/%.2f peak(min/max)=%.2f/%.2f end(max)=%.2f ",
                       tiltAtStart.min() ?? .nan, tiltAtStart.max() ?? .nan, tiltPeak.min() ?? .nan, tiltPeak.max() ?? .nan,
                       tiltAtEnd.max() ?? .nan)
              + "| " + startLine + " | " + results.joined(separator: " | "))
    }
}
