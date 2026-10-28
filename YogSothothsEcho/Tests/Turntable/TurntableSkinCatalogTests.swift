import CoreGraphics
import Foundation
import Testing

@testable import YogSothothsEcho

// CR-034 T6a（yse-1.0.1-skins.md §4.3、§4.4）：皮膚目錄的 preflight（缺檔／壞 JSON／求解拒絕／檔頭尺寸不符 → 不可用、只記一次）
// 與序列圖快取（幀選擇、最近幀頂替、世代擋晚到、釋放、解碼失敗回報）

/// 以記憶體模擬 bundle：檔名 → 內容
private final class FakeSkinBundle: SkinBundleReading, @unchecked Sendable {
    var files: [String: Data] = [:]

    func contents(of name: String, in folder: String) -> Data? { files["\(folder)/\(name)"] }
    func pngPixelSize(of name: String, in folder: String) -> CGSize? {
        files["\(folder)/\(name)"].flatMap(PNGHeader.pixelSize)
    }
}

/// 只有 IHDR 的 PNG 檔頭（preflight 只讀檔頭）
private func pngHeader(_ width: Int, _ height: Int) -> Data {
    var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]) + Data("IHDR".utf8)
    for value in [width, height] { data += withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) } }
    return data + Data([8, 6, 0, 0, 0])
}

private let folder = "Skins/s-arm-1200"

/// 真 bundle 的 skin.json ＋ 依其尺寸補齊每個檔的檔頭（註冊表上每一款序列圖皮膚；增補 A 起不只 s-arm-1200）
private func completeBundle() throws -> FakeSkinBundle {
    let bundle = FakeSkinBundle()
    for folder in TurntableSkinEntry.all.compactMap(\.sprite).map(\.folder) {
        let url = try #require(Bundle.main.url(forResource: "skin", withExtension: "json", subdirectory: folder))
        let json = try Data(contentsOf: url)
        let manifest = try SpriteSkinManifest.decode(json)
        bundle.files["\(folder)/skin.json"] = json
        let l = manifest.layers
        func put(_ name: String, _ size: [Double]) { bundle.files["\(folder)/\(name)"] = pngHeader(Int(size[0]), Int(size[1])) }
        for frame in 0..<manifest.frameCount {
            put(String(format: l.arm.filePattern, frame), l.arm.sizePx)
            put(String(format: l.armShadow.filePattern, frame), l.armShadow.sizePx)
        }
        put(l.base.file, l.base.sizePx)
        if let middle = l.baseMiddle { put(middle.file, middle.sizePx) }
        put(l.baseOverlay.file, l.baseOverlay.sizePx)
    }
    return bundle
}

@MainActor
struct TurntableSkinCatalogTests {
    private func load(_ bundle: FakeSkinBundle) -> (TurntableSkinCatalog, [String]) {
        var reports: [String] = []
        let catalog = TurntableSkinCatalog.load(reader: bundle) { id, error in reports.append("\(id) \(error)") }
        return (catalog, reports)
    }

    @Test func completeBundleOffersClassicFirstThenSArm() throws {
        let (catalog, reports) = load(try completeBundle())
        #expect(catalog.skins.map(\.spec.id) == TurntableSkinEntry.all.map(\.id))
        #expect(reports.isEmpty)
        #expect(catalog.skin(id: "s-arm-1200")?.spec.id == "s-arm-1200" && catalog.skin(id: "nope") == nil && catalog.skin(id: nil) == nil)
    }

    @Test func missingManifestLeavesOnlyClassic() throws {
        let bundle = try completeBundle()
        bundle.files["\(folder)/skin.json"] = nil
        let (catalog, reports) = load(bundle)
        #expect(catalog.skins.map(\.spec.id) == TurntableSkinEntry.all.map(\.id).filter { $0 != "s-arm-1200" })
        #expect(reports == ["s-arm-1200 missingAsset"])
    }

    @Test func brokenManifestLeavesOnlyClassic() throws {
        let bundle = try completeBundle()
        bundle.files["\(folder)/skin.json"] = Data("{".utf8)
        #expect(load(bundle).1 == ["s-arm-1200 invalidManifest"])
        #expect(load(bundle).0.skins.map(\.spec.id) == TurntableSkinEntry.all.map(\.id).filter { $0 != "s-arm-1200" })
    }

