import CoreGraphics
import Foundation
import RemoteProtocol

/// 唱機皮膚（F-V-07 框架；sprint-7-detail.md §4.2、§4.3）。「規格」可由程式常數（classic）或素材 manifest（CR-034）產生，
/// 一律經 `TurntableSkinResolver.resolve` 驗證並求出起止角，UI 只接受 `ResolvedTurntableSkin`。
/// 座標單位是唱片框的 u（474 u＝唱片直徑）；角度是畫面絕對角（0＝臂管朝畫面正下方、順時針為正）
struct TurntableSkin: Sendable, Equatable {
    let id: String
    private(set) var kinematics: TonearmKinematics
    /// 轉動部件（配重＋臂管＋唱頭）的畫框
    private(set) var arm: ArtworkFrame
    /// 固定部件（底座；畫在唱片下）的畫框
    private(set) var base: ArtworkFrame
    private(set) var hitShape: HitShape
    private(set) var rendering: Rendering
    /// 唱片圓心在容器內的位置（CR-034：序列圖皮膚取自 `SpriteSkinDefinition.placement`；封套、全封面、G7 都相對唱片圓心，跟著走）
    private(set) var placement: RecordPlacement
    /// 唱臂投影（與唱臂一起繞支點轉；自己的裁切框，CR-034 r1-1）；nil＝沒有獨立投影層
    private(set) var armShadow: ArtworkFrame?
    /// 底座上層（畫在唱臂之上的固定零件）；nil＝沒有
    private(set) var baseOverlay: ArtworkFrame?
    /// 唱臂與投影的可見輪廓（各自畫框內 u；所有幀 alpha 聯集）：版面以它算旋轉後的可見外接框。nil＝以畫框矩形計（classic）
    private(set) var armOutline: RowOutline?
    private(set) var shadowOutline: RowOutline?
    /// 底座中層（唱片之上、唱臂之下；CR-034 增補 B）；nil＝兩層底座
    private(set) var baseMiddle: ArtworkFrame?
    /// 中層的點擊遮罩（中層素材像素座標）；有中層就必備
    private(set) var middleHitMask: PixelRuns?

    init(id: String, kinematics: TonearmKinematics, arm: ArtworkFrame, base: ArtworkFrame, hitShape: HitShape, rendering: Rendering,
         placement: RecordPlacement = .classic, armShadow: ArtworkFrame? = nil, baseOverlay: ArtworkFrame? = nil,
         armOutline: RowOutline? = nil, shadowOutline: RowOutline? = nil, baseMiddle: ArtworkFrame? = nil, middleHitMask: PixelRuns? = nil) {
        self.id = id
        self.kinematics = kinematics
        self.arm = arm
        self.base = base
        self.hitShape = hitShape
        self.rendering = rendering
        self.placement = placement
        self.armShadow = armShadow
        self.baseOverlay = baseOverlay
        self.armOutline = armOutline
        self.shadowOutline = shadowOutline
        self.baseMiddle = baseMiddle
        self.middleHitMask = middleHitMask
    }

    enum HitShape: Sendable, Equatable {
        /// 臂管＝畫布支點 x 為中線、半寬 `halfWidth` 的細條；唱頭區＝畫框內 y 在 headTop…headBottom 的整列（皆為畫框內 u）
        case tubeStrip(halfWidth: CGFloat, headTop: CGFloat, headBottom: CGFloat)
        /// 逐列可點範圍＝唱臂可見輪廓（`armOutline`，35 幀 alpha 聯集）每列左右各外擴 `margin` u、夾在臂框內（CR-034 r1-5）
        case rowSpans(margin: CGFloat)
    }

    enum Rendering: Sendable, Equatable {
        /// 原版 MD Vinyl 的兩張本機 PNG，缺素材時畫後備圖形
        case classicImages
        /// 每整數度一幀的序列圖（本地 rest 姿態，取最近幀後整張轉完整角度）＋投影＋上下兩層底座
        case spriteSequence(SpriteSkinAssets)
    }

    /// 畫框左上（唱片框座標）＝支點 − 畫布支點；classic 與素材序列圖共用這一個公式
    var armOrigin: CGPoint { origin(of: arm) }
    var baseOrigin: CGPoint { origin(of: base) }

    func origin(of frame: ArtworkFrame) -> CGPoint {
        CGPoint(x: kinematics.pivot.x - frame.localPivot.x, y: kinematics.pivot.y - frame.localPivot.y)
    }

