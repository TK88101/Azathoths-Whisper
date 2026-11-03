import CryptoKit
import Foundation
import IOKit

/// 硬體身分的邊界（⑨ 計劃 §6.2）：測試換成固定值
protocol HardwareIdentity: Sendable {
    func platformUUID() throws(SyncWriterID.Failure) -> String
}

/// 讀 `IOPlatformUUID`。只用來導出 writerID；值本身不進日誌、不寫檔
struct IOKitHardwareIdentity: HardwareIdentity {
    func platformUUID() throws(SyncWriterID.Failure) -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { throw .unavailable }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        else { throw .unavailable }
        return value
    }
}

/// 這台 Mac 在 iCloud 資料夾裡的名字：SHA-256(硬體 UUID ‖ 固定字串) 前 8 bytes 小寫 hex。
/// **不存檔**：同一台重裝仍同一個；遷移助理複製出來的機器硬體不同，自然得到新 ID（§6.2）
enum SyncWriterID {
    enum Failure: Error, Equatable {
        /// 讀不到硬體身分＝不能同步（不退回隨機 ID：那會讓每次啟動都成新寫入者）
        case unavailable
    }

    static let salt = "com.ibridgezhao.azathothswhisper.sync.v1"
    static let length = 16

    static func current(from hardware: any HardwareIdentity) throws(Failure) -> String {
        let uuid = try hardware.platformUUID().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uuid.isEmpty else { throw .unavailable }
        return SHA256.hash(data: Data((uuid + salt).utf8)).prefix(length / 2).map { String(format: "%02x", $0) }.joined()
    }

    /// 「已蓋章」的唯一定義（各記錄型別的 origin 都經這裡）
    static func isStamped(_ origin: String?) -> Bool {
        !(origin ?? "").isEmpty
    }

    /// origin 合格的唯一定義：writerID 格式；本機載入可接受還沒蓋章（nil／空字串）
    static func isAcceptableOrigin(_ origin: String?, allowUnstamped: Bool) -> Bool {
        isStamped(origin) ? isValid(origin ?? "") : allowUnstamped
    }

    /// 資料夾名與 origin 的唯一格式定義：16 位小寫 hex（防路徑穿越）
    static func isValid(_ id: String) -> Bool {
        id.utf8.count == length && id.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}
