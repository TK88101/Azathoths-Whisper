#if os(macOS)
import ApplicationServices
import Foundation
import RemoteProtocol

// Genius（CR-030；s6-61-genius.md §4.2 Mac 執行）：中繼裡唯一的輔助使用（AX）出口。echo_gate E10：AX API 只准出現在本檔，
// 本檔只准按下（kAXPressAction）、不寫屬性、不送鍵盤事件。
// 定位不讀標題（與語言無關）：「控制」選單＝直屬項中有 Space（修飾 8＝無 ⌘）的頂層選單，且只能有一個；
// Genius＝該選單直屬項中唯一的 ⌥Space（修飾 10＝⌥｜無 ⌘）。不掃子選單；任何一步不唯一或缺＝不按。

/// 按 Genius 的結果。refused＝沒按（沒動 Music）；pressed＝已送按下（含按下本身回錯：可能已生效，交給讀回確認）
public enum GeniusPress: Equatable, Sendable {
    case pressed
    case refused(ErrorCode)
    /// 定位成功，但呼叫端在按下前撤回（讀回失敗、連線已撤離）
    case withheld
}

/// 會讓定位中止的 AX 失敗；其他錯誤（沒有值、屬性不支援、元素失效）一律當「沒有這個值」
enum GeniusAXFailure: Error, Sendable {
    /// 未被允許輔助使用（kAXErrorAPIDisabled）
    case apiDisabled
    /// Music 沒回應（kAXErrorCannotComplete，含 messaging timeout）或定位期限到
    case busy
}

struct GeniusMenuItem: Equatable, Sendable {
    static let menuItemRole = kAXMenuItemRole
    static let menuRole = kAXMenuRole

    let role: String?
    let cmdChar: String?
    let modifiers: Int?

    static let playModifiers = 8
    static let geniusModifiers = 10

    func isShortcut(_ modifiers: Int) -> Bool {
        role == Self.menuItemRole && cmdChar == " " && self.modifiers == modifiers
    }
}

/// 選單樹的讀取（正式＝AXMenuTree；測試＝替身）。每個方法＝一次 AX 呼叫（topMenus 為兩次）
protocol GeniusMenuTree {
    associatedtype Element
    func topMenus() throws(GeniusAXFailure) -> [Element]
    func children(_ element: Element) throws(GeniusAXFailure) -> [Element]
    func item(_ element: Element) throws(GeniusAXFailure) -> GeniusMenuItem
    func isEnabled(_ element: Element) throws(GeniusAXFailure) -> Bool
    /// 結果不看：按下後一律交給讀回確認
    func press(_ element: Element)
}

/// Azathoth 設定頁用：本程序是否被允許輔助使用（AX 只在本檔，Azathoth 本體經這裡讀，不直接碰 AX；no_playback_gate R1-ax）
public enum GeniusAccess {
    public static func availability() -> GeniusAvailability { GeniusMenu.availability() }
}

/// 佇列看到的按 Genius 介面（正式＝GeniusMenu；測試＝替身）。不暴露任何 AX 元素
public protocol GeniusPressing: Sendable {
    func pressGenius(prepare: @Sendable () async -> Bool, stillWanted: @Sendable () async -> Bool) async -> GeniusPress
}

struct GeniusMenu: GeniusPressing {
    /// 定位階段整體期限（每次 AX 呼叫前檢查；單次呼叫最多再超 messagingTimeout）
    static let locateDeadline: Double = 3
    static let messagingTimeout: Float = 2

    private let locator: any MusicProcessLocating
    private let trusted: @Sendable () -> Bool
    private let makeTree: @Sendable (pid_t) -> any GeniusMenuTree
    private let now: @Sendable () -> Double

    /// PID 只取自驗證過可執行檔的 locator；不接受外部 PID。正式路徑只用無參數的 `GeniusMenu()`（echo_gate E10 擋本檔以外的注入）
    init(locator: any MusicProcessLocating = RunningMusicLocator(), trusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
         makeTree: (@Sendable (pid_t) -> any GeniusMenuTree)? = nil,
         now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.locator = locator
        self.trusted = trusted
        self.makeTree = makeTree ?? { AXMenuTree(pid: $0) }
        self.now = now
    }

    /// Azathoth 本身是否被允許輔助使用（不彈系統詢問框）
    @Sendable static func availability() -> GeniusAvailability { availability(trusted: AXIsProcessTrusted()) }
    static func availability(trusted: Bool) -> GeniusAvailability { trusted ? .ready : .needsAccessibility }

    /// 定位 → `prepare`（呼叫端取按下前讀回；false＝撤回）→ 項目啟用才按 → `stillWanted`（按下前最後一刻查連線）→ 按下
    /// AX 是同步阻塞呼叫：`@concurrent` 寫死在共用執行緒池上跑，不佔呼叫端（佇列）的 actor
    @concurrent
    func pressGenius(prepare: @Sendable () async -> Bool, stillWanted: @Sendable () async -> Bool) async -> GeniusPress {
        guard trusted() else { return .refused(.accessibilityDenied) }
        guard let pid = locator.musicPID() else { return .refused(.musicNotRunning) }
        return await press(in: makeTree(pid), prepare: prepare, stillWanted: stillWanted)
    }

