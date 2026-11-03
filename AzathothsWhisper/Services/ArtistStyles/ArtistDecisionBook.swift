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

/// 存檔與跨機同步的一筆決定（⑨ 計劃 §6.5）：`spellings`＝下決定時畫面上的歌手寫法，匯入時用來驗樂團表（R1-10）
struct ArtistDecisionPayload: Codable, Equatable, Sendable {
    let choice: ArtistDecision.Choice
    let decidedAt: Date
    let spellings: [String]

    var decision: ArtistDecision { ArtistDecision(choice: choice, decidedAt: decidedAt) }
}

/// 使用者決定的不可變集合。鍵＝寫法家族（`ArtistStyleBook.spellingFamily`）：只折疊大小寫、全半形、變音與空白，保留標點。
/// 不同寫法家族永遠是不同鍵，所以這裡不會撞鍵；同 `normalizedArtist` 的其他家族要一併套用時由使用者明示（R4 A-1）。
/// ⑨：每鍵一個 `SyncRegister`，清除＝墓碑（不刪鍵），另一台較舊的決定不會復活
struct ArtistDecisionBook: Equatable, Sendable {
    enum DecisionError: Error, Equatable {
        /// 署名樂團的樣式不在這裡改（計劃 §10-1）
        case signedBand
        case unknownRow
    }

    typealias Entry = SyncRegister<ArtistDecisionPayload>

    /// 可指定的列：曲風列、通用列兩段（使用者拿掉的列本來就不在表內）；畫面選單也讀這一份
    static let selectableRows = (genre: SongProfileResolver.keywordRows.map(\.id), generic: SongProfileResolver.genericRows.map(\.id))
    static let selectableRowIDs: [String] = selectableRows.genre + selectableRows.generic

    private(set) var entries: [String: Entry]

    init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    static func key(_ artist: String) -> String {
        ArtistStyleBook.spellingFamily(artist)
    }

    /// 生效中的決定（墓碑不算）
    var decisions: [String: ArtistDecision] {
        entries.compactMapValues { $0.value?.decision }
    }

    func decision(forArtist artist: String) -> ArtistDecision? {
        entries[Self.key(artist)]?.value?.decision
    }

    /// 同一個決定寫進每個寫法家族；樣式只給非樂團表歌手，且必須是現有的列
    func deciding(_ choice: ArtistDecision.Choice, forArtists artists: [String], at date: Date) throws(DecisionError) -> ArtistDecisionBook {
        try Self.validate(choice, spellings: artists)
        let byKey = Dictionary(grouping: artists.filter { !Self.key($0).isEmpty }, by: Self.key)
        return byKey.reduce(self) { book, group in
            book.setting(ArtistDecisionPayload(choice: choice, decidedAt: date, spellings: Array(Set(group.value)).sorted()), forKey: group.key)
        }
    }

    func clearing(forArtists artists: [String]) -> ArtistDecisionBook {
        Set(artists.map(Self.key)).reduce(self) { book, key in
            guard book.entries[key]?.value != nil else { return book }
            return book.setting(nil, forKey: key)
        }
    }

    /// 匯出、匯入前替本機改動蓋上這台的 writerID（⑨ §6.3）
    func stamped(by writer: String) -> ArtistDecisionBook {
        ArtistDecisionBook(entries: entries.mapValues { $0.stamped(by: writer) })
    }

    /// 匯入：逐鍵取勝者；不合格的遠端筆（鍵與寫法不符、未知列、樂團表給樣式）不採用、保留本機（§6.5）
    func merging(remote: [String: Entry]) -> (book: ArtistDecisionBook, rejected: Int) {
        let valid = remote.filter { Self.isAcceptable($0.value, underKey: $0.key) }
        return (ArtistDecisionBook(entries: SyncRegister.merged(entries, valid)), remote.count - valid.count)
    }

    private func setting(_ payload: ArtistDecisionPayload?, forKey key: String) -> ArtistDecisionBook {
        let next = entries[key].map { $0.updated(to: payload) } ?? Entry.fresh(payload)
        return ArtistDecisionBook(entries: entries.merging([key: next]) { _, new in new })
    }

    private static func validate(_ choice: ArtistDecision.Choice, spellings: [String]) throws(DecisionError) {
        guard case .style(let rowID) = choice else { return }
        guard selectableRowIDs.contains(rowID) else { throw .unknownRow }
        guard spellings.allSatisfy(SongProfileResolver.needsArtistGenres) else { throw .signedBand }
    }

    /// 遠端與本機載入共用（安全評審 HIGH-1、LOW-6）：版本合法、鍵是寫法家族格式且長度有限；有值時寫法都落在這個鍵、選擇合法
    static func isAcceptable(_ entry: Entry, underKey key: String, allowUnstamped: Bool = false) -> Bool {
        guard entry.version.isAcceptable(allowUnstamped: allowUnstamped), !key.isEmpty, key.count <= TrackMatcher.maxNameLength,
              Self.key(key) == key
        else { return false }
        guard let payload = entry.value else { return true }
        guard !payload.spellings.isEmpty, payload.spellings.count <= ArtistStyleBook.maxSpellings,
              payload.spellings.allSatisfy({ Self.key($0) == key })
        else { return false }
        // 本機載入不驗選擇本身（安全複查 N9）：日後某列被拿掉或歌手進了樂團表，使用者的舊決定不得在載入時被默默丟掉
        return allowUnstamped || (try? validate(payload.choice, spellings: payload.spellings)) != nil
    }

}
