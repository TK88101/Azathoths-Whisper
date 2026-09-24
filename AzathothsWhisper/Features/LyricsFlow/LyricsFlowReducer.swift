import Foundation

/// 畫面：Cover Flow 升起或降下露出 Editor（與分頁正交，只在 Editor 分頁內有意義）
enum LyricsSurface: Equatable, Sendable {
    case coverFlow
    case editor
}

/// 當前曲的身分＝`TrackInfo.signature`（與 monitor 換曲判據同源，N1）：
/// 有 persistentID 就是它，否則退回（artist, title, album）三元組——不另立規則
struct NowPlayingIdentity: Hashable, Sendable {
    let key: String

    init(key: String) {
        self.key = key
    }

    init(track: TrackInfo) {
        self.key = track.signature
    }
}

/// 升回計時的票根：場次＋序號，舊票到期不得升回（ABA）
struct RiseToken: Equatable, Sendable {
    let occurrence: Int
    let serial: Int
}

struct LyricsFlowState: Equatable, Sendable {
    var surface: LyricsSurface = .editor
    var nowPlaying: NowPlayingIdentity?
    /// 當前曲的 persistentID（寫入與標記以它比對；空字串＝無 ID 的曲）
    var nowPlayingPersistentID: String?
    /// 真實換歌場次（同曲重發不加）
    var occurrence = 0
    var status: LyricsStatus = .unknown
    var pendingRise: RiseToken?
    var isDenied = false
    var riseSerial = 0
    /// 本場次（自真實換歌起）使用者是否親手選過畫面（有效的把手、點正中播放卡）。
    /// 使用者拍板②：「讀不到 → 缺詞」只在使用者沒選過時才自動降下
    var hasUserChosenSurface = false
}

enum LyricsFlowEvent: Equatable, Sendable {
    case nowPlaying(NowPlayingIdentity, persistentID: String, status: LyricsStatus)
    case notPlaying
    case permissionDenied
    /// `isCentered` 由條帶的佈局幾何判定（D6、N2）
    case tapPlayingCard(isCentered: Bool)
    case toggleHandle
    case editorTextEdited
    /// `resultingStatus` 由呼叫端以 `LyricsStatus.resolve(寫入的文字, 標記)` 算出
    case writeSucceeded(persistentID: String, resultingStatus: LyricsStatus)
    case writeFailed(persistentID: String)
    case markedNone(persistentID: String)
    case riseDue(RiseToken)
}

enum LyricsFlowEffect: Equatable, Sendable {
    case scheduleRise(RiseToken)
    case cancelRise
    /// 唯讀重讀當前曲：寫入期間 monitor 為 busy、換歌會漏掉（Codex R1-4）
    case forceRefresh
    case cancelAutoFetch(persistentID: String)
    /// 寫入回報成功、但讀回仍缺詞＝寫入沒生效（使用者拍板①：留在 Editor 並提示）
    case writeNotConfirmed(persistentID: String)
}

/// 計劃 §6 的畫面狀態機（純函數）。副作用以 `LyricsFlowEffect` 回傳，由 `LyricsFlowModel` 執行
enum LyricsFlowReducer {
    static func reduce(_ state: LyricsFlowState, _ event: LyricsFlowEvent) -> (LyricsFlowState, [LyricsFlowEffect]) {
        switch event {
        case .nowPlaying(let identity, let persistentID, let status):
            return nowPlaying(state, identity: identity, persistentID: persistentID, status: status)
        case .notPlaying:
            return (state, [])
        case .permissionDenied:
            guard !state.isDenied else { return (state, []) }
            var next = clearingRise(state)
            next.state.surface = .editor
            next.state.isDenied = true
            return (next.state, next.effects)
        case .tapPlayingCard(let isCentered):
            guard isCentered, state.nowPlaying != nil, state.surface == .coverFlow else { return (state, []) }
            var next = clearingRise(state)
            next.state.surface = .editor
            next.state.hasUserChosenSurface = true
            return (next.state, next.effects)
        case .toggleHandle:
            var next = clearingRise(state)
            next.state.surface = state.surface == .coverFlow ? .editor : .coverFlow
            next.state.hasUserChosenSurface = true
            return (next.state, next.effects)
        case .editorTextEdited:
            let next = clearingRise(state)
            return (next.state, next.effects)
        case .writeSucceeded(let persistentID, let resultingStatus):
            return writeSucceeded(state, persistentID: persistentID, resultingStatus: resultingStatus)
        case .writeFailed:
            return (state, [.forceRefresh])
        case .markedNone(let persistentID):
            guard isCurrent(persistentID, in: state) else { return (state, [.cancelAutoFetch(persistentID: persistentID)]) }
            // 只有已知缺詞的當前曲可標記：有詞時標記無意義，讀不到時「沒讀到」不能當成「沒有」
            guard state.status == .missing else { return (state, []) }
            var next = clearingRise(state)
            next.state.status = .markedNone
            next.state.surface = .coverFlow
            return (next.state, next.effects + [.cancelAutoFetch(persistentID: persistentID)])
        case .riseDue(let token):
            guard token == state.pendingRise, token.occurrence == state.occurrence, state.surface == .editor else {
                return (state, [])
            }
            var next = state
            next.pendingRise = nil
            next.surface = .coverFlow
            return (next, [])
        }
    }