    private func press<T: GeniusMenuTree>(in tree: T, prepare: @Sendable () async -> Bool,
                                          stillWanted: @Sendable () async -> Bool) async -> GeniusPress {
        let target: T.Element
        do {
            guard let found = try Self.locate(in: tree, expired: deadline()) else { return .refused(.notApplied) }
            target = found
        } catch {
            return .refused(Self.code(error))
        }
        guard await prepare() else { return .withheld }
        do {
            guard try tree.isEnabled(target) else { return .refused(.notApplied) }
        } catch {
            return .refused(Self.code(error))
        }
        guard await stillWanted() else { return .withheld }
        tree.press(target)
        return .pressed
    }

    private func deadline() -> @Sendable () -> Bool {
        let start = now(), now = self.now
        return { now() - start >= Self.locateDeadline }
    }

    static func code(_ failure: GeniusAXFailure) -> ErrorCode {
        switch failure {
        case .apiDisabled: .accessibilityDenied
        case .busy: .busy
        }
    }

    /// nil＝結構不符（找不到、不唯一）
    static func locate<T: GeniusMenuTree>(in tree: T, expired: () -> Bool) throws(GeniusAXFailure) -> T.Element? {
        func call<R>(_ body: () throws(GeniusAXFailure) -> R) throws(GeniusAXFailure) -> R {
            if expired() { throw .busy }
            return try body()
        }
        var controls: [[(T.Element, GeniusMenuItem)]] = []
        for top in try call({ () throws(GeniusAXFailure) in try tree.topMenus() }) {
            let menus = try call { () throws(GeniusAXFailure) in try tree.children(top) }
            guard menus.count == 1, let menu = menus.first,
                  try call({ () throws(GeniusAXFailure) in try tree.item(menu) }).role == GeniusMenuItem.menuRole else { continue }
            var items: [(T.Element, GeniusMenuItem)] = []
            for element in try call({ () throws(GeniusAXFailure) in try tree.children(menu) }) {
                items.append((element, try call { () throws(GeniusAXFailure) in try tree.item(element) }))
            }
            if items.contains(where: { $0.1.isShortcut(GeniusMenuItem.playModifiers) }) { controls.append(items) }
        }
        guard controls.count == 1, let control = controls.first else { return nil }
        let genius = control.filter { $0.1.isShortcut(GeniusMenuItem.geniusModifiers) }
        return genius.count == 1 ? genius.first?.0 : nil
    }
}

/// 正式選單樹：對 Music 程序的 AX 讀取與按下（fileprivate：本檔以外拿不到任意 PID 的樹；E10）
fileprivate final class AXMenuTree: GeniusMenuTree {
    private let app: AXUIElement

    init(pid: pid_t) {
        app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, GeniusMenu.messagingTimeout)
    }

    func topMenus() throws(GeniusAXFailure) -> [AXUIElement] {
        guard let bar = try Self.element(try Self.copy(app, kAXMenuBarAttribute)) else { return [] }
        return try children(bar)
    }

    func children(_ element: AXUIElement) throws(GeniusAXFailure) -> [AXUIElement] {
        (try Self.copy(element, kAXChildrenAttribute) as? [AnyObject] ?? []).compactMap { try? Self.element($0) }
    }

    func item(_ element: AXUIElement) throws(GeniusAXFailure) -> GeniusMenuItem {
        let names = [kAXRoleAttribute, kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute] as CFArray
        var values: CFArray?
        try Self.check(AXUIElementCopyMultipleAttributeValues(element, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values))
        // 個別屬性缺值時該位置是 AXValue 錯誤物件，轉型失敗＝nil
        let list = values as? [AnyObject] ?? []
        func at(_ i: Int) -> AnyObject? { i < list.count ? list[i] : nil }
        return GeniusMenuItem(role: at(0) as? String, cmdChar: at(1) as? String, modifiers: (at(2) as? NSNumber)?.intValue)
    }

    func isEnabled(_ element: AXUIElement) throws(GeniusAXFailure) -> Bool {
        (try Self.copy(element, kAXEnabledAttribute) as? Bool) ?? false
    }

    func press(_ element: AXUIElement) {
        _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) throws(GeniusAXFailure) -> CFTypeRef? {
        var value: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(element, attribute as CFString, &value))
        return value
    }

    /// apiDisabled／cannotComplete 才中止；其他錯誤＝沒有值（呼叫端拿到 nil 或空集合）
    private static func check(_ error: AXError) throws(GeniusAXFailure) {
        switch error {
        case .apiDisabled: throw .apiDisabled
        case .cannotComplete: throw .busy
        default: return
        }
    }

    /// 逾時只對設定的那個元素有效（AXUIElement.h：「sets it only for that object」）：每個取得的元素都各設一次，
    /// 子元素才不會落回全域預設、讓 worstGenius 的推算失準（simcodex G7 security MEDIUM-1）
    private static func element(_ value: CFTypeRef?) throws(GeniusAXFailure) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, GeniusMenu.messagingTimeout)
        return element
    }
}
#endif
