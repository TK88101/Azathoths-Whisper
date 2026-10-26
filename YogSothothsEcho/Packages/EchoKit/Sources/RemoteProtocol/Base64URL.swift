import Foundation

// RFC 4648 §5 base64url（無 padding）；QR 載荷與曲庫 cursor 共用（同一語義只留一處；只接受正規編碼）
extension Data {
    public init?(base64URL text: String) {
        guard !text.isEmpty,
              text.unicodeScalars.allSatisfy({ CharacterSet.base64URLAlphabet.contains($0) }),
              text.count % 4 != 1 else { return nil }
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
        guard let data = Data(base64Encoded: standard) else { return nil }
        // 拒絕非正規編碼（尾端多餘位元）：重新編碼必須一致
        guard data.base64URLEncoded() == text else { return nil }
        self = data
    }

    public func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    static let base64URLAlphabet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
}
