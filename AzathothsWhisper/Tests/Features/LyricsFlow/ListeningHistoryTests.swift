import Testing

@testable import AzathothsWhisper

// 計劃 AC8b（R3-7）：History.dat 不可讀時的左側來源——有序集合、上限 50、空 ID 不進
@Suite("ListeningHistory")
struct ListeningHistoryTests {
    private typealias Play = ListeningHistory.Play

    @Test func recordsOldestToNewest() {
        let history = ListeningHistory()
            .recording(Play(persistentID: "A", occurrence: 1))
            .recording(Play(persistentID: "B", occurrence: 2))
        #expect(history.plays.map(\.persistentID) == ["A", "B"])
    }

    /// A→B→A：重播移到尾端、不重複
    @Test func replayMovesToTheEndWithoutDuplicating() {
        let history = ListeningHistory()
            .recording(Play(persistentID: "A", occurrence: 1))
            .recording(Play(persistentID: "B", occurrence: 2))
            .recording(Play(persistentID: "A", occurrence: 3))
        #expect(history.plays == [Play(persistentID: "B", occurrence: 2), Play(persistentID: "A", occurrence: 3)])
    }

    @Test func emptyPersistentIDIsIgnored() {
        let history = ListeningHistory().recording(Play(persistentID: "", occurrence: 1))
        #expect(history.plays.isEmpty)
    }

    @Test func capacityDropsTheOldest() {
        let history = (1...(ListeningHistory.capacity + 3)).reduce(ListeningHistory()) { history, n in
            history.recording(Play(persistentID: "P\(n)", occurrence: n))
        }
        #expect(history.plays.count == ListeningHistory.capacity)
        #expect(history.plays.first?.persistentID == "P4")
    }

    @Test func recordingDoesNotMutateTheOriginal() {
        let original = ListeningHistory().recording(Play(persistentID: "A", occurrence: 1))
        _ = original.recording(Play(persistentID: "B", occurrence: 2))
        #expect(original.plays.map(\.persistentID) == ["A"])
    }
}
