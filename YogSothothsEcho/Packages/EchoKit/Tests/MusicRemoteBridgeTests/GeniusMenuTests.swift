#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// CR-030 G3（s6-61-genius.md §4.2 Mac 執行）：Genius 選單項的結構定位與錯誤對照。替身樹＝每個方法一次 AX 呼叫

/// 替身選單節點；index 即 Element
struct FakeNode {
    var role: String
    var cmdChar: String? = nil
    var modifiers: Int? = nil
    var enabled = true
    var children: [Int] = []
}

final class FakeMenuTree: GeniusMenuTree, @unchecked Sendable {
    var nodes: [FakeNode] = []
    var bar: [Int] = []
    /// 每次呼叫前進的秒數（模擬慢 AX）
    var costPerCall: Double = 0
    var failure: GeniusAXFailure?
    /// 第幾次呼叫起丟出 failure（nil＝不丟）
    var failFromCall: Int?
    private(set) var calls = 0
    private(set) var pressed: [Int] = []
    private(set) var enabledReads = 0
    let time: UptimeBox

    init(time: UptimeBox) { self.time = time }

    @discardableResult func add(_ node: FakeNode) -> Int { nodes.append(node); return nodes.count - 1 }

    private func tick() throws(GeniusAXFailure) {
        calls += 1
        time.value += costPerCall
        if let from = failFromCall, calls >= from, let failure { throw failure }
    }

    func topMenus() throws(GeniusAXFailure) -> [Int] { try tick(); return bar }
    func children(_ e: Int) throws(GeniusAXFailure) -> [Int] { try tick(); return nodes[e].children }
    func item(_ e: Int) throws(GeniusAXFailure) -> GeniusMenuItem {
        try tick()
        return GeniusMenuItem(role: nodes[e].role, cmdChar: nodes[e].cmdChar, modifiers: nodes[e].modifiers)
    }
    func isEnabled(_ e: Int) throws(GeniusAXFailure) -> Bool { try tick(); enabledReads += 1; return nodes[e].enabled }
    func press(_ e: Int) { pressed.append(e) }
}

final class HookLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ s: String) { lock.withLock { entries.append(s) } }
    var all: [String] { lock.withLock { entries } }
}

struct GeniusMenuTests {
    let time = UptimeBox(0)
    let tree: FakeMenuTree
    let log = HookLog()
    /// 標準 Music 選單列的 Genius 項
    let genius: Int

    init() {
        tree = FakeMenuTree(time: time)
        genius = Self.standardBar(tree)
    }

    private static let item = GeniusMenuItem.menuItemRole
    private static let menu = GeniusMenuItem.menuRole

    /// 頂層：ミュージック／ファイル／コントロール（Space 播放、⌥Space Genius、⌘→ 下一首）／ウインドウ
    @discardableResult
    static func standardBar(_ tree: FakeMenuTree) -> Int {
        func top(_ items: [FakeNode]) -> Int {
            let ids = items.map { tree.add($0) }
            let menu = tree.add(FakeNode(role: Self.menu, children: ids))
            return tree.add(FakeNode(role: "AXMenuBarItem", children: [menu]))
        }
        let app = top([FakeNode(role: item, cmdChar: "Q", modifiers: 0)])
        let file = top([FakeNode(role: item, cmdChar: "N", modifiers: 0), FakeNode(role: item)])
        let play = FakeNode(role: item, cmdChar: " ", modifiers: 8)
        let next = FakeNode(role: item, cmdChar: "\u{F703}", modifiers: 0)
        let playID = tree.add(play)
        let geniusID = tree.add(FakeNode(role: item, cmdChar: " ", modifiers: 10))
        let nextID = tree.add(next)
        let controlMenu = tree.add(FakeNode(role: Self.menu, children: [playID, geniusID, nextID]))
        let control = tree.add(FakeNode(role: "AXMenuBarItem", children: [controlMenu]))
        let window = top([FakeNode(role: item, cmdChar: "M", modifiers: 0)])
        tree.bar = [app, file, control, window]
        return geniusID
    }

