import Foundation

// F-P-01 點歌脈絡（s0-report.md「F-P-01 點歌脈絡：N1 後續方案」）。
// ③＝中繼以 `shortcuts run` 執行使用者建立的捷徑；通過條件三項各自判定：曲目正確、Mac 段延遲、佇列正確。

public struct AlbumTrack: Sendable, Equatable {
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
    public static func ordered(_ tracks: [AlbumTrack]) -> [String]? {
        let keyed = tracks.map { (key: [max($0.disc, 1), $0.number], id: $0.id) }
        guard keyed.allSatisfy({ $0.key[1] > 0 }), Set(keyed.map(\.key)).count == keyed.count else { return nil }
        return keyed.sorted { $0.key.lexicographicallyPrecedes($1.key) }.map(\.id)
    }

    /// 1 起算的位置（捷徑的輸入）
    public static func position(of id: String, in tracks: [AlbumTrack]) -> Int? {
        ordered(tracks)?.firstIndex(of: id).map { $0 + 1 }
    }

    public static func expected(_ tracks: [AlbumTrack], from id: String) -> [String]? {
        guard let order = ordered(tracks), let start = order.firstIndex(of: id) else { return nil }
        return Array(order[start...])
    }
}

public struct QueueRead: Sendable, Equatable {
    public let at: Double
    /// nil＝讀不到或不是順序模式
    public let ids: [String]?

    public init(at: Double, ids: [String]?) {
        self.at = at
        self.ids = ids
    }
}

/// Queue.dat 會延遲數秒才寫：同一序列連續讀到、且跨越 minGap 秒才算穩定；中間有不同或讀不到就重新起算
public enum QueueSettle {
    public static func stable(_ reads: [QueueRead], minGap: Double) -> [String]? {
        var runStart: QueueRead?
        for read in reads {
            guard let ids = read.ids else { runStart = nil; continue }
            guard let start = runStart, start.ids == ids else { runStart = read; continue }
            if read.at - start.at >= minGap { return ids }
        }
        return nil
    }
}

/// 一個 ③ 樣本：只記 ID 與數值，不記曲名或專輯名
public struct FP01Sample: Codable, Sendable, Equatable {
    public let albumID: String
    public let position: Int
    public let trackCount: Int
    public let multiDisc: Bool
    /// 曲庫中有另一張同名（不分大小寫）的專輯：只靠專輯名查找會撞
    public let sharedTitle: Bool
    public let exitCode: Int32?
    /// `shortcuts run` 發起 → Music 正在播目標曲；nil＝逾時
    public let latencyMilliseconds: Double?
    public let readID: String?
    public let state: PlayerStateValue?
    public let expectedStartID: String
    public let settledQueue: [String]?
    public let expectedQueue: [String]

    public init(albumID: String, position: Int, trackCount: Int, multiDisc: Bool, sharedTitle: Bool,
                exitCode: Int32?, latencyMilliseconds: Double?, readID: String?, state: PlayerStateValue?,
                expectedStartID: String, settledQueue: [String]?, expectedQueue: [String]) {
        self.albumID = albumID
        self.position = position
        self.trackCount = trackCount
        self.multiDisc = multiDisc
        self.sharedTitle = sharedTitle
        self.exitCode = exitCode
        self.latencyMilliseconds = latencyMilliseconds
        self.readID = readID
        self.state = state
        self.expectedStartID = expectedStartID
        self.settledQueue = settledQueue
        self.expectedQueue = expectedQueue
    }

    public var trackCorrect: Bool { readID == expectedStartID && state == .playing }
    public var queueCorrect: Bool { settledQueue == expectedQueue }
}

public enum FP01Verdict {
    public enum Outcome: String, Codable, Sendable { case pass, latencyOnly, fail, undetermined }

    public static let requiredSamples = 20
    /// Mac 段門檻（N-01：Mac 端 p95 > 300 ms 要開 CR）；E2E ≤ 500 ms 留 S4
    public static let maxP95Milliseconds = 300.0

