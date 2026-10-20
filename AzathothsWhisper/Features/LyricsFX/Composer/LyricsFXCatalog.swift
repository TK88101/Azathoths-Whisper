import Foundation

/// 元件目錄（B1：黑金屬＋交響子集，B1 計劃 §3.8；B2 批 1：rock 系 9 團用到的 59 個，B2 計劃 §7.3；B2 批 2：龐克系 39 個，批 2 計劃 §9.3；B2 批 3：Nu-metal 15 個，批 3 計劃 §9.3–9.4）。
/// 向量與 req／forbid **原樣取自原型 `composer.js`**，不改值。標籤：B1 與批 1 是整份照抄；**批 2 起只收「該批專屬」的標籤**
/// （＝該批各團的標籤扣掉其他團也有的），原型上其餘的標籤等它們的團進批次時再補——整份照抄會讓還沒簽字的團跟著變（批 2 計劃 F5）。
/// 移出 B1 的元件與理由見 B1 計劃 §3.8
enum LyricsFXCatalog {
    static let all: [FXComponent] = fonts + backdrops + enters + exits + effects + palettes

    static func component(_ id: String) -> FXComponent? {
        byID[id]
    }

    static func components(in slot: FXSlot) -> [FXComponent] {
        all.filter { $0.slot == slot }
    }

    static func palette(_ id: String) -> FXPalette? {
        if case .palette(let palette)? = component(id)?.payload { palette } else { nil }
    }

    static func font(_ id: String) -> FontFace? {
        if case .font(let face)? = component(id)?.payload { face } else { nil }
    }

    private static let byID: [String: FXComponent] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    private static func make(
        _ slot: FXSlot, _ id: String, _ vector: [FXAxis: Double], _ tags: Set<FXTag>,
        req: [FXAxis: Double] = [:], forbid: [FXAxis: Double] = [:], _ payload: FXComponent.Payload
    ) -> FXComponent {
        FXComponent(id: id, slot: slot, vector: vector, tags: tags, req: req, forbid: forbid, payload: payload)
    }

