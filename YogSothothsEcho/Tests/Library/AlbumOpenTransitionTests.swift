import CoreGraphics
import Testing

@testable import YogSothothsEcho

// S6 T6 → #6-1 第一輪修正（s6-61-round1-fixes.md v0.6 §3 F3＋F4、F6）：四個通道依序走——
// 開：others（0.20 s，其他盒以被點者為界往外滑走淡出）→ flight（0.40 s，封面轉正飛到詳情框）→ reveal（文字浮現秒數，結束時刻依曲目數）；
// 關：reveal 以 2.3 倍速倒放 → flight 0.40 s 回飛 → others 0.20 s 回場。串行＝「其他盒全不可見才飛」（不穿模不變式）
struct AlbumOpenTransitionTests {
    let m = SpineCarouselTests.pro13

    private func finish(_ t: inout AlbumOpenTransition, from start: Double) -> Double {
        var now = start
        while now < start + 10 {
            now += 1.0 / 120
            t.tick(at: now)
            if case .open = t.phase { return now }
            if case .browsing = t.phase { return now }
        }
        return now
    }

    private func transition() -> AlbumOpenTransition { AlbumOpenTransition() }

    /// 文字段 1.0 s 的開啟
    private func open(_ t: inout AlbumOpenTransition, _ id: String = "a", at now: Double) {
        t.open(id, revealEnd: 1.0, at: now)
    }

    private static let full = AlbumOpenTransition.Channels(others: 1, flight: 1, reveal: 1)

    // MARK: 狀態轉移

    @Test func openThenCloseWalksThroughEveryPhase() {
        var t = transition()
        let r1 = t.open("a", revealEnd: 1.0, at: 0)
        #expect(r1)
        #expect(t.phase == .opening("a") && t.albumID == "a")
        let opened = finish(&t, from: 0)
        #expect(t.phase == .open("a"))
        #expect(abs(opened - 0.6) < 0.02)                  // 封面落定（0.20＋0.40）即 open、曲目可點
        #expect(t.isAnimating(at: 1.0) && !t.isAnimating(at: 1.7))   // 文字在 open 裡繼續浮現到 1.6 s
        #expect(t.channels(at: 1.6) == Self.full)
        let r2 = t.close(at: 3)
        #expect(r2)
        #expect(t.phase == .closing("a"))
        let closed = finish(&t, from: 3)
        #expect(t.phase == .browsing && t.albumID == nil)
        #expect(abs((closed - 3) - (1.0 / 2.3 + 0.6)) < 0.02)   // 文字倒放 2.3 倍速＋封面 0.40＋其他盒 0.20
    }

    @Test func tapsAreIgnoredUnlessBrowsing() {
        var t = transition()
        open(&t, at: 0)
        let r3 = t.open("b", revealEnd: 1.0, at: 0.1)
        #expect(!r3)
        #expect(t.phase == .opening("a"))
        t.close(at: 0.2)
        let r4 = t.open("b", revealEnd: 1.0, at: 0.3)
        #expect(!r4)
        #expect(t.phase == .closing("a"))
        var idle = AlbumOpenTransition()
        let r5 = idle.close(at: 0)
        #expect(!r5)
    }

    @Test func tracksAreTappableOnlyWhenOpen() {
        var t = transition()
        #expect(!t.tracksTappable)
        open(&t, at: 0)
        #expect(!t.tracksTappable)
        _ = finish(&t, from: 0)
        #expect(t.tracksTappable)
        t.close(at: 3)
        #expect(!t.tracksTappable)
    }

    @Test func resetReturnsToBrowsing() {
        var t = transition()
        open(&t, at: 0)
        t.reset()
        #expect(t.phase == .browsing && t.channels(at: 1) == .init())
    }

    // MARK: 時序（串行）

