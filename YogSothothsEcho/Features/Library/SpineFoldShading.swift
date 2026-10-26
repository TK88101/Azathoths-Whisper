import CoreGraphics
import SwiftUI

/// 漸層的一個停點：白或黑、不透明度、距該邊（折邊或背側邊）的距離（pt）
struct FoldStop: Equatable, Sendable {
    let white: Bool
    let opacity: Double
    let distance: CGFloat
}

/// 折邊「微圓 1.5」（#6-1 第二輪 F2 ①，使用者 2026-10-22 定案；s6-61-round2.md §4 P1）：
/// 交界不是硬暗線，而是一道「亮→暗」的鼓起明暗。數值取自小樣（A＝764 pt），u＝cover／764 等比例
enum SpineFoldShading {
    static let radius: CGFloat = 1.5

    /// 正面，自折邊（左側盒＝leading）起
    static func front(u: CGFloat) -> [FoldStop] {
        let r = radius * u
        return [FoldStop(white: true, opacity: 0.18, distance: 0), FoldStop(white: true, opacity: 0.26, distance: 1.2 * r),
                FoldStop(white: false, opacity: 0.16, distance: 3.2 * r), FoldStop(white: false, opacity: 0.05, distance: 7 * r),
                FoldStop(white: false, opacity: 0, distance: 7 * r + 10 * u)]
    }

    /// 書脊折邊側，自折邊（左側盒＝trailing）起：受光的弧面
    static func spineFold(u: CGFloat) -> [FoldStop] {
        let r = radius * u
        return [FoldStop(white: true, opacity: 0.24, distance: 0), FoldStop(white: true, opacity: 0.30, distance: 1.2 * r),
                FoldStop(white: true, opacity: 0.06, distance: 3 * r), FoldStop(white: true, opacity: 0, distance: 3 * r + 3 * u)]
    }

    /// 書脊背側，自背側邊（左側盒＝leading）起
    static func spineBack(u: CGFloat) -> [FoldStop] {
        [FoldStop(white: false, opacity: 0.26, distance: 0), FoldStop(white: false, opacity: 0, distance: 2 * u + radius * u)]
    }

    /// distance／面寬，夾在 0…1
    static func locations(_ stops: [FoldStop], length: CGFloat) -> [CGFloat] {
        stops.map { min(1, max(0, $0.distance / length)) }
    }

    /// 自 `from` 那一側起算的漸層
    static func gradient(_ stops: [FoldStop], length: CGFloat, from: UnitPoint, to: UnitPoint) -> LinearGradient {
        let gradientStops = zip(stops, locations(stops, length: length)).map { stop, location in
            Gradient.Stop(color: (stop.white ? Color.white : Color.black).opacity(stop.opacity), location: location)
        }
        return LinearGradient(stops: gradientStops, startPoint: from, endPoint: to)
    }
}
