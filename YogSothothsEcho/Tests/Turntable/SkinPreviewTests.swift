import CoreGraphics
import Foundation
import Testing

@testable import YogSothothsEcho

// CR-034 增補 A T4（yse-1.0.1-skin-picker.md §4.3）：選擇器預覽＝唱臂 rest 姿態＋底座，執行期由各皮膚圖層合成。
// 幾何（純函式）、合成（色塊替身像素測試，r1-5）、renderer 快取（鍵含像素尺寸、同鍵合併、LRU、失敗只記一次、取消不算失敗）

private func solid(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, size: Int = 8) -> CGImage {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()!
}

/// 每一層一個顏色（Z 序由下而上）
private let layerColors: [SkinPreviewLayer.Kind: (CGFloat, CGFloat, CGFloat)] = [
    .base: (1, 0, 0), .baseMiddle: (1, 0, 1), .armShadow: (0, 0, 1), .arm: (0, 1, 0), .baseOverlay: (1, 1, 0),
]

private func stubImage(_ kind: SkinPreviewLayer.Kind) -> CGImage {
    let c = layerColors[kind]!
    return solid(c.0, c.1, c.2)
}

/// 左上原點讀一個像素（RGBA 0…255）
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let i = (y * image.width + x) * 4
    return Array(buffer[i..<i + 4])
}

private func expected(_ kind: SkinPreviewLayer.Kind) -> [UInt8] {
    let c = layerColors[kind]!
    return [UInt8(c.0 * 255), UInt8(c.1 * 255), UInt8(c.2 * 255), 255]
}

private func skins() throws -> [ResolvedTurntableSkin] {
    [.classic, try SpriteSkinFixture.bundled(.sArm1200), try SpriteSkinFixture.bundled(.regaRB330),
     try SpriteSkinFixture.bundled(.technicsSL1200G)]
}

// MARK: 幾何

struct SkinPreviewGeometryTests {
    /// 每層畫框＝版面同一公式（左上＝支點 − 框內支點），rest 姿態不轉；Z 序 base →（中層）→ 投影 → 唱臂 → 上層底座
    @Test func layersUseTheLayoutFormulaInZOrder() throws {
        for skin in try skins() {
            let spec = skin.spec
            let layers = SkinPreviewGeometry.layers(for: skin)
            let middle: [SkinPreviewLayer.Kind] = spec.baseMiddle == nil ? [] : [.baseMiddle]
            let expectedKinds: [SkinPreviewLayer.Kind] = spec.spriteLayers == nil
                ? [.base, .arm] : [.base] + middle + [.armShadow, .arm, .baseOverlay]
            #expect(layers.map(\.kind) == expectedKinds, "\(spec.id)")
            let frames: [SkinPreviewLayer.Kind: ArtworkFrame] = [.base: spec.base, .arm: spec.arm]
                .merging([.armShadow: spec.armShadow, .baseOverlay: spec.baseOverlay, .baseMiddle: spec.baseMiddle]
                    .compactMapValues { $0 }) { a, _ in a }
            for layer in layers {
                let frame = try #require(frames[layer.kind])
                #expect(layer.rect == CGRect(origin: spec.origin(of: frame), size: frame.size), "\(spec.id) \(layer.kind)")
            }
        }
    }

    /// rest 幀不寫死 000：與唱機落臂前畫的同一幀（m-1）
    @Test func restFrameIsTheFrameShownAtRest() throws {
        for skin in try skins() {
            let frame = SkinPreviewGeometry.restFrame(for: skin)
            #expect(frame == TonearmSpriteCache.frameIndex(angle: skin.restDegrees, rest: skin.restDegrees, count: SpriteSkinAssets.frameCount))
        }
    }

