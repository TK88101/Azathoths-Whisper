import CoreGraphics
import Testing

@testable import YogSothothsEcho

// S5 T5（sprint-5-detail.md §4.5、D11）：封面套抽出／收回、唱片旋轉與煞停、浮層計時（甩動狀態機見 SwipeTransitionTests）

struct CoverSleeveStateTests {
    /// 點一下：前半段滑出（M），400 ms 後 M 結束、L 取反；動畫中再點忽略
    @Test func twoPhaseTap() {
        var sleeve = CoverSleeveState()
        let r19 = sleeve.tap()
        #expect(r19 && sleeve.isMidway && !sleeve.isFullCover)
        let r20 = sleeve.tap()
        #expect(!r20)
        sleeve.midwayFinished()
        #expect(!sleeve.isMidway && sleeve.isFullCover)
        let r21 = sleeve.tap()
        #expect(r21)
        sleeve.midwayFinished()
        #expect(!sleeve.isFullCover)
    }

    @Test func presentation() {
        var sleeve = CoverSleeveState()
        #expect(sleeve.rotationDegrees == TurntableMetrics.coverTiltDegrees && sleeve.zIndex == 0.5 && sleeve.offsetFraction == 0)
        _ = sleeve.tap()
        #expect(sleeve.offsetFraction == -0.5)
        sleeve.midwayFinished()
        #expect(sleeve.rotationDegrees == 0 && sleeve.zIndex == 2 && sleeve.offsetFraction == 0)
    }
}

struct RecordSpinTests {
    /// 20 s 一圈（18°/s）；暫停凍結、恢復從當前角度續轉；重複通知同一狀態不重設錨點
    @Test func spinFreezeAndResume() {
        var spin = RecordSpin()
        #expect(spin.angle(at: 5) == 0)
        spin.update(spinning: true, at: 10)
        #expect(abs(spin.angle(at: 15) - 90) < 1e-9)
        spin.update(spinning: true, at: 15)
        #expect(abs(spin.angle(at: 20) - 180) < 1e-9)
        spin.update(spinning: false, at: 20)
        #expect(abs(spin.angle(at: 100) - 180) < 1e-9)
        spin.update(spinning: true, at: 100)
        #expect(abs(spin.angle(at: 105) - 270) < 1e-9)
        #expect(abs(spin.angle(at: 110) - 0) < 1e-9)   // 取模 360
    }

    /// 煞停（G7）：350 ms 內線性減速到 0，角度連續；停住後不再動；從靜止開始煞停＝不動
    @Test func brakeDeceleratesContinuously() {
        var spin = RecordSpin()
        spin.update(.spinning, at: 0)
        spin.update(.braking, at: 1)                     // 此刻 18°
        #expect(abs(spin.angle(at: 1) - 18) < 1e-9)
        let v = RecordSpin.degreesPerSecond, t = RecordSpin.brakeSeconds
        #expect(abs(spin.angle(at: 1 + t / 2) - (18 + v * t / 2 - v * (t / 2) * (t / 2) / (2 * t))) < 1e-9)
        let stop = 18 + v * t / 2
        #expect(abs(spin.angle(at: 1 + t) - stop) < 1e-9)
        #expect(abs(spin.angle(at: 50) - stop) < 1e-9)
        spin.update(.braking, at: 2)                     // 重複通知不重設
        #expect(abs(spin.angle(at: 3) - stop) < 1e-9)
        spin.update(.spinning, at: 10)                   // 從停住的角度續轉
        #expect(abs(spin.angle(at: 11) - (stop + v)) < 1e-9)
        var still = RecordSpin()
        still.update(.braking, at: 0)
        #expect(still.angle(at: 5) == 0)
    }

    /// 煞停途中再起轉（收尾中再甩的反向）：從當下角度續轉，不跳
    @Test func spinResumesMidBrake() {
        var spin = RecordSpin()
        spin.update(.spinning, at: 0)
        spin.update(.braking, at: 1)
        let mid = spin.angle(at: 1.1)
        spin.update(.spinning, at: 1.1)
        #expect(abs(spin.angle(at: 1.1) - mid) < 1e-9)
        spin.update(.still, at: 2)
        #expect(abs(spin.angle(at: 9) - spin.angle(at: 2)) < 1e-9)
    }
}

@MainActor
struct TurntableOverlayTests {
    /// 顯示後 5 s 自動隱藏；再次觸發重新計時；手動切換可關
    @Test func autoHidesAfterFiveSecondsAndRestarts() async {
        let sleeper = ManualSleeper()
        let overlay = TurntableOverlayState(sleep: { await sleeper.sleep($0) })
        overlay.toggle()
        #expect(overlay.isVisible)
        await settleMain()
        #expect(await sleeper.requested == [.seconds(5)])
        overlay.poke()                       // 例如換樣式：重新計時
        await settleMain()
        await sleeper.wake()                 // 兩個計時都醒來：舊的作廢、新的生效
        await settleMain()
        #expect(!overlay.isVisible)
        overlay.toggle()
        overlay.toggle()
        #expect(!overlay.isVisible)
    }

    /// DEBUG 調整面板拖滑桿期間不得自動隱藏：編輯中停計時，放手重新計時 5 s（v2.1 T8）
    @Test func editingPausesAutoHide() async {
        let sleeper = QueueSleeper()
        let overlay = TurntableOverlayState(sleep: { await sleeper.sleep($0) })
        overlay.toggle()
        await settleMain()
        overlay.setEditing(true)
        await settleMain()
        await sleeper.wakeOldest()           // 編輯前的計時醒來：已作廢
        await settleMain()
        #expect(overlay.isVisible)
        overlay.setEditing(false)
        await settleMain()
        #expect(await sleeper.waiting == 1)
        await sleeper.wakeOldest()
        await settleMain()
        #expect(!overlay.isVisible)
    }

    /// 舊計時醒來不得把新一輪顯示關掉（逐個喚醒，先醒舊的）
    @Test func staleTimerDoesNotHideNewShow() async {
        let sleeper = QueueSleeper()
        let overlay = TurntableOverlayState(sleep: { await sleeper.sleep($0) })
        overlay.toggle()
        await settleMain()
        overlay.toggle()   // 關
        overlay.toggle()   // 再開：新計時
        await settleMain()
        #expect(await sleeper.waiting == 2)
        await sleeper.wakeOldest()
        await settleMain()
        #expect(overlay.isVisible)
        await sleeper.wakeOldest()
        await settleMain()
        #expect(!overlay.isVisible)
    }
}

/// 逐個喚醒的 sleep 替身（先進先出）
actor QueueSleeper {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func sleep(_ duration: Duration) async { await withCheckedContinuation { waiters.append($0) } }
    func wakeOldest() { if !waiters.isEmpty { waiters.removeFirst().resume() } }
    var waiting: Int { waiters.count }
}
