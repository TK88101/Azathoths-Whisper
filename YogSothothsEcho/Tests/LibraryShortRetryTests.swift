import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// F-L1 R2（s6-61-library-retry.md §5、§6）：專輯清單分頁遇 busy／rateLimited 短重試；用盡即停；取消與換世代不再試、不採用
@MainActor
struct LibraryShortRetryTests {
    let sleeper = ManualSleeper()
    let retrySleeper = CancellableSleeper()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lib-retry-\(UUID().uuidString)")

    func model() -> LibraryViewModel {
        let sleeper = sleeper
        return LibraryViewModel(artworkDirectory: directory, sleep: { await sleeper.sleep($0) }, retry: retrySleeper.options)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func page(_ cursor: String?) -> Int { (cursor.flatMap(CatalogCursor.decode)?.offset ?? 0) / 100 + 1 }

    /// ① 第 1 頁被限流一次 → 等 0.5 s 重送 → 載完
    @Test func rateLimitedFirstPageIsRetriedOnce() async {
        let client = ScriptedEchoClient(total: 50)
        client.lock.withLock { client.failuresOnCall = [1: .remote(.rateLimited)] }
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready })
        #expect(vm.albums.count == 50)
        #expect(client.calls == 2)
        #expect(retrySleeper.durations == [.milliseconds(500)])
    }

    /// ② 第 2 頁 busy 兩次：只重送第 2 頁（第 1 頁 1 次、第 2 頁 3 次），等 0.5 s、1.0 s
    @Test func busySecondPageRetriesOnlyThatPage() async {
        let client = ScriptedEchoClient(total: 250)
        client.lock.withLock { client.failuresOnCall = [2: .remote(.busy), 3: .remote(.busy)] }
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready })
        #expect(vm.albums.count == 250)
        #expect(client.requestedCursors.map(page) == [1, 2, 2, 2, 3])
        #expect(retrySleeper.durations == [.milliseconds(500), .seconds(1)])
    }

    /// ③ 連 3 次＝失敗、停止自動重試（不排長退避、不再發請求）
    @Test func exhaustedRetriesFailAndStop() async {
        let client = ScriptedEchoClient(total: 50)
        client.lock.withLock { client.failuresOnCall = [1: .remote(.rateLimited), 2: .remote(.busy), 3: .remote(.rateLimited)] }
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .failed(.network) })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(client.calls == 3)
        #expect(await sleeper.waiting == 0)
        #expect(retrySleeper.durations == [.milliseconds(500), .seconds(1)])
    }

    /// ④ 睡眠中按 Retry：舊 task 被取消、不發下一次請求、不覆寫新結果
    @Test func reloadDuringBackoffCancelsOldLoop() async {
        let client = ScriptedEchoClient(total: 50)
        client.lock.withLock { client.failuresOnCall = [1: .remote(.busy)] }
        retrySleeper.lock.withLock { retrySleeper.hold = true }
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { retrySleeper.waiting == 1 })
        vm.retry()
        #expect(await waitUntil { vm.phase == .ready })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(retrySleeper.waiting == 0)
        #expect(client.calls == 2)
        #expect(vm.albums.count == 50 && vm.phase == .ready)
    }

    /// ⑤ 請求在途中換世代，舊請求回來的是成功：不採用、不續發下一頁
    @Test func staleSuccessIsNotAdopted() async {
        let client = ScriptedEchoClient(total: 150)
        client.lock.withLock { client.holdOnCall = 1 }
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { client.heldPages == 1 })
        vm.retry()
        #expect(await waitUntil { vm.phase == .ready })
        #expect(client.calls == 3)
        client.releasePages()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(client.calls == 3)
        #expect(vm.albums.count == 150 && vm.phase == .ready)
    }

    /// ⑤ 請求在途中換世代，舊請求回來的是 busy／rateLimited：不睡、不重送（catch 後檢查點；Codex R4-2）
    @Test(arguments: [ErrorCode.busy, .rateLimited])
    func staleTransientErrorIsNotRetried(_ code: ErrorCode) async {
        let client = ScriptedEchoClient(total: 50)
        client.lock.withLock {
            client.holdOnCall = 1
            client.failuresOnCall = [1: .remote(code)]
        }
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { client.heldPages == 1 })
        vm.retry()
        #expect(await waitUntil { vm.phase == .ready })
        client.releasePages()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(retrySleeper.durations.isEmpty)
        #expect(client.calls == 2)
        #expect(vm.phase == .ready)
    }

    /// ⑤′ 睡眠拋非取消錯誤：照一般失敗呈現，不卡在載入中（Codex R4-1）
    @Test func sleepFailureShowsNetworkFailure() async {
        let client = ScriptedEchoClient(total: 50)
        client.lock.withLock { client.failuresOnCall = [1: .remote(.busy)] }
        retrySleeper.lock.withLock { retrySleeper.failure = SleepFailure() }
        let vm = model()
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .failed(.network) })
        #expect(client.calls == 1)
    }
}
