import Foundation

/// 每個播放 session 抽一次的亂數來源（B1 計劃 §3.7）；測試注入固定序列
protocol FXNonceSource: AnyObject {
    func next() -> UInt64
}

final class SystemNonceSource: FXNonceSource {
    func next() -> UInt64 {
        UInt64.random(in: .min ... .max)
    }
}
