#if os(macOS)
import Foundation
import RemoteProtocol

// 唯一啟動外部程式的檔案（H-27，經 CR-013(c)、CR-014 改訂；echo_gate E4）。
// 執行檔固定 /usr/bin/shortcuts，引數只有三組固定向量：
//   run <綁定的捷徑識別碼> --input-path <本次暫存檔>
//   sign --mode people-who-know-me --input <暫存檔> --output <暫存檔>（#4-0 P1-b：本機即可完成）
//   list --show-identifiers
// 暫存檔放在本 runner 專屬目錄下的子目錄（0700），檔案 0600，用完即刪；stderr 內容不讀、只記是否非空（N-05）；
// list 的輸出（含使用者所有捷徑名稱）只回給呼叫端在記憶體解析，本檔不記錄。

/// 捷徑識別碼（`shortcuts list --show-identifiers` 給的 UUID）；`run` 只接受它、不接受名稱（CR-014）
public struct ShortcutIdentifier: Sendable, Equatable, Codable {
    public let value: String

    public init?(_ text: String) {
        guard let uuid = UUID(uuidString: text) else { return nil }
        value = uuid.uuidString
    }
}

public struct ProcessExit: Sendable, Equatable {
    /// nil＝被終止或沒有正常結束
    public let code: Int32?
    public let stdout: Data
    public let stderrNonEmpty: Bool
}

public protocol LaunchedProcess: Sendable {
    func waitForExit() async -> ProcessExit
    func terminate()
}

/// 外部邊界（正式＝Process；測試＝替身）
public protocol ProcessLaunching: Sendable {
    func launch(executable: URL, arguments: [String]) -> (any LaunchedProcess)?
}

/// 已簽署的捷徑檔：只有 `ShortcutRunner.sign` 能建立（NSWorkspace 只准開它，§4.6 安裝契約步驟 3）
public struct SignedShortcut: Sendable, Equatable {
    public let url: URL
    fileprivate init(url: URL) { self.url = url }
    /// 測試用（模組內部可見；App 端無法憑空造出）
    static func forTesting(_ url: URL) -> SignedShortcut { SignedShortcut(url: url) }
}

/// 執行中的捷徑：等它結束時刪掉本次輸入檔
public struct RunningShortcut: Sendable {
    let process: any LaunchedProcess
    let directory: URL

    public func wait() async -> ProcessExit {
        let exit = await process.waitForExit()
        try? FileManager.default.removeItem(at: directory)
        return exit
    }

    public func terminate() { process.terminate() }
}

public struct ShortcutRunner: Sendable {
    static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")
    public static let signedFileName = "YSE Play v1.shortcut"

    private let launcher: any ProcessLaunching
    private let workDirectory: URL

    public init(launcher: any ProcessLaunching = SystemProcessLauncher(),
                workDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("com.ibridgezhao.yse.shortcuts")) {
        self.launcher = launcher
        self.workDirectory = workDirectory
    }

