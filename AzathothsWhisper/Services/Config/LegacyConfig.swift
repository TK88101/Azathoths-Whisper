import Foundation

// 舊版（Python v1.2.x）配置的讀取語義，供一次性遷移使用。
// 對齊 lyrics_fetcher.py:1565-1609 load_config：優先級 env > JSON 檔 > 預設；
// 檔案非 JSON 時整檔內容視為裸 token（language 回落 system，除非 env 指定）。
struct LegacyConfig: Equatable, Sendable {
    let token: String
    let language: String

    static let defaults = LegacyConfig(token: "", language: "system")
}

enum LegacyConfigReader {
    /// - Parameters:
    ///   - fileContents: `~/.azathoths_whisper_config` 的內容；檔案不存在時傳 nil
    ///   - envToken: 已載入的 GENIUS_ACCESS_TOKEN（未設為 nil）
    ///   - envLanguage: 已載入的 LANGUAGE（未設為 nil）
    static func resolve(
        fileContents: String?,
        envToken: String?,
        envLanguage: String?
    ) -> LegacyConfig {
        // py:1571-1576 env 先寫進 defaults
        let baseToken = envToken ?? ""
        let baseLanguage = (envLanguage?.isEmpty == false) ? envLanguage! : "system"

        guard let raw = fileContents else {
            return LegacyConfig(token: baseToken, language: baseLanguage)
        }

        // py:1583 讀檔後 strip
        let content = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else {
            // py:1600-1605 legacy 裸 token 格式；language 僅在 env 指定時覆蓋
            return LegacyConfig(token: content, language: baseLanguage)
        }

        // py:1592-1598 env 覆蓋檔案值，其餘鍵以 defaults 補齊
        let fileToken = dict["token"] as? String
        let fileLanguage = dict["language"] as? String
        let token = (envToken?.isEmpty == false) ? envToken! : (fileToken ?? baseToken)
        let language = (envLanguage?.isEmpty == false) ? envLanguage! : (fileLanguage ?? baseLanguage)
        return LegacyConfig(token: token, language: language)
    }
}
