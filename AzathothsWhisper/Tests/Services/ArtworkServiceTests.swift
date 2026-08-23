import AppKit
import Foundation
import Testing

@testable import AzathothsWhisper

// 封面取圖編排（M7 P1-2）：查記憶體 → 未命中走 AE → 解碼縮圖 → 存記憶體。
//
// **測試邊界**：這裡用 mock 驗編排邏輯。真實 AE 佇列的公平性（慢請求是否真的釋放佇列）
// 靠 `SBApplication.timeout` 保證，屬 M8 真機驗證——mock 沒有真實的串行 AE 佇列，
// 在此斷言「monitor 不被阻塞」會是自欺。本檔只驗 client 端的 bounded wait 與編排契約。
@Suite("ArtworkService")
struct ArtworkServiceTests {
    /// 造一張可編碼為 PNG 的真圖（解碼路徑需要真實位元組）
    private func pngData(side: Int = 800) -> Data {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return Data() }
        return png
    }

    private func makeService(
        music: MockMusicClient
    ) -> ArtworkService {
        ArtworkService(music: music, memory: ArtworkMemoryCache())
    }

    @Test func fetchesDecodesAndCachesOnMiss() async {
        let music = MockMusicClient()
        await music.setArtwork(pngData(), for: "PID1")
        let service = makeService(music: music)

        let image = await service.artwork(for: "PID1")
        #expect(image != nil)
        #expect(await music.artworkCalls == 1)

        // 第二次應命中記憶體，不再打 AE
        _ = await service.artwork(for: "PID1")
        #expect(await music.artworkCalls == 1, "命中快取不得重複請求 AE")
    }

    /// 縮圖上限 512px（§4.8）——原圖 800px 應被縮小
    @Test func decodesToThumbnailNoLargerThan512() async {
        let music = MockMusicClient()
        await music.setArtwork(pngData(side: 800), for: "PID1")
        let service = makeService(music: music)

        let image = await service.artwork(for: "PID1")
        #expect(image != nil)
        #expect(max(image?.size.width ?? 0, image?.size.height ?? 0) <= 512)
    }

    /// 同一 ID 併發 miss 只發一次 AE（in-flight 去重）
    @Test func concurrentMissesShareOneAERequest() async {
        let gate = LyricsGate()
        let music = MockMusicClient()
        await music.setArtwork(pngData(), for: "PID1")
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        async let a = service.artwork(for: "PID1")
        async let b = service.artwork(for: "PID1")
        async let c = service.artwork(for: "PID1")
        await settle()
        await gate.open()

        let results = await [a, b, c]
        #expect(results.allSatisfy { $0 != nil })
        #expect(await music.artworkCalls == 1, "三個併發請求只該打一次 AE")
    }

    /// AE 拋錯 → 回 nil 不崩，且不寫快取
    @Test func aeFailureReturnsNilWithoutCaching() async {
        let music = MockMusicClient()
        await music.setArtworkOutcome(.failure(.permissionDenied))
        let service = makeService(music: music)

        #expect(await service.artwork(for: "PID1") == nil)

        // 失敗不得寫快取——下次仍須重試
        await music.setArtworkOutcome(.success(pngData()))
        #expect(await service.artwork(for: "PID1") != nil)
        #expect(await music.artworkCalls == 2, "失敗不得寫快取，第二次應重新請求")
    }

    /// 無法解碼的位元組 → 回 nil 且不寫快取
    @Test func undecodableDataReturnsNilWithoutCaching() async {
        let music = MockMusicClient()
        await music.setArtwork(Data([0x00, 0x01, 0x02]), for: "PID1")
        let service = makeService(music: music)

        #expect(await service.artwork(for: "PID1") == nil)
        #expect(await service.artwork(for: "PID1") == nil)
        #expect(await music.artworkCalls == 2, "解碼失敗不得寫快取")
    }

    /// 曲目無封面（AE 回 nil）→ 回 nil，不崩
    @Test func absentArtworkReturnsNil() async {
        let music = MockMusicClient()
        let service = makeService(music: music)
        #expect(await service.artwork(for: "PID1") == nil)
    }

    /// P1 無預取：任一時點在飛的 AE artwork 請求 ≤ 1
    @Test func noPrefetchKeepsInFlightAtMostOne() async {
        let gate = LyricsGate()
        let music = MockMusicClient()
        await music.setArtwork(pngData(), for: "PID1")
        await music.setArtwork(pngData(), for: "PID2")
        await music.setArtworkGate(gate)
        let service = makeService(music: music)

        async let a = service.artwork(for: "PID1")
        await settle()
        #expect(await music.artworkInFlight <= 1)

        await gate.open()
        _ = await a
    }
}
