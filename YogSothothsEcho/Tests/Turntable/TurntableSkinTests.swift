import CoreGraphics
import Foundation
import Testing

@testable import YogSothothsEcho

// S7 T3（sprint-7-detail.md §4.2、§4.3）：皮膚規格 → 唯一入口 resolve 驗證並求起止角。角度一律是畫面絕對角
// （0＝臂管朝畫面正下方、順時針為正）；θ 時針尖＝pivot + rotate(stylusAtRest, θ − restDegrees)

struct TurntableSkinTests {
    private func resolved(_ skin: TurntableSkin) throws -> ResolvedTurntableSkin {
        try TurntableSkinResolver.resolve(skin).get()
    }

    private func with(_ change: (inout TonearmKinematics) -> Void) -> TurntableSkin {
        var k = TurntableSkin.classic.kinematics
        change(&k)
        return TurntableSkin.classic.replacing(kinematics: k)
    }

    @Test func classicResolvesToTheOriginalArmAngles() throws {
        let r = try resolved(.classic)
        // 宣告值原樣採用（不是求解值），既有的精確相等才成立
        #expect(r.startDegrees == 14.1 && r.sweepDegrees == 19.3)
        #expect(abs(r.endDegrees - 33.4) < 1e-9)
        #expect(ResolvedTurntableSkin.classic == r)
    }

    /// DoD：用原版唱臂數值驗算——落針／播完半徑取到 0.1 u 的整數值，求出來仍是 14.1°／33.4°（±0.05°，附錄 B）
    @Test func roundedRadiiStillGiveTheOriginalAngles() throws {
        let r = try resolved(with { $0 = TonearmKinematics(pivot: $0.pivot, stylusAtRest: $0.stylusAtRest, restDegrees: 0,
                                                            leadInRadius: 215.0, runOutRadius: 131.2) })
        #expect(abs(r.startDegrees - 14.1) <= 0.05 && abs(r.endDegrees - 33.4) <= 0.05)
    }

    /// 同一條物理臂、素材畫成轉 10° 的姿態：求出的絕對角與 rest＝0 的素材相同（兩邊都以同一組半徑求解）
    @Test func artworkDrawnAtANonZeroRestKeepsTheAbsoluteAngles() throws {
        let rest = 10.0
        let tip = TonearmGeometry.rotate(CGPoint(x: 6, y: 365), about: .zero, degrees: rest)
        #expect(abs(tip.x - -57.47) < 0.01 && abs(tip.y - 360.50) < 0.01)
        let upright = try resolved(with { $0 = TonearmKinematics(pivot: $0.pivot, stylusAtRest: $0.stylusAtRest, restDegrees: 0,
                                                                  leadInRadius: $0.leadInRadius, runOutRadius: $0.runOutRadius) })
        let r = try resolved(with { $0 = TonearmKinematics(pivot: $0.pivot, stylusAtRest: CGVector(dx: tip.x, dy: tip.y), restDegrees: rest,
                                                            leadInRadius: $0.leadInRadius, runOutRadius: $0.runOutRadius) })
        #expect(abs(r.startDegrees - upright.startDegrees) < 1e-9 && abs(r.endDegrees - upright.endDegrees) < 1e-9)
    }

    /// 支點→唱片圓心 269.3 u、臂長 365.05 u：針尖只掃得到距圓心 95.7–634.4 u 的環帶
    @Test func radiusOutsideTheReachableBandIsRejected() {
        #expect(TurntableSkinResolver.resolve(with { $0 = $0.replacing(leadInRadius: 10) }) == .failure(.noLeadIn))
        #expect(TurntableSkinResolver.resolve(with { $0 = $0.replacing(runOutRadius: 10) }) == .failure(.noRunOut))
    }

    @Test func tangentRadiusIsRejected() {
        let k = TurntableSkin.classic.kinematics
        let center = CGPoint(x: TurntableMetrics.recordSize / 2, y: TurntableMetrics.recordSize / 2)
        let gap = hypot(k.stylusAtRest.dx, k.stylusAtRest.dy) - hypot(center.x - k.pivot.x, center.y - k.pivot.y)
        #expect(TurntableSkinResolver.resolve(with { $0 = $0.replacing(runOutRadius: gap) }) == .failure(.noRunOut))
    }

    @Test func runOutOutsideTheLeadInIsRejected() {
        let skin = with { $0 = $0.replacing(leadInRadius: 131.2).replacing(runOutRadius: 215.0) }
        #expect(TurntableSkinResolver.resolve(skin) == .failure(.runOutBeforeLeadIn))
    }

    /// classic 宣告 14.1°＋19.3°：求解只當驗算，半徑若改到與宣告角對不上（差 > 0.05°）就拒收
    @Test func declaredTravelMustAgreeWithTheSolvedAngles() throws {
        #expect(TurntableSkin.classic.kinematics.declaredTravel != nil)
        #expect(TurntableSkinResolver.resolve(with { $0 = $0.replacing(leadInRadius: 200) }) == .failure(.declaredTravelMismatch))
    }

