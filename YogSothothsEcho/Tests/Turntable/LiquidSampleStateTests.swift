#if LIQUID_SAMPLE
import Foundation
import Testing

@testable import YogSothothsEcho

// CR-038 L-T3（yse-liquid-vinyl-sample.md v0.4 §4.2／§4.4）：預覽四態驅動器、每張唱片的液體狀態 store

struct LiquidPreviewDriverTests {
    /// 自動循環：靜止 3 s → 慢轉 6 s → 正常轉 8 s → 剛停 6 s → 回到靜止
    @Test func autoCycleFollowsPlannedTimeline() {
        var driver = LiquidPreviewDriver(at: 0)
        let expectations: [(Double, LiquidPreviewPhase)] = [
            (1, .still), (2.99, .still), (3.01, .slow), (8.99, .slow), (9.01, .normal),
            (16.99, .normal), (17.01, .justStopped), (22.99, .justStopped), (23.01, .still),
        ]
        for (time, phase) in expectations {
            _ = driver.tick(at: time)
            #expect(driver.phase == phase, "t \(time)")
        }
    }

    /// 一整輪的盤角＝4.5×6 ＋ 18×8；跨相位的一幀分段積分
    @Test func discAngleIntegratesAcrossPhaseBoundaries() {
        var driver = LiquidPreviewDriver(at: 0)
        _ = driver.tick(at: 2.9)
        #expect(abs(driver.tick(at: 3.1) - 0.1 * 4.5) < 1e-9)
        var a = LiquidPreviewDriver(at: 0)
        var angle = 0.0
        var t = 0.0
        while t < 23 { t = min(23, t + 1.0 / 120); angle = a.tick(at: t) }
        #expect(abs(angle - (4.5 * 6 + 18 * 8)) < 1e-6)
        var b = LiquidPreviewDriver(at: 0)
        #expect(abs(b.tick(at: 23) - (4.5 * 6 + 18 * 8)) < 1e-9)
    }

    @Test func manualSelectionHoldsThePhase() {
        var driver = LiquidPreviewDriver(at: 0)
        driver.select(.normal, at: 1)
        #expect(!driver.isAuto)
        _ = driver.tick(at: 100)
        #expect(driver.phase == .normal)
        #expect(abs(driver.discAngle - 99 * 18) < 1e-9)
    }

    /// 停著時點「剛停」：先正常轉 8 s 再停（否則沒有可看的停轉）
    @Test func selectingJustStoppedFromRestSpinsUpFirst() {
        var driver = LiquidPreviewDriver(at: 0)
        driver.select(.justStopped, at: 1)
        #expect(driver.phase == .normal)
        _ = driver.tick(at: 8.9)
        #expect(driver.phase == .normal)
        _ = driver.tick(at: 9.1)
        #expect(driver.phase == .justStopped)
        _ = driver.tick(at: 60)
        #expect(driver.phase == .justStopped)
        #expect(abs(driver.discAngle - 8 * 18) < 1e-9)
    }

    @Test func selectingJustStoppedWhileSpinningStopsImmediately() {
        var driver = LiquidPreviewDriver(at: 0)
        driver.select(.slow, at: 0)
        driver.select(.justStopped, at: 2)
        #expect(driver.phase == .justStopped)
        _ = driver.tick(at: 5)
        #expect(abs(driver.discAngle - 2 * 4.5) < 1e-9)
    }

    /// 重新打開自動：從目前相位重新計時
    @Test func resumingAutoRestartsCurrentPhaseTimer() {
        var driver = LiquidPreviewDriver(at: 0)
        driver.select(.slow, at: 0)
        _ = driver.tick(at: 50)
        driver.setAuto(true, at: 50)
        _ = driver.tick(at: 55.9)
        #expect(driver.phase == .slow)
        _ = driver.tick(at: 56.1)
        #expect(driver.phase == .normal)
    }

    @Test func timeGoingBackwardsIsIgnored() {
        var driver = LiquidPreviewDriver(at: 10)
        _ = driver.tick(at: 9)
        #expect(driver.discAngle == 0)
        #expect(driver.phase == .still)
    }
}

@MainActor
struct LiquidMotionStoreTests {
    private func makeStore() -> LiquidMotionStore { LiquidMotionStore(schedule: { $0() }) }

