import Foundation

// Python 字串語義的等價實作。
// 移植 v1.2.x 時，Foundation/ICU 與 CPython 在兩處字串基礎行為上不同；1:1 驗收口徑下必須對齊。
// 依據：M2 對抗審查（2026-08-10）以全 Unicode 碼點掃描比對兩邊實作後的結論。
enum PythonCompat {
    /// Python `str.strip()` 的字符集，等同 `{cp for cp in range(0x110000) if chr(cp).isspace()}`。
    /// 與 Foundation 的 `.whitespacesAndNewlines` 差異僅五個碼點：
    ///   - Swift 多剝 U+200B（ZWSP）——Python 視為一般字元
    ///   - Python 多剝 U+001C–U+001F（檔案/群組/記錄/單元分隔符）
    static let whitespace: CharacterSet = {
        var set = CharacterSet()
        let scalars: [UInt32] = [
            0x09, 0x0A, 0x0B, 0x0C, 0x0D,       // \t \n \v \f \r
            0x1C, 0x1D, 0x1E, 0x1F,             // 檔案/群組/記錄/單元分隔符
            0x20,                               // space
            0x85,                               // NEL
            0xA0,                               // NBSP
            0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
        ]
        for value in scalars {
            set.insert(Unicode.Scalar(value)!)
        }
        set.insert(charactersIn: Unicode.Scalar(0x2000)!...Unicode.Scalar(0x200A)!)
        return set
    }()

    /// CPython `str.lower()` 的等價：ICU 的 `lowercased()` 不套用希臘文末尾 sigma 規則。
    /// 規則（CPython handle_capital_sigma）：Σ 在「前方有 cased 字元、後方無 cased 字元」時小寫為 ς，否則為 σ。
    /// 兩側掃描時跳過 Case_Ignorable 字元。
    static func lowercased(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0.value == 0x03A3 }) else {
            return value.lowercased()
        }

        let scalars = Array(value.unicodeScalars)
        var output = String.UnicodeScalarView()
        for (index, scalar) in scalars.enumerated() {
            guard scalar.value == 0x03A3 else {
                output.append(contentsOf: String(scalar).lowercased().unicodeScalars)
                continue
            }
            let isFinal = hasCasedScalar(in: scalars[..<index].reversed())
                && !hasCasedScalar(in: scalars[(index + 1)...])
            output.append(Unicode.Scalar(isFinal ? 0x03C2 : 0x03C3)!)
        }
        return String(output)
    }

    private static func hasCasedScalar<S: Sequence>(in scalars: S) -> Bool where S.Element == Unicode.Scalar {
        for scalar in scalars {
            if scalar.properties.isCaseIgnorable { continue }
            return scalar.properties.isCased
        }
        return false
    }
}

extension String {
    /// `str.strip()` 等價
    func pythonStripped() -> String {
        trimmingCharacters(in: PythonCompat.whitespace)
    }

    /// `str.lower()` 等價（含希臘文末尾 sigma 規則）
    func pythonLowercased() -> String {
        PythonCompat.lowercased(self)
    }
}
