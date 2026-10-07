// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import Foundation

/// 預覽場景的配方控制（B1 計劃 §3.10）：固定 nonce、或直接指定七個元件 id。只在 app target（UITests 不同編）
enum LyricsFXPreviewRecipe {
    /// `AZW_LYRICSFX_PREVIEW_RECIPE`＝"font,backdrop,enter,exit,fx1,fx2,palette"；id 數不對或有不在目錄裡的 → nil
    static func forced(in environment: [String: String], profile: SongProfile) -> ComposedRecipe? {
        guard let raw = environment[LyricsFXPreviewFixture.recipeVariable] else { return nil }
        let ids = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard ids.count == 7, ids.allSatisfy({ LyricsFXCatalog.component($0) != nil }) else { return nil }
        return ComposedRecipe(
            font: ids[0], backdrop: ids[1], enter: ids[2], exit: ids[3], fx1: ids[4], fx2: ids[5], palette: ids[6],
            seed: FXHash.fnv1a64(raw), profile: profile
        )
    }

    static func nonce(in environment: [String: String]) -> UInt64? {
        environment[LyricsFXPreviewFixture.nonceVariable].flatMap { UInt64($0) }
    }
}

/// 每次都回同一個 nonce
final class FixedNonceSource: FXNonceSource {
    private let value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

    func next() -> UInt64 {
        value
    }
}
#endif
