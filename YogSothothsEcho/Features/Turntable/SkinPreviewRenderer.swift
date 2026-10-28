import CoreGraphics
import Foundation
import Observation
import OSLog

/// 選擇器預覽的合成與快取（CR-034 增補 A §4.3）：由 TurntableViewModel 持有唯一一個（設定頁與浮層共用，r3-1）。
/// 鍵＝皮膚 id＋裁法＋輸出像素尺寸；同鍵請求合併；LRU 上限；失敗以皮膚 id 記住（之後任何尺寸都不再解、只記一次 log）。
/// 解碼與合成在共用的 detached Task 裡跑（不在主執行緒），呼叫端（格子）被取消不影響它，結果照樣進快取——取消不算失敗（r3-2）。
/// 預覽失敗不影響皮膚可不可用（那由唱機的正式解碼決定，r1-3）
@MainActor
@Observable
final class SkinPreviewRenderer {
    struct Key: Hashable {
        let id: String
        let crop: SkinPreviewCrop
        let width: Int
        let height: Int

        init(_ skin: ResolvedTurntableSkin, _ crop: SkinPreviewCrop, _ pixelSize: CGSize) {
            id = skin.spec.id
            self.crop = crop
            width = Int(pixelSize.width.rounded())
            height = Int(pixelSize.height.rounded())
        }
    }

    private(set) var images: [Key: CGImage] = [:]
    private(set) var unavailable: Set<String> = []
    /// 舊到新
    @ObservationIgnored private var order: [Key] = []
    @ObservationIgnored private var inflight: [Key: Task<Void, Never>] = [:]
    @ObservationIgnored private let source: any SkinPreviewImageSource
    @ObservationIgnored private let capacity: Int
    @ObservationIgnored private let report: (String) -> Void

    private static let log = Logger(subsystem: "com.ibridgezhao.yogsothothsecho", category: "turntable")

    init(source: any SkinPreviewImageSource = BundleSkinPreviewSource(), capacity: Int = 6,
         report: @escaping (String) -> Void = { id in SkinPreviewRenderer.log.error("skin preview unavailable: \(id, privacy: .public)") }) {
        self.source = source
        self.capacity = capacity
        self.report = report
    }

    func isUnavailable(_ id: String) -> Bool { unavailable.contains(id) }

    /// 要求的尺寸；還沒好就給同皮膚同裁法最近的一張（換尺寸不閃空，m-4）；都沒有＝nil
    func image(for skin: ResolvedTurntableSkin, crop: SkinPreviewCrop, pixelSize: CGSize) -> CGImage? {
        let key = Key(skin, crop, pixelSize)
        if let exact = images[key] { return exact }
        return order.last { $0.id == key.id && $0.crop == crop }.flatMap { images[$0] }
    }

    func load(_ skin: ResolvedTurntableSkin, crop: SkinPreviewCrop, pixelSize: CGSize) async {
        let key = Key(skin, crop, pixelSize)
        guard key.width > 0, key.height > 0, !unavailable.contains(key.id) else { return }
        if images[key] != nil {
            touch(key)
            return
        }
        let task = inflight[key] ?? start(skin, crop: crop, key: key)
        await task.value
    }

    private func start(_ skin: ResolvedTurntableSkin, crop: SkinPreviewCrop, key: Key) -> Task<Void, Never> {
        let source = self.source
        let size = CGSize(width: key.width, height: key.height)
        let layers = SkinPreviewGeometry.layers(for: skin)
        let k = SkinPreviewComposer.pixelsPerUnit(region: SkinPreviewGeometry.region(for: skin, crop: crop), pixelSize: size)
        // detached：解碼與合成都不在主執行緒（合成是純函式）；回主執行緒只寫快取。呼叫端被取消也不影響它（r3-2）
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let decoded = await withTaskGroup(of: (Int, CGImage?).self) { group in
                for (index, layer) in layers.enumerated() {
                    let longest = Int((max(layer.rect.width, layer.rect.height) * k).rounded(.up))
                    group.addTask { (index, await source.image(layer.kind, skin: skin, maxPixelSize: max(longest, 1))) }
                }
                var images = [CGImage?](repeating: nil, count: layers.count)
                for await (index, image) in group { images[index] = image }
                return images
            }
            let images = decoded.compactMap { $0 }
            let composed = images.count == layers.count
                ? SkinPreviewComposer.compose(Array(zip(layers, images)), skin: skin, crop: crop, pixelSize: size) : nil
            await self?.finish(key, composed: composed)
        }
        inflight[key] = task
        return task
    }

    private func finish(_ key: Key, composed: CGImage?) {
        inflight[key] = nil
        guard let composed else {
            if unavailable.insert(key.id).inserted { report(key.id) }
            return
        }
        images[key] = composed
        touch(key)
        while order.count > capacity { images[order.removeFirst()] = nil }
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
