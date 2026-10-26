import CoreGraphics
import Foundation
import RemoteProtocol
import Testing
import UIKit

@testable import YogSothothsEcho

// 側封清晰版被擠掉（s6-61-browse-lru.md）：已解碼預算要放得下兩個不重疊停靠的繪製範圍（螢幕上＋兩端緩衝），
// 以真實 1024² 成本驗——其他測試的假圖只有幾個像素，預設預算下永不淘汰，抓不到 g 版 T5 的 44 MiB 退步。
// 另驗記憶體峰值的兩個出口：換展示、記憶體警告都清掉已解碼圖
@MainActor
struct BrowseArtworkBudgetTests {
    let gate = SleepGate()
    let fake = FakeDetailRequests()
    let m = SpineCarouselTests.pro13

    /// 所有解碼共用同一張 1024² 圖：成本照算 4 MiB／張，測試本身不真的吃那麼多記憶體
    static let fullSizeImage = BrowseArtworkHarness.image(side: CGFloat(BrowseArtwork.Rendition.spine.maxPixels))
    static let albumCount = 80
    static let firstStop = 20

    func artwork() -> BrowseArtwork { BrowseArtworkHarness.make(fake: fake, gate: gate, image: Self.fullSizeImage) }
    func eventually(_ condition: @escaping () async -> Bool) async -> Bool { await BrowseArtworkHarness.eventually(condition) }
    func settle() async { await BrowseArtworkHarness.settle(gate) }

    /// 繪製範圍（visibleRange）的取樣最大張數：slot/32 步長，取中段一段（兩端會被清單邊界截短）
    static func maxDrawn(_ m: SpineCarouselMetrics) -> Int {
        stride(from: CGFloat(firstStop) * m.slot, through: CGFloat(firstStop * 2) * m.slot, by: m.slot / 32)
            .map { SpineCarousel.visibleRange(offset: $0, count: albumCount, metrics: m).count }
            .reduce(0, max)
    }

    /// 預算＝2 × 兩種尺寸繪製範圍的最大張數 × 單張成本；相等而非 ≥：幾何改了（多或少）都要回來重定，不讓預算默默不足或過大
    @Test func spineBudgetHoldsTwoDrawnScreens() {
        let drawn = [SpineCarouselTests.pro13, SpineCarouselTests.pro11].map(Self.maxDrawn)
        #expect(BrowseArtwork.spineResident == 2 * (drawn.max() ?? 0), "drawn 13／11 吋＝\(drawn)")
        // 預算以 decodedBytes 推導，它必須等於快取實際計價（CGImage.byteCost）
        #expect(BrowseArtwork.Rendition.spine.decodedBytes == Self.fullSizeImage.cgImage?.byteCost)
    }

    /// 停在 A、滑開一屏到不重疊的 C、再回到 A：A 的每一張在放行升級前就命中，回來也不再要圖
    @Test func returningAfterOneScreenNeedsNoRequest() async throws {
        let a = artwork()
        let albums = BrowseArtworkTests.albums(Self.albumCount)
        let offsetA = CGFloat(Self.firstStop) * m.slot
        let rangeA = SpineCarousel.visibleRange(offset: offsetA, count: albums.count, metrics: m)
        let offsetC = offsetA + CGFloat(rangeA.count) * m.slot
        let rangeC = SpineCarousel.visibleRange(offset: offsetC, count: albums.count, metrics: m)
        try #require(!rangeA.overlaps(rangeC))

        func visibleIDs(_ range: Range<Int>) -> Set<String> { Set(range.map { albums[$0].id }) }
        func stop(at offset: CGFloat, range: Range<Int>) async -> [BrowseArtwork.Candidate] {
            let candidates = BrowseArtwork.candidates(albums: albums, offset: offset, metrics: m)
            let before = a.revision
            a.update(candidates: candidates, visibleIDs: visibleIDs(range))
            await settle()
            #expect(await eventually { a.revision == before + candidates.count })
            return candidates
        }

        let atA = await stop(at: offsetA, range: rangeA)
        _ = await stop(at: offsetC, range: rangeC)
        // 捲回 A（捲動中只撤回、不排程）：此刻 A 的每一張都應還在
        a.update(candidates: [], visibleIDs: visibleIDs(rangeA), schedules: false)
        let missing = atA.filter { a.image(for: $0.album) == nil }.count
        #expect(missing == 0, "A 的 \(atA.count) 張中 \(missing) 張被擠掉")
        let requested = await fake.requested.count
        a.update(candidates: atA, visibleIDs: visibleIDs(rangeA))
        await settle()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await fake.requested.count == requested)
    }

    /// 換展示：兩種已解碼圖都清掉，峰值＝max(spine, grid) 而非相加
    @Test func switchLayoutDropsDecoded() async {
        let a = await artworkWithBothRenditions()
        a.switchLayout()
        #expect(a.image(for: Self.albums[0]) == nil)
        #expect(a.image(for: Self.albums[1], rendition: .grid) == nil)
    }

    /// 記憶體警告：兩種已解碼圖都清掉，且遞增 revision 讓視圖重讀（退回 spine 縮圖、放掉大圖）；私有通知中心，不波及並行測試
    @Test func memoryWarningPurgesDecoded() async {
        let center = NotificationCenter()
        let a = await artworkWithBothRenditions(notifications: center)
        let before = a.revision
        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        #expect(a.image(for: Self.albums[0]) == nil)
        #expect(a.image(for: Self.albums[1], rendition: .grid) == nil)
        #expect(a.revision > before)
    }

    /// 記憶體警告時在途的請求撤回，晚到的結果也不回填（否則清完立刻又寫回大圖）
    @Test func memoryWarningWithdrawsInFlight() async {
        await fake.setHolds(true)
        let center = NotificationCenter()
        let a = BrowseArtworkHarness.make(fake: fake, gate: gate, image: Self.fullSizeImage, notifications: center)
        a.update(candidates: [.init(album: Self.albums[0], distance: 0)], visibleIDs: [Self.albums[0].id])
        await settle()
        #expect(await eventually { await fake.requested.count == 1 })
        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        #expect(await eventually { await fake.withdrawn == [Self.albums[0].id] })
        #expect(a.image(for: Self.albums[0]) == nil)
    }

    static let albums = BrowseArtworkTests.albums(4)

    /// spine 第 0 張、grid 第 1 張已解碼
    private func artworkWithBothRenditions(notifications: NotificationCenter = NotificationCenter()) async -> BrowseArtwork {
        let a = BrowseArtworkHarness.make(fake: fake, gate: gate, image: Self.fullSizeImage, notifications: notifications)
        let albums = Self.albums
        a.update(candidates: [.init(album: albums[0], distance: 0)], visibleIDs: [albums[0].id])
        await settle()
        a.update(candidates: [.init(album: albums[1], distance: 0)], visibleIDs: [albums[1].id], rendition: .grid)
        await settle()
        #expect(await eventually { a.image(for: albums[0]) != nil && a.image(for: albums[1], rendition: .grid) != nil })
        return a
    }
}