    @Test func openingRunsOthersThenFlightThenReveal() {
        var t = transition()
        open(&t, at: 10)
        let early = t.channels(at: 10.1)
        #expect(early.others > 0 && early.others < 1 && early.flight == 0 && early.reveal == 0)
        #expect(t.channels(at: 10.2).others == 1 && t.channels(at: 10.2).flight == 0)
        let flying = t.channels(at: 10.4)
        #expect(flying.flight > 0 && flying.flight < 1 && flying.reveal == 0)
        #expect(t.channels(at: 10.6).flight == 1 && t.channels(at: 10.6).reveal == 0)
        #expect(abs(t.channels(at: 11.1).reveal - 0.5) < 1e-6)
        #expect(t.channels(at: 11.6) == Self.full)
    }

    @Test func closingRunsRevealThenFlightThenOthers() {
        var t = transition()
        open(&t, at: 0)
        _ = finish(&t, from: 0)
        t.close(at: 5)
        let revealEnd = 1.0 / 2.3
        let sinking = t.channels(at: 5 + revealEnd / 2)
        #expect(sinking.reveal > 0 && sinking.reveal < 1 && sinking.flight == 1 && sinking.others == 1)
        // 段落交界前後各取 1 ms（交界那一瞬間是浮點邊界）
        #expect(t.channels(at: 5 + revealEnd - 0.001).flight == 1)
        #expect(t.channels(at: 5 + revealEnd + 0.001).reveal == 0)
        let back = t.channels(at: 5 + revealEnd + 0.2)
        #expect(back.flight > 0 && back.flight < 1 && back.others == 1)
        #expect(t.channels(at: 5 + revealEnd + 0.399).others == 1)
        #expect(t.channels(at: 5 + revealEnd + 0.401).flight == 0)
        #expect(t.channels(at: 5 + revealEnd + 0.6) == .init())
    }

    /// 使用者「開與關速度一致」：others 兩向 0.20 s、flight 兩向 0.40 s；只有文字段關比開快（2.3 倍）
    @Test func othersAndFlightAreMirrored() {
        #expect(AlbumOpenTransition.othersDuration == 0.2 && AlbumOpenTransition.flightDuration == 0.4)
        #expect(AlbumOpenTransition.closeRevealSpeed == 2.3)
    }

    /// 不穿模不變式：任何時刻 flight＞0 ⇒ others＝1；reveal＞0 ⇒ flight＝1（含中途反向）
    @Test func flightNeverStartsBeforeOthersAreGone() {
        for reversal in stride(from: 0.05, through: 1.6, by: 0.05) {
            var t = transition()
            open(&t, at: 0)
            var now = 0.0
            while now < 5 {
                now += 1.0 / 240
                if abs(now - reversal) < 1.0 / 480 { t.close(at: now) }
                t.tick(at: now)
                let c = t.channels(at: now)
                #expect(c.flight == 0 || c.others == 1, "reversal \(reversal) at \(now): \(c)")
                #expect(c.reveal == 0 || c.flight == 1, "reversal \(reversal) at \(now): \(c)")
                if t.phase == .browsing { break }
            }
            #expect(t.phase == .browsing)
        }
    }

    /// 中途反向：反向瞬間各通道不跳（others 段、flight 段、reveal 段）
    @Test func reversingMidwayIsContinuous() {
        for at in [0.1, 0.4, 1.0] {
            var t = transition()
            open(&t, at: 0)
            let before = t.channels(at: at)
            t.close(at: at)
            #expect(t.channels(at: at) == before)
            #expect(t.channels(at: at + 0.02) != before)
        }
    }

    /// 凍結中（唱機開著）曲目載入、更新結束時刻：仍凍結，恢復後從同一點續跑
    @Test func updatingRevealEndKeepsAFrozenTransitionFrozen() {
        var t = transition()
        open(&t, at: 0)
        t.freeze(at: 0.3)
        let held = t.channels(at: 0.3)
        t.updateRevealEnd(2.0, at: 1)
        #expect(t.channels(at: 5) == held && !t.isAnimating(at: 5))
        t.resume(at: 5)
        #expect(t.channels(at: 5) == held && t.isAnimating(at: 5.01))
    }

