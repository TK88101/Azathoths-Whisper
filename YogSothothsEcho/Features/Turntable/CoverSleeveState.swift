/// 點封面抽出／收回唱片（F-V-05；spec「点击封面」）：兩段式——前半段封面向左滑出半個寬度（M），
/// 400 ms 後滑回並切換「全封面」（L）。動畫中再點忽略
struct CoverSleeveState: Equatable {
    static let phaseMilliseconds = 400

    private(set) var isMidway = false
    private(set) var isFullCover = false

    /// 回傳是否接受（接受後由呼叫端 400 ms 後呼叫 `midwayFinished`）
    mutating func tap() -> Bool {
        guard !isMidway else { return false }
        isMidway = true
        return true
    }

    mutating func midwayFinished() {
        guard isMidway else { return }
        isMidway = false
        isFullCover.toggle()
    }

    /// 橫向偏移（乘以封面寬）
    var offsetFraction: Double { isMidway ? -0.5 : 0 }
    var rotationDegrees: Double { Self.rotationDegrees(isFullCover: isFullCover) }
    /// 封套角度的唯一定義：常態斜放、全封面擺正（版面外接框與畫面、命中共用）
    static func rotationDegrees(isFullCover: Bool) -> Double { isFullCover ? 0 : TurntableMetrics.coverTiltDegrees }
    /// 全封面時蓋在唱片（1.0）之上
    var zIndex: Double { isFullCover ? 2 : 0.5 }
}
