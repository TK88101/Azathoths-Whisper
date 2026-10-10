import Testing

@testable import AzathothsWhisper

private func band(_ name: String) throws -> SongProfile {
    guard case .profile(let profile) = SongProfileResolver.resolve(artist: name, genre: nil) else {
        Issue.record("覆寫表沒有 \(name)")
        throw CancellationError()
    }
    return profile
}

private func component(_ slot: FXSlot, _ id: String, vector: [FXAxis: Double] = [:], tags: Set<FXTag> = [],
                       req: [FXAxis: Double] = [:], forbid: [FXAxis: Double] = [:]) -> FXComponent {
    FXComponent(id: id, slot: slot, vector: vector, tags: tags, req: req, forbid: forbid, payload: .fx(.none))
}

// B1 計劃 §3.6：fit。只在元件與目標值都有值的軸上算距離；req 未知＝不合格、forbid 未知＝不觸發
@Suite("Composer fit")
struct FitTests {
    let profile = SongProfile(axes: [.aggression: 0.9, .elegance: 0.1], tags: [.black])

    @Test func noSharedTagMeansZero() {
        #expect(Composer.fit(component(.fx, "a", vector: [.aggression: 0.9], tags: [.symphonic]), profile) == 0)
    }

    @Test func anUntaggedComponentPassesTheTagGate() {
        #expect(Composer.fit(component(.fx, "a", vector: [.aggression: 0.9]), profile) > 0)
    }

    @Test func requireOnAnUnknownAxisFails() {
        #expect(Composer.fit(component(.fx, "a", vector: [.aggression: 0.9], req: [.theatrical: 0.1]), profile) == 0)
    }

    @Test func requireBelowTheThresholdFails() {
        #expect(Composer.fit(component(.fx, "a", req: [.aggression: 0.95]), profile) == 0)
        #expect(Composer.fit(component(.fx, "a", req: [.aggression: 0.9]), profile) > 0)
    }

    @Test func forbidTriggersAtOrAboveTheThresholdOnly() {
        #expect(Composer.fit(component(.fx, "a", forbid: [.aggression: 0.9]), profile) == 0)
        #expect(Composer.fit(component(.fx, "a", forbid: [.aggression: 0.95]), profile) > 0)
        #expect(Composer.fit(component(.fx, "a", forbid: [.bright: 0.1]), profile) > 0, "未知軸不觸發")
    }

    @Test func noSharedAxisGivesTheNeutralFit() {
        #expect(Composer.fit(component(.fx, "a", vector: [.bounce: 0.5]), profile) == Composer.neutralFit)
        #expect(Composer.fit(component(.fx, "a"), profile) == Composer.neutralFit)
    }

    @Test func fitFallsAsTheDistanceGrows() {
        let near = Composer.fit(component(.fx, "a", vector: [.aggression: 0.85]), profile)
        let far = Composer.fit(component(.fx, "a", vector: [.aggression: 0.4]), profile)
        #expect(near > far && far > 0 && near <= 1)
        #expect(Composer.fit(component(.fx, "a", vector: [.aggression: 0.9, .elegance: 0.1]), profile) == 1)
    }
}

// B1 計劃 §3.6、§5：抽樣與硬規則（P11）。目錄＝真目錄
@Suite("Composer")
struct ComposerTests {
    static let seeds = UInt64(0)..<256

    private func composed(_ profile: SongProfile, _ seed: UInt64) throws -> ComposedRecipe {
        guard case .composed(let recipe) = Composer.compose(profile: profile, seed: seed) else {
            Issue.record("期望組合配方")
            throw CancellationError()
        }
        return recipe
    }

    @Test func theSameProfileAndSeedGiveTheSameRecipe() throws {
        let cradle = try band("Cradle of Filth")
        #expect(Composer.compose(profile: cradle, seed: 42) == Composer.compose(profile: cradle, seed: 42))
    }

    @Test func differentSeedsVaryTheRecipe() throws {
        let mayhem = try band("Mayhem")
        let recipes = Set(try Self.seeds.prefix(64).map { try composed(mayhem, $0).componentIDs })
        #expect(recipes.count >= 2)
    }

    @Test func theSecondEffectNeverRepeatsTheFirst() throws {
        for name in ["Mayhem", "Cradle of Filth", "Nightwish"] {
            let profile = try band(name)
            for seed in Self.seeds {
                let recipe = try composed(profile, seed)
                #expect(recipe.fx1 != recipe.fx2 || recipe.fx2 == "none", "\(name) \(seed)")
            }
        }
    }

