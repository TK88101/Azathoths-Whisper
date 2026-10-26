import CoreGraphics
import Testing

@testable import YogSothothsEcho

// S5 T13（sprint-5-detail.md §4.4 v1.3、D4、D5；#5-1 G7）：甩動切歌轉場狀態機——放手即送＋抬臂煞停、
// 抬臂計時與「可以決定了」兩個獨立事件、依已採用狀態分路、各段時長與加速、展示用的位置與層級

private func swipe(scale: CGFloat = 2) -> SwipeTransition { SwipeTransition(displayScale: scale) }

/// 拖過閾值放手，回傳放手的副作用
@discardableResult
private func released(_ t: inout SwipeTransition, _ dx: CGFloat = -80, canSend: Bool = true,
                      reduceMotion: Bool = false) -> SwipeTransition.Effect? {
    t.dragChanged(CGSize(width: dx > 0 ? 5 : -5, height: 0))
    return t.dragEnded(CGSize(width: dx, height: 0), canSend: canSend, reduceMotion: reduceMotion)
}

struct SwipeTransitionTests {
    /// 閾值＝100 px／displayScale；恰等於閾值＝取消（嚴格比較）
    @Test(arguments: [CGFloat(1), 2, 3])
    func thresholdIsHundredPixels(scale: CGFloat) {
        let threshold = 100 / scale
        var exact = swipe(scale: scale)
        #expect(released(&exact, -threshold) == .returnToRest)
        var over = swipe(scale: scale)
        #expect(released(&over, -threshold - 0.01) == .send(.next))
    }

    /// 左甩＝下一首、右甩＝上一首；放手當下就送，進入抬臂段
    @Test func sendsOnReleaseAndLifts() {
        var left = swipe()
        #expect(released(&left, -80) == .send(.next))
        #expect(left.phase == .lifting(.next, ready: false))
        #expect(left.armLifted && left.isTransitioning)
        var right = swipe()
        #expect(released(&right, 80) == .send(.previous))
    }

    /// 不能送（無連線、Music 不可用）＝視同未過閾值：不抬臂、不凍結
    @Test func cannotSendReturnsToRest() {
        var t = swipe()
        #expect(released(&t, -80, canSend: false) == .returnToRest)
        #expect(t.phase == .returning && !t.armLifted && !t.isTransitioning)
        #expect(t.timerFinished() == nil && t.phase == .idle)
    }

    /// 方向鎖：首次移動 |dx| ≤ |dy| 鎖為縱向，整個手勢都不處理
    @Test func verticalLockIgnoresGesture() {
        var t = swipe()
        t.dragChanged(CGSize(width: 3, height: 3))
        #expect(t.phase == .ignoringVertical)
        t.dragChanged(CGSize(width: -300, height: 3))
        #expect(t.dragEnded(CGSize(width: -300, height: 3), canSend: true, reduceMotion: false) == nil && t.phase == .idle)
    }

    /// 回覆先於抬臂計時：記下，計時到才決定
    @Test func readyBeforeLiftTimer() {
        var t = swipe()
        released(&t)
        #expect(t.ready() == nil && t.phase == .lifting(.next, ready: true))
        #expect(t.timerFinished() == .decide)
    }

    /// 回覆晚於抬臂計時：先等，回覆到才決定
    @Test func readyAfterLiftTimer() {
        var t = swipe()
        released(&t)
        #expect(t.timerFinished() == nil && t.phase == .awaiting(.next))
        #expect(t.armLifted)
        #expect(t.ready() == .decide)
    }