    /// 設定頁那一列的裁法：以支點為中心的正方形，左右涵蓋整個底座（m-3）
    @Test func headRegionIsASquareAroundThePivotCoveringTheBase() throws {
        for skin in try skins() {
            let region = SkinPreviewGeometry.headRegion(for: skin)
            let pivot = skin.spec.kinematics.pivot
            let base = CGRect(origin: skin.spec.baseOrigin, size: skin.spec.base.size)
            #expect(abs(region.width - region.height) < 1e-9)
            #expect(abs(region.midX - pivot.x) < 1e-9 && abs(region.midY - pivot.y) < 1e-9)
            #expect(region.minX <= base.minX + 1e-9 && region.maxX >= base.maxX - 1e-9, "\(skin.spec.id)")
        }
    }

    /// 增補 B（Codex r2-4）：head 裁切涵蓋三層固定底座的左右範圍；中層或上層比下層寬時也要涵蓋
    @Test func headRegionCoversEveryFixedLayer() throws {
        let sArm = try SpriteSkinFixture.bundled(.sArm1200)
        let spec = sArm.spec
        let wide = ArtworkFrame(size: CGSize(width: spec.base.size.width * 3, height: 10), localPivot: CGPoint(x: spec.base.size.width * 1.5, y: 5))
        for skin in [spec.replacing(baseMiddle: wide), spec.replacing(baseOverlay: wide)] {
            let resolved = ResolvedTurntableSkin(spec: skin, startDegrees: sArm.startDegrees, sweepDegrees: sArm.sweepDegrees)
            let region = SkinPreviewGeometry.headRegion(for: resolved)
            let layer = CGRect(origin: skin.origin(of: wide), size: wide.size)
            #expect(region.minX <= layer.minX + 1e-9 && region.maxX >= layer.maxX - 1e-9)
        }
    }

    /// 兩層 golden：現有三款的 overlay 都在下層左右範圍內 → head 裁切與只看下層時逐值相同
    @Test func headRegionOfExistingSkinsIsUnchanged() throws {
        for skin in try skins().prefix(3) {
            let pivot = skin.spec.kinematics.pivot
            let base = CGRect(origin: skin.spec.baseOrigin, size: skin.spec.base.size)
            let half = max(pivot.x - base.minX, base.maxX - pivot.x)
            #expect(SkinPreviewGeometry.headRegion(for: skin) == CGRect(x: pivot.x - half, y: pivot.y - half, width: half * 2, height: half * 2),
                    "\(skin.spec.id)")
        }
    }

    @Test func spriteFileNamesFollowTheRestFrame() throws {
        let skin = try SpriteSkinFixture.bundled(.sArm1200)
        let rest = SkinPreviewGeometry.restFrame(for: skin)
        #expect(BundleSkinPreviewSource.fileName(.arm, skin: skin) == SpriteSkinAssets.armFile(rest))
        #expect(BundleSkinPreviewSource.fileName(.armShadow, skin: skin) == SpriteSkinAssets.shadowFile(rest))
        #expect(BundleSkinPreviewSource.fileName(.base, skin: skin) == SpriteSkinAssets.baseFile)
        #expect(BundleSkinPreviewSource.fileName(.baseOverlay, skin: skin) == SpriteSkinAssets.overlayFile)
        #expect(BundleSkinPreviewSource.fileName(.baseMiddle, skin: try SpriteSkinFixture.bundled(.technicsSL1200G)) == SpriteSkinAssets.middleFile)
        #expect(BundleSkinPreviewSource.fileName(.arm, skin: .classic) == nil, "classic 不走 bundle")
    }
}

// MARK: 合成

struct SkinPreviewComposerTests {
    private let size = CGSize(width: 120, height: 400)

    private func compose(_ skin: ResolvedTurntableSkin, crop: SkinPreviewCrop = .wholeArm, size: CGSize? = nil) throws -> CGImage {
        let layers = SkinPreviewGeometry.layers(for: skin).map { ($0, stubImage($0.kind)) }
        return try #require(SkinPreviewComposer.compose(layers, skin: skin, crop: crop, pixelSize: size ?? self.size))
    }

    @Test func outputHasTheRequestedPixelSize() throws {
        for skin in try skins() {
            let image = try compose(skin)
            #expect(image.width == 120 && image.height == 400)
            let head = try compose(skin, crop: .head, size: CGSize(width: 64, height: 64))
            #expect(head.width == 64 && head.height == 64)
        }
    }

