import Foundation
import Testing

@testable import YogSothothsEcho

// CR-034 增補 A T1（yse-1.0.1-skin-picker.md §4.1）：皮膚的 id、名稱、顯示順序只在註冊表定義一次
@MainActor
struct TurntableSkinEntryTests {
    @Test func registryStartsWithClassicAndHasUniqueIDs() {
        let ids = TurntableSkinEntry.all.map(\.id)
        #expect(ids.first == TurntableSkin.classic.id)
        #expect(Set(ids).count == ids.count)
    }

    /// 名稱由使用者 2026-10-26 定（Default／Pioneer／Rega）、2026-10-28 加 Technics；排序＝註冊表順序
    @Test func titlesAndOrderComeFromTheRegistry() {
        #expect(TurntableSkinEntry.all.map(\.title.key) == ["Default", "Pioneer", "Rega", "Technics"])
        #expect(TurntableSkinEntry.all.map(\.id) == ["classic", "s-arm-1200", "rega-rb330", "technics-sl1200g"])
    }

    @Test func resolvedSkinTitleIsLookedUpByID() {
        #expect(ResolvedTurntableSkin.classic.title?.key == "Default")
        let classic = TurntableSkin.classic
        let stranger = TurntableSkin(id: "stranger", kinematics: classic.kinematics, arm: classic.arm, base: classic.base,
                                     hitShape: classic.hitShape, rendering: classic.rendering)
        let resolved = try? TurntableSkinResolver.resolve(stranger).get()
        #expect(resolved != nil && resolved?.title == nil, "不在註冊表＝沒有名稱（畫面以 id 原文顯示，不冒用別款）")
    }
}