    /// 分路：同曲／無曲＝直接回 idle；同專輯＝換標籤；異專輯＝收碟→換封套→抽碟
    @Test func decideBranches() {
        for branch in [SwipeTransition.Branch.sameTrack, .noCurrent] {
            var t = swipe()
            released(&t)
            _ = t.timerFinished()
            t.decide(branch)
            #expect(t.phase == .idle)
        }
        var same = swipe()
        released(&same)
        _ = same.timerFinished()
        same.decide(.sameAlbum)
        #expect(same.phase == .relabeling && same.armLifted)
        #expect(same.timerFinished() == nil && same.phase == .idle && !same.armLifted)

        var other = swipe()
        released(&other, 80)
        _ = other.timerFinished()
        other.decide(.newAlbum)
        var phases = [other.phase]
        while other.phase != .idle {
            _ = other.timerFinished()
            phases.append(other.phase)
        }
        #expect(phases == [.clearing(.previous), .sheathing(.previous), .exchanging(.previous), .drawing(.previous),
                           .placing(.previous), .idle])
    }

    /// Reduce Motion：不抬臂、不煞停；非同曲＝交叉淡化
    @Test func reduceMotionCrossfades() {
        var t = swipe()
        released(&t, reduceMotion: true)
        #expect(!t.armLifted && t.isTransitioning)
        _ = t.timerFinished()
        t.decide(.newAlbum)
        #expect(t.phase == .crossfading && !t.presentation.showsIncomingGroup)
        #expect(t.timerFinished() == nil && t.phase == .idle)
        var same = swipe()
        released(&same, reduceMotion: true)
        _ = same.timerFinished()
        same.decide(.sameTrack)
        #expect(same.phase == .idle)
    }

    /// 在途再甩（過閾值、任一方向）：只加速，不送第二個指令；未過閾值忽略
    @Test func reswipeOnlyAccelerates() {
        var t = swipe()
        released(&t)
        #expect(t.dragEnded(CGSize(width: -10, height: 0), canSend: true, reduceMotion: false) == nil && !t.accelerated)
        #expect(t.dragEnded(CGSize(width: 80, height: 0), canSend: true, reduceMotion: false) == .accelerate && t.accelerated)
        #expect(t.dragEnded(CGSize(width: -80, height: 0), canSend: true, reduceMotion: false) == nil)
        #expect(t.phase == .lifting(.next, ready: false))
    }

    /// 各段時長；加速後進入的段 ×0.4；idle／拖動／等待沒有計時
    @Test func durations() {
        var t = swipe()
        #expect(t.timedDuration == nil)
        released(&t)
        #expect(t.timedDuration == .milliseconds(350))
        _ = t.timerFinished()
        #expect(t.timedDuration == nil)
        t.decide(.newAlbum)
        #expect(t.timedDuration == .milliseconds(150))
        _ = t.dragEnded(CGSize(width: 80, height: 0), canSend: true, reduceMotion: false)
        _ = t.timerFinished()
        #expect(t.timedDuration == .milliseconds(64))   // sheathing 160 × 0.4
        var expected: [Duration] = [.milliseconds(350), .milliseconds(200), .milliseconds(150), .milliseconds(160), .milliseconds(330),
                                    .milliseconds(200), .milliseconds(150), .milliseconds(250), .milliseconds(400)]
        let phases: [SwipeTransition.Phase] = [.lifting(.next, ready: false), .relabeling, .clearing(.next), .sheathing(.next),
                                               .exchanging(.next), .drawing(.next), .placing(.next), .crossfading, .returning]
        for phase in phases {
            #expect(SwipeTransition.duration(of: phase, accelerated: false) == expected.removeFirst())
        }
    }

    /// 斷線／關閉唱機：任一階段回 idle、清加速
    @Test func cancelReturnsToIdle() {
        var t = swipe()
        released(&t)
        _ = t.dragEnded(CGSize(width: 80, height: 0), canSend: true, reduceMotion: false)
        t.cancel()
        #expect(t.phase == .idle && !t.accelerated && !t.isBusy)
    }

    /// 過時訊號：不在對應階段時一律忽略
    @Test func staleSignalsAreIgnored() {
        var t = swipe()
        #expect(t.ready() == nil && t.timerFinished() == nil)
        t.decide(.newAlbum)
        #expect(t.phase == .idle)
        released(&t)
        _ = t.timerFinished()
        t.decide(.sameAlbum)
        #expect(t.ready() == nil && t.phase == .relabeling)
    }

    /// 拖動中封面跟手：向右放大 1.5、向左縮小 1.5，夾在 1.4 倍容器寬；其他階段 0
    @Test func dragOffset() {
        var t = swipe()
        t.dragChanged(CGSize(width: 30, height: 0))
        #expect(t.coverOffset(containerWidth: 1000) == 45)
        t.dragChanged(CGSize(width: -30, height: 0))
        #expect(t.coverOffset(containerWidth: 1000) == -20)
        t.dragChanged(CGSize(width: -5000, height: 0))
        #expect(abs(t.coverOffset(containerWidth: 1000) + 1400 / 1.5) < 1e-9)
        _ = t.dragEnded(CGSize(width: -80, height: 0), canSend: true, reduceMotion: false)
        #expect(t.coverOffset(containerWidth: 1000) == 0)
    }

    /// 異專輯展示：舊組往甩動方向離場、新組從另一側進場；唱片位置、層級與封套重疊那塊的透明度
    @Test func newAlbumPresentation() {
        var t = swipe()
        released(&t, -80)
        _ = t.timerFinished()
        t.decide(.newAlbum)
        var seen: [SwipeTransition.Presentation] = []
        while t.phase != .idle {
            seen.append(t.presentation)
            _ = t.timerFinished()
        }
        // v2.1 T6（使用者選 ⑦）：封套先沿斜軸讓開＋唱片對軸（唱片在上）→ 不重疊時換到下層、沿斜軸收進；抽碟反向。
        // 換層只發生在 clearing→sheathing 與 drawing→placing 的交界，那一刻兩者不重疊
        #expect(seen.map(\.outgoingSlot) == [.aligned, .sleeve, .sleeve, .sleeve, .sleeve])
        #expect(seen.map(\.outgoingSleeveAside) == [true, true, true, true, true])
        #expect(seen.map(\.outgoingRecordBelowCover) == [false, true, true, true, true])
        #expect(seen.map(\.incomingSlot) == [.sleeve, .sleeve, .sleeve, .aligned, .platter])
        #expect(seen.map(\.incomingSleeveAside) == [true, true, true, true, false])
        #expect(seen.map(\.incomingRecordBelowCover) == [true, true, true, true, false])
        // 唱片在封套內＝封套必定讓開（`recordOrigin(.sleeve)` 以讓開後的封套中心為準）
        #expect(seen.allSatisfy { ($0.outgoingSlot != .sleeve || $0.outgoingSleeveAside) && ($0.incomingSlot != .sleeve || $0.incomingSleeveAside) })
        #expect(seen.map(\.outgoingOffset) == [0, 0, -1, -1, -1])
        #expect(seen.map(\.incomingOffset) == [1, 1, 0, 0, 0])
        #expect(seen.map(\.backgroundFromIncoming) == [false, false, true, true, true])
        #expect(seen.map(\.showsIncomingGroup) == [true, true, true, true, true])
        var right = swipe()
        released(&right, 80)
        _ = right.timerFinished()
        right.decide(.newAlbum)
        _ = right.timerFinished(); _ = right.timerFinished()
        #expect(right.presentation.outgoingOffset == 1 && right.presentation.incomingOffset == 0)
        #expect(swipe().presentation == .resting)
        let resting = SwipeTransition.Presentation.resting
        #expect(resting.outgoingSlot == .platter && !resting.outgoingSleeveAside && !resting.outgoingRecordBelowCover)
    }
}

