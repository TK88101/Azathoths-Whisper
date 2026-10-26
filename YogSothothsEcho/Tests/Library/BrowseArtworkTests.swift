import Foundation
import RemoteProtocol
import Testing
import UIKit

@testable import YogSothothsEcho

// S6 T5（sprint-6-detail.md D7、§4.4）：靜止 300 ms 後對中心 ±2 依距離送 detail；離開可見範圍撤回；1,024 px 解碼、已解碼 LRU 24

/// 放行所有等待中的 sleep（模擬「靜止滿 300 ms」）
actor SleepGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var pending = 0
    func wait() async {
        pending += 1
        await withCheckedContinuation { waiters.append($0) }
    }
    func fire() {
        let all = waiters
        waiters = []
        pending = 0
        all.forEach { $0.resume() }
    }
}

actor FakeDetailRequests {
    private(set) var requested: [(String, DetailArtworkScheduler.Priority)] = []
    private(set) var withdrawn: [String] = []
    private(set) var decodedSizes: [Int] = []
    var holds = false
    /// true＝被取消的請求先不返回，等 `releaseCancelled`（重現「舊請求晚到收尾」）
    var holdsCancelled = false
    private var gates: [String: CheckedContinuation<Data?, Never>] = [:]
    private var cancelledGates: [CheckedContinuation<Data?, Never>] = []

    func setHolds(_ value: Bool) { holds = value }
    func setHoldsCancelled(_ value: Bool) { holdsCancelled = value }
    func releaseCancelled() {
        let all = cancelledGates
        cancelledGates = []
        all.forEach { $0.resume(returning: nil) }
    }

    func request(_ id: String, _ priority: DetailArtworkScheduler.Priority) async -> Data? {
        requested.append((id, priority))
        guard holds else { return Data(id.utf8) }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Data?, Never>) in
                if Task.isCancelled { withdrawn.append(id); c.resume(returning: nil) } else { gates[id] = c }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: String) {
        guard let gate = gates.removeValue(forKey: id) else { return }
        withdrawn.append(id)
        if holdsCancelled { cancelledGates.append(gate) } else { gate.resume(returning: nil) }
    }

    func decoded(_ size: Int) { decodedSizes.append(size) }
    var ids: [String] { requested.map(\.0) }
}

@MainActor
struct BrowseArtworkTests {
    let gate = SleepGate()
    let fake = FakeDetailRequests()
    let m = SpineCarouselTests.pro13

    /// 預設預算夠大（不淘汰）；LRU 測試以「張數 × 單張位元組」設預算
    func artwork(spineBytes: Int = BrowseArtwork.spineByteLimit) -> BrowseArtwork {
        BrowseArtworkHarness.make(fake: fake, gate: gate, image: Self.fakeImage, spineBytes: spineBytes)
    }

