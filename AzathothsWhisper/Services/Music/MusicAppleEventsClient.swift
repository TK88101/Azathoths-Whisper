import Foundation
import ScriptingBridge

// ScriptingBridge 對 Music.app 的介面宣告（手寫，免 sdp 產生標頭）。
// 由 M1 spike 實測確立（Scripts/spike/FINDINGS.md）。
@objc private protocol MusicTrackProto {
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

@objc private protocol MusicAppProto {
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

    func currentLyrics() async throws -> String {
        try await run { app in
            guard Self.decodeState(app.playerState ?? 0).hasCurrentTrack,
                  let track = app.currentTrack
            else { return "" }
            return (track as MusicTrackProto).lyrics ?? ""
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
        try await run { app in
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

    private func run<T: Sendable>(_ body: @escaping @Sendable (MusicAppProto) throws -> T) async throws -> T {
        let identifier = bundleIdentifier
        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                guard let app = SBApplication(bundleIdentifier: identifier), app.isRunning else {
                    continuation.resume(throwing: MusicError.notRunning)
                    return
                }
                do {
                    let value = try body(app as MusicAppProto)
                    // SBApplication 不拋錯，改用 lastError() 偵測 AE 失敗（-1743＝自動化權限被拒）
                    if let error = app.lastError() as NSError? {
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
        error.code == -1743 ? .permissionDenied : .scriptingFailure("AE error \(error.code)")
    }
}
