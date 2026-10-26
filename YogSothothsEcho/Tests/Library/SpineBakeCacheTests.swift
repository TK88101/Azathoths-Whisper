import CoreGraphics
import RemoteProtocol
import SwiftUI
import Testing
import UIKit

@testable import YogSothothsEcho

// S6 #6-1 g 版 T2（s6-61-g-perf-wear.md §5.1）：烘焙佇列（並行 2、世代丟棄、同鍵去重、等待者取消不連帶）、預熱兩側、像素來源換鍵

/// 可擋住的假 renderer：記錄呼叫，閘門開了才回圖
final class GatedBakeRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private var gates: [CheckedContinuation<Void, Never>] = []
    private(set) var started: [String] = []
    var blocked = true

    func render(_ input: SpineBake.Input) async -> CGImage? {
        let wait = lock.withLock { () -> Bool in started.append(input.key.albumID + (input.key.side == .left ? "L" : "R")); return blocked }
        if wait { await withCheckedContinuation { c in lock.withLock { gates.append(c) } } }
        return Self.image
    }

    var startedCount: Int { lock.withLock { started.count } }
    var waitingCount: Int { lock.withLock { gates.count } }

    func releaseAll() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in blocked = false; defer { gates = [] }; return gates }
        pending.forEach { $0.resume() }
    }

    static let image: CGImage = {
        let ctx = CGContext(data: nil, width: 2, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }()
}

@MainActor
struct SpineBakeCacheTests {
    static func input(_ id: String, side: CarouselSide = .left) -> SpineBake.Input {
        SpineBake.Input(key: SpineBake.Key(albumID: id, title: "t", artist: "a", source: .placeholder, side: side, thickness: 20,
                                           cover: 600, scale: 2),
                        cover: nil, placeholder: RGBColor(r: 0.3, g: 0.3, b: 0.3))
    }

    static func settle() async { for _ in 0..<20 { await Task.yield() } }

    /// 烘焙在 utility 優先級的 detached task 上開工：全量並行時 20 次 yield 不保證輪得到（S6 #6-1 G1 驗證時 2 條紅）。
    /// 等到條件成立（上限 2 s），再多等一段確認沒有多開工
    static func settle(until condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test func requestBakesOnceAndCaches() async {
        let renderer = GatedBakeRenderer()
        renderer.blocked = false
        let cache = SpineBakeCache(render: renderer.render)
        let a = await cache.request(Self.input("a"))
        let b = await cache.request(Self.input("a"))
        #expect(a != nil && b != nil)
        #expect(renderer.startedCount == 1)
        #expect(cache.cached(Self.input("a").key) != nil)
    }

    @Test func atMostTwoRenderAtOnce() async {
        let renderer = GatedBakeRenderer()
        let cache = SpineBakeCache(render: renderer.render)
        cache.prefetch((0..<5).map { .init(input: Self.input("p\($0)"), priority: $0) })
        await Self.settle { renderer.startedCount >= 2 }
        #expect(renderer.startedCount == 2)
        renderer.releaseAll()
        await Self.settle { renderer.startedCount >= 5 }
        #expect(renderer.startedCount == 5)
    }

    @Test func newGenerationDropsUnwantedPending() async {
        let renderer = GatedBakeRenderer()
        let cache = SpineBakeCache(render: renderer.render)
        cache.prefetch((0..<5).map { .init(input: Self.input("p\($0)"), priority: $0) })
        await Self.settle { renderer.startedCount >= 2 }
        cache.prefetch([.init(input: Self.input("q"), priority: 0)])
        renderer.releaseAll()
        await Self.settle { renderer.startedCount >= 3 }
        #expect(Set(renderer.started) == ["p0L", "p1L", "qL"])
    }

    @Test func pendingWithWaiterIsNotDropped() async {
        let renderer = GatedBakeRenderer()
        let cache = SpineBakeCache(render: renderer.render)
        cache.prefetch([.init(input: Self.input("x"), priority: 0), .init(input: Self.input("y"), priority: 1), .init(input: Self.input("z"), priority: 2)])
        let waiter = Task { await cache.request(Self.input("z")) }
        await Self.settle()
        cache.prefetch([])
        renderer.releaseAll()
        #expect(await waiter.value != nil)
        #expect(renderer.started.contains("zL"))
    }

    @Test func cancellingOneWaiterKeepsSharedBake() async {
        let renderer = GatedBakeRenderer()
        let cache = SpineBakeCache(render: renderer.render)
        let first = Task { await cache.request(Self.input("s")) }
        let second = Task { await cache.request(Self.input("s")) }
        await Self.settle()
        first.cancel()
        renderer.releaseAll()
        #expect(await second.value != nil)
        #expect(renderer.startedCount == 1)
    }

    /// Codex 實作 R1 P1：盒子離開畫面（視圖 task 取消）＝撤掉等待者；沒人等、不在預熱需求內的未開工項目丟棄
    @Test func cancelledWaiterOutsidePrefetchIsDropped() async {
        let renderer = GatedBakeRenderer()
        let cache = SpineBakeCache(render: renderer.render)
        cache.prefetch([.init(input: Self.input("x"), priority: 0), .init(input: Self.input("y"), priority: 1)])
        let waiter = Task { await cache.request(Self.input("gone")) }
        await Self.settle()
        cache.prefetch([.init(input: Self.input("x"), priority: 0), .init(input: Self.input("y"), priority: 1)])
        waiter.cancel()
        #expect(await waiter.value == nil)
        await Self.settle()
        renderer.releaseAll()
        await Self.settle()
        #expect(!renderer.started.contains("goneL"))
    }

    @Test func latestFallsBackToPreviousSourceForSameFace() async {
        let renderer = GatedBakeRenderer()
        renderer.blocked = false
        let cache = SpineBakeCache(render: renderer.render)
        let old = Self.input("f")
        _ = await cache.request(old)
        let upgraded = SpineBake.Key(albumID: "f", title: "t", artist: "a", source: .artwork(token: "k", pixelWidth: 1024), side: .left,
                                     thickness: 20, cover: 600, scale: 2)
        #expect(cache.cached(upgraded) == nil)
        #expect(cache.bestAvailable(upgraded) != nil)
        let otherSide = SpineBake.Key(albumID: "f", title: "t", artist: "a", source: .placeholder, side: .right, thickness: 20, cover: 600,
                                      scale: 2)
        #expect(cache.bestAvailable(otherSide) == nil)
    }
}

// 預熱：可見盒兩側都入隊，目前側優先、距中心越近越先
@MainActor
struct SpineBakePrefetchTests {
    static func album(_ i: Int) -> AlbumSummary {
        AlbumSummary(id: String(format: "%016x", i + 1), title: "T\(i)", artist: "A", trackCount: 1, artworkToken: "k\(i)")
    }