    @Test func manifestTheResolverRejectsLeavesOnlyClassic() throws {
        let bundle = try completeBundle()
        let original = try #require(bundle.files["\(folder)/skin.json"])
        var json = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var kinematics = try #require(json["kinematics"] as? [String: Any])
        kinematics["stylus_at_rest_u"] = [0, 0]
        json["kinematics"] = kinematics
        bundle.files["\(folder)/skin.json"] = try JSONSerialization.data(withJSONObject: json)
        #expect(load(bundle).1 == ["s-arm-1200 zeroStylus"])
    }

    @Test func missingFrameLeavesOnlyClassic() throws {
        let bundle = try completeBundle()
        bundle.files["\(folder)/arm_shadow_017.png"] = nil
        #expect(load(bundle).1 == ["s-arm-1200 missingAsset"])
    }

    @Test func headerSizeMismatchLeavesOnlyClassic() throws {
        let bundle = try completeBundle()
        bundle.files["\(folder)/base_overlay.png"] = pngHeader(10, 10)
        #expect(load(bundle).1 == ["s-arm-1200 missingAsset"])
    }

    /// 增補 B：中層檔缺或檔頭尺寸不符＝只有 Technics 不可用，其餘照常
    @Test func middleLayerFileIsPartOfThePreflight() throws {
        let middle = "Skins/technics-sl1200g/base_middle.png"
        let wrongSize = try completeBundle()
        wrongSize.files[middle] = pngHeader(10, 10)
        #expect(load(wrongSize).1 == ["technics-sl1200g missingAsset"])
        let missing = try completeBundle()
        missing.files[middle] = nil
        let (catalog, reports) = load(missing)
        #expect(reports == ["technics-sl1200g missingAsset"])
        #expect(catalog.skins.map(\.spec.id) == TurntableSkinEntry.all.map(\.id).filter { $0 != "technics-sl1200g" })
    }

    @Test func pngHeaderParsing() {
        #expect(PNGHeader.pixelSize(pngHeader(382, 1938)) == CGSize(width: 382, height: 1938))
        #expect(PNGHeader.pixelSize(Data("not a png at all, long enough".utf8)) == nil)
        #expect(PNGHeader.pixelSize(pngHeader(1, 1).prefix(20)) == nil)
    }

    /// 整合：app bundle 內真的 72 個檔都在、檔頭尺寸與 skin.json 相符
    @Test func realBundlePassesPreflight() {
        var reports: [String] = []
        let catalog = TurntableSkinCatalog.load(reader: MainBundleSkinReader()) { id, error in reports.append("\(id) \(error)") }
        #expect(catalog.skins.map(\.spec.id) == TurntableSkinEntry.all.map(\.id), "\(reports)")
    }
}

// MARK: 序列圖快取

/// 可控的解碼器：每個請求等測試放行；可指定某檔失敗
private actor DecodeGate {
    private var waiting: [String: CheckedContinuation<CGImage?, Never>] = [:]
    private(set) var requested: [String] = []

    func decode(_ name: String) async -> CGImage? {
        requested.append(name)
        return await withCheckedContinuation { waiting[name] = $0 }
    }

    func isWaiting(_ name: String) -> Bool { waiting[name] != nil }

    func release(_ name: String, _ image: CGImage?) {
        waiting.removeValue(forKey: name)?.resume(returning: image)
    }

    func releaseAll() {
        for (name, continuation) in waiting { continuation.resume(returning: name.contains("broken") ? nil : solidImage()) }
        waiting = [:]
    }
}

private func solidImage(_ width: Int = 4, _ height: Int = 4) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@MainActor
struct TonearmSpriteCacheTests {
    private func sArm() throws -> ResolvedTurntableSkin { try SpriteSkinFixture.bundled() }

    /// 等到條件成立，以時間為上限：解碼在背景執行緒，機器忙時「讓出 N 次」不夠等（全量與建置同跑時曾誤紅）
    private func waitUntil(timeout: Duration = .seconds(30), _ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
    }

    /// 取最近的整數度幀，夾在 0…幀數−1
    @Test func frameIndexRoundsAndClamps() {
        #expect(TonearmSpriteCache.frameIndex(angle: 13.4, rest: 0, count: 35) == 13)
        #expect(TonearmSpriteCache.frameIndex(angle: 13.5, rest: 0, count: 35) == 14)
        #expect(TonearmSpriteCache.frameIndex(angle: -3, rest: 0, count: 35) == 0)
        #expect(TonearmSpriteCache.frameIndex(angle: 40, rest: 0, count: 35) == 34)
        #expect(TonearmSpriteCache.frameIndex(angle: 25, rest: 10, count: 35) == 15)
    }

