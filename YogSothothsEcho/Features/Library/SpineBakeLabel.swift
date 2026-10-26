import CoreGraphics
import CoreText
import Foundation

/// 書脊字（同原 `SpineFace.label` 的 LP 書脊排版，由下往上讀）：下端細線＋藝人小字、中間專輯名粗體大寫、
/// 上端廠牌方塊＋型號＋細線。以 CoreText 畫進烘焙點陣（不鏡像）；數值以小樣書脊厚 22.92 px 為 1 換算
enum SpineBakeLabel {
    struct Ink {
        let red, green, blue, alpha: CGFloat
    }

    static func ink(light: Bool) -> Ink {
        light ? Ink(red: 24 / 255, green: 22 / 255, blue: 20 / 255, alpha: 0.9) : Ink(red: 1, green: 1, blue: 1, alpha: 0.95)
    }

    private struct Run {
        let line: CTLine
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
    }

    private static func run(_ text: String, font name: String, size: CGFloat, tracking: CGFloat, ink: Ink, opacity: CGFloat,
                            maxWidth: CGFloat? = nil) -> Run {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let color = CGColor(srgbRed: ink.red, green: ink.green, blue: ink.blue, alpha: ink.alpha * opacity)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
        ]
        var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        if let maxWidth, CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            line = CTLineCreateTruncatedLine(line, Double(max(0, maxWidth)), .end, ellipsis) ?? line
        }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        return Run(line: line, width: width, ascent: ascent, descent: descent)
    }

    static func draw(_ canvas: SpineBake.Canvas, key: SpineBake.Key, light: Bool) {
        let ctx = canvas.ctx, thickness = canvas.size.width, cover = canvas.size.height
        let px = thickness / (SpineCarouselMetrics.referenceCover * SpineCarouselMetrics.spineToCover)
        let ink = ink(light: light)
        ctx.saveGState()
        // 字的框＝cover × thickness，以書脊中心逆時針轉 90°（同 rotationEffect(-90)）
        ctx.translateBy(x: thickness / 2, y: cover / 2)
        ctx.rotate(by: -.pi / 2)
        ctx.translateBy(x: -cover / 2, y: -thickness / 2)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        // 陰影在字的框內往下 1 pt（深底）；轉 90° 後在裝置座標是 +x
        if light {
            ctx.setShadow(offset: .zero, blur: 1.5 * px * key.scale, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55))
        } else {
            ctx.setShadow(offset: CGSize(width: key.scale, height: 0), blur: key.scale, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
        }
        let inner = cover - 20 * px, midY = thickness / 2
        let title = run(key.title.uppercased(), font: "AvenirNextCondensed-Bold", size: 13.5 * px, tracking: 1.6 * px, ink: ink, opacity: 1,
                        maxWidth: inner - 28 * px)
        let titleBox = min(inner, title.width + 28 * px)
        let sideWidth = (inner - titleBox) / 2
        let left = 10 * px, right = cover - 10 * px
        // 下端（框的左）：細線＋藝人
        drawRule(ctx, x: left, midY: midY, px: px, ink: ink)
        let artistStart = left + 1.5 * px + 9 * px
        let artist = run(key.artist.uppercased(), font: "AvenirNextCondensed-Medium", size: 10.5 * px, tracking: 1.4 * px, ink: ink,
                         opacity: 0.8, maxWidth: max(0, sideWidth - 1.5 * px - 9 * px))
        drawLine(ctx, artist, x: artistStart, midY: midY)
        // 中間：專輯名
        drawLine(ctx, title, x: left + sideWidth + (titleBox - title.width) / 2, midY: midY)
        // 上端（框的右）：細線、型號、廠牌方塊（由右往左排）
        let ruleX = right - 1.5 * px
        drawRule(ctx, x: ruleX, midY: midY, px: px, ink: ink)
        let catalog = run(SpineWrap.catalogNumber(albumID: key.albumID), font: "AvenirNextCondensed-DemiBold", size: 9.5 * px,
                          tracking: 0.9 * px, ink: ink, opacity: 0.72)
        let catalogX = ruleX - 7 * px - catalog.width
        drawLine(ctx, catalog, x: catalogX, midY: midY)
        drawBadge(ctx, x: catalogX - 7 * px - 10 * px, midY: midY, px: px, ink: ink, light: light)
        ctx.restoreGState()
    }

    private static func drawLine(_ ctx: CGContext, _ run: Run, x: CGFloat, midY: CGFloat) {
        // y 往下：基線＝中線＋(ascent − descent)/2
        ctx.textPosition = CGPoint(x: x, y: midY + (run.ascent - run.descent) / 2)
        CTLineDraw(run.line, ctx)
    }

    private static func drawRule(_ ctx: CGContext, x: CGFloat, midY: CGFloat, px: CGFloat, ink: Ink) {
        ctx.setFillColor(red: ink.red, green: ink.green, blue: ink.blue, alpha: ink.alpha * 0.55)
        ctx.fill(CGRect(x: x, y: midY - 5.5 * px, width: 1.5 * px, height: 11 * px))
    }

    private static func drawBadge(_ ctx: CGContext, x: CGFloat, midY: CGFloat, px: CGFloat, ink: Ink, light: Bool) {
        let rect = CGRect(x: x, y: midY - 5 * px, width: 10 * px, height: 10 * px)
        ctx.setFillColor(red: ink.red, green: ink.green, blue: ink.blue, alpha: ink.alpha)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 1.5 * px, cornerHeight: 1.5 * px, transform: nil))
        ctx.fillPath()
        let letterInk = light ? Ink(red: 1, green: 1, blue: 1, alpha: 1) : Ink(red: 0, green: 0, blue: 0, alpha: 0.85)
        let letter = run("Y", font: "HelveticaNeue-Bold", size: 7 * px, tracking: 0, ink: letterInk, opacity: 1)
        drawLine(ctx, letter, x: rect.midX - letter.width / 2, midY: midY)
    }
}
