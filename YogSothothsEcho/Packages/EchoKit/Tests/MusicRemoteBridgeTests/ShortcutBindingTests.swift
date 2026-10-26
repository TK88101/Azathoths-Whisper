#if os(macOS)
import Foundation
import Testing
@testable import MusicRemoteBridge

// S4 T7（CR-014；sprint-4-detail.md §4.5 步驟 2、§4.6 步驟 4）：捷徑以安裝時綁定的識別碼辨認。
// 捷徑名稱一律自編；`list` 輸出只在記憶體解析

private let v1 = "8CF4FBAD-400E-412D-A7BA-D3BC9D2939CF"
private let other = "A84240AF-96C9-435C-BCCC-46B77337EA7E"
private let fresh = "4F192261-2906-4A39-9C9F-ECDBD05A0FAA"

private func listing(_ lines: [(String, String)]) -> Data {
    Data(lines.map { "\($0.0) (\($0.1))" }.joined(separator: "\n").appending("\n").utf8)
}

struct ShortcutListingTests {
    @Test func parsesNamesWithParenthesesAndIgnoresMalformedLines() {
        let data = Data("Plain (\(v1))\nMy (cool) thing (\(other))\nno identifier here\nBad (not-a-uuid)\n".utf8)
        let entries = ShortcutListing.parse(data)
        #expect(entries == [ShortcutListing.Entry(name: "Plain", id: ShortcutIdentifier(v1)!),
                            ShortcutListing.Entry(name: "My (cool) thing", id: ShortcutIdentifier(other)!)])
    }

    @Test func installCandidateIsTheSingleNewExactName() {
        let before = ShortcutListing.parse(listing([("Other", other)]))
        let after = ShortcutListing.parse(listing([("Other", other), ("YSE Play v1", fresh)]))
        #expect(ShortcutListing.installed(name: "YSE Play v1", before: before, after: after) == .success(ShortcutIdentifier(fresh)!))
    }

    @Test func nothingNewIsNotYetInstalled() {
        let same = ShortcutListing.parse(listing([("Other", other)]))
        #expect(ShortcutListing.installed(name: "YSE Play v1", before: same, after: same) == .failure(.notFound))
    }

    /// 已有同名者時「捷徑」App 會把新的改名成「… 2」：不猜、要求刪舊重裝
    @Test func renamedDuplicateMeansNameTaken() {
        let before = ShortcutListing.parse(listing([("YSE Play v1", v1)]))
        let after = ShortcutListing.parse(listing([("YSE Play v1", v1), ("YSE Play v1 2", fresh)]))
        #expect(ShortcutListing.installed(name: "YSE Play v1", before: before, after: after) == .failure(.nameTaken))
    }

    @Test func twoNewExactNamesAreAmbiguous() {
        let after = ShortcutListing.parse(listing([("YSE Play v1", v1), ("YSE Play v1", fresh)]))
        #expect(ShortcutListing.installed(name: "YSE Play v1", before: [], after: after) == .failure(.ambiguous))
    }
}

final class MemoryBindingStore: ShortcutBindingStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ShortcutIdentifier?
    init(_ value: ShortcutIdentifier? = nil) { self.value = value }
    func load() -> ShortcutIdentifier? { lock.withLock { value } }
    func save(_ id: ShortcutIdentifier?) { lock.withLock { value = id } }
}

actor FakeLister: ShortcutListing.Source {
    var output: Data? = Data()
    private(set) var calls = 0
    func set(_ data: Data?) { output = data }
    func list(timeout: Double) async -> Data? { calls += 1; return output }
}

struct ShortcutBindingTests {
    let lister = FakeLister()

    @Test func noBindingIsMissingWithoutListing() async {
        let binding = ShortcutBinding(store: MemoryBindingStore(), lister: lister)
        #expect(await binding.status() == .missing)
        #expect(await lister.calls == 0)
    }

    @Test func boundIdentifierPresentIsBoundEvenIfRenamed() async {
        await lister.set(listing([("Renamed by user", v1)]))
        let binding = ShortcutBinding(store: MemoryBindingStore(ShortcutIdentifier(v1)), lister: lister)
        #expect(await binding.status() == .bound(ShortcutIdentifier(v1)!))
    }

    @Test func vanishedIdentifierOrFailedListIsMissing() async {
        let binding = ShortcutBinding(store: MemoryBindingStore(ShortcutIdentifier(v1)), lister: lister)
        await lister.set(listing([("YSE Play v1", fresh)]))
        #expect(await binding.status() == .missing)
        await binding.invalidate()
        await lister.set(nil)
        #expect(await binding.status() == .missing)
    }

    @Test func statusIsCachedUntilInvalidated() async {
        await lister.set(listing([("YSE Play v1", v1)]))
        let binding = ShortcutBinding(store: MemoryBindingStore(ShortcutIdentifier(v1)), lister: lister)
        _ = await binding.status()
        _ = await binding.status()
        #expect(await lister.calls == 1)
        await binding.invalidate()
        _ = await binding.status()
        #expect(await lister.calls == 2)
    }

    @Test func installBindsTheNewShortcutAndPersists() async throws {
        let store = MemoryBindingStore()
        await lister.set(listing([("Other", other)]))
        let binding = ShortcutBinding(store: store, lister: lister)
        let snapshot = try #require(await binding.beginInstall())
        await lister.set(listing([("Other", other), ("YSE Play v1", fresh)]))
        #expect(await binding.checkInstall(snapshot) == .success(ShortcutIdentifier(fresh)!))
        #expect(store.load() == ShortcutIdentifier(fresh))
        #expect(await binding.status() == .bound(ShortcutIdentifier(fresh)!))
    }

    @Test func failedInstallKeepsPreviousBinding() async throws {
        let store = MemoryBindingStore(ShortcutIdentifier(v1))
        await lister.set(listing([("YSE Play v1", v1)]))
        let binding = ShortcutBinding(store: store, lister: lister)
        let snapshot = try #require(await binding.beginInstall())
        await lister.set(listing([("YSE Play v1", v1), ("YSE Play v1 2", fresh)]))
        #expect(await binding.checkInstall(snapshot) == .failure(.nameTaken))
        #expect(store.load() == ShortcutIdentifier(v1))
    }
}
#endif
