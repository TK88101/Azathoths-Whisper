import AppKit
import Foundation

/// Cover Flow 的狀態（計劃 Q3a）。**純展示——不含任何播控**。
///
/// 不自己讀 Music：牌組（左播過、中正在播、右接下來）、卡片詳情與無詞標記都由 `LyricsFlowModel` 給。
/// 本型別負責：居中、使用者接管（H-05）、鍵盤步進（H-09）、預取、封面版本。
///
/// - D6：換牌與設中心在同一次更新內完成、不帶動畫（S5：direct 16/16；兩段式在首次給牌 0/5）
/// - 換歌平移（`docs/plans/2026-09-26-coverflow-follow-playback-slide.md` v5.3）：D6 不變，捲動位置照樣不帶動畫；
///   「滑過去」由條帶的內容位移呈現。本型別只決定要不要滑、條帶吃哪一副牌，並在落定後把暫留卡收掉
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

    /// 進行中的換歌平移。顯示的權威狀態只有 `deck` 與它；`displayCards`、`slide` 都由兩者算出，不另存。
    /// 不變式：不為 nil ⇒ 過渡顯示牌組算得出來（由 `apply` 維護）
    private(set) var transition: SlideTransition?

    /// 條帶、把手刻度、鍵盤步進、預取吃的牌
    var cards: [DeckCard] { displayCards }

    /// 平時＝正式牌組；平移途中多一張暫留的舊當前卡（原 ID），正式牌組不動
    var displayCards: [DeckCard] {
        guard let transition else { return deck.cards }
        return Self.display(of: deck, during: transition) ?? deck.cards
    }

    /// 給條帶的平移指令；沒有過渡就沒有指令
    var slide: CoverFlowSlideRequest? {
        transition.map { CoverFlowSlideRequest(generation: $0.generation, slots: $0.slots) }
    }

    /// 系統「減少動態效果」。View 同步實值之前先當作已開：寧可不滑
    private(set) var prefersReducedMotion = true

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

    /// 牌組張數上限：左右各一個窗口＋中心
    static let cardLimit = 2 * LyricsFlowModel.window + 1
    /// 平移的逾時保險：動畫完成回呼沒到時，由它落定
    static let slideTimeout: Duration = .seconds(Theme.Motion.layerShiftDuration * 2)

    private let clock: any PollClock
    /// 平移指令的世代：單調遞增，遲到的完成回呼與逾時靠它自行作廢
    private var slideGeneration = 0
    @ObservationIgnored private var slideTimeoutTask: Task<Void, Never>?

    /// 測試用：等逾時保險跑完
    @ObservationIgnored var slideTimeoutTaskForTesting: Task<Void, Never>? { slideTimeoutTask }

    init(artwork: any ArtworkProviding, clock: any PollClock = SystemPollClock()) {
        self.artworkProvider = artwork
        self.clock = clock
    }

    // MARK: - 牌組

    /// - Parameters:
    ///   - isRealChange: 真實換歌（persistentID 變更）才解除 H-05 抑制；同曲重發不算
    ///   - slideHint: 換歌方向的佐證（往回跳時牌組本身看不出方向）；只在真實換歌時有意義
    func apply(_ newDeck: DeckSnapshot, isRealChange: Bool, slideHint: SlideHint? = nil) {
        let previousCenter = centerID
        // 要不要滑，看的是換牌**之前**的畫面
        let plan = isRealChange ? slidePlan(for: newDeck, hint: slideHint) : .direct
        if newDeck.currentCardID != deck.currentCardID {
            // 卡片離開「正在播」之後不會再回報 false：不清掉的話，它日後又成為當前卡時舊回報會被當成現況
            centredPlayingCardID = nil
        }
        deck = newDeck
        updateTransition(for: plan, isRealChange: isRealChange)
        pruneCaches()

        if isRealChange {
            userHasOverriddenAutoCenter = false
        }
        let liveIDs = Set(cards.map(\.id))
        if userHasOverriddenAutoCenter, let centerID, liveIDs.contains(centerID) {
            schedulePrefetch(movingFrom: previousCenter)
            return
        }
        // 使用者停著的那張已不在牌組 → 回到當前那張，抑制隨之解除
        userHasOverriddenAutoCenter = false
        centerProgrammatically(on: newDeck.currentCardID ?? newDeck.cards.last?.id)
        schedulePrefetch(movingFrom: previousCenter)
    }

    /// 條帶回報平移動畫跑完（或逾時保險到期、或條帶被重建時的補救）。
    /// 嚴格冪等：世代不符就是 no-op，遲到或重複的回報不得推翻使用者其後的操作
    func slideDidSettle(generation: Int) {
        guard transition?.generation == generation else { return }
        finishTransition()
    }

    func setPrefersReducedMotion(_ prefers: Bool) {
        guard prefers != prefersReducedMotion else { return }
        prefersReducedMotion = prefers
        if prefers, transition != nil {
            finishTransition()
        }
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

    /// 播放卡的曲名（AC3 無障礙標籤「Edit lyrics of %@」）；沒有播放卡、不在牌組或詳情未到 → 空字串
    var playingCardTitle: String {
        guard let id = deck.currentCardID, let card = cards.first(where: { $0.id == id }) else { return "" }
        return details[card.persistentID]?.title ?? ""
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

    // MARK: 換歌平移

    /// 計劃 §3.1：畫面停在舊當前卡上、沒有進行中的過渡、方向可證明、目標卡的位次不變——全部成立才滑
    private func slidePlan(for newDeck: DeckSnapshot, hint: SlideHint?) -> CoverFlowSlidePlan {
        guard !prefersReducedMotion, transition == nil,
              // 幾何回報與 centerID 都要：前者在容差內不代表捲動已停在錨點上，後者在拖曳途中落後於畫面
              isPlayingCardCentered, let oldID = deck.currentCardID, centerID == oldID,
              let old = displayCards.first(where: { $0.id == oldID })
        else { return .direct }
        return CoverFlowSlidePlan.make(previousDisplay: displayCards, old: old, canonical: newDeck,
                                       hint: hint, limit: Self.cardLimit)
    }

    /// `deck` 已換成新牌組之後呼叫
    private func updateTransition(for plan: CoverFlowSlidePlan, isRealChange: Bool) {
        if case .slide(let old, let target, let slots, let targetIndex) = plan {
            beginTransition(old: old, target: target, slots: slots, targetIndex: targetIndex)
            return
        }
        guard let transition else { return }
        // 過渡中又換歌一律直接定位；同曲的更新只要過渡顯示牌組還算得出來就繼續
        if isRealChange || Self.display(of: deck, during: transition) == nil {
            endTransition()
        }
    }

    private func beginTransition(old: DeckCard, target: String, slots: Int, targetIndex: Int) {
        slideGeneration += 1
        let generation = slideGeneration
        transition = SlideTransition(generation: generation, old: old, target: target, slots: slots, targetIndex: targetIndex)
        slideTimeoutTask?.cancel()
        slideTimeoutTask = clock.schedule(after: Self.slideTimeout) { [weak self] in
            self?.slideDidSettle(generation: generation)
        }
    }

    private func endTransition() {
        transition = nil
        slideTimeoutTask?.cancel()
        slideTimeoutTask = nil
    }

    /// 過渡結束後收尾：暫留卡的資料此時才清；使用者若停在暫留卡上，回到當前那張
    private func finishTransition() {
        endTransition()
        pruneCaches()
        guard let centerID, !deck.cards.contains(where: { $0.id == centerID }) else { return }
        userHasOverriddenAutoCenter = false
        centerProgrammatically(on: deck.currentCardID ?? deck.cards.last?.id)
    }

    private static func display(of deck: DeckSnapshot, during transition: SlideTransition) -> [DeckCard]? {
        CoverFlowSlidePlan.display(canonical: deck, old: transition.old, target: transition.target,
                                   slots: transition.slots, targetIndex: transition.targetIndex, limit: cardLimit)
    }

    /// 只保留牌組內的歌。顯示牌組與正式牌組都算：暫留卡在過渡中留著，顯示上讓位的那張也還在正式牌組裡
    private func pruneCaches() {
        let livePIDs = Set((deck.cards + displayCards).map(\.persistentID))
        artworkRevisions = artworkRevisions.filter { livePIDs.contains($0.key) }
        details = details.filter { livePIDs.contains($0.key) }
    }

    // MARK: 居中與預取

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
