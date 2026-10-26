import CoreGraphics

/// 唱機層的生命週期（sprint-6-detail.md §4.8；唯一 owner＝TurntableViewModel）：hidden → entering(滑入、抽出、放上) → shown →
/// leaving（帶關閉當下的唱片位置快照，隨頁面滑走、不再移動）→ hidden。滑完才離開樹；leaving 中不提供反向
enum TurntableLayerState: Equatable {
    case hidden
    case entering(TurntableEntrance.Phase)
    case shown
    case leaving(record: SwipeTransition.Presentation)

    /// 唱機層在樹上（曲庫殼層不可點、不在 AX 樹）
    var isPresent: Bool { self != .hidden }
    /// 進場與離場中忽略點擊與甩動（進場不寫 model.swipe）；hidden 時唱機不在畫面上，不另擋
    var blocksInput: Bool {
        switch self {
        case .entering, .leaving: true
        case .hidden, .shown: false
        }
    }
}

/// 進出唱機的純函式（D9）：頁面滑動 0.35 s；滑完唱片自封套抽出——直接沿用 G7 的 drawing／placing 兩段
/// （同一個 `SwipeTransition.Presentation` 語義、同一組 `TurntableLayout.recordOrigin` 位置與換層規則，不另寫一套）
enum TurntableEntrance {
    enum Phase: Equatable { case sliding, drawing, placing }

    struct Offsets: Equatable {
        var library: CGFloat
        var turntable: CGFloat
        var turntableOpacity: Double
    }

    static let slide: Duration = .milliseconds(350)
    static let reduceMotionFade: Duration = .milliseconds(250)

    static func duration(of phase: Phase, reduceMotion: Bool) -> Duration {
        if reduceMotion { return reduceMotionFade }
        switch phase {
        case .sliding: return slide
        case .drawing: return SwipeTransition.duration(of: .drawing(.next), accelerated: false) ?? .zero
        case .placing: return SwipeTransition.duration(of: .placing(.next), accelerated: false) ?? .zero
        }
    }

    /// Reduce Motion：一次淡入就 shown（唱片直接在唱盤上）
    static func next(after phase: Phase, reduceMotion: Bool) -> Phase? {
        guard !reduceMotion else { return nil }
        switch phase {
        case .sliding: return .drawing
        case .drawing: return .placing
        case .placing: return nil
        }
    }

    /// 主組唱片的位置與上下層：滑動中在封套內（封套下層、封套讓開）→ 抽到對軸點 → 放上唱盤並換到封套上層（＝G7 idle）
    static func presentation(_ phase: Phase, reduceMotion: Bool) -> SwipeTransition.Presentation {
        guard !reduceMotion else { return .resting }
        var p = SwipeTransition.Presentation()
        switch phase {
        case .sliding:
            p.outgoingSlot = .sleeve
            p.outgoingRecordBelowCover = true
            p.outgoingSleeveAside = true
        case .drawing:
            p.outgoingSlot = .aligned
            p.outgoingRecordBelowCover = true
            p.outgoingSleeveAside = true
        case .placing:
            break
        }
        return p
    }

    /// 滑動進度的目標：唱機在畫面上（進場、顯示）＝0，不在（hidden、離場）＝1
    static func slideTarget(_ layer: TurntableLayerState) -> CGFloat {
        switch layer {
        case .hidden, .leaving: 1
        case .entering, .shown: 0
        }
    }

    /// 進度 → 位移：曲庫殼層往左滑出（0 → −W）、唱機從右滑入（W → 0）；Reduce Motion 不位移、只改唱機不透明度。
    /// 殼層以普通 offset 驅動進度（插入轉場 `.move` 實測帶不動唱機的封套，封套一開始就在終點）
    static func offsets(slide: CGFloat, width: CGFloat, reduceMotion: Bool) -> Offsets {
        if reduceMotion { return Offsets(library: 0, turntable: 0, turntableOpacity: Double(1 - slide)) }
        return Offsets(library: -(1 - slide) * width, turntable: slide * width, turntableOpacity: 1)
    }
}
