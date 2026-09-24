import Foundation

@testable import AzathothsWhisper

/// Cover Flow VM 測試用的牌組：卡 ID `C<n>`、persistentID `T<n>`（除非另給）
enum DeckFixtures {
    static func card(_ n: Int, persistentID: String? = nil) -> DeckCard {
        DeckCard(id: "C\(n)", persistentID: persistentID ?? "T\(n)", side: .upcoming)
    }

    /// `ids` 為卡序號；`current` 為中心卡序號
    static func deck(_ ids: [Int], current: Int?, persistentIDs: [Int: String] = [:]) -> DeckSnapshot {
        DeckSnapshot(
            cards: ids.map { card($0, persistentID: persistentIDs[$0]) },
            currentCardID: current.map { "C\($0)" },
            upcoming: .available
        )
    }
}
