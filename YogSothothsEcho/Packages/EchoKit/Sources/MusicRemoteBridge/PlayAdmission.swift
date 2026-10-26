#if os(macOS)
import Foundation
import RemoteProtocol

// 點歌的許可閘門與期待序列（設計 §5.3-1、CR-005；sprint-4-detail.md §4.5 步驟 1）。
// 自 S0 `Spike/Sources/SpikeCore/FP01.swift` 的 ShortcutGate／AlbumSuffix 移植；正規化改用 TextFold（同一語義只留一處）。
// 捷徑只能以專輯名查找，播放前無法證明撈到的是這張專輯的 ID 序列，所以只在「名稱查找必定只撈到這張」時才放行；
// 正規化刻意從寬（TextFold 還會併片假名／平假名）：寧可多降級。

public struct AlbumTrackRef: Sendable, Equatable {
    public let id: String
    /// 0＝未填，視為第 1 片
    public let disc: Int
    public let number: Int

    public init(id: String, disc: Int, number: Int) {
        self.id = id
        self.disc = disc
        self.number = number
    }
}

/// 期待值＝ITLibrary 依專輯身分算出的「第 k 首至末尾」ID 序列（不依文字比對）
public enum AlbumSuffix {
    /// 依 disc、曲序排序；曲序缺漏或同一位置重複＝順序無定義，回 nil
    public static func ordered(_ songs: [AlbumTrackRef]) -> [String]? {
        let keyed = songs.map { (key: [max($0.disc, 1), $0.number], id: $0.id) }
        guard keyed.allSatisfy({ $0.key[1] > 0 }), Set(keyed.map(\.key)).count == keyed.count else { return nil }
        return keyed.sorted { $0.key.lexicographicallyPrecedes($1.key) }.map(\.id)
    }

    /// 1 起算的位置（捷徑的輸入）
    public static func position(of id: String, in songs: [AlbumTrackRef]) -> Int? {
        ordered(songs)?.firstIndex(of: id).map { $0 + 1 }
    }

    public static func expected(_ songs: [AlbumTrackRef], from id: String) -> [String]? {
        guard let order = ordered(songs), let start = order.firstIndex(of: id) else { return nil }
        return Array(order[start...])
    }
}

public enum PlayAdmission {
    /// 去前後空白後 TextFold（NFKC、不分大小寫／全半形／重音、片假名併平假名）
    static func normalize(_ title: String) -> String {
        TextFold.fold(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 正規化專輯名 → 用到這個名稱的專輯 ID；以「每個項目」的專輯名建，不分媒體種類
    public static func titleIndex(_ entries: [(title: String, albumID: String)]) -> [String: Set<String>] {
        // 先依原字串合併再正規化：每首歌都帶專輯名，逐首 fold（NFKC＋假名轉換）是專輯數的數倍
        let byRaw = entries.reduce(into: [String: Set<String>]()) { $0[$1.title, default: []].formUnion([$1.albumID]) }
        return byRaw.reduce(into: [:]) { index, item in index[normalize(item.key), default: []].formUnion(item.value) }
    }

    /// nil＝可交給捷徑；否則回 gate* 降級原因
    public static func check(albumID: String, albumTitles: [String], songs: [AlbumTrackRef],
                             titleIndex: [String: Set<String>]) -> PlayReason? {
        guard let title = albumTitles.first, !title.isEmpty else { return .gateEmptyTitle }
        guard albumTitles.allSatisfy({ $0 == title }) else { return .gateInconsistentTitle }
        guard AlbumSuffix.ordered(songs) != nil else { return .gateOrderUndefined }
        guard titleIndex[normalize(title)] == [albumID] else { return .gateAmbiguousTitle }
        return nil
    }
}

/// 捷徑的輸入（沿用 S0 `ShortcutInput` 的欄位與 JSON 形狀：鍵排序、UTF-8）
public struct ShortcutInput: Codable, Sendable, Equatable {
    public let album: String
    /// 空字串＝未填
    public let albumArtist: String
    /// 全專輯曲目藝人一致時才填，否則空字串（合輯）
    public let artist: String
    /// 1 起算
    public let position: Int
    /// 捷徑查到的首數不等於它就停止、不播
    public let expectedCount: Int

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

/// 放行專輯的捷徑計畫：點歌開始執行時（§4.5 步驟 1）以當下索引算出並繫結在這筆請求上，之後換版不影響
public struct ShortcutPlan: Sendable, Equatable {
    public let album: String
    public let albumArtist: String
    public let artist: String
    /// 依 disc、曲序排好的曲目 ID
    public let order: [String]

    public func input(startingAt id: String) -> ShortcutInput? {
        guard let index = order.firstIndex(of: id) else { return nil }
        return ShortcutInput(album: album, albumArtist: albumArtist, artist: artist, position: index + 1, expectedCount: order.count)
    }

    public func expected(from id: String) -> [String]? {
        order.firstIndex(of: id).map { Array(order[$0...]) }
    }
}

public enum AdmissionResult: Sendable, Equatable {
    case admitted(ShortcutPlan)
    case refused(PlayReason)
}
#endif
