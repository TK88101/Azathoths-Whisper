import Foundation

/// 預取視窗（M7 P2-2）：從中心往兩側展開的取圖順序。
///
/// `±limit` 是**上限而非固定批次**——依滑動方向決定哪一側先取，
/// 兩端 clamp。中心本身不含在內：它由 View 的 explicit 請求取，天然優先。
enum CoverFlowPrefetchWindow {
    /// §5 的「兩側低優先級預取」上限
    static let defaultLimit = 5

    /// - Parameters:
    ///   - persistentIDs: 牌組中每張卡的 persistentID（依畫面順序；同曲可出現多次）
    ///   - direction: 移動方向。`>= 0` 先取右側；`< 0` 先取左側。使用者往哪滑，
    ///     那一側就是他即將看到的
    /// - Returns: 去重後的 persistentID；與中心同曲者不取（中心由 View 的 explicit 請求取）
    static func ids(
        persistentIDs: [String],
        centerIndex: Int,
        direction: Int = 1,
        limit: Int = defaultLimit
    ) -> [String] {
        guard persistentIDs.indices.contains(centerIndex), limit > 0 else { return [] }

        let forwardFirst = direction >= 0
        var seen: Set<String> = [persistentIDs[centerIndex]]
        var result: [String] = []
        for distance in 1...limit {
            let near = centerIndex + (forwardFirst ? distance : -distance)
            let far = centerIndex + (forwardFirst ? -distance : distance)
            for index in [near, far] where persistentIDs.indices.contains(index) {
                if seen.insert(persistentIDs[index]).inserted {
                    result.append(persistentIDs[index])
                }
            }
        }
        return result
    }
}
