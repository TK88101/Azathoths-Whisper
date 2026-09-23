import SwiftUI

/// 條帶自己宣告的座標空間名。
///
/// **為何不能用 `.scrollView`**：`.scrollView` 不跟隨 `safeAreaPadding` 造成的內容位移，
/// 與外層 `GeometryReader` 的尺寸失去可比性，兩端相減得到的 d 會整體偏移
/// `edgePadding / itemWidth`（1192pt 視口、260pt 卡片時實測 1.792），
/// 超過 clamp 邊界導致中心那張也吃滿斜角。修法＝距離的兩端讀**同一個**空間。
private let coverFlowViewportSpace = "coverflow.viewport"

/// Cover Flow 的捲動條帶：負間距覆疊 ＋ 逐項 3D 變換 ＋ viewAligned 吸附。
///
/// 幾何全部委給 `CoverFlowGeometry`（純函數、有測試）；本視圖只做 SwiftUI 接線。
///
/// **實作限制（P1-0 spike 發現）**：`zIndex` 不能寫在 `.visualEffect` 閉包內——
/// 該閉包回傳 `VisualEffect` 而非 `View`，而 `zIndex` 是 View modifier。
/// 故拆成兩路：旋轉／縮放走 `.visualEffect`（需要連續的視口距離），
/// 疊放次序由每張卡自己的佈局位置決定（`CoverFlowStripCell`）。
///
/// **疊放不得跟 `centerID` 走（H-02 缺陷 2）**：`centerID` 是「選中哪張」，
/// 與「畫面上哪張在正中」不同步——捲動途中它落後於畫面，初始值路徑還會整個對不上
/// ——這時歪斜的鄰張就壓在正中那張上面。疊放與旋轉必須讀同一份佈局幾何。
struct CoverFlowStrip<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let itemWidth: CGFloat
    @Binding var centerID: Item.ID?
    let content: (Item) -> Content

    private var geometry: CoverFlowGeometry {
        CoverFlowGeometry(itemWidth: itemWidth)
    }

    var body: some View {
        GeometryReader { outer in
            ScrollView(.horizontal) {
                LazyHStack(spacing: geometry.spacing) {
                    ForEach(items) { item in
                        CoverFlowStripCell(
                            geometry: geometry,
                            viewportMidX: outer.frame(in: .named(coverFlowViewportSpace)).midX
                        ) {
                            content(item)
                                .frame(width: itemWidth)
                                .visualEffect { effect, proxy in
                                    let d = geometry.normalizedDistance(
                                        itemMidX: proxy.frame(in: .named(coverFlowViewportSpace)).midX,
                                        viewportMidX: outer.frame(in: .named(coverFlowViewportSpace)).midX
                                    )
                                    return effect
                                        .rotation3DEffect(
                                            .degrees(geometry.rotationDegrees(forDistance: d)),
                                            axis: (x: 0, y: 1, z: 0),
                                            anchor: geometry.anchorIsTrailing(forDistance: d)
                                                ? .trailing : .leading,
                                            perspective: geometry.perspective
                                        )
                                        .scaleEffect(geometry.scale(forDistance: d))
                                }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(.horizontal, geometry.edgePadding(viewWidth: outer.size.width))
            .scrollPosition(id: $centerID, anchor: .center)
            .scrollIndicators(.hidden)
        }
        .coordinateSpace(.named(coverFlowViewportSpace))
    }
}

/// 單張卡的疊放：讀自己的**佈局位置**（與 `.visualEffect` 旋轉同一份幾何），離中心愈遠愈下沉。
/// 層級按卡位量化（`CoverFlowGeometry.stackingOrder`），捲動時只在越過兩卡中點時改值。
private struct CoverFlowStripCell<Card: View>: View {
    let geometry: CoverFlowGeometry
    let viewportMidX: CGFloat
    @ViewBuilder let card: Card

    @State private var stackingOrder: Double = 0
    /// 量到自己的位置前不顯示。滑動中新具現的卡，SwiftUI 偶爾會先把它放在別張的位置、
    /// 且畫在最上層 1–3 幀（以純色卡辨識身分實測；原始代碼同樣存在，屬間歇現象）
    @State private var isPlaced = false

    var body: some View {
        card
            .onGeometryChange(for: Double.self) { [geometry, viewportMidX] proxy in
                geometry.stackingOrder(forDistance: geometry.normalizedDistance(
                    itemMidX: proxy.frame(in: .named(coverFlowViewportSpace)).midX,
                    viewportMidX: viewportMidX
                ))
            } action: { order in
                stackingOrder = order
                isPlaced = true
            }
            .opacity(isPlaced ? 1 : 0)
            .zIndex(stackingOrder)
    }
}
