import SwiftUI

/// Cover Flow 的捲動條帶：負間距覆疊 ＋ 逐項 3D 變換 ＋ viewAligned 吸附。
///
/// 幾何全部委給 `CoverFlowGeometry`（純函數、有測試）；本視圖只做 SwiftUI 接線。
///
/// **實作限制（P1-0 spike 發現）**：`zIndex` 不能寫在 `.visualEffect` 閉包內——
/// 該閉包回傳 `VisualEffect` 而非 `View`，而 `zIndex` 是 View modifier。
/// 故拆成兩路：旋轉／縮放走 `.visualEffect`（需要連續的視口距離），
/// 疊放次序走 `scrollPosition` 追蹤到的**離散**中心索引（視覺上只需正確的前後次序）。
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
                        content(item)
                            .frame(width: itemWidth)
                            .visualEffect { effect, proxy in
                                let d = geometry.normalizedDistance(
                                    itemMidX: proxy.frame(in: .scrollView).midX,
                                    viewportMidX: outer.size.width / 2
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
                            .zIndex(stackingOrder(of: item))
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(.horizontal, geometry.edgePadding(viewWidth: outer.size.width))
            .scrollPosition(id: $centerID, anchor: .center)
            .scrollIndicators(.hidden)
        }
    }

    /// 離散疊放：距中心愈遠愈下沉。中心未定時全部同層（首次佈局的一瞬）
    private func stackingOrder(of item: Item) -> Double {
        guard let centerID,
              let centerIndex = items.firstIndex(where: { $0.id == centerID }),
              let index = items.firstIndex(where: { $0.id == item.id })
        else { return 0 }
        return geometry.zIndex(forDistance: CGFloat(index - centerIndex))
    }
}
