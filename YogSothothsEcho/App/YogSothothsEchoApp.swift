import SwiftUI

@main
struct YogSothothsEchoApp: App {
    @State private var model = AppModel.live()
    @Environment(\.scenePhase) private var scenePhase

    private var shell: ShellView {
        #if DEBUG
        ShellView(appearance: model.appearance, background: model.background, detailBackground: model.detailBackground, browseLayout: model.browseLayout,
                  connection: model.connection, library: model.library,
                  nowPlaying: model.nowPlaying, albumTracks: model.albumTracks, albumOpen: model.albumOpen, turntable: model.turntable,
                  fakePayload: model.fakePairingPayload, benchmark: model.benchmark)
        #else
        ShellView(appearance: model.appearance, background: model.background, detailBackground: model.detailBackground, browseLayout: model.browseLayout,
                  connection: model.connection, library: model.library,
                  nowPlaying: model.nowPlaying, albumTracks: model.albumTracks, albumOpen: model.albumOpen, turntable: model.turntable,
                  fakePayload: model.fakePairingPayload)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            shell.preferredColorScheme(model.appearance.setting.colorScheme)
        }
        // 回前景重新瀏覽並自動重連；進背景丟棄掃描與配對中狀態（CR-010 ②(l)）
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: Task { await model.connection.resume() }
            case .inactive: model.library.flushBrowseAnchor()
            case .background:
                // 位置記憶先寫盤（慣性中關 App 也保住；CR-027）
                model.library.flushBrowseAnchor()
                model.connection.suspend()
                // 唱機沒開著就放掉序列圖（CR-034 附錄 F）
                model.turntable.releaseSpritesIfHidden()
            default: break
            }
        }
    }
}
