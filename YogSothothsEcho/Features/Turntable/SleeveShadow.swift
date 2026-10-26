import CoreGraphics
import SwiftUI
import UIKit

/// 封面立體感（sprint-6-detail.md D13、§4.13）：原版 Android 唱機封套有投影（高度 8 dp×縮放、寬視窗 12 dp，向下位移＝模糊半徑）
/// ＋內陰影（`landscapeArtworkInnerShadowOpacity`，實際值未從逆向取得＝目視起點 0.28）。詳情封面的投影值取自 `DetailCoverShadow`（#6-1 v0.6 F5）
struct SleeveShadow: Equatable {
    let radius: CGFloat
    let offsetY: CGFloat
    let opacity: Double
    let innerOpacity: Double

    /// Material 的 expanded 寬度（dp）：原版「寬視窗」分支的界線；iPad 橫屏一律落在寬視窗
    static let wideWindowMinWidth: CGFloat = 840
    static let narrowElevation: CGFloat = 8
    static let wideElevation: CGFloat = 12
    /// BLUR 背景下的起點，實機 #6-1 目視再調
    static let turntableOpacity = 0.35
    static let turntableInnerOpacity = 0.28


    static func turntable(scale: CGFloat, containerWidth: CGFloat) -> SleeveShadow {
        let radius = (containerWidth >= wideWindowMinWidth ? wideElevation : narrowElevation) * scale
        return SleeveShadow(radius: radius, offsetY: radius, opacity: turntableOpacity, innerOpacity: turntableInnerOpacity)
    }

    /// 完整投影外框：封套外框往下位移後向四周擴張模糊半徑（不被裁切的檢查以它為準）
    func extent(of rect: CGRect) -> CGRect { rect.offsetBy(dx: 0, dy: offsetY).insetBy(dx: -radius, dy: -radius) }
}

/// 封套面：封面（或佔位）＋圓角＋內陰影（圓角內的疊層）＋投影（圓角外、畫在自己的 background）。
/// 投影屬於這個視圖本身，封套的傾斜、全封面、G7 換片、進唱機都作用在「封套＋投影」整體上，投影自然跟著動
struct SleeveFace: View {
    let image: UIImage?
    let placeholder: Color
    let size: CGSize
    let cornerRadius: CGFloat
    let shadow: SleeveShadow

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
            if shadow.innerOpacity > 0 {
                // 內陰影：沿邊的暗色描邊模糊後只留在圓角內
                shape.stroke(Color.black.opacity(shadow.innerOpacity), lineWidth: max(2, shadow.radius / 2))
                    .blur(radius: max(1, shadow.radius / 3))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .background(
            shape.fill(Color.black.opacity(shadow.opacity))
                .blur(radius: shadow.radius)
                .offset(y: shadow.offsetY)
        )
    }
}
