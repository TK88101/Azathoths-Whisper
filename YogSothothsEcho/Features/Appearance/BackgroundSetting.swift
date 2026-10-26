import Observation
import SwiftUI

/// F-V-09（CR-022；s6-61-round2.md 附錄 E.2）：側封頁背景漸層 7 組（小樣保留 1、2、4、6、7、9、10），預設霧銀藍
enum BackgroundPreset: String, CaseIterable, Sendable {
    case moss, aurora, indigo, forest, roseGraphite, terracotta, silverBlue

    static let defaultValue = BackgroundPreset.silverBlue

    var title: LocalizedStringKey {
        switch self {
        case .moss: "Moss Vinyl"
        case .aurora: "Midnight Aurora"
        case .indigo: "Indigo Current"
        case .forest: "Forest Haze"
        case .roseGraphite: "Rose Graphite"
        case .terracotta: "Terracotta Night"
        case .silverBlue: "Silver Blue"
        }
    }
}

/// F-V-09：專輯詳情背景三種，預設唱機式模糊（使用者 2026-10-23）
enum DetailBackgroundMode: String, CaseIterable, Sendable {
    case gradient, albumColor, turntableBlur

    static let defaultValue = DetailBackgroundMode.turntableBlur

    var title: LocalizedStringKey {
        switch self {
        case .gradient: "Gradient"
        case .albumColor: "Album Color"
        case .turntableBlur: "Turntable Blur"
        }
    }
}

/// 同 `AppearanceViewModel`：記在設定裡，讀到未知值回預設（無既有資料需遷移）
@MainActor
@Observable
final class BackgroundViewModel {
    static let presetKey = "background.preset"
    static let detailModeKey = "background.detailMode"

    @ObservationIgnored private let store: SettingsStore

    var preset: BackgroundPreset {
        didSet { store.set(preset.rawValue, forKey: Self.presetKey) }
    }

    var detailMode: DetailBackgroundMode {
        didSet { store.set(detailMode.rawValue, forKey: Self.detailModeKey) }
    }

    init(store: SettingsStore) {
        self.store = store
        preset = store.string(forKey: Self.presetKey).flatMap(BackgroundPreset.init(rawValue:)) ?? .defaultValue
        detailMode = store.string(forKey: Self.detailModeKey).flatMap(DetailBackgroundMode.init(rawValue:)) ?? .defaultValue
    }
}
