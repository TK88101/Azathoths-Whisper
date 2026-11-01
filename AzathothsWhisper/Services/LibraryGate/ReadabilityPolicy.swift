import Foundation

/// 可讀性稽核涵蓋（⑧ 曲庫閘門計劃 §4.6）：哪些樣式經過 G1–G3、哪些被拒絕。
/// production 只放版本化的清單；G1–G3 本身在測試端跑（`ReadabilityAudit`），`ReadabilityPolicyTests` 斷言清單與 fixture 一致
enum ReadabilityPolicy {
    /// 清單內容變動（補組合、拒絕組合、禁止配對）就加 1。v2：加入 `unreadablePairs`（2026-10-28）
    static let version = 2

    struct Pair: Hashable, Sendable {
        let backdrop: String
        let palette: String
    }

    /// G1 主字對比不及格的「背景×配色」（2026-10-28 組合擴大稽核時量到；單列與樂團表抽不到，只有多列組合會湊出）。
    /// 硬禁止：`Composer.compatiblePalettes` 一律排除、沒有退路（/thecure：軟排除會在候選稀少時靜默失效）。
    /// 組合本身保留，不整組拒絕（整組拒絕會讓 264 首換樣式、37 首掉到素面）。`everyBannedPairReallyFailsTheMinimum` 釘住它們確實不及格
    static let unreadablePairs: Set<Pair> = [
        Pair(backdrop: "crimsonFog", palette: "sunsetInk"), Pair(backdrop: "crimsonFog", palette: "cream60"),
        Pair(backdrop: "crimsonFog", palette: "chalk"), Pair(backdrop: "crimsonFog", palette: "mancSky"),
        Pair(backdrop: "crimsonFog", palette: "popArt"), Pair(backdrop: "crimsonFog", palette: "newsprint"),
        Pair(backdrop: "crimsonFog", palette: "britRed"), Pair(backdrop: "crimsonFog", palette: "yellowBlack"),
        Pair(backdrop: "prism", palette: "crimsonVelvet"), Pair(backdrop: "grid", palette: "crimsonVelvet"),
        Pair(backdrop: "spot", palette: "crimsonVelvet"), Pair(backdrop: "ampGlow", palette: "crimsonVelvet"),
    ]

    static func isUnreadable(backdrop: String, palette: String) -> Bool {
        unreadablePairs.contains(Pair(backdrop: backdrop, palette: palette))
    }

    /// 曲庫出現過、經 G1–G3 稽核的多列組合（列 id 排序）。單列、樂團表、J-Pop 由 `auditable` 自動涵蓋
    static let combinations: [[String]] = [
        ["altindie", "arena"], ["altindie", "classicrock"], ["altindie", "gothic"], ["altindie", "nu"], ["altindie", "punk"],
        ["altindie", "symphonic"], ["ambient", "electronic"], ["arena", "classicrock"], ["black", "death"], ["black", "death", "melodeath"],
        ["black", "death", "symphonic"], ["black", "death", "thrash"], ["black", "doom"], ["black", "gothic"],
        ["black", "gothic", "symphonic"], ["black", "symphonic"], ["black", "thrash"], ["classicrock", "death"], ["classicrock", "doom"],
        ["classicrock", "hardrock"], ["classicrock", "punk"], ["darkwave", "folk", "sacred"], ["death", "doom"],
        ["death", "doom", "melodeath"], ["death", "melodeath"], ["death", "melodeath", "metalcore"], ["death", "melodeath", "symphonic"],
        ["death", "metalcore"], ["death", "symphonic"], ["doom", "gothic"], ["doom", "metalcore"], ["electronic", "experimental", "pop"],
        ["electronic", "industrial"], ["electronic", "pop"], ["experimental", "industrial"], ["experimental", "pop"], ["folk", "pop"],
        ["folk", "sacred"], ["gothic", "hardrock", "nu"], ["gothic", "nu"], ["gothic", "punk"], ["gothic", "symphonic"], ["hardrock", "nu"],
        ["hardrock", "thrash"], ["metalcore", "nu"], ["metalcore", "poppunk", "punk"], ["metalcore", "thrash"],
    ]

    /// G1–G3 不及格的鍵：resolver 視同組不出、落下一層（計劃 §4.6）。每一筆都要有 ACCEPTANCE ⚠️ 與使用者簽字
    static let rejected: Set<ProfileExplanation.AuditKey> = []

    /// 應稽核的全部鍵：組得出的署名團、各單列、J-Pop（三變體全部，`JPopVisualTests`）、上面的組合
    static let auditable: Set<ProfileExplanation.AuditKey> = {
        let bands = SongProfileResolver.bandTable.filter { Composer.isComposable($0.profile) }.map { ProfileExplanation.AuditKey.signed($0.name) }
        let singles = (SongProfileResolver.keywordRows + SongProfileResolver.genericRows).map { ProfileExplanation.AuditKey.rows([$0.id]) }
        return Set(bands + singles + combinations.map { .rows($0) } + [.jpop])
    }()

    static let audited: Set<ProfileExplanation.AuditKey> = auditable.subtracting(rejected)
}