    @Test func loadsEveryLayerAndServesTheNearestDecodedFrame() async throws {
        let gate = DecodeGate()
        let cache = TonearmSpriteCache(decode: { request in await gate.decode(request.name) }, onFailure: { _, _ in })
        let skin = try sArm()
        cache.load(skin, pixelScale: 2)
        await waitUntil { await gate.isWaiting("base_underlay.png") }
        await gate.release("base_underlay.png", solidImage())
        await waitUntil { await gate.isWaiting("base_overlay.png") }
        await gate.release("base_overlay.png", solidImage())
        await waitUntil { await gate.isWaiting("arm_000.png") }
        await waitUntil { await gate.isWaiting("arm_shadow_000.png") }
        #expect(cache.frames(forAngle: 20, skin: skin) == nil, "還沒有任何一對＝不畫唱臂")
        await gate.release("arm_000.png", solidImage(1, 1))
        await gate.release("arm_shadow_000.png", solidImage(1, 1))
        await waitUntil { cache.pairs[0] != nil }
        // 要第 20 幀但只有第 0 幀：以最近的已發布一對頂上
        #expect(cache.frames(forAngle: 20, skin: skin)?.pair.arm.width == 1)
        // releaseAll 只放行當下在等的請求：反覆放行直到全部解完
        let deadline = ContinuousClock.now + .seconds(30)
        while !cache.isComplete, ContinuousClock.now < deadline {
            await gate.releaseAll()
            await Task.yield()
        }
        #expect(cache.isComplete)
        #expect(cache.base != nil && cache.overlay != nil)
        #expect(cache.frames(forAngle: 20.4, skin: skin)?.exact == true)
        #expect(cache.residentBytes > 0)
    }

    /// 增補 B：中層夾在兩層底座之間解碼；全部完成後常駐量＝70 幀＋3 張靜態圖
    @Test func threeLayerSkinDecodesTheMiddleBetweenBaseAndOverlay() async throws {
        let gate = DecodeGate()
        let cache = TonearmSpriteCache(decode: { request in await gate.decode(request.name) }, onFailure: { _, _ in })
        cache.load(try SpriteSkinFixture.bundled(.technicsSL1200G), pixelScale: 2)
        let deadline = ContinuousClock.now + .seconds(30)
        while !cache.isComplete, ContinuousClock.now < deadline {
            await gate.releaseAll()
            await Task.yield()
        }
        #expect(cache.isComplete && cache.middle != nil)
        #expect(Array(await gate.requested.prefix(3)) == [SpriteSkinAssets.baseFile, SpriteSkinAssets.middleFile, SpriteSkinAssets.overlayFile])
        #expect(cache.residentBytes == (SpriteSkinAssets.frameCount * 2 + 3) * solidImage().byteCost)
    }

    /// 兩層 golden（Codex r1-6）：沒有中層的皮膚不請求中層、靜態圖順序仍是 base → overlay、常駐量不變
    @Test func twoLayerSkinNeverRequestsAMiddle() async throws {
        let gate = DecodeGate()
        let cache = TonearmSpriteCache(decode: { request in await gate.decode(request.name) }, onFailure: { _, _ in })
        cache.load(try sArm(), pixelScale: 2)
        let deadline = ContinuousClock.now + .seconds(30)
        while !cache.isComplete, ContinuousClock.now < deadline {
            await gate.releaseAll()
            await Task.yield()
        }
        let requested = await gate.requested
        #expect(cache.isComplete && cache.middle == nil)
        #expect(!requested.contains(SpriteSkinAssets.middleFile) && Array(requested.prefix(2)) == [SpriteSkinAssets.baseFile, SpriteSkinAssets.overlayFile])
        #expect(requested.count == SpriteSkinAssets.frameCount * 2 + 2)
        #expect(cache.residentBytes == (SpriteSkinAssets.frameCount * 2 + 2) * solidImage().byteCost)
    }

