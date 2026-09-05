import Foundation

// 應用語言：內部 enum ↔ legacy 字串 ↔ AppleLanguages（Plan §4.6）
enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case en
    case zhTW = "zh_TW"
    case ja

    /// 寫入 UserDefaults 的 AppleLanguages 陣列；system 表示刪鍵。
    var appleLanguagesValue: [String]? {
        switch self {
        case .system: return nil
        case .en: return ["en"]
        case .zhTW: return ["zh-Hant"]
        case .ja: return ["ja"]
        }
    }

    /// 從 legacy 字串（.env LANGUAGE / 舊 config）還原；無法辨識時回 system。
    static func fromLegacy(_ value: String) -> AppLanguage {
        switch value {
        case "en": return .en
        case "zh_TW", "zh-TW", "zh-Hant": return .zhTW
        case "ja": return .ja
        default: return .system
        }
    }
}

// 系統語言偵測（lyrics_fetcher.py:1621-1644 等價）。
// 原版跑兩次 `defaults read`：先 app 專屬域、再全局域；判定用 substring。
// Swift 側改讀 UserDefaults（同一份 plist 資料），判定規則 1:1。
enum SystemLanguageDetector {
    /// 對齊原版：app 域判定順序 zh → ja → en；app 域皆不匹配才落到全局域（全局域無 en 分支）。
    /// - Parameters:
    ///   - appDomain: app 專屬 AppleLanguages 的原始描述；未設為 nil
    ///   - globalDomain: 全局 AppleLanguages 的原始描述；未設為 nil
    /// - Returns: legacy 語言碼（"zh_TW" / "ja" / "en"）
    static func detect(appDomain: String?, globalDomain: String?) -> String {
        if let app = appDomain {
            if app.contains("zh-Hant") || app.contains("zh-TW") { return "zh_TW" }
            if app.contains("ja") { return "ja" }
            if app.contains("en") { return "en" }
        }
        if let global = globalDomain {
            if global.contains("zh-Hant") || global.contains("zh-TW") { return "zh_TW" }
            if global.contains("ja") { return "ja" }
        }
        return "en"
    }

    /// 便利版：從 UserDefaults 讀兩個域後判定。
    static func detect(
        appDefaults: UserDefaults = .standard,
        globalDefaults: UserDefaults = .standard
    ) -> String {
        let app = appDefaults.object(forKey: "AppleLanguages") as? [String]
        let global = globalDefaults.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        return detect(
            appDomain: app.map { $0.joined(separator: ",") },
            globalDomain: global.map { $0.joined(separator: ",") }
        )
    }
}
