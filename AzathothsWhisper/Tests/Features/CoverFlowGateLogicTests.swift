import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// H-02 UI 測試閘門的判定純邏輯（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.6–3.7）。
//
// 為何判定邏輯要在這裡先測：UITest 只負責量（AX frame、label、像素），紅綠由這些純函數決定。
// 若判定本身有錯，閘門的「抓到缺陷」就是假的——這正是交接檔記錄的三次失敗形態。
@Suite("CoverFlowGateLogic")
struct CoverFlowGateLogicTests {
    private typealias Logic = CoverFlowGateLogic

    private let config = GateConfig(
        itemWidth: 260, stride: 150.8, unrotatedAspect: 377.0 / 260.0, trackCount: 20
    )

    // MARK: 佈景：以區間 ＋ 疊放次序模擬畫面

    /// 每張卡在畫面上佔一段水平區間；取樣點落在多張卡內時，`zOrder` 較後者在上層。
    /// 候選之外的卡片色回 `.uncertain`（真實取樣時那是「第三張卡的顏色」）。
    private struct FakeScreen {
        var painted: [Int: ClosedRange<CGFloat>]
        var zOrder: [Int]

        func pixel(at point: CGPoint, candidates: [Int]) -> GatePixelClass {
            let covering = zOrder.filter { painted[$0]?.contains(point.x) == true }
            guard let top = covering.last else { return .background }
            return candidates.contains(top) ? .card(top) : .uncertain
        }
    }

    /// 以 T07 為幾何中心的一組 AX 外框（右側卡繞內緣旋轉：外框變窄變高）
    private func cards(center: Int = 7, missing: Set<Int> = []) -> [GateCard] {
        let frames: [Int: CGRect] = [
            center - 2: CGRect(x: 205, y: 80, width: 200, height: 410),
            center - 1: CGRect(x: 341, y: 90, width: 215, height: 397),
            center: CGRect(x: 470, y: 100, width: 260, height: 377),
            center + 1: CGRect(x: 644, y: 90, width: 215, height: 397),
            center + 2: CGRect(x: 795, y: 80, width: 200, height: 410),
        ]
        return frames
            .filter { !missing.contains($0.key) && (0..<20).contains($0.key) }
            .map { GateCard(index: $0.key, frame: $0.value) }
            .sorted { $0.index < $1.index }
    }

    private func paintedRanges(_ cards: [GateCard]) -> [Int: ClosedRange<CGFloat>] {
        Dictionary(uniqueKeysWithValues: cards.map { ($0.index, $0.frame.minX...$0.frame.maxX) })
    }

    /// 正確疊放：距中心愈遠愈下層
    private func correctZOrder(center: Int = 7) -> [Int] {
        [center - 2, center + 2, center - 1, center + 1, center]
    }

    private func measure(
        label: String?, cards: [GateCard], screen: FakeScreen, want: Int? = nil, step: String = "T3.s1"
    ) -> GateVerdict {
        Logic.evaluate(
            GateMeasurement(
                step: step, stripMidX: 600, label: label, cards: cards, wantIndex: want,
                pixelAt: { screen.pixel(at: $0, candidates: $1) }
            ),
            config: config
        )
    }

    private func codes(_ verdict: GateVerdict) -> [String] {
        verdict.findings.map(\.code).sorted()
    }

    // MARK: 契約：通過

    @Test func correctlyStackedCenteredCardPasses() {
        let cards = cards()
        let screen = FakeScreen(painted: paintedRanges(cards), zOrder: correctZOrder())
        let verdict = measure(label: "T07", cards: cards, screen: screen, want: 7)
        #expect(verdict.findings.isEmpty, "\(verdict.findings)")
        #expect(verdict.gateLine == "GATE{T3.s1|PASS}")
        #expect(verdict.failureMessages.isEmpty)
    }

    // MARK: C1／C3

