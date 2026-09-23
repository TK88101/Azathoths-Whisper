import AppKit
import Foundation

/// Cover Flow 的狀態（計劃 Q3a）。**純展示——不含任何播控**。
///
/// 不自己讀 Music：牌組（左播過、中正在播、右接下來）、卡片詳情與無詞標記都由 `LyricsFlowModel` 給。
/// 本型別負責：居中、使用者接管（H-05）、鍵盤步進（H-09）、預取、封面版本。
///
/// - D6：換牌與設中心在同一次更新內完成、不帶動畫（S5：direct 16/16；兩段式在首次給牌 0/5）
/// - H-05：使用者拖曳或步進後不搶控制；**真實換歌**才解除。使用者停著的那張若已不在新牌組，回到當前那張
@MainActor
@Observable
final class CoverFlowViewModel {
    private(set) var deck: DeckSnapshot = .empty
    /// 綁給 `CoverFlowStrip` 的 scrollPosition
    var centerID: String?
    /// Editor 分頁在前且畫面＝Cover Flow（計劃 Q3b 接線）；不可見時不預取
    private(set) var isVisible = false
    /// 卡片詳情（名稱、歌詞），以 persistentID 為鍵；只保留牌組內的歌
    private(set) var details: [String: TrackDetails] = [:]
    /// 無詞標記（persistentID）
    private(set) var marks: Set<String> = []

    var cards: [DeckCard] { deck.cards }

    /// 條帶回報「此刻位於幾何正中」的播放卡（D6）。不用 `centerID`：捲動途中它落後於畫面
    private var centredPlayingCardID: String?

    /// 可點＝播放中 ∧ 幾何正中（AC3）。牌組換了播放卡時舊回報自動失效
    var isPlayingCardCentered: Bool {
        guard let centredPlayingCardID else { return false }
        return centredPlayingCardID == deck.currentCardID
    }

    private let artworkProvider: any ArtworkProviding

    /// H-05：使用者拖曳或鍵盤步進後為 true，抑制自動居中
    private var userHasOverriddenAutoCenter = false
    /// 程式化居中期間為 true——SwiftUI 會因程式化捲動回呼 scrollPosition binding，
    /// 若不區分就會把自己的動作誤判為使用者滑動
    private var isCenteringProgrammatically = false

    /// 每首歌的封面版本號（persistentID 為鍵）。取圖失敗時 View 顯示佔位；
    /// 之後退避到期重取成功，provider 通知 → 遞增該歌的版本，只讓這張卡的 `.task(id:)` 重讀
    private(set) var artworkRevisions: [String: Int] = [:]

    /// 預取命令的世代：過時命令在送達 provider 前自行退出
    private var prefetchGeneration = 0
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?

    /// 測試用：等預取命令實際送達 provider
    @ObservationIgnored var prefetchTaskForTesting: Task<Void, Never>? { prefetchTask }

    init(artwork: any ArtworkProviding) {
        self.artworkProvider = artwork
    }

    // MARK: - 牌組

