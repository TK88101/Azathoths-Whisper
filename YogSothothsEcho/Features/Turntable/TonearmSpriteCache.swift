import CoreGraphics
import Foundation
import ImageIO
import Observation

/// 序列圖皮膚的解碼快取（CR-034 §4.4、附錄 F）：由 TurntableViewModel 持有（View 只讀）。皮膚啟用時依畫面像素縮圖解碼兩張底座與
/// 每一度的唱臂＋投影；**唱臂與投影兩張都解完才一次發布成一對**（不會出現新唱臂配舊投影）。解碼順序（E，DEBUG 可關）：
/// 底座 → 「靜止幀 … 目前進度對應幀＋3」（落臂與抬臂都走這段，急件）→ 其餘（低優先權）；每發布一對就重讀焦點（播放中角度在變）。
/// 未發布的幀以最近已發布的一對頂上。換皮膚／換縮放／disableSkin／斷線移出唱機＝`release()`：世代遞增、晚到的結果丟棄。
/// 解碼失敗只回報（皮膚 id＋世代），退回 classic 由擁有者決定（R2-2）
@MainActor
@Observable
final class TonearmSpriteCache {
    struct Request: Sendable, Equatable {
        let folder: String
        let name: String
        /// 縮圖長邊像素
        let maxPixelSize: Int
    }

    typealias Decode = @Sendable (Request) async -> CGImage?

    /// 同一度的唱臂與投影
    struct FramePair {
        let arm: CGImage
        let shadow: CGImage
    }

    /// 要畫的一對：`frame`＝實際拿到的幀，`exact`＝是否就是要求的那一幀
    struct FrameLookup {
        let pair: FramePair
        let frame: Int
        let exact: Bool
    }

    /// 焦點範圍：目標幀之後再多解幾幀（播放中角度往前走）
    nonisolated static let focusLookahead = 3

    private(set) var pairs: [Int: FramePair] = [:]
    private(set) var base: CGImage?
    /// 底座中層（增補 B；沒有中層的皮膚恆為 nil）
    private(set) var middle: CGImage?
    private(set) var overlay: CGImage?
    private(set) var isComplete = false
    @ObservationIgnored private(set) var generation = 0
    /// 解碼失敗的回報（皮膚 id、當時世代）；擁有者在 init 後接上
    @ObservationIgnored var onFailure: (String, Int) -> Void
    /// 落臂／抬臂會經過的目標幀（目前進度對應的幀；未知＝nil）；擁有者接上
    @ObservationIgnored var focusTarget: () -> Int? = { nil }
    /// E 優先序（DEBUG 可關以對照舊順序）
    @ObservationIgnored var prioritized: () -> Bool = { SpriteStrategy.prioritized }
    @ObservationIgnored private let decode: Decode
    @ObservationIgnored private var loaded: (id: String, pixelScale: CGFloat)?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(decode: @escaping Decode = { SpriteDecoder.decode($0) }, onFailure: @escaping (String, Int) -> Void) {
        self.decode = decode
        self.onFailure = onFailure
    }

    /// 最近的整數度幀，夾在 0…count−1（素材每幀是 rest 姿態轉 n 度後再轉回來畫的）
    nonisolated static func frameIndex(angle: Double, rest: Double, count: Int) -> Int {
        min(max(Int((angle - rest).rounded()), 0), max(count - 1, 0))
    }

    /// 下一個要解的幀（純函式）：E 開＝「0 … 目標＋lookahead」由小到大為急件，之後其餘由小到大；E 關＝0…count−1 依序、皆非急件
    nonisolated static func nextFrame(done: Set<Int>, target: Int?, count: Int, prioritized: Bool) -> (frame: Int, urgent: Bool)? {
        let remaining = (0..<count).first { !done.contains($0) }
        guard prioritized else { return remaining.map { ($0, false) } }
        let focusEnd = target.map { min($0 + focusLookahead, count - 1) } ?? 0
        if let urgent = (0...max(focusEnd, 0)).first(where: { !done.contains($0) && $0 < count }) { return (urgent, true) }
        return remaining.map { ($0, false) }
    }

