import Foundation
import Testing

// 計劃 AC9 ③、AC8c：`Scripts/no_playback_gate.sh` 對 repo 退出 0；每條禁止模式各一負對照退出非 0
@Suite("NoPlaybackGateScript")
struct NoPlaybackGateScriptTests {
    private static let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func run(_ arguments: [String], stdin: String? = nil) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [projectRoot.appendingPathComponent("Scripts/no_playback_gate.sh").path] + arguments
        process.currentDirectoryURL = projectRoot
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, text)
    }

    @Test func repositoryPassesTheGate() throws {
        let result = try Self.run([])
        #expect(result.status == 0, "\(result.output)")
    }

    @Test("每條禁止模式各一負對照", arguments: [
        ("UI/Foo.swift", "let s = NSAppleScript(source: \"\")"),
        ("Features/Foo.swift", "e.sendEvent(options: [], timeout: 1)"),
        ("App/Foo.swift", "import Carbon"),
        ("Infra/Foo.swift", "MediaRemote.send()"),
        ("UI/Foo.swift", "import ScriptingBridge"),
        ("Services/Music/MusicAppleEventsClient.swift", "x.perform(Selector((\"pause\")))"),
        ("Services/Music/MusicAppleEventsClient.swift", "x.value(forKey: \"playpause\")"),
        ("Services/Music/MusicAppleEventsClient.swift", "x.setValue(true, forKey: \"shuffleEnabled\")"),
        ("Services/Music/MusicAppleEventsClient.swift", "tracks.add(obj)"),
        ("Services/Music/QueueFileSource.swift", "try data.write(to: url)"),
        ("Services/Music/QueueFileSource.swift", "try FileManager.default.removeItem(at: url)"),
    ])
    func forbiddenPatternIsCaught(asPath: String, line: String) throws {
        let result = try Self.run(["--stdin", asPath], stdin: line + "\n")
        #expect(result.status != 0, "未攔下：\(asPath) ← \(line)")
    }

    @Test func allowedPatternsPass() throws {
        let clientLine = "let reference = artwork.value(forKey: \"rawData\")"
        #expect(try Self.run(["--stdin", "Services/Music/MusicAppleEventsClient.swift"], stdin: clientLine + "\n").status == 0)
        #expect(try Self.run(["--stdin", "Services/Music/MusicAppleEventsClient.swift"], stdin: "import ScriptingBridge\n").status == 0)
        #expect(try Self.run(["--stdin", "Services/Music/QueueFileSource.swift"], stdin: "let data = try Data(contentsOf: url)\n").status == 0)
    }
}
