import Foundation
import Testing

@testable import MusicRemoteBridge
import RemoteProtocol

// CR-018（sprint-5-detail.md §11）：Mac 端 detail 傳輸生命週期——每 peer 1、全域 2；更新的 generation 取代舊傳輸；
// 遲到或過舊的請求不得復活 lease；閒置 30 s 回收；斷線清除；全部塊送出即釋放

private let peerA = UUID(), peerB = UUID(), peerC = UUID()
private let t0 = Date(timeIntervalSince1970: 1_000)
private let digestA = String(repeating: "a", count: 64), digestB = String(repeating: "b", count: 64)

private func key(_ album: String = "00000000000000a1") -> DetailTransferBook.Key {
    DetailTransferBook.Key(albumID: album, token: "00000000000000f1")
}

/// 3 塊：45,000＋45,000＋10
private func payload(_ digest: String = digestA) -> DetailTransferBook.Payload {
    DetailTransferBook.Payload(data: Data(repeating: 1, count: 2 * DetailArtworkLimits.chunkBytes + 10), digest: digest, mime: .jpeg)
}

struct DetailTransferBookTests {
    @Test func beginServesPartZeroAndLaterPartsSlice() throws {
        var book = DetailTransferBook()
        let r1 = book.begin(peer: peerA, key: key(), generation: 1, payload: payload(), now: t0)
        let first = try #require(r1.part)
        #expect(first.part == 0 && first.partCount == 3 && first.chunk.count == DetailArtworkLimits.chunkBytes)
        let r2 = book.part(peer: peerA, key: key(), digest: digestA, generation: 1, index: 2, now: t0)
        let last = try #require(r2)
        #expect(last.chunk.count == 10 && last.isValid)
        #expect(book.activeCount == 1)
    }

    /// 全部塊送出＝釋放；之後同一傳輸的請求一律 restart
    @Test func completionReleases() {
        var book = DetailTransferBook()
        _ = book.begin(peer: peerA, key: key(), generation: 1, payload: payload(), now: t0)
        _ = book.part(peer: peerA, key: key(), digest: digestA, generation: 1, index: 1, now: t0)
        _ = book.part(peer: peerA, key: key(), digest: digestA, generation: 1, index: 2, now: t0)
        #expect(book.activeCount == 0)
        let r3 = book.part(peer: peerA, key: key(), digest: digestA, generation: 1, index: 1, now: t0)
        #expect(r3 == nil)
    }

    @Test func singlePartTransferReleasesImmediately() {
        var book = DetailTransferBook()
        let small = DetailTransferBook.Payload(data: Data([1, 2, 3]), digest: digestA, mime: .png)
        let r4 = book.begin(peer: peerA, key: key(), generation: 1, payload: small, now: t0)
        #expect(r4.part?.partCount == 1)
        #expect(book.activeCount == 0)
    }

    /// 重複的塊可再送（冪等），不算額外完成
    @Test func repeatedPartIsIdempotent() {
        var book = DetailTransferBook()
        _ = book.begin(peer: peerA, key: key(), generation: 1, payload: payload(), now: t0)
        let r5 = book.part(peer: peerA, key: key(), digest: digestA, generation: 1, index: 1, now: t0)
        #expect(r5 != nil)
        let r6 = book.part(peer: peerA, key: key(), digest: digestA, generation: 1, index: 1, now: t0)
        #expect(r6 != nil)
        #expect(book.activeCount == 1)
    }

    /// 取代：同 peer 以更新的 generation 開另一張＝舊的立即結束；舊傳輸的後續塊 restart
    @Test func newerGenerationSupersedes() {
        var book = DetailTransferBook()
        _ = book.begin(peer: peerA, key: key("00000000000000a1"), generation: 1, payload: payload(), now: t0)
        let r7 = book.begin(peer: peerA, key: key("00000000000000a2"), generation: 2, payload: payload(digestB), now: t0)
        #expect(r7.part != nil)
        #expect(book.activeCount == 1)
        let r8 = book.part(peer: peerA, key: key("00000000000000a1"), digest: digestA, generation: 1, index: 1, now: t0)
        #expect(r8 == nil)
        let r9 = book.part(peer: peerA, key: key("00000000000000a2"), digest: digestB, generation: 2, index: 1, now: t0)
        #expect(r9 != nil)
    }

