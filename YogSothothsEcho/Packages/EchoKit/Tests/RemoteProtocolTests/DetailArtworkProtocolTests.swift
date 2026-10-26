import Foundation
import Testing

@testable import RemoteProtocol

// CR-018（sprint-5-detail.md §11）：detail＝原檔分塊。spine 的線上內容必須與 CR-018 前完全一致（特性測試：基準以改動前的程式產生；
// JSONEncoder 鍵順序不固定，所以比對解析後的 JSON 物件——鍵集合與值都要相同，等於證明沒有多出任何欄位）

private let fixedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let album = "0123456789abcdef", token = "fedcba9876543210"

private func object(_ data: Data) -> NSDictionary? {
    (try? JSONSerialization.jsonObject(with: data)) as? NSDictionary
}

private func object(_ text: String) -> NSDictionary? { object(Data(text.utf8)) }

struct SpineWireCompatibilityTests {
    @Test func spineRequestUnchanged() {
        let data = Envelope.encode(.artworkGet, ArtworkRequest(albumID: album, size: .spine, artworkToken: token), id: fixedID)
        let golden = #"{"body":{"albumID":"0123456789abcdef","size":"spine","artworkToken":"fedcba9876543210"},"v":1,"id":"00000000-0000-0000-0000-000000000001","kind":"artwork.get"}"#
        #expect(object(data) == object(golden))
    }

    @Test func spineResponseUnchanged() {
        let response = ArtworkResponse(albumID: album, size: .spine, outcome: .image, artworkToken: token, jpeg: Data([0xFF, 0xD8, 0xFF]))
        let data = Envelope.encode(.artworkGet, response, id: fixedID)
        let golden = #"{"kind":"artwork.get","v":1,"body":{"albumID":"0123456789abcdef","size":"spine","jpeg":"/9j/","outcome":"image","artworkToken":"fedcba9876543210"},"id":"00000000-0000-0000-0000-000000000001"}"#
        #expect(object(data) == object(golden))
    }
}

private let digest = String(repeating: "ab", count: 32)

private func detailImage(part: Int, partCount: Int, totalBytes: Int, chunk: Data, digest: String = digest,
                         mime: ArtworkMime? = .jpeg) -> ArtworkResponse {
    ArtworkResponse(albumID: album, size: .detail, outcome: .image, artworkToken: token, jpeg: nil,
                    detail: ArtworkDetailPart(part: part, partCount: partCount, totalBytes: totalBytes, digest: digest,
                                              mime: mime ?? .jpeg, chunk: chunk))
}

struct DetailArtworkLimitsTests {
    @Test func limits() {
        #expect(DetailArtworkLimits.maxTotalBytes == 6 * 1_048_576)
        #expect(DetailArtworkLimits.chunkBytes == 45_000)
        #expect(DetailArtworkLimits.maxParts == 140)
        #expect(DetailArtworkLimits.partCount(totalBytes: 1) == 1)
        #expect(DetailArtworkLimits.partCount(totalBytes: 45_000) == 1)
        #expect(DetailArtworkLimits.partCount(totalBytes: 45_001) == 2)
        #expect(DetailArtworkLimits.partCount(totalBytes: DetailArtworkLimits.maxTotalBytes) == 140)
    }

    @Test func mimeSniffing() {
        #expect(ArtworkMime.sniff(Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
        #expect(ArtworkMime.sniff(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])) == .png)
        #expect(ArtworkMime.sniff(Data([0x47, 0x49, 0x46, 0x38])) == nil)   // GIF 不收
        #expect(ArtworkMime.sniff(Data([0xFF, 0xD8])) == nil)
        #expect(ArtworkMime.sniff(Data()) == nil)
    }
}

struct DetailArtworkRequestTests {
    @Test func spineMustNotCarryDetailFields() {
        #expect(ArtworkRequest(albumID: album, size: .spine, artworkToken: token).isValid)
        #expect(!ArtworkRequest(albumID: album, size: .spine, artworkToken: token, part: 0, digest: nil, generation: 1).isValid)
    }

    @Test func partZeroNeedsGenerationAndNoDigest() {
        #expect(ArtworkRequest(albumID: album, size: .detail, artworkToken: token, part: 0, digest: nil, generation: 1).isValid)
        #expect(!ArtworkRequest(albumID: album, size: .detail, artworkToken: token, part: 0, digest: nil, generation: nil).isValid)
        #expect(!ArtworkRequest(albumID: album, size: .detail, artworkToken: token, part: 0, digest: digest, generation: 1).isValid)
        #expect(!ArtworkRequest(albumID: album, size: .detail, artworkToken: token).isValid)
    }