    @Test func bothSidesQueuedCurrentSideFirst() {
        let m = SpineCarouselTests.pro13
        let albums = (0..<20).map(Self.album)
        let offset = 10.3 * m.slot
        let requests = SpineBakePrefetch.requests(albums: albums, range: 8..<13, offset: offset, metrics: m, scale: 2) { _ in nil }
        #expect(requests.count == 10)
        let center = requests.filter { $0.input.key.albumID == albums[10].id }
        #expect(Set(center.map(\.input.key.side)) == [.left, .right])
        let sorted = requests.sorted { $0.priority < $1.priority }
        #expect(sorted.first?.input.key.albumID == albums[10].id)
        for album in albums[8..<13] {
            let pair = requests.filter { $0.input.key.albumID == album.id }
            let u = SpineCarousel.u(index: albums.firstIndex(of: album)!, offset: offset, metrics: m)
            let current = SpineCarousel.pose(u: u, metrics: m).side
            let mine = pair.first { $0.input.key.side == current }!, other = pair.first { $0.input.key.side != current }!
            #expect(mine.priority < other.priority)
        }
    }

    @Test func sourceRevisionTracksPixelWidth() {
        let small = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in }
        let large = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in }
        let album = Self.album(0)
        let a = SpineBake.input(album: album, image: small, side: .left, thickness: 20, cover: 600, scale: 2)
        let b = SpineBake.input(album: album, image: large, side: .left, thickness: 20, cover: 600, scale: 2)
        let c = SpineBake.input(album: album, image: nil, side: .left, thickness: 20, cover: 600, scale: 2)
        #expect(a.key.source == .artwork(token: "k0", pixelWidth: 160))
        #expect(b.key.source == .artwork(token: "k0", pixelWidth: 1024))
        #expect(c.key.source == .placeholder)
        #expect(a.key != b.key)
    }
}

// SpineFace 接上烘焙：同步模式下畫出的就是烘焙圖（四角透明）
@MainActor
struct SpineFaceBakeRenderTests {
    @Test func spineFaceShowsBakedSilhouette() throws {
        SpineBakeCache.shared.rendersSynchronously = true
        defer { SpineBakeCache.shared.rendersSynchronously = false }
        let album = AlbumSummary(id: "wear-0", title: "Fixture", artist: "Artist", trackCount: 1, artworkToken: nil)
        let thickness = 400 * SpineCarouselMetrics.spineToCover
        let view = SpineFace(album: album, image: nil, cover: 400, thickness: thickness, side: .left)
            .frame(width: thickness, height: 400)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let p = SpineBakeTests.pixels(image)
        #expect(p.alpha(0, 0) < 255 && p.alpha(p.width - 1, p.height - 1) < 255)
        #expect(p.alpha(p.width / 2, p.height / 2) == 255)
    }
}
