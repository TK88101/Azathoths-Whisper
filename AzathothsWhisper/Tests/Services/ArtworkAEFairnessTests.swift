import AppKit
import Foundation
import Testing

@testable import AzathothsWhisper

// AE 公平性（M7 P2-2b′，Plan V6）。
//
// **這裡證明什麼**：artwork 對 monitor 等待的貢獻**最多一個 AE 呼叫**——
// 即 monitor 的 `currentTrack()` 入列時，它前面至多只有一張正在執行的 artwork，
// 不會排在整批預取後面。
//
// **這裡不證明什麼**：實際的 1.5 秒時間界。那由 `SBApplication.timeout` 給出，
// 屬真機驗證（M8）。mock 沒有真實 AE，在此斷言秒數會是自欺。
@Suite("ArtworkAEFairness")
struct ArtworkAEFairnessTests {
    private func pngData(side: Int = 40) -> Data {
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

    /// 預取 10 張、第 1 張卡在佇列上時 monitor 進來——它必須排在**第 2 張 artwork 之前**。
    /// 若 service 把整批預取一次塞進 AE 佇列，monitor 就會排在 10 張後面
    @Test func monitorCallWaitsBehindAtMostOneArtworkDuringPrefetch() async {
        let gate = LyricsGate()
        let music = SerialAEQueueMusicClient()
        let ids = (0..<10).map { "PID\($0)" }
        for id in ids { await music.setArtwork(pngData(), for: id) }
        await music.setArtworkGate(gate)

        let service = ArtworkService(music: music, memory: ArtworkMemoryCache())
        await service.prefetch(ids)

        // 等第一張真的佔住佇列，再讓 monitor 入列
        await waitFor { await music.executionOrder.count == 1 }
        async let monitorCall: TrackInfo? = try? music.currentTrack()

        await gate.open()
        _ = await monitorCall
        await waitFor { await music.executionOrder.contains("currentTrack") }

        let order = await music.executionOrder
        let monitorIndex = order.firstIndex(of: "currentTrack") ?? .max
        let artworkBefore = order.prefix(monitorIndex).filter { $0.hasPrefix("artwork:") }.count

        #expect(
            artworkBefore <= 1,
            "monitor 前面至多一張 artwork（實際 \(artworkBefore)，序列 \(order.prefix(monitorIndex))）"
        )
    }

    /// 對照組：確認替身本身確實是 FIFO——否則上面那條測的就不是排程性質
    @Test func serialQueueExecutesInFIFOOrder() async {
        let music = SerialAEQueueMusicClient()
        await music.setArtwork(pngData(), for: "A")

        _ = try? await music.currentTrack()
        _ = try? await music.artworkData(persistentID: "A")
        _ = try? await music.currentLyrics()

        let order = await music.executionOrder
        #expect(order == ["currentTrack", "artwork:A", "currentLyrics"])
    }
}
