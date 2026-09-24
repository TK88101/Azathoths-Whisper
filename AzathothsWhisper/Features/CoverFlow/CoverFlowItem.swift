import SwiftUI

/// 單張封面：正面 ＋ 倒影 ＋ 無圖佔位。
///
/// 3D 變換由父視圖透過 `.visualEffect` 套用（需要視口座標，只有父層知道）；
/// 本視圖只負責一張卡片自身的樣子。
struct CoverFlowItem: View {
    let artwork: NSImage?
    let size: CGFloat

    /// 倒影高度佔封面的比例（§4.8：LinearGradient 0.45 → 0）。條帶外的點擊區以此推算封面正面的位置
    static let reflectionRatio: CGFloat = 0.45

    private var reflectionRatio: CGFloat { Self.reflectionRatio }

    var body: some View {
        VStack(spacing: 0) {
            face
            reflection
        }
        // §4.8：整張卡片（含倒影）合成為單一圖層，避免逐幀重繪倒影漸變
        .drawingGroup()
    }

    /// 正面與倒影共用同一份渲染——分開寫兩份的話，日後調整 interpolation／contentMode／
    /// 佔位邏輯時漏改一處，正面圖與倒影會靜默不一致，而 View 層沒有測試會抓到
    private var artworkOrPlaceholder: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        // H-08：佔位與封面**同尺寸固定 frame**，佈局不得跳動
        .frame(width: size, height: size)
        .clipped()
    }

    private var face: some View {
        artworkOrPlaceholder
            .overlay {
                Rectangle().strokeBorder(Theme.border, lineWidth: 1)
            }
    }

    /// H-08：無封面＝六角形 logo 暗紋
    private var placeholder: some View {
        ZStack {
            Theme.cardBackground
            if let logo = BundleAssets.aboutLogo {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.28)
                    .opacity(0.12)          // 暗紋
            }
        }
    }

    private var reflection: some View {
        artworkOrPlaceholder
            .scaleEffect(y: -1)              // §4.8：上下翻轉
            .frame(height: size * reflectionRatio, alignment: .top)
            .clipped()
            .mask {
                LinearGradient(
                    colors: [.white.opacity(0.45), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
    }
}
