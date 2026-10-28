import CoreGraphics
import Foundation

/// 序列圖皮膚的素材位置（CR-034；只存資料，圖片由 `TonearmSpriteCache` 解碼）。檔名一律由程式常數產生：
/// skin.json 的檔名欄位只做核對、不當格式字串（安全評審 M-1／M-2）
struct SpriteSkinAssets: Sendable, Equatable {
    /// 交件契約：0…34° 每整數度一幀（`check_tonearm_skin.py` 的 ANGLES）
    static let frameCount = 35
    static let armPattern = "arm_%03d.png"
    static let shadowPattern = "arm_shadow_%03d.png"
    static let baseFile = "base_underlay.png"
    static let overlayFile = "base_overlay.png"
    /// 可選的第三層底座（唱片之上、唱臂之下；CR-034 增補 B）
    static let middleFile = "base_middle.png"

    /// bundle 內的子資料夾（folder reference，例如 "Skins/s-arm-1200"）
    let folder: String
    /// 素材每 u 的像素數（契約值 4；解碼縮圖時換算畫面像素）
    let pixelsPerUnit: CGFloat

    static func armFile(_ frame: Int) -> String { String(format: armPattern, frame) }
    static func shadowFile(_ frame: Int) -> String { String(format: shadowPattern, frame) }
}

/// 一款序列圖皮膚的 App 端定義：id＝skin.json 的 skin_id＝bundle 子資料夾名；唱片位置屬 App 版面，寫在這裡（不進 skin.json）
struct SpriteSkinDefinition: Sendable {
    let id: String
    let placement: RecordPlacement

    var folder: String { "Skins/\(id)" }

    /// 先鋒型 S 形臂。方案 3（CR-034，使用者 2026-10-26 選）：唱片＋封套沿「支點→唱片圓心」往左下移 16.37 u（10.36 mm），讓出弧形滑槽
    static let sArm1200 = SpriteSkinDefinition(id: "s-arm-1200", placement: RecordPlacement(rightInset: 0.636034, drop: 0.0352))
    /// Rega RB330 型直臂。預設構圖（增補 A §4.5）：交件即以 classic 的唱片位置設計；量測只有底座陰影的淡邊進到唱片下
    static let regaRB330 = SpriteSkinDefinition(id: "rega-rb330", placement: .classic)
    /// Technics SL-1200G 型 S 形臂。預設構圖（增補 B §4.4，使用者 2026-10-28 認可）：唱片不移，卡在下層外盤的缺口；
    /// 刻度環與臂夾在中層（唱片之上、唱臂之下）
    static let technicsSL1200G = SpriteSkinDefinition(id: "technics-sl1200g", placement: .classic)
}

/// skin.json（`Scripts/import_tonearm_skin.py` 產生，schema 1）：只記素材事實；唱片位置、支點、落針半徑屬 App 版面，寫在程式裡
struct SpriteSkinManifest: Decodable, Sendable, Equatable {
    static let schemaVersion = 1

    let schema: Int
    let skinId: String
    let pxPerUnit: Int
    let frameCount: Int
    let layers: Layers
    let kinematics: Kinematics
    let outlineBandU: Double
    let hitMarginU: Double

    struct Layers: Decodable, Sendable, Equatable {
        let arm: SequenceLayer
        let armShadow: SequenceLayer
        let base: StillLayer
        /// nil＝兩層底座的皮膚（Pioneer、Rega）
        let baseMiddle: MiddleLayer?
        let baseOverlay: StillLayer
    }

    struct SequenceLayer: Decodable, Sendable, Equatable {
        let sizePx: [Double]
        let pivotPx: [Double]
        let filePattern: String
        let outlineU: [[Double]?]
    }

    struct StillLayer: Decodable, Sendable, Equatable {
        let sizePx: [Double]
        let pivotPx: [Double]
        let file: String
    }

    /// 中層另帶點擊遮罩：裁切後每一像素列 alpha ≥ 128 的半開區間 [x0, x1)。獨立型別，不動 base／overlay 共用的 StillLayer
    struct MiddleLayer: Decodable, Sendable, Equatable {
        let sizePx: [Double]
        let pivotPx: [Double]
        let file: String
        let hitRunsPx: [[[Int]]]
    }

    struct Kinematics: Decodable, Sendable, Equatable {
        let stylusAtRestU: [Double]
        let restDegrees: Double
    }

    static func decode(_ data: Data) throws(SkinError) -> SpriteSkinManifest {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let manifest = try? decoder.decode(SpriteSkinManifest.self, from: data), manifest.schema == schemaVersion else {
            throw .invalidManifest
        }
        return manifest
    }
}