    /// 缺陷 3 的偏移形態：label 仍是命令目標 T10，畫面中心卻是 T07
    @Test func offsetFormReportsC1WithDiscreteStrides() {
        let cards = cards()
        let screen = FakeScreen(painted: paintedRanges(cards), zOrder: correctZOrder())
        let verdict = measure(label: "T10", cards: cards, screen: screen, want: 10)
        #expect(codes(verdict) == ["C1-OFFSET"])
        #expect(verdict.failureMessages == ["SIG{T3.s1|C1-OFFSET|label=T10|centered=T07|strides=+3}"])
    }

    /// 缺陷 3 的漂移形態：label 被回寫成畫面中心，C1 反而成立——只有 C3 抓得到
    @Test func driftFormIsCaughtOnlyByTargetClause() {
        let cards = cards()
        let screen = FakeScreen(painted: paintedRanges(cards), zOrder: correctZOrder())
        let verdict = measure(label: "T07", cards: cards, screen: screen, want: 10)
        #expect(verdict.failureMessages == ["SIG{T3.s1|C3-TARGET-MISS|want=T10|got=T07}"])
    }

    @Test func emptyLabelIsAProductFinding() {
        let cards = cards()
        let screen = FakeScreen(painted: paintedRanges(cards), zOrder: correctZOrder())
        let verdict = measure(label: "", cards: cards, screen: screen)
        #expect(codes(verdict) == ["C1-LABEL-CARD-MISSING"])
    }

    /// label 所指的卡就是最近中心的那張，但沒對正（例如捲動後沒吸附）
    @Test func nearestButOffCentreCardIsZeroStrideOffset() {
        let shifted = cards().map { GateCard(index: $0.index, frame: $0.frame.offsetBy(dx: 10, dy: 0)) }
        let screen = FakeScreen(painted: paintedRanges(shifted), zOrder: correctZOrder())
        let verdict = measure(label: "T07", cards: shifted, screen: screen)
        #expect(verdict.failureMessages.contains("SIG{T3.s1|C1-OFFSET|label=T07|centered=T07|strides=0}"))
    }

    @Test func rotatedLabelCardIsNotFacing() {
        let tilted = cards().map { card -> GateCard in
            guard card.index == 7 else { return card }
            return GateCard(index: 7, frame: CGRect(x: 489, y: 94, width: 222, height: 388))
        }
        let screen = FakeScreen(painted: paintedRanges(tilted), zOrder: correctZOrder())
        let verdict = measure(label: "T07", cards: tilted, screen: screen)
        #expect(codes(verdict).contains("C1-NOT-FACING"))
        // 中心卡沒正對時 C2 的前提不成立：只記註記，不判疊放
        #expect(!codes(verdict).contains("C2-STACK"))
        #expect(verdict.notes.contains { $0.hasPrefix("C2-NA") })
    }

    // MARK: C2

    /// 缺陷 2 的使用者可見症狀：右側傾斜的鄰張壓住正對觀者那張
    @Test func neighbourPaintedAboveCentreIsC2Stack() {
        let cards = cards()
        let zOrder = [5, 9, 6, 7, 8]   // T08 在 T07 之上
        let screen = FakeScreen(painted: paintedRanges(cards), zOrder: zOrder)
        let verdict = measure(label: "T07", cards: cards, screen: screen)
        #expect(verdict.failureMessages == ["SIG{T3.s1|C2-STACK|G=T07|over=T08|side=R}"])
        #expect(verdict.gateLine == "GATE{T3.s1|FAIL|C2-STACK}")
    }

