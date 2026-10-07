import Foundation

/// 一次播放的配方（母計劃 §2.10）：一次播放內固定。`nil` 不是合法值——沒有組合就是 `.mono`
enum SessionRecipe: Equatable, Sendable {
    case mono
    case composed(ComposedRecipe)
}

struct ComposedRecipe: Equatable, Sendable {
    let font: String
    let backdrop: String
    let enter: String
    let exit: String
    let fx1: String
    let fx2: String
    let palette: String
    /// 逐行個性的種子來源
    let seed: UInt64
    /// 停留模板與變異量依它而定（原型 `styleFromRecipe` 讀 aggression／elegance）
    let profile: SongProfile

    var componentIDs: Set<String> {
        [font, backdrop, enter, exit, fx1, fx2, palette]
    }
}
