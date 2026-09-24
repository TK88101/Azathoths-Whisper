import AppKit
import ApplicationServices
import SwiftUI
import Testing

@testable import AzathothsWhisper

private let probeItemWidth: CGFloat = 260
private let probeViewSize = CGSize(width: 1192, height: 620)
private let probeItemCount = 9
private let probeAXPrefix = "cfstrip-probe-item-"

private struct ProbeCard: Identifiable, Equatable { let id: Int }

/// H-02 接線測試：把 `CoverFlowStrip` 真的渲染出來，讀**渲染後**的幾何，
/// 驗證「落在視口中心的那張必須正面朝人、且愈往兩側愈側轉」。
///
/// **為何純函數測試不夠**：`CoverFlowGeometryTests` 的 15 條釘住的是公式，
/// 而 2026-09-08 的缺陷不在公式而在**接線**——`.visualEffect` 裡
/// `proxy.frame(in: .scrollView)` 不跟隨 `safeAreaPadding` 造成的內容位移，
/// 與 `outer.size.width / 2` 失去可比性，每項的 d 整體偏移 `edgePadding / itemWidth`。
/// 公式測試對此全綠——與 D-01a 記載的假測試同型。
///
/// **為何讀 AX frame 而不是像素**（逐一實測淘汰，非推斷）：
/// - `ImageRenderer` 會求值 `.visualEffect` 閉包，但**不栅格化任何 ScrollView 內容**
///   （非 lazy 的 `HStack` 包在 `ScrollView` 裡也一樣是空圖），拿不到可比對的像素。
/// - 上螢幕之後，`CALayer.render(in:)` 與 `NSView.cacheDisplay(in:to:)` 都**丟掉 3D 變換**
///   （只畫出未變換的卡片），`CARenderer` 離屏取到全黑，`CGWindowListCreateImage`
///   已在 macOS 15 移除，`screencapture -l` 需要 Screen Recording 授權（無人值守不可行）。
/// - AX 樹回報的 frame 是**變換後四邊形的軸對齊外接矩形**：套到 clamp 上限（55° ＋
///   perspective 0.55）的卡片回報約 222.6×388.0，未旋轉的回報約 260×260。
///   這與像素同源（都是同一個 effect 的產物），且**對自家 pid 查詢不需要
///   `AXIsProcessTrusted`**（實測宿主行程 trusted=false 仍可讀全部屬性）。
///
/// **本測試不重算 d**：它只知道自己傳進去的 `itemWidth` 與自己建立的視窗矩形，
/// 其餘全部從渲染結果讀回。
///
/// **必紅的範圍（不得誇大）**：本次的座標偏移缺陷（兩端讀不同空間）與 effect 整體失效
/// ——兩者皆有雙向實測。**不包含**「座標空間的身分」：d 是兩個 x 的差，共同平移相消，
/// 故刪掉 `.coordinateSpace`（兩端仍對稱）或兩端混用原點重合的不同空間，本測試都會綠。
/// 釘住的是「兩端必須可比」這個不變式，不是空間叫什麼名字。
///
/// **失效安全**：若哪天 SwiftUI 改成用「未變換的佈局 frame」回報 AX，本測試不會靜默轉綠
/// ——那時所有卡片都是 260×260，斷言 3（最遠一張必須已側轉）立刻紅。
///
/// **不覆蓋**：旋轉的正負向與 anchor 左右。外接矩形對左右翻轉對稱，
/// 把 `rotationDegrees` 或 `anchorIsTrailing` 的符號改反本測試不會紅——該項仍屬 M8 目視。
@Suite("CoverFlowStripRenderGeometry", .serialized)
@MainActor
struct CoverFlowStripRenderGeometryTests {

    // MARK: 佈景

    /// 內容用純色矩形而非 `CoverFlowItem`：本測試釘的是 strip 的**幾何接線**，
    /// 卡片自身長相另有其測試；純色也讓 AX 元素邊界乾淨可辨。
    private struct Harness: View {
        @State private var centerID: Int?
        private let target: Int?