    /// 釋放後晚到的中層不寫回
    @Test func releaseDropsALateMiddle() async throws {
        let gate = DecodeGate()
        let cache = TonearmSpriteCache(decode: { request in await gate.decode(request.name) }, onFailure: { _, _ in })
        cache.load(try SpriteSkinFixture.bundled(.technicsSL1200G), pixelScale: 2)
        await waitUntil { await gate.isWaiting(SpriteSkinAssets.baseFile) }
        await gate.release(SpriteSkinAssets.baseFile, solidImage())
        await waitUntil { await gate.isWaiting(SpriteSkinAssets.middleFile) }
        cache.release()
        await gate.release(SpriteSkinAssets.middleFile, solidImage())
        for _ in 0..<200 { await Task.yield() }
        #expect(cache.middle == nil && cache.residentBytes == 0)
    }

    @Test func loadingTheSameSkinAndScaleAgainDoesNothing() async throws {
        let gate = DecodeGate()
        let cache = TonearmSpriteCache(decode: { request in await gate.decode(request.name) }, onFailure: { _, _ in })
        let skin = try sArm()
        cache.load(skin, pixelScale: 2)
        let generation = cache.generation
        cache.load(skin, pixelScale: 2)
        #expect(cache.generation == generation)
        cache.load(skin, pixelScale: 3)
        #expect(cache.generation == generation + 1, "畫面縮放變了＝重解")
        cache.release()
        await gate.releaseAll()
    }

    /// 釋放後晚到的解碼結果不進快取（世代不符）
    @Test func releaseDropsEverythingAndIgnoresLateResults() async throws {
        let gate = DecodeGate()
        let cache = TonearmSpriteCache(decode: { request in await gate.decode(request.name) }, onFailure: { _, _ in })
        cache.load(try sArm(), pixelScale: 2)
        await waitUntil { await gate.isWaiting("base_underlay.png") }
        cache.release()
        await gate.release("base_underlay.png", solidImage())
        for _ in 0..<200 { await Task.yield() }
        #expect(cache.base == nil && cache.residentBytes == 0)
    }

    /// 解碼失敗：回報皮膚 id 與當時的世代，由擁有者決定退回（R2-2）
    @Test func decodeFailureReportsTheSkinAndGeneration() async throws {
        let gate = DecodeGate()
        var failures: [(String, Int)] = []
        let cache = TonearmSpriteCache(decode: { request in await gate.decode(request.name) }, onFailure: { failures.append(($0, $1)) })
        cache.load(try sArm(), pixelScale: 2)
        let generation = cache.generation
        await waitUntil { await gate.isWaiting("base_underlay.png") }
        await gate.release("base_underlay.png", nil)
        await waitUntil { !failures.isEmpty }
        #expect(failures.count == 1 && failures.first?.0 == "s-arm-1200" && failures.first?.1 == generation)
    }

    /// T7 記憶體閘門（§4.4）：真素材、真解碼器，13 吋（R＝800 pt、2×）與 mini 的畫面像素下，全部幀常駐量 ≤ 200 MiB
    @Test(arguments: [800.0, 576.6])
    func realAssetsDecodeWithinTheMemoryBudget(recordDiameter: Double) async throws {
        let cache = TonearmSpriteCache(onFailure: { _, _ in Issue.record("解碼失敗") })
        let skin = try sArm()
        cache.load(skin, pixelScale: recordDiameter / TurntableMetrics.recordSize * 2)
        await waitUntil(timeout: .seconds(60)) { cache.isComplete }
        #expect(cache.isComplete && cache.pairs.count == 35)
        let mib = Double(cache.residentBytes) / 1_048_576
        #expect(mib <= 200, "常駐 \(mib) MiB")
        print("CR-034 T7 memory: R=\(recordDiameter) → \(String(format: "%.1f", mib)) MiB")
    }

    /// 解碼尺寸：畫面像素 / u（不超過素材的 4 px/u），以各層長邊計
    @Test func decodeSizeFollowsTheScreenButNeverUpscales() async throws {
        actor Sizes { var values: [String: Int] = [:]; func put(_ k: String, _ v: Int) { values[k] = v } }
        let sizes = Sizes()
        let cache = TonearmSpriteCache(decode: { request in await sizes.put(request.name, request.maxPixelSize); return solidImage() },
                                       onFailure: { _, _ in })
        let skin = try sArm()
        cache.load(skin, pixelScale: 2)
        await waitUntil { cache.isComplete }
        #expect(await sizes.values["arm_000.png"] == Int((skin.spec.arm.size.height * 2).rounded(.up)))
        cache.load(skin, pixelScale: 9)
        await waitUntil { cache.isComplete && cache.generation == 2 }
        #expect(await sizes.values["arm_000.png"] == Int((skin.spec.arm.size.height * 4).rounded(.up)))
    }
}
