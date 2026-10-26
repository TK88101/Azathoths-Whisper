import Foundation

/// 封面取色（F-V-03；sprint-5-detail.md D7）：近似 androidx Palette，不追求逐像素一致。
/// 輸入是縮小後的 RGBA8 像素（呼叫端先縮到約 64×64）；alpha < 128 的像素不計
enum AlbumPalette {
    /// Palette `Target.MUTED`：飽和度目標 0.3（0–0.4）、亮度目標 0.5（0.3–0.7），權重 0.24／0.52／0.24
    private static let mutedSaturation = (target: 0.3, range: 0.0...0.4, weight: 0.24)
    private static let mutedLightness = (target: 0.5, range: 0.3...0.7, weight: 0.52)
    private static let populationWeight = 0.24
    private static let minimumBodyContrast = 4.5
    private static let opaqueThreshold: UInt8 = 128

    private struct Bucket {
        var count = 0
        var sum = (r: 0, g: 0, b: 0)

        mutating func add(_ r: Int, _ g: Int, _ b: Int) {
            count += 1
            sum = (sum.r + r, sum.g + g, sum.b + b)
        }

        var color: RGBColor {
            RGBColor(r: Double(sum.r) / Double(count) / 255, g: Double(sum.g) / Double(count) / 255,
                     b: Double(sum.b) / Double(count) / 255)
        }
    }

    static func extract(rgba: [UInt8]) -> AlbumColors {
        let buckets = quantize(rgba)
        // 同人口取量化格較小者：結果不隨像素順序變
        guard let dominant = buckets.max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) })?.value else {
            return .fallback
        }
        let primary = dominant.color
        let text = textColor(on: primary)
        let muted = muted(buckets)
        return AlbumColors(primary: primary, text: text, secondary: muted ?? AlbumColors.fallback.secondary, hasMuted: muted != nil,
                           vivid: vivid(rgba: rgba))
    }

    /// 底色上的文字（與放射紋）色：WCAG 對比 ≥ 4.5 選白，否則黑
    static func textColor(on background: RGBColor) -> RGBColor {
        contrast(.white, background) >= minimumBodyContrast ? .white : .black
    }

    /// WCAG 對比：(L1 + 0.05) / (L2 + 0.05)，L1 為較亮者
    static func contrast(_ a: RGBColor, _ b: RGBColor) -> Double {
        let (high, low) = a.luminance >= b.luminance ? (a.luminance, b.luminance) : (b.luminance, a.luminance)
        return (high + 0.05) / (low + 0.05)
    }

    /// RGB 各取高 5 bit 為格；格的顏色＝格內像素平均
    private static func quantize(_ rgba: [UInt8]) -> [Int: Bucket] {
        var buckets: [Int: Bucket] = [:]
        for start in stride(from: 0, to: rgba.count - 3, by: 4) where rgba[start + 3] >= opaqueThreshold {
            let r = Int(rgba[start]), g = Int(rgba[start + 1]), b = Int(rgba[start + 2])
            let key = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            buckets[key, default: Bucket()].add(r, g, b)
        }
        return buckets
    }

    private static func muted(_ buckets: [Int: Bucket]) -> RGBColor? {
        let maxCount = Double(buckets.values.map(\.count).max() ?? 1)
        let scored = buckets.compactMap { key, bucket -> (score: Double, key: Int, color: RGBColor)? in
            let color = bucket.color
            let (saturation, lightness) = hsl(color)
            guard mutedSaturation.range.contains(saturation), mutedLightness.range.contains(lightness) else { return nil }
            let score = mutedSaturation.weight * (1 - abs(saturation - mutedSaturation.target))
                + mutedLightness.weight * (1 - abs(lightness - mutedLightness.target))
                + populationWeight * Double(bucket.count) / maxCount
            return (score, key, color)
        }
        return scored.max { ($0.score, $1.key) < ($1.score, $0.key) }?.color
    }

    /// 鮮色：只看飽和 ≥ 0.35、明度 0.2–0.75 的像素
    private static let vividSaturation = 0.35, vividLightness = 0.2...0.75
    /// 色相 30° 一箱、0° 置中（[345°, 15°) 是 0 號箱，紅不被切成兩半）
    private static let vividBinDegrees = 30.0
    /// 最多的箱至少占全部不透明像素的 1%；平均後仍要夠鮮
    private static let vividMinimumShare = 0.01, vividMinimumAverageSaturation = 0.2

    /// 封面上最多的鮮豔色相（v2.1 T11）：5-bit 分格會把同一種血紅拆成許多小格，改以色相分箱計票，回傳該箱平均色
    static func vivid(rgba: [UInt8]) -> RGBColor? {
        var bins: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        var opaque = 0
        for start in stride(from: 0, to: rgba.count - 3, by: 4) where rgba[start + 3] >= opaqueThreshold {
            opaque += 1
            let c = RGBColor(r: Double(rgba[start]) / 255, g: Double(rgba[start + 1]) / 255, b: Double(rgba[start + 2]) / 255)
            let (saturation, lightness) = hsl(c)
            guard saturation >= vividSaturation, vividLightness.contains(lightness) else { continue }
            let bin = Int(((hue(c) + vividBinDegrees / 2).truncatingRemainder(dividingBy: 360)) / vividBinDegrees)
            let sum = bins[bin, default: (0, 0, 0, 0)]
            bins[bin] = (sum.count + 1, sum.r + c.r, sum.g + c.g, sum.b + c.b)
        }
        guard let best = bins.max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) })?.value,
              Double(best.count) >= vividMinimumShare * Double(opaque) else { return nil }
        let n = Double(best.count)
        let color = RGBColor(r: best.r / n, g: best.g / n, b: best.b / n)
        return hsl(color).saturation >= vividMinimumAverageSaturation ? color : nil
    }

    /// 色相（度，[0, 360)）
    private static func hue(_ c: RGBColor) -> Double { c.hsl.hue }

    /// HSL 的飽和度與亮度，0…1（Palette 用 HSL，不是相對亮度；換算本體在 `RGBColor.hsl`）
    private static func hsl(_ c: RGBColor) -> (saturation: Double, lightness: Double) {
        let v = c.hsl
        return (v.saturation / 100, v.lightness / 100)
    }
}
