import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.5「共用 LWW 暫存器」：revision 大者勝、同 revision 取 origin 字典序較小者；
// 三台以上任意順序合併結果相同（R1-1、R2-B4）
@Suite("Sync register")
struct SyncRegisterTests {
    private func reg(_ value: String?, _ revision: Int, _ origin: String) -> SyncRegister<String> {
        SyncRegister(value: value, version: SyncVersion(revision: revision, origin: origin))
    }

    @Test func theHigherRevisionWins() {
        let older = reg("a", 1, "0000000000000001")
        let newer = reg("b", 2, "ffffffffffffffff")
        #expect(SyncRegister.merged(older, newer) == newer)
        #expect(SyncRegister.merged(newer, older) == newer)
    }

    @Test func onTheSameRevisionTheSmallerOriginWins() {
        let a = reg("a", 3, "0000000000000001")
        let b = reg("b", 3, "0000000000000002")
        #expect(SyncRegister.merged(a, b) == a)
        #expect(SyncRegister.merged(b, a) == a)
    }

    @Test func aTombstoneWinsLikeAnyOtherValue() {
        let set = reg("a", 1, "0000000000000001")
        let cleared = set.updated(to: nil)
        #expect(cleared.value == nil)
        #expect(cleared.version.revision == 2)
        #expect(SyncRegister.merged(set, cleared.stamped(by: "0000000000000009")).value == nil, "清除不會被舊值復活")
    }

    @Test func anUpdateIsUnstampedUntilStamped() {
        let updated = reg("a", 4, "0000000000000003").updated(to: "b")
        #expect(updated.version == SyncVersion(revision: 5, origin: ""))
        #expect(updated.version.isStamped == false)
        let stamped = updated.stamped(by: "00000000000000aa")
        #expect(stamped.version == SyncVersion(revision: 5, origin: "00000000000000aa"))
        #expect(stamped.stamped(by: "00000000000000bb") == stamped, "已蓋章的不改")
    }

    @Test func aFreshValueStartsAtRevisionOne() {
        #expect(SyncRegister<String>.fresh("x").version == SyncVersion(revision: 1, origin: ""))
    }

    @Test func mergingIsOrderIndependentAcrossThreeWriters() {
        let writers = ["000000000000000a", "000000000000000b", "000000000000000c"]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let registers = writers.map { reg($0, Int.random(in: 0...3, using: &generator), $0) }
            let expected = registers.reduce(registers[0], SyncRegister.merged)
            for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
                let merged = order.dropFirst().reduce(registers[order[0]]) { SyncRegister.merged($0, registers[$1]) }
                #expect(merged == expected)
            }
        }
    }

    @Test func dictionariesMergeKeyByKey() {
        let local = ["k1": reg("a", 1, "0000000000000001"), "k2": reg("b", 5, "0000000000000001")]
        let remote = ["k1": reg("c", 2, "0000000000000002"), "k3": reg("d", 1, "0000000000000002")]
        let merged = SyncRegister.merged(local, remote)
        #expect(merged["k1"]?.value == "c")
        #expect(merged["k2"]?.value == "b")
        #expect(merged["k3"]?.value == "d")
    }

    @Test func itRoundTripsThroughJSON() throws {
        let original = reg(nil, 7, "0000000000000001")
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(SyncRegister<String>.self, from: data) == original)
    }
}