    /// 兩層重疊處＝上層的顏色；只屬一層處＝該層顏色（實心替身圖：可見範圍＝各層聯集，置中等比縮放）
    @Test func overlappingLayersShowTheUpperOne() throws {
        for skin in try skins() {
            let layers = SkinPreviewGeometry.layers(for: skin)
            let union = layers.map(\.rect).reduce(CGRect.null) { $0.union($1) }
            let scale = min(size.width / union.width, size.height / union.height)
            let offset = CGPoint(x: (size.width - union.width * scale) / 2, y: (size.height - union.height * scale) / 2)
            let image = try compose(skin)
            func check(_ point: CGPoint, _ kind: SkinPreviewLayer.Kind) {
                let x = Int(offset.x + (point.x - union.minX) * scale), y = Int(offset.y + (point.y - union.minY) * scale)
                #expect(pixel(image, x, y) == expected(kind), "\(skin.spec.id) \(kind) at \(point)")
            }
            // 每兩層的重疊中心（以及每層自己的中心）：期望＝包含該點的最上層；離任何層邊 3 pt 以內的點略過（縮放取樣混色）
            let margin = 3 / scale
            var points = layers.map { CGPoint(x: $0.rect.midX, y: $0.rect.midY) }
            for (i, lower) in layers.enumerated() {
                for upper in layers[(i + 1)...] {
                    let both = lower.rect.intersection(upper.rect)
                    if !both.isNull && both.width > 2 * margin && both.height > 2 * margin { points.append(CGPoint(x: both.midX, y: both.midY)) }
                }
            }
            var checked = 0
            for point in points {
                let nearEdge = layers.contains { $0.rect.insetBy(dx: -margin, dy: -margin).contains(point) && !$0.rect.insetBy(dx: margin, dy: margin).contains(point) }
                guard !nearEdge, let top = layers.last(where: { $0.rect.contains(point) }) else { continue }
                check(point, top.kind)
                checked += 1
            }
            #expect(checked >= 2, "\(skin.spec.id) 至少驗到兩點")
        }
    }

    /// 可見範圍裁切（m-2）：四周透明的圖，只算看得見的部分
    @Test func transparentMarginsAreCroppedAway() throws {
        let context = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.fill(CGRect(x: 10, y: 5, width: 20, height: 30))   // CG 左下原點：左上原點的 y＝40−5−30＝5
        let image = try #require(context.makeImage())
        #expect(SkinPreviewComposer.alphaBounds(image) == CGRect(x: 10, y: 5, width: 20, height: 30))
        let empty = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        #expect(SkinPreviewComposer.alphaBounds(empty) == nil)
    }
}

// MARK: renderer

/// 可控的圖源：記錄請求；`gate` 開著時每個請求等測試放行；`failing` 的層回 nil
private actor StubPreviewSource: SkinPreviewImageSource {
    private(set) var requests: [String] = []
    var failing: Set<SkinPreviewLayer.Kind> = []
    var gated = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func setFailing(_ kinds: Set<SkinPreviewLayer.Kind>) { failing = kinds }
    func setGated(_ value: Bool) { gated = value }
    func openGate() { waiting.forEach { $0.resume() }; waiting = [] }
    var waitingCount: Int { waiting.count }

    func image(_ kind: SkinPreviewLayer.Kind, skin: ResolvedTurntableSkin, maxPixelSize: Int) async -> CGImage? {
        requests.append("\(skin.spec.id)/\(kind)/\(maxPixelSize)")
        if gated { await withCheckedContinuation { waiting.append($0) } }
        return failing.contains(kind) ? nil : stubImage(kind)
    }
}