        init(initialCenter: Int = probeItemCount / 2, target: Int? = nil) {
            _centerID = State(initialValue: initialCenter)
            self.target = target
        }

        var body: some View {
            CoverFlowStrip(
                items: (0..<probeItemCount).map(ProbeCard.init),
                itemWidth: probeItemWidth,
                centerID: $centerID
            ) { item in
                Rectangle()
                    .fill(Color(hue: Double(item.id) / Double(probeItemCount),
                                saturation: 1, brightness: 1))
                    .frame(width: probeItemWidth, height: probeItemWidth)
                    .accessibilityElement()
                    .accessibilityIdentifier("\(probeAXPrefix)\(item.id)")
            }
            .frame(width: probeViewSize.width, height: probeViewSize.height)
            .background(Color.black)
            // 運行時變更 centerID——這是產品的主路徑（切歌／載入完成／方向鍵），
            // 與「初始值」路徑不同：後者不觸發 onChange
            .task {
                guard let target else { return }
                try? await Task.sleep(for: .milliseconds(400))
                centerID = target
            }
        }
    }

    // MARK: 讀渲染後幾何

    private struct RenderedItem {
        let index: Int
        let frame: CGRect
        /// 外接矩形的長寬比。正面朝人＝1.0；轉到 ±55°（clamp 上限）實測 ≈1.74
        var aspect: CGFloat { frame.height / frame.width }
    }

