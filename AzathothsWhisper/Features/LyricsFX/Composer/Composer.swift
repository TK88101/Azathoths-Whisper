import Foundation

/// 組合器（B1 計劃 §3.6；移植原型 `composer.js:154-175` 並修正兩處：未知軸語意、無候選退 mono）
enum Composer {
    static let sigma = 0.22
    /// 元件與目標值沒有共同軸時的貼合度（原型常數）
    static let neutralFit = 0.35
    /// 每槽只取貼合度最高的前幾名
    static let shortlist = 5

    /// 0＝不合格（標籤不交集、req 不過、forbid 觸發）；否則 exp(−Σd²／(2σ²·n))，只算雙方都有值的軸（n＝共同軸數）
    static func fit(_ component: FXComponent, _ profile: SongProfile) -> Double {
        if !component.tags.isEmpty, component.tags.isDisjoint(with: profile.tags) { return 0 }
        for (axis, threshold) in component.req {
            guard let value = profile.axes[axis], value >= threshold else { return 0 }
        }
        for (axis, threshold) in component.forbid {
            if let value = profile.axes[axis], value >= threshold { return 0 }
        }
        let shared = component.vector.compactMap { axis, value in profile.axes[axis].map { value - $0 } }
        guard !shared.isEmpty else { return neutralFit }
        let squared = shared.reduce(0) { $0 + $1 * $1 }
        return exp(-squared / (2 * sigma * sigma * Double(shared.count)))
    }

    /// 合格者依貼合度降序取前 `shortlist` 名；同分以 id 定序（決定論）
    static func candidates(_ components: [FXComponent], _ profile: SongProfile) -> [FXComponent] {
        let scored = components.map { ($0, fit($0, profile)) }.filter { $0.1 > 0 }
        let sorted = scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }
        return sorted.prefix(shortlist).map(\.0)
    }

    /// 從前幾名中以 fit 為權重抽一個（只取一次亂數）；沒有候選＝nil。
    /// 原型是 fit²（composer.js:163），最合身者一家獨大；2026-10-06 使用者經 /thecure＋Jev 收斂改為 fit（不平方）。
    /// `avoiding` 先從前幾名裡拿掉，拿掉後沒有候選才允許它——同一次取樣，不重抽（Codex 字型辯論 R2）
    static func sample(_ components: [FXComponent], _ profile: SongProfile, _ random: inout SplitMix64, avoiding: String? = nil) -> FXComponent? {
        let shortlist = candidates(components, profile)
        let allowed = shortlist.filter { $0.id != avoiding }
        let pool = allowed.isEmpty ? shortlist : allowed
        guard !pool.isEmpty else { return nil }
        return LinePersonalities.pick(pool.map { ($0, fit($0, profile)) }, &random)
    }

    /// 兩個效果：第二個不得與第一個同 id；排除後沒有候選就是 none（fx2 不是必選槽，計劃評審 R1-2）
    static func pickEffects(_ effects: [FXComponent], _ profile: SongProfile, _ random: inout SplitMix64, avoiding: String? = nil) -> (String, String) {
        let first = sample(effects, profile, &random, avoiding: avoiding)?.id ?? FXEffect.none.rawValue
        let second = sample(effects.filter { $0.id != first }, profile, &random)?.id ?? FXEffect.none.rawValue
        return (first, second)
    }

    /// 六槽各抽一、效果抽兩個；任一必選槽沒有候選＝整份 mono（修正原型回 `list[0]`，composer.js:164）。
    /// `avoiding`＝同一首歌上一次的配方：每一槽都先排除上一次的元件（使用者：「每次都給我感覺變了」「全部都要隨機起來」），
    /// 只剩它一個候選時才允許重複。每槽恰取一次亂數，排除與否不影響其他槽的取樣位置
    static func compose(
        profile: SongProfile, seed: UInt64, catalog: [FXComponent] = LyricsFXCatalog.all, avoiding previous: ComposedRecipe? = nil
    ) -> SessionRecipe {
        var random = SplitMix64(seed: seed)
        let pick = { (slot: FXSlot, avoided: String?, random: inout SplitMix64) in
            sample(catalog.filter { $0.slot == slot }, profile, &random, avoiding: avoided)?.id
        }
        guard let font = pick(.font, previous?.font, &random), let backdrop = pick(.backdrop, previous?.backdrop, &random),
              let enter = pick(.enter, previous?.enter, &random), let exit = pick(.exit, previous?.exit, &random),
              let palette = pick(.palette, previous?.palette, &random) else { return .mono }
        let (fx1, fx2) = pickEffects(catalog.filter { $0.slot == .fx }, profile, &random, avoiding: previous?.fx1)
        return .composed(ComposedRecipe(
            font: font, backdrop: backdrop, enter: enter, exit: exit, fx1: fx1, fx2: fx2, palette: palette,
            seed: random.next(), profile: profile
        ))
    }
}

/// 目錄的結構性檢查（B1 計劃 §3.6）；字型是否在 bundle 由 app 宿主測試另查
enum CatalogValidator {
    static func problems(in catalog: [FXComponent]) -> [String] {
        var problems: [String] = []
        let ids = catalog.map(\.id)
        for id in Set(ids) where ids.filter({ $0 == id }).count > 1 { problems.append("\(id)：id 重複") }
        for component in catalog {
            let values = Array(component.vector.values) + Array(component.req.values) + Array(component.forbid.values)
            if values.contains(where: { !(0...1).contains($0) }) { problems.append("\(component.id)：軸值超出 0…1") }
            for (axis, floor) in component.req {
                if let ceiling = component.forbid[axis], ceiling <= floor { problems.append("\(component.id)：\(axis) 的 req ≥ forbid，永不合格") }
            }
            if !slotMatches(component) { problems.append("\(component.id)：payload 與槽位不符") }
        }
        // P10：工業金屬與 Nu-Metal 不共用任何元件
        let industrialNu = catalog.filter { $0.tags.contains(.industrial) && $0.tags.contains(.nu) }
        if !industrialNu.isEmpty { problems.append("industrial 與 nu 共用：\(industrialNu.map(\.id))") }
        let required = FXSlot.allCases.filter { $0 != .fx }
        for slot in required where !catalog.contains(where: { $0.slot == slot }) { problems.append("\(slot)：沒有任何元件") }
        if !catalog.contains(where: { $0.slot == .fx && $0.id == FXEffect.none.rawValue }) && catalog.contains(where: { $0.slot == .fx }) {
            problems.append("fx：缺 none")
        }
        return problems
    }

    private static func slotMatches(_ component: FXComponent) -> Bool {
        switch (component.slot, component.payload) {
        case (.font, .font), (.backdrop, .backdrop), (.enter, .enter), (.exit, .exit), (.fx, .fx), (.palette, .palette): return true
        default: return false
        }
    }
}
