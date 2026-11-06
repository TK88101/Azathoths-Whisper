import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.2：writerID＝SHA-256(硬體 UUID ‖ 固定字串) 前 8 bytes 小寫 hex；不存檔、讀不到就回錯（不退回隨機）
@Suite("Sync writer ID")
struct SyncWriterIDTests {
    struct FixedHardware: HardwareIdentity {
        let uuid: String?
        func platformUUID() throws(SyncWriterID.Failure) -> String {
            guard let uuid else { throw .unavailable }
            return uuid
        }
    }

    @Test func theSameHardwareAlwaysGivesTheSameID() throws {
        let first = try SyncWriterID.current(from: FixedHardware(uuid: "6F1C2E1A-0000-4000-8000-000000000001"))
        let second = try SyncWriterID.current(from: FixedHardware(uuid: "6F1C2E1A-0000-4000-8000-000000000001"))
        #expect(first == second)
        #expect(SyncWriterID.isValid(first))
    }

    @Test func differentHardwareGivesADifferentID() throws {
        let a = try SyncWriterID.current(from: FixedHardware(uuid: "6F1C2E1A-0000-4000-8000-000000000001"))
        let b = try SyncWriterID.current(from: FixedHardware(uuid: "6F1C2E1A-0000-4000-8000-000000000002"))
        #expect(a != b)
    }

    @Test func missingHardwareIdentityIsAnError() {
        #expect(throws: SyncWriterID.Failure.unavailable) { try SyncWriterID.current(from: FixedHardware(uuid: nil)) }
        #expect(throws: SyncWriterID.Failure.unavailable) { try SyncWriterID.current(from: FixedHardware(uuid: "  ")) }
    }

    @Test(arguments: ["000000000000000a", "0123456789abcdef"])
    func validIDs(_ id: String) { #expect(SyncWriterID.isValid(id)) }

    @Test(arguments: ["000000000000000A", "000000000000000", "000000000000000g", "", "0123456789abcdef0", "../../etc/passwd"])
    func invalidIDs(_ id: String) { #expect(SyncWriterID.isValid(id) == false) }

    @Test func theIOKitIdentityReadsAWellFormedID() throws {
        // 只驗格式，不記值（日誌與測試輸出都不出現硬體 UUID，§6.2）
        let id = try SyncWriterID.current(from: IOKitHardwareIdentity())
        #expect(SyncWriterID.isValid(id))
    }
}