    private func menu(trusted: Bool = true, pid: pid_t? = 42) -> GeniusMenu {
        let tree = self.tree, time = self.time
        let locator = FakeLocator()
        locator.pid = pid
        return GeniusMenu(locator: locator, trusted: { trusted }, makeTree: { _ in tree }, now: { time.value })
    }

    private func press(_ menu: GeniusMenu, prepare: Bool = true, stillWanted: Bool = true) async -> GeniusPress {
        let log = self.log
        return await menu.pressGenius(prepare: { log.append("prepare"); return prepare },
                                      stillWanted: { log.append("alive"); return stillWanted })
    }

    // MARK: 定位

    @Test func uniqueGeniusInControlMenuIsPressedAfterPrepareAndAliveCheck() async {
        #expect(await press(menu()) == .pressed)
        #expect(tree.pressed == [genius])
        #expect(log.all == ["prepare", "alive"])
        #expect(tree.enabledReads == 1)
    }

    @Test func missingGeniusItemIsNotPressed() async {
        tree.nodes[genius].modifiers = nil
        tree.nodes[genius].cmdChar = nil
        #expect(await press(menu()) == .refused(.notApplied))
        #expect(tree.pressed.isEmpty && log.all.isEmpty)
    }

    @Test func twoGeniusItemsAreAmbiguous() async {
        let extra = tree.add(FakeNode(role: GeniusMenuItem.menuItemRole, cmdChar: " ", modifiers: 10))
        let controlMenu = tree.nodes[tree.bar[2]].children[0]
        tree.nodes[controlMenu].children.append(extra)
        #expect(await press(menu()) == .refused(.notApplied))
        #expect(tree.pressed.isEmpty)
    }

    @Test func disabledGeniusIsNotPressed() async {
        tree.nodes[genius].enabled = false
        #expect(await press(menu()) == .refused(.notApplied))
        #expect(tree.pressed.isEmpty)
    }

    @Test(arguments: [(" ", 2), (" ", 0), ("G", 10), (" ", 11)])
    func otherShortcutIsNotGenius(cmdChar: String, modifiers: Int) async {
        tree.nodes[genius].cmdChar = cmdChar
        tree.nodes[genius].modifiers = modifiers
        #expect(await press(menu()) == .refused(.notApplied))
        #expect(tree.pressed.isEmpty)
    }

    @Test func geniusShortcutWithWrongRoleIsNotPressed() async {
        tree.nodes[genius].role = "AXMenuBarItem"
        #expect(await press(menu()) == .refused(.notApplied))
    }

    /// 干擾項：其他頂層選單也有 ⌥Space（但沒有 Space 播放）→ 只按控制選單裡那一個
    @Test func optionSpaceDecoyInAnotherTopMenuIsIgnored() async {
        let decoy = tree.add(FakeNode(role: GeniusMenuItem.menuItemRole, cmdChar: " ", modifiers: 10))
        let windowMenu = tree.nodes[tree.bar[3]].children[0]
        tree.nodes[windowMenu].children.append(decoy)
        #expect(await press(menu()) == .pressed)
        #expect(tree.pressed == [genius])
    }

    @Test func twoControlMenusAreAmbiguous() async {
        let play = tree.add(FakeNode(role: GeniusMenuItem.menuItemRole, cmdChar: " ", modifiers: 8))
        let windowMenu = tree.nodes[tree.bar[3]].children[0]
        tree.nodes[windowMenu].children.append(play)
        #expect(await press(menu()) == .refused(.notApplied))
        #expect(tree.pressed.isEmpty)
    }

