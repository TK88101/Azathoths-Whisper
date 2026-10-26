import os

/// OSLog 輸出：只記 renderer 的固定欄位（皆為封閉 enum rawValue 或 UUID，可標 public）
public struct OSLogAuditOutput: RenderedAuditOutput {
    private let logger: Logger

    public init(subsystem: String, category: String = "transport") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func write(_ fields: [AuditRenderer.Field]) {
        let line = fields.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        logger.info("\(line, privacy: .public)")
    }
}
