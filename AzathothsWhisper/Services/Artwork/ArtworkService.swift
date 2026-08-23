import AppKit
import Foundation
import ImageIO

/// 封面來源抽象——ViewModel 只依賴它，測試可注入替身
protocol ArtworkProviding: Sendable {
    func artwork(for persistentID: String) async -> NSImage?
}

/// 取圖編排（M7 P1-2）：查記憶體 → 未命中走 AE → 解碼縮圖 → 存記憶體。
///
/// **best-effort 語義**：任何一步失敗都回 `nil`，由呼叫端顯示佔位（H-08）。
/// 失敗**不寫快取**——否則一次網路/權限抖動會把「沒有封面」永久固化。
///
/// AE 的等待上限由 `MusicAppleEventsClient.artworkTimeoutTicks`（`SBApplication.timeout`）
/// 保證；Swift 層的 timeout 無法釋放 AE 佇列，故此處不做那種假保證。
actor ArtworkService: ArtworkProviding {
    /// §4.8：縮圖上限
    static let maxPixelSize = 512

    private let music: any MusicControlling
    private let memory: ArtworkMemoryCache
    /// 同一 persistentID 的併發 miss 共享同一個請求，避免對 AE 打出重複流量
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    init(music: any MusicControlling, memory: ArtworkMemoryCache = ArtworkMemoryCache()) {
        self.music = music
        self.memory = memory
    }

    func artwork(for persistentID: String) async -> NSImage? {
        if let cached = memory.image(for: persistentID) { return cached }
        if let running = inFlight[persistentID] { return await running.value }

        let task = Task<NSImage?, Never> { [music] in
            guard let data = try? await music.artworkData(persistentID: persistentID),
                  let image = Self.thumbnail(from: data)
            else { return nil }
            return image
        }
        inFlight[persistentID] = task
        let image = await task.value
        inFlight[persistentID] = nil

        // 只有成功才寫快取：失敗寫入會把暫時性錯誤固化成永久的「無封面」
        if let image { memory.store(image, for: persistentID) }
        return image
    }

    /// 解碼為 ≤512px 的縮圖。原圖可能是專輯級的大圖，直接進記憶體會炸。
    nonisolated static func thumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
