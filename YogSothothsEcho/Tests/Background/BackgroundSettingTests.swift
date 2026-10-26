import SwiftUI
import Testing
@testable import YogSothothsEcho

// F10 T2a（附錄 E.2）：背景 7 組＋詳情 3 種，預設霧銀藍／唱機式模糊；存讀；未知值回預設
struct BackgroundSettingTests {
    @Test func presetsInMenuOrderWithSilverBlueDefault() {
        #expect(BackgroundPreset.allCases == [.moss, .aurora, .indigo, .forest, .roseGraphite, .terracotta, .silverBlue])
        #expect(BackgroundPreset.defaultValue == .silverBlue)
    }

    @Test func detailModesWithTurntableBlurDefault() {
        #expect(DetailBackgroundMode.allCases == [.gradient, .albumColor, .turntableBlur])
        #expect(DetailBackgroundMode.defaultValue == .turntableBlur)
    }
}

@MainActor
struct BackgroundViewModelTests {
    @Test func defaultsWhenNothingStored() {
        let model = BackgroundViewModel(store: InMemorySettingsStore())
        #expect(model.preset == .silverBlue)
        #expect(model.detailMode == .turntableBlur)
    }

    @Test func choicesPersistUnderTheirKeysAndAreReadBack() {
        let store = InMemorySettingsStore()
        let model = BackgroundViewModel(store: store)
        model.preset = .forest
        model.detailMode = .albumColor
        #expect(store.string(forKey: "background.preset") == "forest")
        #expect(store.string(forKey: "background.detailMode") == "albumColor")
        let reopened = BackgroundViewModel(store: store)
        #expect(reopened.preset == .forest)
        #expect(reopened.detailMode == .albumColor)
    }

    @Test func unknownStoredValuesFallBackToDefaults() {
        let store = InMemorySettingsStore()
        store.set("sunsetAmber", forKey: BackgroundViewModel.presetKey)
        store.set("sepia", forKey: BackgroundViewModel.detailModeKey)
        let model = BackgroundViewModel(store: store)
        #expect(model.preset == .silverBlue)
        #expect(model.detailMode == .turntableBlur)
    }
}
