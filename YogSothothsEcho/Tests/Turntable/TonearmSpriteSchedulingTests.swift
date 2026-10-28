import CoreGraphics
import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// CR-034 附錄 F（S-Arm 唱臂偶發卡頓）：解碼優先序（E）、唱臂／投影成對發布、關唱機不釋放（A′）、
// 記憶體警告／進背景只在唱機未顯示時釋放、落臂目標幀；DEBUG trace 只在唱臂動畫期間記取幀

private func image(_ side: Int = 1) -> CGImage {
    CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}

/// 每個檔名一個閘門：測試決定放行順序，並記錄請求順序
private actor NamedGate {
    private var waiting: [String: CheckedContinuation<CGImage?, Never>] = [:]
    private(set) var order: [String] = []

    func decode(_ name: String) async -> CGImage? {
        order.append(name)
        return await withCheckedContinuation { waiting[name] = $0 }
    }

    func isWaiting(_ name: String) -> Bool { waiting[name] != nil }
    func release(_ name: String) { waiting.removeValue(forKey: name)?.resume(returning: image()) }
}

struct TonearmSpriteSchedulingTests {
    /// E：先解「靜止幀 0 … 目標幀＋3」（落臂與抬臂都走這段，焦點內為急件），再補其餘
    @Test func prioritizedOrderCoversTheWholeArmPathFirst() {
        var done = Set<Int>(), order: [Int] = [], urgent: [Bool] = []
        while let next = TonearmSpriteCache.nextFrame(done: done, target: 10, count: 35, prioritized: true) {
            order.append(next.frame)
            urgent.append(next.urgent)
            done.insert(next.frame)
        }
        #expect(order == Array(0...34))
        #expect(urgent == Array(repeating: true, count: 14) + Array(repeating: false, count: 21))
    }

    /// 目標在中途變大（播放中角度往前走）：下一個挑的是新範圍內還沒解的
    @Test func targetIsReadEachTime() {
        let done = Set(0...13)
        #expect(TonearmSpriteCache.nextFrame(done: done, target: 10, count: 35, prioritized: true)?.urgent == false)
        let next = TonearmSpriteCache.nextFrame(done: done, target: 20, count: 35, prioritized: true)
        #expect(next?.frame == 14 && next?.urgent == true)
    }

    /// 目標未知（沒有播放資訊）：只有靜止幀算急件；目標超出幀數則夾到最後一幀
    @Test func unknownOrOutOfRangeTargets() {
        #expect(TonearmSpriteCache.nextFrame(done: [], target: nil, count: 35, prioritized: true)! == (0, true))
        #expect(TonearmSpriteCache.nextFrame(done: [0], target: nil, count: 35, prioritized: true)! == (1, false))
        #expect(TonearmSpriteCache.nextFrame(done: Set(0...33), target: 40, count: 35, prioritized: true)! == (34, true))
        #expect(TonearmSpriteCache.nextFrame(done: Set(0...34), target: 5, count: 35, prioritized: true) == nil)
    }

    /// 關掉 E＝舊順序（0…34 依序、全部當一般件）
    @Test func unprioritizedOrderIsAscending() {
        #expect(TonearmSpriteCache.nextFrame(done: [0, 1], target: 30, count: 35, prioritized: false)! == (2, false))
    }
}

@MainActor
struct TonearmSpritePairPublishingTests {
    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<20_000 where !(await condition()) { await Task.yield() }
    }

    /// 唱臂解好、投影還沒好：不發布；兩張都好才一次發布成一對
    @Test func armAndShadowArePublishedTogether() async throws {
        let gate = NamedGate()
        let cache = TonearmSpriteCache(decode: { await gate.decode($0.name) }, onFailure: { _, _ in })
        cache.prioritized = { false }
        let skin = try SpriteSkinFixture.bundled()
        cache.load(skin, pixelScale: 2)
        for name in ["base_underlay.png", "base_overlay.png"] {
            await waitUntil { await gate.isWaiting(name) }
            await gate.release(name)
        }
        await waitUntil { await gate.isWaiting("arm_000.png") }
        await waitUntil { await gate.isWaiting("arm_shadow_000.png") }
        await gate.release("arm_000.png")
        for _ in 0..<500 { await Task.yield() }
        #expect(cache.pairs[0] == nil, "投影還沒好就不發布")
        #expect(cache.frames(forAngle: 0, skin: skin) == nil)
        await gate.release("arm_shadow_000.png")
        await waitUntil { cache.pairs[0] != nil }
        let lookup = try #require(cache.frames(forAngle: 5, skin: skin))
        #expect(lookup.frame == 0 && !lookup.exact, "要第 5 幀只有第 0 幀：最近的一對頂上、標記非精確")
        #expect(cache.frames(forAngle: 0.2, skin: skin)?.exact == true)
        cache.release()
    }

    /// 每解完一對就重讀焦點：焦點改到 20 之後，下一對是急件範圍內最小的未解幀
    @Test func focusIsReadBetweenPairs() async throws {
        let gate = NamedGate()
        let cache = TonearmSpriteCache(decode: { await gate.decode($0.name) }, onFailure: { _, _ in })
        var target: Int? = nil
        cache.focusTarget = { target }
        cache.prioritized = { true }
        cache.load(try SpriteSkinFixture.bundled(), pixelScale: 2)
        for name in ["base_underlay.png", "base_overlay.png"] {
            await waitUntil { await gate.isWaiting(name) }
            await gate.release(name)
        }
        await waitUntil { await gate.isWaiting("arm_000.png") }
        await waitUntil { await gate.isWaiting("arm_shadow_000.png") }
        await gate.release("arm_000.png")
        await gate.release("arm_shadow_000.png")
        await waitUntil { await gate.isWaiting("arm_001.png") }
        await waitUntil { await gate.isWaiting("arm_shadow_001.png") }
        #expect(Set(await gate.order.suffix(2)) == ["arm_001.png", "arm_shadow_001.png"])
        target = 20
        await gate.release("arm_001.png")
        await gate.release("arm_shadow_001.png")
        await waitUntil { await gate.isWaiting("arm_002.png") }
        #expect(cache.pairs.keys.sorted() == [0, 1])
        cache.release()
    }
}