    /// 開唱機時凍結、關唱機後從同一點續跑
    @Test func freezeHoldsProgress() {
        var t = transition()
        open(&t, at: 0)
        t.freeze(at: 0.2)
        let held = t.channels(at: 0.2)
        #expect(t.channels(at: 5) == held)
        t.tick(at: 5)
        #expect(t.phase == .opening("a") && !t.isAnimating(at: 5))
        t.resume(at: 5)
        #expect(t.channels(at: 5) == held)
        #expect(t.channels(at: 6.4) == Self.full)
    }

    // MARK: 繪製 owner（恰一份可見）

    @Test func ownerFollowsTheFlight() {
        typealias C = AlbumOpenTransition.Channels
        var t = transition()
        #expect(t.owner(C()) == .browser)                                  // browsing
        open(&t, at: 0)
        #expect(t.owner(C(others: 0.5)) == .browser)
        #expect(t.owner(C(others: 1)) == .browser)
        #expect(t.owner(C(others: 1, flight: 0.3)) == .stage)
        #expect(t.owner(C(others: 1, flight: 1, reveal: 0.4)) == .detail)
        // Reduce Motion：一開始就離開側封（原槽位立即隱藏），詳情框原地淡入
        var rm = transition()
        rm.reduceMotion = true
        rm.open("a", revealEnd: 1.0, at: 0)
        #expect(rm.owner(C()) == .stage)
        #expect(rm.owner(Self.full) == .detail)
    }

    /// 曲目載入後更新結束時刻：從現值續走、不跳格；已走完的會再動起來
    @Test func updatingRevealEndContinuesFromTheCurrentValue() {
        var t = transition()
        open(&t, at: 0)
        let before = t.channels(at: 0.9)
        t.updateRevealEnd(2.0, at: 0.9)
        #expect(t.channels(at: 0.9) == before)
        _ = finish(&t, from: 0.9)                               // 封面早已落定 → open
        #expect(t.channels(at: 2.65).reveal == 2.0 && !t.isAnimating(at: 2.7))
        t.updateRevealEnd(3.0, at: 3)
        #expect(t.isAnimating(at: 3.1) && t.channels(at: 4.1).reveal == 3.0)
    }

