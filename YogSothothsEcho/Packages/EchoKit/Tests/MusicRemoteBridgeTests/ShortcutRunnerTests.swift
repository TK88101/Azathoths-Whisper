#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// S4 T7（sprint-4-detail.md §4.5 步驟 4、§4.6；H-27 經 CR-013(c)／CR-014 改訂）：
// 唯一的外部程式啟動點；每條路徑的執行檔與引數都是三組固定向量之一；暫存檔受控（0700 目錄、0600 檔、用完即刪）。

final class FakeProcess: LaunchedProcess, @unchecked Sendable {
    let lock = NSLock()
    var exitCode: Int32 = 0
    var stdout = Data()
    var stderrNonEmpty = false
    var hang = false
    private(set) var terminated = false
    private var waiter: CheckedContinuation<Void, Never>?

    func waitForExit() async -> ProcessExit {
        if lock.withLock({ hang && !terminated }) { await withCheckedContinuation { c in lock.withLock { waiter = c } } }
        return lock.withLock { ProcessExit(code: terminated ? nil : exitCode, stdout: stdout, stderrNonEmpty: stderrNonEmpty) }
    }

    func terminate() {
        let pending = lock.withLock { terminated = true; defer { waiter = nil }; return waiter }
        pending?.resume()
    }
}

final class FakeLauncher: ProcessLaunching, @unchecked Sendable {
    let lock = NSLock()
    var process = FakeProcess()
    var launchFails = false
    private(set) var launches: [(executable: String, arguments: [String])] = []
    /// 啟動當下暫存輸入檔的內容與權限（跑完會被刪，所以在啟動時記）
    private(set) var inputAtLaunch: (json: Data, permissions: Int)?
    var onLaunch: (([String]) -> Void)?

    func launch(executable: URL, arguments: [String]) -> (any LaunchedProcess)? {
        lock.withLock { launches.append((executable.path, arguments)) }
        if let index = arguments.firstIndex(of: "--input-path") {
            let path = arguments[index + 1]
            let data = FileManager.default.contents(atPath: path) ?? Data()
            let perms = (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int) ?? -1
            lock.withLock { inputAtLaunch = (data, perms ?? -1) }
        }
        onLaunch?(arguments)
        return launchFails ? nil : process
    }
}

private let bound = ShortcutIdentifier("8CF4FBAD-400E-412D-A7BA-D3BC9D2939CF")!
private let input = ShortcutInput(album: "Some Album", albumArtist: "", artist: "Someone", position: 3, expectedCount: 8)

struct ShortcutRunnerTests {
    let launcher = FakeLauncher()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yse-runner-tests-\(UUID().uuidString)")
    var runner: ShortcutRunner { ShortcutRunner(launcher: launcher, workDirectory: directory) }

    @Test func identifierAcceptsOnlyUUIDs() {
        #expect(ShortcutIdentifier("8cf4fbad-400e-412d-a7ba-d3bc9d2939cf")?.value == "8CF4FBAD-400E-412D-A7BA-D3BC9D2939CF")
        #expect(ShortcutIdentifier("YSE Play v1") == nil)
        #expect(ShortcutIdentifier("") == nil)
        #expect(ShortcutIdentifier("--output-type") == nil)
    }

    @Test func runUsesFixedVectorPrivateInputAndCleansUp() async throws {
        let running = try #require(runner.start(bound, input: input))
        let launch = try #require(launcher.launches.first)
        #expect(launch.executable == "/usr/bin/shortcuts")
        #expect(launch.arguments.count == 4 && launch.arguments[0] == "run" && launch.arguments[1] == bound.value
                && launch.arguments[2] == "--input-path")
        let atLaunch = try #require(launcher.inputAtLaunch)
        #expect(atLaunch.json == (try input.json()) && atLaunch.permissions == 0o600)
        let path = launch.arguments[3]
        #expect(path.hasPrefix(directory.path))
        let exit = await running.wait()
        #expect(exit.code == 0)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func launchFailureCleansUpAndReturnsNil() {
        launcher.launchFails = true
        #expect(runner.start(bound, input: input) == nil)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(files.allSatisfy { !$0.hasSuffix(".json") })
    }

    @Test func nonZeroExitAndStderrAreReportedWithoutContent() async throws {
        launcher.process.exitCode = 1
        launcher.process.stderrNonEmpty = true
        let exit = await try #require(runner.start(bound, input: input)).wait()
        #expect(exit.code == 1 && exit.stderrNonEmpty)
    }

    @Test func terminateEndsAHangingRun() async throws {
        launcher.process.hang = true
        let running = try #require(runner.start(bound, input: input))
        running.terminate()
        let exit = await running.wait()
        #expect(exit.code == nil && launcher.process.terminated)
    }

    @Test func signUsesFixedVectorAndReturnsSignedFile() async throws {
        launcher.onLaunch = { arguments in
            if let index = arguments.firstIndex(of: "--output") { FileManager.default.createFile(atPath: arguments[index + 1], contents: Data([1])) }
        }
        let signed = try #require(await runner.sign(template: Data("tpl".utf8), timeout: 5))
        let launch = try #require(launcher.launches.first)
        #expect(launch.arguments.count == 7 && Array(launch.arguments[0...2]) == ["sign", "--mode", "people-who-know-me"]
                && launch.arguments[3] == "--input" && launch.arguments[5] == "--output")
        #expect(FileManager.default.fileExists(atPath: signed.url.path))
        runner.discard(signed)
        #expect(!FileManager.default.fileExists(atPath: signed.url.deletingLastPathComponent().path))
    }

    @Test func signFailureLeavesNothingBehind() async {
        launcher.process.exitCode = 1
        #expect(await runner.sign(template: Data("tpl".utf8), timeout: 5) == nil)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func listUsesFixedVectorAndReturnsStdout() async throws {
        launcher.process.stdout = Data("A (8CF4FBAD-400E-412D-A7BA-D3BC9D2939CF)\n".utf8)
        let output = try #require(await runner.list(timeout: 1))
        #expect(launcher.launches.first?.arguments == ["list", "--show-identifiers"])
        #expect(output == launcher.process.stdout)
    }

    @Test func listTimeoutTerminatesAndReturnsNil() async {
        launcher.process.hang = true
        #expect(await runner.list(timeout: 0.05) == nil)
        #expect(launcher.process.terminated)
    }

    @Test func sweepRemovesStaleWorkDirectories() throws {
        let stale = directory.appendingPathComponent("run-old")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        runner.sweep()
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }
}
#endif
