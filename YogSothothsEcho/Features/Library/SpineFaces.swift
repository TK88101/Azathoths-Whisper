import RemoteProtocol
import SwiftUI
import UIKit

// 方盒兩面的畫面（#6-1 使用者選定 s6-spine-preview.html 樣式 5「印刷＋覆膜」）。內容不依 pose：捲動中每幀只更新投影矩陣。
// 疊層以「左側盒」方向寫（書脊在封面左緣：書脊的折邊在右、封面的折邊在左），右側盒水平鏡像；字不鏡像。
// 數值取自小樣（A＝764 pt 時的 px），按 A／書脊厚等比例

/// 正面：封面＋靠書脊那側的折邊明暗（微圓）＋極淡斜向光澤＋紙纖維＋磨損
struct CoverFace: View, Equatable {
    let album: AlbumSummary
    let image: UIImage?
    let length: CGFloat
    let side: CarouselSide

    /// 圖以實例比較（同一張就是同一個物件），不走 UIImage.isEqual
    nonisolated static func == (a: CoverFace, b: CoverFace) -> Bool {
        a.album == b.album && a.image === b.image && a.length == b.length && a.side == b.side
    }

    var body: some View {
        let u = length / SpineCarouselMetrics.referenceCover
        AlbumCoverImage(album: album, image: image)
            .frame(width: length, height: length)
            .overlay {
                ZStack {
                    // 折邊「微圓 1.5」：亮→暗的鼓起明暗（#6-1 第二輪 F2 ①）
                    SpineFoldShading.gradient(SpineFoldShading.front(u: u), length: length, from: .leading, to: .trailing)
                    // 斜向覆膜光澤＋上亮下暗
                    LinearGradient(stops: [.init(color: .clear, location: 0.30), .init(color: .white.opacity(0.10), location: 0.44),
                                           .init(color: .clear, location: 0.58)],
                                   startPoint: UnitPoint(x: 0, y: 0.23), endPoint: UnitPoint(x: 1, y: 0.77))
                    LinearGradient(stops: [.init(color: .white.opacity(0.04), location: 0), .init(color: .clear, location: 0.30),
                                           .init(color: .clear, location: 0.75), .init(color: .black.opacity(0.08), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .scaleEffect(x: side == .left ? 1 : -1)
                .allowsHitTesting(false)
            }
            // 紙纖維與磨損不鏡像：同一張專輯換邊時磨損位置不變（F2 ④⑤）
            // 紙纖維、邊緣磨白、磨損：一張預先畫好的點陣（FaceTexture；CPU 平鋪改 GPU 貼圖）
            .overlay { FaceTextureView(key: .front(albumID: album.id, length: length)) }
            // 折邊兩角挖掉與書脊同一組缺口，兩面在折邊處接齊（G2 接縫 A′；使用者 2026-10-23 實機否定只改書脊）
            .mask {
                FrontFoldMask(albumID: album.id, thickness: length * SpineCarouselMetrics.spineToCover, side: side)
            }
    }
}

/// 書脊：整面在背景烘成一張點陣（`SpineBake`：包覆條、弧度、紙紋、折邊明暗、覆膜、泛白磨損、不規則剪影、字），這裡只貼圖。
/// 實機 n03-b（2026-10-23）：舊版每張新盒子在主執行緒量字排版、算邊條亮度、疊 6 層漸層＋3 張紋理，是快甩時長幀的來源
struct SpineFace: View, Equatable {
    let album: AlbumSummary
    let image: UIImage?
    let cover: CGFloat
    let thickness: CGFloat
    let side: CarouselSide
    @Environment(\.displayScale) private var displayScale

    nonisolated static func == (a: SpineFace, b: SpineFace) -> Bool {
        a.album == b.album && a.image === b.image && a.cover == b.cover && a.thickness == b.thickness && a.side == b.side
    }

    var body: some View {
        SpineBakeView(input: SpineBake.input(album: album, image: image, side: side, thickness: thickness, cover: cover, scale: displayScale))
            .frame(width: thickness, height: cover)
    }
}

/// 正面遮罩（G2 接縫，s6-61-g-perf-wear.md 附錄 C）：正面靠折邊的上下緣接續書脊端面的內縮——在折邊處與書脊等高，
/// 往正面內側逐漸收回到 0；再挖掉書脊折邊兩角的同一組缺口。展開成平面時書脊在正面的折邊外側：
/// 左側盒 x_正面＝x_書脊 − 書脊厚；右側盒（書脊鏡像）x_正面＝A＋書脊厚 − x_書脊
struct FrontFoldMask: Shape {
    let albumID: String
    let thickness: CGFloat
    let side: CarouselSide

    /// 收回距離＝折邊處內縮的倍數＋缺口半徑（u＝1 的 pt）
    static let taperFactor: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let size = CGSize(width: thickness, height: rect.height)
        let shape = SpineWear.shape(albumID: albumID), seed = SpineWear.seed(albumID: albumID)
        let u = size.height / SpineCarouselMetrics.referenceCover, p = SpineBakeOutline.profile(shape, u: u)
        let chips = SpineBakeOutline.cornerChips(albumID: albumID, shape: shape, size: size)
        let toFront = side == .left
            ? CGAffineTransform(translationX: rect.minX - thickness, y: rect.minY)
            : CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.maxX + thickness, ty: rect.minY)
        // 逐塊挖（不先疊成一條路徑：缺口與收回帶繞向不同，疊起來的重疊處會互相抵消）
        var cuts = [chips[1], chips[3]]
        for end in 0..<2 {
            // 書脊座標裡 x 由折邊（w）往外延伸＝正面由折邊往內
            let reach = Self.taperFactor * p.ends[end] + p.cornerRadius
            let xs = Array(stride(from: 0, through: reach, by: 0.5 * u)) + [reach]
            let curve = xs.map { d -> CGPoint in
                let t = 1 - d / reach
                let inset = SpineBakeOutline.endInset(p, end: end, x: thickness + d, width: thickness, seed: seed) * t * t
                return CGPoint(x: thickness + d, y: end == 0 ? inset : size.height - inset)
            }
            let edgeY: CGFloat = end == 0 ? -1 : size.height + 1
            var band = Path()
            band.addLines([CGPoint(x: thickness, y: edgeY)] + curve + [CGPoint(x: thickness + reach, y: edgeY)])
            band.closeSubpath()
            cuts.append(band)
        }
        return cuts.reduce(Path(rect)) { $0.subtracting($1.applying(toFront)) }
    }
}

/// 距邊緣 [from, to) 的條帶（左右兩側，或四邊）
struct EdgeBands: Shape {
    let from: CGFloat, to: CGFloat
    let allSides: Bool

    func path(in rect: CGRect) -> Path {
        let depth = max(0, min(to, rect.width / 2, rect.height / 2) - from)
        var path = Path()
        guard depth > 0 else { return path }
        path.addRect(CGRect(x: rect.minX + from, y: rect.minY, width: depth, height: rect.height))
        path.addRect(CGRect(x: rect.maxX - from - depth, y: rect.minY, width: depth, height: rect.height))
        if allSides {
            path.addRect(CGRect(x: rect.minX, y: rect.minY + from, width: rect.width, height: depth))
            path.addRect(CGRect(x: rect.minX, y: rect.maxY - from - depth, width: rect.width, height: depth))
        }
        return path
    }
}
