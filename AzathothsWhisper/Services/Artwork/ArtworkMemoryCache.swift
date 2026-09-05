import AppKit
import Foundation

/// 封面的記憶體快取（M7 P1-1）。
///
/// 配額與磁碟層（P2：200 張／50MB）是**兩套獨立上限**，不混談：
/// 記憶體壓力來自解碼後的點陣圖，磁碟壓力來自壓縮後的檔案。
///
/// `NSCache` 的 countLimit／totalCostLimit 是 **soft limit**——實際驅逐由系統依
/// 記憶體壓力決定。這正是選它而非自建 LRU 的理由：系統吃緊時它會自動讓路，
/// 而封面丟了只是重取一次，不影響正確性。代價是驅逐時機不可測（見測試註釋）。
final class ArtworkMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, NSImage>()

    var countLimit: Int { cache.countLimit }
    var totalCostLimit: Int { cache.totalCostLimit }

    init(countLimit: Int = 60, totalCostLimit: Int = 40 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func image(for persistentID: String) -> NSImage? {
        cache.object(forKey: persistentID as NSString)
    }

    func store(_ image: NSImage, for persistentID: String) {
        cache.setObject(image, forKey: persistentID as NSString, cost: Self.cost(of: image))
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    /// 以解碼後位元組估算（寬×高×4 bytes RGBA）。
    /// 至少回 1——0 cost 會讓該項在 totalCostLimit 眼中「免費」而無限堆積。
    static func cost(of image: NSImage) -> Int {
        let pixels = Int(image.size.width * image.size.height)
        return max(1, pixels * 4)
    }
}