    @Test func createsKeepsAndReleasesPerTrackState() {
        let store = makeStore()
        _ = store.frame(for: "a", rawAngle: 0, at: 0, preset: .liquid, reduceMotion: false)
        #expect(store.count == 1)
        // 保留：同一張唱片繼續積分（等速轉 1 s 後有落後）
        var t = 0.0
        while t < 1 { t += 1.0 / 120; _ = store.frame(for: "a", rawAngle: (18 * t).truncatingRemainder(dividingBy: 360), at: t, preset: .liquid, reduceMotion: false) }
        #expect(store.frame(for: "a", rawAngle: 18 * t, at: t, preset: .liquid, reduceMotion: false).lag > 0)
        store.release("a")
        #expect(store.count == 0)
        // 釋放後重建：從零開始
        #expect(store.frame(for: "a", rawAngle: 100, at: 2, preset: .liquid, reduceMotion: false).lag == 0)
    }

    /// G7：舊新兩盤共用同一個盤角輸入、狀態各自獨立；並存 ≤ 2（第三張進來淘汰最久沒用的）
    @Test func atMostTwoRecordsCoexist() {
        let store = makeStore()
        _ = store.frame(for: "old", rawAngle: 0, at: 0, preset: .liquid, reduceMotion: false)
        _ = store.frame(for: "new", rawAngle: 0, at: 0.01, preset: .liquid, reduceMotion: false)
        _ = store.frame(for: "old", rawAngle: 1, at: 0.02, preset: .liquid, reduceMotion: false)
        _ = store.frame(for: "third", rawAngle: 1, at: 0.03, preset: .liquid, reduceMotion: false)
        #expect(store.count == 2)
        #expect(store.contains("old"))
        #expect(store.contains("third"))
        #expect(!store.contains("new"))
    }

    /// 盤角每 360° 回繞：store 內部展開，不會把 359°→0° 當成倒轉一圈
    @Test func wrappedAnglesAreUnwrapped() {
        let store = makeStore()
        _ = store.frame(for: "a", rawAngle: 359, at: 0, preset: .liquid, reduceMotion: false)
        let frame = store.frame(for: "a", rawAngle: 0.5, at: 1.0 / 120, preset: .liquid, reduceMotion: false)
        #expect(abs(frame.discAngle - 360.5) < 1e-9)
        #expect(abs(frame.lag) < 2)
    }

    /// 換 preset：以目前盤角重建（液體回到盤上）
    @Test func changingPresetRebuildsState() {
        let store = makeStore()
        var t = 0.0
        while t < 2 { t += 1.0 / 120; _ = store.frame(for: "a", rawAngle: (18 * t).truncatingRemainder(dividingBy: 360), at: t, preset: .liquid, reduceMotion: false) }
        let frame = store.frame(for: "a", rawAngle: (18 * (t + 0.01)).truncatingRemainder(dividingBy: 360), at: t + 0.01, preset: .dramatic, reduceMotion: false)
        #expect(frame.lag == 0)
        #expect(frame.flingGain == LiquidPreset.dramatic.flingGain)
    }

    /// 動畫中＝TimelineView 不可暫停；停轉收斂後才回報可暫停（轉換以 schedule 送出，不在 body 內改狀態）
    @Test func reportsAnimatingUntilSettled() {
        let store = makeStore()
        _ = store.frame(for: "a", rawAngle: 0, at: 0, preset: .subtle, reduceMotion: false)
        #expect(!store.isAnimating("a"))
        var t = 0.0, disc = 0.0
        while t < 3 { t += 1.0 / 120; disc += 18.0 / 120; _ = store.frame(for: "a", rawAngle: disc.truncatingRemainder(dividingBy: 360), at: t, preset: .subtle, reduceMotion: false) }
        #expect(store.isAnimating("a"))
        while t < 30, store.isAnimating("a") { t += 1.0 / 120; _ = store.frame(for: "a", rawAngle: disc.truncatingRemainder(dividingBy: 360), at: t, preset: .subtle, reduceMotion: false) }
        #expect(!store.isAnimating("a"))
        #expect(t < 30)
        store.release("a")
        #expect(!store.isAnimating("a"))
    }

    @Test func reduceMotionPreviewFrameIsRigid() {
        let store = makeStore()
        var t = 0.0, disc = 0.0
        while t < 2 { t += 1.0 / 120; disc += 18.0 / 120; _ = store.frame(for: "a", rawAngle: disc.truncatingRemainder(dividingBy: 360), at: t, preset: .liquid, reduceMotion: false) }
        let frame = store.frame(for: "a", rawAngle: (disc + 0.15).truncatingRemainder(dividingBy: 360), at: t + 1.0 / 120, preset: .liquid, reduceMotion: true)
        #expect(frame.lag == 0)
        #expect(frame.fling == 0)
    }
}
#endif
