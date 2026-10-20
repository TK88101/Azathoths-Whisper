import Testing

@testable import AzathothsWhisper

// 全專案唯一的編輯距離（R3）：帶上限時提早結束，但門檻內的值必須精確
@Suite("EditDistance")
struct EditDistanceTests {
    private func distance(_ a: String, _ b: String, limit: Int = .max) -> Int {
        EditDistance.between(Array(a), Array(b), limit: limit)
    }

    @Test func exactWithoutALimit() {
        #expect(distance("kitten", "sitting") == 3)
        #expect(distance("", "abc") == 3)
        #expect(distance("same", "same") == 0)
    }

    @Test func withinTheLimitTheValueIsExact() {
        #expect(distance("kitten", "sitting", limit: 3) == 3)
        #expect(distance("watchers", "watehers", limit: 1) == 1)
    }

    @Test func pastTheLimitItStopsEarlyWithLimitPlusOne() {
        #expect(distance("kitten", "sitting", limit: 1) == 2)
        #expect(distance("short", "a much longer line", limit: 2) == 3)
    }

    @Test(arguments: [("abcdef", "abdcef"), ("lanterns over the river", "lantern over a river"), ("a", "b"), ("xyz", "")])
    func theBandGivesTheSameAnswerAsTheFullTable(left: String, right: String) {
        let exact = distance(left, right)
        for limit in 0...6 {
            #expect(distance(left, right, limit: limit) == (exact > limit ? limit + 1 : exact), "limit \(limit)")
        }
    }

    /// 對齊最壞情況：長度相近但內容完全不同的長行。帶狀＋提早結束讓每一對只算一小部分
    @Test func dissimilarLinesOfSimilarLengthStayFast() {
        let a = Array(String(repeating: "ab", count: 250))
        let b = Array(String(repeating: "cd", count: 250))
        let elapsed = ContinuousClock().measure {
            for _ in 0..<200 { #expect(EditDistance.between(a, b, limit: 100) == 101) }
        }
        #expect(elapsed < .seconds(2))
    }
}
