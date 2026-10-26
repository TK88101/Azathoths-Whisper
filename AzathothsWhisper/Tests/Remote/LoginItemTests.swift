import Foundation
import Testing

@testable import AzathothsWhisper

// S6 T10（sprint-6-detail.md §4.10、D11、CR-021）：登入時啟動——狀態以系統為準（不存 UserDefaults）、一次只一個操作、
// 失敗回原值並顯示錯誤種類、操作後重讀、需要批准時引導到系統設定

final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: LoginItemStatus
    var registerError: Error?
    private(set) var calls: [String] = []
    /// 有值＝register／unregister 停在這裡，直到 release
    private var gate: DispatchSemaphore?

    init(_ status: LoginItemStatus) { _status = status }

    var status: LoginItemStatus { lock.withLock { _status } }
    func set(_ status: LoginItemStatus) { lock.withLock { _status = status } }
    func hold() { lock.withLock { gate = DispatchSemaphore(value: 0) } }
    func release() { lock.withLock { gate }?.signal() }

    func register() throws {
        lock.withLock { calls.append("register") }
        lock.withLock { gate }?.wait()
        if let registerError = lock.withLock({ registerError }) { throw registerError }
        set(.enabled)
    }

    func unregister() throws {
        lock.withLock { calls.append("unregister") }
        lock.withLock { gate }?.wait()
        set(.disabled)
    }

    func openSystemSettings() { lock.withLock { calls.append("settings") } }
    var recorded: [String] { lock.withLock { calls } }
}

struct TestLoginError: Error {}

@Suite("LoginItemPresentation")
struct LoginItemPresentationTests {
    @Test func everyStatusHasAPresentation() {
        #expect(LoginItemPresentation.isOn(.enabled))
        #expect(!LoginItemPresentation.isOn(.disabled) && !LoginItemPresentation.isOn(.requiresApproval) && !LoginItemPresentation.isOn(.unavailable))
        #expect(LoginItemPresentation.noteKey(.enabled) == nil && LoginItemPresentation.noteKey(.disabled) == nil)
        #expect(LoginItemPresentation.noteKey(.requiresApproval) == "login_item_requires_approval")
        #expect(LoginItemPresentation.noteKey(.unavailable) == "login_item_unavailable")
        #expect(LoginItemPresentation.showsSettingsButton(.requiresApproval))
        #expect(!LoginItemPresentation.showsSettingsButton(.enabled) && !LoginItemPresentation.showsSettingsButton(.unavailable))
    }
}

@MainActor
@Suite("LoginItemController")
struct LoginItemControllerTests {
    @Test func readsStatusFromTheSystem() {
        let fake = FakeLoginItem(.enabled)
        let c = LoginItemController(control: fake)
        #expect(c.status == .enabled)
        fake.set(.disabled)
        c.refresh()
        #expect(c.status == .disabled)
    }

    @Test func turningOnRegistersOnceAndRereads() async {
        let fake = FakeLoginItem(.disabled)
        let c = LoginItemController(control: fake)
        await c.setEnabled(true)
        #expect(fake.recorded == ["register"] && c.status == .enabled && c.failure == nil && !c.isBusy)
    }

    @Test func failureKeepsTheOldValueAndShowsTheKind() async {
        let fake = FakeLoginItem(.disabled)
        fake.registerError = TestLoginError()
        let c = LoginItemController(control: fake)
        await c.setEnabled(true)
        #expect(c.status == .disabled && c.failure?.hasSuffix("TestLoginError 1") == true)
        fake.registerError = nil
        await c.setEnabled(true)
        #expect(c.status == .enabled && c.failure == nil)
    }

    @Test func turningOffUnregisters() async {
        let fake = FakeLoginItem(.enabled)
        let c = LoginItemController(control: fake)
        await c.setEnabled(false)
        #expect(fake.recorded == ["unregister"] && c.status == .disabled)
    }

    /// 開後立刻關：第二次在第一次完成前被擋
    @Test func secondToggleWhileBusyIsIgnored() async {
        let fake = FakeLoginItem(.disabled)
        fake.hold()
        let c = LoginItemController(control: fake)
        let first = Task { await c.setEnabled(true) }
        while fake.recorded.isEmpty { await Task.yield() }
        #expect(c.isBusy)
        await c.setEnabled(false)
        fake.release()
        await first.value
        #expect(fake.recorded == ["register"] && c.status == .enabled)
    }

    /// 前景重讀早於舊操作完成：顯示最新的系統狀態，舊操作的結果不覆蓋（完成時一律再讀一次系統）
    @Test func refreshDuringOperationWins() async {
        let fake = FakeLoginItem(.disabled)
        fake.registerError = TestLoginError()
        fake.hold()
        let c = LoginItemController(control: fake)
        let op = Task { await c.setEnabled(true) }
        while fake.recorded.isEmpty { await Task.yield() }
        fake.set(.requiresApproval)
        c.refresh()
        #expect(c.status == .requiresApproval)
        fake.release()
        await op.value
        #expect(c.status == .requiresApproval && c.failure == nil)
    }

    @Test func approvalOpensSystemSettings() {
        let fake = FakeLoginItem(.requiresApproval)
        let c = LoginItemController(control: fake)
        c.openSystemSettings()
        #expect(fake.recorded == ["settings"])
    }
}
