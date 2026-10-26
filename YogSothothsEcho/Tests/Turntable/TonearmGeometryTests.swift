import CoreGraphics
import RemoteProtocol
import Testing

@testable import YogSothothsEcho

// S5 T2（sprint-5-detail.md §4.3；spec「唱臂角度 ↔ 播放進度」）：角度↔進度與播放中角度（拖唱頭、唱頭觸摸區、鬆手三段、收斂規則已隨 CR-019 刪除）

struct TonearmGeometryTests {
    @Test func angleAndProgressRoundTrip() {
        #expect(ResolvedTurntableSkin.classic.angle(progress: 0) == 14.1)
        #expect(abs(ResolvedTurntableSkin.classic.angle(progress: 1) - 33.4) < 1e-9)
        #expect(abs(ResolvedTurntableSkin.classic.angle(progress: 0.5) - (14.1 + 9.65)) < 1e-9)
        for p in stride(from: 0.0, through: 1.0, by: 0.125) {
            #expect(abs(ResolvedTurntableSkin.classic.progress(angle: ResolvedTurntableSkin.classic.angle(progress: p)) - p) < 1e-9)
        }
        #expect(ResolvedTurntableSkin.classic.angle(progress: -1) == 14.1 && abs(ResolvedTurntableSkin.classic.angle(progress: 3) - 33.4) < 1e-9)
        #expect(ResolvedTurntableSkin.classic.progress(angle: 0) == 0 && ResolvedTurntableSkin.classic.progress(angle: 90) == 1)
    }

    /// 播放中跟進度；暫停、停止、無長度＝抬臂 0°（spec：0° 靜止＝暫停／無播放）
    @Test func playbackAngle() {
        #expect(abs(ResolvedTurntableSkin.classic.playbackAngle(state: .playing, position: 50, duration: 100) - 23.75) < 1e-9)
        #expect(ResolvedTurntableSkin.classic.playbackAngle(state: .paused, position: 50, duration: 100) == 0)
        #expect(ResolvedTurntableSkin.classic.playbackAngle(state: .stopped, position: 0, duration: 100) == 0)
        #expect(ResolvedTurntableSkin.classic.playbackAngle(state: .playing, position: 50, duration: nil) == 0)
        #expect(ResolvedTurntableSkin.classic.playbackAngle(state: .playing, position: 50, duration: 0) == 0)
    }
}
