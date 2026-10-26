import CoreGraphics
import Foundation
import RemoteProtocol

/// 唱機皮膚（F-V-07 框架；sprint-7-detail.md §4.2、§4.3）。「規格」可由程式常數（classic）或素材 manifest（CR-034）產生，
/// 一律經 `TurntableSkinResolver.resolve` 驗證並求出起止角，UI 只接受 `ResolvedTurntableSkin`。
/// 座標單位是唱片框的 u（474 u＝唱片直徑）；角度是畫面絕對角（0＝臂管朝畫面正下方、順時針為正）
struct TurntableSkin: Sendable, Equatable {
    let id: String
    let kinematics: TonearmKinematics
    /// 轉動部件（配重＋臂管＋唱頭）的畫框
    let arm: ArtworkFrame
    /// 固定部件（底座）的畫框
    let base: ArtworkFrame
    let hitShape: HitShape
    let rendering: Rendering

    enum HitShape: Sendable, Equatable {
        /// 臂管＝畫布支點 x 為中線、半寬 `halfWidth` 的細條；唱頭區＝畫框內 y 在 headTop…headBottom 的整列（皆為畫框內 u）
        case tubeStrip(halfWidth: CGFloat, headTop: CGFloat, headBottom: CGFloat)
    }

    enum Rendering: Sendable, Equatable {
        /// 原版 MD Vinyl 的兩張本機 PNG，缺素材時畫後備圖形
        case classicImages
    }

    /// 畫框左上（唱片框座標）＝支點 − 畫布支點；classic 與素材序列圖共用這一個公式
    var armOrigin: CGPoint { origin(of: arm) }
    var baseOrigin: CGPoint { origin(of: base) }

    private func origin(of frame: ArtworkFrame) -> CGPoint {
        CGPoint(x: kinematics.pivot.x - frame.localPivot.x, y: kinematics.pivot.y - frame.localPivot.y)
    }

    func replacing(kinematics: TonearmKinematics) -> TurntableSkin {
        TurntableSkin(id: id, kinematics: kinematics, arm: arm, base: base, hitShape: hitShape, rendering: rendering)
    }

    func replacing(arm: ArtworkFrame) -> TurntableSkin {
        TurntableSkin(id: id, kinematics: kinematics, arm: arm, base: base, hitShape: hitShape, rendering: rendering)
    }

    func replacing(base: ArtworkFrame) -> TurntableSkin {
        TurntableSkin(id: id, kinematics: kinematics, arm: arm, base: base, hitShape: hitShape, rendering: rendering)
    }
}

struct TonearmKinematics: Sendable, Equatable {
    /// 唱片框座標（u）
    let pivot: CGPoint
    /// 素材畫成 rest 姿態時，針尖相對支點（u）
    let stylusAtRest: CGVector
    /// 素材 rest 姿態的畫面絕對角
    let restDegrees: Double
    /// 落針點、播完點距唱片圓心（u）
    let leadInRadius: CGFloat
    let runOutRadius: CGFloat
    /// 規格已明定起止角的唱臂（原版 VINYL_SPEC 14.1°＋19.3°）：求解只當驗算（差 ≤ 0.05° 才收），實際採用宣告值，
    /// 讓既有的精確相等不被浮點誤差改動。nil＝以兩個半徑求解
    let declaredTravel: DeclaredTravel?

    struct DeclaredTravel: Sendable, Equatable {
        let startDegrees: Double
        let sweepDegrees: Double
    }

    init(pivot: CGPoint, stylusAtRest: CGVector, restDegrees: Double, leadInRadius: CGFloat, runOutRadius: CGFloat,
         declaredTravel: DeclaredTravel? = nil) {
        self.pivot = pivot
        self.stylusAtRest = stylusAtRest
        self.restDegrees = restDegrees
        self.leadInRadius = leadInRadius
        self.runOutRadius = runOutRadius
        self.declaredTravel = declaredTravel
    }

    func replacing(leadInRadius: CGFloat) -> TonearmKinematics {
        TonearmKinematics(pivot: pivot, stylusAtRest: stylusAtRest, restDegrees: restDegrees,
                          leadInRadius: leadInRadius, runOutRadius: runOutRadius, declaredTravel: declaredTravel)
    }

    func replacing(runOutRadius: CGFloat) -> TonearmKinematics {
        TonearmKinematics(pivot: pivot, stylusAtRest: stylusAtRest, restDegrees: restDegrees,
                          leadInRadius: leadInRadius, runOutRadius: runOutRadius, declaredTravel: declaredTravel)
    }
}

