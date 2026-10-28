import Foundation

/// 皮膚註冊表（CR-034 增補 A §4.1）：id、名稱、顯示順序只在這裡定義一次；目錄、選擇器、設定頁都讀它。
/// classic 恆在第一（目錄的後備與預設）；名稱由使用者 2026-10-26 定，Technics（松下）2026-10-28 定
struct TurntableSkinEntry: Sendable {
    let title: LocalizedStringResource
    /// bundle 內的序列圖皮膚（啟動時 preflight）；nil＝程式常數的原版 MD Vinyl 皮膚（`TurntableSkin.classic`）
    let sprite: SpriteSkinDefinition?

    var id: String { sprite?.id ?? TurntableSkin.classic.id }

    static let all: [TurntableSkinEntry] = [
        TurntableSkinEntry(title: LocalizedStringResource("Default"), sprite: nil),
        TurntableSkinEntry(title: LocalizedStringResource("Pioneer"), sprite: .sArm1200),
        TurntableSkinEntry(title: LocalizedStringResource("Rega"), sprite: .regaRB330),
        TurntableSkinEntry(title: LocalizedStringResource("Technics"), sprite: .technicsSL1200G),
    ]

    static func entry(id: String) -> TurntableSkinEntry? {
        all.first { $0.id == id }
    }
}

extension ResolvedTurntableSkin {
    /// 註冊表上的名稱；不在表上＝nil（畫面以 id 原文顯示，不冒用別款的名稱）
    var title: LocalizedStringResource? { TurntableSkinEntry.entry(id: spec.id)?.title }
}
