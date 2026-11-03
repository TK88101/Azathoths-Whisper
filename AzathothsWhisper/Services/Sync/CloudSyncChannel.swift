import Darwin
import Foundation

/// 一次採用的結果：被驗證器丟掉的筆數、本機正本有沒有變、本機寫入有沒有失敗
struct CloudSyncAdoption: Equatable, Sendable {
    let rejected: Int
    let changed: Bool
    /// 本機寫入失敗（壞檔、磁碟滿）：這份遠端檔下輪要重試，不能記成「已採用」（codex review P2）
    var failed = false

    static let none = CloudSyncAdoption(rejected: 0, changed: false)

    static func + (lhs: CloudSyncAdoption, rhs: CloudSyncAdoption) -> CloudSyncAdoption {
        CloudSyncAdoption(rejected: lhs.rejected + rhs.rejected, changed: lhs.changed || rhs.changed, failed: lhs.failed || rhs.failed)
    }
}

/// 讀完他機檔、還沒採用的一份結果。讀（可能阻塞）與採用（寫本機）分開：逾時的讀取結果直接丟，不會晚到才寫入（R1-16）
struct CloudSyncRead: Sendable {
    /// 讀到的他機與各自的 writtenAt
    let writers: [String: Date]
    /// 這輪讀到（或確認沒變）的他機檔；採用成功後記下，下輪據以略過
    let stamps: [String: SyncFolder.FileStamp]
    let skipped: Int
    let pendingDownloads: Int
    let apply: @Sendable () async -> CloudSyncAdoption
}

/// 一類資料的本機端（⑨ 計劃 §6.7）：`AppModel` 組裝真的、測試組裝替身；coordinator 不認識任何 store
struct CloudSyncChannel: Sendable {
    let kind: SyncKind
    /// 替缺 origin 的本機記錄蓋章並寫回正本（§6.3；冪等）
    let stamp: @Sendable (_ writer: String) async throws -> Void
    /// 匯出本機正本；與自己資料夾那份雜湊相同就不寫（效率評審 #4：沒變也整檔重寫會讓每台他機重新下載）。true＝寫了
    let export: @Sendable (_ folder: SyncFolder, _ at: Date) async throws -> Bool
    /// `known`＝各他機上次採用成功時的檔案大小與時間
    let read: @Sendable (_ folder: SyncFolder, _ known: [String: SyncFolder.FileStamp]) async -> CloudSyncRead

    static func make<Payload: Codable & Sendable>(
        kind: SyncKind, as type: Payload.Type,
        stamp: @escaping @Sendable (String) async throws -> Void,
        payload: @escaping @Sendable () async -> Payload,
        adopt: @escaping @Sendable ([SyncEnvelope<Payload>]) async -> CloudSyncAdoption
    ) -> CloudSyncChannel {
        let lastExport = LastExport()
        return CloudSyncChannel(
            kind: kind, stamp: stamp,
            export: { folder, date in
                let current = await payload()
                let hash = SyncCodec.payloadHash(current)
                // 上次匯出的雜湊記在記憶體；只有本 session 第一次才讀自己資料夾那份比對（效率評審 R2-1）
                let previous = await lastExport.hash ?? folder.ownPayloadHash(kind)
                guard hash != previous else {
                    await lastExport.set(hash)
                    return false
                }
                do {
                    try folder.write(current, kind: kind, at: date, hash: hash)
                } catch SyncFolder.Failure.tooLarge {
                    // 同一份不再重算重試；資料變了才再試（安全複查 N7）
                    await lastExport.set(hash)
                    throw SyncFolder.Failure.tooLarge
                }
                await lastExport.set(hash)
                return true
            },
            read: { folder, known in
                let scan = folder.readOthers(kind, as: type, unchangedSince: known)
                return CloudSyncRead(
                    writers: Dictionary(scan.envelopes.map { ($0.writerID, $0.writtenAt) }, uniquingKeysWith: max),
                    stamps: scan.stamps, skipped: scan.skipped, pendingDownloads: scan.pendingDownloads,
                    apply: { scan.envelopes.isEmpty ? .none : await adopt(scan.envelopes) }
                )
            }
        )
    }
}

/// 這個 channel 上次寫出（或確認相同）的 payload 雜湊
private actor LastExport {
    private(set) var hash: String?
    func set(_ value: String) { hash = value }
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

/// 限時執行（讀他機檔、退出前匯出共用；simplify 三視角同指）：工作放到 actor 外，逾時就回 nil、晚到的結果丟掉。
/// 不用 TaskGroup：它要等子工作結束，擋不住阻塞式檔案讀取
enum SyncDeadline {
    static func run<Value: Sendable>(
        _ budget: Duration, clock: any PollClock, _ work: @escaping @Sendable () async -> Value
    ) async -> Value? {
        let race = Race<Value>()
        return await withCheckedContinuation { continuation in
            race.begin(continuation)
            let timer = Task.detached {
                // 被取消（工作先做完）就不回報逾時——否則取消後的計時器可能搶先回 nil（R3 效率評審）
                guard (try? await clock.sleep(for: budget)) != nil, !Task.isCancelled else { return }
                race.finish(nil)
            }
            Task.detached {
                let value = await work()
                race.finish(value)
                timer.cancel()
            }
        }
    }

    /// 只讓第一個結果（做完或逾時）回去
    private final class Race<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value?, Never>?

        func begin(_ continuation: CheckedContinuation<Value?, Never>) {
            lock.withLock { self.continuation = continuation }
        }

        func finish(_ value: Value?) {
            let pending: CheckedContinuation<Value?, Never>? = lock.withLock {
                defer { continuation = nil }
                return continuation
            }
            pending?.resume(returning: value)
        }
    }
}
