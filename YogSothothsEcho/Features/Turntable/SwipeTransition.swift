import CoreGraphics
import RemoteProtocol

/// 全螢幕橫向甩動切歌（F-P-03；sprint-5-detail.md §4.4 v1.3、D4、D5；#5-1 G7）。純狀態機：事件進來回傳要做的副作用，
/// 計時、送指令與讀已採用狀態由 TurntableViewModel 執行。放手過閾值即送指令並抬臂煞停；抬臂計時與「可以決定了」
/// （回覆或 1.5 s 期限）兩者都到才依已採用狀態分路。轉場未結束時的新甩動只加速、不送第二個指令
struct SwipeTransition: Equatable {
    enum Direction: Equatable { case next, previous }

    /// 依已採用狀態與甩動前快照比較的分路（`branch`）
    enum Branch: Equatable { case sameTrack, noCurrent, sameAlbum, newAlbum }

    enum Phase: Equatable {
        case idle
        case ignoringVertical
        case dragging(dx: CGFloat)
        /// 未過閾值（或不能送）：封面回原位
        case returning
        /// 抬臂＋煞停；`ready`＝回覆已到或期限已過
        case lifting(Direction, ready: Bool)
        /// 抬臂完、等回覆或期限
        case awaiting(Direction)
        /// 同專輯：標籤與唱片面交叉淡化
        case relabeling
        /// Reduce Motion：整個場景交叉淡化
        case crossfading
        /// 異專輯（v2.1 T6，使用者選 ⑦）：封套沿斜軸讓開＋唱片對軸 → 唱片換到下層、沿斜軸收進 → 換封套 →
        /// 新唱片在下層沿斜軸抽出 → 換到上層、唱片回唱盤＋封套滑回唱片下。換層只在兩者不重疊的瞬間發生
        case clearing(Direction)
        case sheathing(Direction)
        case exchanging(Direction)
        case drawing(Direction)
        case placing(Direction)
    }

    enum Effect: Equatable {
        case send(Direction)
        case returnToRest
        /// 在途再甩：之後的段加速
        case accelerate
        /// 抬臂計時與 ready 都到了：讀已採用狀態分路
        case decide
    }

    /// 唱片位置：唱盤上／對軸點（唱盤旁、在封套斜軸上）／讓開後的封套內
    enum RecordSlot: Equatable { case platter, aligned, sleeve }

    /// 視圖要畫的位置與層級（已解析，視圖不自行組合）；位移以「離場距離」（1.4 倍容器寬）為單位，負＝往左。
    /// `sleeveAside`＝封套沿斜軸讓開（v2.1 T6）；換層（`recordBelowCover`）只在唱片在對軸點、封套讓開時切換
    struct Presentation: Equatable {
        var outgoingSlot = RecordSlot.platter
        var outgoingRecordBelowCover = false
        var outgoingSleeveAside = false
        var outgoingOffset: CGFloat = 0
        var showsIncomingGroup = false
        var incomingSlot = RecordSlot.sleeve
        var incomingRecordBelowCover = true
        var incomingSleeveAside = true
        var incomingOffset: CGFloat = 0
        var backgroundFromIncoming = false

        static let resting = Presentation()
    }

    static let thresholdPixels: CGFloat = 100
    static let maxOffsetWidthFactor: CGFloat = 1.4
    static let rightwardAmplify: CGFloat = 1.5
    static let confirmDeadline: Duration = .milliseconds(1500)
    static let accelerationFactor = 0.4
    /// 抬臂＋煞停段（唱臂動畫與煞停共用）
    static let liftDuration: Duration = .milliseconds(350)
    /// 換封套段：舊組離場與新組進場各佔 2/3，新組晚 1/3 起步（重疊 110／330 ms）
    static let exchangeLegFraction = 2.0 / 3

    private(set) var phase: Phase = .idle
    private(set) var accelerated = false
    private(set) var reduceMotion = false
    /// 閾值（pt）＝100 px／displayScale（D4）
    let threshold: CGFloat

    init(displayScale: CGFloat) {
        threshold = Self.thresholdPixels / max(displayScale, 1)
    }

    // MARK: 事件

    mutating func dragChanged(_ translation: CGSize) {
        switch phase {
        case .idle:
            phase = abs(translation.width) > abs(translation.height) ? .dragging(dx: translation.width) : .ignoringVertical
        case .dragging:
            phase = .dragging(dx: translation.width)
        default:
            break
        }
    }

    mutating func dragEnded(_ translation: CGSize, canSend: Bool, reduceMotion: Bool) -> Effect? {
        let direction = passedThreshold(translation)
        switch phase {
        case .ignoringVertical:
            phase = .idle
            return nil
        case .dragging:
            guard let direction, canSend else {
                phase = .returning
                return .returnToRest
            }
            phase = .lifting(direction, ready: false)
            accelerated = false
            self.reduceMotion = reduceMotion
            return .send(direction)
        default:
            guard isTransitioning, direction != nil, !accelerated else { return nil }
            accelerated = true
            return .accelerate
        }
    }

    /// 回覆正常到達或期限已過
    mutating func ready() -> Effect? {
        switch phase {
        case .lifting(let direction, ready: false):
            phase = .lifting(direction, ready: true)
            return nil
        case .awaiting:
            return .decide
        default:
            return nil
        }
    }