    @Test func invalidNumbersAreRejectedBeforeSolving() {
        #expect(TurntableSkinResolver.resolve(with { $0 = TonearmKinematics(pivot: CGPoint(x: CGFloat.nan, y: 60), stylusAtRest: $0.stylusAtRest,
            restDegrees: 0, leadInRadius: $0.leadInRadius, runOutRadius: $0.runOutRadius) }) == .failure(.nonFinite))
        #expect(TurntableSkinResolver.resolve(with { $0 = TonearmKinematics(pivot: $0.pivot, stylusAtRest: $0.stylusAtRest,
            restDegrees: .infinity, leadInRadius: $0.leadInRadius, runOutRadius: $0.runOutRadius) }) == .failure(.nonFinite))
        #expect(TurntableSkinResolver.resolve(with { $0 = TonearmKinematics(pivot: $0.pivot, stylusAtRest: .zero,
            restDegrees: 0, leadInRadius: $0.leadInRadius, runOutRadius: $0.runOutRadius) }) == .failure(.zeroStylus))
        #expect(TurntableSkinResolver.resolve(with { $0 = $0.replacing(leadInRadius: 0) }) == .failure(.nonPositiveRadius))
        #expect(TurntableSkinResolver.resolve(with { $0 = $0.replacing(runOutRadius: -1) }) == .failure(.nonPositiveRadius))
    }

    @Test func invalidArtworkFramesAreRejected() {
        let classic = TurntableSkin.classic
        let flat = ArtworkFrame(size: CGSize(width: 0, height: 457), localPivot: .zero)
        let outside = ArtworkFrame(size: classic.base.size, localPivot: CGPoint(x: 34, y: 200))
        #expect(TurntableSkinResolver.resolve(classic.replacing(arm: flat)) == .failure(.invalidFrame))
        #expect(TurntableSkinResolver.resolve(classic.replacing(base: outside)) == .failure(.pivotOutsideFrame))
    }

    @Test func invalidHitShapesAreRejected() {
        let classic = TurntableSkin.classic
        func shaped(_ shape: TurntableSkin.HitShape) -> TurntableSkin {
            TurntableSkin(id: classic.id, kinematics: classic.kinematics, arm: classic.arm, base: classic.base, hitShape: shape,
                          rendering: classic.rendering)
        }
        for shape in [TurntableSkin.HitShape.tubeStrip(halfWidth: .nan, headTop: 337, headBottom: 407),
                      .tubeStrip(halfWidth: -1, headTop: 337, headBottom: 407),
                      .tubeStrip(halfWidth: 14, headTop: 407, headBottom: 337),
                      .tubeStrip(halfWidth: 14, headTop: -1, headBottom: 407),
                      .tubeStrip(halfWidth: 14, headTop: 337, headBottom: 458)] {
            #expect(TurntableSkinResolver.resolve(shaped(shape)) == .failure(.invalidHitShape), "\(shape)")
        }
    }

    /// 畫框左上＝支點 − 畫布支點：classic 回到原版的臂框 (406, 24)、底座 (406, 11)（唱片框座標，u）
    @Test func classicFramesLandOnTheOriginalOrigins() {
        let skin = TurntableSkin.classic
        #expect(abs(skin.armOrigin.x - 406) < 1e-9 && abs(skin.armOrigin.y - 24) < 1e-9)
        #expect(abs(skin.baseOrigin.x - 406) < 1e-9 && abs(skin.baseOrigin.y - 11) < 1e-9)
        #expect(skin.arm.size == CGSize(width: 106, height: 457) && skin.base.size == CGSize(width: 106, height: 154))
    }

    /// 同一條臂、素材畫成轉 10° 的姿態：版面外接框與點擊判定都只經 `armRotation`——與 classic 在「θ − 10°」時逐點相同
    @Test func nonZeroRestSkinRotatesLayoutAndHitTestTheSameWay() throws {
        let rest = 10.0
        let tip = TonearmGeometry.rotate(CGPoint(x: 6, y: 365), about: .zero, degrees: rest)
        let k = TurntableSkin.classic.kinematics
        let turned = try resolved(.classic.replacing(kinematics: TonearmKinematics(
            pivot: k.pivot, stylusAtRest: CGVector(dx: tip.x, dy: tip.y), restDegrees: rest,
            leadInRadius: k.leadInRadius, runOutRadius: k.runOutRadius)))
        let container = CGRect(x: 0, y: 24, width: 1376, height: 988)
        let a = TurntableLayout(container: container, fullCover: false, skin: turned)
        let b = TurntableLayout(container: container, fullCover: false, skin: .classic)
        for angle in [14.1, 24.0, 33.4] {
            let boxA = a.armBoundingBox(angle: angle), boxB = b.armBoundingBox(angle: angle - rest)
            #expect([boxA.minX - boxB.minX, boxA.minY - boxB.minY, boxA.maxX - boxB.maxX, boxA.maxY - boxB.maxY].allSatisfy { abs($0) < 1e-9 },
                    "外接框 \(angle)°")
            for x in stride(from: a.arm.minX - 200, through: a.arm.maxX + 200, by: 9) {
                for y in stride(from: a.arm.minY, through: a.arm.maxY + 100, by: 9) {
                    let point = CGPoint(x: x, y: y)
                    #expect(TurntableHitTest.classify(point, layout: a, sleeve: CoverSleeveState(), armAngle: angle)
                            == TurntableHitTest.classify(point, layout: b, sleeve: CoverSleeveState(), armAngle: angle - rest))
                }
            }
        }
    }
}
