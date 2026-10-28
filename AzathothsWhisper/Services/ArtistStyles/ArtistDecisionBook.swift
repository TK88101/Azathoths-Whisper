import Foundation

/// 使用者對一位歌手的決定（⑧ 曲庫閘門計劃 §4.3）
struct ArtistDecision: Codable, Equatable, Sendable {
    enum Choice: Codable, Equatable, Sendable {
        /// 樂團指定：單一曲風列或通用列（單列都在可讀性稽核清單內）
        case style(rowID: String)
        /// 身分不認、照目前樣式：只解除「身分未定」，不改判定
        case keepFallback
    }

    let choice: Choice
    let decidedAt: Date
}

/// 使用者決定的不可變集合。鍵＝寫法家族（`ArtistStyleBook.spellingFamily`）：只折疊大小寫、全半形、變音與空白，保留標點。
/// 不同寫法家族永遠是不同鍵，所以這裡不會撞鍵；同 `normalizedArtist` 的其他家族要一併套用時由使用者明示（R4 A-1）
struct ArtistDecisionBook: Equatable, Sendable {
    enum DecisionError: Error, Equatable {
        /// 署名樂團的樣式不在這裡改（計劃 §10-1）
        case signedBand
        case unknownRow
    }

    /// 可指定的列：曲風列＋通用列（使用者拿掉的列本來就不在表內）
    static let selectableRowIDs: [String] = (SongProfileResolver.keywordRows + SongProfileResolver.genericRows).map(\.id)

    private(set) var decisions: [String: ArtistDecision]

    init(decisions: [String: ArtistDecision] = [:]) {
        self.decisions = decisions
    }

    static func key(_ artist: String) -> String {
        ArtistStyleBook.spellingFamily(artist)
    }

    func decision(forArtist artist: String) -> ArtistDecision? {
        decisions[Self.key(artist)]
    }

    /// 同一個決定寫進每個寫法家族；樣式只給非樂團表歌手，且必須是現有的列
    func deciding(_ choice: ArtistDecision.Choice, forArtists artists: [String], at date: Date) throws(DecisionError) -> ArtistDecisionBook {
        if case .style(let rowID) = choice {
            guard Self.selectableRowIDs.contains(rowID) else { throw .unknownRow }
            guard artists.allSatisfy(SongProfileResolver.needsArtistGenres) else { throw .signedBand }
        }
        let keys = artists.map(Self.key).filter { !$0.isEmpty }
        let decision = ArtistDecision(choice: choice, decidedAt: date)
        return ArtistDecisionBook(decisions: decisions.merging(keys.map { ($0, decision) }) { _, new in new })
    }

    func clearing(forArtists artists: [String]) -> ArtistDecisionBook {
        let keys = Set(artists.map(Self.key))
        return ArtistDecisionBook(decisions: decisions.filter { !keys.contains($0.key) })
    }
}