    /// 只看直屬項：Genius 藏在控制選單的子選單裡＝找不到
    @Test func geniusInsideSubmenuIsNotFound() async {
        let controlMenu = tree.nodes[tree.bar[2]].children[0]
        tree.nodes[controlMenu].children.removeAll { $0 == genius }
        let sub = tree.add(FakeNode(role: GeniusMenuItem.menuRole, children: [genius]))
        let holder = tree.add(FakeNode(role: GeniusMenuItem.menuItemRole, children: [sub]))
        tree.nodes[controlMenu].children.append(holder)
        #expect(await press(menu()) == .refused(.notApplied))
        #expect(tree.pressed.isEmpty)
    }

    /// 頂層項沒有唯一的 AXMenu 子元素＝不是候選（不影響其他選單）；控制選單本身這樣＝找不到
    @Test func topItemWithoutSingleMenuChildIsSkipped() async {
        let control = tree.bar[2]
        let controlMenu = tree.nodes[control].children[0]
        tree.nodes[control].children.append(controlMenu)
        #expect(await press(menu()) == .refused(.notApplied))
    }

    // MARK: 期限與按下前撤回

    @Test func locatingPastDeadlineAbortsWithoutPressing() async {
        tree.costPerCall = 0.2   // 走訪呼叫數遠超 15 次 → 超過 3 s
        #expect(await press(menu()) == .refused(.busy))
        #expect(tree.pressed.isEmpty && log.all.isEmpty)
        #expect(time.value <= GeniusMenu.locateDeadline + 0.2 + 1e-9)
    }

    @Test func prepareDeclinedWithholdsBeforeReadingEnabled() async {
        #expect(await press(menu(), prepare: false) == .withheld)
        #expect(tree.pressed.isEmpty && tree.enabledReads == 0 && log.all == ["prepare"])
    }

    @Test func connectionGoneAtLastMomentWithholds() async {
        #expect(await press(menu(), stillWanted: false) == .withheld)
        #expect(tree.pressed.isEmpty && log.all == ["prepare", "alive"])
    }

    // MARK: 錯誤對照（按下前＝沒動 Music）

    @Test func untrustedProcessIsAccessibilityDeniedWithoutTouchingMusic() async {
        #expect(await press(menu(trusted: false)) == .refused(.accessibilityDenied))
        #expect(tree.calls == 0)
    }

    @Test func noMusicProcessIsMusicNotRunning() async {
        #expect(await press(menu(pid: nil)) == .refused(.musicNotRunning))
        #expect(tree.calls == 0)
    }

    @Test(arguments: [(GeniusAXFailure.apiDisabled, ErrorCode.accessibilityDenied), (.busy, .busy)])
    func axFailureWhileLocatingMapsToCode(failure: GeniusAXFailure, code: ErrorCode) async {
        tree.failure = failure
        tree.failFromCall = 3
        #expect(await press(menu()) == .refused(code))
        #expect(tree.pressed.isEmpty)
    }

    @Test(arguments: [(GeniusAXFailure.apiDisabled, ErrorCode.accessibilityDenied), (.busy, .busy)])
    func axFailureReadingEnabledMapsToCode(failure: GeniusAXFailure, code: ErrorCode) async {
        let locatingCalls = await { () -> Int in
            let probe = FakeMenuTree(time: UptimeBox(0))
            Self.standardBar(probe)
            _ = await GeniusMenu(locator: FakeLocator(), trusted: { true }, makeTree: { _ in probe }, now: { 0 })
                .pressGenius(prepare: { false }, stillWanted: { true })
            return probe.calls
        }()
        tree.failure = failure
        tree.failFromCall = locatingCalls + 1
        #expect(await press(menu()) == .refused(code))
        #expect(tree.pressed.isEmpty && log.all == ["prepare"])
    }

    /// 可用性：權限屬 Azathoth 本身
    @Test func availabilityFollowsTrust() {
        #expect(GeniusMenu.availability(trusted: true) == .ready)
        #expect(GeniusMenu.availability(trusted: false) == .needsAccessibility)
    }
}
#endif
