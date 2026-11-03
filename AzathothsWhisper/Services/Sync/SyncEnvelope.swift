import CryptoKit
import Foundation

/// iCloud 資料夾裡的四種檔（⑨ 計劃 §6.1、§6.3）
enum SyncKind: String, CaseIterable, Sendable {
    case timings, artists, decisions, nolyrics

    var fileName: String { "\(rawValue).json" }

    /// 曲庫 12,271 首全有時間軸約 12 MB（§6.3 實測估算）；其他三類數百 KB 以內
    var maxBytes: Int { self == .timings ? 32 << 20 : 1 << 20 }
}

/// 各類 payload 的形狀：本機存檔格式本身（同一語義只留一處定義）
enum SyncPayload {
    typealias Timings = [TimingRecordFile]
    typealias Artists = [String: ArtistStyleBook.Record]
    typealias Decisions = [String: ArtistDecisionBook.Entry]
    typealias NoLyrics = ConfigStore.NoLyricsMarkLedger

    /// 語義無序的陣列一律排序（R3-5）：寫法、release-group 字典序，曲風依 (name, count)；時間軸錨點有順序，不排
    static func canonicalArtists(_ records: Artists) -> Artists {
        records.mapValues { record in
            ArtistStyleBook.Record(
                spellings: record.spellings.sorted(), mbid: record.mbid, matchedReleaseGroups: record.matchedReleaseGroups.sorted(),
                genres: record.genres.sorted { ($0.name, $0.count) < ($1.name, $1.count) },
                reason: record.reason, fetchedAt: record.fetchedAt, origin: record.origin
            )
        }
    }

    static func canonicalTimings(_ records: [TimingRecord]) -> Timings {
        records.sorted { $0.persistentID < $1.persistentID }.map(TimingRecordFile.init)
    }
}

/// 四檔共通外殼
struct SyncEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    static var schemaVersion: Int { 1 }

    let schemaVersion: Int
    let kind: String
    let writerID: String
    let appVersion: String
    let writtenAt: Date
    let payloadSHA256: String
    let payload: Payload
}

enum SyncCodec {
    enum ReadFailure: Error, Equatable {
        case corrupt, newerSchema, wrongKind, wrongWriter, hashMismatch
    }

    /// 正規形式（R2-B6）：sortedKeys、不 pretty、ISO 8601 秒精度。雜湊＝這段 payload bytes 的 SHA-256
    static func canonicalData<Payload: Encodable>(_ payload: Payload) throws -> Data {
        try encoder.encode(payload)
    }

    static func payloadHash<Payload: Encodable>(_ payload: Payload) -> String {
        guard let data = try? canonicalData(payload) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encode<Payload: Codable & Sendable>(
        _ payload: Payload, kind: SyncKind, writerID: String, appVersion: String, writtenAt: Date
    ) throws -> Data {
        try encoder.encode(SyncEnvelope(
            schemaVersion: SyncEnvelope<Payload>.schemaVersion, kind: kind.rawValue, writerID: writerID, appVersion: appVersion,
            writtenAt: writtenAt, payloadSHA256: payloadHash(payload), payload: payload
        ))
    }

    /// 只解碼、不做逐筆驗證（逐筆驗證在各類的合併函式）。雜湊以解碼後重新正規化的 bytes 比對
    static func decode<Payload: Codable & Sendable>(
        _ data: Data, as type: Payload.Type, kind: SyncKind, expectedWriter: String
    ) -> Result<SyncEnvelope<Payload>, ReadFailure> {
        guard let probe = try? decoder.decode(Probe.self, from: data) else { return .failure(.corrupt) }
        guard probe.schemaVersion <= SyncEnvelope<Payload>.schemaVersion else { return .failure(.newerSchema) }
        guard probe.kind == kind.rawValue else { return .failure(.wrongKind) }
        guard probe.writerID == expectedWriter else { return .failure(.wrongWriter) }
        guard let envelope = try? decoder.decode(SyncEnvelope<Payload>.self, from: data) else { return .failure(.corrupt) }
        guard payloadHash(envelope.payload) == envelope.payloadSHA256 else { return .failure(.hashMismatch) }
        return .success(envelope)
    }

    private struct Probe: Decodable {
        let schemaVersion: Int
        let kind: String
        let writerID: String
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
