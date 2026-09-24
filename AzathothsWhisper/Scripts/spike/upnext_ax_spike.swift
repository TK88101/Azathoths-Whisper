// 唯讀 spike：能否以 Accessibility 讀出 Music「再生を続ける／Up Next」面板的列（計劃 §8 SEQ-S，2026-09-23 追加）。
// 只呼叫 AXUIElementCopyAttributeValue／CopyAttributeNames；**不**執行任何 AX action、不設任何屬性、不送 Apple Event。
// 前置：AXIsProcessTrustedWithOptions(prompt: false) 必須為 true（不彈授權框）；Music 必須已在執行（不啟動它）。
// 編譯：swiftc -O upnext_ax_spike.swift -o <scratch>/upnext_ax_spike
import AppKit
import ApplicationServices

let headings: Set<String> = ["再生を続ける", "次はこちら", "Continue Playing", "Playing Next", "Up Next", "繼續播放", "接下來播放"]
let maxNodes = 40_000
let maxDepth = 40

func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func text(_ element: AXUIElement) -> String? {
    for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] as [String] {
        if let s = attr(element, key) as? String, !s.isEmpty { return s }
    }
    return nil
}

func role(_ element: AXUIElement) -> String { (attr(element, kAXRoleAttribute) as? String) ?? "?" }

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func texts(in element: AXUIElement, depth: Int = 0) -> [String] {
    guard depth < 8 else { return [] }
    var out: [String] = []
    if role(element) == "AXStaticText", let t = text(element) { out.append(t) }
    for child in children(element) { out += texts(in: child, depth: depth + 1) }
    return out
}

guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary) else {
    print("STOP: 本行程沒有輔助使用授權（不彈框）"); exit(4)
}
guard let music = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
    print("STOP: Music 未執行（不啟動它）"); exit(3)
}
let root = AXUIElementCreateApplication(music.processIdentifier)
AXUIElementSetMessagingTimeout(root, 2.0)   // 本行程端的等待上限（不改變 Music）

let start = Date()
var queue: [(AXUIElement, Int, [AXUIElement])] = [(root, 0, [])]
var visited = 0
var headingHit: (label: String, ancestors: [AXUIElement])?
while !queue.isEmpty, visited < maxNodes, headingHit == nil {
    let (node, depth, ancestors) = queue.removeFirst()
    visited += 1
    if let t = text(node), headings.contains(t) {
        headingHit = (t, ancestors)
        break
    }
    guard depth < maxDepth else { continue }
    for child in children(node) { queue.append((child, depth + 1, ancestors + [node])) }
}
print(String(format: "visited=%d nodes in %.0fms", visited, Date().timeIntervalSince(start) * 1000))
guard let hit = headingHit else { print("heading NOT found（面板可能收起／語系不同）"); exit(0) }
print("heading found: \(hit.label) depth=\(hit.ancestors.count)")

// 往上找最近一個含有列容器（AXTable／AXOutline／AXList）的祖先，逐列讀文字
let rowRoles: Set<String> = ["AXRow", "AXCell", "AXGroup"]
for ancestor in hit.ancestors.reversed().prefix(4) {
    var containers: [AXUIElement] = []
    var stack = [ancestor]
    var seen = 0
    while let node = stack.popLast(), seen < 5000 {
        seen += 1
        if ["AXTable", "AXOutline", "AXList"].contains(role(node)) { containers.append(node) }
        stack += children(node)
    }
    guard let list = containers.first else { continue }
    let rows = (attr(list, kAXRowsAttribute) as? [AXUIElement]) ?? children(list).filter { rowRoles.contains(role($0)) }
    print("container role=\(role(list)) rows=\(rows.count)")
    for (i, row) in rows.prefix(25).enumerated() {
        print(String(format: "%2d ", i + 1) + texts(in: row).prefix(3).joined(separator: " | "))
    }
    print(String(format: "total %.0fms", Date().timeIntervalSince(start) * 1000))
    exit(0)
}
print("no row container near heading")
