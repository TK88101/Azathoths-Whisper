import CoreGraphics
import Foundation
import Testing

@testable import YogSothothsEcho

// S6 T9（sprint-6-detail.md §4.8、D9）：播放列唱機鈕＝整頁往左、唱機從右滑入（0.35 s）→ 唱片自封套抽出（G7 的 drawing 0.2 s、
// placing 0.15 s 兩段，同一套位置與換層）→ shown；關閉＝反向滑出、唱片停在關閉當下的位置隨頁面滑走
struct TurntableEntranceTests {
    @Test func phasesRunSlideThenDrawThenPlace() {
        #expect(TurntableEntrance.next(after: .sliding, reduceMotion: false) == .drawing)
        #expect(TurntableEntrance.next(after: .drawing, reduceMotion: false) == .placing)
        #expect(TurntableEntrance.next(after: .placing, reduceMotion: false) == nil)
        #expect(TurntableEntrance.duration(of: .sliding, reduceMotion: false) == .milliseconds(350))
        #expect(TurntableEntrance.duration(of: .drawing, reduceMotion: false) == SwipeTransition.duration(of: .drawing(.next), accelerated: false))
        #expect(TurntableEntrance.duration(of: .placing, reduceMotion: false) == SwipeTransition.duration(of: .placing(.next), accelerated: false))
    }

    /// 抽唱片只在滑完之後：滑動中唱片在封套內、封套下層；抽出段＝G7 drawing、放上段＝G7 placing（同一組位置值）
    @Test func recordFollowsTheG7DrawAndPlace() {
        let sliding = TurntableEntrance.presentation(.sliding, reduceMotion: false)
        #expect(sliding.outgoingSlot == .sleeve && sliding.outgoingRecordBelowCover && sliding.outgoingSleeveAside)
        #expect(!sliding.showsIncomingGroup && sliding.outgoingOffset == 0)
        let drawing = TurntableEntrance.presentation(.drawing, reduceMotion: false)
        #expect(drawing.outgoingSlot == .aligned && drawing.outgoingRecordBelowCover && drawing.outgoingSleeveAside)
        let placing = TurntableEntrance.presentation(.placing, reduceMotion: false)
        #expect(placing.outgoingSlot == .platter && !placing.outgoingRecordBelowCover && !placing.outgoingSleeveAside)
    }

    /// 放上段的位置＝G7 idle：轉 shown 那一幀不跳
    @Test func placedRecordEqualsIdleScene() {
        #expect(TurntableEntrance.presentation(.placing, reduceMotion: false) == SwipeTransition(displayScale: 2).presentation)
    }

    @Test func pageOffsets() {
        let w: CGFloat = 1376
        #expect(TurntableEntrance.slideTarget(.hidden) == 1 && TurntableEntrance.slideTarget(.leaving(record: .resting)) == 1)
        #expect(TurntableEntrance.slideTarget(.entering(.sliding)) == 0 && TurntableEntrance.slideTarget(.shown) == 0)
        #expect(TurntableEntrance.offsets(slide: 1, width: w, reduceMotion: false) == .init(library: 0, turntable: w, turntableOpacity: 1))
        #expect(TurntableEntrance.offsets(slide: 0, width: w, reduceMotion: false) == .init(library: -w, turntable: 0, turntableOpacity: 1))
        #expect(TurntableEntrance.offsets(slide: 0.5, width: w, reduceMotion: false) == .init(library: -w / 2, turntable: w / 2, turntableOpacity: 1))
    }

    /// Reduce Motion：不位移、只淡入淡出 0.25 s；唱片直接在唱盤上（不抽）
    @Test func reduceMotionCrossFades() {
        let w: CGFloat = 1376
        #expect(TurntableEntrance.offsets(slide: 0, width: w, reduceMotion: true) == .init(library: 0, turntable: 0, turntableOpacity: 1))
        #expect(TurntableEntrance.offsets(slide: 1, width: w, reduceMotion: true) == .init(library: 0, turntable: 0, turntableOpacity: 0))
        #expect(TurntableEntrance.presentation(.sliding, reduceMotion: true) == .resting)
        #expect(TurntableEntrance.next(after: .sliding, reduceMotion: true) == nil)
        #expect(TurntableEntrance.duration(of: .sliding, reduceMotion: true) == .milliseconds(250))
    }

