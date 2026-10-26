import Foundation

// F-P-01 ③：唯一呼叫 `shortcuts` 的檔案（spike_gate.sh 限定）。捷徑是協議外的 Music 控制路徑，
// 故只在 Experiments.run 的 Session 內使用（同意、預扣上限、快照與還原）。
// 輸入 JSON 寫進本次專用的暫存檔、跑完即刪（2026-10-15 preflight：`--input-path /dev/stdin` 捷徑讀到空輸入、改播整個曲庫）。
// stderr 只印在終端機，不寫進結果檔（可能含專輯名）。
enum ShortcutRunner {
    static let executable = "/usr/bin/shortcuts"
    static let finishTimeout: Duration = .seconds(20)

    struct Outcome: Encodable {
        let exitCode: Int32?
        let timedOut: Bool
    }

    struct Running {
        let process: Process
        let stderr: Pipe
        let inputFile: URL?
    }

    /// input 為 nil＝不帶 --input-path（驗非互動、無輸入）
    static func start(name: String, input: Data?) throws -> Running {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        var arguments = ["run", name]
        var inputFile: URL?
        if let input {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("yse-fp01-\(UUID().uuidString).json")
            try write(input, to: file)
            inputFile = file
            arguments += ["--input-path", file.path]
        }
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let stderr = Pipe()
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            remove(inputFile)
            throw error
        }
        return Running(process: process, stderr: stderr, inputFile: inputFile)
    }

    private static func write(_ input: Data, to inputFile: URL) throws {
        try input.write(to: inputFile)
    }

    private static func remove(_ inputFile: URL?) {
        guard let inputFile else { return }
        try? FileManager.default.removeItem(at: inputFile)
    }

    /// 等它結束（逾時就終止）；stderr 第一行只印出來給在場的人看
    static func finish(_ running: Running, label: String) async -> Outcome {
        defer { remove(running.inputFile) }
        let process = running.process
        let deadline = ContinuousClock.now + finishTimeout
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !process.isRunning else {
            process.terminate()
            print("[\(label)] shortcuts 逾時，已終止")
            return Outcome(exitCode: nil, timedOut: true)
        }
        let message = String(decoding: running.stderr.fileHandleForReading.availableData, as: UTF8.self)
            .split(separator: "\n").first.map(String.init) ?? ""
        print("[\(label)] exit \(process.terminationStatus)\(message.isEmpty ? "" : "：\(message)")")
        return Outcome(exitCode: process.terminationStatus, timedOut: false)
    }
}
