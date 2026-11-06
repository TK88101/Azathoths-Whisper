import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.3：四檔共通外殼＋正規形式雜湊；讀他機檔的防線（writerID／kind／雜湊／版本／大小）
@Suite("Sync envelope")
struct SyncEnvelopeTests {
    static let writer = "000000000000000a"
    static let at = Date(timeIntervalSince1970: 1_790_000_000)
    typealias Marks = SyncPayload.NoLyrics

    private let marks: Marks = ["AAAA000000000001": SyncRegister(value: true, version: SyncVersion(revision: 1, origin: writer))]

    private func encoded(_ payload: Marks = [:], kind: SyncKind = .nolyrics, writer: String = writer) throws -> Data {
        try SyncCodec.encode(payload, kind: kind, writerID: writer, appVersion: "3.1.0", writtenAt: Self.at)
    }

    @Test func itRoundTrips() throws {
        let data = try encoded(marks)
        let envelope = try SyncCodec.decode(data, as: Marks.self, kind: .nolyrics, expectedWriter: Self.writer).get()
        #expect(envelope.payload == marks)
        #expect(envelope.writtenAt == Self.at)
        #expect(envelope.payloadSHA256 == SyncCodec.payloadHash(marks))
    }

    @Test func theHashDoesNotDependOnInsertionOrder() throws {
        var forward: Marks = [:]
        var backward: Marks = [:]
        let keys = (1...20).map { String(format: "AAAA%012d", $0) }
        for key in keys { forward[key] = SyncRegister(value: true, version: SyncVersion(revision: 1, origin: Self.writer)) }
        for key in keys.reversed() { backward[key] = SyncRegister(value: true, version: SyncVersion(revision: 1, origin: Self.writer)) }
        #expect(SyncCodec.payloadHash(forward) == SyncCodec.payloadHash(backward))
    }

    @Test func aFileInTheWrongWritersFolderIsRejected() throws {
        let data = try encoded(marks)
        #expect(throws: SyncCodec.ReadFailure.wrongWriter) {
            try SyncCodec.decode(data, as: Marks.self, kind: .nolyrics, expectedWriter: "000000000000000b").get()
        }
    }

    @Test func aFileOfAnotherKindIsRejected() throws {
        let data = try encoded([:], kind: .decisions)
        #expect(throws: SyncCodec.ReadFailure.wrongKind) {
            try SyncCodec.decode(data, as: Marks.self, kind: .nolyrics, expectedWriter: Self.writer).get()
        }
    }

    @Test func aTamperedPayloadFailsTheHash() throws {
        let text = String(decoding: try encoded(marks), as: UTF8.self).replacingOccurrences(of: "\"revision\":1", with: "\"revision\":9")
        #expect(throws: SyncCodec.ReadFailure.hashMismatch) {
            try SyncCodec.decode(Data(text.utf8), as: Marks.self, kind: .nolyrics, expectedWriter: Self.writer).get()
        }
    }

    @Test func aNewerSchemaIsSkipped() throws {
        let text = String(decoding: try encoded(marks), as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
        #expect(throws: SyncCodec.ReadFailure.newerSchema) {
            try SyncCodec.decode(Data(text.utf8), as: Marks.self, kind: .nolyrics, expectedWriter: Self.writer).get()
        }
    }

    @Test(arguments: ["", "not json", "{\"schemaVersion\":1}", "[]"])
    func garbageIsCorrupt(_ text: String) {
        #expect(throws: SyncCodec.ReadFailure.corrupt) {
            try SyncCodec.decode(Data(text.utf8), as: Marks.self, kind: .nolyrics, expectedWriter: Self.writer).get()
        }
    }

    @Test func eachKindHasItsFileNameAndLimit() {
        #expect(SyncKind.allCases.map(\.fileName) == ["timings.json", "artists.json", "decisions.json", "nolyrics.json"])
        #expect(SyncKind.timings.maxBytes == 32 << 20)
        #expect(SyncKind.decisions.maxBytes == 1 << 20)
    }

    @Test func artistRecordsAreCanonicalized() {
        let record = ArtistStyleBook.Record(spellings: ["b", "a"], mbid: nil, matchedReleaseGroups: ["z", "y"],
                                            genres: [.init(name: "rock", count: 1), .init(name: "doom", count: 4)],
                                            reason: .collision, fetchedAt: Self.at, origin: Self.writer)
        let canonical = SyncPayload.canonicalArtists(["k": record])["k"]
        #expect(canonical?.spellings == ["a", "b"])
        #expect(canonical?.matchedReleaseGroups == ["y", "z"])
        #expect(canonical?.genres.map(\.name) == ["doom", "rock"])
    }
}
