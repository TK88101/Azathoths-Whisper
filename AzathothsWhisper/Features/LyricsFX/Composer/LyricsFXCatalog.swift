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
        // ⑥a J-Pop（docs/plans/2026-10-23-lyrics-fx-jpop.md §4.3）：每個元件只帶一個變體的私有標籤；日文行一律冬青黑體，這裡只管拉丁字
        make(.font, "jpKiraLilita", [.bounce: 0.8, .bright: 0.85, .warm: 0.65], [.jpopKira],
             .font(FontFace(id: "Lilita", family: "Lilita One", weight: nil))),
        make(.font, "jpCityArchivo", [.elegance: 0.6, .bright: 0.7, .cold: 0.35], [.jpopCity],
             .font(FontFace(id: "Archivo", family: "Archivo Black", weight: nil))),
        make(.font, "jpBalladCormorant", [.elegance: 0.85, .speed: 0.15, .warm: 0.6], [.jpopBallad],
             .font(FontFace(id: "CormorantIt", family: "Cormorant Garamond", weight: .semibold, italic: true))),
        // ⑦ 通用・工業（docs/plans/2026-10-25-lyrics-fx-generic-parts.md §4.4）：只帶 genIndustrial；payload 全部沿用既有種類
        make(.font, "genIndBlackOps", [.aggression: 0.75, .cold: 0.6, .raw: 0.5], [.genIndustrial],
             .font(FontFace(id: "BlackOps", family: "Black Ops One", weight: nil, uppercase: true))),
        make(.font, "genIndSpaceMono", [.cold: 0.85, .speed: 0.6, .bounce: 0.2], [.genIndustrial],
             .font(FontFace(id: "SpaceMono", family: "Space Mono", weight: .bold, uppercase: true))),
        // ⑦ 通用・實驗：只帶 genExperimental
        make(.font, "genExpElite", [.raw: 0.65, .decay: 0.6], [.genExperimental], .font(FontFace(id: "Elite", family: "Special Elite", weight: nil, uppercase: true))),
        make(.font, "genExpCourierPrime", [.cold: 0.55, .elegance: 0.45], [.genExperimental], .font(FontFace(id: "CourierPrime", family: "Courier Prime", weight: .bold))),
        // ⑦ 通用・電子：只帶 genElectronic
        make(.font, "genEleGrotesk", [.cold: 0.55, .elegance: 0.5, .speed: 0.55], [.genElectronic], .font(FontFace(id: "Grotesk", family: "Space Grotesk", weight: .regular))),
        make(.font, "genEleSyncopate", [.cold: 0.6, .theatrical: 0.55, .bright: 0.6], [.genElectronic], .font(FontFace(id: "Syncopate", family: "Syncopate", weight: .bold, uppercase: true))),
        // ⑦ 通用・流行：只帶 genPop
        make(.font, "genPopRubik", [.bright: 0.8, .bounce: 0.6, .warm: 0.6], [.genPop], .font(FontFace(id: "Rubik", family: "Rubik", weight: .bold))),
        make(.font, "genPopLilita", [.bounce: 0.75, .bright: 0.85, .warm: 0.65], [.genPop], .font(FontFace(id: "Lilita", family: "Lilita One", weight: nil))),
        make(.font, "genPopArchivo", [.bright: 0.7, .elegance: 0.4], [.genPop], .font(FontFace(id: "Archivo", family: "Archivo Black", weight: nil))),
        // ⑦ 通用・民謠：只帶 genFolk
        make(.font, "genFolkPlayfairIt", [.elegance: 0.6, .warm: 0.7], [.genFolk], .font(FontFace(id: "PlayfairIt", family: "Playfair Display", weight: .bold, italic: true))),
        make(.font, "genFolkGochi", [.warm: 0.8, .raw: 0.35], [.genFolk], .font(FontFace(id: "Gochi", family: "Gochi Hand", weight: nil))),
        make(.font, "genFolkShadowsLight", [.warm: 0.7, .elegance: 0.5], [.genFolk], .font(FontFace(id: "ShadowsLight", family: "Shadows Into Light", weight: nil))),
        // ⑦ 通用・氛圍：只帶 genAmbient
        make(.font, "genAmbCormorantIt", [.elegance: 0.85, .speed: 0.1], [.genAmbient], .font(FontFace(id: "CormorantIt", family: "Cormorant Garamond", weight: .semibold, italic: true))),
        make(.font, "genAmbGrotesk", [.cold: 0.6, .elegance: 0.7], [.genAmbient], .font(FontFace(id: "Grotesk", family: "Space Grotesk", weight: .regular))),
        // ⑦ 通用・古樂：只帶 genSacred
        make(.font, "genSacFraktur", [.theatrical: 0.75, .elegance: 0.85], [.genSacred], .font(FontFace(id: "Fraktur", family: "UnifrakturMaguntia", weight: nil))),
        make(.font, "genSacCinzel", [.elegance: 0.9, .theatrical: 0.7], [.genSacred], .font(FontFace(id: "Cinzel", family: "Cinzel", weight: .bold, uppercase: true))),
        // ⑦ 通用・暗潮：只帶 genDarkwave
        make(.font, "genDwMirage", [.cold: 0.7, .theatrical: 0.6, .elegance: 0.6], [.genDarkwave], .font(FontFace(id: "Mirage", family: "Mirage Gothic", weight: nil, uppercase: true))),
        make(.font, "genDwSyncopate", [.cold: 0.75, .elegance: 0.6], [.genDarkwave], .font(FontFace(id: "Syncopate", family: "Syncopate", weight: .bold, uppercase: true))),
        // ⑦ 通用・嘻哈：只帶 genHipHop
        make(.font, "genHipAnton", [.aggression: 0.55, .bounce: 0.6, .raw: 0.5], [.genHipHop], .font(FontFace(id: "Anton", family: "Anton", weight: nil, uppercase: true, sizeScale: 0.15 / 0.12, rasterizes: false))),
        make(.font, "genHipBebas", [.bounce: 0.7, .bright: 0.5], [.genHipHop], .font(FontFace(id: "Bebas", family: "Bebas Neue", weight: nil, uppercase: true))),
        make(.font, "genHipMarker", [.raw: 0.55, .warm: 0.55, .bounce: 0.75], [.genHipHop], .font(FontFace(id: "Marker", family: "Permanent Marker", weight: nil, uppercase: true))),
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
        // ⑥a J-Pop
        make(.backdrop, "jpKiraSparkle", [.bright: 0.9, .bounce: 0.8], [.jpopKira], .backdrop(.sparkle)),
        make(.backdrop, "jpCityNeon", [.bright: 0.7, .elegance: 0.6, .theatrical: 0.55], [.jpopCity], .backdrop(.cityNeon)),
        make(.backdrop, "jpBalladPaper", [.elegance: 0.8, .warm: 0.6, .speed: 0.15], [.jpopBallad], .backdrop(.paper)),
        // ⑦ 通用・工業（docs/plans/2026-10-25-lyrics-fx-generic-parts.md §4.4）：只帶 genIndustrial；payload 全部沿用既有種類
        make(.backdrop, "genIndGrid", [.cold: 0.8, .aggression: 0.5], [.genIndustrial], .backdrop(.grid)),
        make(.backdrop, "genIndScan", [.aggression: 0.65, .raw: 0.5, .bright: 0.15], [.genIndustrial], .backdrop(.scan)),
        make(.backdrop, "genIndFilm", [.raw: 0.7, .decay: 0.6], [.genIndustrial], .backdrop(.film)),
        // ⑦ 通用・實驗：只帶 genExperimental
        make(.backdrop, "genExpXerox", [.raw: 0.7, .decay: 0.5], [.genExperimental], .backdrop(.xerox)),
        make(.backdrop, "genExpFilm", [.raw: 0.75, .decay: 0.65], [.genExperimental], .backdrop(.film)),
        make(.backdrop, "genExpHaze", [.cold: 0.5, .elegance: 0.45], [.genExperimental], .backdrop(.haze)),
        // ⑦ 通用・電子：只帶 genElectronic
        make(.backdrop, "genEleGrid", [.cold: 0.6, .speed: 0.65], [.genElectronic], .backdrop(.grid)),
        make(.backdrop, "genEleHaze", [.elegance: 0.5, .bright: 0.55], [.genElectronic], .backdrop(.haze)),
        make(.backdrop, "genElePrism", [.theatrical: 0.6, .bright: 0.65], [.genElectronic], .backdrop(.prism)),
        // ⑦ 通用・流行：只帶 genPop
        make(.backdrop, "genPopSkyGrad", [.bright: 0.8, .bounce: 0.55], [.genPop], .backdrop(.skyGrad)),
        make(.backdrop, "genPopFlat", [.bright: 0.85, .bounce: 0.7], [.genPop], .backdrop(.flat)),
        make(.backdrop, "genPopBokeh", [.elegance: 0.5, .warm: 0.65], [.genPop], .backdrop(.bokeh)),
        // ⑦ 通用・民謠：只帶 genFolk
        make(.backdrop, "genFolkPaper", [.warm: 0.75, .raw: 0.4], [.genFolk], .backdrop(.paper)),
        make(.backdrop, "genFolkTapeLeak", [.warm: 0.8, .bright: 0.5], [.genFolk], .backdrop(.tapeLeak)),
        make(.backdrop, "genFolkHaze", [.elegance: 0.55, .cold: 0.3], [.genFolk], .backdrop(.haze)),
        // ⑦ 通用・氛圍：只帶 genAmbient
        make(.backdrop, "genAmbHaze", [.elegance: 0.8, .cold: 0.55], [.genAmbient], .backdrop(.haze)),
        make(.backdrop, "genAmbStars", [.elegance: 0.75, .bright: 0.45], [.genAmbient], .backdrop(.stars)),
        make(.backdrop, "genAmbBluehour", [.cold: 0.65, .elegance: 0.7], [.genAmbient], .backdrop(.bluehour)),
        // ⑦ 通用・古樂：只帶 genSacred
        make(.backdrop, "genSacShafts", [.theatrical: 0.8, .elegance: 0.85], [.genSacred], .backdrop(.shafts)),
        make(.backdrop, "genSacPaper", [.elegance: 0.8, .warm: 0.5], [.genSacred], .backdrop(.paper)),
        make(.backdrop, "genSacAsh", [.theatrical: 0.6, .decay: 0.4], [.genSacred], .backdrop(.ash)),
        // ⑦ 通用・暗潮：只帶 genDarkwave
        make(.backdrop, "genDwSnow", [.cold: 0.8, .elegance: 0.5], [.genDarkwave], .backdrop(.snow)),
        make(.backdrop, "genDwAsh", [.decay: 0.55, .theatrical: 0.6], [.genDarkwave], .backdrop(.ash)),
        make(.backdrop, "genDwGrid", [.cold: 0.75, .speed: 0.45], [.genDarkwave], .backdrop(.grid)),
        // ⑦ 通用・嘻哈：只帶 genHipHop
        make(.backdrop, "genHipSpot", [.theatrical: 0.5, .bright: 0.5], [.genHipHop], .backdrop(.spot)),
        make(.backdrop, "genHipSmokeHaze", [.raw: 0.5, .warm: 0.55], [.genHipHop], .backdrop(.smokeHaze)),
        make(.backdrop, "genHipFlat", [.bounce: 0.8, .bright: 0.5], [.genHipHop], .backdrop(.flat)),
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
        // 拿掉 fling（2026-10-20 讀得到的檢查 G3：fling 衝過頭再彈回，慢步調下壓到已到位的鄰字；原型 composer.js:101 是 swoop 3／orbit 1／fling 1）
        make(.enter, "swoop", [.theatrical: 0.55, .speed: 0.6, .elegance: 0.3], [.glam, .arena, .symphonic, .power, .gothic, .heavy, .gothmetal, .emo],
             .enter(EnterSpec(weights: [(.swoop, 3), (.orbit, 1)], duration: 0.3...0.6))),
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
        // ⑥a J-Pop：原型 jpop 三變體的 enter。ballad 是淡入型，時長依 P12 縮 40%（原型 0.8–1.4）
        make(.enter, "jpKiraPop", [.bounce: 0.85, .speed: 0.65], [.jpopKira],
             .enter(EnterSpec(weights: [(.pop, 2), (.fadeUp, 2), (.grow, 1)], duration: 0.25...0.5))),
        // 原型是 slide 3；slide 從遠處滑入會橫越已到位的鄰字，使用者 2026-10-23 看並排比較選短距離的 sidle（不列 G3 豁免）
        make(.enter, "jpCitySlide", [.speed: 0.5, .elegance: 0.6], [.jpopCity],
             .enter(EnterSpec(weights: [(.sidle, 3), (.fadeUp, 2)], duration: 0.3...0.6))),
        make(.enter, "jpBalladFade", [.elegance: 0.85, .speed: 0.15], [.jpopBallad],
             .enter(EnterSpec(weights: [(.fadeUp, 3), (.smoke, 1)], duration: 0.48...0.84))),
        // ⑦ 通用・工業（docs/plans/2026-10-25-lyrics-fx-generic-parts.md §4.4）：只帶 genIndustrial；payload 全部沿用既有種類
        make(.enter, "genIndStamp", [.aggression: 0.8, .speed: 0.65], [.genIndustrial],
             .enter(EnterSpec(weights: [(.stamp, 4), (.type, 1)], duration: 0.1...0.25))),
        make(.enter, "genIndType", [.cold: 0.7, .speed: 0.75, .raw: 0.5], [.genIndustrial],
             .enter(EnterSpec(weights: [(.type, 5), (.flip, 1)], duration: 0.06...0.15))),
        // ⑦ 通用・實驗：只帶 genExperimental
        make(.enter, "genExpType", [.raw: 0.6, .speed: 0.55], [.genExperimental], .enter(EnterSpec(weights: [(.type, 3), (.slant, 2), (.fadeUp, 1)], duration: 0.1...0.24))),
        make(.enter, "genExpNegative", [.raw: 0.7, .theatrical: 0.55], [.genExperimental], .enter(EnterSpec(weights: [(.negative, 3), (.fadeUp, 1)], duration: 0.2...0.35))),
        // ⑦ 通用・電子：只帶 genElectronic
        make(.enter, "genEleFlip", [.speed: 0.8, .cold: 0.55], [.genElectronic], .enter(EnterSpec(weights: [(.flip, 4), (.type, 1)], duration: 0.08...0.2))),
        make(.enter, "genEleSidle", [.elegance: 0.5, .bounce: 0.55], [.genElectronic], .enter(EnterSpec(weights: [(.sidle, 3), (.fadeUp, 2)], duration: 0.3...0.6))),
        // ⑦ 通用・流行：只帶 genPop
        make(.enter, "genPopHop", [.bounce: 0.75, .bright: 0.8], [.genPop], .enter(EnterSpec(weights: [(.pop, 3), (.fallIn, 2), (.fadeUp, 1)], duration: 0.18...0.4))),
        make(.enter, "genPopEase", [.elegance: 0.45, .warm: 0.6], [.genPop], .enter(EnterSpec(weights: [(.fadeUp, 3), (.pop, 1)], duration: 0.25...0.5))),
        // ⑦ 通用・民謠：只帶 genFolk
        make(.enter, "genFolkFadeUp", [.elegance: 0.55, .speed: 0.35], [.genFolk], .enter(EnterSpec(weights: [(.fadeUp, 4), (.grow, 1)], duration: 0.3...0.6))),
        make(.enter, "genFolkBloom", [.elegance: 0.6, .warm: 0.7], [.genFolk], .enter(EnterSpec(weights: [(.grow, 3), (.fadeUp, 2)], duration: 0.6...1.2))),
        // ⑦ 通用・氛圍：只帶 genAmbient
        make(.enter, "genAmbBloom", [.elegance: 0.8, .speed: 0.1], [.genAmbient], .enter(EnterSpec(weights: [(.grow, 3), (.fadeUp, 2)], duration: 0.6...1.2))),
        make(.enter, "genAmbRise", [.elegance: 0.8, .theatrical: 0.45], [.genAmbient], .enter(EnterSpec(weights: [(.rise, 4), (.grow, 1)], duration: 0.36...0.72))),
        // ⑦ 通用・古樂：只帶 genSacred
        make(.enter, "genSacRise", [.theatrical: 0.75, .elegance: 0.9], [.genSacred], .enter(EnterSpec(weights: [(.rise, 4), (.grow, 1)], duration: 0.36...0.72))),
        make(.enter, "genSacSmoke", [.theatrical: 0.7, .elegance: 0.8], [.genSacred], .enter(EnterSpec(weights: [(.smoke, 4), (.fadeUp, 1)], duration: 0.36...0.78))),
        // ⑦ 通用・暗潮：只帶 genDarkwave
        make(.enter, "genDwSmoke", [.theatrical: 0.65, .cold: 0.7], [.genDarkwave], .enter(EnterSpec(weights: [(.smoke, 4), (.fadeUp, 1)], duration: 0.36...0.78))),
        make(.enter, "genDwSwoop", [.theatrical: 0.6, .speed: 0.5], [.genDarkwave], .enter(EnterSpec(weights: [(.swoop, 3), (.orbit, 1)], duration: 0.3...0.6))),
        // ⑦ 通用・嘻哈：只帶 genHipHop
        make(.enter, "genHipKick", [.bounce: 0.8, .aggression: 0.55], [.genHipHop], .enter(EnterSpec(weights: [(.stamp, 3), (.pop, 2), (.slide, 1)], duration: 0.12...0.28))),
        make(.enter, "genHipDrop", [.aggression: 0.55, .speed: 0.6], [.genHipHop], .enter(EnterSpec(weights: [(.drop, 4), (.stamp, 1)], duration: 0.18...0.4))),
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
        // ⑥a J-Pop
        make(.exit, "jpKiraUp", [.bounce: 0.6, .speed: 0.6], [.jpopKira], .exit(ExitSpec(weights: [(.up, 1)], duration: 0.5))),
        make(.exit, "jpCitySlideOut", [.speed: 0.5, .elegance: 0.6], [.jpopCity], .exit(ExitSpec(weights: [(.slideOut, 1)], duration: 0.6))),
        make(.exit, "jpBalladFadeOut", [.elegance: 0.85, .speed: 0.1], [.jpopBallad],
             .exit(ExitSpec(weights: [(.fade, 1)], duration: 1.4, trail: true))),
        // ⑦ 通用・工業（docs/plans/2026-10-25-lyrics-fx-generic-parts.md §4.4）：只帶 genIndustrial；payload 全部沿用既有種類
        make(.exit, "genIndCut", [.aggression: 0.8, .raw: 0.6], [.genIndustrial], .exit(ExitSpec(weights: [(.cut, 1)], duration: 0))),
        make(.exit, "genIndBands", [.cold: 0.7, .speed: 0.7], [.genIndustrial], .exit(ExitSpec(weights: [(.bands, 3), (.slideOut, 1)], duration: 0.3))),
        // ⑦ 通用・實驗：只帶 genExperimental
        make(.exit, "genExpScatter", [.cold: 0.6, .raw: 0.5], [.genExperimental], .exit(ExitSpec(weights: [(.scatter, 1)], duration: 0.7))),
        make(.exit, "genExpDissolve", [.decay: 0.6, .elegance: 0.4], [.genExperimental], .exit(ExitSpec(weights: [(.dissolve, 1)], duration: 1.6, trail: true))),
        // ⑦ 通用・電子：只帶 genElectronic
        make(.exit, "genEleSlideOut", [.speed: 0.7, .bounce: 0.5], [.genElectronic], .exit(ExitSpec(weights: [(.slideOut, 1)], duration: 0.4))),
        make(.exit, "genEleUp", [.elegance: 0.45, .bright: 0.65], [.genElectronic], .exit(ExitSpec(weights: [(.up, 1)], duration: 0.5))),
        // ⑦ 通用・流行：只帶 genPop
        make(.exit, "genPopSnapOut", [.bounce: 0.7, .speed: 0.55], [.genPop], .exit(ExitSpec(weights: [(.shrink, 3), (.up, 1)], duration: 0.3))),
        make(.exit, "genPopDrift", [.elegance: 0.45, .warm: 0.6], [.genPop], .exit(ExitSpec(weights: [(.up, 2), (.fade, 1)], duration: 0.7))),
        // ⑦ 通用・民謠：只帶 genFolk
        make(.exit, "genFolkDrift", [.warm: 0.75, .elegance: 0.5], [.genFolk], .exit(ExitSpec(weights: [(.up, 2), (.fade, 1)], duration: 0.7))),
        make(.exit, "genFolkFadeShort", [.elegance: 0.55, .speed: 0.35], [.genFolk], .exit(ExitSpec(weights: [(.fade, 1)], duration: 0.6))),
        // ⑦ 通用・氛圍：只帶 genAmbient
        make(.exit, "genAmbFade", [.elegance: 0.8, .speed: 0.1], [.genAmbient], .exit(ExitSpec(weights: [(.fade, 1)], duration: 1.2, trail: true))),
        make(.exit, "genAmbFloatAway", [.elegance: 0.75, .cold: 0.55], [.genAmbient], .exit(ExitSpec(weights: [(.up, 2), (.scatter, 1)], duration: 1))),
        // ⑦ 通用・古樂：只帶 genSacred
        make(.exit, "genSacFade", [.elegance: 0.85, .speed: 0.15], [.genSacred], .exit(ExitSpec(weights: [(.fade, 1)], duration: 1.2, trail: true))),
        make(.exit, "genSacDissolve", [.decay: 0.4, .elegance: 0.8], [.genSacred], .exit(ExitSpec(weights: [(.dissolve, 1)], duration: 1.6, trail: true))),
        // ⑦ 通用・暗潮：只帶 genDarkwave
        make(.exit, "genDwDissolve", [.cold: 0.75, .decay: 0.55], [.genDarkwave], .exit(ExitSpec(weights: [(.dissolve, 1)], duration: 1.6, trail: true))),
        make(.exit, "genDwFade", [.elegance: 0.6, .theatrical: 0.6], [.genDarkwave], .exit(ExitSpec(weights: [(.fade, 1)], duration: 1.2, trail: true))),
        // ⑦ 通用・嘻哈：只帶 genHipHop
        make(.exit, "genHipDropOut", [.bounce: 0.75, .speed: 0.6], [.genHipHop], .exit(ExitSpec(weights: [(.fall, 2), (.shrink, 2)], duration: 0.45))),
        make(.exit, "genHipSlideOut", [.speed: 0.6, .aggression: 0.5], [.genHipHop], .exit(ExitSpec(weights: [(.slideOut, 1)], duration: 0.4))),
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
        // ⑥a J-Pop：kira 的停留是彈跳與呼吸；city 的字帶光暈（代原型粉紅 shadowBlur）；ballad 只有共用的 none
        make(.fx, "jpKiraBob", [.bounce: 0.85, .bright: 0.85], [.jpopKira], .fx(.bob)),
        make(.fx, "jpKiraBreathe", [.bounce: 0.7, .elegance: 0.45], [.jpopKira], .fx(.breathe)),
        make(.fx, "jpCityGlow", [.elegance: 0.65, .bright: 0.7, .theatrical: 0.55], [.jpopCity], .fx(.glow)),
        // ⑦ 通用・工業（docs/plans/2026-10-25-lyrics-fx-generic-parts.md §4.4）：只帶 genIndustrial；payload 全部沿用既有種類
        make(.fx, "genIndShake", [.aggression: 0.85], [.genIndustrial], .fx(.shake)),
        make(.fx, "genIndRgbsplit", [.cold: 0.7, .speed: 0.65], [.genIndustrial], .fx(.rgbsplit)),
        // ⑦ 通用・實驗：只帶 genExperimental
        make(.fx, "genExpMisreg", [.raw: 0.75, .decay: 0.55], [.genExperimental], .fx(.misreg)),
        make(.fx, "genExpJitter", [.raw: 0.6, .speed: 0.5], [.genExperimental], .fx(.jitter)),
        make(.fx, "genExpFlicker", [.decay: 0.6, .theatrical: 0.55], [.genExperimental], .fx(.flicker)),
        // ⑦ 通用・電子：只帶 genElectronic
        make(.fx, "genEleNeonstroke", [.bright: 0.75, .theatrical: 0.5], [.genElectronic], .fx(.neonstroke)),
        make(.fx, "genEleRgbsplit", [.speed: 0.7, .cold: 0.6], [.genElectronic], .fx(.rgbsplit)),
        make(.fx, "genEleThump", [.bounce: 0.65, .speed: 0.65], [.genElectronic], .fx(.thump)),
        // ⑦ 通用・流行：只帶 genPop
        make(.fx, "genPopBob", [.bounce: 0.7, .warm: 0.65], [.genPop], .fx(.bob)),
        make(.fx, "genPopTilt", [.bounce: 0.65, .bright: 0.8], [.genPop], .fx(.tilt)),
        // ⑦ 通用・民謠：只帶 genFolk
        make(.fx, "genFolkBreathe", [.elegance: 0.55, .speed: 0.3], [.genFolk], .fx(.breathe)),
        make(.fx, "genFolkFlicker", [.warm: 0.8, .decay: 0.35], [.genFolk], .fx(.flicker)),
        // ⑦ 通用・氛圍：只帶 genAmbient
        make(.fx, "genAmbBreathe", [.elegance: 0.8, .speed: 0.1], [.genAmbient], .fx(.breathe)),
        make(.fx, "genAmbReflect", [.elegance: 0.75, .cold: 0.55], [.genAmbient], .fx(.reflect)),
        // ⑦ 通用・古樂：只帶 genSacred
        make(.fx, "genSacGlow", [.theatrical: 0.75, .elegance: 0.85], [.genSacred], .fx(.glow)),
        make(.fx, "genSacReflect", [.elegance: 0.85, .theatrical: 0.6], [.genSacred], .fx(.reflect)),
        // ⑦ 通用・暗潮：只帶 genDarkwave
        make(.fx, "genDwReflect", [.elegance: 0.6, .cold: 0.7], [.genDarkwave], .fx(.reflect)),
        make(.fx, "genDwBreathe", [.theatrical: 0.6, .speed: 0.4], [.genDarkwave], .fx(.breathe)),
        // ⑦ 通用・嘻哈：只帶 genHipHop
        make(.fx, "genHipThump", [.bounce: 0.8, .speed: 0.6], [.genHipHop], .fx(.thump)),
        make(.fx, "genHipWobble", [.bounce: 0.7, .raw: 0.5], [.genHipHop], .fx(.wobble)),
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
        // ⑥a J-Pop：原型三變體的 bg／fg／a1；dim 取原型 a2（ballad 同）
        make(.palette, "jpKira", [.bright: 0.9, .warm: 0.7], [.jpopKira],
             .palette(FXPalette(bg: RGB(hex: 0xEAF6FF), fg: RGB(hex: 0x2E3A59), acc: RGB(hex: 0xFF7AB6), dim: RGB(hex: 0x6EC6FF)))),
        make(.palette, "jpCity", [.bright: 0.7, .elegance: 0.65], [.jpopCity],
             .palette(FXPalette(bg: RGB(hex: 0x1B1040), fg: RGB(hex: 0xFFF3E0), acc: RGB(hex: 0xFF6AA0), dim: RGB(hex: 0x4FD3FF)))),
        make(.palette, "jpBallad", [.elegance: 0.85, .warm: 0.6], [.jpopBallad],
             .palette(FXPalette(bg: RGB(hex: 0xF7F4EE), fg: RGB(hex: 0x3B3A44), acc: RGB(hex: 0xC96A7A), dim: RGB(hex: 0x8FA6C9)))),
        // ⑦ 通用・工業（docs/plans/2026-10-25-lyrics-fx-generic-parts.md §4.4）：只帶 genIndustrial；payload 全部沿用既有種類
        make(.palette, "genIndRust", [.raw: 0.6, .decay: 0.5, .warm: 0.2], [.genIndustrial],
             .palette(FXPalette(bg: RGB(hex: 0x0B0C0D), fg: RGB(hex: 0xE6E6E3), acc: RGB(hex: 0xC2410C), dim: RGB(hex: 0x4B4F54)))),
        make(.palette, "genIndHazard", [.aggression: 0.75, .bright: 0.3], [.genIndustrial],
             .palette(FXPalette(bg: RGB(hex: 0x0D0D0D), fg: RGB(hex: 0xF2F2F2), acc: RGB(hex: 0xF5C400), dim: RGB(hex: 0x555555)))),
        make(.palette, "genIndSteel", [.cold: 0.9, .elegance: 0.2], [.genIndustrial],
             .palette(FXPalette(bg: RGB(hex: 0x101418), fg: RGB(hex: 0xDCE3EA), acc: RGB(hex: 0x7FA7C9), dim: RGB(hex: 0x3E4A56)))),
        // ⑦ 通用・實驗：只帶 genExperimental
        make(.palette, "genExpBone", [.raw: 0.6, .decay: 0.55], [.genExperimental],
             .palette(FXPalette(bg: RGB(hex: 0x0A0A0A), fg: RGB(hex: 0xEDEAE4), acc: RGB(hex: 0xD7263D), dim: RGB(hex: 0x5C5A57)))),
        make(.palette, "genExpPhotocopy", [.raw: 0.55, .bright: 0.5], [.genExperimental],
             .palette(FXPalette(bg: RGB(hex: 0xEDEBE6), fg: RGB(hex: 0x141414), acc: RGB(hex: 0x1F4FFF), dim: RGB(hex: 0x8E8C88)))),
        make(.palette, "genExpStatic", [.cold: 0.6, .theatrical: 0.55], [.genExperimental],
             .palette(FXPalette(bg: RGB(hex: 0x0D1012), fg: RGB(hex: 0xE4E8EA), acc: RGB(hex: 0x8FD14F), dim: RGB(hex: 0x4A5257)))),
        // ⑦ 通用・電子：只帶 genElectronic
        make(.palette, "genEleNeon", [.cold: 0.65, .bright: 0.7], [.genElectronic],
             .palette(FXPalette(bg: RGB(hex: 0x07081A), fg: RGB(hex: 0xF2F4FF), acc: RGB(hex: 0x00E5FF), dim: RGB(hex: 0x3A3F6B)))),
        make(.palette, "genEleAcid", [.speed: 0.7, .bounce: 0.6], [.genElectronic],
             .palette(FXPalette(bg: RGB(hex: 0x0A0F0A), fg: RGB(hex: 0xE8FFE8), acc: RGB(hex: 0xB6FF00), dim: RGB(hex: 0x3F5A3F)))),
        make(.palette, "genEleMagenta", [.theatrical: 0.55, .warm: 0.35], [.genElectronic],
             .palette(FXPalette(bg: RGB(hex: 0x120818), fg: RGB(hex: 0xFBEFFF), acc: RGB(hex: 0xFF3EC8), dim: RGB(hex: 0x5A3B66)))),
        // ⑦ 通用・流行：只帶 genPop
        make(.palette, "genPopCandy", [.bright: 0.85, .warm: 0.6], [.genPop],
             .palette(FXPalette(bg: RGB(hex: 0xFFF0F5), fg: RGB(hex: 0x2A1B3D), acc: RGB(hex: 0xFF4F9A), dim: RGB(hex: 0xB49AB0)))),
        make(.palette, "genPopLemon", [.bright: 0.85, .bounce: 0.7], [.genPop],
             .palette(FXPalette(bg: RGB(hex: 0xFFF7D6), fg: RGB(hex: 0x1E2240), acc: RGB(hex: 0xFF6A3D), dim: RGB(hex: 0xB3AC8C)))),
        make(.palette, "genPopNight", [.elegance: 0.5, .theatrical: 0.5], [.genPop],
             .palette(FXPalette(bg: RGB(hex: 0x14102A), fg: RGB(hex: 0xFFF3FA), acc: RGB(hex: 0xFF7AC6), dim: RGB(hex: 0x4E4670)))),
        make(.palette, "genPopTeal", [.bounce: 0.6, .warm: 0.55], [.genPop],
             .palette(FXPalette(bg: RGB(hex: 0x0B1F24), fg: RGB(hex: 0xF0FFFC), acc: RGB(hex: 0xFFD24D), dim: RGB(hex: 0x3C5A5E)))),
        // ⑦ 通用・民謠：只帶 genFolk
        make(.palette, "genFolkLinen", [.warm: 0.75, .bright: 0.55], [.genFolk],
             .palette(FXPalette(bg: RGB(hex: 0xF1E9DA), fg: RGB(hex: 0x2E2418), acc: RGB(hex: 0x9C4A1A), dim: RGB(hex: 0xA89A82)))),
        make(.palette, "genFolkForest", [.warm: 0.6, .cold: 0.3], [.genFolk],
             .palette(FXPalette(bg: RGB(hex: 0x15201A), fg: RGB(hex: 0xEDE6D3), acc: RGB(hex: 0xC9A54A), dim: RGB(hex: 0x55624F)))),
        make(.palette, "genFolkHearth", [.warm: 0.85, .raw: 0.35], [.genFolk],
             .palette(FXPalette(bg: RGB(hex: 0x1E140D), fg: RGB(hex: 0xF3E6CF), acc: RGB(hex: 0xE07A3A), dim: RGB(hex: 0x6B5240)))),
        // ⑦ 通用・氛圍：只帶 genAmbient
        make(.palette, "genAmbMist", [.cold: 0.6, .elegance: 0.8], [.genAmbient],
             .palette(FXPalette(bg: RGB(hex: 0x0E1418), fg: RGB(hex: 0xE3ECF0), acc: RGB(hex: 0x9CC7D9), dim: RGB(hex: 0x48575F)))),
        make(.palette, "genAmbDusk", [.elegance: 0.8, .warm: 0.35], [.genAmbient],
             .palette(FXPalette(bg: RGB(hex: 0x14121F), fg: RGB(hex: 0xECE6F5), acc: RGB(hex: 0xB9A3E3), dim: RGB(hex: 0x575070)))),
        make(.palette, "genAmbDeep", [.cold: 0.65, .speed: 0.1], [.genAmbient],
             .palette(FXPalette(bg: RGB(hex: 0x081014), fg: RGB(hex: 0xDDE8EA), acc: RGB(hex: 0x6FB3B8), dim: RGB(hex: 0x35484C)))),
        // ⑦ 通用・古樂：只帶 genSacred
        make(.palette, "genSacGold", [.theatrical: 0.75, .warm: 0.5], [.genSacred],
             .palette(FXPalette(bg: RGB(hex: 0x0F0B06), fg: RGB(hex: 0xF0DFB0), acc: RGB(hex: 0xD4A93A), dim: RGB(hex: 0x5E4E2C)))),
        make(.palette, "genSacVellum", [.elegance: 0.85, .bright: 0.45], [.genSacred],
             .palette(FXPalette(bg: RGB(hex: 0xEFE6D2), fg: RGB(hex: 0x2B1D12), acc: RGB(hex: 0x8E1B1B), dim: RGB(hex: 0xA2957C)))),
        make(.palette, "genSacNight", [.elegance: 0.9, .cold: 0.45], [.genSacred],
             .palette(FXPalette(bg: RGB(hex: 0x0B0E1A), fg: RGB(hex: 0xE8E2CC), acc: RGB(hex: 0xC9A86A), dim: RGB(hex: 0x41465E)))),
        // ⑦ 通用・暗潮：只帶 genDarkwave
        make(.palette, "genDwViolet", [.theatrical: 0.65, .cold: 0.7], [.genDarkwave],
             .palette(FXPalette(bg: RGB(hex: 0x0D0A14), fg: RGB(hex: 0xE7E1F2), acc: RGB(hex: 0x9B6BFF), dim: RGB(hex: 0x463C5C)))),
        make(.palette, "genDwCold", [.cold: 0.8, .elegance: 0.55], [.genDarkwave],
             .palette(FXPalette(bg: RGB(hex: 0x080B10), fg: RGB(hex: 0xDDE4EE), acc: RGB(hex: 0x5FA8D3), dim: RGB(hex: 0x36404D)))),
        make(.palette, "genDwRose", [.decay: 0.55, .theatrical: 0.65], [.genDarkwave],
             .palette(FXPalette(bg: RGB(hex: 0x120A10), fg: RGB(hex: 0xF0E2EA), acc: RGB(hex: 0xD6457A), dim: RGB(hex: 0x56404D)))),
        // ⑦ 通用・嘻哈：只帶 genHipHop
        make(.palette, "genHipGold", [.bounce: 0.75, .bright: 0.5], [.genHipHop],
             .palette(FXPalette(bg: RGB(hex: 0x0B0B0B), fg: RGB(hex: 0xF5F5F5), acc: RGB(hex: 0xF2C230), dim: RGB(hex: 0x555555)))),
        make(.palette, "genHipRed", [.aggression: 0.55, .warm: 0.55], [.genHipHop],
             .palette(FXPalette(bg: RGB(hex: 0x120909), fg: RGB(hex: 0xF7EDE6), acc: RGB(hex: 0xE53935), dim: RGB(hex: 0x5E4642)))),
        make(.palette, "genHipPurple", [.theatrical: 0.5, .bounce: 0.7], [.genHipHop],
             .palette(FXPalette(bg: RGB(hex: 0x100A1A), fg: RGB(hex: 0xF4EEFF), acc: RGB(hex: 0xA66BFF), dim: RGB(hex: 0x4F456B)))),
    ]
}
