import Foundation

/// 元件目錄（B1：黑金屬＋交響子集，B1 計劃 §3.8；B2 批 1：rock 系 9 團用到的 59 個，B2 計劃 §7.3）。向量、標籤、req／forbid **原樣抄自原型 `composer.js`**（行號見各列註解），不改值。
/// 移出 B1 的元件與理由見計劃 §3.8
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
             .font(FontFace(id: "Cenobyte", family: "Cenobyte", weight: nil, uppercase: true))),
        make(.font, "DarkMetal", [.raw: 0.7, .decay: 0.8, .theatrical: 0.25, .cold: 0.5, .aggression: 0.5], [.black],
             .font(FontFace(id: "DarkMetal", family: "Dark Metal", weight: nil, uppercase: true))),
        make(.font, "Mirage", [.cold: 0.6, .elegance: 0.65, .theatrical: 0.55, .aggression: 0.4], [.black, .gothic, .symphonic],
             .font(FontFace(id: "Mirage", family: "Mirage Gothic", weight: nil, uppercase: true))),
        make(.font, "Fraktur", [.theatrical: 0.6, .elegance: 0.7, .cold: 0.45, .raw: 0.3, .aggression: 0.3], [.black, .symphonic, .gothic],
             .font(FontFace(id: "Fraktur", family: "UnifrakturMaguntia", weight: nil))),
        make(.font, "Cinzel", [.elegance: 0.9, .theatrical: 0.8, .bright: 0.4, .aggression: 0.15], [.symphonic, .gothic, .power],
             forbid: [.aggression: 0.65], .font(FontFace(id: "Cinzel", family: "Cinzel", weight: .bold, uppercase: true))),
        make(.font, "CormorantIt", [.elegance: 0.85, .theatrical: 0.6, .cold: 0.3, .aggression: 0.05, .speed: 0.2], [.gothic, .doom],
             forbid: [.aggression: 0.65], .font(FontFace(id: "CormorantIt", family: "Cormorant Garamond", weight: .semibold, italic: true))),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.font, "Abril", [.theatrical: 0.9, .elegance: 0.7, .bright: 0.7, .warm: 0.5], [.glam, .classicrock],
             forbid: [.raw: 0.5], .font(FontFace(id: "Abril", family: "Abril Fatface", weight: nil))),
        make(.font, "AlfaSlab", [.aggression: 0.6, .warm: 0.6, .raw: 0.5, .bounce: 0.4], [.hardrock, .classicrock],
             .font(FontFace(id: "AlfaSlab", family: "Alfa Slab One", weight: nil, uppercase: true))),
        make(.font, "Anton", [.aggression: 0.7, .speed: 0.6, .raw: 0.3, .bounce: 0.3], [.hardrock, .hardcore, .nu, .death, .thrash, .punk, .skatepunk, .bigbeat, .rock],
             .font(FontFace(id: "Anton", family: "Anton", weight: nil, uppercase: true))),
        make(.font, "Archivo", [.raw: 0.45, .aggression: 0.4, .bright: 0.5, .warm: 0.5], [.britpop, .indie],
             .font(FontFace(id: "Archivo", family: "Archivo Black", weight: nil))),
        make(.font, "Bebas", [.aggression: 0.45, .speed: 0.5, .bright: 0.5, .raw: 0.3, .theatrical: 0.4], [.hardrock, .britpop, .arena],
             .font(FontFace(id: "Bebas", family: "Bebas Neue", weight: nil, uppercase: true))),
        make(.font, "Bungee", [.bounce: 0.7, .bright: 0.75, .warm: 0.5, .speed: 0.55], [.britpop, .pop],
             forbid: [.aggression: 0.5], .font(FontFace(id: "Bungee", family: "Bungee", weight: nil, uppercase: true))),
        make(.font, "Elite", [.raw: 0.7, .decay: 0.5, .bounce: 0.2, .warm: 0.3], [.punk, .punk77, .indie],
             .font(FontFace(id: "Elite", family: "Special Elite", weight: nil, uppercase: true))),
        make(.font, "Grotesk", [.cold: 0.4, .elegance: 0.5, .bright: 0.3, .speed: 0.3, .bounce: 0], [.idm, .ambient, .house, .indie],
             .font(FontFace(id: "Grotesk", family: "Space Grotesk", weight: .regular))),
        make(.font, "Oswald", [.aggression: 0.5, .speed: 0.6, .raw: 0.35, .bounce: 0.3], [.hardrock, .britpop, .arena, .punk, .poppunk, .skatepunk, .hardcore, .rock, .bigbeat],
             .font(FontFace(id: "Oswald", family: "Oswald", weight: .bold, uppercase: true))),
        make(.font, "PlayfairIt", [.elegance: 0.8, .theatrical: 0.6, .warm: 0.5, .speed: 0.3], [.glam, .classicrock, .psych, .arena],
             forbid: [.aggression: 0.5], .font(FontFace(id: "PlayfairIt", family: "Playfair Display", weight: .bold, italic: true))),
        make(.font, "Righteous", [.bright: 0.75, .theatrical: 0.65, .bounce: 0.5, .elegance: 0.45], [.glam],
             .font(FontFace(id: "Righteous", family: "Righteous", weight: nil, uppercase: true))),
        make(.font, "Syncopate", [.cold: 0.6, .elegance: 0.7, .speed: 0.1, .theatrical: 0.6], [.psych, .arena],
             forbid: [.aggression: 0.5], .font(FontFace(id: "Syncopate", family: "Syncopate", weight: .bold, uppercase: true))),
    ]

    // composer.js:36-40,43
    static let backdrops: [FXComponent] = [
        make(.backdrop, "void", [.raw: 0.5, .cold: 0.6, .theatrical: 0.1], [], .backdrop(.void)),
        make(.backdrop, "film", [.raw: 0.95, .decay: 0.7, .theatrical: 0.1], [.black, .death, .hardcore, .thrash], .backdrop(.film)),
        make(.backdrop, "snow", [.cold: 0.95, .theatrical: 0.3, .elegance: 0.3], [.black, .gothic, .doom], .backdrop(.snow)),
        make(.backdrop, "shafts", [.theatrical: 0.95, .elegance: 0.85, .bright: 0.4], [.symphonic, .gothic, .power],
             req: [.theatrical: 0.45], forbid: [.aggression: 0.65], .backdrop(.shafts)),
        make(.backdrop, "ash", [.theatrical: 0.5, .elegance: 0.5, .decay: 0.55, .cold: 0.3], [.gothic, .doom, .black], .backdrop(.ash)),
        make(.backdrop, "crimsonFog", [.theatrical: 0.85, .aggression: 0.7, .decay: 0.6, .elegance: 0.4, .bright: 0.05], [.black, .gothic],
             req: [.theatrical: 0.6], .backdrop(.crimsonFog)),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.backdrop, "ampGlow", [.warm: 0.7, .aggression: 0.55, .bright: 0.4, .theatrical: 0.45], [.hardrock, .arena, .classicrock],
             .backdrop(.ampGlow)),
        make(.backdrop, "embers", [.theatrical: 0.5, .aggression: 0.45, .bright: 0.5], [.hardrock, .power, .heavy, .thrash],
             .backdrop(.embers)),
        make(.backdrop, "halftone", [.bright: 0.8, .bounce: 0.6, .warm: 0.6], [.britpop, .pop, .classicrock],
             forbid: [.aggression: 0.5, .elegance: 0.7], .backdrop(.halftone)),
        make(.backdrop, "haze", [.elegance: 0.6, .cold: 0.3, .bright: 0.3, .speed: 0.1], [.psych, .ambient, .idm, .indie, .house],
             .backdrop(.haze)),
        make(.backdrop, "paper", [.raw: 0.6, .decay: 0.5, .warm: 0.5, .bounce: 0.3], [.punk, .punk77, .indie],
             .backdrop(.paper)),
        make(.backdrop, "prism", [.cold: 0.6, .theatrical: 0.75, .elegance: 0.7, .speed: 0.1], [.psych],
             forbid: [.aggression: 0.5], .backdrop(.prism)),
        make(.backdrop, "smokeHaze", [.raw: 0.6, .decay: 0.45, .warm: 0.5, .theatrical: 0.5], [.hardrock],
             .backdrop(.smokeHaze)),
        make(.backdrop, "spot", [.theatrical: 0.8, .bright: 0.4, .elegance: 0.5], [.glam, .arena, .classicrock, .hardrock],
             .backdrop(.spot)),
        make(.backdrop, "stars", [.elegance: 0.75, .bright: 0.5, .cold: 0.35, .speed: 0.2, .theatrical: 0.5], [.arena, .psych],
             forbid: [.aggression: 0.5], .backdrop(.stars)),
        make(.backdrop, "sunset", [.warm: 0.9, .bright: 0.7, .bounce: 0.4, .elegance: 0.3], [.poppunk, .skatepunk, .pop, .indie, .rock],
             .backdrop(.sunset)),
        make(.backdrop, "tapeLeak", [.warm: 0.75, .raw: 0.45, .bright: 0.5, .decay: 0.3], [.britpop, .classicrock, .hardrock, .indie],
             .backdrop(.tapeLeak)),
    ]

    // composer.js:55,57-61,64。淡入型（condense、smoke、rise）的時長依 P12 縮短 40%（使用者 2026-10-06：「漸入漸出稍長，字發虛」）
    static let enters: [FXComponent] = [
        make(.enter, "slam", [.aggression: 0.9, .speed: 0.9, .raw: 0.7, .elegance: 0], [.black, .death, .hardcore, .thrash, .grind],
             forbid: [.elegance: 0.8], .enter(EnterSpec(weights: [(.slam, 1)], duration: 0.14...0.26, wordLevel: true, pile: true, expires: true))),
        make(.enter, "condense", [.cold: 0.85, .speed: 0.1, .elegance: 0.4], [.black, .gothic, .doom],
             .enter(EnterSpec(weights: [(.condense, 4), (.fadeUp, 1)], duration: 0.54...1.02))),
        make(.enter, "negative", [.raw: 0.8, .aggression: 0.6, .speed: 0.6], [.black],
             .enter(EnterSpec(weights: [(.negative, 3), (.fadeUp, 1)], duration: 0.2...0.35))),
        make(.enter, "smoke", [.theatrical: 0.6, .elegance: 0.55, .speed: 0.2, .cold: 0.3], [.gothic, .doom, .symphonic],
             .enter(EnterSpec(weights: [(.smoke, 4), (.fadeUp, 1)], duration: 0.36...0.78))),
        make(.enter, "rise", [.theatrical: 0.85, .elegance: 0.85, .speed: 0.2, .bright: 0.4], [.symphonic, .power, .gothic],
             forbid: [.raw: 0.8, .aggression: 0.65], .enter(EnterSpec(weights: [(.rise, 4), (.grow, 1)], duration: 0.36...0.72))),
        make(.enter, "swoop", [.theatrical: 0.55, .speed: 0.6, .elegance: 0.3], [.glam, .arena, .symphonic, .power, .gothic, .heavy],
             .enter(EnterSpec(weights: [(.swoop, 3), (.orbit, 1), (.fling, 1)], duration: 0.3...0.6))),
        make(.enter, "lash", [.aggression: 0.85, .theatrical: 0.8, .speed: 0.85, .elegance: 0.4], [.black, .gothic, .symphonic],
             req: [.theatrical: 0.6], .enter(EnterSpec(weights: [(.fling, 3), (.slant, 2), (.swoop, 1)], duration: 0.12...0.25))),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.enter, "bloom", [.elegance: 0.75, .speed: 0.15, .theatrical: 0.6], [.psych, .arena, .classicrock],
             forbid: [.aggression: 0.5], .enter(EnterSpec(weights: [(.grow, 3), (.fadeUp, 2)], duration: 0.6...1.2))),
        make(.enter, "fadeUp", [.elegance: 0.5, .bounce: 0.1, .speed: 0.3], [.britpop, .arena, .psych, .classicrock, .indie, .ambient, .rock, .punk, .idm],
             .enter(EnterSpec(weights: [(.fadeUp, 4), (.grow, 1)], duration: 0.3...0.6))),
        make(.enter, "hop", [.bounce: 0.65, .bright: 0.7, .warm: 0.6, .speed: 0.5], [.britpop, .classicrock, .pop],
             forbid: [.aggression: 0.5, .theatrical: 0.8], .enter(EnterSpec(weights: [(.pop, 3), (.fallIn, 2), (.fadeUp, 1)], duration: 0.18...0.4))),
        make(.enter, "kick", [.aggression: 0.6, .bounce: 0.5, .speed: 0.65, .warm: 0.4], [.hardrock],
             .enter(EnterSpec(weights: [(.stamp, 3), (.pop, 2), (.slide, 1)], duration: 0.12...0.28))),
        make(.enter, "slide", [.aggression: 0.6, .speed: 0.7, .bounce: 0.2], [.hardrock, .heavy, .thrash, .nu, .hardcore, .punk, .skatepunk, .rock, .bigbeat],
             .enter(EnterSpec(weights: [(.slide, 4), (.stamp, 1)], duration: 0.15...0.35))),
        make(.enter, "stamp", [.aggression: 0.7, .speed: 0.8, .raw: 0.3], [.hardrock, .hardcore, .nu, .heavy, .thrash],
             .enter(EnterSpec(weights: [(.stamp, 4), (.pop, 1)], duration: 0.1...0.25))),
        make(.enter, "strut", [.theatrical: 0.8, .bright: 0.6, .speed: 0.5, .elegance: 0.5], [.glam, .arena],
             .enter(EnterSpec(weights: [(.slant, 3), (.swoop, 2), (.stamp, 1)], duration: 0.2...0.4))),
        make(.enter, "swagger", [.raw: 0.5, .aggression: 0.4, .speed: 0.45, .warm: 0.5], [.britpop, .hardrock, .indie],
             .enter(EnterSpec(weights: [(.slide, 3), (.fadeUp, 2)], duration: 0.3...0.55))),
    ]

    // composer.js:73-75,77
    static let exits: [FXComponent] = [
        make(.exit, "cut", [.aggression: 0.9, .raw: 0.8, .speed: 0.9], [.black, .death, .hardcore, .grind],
             .exit(ExitSpec(weights: [(.cut, 1)], duration: 0))),
        make(.exit, "scatter", [.cold: 0.6, .raw: 0.5], [.black], .exit(ExitSpec(weights: [(.scatter, 1)], duration: 0.7))),
        make(.exit, "dissolve", [.cold: 0.75, .elegance: 0.45, .speed: 0.1], [.black, .gothic, .doom],
             .exit(ExitSpec(weights: [(.dissolve, 1)], duration: 1.6, trail: true))),
        make(.exit, "fade", [.elegance: 0.7, .theatrical: 0.5, .speed: 0.1], [.symphonic, .gothic, .doom],
             .exit(ExitSpec(weights: [(.fade, 1)], duration: 1.2, trail: true))),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.exit, "dropOut", [.aggression: 0.55, .speed: 0.6, .bounce: 0.4], [.hardrock, .glam, .britpop],
             .exit(ExitSpec(weights: [(.fall, 2), (.shrink, 2)], duration: 0.45))),
        make(.exit, "fadeShort", [.elegance: 0.55, .speed: 0.35, .bright: 0.5], [.arena, .britpop, .classicrock, .glam, .indie],
             .exit(ExitSpec(weights: [(.fade, 1)], duration: 0.6))),
        make(.exit, "fall", [.aggression: 0.6, .speed: 0.6], [.hardrock, .glam, .heavy, .thrash, .death, .power],
             .exit(ExitSpec(weights: [(.fall, 3), (.shrink, 1)], duration: 0.5))),
        make(.exit, "floatAway", [.elegance: 0.7, .speed: 0.1, .cold: 0.4], [.psych, .arena],
             forbid: [.aggression: 0.5], .exit(ExitSpec(weights: [(.up, 2), (.scatter, 1)], duration: 1))),
        make(.exit, "slideOut", [.speed: 0.7, .aggression: 0.4], [.hardrock, .britpop, .rock, .punk, .techno, .electro, .house],
             .exit(ExitSpec(weights: [(.slideOut, 1)], duration: 0.4))),
        make(.exit, "up", [.elegance: 0.4, .bounce: 0.2, .speed: 0.4], [.britpop, .arena, .classicrock, .pop, .indie, .rock, .house, .idm, .poppunk],
             .exit(ExitSpec(weights: [(.up, 1)], duration: 0.5))),
    ]

    // composer.js:87,88,92,101
    static let effects: [FXComponent] = [
        make(.fx, "shake", [.aggression: 0.9, .speed: 0.7], [.black, .death, .hardcore, .thrash, .nu], .fx(.shake)),
        make(.fx, "misreg", [.raw: 0.9, .decay: 0.5], [.black, .hardcore], .fx(.misreg)),
        make(.fx, "breathe", [.elegance: 0.6, .theatrical: 0.5, .speed: 0.2], [.psych, .arena, .symphonic, .gothic, .doom, .power],
             forbid: [.aggression: 0.65], .fx(.breathe)),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.fx, "bob", [.bounce: 0.6, .warm: 0.6, .bright: 0.6], [.britpop, .classicrock, .pop],
             forbid: [.aggression: 0.5, .theatrical: 0.8], .fx(.bob)),
        make(.fx, "flicker", [.warm: 0.6, .decay: 0.4, .raw: 0.5, .theatrical: 0.5], [.hardrock, .psych],
             .fx(.flicker)),
        make(.fx, "glow", [.theatrical: 0.75, .elegance: 0.75, .bright: 0.5], [.glam, .arena, .symphonic, .power, .gothic],
             forbid: [.raw: 0.75, .aggression: 0.65], .fx(.glow)),
        make(.fx, "neonstroke", [.bright: 0.8, .theatrical: 0.5, .bounce: 0.4, .warm: 0.3], [.arena, .house, .frenchhouse, .electro, .pop],
             .fx(.neonstroke)),
        make(.fx, "reflect", [.elegance: 0.6, .theatrical: 0.5], [.psych, .glam, .gothic, .doom, .symphonic],
             .fx(.reflect)),
        make(.fx, "thump", [.aggression: 0.6, .speed: 0.6, .bounce: 0.6], [.hardrock, .arena, .bigbeat, .techno, .hardcore, .house],
             .fx(.thump)),
        make(.fx, "wobble", [.raw: 0.5, .aggression: 0.5, .bounce: 0.4], [.hardrock, .britpop],
             .fx(.wobble)),
        make(.fx, "none", [:], [], .fx(.none)),
    ]

    // composer.js:104-107,110,113
    static let palettes: [FXComponent] = [
        make(.palette, "boneBlood", [.aggression: 0.7, .raw: 0.6, .decay: 0.5], [.black, .death, .melodeath],
             .palette(FXPalette(bg: RGB(hex: 0x050506), fg: RGB(hex: 0xE8ECEF), acc: RGB(hex: 0x7A0B14), dim: RGB(hex: 0x9AA3AB)))),
        make(.palette, "ice", [.cold: 0.95, .elegance: 0.4], [.black, .doom],
             .palette(FXPalette(bg: RGB(hex: 0x05070A), fg: RGB(hex: 0xD8DEE4), acc: RGB(hex: 0xD8DEE4), dim: RGB(hex: 0x7C8793)))),
        make(.palette, "goldNavy", [.theatrical: 0.9, .elegance: 0.85, .bright: 0.5], [.symphonic, .power],
             forbid: [.raw: 0.75, .aggression: 0.65],
             .palette(FXPalette(bg: RGB(hex: 0x0E1733), fg: RGB(hex: 0xC9A227), acc: RGB(hex: 0xF0D47A), dim: RGB(hex: 0x6B5A45)))),
        make(.palette, "crimsonVelvet", [.theatrical: 0.7, .elegance: 0.65, .decay: 0.5], [.gothic, .doom, .symphonic],
             .palette(FXPalette(bg: RGB(hex: 0x140A1A), fg: RGB(hex: 0x8A1C2B), acc: RGB(hex: 0xC9A0A8), dim: RGB(hex: 0x6B5C73)))),
        make(.palette, "bloodBlack", [.theatrical: 0.85, .aggression: 0.8, .decay: 0.6, .bright: 0.05, .elegance: 0.4], [.black, .gothic],
             .palette(FXPalette(bg: RGB(hex: 0x030203), fg: RGB(hex: 0xEDE6DA), acc: RGB(hex: 0xB3001B), dim: RGB(hex: 0x4A2A2E)))),
        make(.palette, "ashGrey", [.raw: 0.8, .decay: 0.7, .cold: 0.4], [.black, .hardcore, .death],
             .palette(FXPalette(bg: RGB(hex: 0x060606), fg: RGB(hex: 0xC8C8C8), acc: RGB(hex: 0x8F0F1A), dim: RGB(hex: 0x666666)))),
        // B2 批 1（使用者 2026-10-07 簽字；由原型 composer.js 產生，不手抄）
        make(.palette, "ampRed", [.aggression: 0.65, .warm: 0.6, .bright: 0.5, .raw: 0.5], [.hardrock],
             .palette(FXPalette(bg: RGB(hex: 0x0B0909), fg: RGB(hex: 0xF4EFE6), acc: RGB(hex: 0xD81E1E), dim: RGB(hex: 0x5A4A46)))),
        make(.palette, "britRed", [.bright: 0.75, .bounce: 0.65, .speed: 0.55], [.britpop, .indie],
             .palette(FXPalette(bg: RGB(hex: 0xF3F0E8), fg: RGB(hex: 0x17203A), acc: RGB(hex: 0xD5202B), dim: RGB(hex: 0x9AA0AE)))),
        make(.palette, "cream60", [.warm: 0.85, .bright: 0.7, .elegance: 0.5, .bounce: 0.4], [.classicrock, .britpop],
             forbid: [.aggression: 0.5], .palette(FXPalette(bg: RGB(hex: 0xF1E6CF), fg: RGB(hex: 0x3B2A1E), acc: RGB(hex: 0xD9622B), dim: RGB(hex: 0xA8977A)))),
        make(.palette, "dusk", [.elegance: 0.7, .theatrical: 0.6, .cold: 0.4, .warm: 0.3, .speed: 0.15], [.psych, .arena],
             .palette(FXPalette(bg: RGB(hex: 0x141026), fg: RGB(hex: 0xD9CFF2), acc: RGB(hex: 0xF2A65A), dim: RGB(hex: 0x5A4F7A)))),
        make(.palette, "hazard", [.aggression: 0.6, .bounce: 0.5, .bright: 0.55, .speed: 0.6], [.hardrock, .arena],
             .palette(FXPalette(bg: RGB(hex: 0x0A0A0B), fg: RGB(hex: 0xEDEDED), acc: RGB(hex: 0xFFC400), dim: RGB(hex: 0x55555A)))),
        make(.palette, "mancSky", [.raw: 0.45, .bright: 0.6, .cold: 0.3, .warm: 0.4], [.britpop],
             .palette(FXPalette(bg: RGB(hex: 0xDCE6EE), fg: RGB(hex: 0x14233A), acc: RGB(hex: 0x2C6FB7), dim: RGB(hex: 0x8FA3B5)))),
        make(.palette, "newsprint", [.raw: 0.5, .decay: 0.4, .warm: 0.4, .bounce: 0.3], [.punk77, .punk, .indie],
             .palette(FXPalette(bg: RGB(hex: 0xE9E2CF), fg: RGB(hex: 0x1A1A1A), acc: RGB(hex: 0xC8102E), dim: RGB(hex: 0x9A9A9A)))),
        make(.palette, "parka", [.raw: 0.55, .warm: 0.55, .aggression: 0.4, .decay: 0.3], [.britpop, .indie],
             .palette(FXPalette(bg: RGB(hex: 0x1C2418), fg: RGB(hex: 0xE8E2CF), acc: RGB(hex: 0xD9A441), dim: RGB(hex: 0x5F6B52)))),
        make(.palette, "popArt", [.bright: 0.9, .bounce: 0.65, .warm: 0.7], [.britpop, .pop],
             forbid: [.aggression: 0.5], .palette(FXPalette(bg: RGB(hex: 0xF4D21F), fg: RGB(hex: 0x16161D), acc: RGB(hex: 0xE4322B), dim: RGB(hex: 0x8A7A1A)))),
        make(.palette, "prismBlack", [.cold: 0.65, .elegance: 0.75, .theatrical: 0.7, .bright: 0.25], [.psych],
             .palette(FXPalette(bg: RGB(hex: 0x050507), fg: RGB(hex: 0xF2F2F4), acc: RGB(hex: 0x7FD4FF), dim: RGB(hex: 0x4A4A58)))),
        make(.palette, "royal", [.theatrical: 0.95, .elegance: 0.75, .bright: 0.7, .warm: 0.5], [.glam],
             .palette(FXPalette(bg: RGB(hex: 0x1B0A24), fg: RGB(hex: 0xF2D9A0), acc: RGB(hex: 0xFF4F8B), dim: RGB(hex: 0x6E4F7A)))),
        make(.palette, "starlight", [.elegance: 0.75, .bright: 0.75, .warm: 0.6, .speed: 0.3], [.arena],
             forbid: [.aggression: 0.5], .palette(FXPalette(bg: RGB(hex: 0x0A1230), fg: RGB(hex: 0xF6E7A8), acc: RGB(hex: 0xFFFFFF), dim: RGB(hex: 0x44507A)))),
        make(.palette, "tuxedo", [.theatrical: 0.8, .elegance: 0.7, .bright: 0.6], [.glam, .arena, .classicrock],
             .palette(FXPalette(bg: RGB(hex: 0x0D0D12), fg: RGB(hex: 0xFFFFFF), acc: RGB(hex: 0xE8B84A), dim: RGB(hex: 0x5B5B66)))),
        make(.palette, "vegas", [.bright: 0.75, .theatrical: 0.7, .bounce: 0.5, .warm: 0.5], [.arena],
             .palette(FXPalette(bg: RGB(hex: 0x0B0A1E), fg: RGB(hex: 0xFFF4E0), acc: RGB(hex: 0xFF4D6D), dim: RGB(hex: 0x3B3A6B)))),
        make(.palette, "whiskey", [.warm: 0.8, .raw: 0.6, .decay: 0.45, .theatrical: 0.5], [.hardrock, .classicrock],
             .palette(FXPalette(bg: RGB(hex: 0x120C07), fg: RGB(hex: 0xE9C27A), acc: RGB(hex: 0xF4EBDD), dim: RGB(hex: 0x6A5236)))),
    ]
}
