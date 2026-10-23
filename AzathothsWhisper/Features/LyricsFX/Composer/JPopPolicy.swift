import Foundation

/// J-Pop 三變體（原型 lyrics-fx-preview.html:736-755 的 A きらきら／B シティポップ／C バラード；⑥a 計劃 §4.2）。
/// 十軸依原型調性手定，不是署名代表團平均（使用者指定的政策列，ACCEPTANCE I-65）。
/// 在變體目錄裡十軸只決定 `ResolvedStyle` 的變異量與停留，所以 elegance 由原型各變體的 vary 反推：
/// dy＝0.08＋elegance×0.1、scatter＝0.02＋elegance×0.06——kira 0.2（原型 dy 0.1）、city 與 ballad 0（原型 dy 0.04／0.08，公式下限）。
/// ballad 原手定 0.85 時字的位移約原型兩倍，讀得到的檢查 G3 量到疊住 0.62 s
enum JPopVariant: String, CaseIterable, Sendable {
    case kira, city, ballad

    var tag: FXTag {
        switch self {
        case .kira: .jpopKira
        case .city: .jpopCity
        case .ballad: .jpopBallad
        }
    }

    var profile: SongProfile {
        switch self {
        case .kira:
            SongProfile(axes: [.raw: 0.1, .theatrical: 0.5, .cold: 0.1, .aggression: 0.1, .speed: 0.65, .elegance: 0.2, .decay: 0, .bright: 0.9, .bounce: 0.85, .warm: 0.7], tags: [tag])
        case .city:
            SongProfile(axes: [.raw: 0.15, .theatrical: 0.55, .cold: 0.35, .aggression: 0.15, .speed: 0.5, .elegance: 0, .decay: 0.05, .bright: 0.7, .bounce: 0.45, .warm: 0.5], tags: [tag])
        case .ballad:
            SongProfile(axes: [.raw: 0.05, .theatrical: 0.5, .cold: 0.3, .aggression: 0.05, .speed: 0.15, .elegance: 0, .decay: 0.15, .bright: 0.55, .bounce: 0.05, .warm: 0.6], tags: [tag])
        }
    }

    /// 由一份配方的配色推回它的變體：J-Pop 配色只帶一個變體的私有標籤；其他配色、壞 id＝nil。
    /// 「上一次的變體」就這樣取得，不另存欄位（計劃 §4.2）
    init?(paletteID: String) {
        guard let component = LyricsFXCatalog.component(paletteID), component.slot == .palette,
              let variant = Self.allCases.first(where: { component.tags == [$0.tag] }) else { return nil }
        self = variant
    }
}

enum JPopPolicy {
    /// 變體鎖定目錄：只帶該變體私有標籤的元件＋共用 fx `none`。untagged 的 `void` 不在內，各變體的背景一定出現（計劃 §4.2、R1-1）
    static func catalog(_ variant: JPopVariant) -> [FXComponent] {
        LyricsFXCatalog.all.filter { $0.tags == [variant.tag] || ($0.slot == .fx && $0.id == FXEffect.none.rawValue) }
    }

    /// 這一次播放的 J-Pop 目標：選變體（排除上一次配色所屬的變體）→ 該變體的目標值與鎖定目錄。
    /// 變體的亂數與組合器的亂數串分開（同一 session 種子加鹽），不改組合器的取樣位置
    static func target(signature: String, nonce: UInt64, previousPalette: String?) -> (profile: SongProfile, catalog: [FXComponent]) {
        let chosen = variant(seed: FXHash.fnv1a64("jpop|\(signature)") ^ nonce, previous: previousPalette.flatMap(JPopVariant.init(paletteID:)))
        return (chosen.profile, catalog(chosen))
    }

    /// 均勻抽一個變體，先排除上一次的（使用者：「每次都給我感覺變了」）
    static func variant(seed: UInt64, previous: JPopVariant?) -> JPopVariant {
        let pool = JPopVariant.allCases.filter { $0 != previous }
        return pool[Int(seed % UInt64(pool.count))]
    }
}
