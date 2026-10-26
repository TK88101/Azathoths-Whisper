import Foundation

/// 外層訊息的編碼（設計 §4.1）。傳輸層實際送出與曲庫回應的位元組預算共用這一份，量到的就是送出的
public enum Envelope {
    struct Outgoing<Body: Encodable>: Encodable {
        let v: Int
        let id: UUID
        let seq: UInt64?
        let nonce: Data?
        let kind: MessageKind
        let body: Body
    }

    public static func encode<Body: Encodable>(_ kind: MessageKind, _ body: Body, id: UUID = UUID(), seq: UInt64? = nil,
                                               nonce: Data? = nil) -> Data {
        // 自家型別的編碼不會失敗；失敗代表程式錯誤
        try! encoder.encode(Outgoing(v: ProtocolVersion.current, id: id, seq: seq, nonce: nonce, kind: kind, body: body))
    }

    /// 不跳脫 `/`：預設會把 base64 的 `/` 寫成 `\/`，最壞讓封面資料膨脹近 2 倍、超過 64 KiB（T2 實測）。
    /// 解碼端兩種寫法都接受，不影響既有訊息
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return encoder
    }
}

/// 完整訊息位元組預算（sprint-3-detail.md §4.3）：以實際編碼結果二分搜尋能放進預算的最多筆數
public enum ResponseBudget {
    /// `encode(n)` 必須回「放 n 筆時的完整外層訊息」，且大小隨 n 單調不減。連 0 筆都放不下時回 0
    public static func largestFittingCount(upTo maxCount: Int, budget: Int = TransportLimits.responseBudgetBytes,
                                           encode: (Int) -> Data) -> Int {
        guard encode(0).count <= budget else { return 0 }
        var low = 0, high = maxCount
        while low < high {
            let mid = (low + high + 1) / 2
            if encode(mid).count <= budget { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