    /// 目前段的計時到期
    mutating func timerFinished() -> Effect? {
        switch phase {
        case .lifting(let direction, let ready):
            if ready { return .decide }
            phase = .awaiting(direction)
        case .clearing(let direction): phase = .sheathing(direction)
        case .sheathing(let direction): phase = .exchanging(direction)
        case .exchanging(let direction): phase = .drawing(direction)
        case .drawing(let direction): phase = .placing(direction)
        case .placing, .relabeling, .crossfading, .returning: finish()
        default: break
        }
        return nil
    }

    mutating func decide(_ branch: Branch) {
        let direction: Direction
        switch phase {
        case .lifting(let d, _), .awaiting(let d): direction = d
        default: return
        }
        switch branch {
        case .sameTrack, .noCurrent: finish()
        case _ where reduceMotion: phase = .crossfading
        case .sameAlbum: phase = .relabeling
        case .newAlbum: phase = .clearing(direction)
        }
    }

    /// 斷線、關閉唱機
    mutating func cancel() { finish() }

    private mutating func finish() {
        phase = .idle
        accelerated = false
    }

    // MARK: 判定

    /// 依序：目前無曲 → noCurrent；甩動前無曲 → newAlbum；同曲 → sameTrack；兩側專輯都有且相等 → sameAlbum；其餘 → newAlbum
    static func branch(outgoingTrack: String?, outgoingAlbum: String?, currentTrack: String?, currentAlbum: String?) -> Branch {
        guard let currentTrack else { return .noCurrent }
        guard let outgoingTrack else { return .newAlbum }
        if outgoingTrack == currentTrack { return .sameTrack }
        if let outgoingAlbum, outgoingAlbum == currentAlbum { return .sameAlbum }
        return .newAlbum
    }

    static func duration(of phase: Phase, accelerated: Bool) -> Duration? {
        let milliseconds: Double
        switch phase {
        case .lifting: milliseconds = liftDuration.secondsValue * 1000
        case .relabeling, .drawing: milliseconds = 200
        case .clearing, .placing: milliseconds = 150
        case .sheathing: milliseconds = 160
        case .exchanging: milliseconds = 330
        case .crossfading: milliseconds = 250
        case .returning: milliseconds = 400
        case .idle, .ignoringVertical, .dragging, .awaiting: return nil
        }
        return .milliseconds((accelerated ? milliseconds * accelerationFactor : milliseconds).rounded())
    }

    /// 目前段的計時長度（加速後進入的段才縮短；目前段照原速）
    var timedDuration: Duration? { Self.duration(of: phase, accelerated: accelerated) }

    // MARK: 展示

    var isBusy: Bool {
        switch phase {
        case .idle, .ignoringVertical: false
        default: true
        }
    }

    /// 放手過閾值到回 idle：畫面畫凍結的快照
    var isTransitioning: Bool {
        switch phase {
        case .idle, .ignoringVertical, .dragging, .returning: false
        default: true
        }
    }

    /// 抬臂中（唱片同時煞停）
    var armLifted: Bool { isTransitioning && !reduceMotion && phase != .crossfading }

    /// 拖動中封面跟手：clamp(dx/maxOffset)×maxOffset，向右 ×1.5、向左 ÷1.5（spec）；其他階段 0
    func coverOffset(containerWidth: CGFloat) -> CGFloat {
        guard case .dragging(let dx) = phase else { return 0 }
        let maxOffset = containerWidth * Self.maxOffsetWidthFactor
        let offset = min(max(dx / maxOffset, -1), 1) * maxOffset
        return offset > 0 ? offset * Self.rightwardAmplify : offset / Self.rightwardAmplify
    }

    var presentation: Presentation {
        var p = Presentation()
        switch phase {
        case .clearing(let d):
            p.outgoingSlot = .aligned
            p.outgoingSleeveAside = true
            p.showsIncomingGroup = true
            p.incomingOffset = Self.entrySide(d)
        case .sheathing(let d):
            p.outgoingSlot = .sleeve
            p.outgoingRecordBelowCover = true
            p.outgoingSleeveAside = true
            p.showsIncomingGroup = true
            p.incomingOffset = Self.entrySide(d)
        case .exchanging(let d), .drawing(let d), .placing(let d):
            p.outgoingSlot = .sleeve
            p.outgoingRecordBelowCover = true
            p.outgoingSleeveAside = true
            p.outgoingOffset = -Self.entrySide(d)
            p.showsIncomingGroup = true
            p.backgroundFromIncoming = true
            if case .drawing = phase { p.incomingSlot = .aligned }
            if case .placing = phase {
                p.incomingSlot = .platter
                p.incomingRecordBelowCover = false
                p.incomingSleeveAside = false
            }
        default:
            break
        }
        return p
    }

    /// 新組進場的一側：下一首（左甩）從右邊進
    private static func entrySide(_ direction: Direction) -> CGFloat { direction == .next ? 1 : -1 }

    private func passedThreshold(_ translation: CGSize) -> Direction? {
        guard abs(translation.width) > abs(translation.height) else { return nil }
        if translation.width < -threshold { return .next }
        if translation.width > threshold { return .previous }
        return nil
    }
}
