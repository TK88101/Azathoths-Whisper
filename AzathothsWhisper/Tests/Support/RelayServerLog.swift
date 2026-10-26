@testable import AzathothsWhisper

/// 測試建立過的 server（RelayHostTests、AppModelRelayLaunchTests 共用；`FakeRelayServer` 在 RelayHostTests.swift）
final class RelayServerLog: @unchecked Sendable {
    var made: [FakeRelayServer] = []
    var holdStart = false
    var last: FakeRelayServer? { made.last }
}
