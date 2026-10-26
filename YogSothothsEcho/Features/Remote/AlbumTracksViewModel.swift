import Foundation
import Observation
import RemoteProtocol
import RemoteTransport

/// 控制用極簡曲目選擇器（sprint-4-detail.md §4.8；CR-013(f)，正式詳情頁是 S6）：點專輯格進入、分頁取完曲目、點曲目＝點歌。
/// 清單載入與點歌各自一個世代（S3 T11 的教訓：不共用）；點了新的一首，舊的點歌結果不改畫面
@MainActor
@Observable
final class AlbumTracksViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(Failure)
    }

    enum Failure: Equatable { case libraryUnavailable, network }

    private(set) var album: AlbumSummary?
    private(set) var songs: [TrackSummary] = []
    /// false＝許可閘門不放行：點歌只會播單曲（列首事先提示）
    private(set) var contextPlayable = true
    private(set) var phase: Phase = .idle
    /// 點了、Mac 還沒回結果
    private(set) var pendingTrackID: String?
    /// 「重新同步」：由組裝根接到 NowPlayingViewModel
    @ObservationIgnored var onResync: (() -> Void)?

    private let fader: FadingNotice
    /// 曲目頁遇 busy／rateLimited 的短重試（F-L1）；`sleep` 只給 FadingNotice，不共用
    @ObservationIgnored private let shortRetry: ShortTransientRetry.Options
    @ObservationIgnored private var client: (any PlaybackClient)?
    @ObservationIgnored private var loadGeneration = 0
    /// 實際在跑 `allTracks` 的那一個：斷線、關閉、換專輯時取消（F7）；世代守衛仍是第二道
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var playGeneration = 0
    @ObservationIgnored private var lastPlayed: TrackSummary?

    init(sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         retry: ShortTransientRetry.Options = .live) {
        fader = FadingNotice(sleep: sleep)
        shortRetry = retry
    }

    var notice: PlaybackPresentation.Notice? { fader.current }
    var canPlay: Bool { client != nil && phase == .ready }

    // MARK: 連線

    /// 斷線期間開的、或載到一半被斷線打斷的專輯，重連後自動載入（F7）
    func attach(_ client: any PlaybackClient) {
        self.client = client
        guard album != nil, phase != .ready else { return }
        Task { await load() }
    }

    /// 不改 phase：重連前維持轉圈
    func detach() {
        client = nil
        cancelLoad()
        playGeneration += 1
        pendingTrackID = nil
    }

    // MARK: 清單

    func open(_ album: AlbumSummary) async {
        self.album = album
        songs = []
        contextPlayable = true
        phase = .loading
        show(nil)
        await load()
    }

    func retry() async { await load() }

    func close() {
        cancelLoad()
        album = nil
        songs = []
        phase = .idle
        pendingTrackID = nil
        show(nil)
    }

    private func cancelLoad() {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
    }

    private func load() async {
        guard let client, let album else { return }
        cancelLoad()
        let token = loadGeneration, retry = shortRetry
        phase = .loading
        let task = Task { [weak self] in
            let result: Result<(songs: [TrackSummary], contextPlayable: Bool), EchoRequestError>
            do throws(EchoRequestError) { result = .success(try await client.allTracks(albumID: album.id, retry: retry)) } catch { result = .failure(error) }
            self?.finishLoad(result, token: token)
        }
        loadTask = task
        await task.value
    }

    private func finishLoad(_ result: Result<(songs: [TrackSummary], contextPlayable: Bool), EchoRequestError>, token: Int) {
        guard token == loadGeneration else { return }
        loadTask = nil
        switch result {
        case .success(let tracks):
            songs = tracks.songs
            contextPlayable = tracks.contextPlayable
            phase = .ready
        case .failure(let error):
            phase = .failed(error == .remote(.libraryUnavailable) ? .libraryUnavailable : .network)
        }
    }

    // MARK: 點歌

    func play(_ song: TrackSummary) async {
        guard let client, let album else { return }
        playGeneration += 1
        let token = playGeneration
        lastPlayed = song
        pendingTrackID = song.id
        show(nil)
        let result: Result<PlayResult, EchoRequestError>
        do { result = .success(try await client.play(trackID: song.id, albumID: album.id)) } catch { result = .failure(error) }
        guard token == playGeneration else { return }
        pendingTrackID = nil
        switch result {
        case .success(let outcome): show(PlaybackPresentation.notice(for: outcome))
        case .failure(let error): show(PlaybackPresentation.notice(for: error))
        }
    }

    /// 詳情層的 Play 鈕（S6 §4.6）：從排序後第一首播起，走同一個 play.track 專輯脈絡（contextPlayable＝false 時照 S4 只播那首並提示）
    func playFirst() async {
        guard let first = AlbumDetailPresentation.ordered(songs).first else { return }
        await play(first)
    }

    /// 提示上的「重試」：重點上一次點的那首
    func retryPlay() async {
        guard let lastPlayed else { return }
        await play(lastPlayed)
    }

    func resync() {
        show(nil)
        onResync?()
    }

    private func show(_ notice: PlaybackPresentation.Notice?) { fader.show(notice) }
}
