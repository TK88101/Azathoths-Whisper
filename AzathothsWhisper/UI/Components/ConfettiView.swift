import SwiftUI

// 保存成功時的五連發（py:544-545 triggerConfetti）。全窗覆蓋、不吃點擊。
@MainActor
@Observable
final class ConfettiEngine {
    private(set) var particles: [ConfettiParticle] = []
    private var generator = SystemRandomNumberGenerator()

    var isRunning: Bool { !particles.isEmpty }

    func fire(_ bursts: [ConfettiBurst], canvasSize: CGSize) {
        for burst in bursts {
            particles.append(
                contentsOf: ConfettiFactory.makeParticles(burst: burst, canvasSize: canvasSize, using: &generator)
            )
        }
    }

    func step() {
        for index in particles.indices {
            particles[index].step(using: &generator)
        }
        particles.removeAll { !$0.isAlive }
    }
}

struct ConfettiView: View {
    /// 每次遞增觸發一輪；0 表示尚未觸發
    let trigger: Int

    @State private var engine = ConfettiEngine()

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, _ in
                for particle in engine.particles {
                    draw(particle, in: &context)
                }
            }
            .task(id: trigger) {
                guard trigger > 0 else { return }
                engine.fire(ConfettiBurst.saveCelebration, canvasSize: proxy.size)
                while engine.isRunning, !Task.isCancelled {
                    engine.step()
                    try? await Task.sleep(for: ConfettiTiming.frameInterval)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ particle: ConfettiParticle, in context: inout GraphicsContext) {
        let color = Color(
            red: particle.color.red,
            green: particle.color.green,
            blue: particle.color.blue
        ).opacity(particle.alpha)

        switch particle.shape {
        case .square:
            var path = Path()
            let points = particle.quad
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
            context.fill(path, with: .color(color))

        case .circle:
            let oval = particle.oval
            let rect = CGRect(
                x: oval.center.x - oval.radii.width,
                y: oval.center.y - oval.radii.height,
                width: oval.radii.width * 2,
                height: oval.radii.height * 2
            )
            var transformed = context
            transformed.translateBy(x: oval.center.x, y: oval.center.y)
            transformed.rotate(by: .radians(oval.rotation))
            transformed.translateBy(x: -oval.center.x, y: -oval.center.y)
            transformed.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}
