import Foundation

/// 預取視窗（M7 P2-2）：從中心往兩側展開的取圖順序。
///
/// `±limit` 是**上限而非固定批次**——依滑動方向決定哪一側先取，
/// 兩端 clamp。中心本身不含在內：它由 View 的 explicit 請求取，天然優先。
enum CoverFlowPrefetchWindow {
    /// §5 的「兩側低優先級預取」上限
    static let defaultLimit = 5

    /// - Parameters:
    ///   - direction: 移動方向。`>= 0` 先取右側；`< 0` 先取左側。使用者往哪滑，
    ///     那一側就是他即將看到的
    static func ids(
        items: [AlbumTrack],
        centerIndex: Int,
        direction: Int = 1,
        limit: Int = defaultLimit
    ) -> [String] {
        guard items.indices.contains(centerIndex), limit > 0 else { return [] }

        let forwardFirst = direction >= 0
        var result: [String] = []
        for distance in 1...limit {
            let near = centerIndex + (forwardFirst ? distance : -distance)
            let far = centerIndex + (forwardFirst ? -distance : distance)
            for index in [near, far] where items.indices.contains(index) {
                result.append(items[index].persistentID)
            }
        }
        return result
    }
}
