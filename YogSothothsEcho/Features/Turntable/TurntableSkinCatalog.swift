import CoreGraphics
import Foundation
import OSLog

/// 皮膚素材的讀取邊界（Bjork 慣例：外部邊界 protocol＋替身）；名稱是 bundle 子資料夾內的檔名
protocol SkinBundleReading: Sendable {
    func contents(of name: String, in folder: String) -> Data?
    /// PNG 檔頭（IHDR）的像素尺寸；沒有檔或不是 PNG＝nil。只讀檔頭，不解碼
    func pngPixelSize(of name: String, in folder: String) -> CGSize?
}

struct MainBundleSkinReader: SkinBundleReading {
    func contents(of name: String, in folder: String) -> Data? {
        url(name, folder).flatMap { try? Data(contentsOf: $0) }
    }

    func pngPixelSize(of name: String, in folder: String) -> CGSize? {
        guard let url = url(name, folder), let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: PNGHeader.length)).flatMap(PNGHeader.pixelSize)
    }

    private func url(_ name: String, _ folder: String) -> URL? {
        let file = name as NSString
        return Bundle.main.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: folder)
    }
}

/// PNG 簽名＋IHDR 的寬高（大端）
enum PNGHeader {
    static let length = 24
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static func pixelSize(_ data: Data) -> CGSize? {
        let bytes = [UInt8](data.prefix(length))
        guard bytes.count == length, Array(bytes[0..<8]) == signature, Array(bytes[12..<16]) == Array("IHDR".utf8) else { return nil }
        func value(_ offset: Int) -> Int { bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) } }
        return CGSize(width: value(16), height: value(20))
    }
}

/// 可用的皮膚（CR-034 §4.3）：classic 永遠在第一個；序列圖皮膚在啟動時 preflight（skin.json、求解、每個檔存在且檔頭尺寸相符），
/// 任一不過＝不列入並記一次。執行期才發現的解碼失敗由 TurntableViewModel 從本 session 的可用清單移除（R2-2）
struct TurntableSkinCatalog: Sendable, Equatable {
    let skins: [ResolvedTurntableSkin]

    static let classicOnly = TurntableSkinCatalog(skins: [.classic])

    private static let log = Logger(subsystem: "com.ibridgezhao.yogsothothsecho", category: "turntable")

    func skin(id: String?) -> ResolvedTurntableSkin? {
        guard let id else { return nil }
        return skins.first { $0.spec.id == id }
    }

    static func load(reader: some SkinBundleReading,
                     report: (String, SkinError) -> Void = { id, error in logUnavailable(id, error) }) -> TurntableSkinCatalog {
        // 依註冊表順序（classic 恆第一，見 TurntableSkinEntry）
        let sprites = TurntableSkinEntry.all.compactMap(\.sprite).compactMap { definition -> ResolvedTurntableSkin? in
            do throws(SkinError) {
                return try preflight(definition, reader: reader)
            } catch {
                report(definition.id, error)
                return nil
            }
        }
        return TurntableSkinCatalog(skins: [.classic] + sprites)
    }

    /// 只記 id 與錯誤類型（不記任何曲名）
    static func logUnavailable(_ id: String, _ error: SkinError) {
        log.error("skin unavailable: \(id, privacy: .public) \(String(describing: error), privacy: .public)")
    }

    /// 序列圖皮膚在 bundle 內的每一個檔與它的畫框：幀（唱臂、投影）→ 下層底座 →（中層）→ 上層底座
    static func assetFiles(of skin: TurntableSkin, layers: TurntableSkin.SpriteLayers) -> [(name: String, frame: ArtworkFrame)] {
        let frames = (0..<SpriteSkinAssets.frameCount).flatMap {
            [(SpriteSkinAssets.armFile($0), skin.arm), (SpriteSkinAssets.shadowFile($0), layers.shadow)]
        }
        let middle = layers.middle.map { [(SpriteSkinAssets.middleFile, $0)] } ?? []
        return (frames + [(SpriteSkinAssets.baseFile, skin.base)] + middle + [(SpriteSkinAssets.overlayFile, layers.overlay)])
            .map { (name: $0.0, frame: $0.1) }
    }

    private static func preflight(_ definition: SpriteSkinDefinition, reader: some SkinBundleReading) throws(SkinError) -> ResolvedTurntableSkin {
        let folder = definition.folder
        guard let data = reader.contents(of: "skin.json", in: folder) else { throw .missingAsset }
        let resolved = try TurntableSkinResolver.resolve(TurntableSkin.sprite(definition, manifest: SpriteSkinManifest.decode(data))).get()
        let skin = resolved.spec
        guard let sprite = skin.spriteLayers else { throw .invalidRendering }
        let unit = sprite.assets.pixelsPerUnit
        for (name, frame) in assetFiles(of: skin, layers: sprite) {
            let pixels = CGSize(width: (frame.size.width * unit).rounded(), height: (frame.size.height * unit).rounded())
            guard reader.pngPixelSize(of: name, in: folder) == pixels else { throw .missingAsset }
        }
        return resolved
    }
}
