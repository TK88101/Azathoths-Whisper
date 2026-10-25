import SwiftUI

// 六角形 logo（splash.py:77-81 的 SVG，viewBox 0 0 100 100）。開場畫面 2026-10-25 拿掉後，只剩 About 的備用 logo 使用
struct HexagonLogo: View {
    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 100

            ZStack {
                hexagon(points: [(50, 0), (100, 25), (100, 75), (50, 100), (0, 75), (0, 25)], scale: scale)
                    .stroke(Color(hex: 0x555555), lineWidth: 2 * scale)
                hexagon(points: [(50, 10), (90, 30), (90, 70), (50, 90), (10, 70), (10, 30)], scale: scale)
                    .stroke(Color.white, lineWidth: 3 * scale)
                Circle()
                    .stroke(Color.white, lineWidth: 2 * scale)
                    .frame(width: 30 * scale, height: 30 * scale)
                    .position(x: 50 * scale, y: 50 * scale)
            }
        }
    }

    private func hexagon(points: [(Double, Double)], scale: Double) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.0 * scale, y: first.1 * scale))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.0 * scale, y: point.1 * scale))
        }
        path.closeSubpath()
        return path
    }
}