    // composer.js:8-13,20,21
    static let fonts: [FXComponent] = [
        make(.font, "Catacombs", [.raw: 0.8, .aggression: 0.85, .cold: 0.5, .decay: 0.9, .elegance: 0.1], [.black, .death, .thrash],
             .font(FontFace(id: "Catacombs", family: "Catacombs", weight: nil, uppercase: true))),
        make(.font, "Grimoire", [.aggression: 0.6, .elegance: 0.5, .theatrical: 0.35, .cold: 0.5, .raw: 0.4], [.black, .death, .thrash, .heavy],
             .font(FontFace(id: "Grimoire", family: "Grimoire Of Death", weight: nil, uppercase: true))),
        // composer.js:9,11,12。這三套授權未確認（Cenobyte 只寫 Freeware、Mirage Gothic 內嵌 All rights reserved、Dark Metal 無授權檔），
        // 使用者 2026-10-06 裁定「放進去，風險我承擔」
        make(.font, "Cenobyte", [.cold: 0.9, .raw: 0.6, .aggression: 0.6, .elegance: 0.35, .theatrical: 0.3], [.black, .gothic],
             .font(FontFace(id: "Cenobyte", family: "Cenobyte", weight: nil, uppercase: true, spacing: 0.2))),
        make(.font, "DarkMetal", [.raw: 0.7, .decay: 0.8, .theatrical: 0.25, .cold: 0.5, .aggression: 0.5], [.black],
             .font(FontFace(id: "DarkMetal", family: "Dark Metal", weight: nil, uppercase: true))),
        make(.font, "Mirage", [.cold: 0.6, .elegance: 0.65, .theatrical: 0.55, .aggression: 0.4], [.black, .gothic, .symphonic, .gothmetal],
             .font(FontFace(id: "Mirage", family: "Mirage Gothic", weight: nil, uppercase: true))),
        make(.font, "Fraktur", [.theatrical: 0.6, .elegance: 0.7, .cold: 0.45, .raw: 0.3, .aggression: 0.3], [.black, .symphonic, .gothic],
             .font(FontFace(id: "Fraktur", family: "UnifrakturMaguntia", weight: nil))),
        make(.font, "Cinzel", [.elegance: 0.9, .theatrical: 0.8, .bright: 0.4, .aggression: 0.15], [.symphonic, .gothic, .power, .gothmetal],
             forbid: [.aggression: 0.65], .font(FontFace(id: "Cinzel", family: "Cinzel", weight: .bold, uppercase: true))),
        make(.font, "CormorantIt", [.elegance: 0.85, .theatrical: 0.6, .cold: 0.3, .aggression: 0.05, .speed: 0.2], [.gothic, .doom, .gothmetal, .indieemo],
             forbid: [.aggression: 0.65], .font(FontFace(id: "CormorantIt", family: "Cormorant Garamond", weight: .semibold, italic: true))),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.font, "Abril", [.theatrical: 0.9, .elegance: 0.7, .bright: 0.7, .warm: 0.5], [.glam, .classicrock],
             forbid: [.raw: 0.5], .font(FontFace(id: "Abril", family: "Abril Fatface", weight: nil))),
        make(.font, "AlfaSlab", [.aggression: 0.6, .warm: 0.6, .raw: 0.5, .bounce: 0.4], [.hardrock, .classicrock, .latinmetal],
             .font(FontFace(id: "AlfaSlab", family: "Alfa Slab One", weight: nil, uppercase: true))),
        make(.font, "Anton", [.aggression: 0.7, .speed: 0.6, .raw: 0.3, .bounce: 0.3], [.hardrock, .hardcore, .nu, .death, .thrash, .punk, .skatepunk, .bigbeat, .rock, .melodichc, .ska, .rapmetal, .altmetal, .posthardcore],
             .font(FontFace(id: "Anton", family: "Anton", weight: nil, uppercase: true, sizeScale: 0.15 / 0.12, rasterizes: false))),
        make(.font, "Archivo", [.raw: 0.45, .aggression: 0.4, .bright: 0.5, .warm: 0.5], [.britpop, .indie, .powerpop, .emopop],
             .font(FontFace(id: "Archivo", family: "Archivo Black", weight: nil))),
        make(.font, "Bebas", [.aggression: 0.45, .speed: 0.5, .bright: 0.5, .raw: 0.3, .theatrical: 0.4], [.hardrock, .britpop, .arena, .altmetal, .emopop],
             .font(FontFace(id: "Bebas", family: "Bebas Neue", weight: nil, uppercase: true))),
        make(.font, "Bungee", [.bounce: 0.7, .bright: 0.75, .warm: 0.5, .speed: 0.55], [.britpop, .pop],
             forbid: [.aggression: 0.5], .font(FontFace(id: "Bungee", family: "Bungee", weight: nil, uppercase: true))),
        make(.font, "Elite", [.raw: 0.7, .decay: 0.5, .bounce: 0.2, .warm: 0.3], [.punk, .punk77, .indie, .horrormetal],
             .font(FontFace(id: "Elite", family: "Special Elite", weight: nil, uppercase: true))),
        make(.font, "Grotesk", [.cold: 0.4, .elegance: 0.5, .bright: 0.3, .speed: 0.3, .bounce: 0], [.idm, .ambient, .house, .indie, .cybermetal, .indieemo],
             .font(FontFace(id: "Grotesk", family: "Space Grotesk", weight: .regular))),
        make(.font, "Oswald", [.aggression: 0.5, .speed: 0.6, .raw: 0.35, .bounce: 0.3], [.hardrock, .britpop, .arena, .punk, .poppunk, .skatepunk, .hardcore, .rock, .bigbeat, .melodichc, .ska, .altmetal, .emopop, .posthardcore],
             .font(FontFace(id: "Oswald", family: "Oswald", weight: .bold, uppercase: true))),
        make(.font, "PlayfairIt", [.elegance: 0.8, .theatrical: 0.6, .warm: 0.5, .speed: 0.3], [.glam, .classicrock, .psych, .arena],
             forbid: [.aggression: 0.5], .font(FontFace(id: "PlayfairIt", family: "Playfair Display", weight: .bold, italic: true))),
        make(.font, "Righteous", [.bright: 0.75, .theatrical: 0.65, .bounce: 0.5, .elegance: 0.45], [.glam],
             .font(FontFace(id: "Righteous", family: "Righteous", weight: nil, uppercase: true))),
        make(.font, "Syncopate", [.cold: 0.6, .elegance: 0.7, .speed: 0.1, .theatrical: 0.6], [.psych, .arena],
             forbid: [.aggression: 0.5], .font(FontFace(id: "Syncopate", family: "Syncopate", weight: .bold, uppercase: true))),
        // B2 批 2（龐克系；原型 composer.js 的 B2 批 2 段）。標籤只收本批專屬的，其餘等它們的團進批次再補
        make(.font, "Bangers", [.bounce: 0.75, .bright: 0.7, .speed: 0.7, .aggression: 0.45], [.poppunk, .skatepunk, .ska, .rapmetal],
             .font(FontFace(id: "Bangers", family: "Bangers", weight: nil, uppercase: true))),
        make(.font, "Dela", [.bounce: 0.6, .bright: 0.6, .aggression: 0.4, .speed: 0.6], [.poppunk],
             .font(FontFace(id: "Dela", family: "Dela Gothic One", weight: nil, uppercase: true))),
        make(.font, "Gochi", [.warm: 0.7, .elegance: 0.45, .bounce: 0.35, .raw: 0.25, .theatrical: 0.5], [.poprock, .indieemo, .emopop],
             forbid: [.aggression: 0.5], .font(FontFace(id: "Gochi", family: "Gochi Hand", weight: nil))),
        make(.font, "Lilita", [.bounce: 0.65, .bright: 0.75, .warm: 0.6, .aggression: 0.35], [.poprock, .poppunk, .ska],
             .font(FontFace(id: "Lilita", family: "Lilita One", weight: nil))),
        make(.font, "Marker", [.raw: 0.65, .bounce: 0.5, .speed: 0.7, .warm: 0.4, .aggression: 0.5], [.punk, .skatepunk, .melodichc, .rapmetal, .posthardcore, .emopop],
             .font(FontFace(id: "Marker", family: "Permanent Marker", weight: nil, uppercase: true))),
        make(.font, "Rubik", [.bright: 0.7, .bounce: 0.45, .warm: 0.5, .raw: 0.25, .aggression: 0.3], [.powerpop, .poprock, .emopop],
             .font(FontFace(id: "Rubik", family: "Rubik", weight: .bold))),
        make(.font, "SairaStencil", [.aggression: 0.75, .raw: 0.4, .speed: 0.8, .cold: 0.3], [.melodichc],
             .font(FontFace(id: "SairaStencil", family: "Saira Stencil One", weight: nil, uppercase: true))),
        // B2 批 3（Nu-metal；原型 composer.js 的 B2 批 3 段）。標籤只收本批專屬的（新團的私有子標籤＋連帶的 Korn／Hatebreed 的 nu、hardcore）
        make(.font, "Barrio", [.warm: 0.75, .bounce: 0.55, .raw: 0.5, .aggression: 0.55, .theatrical: 0.45], [.latinmetal],
             .font(FontFace(id: "Barrio", family: "Barrio", weight: nil, uppercase: true))),
        make(.font, "BlackOps", [.aggression: 0.7, .raw: 0.45, .speed: 0.6], [.horrormetal, .cybermetal, .hardcore, .nu],
             .font(FontFace(id: "BlackOps", family: "Black Ops One", weight: nil, uppercase: true))),
        make(.font, "SpaceMono", [.cold: 0.5, .bright: 0.4, .speed: 0.6, .bounce: 0.1], [.cybermetal],
             .font(FontFace(id: "SpaceMono", family: "Space Mono", weight: .bold, uppercase: true))),
        // B2 批 4（emo 群；原型 composer.js 的 B2 批 4 段）。標籤只收本批私有的（emo／posthardcore／indieemo／emopop）
        make(.font, "CourierPrime", [.cold: 0.4, .elegance: 0.5, .raw: 0.3, .speed: 0.3, .aggression: 0.2], [.indieemo, .emo],
             .font(FontFace(id: "CourierPrime", family: "Courier Prime", weight: .bold))),
        make(.font, "IMFell", [.theatrical: 0.85, .decay: 0.6, .elegance: 0.5, .aggression: 0.5], [.emo],
             req: [.theatrical: 0.5], .font(FontFace(id: "IMFell", family: "IM FELL English SC", weight: nil))),
        make(.font, "RockSalt", [.raw: 0.7, .decay: 0.5, .theatrical: 0.55, .aggression: 0.6], [.emo, .posthardcore],
             .font(FontFace(id: "RockSalt", family: "Rock Salt", weight: nil, sizeScale: 0.085 / 0.12))),
        make(.font, "ShadowsLight", [.warm: 0.45, .elegance: 0.4, .raw: 0.4, .theatrical: 0.45, .aggression: 0.3], [.indieemo, .emo, .emopop],
             .font(FontFace(id: "ShadowsLight", family: "Shadows Into Light", weight: nil))),
    ]

    // composer.js:36-40,43
    static let backdrops: [FXComponent] = [
        make(.backdrop, "void", [.raw: 0.5, .cold: 0.6, .theatrical: 0.1], [], .backdrop(.void)),
        make(.backdrop, "film", [.raw: 0.95, .decay: 0.7, .theatrical: 0.1], [.black, .death, .hardcore, .thrash, .horrormetal], .backdrop(.film)),
        make(.backdrop, "snow", [.cold: 0.95, .theatrical: 0.3, .elegance: 0.3], [.black, .gothic, .doom], .backdrop(.snow)),
        make(.backdrop, "shafts", [.theatrical: 0.95, .elegance: 0.85, .bright: 0.4], [.symphonic, .gothic, .power, .gothmetal],
             req: [.theatrical: 0.45], forbid: [.aggression: 0.65], .backdrop(.shafts)),
        make(.backdrop, "ash", [.theatrical: 0.5, .elegance: 0.5, .decay: 0.55, .cold: 0.3], [.gothic, .doom, .black, .gothmetal], .backdrop(.ash)),
        make(.backdrop, "crimsonFog", [.theatrical: 0.85, .aggression: 0.7, .decay: 0.6, .elegance: 0.4, .bright: 0.05], [.black, .gothic, .gothmetal],
             req: [.theatrical: 0.6], .backdrop(.crimsonFog)),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.backdrop, "ampGlow", [.warm: 0.7, .aggression: 0.55, .bright: 0.4, .theatrical: 0.45], [.hardrock, .arena, .classicrock],
             .backdrop(.ampGlow)),
        make(.backdrop, "embers", [.theatrical: 0.5, .aggression: 0.45, .bright: 0.5], [.hardrock, .power, .heavy, .thrash, .latinmetal],
             .backdrop(.embers)),
        make(.backdrop, "halftone", [.bright: 0.8, .bounce: 0.6, .warm: 0.6], [.britpop, .pop, .classicrock],
             forbid: [.aggression: 0.5, .elegance: 0.7], .backdrop(.halftone)),
        make(.backdrop, "haze", [.elegance: 0.6, .cold: 0.3, .bright: 0.3, .speed: 0.1], [.psych, .ambient, .idm, .indie, .house, .indieemo],
             .backdrop(.haze)),
        make(.backdrop, "paper", [.raw: 0.6, .decay: 0.5, .warm: 0.5, .bounce: 0.3], [.punk, .punk77, .indie],
             .backdrop(.paper)),
        make(.backdrop, "prism", [.cold: 0.6, .theatrical: 0.75, .elegance: 0.7, .speed: 0.1], [.psych],
             forbid: [.aggression: 0.5], .backdrop(.prism)),
        make(.backdrop, "smokeHaze", [.raw: 0.6, .decay: 0.45, .warm: 0.5, .theatrical: 0.5], [.hardrock, .altmetal, .latinmetal],
             .backdrop(.smokeHaze)),
        make(.backdrop, "spot", [.theatrical: 0.8, .bright: 0.4, .elegance: 0.5], [.glam, .arena, .classicrock, .hardrock, .emo],
             .backdrop(.spot)),
        make(.backdrop, "stars", [.elegance: 0.75, .bright: 0.5, .cold: 0.35, .speed: 0.2, .theatrical: 0.5], [.arena, .psych],
             forbid: [.aggression: 0.5], .backdrop(.stars)),
        make(.backdrop, "sunset", [.warm: 0.9, .bright: 0.7, .bounce: 0.4, .elegance: 0.3], [.poppunk, .skatepunk, .pop, .indie, .rock, .poprock, .powerpop, .emopop],
             .backdrop(.sunset)),
        make(.backdrop, "tapeLeak", [.warm: 0.75, .raw: 0.45, .bright: 0.5, .decay: 0.3], [.britpop, .classicrock, .hardrock, .indie, .indieemo, .emopop],
             .backdrop(.tapeLeak)),
        // B2 批 2（龐克系；原型 composer.js 的 B2 批 2 段）。標籤只收本批專屬的，其餘等它們的團進批次再補
        make(.backdrop, "bokeh", [.elegance: 0.5, .theatrical: 0.55, .warm: 0.6, .bright: 0.5, .speed: 0.4], [.poprock, .indieemo, .emopop],
             forbid: [.aggression: 0.6], .backdrop(.bokeh)),
        make(.backdrop, "checker", [.bounce: 0.9, .bright: 0.6, .speed: 0.7], [.ska],
             .backdrop(.checker)),
        make(.backdrop, "flat", [.bright: 0.8, .bounce: 0.7, .warm: 0.5, .raw: 0.2], [.ska, .powerpop, .poprock, .poppunk, .skatepunk, .emopop],
             .backdrop(.flat)),
        make(.backdrop, "gig", [.aggression: 0.7, .raw: 0.5, .warm: 0.4, .speed: 0.7, .theatrical: 0.35], [.melodichc, .punk, .skatepunk, .ska, .rapmetal, .altmetal, .posthardcore, .emopop],
             .backdrop(.gig)),
        make(.backdrop, "skyGrad", [.bright: 0.7, .raw: 0.2, .bounce: 0.45, .warm: 0.45], [.powerpop, .poprock, .emopop],
             forbid: [.aggression: 0.6], .backdrop(.skyGrad)),
        make(.backdrop, "xerox", [.raw: 0.7, .aggression: 0.55, .decay: 0.4, .speed: 0.6], [.punk, .skatepunk, .melodichc, .horrormetal, .posthardcore],
             .backdrop(.xerox)),
        // B2 批 3（Nu-metal；原型 composer.js 的 B2 批 3 段）。標籤只收本批專屬的（新團的私有子標籤＋連帶的 Korn／Hatebreed 的 nu、hardcore）
        make(.backdrop, "grid", [.bright: 0.4, .aggression: 0.4, .cold: 0.4], [.cybermetal, .nu],
             .backdrop(.grid)),
        make(.backdrop, "scan", [.aggression: 0.5, .raw: 0.4, .bright: 0.2], [.cybermetal, .rapmetal, .nu, .hardcore],
             .backdrop(.scan)),
        // B2 批 4（emo 群；原型 composer.js 的 B2 批 4 段）。標籤只收本批私有的（emo／posthardcore／indieemo／emopop）
        make(.backdrop, "bluehour", [.cold: 0.55, .elegance: 0.6, .bright: 0.4, .speed: 0.15], [.indieemo, .emo],
             .backdrop(.bluehour)),
    ]

    // composer.js:55,57-61,64。淡入型（condense、smoke、rise）的時長依 P12 縮短 40%（使用者 2026-10-06：「漸入漸出稍長，字發虛」）
    static let enters: [FXComponent] = [
        // slam（彈片堆）2026-10-19 依使用者指示拿掉：詞互相疊住、讀不出歌詞。引擎的 pile／expires 畫法保留未刪
        make(.enter, "condense", [.cold: 0.85, .speed: 0.1, .elegance: 0.4], [.black, .gothic, .doom],
             .enter(EnterSpec(weights: [(.condense, 4), (.fadeUp, 1)], duration: 0.54...1.02))),
        make(.enter, "negative", [.raw: 0.8, .aggression: 0.6, .speed: 0.6], [.black],
             .enter(EnterSpec(weights: [(.negative, 3), (.fadeUp, 1)], duration: 0.2...0.35))),
        make(.enter, "smoke", [.theatrical: 0.6, .elegance: 0.55, .speed: 0.2, .cold: 0.3], [.gothic, .doom, .symphonic, .gothmetal],
             .enter(EnterSpec(weights: [(.smoke, 4), (.fadeUp, 1)], duration: 0.36...0.78))),
        make(.enter, "rise", [.theatrical: 0.85, .elegance: 0.85, .speed: 0.2, .bright: 0.4], [.symphonic, .power, .gothic, .gothmetal],
             forbid: [.raw: 0.8, .aggression: 0.65], .enter(EnterSpec(weights: [(.rise, 4), (.grow, 1)], duration: 0.36...0.72))),
        make(.enter, "swoop", [.theatrical: 0.55, .speed: 0.6, .elegance: 0.3], [.glam, .arena, .symphonic, .power, .gothic, .heavy, .gothmetal, .emo],
             .enter(EnterSpec(weights: [(.swoop, 3), (.orbit, 1), (.fling, 1)], duration: 0.3...0.6))),
        make(.enter, "lash", [.aggression: 0.85, .theatrical: 0.8, .speed: 0.85, .elegance: 0.4], [.black, .gothic, .symphonic],
             req: [.theatrical: 0.6], .enter(EnterSpec(weights: [(.fling, 3), (.slant, 2), (.swoop, 1)], duration: 0.12...0.25))),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.enter, "bloom", [.elegance: 0.75, .speed: 0.15, .theatrical: 0.6], [.psych, .arena, .classicrock, .indieemo],
             forbid: [.aggression: 0.5], .enter(EnterSpec(weights: [(.grow, 3), (.fadeUp, 2)], duration: 0.6...1.2))),
        make(.enter, "fadeUp", [.elegance: 0.5, .bounce: 0.1, .speed: 0.3], [.britpop, .arena, .psych, .classicrock, .indie, .ambient, .rock, .punk, .idm, .poprock, .powerpop, .indieemo],
             .enter(EnterSpec(weights: [(.fadeUp, 4), (.grow, 1)], duration: 0.3...0.6))),
        make(.enter, "hop", [.bounce: 0.65, .bright: 0.7, .warm: 0.6, .speed: 0.5], [.britpop, .classicrock, .pop, .ska, .poprock, .powerpop, .poppunk, .emopop],
             forbid: [.aggression: 0.5, .theatrical: 0.8], .enter(EnterSpec(weights: [(.pop, 3), (.fallIn, 2), (.fadeUp, 1)], duration: 0.18...0.4))),
        make(.enter, "kick", [.aggression: 0.6, .bounce: 0.5, .speed: 0.65, .warm: 0.4], [.hardrock, .rapmetal, .latinmetal],
             .enter(EnterSpec(weights: [(.stamp, 3), (.pop, 2), (.slide, 1)], duration: 0.12...0.28))),
        make(.enter, "slide", [.aggression: 0.6, .speed: 0.7, .bounce: 0.2], [.hardrock, .heavy, .thrash, .nu, .hardcore, .punk, .skatepunk, .rock, .bigbeat, .melodichc, .ska, .rapmetal, .altmetal, .posthardcore, .emopop],
             .enter(EnterSpec(weights: [(.slide, 4), (.stamp, 1)], duration: 0.15...0.35))),
        make(.enter, "stamp", [.aggression: 0.7, .speed: 0.8, .raw: 0.3], [.hardrock, .hardcore, .nu, .heavy, .thrash, .rapmetal, .altmetal, .latinmetal, .posthardcore],
             .enter(EnterSpec(weights: [(.stamp, 4), (.pop, 1)], duration: 0.1...0.25))),
        make(.enter, "strut", [.theatrical: 0.8, .bright: 0.6, .speed: 0.5, .elegance: 0.5], [.glam, .arena],
             .enter(EnterSpec(weights: [(.slant, 3), (.swoop, 2), (.stamp, 1)], duration: 0.2...0.4))),
        make(.enter, "swagger", [.raw: 0.5, .aggression: 0.4, .speed: 0.45, .warm: 0.5], [.britpop, .hardrock, .indie, .latinmetal],
             .enter(EnterSpec(weights: [(.slide, 3), (.fadeUp, 2)], duration: 0.3...0.55))),
        // B2 批 2（龐克系；原型 composer.js 的 B2 批 2 段）。標籤只收本批專屬的，其餘等它們的團進批次再補
        make(.enter, "ease", [.elegance: 0.4, .bounce: 0.35, .speed: 0.5, .warm: 0.5], [.poprock, .powerpop, .indieemo, .emopop],
             .enter(EnterSpec(weights: [(.fadeUp, 3), (.pop, 1)], duration: 0.25...0.5))),
        make(.enter, "pop", [.bounce: 0.9, .bright: 0.6, .speed: 0.6, .aggression: 0.2], [.ska, .poprock, .powerpop, .poppunk, .emopop],
             forbid: [.raw: 0.7], .enter(EnterSpec(weights: [(.pop, 4), (.fallIn, 2)], duration: 0.18...0.4))),
        make(.enter, "punch", [.aggression: 0.75, .speed: 0.9, .raw: 0.4], [.melodichc, .skatepunk, .emopop, .posthardcore],
             .enter(EnterSpec(weights: [(.stamp, 3), (.slide, 2)], duration: 0.08...0.2))),
        make(.enter, "skank", [.bounce: 0.9, .speed: 0.75, .bright: 0.6], [.ska],
             .enter(EnterSpec(weights: [(.pop, 2), (.slide, 2), (.fallIn, 1)], duration: 0.14...0.3))),
        make(.enter, "tumble", [.bounce: 0.6, .aggression: 0.6, .speed: 0.8, .raw: 0.5], [.ska, .punk, .punk77, .skatepunk, .hardcore],
             .enter(EnterSpec(weights: [(.tumble, 3), (.stamp, 2), (.fling, 1)], duration: 0.12...0.3))),
        // B2 批 3（Nu-metal；原型 composer.js 的 B2 批 3 段）。標籤只收本批專屬的（新團的私有子標籤＋連帶的 Korn／Hatebreed 的 nu、hardcore）
        make(.enter, "drop", [.aggression: 0.8, .speed: 0.7, .raw: 0.4], [.horrormetal, .altmetal, .hardcore, .nu],
             .enter(EnterSpec(weights: [(.drop, 4), (.stamp, 1)], duration: 0.18...0.4))),
        make(.enter, "flip", [.speed: 0.9, .aggression: 0.5, .cold: 0.4, .bounce: 0.3], [.cybermetal],
             .enter(EnterSpec(weights: [(.flip, 4), (.type, 1)], duration: 0.08...0.2))),
        make(.enter, "type", [.raw: 0.5, .aggression: 0.5, .speed: 0.9], [.cybermetal, .nu, .hardcore],
             .enter(EnterSpec(weights: [(.type, 5), (.flip, 1)], duration: 0.06...0.15))),
        // B2 批 4（emo 群；原型 composer.js 的 B2 批 4 段）。標籤只收本批私有的（emo／posthardcore／indieemo／emopop）
        make(.enter, "lurch", [.aggression: 0.75, .speed: 0.8, .raw: 0.6, .theatrical: 0.5], [.posthardcore, .emo],
             .enter(EnterSpec(weights: [(.fling, 3), (.stamp, 2), (.slant, 1)], duration: 0.12...0.26))),
        make(.enter, "scrawl", [.raw: 0.6, .speed: 0.6, .theatrical: 0.5, .aggression: 0.5], [.emo, .posthardcore],
             .enter(EnterSpec(weights: [(.type, 3), (.slant, 2), (.fadeUp, 1)], duration: 0.1...0.24))),
    ]

    // composer.js:73-75,77
    static let exits: [FXComponent] = [
        make(.exit, "cut", [.aggression: 0.9, .raw: 0.8, .speed: 0.9], [.black, .death, .hardcore, .grind, .horrormetal, .cybermetal, .posthardcore],
             .exit(ExitSpec(weights: [(.cut, 1)], duration: 0))),
        make(.exit, "scatter", [.cold: 0.6, .raw: 0.5], [.black, .cybermetal], .exit(ExitSpec(weights: [(.scatter, 1)], duration: 0.7))),
        make(.exit, "dissolve", [.cold: 0.75, .elegance: 0.45, .speed: 0.1], [.black, .gothic, .doom, .gothmetal],
             .exit(ExitSpec(weights: [(.dissolve, 1)], duration: 1.6, trail: true))),
        make(.exit, "fade", [.elegance: 0.7, .theatrical: 0.5, .speed: 0.1], [.symphonic, .gothic, .doom, .gothmetal, .indieemo],
             .exit(ExitSpec(weights: [(.fade, 1)], duration: 1.2, trail: true))),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.exit, "dropOut", [.aggression: 0.55, .speed: 0.6, .bounce: 0.4], [.hardrock, .glam, .britpop, .rapmetal, .emopop],
             .exit(ExitSpec(weights: [(.fall, 2), (.shrink, 2)], duration: 0.45))),
        make(.exit, "fadeShort", [.elegance: 0.55, .speed: 0.35, .bright: 0.5], [.arena, .britpop, .classicrock, .glam, .indie, .indieemo],
             .exit(ExitSpec(weights: [(.fade, 1)], duration: 0.6))),
        make(.exit, "fall", [.aggression: 0.6, .speed: 0.6], [.hardrock, .glam, .heavy, .thrash, .death, .power, .altmetal, .horrormetal, .latinmetal],
             .exit(ExitSpec(weights: [(.fall, 3), (.shrink, 1)], duration: 0.5))),
        make(.exit, "floatAway", [.elegance: 0.7, .speed: 0.1, .cold: 0.4], [.psych, .arena],
             forbid: [.aggression: 0.5], .exit(ExitSpec(weights: [(.up, 2), (.scatter, 1)], duration: 1))),
        make(.exit, "slideOut", [.speed: 0.7, .aggression: 0.4], [.hardrock, .britpop, .rock, .punk, .techno, .electro, .house, .melodichc, .skatepunk, .rapmetal, .altmetal, .nu, .latinmetal, .emopop],
             .exit(ExitSpec(weights: [(.slideOut, 1)], duration: 0.4))),
        make(.exit, "up", [.elegance: 0.4, .bounce: 0.2, .speed: 0.4], [.britpop, .arena, .classicrock, .pop, .indie, .rock, .house, .idm, .poppunk, .ska, .poprock, .powerpop, .emopop, .indieemo],
             .exit(ExitSpec(weights: [(.up, 1)], duration: 0.5))),
        // B2 批 2（龐克系；原型 composer.js 的 B2 批 2 段）。標籤只收本批專屬的，其餘等它們的團進批次再補
        make(.exit, "drift", [.elegance: 0.5, .speed: 0.35, .warm: 0.5], [.poprock, .powerpop, .indieemo, .emopop],
             forbid: [.aggression: 0.6], .exit(ExitSpec(weights: [(.up, 2), (.fade, 1)], duration: 0.7))),
        make(.exit, "rip", [.aggression: 0.65, .speed: 0.9, .raw: 0.5], [.melodichc, .skatepunk, .punk, .posthardcore, .emopop],
             .exit(ExitSpec(weights: [(.slideOut, 3), (.fall, 1)], duration: 0.25))),
        make(.exit, "snapOut", [.bounce: 0.65, .speed: 0.7, .bright: 0.6], [.poppunk, .ska, .powerpop, .poprock, .emopop],
             .exit(ExitSpec(weights: [(.shrink, 3), (.up, 1)], duration: 0.3))),
        make(.exit, "tumbleOut", [.bounce: 0.7, .speed: 0.7, .aggression: 0.4], [.ska, .punk, .poppunk, .skatepunk, .punk77],
             .exit(ExitSpec(weights: [(.tumbleOut, 3), (.fall, 1)], duration: 0.5))),
        // B2 批 3（Nu-metal；原型 composer.js 的 B2 批 3 段）。標籤只收本批專屬的（新團的私有子標籤＋連帶的 Korn／Hatebreed 的 nu、hardcore）
        make(.exit, "bands", [.aggression: 0.6, .speed: 0.8, .raw: 0.3], [.cybermetal, .rapmetal, .nu, .hardcore],
             .exit(ExitSpec(weights: [(.bands, 3), (.slideOut, 1)], duration: 0.3))),
        // B2 批 4（emo 群；原型 composer.js 的 B2 批 4 段）。標籤只收本批私有的（emo／posthardcore／indieemo／emopop）
        make(.exit, "sink", [.theatrical: 0.6, .decay: 0.5, .elegance: 0.4, .speed: 0.3], [.emo, .indieemo],
             .exit(ExitSpec(weights: [(.fall, 1), (.fade, 2)], duration: 0.8))),
        make(.exit, "wither", [.decay: 0.6, .theatrical: 0.5, .aggression: 0.4], [.emo],
             .exit(ExitSpec(weights: [(.shrink, 2), (.fall, 1), (.fade, 1)], duration: 0.6))),
    ]

    // composer.js:87,88,92,101
    static let effects: [FXComponent] = [
        make(.fx, "shake", [.aggression: 0.9, .speed: 0.7], [.black, .death, .hardcore, .thrash, .nu, .melodichc, .horrormetal, .altmetal, .posthardcore], .fx(.shake)),
        make(.fx, "misreg", [.raw: 0.9, .decay: 0.5], [.black, .hardcore, .horrormetal, .posthardcore], .fx(.misreg)),
        make(.fx, "breathe", [.elegance: 0.6, .theatrical: 0.5, .speed: 0.2], [.psych, .arena, .symphonic, .gothic, .doom, .power, .gothmetal, .indieemo],
             forbid: [.aggression: 0.65], .fx(.breathe)),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.fx, "bob", [.bounce: 0.6, .warm: 0.6, .bright: 0.6], [.britpop, .classicrock, .pop, .poppunk, .ska, .powerpop, .poprock, .emopop],
             forbid: [.aggression: 0.5, .theatrical: 0.8], .fx(.bob)),
        make(.fx, "flicker", [.warm: 0.6, .decay: 0.4, .raw: 0.5, .theatrical: 0.5], [.hardrock, .psych, .latinmetal, .emo],
             .fx(.flicker)),
        make(.fx, "glow", [.theatrical: 0.75, .elegance: 0.75, .bright: 0.5], [.glam, .arena, .symphonic, .power, .gothic, .gothmetal],
             forbid: [.raw: 0.75, .aggression: 0.65], .fx(.glow)),
        make(.fx, "neonstroke", [.bright: 0.8, .theatrical: 0.5, .bounce: 0.4, .warm: 0.3], [.arena, .house, .frenchhouse, .electro, .pop],
             .fx(.neonstroke)),
        make(.fx, "reflect", [.elegance: 0.6, .theatrical: 0.5], [.psych, .glam, .gothic, .doom, .symphonic, .gothmetal, .indieemo, .emo],
             .fx(.reflect)),
        make(.fx, "thump", [.aggression: 0.6, .speed: 0.6, .bounce: 0.6], [.hardrock, .arena, .bigbeat, .techno, .hardcore, .house, .poppunk, .melodichc, .rapmetal, .altmetal, .latinmetal, .posthardcore, .emopop],
             .fx(.thump)),
        make(.fx, "wobble", [.raw: 0.5, .aggression: 0.5, .bounce: 0.4], [.hardrock, .britpop, .punk, .skatepunk, .ska, .rapmetal, .emopop, .posthardcore],
             .fx(.wobble)),
        make(.fx, "none", [:], [], .fx(.none)),
        // B2 批 2（龐克系；原型 composer.js 的 B2 批 2 段）。標籤只收本批專屬的，其餘等它們的團進批次再補
        make(.fx, "jitter", [.raw: 0.7, .speed: 0.75, .aggression: 0.55], [.punk, .skatepunk, .melodichc, .punk77, .cybermetal, .horrormetal, .emo, .posthardcore],
             .fx(.jitter)),
        make(.fx, "ransom", [.raw: 0.8, .decay: 0.5, .bounce: 0.5, .warm: 0.2], [.punk77],
             forbid: [.elegance: 0.6], .fx(.ransom)),
        make(.fx, "ransomPop", [.bounce: 0.6, .bright: 0.65, .raw: 0.35, .speed: 0.85, .aggression: 0.45], [.poppunk],
             forbid: [.theatrical: 0.4], .fx(.ransom)),
        make(.fx, "speedlines", [.speed: 0.9, .aggression: 0.5, .bounce: 0.4], [.melodichc, .skatepunk, .poppunk, .emopop],
             .fx(.speedlines)),
        make(.fx, "tilt", [.bounce: 0.6, .bright: 0.55, .raw: 0.35], [.ska, .poppunk, .skatepunk, .powerpop, .emopop],
             .fx(.tilt)),
        // B2 批 3（Nu-metal；原型 composer.js 的 B2 批 3 段）。標籤只收本批專屬的（新團的私有子標籤＋連帶的 Korn／Hatebreed 的 nu、hardcore）
        make(.fx, "rgbsplit", [.aggression: 0.5, .speed: 0.8, .bright: 0.4], [.cybermetal, .nu],
             .fx(.rgbsplit)),
        // B2 批 4（emo 群；原型 composer.js 的 B2 批 4 段）。標籤只收本批私有的（emo／posthardcore／indieemo／emopop）
        make(.fx, "weep", [.theatrical: 0.7, .decay: 0.6, .elegance: 0.3, .raw: 0.4], [.emo],
             .fx(.weep)),
    ]

    // composer.js:104-107,110,113
    static let palettes: [FXComponent] = [
        make(.palette, "boneBlood", [.aggression: 0.7, .raw: 0.6, .decay: 0.5], [.black, .death, .melodeath],
             .palette(FXPalette(bg: RGB(hex: 0x050506), fg: RGB(hex: 0xE8ECEF), acc: RGB(hex: 0x7A0B14), dim: RGB(hex: 0x9AA3AB)))),
        make(.palette, "ice", [.cold: 0.95, .elegance: 0.4], [.black, .doom, .gothmetal],
             .palette(FXPalette(bg: RGB(hex: 0x05070A), fg: RGB(hex: 0xD8DEE4), acc: RGB(hex: 0xD8DEE4), dim: RGB(hex: 0x7C8793)))),
        make(.palette, "goldNavy", [.theatrical: 0.9, .elegance: 0.85, .bright: 0.5], [.symphonic, .power],
             forbid: [.raw: 0.75, .aggression: 0.65],
             .palette(FXPalette(bg: RGB(hex: 0x0E1733), fg: RGB(hex: 0xC9A227), acc: RGB(hex: 0xF0D47A), dim: RGB(hex: 0x6B5A45)))),
        // 字色 2026-10-20 由 #8A1C2B（對比約 2.1，B1 簽字時的例外）改為 #FF6E6E：使用者看新舊並排後重簽；背景與輔助色不變
        make(.palette, "crimsonVelvet", [.theatrical: 0.7, .elegance: 0.65, .decay: 0.5], [.gothic, .doom, .symphonic],
             .palette(FXPalette(bg: RGB(hex: 0x140A1A), fg: RGB(hex: 0xFF6E6E), acc: RGB(hex: 0xC9A0A8), dim: RGB(hex: 0x6B5C73)))),
        make(.palette, "bloodBlack", [.theatrical: 0.85, .aggression: 0.8, .decay: 0.6, .bright: 0.05, .elegance: 0.4], [.black, .gothic, .horrormetal, .gothmetal],
             .palette(FXPalette(bg: RGB(hex: 0x030203), fg: RGB(hex: 0xEDE6DA), acc: RGB(hex: 0xB3001B), dim: RGB(hex: 0x4A2A2E)))),
        make(.palette, "ashGrey", [.raw: 0.8, .decay: 0.7, .cold: 0.4], [.black, .hardcore, .death, .horrormetal],
             .palette(FXPalette(bg: RGB(hex: 0x060606), fg: RGB(hex: 0xC8C8C8), acc: RGB(hex: 0x8F0F1A), dim: RGB(hex: 0x666666)))),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.palette, "ampRed", [.aggression: 0.65, .warm: 0.6, .bright: 0.5, .raw: 0.5], [.hardrock, .altmetal, .latinmetal],
             .palette(FXPalette(bg: RGB(hex: 0x0B0909), fg: RGB(hex: 0xF4EFE6), acc: RGB(hex: 0xD81E1E), dim: RGB(hex: 0x5A4A46)))),
        make(.palette, "britRed", [.bright: 0.75, .bounce: 0.65, .speed: 0.55], [.britpop, .indie],
             .palette(FXPalette(bg: RGB(hex: 0xF3F0E8), fg: RGB(hex: 0x17203A), acc: RGB(hex: 0xD5202B), dim: RGB(hex: 0x9AA0AE)))),
        make(.palette, "cream60", [.warm: 0.85, .bright: 0.7, .elegance: 0.5, .bounce: 0.4], [.classicrock, .britpop],
             forbid: [.aggression: 0.5], .palette(FXPalette(bg: RGB(hex: 0xF1E6CF), fg: RGB(hex: 0x3B2A1E), acc: RGB(hex: 0xD9622B), dim: RGB(hex: 0xA8977A)))),
        make(.palette, "dusk", [.elegance: 0.7, .theatrical: 0.6, .cold: 0.4, .warm: 0.3, .speed: 0.15], [.psych, .arena],
             .palette(FXPalette(bg: RGB(hex: 0x141026), fg: RGB(hex: 0xD9CFF2), acc: RGB(hex: 0xF2A65A), dim: RGB(hex: 0x5A4F7A)))),
        make(.palette, "hazard", [.aggression: 0.6, .bounce: 0.5, .bright: 0.55, .speed: 0.6], [.hardrock, .arena, .rapmetal],
             .palette(FXPalette(bg: RGB(hex: 0x0A0A0B), fg: RGB(hex: 0xEDEDED), acc: RGB(hex: 0xFFC400), dim: RGB(hex: 0x55555A)))),
        make(.palette, "mancSky", [.raw: 0.45, .bright: 0.6, .cold: 0.3, .warm: 0.4], [.britpop],
             .palette(FXPalette(bg: RGB(hex: 0xDCE6EE), fg: RGB(hex: 0x14233A), acc: RGB(hex: 0x2C6FB7), dim: RGB(hex: 0x8FA3B5)))),
        make(.palette, "newsprint", [.raw: 0.5, .decay: 0.4, .warm: 0.4, .bounce: 0.3], [.punk77, .punk, .indie],
             .palette(FXPalette(bg: RGB(hex: 0xE9E2CF), fg: RGB(hex: 0x1A1A1A), acc: RGB(hex: 0xC8102E), dim: RGB(hex: 0x9A9A9A)))),
        make(.palette, "parka", [.raw: 0.55, .warm: 0.55, .aggression: 0.4, .decay: 0.3], [.britpop, .indie, .indieemo],
             .palette(FXPalette(bg: RGB(hex: 0x1C2418), fg: RGB(hex: 0xE8E2CF), acc: RGB(hex: 0xD9A441), dim: RGB(hex: 0x5F6B52)))),
        make(.palette, "popArt", [.bright: 0.9, .bounce: 0.65, .warm: 0.7], [.britpop, .pop],
             forbid: [.aggression: 0.5], .palette(FXPalette(bg: RGB(hex: 0xF4D21F), fg: RGB(hex: 0x16161D), acc: RGB(hex: 0xE4322B), dim: RGB(hex: 0x8A7A1A)))),
        make(.palette, "prismBlack", [.cold: 0.65, .elegance: 0.75, .theatrical: 0.7, .bright: 0.25], [.psych, .gothmetal, .cybermetal],
             .palette(FXPalette(bg: RGB(hex: 0x050507), fg: RGB(hex: 0xF2F2F4), acc: RGB(hex: 0x7FD4FF), dim: RGB(hex: 0x4A4A58)))),
        make(.palette, "royal", [.theatrical: 0.95, .elegance: 0.75, .bright: 0.7, .warm: 0.5], [.glam],
             .palette(FXPalette(bg: RGB(hex: 0x1B0A24), fg: RGB(hex: 0xF2D9A0), acc: RGB(hex: 0xFF4F8B), dim: RGB(hex: 0x6E4F7A)))),
        make(.palette, "starlight", [.elegance: 0.75, .bright: 0.75, .warm: 0.6, .speed: 0.3], [.arena],
             forbid: [.aggression: 0.5], .palette(FXPalette(bg: RGB(hex: 0x0A1230), fg: RGB(hex: 0xF6E7A8), acc: RGB(hex: 0xFFFFFF), dim: RGB(hex: 0x44507A)))),
        make(.palette, "tuxedo", [.theatrical: 0.8, .elegance: 0.7, .bright: 0.6], [.glam, .arena, .classicrock],
             .palette(FXPalette(bg: RGB(hex: 0x0D0D12), fg: RGB(hex: 0xFFFFFF), acc: RGB(hex: 0xE8B84A), dim: RGB(hex: 0x5B5B66)))),
        make(.palette, "vegas", [.bright: 0.75, .theatrical: 0.7, .bounce: 0.5, .warm: 0.5], [.arena],
             .palette(FXPalette(bg: RGB(hex: 0x0B0A1E), fg: RGB(hex: 0xFFF4E0), acc: RGB(hex: 0xFF4D6D), dim: RGB(hex: 0x3B3A6B)))),
        make(.palette, "whiskey", [.warm: 0.8, .raw: 0.6, .decay: 0.45, .theatrical: 0.5], [.hardrock, .classicrock, .latinmetal],
             .palette(FXPalette(bg: RGB(hex: 0x120C07), fg: RGB(hex: 0xE9C27A), acc: RGB(hex: 0xF4EBDD), dim: RGB(hex: 0x6A5236)))),
        // B2 批 2（龐克系；原型 composer.js 的 B2 批 2 段）。標籤只收本批專屬的，其餘等它們的團進批次再補
        make(.palette, "chalk", [.bright: 0.75, .raw: 0.3, .bounce: 0.45, .cold: 0.25], [.powerpop],
             .palette(FXPalette(bg: RGB(hex: 0xEEF3F2), fg: RGB(hex: 0x1E2B33), acc: RGB(hex: 0x0B7A50), dim: RGB(hex: 0x9AA9AE)))),
        make(.palette, "daydream", [.warm: 0.7, .bright: 0.75, .bounce: 0.4, .elegance: 0.4], [.poprock],
             .palette(FXPalette(bg: RGB(hex: 0xF6EFE6), fg: RGB(hex: 0x2B2A3A), acc: RGB(hex: 0xC2334D), dim: RGB(hex: 0xA9A2A8)))),
        make(.palette, "gigRed", [.aggression: 0.7, .raw: 0.5, .speed: 0.75, .bright: 0.4], [.melodichc, .punk, .skatepunk, .rapmetal, .altmetal, .posthardcore, .emopop],
             .palette(FXPalette(bg: RGB(hex: 0x0C0A0A), fg: RGB(hex: 0xF2EDE4), acc: RGB(hex: 0xE0241B), dim: RGB(hex: 0x5A4B48)))),
        make(.palette, "mallPink", [.bright: 0.6, .bounce: 0.6, .aggression: 0.45, .speed: 0.7], [.poppunk, .poprock, .emo, .emopop],
             .palette(FXPalette(bg: RGB(hex: 0x111014), fg: RGB(hex: 0xFFFFFF), acc: RGB(hex: 0xFF3E8A), dim: RGB(hex: 0x54505C)))),
        make(.palette, "mono", [.aggression: 0.5, .speed: 0.7, .raw: 0.3, .bright: 0.5], [.melodichc, .skatepunk, .ska, .punk, .cybermetal, .rapmetal, .nu, .hardcore, .posthardcore, .emopop],
             .palette(FXPalette(bg: RGB(hex: 0x000000), fg: RGB(hex: 0xFFFFFF), acc: RGB(hex: 0xB6FF00), dim: RGB(hex: 0x222222)))),
        make(.palette, "polaroid", [.warm: 0.7, .elegance: 0.5, .theatrical: 0.55, .bright: 0.55], [.poprock, .indieemo, .emopop],
             .palette(FXPalette(bg: RGB(hex: 0x17131C), fg: RGB(hex: 0xF6E9D8), acc: RGB(hex: 0xF2A07B), dim: RGB(hex: 0x6B5F73)))),
        make(.palette, "skateTeal", [.speed: 0.85, .bright: 0.6, .bounce: 0.5, .aggression: 0.45], [.skatepunk, .emopop],
             .palette(FXPalette(bg: RGB(hex: 0x071A1C), fg: RGB(hex: 0xEAF7F2), acc: RGB(hex: 0xFF7A1A), dim: RGB(hex: 0x3F5F60)))),
        make(.palette, "sunsetInk", [.warm: 0.9, .bright: 0.7, .bounce: 0.5], [.poprock, .powerpop, .poppunk, .skatepunk, .rock, .emopop],
             .palette(FXPalette(bg: RGB(hex: 0xFFD9A8), fg: RGB(hex: 0x1D2A44), acc: RGB(hex: 0xFF5A36), dim: RGB(hex: 0x9AA0AA)))),
        make(.palette, "twoTone", [.bounce: 0.85, .bright: 0.6, .speed: 0.75], [.ska],
             .palette(FXPalette(bg: RGB(hex: 0x0B0B0B), fg: RGB(hex: 0xFFFFFF), acc: RGB(hex: 0xFFD400), dim: RGB(hex: 0x5A5A5A)))),
        make(.palette, "twoToneLight", [.bounce: 0.9, .bright: 0.8, .warm: 0.5], [.ska],
             .palette(FXPalette(bg: RGB(hex: 0xF4F1EA), fg: RGB(hex: 0x111111), acc: RGB(hex: 0xD81E1E), dim: RGB(hex: 0x9A968C)))),
        make(.palette, "weezBlue", [.bright: 0.7, .bounce: 0.5, .raw: 0.3, .cold: 0.25], [.powerpop],
             .palette(FXPalette(bg: RGB(hex: 0x0A5A8F), fg: RGB(hex: 0xFFFFFF), acc: RGB(hex: 0xFFE14D), dim: RGB(hex: 0x083F66)))),
        make(.palette, "yellowBlack", [.bright: 0.9, .bounce: 0.8, .aggression: 0.4, .warm: 0.5], [.ska, .poppunk, .skatepunk],
             .palette(FXPalette(bg: RGB(hex: 0xF5D90A), fg: RGB(hex: 0x111111), acc: RGB(hex: 0xFF2E2E), dim: RGB(hex: 0x6B5A00)))),
        // B2 批 3（Nu-metal；原型 composer.js 的 B2 批 3 段）。標籤只收本批專屬的（新團的私有子標籤＋連帶的 Korn／Hatebreed 的 nu、hardcore）
        make(.palette, "acid", [.aggression: 0.6, .bright: 0.5, .raw: 0.3], [.cybermetal, .rapmetal, .nu],
             .palette(FXPalette(bg: RGB(hex: 0x1A1B1D), fg: RGB(hex: 0xB6FF00), acc: RGB(hex: 0xFF6A00), dim: RGB(hex: 0x555555)))),
        make(.palette, "hybridGrey", [.cold: 0.55, .aggression: 0.6, .raw: 0.35, .bright: 0.3], [.cybermetal, .rapmetal],
             .palette(FXPalette(bg: RGB(hex: 0x121314), fg: RGB(hex: 0xEDEDED), acc: RGB(hex: 0xD0202A), dim: RGB(hex: 0x5A5C60)))),
        make(.palette, "rust", [.raw: 0.8, .decay: 0.75, .aggression: 0.8, .warm: 0.2], [.horrormetal, .altmetal],
             .palette(FXPalette(bg: RGB(hex: 0x0D0907), fg: RGB(hex: 0xE6DCCB), acc: RGB(hex: 0xB8461C), dim: RGB(hex: 0x5E4A3C)))),
        make(.palette, "sangre", [.warm: 0.8, .aggression: 0.65, .theatrical: 0.5, .raw: 0.45], [.latinmetal],
             .palette(FXPalette(bg: RGB(hex: 0x120806), fg: RGB(hex: 0xF3E3C3), acc: RGB(hex: 0xE0522B), dim: RGB(hex: 0x6A3B2A)))),
        make(.palette, "terminal", [.cold: 0.6, .bright: 0.5, .speed: 0.6], [.cybermetal],
             .palette(FXPalette(bg: RGB(hex: 0x04070A), fg: RGB(hex: 0x5CFFB0), acc: RGB(hex: 0x2EE6FF), dim: RGB(hex: 0x1E4C3A)))),
        // B2 批 4（emo 群；原型 composer.js 的 B2 批 4 段）。標籤只收本批私有的（emo／posthardcore／indieemo／emopop）
        make(.palette, "bruise", [.theatrical: 0.6, .cold: 0.5, .decay: 0.4, .elegance: 0.5], [.emo, .indieemo],
             .palette(FXPalette(bg: RGB(hex: 0x14121F), fg: RGB(hex: 0xE4E0EC), acc: RGB(hex: 0x9A7FD1), dim: RGB(hex: 0x5A5470)))),
        make(.palette, "overcast", [.cold: 0.55, .elegance: 0.6, .bright: 0.45, .warm: 0.3], [.indieemo],
             .palette(FXPalette(bg: RGB(hex: 0x18212B), fg: RGB(hex: 0xECE6D8), acc: RGB(hex: 0x8FB8D0), dim: RGB(hex: 0x5C6B7A)))),
        make(.palette, "parade", [.theatrical: 0.9, .cold: 0.5, .elegance: 0.55, .bright: 0.2], [.emo],
             req: [.theatrical: 0.7], .palette(FXPalette(bg: RGB(hex: 0x0A0A0B), fg: RGB(hex: 0xE6E6E6), acc: RGB(hex: 0xB9BDC4), dim: RGB(hex: 0x5F6166)))),
        make(.palette, "revenge", [.theatrical: 0.8, .aggression: 0.65, .decay: 0.5, .bright: 0.15], [.emo, .posthardcore],
             .palette(FXPalette(bg: RGB(hex: 0x0B0B0C), fg: RGB(hex: 0xF2F0EA), acc: RGB(hex: 0xC1121F), dim: RGB(hex: 0x6E6A66)))),
    ]
}
