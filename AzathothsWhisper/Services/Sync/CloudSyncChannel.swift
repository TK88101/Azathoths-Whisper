import Darwin
import Foundation

/// 一次採用的結果：被驗證器丟掉的筆數、本機正本有沒有變
struct CloudSyncAdoption: Equatable, Sendable {
    let rejected: Int
    let changed: Bool
}

/// 讀完他機檔、還沒採用的一份結果。讀（可能阻塞）與採用（寫本機）分開：逾時的讀取結果直接丟，不會晚到才寫入（R1-16）
struct CloudSyncRead: Sendable {
    /// 讀到的他機與各自的 writtenAt
    let writers: [String: Date]
    /// 這次要採用的他機檔雜湊（已採用過、沒變的不在內）
    let hashes: [String: String]
    let skipped: Int
    let pendingDownloads: Int
    let apply: @Sendable () async -> CloudSyncAdoption
}

/// 一類資料的本機端（⑨ 計劃 §6.7）：`AppModel` 組裝真的、測試組裝替身；coordinator 不認識任何 store
struct CloudSyncChannel: Sendable {
    let kind: SyncKind
    /// 替缺 origin 的本機記錄蓋章並寫回正本（§6.3；冪等）
    let stamp: @Sendable (_ writer: String) async throws -> Void
    /// 本機正本正規化 payload 的雜湊（啟動時與自己資料夾那份比，§6.4）
    let localHash: @Sendable () async -> String
    let export: @Sendable (_ folder: SyncFolder, _ at: Date) async throws -> Void
    /// `known`＝各他機已採用過的 payload 雜湊
    let read: @Sendable (_ folder: SyncFolder, _ known: [String: String]) async -> CloudSyncRead

    static func make<Payload: Codable & Sendable>(
        kind: SyncKind, as type: Payload.Type,
        stamp: @escaping @Sendable (String) async throws -> Void,
        payload: @escaping @Sendable () async -> Payload,
        adopt: @escaping @Sendable ([SyncEnvelope<Payload>]) async -> CloudSyncAdoption
    ) -> CloudSyncChannel {
        CloudSyncChannel(
            kind: kind, stamp: stamp,
            localHash: { SyncCodec.payloadHash(await payload()) },
            export: { folder, date in try folder.write(await payload(), kind: kind, at: date) },
            read: { folder, known in
                let scan = folder.readOthers(kind, as: type)
                let fresh = scan.envelopes.filter { known[$0.writerID] != $0.payloadSHA256 }
                return CloudSyncRead(
                    writers: Dictionary(scan.envelopes.map { ($0.writerID, $0.writtenAt) }, uniquingKeysWith: max),
                    hashes: Dictionary(fresh.map { ($0.writerID, $0.payloadSHA256) }, uniquingKeysWith: { first, _ in first }),
                    skipped: scan.skipped, pendingDownloads: scan.pendingDownloads,
                    apply: { fresh.isEmpty ? CloudSyncAdoption(rejected: 0, changed: false) : await adopt(fresh) }
                )
            }
        )
    }
}

/// 同一台機器同時跑兩份 app 時，只讓一份匯出（R1-17）。鎖檔放本機 Application Support，不放 iCloud
struct SyncLock: Sendable {
    final class Held: @unchecked Sendable {
        private let lock = NSLock()
        private var descriptor: Int32

        init(descriptor: Int32) { self.descriptor = descriptor }
        deinit { release() }

        func release() {
            lock.withLock {
                guard descriptor >= 0 else { return }
                flock(descriptor, LOCK_UN)
                close(descriptor)
                descriptor = -1
            }
        }
    }

    static let defaultURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.ibridgezhao.azathothswhisper/sync.lock")

    let url: URL

    /// 拿不到（別的實例拿著）＝nil
    func tryAcquire() -> Held? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return Held(descriptor: descriptor)
    }
}
