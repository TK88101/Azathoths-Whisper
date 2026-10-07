import Foundation
import Testing

@testable import AzathothsWhisper

// 同一首歌上一次的配方（2026-10-06 定案）：只以 Music 的 16 位 hex persistentID 為鍵、最多 500 首、只存元件代號（不存曲名與歌詞）
@Suite("ConfigStore recipe history")
struct ConfigStoreRecipeHistoryTests {
    private func picks(_ font: String) -> RecipePicks {
        RecipePicks(stored: [font, "snow", "slam", "cut", "shake", "ice"])!
    }

    private func store() -> (ConfigStore, UserDefaults) {
        let suite = "azw.test.fonthistory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (ConfigStore(secrets: EphemeralSecretStore(), defaults: defaults), defaults)
    }

    @Test func everySlotIsStoredAndReadBack() {
        let (config, _) = store()
        config.recordLyricsFXPicks(picks("Cenobyte"), forTrack: "0A2E500000000001")
        #expect(config.lastLyricsFXPicks(forTrack: "0A2E500000000001") == picks("Cenobyte"))
    }

    @Test func aRecordedFontReadsBack() {
        let (config, _) = store()
        config.recordLyricsFXPicks(picks("Cenobyte"), forTrack: "0A2E500000000001")
        #expect(config.lastLyricsFXPicks(forTrack: "0A2E500000000001")?.font == "Cenobyte")
        config.recordLyricsFXPicks(picks("Grimoire"), forTrack: "0A2E500000000001")
        #expect(config.lastLyricsFXPicks(forTrack: "0A2E500000000001")?.font == "Grimoire")
    }

    @Test(arguments: ["", "not-hex", "0A2E5", "0a2e500000000001zz", "Artist|Title|Album"])
    func onlyMusicPersistentIDsArePersisted(id: String) {
        let (config, defaults) = store()
        config.recordLyricsFXPicks(picks("Cenobyte"), forTrack: id)
        #expect(config.lastLyricsFXPicks(forTrack: id) == nil)
        #expect(defaults.array(forKey: ConfigStore.RecipeHistoryKey.lastPicks) == nil)
    }

    @Test func lowercaseIDsAreNormalized() {
        let (config, _) = store()
        config.recordLyricsFXPicks(picks("Mirage"), forTrack: "0a2e500000000001")
        #expect(config.lastLyricsFXPicks(forTrack: "0A2E500000000001")?.font == "Mirage")
    }

    @Test func theOldestEntriesFallOffPastTheCap() {
        let (config, _) = store()
        for index in 0...ConfigStore.recipeHistoryCapacity {
            config.recordLyricsFXPicks(picks("Grimoire"), forTrack: String(format: "%016X", index))
        }
        #expect(config.lastLyricsFXPicks(forTrack: String(format: "%016X", 0)) == nil, "最舊的被擠掉")
        #expect(config.lastLyricsFXPicks(forTrack: String(format: "%016X", ConfigStore.recipeHistoryCapacity))?.font == "Grimoire")
    }

    @Test func playingAgainMovesASongToTheNewestEnd() {
        let (config, _) = store()
        config.recordLyricsFXPicks(picks("Grimoire"), forTrack: String(format: "%016X", 0))
        for index in 1..<ConfigStore.recipeHistoryCapacity {
            config.recordLyricsFXPicks(picks("Grimoire"), forTrack: String(format: "%016X", index))
        }
        config.recordLyricsFXPicks(picks("Cenobyte"), forTrack: String(format: "%016X", 0))
        config.recordLyricsFXPicks(picks("Grimoire"), forTrack: String(format: "%016X", 99_999))
        #expect(config.lastLyricsFXPicks(forTrack: String(format: "%016X", 0))?.font == "Cenobyte", "剛播過的不會被擠掉")
        #expect(config.lastLyricsFXPicks(forTrack: String(format: "%016X", 1)) == nil)
    }

    @Test func corruptEntriesAreSkipped() {
        let (config, defaults) = store()
        defaults.set([["0A2E500000000001", "Grimoire", "snow", "slam", "cut", "shake", "ice"], 42, ["bad"]], forKey: ConfigStore.RecipeHistoryKey.lastPicks)
        #expect(config.lastLyricsFXPicks(forTrack: "0A2E500000000001")?.font == "Grimoire")
    }
}
