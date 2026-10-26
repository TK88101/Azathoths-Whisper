#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// S4 T9（sprint-4-detail.md §4.6 安裝契約；CR-013(c)、CR-014；#4-0 P1-a 新發現）

private let fresh = "4F192261-2906-4A39-9C9F-ECDBD05A0FAA"

actor FakeSigner: ShortcutSigning {
    var succeed = true
    private(set) var signed = 0
    private(set) var discarded = 0
    func set(succeed: Bool) { self.succeed = succeed }
    func sign(template: Data, timeout: Double) async -> SignedShortcut? {
        signed += 1
        guard succeed else { return nil }
        return SignedShortcut.forTesting(URL(fileURLWithPath: "/tmp/fake/YSE Play v1.shortcut"))
    }
    func discard(_ signed: SignedShortcut) { discarded += 1 }
}

actor FakeInstallBinding: ShortcutInstallBinding {
    var before: [ShortcutListing.Entry]? = []
    /// 第 n 次 checkInstall 回什麼（用完後重複最後一個）
    var checks: [Result<ShortcutIdentifier, ShortcutListing.InstallFailure>] = [.success(ShortcutIdentifier(fresh)!)]
    private(set) var checkCount = 0
    func set(before: [ShortcutListing.Entry]?) { self.before = before }
    func set(checks: [Result<ShortcutIdentifier, ShortcutListing.InstallFailure>]) { self.checks = checks }
    func beginInstall() async -> [ShortcutListing.Entry]? { before }
    func checkInstall(_ before: [ShortcutListing.Entry]) async -> Result<ShortcutIdentifier, ShortcutListing.InstallFailure> {
        defer { checkCount += 1 }
        return checks[min(checkCount, checks.count - 1)]
    }
}

final class OpenerLog: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var result = true
    func open(_ signed: SignedShortcut) -> Bool { lock.withLock { urls.append(signed.url) }; return result }
    var opened: [URL] { lock.withLock { urls } }
}

final class PhaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var phases: [ShortcutInstaller.Phase] = []
    func append(_ p: ShortcutInstaller.Phase) { lock.withLock { phases.append(p) } }
    var all: [ShortcutInstaller.Phase] { lock.withLock { phases } }
}

@Suite(.serialized, .timeLimit(.minutes(1))) struct ShortcutInstallerTests {
    let clock = ManualControlClock()
    let signer = FakeSigner()
    let binding = FakeInstallBinding()
    let opener = OpenerLog()
    let starter = FakeStarter()
    let phases = PhaseLog()

    /// 推進 `span` 秒（相對於目前時鐘）：同一測試內可連續呼叫；用絕對時刻時第二次呼叫不會再推進、睡眠者永不醒
    private func install(for span: Double = 40) async -> ShortcutInstaller.Outcome {
        let opener = self.opener, phases = self.phases
        let installer = ShortcutInstaller(signer: signer, binding: binding, open: { opener.open($0) }, starter: starter, clock: clock)
        let task = Task { await installer.install(progress: { phases.append($0) }) }
        await clock.settle()
        await clock.advance(by: span)
        return await task.value
    }

    @Test func happyPathBindsThenTriggersFirstRunPromptAndCleansUp() async throws {
        await binding.set(checks: [.failure(.notFound), .success(ShortcutIdentifier(fresh)!)])
        #expect(await install() == .installed(ShortcutIdentifier(fresh)!))
        #expect(opener.opened.count == 1 && opener.opened[0].lastPathComponent == "YSE Play v1.shortcut")
        #expect(await signer.discarded == 1)
        // 首次播放的分享確認：以必停輸入（不存在的專輯）跑一次已綁定的捷徑
        let first = try #require(starter.started.first)
        #expect(first.0 == ShortcutIdentifier(fresh)! && first.1.expectedCount == 1 && first.1.album.hasPrefix("yse-first-run-"))
        #expect(phases.all == [.waitingForAdd, .confirmingFirstRun])
    }

    @Test func listingUnavailableStopsBeforeSigning() async {
        await binding.set(before: nil)
        #expect(await install() == .listUnavailable)
        #expect(await signer.signed == 0)
    }

    @Test func signFailureNeverOpensAnything() async {
        await signer.set(succeed: false)
        #expect(await install() == .signFailed)
        #expect(opener.opened.isEmpty)
    }

    @Test func openFailureDiscardsSignedFile() async {
        opener.result = false
        #expect(await install() == .openFailed)
        #expect(await signer.discarded == 1)
    }

    @Test func notDetectedWithinThirtySeconds() async {
        await binding.set(checks: [.failure(.notFound)])
        #expect(await install(for: 60) == .notDetected)
        #expect(starter.startCount == 0)
        let checks = await binding.checkCount
        #expect((14...16).contains(checks))
    }

    @Test func nameTakenAndAmbiguousStopImmediately() async {
        await binding.set(checks: [.failure(.nameTaken)])
        #expect(await install() == .nameTaken)
        await binding.set(checks: [.failure(.ambiguous)])
        #expect(await install() == .ambiguous)
        #expect(starter.startCount == 0)
    }
}
#endif
