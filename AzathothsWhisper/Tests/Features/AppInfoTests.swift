import Foundation
import Testing

@testable import AzathothsWhisper

// 關於畫面的版本行（2026-09-24 使用者拍板）：ad-hoc 簽名每次打包都不同，同一個 2.0.0 要能分辨是哪一次建置
@Suite("AppInfo")
struct AppInfoTests {
    @Test func aboutLineShowsTheBuildNumber() {
        #expect(AppInfo.aboutVersionLine(version: "2.0.0", build: "2000001") == "Version 2.0.0 (Build 2000001)")
    }

    @Test("沒有建置號或與版本號相同時只顯示版本", arguments: ["", "2.0.0"])
    func aboutLineOmitsAMeaninglessBuild(build: String) {
        #expect(AppInfo.aboutVersionLine(version: "2.0.0", build: build) == "Version 2.0.0")
    }

    /// 單一來源：project.yml 的 CURRENT_PROJECT_VERSION 進到 Info.plist 的 CFBundleVersion
    @Test func buildNumberIsAPlainIncreasingInteger() {
        #expect(Int(AppInfo.build) != nil, "CFBundleVersion 應是只增不減的整數，實際 \(AppInfo.build)")
    }

    /// ⑥b：CC BY-NC-SA 3.0 要求註明來源與授權連結
    @Test func theGenreDataCreditLinksToMusicBrainzAndTheLicense() {
        #expect(AppInfo.musicBrainzURL.absoluteString == "https://musicbrainz.org")
        #expect(AppInfo.genreDataLicenseURL.absoluteString == "https://creativecommons.org/licenses/by-nc-sa/3.0/")
        #expect(AppInfo.genreDataLicense == "CC BY-NC-SA 3.0")
    }

    @Test(arguments: ["en", "ja", "zh-Hant"])
    func theGenreDataCreditIsTranslated(language: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let text = try #require(Bundle(path: path)).localizedString(forKey: "about_genre_credit", value: nil, table: nil)
        #expect(text != "about_genre_credit" && text.contains("MusicBrainz") && text.contains("CC BY-NC-SA 3.0"))
    }
}