    /// - Parameter isRealChange: 真實換歌（persistentID 變更）才解除 H-05 抑制；同曲重發不算
    func apply(_ newDeck: DeckSnapshot, isRealChange: Bool) {
        let previousCenter = centerID
        deck = newDeck
        let livePIDs = Set(newDeck.cards.map(\.persistentID))
        artworkRevisions = artworkRevisions.filter { livePIDs.contains($0.key) }
        details = details.filter { livePIDs.contains($0.key) }

        if isRealChange {
            userHasOverriddenAutoCenter = false
        }
        let liveIDs = Set(newDeck.cards.map(\.id))
        if userHasOverriddenAutoCenter, let centerID, liveIDs.contains(centerID) {
            schedulePrefetch(movingFrom: previousCenter)
            return
        }
        // 使用者停著的那張已不在牌組 → 回到當前那張，抑制隨之解除
        userHasOverriddenAutoCenter = false
        centerProgrammatically(on: newDeck.currentCardID ?? newDeck.cards.last?.id)
        schedulePrefetch(movingFrom: previousCenter)
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            schedulePrefetch()
        } else {
            cancelPrefetch()        // 看不見的層不該佔用 AE
        }
    }

    func updateDetails(_ newDetails: [String: TrackDetails]) {
        details.merge(newDetails) { _, new in new }
    }

    func updateMarks(_ newMarks: Set<String>) {
        marks = newMarks
    }

    /// 徽章狀態（AC7）：詳情還沒讀到＝unknown，不是缺詞
    func status(for card: DeckCard) -> LyricsStatus {
        LyricsStatus.resolve(
            lyrics: details[card.persistentID].flatMap(\.lyrics),
            isMarked: marks.contains(card.persistentID)
        )
    }

    /// H-03：中心下方標籤 `ARTIST // TITLE`
    var centerLabel: String {
        CoverFlowCenterLabel.text(centerID: centerID, cards: cards, details: details)
    }

    /// 條帶依佈局幾何回報播放卡是否在正中（容差見 `CoverFlowGeometry.isCentered`）
    func playingCardCentering(cardID: String, isCentered: Bool) {
        if isCentered {
            centredPlayingCardID = cardID
        } else if centredPlayingCardID == cardID {
            centredPlayingCardID = nil
        }
    }

    // MARK: - 使用者互動

    /// 使用者拖曳造成的中心變更（View 層在確認非程式化捲動後呼叫）
    func userDidScroll(to id: String) {
        let previous = centerID
        centerID = id
        userHasOverriddenAutoCenter = true
        schedulePrefetch(movingFrom: previous)
    }

    /// scrollPosition binding 的回呼。程式化居中期間不得被當成使用者滑動
    func scrollPositionDidChange(to id: String?) {
        guard !isCenteringProgrammatically, let id, id != centerID else { return }
        userDidScroll(to: id)
    }

    /// H-09：鍵盤步進。與拖曳同樣算「使用者接管」
    func stepCenter(by offset: Int) {
        guard let centerID, let index = cards.firstIndex(where: { $0.id == centerID }) else { return }
        let target = min(max(index + offset, 0), cards.count - 1)
        guard target != index else { return }
        userDidScroll(to: cards[target].id)
    }

    // MARK: - 封面

    func artwork(for persistentID: String) async -> NSImage? {
        await artworkProvider.artwork(for: persistentID)
    }

    /// 由組裝根接上取圖完成通知。吃**協議**而非具體型別：否則測試替身無法傳入
    func observeArtworkStores(from provider: any ArtworkProviding) {
        Task { [weak self] in
            await provider.setOnStored { [weak self] id in
                // `[weak self]` **不會**自動傳進巢狀 closure：內層若直接用外層解出的
                // optional，捕獲的是它的強副本，存進 provider 的 handler 就永久持有整個 VM
                Task { @MainActor in self?.artworkDidStore(id) }
            }
        }
    }

    /// provider 回報某首歌從失敗中恢復（「是否為恢復」由 provider 判定）
    func artworkDidStore(_ persistentID: String) {
        // 牌組外的殘留通知不得寫進字典，否則長時間聽歌會讓它無界增長
        guard cards.contains(where: { $0.persistentID == persistentID }) else { return }
        artworkRevisions[persistentID, default: 0] += 1
    }

    /// View 的 `.task(id:)` key。版本變更即重讀（命中記憶體，成本是一次字典查找）
    func artworkRevision(for persistentID: String) -> Int {
        artworkRevisions[persistentID] ?? 0
    }

    // MARK: - 內部

    private func centerProgrammatically(on id: String?) {
        isCenteringProgrammatically = true
        centerID = id
        isCenteringProgrammatically = false
    }

    /// 以中心兩側的 window 取代目前的預取集合。`movingFrom` 決定哪一側先取
    private func schedulePrefetch(movingFrom previous: String? = nil) {
        guard isVisible, let centerID, let centerIndex = cards.firstIndex(where: { $0.id == centerID }) else { return }
        let previousIndex = previous.flatMap { id in cards.firstIndex(where: { $0.id == id }) }
        let direction = previousIndex.map { centerIndex >= $0 ? 1 : -1 } ?? 1
        dispatchPrefetch(CoverFlowPrefetchWindow.ids(
            persistentIDs: cards.map(\.persistentID), centerIndex: centerIndex, direction: direction
        ))
    }

    private func cancelPrefetch() {
        dispatchPrefetch([])
    }

    /// 串鏈 ＋ 世代門：串鏈保證送達順序，世代門讓過時命令在呼叫 provider 前退出
    private func dispatchPrefetch(_ ids: [String]) {
        prefetchGeneration += 1
        let generation = prefetchGeneration
        let previous = prefetchTask
        let provider = artworkProvider
        prefetchTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, generation == self.prefetchGeneration else { return }
            await provider.prefetch(ids)
        }
    }
}
