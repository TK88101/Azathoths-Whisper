import Testing
@testable import YogSothothsEcho

// CR-024（s6-61-f8f9-shell.md §5.4）：側封／小圖切換——預設側封、存讀、未知值回預設；左鍵圖示＝點了會變成的樣子；
// 小圖欄數與 anchor 帶入
struct BrowseLayoutTests {
    @Test func toggleTargetsTheOtherLayout() {
        #expect(BrowseLayout.spines.toggled == .grid)
        #expect(BrowseLayout.grid.toggled == .spines)
    }

    /// 圖示顯示點了會變成的樣子：側封時四方塊、小圖時側封
    @Test func buttonIconShowsTheTarget() {
        #expect(BrowseLayout.spines.buttonIcon == .squares)
        #expect(BrowseLayout.grid.buttonIcon == .spines)
    }

    /// 欄數＝max(3, floor((寬−2·44＋28)/(220＋28)))：13 吋 5 欄、11 吋 4 欄
    @Test(arguments: [(1376.0, 5), (1210.0, 4), (1032.0, 3), (700.0, 3)])
    func gridColumnsFollowTheWidth(width: Double, columns: Int) {
        #expect(GridBrowser.columns(width: width) == columns)
    }

    /// 兩種展示互帶的 anchor：規則統一在 `BrowserScrollAnchor.target`（g 版 simcodex R2 刪除重複的 `GridBrowser.anchor`）
    @Test func anchorFallsBackToFirstWhenMissing() {
        #expect(BrowserScrollAnchor.target(previousCenter: "b", newIDs: ["a", "b", "c"], queryChanged: false) == "b")
        #expect(BrowserScrollAnchor.target(previousCenter: "z", newIDs: ["a", "b"], queryChanged: false) == "a")
        #expect(BrowserScrollAnchor.target(previousCenter: nil, newIDs: ["a"], queryChanged: false) == "a")
        #expect(BrowserScrollAnchor.target(previousCenter: "a", newIDs: [], queryChanged: false) == nil)
    }
}

@MainActor
struct BrowseLayoutViewModelTests {
    @Test func defaultsToSpinesAndPersists() {
        let store = InMemorySettingsStore()
        let model = BrowseLayoutViewModel(store: store)
        #expect(model.layout == .spines)
        model.toggle()
        #expect(store.string(forKey: "browse.layout") == "grid")
        #expect(BrowseLayoutViewModel(store: store).layout == .grid)
    }

    @Test func unknownStoredValueFallsBackToSpines() {
        let store = InMemorySettingsStore()
        store.set("list", forKey: BrowseLayoutViewModel.storageKey)
        #expect(BrowseLayoutViewModel(store: store).layout == .spines)
    }
}