/// 素材畫布在 u 下的尺寸，與畫布內的支點
struct ArtworkFrame: Sendable, Equatable {
    let size: CGSize
    let localPivot: CGPoint

    /// 畫布支點在畫框內的比例（旋轉錨點；classic＝原版的 armPivotFraction）
    var pivotFraction: CGPoint { CGPoint(x: localPivot.x / size.width, y: localPivot.y / size.height) }
}

struct ResolvedTurntableSkin: Sendable, Equatable {
    let spec: TurntableSkin
    let startDegrees: Double
    let sweepDegrees: Double

    var endDegrees: Double { startDegrees + sweepDegrees }
    var restDegrees: Double { spec.kinematics.restDegrees }

    /// 畫面絕對角 → rest 姿態的素材要轉幾度。版面外接框、點擊判定、繪製都只經這裡（同一語義只一處定義）
    func armRotation(forAngle angle: Double) -> Double { angle - restDegrees }

    // 唱臂角度 ↔ 播放進度（sprint-5-detail.md §4.3；spec「唱臂角度 ↔ 播放進度」）。唱機不提供拖唱頭（CR-019），唱臂只隨進度

    func angle(progress: Double) -> Double {
        startDegrees + sweepDegrees * min(max(progress, 0), 1)
    }

    func progress(angle: Double) -> Double {
        min(max((angle - startDegrees) / sweepDegrees, 0), 1)
    }

    /// 播放中跟進度走；暫停、停止或沒有長度＝抬臂靜止
    func playbackAngle(state: PlaybackState, position: Double, duration: Double?) -> Double {
        guard state == .playing, let duration, duration > 0 else { return restDegrees }
        return angle(progress: position / duration)
    }

    /// 原版唱臂；解不出是開發錯誤（單測守），不悄悄落回
    static let classic: ResolvedTurntableSkin = {
        switch TurntableSkinResolver.resolve(.classic) {
        case .success(let resolved): return resolved
        case .failure(let error): preconditionFailure("classic 皮膚解不出：\(error)")
        }
    }()
}

enum SkinError: Error, Equatable {
    case nonFinite, zeroStylus, nonPositiveRadius, invalidFrame, pivotOutsideFrame, noLeadIn, noRunOut, runOutBeforeLeadIn
    /// 宣告的起止角與求解差超過容許值（`declaredTravelTolerance`）
    case declaredTravelMismatch
    /// 點擊外形的數值非有限、為負、上下界顛倒或超出臂框
    case invalidHitShape
}

enum TurntableSkinResolver {
    /// 唯一入口：先驗輸入，再以唱片圓心（recordSize／2）求起止角
    static func resolve(_ skin: TurntableSkin, recordSize: CGFloat = TurntableMetrics.recordSize) -> Result<ResolvedTurntableSkin, SkinError> {
        if let error = invalidity(of: skin) { return .failure(error) }
        let k = skin.kinematics
        let center = CGPoint(x: recordSize / 2, y: recordSize / 2)
        guard let start = TonearmSolver.angle(k, reachingRadius: k.leadInRadius, around: center) else { return .failure(.noLeadIn) }
        guard let end = TonearmSolver.angle(k, reachingRadius: k.runOutRadius, around: center) else { return .failure(.noRunOut) }
        guard end > start else { return .failure(.runOutBeforeLeadIn) }
        guard let declared = k.declaredTravel else {
            return .success(ResolvedTurntableSkin(spec: skin, startDegrees: start, sweepDegrees: end - start))
        }
        let declaredEnd = declared.startDegrees + declared.sweepDegrees
        guard abs(start - declared.startDegrees) <= declaredTravelTolerance, abs(end - declaredEnd) <= declaredTravelTolerance else {
            return .failure(.declaredTravelMismatch)
        }
        return .success(ResolvedTurntableSkin(spec: skin, startDegrees: declared.startDegrees, sweepDegrees: declared.sweepDegrees))
    }

    /// 半徑取 0.1 u 精度時角度誤差 ≤ 0.026°（sprint-7-detail.md 附錄 B）
    static let declaredTravelTolerance = 0.05

