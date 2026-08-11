import Foundation
import Testing

@testable import AzathothsWhisper

// py:884-899 的 canvas-confetti 五連發參數與物理行為
@Suite("Confetti")
struct ConfettiPhysicsTests {
    @Test func saveCelebrationMatchesPythonParameters() {
        let bursts = ConfettiBurst.saveCelebration
        #expect(bursts.count == 5)
        #expect(bursts.map(\.particleCount) == [50, 40, 70, 20, 20])
        #expect(bursts.reduce(0) { $0 + $1.particleCount } == 200)
        #expect(bursts.map(\.spread) == [26, 60, 100, 120, 120])
        #expect(bursts.map(\.startVelocity) == [55, 45, 45, 25, 45])
        #expect(bursts.map(\.decay) == [0.9, 0.9, 0.91, 0.92, 0.9])
        #expect(bursts.map(\.scalar) == [1, 1, 0.8, 1.2, 1])
        #expect(bursts.allSatisfy { $0.originY == 0.7 })
        #expect(bursts.allSatisfy { $0.angle == 90 && $0.ticks == 200 })
    }

    @Test func particlesStartAtOriginScaledToCanvas() {
        var generator = SystemRandomNumberGenerator()
        let burst = ConfettiBurst(particleCount: 10, originX: 0.5, originY: 0.7)
        let particles = ConfettiFactory.makeParticles(
            burst: burst,
            canvasSize: CGSize(width: 1000, height: 800),
            using: &generator
        )

        #expect(particles.count == 10)
        #expect(particles.allSatisfy { $0.x == 500 && $0.y == 560 })
        #expect(particles.allSatisfy { $0.gravity == 3 })   // opts.gravity * 3
    }

    @Test func zeroSpreadParticleTravelsStraightUp() {
        var generator = SystemRandomNumberGenerator()
        let burst = ConfettiBurst(particleCount: 1, spread: 0, startVelocity: 50)
        var particle = ConfettiFactory.makeParticles(
            burst: burst,
            canvasSize: CGSize(width: 100, height: 100),
            using: &generator
        )[0]
        let startX = particle.x
        let startY = particle.y

        particle.step(using: &generator)

        #expect(abs(particle.x - startX) < 0.000_1, "spread 0 時水平位移為零")
        #expect(particle.y < startY, "canvas 座標 y 向下，向上飛應使 y 變小")
    }

    @Test func velocityDecaysAndAlphaFadesToDeath() {
        var generator = SystemRandomNumberGenerator()
        let burst = ConfettiBurst(particleCount: 1, decay: 0.9, ticks: 5)
        var particle = ConfettiFactory.makeParticles(
            burst: burst,
            canvasSize: CGSize(width: 100, height: 100),
            using: &generator
        )[0]
        let initialVelocity = particle.velocity

        #expect(particle.alpha == 1)
        for _ in 0..<5 { particle.step(using: &generator) }

        #expect(particle.velocity < initialVelocity)
        #expect(particle.alpha == 0)
        #expect(particle.isAlive == false)
    }

    @Test func quadHasFourVerticesForSquareShape() {
        var generator = SystemRandomNumberGenerator()
        let burst = ConfettiBurst(particleCount: 1)
        var particle = ConfettiFactory.makeParticles(
            burst: burst,
            canvasSize: CGSize(width: 100, height: 100),
            using: &generator
        )[0]
        particle.step(using: &generator)

        #expect(particle.quad.count == 4)
    }
}
