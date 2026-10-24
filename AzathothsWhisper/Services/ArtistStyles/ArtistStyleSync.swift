import Foundation
import OSLog

private let syncLog = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "artist-styles")

/// 背景查 MB（⑥b 計劃 §4.1、§4.5）：掃曲庫 → 扣掉已存的、樂團表的、全是日文歌的 → 曲多的先查；正在播的插隊。
/// 單一工作者，每查完一位就寫檔並發布新的 snapshot（中斷可續）。日誌只記計數與錯誤類型，不記歌手名、專輯名
actor ArtistStyleSync {
    typealias Identify = @Sendable (_ artist: String, _ albums: [String]) async throws(ProviderFailure) -> ArtistStyleBook.Lookup

    private let music: any MusicControlling
    private let store: ArtistStyleStore
    private let now: @Sendable () -> Date
    private let identify: Identify
    private let publish: @Sendable (ArtistStyleBook) async -> Void

    private var book = ArtistStyleBook()
    /// 排隊中（鍵＋曲庫裡這個鍵的所有寫法，第一個是查詢用的），只有它們能插隊
    private var queued: [(key: String, spellings: [String])] = []
    private var inFlight: String?

    init(
        music: any MusicControlling, store: ArtistStyleStore, now: @escaping @Sendable () -> Date = { Date() },
        identify: @escaping Identify, publish: @escaping @Sendable (ArtistStyleBook) async -> Void
    ) {
        self.music = music
        self.store = store
        self.now = now
        self.identify = identify
        self.publish = publish
    }

    /// 正在播的歌手插到隊首；查過的、正在查的、不在隊裡的不動
    func prioritize(artist: String) {
        let key = ArtistStyleBook.key(artist)
        guard key != inFlight, let index = queued.firstIndex(where: { $0.key == key }) else { return }
        let entry = queued.remove(at: index)
        queued.insert(entry, at: 0)
    }

    func run() async {
        let loaded = store.load()
        book = loaded.book
        await publish(book)
        guard loaded.isWritable else {
            syncLog.error("artist style file unreadable; not querying")
            return
        }
        guard let library = try? await music.libraryArtistAlbums() else {
            syncLog.error("library scan failed; will retry next launch")
            return
        }
        // 掃描時記下的撞鍵也要立刻生效，不能等下次啟動（simcodex R1 Codex）
        if prepareQueue(library) { await publish(book) }
        syncLog.info("artist styles queued=\(self.queued.count, privacy: .public) stored=\(self.book.records.count, privacy: .public)")
        while !Task.isCancelled, !queued.isEmpty {
            let next = queued.removeFirst()
            inFlight = next.key
            let keepGoing = await query(next.spellings)
            inFlight = nil
            if !keepGoing { break }
        }
        let summary = book.summary
        syncLog.info("artist styles verified=\(summary.verified, privacy: .public) unresolved=\(summary.unresolved, privacy: .public) remaining=\(self.queued.count, privacy: .public)")
    }

    /// 樂團表的團不查；寫法與撞鍵交給 book（`reconcilingLibrary`）；其餘還沒記錄的鍵排隊，曲多的先。true＝book 有變
    private func prepareQueue(_ library: [LibraryArtistAlbum]) -> Bool {
        // 先依寫法去重（曲庫幾萬首、寫法幾百個），之後的正規化都只做在寫法上
        let tracksBySpelling = Dictionary(library.map { ($0.artist, 1) }, uniquingKeysWith: +)
            .filter { !$0.key.isEmpty && SongProfileResolver.needsArtistGenres($0.key) }
        let before = book
        book = book.reconcilingLibrary(Array(tracksBySpelling.keys), at: now())
        let byKey: [String: [String]] = Dictionary(grouping: tracksBySpelling.keys, by: ArtistStyleBook.key)
        let pending: [(key: String, spellings: [String], tracks: Int)] = byKey.compactMap { key, spellings in
            guard !key.isEmpty, book.records[key] == nil else { return nil }
            return (key, spellings.sorted(), spellings.reduce(0) { $0 + (tracksBySpelling[$1] ?? 0) })
        }
        queued = pending.sorted { $0.tracks != $1.tracks ? $0.tracks > $1.tracks : $0.key < $1.key }.map { ($0.key, $0.spellings) }
        guard book != before else { return false }
        persist()
        return true
    }

    /// false＝本次停下（熔斷或取消）
    private func query(_ spellings: [String]) async -> Bool {
        var tracks: [ArtistTrack] = []
        for spelling in spellings {
            guard let read = try? await music.artistTracks(artist: spelling) else { return true }
            tracks += read
        }
        guard let artist = spellings.first, let albums = ArtistIdentity.albumsToCompare(tracks) else { return true }
        do {
            let lookup = try await identify(artist, albums)
            book = book.recording(lookup, forSpelling: artist, at: now()).noting(spellings: Array(spellings.dropFirst()))
            persist()
            await publish(book)
            return true
        } catch {
            let kind = OSLogTimingDiagnostics.name(error)
            syncLog.error("artist style query failed kind=\(kind, privacy: .public)")
            book = book.recordingNetworkFailure(kind, at: now())
            persist()
            return error != .circuitOpen && error != .cancelled
        }
    }

    private func persist() {
        do {
            try store.save(book)
        } catch {
            syncLog.error("artist style file not written")
        }
    }
}
