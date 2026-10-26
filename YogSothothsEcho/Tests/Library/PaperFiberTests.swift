import CoreGraphics
import Testing

@testable import YogSothothsEcho

// F2 ⑤紙纖維 中（s6-61-round2.md §4 P1、附錄 D）：與小樣同一演算法（feTurbulence 移植）、可重現、四邊無縫
struct PaperFiberTests {
    static let tileBytes = PaperFiber.bytes(PaperFiber.layers, side: PaperFiber.tileSide)

    @Test func tileIsDeterministic() {
        #expect(PaperFiber.bytes(PaperFiber.layers, side: PaperFiber.tileSide) == Self.tileBytes)
        #expect(Self.tileBytes.count == PaperFiber.tileSide * PaperFiber.tileSide * 4)
    }

    @Test func meanAlphaInRange() {
        let bytes = Self.tileBytes
        let alphas = stride(from: 3, to: bytes.count, by: 4).map { Double(bytes[$0]) / 255 }
        let mean = alphas.reduce(0, +) / Double(alphas.count)
        #expect((0.02...0.10).contains(mean), "平均 alpha \(mean)")
    }

    /// 每層的非零比例與平均 alpha＝小樣在 Chrome 實測值（2026-10-22；C、D 小樣 tile 為 200／180，App 統一 260，容差放寬）
    @Test func layersMatchPreviewMeasurement() {
        let measured: [(coverage: Double, mean: Double)] = [(0.657, 0.248), (0.598, 0.212), (0.109, 0.036), (0.814, 0.199)]
        for (layer, target) in zip(PaperFiber.layers, measured) {
            let alpha = PaperFiber.alpha(of: layer, side: PaperFiber.tileSide)
            let coverage = Double(alpha.filter { $0 > 0 }.count) / Double(alpha.count)
            let mean = alpha.reduce(0, +) / Double(alpha.count)
            #expect(abs(coverage - target.coverage) <= 0.05, "種子 \(layer.seed) 非零比例 \(coverage)")
            #expect(abs(mean - target.mean) <= max(0.01, target.mean * 0.15), "種子 \(layer.seed) 平均 \(mean)")
        }
    }

    /// 深纖維層：橫向（位移 4 px）自相關 > 縱向＝橫向條紋
    @Test func fibersRunHorizontally() {
        let side = PaperFiber.tileSide
        let n = PaperFiber.alpha(of: PaperFiber.layers[0], side: side)
        func correlation(dx: Int, dy: Int) -> Double {
            let mean = n.reduce(0, +) / Double(n.count)
            var num = 0.0, den = 0.0
            for y in 0..<side { for x in 0..<side {
                let a = n[y * side + x] - mean, b = n[((y + dy) % side) * side + (x + dx) % side] - mean
                num += a * b; den += a * a
            } }
            return num / den
        }
        #expect(correlation(dx: 4, dy: 0) > correlation(dx: 0, dy: 4) + 0.2)
    }

    /// 四邊無縫：低頻那一軸，跨邊差不超過內部相鄰差的最大值（stitchTiles）
    @Test func tileWrapsSeamlessly() {
        let side = PaperFiber.tileSide
        let n = Turbulence(seed: 4).fractalNoiseTile(channel: 0, width: side, height: side, baseFrequencyX: 0.05, baseFrequencyY: 0.05, octaves: 2)
        func columnDiff(_ a: Int, _ b: Int) -> Double { (0..<side).map { abs(n[$0 * side + a] - n[$0 * side + b]) }.reduce(0, +) / Double(side) }
        func rowDiff(_ a: Int, _ b: Int) -> Double { (0..<side).map { abs(n[a * side + $0] - n[b * side + $0]) }.reduce(0, +) / Double(side) }
        #expect(columnDiff(side - 1, 0) <= (0..<side - 1).map { columnDiff($0, $0 + 1) }.max()! + 1e-9)
        #expect(rowDiff(side - 1, 0) <= (0..<side - 1).map { rowDiff($0, $0 + 1) }.max()! + 1e-9)
    }

    /// 反例：取 2 倍大 tile 的一角（不週期），接縫明顯（確認上面的測試抓得到）
    @Test func nonPeriodicNoiseWouldFailTheSeamCheck() {
        let side = PaperFiber.tileSide
        let n = Turbulence(seed: 4).fractalNoiseTile(channel: 0, width: side * 2, height: side * 2, baseFrequencyX: 0.05, baseFrequencyY: 0.05, octaves: 2)
        func at(_ x: Int, _ y: Int) -> Double { n[y * side * 2 + x] }
        let seam = (0..<side).map { abs(at(side - 1, $0) - at(0, $0)) }.reduce(0, +) / Double(side)
        let inner = (0..<side - 1).map { x in (0..<side).map { abs(at(x, $0) - at(x + 1, $0)) }.reduce(0, +) / Double(side) }.max()!
        #expect(seam > inner)
    }

    @Test func tileImageIsBuiltOnce() {
        #expect(PaperFiber.tileImage === PaperFiber.tileImage)
        #expect(PaperFiber.haloImage === PaperFiber.haloImage)
        #expect(PaperFiber.haloImage.width == PaperFiber.haloSide)
    }
}
