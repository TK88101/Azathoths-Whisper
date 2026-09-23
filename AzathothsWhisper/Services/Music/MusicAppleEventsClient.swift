import AppKit
import CoreServices
import Foundation
import ScriptingBridge

// ScriptingBridge 對 Music.app 的介面宣告（手寫，免 sdp 產生標頭）。
// 由 M1 spike 實測確立（Scripts/spike/FINDINGS.md）。
// 明確的 ObjC 名稱讓執行期內省找得到這兩個 private 協議（計劃 AC9 ②：選擇器白名單測試）
@objc(AZWMusicTrackProto) private protocol MusicTrackProto {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var persistentID: String { get }
    @objc optional var lyrics: String { get }
    @objc optional var discNumber: Int { get }
    @objc optional var trackNumber: Int { get }
    @objc optional func setLyrics(_ value: String)
    @objc optional func artworks() -> SBElementArray
}

@objc(AZWMusicAppProto) private protocol MusicAppProto {
    @objc optional var playerState: UInt32 { get }
    @objc optional var currentTrack: SBObject { get }
    @objc optional func tracks() -> SBElementArray
}

extension SBApplication: MusicAppProto {}
extension SBObject: MusicTrackProto {}

// Apple Events 為同步阻塞呼叫，全部收攏到專用序列佇列，再以 continuation 轉成 async。
// 序列化同時避免打爆 Music.app（Cover Flow 取封面時尤其重要）。
struct MusicAppleEventsClient: MusicControlling {
    private static let queue = DispatchQueue(label: "com.ibridgezhao.azathothswhisper.applescript")
    private let bundleIdentifier: String

    init(bundleIdentifier: String = "com.apple.Music") {
        self.bundleIdentifier = bundleIdentifier
    }

    // MARK: MusicControlling

    func playerState() async throws -> PlayerState {
        try await run { app in
            Self.decodeState(app.playerState ?? 0)
        }
    }

    func currentTrack() async throws -> TrackInfo? {
        try await run { app in
            guard Self.decodeState(app.playerState ?? 0).hasCurrentTrack,
                  let track = app.currentTrack
            else { return nil }
            return Self.makeTrackInfo(track)
        }
    }

    func nowPlaying() async throws -> NowPlayingRead? {
        // 自行檢查 lastError：歌詞讀取失敗只讓歌詞成為 nil，曲目仍有效（run 的預設檢查會讓整次失敗）
        try await run(checksLastError: false) { app in
            guard Self.decodeState(app.playerState ?? 0).hasCurrentTrack,
                  let reference = app.currentTrack
            else {
                try Self.throwIfFailed(app)
                return nil
            }
            // D9：get() 把 `current track` 釘成 `file track id … of …`，之後每個屬性都讀同一首
            guard let pinned = reference.get() as? SBObject else {
                try Self.throwIfFailed(app)
                return nil
            }
            let track = Self.makeTrackInfo(pinned)
            try Self.throwIfFailed(app)
            let lyrics = (pinned as MusicTrackProto).lyrics
            let lyricsFailed = Self.lastError(of: app) != nil
            return NowPlayingRead(track: track, lyrics: lyricsFailed ? nil : (lyrics ?? ""))
        }
    }

    func trackDetails(persistentIDs: [String]) async throws -> [TrackDetails] {
        let ids = Array(Set(persistentIDs.filter { !$0.isEmpty })).sorted()
        guard !ids.isEmpty else { return [] }
        return try await run { app in
            // 預算從輪到本批執行時起算：量的是本批佔住 AE 佇列的時間。篩選也在同一預算內——
            // 實測它不另送 AE（S6：5 欄≈5 AE），但萬一送了也不得沒有上限
            let budget = AEBudget(total: Self.detailsBudget, start: .now)
            let sbApp = app as? SBApplication
            let setTimeout: (Int) -> Void = { sbApp?.timeout = $0 }
            guard budget.spend(setTimeout: setTimeout), let all = app.tracks?() else { return [] }
            let predicate = NSCompoundPredicate(
                orPredicateWithSubpredicates: ids.map { NSPredicate(format: "persistentID == %@", $0) }
            )
            // S6：OR 串接的 whose 一次取回元素，再逐屬性各一次批次取值（21 首約 5 AE、p50 51ms；逐首讀要 1 秒）。
            // Swift 端 filtered(using:) 回傳 [Any]，需轉回 SBElementArray 才能批次取值
            guard let matches = (all.filtered(using: predicate) as NSArray) as? SBElementArray else { return [] }
            // 每欄一個 AE（依 `TrackDetails.Column` 的順序）；送出前以剩餘預算當它的 timeout，用完整批作廢
            let columns = budget.readColumns(
                TrackDetails.Column.allCases.map(Self.selector),
                setTimeout: setTimeout,
                read: { matches.array(byApplying: $0) }
            )
            return columns.map(TrackDetails.fromColumns) ?? []
        }
    }

