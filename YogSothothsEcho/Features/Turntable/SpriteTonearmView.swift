import SwiftUI

/// 序列圖唱臂（CR-034 §4.4）：Animatable——落臂／抬臂動畫的每一幀以插值角度取最近的整數度幀（投影同幀），
/// 整張繞支點轉完整角度（素材每幀是 rest 姿態）。還沒解到的幀用最近已解碼的頂上；一張都沒有＝不畫
struct SpriteTonearmView: View, Animatable {
    var angle: Double
    let layout: TurntableLayout
    let sprites: TonearmSpriteCache

    /// SwiftUI 動畫逐幀寫入的插值角度（Animatable 非隔離協定；角度是 Sendable 的值）
    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let lookup = sprites.frames(forAngle: angle, skin: layout.skin)
        let degrees = layout.skin.armRotation(forAngle: angle)
        #if DEBUG
        if let lookup {
            let requested = TonearmSpriteCache.frameIndex(angle: angle, rest: layout.skin.restDegrees, count: SpriteSkinAssets.frameCount)
            SpriteTrace.current?.frameRequested(requested: requested, served: lookup.frame, exact: lookup.exact)
        }
        #endif
        return ZStack(alignment: .topLeading) {
            if let lookup, let rect = layout.armShadow, let frame = layout.skin.spec.armShadow {
                Self.layer(lookup.pair.shadow, rect, frame, degrees)
            }
            if let lookup {
                Self.layer(lookup.pair.arm, layout.arm, layout.skin.spec.arm, degrees)
            }
        }
    }

    private static func layer(_ image: CGImage, _ rect: CGRect, _ frame: ArtworkFrame, _ degrees: Double) -> some View {
        Image(decorative: image, scale: 1).resizable()
            .frame(width: rect.width, height: rect.height)
            .rotationEffect(.degrees(degrees), anchor: UnitPoint(x: frame.pivotFraction.x, y: frame.pivotFraction.y))
            .offset(x: rect.minX, y: rect.minY)
    }
}
