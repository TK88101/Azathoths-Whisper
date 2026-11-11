#if LIQUID_SAMPLE
import SwiftUI

/// CR-038 液態黑膠小樣的盤面（§4.1）：盤體色（半透明藍紫）→ 液體層（只在環帶內）。
/// 溝紋高光、外沿光環、標籤、中心孔照舊由 VinylRecordView 疊在上面
struct LiquidVinylLayer: View {
    static let bodyColor = RGBColor(hex: 0x5B4BD6)
    static let bodyOpacity = 0.55

    let frame: LiquidFrame
    let side: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Self.bodyColor.color.opacity(Self.bodyOpacity))
            Self.liquid(frame, side: side)
        }
    }

    /// 只有液體層（渲染測試直接取樣這一層）
    static func liquid(_ frame: LiquidFrame, side: CGFloat) -> some View {
        Rectangle().fill(Color.white)
            .frame(width: side, height: side)
            .colorEffect(shader(frame, side: side))
    }

    static func shader(_ frame: LiquidFrame, side: CGFloat) -> Shader {
        ShaderLibrary.liquidVinyl(
            .float2(CGSize(width: side, height: side)),
            .float(frame.discAngle.truncatingRemainder(dividingBy: 360)),
            .float(frame.lag),
            .float(frame.fling),
            .float(frame.flingGain),
            .floatArray(blobUniforms)
        )
    }

    /// 每顆 4 個 float：核心半徑基準、角位置、角向寬度、濃度
    static let blobUniforms: [Float] = LiquidBlob.seeds.flatMap {
        [Float($0.baseRadius), Float($0.angle), Float($0.angularSpread), Float($0.strength)]
    }
}
#endif
