// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import CoreGraphics
import Foundation

/// H-02 UI 測試閘門的固定資料與旗標（docs/plans/2026-09-11-coverflow-h02-uitest-gate.md §3.1–3.3）。
///
/// **app 與 UITests 兩個 target 同編此檔**（見 project.yml）：旗標名、色板、ID 格式都只有一個來源，
/// 不重演 `AZW_UNIT_TEST_HOST` 兩邊各寫一份、再用測試釘住的模式。
enum CoverFlowUITestFixture {
    // MARK: 環境變數（UITest 以 launchEnvironment 注入）

    /// 啟用測試組裝：真實 RootView／AppModel／monitor／VM／ArtworkService，只換掉 Music
    static let launchFlag = "AZW_COVERFLOW_UI_TEST"
    /// 捲動軌跡檔的路徑；未設即不記錄
    static let tracePathVariable = "AZW_COVERFLOW_TRACE_PATH"
    /// 假 `albumTracks` 的延遲（毫秒）
    static let albumDelayVariable = "AZW_COVERFLOW_ALBUM_DELAY_MS"
    /// 真實 app 的 albumTracks 走串行 AE，必然「先掛空視圖、後填資料」；
    /// 延遲只為保住這個**次序**，任何遠大於一幀的值都行（計劃 §3.2）
    static let defaultAlbumDelayMilliseconds = 400

    // MARK: 資料

    static let trackCount = 20
    /// 固定起點在中段：兩側都有鄰張，疊放兩側都能驗
    static let playingIndex = 10
    static let artist = "AZW FIXTURE"
    static let album = "COVERFLOW GATE"

    // MARK: 幾何鏡像（UITests 不能 import 產品模組；同源由單元測試釘住）

    /// ＝`CoverFlowView.itemWidth`
    static let itemWidth: CGFloat = 260
    /// 相鄰卡片中心距＝itemWidth ＋ 負間距（`CoverFlowGeometry` 的覆疊比例 −0.42）
    static let stride: CGFloat = itemWidth * (1 - 0.42)

    // MARK: 查詢

    static func isEnabled(in environment: [String: String]) -> Bool {
        environment[launchFlag] == "1"
    }

    static func albumDelayMilliseconds(in environment: [String: String]) -> Int {
        guard let raw = environment[albumDelayVariable], let value = Int(raw), value >= 0 else {
            return defaultAlbumDelayMilliseconds
        }
        return value
    }

    static func persistentID(at index: Int) -> String {
        String(format: "T%02d", index)
    }

    /// 只接受 `T00`…`T19`；其他任何字串（含真實曲庫的 persistentID）一律 nil
    static func index(of persistentID: String) -> Int? {
        let characters = Array(persistentID)
        guard characters.count == 3, characters[0] == "T",
              characters[1].isASCII, characters[1].isNumber,
              characters[2].isASCII, characters[2].isNumber,
              let value = Int(String(characters[1...])),
              (0..<trackCount).contains(value)
        else { return nil }
        return value
    }

    static func title(at index: Int) -> String {
        "TRACK \(persistentID(at: index))"
    }

    /// 每張卡的辨識色（整面單色）。`hue = (i×7 mod 20)/20`：相鄰索引色相差 126°、隔一差 108°，
    /// 讓交疊區只需在「中心卡 vs 鄰張」兩色之間二選一
    static func color(at index: Int) -> GateRGB {
        let hue = Double((index * 7) % trackCount) / Double(trackCount)
        return GateRGB(hue: hue, saturation: 0.85, value: 0.95)
    }
}

/// sRGB 分量，0…1
struct GateRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

extension GateRGB {
    init(hue: Double, saturation: Double, value: Double) {
        let sector = (hue * 6).truncatingRemainder(dividingBy: 6)
        let chroma = value * saturation
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch Int(sector) {
        case 0: (r, g, b) = (chroma, x, 0)
        case 1: (r, g, b) = (x, chroma, 0)
        case 2: (r, g, b) = (0, chroma, x)
        case 3: (r, g, b) = (0, x, chroma)
        case 4: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        let m = value - chroma
        self.init(red: r + m, green: g + m, blue: b + m)
    }
}
#endif
