import Foundation

/// 同一首歌上一次的配方（組合器每槽排除上次的元件）。鍵＝`TrackInfo.signature`
@MainActor
protocol LyricsFXRecipeHistory: AnyObject {
    func lastPicks(forTrack signature: String) -> RecipePicks?
    func record(_ picks: RecipePicks, forTrack signature: String)
}

/// 一份配方裡各槽選中的元件 id（存檔只存這些代號，不存曲名、歌詞）
struct RecipePicks: Equatable, Sendable {
    let font, backdrop, enter, exit, fx1, palette: String

    init(_ recipe: ComposedRecipe) {
        font = recipe.font
        backdrop = recipe.backdrop
        enter = recipe.enter
        exit = recipe.exit
        fx1 = recipe.fx1
        palette = recipe.palette
    }

    init?(stored ids: [String]) {
        guard ids.count == 6 else { return nil }
        (font, backdrop, enter, exit, fx1, palette) = (ids[0], ids[1], ids[2], ids[3], ids[4], ids[5])
    }

    var stored: [String] { [font, backdrop, enter, exit, fx1, palette] }

    /// 給組合器的「上一次」：只有各槽 id 有意義，種子與目標值不參與
    var asPrevious: ComposedRecipe {
        ComposedRecipe(font: font, backdrop: backdrop, enter: enter, exit: exit, fx1: fx1, fx2: "", palette: palette, seed: 0, profile: SongProfile(axes: [:], tags: []))
    }
}

/// 只在記憶體（測試，與沒有 persistentID 的曲目）
@MainActor
final class InMemoryRecipeHistory: LyricsFXRecipeHistory {
    private var picks: [String: RecipePicks] = [:]

    func lastPicks(forTrack signature: String) -> RecipePicks? {
        picks[signature]
    }

    func record(_ picks: RecipePicks, forTrack signature: String) {
        self.picks[signature] = picks
    }
}

/// 生產用：有 persistentID 的曲目存進設定（跨重啟），其餘只在記憶體
@MainActor
final class StoredRecipeHistory: LyricsFXRecipeHistory {
    private let store: ConfigStore
    private let memory = InMemoryRecipeHistory()

    init(store: ConfigStore) {
        self.store = store
    }

    func lastPicks(forTrack signature: String) -> RecipePicks? {
        store.lastLyricsFXPicks(forTrack: signature) ?? memory.lastPicks(forTrack: signature)
    }

    func record(_ picks: RecipePicks, forTrack signature: String) {
        if ConfigStore.recipeHistoryKey(signature) != nil {
            store.recordLyricsFXPicks(picks, forTrack: signature)
        } else {
            memory.record(picks, forTrack: signature)
        }
    }
}