    /// 序列圖皮膚必備的圖層（resolver 已保證齊全；不是序列圖＝nil）。目錄與快取經這裡解包；版面與繪製讀各層畫框（classic 為 nil）。
    /// 中層是可選的：不列入必備條件，沒有中層照樣解包（兩層皮膚路徑不變）
    var spriteLayers: SpriteLayers? {
        guard case .spriteSequence(let assets) = rendering, let armShadow, let baseOverlay else { return nil }
        return SpriteLayers(assets: assets, shadow: armShadow, overlay: baseOverlay, middle: baseMiddle)
    }

    struct SpriteLayers: Sendable, Equatable {
        let assets: SpriteSkinAssets
        let shadow: ArtworkFrame
        let overlay: ArtworkFrame
        let middle: ArtworkFrame?
    }

    func replacing(kinematics: TonearmKinematics) -> TurntableSkin { with { $0.kinematics = kinematics } }
    func replacing(arm: ArtworkFrame) -> TurntableSkin { with { $0.arm = arm } }
    func replacing(base: ArtworkFrame) -> TurntableSkin { with { $0.base = base } }
    func replacing(hitShape: HitShape) -> TurntableSkin { with { $0.hitShape = hitShape } }
    func replacing(rendering: Rendering) -> TurntableSkin { with { $0.rendering = rendering } }
    func replacing(placement: RecordPlacement) -> TurntableSkin { with { $0.placement = placement } }
    func replacing(armShadow: ArtworkFrame?) -> TurntableSkin { with { $0.armShadow = armShadow } }
    func replacing(baseOverlay: ArtworkFrame?) -> TurntableSkin { with { $0.baseOverlay = baseOverlay } }
    func replacing(armOutline: RowOutline?) -> TurntableSkin { with { $0.armOutline = armOutline } }
    func replacing(baseMiddle: ArtworkFrame?) -> TurntableSkin { with { $0.baseMiddle = baseMiddle } }
    func replacing(middleHitMask: PixelRuns?) -> TurntableSkin { with { $0.middleHitMask = middleHitMask } }

    /// 複製後改一處（欄位對外唯讀）
    private func with(_ change: (inout TurntableSkin) -> Void) -> TurntableSkin {
        var copy = self
        change(&copy)
        return copy
    }
}

/// 逐像素列的點擊遮罩（CR-034 增補 B §4.5）：每列若干段半開區間 [x0, x1)，座標＝該層素材像素。由 `import_tonearm_skin.py` 產生
struct PixelRuns: Sendable, Equatable {
    let rows: [[Range<Int>]]

    func contains(x: Int, y: Int) -> Bool {
        guard rows.indices.contains(y) else { return false }
        return rows[y].contains { $0.contains(x) }
    }

    /// 列數＝素材像素高；每段在寬度內、同列遞增不重疊
    func fits(width: Int, height: Int) -> Bool {
        rows.count == height && rows.allSatisfy { row in
            zip([0..<0] + row, row).allSatisfy { previous, run in run.lowerBound >= previous.upperBound && !run.isEmpty }
                && (row.last?.upperBound ?? 0) <= width && (row.first?.lowerBound ?? 0) >= 0
        }
    }
}

/// 逐列輪廓（畫框內 u）：每 `bandHeight` 一列，該列 alpha 的最左…最右；nil＝整列透明。由 `import_tonearm_skin.py` 從所有幀的聯集產生
struct RowOutline: Sendable, Equatable {
    let bandHeight: CGFloat
    let spans: [ClosedRange<CGFloat>?]

    /// 畫框內 y 所在列的範圍；超出列數或該列透明＝nil
    func span(atY y: CGFloat) -> ClosedRange<CGFloat>? {
        guard y >= 0, bandHeight > 0 else { return nil }
        let row = Int(y / bandHeight)
        return row < spans.count ? spans[row] : nil
    }

    /// 每列的四個角（畫框內 u）：旋轉後的可見外接框以這些點計
    var corners: [CGPoint] {
        spans.enumerated().flatMap { row, span -> [CGPoint] in
            guard let span else { return [] }
            let top = CGFloat(row) * bandHeight, bottom = top + bandHeight
            return [CGPoint(x: span.lowerBound, y: top), CGPoint(x: span.upperBound, y: top),
                    CGPoint(x: span.lowerBound, y: bottom), CGPoint(x: span.upperBound, y: bottom)]
        }
    }

    func fits(in frame: ArtworkFrame) -> Bool {
        guard bandHeight.isFinite, bandHeight > 0, spans.contains(where: { $0 != nil }),
              CGFloat(spans.count) <= (frame.size.height / bandHeight).rounded(.up) else { return false }
        return spans.allSatisfy { span in
            guard let span else { return true }
            return span.lowerBound.isFinite && span.upperBound.isFinite && span.lowerBound >= 0 && span.upperBound <= frame.size.width
        }
    }
}