    private static func invalidity(of skin: TurntableSkin) -> SkinError? {
        let k = skin.kinematics
        let travel = k.declaredTravel.map { [CGFloat($0.startDegrees), CGFloat($0.sweepDegrees)] } ?? []
        let numbers: [CGFloat] = [k.pivot.x, k.pivot.y, k.stylusAtRest.dx, k.stylusAtRest.dy, CGFloat(k.restDegrees),
                                  k.leadInRadius, k.runOutRadius] + travel + [skin.arm, skin.base].flatMap {
            [$0.size.width, $0.size.height, $0.localPivot.x, $0.localPivot.y]
        }
        if numbers.contains(where: { !$0.isFinite }) { return .nonFinite }
        if hypot(k.stylusAtRest.dx, k.stylusAtRest.dy) <= 0 { return .zeroStylus }
        if k.leadInRadius <= 0 || k.runOutRadius <= 0 { return .nonPositiveRadius }
        let frames = [skin.arm, skin.base]
        if frames.contains(where: { $0.size.width <= 0 || $0.size.height <= 0 }) { return .invalidFrame }
        let inside = frames.allSatisfy { f in
            (0...f.size.width).contains(f.localPivot.x) && (0...f.size.height).contains(f.localPivot.y)
        }
        guard inside else { return .pivotOutsideFrame }
        switch skin.hitShape {
        case .tubeStrip(let halfWidth, let headTop, let headBottom):
            let valid = [halfWidth, headTop, headBottom].allSatisfy(\.isFinite) && halfWidth >= 0
                && 0 <= headTop && headTop <= headBottom && headBottom <= skin.arm.size.height
            return valid ? nil : .invalidHitShape
        }
    }
}

/// 針尖軌跡＝以支點為圓心、半徑＝|stylusAtRest| 的圓（純函式）
enum TonearmSolver {
    /// 比 1 差不到這麼多就當相切（只有一點＝不可用）
    private static let tangencyMargin = 1e-12

    /// 針尖到唱片圓心距離＝`radius` 的角度：兩圓交點中、從 rest 順時針轉過去先碰到的那個（rest 之後 180° 內）
    static func angle(_ k: TonearmKinematics, reachingRadius radius: CGFloat, around center: CGPoint) -> Double? {
        let v = k.stylusAtRest
        let d = CGVector(dx: center.x - k.pivot.x, dy: center.y - k.pivot.y)
        let length = Double(hypot(v.dx, v.dy)), span = Double(hypot(d.dx, d.dy))
        guard span > 0 else { return nil }
        let cosine = (length * length + span * span - Double(radius * radius)) / (2 * length * span)
        guard abs(cosine) < 1 - tangencyMargin else { return nil }
        let base = atan2(Double(d.dy), Double(d.dx)) - atan2(Double(v.dy), Double(v.dx))
        let spread = acos(cosine)
        let turns = [base + spread, base - spread].map { normalized($0 * 180 / .pi) }.filter { $0 > 0 && $0 < 180 }
        return turns.min().map { k.restDegrees + $0 }
    }

    private static func normalized(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}

extension TurntableSkin {
    /// 原版 MD Vinyl 唱臂（sprint-5-detail.md §4.2；VINYL_SPEC「尺寸常量」「唱臂角度」；數值逐一照搬，不改）。
    /// 支點與畫布支點由原版的臂框左上＋支點比例推出，讓「畫框左上＝支點 − 畫布支點」在浮點上回到原框；
    /// 起止角照規格宣告（14.1°＋19.3°）；落針／播完半徑取 0.1 u 精度的量測值（附錄 B），求解與宣告角互相驗算（≤ 0.05°）
    static let classic: TurntableSkin = {
        /// 臂框左上：x＝原版組寬 891.2 − 臂寬 106 − 唱片 x 379.2；底座與臂同 x、上緣 11
        let armOrigin = CGPoint(x: 406, y: 24), baseTop: CGFloat = 11
        let armSize = CGSize(width: 106, height: 457), baseSize = CGSize(width: 106, height: 154)
        /// 唱臂圖內的旋轉支點（比例；≈ 34, 36）
        let armLocal = CGPoint(x: 0.3207547 * armSize.width, y: 0.0787746 * armSize.height)
        let pivot = CGPoint(x: armOrigin.x + armLocal.x, y: armOrigin.y + armLocal.y)
        let kinematics = TonearmKinematics(pivot: pivot, stylusAtRest: CGVector(dx: 6, dy: 365), restDegrees: 0,
                                           leadInRadius: 215.0, runOutRadius: 131.2,
                                           declaredTravel: .init(startDegrees: 14.1, sweepDegrees: 19.3))
        return TurntableSkin(
            id: "classic", kinematics: kinematics,
            arm: ArtworkFrame(size: armSize, localPivot: armLocal),
            base: ArtworkFrame(size: baseSize, localPivot: CGPoint(x: pivot.x - armOrigin.x, y: pivot.y - baseTop)),
            /// 點擊命中：臂管寬（以支點 x 為中線的半寬）與唱頭區（臂圖內 y）
            hitShape: .tubeStrip(halfWidth: 14, headTop: 337, headBottom: 407),
            rendering: .classicImages)
    }()
}
