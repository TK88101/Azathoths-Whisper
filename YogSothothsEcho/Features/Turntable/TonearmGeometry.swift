import CoreGraphics
import Foundation

/// 唱臂的幾何工具（sprint-5-detail.md §4.3）。角度↔進度在 `ResolvedTurntableSkin`（S7：起止角屬於皮膚）
/// 角度單位是度，順時針（向唱片內擺）為正；座標是畫面座標（y 向下）
enum TonearmGeometry {
    /// 繞 `pivot` 順時針轉 `degrees` 度（畫面座標；TurntableLayout 算唱臂旋轉外接框用）
    static func rotate(_ point: CGPoint, about pivot: CGPoint, degrees: Double) -> CGPoint {
        let rad = degrees * .pi / 180
        let dx = Double(point.x - pivot.x), dy = Double(point.y - pivot.y)
        return CGPoint(x: Double(pivot.x) + dx * cos(rad) - dy * sin(rad), y: Double(pivot.y) + dx * sin(rad) + dy * cos(rad))
    }
}
