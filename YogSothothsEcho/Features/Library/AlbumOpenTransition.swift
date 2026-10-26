import CoreGraphics

/// 開合轉場的狀態機（sprint-6-detail.md §4.5、D2、D10；#6-1 第一輪修正 s6-61-round1-fixes.md v0.6 §3 F3＋F4、F6）：
/// browsing →（點盒子）opening →（封面落定）open →（返回鍵、escape）closing → browsing。
/// 三個通道依序走（串行）：開＝others（其他盒以被點者為界往外滑走淡出）→ flight（封面轉正飛到詳情框；詳情底色同步）→ reveal（文字浮現）；
/// 關＝reveal（2.3 倍速倒放）→ flight → others。串行保證「其他盒全不可見才飛、封面落回槽位其他盒才回來」＝慢放也不穿模。
/// 中途反向時從現值續走，位置不跳
struct AlbumOpenTransition: Equatable {
    enum Phase: Equatable {
        case browsing, opening(String), open(String), closing(String)

        /// 返回鍵與 escape 有效：開啟中可中途反向、已開可關
        var isClosable: Bool {
            switch self {
            case .opening, .open: true
            case .browsing, .closing: false
            }
        }

        var isOpen: Bool { if case .open = self { true } else { false } }
    }

    /// others、flight 為 0…1；reveal 是文字段已走的秒數（0…`revealEnd`），結束時刻可在曲目載入後更新而不跳格
    struct Channels: Equatable {
        var others = 0.0, flight = 0.0, reveal = 0.0
    }

    /// 被點那張此刻由誰畫（恰一份可見）：側封原槽位、舞台（飛行中）、詳情層
    enum Owner: Equatable { case browser, stage, detail }

    static let othersDuration = 0.2
    static let flightDuration = 0.4
    /// 關閉時文字倒放的倍速（使用者 2026-10-22：「倒放對，要快一點」→ 2 倍後再「稍微快一點點」）
    static let closeRevealSpeed = 2.3
    static let reduceMotionDuration = 0.25
    /// 時間相減的浮點誤差（0.2 − 0 得 0.1999…）不該讓通道停在 0.99999
    private static let timeEpsilon = 1e-9

    var reduceMotion = false
    /// 文字全部浮現完的時刻（秒，`DetailRevealSchedule.end`）；只由 `open`／`updateRevealEnd` 寫
    private(set) var revealEnd = 1.0
    private(set) var phase: Phase = .browsing
    private var anchor = Channels()
    private var anchorTime = 0.0
    /// 凍結前已走的時間；凍結中 `isFrozen`，恢復時從此續算（不以 now − elapsed 重建錨點，避免浮點誤差）
    private var elapsedBefore = 0.0
    private var isFrozen = false

    var albumID: String? {
        switch phase {
        case .browsing: nil
        case .opening(let id), .open(let id), .closing(let id): id
        }
    }

    var tracksTappable: Bool { phase.isOpen }

    /// 通道往「開」走（opening、open）還是往「關」走
    private var isOpening: Bool {
        switch phase {
        case .opening, .open: true
        case .browsing, .closing: false
        }
    }

    func channels(at now: Double) -> Channels {
        guard phase != .browsing else { return Channels() }
        let elapsed = isFrozen ? elapsedBefore : elapsedBefore + (now - anchorTime)
        return reduceMotion ? parallel(elapsed: elapsed) : sequential(elapsed: elapsed)
    }

    /// 還要不要逐幀推進：轉場中，或已 open 但文字還在浮現
    func isAnimating(at now: Double) -> Bool {
        switch phase {
        case .browsing: false
        case .opening, .closing: !isFrozen
        case .open: !isFrozen && channels(at: now).reveal < revealEnd
        }
    }

    func owner(_ c: Channels) -> Owner {
        if phase == .browsing { return .browser }
        if c.flight >= 1 { return .detail }
        // Reduce Motion：原槽位一開始就隱藏，封面在詳情框原地淡入（不飛、不換層）
        if reduceMotion { return .stage }
        return c.flight > 0 ? .stage : .browser
    }

