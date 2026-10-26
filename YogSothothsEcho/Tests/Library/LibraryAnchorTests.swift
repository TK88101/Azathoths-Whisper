import Foundation
import Testing

@testable import YogSothothsEcho

// S6 #6-1 g 版 T6（s6-61-g-perf-wear.md §5.6、CR-027）：位置記憶——重開回上次位置、清空搜尋回搜尋前、與播放無關；
// 只有使用者造成的移動更新 anchor；寫盤只在停下／搜尋結束／進背景 flush
@MainActor
struct LibraryAnchorTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("anchor-\(UUID().uuidString)")

    func model(_ store: SettingsStore) -> LibraryViewModel {
        LibraryViewModel(store: store, artworkDirectory: directory, sleep: { _ in await Task.yield() })
    }

    @Test func launchRestoresStoredAnchor() {
        let store = InMemorySettingsStore()
        store.set("x", forKey: LibraryViewModel.anchorKey)
        let vm = model(store)
        #expect(vm.browseCenterID == "x" && vm.pendingRestore == "x")
    }

    @Test func userMoveIsInMemoryUntilFlush() {
        let store = InMemorySettingsStore()
        let vm = model(store)
        vm.userMovedAnchor("a", )
        #expect(vm.browseCenterID == "a" && store.string(forKey: LibraryViewModel.anchorKey) == nil)
        vm.flushBrowseAnchor()
        #expect(store.string(forKey: LibraryViewModel.anchorKey) == "a")
    }

    @Test func searchSessionRemembersPreSearchAnchorOnce() {
        let store = InMemorySettingsStore()
        let vm = model(store)
        vm.userMovedAnchor("b", )
        vm.query = "abc"
        vm.userMovedAnchor("r1", )
        vm.query = "abcd"
        vm.flushBrowseAnchor()
        #expect(store.string(forKey: LibraryViewModel.anchorKey) == "b")
        vm.query = ""
        #expect(vm.pendingRestore == "b" && vm.browseCenterID == "b")
        #expect(store.string(forKey: LibraryViewModel.anchorKey) == "b")
    }

    @Test func whitespaceQueryDoesNotStartSession() {
        let vm = model(InMemorySettingsStore())
        vm.userMovedAnchor("b", )
        vm.query = "   "
        vm.userMovedAnchor("c", )
        vm.query = ""
        #expect(vm.pendingRestore == nil && vm.browseCenterID == "c")
    }

    @Test func scrollTargetConsumesRestoreOnceAndFallsBack() {
        let store = InMemorySettingsStore()
        store.set("gone", forKey: LibraryViewModel.anchorKey)
        let vm = model(store)
        #expect(vm.scrollTarget(ids: [], previousCenter: nil) == nil)
        #expect(vm.pendingRestore == "gone", "空清單不消耗待還原")
        #expect(vm.scrollTarget(ids: ["a", "b"], previousCenter: "b") == "a", "待還原不在清單＝第一張")
        #expect(vm.pendingRestore == nil)
        #expect(vm.scrollTarget(ids: ["a", "b"], previousCenter: "b") == "b")
    }

    /// Codex 確認輪 P1：清單分頁載入中、目標還沒到＝先不消耗待還原（照規則停在原處），目標到了才還原
    @Test func restoreWaitsWhileCatalogIsStillLoading() {
        let store = InMemorySettingsStore()
        store.set("late", forKey: LibraryViewModel.anchorKey)
        let vm = model(store)
        #expect(vm.scrollTarget(ids: ["a", "b"], previousCenter: nil, listComplete: false) == "a")
        #expect(vm.pendingRestore == "late")
        #expect(vm.scrollTarget(ids: ["a", "b", "late"], previousCenter: "a", listComplete: false) == "late")
        #expect(vm.pendingRestore == nil)
    }

    @Test func restoreFallsBackOnlyWhenListComplete() {
        let store = InMemorySettingsStore()
        store.set("gone", forKey: LibraryViewModel.anchorKey)
        let vm = model(store)
        #expect(vm.scrollTarget(ids: ["a"], previousCenter: nil, listComplete: true) == "a")
        #expect(vm.pendingRestore == nil)
    }

    @Test func queryChangeIsConsumedByNextScrollTarget() {
        let vm = model(InMemorySettingsStore())
        vm.query = "abc"
        #expect(vm.queryChangedSinceScroll)
        #expect(vm.scrollTarget(ids: ["r1", "r2"], previousCenter: "r2") == "r1", "搜尋改變＝第一張")
        #expect(!vm.queryChangedSinceScroll)
        #expect(vm.scrollTarget(ids: ["r1", "r2"], previousCenter: "r2") == "r2")
    }

    @Test func userScrollGateFlushesOnEnd() {
        let store = InMemorySettingsStore()
        store.set("x", forKey: LibraryViewModel.anchorKey)
        let vm = model(store)
        vm.userScrollBegan()
        #expect(vm.isUserScrolling && vm.pendingRestore == nil)
        vm.userMovedAnchor("m")
        vm.userScrollEnded()
        #expect(!vm.isUserScrolling && store.string(forKey: LibraryViewModel.anchorKey) == "m")
    }

    @Test func userTakeoverCancelsPendingRestore() {
        let store = InMemorySettingsStore()
        store.set("x", forKey: LibraryViewModel.anchorKey)
        let vm = model(store)
        vm.userStepped(to: "v")
        #expect(vm.pendingRestore == nil && vm.browseCenterID == "v")
    }

    @Test func noStoreMeansNoRestore() {
        let vm = LibraryViewModel(artworkDirectory: directory, sleep: { _ in await Task.yield() })
        #expect(vm.pendingRestore == nil)
        vm.userMovedAnchor("a", )
        vm.flushBrowseAnchor()
    }
}
