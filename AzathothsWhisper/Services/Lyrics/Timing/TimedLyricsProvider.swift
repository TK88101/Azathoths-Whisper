import Foundation

/// 「這次問不到」——與「沒有」不同：失敗不得換成 7 天的 notFound（C 段計劃 §3.5）
enum ProviderFailure: Error, Equatable, Sendable {
    case rateLimited(retryAfter: TimeInterval?)
    case blocked(status: Int)
    case server(status: Int)
    case transport
    case timedOut
    case unparsable
    case cancelled
    case circuitOpen
}

/// 這個來源明確回答「沒有可用的時間軸」（可存成 notFound 的一部分）
enum NoTimingReason: String, Equatable, Sendable {
    case notFound
    /// 有候選，但歌手／曲名／時長／版本對不上（TrackMatcher）
    case mismatch
    /// 配對正確，只有純文字
    case plainOnly
    /// 驗證後帶時間的行少於 3 行（C 段計劃 §3.7）
    case tooFewLines
    /// 行數超過上限：不是一首歌的歌詞（安全評審 MEDIUM-1，防對齊被拖住）
    case oversized
}

enum ProviderOutcome: Equatable, Sendable {
    /// 帶時間的行（只在記憶體，不落地；只借時間、不借文字）
    case timed([LRCLine], matched: MatchedTrack)
    case noTiming(NoTimingReason)

    static let minimumTimedLines = 3
    /// 對齊是 O(行數 × 字數²)：外部 LRC 的行數與單行長度都要有上限（安全評審 MEDIUM-1）
    static let maximumTimedLines = 2000
    static let maximumLineLength = 500

    /// 文字型 LRC 的共用收尾：空白＝notFound、沒有時間標籤＝plainOnly、否則解析後走 `timed`
    static func fromLRCText(_ text: String, matched: MatchedTrack, duration: Double) -> ProviderOutcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .noTiming(.notFound) }
        guard LRCParser.isLRC(text) else { return .noTiming(.plainOnly) }
        return .validatedTiming(LRCParser.parse(text), matched: matched, duration: duration)
    }

    /// 所有來源的唯一出口：外部 cue 先過 `LRCAligner.sanitizedCues`、去掉製作資訊行（`LyricCredits`），
    /// 剩下的非空行少於 3 行＝tooFewLines
    static func validatedTiming(_ lines: [LRCLine], matched: MatchedTrack, duration: Double) -> ProviderOutcome {
        guard lines.count <= maximumTimedLines else { return .noTiming(.oversized) }
        let clean = LRCAligner.sanitizedCues(lines, duration: duration)
            .filter { $0.text.count <= maximumLineLength && !LyricCredits.isCredit($0.text) }
        guard clean.filter({ !LRCAligner.normalized($0.text).isEmpty }).count >= minimumTimedLines else { return .noTiming(.tooFewLines) }
        return .timed(clean, matched: matched)
    }
}

/// 一個外部時間軸來源（C 段計劃 §3.2）。對外只送 `TimingQuery` 的三樣；每個請求都經過自己的 `SourceGate`
protocol TimedLyricsProvider: Sendable {
    var source: StoredTimingSource { get }
    func lookup(_ query: TimingQuery) async throws(ProviderFailure) -> ProviderOutcome
}

/// 來源搜尋結果裡的一筆候選：比對用的曲目資料＋該來源取歌詞要用的 ID
struct TimingCandidate: Sendable {
    let track: MatchedTrack
    let id: String

    /// 每個來源最多看前幾筆候選（比對要做 folding 與 regex；回應可帶上萬筆）。全專案唯一的上限：
    /// 來源解析時不自行截斷，請求的 page size 也用它；LRCLIB 的「唯一」判定同樣只看前這幾筆
    static let limit = 10

    /// 前 `limit` 筆中第一個通過 `TrackMatcher` 的候選
    static func pick(_ candidates: [TimingCandidate], for query: TimingQuery) -> TimingCandidate? {
        candidates.prefix(limit).first { TrackMatcher.matches(query, $0.track) }
    }
}

extension NoTimingReason {
    /// 沒有候選＝notFound；有候選但都對不上＝mismatch
    static func miss(among candidateCount: Int) -> NoTimingReason {
        candidateCount == 0 ? .notFound : .mismatch
    }
}

/// 中文平台 LRC 開頭常見的製作資訊行（作词：…）：不是歌詞，留著會拉低 LRC 側覆蓋率（C 段計劃 §3.4）。
/// 所有來源共用：在 `ProviderOutcome.validatedTiming` 唯一出口過濾
enum LyricCredits {
    private static var credit: Regex<Substring> {
        /^\s*(?:作词|作詞|作曲|编曲|編曲|制作人|製作人|词|詞|曲|lyrics\s+by|composed\s+by|written\s+by|arranged\s+by|produced\s+by|producer)\s*[:：]/
            .ignoresCase()
    }

    static func isCredit(_ line: String) -> Bool {
        line.firstMatch(of: credit) != nil
    }
}

extension HTTPRequest {
    /// 時間軸來源的 GET：查詢參數依名稱排序（快取鍵穩定）。逾時由 `SourceGate` 一律覆蓋，這裡只填佔位
    static func timingGET(_ url: URL, query: [String: String] = [:], headers: [String: String] = [:]) -> HTTPRequest {
        let items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return HTTPRequest(
            method: "GET", url: items.isEmpty ? url : url.appending(queryItems: items), headers: headers,
            timeout: SourceGate.Policy.defaultTimeout
        )
    }

    static func timingPOST(_ url: URL, body: Data, headers: [String: String]) -> HTTPRequest {
        HTTPRequest(method: "POST", url: url, headers: headers, body: body, timeout: SourceGate.Policy.defaultTimeout)
    }
}

extension HTTPResponse {
    /// 200 的本文；其他狀態（gate 已把 429／403／5xx 轉成失敗）一律當伺服器異常
    func okBody() throws(ProviderFailure) -> String {
        guard statusCode == 200 else { throw .server(status: statusCode) }
        return body
    }
}

/// 回應 JSON 的寬鬆讀取（非公開介面的形狀會變：讀不到的欄位一律當沒有，不崩潰）
enum TimingJSON {
    static func data(_ object: [String: Any]) throws(ProviderFailure) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { throw .unparsable }
        return data
    }

    static func dictionary(_ body: String) throws(ProviderFailure) -> [String: Any] {
        guard let value = try object(body) as? [String: Any] else { throw .unparsable }
        return value
    }

    static func array(_ body: String) throws(ProviderFailure) -> [[String: Any]] {
        guard let value = try object(body) as? [[String: Any]] else { throw .unparsable }
        return value
    }

    static func object(_ body: String) throws(ProviderFailure) -> Any {
        guard let data = body.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw .unparsable
        }
        return value
    }

    /// 深度優先找出所有名為 `key` 的值（YouTube Music 的回應層級很深且常變）
    static func values(forKey key: String, in value: Any) -> [Any] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { entry -> [Any] in
                (entry.key == key ? [entry.value] : []) + values(forKey: key, in: entry.value)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap { values(forKey: key, in: $0) }
        }
        return []
    }

    /// 非有限值（"nan"、"inf"、"1e999"、超長數字）一律當沒有：下游不得靠 `abs(inf − x)` 碰巧為假
    static func double(_ value: Any?) -> Double? {
        let number: Double?
        switch value {
        case let boxed as NSNumber: number = boxed.doubleValue
        case let text as String: number = Double(text)
        default: number = nil
        }
        return number.flatMap { $0.isFinite ? $0 : nil }
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}