    @discardableResult
    mutating func open(_ id: String, revealEnd: Double, at now: Double) -> Bool {
        guard phase == .browsing else { return false }
        self.revealEnd = revealEnd
        phase = .opening(id)
        restart(from: Channels(), at: now)
        return true
    }

    /// 曲目載入後以實際項目數更新；從現值續走（不跳格）。回傳是否有變
    @discardableResult
    mutating func updateRevealEnd(_ end: Double, at now: Double) -> Bool {
        guard end != revealEnd else { return false }
        if phase != .browsing {
            // 唱機開著（凍結）時曲目載入：錨在凍結那一刻的值、仍凍結，恢復後從同一點續跑
            let frozen = isFrozen
            restart(from: channels(at: now), at: now)
            isFrozen = frozen
        }
        revealEnd = end
        return true
    }

    /// opening／open → closing（從現值反向）；其他狀態忽略
    @discardableResult
    mutating func close(at now: Double) -> Bool {
        switch phase {
        case .opening(let id), .open(let id):
            let current = channels(at: now)
            phase = .closing(id)
            restart(from: current, at: now)
        case .browsing, .closing:
            return false
        }
        return true
    }

    /// 走完就轉下一個狀態；凍結中不轉。封面落定即 open（曲目可點），文字在 open 裡繼續浮現
    mutating func tick(at now: Double) {
        guard !isFrozen else { return }
        let current = channels(at: now)
        switch phase {
        case .opening(let id) where current.others == 1 && current.flight == 1: phase = .open(id)
        case .closing where current == Channels(): phase = .browsing
        default: break
        }
    }

    /// 轉場中開唱機：進度停在當下，關唱機後從同一點續跑
    mutating func freeze(at now: Double) {
        guard !isFrozen else { return }
        elapsedBefore += now - anchorTime
        isFrozen = true
    }

    mutating func resume(at now: Double) {
        guard isFrozen else { return }
        anchorTime = now
        isFrozen = false
    }

    /// 斷線而殼層換成連線畫面
    mutating func reset() {
        phase = .browsing
        anchor = Channels()
        elapsedBefore = 0
        isFrozen = false
    }

    private mutating func restart(from channels: Channels, at now: Double) {
        anchor = channels
        anchorTime = now
        elapsedBefore = 0
        isFrozen = false
    }

    /// 往目標走 `amount`、到了就停
    private static func stepped(_ value: Double, toward target: Double, by amount: Double) -> Double {
        target > value ? min(target, value + amount) : max(target, value - amount)
    }

    /// 依序把時間花在各通道上：前一段走完才輪到下一段；`secondsPerUnit`＝每走 1 單位所需秒數（others／flight 為整段 0→1 的秒數，reveal 已是秒制＝1）
    private func sequential(elapsed: Double) -> Channels {
        var c = anchor
        var left = elapsed
        func spend(_ value: inout Double, toward target: Double, secondsPerUnit: Double) {
            guard left > 0 else { return }
            let needed = abs(target - value) * secondsPerUnit
            value = Self.stepped(value, toward: target, by: left / secondsPerUnit + Self.timeEpsilon)
            left -= needed
        }
        if isOpening {
            spend(&c.others, toward: 1, secondsPerUnit: Self.othersDuration)
            spend(&c.flight, toward: 1, secondsPerUnit: Self.flightDuration)
            spend(&c.reveal, toward: revealEnd, secondsPerUnit: 1)
        } else {
            spend(&c.reveal, toward: 0, secondsPerUnit: 1 / Self.closeRevealSpeed)
            spend(&c.flight, toward: 0, secondsPerUnit: Self.flightDuration)
            spend(&c.others, toward: 0, secondsPerUnit: Self.othersDuration)
        }
        return c
    }

    /// Reduce Motion：三個通道同時走 0.25 s（交叉淡化）
    private func parallel(elapsed: Double) -> Channels {
        let fraction = max(0, elapsed) / Self.reduceMotionDuration + Self.timeEpsilon
        let unit = isOpening ? 1.0 : 0.0
        return Channels(others: Self.stepped(anchor.others, toward: unit, by: fraction),
                        flight: Self.stepped(anchor.flight, toward: unit, by: fraction),
                        reveal: Self.stepped(anchor.reveal, toward: unit * revealEnd, by: fraction * revealEnd))
    }
}

