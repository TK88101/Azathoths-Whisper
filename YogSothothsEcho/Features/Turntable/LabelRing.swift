import SwiftUI

/// UPC-A 條碼（標籤外圈的彩蛋；#5-1 使用者指定）：11 位數字＋程式算出的檢查碼 → 95 個模組（true＝黑條）
enum UPCABarcode {
    private static let left = ["0001101", "0011001", "0010011", "0111101", "0100011",
                               "0110001", "0101111", "0111011", "0110111", "0001011"]

    static func checkDigit(_ digits: String) -> Int? {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == 11, digits.count == 11 else { return nil }
        let sum = values.enumerated().reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
        return (10 - sum % 10) % 10
    }

    static func modules(_ digits: String) -> [Bool]? {
        guard let check = checkDigit(digits) else { return nil }
        let all = digits.compactMap(\.wholeNumberValue) + [check]
        let leftHalf = all.prefix(6).map { left[$0] }.joined()
        // 右半＝左碼取反
        let rightHalf = all.suffix(6).map { String(left[$0].map { $0 == "0" ? "1" : "0" }) }.joined()
        return ("101" + leftHalf + "01010" + rightHalf + "101").map { $0 == "1" }
    }
}

/// 標籤版面（sprint-5-detail.md §4.2b v1.4；#5-1 G3 定案 Label Close-up；v1.6 拿掉條碼數字、條紋加長）：以標籤直徑 L 為單位、標籤圓心為原點、y 向下
enum LabelLayout {
    static let ringText = "DESIGNED BY YOG-SOTHOTH'S ECHO IN FUKUOKA · MADE IN JAPAN"
    static let wordmark = "YOG-SOTHOTH'S ECHO"

    static let ringRadius: CGFloat = 0.437
    static let ringFont: CGFloat = 0.026
    /// 環狀字相鄰間隔（弧度；固定，不依字寬）
    static let ringStep = 0.0915
    static let rimDiameter: CGFloat = 0.95

    /// 歌名＋歌手整塊的下緣（中心孔上方）
    static let titleBlockBottom: CGFloat = -0.06
    static let titleFont: CGFloat = 0.068
    static let artistFont: CGFloat = 0.045
    static let textWidth: CGFloat = 0.6

    static let wordmarkTop: CGFloat = 0.16
    static let wordmarkFont: CGFloat = 0.03
    static let wordmarkTracking: CGFloat = 0.004
    static let barcodeTop: CGFloat = 0.205
    /// 不畫數字（#5-1 第 2 項）：條紋加長到原本「條碼＋數字」的總長，護條底緣＝原數字底緣 0.3238L
    static let barcodeHeight: CGFloat = 0.106
    static let barcodeWidth: CGFloat = 0.32
    /// 首、中、尾護條比資料條長
    static let guardExtension: CGFloat = 1.12

    struct Glyph: Equatable {
        let position: CGPoint
        /// 順時針弧度（字頭朝外）
        let rotation: Double
    }

    /// 每字中心角（弧度；0＝12 點、順時針為正），整段以 12 點為中心
    static func ringAngles(count: Int) -> [Double] {
        let start = -ringStep * Double(count - 1) / 2
        return (0..<count).map { start + Double($0) * ringStep }
    }

    static func ringGlyph(angle: Double, center: CGPoint, diameter: CGFloat) -> Glyph {
        let radius = ringRadius * diameter
        return Glyph(position: CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle))),
                     rotation: angle)
    }

    /// 條碼每段黑條（相對標籤圓心）：95 個模組平均分在條碼寬內、水平置中；連續的黑模組合成一條
    static func barcodeBars(_ modules: [Bool], diameter: CGFloat) -> [CGRect] {
        let width = barcodeWidth * diameter / CGFloat(modules.count)
        let left = -barcodeWidth * diameter / 2, top = barcodeTop * diameter, height = barcodeHeight * diameter
        var bars: [CGRect] = []
        var start: Int?
        for index in 0...modules.count {
            let black = index < modules.count && modules[index]
            if black, start == nil { start = index }
            guard !black, let first = start else { continue }
            let isGuard = first < 3 || (45..<50).contains(first) || first >= modules.count - 3
            bars.append(CGRect(x: left + CGFloat(first) * width, y: top, width: CGFloat(index - first) * width,
                               height: isGuard ? height * guardExtension : height))
            start = nil
        }
        return bars
    }
}

/// 標籤上的固定印字：外圈環狀字、內緣細圈、品牌字、條碼（不畫數字；取代 MD Vinyl 素材的印字；#5-1）。`diameter`＝標籤直徑
struct LabelRing: View {
    let diameter: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let rim = LabelLayout.rimDiameter * diameter
                context.stroke(Path(ellipseIn: CGRect(x: center.x - rim / 2, y: center.y - rim / 2, width: rim, height: rim)),
                               with: .color(color.opacity(0.25)), lineWidth: max(0.5, diameter * 0.0037))
                drawRing(center: center, in: &context)
                if let modules = VinylAssetsEasterEgg.digits.flatMap(UPCABarcode.modules) {
                    for bar in LabelLayout.barcodeBars(modules, diameter: diameter) {
                        context.fill(Path(bar.offsetBy(dx: center.x, dy: center.y)), with: .color(color))
                    }
                }
            }
            Text(verbatim: LabelLayout.wordmark)
                .font(.system(size: LabelLayout.wordmarkFont * diameter, weight: .bold))
                .tracking(LabelLayout.wordmarkTracking * diameter)
                .offset(y: (LabelLayout.wordmarkTop + LabelLayout.wordmarkFont / 2) * diameter)
        }
        .foregroundStyle(color)
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func drawRing(center: CGPoint, in context: inout GraphicsContext) {
        let font = Font.system(size: LabelLayout.ringFont * diameter, weight: .semibold)
        let characters = Array(LabelLayout.ringText)
        for (character, angle) in zip(characters, LabelLayout.ringAngles(count: characters.count)) where character != " " {
            let glyph = LabelLayout.ringGlyph(angle: angle, center: center, diameter: diameter)
            var local = context
            local.translateBy(x: glyph.position.x, y: glyph.position.y)
            local.rotate(by: .radians(glyph.rotation))
            local.draw(local.resolve(Text(String(character)).font(font).foregroundStyle(color.opacity(0.8))), at: .zero, anchor: .center)
        }
    }
}

/// 條碼彩蛋的數字只放本機（`VinylAssets.local/barcode.txt`，不進公開 repo）；沒有或不是 11 位數字＝不畫條碼
enum VinylAssetsEasterEgg {
    static let digits: String? = {
        guard let url = Bundle.main.url(forResource: "barcode", withExtension: "txt", subdirectory: "VinylAssets.local"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return UPCABarcode.checkDigit(trimmed) == nil ? nil : trimmed
    }()
}
