#if os(macOS)
import Foundation
import ScriptingBridge

// `tracks` 的編譯期邊界（CR-009）：協定是 fileprivate，其他檔案叫不到。
// 只准以 persistent ID 篩選取單一曲目，不得列舉（echo_gate.py E3）。
@objc(AZWMusicRemoteLibraryProto) fileprivate protocol MusicRemoteLibraryProto {
    @objc optional func tracks() -> SBElementArray
}

extension SBApplication: MusicRemoteLibraryProto {}

extension RemoteSelectorAllowList {
    /// 白名單中屬於本檔協定的一筆（CR-009）
    static let libraryEntry: (String, Set<String>) = ("AZWMusicRemoteLibraryProto", ["tracks"])
}

/// Bridge 內唯一能碰 `tracks` 的 API：給一個 persistent ID、回單一曲目或 nil（S4 T5）
enum TrackLookup {
    /// 以 persistent ID 取單一曲目。Music 內 persistent ID 唯一；萬一回多筆取第一筆（本檔依 E3 不得計數或列舉）
    static func find(persistentID: String, in app: SBApplication) -> SBObject? {
        resolve(persistentID: persistentID) { predicate in
            (app as MusicRemoteLibraryProto).tracks?().filtered(using: predicate) ?? []
        } as? SBObject
    }

    /// 查找的純邏輯（可單測）：空或格式不對的 ID 不查；`matches` 只收以 persistentID 相等為條件的述詞
    static func resolve(persistentID: String, matches: (NSPredicate) -> [Any]) -> Any? {
        guard MusicPersistentID.isValid(persistentID) else { return nil }
        return matches(NSPredicate(format: "persistentID == %@", persistentID)).first
    }
}
#endif