    @Test func layerFlags() {
        #expect(!TurntableLayerState.hidden.isPresent)
        #expect(TurntableLayerState.entering(.drawing).isPresent && TurntableLayerState.leaving(record: .resting).isPresent)
        #expect(!TurntableLayerState.shown.blocksInput && !TurntableLayerState.hidden.blocksInput)
        #expect(TurntableLayerState.entering(.placing).blocksInput && TurntableLayerState.leaving(record: .resting).blocksInput)
    }
}

/// 唱機層的生命週期（VM 是唯一 owner）：世代守衛、抽片中關閉、G7 換片中關閉再開、斷線
@MainActor
struct TurntableLayerTests {
    let gate = SleepGate()
    let nowPlaying = NowPlayingViewModel()

    func model() -> TurntableViewModel {
        let gate = gate
        return TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: InMemorySettingsStore(), displayScale: 2, artwork: { _ in nil },
                                  palette: { _ in .fallback }, sleep: { _ in }, transitionSleep: { _ in await gate.wait() })
    }

    func step() async {
        for _ in 0..<200 where await gate.pending == 0 { await Task.yield() }
        await gate.fire()
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func openWalksToShownAndCloseSlidesOut() async {
        let m = model()
        m.open(reduceMotion: false)
        #expect(m.layer == .entering(.sliding))
        #expect(m.scenePresentation == TurntableEntrance.presentation(.sliding, reduceMotion: false))
        await step()
        #expect(m.layer == .entering(.drawing))
        await step()
        #expect(m.layer == .entering(.placing))
        await step()
        #expect(m.layer == .shown && m.scenePresentation == .resting)
        m.close(reduceMotion: false)
        #expect(m.layer == .leaving(record: .resting))
        await step()
        #expect(m.layer == .hidden)
    }

    /// 抽片中關閉：.leaving 帶關閉當下的唱片快照（不跳回唱盤）；舊世代的計時醒來不改狀態
    @Test func closingWhileDrawingFreezesTheRecord() async {
        let m = model()
        m.open(reduceMotion: false)
        await step()
        #expect(m.layer == .entering(.drawing))
        m.close(reduceMotion: false)
        let snapshot = TurntableEntrance.presentation(.drawing, reduceMotion: false)
        #expect(m.layer == .leaving(record: snapshot) && m.scenePresentation == snapshot)
        await step()
        #expect(m.layer == .hidden)
    }

    /// 滑完才轉 hidden；hidden 之前再按唱機鈕不反向（無入口），hidden 之後從頭進場
    @Test func reopenOnlyAfterHidden() async {
        let m = model()
        m.open(reduceMotion: false)
        m.close(reduceMotion: false)
        m.open(reduceMotion: false)
        #expect(m.layer == .leaving(record: TurntableEntrance.presentation(.sliding, reduceMotion: false)))
        await step()
        #expect(m.layer == .hidden)
        m.open(reduceMotion: false)
        #expect(m.layer == .entering(.sliding))
    }

    /// 進場中手勢被忽略、model.swipe 不被寫入
    @Test func gesturesAreIgnoredWhileEntering() async {
        let m = model()
        m.open(reduceMotion: false)
        m.swipeChanged(CGSize(width: -300, height: 0))
        m.swipeEnded(CGSize(width: -300, height: 0), reduceMotion: false)
        #expect(m.swipe.phase == .idle)
        #expect(!m.tapSleeve())
    }

    /// 進場中唱臂停在原位（放上唱片後才落臂）
    @Test func armRestsWhileEntering() {
        let m = model()
        m.open(reduceMotion: false)
        #expect(m.armAngle() == ResolvedTurntableSkin.classic.restDegrees)
    }

    /// 斷線（殼層換連線畫面）：直接 hidden，舊計時作廢
    @Test func hideImmediatelyCancelsEverything() async {
        let m = model()
        m.open(reduceMotion: false)
        m.hideImmediately()
        #expect(m.layer == .hidden)
        await step()
        #expect(m.layer == .hidden)
    }

    @Test func reduceMotionEntersInOneFade() async {
        let m = model()
        m.open(reduceMotion: true)
        #expect(m.scenePresentation == .resting)
        await step()
        #expect(m.layer == .shown)
    }
}
