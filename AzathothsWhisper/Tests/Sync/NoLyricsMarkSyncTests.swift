import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.5「沒有歌詞標記」：ledger＋墓碑；舊鍵單向遷移後凍結（R2-B4、R3-2）
@Suite("No-lyrics mark sync")
struct NoLyricsMarkSyncTests {
    private func makeStore() -> (ConfigStore, UserDefaults, String) {
        let name = "NoLyricsMarkSyncTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (ConfigStore(secrets: EphemeralSecretStore(), defaults: defaults), defaults, name)
    }

    @Test func legacyMarksMigrateAsRevisionZeroAndTheOldKeyFreezes() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["AAAA000000000001", "AAAA000000000002"], forKey: ConfigStore.NoLyricsMarksKey.markedTrackIDs)

        #expect(store.noLyricsMarks == ["AAAA000000000001", "AAAA000000000002"])
        #expect(store.noLyricsMarkLedger["AAAA000000000001"]?.version == SyncVersion(revision: 0, origin: ""))
        store.markNoLyrics("AAAA000000000003")
        store.clearNoLyricsMark("AAAA000000000001")
        #expect(store.noLyricsMarks == ["AAAA000000000002", "AAAA000000000003"])
        #expect(defaults.stringArray(forKey: ConfigStore.NoLyricsMarksKey.markedTrackIDs) == ["AAAA000000000001", "AAAA000000000002"],
                "舊鍵凍結，不再寫")
    }

    @Test func clearingLeavesATombstone() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.markNoLyrics("AAAA000000000001")
        store.clearNoLyricsMark("AAAA000000000001")
        let entry = store.noLyricsMarkLedger["AAAA000000000001"]
        #expect(entry?.value == nil)
        #expect(entry?.version.revision == 2)
        store.markNoLyrics("AAAA000000000001")
        #expect(store.noLyricsMarkLedger["AAAA000000000001"]?.version.revision == 3)
    }

    @Test func aStaleRemoteMarkDoesNotComeBackAfterClearing() {
        let (store, defaults, name) = makeStore()
        defer { defaults.removePersistentDomain(forName: name) }
        store.markNoLyrics("AAAA000000000001")
        let remote = store.noLyricsMarkLedger.mapValues { $0.stamped(by: "000000000000000b") }
        store.clearNoLyricsMark("AAAA000000000001")
        let local = store.noLyricsMarkLedger.mapValues { $0.stamped(by: "000000000000000a") }
        store.writeNoLyricsMarkLedger(SyncRegister.merged(local, remote))
        #expect(store.noLyricsMarks.isEmpty)
    }
}
