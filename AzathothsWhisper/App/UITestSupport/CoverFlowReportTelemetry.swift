// 測試基礎設施，不得進入 Release 成品（同 AppModel.unitTestHostFlag 的慣例）
#if DEBUG
import CoreGraphics
import Foundation

/// 契約報告的新增輸出（docs/plans/2026-09-13-coverflow-h02-fix4.md §5.7 (9)）。
///
/// **只增輸出，不改判定**：`GATE{…}` 行與 `SIG{…}` 格式一個字都不動——那是判定腳本的介面。
/// 三項各補一個已知盲區：
/// - 截圖起訖 wall-clock：兩格不一致（T1.s3／T2.s2）的 PASS／FAIL 之差是否落在取樣窗口內（§5.3 (b)）
/// - C2 實際取樣點與候選卡：報告只寫 `C2-STACK|G=…|over=…` 時無從復盤像素到底取在哪裡
/// - 落定耗時與輪詢次數：F3b (c) 觀察者效應要比對 ON／OFF 的中位數
///
/// 行首刻意避開 `GATE{`／`SIG{`／`[PROBE-`：腳本靠這三個前綴分類，多印一行就會被數進去。
enum CoverFlowReportTelemetry {
    /// 一次 `readStable` 的截圖窗口（wall-clock µs，與 marks／trace header 的 `epoch-us` 同錨點）
    struct ShotWindow: Equatable, Sendable {
        let beginMicroseconds: Int64
        let endMicroseconds: Int64

        var spanMilliseconds: Int { Int((endMicroseconds - beginMicroseconds) / 1000) }
    }

    /// 一次 `waitForStableCenter` 的耗時與輪詢次數
    struct Settle: Equatable, Sendable {
        let milliseconds: Int
        let polls: Int
    }

    /// 一次像素分類的實際輸入與結果（由 `pixelClassifier` 的記錄器收集，不經判定器）
    struct PixelSample: Equatable, Sendable {
        let point: CGPoint
        let candidates: [Int]
        let classification: GatePixelClass
    }

    static func shotLine(_ window: ShotWindow?) -> String? {
        guard let window else { return nil }
        return "shot-epoch-us=\(window.beginMicroseconds)..\(window.endMicroseconds)"
            + " span-ms=\(window.spanMilliseconds)"
    }

    static func settleLine(_ settle: Settle?) -> String? {
        guard let settle else { return nil }
        return "settle-ms=\(settle.milliseconds) polls=\(settle.polls)"
    }

    static func sampleLines(_ samples: [PixelSample]) -> [String] {
        samples.map { sample in
            let candidates = sample.candidates.map(CoverFlowUITestFixture.persistentID(at:)).joined(separator: "/")
            return "  sample point=\(format(sample.point)) candidates=\(candidates)"
                + " class=\(describe(sample.classification))"
        }
    }

    static func describe(_ classification: GatePixelClass) -> String {
        switch classification {
        case .card(let index): return "card:\(CoverFlowUITestFixture.persistentID(at: index))"
        case .background: return "background"
        case .uncertain: return "uncertain"
        }
    }

    private static func format(_ point: CGPoint) -> String {
        String(format: "%.1f,%.1f", point.x, point.y)
    }
}
#endif
