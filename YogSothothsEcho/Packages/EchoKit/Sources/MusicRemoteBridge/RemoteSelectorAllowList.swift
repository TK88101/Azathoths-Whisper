#if os(macOS)
import Foundation
import ObjectiveC

/// 一個 @objc 協定的選擇器稽核結果
public struct SelectorAudit: Sendable, Equatable {
    public let found: Bool
    public let missing: Set<String>
    public let extra: Set<String>
    public let requiredCount: Int

    /// 白名單外的 setter（`set…:`）：寫入類能力，單獨列出
    public var unlistedSetters: Set<String> { extra.filter { $0.hasPrefix("set") && $0.hasSuffix(":") } }
    public var isExact: Bool { found && missing.isEmpty && extra.isEmpty && requiredCount == 0 }
}

/// 逐協定完全等於（CR-006④、CR-009）。`tracks` 那一筆定義在 TrackLookup.swift（echo_gate.py E3 只許它出現在那裡）。與 Azathoth 的 SelectorAllowList 相似但不共用：EchoKit 不得依賴 Azathoth
public enum RemoteSelectorAllowList {
    public static let expected: [String: Set<String>] = [
        "AZWMusicRemoteProto": [
            "playpause", "nextTrack", "previousTrack", "playerPosition", "setPlayerPosition:", "playerState",
            "currentTrack", "AirPlayDevices", "currentAirPlayDevices", "setCurrentAirPlayDevices:",
        ],
        "AZWMusicRemoteTrackProto": ["persistentID", "duration", "playOnce:"],
        "AZWMusicRemoteAirPlayProto": ["persistentID", "selected", "kind"],
    ].merging([libraryEntry]) { _, _ in [] }

    public static func audit(protocolName: String) -> SelectorAudit {
        audit(protocolName: protocolName, expected: expected[protocolName] ?? [])
    }

    /// optional／required × instance／class 四種組合都讀（spike selfCheck 已驗證的做法）
    public static func audit(protocolName: String, expected: Set<String>) -> SelectorAudit {
        guard let proto = objc_getProtocol(protocolName) else {
            return SelectorAudit(found: false, missing: expected, extra: [], requiredCount: 0)
        }
        var declared = Set<String>()
        var requiredCount = 0
        for (isRequired, isInstance) in [(false, true), (false, false), (true, true), (true, false)] {
            let names = selectors(of: proto, required: isRequired, instance: isInstance)
            declared.formUnion(names)
            if isRequired { requiredCount += names.count }
        }
        return SelectorAudit(found: true, missing: expected.subtracting(declared),
                             extra: declared.subtracting(expected), requiredCount: requiredCount)
    }

    private static func selectors(of proto: Protocol, required: Bool, instance: Bool) -> [String] {
        var count: UInt32 = 0
        guard let list = protocol_copyMethodDescriptionList(proto, required, instance, &count) else { return [] }
        defer { free(list) }
        return (0..<Int(count)).compactMap { list[$0].name.map(NSStringFromSelector) }
    }
}
#endif
