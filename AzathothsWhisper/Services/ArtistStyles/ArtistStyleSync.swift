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
        prepareQueue(library)
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

    /// 依鍵分組：已有記錄的併寫法（或記撞鍵）；新鍵上有不同寫法＝撞鍵、不查；其餘排隊，曲多的先
    private func prepareQueue(_ library: [LibraryArtistAlbum]) {
        let spellingsByKey = Dictionary(grouping: library.map(\.artist).filter { !$0.isEmpty }, by: ArtistStyleBook.key)
        let before = book
        book = book.noting(spellings: Array(Set(library.map(\.artist))))
        var pending: [(key: String, spellings: [String], tracks: Int)] = []
        for (key, spellings) in spellingsByKey where !key.isEmpty && !book.hasRecord(forArtist: spellings[0]) {
            guard SongProfileResolver.overrides[key] == nil else { continue }
            let distinct = Set(spellings).sorted()
            let families = Set(distinct.map(ArtistStyleBook.spellingFamily))
            if families.count > 1 {
                book = book.recording(.unresolved(.collision), forSpelling: distinct[0], at: now()).noting(spellings: Array(distinct.dropFirst()))
                continue
            }
            pending.append((key, distinct, spellings.count))
        }
        queued = pending.sorted { $0.tracks != $1.tracks ? $0.tracks > $1.tracks : $0.key < $1.key }.map { ($0.key, $0.spellings) }
        if book != before { persist() }
    }

    /// false＝本次停下（熔斷或取消）
    private func query(_ spellings: [String]) async -> Bool {
        var tracks: [ArtistTrack] = []
        for spelling in spellings {
            guard let read = try? await music.artistTracks(artist: spelling) else { return true }
            tracks += read
        }
        guard let artist = spellings.first, !tracks.isEmpty else { return true }
        let nonJapanese = tracks.filter { !LyricsScript.isJapaneseSong($0.lyrics) }
        guard !nonJapanese.isEmpty else { return true }
        let albums = ArtistIdentity.outgoingAlbums(nonJapanese.map(\.album))
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