@MainActor
struct TurntableSpriteLifecycleTests {
    let client = FakePlaybackClient()
    let nowPlaying = NowPlayingViewModel(now: ManualNow().now, sleep: { _ in })
    let store = InMemorySettingsStore()

    private func makeModel(keepOnClose: Bool) throws -> TurntableViewModel {
        let model = TurntableViewModel(nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2, artwork: { _ in nil },
                                       palette: { _ in .fallback }, sleep: { _ in }, transitionSleep: { _ in },
                                       catalog: TurntableSkinCatalog(skins: [.classic, try SpriteSkinFixture.bundled()]),
                                       spriteDecode: { _ in image() }, keepSpritesOnClose: { keepOnClose })
        return model
    }

    private func shownWithSArm(_ model: TurntableViewModel) async {
        model.open(reduceMotion: true)
        for _ in 0..<1000 where model.layer != .shown { await Task.yield() }
        model.selectSkin("s-arm-1200")
        model.prepareSprites(layoutScale: 1.7)
        for _ in 0..<20_000 where !model.sprites.isComplete { await Task.yield() }
    }

    /// A′：關唱機不釋放、不換世代；再開同皮膚同縮放不重解
    @Test func closingKeepsDecodedFrames() async throws {
        let model = try makeModel(keepOnClose: true)
        await shownWithSArm(model)
        let generation = model.sprites.generation
        model.close(reduceMotion: true)
        #expect(model.sprites.generation == generation && model.sprites.isComplete)
        model.prepareSprites(layoutScale: 1.7)
        #expect(model.sprites.generation == generation)
    }

    /// 關掉 A′＝舊行為（關唱機即釋放）
    @Test func closingReleasesWhenKeepIsOff() async throws {
        let model = try makeModel(keepOnClose: false)
        await shownWithSArm(model)
        let generation = model.sprites.generation
        model.close(reduceMotion: true)
        #expect(model.sprites.generation > generation && model.sprites.pairs.isEmpty)
    }

    /// 斷線使唱機被移出：照舊釋放
    @Test func hidingImmediatelyStillReleases() async throws {
        let model = try makeModel(keepOnClose: true)
        await shownWithSArm(model)
        model.hideImmediately()
        #expect(model.sprites.pairs.isEmpty && model.sprites.base == nil)
    }

    /// 記憶體警告／進背景：唱機顯示中不釋放（釋放會讓唱臂空白又立刻重解），未顯示才釋放
    @Test func memoryPressureReleasesOnlyWhenHidden() async throws {
        let model = try makeModel(keepOnClose: true)
        await shownWithSArm(model)
        model.releaseSpritesIfHidden()
        #expect(model.sprites.isComplete, "顯示中保留")
        model.close(reduceMotion: true)
        for _ in 0..<1000 where model.layer != .hidden { await Task.yield() }
        model.releaseSpritesIfHidden()
        #expect(model.sprites.pairs.isEmpty)
    }

    /// 解碼焦點＝目前進度在這款皮膚上對應的幀（落臂會落到那裡；抬臂從那裡起）
    @Test func focusFollowsPlaybackProgress() async throws {
        let model = try makeModel(keepOnClose: true)
        #expect(model.spriteFocusFrame == nil, "沒有播放資訊")
        nowPlaying.attach(client)
        await settle()
        client.push(PlaybackSamples.event(PlaybackSamples.t1, .paused, position: 100, at: 1))
        await settle()
        await shownWithSArm(model)
        let expected = TonearmSpriteCache.frameIndex(angle: model.skin.angle(progress: 0.5), rest: model.skin.restDegrees, count: 35)
        #expect(model.spriteFocusFrame == expected)
    }
}

#if DEBUG
@MainActor
struct SpriteTraceTests {
    /// 取幀只在唱臂動畫期間記錄；存檔含開關狀態，不含曲名
    @Test func recordsFrameRequestsOnlyDuringArmMotion() throws {
        var now = 100.0
        let trace = SpriteTrace(clock: { now })
        trace.frameRequested(requested: 5, served: 3, exact: false)
        #expect(trace.events.isEmpty)
        trace.armMotionStarted(duration: 1)
        trace.frameRequested(requested: 5, served: 3, exact: false)
        now = 100.5
        trace.decodePublished(frame: 5, generation: 2)
        now = 101.2
        trace.frameRequested(requested: 6, served: 6, exact: true)
        #expect(trace.events.map(\.kind) == ["armMotionStart", "frame", "published"])
        let data = try trace.encoded(context: ["keepOnClose": "true", "prioritized": "false"])
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"prioritized\":\"false\"") && json.contains("\"requested\":5"))
    }
}
#endif
