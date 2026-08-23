import AppKit
import Foundation
import Testing

@testable import AzathothsWhisper

// Cover Flow 的狀態機（M7 P1-3）。對應 ACCEPTANCE H-01／H-04／H-05／H-06／H-11。
//
// 守衛只有兩個（非 Plan 草案的三個）：albumGeneration 與 centerTrackID。
// per-item artworkToken 移到 P2——P1 無預取，圖片由 View 的 .task 按需取、
// SwiftUI 在 view 消失時自動取消，沒有 VM 層的回寫路徑可被污染。
@MainActor
@Suite("CoverFlowViewModel")
struct CoverFlowViewModelTests {
    private let albumKey = "Dark Tranquillity\u{1}Damage Done"

    private var tracks: [AlbumTrack] {
        [
            .fixture(id: "T1", title: "Alpha", track: 1),
            .fixture(id: "T2", title: "Beta", track: 2),
            .fixture(id: "T3", title: "Gamma", track: 3),
        ]
    }

    private func makeModel(
        albumTracks: [AlbumTrack]? = nil,
        music: MockMusicClient? = nil
    ) async -> (CoverFlowViewModel, MockMusicClient) {
        let client = music ?? MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await client.setAlbumTracks(albumTracks ?? tracks)
        let model = CoverFlowViewModel(
            music: client,
            artwork: StubArtworkProvider()
        )
        return (model, client)
    }

    // MARK: H-01 懶載入

