import Foundation
import ObjectiveC

/// Music `@objc` 協議的選擇器白名單檢查（計劃 AC9 ②）。
///
/// 以執行期內省列出協議**實際的**選擇器——`{ get set }` 的隱式 setter、`@objc(改名)`、
/// `playOnce:` 這類名稱與命令不同的選擇器都會現形；原始碼 grep 看不到這些，註解也不會造成誤判。
enum SelectorAllowList {
    static func selectors(of proto: Protocol) -> [(name: String, required: Bool)] {
        var out: [(String, Bool)] = []
        for required in [true, false] {
            for instance in [true, false] {
                var count: UInt32 = 0
                guard let list = protocol_copyMethodDescriptionList(proto, required, instance, &count) else { continue }
                for index in 0..<Int(count) {
                    if let selector = list[index].name { out.append((NSStringFromSelector(selector), required)) }
                }
                free(list)
            }
        }
        return out
    }

    /// 每個選擇器至多一條違規；`allowedSetters` 以外的 `set*:` 一律違規
    static func violations(protocolName: String, allowed: Set<String>, allowedSetters: Set<String> = []) -> [String] {
        guard let proto = NSProtocolFromString(protocolName) else {
            return ["\(protocolName): runtime 找不到協議"]
        }
        return selectors(of: proto).flatMap { selector, required -> [String] in
            var found: [String] = required ? ["\(protocolName): required \(selector)"] : []
            if selector.hasPrefix("set") {
                if !allowedSetters.contains(selector) { found.append("\(protocolName): setter \(selector)") }
            } else if !allowed.contains(selector) {
                found.append("\(protocolName): 不在允許清單 \(selector)")
            }
            return found
        }
    }

    /// 類別上掛的、名稱以 `prefix` 開頭的協議
    static func protocols(on cls: AnyClass, prefix: String) -> [String] {
        var count: UInt32 = 0
        guard let list = class_copyProtocolList(cls, &count) else { return [] }
        return (0..<Int(count)).map { NSStringFromProtocol(list[$0]) }.filter { $0.hasPrefix(prefix) }
    }
}