    /// `pixelScale`＝畫面每 u 的像素數（版面縮放 × displayScale）；不放大超過素材本身
    func load(_ skin: ResolvedTurntableSkin, pixelScale: CGFloat) {
        guard let sprite = skin.spec.spriteLayers else { return release() }
        let scale = min(pixelScale, sprite.assets.pixelsPerUnit)
        if let loaded, loaded.id == skin.spec.id, loaded.pixelScale == scale { return }
        release()
        loaded = (skin.spec.id, scale)
        let token = generation, id = skin.spec.id, decode = self.decode
        let requests = Self.Requests(skin.spec, sprite, scale: scale)
        task = Task { [weak self] in
            for (layer, request) in requests.stills {
                let image = await Self.decoded(request, urgent: true, decode)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                guard let image else { return self.onFailure(id, token) }
                switch layer {
                case .base: self.base = image
                case .middle: self.middle = image
                case .overlay: self.overlay = image
                }
            }
            var done = Set<Int>()
            while let self, self.generation == token, !Task.isCancelled,
                  let next = Self.nextFrame(done: done, target: self.focusTarget(), count: SpriteSkinAssets.frameCount,
                                            prioritized: self.prioritized()) {
                self.traceDecodeStart(next.frame, urgent: next.urgent)
                let armRequest = requests.arm(next.frame), shadowRequest = requests.shadow(next.frame)
                async let arm = Self.decoded(armRequest, urgent: next.urgent, decode)
                async let shadow = Self.decoded(shadowRequest, urgent: next.urgent, decode)
                let (armImage, shadowImage) = await (arm, shadow)
                guard self.generation == token, !Task.isCancelled else { return }
                guard let armImage, let shadowImage else { return self.onFailure(id, token) }
                self.pairs[next.frame] = FramePair(arm: armImage, shadow: shadowImage)
                self.tracePublished(next.frame)
                done.insert(next.frame)
            }
            guard let self, self.generation == token else { return }
            self.isComplete = true
        }
    }

    func release() {
        generation += 1
        task?.cancel()
        task = nil
        loaded = nil
        pairs = [:]
        base = nil
        middle = nil
        overlay = nil
        isComplete = false
        #if DEBUG
        SpriteTrace.current?.released(generation: generation)
        #endif
    }

    /// 這個角度要畫的一對（沒有的話用最近已發布的；一對都沒有＝nil）
    func frames(forAngle angle: Double, skin: ResolvedTurntableSkin) -> FrameLookup? {
        guard skin.spec.spriteLayers != nil else { return nil }
        let index = Self.frameIndex(angle: angle, rest: skin.restDegrees, count: SpriteSkinAssets.frameCount)
        if let exact = pairs[index] { return FrameLookup(pair: exact, frame: index, exact: true) }
        return pairs.min { abs($0.key - index) < abs($1.key - index) }.map { FrameLookup(pair: $0.value, frame: $0.key, exact: false) }
    }

    /// 常駐的解碼點陣位元組數（T7 記憶體閘門與 DEBUG 量測）
    var residentBytes: Int {
        (pairs.values.flatMap { [$0.arm, $0.shadow] } + [base, middle, overlay].compactMap { $0 }).reduce(0) { $0 + $1.byteCost }
    }

    /// 焦點內（急件）用 userInitiated，其餘 utility，避免長串背景解碼搶走動畫的 CPU
    nonisolated private static func decoded(_ request: Request, urgent: Bool, _ decode: @escaping Decode) async -> CGImage? {
        await Task.detached(priority: urgent ? .userInitiated : .utility) { await decode(request) }.value
    }

    private func traceDecodeStart(_ frame: Int, urgent: Bool) {
        #if DEBUG
        SpriteTrace.current?.decodeStarted(frame: frame, generation: generation, urgent: urgent)
        #endif
    }

    private func tracePublished(_ frame: Int) {
        #if DEBUG
        SpriteTrace.current?.decodePublished(frame: frame, generation: generation)
        #endif
    }

    /// 各層的解碼請求（縮圖長邊＝畫框長邊 × 畫面每 u 像素數）
    private struct Requests {
        enum Still { case base, middle, overlay }

        /// 靜態底座層，依解碼順序：下層 →（中層）→ 上層
        let stills: [(Still, Request)]
        let arm: (Int) -> Request, shadow: (Int) -> Request

        init(_ spec: TurntableSkin, _ sprite: TurntableSkin.SpriteLayers, scale: CGFloat) {
            let folder = sprite.assets.folder
            func request(_ name: String, _ frame: ArtworkFrame) -> Request {
                Request(folder: folder, name: name, maxPixelSize: Int((max(frame.size.width, frame.size.height) * scale).rounded(.up)))
            }
            let middle = sprite.middle.map { [(Still.middle, request(SpriteSkinAssets.middleFile, $0))] } ?? []
            stills = [(.base, request(SpriteSkinAssets.baseFile, spec.base))] + middle
                + [(.overlay, request(SpriteSkinAssets.overlayFile, sprite.overlay))]
            let armFrame = spec.arm, shadowFrame = sprite.shadow
            arm = { request(SpriteSkinAssets.armFile($0), armFrame) }
            shadow = { request(SpriteSkinAssets.shadowFile($0), shadowFrame) }
        }
    }
}

/// ImageIO 縮圖解碼（背景執行緒呼叫）
enum SpriteDecoder {
    static func decode(_ request: TonearmSpriteCache.Request) -> CGImage? {
        let file = request.name as NSString
        guard let url = Bundle.main.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: request.folder),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: request.maxPixelSize,
                                        kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