    @Test func bothSidesAreReportedIndependently() {
        let cards = cards()
        let screen = FakeScreen(painted: paintedRanges(cards), zOrder: [5, 9, 7, 6, 8])
        let verdict = measure(label: "T07", cards: cards, screen: screen)
        #expect(verdict.failureMessages.sorted() == [
            "SIG{T3.s1|C2-STACK|G=T07|over=T06|side=L}",
            "SIG{T3.s1|C2-STACK|G=T07|over=T08|side=R}",
        ])
    }

    /// 負間距下相鄰卡必然交疊；外框不交＝佈局錯，是產品碼而不是取樣失敗
    @Test func neighbourWithoutHorizontalIntersectionIsC2Gap() {
        let apart = cards().map { card -> GateCard in
            guard card.index == 8 else { return card }
            return GateCard(index: 8, frame: CGRect(x: 740, y: 90, width: 215, height: 397))
        }
        let screen = FakeScreen(painted: paintedRanges(apart), zOrder: correctZOrder())
        let verdict = measure(label: "T07", cards: apart, screen: screen)
        #expect(verdict.failureMessages.contains { $0.hasPrefix("SIG{T3.s1|C2-GAP|G=T07|side=R") })
    }

    @Test func blankOverlapIsC2Gap() {
        let cards = cards()
        var painted = paintedRanges(cards)
        painted[7] = 470...680          // AX 說兩張交疊於 644–730，畫面上交疊區卻兩張都沒畫
        painted[8] = 700...859
        let screen = FakeScreen(painted: painted, zOrder: correctZOrder())
        let verdict = measure(label: "T07", cards: cards, screen: screen)
        #expect(verdict.failureMessages.contains { $0.hasPrefix("SIG{T3.s1|C2-GAP|G=T07|side=R") })
    }

    /// 參考點落在背景上：AX 說那裡有卡，畫面上沒有——產品碼（卡片缺位），不是探針錯
    @Test func centreReferenceOnBackgroundIsBlankCard() {
        let cards = cards()
        var painted = paintedRanges(cards)
        painted[7] = 470...560          // T07 只畫了左邊一小段
        let screen = FakeScreen(painted: painted, zOrder: correctZOrder())
        let verdict = measure(label: "T07", cards: cards, screen: screen)
        #expect(verdict.failureMessages.contains("SIG{T3.s1|C0-BLANK-CARD|card=T07}"))
    }

    /// 參考點被第三張卡蓋住：這是取樣位置錯，屬探針問題，不得計入產品判決
    @Test func referenceCoveredByAnotherCardIsProbe() {
        let cards = cards()
        var painted = paintedRanges(cards)
        painted[9] = 700...995          // T09 蓋到 T08 的參考點
        let screen = FakeScreen(painted: painted, zOrder: [5, 6, 7, 8, 9])
        let verdict = measure(label: "T07", cards: cards, screen: screen)
        #expect(verdict.findings.contains { $0.code == "PROBE-REF" })
        #expect(verdict.gateLine.hasPrefix("GATE{T3.s1|FAIL|"))
        #expect(verdict.gateLine.contains("PROBE-REF"))
        #expect(verdict.failureMessages.contains { $0.hasPrefix("[PROBE-REF]") })
    }

    // MARK: C0

    @Test func missingNeighbourOverBackgroundIsBlankSide() {
        let partial = cards(missing: [8, 9])
        let screen = FakeScreen(painted: paintedRanges(partial), zOrder: [5, 6, 7])
        let verdict = measure(label: "T07", cards: partial, screen: screen)
        #expect(verdict.failureMessages.contains("SIG{T3.s1|C0-BLANK-SIDE|G=T07|side=R}"))
    }

    /// AX 樹沒有鄰張但畫面上有卡：AX 裁剪，屬探針問題
    @Test func missingNeighbourThatIsPaintedIsAXCull() {
        let all = cards()
        let visibleInAX = all.filter { $0.index != 8 }
        let screen = FakeScreen(painted: paintedRanges(all), zOrder: correctZOrder())
        let verdict = measure(label: "T07", cards: visibleInAX, screen: screen)
        #expect(verdict.findings.contains { $0.code == "PROBE-AX-CULL" })
    }

    /// 端點沒有外側鄰張是正常的
    @Test func endpointDoesNotRequireOuterNeighbour() {
        let endpoint = cards(center: 0)
        let screen = FakeScreen(painted: paintedRanges(endpoint), zOrder: [2, 1, 0])
        let verdict = measure(label: "T00", cards: endpoint, screen: screen, want: 0)
        #expect(verdict.findings.isEmpty, "\(verdict.findings)")
    }

    @Test func noCardsInAXIsProbe() {
        let screen = FakeScreen(painted: [:], zOrder: [])
        let verdict = measure(label: "T07", cards: [], screen: screen)
        #expect(codes(verdict) == ["PROBE-AX"])
    }

    // MARK: C4（捲動回寫軌跡）

    @Test func monotonicWritebackThatHoldsIsClean() {
        #expect(Logic.writebackFindings(start: 11, gesture: [12, 13, 13, nil, 13], hold: [], settled: 13).isEmpty)
        #expect(Logic.writebackFindings(start: 11, gesture: [10, 9], hold: [9], settled: 9).isEmpty)
    }

    @Test func noWritebackWhenGestureNeverLeavesStart() {
        #expect(Logic.writebackFindings(start: 11, gesture: [], hold: [], settled: 11).map(\.code) == ["C4-NO-WRITEBACK"])
        #expect(Logic.writebackFindings(start: 11, gesture: [11, nil, 11], hold: [], settled: 11).map(\.code) == ["C4-NO-WRITEBACK"])
    }

    /// `viewAligned` 的自然吸附只會選最近項，不會使回寫值反向；反向＝有東西在拉回
    @Test func directionChangeWithinOneGestureIsReversal() {
        let findings = Logic.writebackFindings(start: 11, gesture: [12, 11, 13], hold: [], settled: 13)
        #expect(findings == [GateFinding(code: "C4-REVERSAL", detail: "seq=T11>T12>T11>T13")])
    }

    @Test func changeAfterSettleIsSnapback() {
        let findings = Logic.writebackFindings(start: 11, gesture: [12, 13], hold: [12], settled: 13)
        #expect(findings == [GateFinding(code: "C4-SNAPBACK", detail: "from=T13|to=T12")])
    }

    // MARK: 落定判定

    @Test func settledRequiresConsecutiveIdenticalReadings() {
        let a = GateReading(label: "T07", centerIndex: 7, frameKey: [940, 200, 520, 754])
        let b = GateReading(label: "T08", centerIndex: 8, frameKey: [1242, 200, 520, 754])
        #expect(Logic.isSettled([b, a, a, a, a], required: 4))
        #expect(!Logic.isSettled([a, a, a], required: 4))
        #expect(!Logic.isSettled([a, a, b, a, a], required: 4))
        let unknown = GateReading(label: "T07", centerIndex: nil, frameKey: [])
        #expect(!Logic.isSettled([unknown, unknown, unknown, unknown], required: 4))
    }

    /// frame 取 0.5pt 精度：次像素抖動不應阻止落定，真實位移必須被看見
    @Test func readingKeyRoundsFramesToHalfPoints() {
        let base = GateCard(index: 7, frame: CGRect(x: 470.1, y: 100, width: 260, height: 377))
        let jitter = GateCard(index: 7, frame: CGRect(x: 470.2, y: 100, width: 260, height: 377))
        let moved = GateCard(index: 7, frame: CGRect(x: 471.0, y: 100, width: 260, height: 377))
        let r1 = GateReading(label: "T07", cards: [base], stripMidX: 600)
        let r2 = GateReading(label: "T07", cards: [jitter], stripMidX: 600)
        let r3 = GateReading(label: "T07", cards: [moved], stripMidX: 600)
        #expect(r1 == r2)
        #expect(r1 != r3)
    }

    // MARK: 分類與幾何原語

    @Test func classifyPicksNearestCandidateOrBackground() {
        let a = CoverFlowUITestFixture.color(at: 7)
        let noisy = GateRGB(red: a.red + 0.08, green: max(0, a.green - 0.08), blue: a.blue)
        #expect(Logic.classify(noisy, candidates: [7, 8], threshold: 0.35) == .card(7))
        #expect(Logic.classify(GateRGB(red: 0.03, green: 0.02, blue: 0.04), candidates: [7, 8], threshold: 0.35) == .background)
        #expect(Logic.classify(GateRGB(red: 0.5, green: 0.5, blue: 0.5), candidates: [7, 8], threshold: 0.35) == .uncertain)
    }

    /// 截圖是顯示器色彩空間（本機為 Display P3 類），色板是 sRGB。讀色必須經 CoreGraphics 色彩匹配轉回 sRGB；
    /// 直接拿 `NSColor.usingColorSpace(.sRGB)` 會再套一次裝置描述檔（實測偏 0.08–0.16，足以把分類推過閾值）
    @Test func averageSRGBRecoversPaletteThroughAnotherColourSpace() throws {
        let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let expected = CoverFlowUITestFixture.color(at: 7)
        let source = try #require(Self.solidImage(expected, space: srgb))
        // 模擬截圖：同一張圖經色彩匹配畫進 P3 位圖
        let screenshotLike = try #require(Self.redraw(source, into: p3))
        let sample = try #require(Logic.averageSRGB(of: screenshotLike, pixelRect: CGRect(x: 10, y: 10, width: 5, height: 5)))
        #expect(Logic.distance(sample, expected) < 0.02, "\(sample) vs \(expected)")
    }

    @Test func averageSRGBRejectsRectOutsideImage() throws {
        let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try #require(Self.solidImage(GateRGB(red: 1, green: 0, blue: 0), space: srgb))
        #expect(Logic.averageSRGB(of: image, pixelRect: CGRect(x: 100, y: 100, width: 5, height: 5)) == nil)
    }

    private static func solidImage(_ color: GateRGB, space: CGColorSpace, side: Int = 32) -> CGImage? {
        guard let fill = CGColor(colorSpace: space, components: [color.red, color.green, color.blue, 1]),
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.setFillColor(fill)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private static func redraw(_ image: CGImage, into space: CGColorSpace) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    @Test func facingDependsOnWidthAndAspect() {
        #expect(Logic.isFacing(CGSize(width: 260, height: 377), config: config))
        #expect(Logic.isFacing(CGSize(width: 255, height: 370), config: config))
        #expect(!Logic.isFacing(CGSize(width: 222.6, height: 388), config: config))
        #expect(!Logic.isFacing(CGSize(width: 240, height: 377), config: config))
    }

    @Test func strideBucketRoundsToNearestCard() {
        #expect(Logic.strideBucket(offset: 452.4, stride: 150.8) == 3)
        #expect(Logic.strideBucket(offset: -150.8, stride: 150.8) == -1)
        #expect(Logic.strideBucket(offset: 70, stride: 150.8) == 0)
        #expect(Logic.strideBucket(offset: 80, stride: 150.8) == 1)
        #expect(Logic.signed(3) == "+3")
        #expect(Logic.signed(-1) == "-1")
        #expect(Logic.signed(0) == "0")
    }

    @Test func overlapPointIsMidOfIntersectionOnFaceBand() {
        let centre = CGRect(x: 470, y: 100, width: 260, height: 377)
        let right = CGRect(x: 644, y: 90, width: 215, height: 397)
        #expect(Logic.overlapSamplePoint(centre: centre, neighbour: right) == CGPoint(x: 687, y: 230))
        let apart = CGRect(x: 740, y: 90, width: 215, height: 397)
        #expect(Logic.overlapSamplePoint(centre: centre, neighbour: apart) == nil)
    }

    @Test func neighbourReferenceSitsBetweenCentreEdgeAndNextCard() {
        let centre = CGRect(x: 470, y: 100, width: 260, height: 377)
        let right = CGRect(x: 644, y: 90, width: 215, height: 397)
        let beyond = CGRect(x: 795, y: 80, width: 200, height: 410)
        #expect(Logic.neighbourReferencePoint(centre: centre, neighbour: right, beyond: beyond) == CGPoint(x: 762.5, y: 230))
        #expect(Logic.neighbourReferencePoint(centre: centre, neighbour: right, beyond: nil) == CGPoint(x: 794.5, y: 230))
        let left = CGRect(x: 341, y: 90, width: 215, height: 397)
        let beyondLeft = CGRect(x: 205, y: 80, width: 200, height: 410)
        #expect(Logic.neighbourReferencePoint(centre: centre, neighbour: left, beyond: beyondLeft) == CGPoint(x: 437.5, y: 230))
        // 下一張把鄰張整個蓋過中心卡外緣：沒有無遮擋區
        let swallowing = CGRect(x: 700, y: 80, width: 200, height: 410)
        #expect(Logic.neighbourReferencePoint(centre: centre, neighbour: right, beyond: swallowing) == nil)
    }

    // MARK: 簽名格式

    @Test func signaturesAndGateLinesAreDiscreteAndSorted() {
        let verdict = GateVerdict(
            step: "T4.s2",
            findings: [
                GateFinding(code: "C2-STACK", detail: "G=T16|over=T17|side=R"),
                GateFinding(code: "C1-OFFSET", detail: "label=T19|centered=T16|strides=+3"),
            ],
            notes: []
        )
        #expect(verdict.gateLine == "GATE{T4.s2|FAIL|C1-OFFSET,C2-STACK}")
        #expect(verdict.failureMessages == [
            "SIG{T4.s2|C2-STACK|G=T16|over=T17|side=R}",
            "SIG{T4.s2|C1-OFFSET|label=T19|centered=T16|strides=+3}",
        ])
        let probe = GateVerdict(step: "T2.s1", findings: [GateFinding(code: "PROBE-REF", detail: "point=762.5,230")], notes: [])
        #expect(probe.failureMessages == ["[PROBE-REF] T2.s1 point=762.5,230"])
    }

    // MARK: C5（切 tab 往返的漂移）

    @Test func sameLabelAfterRebuildIsNoDrift() {
        #expect(Logic.driftFindings(before: "T19", after: "T19").isEmpty)
    }

    @Test func changedLabelAfterRebuildIsC5Drift() {
        let findings = Logic.driftFindings(before: "T19", after: "T16")
        #expect(findings.map(\.code) == ["C5-DRIFT"])
        #expect(findings.first?.detail == "before=T19|after=T16")
    }

    /// 量測失敗不得冒充產品 C5（R5-4 Round 2 P1 ④）：任一側 label 讀不到 → 探針碼，絕不是 `C5-DRIFT`
    @Test func unreadableLabelAroundRebuildIsProbeNotDrift() {
        #expect(Logic.driftFindings(before: nil, after: "T19").map(\.code) == ["PROBE-AX"])
        #expect(Logic.driftFindings(before: "T19", after: nil).map(\.code) == ["PROBE-AX"])
        #expect(Logic.driftFindings(before: nil, after: nil).map(\.code) == ["PROBE-AX"])
    }

    // MARK: 落定逾時分流（§3.6 TV4）與截圖穩定鍵（TV6）

    private func reading(_ center: Int?, x: Int) -> GateReading {
        GateReading(label: center.map { "T\($0)" }, centerIndex: center, frameKey: [x, 0, 520, 260])
    }

    @Test func stillMovingWithReadableAxIsProductNeverSettles() {
        let moving = (0..<4).map { reading(7, x: $0) }
        #expect(Logic.settleOutcome(readings: moving, required: 4, lastReadFailed: false) == .neverSettles)
    }

    @Test func settledTailIsSettled() {
        let steady = Array(repeating: reading(7, x: 3), count: 4)
        #expect(Logic.settleOutcome(readings: steady, required: 4, lastReadFailed: false) == .settled)
    }

    /// AX 在最後失效、樣本不足、或中心卡讀不到，都是探針問題——不得掛成產品 C6
    @Test func unreadableAxIsProbeNotProductC6() {
        let moving = (0..<4).map { reading(7, x: $0) }
        #expect(Logic.settleOutcome(readings: moving, required: 4, lastReadFailed: true) == .axUnreadable)
        #expect(Logic.settleOutcome(readings: Array(moving.prefix(2)), required: 4, lastReadFailed: false) == .axUnreadable)
        let noCentre = (0..<4).map { reading(nil, x: $0) }
        #expect(Logic.settleOutcome(readings: noCentre, required: 4, lastReadFailed: false) == .axUnreadable)
    }

    /// 落定樣本必須真正「連續」（R5-4 Round 2 P1 ①）：讀取失敗要清空 streak——
    /// 「3 成功＋1 失敗＋1 成功」不得算成 4 次連續而提前 settled（那會繞過 settleOutcome 的分流）
    @Test func readFailureClearsTheSettleStreak() {
        let steady = reading(7, x: 3)
        let broken = GateSettleTracker(required: 4)
            .observing(steady).observing(steady).observing(steady).observing(nil).observing(steady)
        #expect(!broken.isSettled)
        #expect(broken.outcome == .axUnreadable, "失敗後樣本不足＝探針問題，不得報成產品 C6")
        let recovered = broken.observing(steady).observing(steady).observing(steady)
        #expect(recovered.isSettled)
        #expect(recovered.outcome == .settled)
    }

    /// 一次晚期讀取失敗不得把真正在動的產品 C6 降成探針碼：逾時分流看全部成功樣本，尾段仍在變 → C6
    @Test func lateSingleReadFailureKeepsProductNeverSettles() {
        var tracker = GateSettleTracker(required: 4)
        for x in 0..<6 { tracker = tracker.observing(reading(7, x: x)) }
        tracker = tracker.observing(nil)
        for x in 6..<9 { tracker = tracker.observing(reading(7, x: x)) }
        #expect(!tracker.isSettled)
        #expect(tracker.outcome == .neverSettles)
    }

    /// 尾段全同卻從未連續四次成功＝AX 斷續失敗 → 探針，不是 C6
    @Test func intermittentAxWithSteadyFramesIsProbeNotC6() {
        let steady = reading(7, x: 3)
        var tracker = GateSettleTracker(required: 4)
        for _ in 0..<5 { tracker = tracker.observing(steady).observing(steady).observing(nil) }
        #expect(!tracker.isSettled)
        #expect(tracker.observing(steady).outcome == .axUnreadable)
    }

    @Test func trackerReportsNeverSettlesOnlyWhileAxStaysReadable() {
        let moving = (0..<4).reduce(GateSettleTracker(required: 4)) { $0.observing(reading(7, x: $1)) }
        #expect(moving.outcome == .neverSettles)
        #expect(moving.observing(nil).outcome == .axUnreadable)
        #expect(GateSettleTracker(required: 4).outcome == .axUnreadable)
    }

    @Test func stabilityKeyCoversEveryCardNotJustTheCentre() {
        let base = cards()
        let strip = CGRect(x: 265, y: 131, width: 680, height: 664)
        let window = CGRect(x: 5, y: 50, width: 1200, height: 800)
        let key = Logic.stabilityKey(label: "T07", cards: base, stripFrame: strip, windowFrame: window)
        #expect(key == Logic.stabilityKey(label: "T07", cards: base, stripFrame: strip, windowFrame: window))
        // 只有鄰張動了：中心卡讀數不變，穩定鍵必須不同（否則會用不同時刻的 frame 與像素判 C2）
        let neighbourMoved = base.map { card -> GateCard in
            card.index == 8 ? GateCard(index: 8, frame: card.frame.offsetBy(dx: 12, dy: 0)) : card
        }
        #expect(key != Logic.stabilityKey(label: "T07", cards: neighbourMoved, stripFrame: strip, windowFrame: window))
    }
}
