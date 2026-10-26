import Foundation
import Testing
@testable import RemoteProtocol

// 基本設計 §4.3：kind 是封閉列舉；未知 kind、缺欄位、型別錯 → invalidRequest；版本不符 → protocolMismatch
struct MessageKindTests {
    @Test func rawValuesMatchBasicDesignSection43() {
        let expected: Set<String> = [
            "catalog.page", "catalog.search", "album.tracks", "artwork.get",
            "play.track", "play.result", "play.toggle", "play.next", "play.previous", "play.seek",
            "output.list", "output.set", "event.playback", "event.catalogChanged", "error",
            // CR-010（sprint-2-detail.md §4.2）
            "pair.proof", "pair.pending", "pair.result", "session.hello",
            // CR-030（s6-61-genius.md §4.2）
            "play.genius",
        ]
        #expect(Set(MessageKind.allCases.map(\.rawValue)) == expected)
        #expect(MessageKind.allCases.count == 20)
    }
}

struct EnvelopeHeaderTests {
    private let id = "6F1C2B4E-1A2B-4C3D-8E9F-0A1B2C3D4E5F"

    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func validHeaderDecodes() throws {
        let result = EnvelopeHeader.decode(data(#"{"v":1,"id":"\#(id)","kind":"play.next"}"#))
        let header = try result.get()
        #expect(header.v == ProtocolVersion.current)
        #expect(header.kind == .playNext)
        #expect(header.id.uuidString == id)
    }

    @Test func otherVersionIsProtocolMismatch() {
        let result = EnvelopeHeader.decode(data(#"{"v":2,"id":"\#(id)","kind":"play.next"}"#))
        #expect(result.failure == .protocolMismatch)
    }

    @Test func unknownKindIsInvalidRequest() {
        let result = EnvelopeHeader.decode(data(#"{"v":1,"id":"\#(id)","kind":"play.everything"}"#))
        #expect(result.failure == .invalidRequest)
    }

    @Test func missingFieldIsInvalidRequest() {
        #expect(EnvelopeHeader.decode(data(#"{"v":1,"kind":"play.next"}"#)).failure == .invalidRequest)
        #expect(EnvelopeHeader.decode(data(#"{"id":"\#(id)","kind":"play.next"}"#)).failure == .invalidRequest)
    }

    @Test func wrongTypeIsInvalidRequest() {
        #expect(EnvelopeHeader.decode(data(#"{"v":"1","id":"\#(id)","kind":"play.next"}"#)).failure == .invalidRequest)
        #expect(EnvelopeHeader.decode(data(#"{"v":1,"id":"not-a-uuid","kind":"play.next"}"#)).failure == .invalidRequest)
    }

    @Test func notJSONIsInvalidRequest() {
        #expect(EnvelopeHeader.decode(data("{")).failure == .invalidRequest)
    }

    /// 版本不符優先於其他錯誤：舊版 iPad 送來未知 kind 時，要提示更新而不是「請求無效」
    @Test func versionMismatchWinsOverUnknownKind() {
        let result = EnvelopeHeader.decode(data(#"{"v":2,"id":"\#(id)","kind":"pair.begin"}"#))
        #expect(result.failure == .protocolMismatch)
    }

    @Test func headerRoundTrips() throws {
        let header = EnvelopeHeader(v: ProtocolVersion.current, id: UUID(), kind: .eventPlayback)
        let encoded = try JSONEncoder().encode(header)
        #expect(try EnvelopeHeader.decode(encoded).get() == header)
    }
}

struct ErrorCodeTests {
    /// 解碼失敗直接回協定的錯誤碼，不另設一套對應
    @Test func decodeFailuresAreProtocolErrorCodes() {
        let failure: ErrorCode? = EnvelopeHeader.decode(Data("{".utf8)).failure
        #expect(failure == .invalidRequest)
    }

    @Test func listsCodesNamedInUpstream() {
        let expected: Set<String> = [
            "invalidRequest", "protocolMismatch", "rateLimited", "replayed", "musicNotRunning",
            "busy", "notApplied", "superseded",
            // CR-010（sprint-2-detail.md §4.2）
            "pairingInvalid", "pairingUnavailable", "notPaired",
            // CR-012（sprint-3-detail.md §10-1a）
            "libraryUnavailable",
            // CR-013(a)（sprint-4-detail.md §11）
            "musicNotAuthorized",
            // CR-030（s6-61-genius.md §4.2）
            "accessibilityDenied",
        ]
        #expect(Set(ErrorCode.allCases.map(\.rawValue)) == expected)
    }

    /// CR-012：retryable 映射集中在 ErrorCode（原 Wire.error 只對 rateLimited／busy 為 true）
    @Test func retryableCodesAreRateLimitedBusyAndLibraryUnavailable() {
        let retryable = Set(ErrorCode.allCases.filter(\.isRetryable))
        #expect(retryable == [.rateLimited, .busy, .libraryUnavailable])
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
