import CoreGraphics
import Foundation

/// 唱機場景版面（sprint-5-detail.md §4.2b v1.6／v1.8）：以唱片直徑 R 與唱片圓心為錨，推出封套、唱臂、底座。
/// 封套比唱片大（真實比例）、斜放（位置與角度由使用者在 Pencil 擺定），允許往左出框；
/// 全封面時唱片原地不動，封套擺正、與唱片同高、右緣對齊唱片圓心（唱片一半裝進封套）；唱片、唱臂、底座一律完整在畫面內
struct TurntableLayout: Equatable {
    typealias M = TurntableMetrics

    let container: CGRect
    let scale: CGFloat
    let record: CGRect
    /// 封套未旋轉時的正方形（旋轉與抽出位移由 CoverSleeveState 疊加）
    let cover: CGRect
    let arm: CGRect
    let armBase: CGRect
    let armPivot: CGPoint
    let fullCover: Bool
    /// 唱臂與底座的來源（S7 F-V-07）；由組裝根注入，版面、點擊判定、繪製共用這一個值
    let skin: ResolvedTurntableSkin
    /// 畫面上唱片相對 `record` 框的縮放（畫面與點擊命中共用）
    let recordVisibleScale: CGFloat

    init(container: CGRect, fullCover: Bool, skin: ResolvedTurntableSkin) {
        let r = min(M.recordHeightFraction * container.height, container.width / M.recordWidthDivisor)
        let s = r / M.recordSize
        let center = CGPoint(x: container.maxX - M.recordCenterRightInset * r, y: container.midY + M.recordCenterDrop * r)
        let record = CGRect(x: center.x - r / 2, y: center.y - r / 2, width: r, height: r)
        let side = M.sleeveToRecord * r * M.recordVisibleScale
        let coverCenter = fullCover
            ? CGPoint(x: center.x - side / 2, y: center.y)
            : CGPoint(x: center.x + M.sleeveCenterOffset.x * r, y: center.y + M.sleeveCenterOffset.y * r)
        self.container = container
        self.fullCover = fullCover
        self.skin = skin
        recordVisibleScale = M.recordVisibleScale
        scale = s
        self.record = record
        cover = CGRect(x: coverCenter.x - side / 2, y: coverCenter.y - side / 2, width: side, height: side)
        let look = skin.spec
        arm = CGRect(x: record.minX + look.armOrigin.x * s, y: record.minY + look.armOrigin.y * s,
                     width: look.arm.size.width * s, height: look.arm.size.height * s)
        armBase = CGRect(x: record.minX + look.baseOrigin.x * s, y: record.minY + look.baseOrigin.y * s,
                         width: look.base.size.width * s, height: look.base.size.height * s)
        armPivot = CGPoint(x: arm.minX + look.arm.localPivot.x * s, y: arm.minY + look.arm.localPivot.y * s)
    }

    /// G7 換層瞬間唱片與讓開後封套的最小距離（pt；Codex R4：避免抗鋸齒邊緣一閃）
    static let sleeveAsideMargin: CGFloat = 3

    /// 封套斜軸（單位向量，畫面座標 y 向下、正角順時針）：一般 −7.88°，全封面 0°
    var coverAxis: CGVector {
        let radians = CoverSleeveState.rotationDegrees(isFullCover: fullCover) * .pi / 180
        return CGVector(dx: cos(radians), dy: sin(radians))
    }

    /// 唱片圓心相對封套中心在斜軸方向（along）與法線方向（across）的分量
    private var recordFromCover: (along: CGFloat, across: CGFloat) {
        let u = coverAxis
        let dx = record.midX - cover.midX, dy = record.midY - cover.midY
        return (dx * u.dx + dy * u.dy, -dx * u.dy + dy * u.dx)
    }

    /// G7 封套讓開（v2.1 T6）：只沿自身斜軸往左平移，讓對軸點上的唱片與封套剛好相距 `sleeveAsideMargin`
    var sleeveAsideOffset: CGVector {
        let u = coverAxis
        let distance = max(cover.width / 2 + record.width * recordVisibleScale / 2 + Self.sleeveAsideMargin - recordFromCover.along, 0)
        return CGVector(dx: -u.dx * distance, dy: -u.dy * distance)
    }

    /// G7 唱片位置的左上角：唱盤／對軸點（沿法線移到封套斜軸上）／讓開後的封套內（唱片圓心對齊封套中心）
    func recordOrigin(_ slot: SwipeTransition.RecordSlot) -> CGPoint {
        switch slot {
        case .platter:
            return record.origin
        case .aligned:
            let u = coverAxis, across = recordFromCover.across
            return CGPoint(x: record.minX + u.dy * across, y: record.minY - u.dx * across)
        case .sleeve:
            let aside = sleeveAsideOffset
            return CGPoint(x: cover.midX + aside.dx - record.width / 2, y: cover.midY + aside.dy - record.height / 2)
        }
    }

    /// 唱臂轉到 `angle` 度（順時針）後的外接矩形
    func armBoundingBox(angle: Double) -> CGRect {
        Self.boundingBox(of: arm, rotatedBy: skin.armRotation(forAngle: angle), about: armPivot)
    }

    /// 封套（常態傾斜，全封面時擺正）的外接矩形
    var coverBoundingBox: CGRect {
        Self.boundingBox(of: cover, rotatedBy: CoverSleeveState.rotationDegrees(isFullCover: fullCover),
                         about: CGPoint(x: cover.midX, y: cover.midY))
    }

    static func boundingBox(of rect: CGRect, rotatedBy degrees: Double, about pivot: CGPoint) -> CGRect {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            .map { TonearmGeometry.rotate($0, about: pivot, degrees: degrees) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
