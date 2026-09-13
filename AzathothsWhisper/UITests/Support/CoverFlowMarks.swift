import Foundation

/// runner marks 檔的寫入端（docs/plans/2026-09-13-coverflow-h02-fix4.md §5.7 (10)）。
///
/// **為何獨立成檔、而不是寫進 trace**：`readUntilQuiet` 以**檔案位移**判「軌跡靜止 500 ms」
/// （凍結參數），任何往同一份 trace 每步追加的記錄都會讓它永不靜止、燒滿 5 s 上限（計劃 §2）。
///
/// **為何是 no-op 而不是 optional 散落各處**：閘門輪不設 `AZW_EVIDENCE_DIR`，此時每個 `record`
/// 都要靜默跳過；把這個分支收在這裡，呼叫點就不必到處寫 `if let marks`。
///
/// 寫入協議與 trace 相同（`CoverFlowTraceFormat.appendAll`）：O_APPEND 同步 `write(2)`、不 fsync。
final class CoverFlowMarks {
    private var descriptor: Int32?
    private(set) var writeErrors = 0

    var isRecording: Bool { descriptor != nil }

    /// `path == nil`（未設證據目錄）或開檔失敗 → 整個物件是 no-op
    init(path: String?) {
        guard let path else { return }
        let opened = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        descriptor = opened >= 0 ? opened : nil
    }

    deinit {
        if let descriptor { Darwin.close(descriptor) }
    }

    func record(_ kind: CoverFlowMarksFormat.Kind, _ payload: String = "") {
        guard let descriptor else { return }
        let line = CoverFlowMarksFormat.line(
            epochMicroseconds: CoverFlowTraceFormat.nowEpochMicroseconds(), kind: kind, payload: payload
        )
        if !CoverFlowTraceFormat.appendAll(Array(line.utf8), to: descriptor) { writeErrors += 1 }
    }

    /// 收尾：manifest 的 md5 必須算在最終內容上，算之前要先關檔
    func close() {
        guard let descriptor else { return }
        Darwin.close(descriptor)
        self.descriptor = nil
    }
}
