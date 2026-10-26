import CryptoKit
import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// CR-018（sprint-5-detail.md §11）：iPad 端 detail 接收——暫存檔＋位圖組裝、逐塊核對 metadata、組完驗 SHA-256 與 magic bytes；
// part 0 後最多 2 塊並行；restart 換新世代重來（最多 2 次）；stale／none／tooLarge／錯誤＝不可用（沿用 spine）

private let album = "00000000000000a1", token = "00000000000000f1"

private func jpegLike(_ count: Int) -> Data {
    var data = Data([0xFF, 0xD8, 0xFF, 0xE0])
    data.append(Data((0..<(count - 4)).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 5) }))
    return data
}

private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

/// 模擬 Mac：依原檔切塊回覆；可插入 restart、改寫某塊、記錄呼叫
final class FakeDetailMac: @unchecked Sendable {
    let lock = NSLock()
    var original: Data
    var digestOverride: String?
    var restartOnCalls: Set<Int> = []
    var outcomeForPartZero: ArtworkOutcome = .image
    var tamperPart: Int?
    var wrongTokenOnPart: Int?
    /// 第 n 次呼叫（從 1 起）回「Mac 限流」（#6-1：側封快甩時小封面請求把每秒 60 個讀取配額用完）
    var rateLimitedOnCalls: Set<Int> = []
    private(set) var calls: [(part: Int, digest: String?, generation: UInt64)] = []
    private var inFlight = 0
    private(set) var maxInFlight = 0

    init(_ original: Data) { self.original = original }

    func respond(part: Int, digest: String?, generation: UInt64) async throws(EchoRequestError) -> ArtworkResponse {
        let (count, original, restart, zeroOutcome, tamper, wrongToken) = lock.withLock {
            calls.append((part, digest, generation))
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            return (calls.count, self.original, restartOnCalls, outcomeForPartZero, tamperPart, wrongTokenOnPart)
        }
        if lock.withLock({ rateLimitedOnCalls.contains(count) }) {
            lock.withLock { inFlight -= 1 }
            throw .remote(.rateLimited)
        }
        await Task.yield()
        await Task.yield()
        defer { lock.withLock { inFlight -= 1 } }
        if restart.contains(count) { return response(.restart, nil) }
        if part == 0, zeroOutcome != .image { return response(zeroOutcome, nil) }
        let total = original.count
        let start = part * DetailArtworkLimits.chunkBytes
        var chunk = original.subdata(in: start..<min(start + DetailArtworkLimits.chunkBytes, total))
        if tamper == part { chunk[chunk.startIndex] ^= 0xFF }
        let detail = ArtworkDetailPart(part: part, partCount: DetailArtworkLimits.partCount(totalBytes: total), totalBytes: total,
                                       digest: lock.withLock { digestOverride } ?? sha(original),
                                       mime: ArtworkMime.sniff(original) ?? .jpeg, chunk: chunk)
        return ArtworkResponse(albumID: album, size: .detail, outcome: .image,
                               artworkToken: wrongToken == part ? "00000000000000ee" : token, jpeg: nil, detail: detail)
    }

    private func response(_ outcome: ArtworkOutcome, _ detail: ArtworkDetailPart?) -> ArtworkResponse {
        ArtworkResponse(albumID: album, size: .detail, outcome: outcome, artworkToken: token, jpeg: nil, detail: detail)
    }

    var recorded: [(part: Int, digest: String?, generation: UInt64)] { lock.withLock { calls } }
}

final class GenerationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func next() -> UInt64 { lock.withLock { value += 1; return value } }
}