    /// 遲到的舊 part 0（generation 不大於已接受者）不得把新傳輸換回去、也不得占名額
    @Test func lateOlderPartZeroIsRejected() {
        var book = DetailTransferBook()
        _ = book.begin(peer: peerA, key: key("00000000000000a2"), generation: 5, payload: payload(digestB), now: t0)
        let r10 = book.begin(peer: peerA, key: key("00000000000000a1"), generation: 4, payload: payload(), now: t0)
        #expect(r10 == .restart)
        let r11 = book.begin(peer: peerA, key: key("00000000000000a2"), generation: 5, payload: payload(digestB), now: t0)
        #expect(r11 == .restart)
        let r12 = book.part(peer: peerA, key: key("00000000000000a2"), digest: digestB, generation: 5, index: 1, now: t0)
        #expect(r12 != nil)
    }

    /// 後續塊要同時符合 key、digest、generation、序號範圍
    @Test func laterPartMustMatchEverything() {
        var book = DetailTransferBook()
        _ = book.begin(peer: peerA, key: key(), generation: 1, payload: payload(), now: t0)
        let r13 = book.part(peer: peerA, key: key(), digest: digestB, generation: 1, index: 1, now: t0)
        #expect(r13 == nil)
        let r14 = book.part(peer: peerA, key: key(), digest: digestA, generation: 2, index: 1, now: t0)
        #expect(r14 == nil)
        let r15 = book.part(peer: peerA, key: key("00000000000000a9"), digest: digestA, generation: 1, index: 1, now: t0)
        #expect(r15 == nil)
        let r16 = book.part(peer: peerA, key: key(), digest: digestA, generation: 1, index: 3, now: t0)
        #expect(r16 == nil)
        let r17 = book.part(peer: peerB, key: key(), digest: digestA, generation: 1, index: 1, now: t0)
        #expect(r17 == nil)
        #expect(book.activeCount == 1)   // 不符的請求不影響現有傳輸
    }

    /// 全域 2：第三個 peer 開新傳輸＝busy，且不記錄其 generation
    @Test func globalLimitIsTwo() {
        var book = DetailTransferBook()
        _ = book.begin(peer: peerA, key: key(), generation: 1, payload: payload(), now: t0)
        _ = book.begin(peer: peerB, key: key(), generation: 1, payload: payload(), now: t0)
        let r18 = book.begin(peer: peerC, key: key(), generation: 1, payload: payload(), now: t0)
        #expect(r18 == .busy)
        #expect(book.activeCount == 2)
        _ = book.peerGone(peerA)
        let r19 = book.begin(peer: peerC, key: key(), generation: 1, payload: payload(), now: t0)
        #expect(r19.part != nil)
    }

    /// 已有傳輸的 peer 取代自己不受全域上限影響
    @Test func supersedeDoesNotNeedAFreeSlot() {
        var book = DetailTransferBook()
        _ = book.begin(peer: peerA, key: key(), generation: 1, payload: payload(), now: t0)
        _ = book.begin(peer: peerB, key: key(), generation: 1, payload: payload(), now: t0)
        let r20 = book.begin(peer: peerA, key: key("00000000000000a2"), generation: 2, payload: payload(), now: t0)
        #expect(r20.part != nil)
    }

    /// 閒置 30 s 回收；回收後的後續塊 restart、不得復活；活動會延長期限
    @Test func idleTimeoutReclaimsWithoutResurrection() {
        var book = DetailTransferBook()
        _ = book.begin(peer: peerA, key: key(), generation: 1, payload: payload(), now: t0)
        let r21 = book.part(peer: peerA, key: key(), digest: digestA, generation: 1, index: 1, now: t0 + 29)
        #expect(r21 != nil)
        #expect(book.activeCount(now: t0 + 58) == 1)
        #expect(book.activeCount(now: t0 + 59.1) == 0)
        let r22 = book.part(peer: peerA, key: key(), digest: digestA, generation: 1, index: 2, now: t0 + 60)
        #expect(r22 == nil)
        let r23 = book.begin(peer: peerA, key: key(), generation: 1, payload: payload(), now: t0 + 60)
        #expect(r23 == .restart)
        let r24 = book.begin(peer: peerA, key: key(), generation: 2, payload: payload(), now: t0 + 60)
        #expect(r24.part != nil)
    }

    /// 斷線：清掉傳輸與 generation 紀錄（新連線的 iPad 從頭計世代）
    @Test func peerGoneClearsEverything() {
        var book = DetailTransferBook()
        _ = book.begin(peer: peerA, key: key(), generation: 9, payload: payload(), now: t0)
        _ = book.peerGone(peerA)
        #expect(book.activeCount == 0)
        let r25 = book.begin(peer: peerA, key: key(), generation: 1, payload: payload(), now: t0)
        #expect(r25.part != nil)
    }
}
