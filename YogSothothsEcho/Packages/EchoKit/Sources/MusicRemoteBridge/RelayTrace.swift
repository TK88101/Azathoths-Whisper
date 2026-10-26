import os

/// relay-measure 診斷紀錄的唯一出口（#4-1 N-01／D2；Release 不含，也不組字）。
/// 只記 ID、數字與規則名；`log show` 判讀與 Scripts/d2_pair.py 依賴字面，改字要同步
public enum RelayTrace {
    #if DEBUG
    private static let logger = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "relay-measure")
    #endif

    public static func notice(_ line: @autoclosure () -> String) {
        #if DEBUG
        let text = line()
        logger.notice("\(text, privacy: .public)")
        #endif
    }

    /// 高頻的到達紀錄用 info（`log stream --level info` 才看得到）
    public static func info(_ line: @autoclosure () -> String) {
        #if DEBUG
        let text = line()
        logger.info("\(text, privacy: .public)")
        #endif
    }
}
