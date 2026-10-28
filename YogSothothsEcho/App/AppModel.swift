import Foundation
import QuartzCore
import Observation
import UIKit

/// 組裝根：建立服務並接線（Bjork 慣例）
@MainActor
@Observable
final class AppModel {
    let appearance: AppearanceViewModel
    /// F10 背景設定（CR-022）與詳情背景的產生／快取
    let background: BackgroundViewModel
    let detailBackground = DetailBackgroundController()
    /// CR-024 側封／小圖
    let browseLayout: BrowseLayoutViewModel
    let connection: ConnectionViewModel
    let library: LibraryViewModel
    let nowPlaying: NowPlayingViewModel
    let albumTracks: AlbumTracksViewModel
    /// 側封→詳情的開合轉場（S6 §4.5）：開＝載曲目、關完＝關清單
    let albumOpen: AlbumOpenController
    let turntable: TurntableViewModel
    /// 唱機原圖（CR-018）：連線時接上 Mac、斷線時解除
    let detailArtwork = DetailArtworkLoader()
    /// detail 原檔單飛排程（S6 D8）：唱機、開啟的專輯、瀏覽共用，同時只送一個
    let detailScheduler: DetailArtworkScheduler
    #if DEBUG
    /// N-01／B6／D2 量測（§4.12）
    let benchmark = ControlBenchmark()
    #endif
    /// 只在 DEBUG 的 UI 測試：以假載荷代替相機
    let fakePairingPayload: String?

    init(store: SettingsStore, connector: any RemoteConnecting, camera: any CameraAuthorizing, deviceName: String,
         fakePairingPayload: String? = nil) {
        appearance = AppearanceViewModel(store: store)
        background = BackgroundViewModel(store: store)
        browseLayout = BrowseLayoutViewModel(store: store)
        connection = ConnectionViewModel(connector: connector, camera: camera, deviceName: deviceName)
        library = LibraryViewModel(store: store)
        nowPlaying = NowPlayingViewModel()
        albumTracks = AlbumTracksViewModel()
        let detailArtwork = detailArtwork, detailSession = SerialTaskChain()
        let detailScheduler = DetailArtworkScheduler(cached: { await detailArtwork.cachedData(albumID: $0, token: $1) },
                                                     fetch: { await detailArtwork.fetchData(albumID: $0, token: $1) },
                                                     evict: { await detailArtwork.evict(albumID: $0, token: $1) })
        self.detailScheduler = detailScheduler
        library.browseArtwork = BrowseArtwork(
            request: { await detailScheduler.request(albumID: $0, token: $1, priority: $2) },
            decode: { await DetailArtworkDecoder.decoded($0, maxPixels: $1) },
            sleep: { try? await Task.sleep(for: $0) })
        let library = library
        // 唱機封面：先用曲庫的 spine，再換 Mac 的原檔（CR-018）；專輯不在已載入的清單裡＝佔位
        turntable = TurntableViewModel(
            nowPlaying: nowPlaying, skin: .classic, store: store, displayScale: 2,   // 視圖出現時改用畫面的實際值
            artwork: { id in
                guard let album = library.albums.first(where: { $0.id == id }) else { return nil }
                return await library.image(for: album)
            },
            detailArtwork: { id in
                let token = library.albums.first(where: { $0.id == id })?.artworkToken
                return await detailScheduler.image(albumID: id, token: token, priority: .turntable)
            },
            palette: { image in AlbumPalette.extract(from: image) },
            catalog: TurntableSkinCatalog.load(reader: MainBundleSkinReader()))   // CR-034：preflight 不過的皮膚不列入
        albumOpen = AlbumOpenController(
            now: { CACurrentMediaTime() }, sleep: { try? await Task.sleep(for: $0) },
            spineCover: { await library.image(for: $0) },
            detailCover: { await detailScheduler.image(albumID: $0.id, token: $0.artworkToken, priority: .opened) })
        self.fakePairingPayload = fakePairingPayload
        // 跨 feature 只經組裝根接線（Bjork 慣例）
        let nowPlaying = self.nowPlaying, albumTracks = self.albumTracks
        nowPlaying.albumLookup = { id in library.albums.first { $0.id == id } }
        albumTracks.onResync = { nowPlaying.resync() }
        albumOpen.onOpen = { album in Task { await albumTracks.open(album) } }
        albumOpen.onClosed = { albumTracks.close() }
        #if DEBUG
        let benchmark = self.benchmark
        benchmark.current = { nowPlaying.clock?.event }
        benchmark.position = { nowPlaying.position() }
        nowPlaying.onEventAdopted = { benchmark.eventArrived($0) }
        #endif
        connection.onSessionOpened = { client, playback in
            library.attach(client)
            nowPlaying.attach(playback)
            if let detail = client as? any DetailArtworkRequesting { detailSession.enqueue { await detailArtwork.attach(detail) } }
            albumTracks.attach(playback)
            #if DEBUG
            benchmark.attach(playback, receipt: { id in await client.measurementReceipt(id: id) })
            #endif
        }
        connection.onSessionClosed = {
            library.detach()
            nowPlaying.detach()
            // 先取消再解除，且與下一次 attach 串在同一條鏈上：快速斷線重連時 cancelAll 不會誤殺新連線的請求
            detailSession.enqueue {
                await detailScheduler.cancelAll()
                await detailArtwork.detach()
            }
            albumTracks.detach()
            #if DEBUG
            benchmark.detach()
            #endif
        }
    }

    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        let store = UserDefaultsSettingsStore()
        var connector: any RemoteConnecting = LiveRemoteConnector()
        var camera: any CameraAuthorizing = LiveCameraAuthorization()
        var fakePayload: String?
        #if DEBUG
        if arguments.contains(AccessibilityID.resetSettingsArgument) {
            store.removeValue(forKey: AppearanceViewModel.storageKey)
            store.removeValue(forKey: BackgroundViewModel.presetKey)
            store.removeValue(forKey: BackgroundViewModel.detailModeKey)
            store.removeValue(forKey: BrowseLayoutViewModel.storageKey)
            store.removeValue(forKey: LibraryViewModel.anchorKey)
            store.removeValue(forKey: TurntableViewModel.skinKey)
        }
        if arguments.contains(AccessibilityID.resetPositionArgument) { store.removeValue(forKey: LibraryViewModel.anchorKey) }
        connector = UITestSupport.connector(arguments) ?? connector
        let forgetsAfterDelay = arguments.contains(AccessibilityID.forgetAfterDelayArgument)
        camera = UITestSupport.camera(arguments) ?? camera
        fakePayload = UITestSupport.fakePayload(arguments)
        // 要在 LibraryViewModel 建封面快取之前：沒預約的啟動一律是 warm（FrameRateMonitor 預設）
        if ColdStartRequest.consume(directory: ArtworkCache.defaultDirectory) { FrameRateMonitor.shared.cache = .cold }
        #endif
        let model = AppModel(store: store, connector: connector, camera: camera, deviceName: UIDevice.current.name,
                             fakePairingPayload: fakePayload)
        #if DEBUG
        if forgetsAfterDelay {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                await model.connection.forgetMac()
            }
        }
        #endif
        return model
    }
}

/// 依呼叫順序一個接一個執行的非同步工作（連線開關事件各開 Task 時，跨 actor 的先後不保證）
@MainActor
final class SerialTaskChain {
    private var last: Task<Void, Never>?

    func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let previous = last
        last = Task {
            await previous?.value
            await work()
        }
    }
}