extension TurntableSkin {
    /// skin.json → 序列圖皮膚。落針／播完半徑與 classic 相同；起止角由求解器算（s-arm-1200：13.81°→31.24°）。
    /// skin_id、幀數、檔名須與定義及契約常數一致（不一致＝invalidManifest，不拿資料組檔名）
    static func sprite(_ definition: SpriteSkinDefinition, manifest: SpriteSkinManifest) throws(SkinError) -> TurntableSkin {
        let unit = CGFloat(manifest.pxPerUnit)
        let layers = manifest.layers
        guard manifest.skinId == definition.id, manifest.frameCount == SpriteSkinAssets.frameCount, unit > 0,
              manifest.kinematics.stylusAtRestU.count == 2,
              layers.arm.filePattern == SpriteSkinAssets.armPattern, layers.armShadow.filePattern == SpriteSkinAssets.shadowPattern,
              layers.base.file == SpriteSkinAssets.baseFile, layers.baseOverlay.file == SpriteSkinAssets.overlayFile,
              layers.baseMiddle.map({ $0.file == SpriteSkinAssets.middleFile }) ?? true else {
            throw .invalidManifest
        }
        let band = CGFloat(manifest.outlineBandU)
        let classic = TurntableSkin.classic
        let kinematics = TonearmKinematics(
            pivot: pivot(keepingScreenPositionOf: classic, under: definition.placement),
            stylusAtRest: CGVector(dx: manifest.kinematics.stylusAtRestU[0], dy: manifest.kinematics.stylusAtRestU[1]),
            restDegrees: manifest.kinematics.restDegrees,
            leadInRadius: classic.kinematics.leadInRadius, runOutRadius: classic.kinematics.runOutRadius)
        return TurntableSkin(
            id: definition.id, kinematics: kinematics, arm: try frame(layers.arm.sizePx, layers.arm.pivotPx, unit),
            base: try frame(layers.base.sizePx, layers.base.pivotPx, unit),
            hitShape: .rowSpans(margin: CGFloat(manifest.hitMarginU)),
            rendering: .spriteSequence(SpriteSkinAssets(folder: definition.folder, pixelsPerUnit: unit)), placement: definition.placement,
            armShadow: try frame(layers.armShadow.sizePx, layers.armShadow.pivotPx, unit),
            baseOverlay: try frame(layers.baseOverlay.sizePx, layers.baseOverlay.pivotPx, unit),
            armOutline: try outline(layers.arm.outlineU, band: band), shadowOutline: try outline(layers.armShadow.outlineU, band: band),
            baseMiddle: try layers.baseMiddle.map { middle throws(SkinError) in try frame(middle.sizePx, middle.pivotPx, unit) },
            middleHitMask: try layers.baseMiddle.map { middle throws(SkinError) in try runs(middle.hitRunsPx) })
    }

    private static func runs(_ rows: [[[Int]]]) throws(SkinError) -> PixelRuns {
        let ranges = try rows.map { row throws(SkinError) -> [Range<Int>] in
            try row.map { run throws(SkinError) -> Range<Int> in
                guard run.count == 2, run[0] < run[1] else { throw .invalidManifest }
                return run[0]..<run[1]
            }
        }
        return PixelRuns(rows: ranges)
    }

    /// 換了唱片位置後，讓支點的螢幕位置不變：唱片框原點隨 placement 移多少，支點的唱片框座標就反向移多少（u）
    static func pivot(keepingScreenPositionOf reference: TurntableSkin, under placement: RecordPlacement) -> CGPoint {
        let size = TurntableMetrics.recordSize, from = reference.placement
        return CGPoint(x: reference.kinematics.pivot.x + (placement.rightInset - from.rightInset) * size,
                       y: reference.kinematics.pivot.y - (placement.drop - from.drop) * size)
    }

    private static func outline(_ rows: [[Double]?], band: CGFloat) throws(SkinError) -> RowOutline {
        let spans = try rows.map { span throws(SkinError) -> ClosedRange<CGFloat>? in
            guard let span else { return nil }
            guard span.count == 2, span[0] <= span[1] else { throw .invalidManifest }
            return CGFloat(span[0])...CGFloat(span[1])
        }
        return RowOutline(bandHeight: band, spans: spans)
    }

    private static func frame(_ sizePx: [Double], _ pivotPx: [Double], _ unit: CGFloat) throws(SkinError) -> ArtworkFrame {
        guard sizePx.count == 2, pivotPx.count == 2 else { throw .invalidManifest }
        return ArtworkFrame(size: CGSize(width: CGFloat(sizePx[0]) / unit, height: CGFloat(sizePx[1]) / unit),
                            localPivot: CGPoint(x: CGFloat(pivotPx[0]) / unit, y: CGFloat(pivotPx[1]) / unit))
    }
}