    @Test func laterPartsNeedFullLowercaseDigestAndRange() {
        #expect(ArtworkRequest(albumID: album, size: .detail, artworkToken: token, part: 139, digest: digest, generation: 1).isValid)
        #expect(!ArtworkRequest(albumID: album, size: .detail, artworkToken: token, part: 140, digest: digest, generation: 1).isValid)
        #expect(!ArtworkRequest(albumID: album, size: .detail, artworkToken: token, part: -1, digest: digest, generation: 1).isValid)
        #expect(!ArtworkRequest(albumID: album, size: .detail, artworkToken: token, part: 3, digest: nil, generation: 1).isValid)
        #expect(!ArtworkRequest(albumID: album, size: .detail, artworkToken: token, part: 3, digest: digest.uppercased(), generation: 1).isValid)
        #expect(!ArtworkRequest(albumID: album, size: .detail, artworkToken: token, part: 3, digest: String(digest.prefix(16)), generation: 1).isValid)
    }

    @Test func fullIsNeverValid() {
        #expect(!ArtworkRequest(albumID: album, size: .full, artworkToken: token).isValid)
    }
}

struct DetailArtworkResponseTests {
    @Test func validDetailParts() {
        #expect(detailImage(part: 0, partCount: 2, totalBytes: 45_010, chunk: Data(count: 45_000)).isValid)
        #expect(detailImage(part: 1, partCount: 2, totalBytes: 45_010, chunk: Data(count: 10)).isValid)
        #expect(detailImage(part: 0, partCount: 1, totalBytes: 7, chunk: Data(count: 7)).isValid)
    }

    @Test func inconsistentDetailPartsAreInvalid() {
        #expect(!detailImage(part: 0, partCount: 3, totalBytes: 45_010, chunk: Data(count: 45_000)).isValid)   // 塊數不符
        #expect(!detailImage(part: 2, partCount: 2, totalBytes: 45_010, chunk: Data(count: 10)).isValid)      // 越界
        #expect(!detailImage(part: 0, partCount: 2, totalBytes: 45_010, chunk: Data(count: 44_999)).isValid)  // 非末塊長度
        #expect(!detailImage(part: 1, partCount: 2, totalBytes: 45_010, chunk: Data(count: 11)).isValid)      // 末塊長度
        #expect(!detailImage(part: 0, partCount: 1, totalBytes: DetailArtworkLimits.maxTotalBytes + 1, chunk: Data(count: 1)).isValid)
        #expect(!detailImage(part: 0, partCount: 1, totalBytes: 7, chunk: Data(count: 7), digest: "xyz").isValid)
        // detail 的 image 不得帶 jpeg 欄位；spine 不得帶 detail
        #expect(!ArtworkResponse(albumID: album, size: .detail, outcome: .image, artworkToken: token, jpeg: Data([1]), detail: nil).isValid)
        let part = ArtworkDetailPart(part: 0, partCount: 1, totalBytes: 1, digest: digest, mime: .png, chunk: Data([1]))
        #expect(!ArtworkResponse(albumID: album, size: .spine, outcome: .image, artworkToken: token, jpeg: Data([1]), detail: part).isValid)
    }

    @Test(arguments: [ArtworkOutcome.none, .stale, .restart, .tooLarge])
    func nonImageOutcomesCarryNoPayload(outcome: ArtworkOutcome) {
        #expect(ArtworkResponse(albumID: album, size: .detail, outcome: outcome, artworkToken: token, jpeg: nil, detail: nil).isValid)
        let part = ArtworkDetailPart(part: 0, partCount: 1, totalBytes: 1, digest: digest, mime: .jpeg, chunk: Data([1]))
        #expect(!ArtworkResponse(albumID: album, size: .detail, outcome: outcome, artworkToken: token, jpeg: nil, detail: part).isValid)
    }

    @Test func detailRoundTrips() throws {
        let response = detailImage(part: 1, partCount: 2, totalBytes: 45_010, chunk: Data(repeating: 7, count: 10))
        let decoded = try JSONDecoder().decode(ArtworkResponse.self, from: JSONEncoder().encode(response))
        #expect(decoded == response)
    }

    /// 最壞塊（滿 45,000 B、全需跳脫的 base64 不存在——base64 只含安全字元；欄位取最長）放進完整外層訊息仍在預算內
    @Test func worstChunkFitsResponseBudget() {
        let response = detailImage(part: 139, partCount: 140, totalBytes: DetailArtworkLimits.maxTotalBytes,
                                   chunk: Data(repeating: 0xFF, count: DetailArtworkLimits.chunkBytes))
        let first = detailImage(part: 0, partCount: 140, totalBytes: DetailArtworkLimits.maxTotalBytes,
                                chunk: Data(repeating: 0xFB, count: DetailArtworkLimits.chunkBytes), mime: .png)
        for body in [response, first] {
            let size = Envelope.encode(.artworkGet, body, id: UUID(), seq: UInt64.max, nonce: Data(count: 32)).count
            #expect(size <= TransportLimits.responseBudgetBytes, "\(size)")
        }
    }
}