/// 唱片圓心距容器右緣（× R）、比垂直中線往下（× R）；R＝唱片直徑（sprint-5-detail.md §4.2b）
struct RecordPlacement: Sendable, Equatable {
    let rightInset: CGFloat
    let drop: CGFloat

    /// 原版構圖（v1.6／v1.8）
    static let classic = RecordPlacement(rightInset: 0.61, drop: 0.0125)
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
    /// 唱片位置非有限，或右距不在 0…1 之間（不含端點）
    case invalidPlacement
    /// 序列圖沒有幀、或每 u 像素數不為正
    case invalidRendering
    /// skin.json 解不開或 schema 不符
    case invalidManifest
    /// 可見輪廓沒有任何列、列高非正，或某列超出所屬畫框
    case invalidOutline
    /// bundle 內缺 skin.json、缺幀，或某檔的 PNG 檔頭尺寸與 skin.json 不符
    case missingAsset
    /// preflight 通過、執行期某幀解碼失敗
    case decodeFailed
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
                                  k.leadInRadius, k.runOutRadius] + travel + frames(of: skin).flatMap {
            [$0.size.width, $0.size.height, $0.localPivot.x, $0.localPivot.y]
        }
        if numbers.contains(where: { !$0.isFinite }) { return .nonFinite }
        if hypot(k.stylusAtRest.dx, k.stylusAtRest.dy) <= 0 { return .zeroStylus }
        if k.leadInRadius <= 0 || k.runOutRadius <= 0 { return .nonPositiveRadius }
        let frames = frames(of: skin)
        if frames.contains(where: { $0.size.width <= 0 || $0.size.height <= 0 }) { return .invalidFrame }
        let inside = frames.allSatisfy { f in
            (0...f.size.width).contains(f.localPivot.x) && (0...f.size.height).contains(f.localPivot.y)
        }
        guard inside else { return .pivotOutsideFrame }
        let p = skin.placement
        guard p.rightInset.isFinite, p.drop.isFinite, p.rightInset > 0, p.rightInset < 1 else { return .invalidPlacement }
        if case .spriteSequence(let assets) = skin.rendering {
            // 序列圖皮膚：投影、上層底座、兩份輪廓都必備（`spriteLayers` 據此解包）
            guard assets.pixelsPerUnit > 0, skin.spriteLayers != nil, skin.armOutline != nil, skin.shadowOutline != nil else {
                return .invalidRendering
            }
        }
        guard fits(skin.armOutline, skin.arm), fits(skin.shadowOutline, skin.armShadow), middleMaskFits(skin) else { return .invalidOutline }
        return isValid(skin.hitShape, of: skin) ? nil : .invalidHitShape
    }

    /// 會畫出來的每一層（驗證畫框與支點用）
    private static func frames(of skin: TurntableSkin) -> [ArtworkFrame] {
        [skin.arm, skin.base] + [skin.armShadow, skin.baseOverlay, skin.baseMiddle].compactMap { $0 }
    }

    /// 中層與遮罩同進同出；遮罩要對得上中層的像素尺寸（每 u 像素數取自序列圖）
    private static func middleMaskFits(_ skin: TurntableSkin) -> Bool {
        switch (skin.baseMiddle, skin.middleHitMask) {
        case (nil, nil): return true
        case (let middle?, let mask?):
            guard case .spriteSequence(let assets) = skin.rendering else { return false }
            let unit = assets.pixelsPerUnit
            return mask.fits(width: Int((middle.size.width * unit).rounded()), height: Int((middle.size.height * unit).rounded()))
        default: return false
        }
    }

    /// 沒有輪廓＝不必驗；有輪廓就得有對應畫框且落在框內
    private static func fits(_ outline: RowOutline?, _ frame: ArtworkFrame?) -> Bool {
        guard let outline else { return true }
        return frame.map(outline.fits) ?? false
    }

    private static func isValid(_ shape: TurntableSkin.HitShape, of skin: TurntableSkin) -> Bool {
        let arm = skin.arm
        switch shape {
        case .tubeStrip(let halfWidth, let headTop, let headBottom):
            return [halfWidth, headTop, headBottom].allSatisfy(\.isFinite) && halfWidth >= 0
                && 0 <= headTop && headTop <= headBottom && headBottom <= arm.size.height
        case .rowSpans(let margin):
            return margin.isFinite && margin >= 0 && skin.armOutline != nil
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
