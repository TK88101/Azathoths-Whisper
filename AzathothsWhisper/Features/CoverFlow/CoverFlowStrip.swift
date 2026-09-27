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
///
/// **可點判定（計劃 D6、N2）**：內容閉包的第二個參數 `isCentered`＝該卡的佈局中點距視口中點 ≤ 0.2 個卡寬，
/// 與疊放同一個 `onGeometryChange` 路徑算出——不用 `centerID`（捲動途中落後於畫面）、
/// 也不用四捨五入後的疊放層級（跨中點時會有一張卡被誤判為正中）。
///
/// **換歌平移（`docs/plans/2026-09-26-coverflow-follow-playback-slide.md` v5.3）**：捲動位置照舊不帶動畫；
/// 「滑過去」是內容位移（`.offset`）從一個卡距動畫歸零。凡是換牌的同一次更新要無動畫改捲動位置，
/// 那次修正有機率晚一次畫面提交才生效（該計劃 §8.3）；位移不碰捲動位置，所以不閃。
/// 位移量由輸入同步算出，與換牌在同一次更新生效；指令只在 `onChange` 一處被消費。
struct CoverFlowStrip<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let itemWidth: CGFloat
    @Binding var centerID: Item.ID?
    let slide: CoverFlowSlideRequest?
    let slideAnimation: Animation
    let onSlideSettled: (Int) -> Void
    let content: (Item, Bool) -> Content

    init(items: [Item], itemWidth: CGFloat, centerID: Binding<Item.ID?>,
         slide: CoverFlowSlideRequest? = nil, slideAnimation: Animation = Theme.Motion.layerShift,
         onSlideSettled: @escaping (Int) -> Void = { _ in },
         @ViewBuilder content: @escaping (Item, _ isCentered: Bool) -> Content) {
        self.items = items
        self.itemWidth = itemWidth
        self._centerID = centerID
        self.slide = slide
        self.slideAnimation = slideAnimation
        self.onSlideSettled = onSlideSettled
        self.content = content
    }

    /// 不需要可點判定的呼叫端（疊放／轉場的量測測試）
    init(items: [Item], itemWidth: CGFloat, centerID: Binding<Item.ID?>,
         slide: CoverFlowSlideRequest? = nil, onSlideSettled: @escaping (Int) -> Void = { _ in },
         @ViewBuilder content: @escaping (Item) -> Content) {
        self.init(items: items, itemWidth: itemWidth, centerID: centerID,
                  slide: slide, onSlideSettled: onSlideSettled) { item, _ in content(item) }
    }

    /// 位移已開始歸零的那次指令。條帶被重建時歸零，所以「出現時就帶著指令」看得出來
    @State private var releasedGeneration = 0

    private var geometry: CoverFlowGeometry {
        CoverFlowGeometry(itemWidth: itemWidth)
    }

    /// 指令剛到、還沒釋放：把整排往回推，畫面上舊當前卡仍在正中
    private var slideShift: CGFloat {
        guard let slide, slide.generation != releasedGeneration else { return 0 }
        return geometry.slideOffset(slots: slide.slots)
    }

    var body: some View {
        GeometryReader { outer in
          ScrollViewReader { reader in
            ScrollView(.horizontal) {
                // 不用 LazyHStack：前面有項目被移除時它用估算位置，明確捲回也會停在兩張之間（實測偏 119pt）。
                // 牌組至多 21 張，全數具現的成本可接受
                HStack(spacing: geometry.spacing) {
                    ForEach(items) { item in
                        CoverFlowStripCell(
                            geometry: geometry,
                            viewportMidX: outer.frame(in: .named(coverFlowViewportSpace)).midX,
                            shift: slideShift
                        ) { isCentered in
                            content(item, isCentered)
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
                // 撐滿捲動區高度、卡片垂直置中（LazyHStack 原本如此；HStack 只取內容高度、貼在頂端——
                // 卡片上緣被把手切掉、點擊判定區也對不上，2026-09-24 UITest 截圖）
                .frame(maxHeight: .infinity)
                .scrollTargetLayout()
                .offset(x: slideShift)
            }
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(.horizontal, geometry.edgePadding(viewWidth: outer.size.width))
            .scrollPosition(id: $centerID, anchor: .center)
            .scrollIndicators(.hidden)
            // 牌組換了而正中的卡沒變（履歴晚到、播完的歌由佇列卡換成履歴卡、窗口滑動）：scrollPosition 的值沒變就不會捲，
            // SwiftUI 保住的是數值位移而非 center 錨點——條帶停歪、正中那張被鄰張蓋住（2026-09-24 使用者實機）。
            // 內容一變就明確捲回正中那張，不帶動畫（`CoverFlowDeckSideChangeTests`）。
            // 卡 ID 序列與平移指令併成一個觀察值：兩者常在同一次更新一起變，順序由這裡決定
            .onChange(of: CoverFlowStripInput(ids: items.map(\.id), slide: slide), initial: true) { old, new in
                if let request = new.slide, request.generation != releasedGeneration {
                    consume(request, isInitial: old == new, reader: reader)
                    return
                }
                guard new.ids != old.ids, let centerID else { return }
                reader.scrollTo(centerID, anchor: .center)
            }
          }
        }
        .coordinateSpace(.named(coverFlowViewportSpace))
    }

    /// 還沒釋放的指令只在這裡處理一次
    private func consume(_ request: CoverFlowSlideRequest, isInitial: Bool, reader: ScrollViewProxy) {
        guard !isInitial else {
            // 條帶出現時就帶著指令＝被重建：`onChange` 不會再為它觸發，不處理的話位移會卡在一個卡距上。
            // 已釋放的指令不會走到這裡（條帶只是重新出現時 `@State` 還在），動畫照常由自己落定
            releasedGeneration = request.generation
            onSlideSettled(request.generation)
            return
        }
        if let centerID {
            reader.scrollTo(centerID, anchor: .center)
        }
        // 釋放要在「位移已套用」之後的另一次更新，才有起點可以動畫
        withAnimation(slideAnimation, completionCriteria: .logicallyComplete) {
            releasedGeneration = request.generation
        } completion: {
            onSlideSettled(request.generation)
        }
    }
}

private struct CoverFlowStripInput<ID: Hashable>: Equatable {
    let ids: [ID]
    let slide: CoverFlowSlideRequest?
}

/// 單張卡的疊放與可點判定：讀自己的**佈局位置**（與 `.visualEffect` 旋轉同一份幾何），離中心愈遠愈下沉。
/// 層級按卡位量化（`CoverFlowGeometry.stackingOrder`），捲動時只在越過兩卡中點時改值；
/// `isCentered` 只在越過 ±0.2 容差時改值——兩者都不逐幀寫狀態。
///
/// `Animatable`：換歌平移期間 SwiftUI 逐幀以內插後的 `shift` 重算 body，疊放與正中判定才跟得上畫面。
/// `shift` **只**加進這兩者：`onGeometryChange` 讀到的版面位置不含 `.offset`；
/// 旋轉／縮放走 `.visualEffect`，它的幾何本來就含 `.offset`，再加會算兩次（該計劃 §8.3 事實 6）
private struct CoverFlowStripCell<Card: View>: View, @preconcurrency Animatable {
    let geometry: CoverFlowGeometry
    let viewportMidX: CGFloat
    /// 條帶內容此刻的位移（版面位置之外、畫面上多移的量）
    var shift: CGFloat
    @ViewBuilder let card: (Bool) -> Card

    var animatableData: CGFloat {
        get { shift }
        set { shift = newValue }
    }

    @State private var placement = CoverFlowStripPlacement(stackingOrder: 0, isCentered: false)
    /// 量到自己的位置前不顯示。滑動中新具現的卡，SwiftUI 偶爾會先把它放在別張的位置、
    /// 且畫在最上層 1–3 幀（以純色卡辨識身分實測；原始代碼同樣存在，屬間歇現象）
    @State private var isPlaced = false

    var body: some View {
        card(placement.isCentered)
            .onGeometryChange(for: CoverFlowStripPlacement.self) { [geometry, viewportMidX, shift] proxy in
                let d = geometry.normalizedDistance(
                    itemMidX: proxy.frame(in: .named(coverFlowViewportSpace)).midX + shift,
                    viewportMidX: viewportMidX
                )
                return CoverFlowStripPlacement(stackingOrder: geometry.stackingOrder(forDistance: d), isCentered: geometry.isCentered(forDistance: d))
            } action: { newPlacement in
                placement = newPlacement
                isPlaced = true
            }
            .opacity(isPlaced ? 1 : 0)
            .zIndex(placement.stackingOrder)
    }
}

/// 一張卡在視口中的位置判定。放在檔案層級而非卡片視圖內：巢在泛型型別裡會讓幾何回呼捕獲泛型元型別
private struct CoverFlowStripPlacement: Equatable {
    let stackingOrder: Double
    let isCentered: Bool
}