    func albumTracks(artist: String, album: String) async throws -> [AlbumTrack] {
        try await run { app in
            guard let all = app.tracks?() else { return [] }
            // py:1154-1183 的雙條件過濾（避免同名專輯串味）
            let predicate = NSPredicate(format: "album == %@ AND artist == %@", album, artist)
            return all.filtered(using: predicate).compactMap { element in
                guard let object = element as? SBObject else { return nil }
                let track = object as MusicTrackProto
                return AlbumTrack(
                    persistentID: track.persistentID ?? "",
                    artist: track.artist ?? "",
                    title: track.name ?? "",
                    album: track.album ?? "",
                    discNumber: track.discNumber ?? 0,
                    trackNumber: track.trackNumber ?? 0,
                    lyrics: track.lyrics ?? ""
                )
            }
        }
    }

    func setLyrics(persistentID: String, lyrics: String) async throws -> Bool {
        try await run { app in
            guard let track = Self.findTrack(persistentID: persistentID, in: app) else { return false }
            track.setLyrics?(lyrics)
            return (track.lyrics ?? "") == lyrics
        }
    }

    func artworkData(persistentID: String) async throws -> Data? {
        // 封面是 best-effort：逾時即放棄，不得拖住 monitor 的輪詢（見 artworkTimeoutTicks）
        try await run(aeTimeoutTicks: Self.artworkTimeoutTicks) { app in
            guard let track = Self.findTrack(persistentID: persistentID, in: app),
                  let artworks = track.artworks?(), artworks.count > 0,
                  let artwork = artworks.object(at: 0) as? SBObject
            else { return nil }

            // spike 陷阱 3：rawData 宣告成 Data/NSData 直接取用會炸（回傳未求值的 SBObject 代理）。
            // 正解＝KVC 取參照 → get() 強制求值 → 得 NSAppleEventDescriptor，其 .data 才是影像位元組。
            let reference = artwork.value(forKey: "rawData")
            let evaluated = (reference as? SBObject)?.get() ?? reference
            if let descriptor = evaluated as? NSAppleEventDescriptor {
                return descriptor.data
            }
            return evaluated as? Data
        }
    }

    // MARK: 內部

    private static func decodeState(_ raw: UInt32) -> PlayerState {
        switch raw {
        case 0x6B50_5350: return .playing   // 'kPSP'
        case 0x6B50_5370: return .paused    // 'kPSp'
        case 0x6B50_5353: return .stopped   // 'kPSS'
        default:
            let chars = [24, 16, 8, 0].compactMap { Unicode.Scalar((raw >> UInt32($0)) & 0xFF).map(Character.init) }
            return .other(String(chars))
        }
    }

    private static func selector(_ column: TrackDetails.Column) -> Selector {
        switch column {
        case .persistentID: return #selector(getter: MusicTrackProto.persistentID)
        case .artist: return #selector(getter: MusicTrackProto.artist)
        case .title: return #selector(getter: MusicTrackProto.name)
        case .album: return #selector(getter: MusicTrackProto.album)
        case .discNumber: return #selector(getter: MusicTrackProto.discNumber)
        case .trackNumber: return #selector(getter: MusicTrackProto.trackNumber)
        case .lyrics: return #selector(getter: MusicTrackProto.lyrics)
        }
    }

    private static func throwIfFailed(_ app: MusicAppProto) throws {
        if let error = lastError(of: app) {
            throw mapError(error)
        }
    }

