import Foundation

@testable import AzathothsWhisper

/// 以程式組出與 Music `Queue.dat`／`History.dat` 同構的 plist（計劃 §3 事實 20–25）。
/// 真實形狀另有去識別化的樣本檔：`Fixtures/Queue/*.plist`。
enum QueueFixtures {
    struct Item {
        let trackID: Int64?
        let itemID: Int64?

        init(_ trackID: Int64?, itemID: Int64? = nil) {
            self.trackID = trackID
            self.itemID = itemID
        }
    }

    /// `shuffled` 為 nil ＝ 不寫 `shuffledList`；`shuffleMode` 寫在 items 與頂層兩處（與實檔同）
    static func queue(
        list: [Item],
        shuffled: [Item]? = nil,
        shuffleMode: String = "off",
        segments: Int = 1
    ) -> Data {
        var items: [String: Any] = [
            "list": ["items": ["iar": list.map(entry)]],
            "shuffleMode": shuffleMode,
        ]
        if let shuffled {
            items["shuffledList"] = [
                "items": ["iar": shuffled.map(entry)],
                "shuffleMode": shuffleMode,
                "shuffleTable": Array(0..<shuffled.count),
            ]
        }
        let segment: [String: Any] = ["items": items, "scID": 1, "subcKind": 1]
        let root: [String: Any] = [
            "sega": Array(repeating: segment, count: segments),
            "shuffleMode": shuffleMode,
            "version": 1,
        ]
        return try! PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    /// libraryItemID 以 `PID:0x<小寫 hex>` 表示（與實檔同）；nil ＝ 該項沒有 libraryItemID
    static func history(_ trackIDs: [Int64?]) -> Data {
        let items: [[String: Any]] = trackIDs.map { trackID in
            var identifiers: [String: Any] = [:]
            if let trackID {
                let hex = String(format: "%llx", UInt64(bitPattern: trackID))
                identifiers["libraryItemID"] = "DBID:0x1111111111111111-PID:0x\(hex)-PPID:0x0-PIPID:0x0-IKIND:eSong"
            }
            return ["pm": ["contentDesc": ["identifiers": identifiers, "kind": "song"], "name": "x"], "dKind": 1]
        }
        let root: [String: Any] = ["items": ["iar": items], "version": 1]
        return try! PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    static func pid(_ trackID: Int64) -> String {
        String(format: "%016llX", UInt64(bitPattern: trackID))
    }

    private static func entry(_ item: Item) -> [String: Any] {
        var pm: [String: Any] = ["name": "x", "dKind": 1]
        if let trackID = item.trackID { pm["piObjSpec"] = ["tID": trackID, "pID": 1] }
        var entry: [String: Any] = ["pm": pm, "spcID": 1, "sh": false]
        if let itemID = item.itemID { entry["itID"] = itemID }
        return entry
    }
}
