import Foundation

/// 同歌手 Apple 曲風共識（增補計劃 §4.2；使用者 2026-10-28：「以相同的樂團或相同的藝人去做分類就行」）。
/// 每個寫法家族、每個 tier 各自計票；證據只取「沒有共識時實際被該 Apple 層採用」的曲（R3-2、R3-4），
/// 證據 ≥ 2 首且勝出的列組合嚴格過半才採用。不可變、可落盤
struct AppleGenreConsensus: Codable, Equatable, Sendable {
    /// `genreRows`＝取代逐曲 Apple 曲風列；`genericRows`＝取代逐曲通用 Apple 列。層與 tier 的對應只定義在這裡
    enum Tier: CaseIterable, Sendable {
        case genreRows, genericRows

        /// 證據來源：沒有共識時，曲子自己的 Apple 曲風被這一層採用
        var appleLayer: ProfileExplanation.Layer {
            switch self {
            case .genreRows: .appleGenre
            case .genericRows: .genericApple
            }
        }

        /// 採用共識時記在 key／trace 的層
        var consensusLayer: ProfileExplanation.Layer {
            switch self {
            case .genreRows: .appleConsensus
            case .genericRows: .genericAppleConsensus
            }
        }
    }

    struct Vote: Codable, Equatable, Sendable {
        /// 勝出的列組合（排序；與證據曲的 key 相同）
        let rowIDs: [String]
        let votes: Int
        let evidence: Int

        /// 非空、不重複、不比列目錄長（存檔可能被竄改；安全評審 L2）
        func isWellFormed(maxRows: Int) -> Bool {
            !rowIDs.isEmpty && rowIDs.count <= maxRows && Set(rowIDs).count == rowIDs.count
        }
    }

    /// 一首證據曲：它所屬的家族、被哪個 Apple 層採用、用了哪幾列
    struct Evidence: Equatable, Sendable {
        let familyKey: String
        let tier: Tier
        let rowIDs: [String]
    }

    static let minimumEvidence = 2

    let genreRows: Vote?
    let genericRows: Vote?

    /// 兩個 tier 都沒有票＝沒有共識（nil）
    static func nonEmpty(genreRows: Vote?, genericRows: Vote?) -> AppleGenreConsensus? {
        genreRows == nil && genericRows == nil ? nil : AppleGenreConsensus(genreRows: genreRows, genericRows: genericRows)
    }

    func vote(for tier: Tier) -> Vote? {
        switch tier {
        case .genreRows: genreRows
        case .genericRows: genericRows
        }
    }

    /// 只有曲子自己的 Apple 兩層算證據：共識結果本身、J-Pop、署名、使用者樣式、MB 都不算
    static func evidenceTier(of key: ProfileExplanation.Key) -> Tier? {
        guard case .rows(let layer, _) = key else { return nil }
        return Tier.allCases.first { $0.appleLayer == layer }
    }

    /// 家族鍵 → 共識；兩個 tier 都沒過門檻的家族不列
    static func table(_ evidence: [Evidence]) -> [String: AppleGenreConsensus] {
        Dictionary(grouping: evidence, by: \.familyKey).compactMapValues { items in
            nonEmpty(genreRows: winner(items.filter { $0.tier == .genreRows }), genericRows: winner(items.filter { $0.tier == .genericRows }))
        }
    }

    /// 泛用曲風列（metal…）：家族裡有任何具體命中時不算票（U3 實測：否則黑金屬會被多數的 metal 蓋掉）
    private static let genericRowIDs = Set(SongProfileResolver.keywordRows.filter(\.isGeneric).map(\.id))

    /// 嚴格過半已排除平手，所以勝者唯一
    private static func winner(_ all: [Evidence]) -> Vote? {
        let items = SongProfileResolver.preferSpecific(all) { $0.rowIDs.allSatisfy(genericRowIDs.contains) }
        guard items.count >= minimumEvidence else { return nil }
        let counts = Dictionary(items.map { ($0.rowIDs, 1) }, uniquingKeysWith: +)
        guard let top = counts.first(where: { $0.value * 2 > items.count }) else { return nil }
        return Vote(rowIDs: top.key, votes: top.value, evidence: items.count)
    }
}

extension ProfileExplanation.Layer {
    /// 這一層若是同歌手共識，用的是哪個 tier 的票
    var consensusTier: AppleGenreConsensus.Tier? {
        AppleGenreConsensus.Tier.allCases.first { $0.consensusLayer == self }
    }
}