    @Test func activatingTabWithEmptyListLoads() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        #expect(model.items.count == 3)
    }

    @Test func activatingTabWithLoadedListDoesNotReload() async {
        let (model, music) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        let calls = await music.albumTracksCalls

        model.tabDeactivated()
        model.tabActivated()
        await model.loadTask?.value
        #expect(await music.albumTracksCalls == calls, "已有資料不得重載")
    }

    // MARK: H-06 切專輯用事件裡的 albumKey，不重讀 currentTrack

    /// 事件發布後再讀 currentTrack() 可能拿到**已切走的下一張**專輯
    @Test func albumChangedQueriesUsingEventKeyNotCurrentTrack() async {
        let (model, music) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value

        // 讓 currentTrack() 回一張**不同**的專輯——若實作誤讀它就會用錯參數
        await music.setScript([.track(.fixture(id: "OTHER", artist: "Wrong", album: "Wrong Album"), lyrics: "")])
        await model.handle(.albumChanged("Opeth\u{1}Blackwater Park"))
        await model.loadTask?.value

        let (artist, album) = await music.lastAlbumTracksQuery ?? ("", "")
        #expect(artist == "Opeth", "須用事件 albumKey 的 artist")
        #expect(album == "Blackwater Park", "須用事件 albumKey 的 album")
    }

    /// 過期的 albumGeneration 不得回寫
    @Test func staleAlbumLoadDoesNotOverwriteNewer() async {
        let gate = LyricsGate()
        let music = MockMusicClient(script: [.track(.fixture(), lyrics: "")])
        await music.setAlbumTracks(tracks)
        await music.setAlbumTracksGate(gate)
        let model = CoverFlowViewModel(music: music, artwork: StubArtworkProvider())
        model.tabActivated()

        let stale = model.loadTask
        await settle()

        // 切到新專輯（generation 遞增），新載入不卡
        await music.setAlbumTracksGateQueue([gate, LyricsGate.opened()])
        await music.setAlbumTracks([.fixture(id: "N1", title: "NewOne")])
        await model.handle(.albumChanged("Opeth\u{1}Blackwater Park"))
        await model.loadTask?.value
        await gate.open()
        await stale?.value

        #expect(model.items.map(\.persistentID) == ["N1"], "過期載入不得覆蓋新專輯")
    }

    /// H-01 的懶載入必須也擋住**事件驅動**的載入：Cover Flow 不可見時切專輯只清空，
    /// 不得發 AE 查詢——那既違反懶載入，也會往共用的串行 AE 佇列塞工作、
    /// 拖慢 monitor 與 Editor（對齊 Batch 的 C-17）
    @Test func albumChangeWhileHiddenClearsWithoutLoading() async {
        let (model, music) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        let callsAfterInitialLoad = await music.albumTracksCalls

        model.tabDeactivated()
        await model.handle(.albumChanged("Opeth\u{1}Blackwater Park"))
        await model.loadTask?.value

        #expect(model.items.isEmpty, "切專輯須清空列表")
        #expect(await music.albumTracksCalls == callsAfterInitialLoad, "不可見時不得發 AE 查詢")
    }

    /// 不可見時記住的專輯，切回 tab 時才載入
    @Test func hiddenAlbumChangeLoadsOnReactivation() async {
        let (model, music) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value

        model.tabDeactivated()
        await music.setAlbumTracks([.fixture(id: "N1", title: "NewOne")])
        await model.handle(.albumChanged("Opeth\u{1}Blackwater Park"))
        await model.loadTask?.value

        model.tabActivated()
        await model.loadTask?.value

        #expect(model.items.map(\.persistentID) == ["N1"])
        let (artist, _) = await music.lastAlbumTracksQuery ?? ("", "")
        #expect(artist == "Opeth", "切回時須用當初記住的 albumKey，而非重讀 currentTrack")
    }

    // MARK: H-04 切歌居中

    @Test func trackChangeCentersOnThatTrack() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value

        await model.handle(.trackChanged(.fixture(id: "T3", title: "Gamma"), existingLyrics: ""))
        #expect(model.centerID == "T3")
    }

    /// 快速連續切歌只停在最後一首
    @Test func rapidTrackChangesLandOnLast() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value

        await model.handle(.trackChanged(.fixture(id: "T2", title: "Beta"), existingLyrics: ""))
        await model.handle(.trackChanged(.fixture(id: "T3", title: "Gamma"), existingLyrics: ""))
        #expect(model.centerID == "T3")
    }

    /// 不在列表中的曲目不改變中心（切到別張專輯的曲目時，等 albumChanged 重建）
    @Test func trackNotInListLeavesCenterAlone() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        await model.handle(.trackChanged(.fixture(id: "T2"), existingLyrics: ""))

        await model.handle(.trackChanged(.fixture(id: "ELSEWHERE"), existingLyrics: ""))
        #expect(model.centerID == "T2")
    }

    // MARK: H-05 手動滑走後不搶控制

    @Test func manualScrollSuppressesAutoCenter() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        await model.handle(.trackChanged(.fixture(id: "T1"), existingLyrics: ""))

        model.userDidScroll(to: "T3")
        await model.handle(.trackChanged(.fixture(id: "T1"), existingLyrics: ""))
        #expect(model.centerID == "T3", "手動滑走後同曲事件不得搶回控制")
    }

    /// **真實切歌**＝persistentID 變更。forceRefresh 對同一曲重發事件不算
    @Test func sameTrackRefreshDoesNotClearOverride() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        await model.handle(.trackChanged(.fixture(id: "T1"), existingLyrics: ""))

        model.userDidScroll(to: "T3")
        // forceRefresh 會對同一曲再發一次 trackChanged
        await model.handle(.trackChanged(.fixture(id: "T1"), existingLyrics: "again"))
        #expect(model.centerID == "T3", "同曲 refresh 不是真實切歌，不得解除抑制")
    }

    @Test func realTrackChangeClearsOverrideAndCenters() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        await model.handle(.trackChanged(.fixture(id: "T1"), existingLyrics: ""))

        model.userDidScroll(to: "T3")
        await model.handle(.trackChanged(.fixture(id: "T2", title: "Beta"), existingLyrics: ""))
        #expect(model.centerID == "T2", "真實切歌須解除抑制並居中")
    }

    /// 切專輯明確重置抑制——新專輯應回到目前播放曲
    @Test func albumChangeResetsOverride() async {
        let (model, music) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        model.userDidScroll(to: "T3")

        await music.setAlbumTracks([.fixture(id: "N1", title: "NewOne"), .fixture(id: "N2", title: "NewTwo")])
        await model.handle(.albumChanged("Opeth\u{1}Blackwater Park"))
        await model.loadTask?.value
        await model.handle(.trackChanged(.fixture(id: "N2", title: "NewTwo"), existingLyrics: ""))

        #expect(model.centerID == "N2", "切專輯須重置抑制")
    }

    /// 程式化居中**落定後**的回呼（id 已等於 centerID）不得把抑制旗標設回 true。
    ///
    /// 注意這條**只驗落定態**：`id != centerID` 這個條件本身就擋下了它，
    /// 不足以證明 `isCenteringProgrammatically` 有效。真正檢驗該旗標的是下一條。
    @Test func settledProgrammaticCallbackDoesNotSetOverride() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value

        await model.handle(.trackChanged(.fixture(id: "T2"), existingLyrics: ""))
        model.scrollPositionDidChange(to: "T2")
        await model.handle(.trackChanged(.fixture(id: "T3"), existingLyrics: ""))

        #expect(model.centerID == "T3")
    }

    /// **已知限制**（2026-08-23 altitude 審查揭露，如實記錄而非假裝已解決）：
    ///
    /// `scrollPositionDidChange` 無法區分「使用者拖曳」與「程式化動畫的途經回呼」——
    /// 只要回報的 id 與目前 centerID 不同，一律當成使用者接管。
    /// `isCenteringProgrammatically` 的保護窗口是**同步**的（set → 寫 centerID → clear
    /// 全程無 await），擋不住動畫展開期間跨幀送來的途經回呼。
    ///
    /// **目前尚未爆出**：P1 的居中是同步賦值、沒有 `withAnimation`，不產生途經回呼，
    /// 故只有真正的使用者拖曳才會送來不同的 id。
    ///
    /// **M8 導入平滑動畫（H-04「自動平滑居中」）時必須先修**：讓旗標的清除時機覆蓋
    /// 動畫的實際持續期，而非函式呼叫的同步範圍。否則使用者從未碰觸捲動條，
    /// 卻會因途經回呼被誤判為接管，此後自動居中永久失靈。
    ///
    /// 本條釘住的是**當前的實際行為**（不同 id 即視為接管），而非期望行為——
    /// 修好之後這條會轉紅，屆時請連同上述註釋一起更新。
    @Test func differentIDCallbackIsTreatedAsUserTakeoverEvenIfProgrammatic() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        await model.handle(.trackChanged(.fixture(id: "T1"), existingLyrics: ""))

        // 模擬動畫途經 T2（使用者其實沒碰過捲動條）
        model.scrollPositionDidChange(to: "T2")

        // 同曲 refresh 此時搶不回控制——因為途經回呼已被記為「使用者接管」
        await model.handle(.trackChanged(.fixture(id: "T1"), existingLyrics: "refresh"))
        #expect(
            model.centerID == "T2",
            "當前行為：途經回呼被當成使用者接管。修好動畫期保護後本條應轉紅"
        )
    }

    // MARK: H-09 鍵盤步進

    @Test func stepMovesCenterByOffset() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        await model.handle(.trackChanged(.fixture(id: "T1"), existingLyrics: ""))

        model.stepCenter(by: 1)
        #expect(model.centerID == "T2")
        model.stepCenter(by: 1)
        #expect(model.centerID == "T3")
        model.stepCenter(by: -1)
        #expect(model.centerID == "T2")
    }

    /// 到頭到尾不得越界（越界會讓 centerID 指向不存在的項目，列表整個空掉）
    @Test func stepIsClampedAtBothEnds() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        await model.handle(.trackChanged(.fixture(id: "T1"), existingLyrics: ""))

        model.stepCenter(by: -1)
        #expect(model.centerID == "T1", "已在頭部，左移不得越界")

        model.stepCenter(by: 99)
        #expect(model.centerID == "T3", "右移超出範圍應停在尾項")
        model.stepCenter(by: 1)
        #expect(model.centerID == "T3", "已在尾部，右移不得越界")
    }

    /// 鍵盤步進與拖曳同樣算「使用者接管」——否則下一次輪詢就把中心搶回去
    @Test func keyboardStepSuppressesAutoCenter() async {
        let (model, _) = await makeModel()
        model.tabActivated()
        await model.loadTask?.value
        await model.handle(.trackChanged(.fixture(id: "T1"), existingLyrics: ""))

        model.stepCenter(by: 2)
        await model.handle(.trackChanged(.fixture(id: "T1"), existingLyrics: "refresh"))
        #expect(model.centerID == "T3", "鍵盤步進後同曲事件不得搶回控制")
    }

    /// 空列表時步進不得崩
    @Test func stepOnEmptyListIsNoOp() async {
        let (model, _) = await makeModel(albumTracks: [])
        model.tabActivated()
        await model.loadTask?.value
        model.stepCenter(by: 1)
        #expect(model.centerID == nil)
    }

    // MARK: H-11 穩定排序

    @Test func itemsUseStableDisplayOrder() async {
        let unsorted: [AlbumTrack] = [
            .fixture(id: "B", title: "B", disc: 1, track: 2),
            .fixture(id: "A", title: "A", disc: 1, track: 1),
            .fixture(id: "C", title: "C", disc: 2, track: 1),
        ]
        let (model, _) = await makeModel(albumTracks: unsorted)
        model.tabActivated()
        await model.loadTask?.value
        #expect(model.items.map(\.persistentID) == ["A", "B", "C"])
    }
}

/// 固定回 nil 的封面替身：VM 測試不關心圖片內容
struct StubArtworkProvider: ArtworkProviding {
    func artwork(for persistentID: String) async -> NSImage? { nil }
}
