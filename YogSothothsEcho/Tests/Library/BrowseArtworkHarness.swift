import Foundation
import Testing
import UIKit

@testable import YogSothothsEcho

/// BrowseArtwork 測試共用（BrowseArtworkTests、BrowseArtworkRenditionTests、BrowseArtworkBudgetTests）
@MainActor
enum BrowseArtworkHarness {
    /// 以替身組 BrowseArtwork：每次解碼回同一張 `image`（快取成本照該圖像素計）
    static func make(fake: FakeDetailRequests, gate: SleepGate, image: UIImage,
                     spineBytes: Int = BrowseArtwork.spineByteLimit, gridBytes: Int = BrowseArtwork.gridByteLimit,
                     notifications: NotificationCenter = NotificationCenter()) -> BrowseArtwork {
        BrowseArtwork(
            request: { id, token, priority in token == nil ? nil : await fake.request(id, priority) },
            decode: { _, size in
                await fake.decoded(size)
                return image
            },
            sleep: { _ in await gate.wait() }, spineByteLimit: spineBytes, gridByteLimit: gridBytes, notifications: notifications)
    }

    /// 條件成立前每 5 ms 重查，最多約 2 s
    static func eventually(_ condition: @escaping () async -> Bool) async -> Bool {
        for _ in 0..<400 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    /// 等計時 Task 進入等待再放行（先放行會落空）
    static func settle(_ gate: SleepGate) async {
        _ = await eventually { await gate.pending >= 1 }
        await gate.fire()
    }

    /// scale 1 的空白圖（像素＝pt）
    static func image(side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in }
    }
}