@MainActor
struct SkinPreviewRendererTests {
    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<20_000 where !(await condition()) { await Task.yield() }
    }

    private let small = CGSize(width: 60, height: 200), large = CGSize(width: 120, height: 400)

    @Test func sameKeyRequestsShareOneDecode() async throws {
        let source = StubPreviewSource()
        await source.setGated(true)
        let renderer = SkinPreviewRenderer(source: source)
        let skin = try SpriteSkinFixture.bundled(.sArm1200)
        async let first: Void = renderer.load(skin, crop: .wholeArm, pixelSize: small)
        async let second: Void = renderer.load(skin, crop: .wholeArm, pixelSize: small)
        await waitUntil { await source.waitingCount == 4 }
        await source.openGate()
        _ = await (first, second)
        #expect(await source.requests.count == 4, "四層各一次")
        #expect(renderer.image(for: skin, crop: .wholeArm, pixelSize: small)?.width == 60)
    }

    @Test func differentPixelSizesAreCachedSeparately() async throws {
        let source = StubPreviewSource()
        let renderer = SkinPreviewRenderer(source: source)
        await renderer.load(.classic, crop: .wholeArm, pixelSize: small)
        await renderer.load(.classic, crop: .wholeArm, pixelSize: large)
        #expect(await source.requests.count == 4, "classic 兩層 × 兩種尺寸")
        #expect(renderer.image(for: .classic, crop: .wholeArm, pixelSize: small)?.width == 60)
        #expect(renderer.image(for: .classic, crop: .wholeArm, pixelSize: large)?.width == 120)
    }

    /// 換尺寸還沒好：先給同 id 同裁法最近的一張（m-4）
    @Test func aNewSizeFallsBackToTheLatestImageOfTheSameSkin() async throws {
        let renderer = SkinPreviewRenderer(source: StubPreviewSource())
        await renderer.load(.classic, crop: .wholeArm, pixelSize: small)
        #expect(renderer.image(for: .classic, crop: .wholeArm, pixelSize: large)?.width == 60)
        #expect(renderer.image(for: .classic, crop: .head, pixelSize: large) == nil, "裁法不同不混用")
    }

    @Test func leastRecentlyUsedImagesAreEvicted() async throws {
        let renderer = SkinPreviewRenderer(source: StubPreviewSource(), capacity: 2)
        let sizes = [CGSize(width: 10, height: 30), CGSize(width: 20, height: 60), CGSize(width: 30, height: 90)]
        for size in sizes { await renderer.load(.classic, crop: .wholeArm, pixelSize: size) }
        #expect(renderer.images.count == 2)
        #expect(renderer.images[SkinPreviewRenderer.Key(.classic, .wholeArm, sizes[0])] == nil)
        #expect(renderer.images[SkinPreviewRenderer.Key(.classic, .wholeArm, sizes[2])] != nil)
    }

    /// 失敗＝後備圖形；同 id 之後任何尺寸都不再呼叫圖源、只記一次（r2-2）
    @Test func failureIsRememberedPerSkinAndReportedOnce() async throws {
        let source = StubPreviewSource()
        await source.setFailing([.arm])
        var reports: [String] = []
        let renderer = SkinPreviewRenderer(source: source, report: { reports.append($0) })
        await renderer.load(.classic, crop: .wholeArm, pixelSize: small)
        #expect(renderer.image(for: .classic, crop: .wholeArm, pixelSize: small) == nil && renderer.isUnavailable("classic"))
        let count = await source.requests.count
        await renderer.load(.classic, crop: .wholeArm, pixelSize: large)
        await renderer.load(.classic, crop: .head, pixelSize: small)
        #expect(await source.requests.count == count, "不重試")
        #expect(reports == ["classic"])
    }

    /// 呼叫端取消（格子卸載）不算失敗：解碼照樣完成並進快取（r3-2）
    @Test func cancellingTheCallerIsNotAFailure() async throws {
        let source = StubPreviewSource()
        await source.setGated(true)
        let renderer = SkinPreviewRenderer(source: source)
        let caller = Task { await renderer.load(.classic, crop: .wholeArm, pixelSize: small) }
        await waitUntil { await source.waitingCount == 2 }
        caller.cancel()
        await source.openGate()
        await waitUntil { renderer.images[SkinPreviewRenderer.Key(.classic, .wholeArm, small)] != nil }
        #expect(!renderer.isUnavailable("classic"))
        #expect(renderer.images[SkinPreviewRenderer.Key(.classic, .wholeArm, small)] != nil)
    }
}
