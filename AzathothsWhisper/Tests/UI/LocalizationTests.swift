import Foundation
import Testing

@testable import AzathothsWhisper

// ACCEPTANCE E-01…E-04 / E-10：三語 catalog 的實際編譯產物逐鍵核對
@Suite("Localization")
struct LocalizationTests {
    private func bundle(for language: String) throws -> Bundle {
        let path = try #require(
            Bundle.main.path(forResource: language, ofType: "lproj"),
            "app bundle 應含 \(language).lproj"
        )
        return try #require(Bundle(path: path))
    }

    private func value(_ key: String, _ language: String) throws -> String {
        let sentinel = "<<missing>>"
        let result = try bundle(for: language).localizedString(forKey: key, value: sentinel, table: nil)
        #expect(result != sentinel, "\(language) 缺鍵 \(key)")
        return result
    }

    // E-01：en 的三處數據錯已修（status_ready 原為日文；batch_* 三鍵原本缺失）
    @Test func englishDataDefectsAreFixed() throws {
        #expect(try value("status_ready", "en") == "Ready")
        #expect(try value("batch_fetch", "en") == "Fetch Missing")
        #expect(try value("batch_import", "en") == "Import Selected")
        #expect(try value("batch_all", "en") == "Import All")
    }

    // E-02 / E-03：TRANSLATIONS 逐鍵保真抽查
    @Test func traditionalChineseAndJapaneseMatchSource() throws {
        #expect(try value("status_ready", "zh-Hant") == "就緒")
        #expect(try value("status_ready", "ja") == "準備完了")
        #expect(try value("fetch_btn", "zh-Hant") == "獲取歌詞")
        #expect(try value("write_btn", "ja") == "iTunesに書き込み")
        #expect(try value("lines_label", "zh-Hant") == "行數:")
    }

    // E-04：Editor/Settings 實際使用的 i18n 位點在三語皆有值
    @Test func everyUIKeyResolvesInAllThreeLanguages() throws {
        let keys = [
            "nav_editor", "nav_batch", "nav_coverflow",
            "source", "fetch_btn", "write_btn",
            "status_label", "status_ready", "lines_label",
            "settings_title", "token_label", "lang_label", "save_btn",
            "col_artist", "col_title", "col_stat", "col_preview",
            "batch_fetch", "batch_import", "batch_all",
        ]
        for language in ["en", "zh-Hant", "ja"] {
            for key in keys {
                _ = try value(key, language)
            }
        }
    }

    // E-10：Cover Flow 新鍵
    @Test func coverFlowKeyIsTranslated() throws {
        #expect(try value("nav_coverflow", "en") == "Cover Flow")
        #expect(try value("nav_coverflow", "zh-Hant") == "封面瀏覽")
        #expect(try value("nav_coverflow", "ja") == "カバーフロー")
    }

    // E-05：運行時狀態文案是常量而非 catalog 鍵（避免日後誤本地化）
    @Test func runtimeStatusTextIsNotLocalized() throws {
        let sentinel = "<<missing>>"
        for language in ["en", "zh-Hant", "ja"] {
            let looked = try bundle(for: language)
                .localizedString(forKey: StatusText.lyricsFetched, value: sentinel, table: nil)
            #expect(looked == sentinel, "\(StatusText.lyricsFetched) 不應存在於 catalog")
        }
    }
}
