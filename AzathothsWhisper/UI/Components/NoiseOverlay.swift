import SwiftUI

// 全屏噪點層（py:127）：fixed inset-0 pointer-events-none z-50 bg-noise opacity-40 mix-blend-overlay
// 原版噪點＝內嵌 SVG feTurbulence；此處為等效的預渲染 PNG 平鋪（決策 4：CDN/內嵌資源本地化）。
struct NoiseOverlay: View {
    var body: some View {
        Group {
            if let noise = BundleAssets.noise {
                Image(nsImage: noise)
                    .resizable(resizingMode: .tile)
            } else {
                Color.clear
            }
        }
        .opacity(0.4)
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}