    /// P11：Cradle of Filth 抽不到使用者點名的溫柔交響元件，且每份都至少一個 black 群元件
    @Test func cradleNeverGetsTheGentleSymphonicComponents() throws {
        let cradle = try band("Cradle of Filth")
        let gentle: Set<String> = ["Cinzel", "CormorantIt", "shafts", "rise", "goldNavy", "breathe"]
        for seed in Self.seeds {
            let recipe = try composed(cradle, seed)
            #expect(gentle.isDisjoint(with: recipe.componentIDs), "seed \(seed)")
            #expect(recipe.componentIDs.contains { LyricsFXCatalog.component($0)?.tags.contains(.black) ?? false })
        }
    }

    /// 反向：同一批溫柔元件 Nightwish 抽得到（證明 P11 不是因為元件不存在才成立）
    @Test func nightwishDoesGetThem() throws {
        let nightwish = try band("Nightwish")
        let gentle: Set<String> = ["Cinzel", "CormorantIt", "shafts", "rise", "goldNavy", "breathe"]
        let seen = try Self.seeds.reduce(into: Set<String>()) { $0.formUnion(try composed(nightwish, $1).componentIDs.intersection(gentle)) }
        #expect(seen.count >= 3, "實得 \(seen)")
    }

    @Test func mayhemNeverGetsASymphonicOnlyComponent() throws {
        let mayhem = try band("Mayhem")
        for seed in Self.seeds {
            for id in try composed(mayhem, seed).componentIDs {
                let tags = LyricsFXCatalog.component(id)?.tags ?? []
                #expect(tags.isEmpty || tags.contains(.black), "\(id)")
            }
        }
    }

    @Test(arguments: ["Nightwish", "Epica", "Emperor", "Dimmu Borgir", "Cradle of Filth", "Mayhem", "Burzum"])
    func everyB1BandGetsAFullRecipe(name: String) throws {
        let profile = try band(name)
        for slot in FXSlot.allCases where slot != .fx {
            #expect(!Composer.candidates(LyricsFXCatalog.components(in: slot), profile).isEmpty, "\(name) \(slot)")
        }
        _ = try composed(profile, 1)
    }

    @Test func aProfileOutsideTheCatalogFallsBackToMono() {
        // 必選槽無候選＝整份 mono。拿掉整個字型槽，不依賴「哪個曲風剛好還沒有字型」（目錄每批都在長）
        let polka = SongProfile(axes: [.bounce: 1, .warm: 1], tags: [.pop])
        #expect(Composer.compose(profile: polka, seed: 3, catalog: LyricsFXCatalog.all.filter { $0.slot != .font }) == .mono)
    }

    /// fx2 不是必選槽：排除 fx1 後沒有候選就是 none（計劃評審 R1-2）
    @Test(arguments: [[String](), ["onlyFx"], ["fxA", "fxB"]])
    func theSecondEffectNeverRepeatsUnlessBothAreNone(ids: [String]) {
        let profile = SongProfile(axes: [.aggression: 0.5], tags: [.black])
        let effects = [component(.fx, "none")] + ids.map { component(.fx, $0, vector: [.aggression: 0.5], tags: [.black]) }
        for seed in UInt64(0)..<32 {
            var random = SplitMix64(seed: seed)
            let (first, second) = Composer.pickEffects(effects, profile, &random)
            #expect(first != second || (first == "none" && second == "none"), "\(ids) \(seed)")
            #expect(ids.isEmpty == (first == "none" && second == "none"))
        }
    }
}

// 抽籤（2026-10-06 使用者經 /thecure＋Jev 收斂定案，並要求「全部都要隨機起來」）：每槽以 fit（不平方）加權；
// 同一首歌下次每槽排除上一次的元件
@Suite("Composer sampling")
struct ComposerSamplingTests {
    private func black() throws -> SongProfile {
        guard case .profile(let profile) = SongProfileResolver.resolve(artist: "x", genre: "Black Metal") else { throw CancellationError() }
        return profile
    }

    private func composed(_ recipe: SessionRecipe) -> ComposedRecipe? {
        if case .composed(let value) = recipe { value } else { nil }
    }

