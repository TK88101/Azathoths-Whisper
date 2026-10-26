import CoreGraphics
import RemoteProtocol
import UIKit

/// 書脊整面烘焙（s6-61-g-perf-wear.md §5.1）：包覆條、弧度、紙纖維、折邊明暗、邊緣磨白、覆膜、泛白磨損、字，
/// 最後被不規則輪廓裁出剪影——在任意執行緒畫成一張螢幕倍率的點陣，畫面只貼圖。
/// 實測根因（n03-b Time Profiler）：主執行緒的書脊量字排版、邊條亮度與多層合成是新盒子湧入時的長幀來源
enum SpineBake {
    /// 改了任何繪製演算法就加 1（舊快取不得混用）
    static let rendererVersion = 1

    /// 實際的像素來源：同 token 由 160 px 縮圖升為 1024 px 也要換鍵（token＋圖素寬）
    enum SourceRevision: Hashable, Sendable {
        case placeholder
        case artwork(token: String, pixelWidth: Int)
    }

    /// 影響像素的全部輸入
    struct Key: Hashable, Sendable {
        let albumID: String
        let title: String
        let artist: String
        let source: SourceRevision
        let side: CarouselSide
        let thickness: CGFloat
        let cover: CGFloat
        let scale: CGFloat
        var rendererVersion = SpineBake.rendererVersion
    }

    /// 主執行緒上萃取好的可傳送輸入；renderer 不碰 UIKit 與 view state
    struct Input: Sendable {
        let key: Key
        /// 封面（方向已為 up）；折邊條在烘焙裡依 side 取（`SpineWrap.edgeStrip`）
        let cover: CGImage?
        /// 沒有封面時的底色（`LibraryPresentation.placeholderColor`）
        let placeholder: RGBColor
    }

    /// 主執行緒上組輸入：只取 `cgImage`（方向非 up 才重繪，少見）；裁條、算亮度、畫圖都在烘焙裡
    @MainActor
    static func input(album: AlbumSummary, image: UIImage?, side: CarouselSide, thickness: CGFloat, cover: CGFloat,
                      scale: CGFloat) -> Input {
        let cg = image.flatMap(CoverCrop.normalized)
        let source: SourceRevision = cg.map { .artwork(token: album.artworkToken ?? "", pixelWidth: $0.width) } ?? .placeholder
        let key = Key(albumID: album.id, title: album.title, artist: album.artist, source: source, side: side, thickness: thickness,
                      cover: cover, scale: scale)
        return Input(key: key, cover: cg, placeholder: LibraryPresentation.placeholderRGB(for: album.id))
    }

    struct Canvas {
        let ctx: CGContext
        let size: CGSize
    }

