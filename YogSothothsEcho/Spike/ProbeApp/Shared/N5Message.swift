import Foundation

/// N5 的固定訊息格式：`YSE-N5:` + 6 位數 challenge + 換行（明文 TCP，不承載機密；N5 不驗 TLS）。
/// Mac 端 `Sources/yse-spike/N5Listen.swift` 經 Spike 套件依賴本模組，收發兩端共用同一份格式。
public enum N5Message {
    /// Bonjour 服務類型（n5-listen 廣播、iPad 探針瀏覽）
    public static let serviceType = "_yse._tcp"
    public static let prefix = "YSE-N5:"
    public static let challengeLength = 6
    /// 一行訊息的上限（前綴 7 ＋ 6 位數 ＋ CRLF 2 ＝ 15，留餘裕）；超過仍無換行視為垃圾
    public static let maxFrameBytes = 32

    public enum Frame: Equatable, Sendable {
        case needMore
        case challenge(String)
        case invalid
    }

    /// 只收 ASCII 0-9 且恰好 6 位（拒絕全形數字等 Unicode 數字）
    public static func isValidChallenge(_ text: String) -> Bool {
        text.utf8.count == challengeLength && text.utf8.allSatisfy { (0x30...0x39).contains($0) }
    }

    /// 6 位數 challenge（只供肉眼比對，不是秘密；Int.random 用系統安全亂數、無取模偏差）
    public static func makeChallenge() -> String {
        String(format: "%06d", Int.random(in: 0..<1_000_000))
    }

    public static func make(challenge: String) -> String? {
        guard isValidChallenge(challenge) else { return nil }
        return prefix + challenge + "\n"
    }

    /// 單行解析：容許結尾一個 LF 或 CRLF，其餘多餘內容一律拒絕。
    /// 以 UTF-8 位元組處理：Swift 的 Character 會把 "\r\n" 合成一個字元，字元計數會錯。
    public static func parse(_ raw: String) -> String? {
        var bytes = Array(raw.utf8)
        if bytes.last == 0x0A {
            bytes.removeLast()
            if bytes.last == 0x0D { bytes.removeLast() }
        }
        let head = Array(prefix.utf8)
        guard bytes.count == head.count + challengeLength, bytes.starts(with: head),
              let challenge = String(bytes: bytes.dropFirst(head.count), encoding: .utf8) else { return nil }
        return isValidChallenge(challenge) ? challenge : nil
    }

    /// 串流接收用：TCP 可能分段到達，累積到出現換行才判定
    public static func frame(_ buffer: Data) -> Frame {
        guard let newline = buffer.firstIndex(of: 0x0A) else {
            return buffer.count > maxFrameBytes ? .invalid : .needMore
        }
        let line = buffer[buffer.startIndex...newline]
        guard line.count <= maxFrameBytes, let text = String(data: line, encoding: .utf8),
              let challenge = parse(text) else { return .invalid }
        return .challenge(challenge)
    }
}