/// 開合轉場中各元件的畫面值（純函式）：飛行封面的 BoxPose（沿用側封投影）、其他盒的位移／模糊／透明（詳情底色見 `backgroundBlend`）
struct AlbumOpenPose: Equatable {
    var flight: BoxPose
    var flightOpacity: Double
    var spineOpacity: Double
    /// 其他盒往外的位移量（呼叫端乘上各盒的側別）
    var othersOffset: CGFloat
    var othersBlur: CGFloat
    var othersOpacity: Double

    /// 小樣 13 吋值（A 764 時）：其他盒往外 260 pt、模糊 6 pt、詳情封面 444 pt；按 A 等比例
    static let othersTravel: CGFloat = 260
    static let othersMaxBlur: CGFloat = 6
    static let detailCoverToCover: CGFloat = 444.0 / 764
    static let detailCoverToBrowseHeightMax: CGFloat = 0.5
    static let detailCoverLeft: CGFloat = 0.155
    static let detailCoverTop: CGFloat = 0.12

    /// 詳情封面框（瀏覽區座標；左封面右清單，§4.6）
    static func detailCoverFrame(metrics: SpineCarouselMetrics) -> CGRect {
        let browse = metrics.browse
        let side = min(detailCoverToCover * metrics.cover, detailCoverToBrowseHeightMax * browse.height)
        return CGRect(x: browse.minX + detailCoverLeft * browse.width, y: browse.minY + detailCoverTop * browse.height,
                      width: side, height: side)
    }

    /// 終點 pose：轉正（0°）、以書脊邊為錨縮放，反解透視使正面投影恰為 `target`（交接給 2D 詳情層時無位移）。
    /// 正面在 z＝T·s，投影＝以消失點為中心等比放大 k＝d/(d − T·s)；寬 A·s·k＝target.width 解出 s
    static func endPose(target: CGRect, side: CarouselSide, metrics m: SpineCarouselMetrics) -> BoxPose {
        let s = target.width * m.perspective / (m.cover * m.perspective + target.width * m.spine)
        let k = m.perspective / (m.perspective - m.spine * s)
        let edge = side == .left ? target.minX : target.maxX
        return BoxPose(x: (edge - m.center.x) / k, rotationDegrees: 0, side: side, scale: s,
                       y: (target.minY - m.center.y) / k + m.cover * s / 2)
    }

    static func make(_ c: AlbumOpenTransition.Channels, start: BoxPose, target: CGRect, metrics m: SpineCarouselMetrics,
                     reduceMotion: Bool, hasReturnSlot: Bool) -> AlbumOpenPose {
        let end = endPose(target: target, side: start.side, metrics: m)
        let others = ease(c.others), flight = ease(c.flight)
        let unit = m.cover / SpineCarouselMetrics.referenceCover
        let moves = !reduceMotion && hasReturnSlot
        return AlbumOpenPose(
            flight: moves ? lerp(start, end, flight) : end,
            flightOpacity: moves ? 1 : flight,
            spineOpacity: moves ? max(0, 1 - flight * 2) : 0,
            othersOffset: reduceMotion ? 0 : othersTravel * unit * others,
            othersBlur: reduceMotion ? 0 : othersMaxBlur * unit * others,
            othersOpacity: 1 - others)
    }

    /// 詳情底色的混入比例（與封面飛行同步；只要這一個值時不必算整套 pose）
    static func backgroundBlend(_ c: AlbumOpenTransition.Channels) -> Double { ease(c.flight) }

    private static func ease(_ v: Double) -> Double { v * v * (3 - 2 * v) }

    private static func lerp(_ a: BoxPose, _ b: BoxPose, _ f: Double) -> BoxPose {
        let g = CGFloat(f)
        return BoxPose(x: a.x + (b.x - a.x) * g, rotationDegrees: a.rotationDegrees + (b.rotationDegrees - a.rotationDegrees) * f,
                       side: a.side, scale: a.scale + (b.scale - a.scale) * g, y: a.y + (b.y - a.y) * g)
    }
}
