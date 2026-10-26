import Foundation
#if DEBUG
import OSLog
#endif
import RemoteProtocol
import RemoteTransport

/// detail 封面（原檔分塊，CR-018；sprint-5-detail.md §11）的 iPad 接收端：part 0 → 其餘最多 2 塊並行 → 組裝驗證。
/// restart＝換新世代從 part 0 重來（最多 2 次）；stale／none／tooLarge／錯誤／取消＝不可用（呼叫端沿用 spine）
struct DetailArtworkFetcher: Sendable {
    typealias Request = @Sendable (_ part: Int, _ digest: String?, _ generation: UInt64) async throws(EchoRequestError) -> ArtworkResponse

    enum Outcome: Equatable, Sendable {
        case image(Data)
        case unavailable
        /// 曲庫已換版：呼叫端不寫快取、以新 token 重取
        case stale
    }

    static let maxRestarts = 2
    static let parallelParts = 2

    /// 暫存檔所在目錄（App 沙盒內固定位置；啟動時由呼叫端清空）
    let directory: URL
    /// 每次開始一個傳輸取一個只增不減的世代（Mac 以它防遲到的舊 part 0）
    let nextGeneration: @Sendable () -> UInt64
    /// Mac 回 busy／rateLimited 時同一塊的重試（與 spine 的 ArtworkCache 同一規則 ShortTransientRetry；測試注入即刻返回的 sleeper）
    var retry: ShortTransientRetry.Options = .live

    func fetch(albumID: String, token: String, request: @escaping Request) async -> Outcome {
        let started = Date()
        for round in 0...Self.maxRestarts {
            switch await attempt(albumID: albumID, token: token, request: request) {
            case .done(let outcome):
                Self.trace(albumID, "done \(Self.describe(outcome)) round=\(round) elapsed=\(Self.elapsed(since: started))")
                return outcome
            case .restart:
                Self.trace(albumID, "restart round=\(round)")
                continue
            }
        }
        Self.trace(albumID, "restarts exhausted elapsed=\(Self.elapsed(since: started))")
        return .unavailable
    }

    #if DEBUG
    /// v2.1 T4 延伸：唱機封面只停在 spine（Rise Against《Appeal to Reason》4.98 MB PNG）時查原因；只記 albumID 與結果，不記曲名
    private static let traceLog = Logger(subsystem: "com.ibridgezhao.yogsothothsecho", category: "detail")
    #endif

    static func trace(_ albumID: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        traceLog.notice("detail album=\(albumID, privacy: .public) \(text, privacy: .public)")
        #endif
    }

    private static func describe(_ outcome: Outcome) -> String {
        switch outcome {
        case .image(let data): "image bytes=\(data.count)"
        case .unavailable: "unavailable"
        case .stale: "stale"
        }
    }

    private static func elapsed(since start: Date) -> String { String(format: "%.2fs", Date().timeIntervalSince(start)) }

    private enum Attempt { case done(Outcome), restart }

    private enum Reply {
        case part(ArtworkDetailPart)
        case restart, stale, failed
    }

    private func attempt(albumID: String, token: String, request: @escaping Request) async -> Attempt {
        let generation = nextGeneration()
        let retry = retry
        let first: Reply = await Self.ask(albumID: albumID, token: token, part: 0, digest: nil, generation: generation,
                                          retry: retry, request: request)
        guard case .part(let head) = first else { return Self.settle(first) }
        Self.trace(albumID, "head total=\(head.totalBytes) parts=\(head.partCount) mime=\(head.mime)")
        guard let assembly = try? DetailAssembly(first: head, directory: directory) else {
            Self.trace(albumID, "assembly init failed")
            return .done(.unavailable)
        }
        defer { assembly.discard() }
        let remaining = Array(1..<head.partCount)
        var next = remaining.makeIterator()
        let outcome: Attempt? = await withTaskGroup(of: (Int, Reply).self) { group in
            func launch() -> Bool {
                guard let index = next.next() else { return false }
                group.addTask {
                    (index, await Self.ask(albumID: albumID, token: token, part: index, digest: head.digest, generation: generation,
                                           retry: retry, request: request))
                }
                return true
            }
            for _ in 0..<Self.parallelParts {
                guard launch() else { break }
            }
            while let (index, reply) = await group.next() {
                guard case .part(let part) = reply, part.part == index, assembly.accept(part) else {
                    Self.trace(albumID, "part=\(index) rejected")
                    group.cancelAll()
                    return Self.settle(reply)
                }
                if Task.isCancelled { group.cancelAll(); return .done(.unavailable) }
                _ = launch()
            }
            return nil
        }
        if let outcome { return outcome }
        guard !Task.isCancelled, let data = assembly.finish() else {
            Self.trace(albumID, "finish failed cancelled=\(Task.isCancelled)")
            return .done(.unavailable)
        }
        return .done(.image(data))
    }

