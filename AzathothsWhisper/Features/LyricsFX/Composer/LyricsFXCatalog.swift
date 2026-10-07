import Foundation

/// 元件目錄（B1：黑金屬＋交響子集；B1 計劃 §3.8）。向量、標籤、req／forbid **原樣抄自原型 `composer.js`**（行號見各列註解），不改值。
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
        make(.enter, "swoop", [.theatrical: 0.55, .speed: 0.6, .elegance: 0.3], [.symphonic, .power, .gothic, .heavy],
             .enter(EnterSpec(weights: [(.swoop, 3), (.orbit, 1), (.fling, 1)], duration: 0.3...0.6))),
        make(.enter, "lash", [.aggression: 0.85, .theatrical: 0.8, .speed: 0.85, .elegance: 0.4], [.black, .gothic, .symphonic],
             req: [.theatrical: 0.6], .enter(EnterSpec(weights: [(.fling, 3), (.slant, 2), (.swoop, 1)], duration: 0.12...0.25))),
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
    ]

    // composer.js:87,88,92,101
    static let effects: [FXComponent] = [
        make(.fx, "shake", [.aggression: 0.9, .speed: 0.7], [.black, .death, .hardcore, .thrash, .nu], .fx(.shake)),
        make(.fx, "misreg", [.raw: 0.9, .decay: 0.5], [.black, .hardcore], .fx(.misreg)),
        make(.fx, "breathe", [.elegance: 0.6, .theatrical: 0.5, .speed: 0.2], [.symphonic, .gothic, .doom, .power],
             forbid: [.aggression: 0.65], .fx(.breathe)),
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
    ]
}
