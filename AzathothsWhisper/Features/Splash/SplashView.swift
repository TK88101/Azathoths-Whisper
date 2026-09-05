import SwiftUI

// 啟動畫面（splash.py:3-90）。時序 1:1：
//   container fadeIn 3s（0→20% 淡入、80%→100% 淡出）／logo 1s@0.5s／text 1s@1.5s
struct SplashView: View {
    @State private var containerOpacity = 0.0
    @State private var logoOpacity = 0.0
    @State private var logoScale = 0.9
    @State private var textOpacity = 0.0
    @State private var textOffset = 4.0

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                HexagonLogo()
                    .frame(width: 128, height: 128)
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)

                VStack(spacing: 16) {
                    Text(verbatim: AppInfo.title)
                        .font(.system(size: 30, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(9)                       // letter-spacing 0.3em @30px
                        .foregroundStyle(.white)
                        .textGlow()
                    Text(verbatim: "Initializing Core Logic")
                        .font(Theme.Fonts.mono(12))
                        .textCase(.uppercase)
                        .tracking(1.2)                     // 0.1em @12px
                        .foregroundStyle(Color(hex: 0x888888))
                }
                .padding(.top, 32)
                .opacity(textOpacity)
                .offset(y: textOffset)
            }
            .opacity(containerOpacity)
        }
        .ignoresSafeArea()
        .task { await animate() }
    }

    private func animate() async {
        withAnimation(.linear(duration: 0.6)) { containerOpacity = 1 }
        withAnimation(.easeOut(duration: 1).delay(0.5)) {
            logoOpacity = 1
            logoScale = 1
        }
        withAnimation(.easeOut(duration: 1).delay(1.5)) {
            textOpacity = 1
            textOffset = 0
        }
        try? await Task.sleep(for: .milliseconds(2400))
        withAnimation(.linear(duration: 0.6)) { containerOpacity = 0 }
    }
}

// splash.py:77-81 的 SVG（viewBox 0 0 100 100）
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