    /// owner 不是側封時，其他盒必全不可見
    @Test func othersAreInvisibleWheneverTheTargetLeftTheBrowser() {
        let start = SpineCarousel.pose(u: 1.4, metrics: m)
        let target = AlbumOpenPose.detailCoverFrame(metrics: m)
        var t = transition()
        open(&t, at: 0)
        var now = 0.0
        while now < 2 {
            now += 1.0 / 120
            let c = t.channels(at: now)
            let pose = AlbumOpenPose.make(c, start: start, target: target, metrics: m, reduceMotion: false, hasReturnSlot: true)
            if t.owner(c) != .browser { #expect(pose.othersOpacity == 0) }
        }
    }

    // MARK: pose

    /// 起點＝被點那張當下的 pose；終點的投影外框＝詳情封面框（交接無位移，左右兩側都是）
    @Test func flightEndpointsMatchStartAndDetailFrame() {
        let target = AlbumOpenPose.detailCoverFrame(metrics: m)
        #expect(target.width > 300 && target.minX > 0 && target.maxY < m.browse.maxY)
        let projection = BoxProjection(metrics: m)
        for u: CGFloat in [-1.6, 0, 2.3] {
            let start = SpineCarousel.pose(u: u, metrics: m)
            let begin = AlbumOpenPose.make(.init(), start: start, target: target, metrics: m, reduceMotion: false, hasReturnSlot: true)
            #expect(begin.flight == start && begin.flightOpacity == 1 && begin.spineOpacity == 1)
            #expect(begin.othersOffset == 0 && begin.othersOpacity == 1 && begin.othersBlur == 0)
            let end = AlbumOpenPose.make(Self.full, start: start, target: target, metrics: m,
                                         reduceMotion: false, hasReturnSlot: true)
            let frame = projection.bounds(.front, pose: end.flight)
            #expect(abs(frame.minX - target.minX) <= 0.5 && abs(frame.maxX - target.maxX) <= 0.5, "u=\(u) \(frame) vs \(target)")
            #expect(abs(frame.minY - target.minY) <= 0.5 && abs(frame.maxY - target.maxY) <= 0.5)
            #expect(end.flight.rotationDegrees == 0 && end.spineOpacity == 0)
            #expect(end.othersOpacity == 0 && end.othersBlur == 6 * m.cover / SpineCarouselMetrics.referenceCover)
            #expect(AlbumOpenPose.backgroundBlend(Self.full) == 1)
        }
    }

    /// 縮放以書脊邊為錨：左側盒落點對齊詳情框左緣、右側對齊右緣（原點不變＝轉場開頭不跳）
    @Test func scalingAnchorsOnTheSpineEdge() {
        let target = AlbumOpenPose.detailCoverFrame(metrics: m)
        let left = AlbumOpenPose.endPose(target: target, side: .left, metrics: m)
        let right = AlbumOpenPose.endPose(target: target, side: .right, metrics: m)
        let projection = BoxProjection(metrics: m)
        #expect(abs(projection.project(.zero, face: .front, pose: left).x - target.minX) <= 0.5)
        #expect(abs(projection.project(CGPoint(x: m.cover, y: 0), face: .front, pose: right).x - target.maxX) <= 0.5)
    }

    @Test func backgroundBlendIsMonotonic() {
        var t = transition()
        open(&t, at: 0)
        var last = -1.0
        for step in 0...160 {
            let blend = AlbumOpenPose.backgroundBlend(t.channels(at: Double(step) / 100))
            #expect(blend >= last)
            last = blend
        }
    }

    /// Reduce Motion：位置與角度恆為終點、只變不透明度；四個通道同時走 0.25 s
    @Test func reduceMotionOnlyCrossFades() {
        var t = transition()
        t.reduceMotion = true
        open(&t, at: 0)
        let start = SpineCarousel.pose(u: -2, metrics: m)
        let target = AlbumOpenPose.detailCoverFrame(metrics: m)
        let end = AlbumOpenPose.endPose(target: target, side: start.side, metrics: m)
        for time in [0.0, 0.1, 0.2, 0.25] {
            let pose = AlbumOpenPose.make(t.channels(at: time), start: start, target: target, metrics: m, reduceMotion: true, hasReturnSlot: true)
            #expect(pose.flight == end && pose.othersOffset == 0 && pose.othersBlur == 0)
        }
        #expect(t.channels(at: 0.25) == Self.full)
        let mid = AlbumOpenPose.make(t.channels(at: 0.1), start: start, target: target, metrics: m, reduceMotion: true, hasReturnSlot: true)
        #expect(mid.flightOpacity > 0 && mid.flightOpacity < 1)
        _ = finish(&t, from: 0)
        t.close(at: 1)
        #expect(t.channels(at: 1.25) == .init())
    }

    /// 回程沒有槽位（換版後專輯不在清單）＝原地淡出：封面停在詳情框、只降不透明度
    @Test func missingReturnSlotFadesInPlace() {
        let start = SpineCarousel.pose(u: 1, metrics: m)
        let target = AlbumOpenPose.detailCoverFrame(metrics: m)
        let end = AlbumOpenPose.endPose(target: target, side: start.side, metrics: m)
        let half = AlbumOpenPose.make(.init(others: 0.5, flight: 0.5), start: start, target: target, metrics: m,
                                      reduceMotion: false, hasReturnSlot: false)
        #expect(half.flight == end && half.flightOpacity < 1 && half.flightOpacity > 0)
    }
}