    /// 假解碼圖 2×2 pt × 螢幕倍率
    static let fakeImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }
    static var fakeImageBytes: Int { fakeImage.cgImage?.byteCost ?? 0 }

    static func albums(_ count: Int, tokenless: Set<Int> = []) -> [AlbumSummary] {
        (0..<count).map {
            AlbumSummary(id: String(format: "%016llx", UInt64($0 + 1)), title: "Album \($0)", artist: "Artist", trackCount: 1,
                         artworkToken: tokenless.contains($0) ? nil : String(format: "%016llx", UInt64($0 + 100)))
        }
    }

    func eventually(_ condition: @escaping () async -> Bool) async -> Bool { await BrowseArtworkHarness.eventually(condition) }
    func settle() async { await BrowseArtworkHarness.settle(gate) }

    func id(_ i: Int) -> String { String(format: "%016llx", UInt64(i + 1)) }
    /// 40 張、停在第 center 張時應升級的張數（螢幕上看得到的全部）
    func expectedCount(center: Int) -> Int {
        BrowseArtwork.candidates(albums: Self.albums(40), offset: CGFloat(center) * m.slot, metrics: m).count
    }

    /// #6-1（使用者 2026-10-22「停下後畫面上約 11 張都要清晰」）：螢幕上看得到的盒子全部升級，不含兩端的緩衝盒；依距中心由近到遠
    @Test func candidatesAreEveryOnScreenBoxByDistance() {
        let albums = Self.albums(40)
        let offset = 10 * m.slot + 10
        let visible = SpineCarousel.visibleRange(offset: offset, count: albums.count, metrics: m)
        let candidates = BrowseArtwork.candidates(albums: albums, offset: offset, metrics: m)
        #expect(candidates.count == visible.count - 2)
        #expect(candidates.count >= 9)
        #expect(candidates.first?.album.id == id(10) && candidates.first?.distance == 0)
        #expect(zip(candidates, candidates.dropFirst()).allSatisfy { $0.distance <= $1.distance })
        #expect(!candidates.contains { $0.album.id == albums[visible.lowerBound].id || $0.album.id == albums[visible.upperBound - 1].id })
        // 起點：左邊沒有盒子也沒有緩衝，只扣右端緩衝
        let start = BrowseArtwork.candidates(albums: albums, offset: 0, metrics: m)
        #expect(start.count == SpineCarousel.visibleRange(offset: 0, count: albums.count, metrics: m).count - 1)
        #expect(start.first?.album.id == id(0))
        #expect(BrowseArtwork.candidates(albums: [], offset: 0, metrics: m).isEmpty)
    }

    @Test func nothingIsRequestedBeforeSettling() async {
        let a = artwork()
        let albums = Self.albums(40)
        let candidates = BrowseArtwork.candidates(albums: albums, offset: 10 * m.slot, metrics: m)
        a.update(candidates: candidates, visibleIDs: Set(albums.map(\.id)))
        #expect(await eventually { await gate.pending == 1 })
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await fake.requested.isEmpty)
        await settle()
        let expected = BrowseArtwork.candidates(albums: albums, offset: 10 * m.slot, metrics: m).count
        #expect(await eventually { await fake.requested.count == expected })
        // 各請求在自己的 Task 裡發出、開始順序不保證；先後由排程器依距離決定（DetailArtworkSchedulerTests），這裡驗帶對距離
        let requested = await fake.requested
        #expect(requested.first { $0.0 == id(10) }?.1 == .browse(distance: 0))
        #expect(requested.first { $0.0 == id(12) }?.1 == .browse(distance: 2))
    }

    /// 再捲動＝重新計時；舊的計時到了也不送
    @Test func scrollingAgainRestartsTheTimer() async {
        let a = artwork()
        let albums = Self.albums(40)
        a.update(candidates: BrowseArtwork.candidates(albums: albums, offset: 10 * m.slot, metrics: m), visibleIDs: Set(albums.map(\.id)))
        a.update(candidates: BrowseArtwork.candidates(albums: albums, offset: 20 * m.slot, metrics: m), visibleIDs: Set(albums.map(\.id)))
        #expect(await eventually { await gate.pending >= 1 })
        await settle()
        let expected = BrowseArtwork.candidates(albums: albums, offset: 20 * m.slot, metrics: m)
        #expect(await eventually { await fake.requested.count == expected.count })
        try? await Task.sleep(for: .milliseconds(20))
        #expect(Set(await fake.ids) == Set(expected.map(\.album.id)))
    }

    @Test func leavingTheVisibleRangeWithdraws() async {
        await fake.setHolds(true)
        let a = artwork()
        let albums = Self.albums(40)
        a.update(candidates: BrowseArtwork.candidates(albums: albums, offset: 10 * m.slot, metrics: m), visibleIDs: Set(albums.map(\.id)))
        await settle()
        let n = expectedCount(center: 10)
        #expect(await eventually { await fake.requested.count == n })
        var visible = Set(albums.map(\.id))
        visible.remove(id(8))
        a.update(candidates: [], visibleIDs: visible)
        #expect(await eventually { await fake.withdrawn == [id(8)] })
    }

    @Test func tokenlessAlbumsAreNeverRequested() async {
        let a = artwork()
        let albums = Self.albums(40, tokenless: [10])
        a.update(candidates: BrowseArtwork.candidates(albums: albums, offset: 10 * m.slot, metrics: m), visibleIDs: Set(albums.map(\.id)))
        await settle()
        let n = expectedCount(center: 10) - 1
        #expect(await eventually { await fake.requested.count == n })
        #expect(await !fake.ids.contains(id(10)))
    }

    /// 捲動中（還沒停）：只撤回範圍外的，不排程升級——慢速拖曳時不能用過期的中心去要 detail
    @Test func scrollingUpdatesDoNotSchedule() async {
        let a = artwork()
        let albums = Self.albums(40)
        a.update(candidates: BrowseArtwork.candidates(albums: albums, offset: 10 * m.slot, metrics: m),
                 visibleIDs: Set(albums.map(\.id)), schedules: false)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await gate.pending == 0)
        await gate.fire()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await fake.requested.isEmpty)
    }

    /// 停在新中心：舊中心還在途、但已不在新的升級範圍內的請求要取消
    @Test func settlingOnANewCenterCancelsStaleRequests() async {
        await fake.setHolds(true)
        let a = artwork()
        let albums = Self.albums(40)
        let all = Set(albums.map(\.id))
        a.update(candidates: BrowseArtwork.candidates(albums: albums, offset: 10 * m.slot, metrics: m), visibleIDs: all)
        await settle()
        let old = Set(BrowseArtwork.candidates(albums: albums, offset: 10 * m.slot, metrics: m).map(\.album.id))
        #expect(await eventually { await fake.requested.count == old.count })
        let new = Set(BrowseArtwork.candidates(albums: albums, offset: 13 * m.slot, metrics: m).map(\.album.id))
        a.update(candidates: BrowseArtwork.candidates(albums: albums, offset: 13 * m.slot, metrics: m), visibleIDs: all)
        await settle()
        #expect(!old.subtracting(new).isEmpty)
        #expect(await eventually { Set(await fake.withdrawn) == old.subtracting(new) })
    }

    /// 捲出又捲回：被取消的舊請求晚到收尾，不得清掉新請求的在途條目（否則新請求再也撤不掉）
    @Test func staleCancelledRequestDoesNotClearTheNewOne() async {
        await fake.setHolds(true)
        await fake.setHoldsCancelled(true)
        let a = artwork()
        let albums = Self.albums(40)
        let all = Set(albums.map(\.id))
        let near10 = BrowseArtwork.candidates(albums: albums, offset: 10 * m.slot, metrics: m)
        a.update(candidates: near10, visibleIDs: all)
        await settle()
        #expect(await eventually { await fake.requested.count == near10.count })
        a.update(candidates: [], visibleIDs: all.subtracting([id(10)]), schedules: false)   // 捲動中捲出：撤回 10
        #expect(await eventually { await fake.withdrawn.contains(id(10)) })
        a.update(candidates: near10, visibleIDs: all)                       // 捲回：再發 10
        await settle()
        #expect(await eventually { (await fake.ids.filter { $0 == id(10) }.count) == 2 })
        await fake.releaseCancelled()                                        // 舊 Task 這時才收尾
        try? await Task.sleep(for: .milliseconds(30))
        a.update(candidates: [], visibleIDs: all.subtracting([id(10)]), schedules: false)   // 再捲出：新的那個也要撤得掉
        #expect(await eventually { (await fake.withdrawn.filter { $0 == id(10) }.count) == 2 })
    }

    /// 在途中封面 token 換了（曲庫換版）：以新 token 重發，不因同一張專輯在途就略過
    @Test func tokenChangeInFlightRequestsAgain() async {
        await fake.setHolds(true)
        let a = artwork()
        let old = Self.albums(1)
        a.update(candidates: [.init(album: old[0], distance: 0)], visibleIDs: [old[0].id])
        await settle()
        #expect(await eventually { await fake.requested.count == 1 })
        let renewed = AlbumSummary(id: old[0].id, title: old[0].title, artist: old[0].artist, trackCount: 1, artworkToken: "00000000000000ff")
        a.update(candidates: [.init(album: renewed, distance: 0)], visibleIDs: [renewed.id])
        await settle()
        #expect(await eventually { await fake.requested.count == 2 })
        #expect(await eventually { await fake.withdrawn == [old[0].id] })
    }

    /// 1,024 px 解碼；已解碼的不再請求；LRU（g 版改以位元組計：預算＝24 張的量），超過逐出最舊
    @Test func decodedImagesAreCachedWithLRU() async {
        let a = artwork(spineBytes: 24 * Self.fakeImageBytes)
        let albums = Self.albums(40)
        // 候選固定為中心 ±2（與升級範圍大小脫鉤，只驗快取）
        func near(_ center: Int) -> [BrowseArtwork.Candidate] {
            (center - 2...center + 2).filter { albums.indices.contains($0) }.map { .init(album: albums[$0], distance: abs($0 - center)) }
        }
        for center in stride(from: 2, through: 32, by: 5) {
            a.update(candidates: near(center), visibleIDs: Set(albums.map(\.id)))
            await settle()
            #expect(await eventually { a.image(for: albums[center]) != nil })
            #expect(await eventually { (await fake.requested.count) == (center + 3) })
        }
        #expect(await eventually { (0...34).filter { a.image(for: albums[$0]) != nil }.count == 24 })
        #expect(a.image(for: albums[0]) == nil)
        #expect(a.image(for: albums[34]) != nil)
        #expect(await fake.decodedSizes.allSatisfy { $0 == 1024 })
        // 已解碼的不再請求
        let before = await fake.requested.count
        a.update(candidates: near(32), visibleIDs: Set(albums.map(\.id)))
        await settle()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await fake.requested.count == before)
    }
}