    static func render(_ input: Input) -> CGImage? {
        let key = input.key
        let width = Int((key.thickness * key.scale).rounded()), height = Int((key.cover * key.scale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 座標＝面的本地 pt、左上為原點、y 往下
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: key.scale, y: key.scale)
        ctx.interpolationQuality = .medium
        let canvas = Canvas(ctx: ctx, size: CGSize(width: key.thickness, height: key.cover))
        let shape = SpineWear.shape(albumID: key.albumID)
        let strip = input.cover.flatMap { SpineWrap.edgeStrip(of: $0, side: key.side) }
        let light = isLight(strip: strip, placeholder: input.placeholder)

        // 剪影要留在整張圖的 state 裡：不能包在 withSide 的 save／restore 內（restore 會連裁切一起丟掉；simcodex R3 P0）
        mirrorIfRight(canvas, key.side)
        SpineBakeOutline.clip(canvas, albumID: key.albumID, shape: shape)
        mirrorIfRight(canvas, key.side)
        drawWrap(canvas, strip: strip, placeholder: input.placeholder)
        withSide(canvas, key.side) {
            drawLayers(canvas, light: light)
            SpineBakeOutline.drawWear(canvas, albumID: key.albumID, shape: shape)
        }
        SpineBakeLabel.draw(canvas, key: key, light: light)
        return ctx.makeImage()
    }

    /// 字色依邊條亮度（同 `SpineWrap.isLight`）；在烘焙裡算，不佔主執行緒
    static func isLight(strip: CGImage?, placeholder: RGBColor) -> Bool {
        SpineWrap.isLight(luminance: strip.map(SpineWrap.averageLuminance) ?? placeholder.luminance)
    }

    /// 疊層以左側盒方向畫（折邊在 trailing）；右側盒水平鏡像（字不在此內）
    static func withSide(_ canvas: Canvas, _ side: CarouselSide, _ body: () -> Void) {
        guard side == .right else { return body() }
        canvas.ctx.saveGState()
        mirrorIfRight(canvas, side)
        body()
        canvas.ctx.restoreGState()
    }

    /// 水平鏡像（自身即反函數：做兩次＝復原），不動 graphics state 的其他部分
    static func mirrorIfRight(_ canvas: Canvas, _ side: CarouselSide) {
        guard side == .right else { return }
        canvas.ctx.translateBy(x: canvas.size.width, y: 0)
        canvas.ctx.scaleBy(x: -1, y: 1)
    }

    /// 在 y 往下的座標裡把點陣正著畫進 rect
    static func drawUpright(_ ctx: CGContext, _ image: CGImage, in rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// 封面最靠折邊的那一條拉伸到書脊寬並左右翻轉（同原 `SpineFace.wrap`）；沒有封面＝佔位色
    private static func drawWrap(_ canvas: Canvas, strip: CGImage?, placeholder c: RGBColor) {
        let ctx = canvas.ctx, rect = CGRect(origin: .zero, size: canvas.size)
        guard let strip else {
            ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
            ctx.fill(rect)
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: rect.width, y: 0)
        ctx.scaleBy(x: -1, y: 1)
        drawUpright(ctx, strip, in: rect)
        ctx.restoreGState()
    }

    /// 同原 `SpineFace.layers`（不含磨損）：弧度、紙纖維、背側與折邊明暗、邊緣磨白、覆膜兩道
    private static func drawLayers(_ canvas: Canvas, light: Bool) {
        let w = canvas.size.width
        let px = w / (SpineCarouselMetrics.referenceCover * SpineCarouselMetrics.spineToCover)
        horizontal(canvas, [.black(0.22, 0), .white(light ? 0.10 : 0.06, 0.42), .white(0, 0.62), .black(0, 0.62), .black(0.16, 1)])
        TextureDrawing.tile(canvas.ctx, PaperFiber.tileImage, in: CGRect(origin: .zero, size: canvas.size))
        fold(canvas, SpineFoldShading.spineBack(u: px), fromLeading: true)
        fold(canvas, SpineFoldShading.spineFold(u: px), fromLeading: false)
        TextureDrawing.edgeBands(canvas.ctx, in: CGRect(origin: .zero, size: canvas.size), width: 2.5 * px, allSides: false, opacity: 0.6)
        horizontal(canvas, [.white(0, 0.22), .white(0.20, 0.36), .white(0.05, 0.46), .white(0, 0.54)])
        vertical(canvas, [.white(0.12, 0), .white(0, 0.30), .black(0, 0.70), .black(0.14, 1)])
    }

    struct Stop {
        let gray: Double, alpha: Double, location: CGFloat
        static func white(_ alpha: Double, _ location: CGFloat) -> Stop { Stop(gray: 1, alpha: alpha, location: location) }
        static func black(_ alpha: Double, _ location: CGFloat) -> Stop { Stop(gray: 0, alpha: alpha, location: location) }
    }

    static func gradient(_ canvas: Canvas, _ stops: [Stop], from start: CGPoint, to end: CGPoint) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let components = stops.flatMap { [$0.gray, $0.gray, $0.gray, $0.alpha].map { CGFloat($0) } }
        let locations = stops.map(\.location)
        guard let g = CGGradient(colorSpace: space, colorComponents: components, locations: locations, count: stops.count) else { return }
        canvas.ctx.saveGState()
        canvas.ctx.clip(to: CGRect(origin: .zero, size: canvas.size))
        canvas.ctx.drawLinearGradient(g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        canvas.ctx.restoreGState()
    }

    private static func horizontal(_ canvas: Canvas, _ stops: [Stop]) {
        gradient(canvas, stops, from: .zero, to: CGPoint(x: canvas.size.width, y: 0))
    }

    private static func vertical(_ canvas: Canvas, _ stops: [Stop]) {
        gradient(canvas, stops, from: .zero, to: CGPoint(x: 0, y: canvas.size.height))
    }

    /// 折邊明暗：停點以距該邊的 pt 表示（`SpineFoldShading`）
    private static func fold(_ canvas: Canvas, _ stops: [FoldStop], fromLeading: Bool) {
        let w = canvas.size.width
        let mapped = zip(stops, SpineFoldShading.locations(stops, length: w)).map { stop, location in
            Stop(gray: stop.white ? 1 : 0, alpha: stop.opacity, location: location)
        }
        let start = CGPoint(x: fromLeading ? 0 : w, y: 0), end = CGPoint(x: fromLeading ? w : 0, y: 0)
        gradient(canvas, mapped, from: start, to: end)
    }
}