    private static func axAttribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success
        else { return nil }
        return value
    }

    private static func collect(_ element: AXUIElement, depth: Int = 0, into out: inout [RenderedItem]) {
        guard depth < 40 else { return }
        let identifier = axAttribute(element, "AXIdentifier") as? String ?? ""
        if identifier.hasPrefix(probeAXPrefix),
           let index = Int(identifier.dropFirst(probeAXPrefix.count)),
           let rawPosition = axAttribute(element, kAXPositionAttribute),
           let rawSize = axAttribute(element, kAXSizeAttribute),
           CFGetTypeID(rawPosition) == AXValueGetTypeID(),
           CFGetTypeID(rawSize) == AXValueGetTypeID() {
            var origin = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(rawPosition as! AXValue, .cgPoint, &origin)
            AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
            out.append(RenderedItem(index: index, frame: CGRect(origin: origin, size: size)))
        }
        for child in (axAttribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            collect(child, depth: depth + 1, into: &out)
        }
    }

    /// 等到渲染穩定：連兩次輪詢讀到**相同**的一組 frame 才算數。
    /// 睡固定秒數會在機器忙時讀到中間態，比等待條件更慢也更 flaky。
    private static func renderedItems(timeout: TimeInterval = 10) async -> [RenderedItem] {
        let application = AXUIElementCreateApplication(getpid())
        var previous: [RenderedItem] = []
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            var current: [RenderedItem] = []
            collect(application, into: &current)
            current.sort { $0.index < $1.index }
            let stable = current.count >= 5
                && current.count == previous.count
                && zip(current, previous).allSatisfy {
                    $0.index == $1.index && $0.frame.equalTo($1.frame)
                }
            if stable { return current }
            previous = current
        }
        return previous
    }

    /// 開一個真的上螢幕的視窗。不呼叫 `NSApp.activate(ignoringOtherApps:)`——
    /// 實測不需要，且會搶走使用者的焦點。
    private static func withRenderedStrip<T>(
        initialCenter: Int = probeItemCount / 2,
        target: Int? = nil,
        _ body: (_ viewportMidX: CGFloat, _ items: [RenderedItem]) async -> T
    ) async -> T {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: screen.midX - probeViewSize.width / 2,
            y: screen.midY - probeViewSize.height / 2
        )
        let window = NSWindow(
            contentRect: CGRect(origin: origin, size: probeViewSize),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = NSHostingView(rootView: Harness(initialCenter: initialCenter, target: target))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        let items = await renderedItems()
        let content = window.contentView!
        let viewport = window.convertToScreen(content.convert(content.bounds, to: nil))
        return await body(viewport.midX, items)
    }

    // MARK: 斷言

    @Test("視口中心的封面正面朝人，兩側依距離漸次側轉")
    func centerCoverFacesViewerAndSidesTiltAway() async throws {
        await Self.withRenderedStrip { viewportMidX, items in
            #expect(items.count >= 5, "AX 樹應讀到已渲染的封面；讀到 \(items.count) 個")
            guard items.count >= 5 else { return }

            let byDistance = items
                .map { (item: $0, distance: abs($0.frame.midX - viewportMidX)) }
                .sorted { $0.distance < $1.distance }
            let report = byDistance
                .map { String(format: "#%d Δ=%.1f %.1f×%.1f aspect=%.3f",
                              $0.item.index, $0.distance,
                              $0.item.frame.width, $0.item.frame.height, $0.item.aspect) }
                .joined(separator: "  |  ")
            print("RENDERED  vpMidX=\(viewportMidX)  \(report)")

            let center = byDistance[0]
            // 佈局本身（edgePadding ＋ viewAligned）保證有一項落在視口中心；不成立表示佈局也壞了
            #expect(
                center.distance < probeItemWidth / 2,
                "應有一張封面落在視口中心附近；最近的一張偏了 \(center.distance)px。\(report)"
            )

            // 1) 中心那張必須未旋轉：外接矩形接近正方形
            #expect(
                abs(center.item.aspect - 1) < 0.05,
                """
                視口中心的封面應正面朝人（外接矩形長寬比≈1），實測 \
                \(String(format: "%.3f", center.item.aspect))。長寬比 >1 表示它被旋轉了\
                ——距離基準與視口中心不同源（H-02 接線缺陷）。\(report)
                """
            )

            // 2) 中心那張必須是滿尺寸：scale(d=0)=1.0
            #expect(
                center.item.frame.width > probeItemWidth * 0.95,
                """
                視口中心的封面應為滿尺寸 \(probeItemWidth)pt，實測寬 \
                \(String(format: "%.1f", center.item.frame.width))。\(report)
                """
            )

            // 3) 兩側必須真的側轉——否則「effect 整個沒套上」也會通過 1) 與 2)
            let farthest = byDistance[byDistance.count - 1]
            #expect(
                farthest.item.aspect > 1.3,
                """
                離視口中心最遠的封面應已轉到 clamp 上限（長寬比 ≈1.74），實測 \
                \(String(format: "%.3f", farthest.item.aspect))——3D 變換可能整個失效。\(report)
                """
            )

            // 4) 左右等距的兩張，側轉幅度必須一致（擋左右兩側變換幅度不對稱）。
            //    配對的「存在」與「等距」本身也是斷言——寫成 if-let 條件會在配對缺失時
            //    整條靜默跳過，那正是本專案 D-01a 記載的假測試形態。
            let rest = byDistance.dropFirst()
            let left = rest.first(where: { $0.item.frame.midX < viewportMidX })
            let right = rest.first(where: { $0.item.frame.midX > viewportMidX })
            #expect(
                left != nil && right != nil,
                "中心兩側都應有已渲染的封面可供對稱比較。\(report)"
            )
            if let left, let right {
                #expect(
                    abs(left.distance - right.distance) < 20,
                    """
                    中心左右最近的兩張應等距（負間距佈局下應對稱），實測 \
                    左 \(String(format: "%.1f", left.distance))px / \
                    右 \(String(format: "%.1f", right.distance))px。\(report)
                    """
                )
                #expect(
                    abs(left.item.aspect - right.item.aspect) < 0.05,
                    """
                    中心左右等距的兩張封面側轉幅度應對稱，實測 \
                    左 \(String(format: "%.3f", left.item.aspect)) / \
                    右 \(String(format: "%.3f", right.item.aspect))。\(report)
                    """
                )
            }

            // 5) 愈遠離視口中心，側轉愈明顯（不得回頭）
            let aspects = byDistance.map(\.item.aspect)
            let monotonic = zip(aspects, aspects.dropFirst()).allSatisfy { $1 >= $0 - 0.05 }
            #expect(
                monotonic,
                "側轉幅度應隨離視口中心的距離單調遞增，實測非單調。\(report)"
            )
        }
    }

    /// 首項／末項也必須能吸附到視口中心並正面朝人。
    ///
    /// **為何單獨測首尾**：`edgePadding` 存在的唯一理由就是讓首尾可達中心。
    /// 中段項居中不能推出首尾也居中——邊距算錯時，中段靠 viewAligned 吸附照樣正確，
    /// 只有首尾會偏。2026-09-09 目視複驗中「最右側項位置異常」即由本測試分類：
    /// 若本測試綠，該現象就不是佈局缺陷，而是疊放次序造成的視覺假象。
    @Test("首項與末項吸附後同樣正面朝人", arguments: [0, 1, 4, 5, 6, 7, probeItemCount - 1])
    func edgeItemsAlsoReachCenter(initialCenter: Int) async throws {
        await Self.withRenderedStrip(initialCenter: initialCenter) { viewportMidX, items in
            #expect(items.count >= 5, "AX 樹應讀到已渲染的封面；讀到 \(items.count) 個")
            guard items.count >= 5 else { return }

            let byDistance = items
                .map { (item: $0, distance: abs($0.frame.midX - viewportMidX)) }
                .sorted { $0.distance < $1.distance }
            let report = byDistance
                .map { String(format: "#%d d=%.1f aspect=%.3f", $0.item.index, $0.distance, $0.item.aspect) }
                .joined(separator: "  |  ")
            print("EDGE(\(initialCenter))  vpMidX=\(viewportMidX)  \(report)")

            let center = byDistance[0]
            #expect(
                center.item.index == initialCenter,
                "初始中心設為 #\(initialCenter)，但離視口中心最近的是 #\(center.item.index)——首尾未能抵達中心。\(report)"
            )
            #expect(
                abs(center.item.aspect - 1) < 0.05,
                "第 \(initialCenter) 項吸附後應正面朝人，實測長寬比 \(center.item.aspect)。\(report)"
            )
            #expect(
                center.item.frame.width > probeItemWidth * 0.95,
                "第 \(initialCenter) 項吸附後應為滿尺寸，實測寬 \(center.item.frame.width)。\(report)"
            )
        }
    }

    /// **command 路徑**：運行時變更 centerID 後，目標項必須抵達視口中心。
    ///
    /// 這是產品的主路徑（切歌自動居中 H-04、方向鍵步進 H-09、載入完成後定位），
    /// 與 `edgeItemsAlsoReachCenter` 測的「初始值」路徑是兩條不同的 SwiftUI 代碼路徑：
    /// 初始值不觸發 `onChange`，因此不走 `ScrollViewReader.scrollTo`。
    @Test("運行時變更 centerID 後目標項抵達中心", arguments: [1, 4, 8])
    func runtimeCenterChangeReachesTarget(target: Int) async throws {
        await Self.withRenderedStrip(initialCenter: 0, target: target) { viewportMidX, items in
            #expect(items.count >= 5, "AX 樹應讀到已渲染的封面；讀到 \(items.count) 個")
            guard items.count >= 5 else { return }

            let byDistance = items
                .map { (item: $0, distance: abs($0.frame.midX - viewportMidX)) }
                .sorted { $0.distance < $1.distance }
            let report = byDistance
                .map { String(format: "#%d d=%.1f aspect=%.3f", $0.item.index, $0.distance, $0.item.aspect) }
                .joined(separator: "  |  ")
            print("RUNTIME(0->\(target))  \(report)")

            let center = byDistance[0]
            #expect(
                center.item.index == target,
                "centerID 改為 #\(target) 後，最接近視口中心的應是它，實測 #\(center.item.index)。\(report)"
            )
            #expect(
                abs(center.item.aspect - 1) < 0.05,
                "目標項應正面朝人，實測長寬比 \(center.item.aspect)。\(report)"
            )
        }
    }
}
