import CoreGraphics
import Foundation
import RemoteProtocol
import Testing
import UIKit

@testable import YogSothothsEcho

// S6 #6-1 g 版 T5（s6-61-g-perf-wear.md §5.5）：小圖清晰版——rendition 進鍵（spine 1024／grid 512）、
// 同專輯兩種 rendition 同時在途互不取消、切展示撤回舊世代且不回填、兩個固定預算 LRU 互不擠壓；小圖候選與中心格
@MainActor
struct BrowseArtworkRenditionTests {
    let gate = SleepGate()
    let fake = FakeDetailRequests()

    func artwork(spineBytes: Int = BrowseArtwork.spineByteLimit, gridBytes: Int = BrowseArtwork.gridByteLimit) -> BrowseArtwork {
        BrowseArtworkHarness.make(fake: fake, gate: gate, image: BrowseArtworkHarness.image(side: 4), spineBytes: spineBytes,
                                  gridBytes: gridBytes)
    }

    func eventually(_ condition: @escaping () async -> Bool) async -> Bool { await BrowseArtworkHarness.eventually(condition) }
    func settle() async { await BrowseArtworkHarness.settle(gate) }

    static let albums = BrowseArtworkTests.albums(30)
    func candidates(_ range: ClosedRange<Int>) -> [BrowseArtwork.Candidate] {
        range.map { .init(album: Self.albums[$0], distance: $0 - range.lowerBound) }
    }

    @Test func gridDecodesAt512AndIsSeparateFromSpine() async {
        let a = artwork()
        a.update(candidates: candidates(0...2), visibleIDs: Set(Self.albums.map(\.id)), rendition: .grid)
        await settle()
        #expect(await eventually { a.image(for: Self.albums[0], rendition: .grid) != nil })
        #expect(a.image(for: Self.albums[0], rendition: .spine) == nil)
        #expect(await fake.decodedSizes.allSatisfy { $0 == 512 })
    }

    @Test func bothRenditionsInFlightTogether() async {
        await fake.setHolds(true)
        let a = artwork()
        let all = Set(Self.albums.map(\.id))
        a.update(candidates: candidates(0...0), visibleIDs: all, rendition: .spine)
        await settle()
        a.update(candidates: candidates(0...0), visibleIDs: all, rendition: .grid)
        await settle()
        #expect(await eventually { await fake.requested.count == 2 })
        #expect(await fake.withdrawn.isEmpty)
    }

    @Test func switchingLayoutWithdrawsAndDoesNotBackfill() async {
        await fake.setHolds(true)
        let a = artwork()
        a.update(candidates: candidates(0...1), visibleIDs: Set(Self.albums.map(\.id)), rendition: .spine)
        await settle()
        #expect(await eventually { await fake.requested.count == 2 })
        a.switchLayout()
        #expect(await eventually { await fake.withdrawn.count == 2 })
        #expect(a.image(for: Self.albums[0], rendition: .spine) == nil)
    }

    @Test func budgetsDoNotSqueezeEachOther() async {
        let bytes = 4 * 4 * 4
        let a = artwork(spineBytes: 2 * bytes, gridBytes: 3 * bytes)
        let all = Set(Self.albums.map(\.id))
        a.update(candidates: candidates(0...2), visibleIDs: all, rendition: .grid)
        await settle()
        #expect(await eventually { (0...2).allSatisfy { a.image(for: Self.albums[$0], rendition: .grid) != nil } })
        a.update(candidates: candidates(10...13), visibleIDs: all, rendition: .spine)
        await settle()
        // 4 張並行解碼、完成順序不定：只斷言 spine 留滿 2 張，grid 的 3 張一張都沒被擠掉
        #expect(await eventually { await fake.decodedSizes.count == 7 })
        #expect(await eventually { (10...13).filter { a.image(for: Self.albums[$0], rendition: .spine) != nil }.count == 2 })
        #expect((0...2).allSatisfy { a.image(for: Self.albums[$0], rendition: .grid) != nil })
    }

    @Test func budgetsAreDocumented() {
        #expect(BrowseArtwork.gridByteLimit == 28 * 1_048_576)
    }
}

// 小圖候選：同一 named space 的 frames 與 viewport 求交、由上而下；中心格＝離 viewport 中心最近
struct GridBrowserCandidateTests {
    static let viewport = CGRect(x: 0, y: 100, width: 600, height: 400)

    @Test func candidatesAreVisibleActiveCellsTopToBottom() {
        let frames: [String: CGRect] = [
            "a": CGRect(x: 300, y: 120, width: 100, height: 100), "b": CGRect(x: 10, y: 120, width: 100, height: 100),
            "c": CGRect(x: 10, y: 300, width: 100, height: 100),
            "below": CGRect(x: 10, y: 600, width: 100, height: 100), "edge": CGRect(x: 10, y: 450, width: 100, height: 100),
        ]
        let ids = GridBrowser.visibleIDs(frames: frames, viewport: Self.viewport)
        #expect(ids == ["b", "a", "c", "edge"])
    }

    @Test func centerCellIsNearestToViewportCenter() {
        let frames: [String: CGRect] = ["a": CGRect(x: 0, y: 100, width: 100, height: 100), "b": CGRect(x: 250, y: 250, width: 100, height: 100),
                                        "c": CGRect(x: 500, y: 400, width: 100, height: 100)]
        #expect(GridBrowser.centerCell(frames: frames, viewport: Self.viewport) == "b")
        #expect(GridBrowser.centerCell(frames: [:], viewport: Self.viewport) == nil)
        #expect(GridBrowser.centerCell(frames: frames.filter { $0.key != "b" }, viewport: Self.viewport) != "b")
    }
}