struct DetailArtworkFetcherTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("detail-\(UUID().uuidString)", isDirectory: true)
    let generations = GenerationCounter()

    let sleeper = CancellableSleeper()

    private func fetcher() -> DetailArtworkFetcher {
        let generations = generations
        return DetailArtworkFetcher(directory: directory, nextGeneration: { generations.next() }, retry: sleeper.options)
    }

    private func fetch(_ mac: FakeDetailMac) async -> DetailArtworkFetcher.Outcome {
        await fetcher().fetch(albumID: album, token: token) { part, digest, generation throws(EchoRequestError) in
            try await mac.respond(part: part, digest: digest, generation: generation)
        }
    }

    private var leftovers: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    /// 全部塊組回原檔；後續塊帶 part 0 的 digest 與同一世代；最多 2 塊並行；暫存檔清掉
    @Test func reassemblesOriginalWithBoundedParallelism() async {
        let original = jpegLike(5 * DetailArtworkLimits.chunkBytes + 123)
        let mac = FakeDetailMac(original)
        #expect(await fetch(mac) == .image(original))
        let calls = mac.recorded
        #expect(calls.count == 6 && Set(calls.map(\.part)) == Set(0..<6))
        #expect(calls.dropFirst().allSatisfy { $0.digest == sha(original) && $0.generation == calls[0].generation })
        #expect(mac.maxInFlight <= 2)
        #expect(leftovers.isEmpty)
    }

    /// 被 Mac 限流（或 busy）：同一塊退避後重試，最多 3 次；不放棄整張（#6-1：原本一被擋就放棄，封面一直停在模糊的小圖）
    @Test func rateLimitedPartsAreRetried() async {
        let original = jpegLike(3 * DetailArtworkLimits.chunkBytes + 7)
        let mac = FakeDetailMac(original)
        mac.lock.withLock { mac.rateLimitedOnCalls = [1, 3] }
        #expect(await fetch(mac) == .image(original))
        #expect(mac.recorded.count == 6)
    }

    @Test func persistentRateLimitGivesUpAfterThreeTries() async {
        let mac = FakeDetailMac(jpegLike(1_000))
        mac.lock.withLock { mac.rateLimitedOnCalls = [1, 2, 3, 4] }
        #expect(await fetch(mac) == .unavailable)
        #expect(mac.recorded.count == 3)
        #expect(sleeper.durations == [.milliseconds(500), .seconds(1)], "共用規則：0.5 s、1.0 s（F-L1）")
    }

    /// F-L1 R4：睡眠被取消＝既有的取消結果；拋其他錯誤＝該塊失敗。兩者都不再送（Codex R5-2）
    @Test(arguments: [true, false])
    func sleepErrorStopsThatPart(_ cancellation: Bool) async {
        let mac = FakeDetailMac(jpegLike(1_000))
        mac.lock.withLock { mac.rateLimitedOnCalls = [1] }
        sleeper.lock.withLock { sleeper.failure = cancellation ? CancellationError() : SleepFailure() }
        #expect(await fetch(mac) == .unavailable)
        #expect(mac.recorded.count == 1)
    }

    /// 一塊在退避中，另一塊照常完成並續送下一塊；退避結束後整張組回
    @Test func otherPartProceedsWhileOneBacksOff() async {
        let original = jpegLike(3 * DetailArtworkLimits.chunkBytes + 7)
        let mac = FakeDetailMac(original)
        mac.lock.withLock { mac.rateLimitedOnCalls = [2] }
        sleeper.lock.withLock { sleeper.hold = true }
        let task = Task { await fetch(mac) }
        let sleeper = sleeper
        let backingOff = await eventually { sleeper.waiting == 1 }
        let othersDone = await eventually { mac.recorded.count == 4 }
        #expect(backingOff && othersDone)
        sleeper.wake()
        #expect(await task.value == .image(original))
        #expect(mac.recorded.count == 5)
    }

    @Test func singlePartImage() async {
        let original = jpegLike(1_000)
        #expect(await fetch(FakeDetailMac(original)) == .image(original))
    }

    /// restart：換新世代從 part 0 重來；最多 2 次，第 3 次放棄
    @Test func restartsWithNewGenerationUpToTwice() async {
        let original = jpegLike(3 * DetailArtworkLimits.chunkBytes)
        let mac = FakeDetailMac(original)
        mac.lock.withLock { mac.restartOnCalls = [2] }   // 第 2 個呼叫（某個後續塊）回 restart
        #expect(await fetch(mac) == .image(original))
        let zeros = mac.recorded.filter { $0.part == 0 }
        #expect(zeros.count == 2 && zeros[1].generation > zeros[0].generation)
        let always = FakeDetailMac(original)
        always.lock.withLock { always.outcomeForPartZero = .restart }
        #expect(await fetch(always) == .unavailable)
        #expect(always.recorded.count == 3)
        #expect(leftovers.isEmpty)
    }

    @Test(arguments: [ArtworkOutcome.none, .tooLarge])
    func noDetailIsUnavailable(outcome: ArtworkOutcome) async {
        let mac = FakeDetailMac(jpegLike(100))
        mac.lock.withLock { mac.outcomeForPartZero = outcome }
        #expect(await fetch(mac) == .unavailable)
    }

    @Test func staleTokenIsStale() async {
        let mac = FakeDetailMac(jpegLike(100))
        mac.lock.withLock { mac.outcomeForPartZero = .stale }
        #expect(await fetch(mac) == .stale)
    }

    /// 內容被改（SHA-256 不符）、某塊 token 不符、digest 宣告不合法：都不得當成功，暫存清掉
    @Test func corruptOrMismatchedPartsAreRejected() async {
        let original = jpegLike(2 * DetailArtworkLimits.chunkBytes + 5)
        let tampered = FakeDetailMac(original)
        tampered.lock.withLock { tampered.tamperPart = 1 }
        #expect(await fetch(tampered) == .unavailable)
        let wrongToken = FakeDetailMac(original)
        wrongToken.lock.withLock { wrongToken.wrongTokenOnPart = 2 }
        #expect(await fetch(wrongToken) == .unavailable)
        #expect(leftovers.isEmpty)
    }

    /// 組完的位元組不是 JPEG／PNG（magic bytes 不符宣告）＝拒絕
    @Test func wrongMagicIsRejected() async {
        var notJPEG = jpegLike(500)
        notJPEG[notJPEG.startIndex] = 0x00
        #expect(await fetch(FakeDetailMac(notJPEG)) == .unavailable)
    }

    /// 傳輸錯誤（busy、斷線）＝不可用
    @Test func transportErrorIsUnavailable() async {
        let outcome = await fetcher().fetch(albumID: album, token: token) { _, _, _ throws(EchoRequestError) in throw .remote(.busy) }
        #expect(outcome == .unavailable)
    }

    /// 取消：不回成功、暫存清掉
    @Test func cancellationCleansUp() async {
        let mac = FakeDetailMac(jpegLike(20 * DetailArtworkLimits.chunkBytes))
        let task = Task { await fetch(mac) }
        task.cancel()
        #expect(await task.value == .unavailable)
        #expect(leftovers.isEmpty)
    }
}
