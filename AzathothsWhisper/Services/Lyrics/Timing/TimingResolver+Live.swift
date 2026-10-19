import Foundation

extension TimingResolver {
    /// 退路順序（C 段計劃 §3.5；使用者 2026-10-18：全開、不給選）。酷狗待 §9-1 拍板，未列入
    static func liveProviders(client: any HTTPClient) -> [any TimedLyricsProvider] {
        func gate(_ interval: TimeInterval) -> SourceGate {
            SourceGate(policy: .init(minimumInterval: interval), client: client)
        }
        return [
            LRCLIBProvider(gate: gate(LRCLIBProvider.minimumInterval)),
            YouTubeMusicProvider(gate: gate(defaultInterval)),
            DeezerProvider(gate: gate(defaultInterval)),
            QQMusicProvider(gate: gate(defaultInterval)),
            NetEaseProvider(gate: gate(defaultInterval)),
        ]
    }

    /// 非 LRCLIB 的來源沒有公開節流規則：探針 1.2 s 無 429，取 1 s
    static let defaultInterval: TimeInterval = 1

    /// 正式組裝：時間軸專用、不收不送 cookie 的連線；寫入觸發時向 Music 唯讀補讀 artist／title／duration
    static func live(music: any MusicControlling, defaults: UserDefaults = .standard) -> TimingResolver {
        let client = URLSessionHTTPClient(session: URLSession(configuration: URLSessionHTTPClient.cookielessConfiguration()))
        return TimingResolver(
            providers: liveProviders(client: client),
            store: TimingStore(directory: TimingStore.defaultDirectory),
            metadata: { persistentID in
                guard let details = try? await music.trackDetails(persistentIDs: [persistentID]).first else { return nil }
                return TimingQuery(artist: details.artist, title: details.title, duration: details.duration ?? 0)
            },
            switches: .read(from: defaults),
            diagnostics: OSLogTimingDiagnostics()
        )
    }
}