    /// 協議存在值底下就是 run() 建的那個 SBApplication（@objc 協議，執行期可轉回）
    private static func lastError(of app: MusicAppProto) -> NSError? {
        (app as? SBApplication)?.lastError() as NSError?
    }

    private static func makeTrackInfo(_ track: SBObject) -> TrackInfo {
        let proto = track as MusicTrackProto
        return TrackInfo(
            persistentID: proto.persistentID ?? "",
            artist: proto.artist ?? "",
            title: proto.name ?? "",
            album: proto.album ?? "",
            discNumber: proto.discNumber ?? 0,
            trackNumber: proto.trackNumber ?? 0
        )
    }

    /// spike 陷阱 1：SBElementArray.filtered(using:) 在 Swift 回傳 [Any]，要用 .first 而非 .object(at:)
    private static func findTrack(persistentID: String, in app: MusicAppProto) -> MusicTrackProto? {
        guard !persistentID.isEmpty, let all = app.tracks?() else { return nil }
        let matches = all.filtered(using: NSPredicate(format: "persistentID == %@", persistentID))
        guard let object = matches.first as? SBObject else { return nil }
        return object as MusicTrackProto
    }

    /// AE reply 的等待上限，單位 ticks（1/60 秒）。
    ///
    /// 為何需要它（2026-08-23 M7 P1-2）：`body` 是**同步**執行在串行佇列上的 AE 呼叫，
    /// Swift 的 Task cancellation **不會**中斷已開始的 dispatch block——Swift 層的 timeout
    /// 只讓呼叫方放棄 continuation，那個 AE 操作仍佔著佇列，後續 `currentTrack()` 照樣排在後面。
    /// `SBApplication.timeout` 才是 AE reply 的實際等待上限，能讓呼叫本身逾時返回並**釋放佇列**。
    ///
    /// 誠實邊界：這只保證 client 端 bounded wait，**不保證**遠端操作被撤銷——
    /// Music.app 可能仍在服務端處理已送出的 Apple Event。
    static let artworkTimeoutTicks: Int = 90    // 1.5 秒；與 currentTrack() 合計須留在 H-04 的 3 秒內
    /// 卡片詳情一批的**總**時限（AC8d；約 7 個 AE，S6 實測整批 p95 76ms）：與 artwork 同為 1.5 秒，
    /// monitor 最多多等一批（見 `AEBudget`）
    static let detailsBudget: Duration = .milliseconds(1500)

    private func run<T: Sendable>(
        aeTimeoutTicks: Int? = nil,
        checksLastError: Bool = true,
        _ body: @escaping @Sendable (MusicAppProto) throws -> T
    ) async throws -> T {
        let identifier = bundleIdentifier
        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                // D10：以 pid 定址——Music 中途退出時 AE 以 -600 失敗，而不是把 Music 重新叫起來
                // （以 bundle ID 定址的 SBApplication 會啟動目標 app，那就改變了使用者的 Music 狀態）
                guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first,
                      !running.isTerminated,
                      let app = SBApplication(processIdentifier: running.processIdentifier)
                else {
                    continuation.resume(throwing: MusicError.notRunning)
                    return
                }
                // Music 端不得彈出任何需要使用者回應的互動（例如離線檔的提示）
                app.sendMode = AESendMode(kAEWaitReply | kAENeverInteract | kAEDontRecord)
                // 每次 run 都新建 SBApplication，故此設定是 per-call 的
                if let aeTimeoutTicks {
                    app.timeout = aeTimeoutTicks
                }
                do {
                    let value = try body(app as MusicAppProto)
                    // SBApplication 不拋錯，改用 lastError() 偵測 AE 失敗（-1743＝自動化權限被拒）
                    if checksLastError, let error = app.lastError() as NSError? {
                        continuation.resume(throwing: Self.mapError(error))
                        return
                    }
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func mapError(_ error: NSError) -> MusicError {
        switch error.code {
        case -1743: return .permissionDenied                 // errAEEventNotPermitted
        case -600, -609: return .notRunning                  // procNotFound／connectionInvalid（D10：Music 已退出）
        default: return .scriptingFailure("AE error \(error.code)")
        }
    }
}
