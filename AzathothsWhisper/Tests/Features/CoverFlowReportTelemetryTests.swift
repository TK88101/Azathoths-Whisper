import CoreGraphics
import Foundation
import Testing

@testable import AzathothsWhisper

// 契約報告的新增輸出（docs/plans/2026-09-13-coverflow-h02-fix4.md §5.7 (9)）。
//
// **只增輸出，不改判定**：GATE 行與 SIG 格式一個字都不動（那是判定腳本的介面）。
// 新增的三項各對應一個已知盲區：截圖起訖 wall-clock（兩格不一致是否落在取樣窗口內，§5.3 (b)）、
// C2 實際取樣點與候選卡（像素分類到底看的是哪裡）、落定耗時與輪詢次數（F3b (c) 觀察者效應）。
@Suite("CoverFlowReportTelemetry")
struct CoverFlowReportTelemetryTests {
    @Test func shotLineCarriesWallClockStartEndAndSpan() {
        let window = CoverFlowReportTelemetry.ShotWindow(
            beginMicroseconds: 1_726_200_000_000_000, endMicroseconds: 1_726_200_000_180_000
        )
        #expect(CoverFlowReportTelemetry.shotLine(window)
            == "shot-epoch-us=1726200000000000..1726200000180000 span-ms=180")
        #expect(CoverFlowReportTelemetry.shotLine(nil) == nil, "沒截圖的步驟不印空欄位")
    }

    @Test func settleLineCarriesDurationAndPollCount() {
        let settle = CoverFlowReportTelemetry.Settle(milliseconds: 480, polls: 8)
        #expect(CoverFlowReportTelemetry.settleLine(settle) == "settle-ms=480 polls=8")
        #expect(CoverFlowReportTelemetry.settleLine(nil) == nil)
    }

    /// C2 的判定輸入是「一個點 ＋ 兩張候選卡」；報告只說 `C2-STACK|G=…|over=…` 時無從復盤取樣位置
    @Test func sampleLinesNameThePointCandidatesAndClassification() {
        let samples = [
            CoverFlowReportTelemetry.PixelSample(
                point: CGPoint(x: 612.5, y: 300), candidates: [10, 11], classification: .card(11)
            ),
            CoverFlowReportTelemetry.PixelSample(
                point: CGPoint(x: 700, y: 300.25), candidates: [10, 11], classification: .background
            ),
            CoverFlowReportTelemetry.PixelSample(
                point: CGPoint(x: 1, y: 2), candidates: [0], classification: .uncertain
            ),
        ]
        #expect(CoverFlowReportTelemetry.sampleLines(samples) == [
            "  sample point=612.5,300.0 candidates=T10/T11 class=card:T11",
            // `%.1f` 與既有的 `CoverFlowGateLogic.format` 同慣例（round-half-to-even）：300.25 → 300.2
            "  sample point=700.0,300.2 candidates=T10/T11 class=background",
            "  sample point=1.0,2.0 candidates=T00 class=uncertain",
        ])
        #expect(CoverFlowReportTelemetry.sampleLines([]).isEmpty)
    }

    /// 新增行不得以 `GATE{`／`SIG{`／`[PROBE-` 起首：腳本靠這三個前綴分類，多印一行就會被數進去
    @Test func newLinesCannotBeMistakenForGateOutput() {
        let lines = [
            CoverFlowReportTelemetry.shotLine(.init(beginMicroseconds: 1, endMicroseconds: 2)),
            CoverFlowReportTelemetry.settleLine(.init(milliseconds: 1, polls: 1)),
        ].compactMap { $0 } + CoverFlowReportTelemetry.sampleLines([
            .init(point: .zero, candidates: [1], classification: .card(1)),
        ])
        for line in lines {
            #expect(!line.hasPrefix("GATE{"))
            #expect(!line.hasPrefix("SIG{"))
            #expect(!line.contains("[PROBE-"))
        }
    }
}
