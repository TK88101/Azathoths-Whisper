import Foundation
import Testing

@testable import AzathothsWhisper

// ⑥a J-Pop 計劃 T0（docs/plans/2026-10-23-lyrics-fx-jpop.md）：既有團與曲風列在固定種子下抽出的配方，
// 加 J-Pop 元件與判定前後必須一字不差（新元件只帶 J-Pop 私有標籤，對既有 profile 不合格）。
// 摘要在 main（e0818da）＋ `Composer.fit` 固定軸序加總的修正上錄下（修正前字典走訪順序每次啟動不同，
// 21 組數學上相等的貼合度差在最後一位、同分排序會翻轉：同一份程式碼曾錄出 41f7… 與 2f80… 兩種摘要）

@Suite("Recipe golden")
struct RecipeGoldenTests {
    static let seeds: ClosedRange<UInt64> = 1...20
    /// e0818da＋fit 軸序修正上 `digest()` 的值（逐行與本分支的 `printTheLines()` 輸出比對一致）
    static let recordedDigest: UInt64 = 0x2f80_4412_4f79_d4dc

    /// 只取既有的 profile（樂團表＋曲風列）；不用 `ReadabilityAudit.profiles`——它之後會加入 J-Pop 變體
    static let existingProfiles: [(name: String, profile: SongProfile)] =
        SongProfileResolver.bandTable.map { ($0.name, $0.profile) }
            + SongProfileResolver.keywordRows.compactMap { row in
                SongProfileResolver.compose(genre: row.keywords[0], rows: [row]).map { ("genre:\(row.keywords[0])", $0) }
            }

    /// 每個 profile 連抽（排除上一次）的配方逐槽串成一行，再取 FNV-1a 64
    static func digest() -> UInt64 {
        FXHash.fnv1a64(lines().joined(separator: "\n"))
    }

    static func lines() -> [String] {
        let lines = existingProfiles.flatMap { name, profile in
            var previous: ComposedRecipe?
            return seeds.map { seed -> String in
                switch Composer.compose(profile: profile, seed: seed, avoiding: previous) {
                case .mono:
                    previous = nil
                    return "\(name)|\(seed)|mono"
                case .composed(let recipe):
                    previous = recipe
                    let ids = [recipe.font, recipe.backdrop, recipe.enter, recipe.exit, recipe.fx1, recipe.fx2, recipe.palette]
                    return "\(name)|\(seed)|\(ids.joined(separator: ","))|\(recipe.seed)"
                }
            }
        }
        return lines
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AZW_PRINT_RECIPE_GOLDEN"] != nil))
    func printTheLines() {
        print("<<<GOLDEN\n\(Self.lines().joined(separator: "\n"))\nGOLDEN>>>")
    }

    @Test func existingProfilesDrawTheSameRecipesAsBeforeJPop() {
        let digest = Self.digest()
        #expect(digest == Self.recordedDigest, "摘要 \(String(digest, radix: 16))")
    }
}
