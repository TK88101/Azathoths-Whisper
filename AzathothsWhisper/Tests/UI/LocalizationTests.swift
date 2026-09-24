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
            // Cover Flow × 找歌詞（計劃 §9.5）
            "mark_no_lyrics", "lyrics_status_present", "lyrics_status_missing", "lyrics_status_marked",
            "lyrics_status_unknown", "edit_lyrics_hint", "upnext_unavailable", "coverflow_show",
            "coverflow_hide", "edit_lyrics_of %@",
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

    // 計劃 §9.5：Cover Flow × 找歌詞新鍵的三語譯文（表格即規格）
    @Test("新鍵三語", arguments: [
        ("mark_no_lyrics", "No lyrics for this song", "這首沒有歌詞", "この曲は歌詞なし"),
        ("lyrics_status_present", "Lyrics in file", "已有歌詞", "歌詞あり"),
        ("lyrics_status_missing", "Missing lyrics", "缺少歌詞", "歌詞なし"),
        ("lyrics_status_marked", "Marked: no lyrics", "已標記：沒有歌詞", "歌詞なしとして記録済み"),
        ("lyrics_status_unknown", "Lyrics unreadable", "讀不到歌詞", "歌詞を読み取れません"),
        ("edit_lyrics_hint", "Edit lyrics", "編輯歌詞", "歌詞を編集"),
        ("upnext_unavailable", "Up next isn't available right now", "接下來的歌暫時讀不到", "次の曲を読み取れません"),
        ("coverflow_show", "Show Cover Flow", "顯示封面瀏覽", "カバーフローを表示"),
        ("coverflow_hide", "Hide Cover Flow", "隱藏封面瀏覽", "カバーフローを隠す"),
        ("edit_lyrics_of %@", "Edit lyrics of %@", "編輯「%@」的歌詞", "「%@」の歌詞を編集"),
    ])
    func lyricsFlowKeysAreTranslated(key: String, en: String, zhHant: String, ja: String) throws {
        #expect(try value(key, "en") == en)
        #expect(try value(key, "zh-Hant") == zhHant)
        #expect(try value(key, "ja") == ja)
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