    @Test(arguments: [FXSlot.font, .backdrop, .enter, .exit, .palette])
    func eachSlotIsWeightedByPlainFit(slot: FXSlot) throws {
        let profile = try black()
        let shortlist = Composer.candidates(LyricsFXCatalog.components(in: slot), profile)
        let total = shortlist.reduce(0) { $0 + Composer.fit($1, profile) }
        var counts: [String: Int] = [:]
        let draws = 4000
        for seed in UInt64(0)..<UInt64(draws) {
            guard let recipe = composed(Composer.compose(profile: profile, seed: seed &* 0x9E37_79B9_7F4A_7C15)) else { continue }
            let id = switch slot {
            case .font: recipe.font
            case .backdrop: recipe.backdrop
            case .enter: recipe.enter
            case .exit: recipe.exit
            default: recipe.palette
            }
            counts[id, default: 0] += 1
        }
        for candidate in shortlist {
            let expected = Composer.fit(candidate, profile) / total
            let actual = Double(counts[candidate.id] ?? 0) / Double(draws)
            #expect(abs(actual - expected) < 0.04, "\(slot) \(candidate.id) 期望 \(expected) 實得 \(actual)")
        }
    }

    @Test func avoidingThePreviousRecipeChangesEverySlotThatHasAnAlternative() throws {
        let profile = try black()
        for seed in UInt64(0)..<256 {
            guard let first = composed(Composer.compose(profile: profile, seed: seed)),
                  let next = composed(Composer.compose(profile: profile, seed: seed &+ 1, avoiding: first)) else {
                Issue.record("應有組合配方")
                continue
            }
            #expect(next.font != first.font && next.backdrop != first.backdrop && next.enter != first.enter)
            #expect(next.exit != first.exit && next.fx1 != first.fx1 && next.palette != first.palette)
        }
    }

    /// 排除只改各槽自己的取樣：每槽恰一次亂數（Codex 字型辯論 R2 最擔心的一點）——只排除字型時，其餘五槽與種子不動
    @Test func avoidingOnlyTheFontLeavesTheOtherSlotsUntouched() throws {
        let profile = try black()
        for seed in UInt64(0)..<128 {
            guard let free = composed(Composer.compose(profile: profile, seed: seed)) else { continue }
            let onlyFont = ComposedRecipe(font: free.font, backdrop: "", enter: "", exit: "", fx1: "", fx2: "", palette: "", seed: 0, profile: profile)
            guard let avoiding = composed(Composer.compose(profile: profile, seed: seed, avoiding: onlyFont)) else { continue }
            #expect(avoiding.font != free.font)
            #expect(avoiding.backdrop == free.backdrop && avoiding.enter == free.enter && avoiding.exit == free.exit)
            #expect(avoiding.fx1 == free.fx1 && avoiding.fx2 == free.fx2 && avoiding.palette == free.palette && avoiding.seed == free.seed)
        }
    }

    @Test func withASingleCandidateTheAvoidedOneIsStillAllowed() {
        let profile = SongProfile(axes: [.aggression: 0.5], tags: [.black])
        let only = LyricsFXCatalog.all.filter { $0.slot != .font } + LyricsFXCatalog.components(in: .font).filter { $0.id == "Grimoire" }
        let previous = ComposedRecipe(font: "Grimoire", backdrop: "", enter: "", exit: "", fx1: "", fx2: "", palette: "", seed: 0, profile: profile)
        #expect(composed(Composer.compose(profile: profile, seed: 3, catalog: only, avoiding: previous))?.font == "Grimoire")
    }
}

@Suite("Catalog validator")
struct CatalogValidatorTests {
    @Test func theRealCatalogPasses() {
        #expect(CatalogValidator.problems(in: LyricsFXCatalog.all) == [])
    }

    @Test func eachRuleCatchesItsCase() {
        let good = component(.fx, "ok", vector: [.aggression: 0.5], tags: [.black])
        #expect(!CatalogValidator.problems(in: [good, component(.fx, "range", vector: [.aggression: 1.2])]).isEmpty, "值域")
        #expect(!CatalogValidator.problems(in: [good, component(.fx, "self", req: [.aggression: 0.7], forbid: [.aggression: 0.6])]).isEmpty, "自相矛盾")
        #expect(!CatalogValidator.problems(in: [good, good]).isEmpty, "id 重複")
        #expect(!CatalogValidator.problems(in: [good, component(.fx, "ind", tags: [.industrial]), component(.fx, "nuToo", tags: [.industrial, .nu])]).isEmpty, "industrial 與 nu 共用")
    }
}