struct SwipeBranchTests {
    typealias B = SwipeTransition.Branch
    static let a = "00000000000000aa", b = "00000000000000bb", t1 = "0000000000000001", t2 = "0000000000000002"

    /// 依序：目前無曲 → noCurrent；甩動前無曲 → newAlbum；同曲 → sameTrack；兩側專輯都有且相等 → sameAlbum；其餘 → newAlbum
    @Test(arguments: [
        (t1, a, nil, a, B.noCurrent), (nil, nil, nil, nil, .noCurrent), (nil, nil, t1, a, .newAlbum),
        (t1, a, t1, a, .sameTrack), (t1, nil, t1, nil, .sameTrack), (t1, a, t1, b, .sameTrack),
        (t1, a, t2, a, .sameAlbum), (t1, a, t2, b, .newAlbum),
        (t1, nil, t2, nil, .newAlbum), (t1, a, t2, nil, .newAlbum), (t1, nil, t2, a, .newAlbum),
    ] as [(String?, String?, String?, String?, B)])
    func branch(outgoingTrack: String?, outgoingAlbum: String?, currentTrack: String?, currentAlbum: String?, expected: B) {
        #expect(SwipeTransition.branch(outgoingTrack: outgoingTrack, outgoingAlbum: outgoingAlbum,
                                       currentTrack: currentTrack, currentAlbum: currentAlbum) == expected)
    }
}