    private static func nowPlaying(
        _ state: LyricsFlowState, identity: NowPlayingIdentity, persistentID: String, status: LyricsStatus
    ) -> (LyricsFlowState, [LyricsFlowEffect]) {
        // 同曲重發（forceRefresh、停止後再播同曲）見 `sameTrack`；
        // 例外：從權限被拒恢復，需要重新套用該曲的規則
        guard identity != state.nowPlaying || state.isDenied else {
            return sameTrack(state, status: status)
        }
        var next = clearingRise(state)
        if identity != state.nowPlaying {
            next.state.occurrence += 1
            next.state.hasUserChosenSurface = false
        }
        next.state.nowPlaying = identity
        next.state.nowPlayingPersistentID = persistentID
        next.state.status = status
        next.state.isDenied = false
        next.state.surface = status == .missing ? .editor : .coverFlow
        return (next.state, next.effects)
    }

    /// AC6：同曲重發只更新狀態，不動畫面、不取消待升回——防止把使用者從 Editor 踢出去。兩個例外（使用者 2026-09-23 拍板）：
    /// ① 待升回期間讀回仍缺詞＝寫入沒生效 → 取消升回、留在 Editor、提示
    /// ② 由「讀不到」變「缺詞」、且本場次使用者沒親手選過畫面 → 降下露出 Editor
    private static func sameTrack(_ state: LyricsFlowState, status: LyricsStatus) -> (LyricsFlowState, [LyricsFlowEffect]) {
        var next = state
        next.status = status
        if status == .missing, state.pendingRise != nil {
            next.pendingRise = nil
            return (next, [.cancelRise, .writeNotConfirmed(persistentID: state.nowPlayingPersistentID ?? "")])
        }
        if state.status == .unknown, status == .missing, !state.hasUserChosenSurface, state.surface == .coverFlow {
            next.surface = .editor
        }
        return (next, [])
    }

    private static func writeSucceeded(
        _ state: LyricsFlowState, persistentID: String, resultingStatus: LyricsStatus
    ) -> (LyricsFlowState, [LyricsFlowEffect]) {
        guard isCurrent(persistentID, in: state) else { return (state, [.forceRefresh]) }
        var next = state
        next.status = resultingStatus
        // 寫入空字串：先前寫入排下的升回一併取消（對抗覆核 P1②），缺詞曲不得升回
        guard resultingStatus == .present else {
            let cleared = clearingRise(next)
            return (cleared.state, cleared.effects + [.forceRefresh])
        }
        guard state.surface == .editor else { return (next, [.forceRefresh]) }
        next.riseSerial += 1
        let token = RiseToken(occurrence: state.occurrence, serial: next.riseSerial)
        next.pendingRise = token
        return (next, [.scheduleRise(token), .forceRefresh])
    }

    private static func isCurrent(_ persistentID: String, in state: LyricsFlowState) -> Bool {
        !persistentID.isEmpty && persistentID == state.nowPlayingPersistentID
    }

    /// 清掉待升回；原本有待升回才附 `cancelRise`
    private static func clearingRise(_ state: LyricsFlowState) -> (state: LyricsFlowState, effects: [LyricsFlowEffect]) {
        guard state.pendingRise != nil else { return (state, []) }
        var next = state
        next.pendingRise = nil
        return (next, [.cancelRise])
    }
}