    /// 啟動一次點歌；寫檔或啟動失敗回 nil（不留暫存檔）。自此不可取消（設計 §5.3-2），只能 terminate 子行程
    public func start(_ shortcut: ShortcutIdentifier, input: ShortcutInput) -> RunningShortcut? {
        guard let directory = makePrivateDirectory(prefix: "run"), let json = try? input.json() else { return nil }
        let file = directory.appendingPathComponent("input.json")
        guard writePrivate(json, to: file),
              let process = launcher.launch(executable: Self.executable, arguments: ["run", shortcut.value, "--input-path", file.path])
        else {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
        return RunningShortcut(process: process, directory: directory)
    }

    /// 簽署模板；成功回簽好的檔（呼叫端用完要 discard），失敗或逾時回 nil 且不留檔
    public func sign(template: Data, timeout: Double) async -> SignedShortcut? {
        guard let directory = makePrivateDirectory(prefix: "sign") else { return nil }
        let input = directory.appendingPathComponent("unsigned.shortcut")
        let output = directory.appendingPathComponent(Self.signedFileName)
        guard writePrivate(template, to: input),
              let process = launcher.launch(executable: Self.executable, arguments: [
                  "sign", "--mode", "people-who-know-me", "--input", input.path, "--output", output.path,
              ])
        else {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
        let exit = await Self.wait(process, timeout: timeout)
        guard exit.code == 0, FileManager.default.fileExists(atPath: output.path) else {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
        try? FileManager.default.removeItem(at: input)
        return SignedShortcut(url: output)
    }

    public func discard(_ signed: SignedShortcut) {
        try? FileManager.default.removeItem(at: signed.url.deletingLastPathComponent())
    }

    /// 列出捷徑與識別碼；失敗、非零或逾時回 nil
    public func list(timeout: Double) async -> Data? {
        guard let process = launcher.launch(executable: Self.executable, arguments: ["list", "--show-identifiers"]) else { return nil }
        let exit = await Self.wait(process, timeout: timeout)
        return exit.code == 0 ? exit.stdout : nil
    }

    /// 啟動時清掉上次異常結束留下的子目錄（刪除失敗不影響功能）
    public func sweep() {
        let entries = (try? FileManager.default.contentsOfDirectory(at: workDirectory, includingPropertiesForKeys: nil)) ?? []
        for entry in entries { try? FileManager.default.removeItem(at: entry) }
    }

    private static func wait(_ process: any LaunchedProcess, timeout: Double) async -> ProcessExit {
        let timer = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if !Task.isCancelled { process.terminate() }
        }
        let exit = await process.waitForExit()
        timer.cancel()
        return exit
    }

    private func makePrivateDirectory(prefix: String) -> URL? {
        let directory = workDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            return directory
        } catch {
            return nil
        }
    }

    private func writePrivate(_ data: Data, to file: URL) -> Bool {
        FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
    }
}

/// 正式的啟動器：本檔唯一的 Process 建立點與唯一的啟動呼叫（echo_gate E4 計數）
public struct SystemProcessLauncher: ProcessLaunching {
    public init() {}

    public func launch(executable: URL, arguments: [String]) -> (any LaunchedProcess)? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let handle = SystemProcess(process: process)
        do {
            try process.run()
        } catch {
            return nil
        }
        return handle
    }
}

private final class SystemProcess: LaunchedProcess, @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var output = Data()
    private var errorSeen = false
    private var finished: ProcessExit?
    private var waiters: [CheckedContinuation<ProcessExit, Never>] = []
    private var terminated = false

    init(process: Process) {
        self.process = process
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        // 邊讀邊收，避免輸出塞滿管線緩衝讓子行程卡住
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            self?.lock.withLock { self?.output.append(chunk) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData   // 內容丟棄，只記是否非空
            if !chunk.isEmpty { self?.lock.withLock { self?.errorSeen = true } }
        }
        process.terminationHandler = { [weak self] finishedProcess in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let rest = out.fileHandleForReading.readDataToEndOfFile()
            self?.finish(code: finishedProcess.terminationStatus, rest: rest)
        }
    }

    private func finish(code: Int32, rest: Data) {
        let (exit, pending) = lock.withLock { () -> (ProcessExit, [CheckedContinuation<ProcessExit, Never>]) in
            output.append(rest)
            let exit = ProcessExit(code: terminated ? nil : code, stdout: output, stderrNonEmpty: errorSeen)
            finished = exit
            defer { waiters = [] }
            return (exit, waiters)
        }
        pending.forEach { $0.resume(returning: exit) }
    }

    func waitForExit() async -> ProcessExit {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { () -> ProcessExit? in
                if let finished { return finished }
                waiters.append(continuation)
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    func terminate() {
        lock.withLock { terminated = true }
        if process.isRunning { process.terminate() }
    }
}
#endif
