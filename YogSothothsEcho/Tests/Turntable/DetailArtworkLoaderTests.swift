import Foundation
import RemoteProtocol
import RemoteTransport
import Testing
import UIKit

@testable import YogSothothsEcho

// CR-018：唱機的原圖來源——先查磁碟快取，沒有才向 Mac 分塊取，成功後存回；未連線＝nil；世代只增不減

final class FakeDetailRequester: DetailArtworkRequesting, @unchecked Sendable {
    let mac: FakeDetailMac
    init(_ mac: FakeDetailMac) { self.mac = mac }
    func artworkDetail(albumID: String, token: String, part: Int, digest: String?, generation: UInt64)
        async throws(EchoRequestError) -> ArtworkResponse {
        try await mac.respond(part: part, digest: digest, generation: generation)
    }
}

private func pngData() -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
        UIColor.orange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
}

/// 只有檔頭的 PNG：IHDR 宣告 `side`×`side`、RGBA（解碼後約 side²×4 位元組）——驗「先讀尺寸、不解碼就拒收」
func headerOnlyPNG(side: UInt32) -> Data {
    func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
    func be(_ value: UInt32) -> [UInt8] { [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) } }
    func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let typed = Array(type.utf8) + body
        return be(UInt32(body.count)) + typed + be(crc32(typed))
    }
    let ihdr = be(side) + be(side) + [8, 6, 0, 0, 0]
    return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", ihdr) + chunk("IEND", []))
}

private func solidPNG(width: Int, height: Int) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
        UIColor.purple.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

/// simcodex R1（security MEDIUM-1、efficiency #3）：原圖先讀像素尺寸擋解壓炸彈，再降採樣到唱機顯示大小
struct DetailArtworkDecoderTests {
    @Test func decompressionBombIsRejectedWithoutDecoding() {
        #expect(DetailArtworkDecoder.displayImage(headerOnlyPNG(side: 20_000)) == nil)
    }

    @Test func largeOriginalIsDownsampledForDisplay() throws {
        let image = try #require(DetailArtworkDecoder.displayImage(solidPNG(width: 3000, height: 2000)))
        let cg = try #require(image.cgImage)
        #expect(max(cg.width, cg.height) == DetailArtworkDecoder.displayMaxPixels && cg.width > cg.height)
    }

    @Test func smallOriginalKeepsItsSize() throws {
        let cg = try #require(DetailArtworkDecoder.displayImage(solidPNG(width: 800, height: 800))?.cgImage)
        #expect(cg.width == 800 && cg.height == 800)
    }
}

/// 測試便利：產品碼由排程器分別呼叫 cachedData（不排隊）與 fetchData（單飛）；這裡依同樣順序組回「取一張圖」，驗兩者的行為
private extension DetailArtworkLoader {
    func image(albumID: String, token: String) async -> UIImage? {
        if let cached = await cachedData(albumID: albumID, token: token) { return DetailArtworkDecoder.displayImage(cached) }
        return await fetchData(albumID: albumID, token: token).flatMap { DetailArtworkDecoder.displayImage($0) }
    }
}

struct DetailArtworkLoaderTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("detail-loader-\(UUID().uuidString)", isDirectory: true)

    @Test func fetchesOnceThenServesFromDisk() async {
        let mac = FakeDetailMac(pngData())
        let loader = DetailArtworkLoader(store: DetailArtworkStore(directory: directory))
        await loader.attach(FakeDetailRequester(mac))
        #expect(await loader.image(albumID: "00000000000000a1", token: "00000000000000f1") != nil)
        let calls = mac.recorded.count
        #expect(await loader.image(albumID: "00000000000000a1", token: "00000000000000f1") != nil)
        #expect(mac.recorded.count == calls)
    }

    @Test func notConnectedIsNil() async {
        let loader = DetailArtworkLoader(store: DetailArtworkStore(directory: directory))
        #expect(await loader.image(albumID: "00000000000000a1", token: "00000000000000f1") == nil)
        await loader.attach(FakeDetailRequester(FakeDetailMac(pngData())))
        await loader.detach()
        #expect(await loader.image(albumID: "00000000000000a1", token: "00000000000000f1") == nil)
    }

    /// 炸彈圖：不回圖、也不進快取（下次仍向 Mac 要，不會每次播到都解碼一次）
    @Test func undecodableOriginalIsNotCached() async {
        let mac = FakeDetailMac(headerOnlyPNG(side: 20_000))
        let loader = DetailArtworkLoader(store: DetailArtworkStore(directory: directory))
        await loader.attach(FakeDetailRequester(mac))
        #expect(await loader.image(albumID: "00000000000000a1", token: "00000000000000f1") == nil)
        let calls = mac.recorded.count
        #expect(await loader.image(albumID: "00000000000000a1", token: "00000000000000f1") == nil)
        #expect(mac.recorded.count > calls)
    }

    /// 快取裡的檔解不出來（損毀、或是本版上限之前存的炸彈圖）：丟掉這筆、改向 Mac 重取（codex R3）
    @Test func undecodableCacheEntryIsDroppedAndRefetched() async {
        let store = DetailArtworkStore(directory: directory)
        await store.put(headerOnlyPNG(side: 20_000), albumID: "00000000000000a1", token: "00000000000000f1")
        let mac = FakeDetailMac(pngData())
        let loader = DetailArtworkLoader(store: store)
        await loader.attach(FakeDetailRequester(mac))
        #expect(await loader.image(albumID: "00000000000000a1", token: "00000000000000f1") != nil)
        #expect(!mac.recorded.isEmpty)
        #expect(await store.data(albumID: "00000000000000a1", token: "00000000000000f1") == pngData())
    }

    @Test func generationsKeepIncreasingAcrossFetches() async {
        let mac = FakeDetailMac(pngData())
        let loader = DetailArtworkLoader(store: DetailArtworkStore(directory: directory))
        await loader.attach(FakeDetailRequester(mac))
        _ = await loader.image(albumID: "00000000000000a1", token: "00000000000000f1")
        _ = await loader.image(albumID: "00000000000000a2", token: "00000000000000f1")
        let generations = mac.recorded.filter { $0.part == 0 }.map(\.generation)
        #expect(generations.count == 2 && generations[1] > generations[0])
    }
}
