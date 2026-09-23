import AppKit
import QuartzCore

// Cover Flow 條帶的層樹讀取器（由 CoverFlowStripStackingTests 抽出，供疊放與牌組轉場測試共用）。
// 讀 CALayer 而非 AX：in-process 讀 AX 會讓 LazyHStack 多具現一張卡、改變捲動落點（fix4 §13 F-AX）。

// MARK: - 讀層樹

struct StackFrame {
    /// 佈局 midX（contentView 層座標）與在父層 `sublayers` 中的次序（大＝在上）
    let cards: [(midX: CGFloat, order: Int)]
    let viewportMidX: CGFloat
    /// NSScrollView 的捲動原點 x（只用來確認條帶真的捲動了）
    var scrollX: CGFloat?

    private var byPosition: [(midX: CGFloat, order: Int)] { cards.sorted { $0.midX < $1.midX } }

    private var centerPosition: Int {
        let sorted = byPosition
        return sorted.indices.min {
            abs(sorted[$0].midX - viewportMidX) < abs(sorted[$1].midX - viewportMidX)
        } ?? 0
    }

    /// 正中那張的次序高於左右緊鄰者（首尾只比存在的一側）
    var centerIsOnTop: Bool {
        let sorted = byPosition
        let g = centerPosition
        let neighbours = [g - 1, g + 1].filter(sorted.indices.contains)
        return neighbours.allSatisfy { sorted[$0].order < sorted[g].order }
    }

    var signature: String {
        byPosition.map { "\(Int($0.midX.rounded())):\($0.order)" }.joined(separator: ",")
    }

    var report: String {
        let sorted = byPosition
        let g = centerPosition
        return "vpMidX=\(Int(viewportMidX)) " + sorted.enumerated().map { i, card in
            (i == g ? "[G]" : "") + "x=\(Int(card.midX.rounded()))/z\(card.order)"
        }.joined(separator: " ")
    }
}

@MainActor
enum StackReader {
    static func read(_ window: NSWindow, itemWidth: CGFloat = 260) -> StackFrame? {
        guard let root = window.contentView?.layer else { return nil }
        var all: [CALayer] = []
        collect(root, depth: 0, into: &all)
        let candidates = all.filter { abs($0.bounds.width - itemWidth) < 0.5 && $0.bounds.height > 100 }
        let refs = Set(candidates.map(ObjectIdentifier.init))
        // 卡層＝候選中最外層者（product 卡每張 3 層，只取帶變換的那層）
        let cardLayers = candidates.filter { layer in
            // 看不見的層蓋不住任何東西
            guard !layer.isHidden, (layer.presentation()?.opacity ?? layer.opacity) > 0.01 else { return false }
            var ancestor = layer.superlayer
            while let a = ancestor {
                if refs.contains(ObjectIdentifier(a)) { return false }
                ancestor = a.superlayer
            }
            return true
        }
        let parents = Set(cardLayers.compactMap { $0.superlayer.map(ObjectIdentifier.init) })
        guard parents.count == 1, let siblings = cardLayers.first?.superlayer?.sublayers else { return nil }
        let cards = cardLayers.compactMap { layer -> (midX: CGFloat, order: Int)? in
            guard let order = siblings.firstIndex(where: { $0 === layer }) else { return nil }
            return (layoutMidX(layer, in: root), order)
        }
        var frame = StackFrame(cards: cards, viewportMidX: root.bounds.midX)
        frame.scrollX = window.contentView.flatMap(scrollView(in:))?.contentView.bounds.origin.x
        return frame
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        return view.subviews.lazy.compactMap(scrollView(in:)).first
    }

    private static func collect(_ layer: CALayer, depth: Int, into out: inout [CALayer]) {
        guard depth < 40 else { return }
        out.append(layer)
        for sub in layer.sublayers ?? [] { collect(sub, depth: depth + 1, into: &out) }
    }

    /// 卡層 position／anchor 皆為 (0,0)，平移烘進 transform。旋轉軸那條豎邊 z＝0 → 齊次 w＝1、
    /// 不受透視影響；其長度＝scale×h（scale 以卡中心為錨）→ 佈局 midX＝軸邊 x＋scale×(w/2 − 軸 x)。
    private static func layoutMidX(_ layer: CALayer, in root: CALayer) -> CGFloat {
        let t = layer.transform
        let b = layer.bounds
        let yMid = b.height / 2
        let wLeading = yMid * t.m24 + t.m44
        let wTrailing = b.width * t.m14 + yMid * t.m24 + t.m44
        let axisX: CGFloat = abs(wLeading - 1) <= abs(wTrailing - 1) ? 0 : b.width
        let top = root.convert(CGPoint(x: b.minX + axisX, y: b.minY), from: layer)
        let bottom = root.convert(CGPoint(x: b.minX + axisX, y: b.maxY), from: layer)
        let scale = abs(bottom.y - top.y) / b.height
        return (top.x + bottom.x) / 2 + scale * (b.width / 2 - axisX)
    }
}
