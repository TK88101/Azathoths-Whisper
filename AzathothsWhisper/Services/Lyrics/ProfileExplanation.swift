import Foundation

/// 一首歌的解決來源（⑧ 曲庫閘門計劃 §4.2）：判定結果＋顯示用的 key＋每一層試過什麼。
/// 由 `SongProfileResolver.explain` 產生；`resolve` 只取其中的 `resolution`，兩者是同一份判定
struct ProfileExplanation: Equatable, Sendable {
    /// 曲風列命中的層
    enum Layer: String, Sendable {
        /// `userStyle`＝使用者指定的列（計劃 §4.3）
        case userStyle, mbGenre, appleGenre, genericMB, genericApple
    }

    enum Key: Hashable, Sendable {
        case signed(String)
        case jpop
        /// ids＝合成實際用到的列（排序；generic 抑制之後）
        case rows(Layer, [String])
        case userStyle(String)
        case none
        case pending
    }

    /// 可讀性稽核用的鍵：不分層——同一組列不論從哪層命中，合成的目標值與配方空間都相同（計劃 §4.2、R4 B-1）
    enum AuditKey: Hashable, Sendable {
        case signed(String)
        case jpop
        case rows([String])
    }

    enum Outcome: Equatable, Sendable {
        /// `rejectedByReadability`＝組得出但 G1–G3 不及格（`ReadabilityPolicy.rejected`），同組不出一樣落下一層
        case adopted, notComposable, rejectedByReadability, noHit
    }

    struct Attempt: Equatable, Sendable {
        let layer: Layer
        let rowIDs: [String]
        let outcome: Outcome
    }

    let resolution: ProfileResolution
    let key: Key
    let trace: [Attempt]

    var auditKey: AuditKey? {
        switch key {
        case .signed(let name): .signed(name)
        case .jpop: .jpop
        case .rows(_, let ids): .rows(ids)
        case .userStyle(let id): .rows([id])
        case .none, .pending: nil
        }
    }
}
