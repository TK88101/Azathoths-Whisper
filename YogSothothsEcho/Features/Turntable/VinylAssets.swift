import OSLog
import UIKit

/// MD Vinyl 素材（只放本機，sprint-5-detail.md D1）：從 bundle 的 `VinylAssets.local/` 讀 PNG；找不到回 nil，呼叫端畫後備圖形
@MainActor
enum VinylAssets {
    enum Name: String, CaseIterable {
        case base = "vinyl_player_vinyl_record_colorful_base"
        case noise = "vinyl_player_vinyl_record_colorful_noise"
        case pattern1 = "vinyl_player_vinyl_record_colorful_pattern1"
        case pattern2 = "vinyl_player_vinyl_record_colorful_pattern2"
        case marble = "vinyl_player_vinyl_record_colorful_marble"
        case center = "vinyl_player_vinyl_center"
        case arm = "vinyl_player_arm_black"
        case armBase = "vinyl_player_base_blur"
        case blurBackground = "vinyl_player_blur_bg"
        /// 浮層樣式五選一的小唱片預覽（#5-1 G6）
        case previewClassic = "vinyl_player_vinyl_preview_classic"
        case previewColoredBase = "vinyl_player_vinyl_preview_colored_base"
        case previewSplash = "vinyl_player_vinyl_preview_splash_pattern"
        case previewMarble = "vinyl_player_vinyl_preview_marble"
    }

    private static let folder = "VinylAssets.local"
    private static let log = Logger(subsystem: "com.ibridgezhao.yogsothothsecho", category: "turntable")
    private static var cache: [Name: UIImage] = [:]
    private static var reportedMissing = false

    static func image(_ name: Name) -> UIImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name.rawValue, withExtension: "png", subdirectory: folder),
              let image = UIImage(contentsOfFile: url.path) else {
            reportMissingOnce()
            return nil
        }
        cache[name] = image
        return image
    }

    /// 只記一次、只記素材資料夾缺失（不記任何曲名）
    private static func reportMissingOnce() {
        guard !reportedMissing else { return }
        reportedMissing = true
        log.info("vinyl assets missing; drawing fallback shapes")
    }
}
