import Foundation
import Testing

@testable import AzathothsWhisper

// runner marks 檔（docs/plans/2026-09-13-coverflow-h02-fix4.md §5.4「分段來源」、§5.7 (10)）。
//
// 過渡態判定要把 sampler 的每幀幾何切成「運動段／hold 段」，段邊界只有 runner 知道
// （按鍵、捲動、截圖、落定各發生在哪個 wall-clock 時刻）。marks 檔就是這份邊界，
// 與 trace header 的 `epoch-us` 同錨點——格式錯一個欄位，整段時間軸就對不齊。
@Suite("CoverFlowMarksFormat")
struct CoverFlowMarksFormatTests {
    @Test func lineIsEpochKindPayloadSeparatedByTabs() {
        #expect(
            CoverFlowMarksFormat.line(epochMicroseconds: 1_726_200_000_123_456, kind: .stepBegin, payload: "T1.s2")
                == "1726200000123456\tstep-begin\tT1.s2\n"
        )
        #expect(CoverFlowMarksFormat.line(epochMicroseconds: 0, kind: .settled, payload: "") == "0\tsettled\t\n")
    }

    /// 種類是預登記詞彙（§5.7 (10)）：改名／漏項會讓離線判定找不到段邊界
    @Test func kindVocabularyIsTheRegisteredOne() {
        #expect(CoverFlowMarksFormat.Kind.allCases.map(\.rawValue) == [
            "step-begin", "step-end", "key", "scroll-begin", "scroll-end", "shot-begin", "shot-end", "settled",
        ])
    }

    /// payload 內的分欄／換行必須被吃掉，否則讀取端會切錯行（與 trace 同協議）
    @Test func payloadSeparatorsAreSanitised() {
        let line = CoverFlowMarksFormat.line(epochMicroseconds: 7, kind: .key, payload: "right\tArrow\nnext")
        #expect(line == "7\tkey\tright Arrow next\n")
        #expect(line.filter { $0 == "\n" }.count == 1)
    }

    /// 追加協議與 trace 相同：短寫續寫、寫不完即失敗（不當成已寫入）
    @Test func appendAllWritesEveryByteSynchronously() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("azw-marks-\(UUID().uuidString).marks").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let descriptor = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        #expect(descriptor >= 0)
        defer { close(descriptor) }

        let first = CoverFlowMarksFormat.line(epochMicroseconds: 1, kind: .scrollBegin, payload: "-300.0")
        let second = CoverFlowMarksFormat.line(epochMicroseconds: 2, kind: .scrollEnd, payload: "-300.0")
        #expect(CoverFlowTraceFormat.appendAll(Array(first.utf8), to: descriptor))
        #expect(CoverFlowTraceFormat.appendAll(Array(second.utf8), to: descriptor))

        let written = try String(contentsOfFile: path, encoding: .utf8)
        #expect(written == first + second)
        #expect(!CoverFlowTraceFormat.appendAll(Array("x".utf8), to: -1), "壞檔案描述子不得回報成功")
    }
}