    /// 非 part 的回覆怎麼收場（part 卻不符＝failed）
    private static func settle(_ reply: Reply) -> Attempt {
        switch reply {
        case .restart: .restart
        case .stale: .done(.stale)
        case .part, .failed: .done(.unavailable)
        }
    }

    private static func ask(albumID: String, token: String, part: Int, digest: String?, generation: UInt64,
                            retry: ShortTransientRetry.Options, request: @escaping Request) async -> Reply {
        var attempt = 1
        while true {
            guard !Task.isCancelled else { return .failed }
            do {
                return validate(try await request(part, digest, generation), albumID: albumID, token: token, part: part)
            } catch {
                trace(albumID, "part=\(part) error=\(error) attempt=\(attempt)")
                // Mac 每秒讀取有配額（側封快甩時 spine 請求會用完）：被擋＝退避重試同一塊，不放棄整張。
                // 睡眠被取消或拋其他錯誤＝該塊失敗（既有的取消結果同樣是 failed；Codex R5-2）
                guard ShortTransientRetry.shouldRetry(error, afterAttempt: attempt),
                      (try? await retry.pause(beforeAttempt: attempt + 1)) != nil
                else { return .failed }
                attempt += 1
            }
        }
    }

    private static func validate(_ response: ArtworkResponse, albumID: String, token: String, part: Int) -> Reply {
        guard response.isValid, response.size == .detail, response.albumID == albumID else {
            trace(albumID, "part=\(part) invalid response")
            return .failed
        }
        switch response.outcome {
        case .image:
            guard response.artworkToken == token, let detail = response.detail else {
                trace(albumID, "part=\(part) token or payload mismatch")
                return .failed
            }
            return .part(detail)
        case .restart: return .restart
        case .stale: return .stale
        case .none, .tooLarge:
            trace(albumID, "part=\(part) outcome=\(response.outcome)")
            return .failed
        }
    }
}

/// 一次 detail 傳輸的組裝：暫存檔依 offset 寫入＋已收塊位圖（不以檔案長度判斷完成）；
/// 每塊 metadata 須與 part 0 相同；組完驗完整 SHA-256 與 magic bytes 才交出。暫存檔一律由 `discard` 清掉
final class DetailAssembly {
    private let head: ArtworkDetailPart
    private let file: URL
    private let handle: FileHandle
    private var received: Set<Int> = []

    init(first: ArtworkDetailPart, directory: URL) throws {
        guard first.isValid, first.part == 0, first.totalBytes <= DetailArtworkLimits.maxTotalBytes else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(UUID().uuidString + ".part", isDirectory: false)
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        self.file = file
        handle = try FileHandle(forWritingTo: file)
        head = first
        guard accept(first) else { discard(); throw CocoaError(.fileWriteUnknown) }
    }

    /// 重複的塊冪等（已收過就略過）；metadata 不符或寫入失敗＝false
    func accept(_ part: ArtworkDetailPart) -> Bool {
        guard part.isValid, part.digest == head.digest, part.mime == head.mime, part.totalBytes == head.totalBytes,
              part.partCount == head.partCount else { return false }
        guard !received.contains(part.part) else { return true }
        do {
            try handle.seek(toOffset: UInt64(part.part * DetailArtworkLimits.chunkBytes))
            try handle.write(contentsOf: part.chunk)
        } catch { return false }
        received.insert(part.part)
        return true
    }

    /// 全部塊到齊、SHA-256 與宣告相同、magic bytes 與宣告的格式相同才回原檔
    func finish() -> Data? {
        guard received.count == head.partCount, (try? handle.synchronize()) != nil,
              let data = try? Data(contentsOf: file), data.count == head.totalBytes,
              data.sha256Hex == head.digest,
              ArtworkMime.sniff(data) == head.mime else { return nil }
        return data
    }

    func discard() {
        try? handle.close()
        try? FileManager.default.removeItem(at: file)
    }
}
