import Foundation
import Testing

@testable import AzathothsWhisper

// 計劃 D4、AC5：標記存 app 設定（注入的 suite），不碰使用者的 .standard；空 ID 拒絕
@Suite("NoLyricsMarks")
struct NoLyricsMarksTests {
    private func makeStore() -> (ConfigStore, UserDefaults, String) {
        let name = "NoLyricsMarksTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (ConfigStore(secrets: EphemeralSecretStore(), defaults: defaults), defaults, name)
    }

    @Test func markingPersistsAcrossStoreInstances() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(store.markNoLyrics("PID1"))
        let reopened = ConfigStore(secrets: EphemeralSecretStore(), defaults: defaults)
        #expect(reopened.noLyricsMarks == ["PID1"])
    }

    @Test func emptyPersistentIDIsRejected() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(!store.markNoLyrics(""))
        #expect(store.noLyricsMarks.isEmpty)
    }

    @Test func clearingRemovesOnlyThatTrack() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }

        store.markNoLyrics("PID1")
        store.markNoLyrics("PID2")
        store.clearNoLyricsMark("PID1")
        #expect(store.noLyricsMarks == ["PID2"])
    }

    @Test func markingTwiceKeepsASingleEntry() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }

        store.markNoLyrics("PID1")
        store.markNoLyrics("PID1")
        #expect(defaults.stringArray(forKey: ConfigStore.NoLyricsMarksKey.markedTrackIDs) == ["PID1"])
    }
}