    public static func judge(_ samples: [FP01Sample]) -> Outcome {
        guard samples.count >= requiredSamples else { return .undetermined }
        guard samples.allSatisfy({ $0.trackCorrect && $0.queueCorrect }) else { return .fail }
        // 逾時（5 s 內沒播到目標曲）不靠 p95 稀釋：同 B6，任一逾時即延遲不達標
        let latencies = samples.compactMap(\.latencyMilliseconds)
        guard latencies.count == samples.count, let p95 = Stats.percentile(latencies, 0.95),
              p95 <= maxP95Milliseconds
        else { return .latencyOnly }
        return .pass
    }
}

/// 捷徑的輸入：鍵排序、UTF-8 JSON，特殊字元由 JSON 跳脫，無歧義
public struct ShortcutInput: Codable, Sendable, Equatable {
    public let album: String
    /// 曲庫約半數專輯沒填（2026-10-15 fp01-catalog：446／1000），空字串＝未填
    public let albumArtist: String
    /// 全專輯曲目藝人一致時才填，否則空字串（合輯）
    public let artist: String
    /// 依 disc、曲序排序後的 1 起算位置
    public let position: Int
    /// 專輯總首數：捷徑查找結果的首數不等於它就停止、不播（YSE-play2）
    public let expectedCount: Int

    public init(album: String, albumArtist: String, artist: String, position: Int, expectedCount: Int) {
        self.album = album
        self.albumArtist = albumArtist
        self.artist = artist
        self.position = position
        self.expectedCount = expectedCount
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

/// 捷徑許可閘門（2026-10-15 Codex 2 輪收斂）：捷徑只能以專輯名查找，無法在播放前證明撈到的是這張專輯的 ID 序列，
/// 所以只在「名稱查找必定只撈到這張」時才交給捷徑；其餘降級為只播這首（①）。正規化刻意從寬：寧可多降級
public enum ShortcutGate {
    public enum Refusal: String, Codable, Sendable, CaseIterable {
        case emptyTitle, inconsistentTitle, ambiguousTitle, orderUndefined
    }

    /// NFKC（全半角）→ 去重音 → 不分大小寫 → 去前後空白。ソート名不比（Music 的「アルバム が次と等しい」是否看它無證據）
    public static func normalize(_ title: String) -> String {
        title.precomposedStringWithCompatibilityMapping
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 正規化專輯名 → 用到這個名稱的專輯 ID；以「每首曲目」的專輯名建，不分媒體種類（查找可能撈到的都算）
    public static func titleIndex(_ entries: [(title: String, albumID: String)]) -> [String: Set<String>] {
        entries.reduce(into: [:]) { index, entry in index[normalize(entry.title), default: []].formUnion([entry.albumID]) }
    }

    /// nil＝可交給捷徑
    public static func check(albumID: String, trackTitles: [String], tracks: [AlbumTrack],
                             titleIndex: [String: Set<String>]) -> Refusal? {
        guard let title = trackTitles.first, !title.isEmpty else { return .emptyTitle }
        guard trackTitles.allSatisfy({ $0 == title }) else { return .inconsistentTitle }
        guard AlbumSuffix.ordered(tracks) != nil else { return .orderUndefined }
        guard titleIndex[normalize(title)] == [albumID] else { return .ambiguousTitle }
        return nil
    }
}

/// 樣本選法：專輯依類型分層（StratifiedSampler 每層先取 1 張），起點 k 依種子決定
public enum FP01Plan {
    public static let seed: UInt64 = 20_261_015

    public static func kind(multiDisc: Bool, sharedTitle: Bool) -> String {
        multiDisc ? "multi-disc" : sharedTitle ? "shared-title" : "plain"
    }

    /// 1…n-1（佇列至少剩 2 首）；n < 2 的專輯不該進樣本
    public static func startPosition(trackCount: Int, sampleIndex: Int, seed: UInt64) -> Int {
        guard trackCount >= 2 else { return 1 }
        var generator = SeededGenerator(seed: seed &+ UInt64(sampleIndex))
        return Int.random(in: 1...(trackCount - 1), using: &generator)
    }
}
