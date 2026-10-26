import Foundation

/// SVG `feTurbulence` 的 Swift 移植（SVG 1.1 規格 15.22 節附的參考實作；type＝fractalNoise、stitchTiles＝stitch）。
/// 小樣的紙纖維與磨損毛邊都由瀏覽器的 feTurbulence 產生；App 用同一類 Perlin 梯度雜訊、同頻率與透明度公式（#6-1 第二輪 F2）。
/// 註：Chrome（Skia）的取樣座標與拼接細節與規格參考碼不同，逐像素值對不上（2026-10-22 實測）；只要求統計性質一致（見 PaperFiberTests）
struct Turbulence {
    private static let bSize = 0x100, bMask = 0xFF, perlinN = 0x1000
    private static let randM = 2_147_483_647, randA = 16_807, randQ = 127_773, randR = 2_836

    private var lattice = [Int](repeating: 0, count: 0x100 + 0x100 + 2)
    /// [channel][index] → (x, y)
    private var gradient = [[(Double, Double)]](repeating: [(Double, Double)](repeating: (0, 0), count: 0x100 + 0x100 + 2), count: 4)

    init(seed: Int) {
        var s = Self.setupSeed(seed)
        func random() -> Int {
            var result = Self.randA * (s % Self.randQ) - Self.randR * (s / Self.randQ)
            if result <= 0 { result += Self.randM }
            s = result
            return result
        }
        for k in 0..<4 {
            for i in 0..<Self.bSize {
                lattice[i] = i
                let gx = Double((random() % (Self.bSize + Self.bSize)) - Self.bSize) / Double(Self.bSize)
                let gy = Double((random() % (Self.bSize + Self.bSize)) - Self.bSize) / Double(Self.bSize)
                let length = (gx * gx + gy * gy).squareRoot()
                gradient[k][i] = length == 0 ? (0, 0) : (gx / length, gy / length)
            }
        }
        var i = Self.bSize - 1
        while i > 0 {
            let k = lattice[i]
            let j = random() % Self.bSize
            lattice[i] = lattice[j]
            lattice[j] = k
            i -= 1
        }
        for i in 0..<(Self.bSize + 2) {
            lattice[Self.bSize + i] = lattice[i]
            for k in 0..<4 { gradient[k][Self.bSize + i] = gradient[k][i] }
        }
    }

    private static func setupSeed(_ seed: Int) -> Int {
        var s = seed
        if s <= 0 { s = -(s % (randM - 1)) + 1 }
        if s > randM - 1 { s = randM - 1 }
        return s
    }

    private struct Stitch { var width: Int, height: Int, wrapX: Int, wrapY: Int }

    private func noise2(_ channel: Int, _ x: Double, _ y: Double, _ stitch: Stitch) -> Double {
        let tx = x + Double(Self.perlinN), ty = y + Double(Self.perlinN)
        let rx0 = tx - Double(Int(tx)), rx1 = rx0 - 1
        let ry0 = ty - Double(Int(ty)), ry1 = ry0 - 1
        // 拼接：以未遮罩的格點與 wrap 比較，再遮罩
        let ux0 = Int(tx), ux1 = ux0 + 1, uy0 = Int(ty), uy1 = uy0 + 1
        let bx0 = (ux0 >= stitch.wrapX ? ux0 - stitch.width : ux0) & Self.bMask
        let bx1 = (ux1 >= stitch.wrapX ? ux1 - stitch.width : ux1) & Self.bMask
        let by0 = (uy0 >= stitch.wrapY ? uy0 - stitch.height : uy0) & Self.bMask
        let by1 = (uy1 >= stitch.wrapY ? uy1 - stitch.height : uy1) & Self.bMask
        let i = lattice[bx0], j = lattice[bx1]
        let b00 = lattice[i + by0], b10 = lattice[j + by0], b01 = lattice[i + by1], b11 = lattice[j + by1]
        let sx = rx0 * rx0 * (3 - 2 * rx0), sy = ry0 * ry0 * (3 - 2 * ry0)
        let g = gradient[channel]
        var u = rx0 * g[b00].0 + ry0 * g[b00].1, v = rx1 * g[b10].0 + ry0 * g[b10].1
        let a = u + sx * (v - u)
        u = rx0 * g[b01].0 + ry1 * g[b01].1
        v = rx1 * g[b11].0 + ry1 * g[b11].1
        let b = u + sx * (v - u)
        return a + sy * (b - a)
    }

    /// 整張 tile 某一通道（0＝R…3＝A）的 fractalNoise（0…1，列優先），stitchTiles＝stitch（四邊無縫）
    func fractalNoiseTile(channel: Int, width: Int, height: Int, baseFrequencyX: Double, baseFrequencyY: Double, octaves: Int) -> [Double] {
        func adjusted(_ frequency: Double, _ size: Int) -> Double {
            guard frequency != 0 else { return 0 }
            let low = floor(Double(size) * frequency) / Double(size), high = ceil(Double(size) * frequency) / Double(size)
            return (low > 0 && frequency / low < high / frequency) ? low : high
        }
        let fx = adjusted(baseFrequencyX, width), fy = adjusted(baseFrequencyY, height)
        let stitchWidth = Int(Double(width) * fx + 0.5), stitchHeight = Int(Double(height) * fy + 0.5)
        let base = Stitch(width: stitchWidth, height: stitchHeight, wrapX: Self.perlinN + stitchWidth, wrapY: Self.perlinN + stitchHeight)
        var out = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0, ratio = 1.0
                var vx = Double(x) * fx, vy = Double(y) * fy
                var stitch = base
                for _ in 0..<octaves {
                    sum += noise2(channel, vx, vy, stitch) / ratio
                    vx *= 2; vy *= 2; ratio *= 2
                    stitch.width *= 2; stitch.wrapX = 2 * stitch.wrapX - Self.perlinN
                    stitch.height *= 2; stitch.wrapY = 2 * stitch.wrapY - Self.perlinN
                }
                out[y * width + x] = min(1, max(0, (sum + 1) / 2))
            }
        }
        return out
    }
}
