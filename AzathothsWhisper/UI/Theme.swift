import SwiftUI

// 設計 token（HTML_CONTENT tailwind.config 對應，py:69-98）
enum Theme {
    static let background = Color(red: 0, green: 0, blue: 0)                    // #000000
    static let surface = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255)  // #0a0a0a
    static let border = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)   // #333333
    static let coldWhite = Color(red: 0xE0 / 255, green: 0xE0 / 255, blue: 0xE0 / 255) // #E0E0E0
    static let primary = Color(red: 0x16 / 255, green: 0x43 / 255, blue: 0x9C / 255)   // #16439c

    // 全 0 圓角（About modal 例外在其視圖內自定義）
    static let cornerRadius: CGFloat = 0

    // 文字 glow：text-shadow 0 0 8px rgba(255,255,255,0.15)
    static let glowColor = Color.white.opacity(0.15)
    static let glowRadius: CGFloat = 8

    // Tailwind v3 預設 gray 色階（HTML 直接用 text-gray-500 等類名，值須逐一對齊）
    enum Gray {
        static let g300 = Color(hex: 0xD1D5DB)
        static let g400 = Color(hex: 0x9CA3AF)
        static let g500 = Color(hex: 0x6B7280)
        static let g600 = Color(hex: 0x4B5563)
        static let g700 = Color(hex: 0x374151)
        static let g800 = Color(hex: 0x1F2937)
        static let g900 = Color(hex: 0x111827)
    }

    // 面板底色（HTML 內硬編碼十六進位）
    static let cardBackground = Color(hex: 0x050505)     // Now Editing 卡片 bg-[#050505]
    static let editorBackground = Color(hex: 0x020202)   // 歌詞框 bg-[#020202]
    static let danger = Color(hex: 0xEF4444)             // text-red-500
    static let success = Color(hex: 0x22C55E)            // text-green-500
    static let link = Color(hex: 0x60A5FA)               // text-blue-400

    enum Fonts {
        static let displayName = "Space Grotesk"
        static let symbolName = "Material Symbols Outlined"

        static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .custom(displayName, fixedSize: size).weight(weight)
        }

        /// HTML 的 font-mono 走系統等寬堆疊（Menlo 優先）
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// .text-glow（py:118-120）
    func textGlow() -> some View {
        shadow(color: Theme.glowColor, radius: Theme.glowRadius / 2)
    }
}
