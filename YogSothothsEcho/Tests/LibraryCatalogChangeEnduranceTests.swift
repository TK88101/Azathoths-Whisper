import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// S7 T6 E2（sprint-7-detail.md §4.5）：分頁取回中途曲庫連續變動 50 輪。每輪先換一版、讓第 2 頁卡在途中，
// 再換一版——最後清單必須＝最後一版、沒有重複專輯、卡住的舊頁放行後也不得混進來。名稱一律自編（ScriptedEchoClient）

@MainActor
@Suite(.timeLimit(.minutes(2)))
struct LibraryCatalogChangeEnduranceTests {
    static let rounds = 50
    let sleeper = ManualSleeper()
    let retrySleeper = CancellableSleeper()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lib-endurance-\(UUID().uuidString)")

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private static func version(_ round: Int, _ step: Int) -> String { String(format: "%014llx%02x", UInt64(round), step) }

    @Test func changesDuringPagingAlwaysEndOnTheLatestVersion() async {
        let client = ScriptedEchoClient(total: 120)
        let sleeper = sleeper
        let vm = LibraryViewModel(artworkDirectory: directory, sleep: { await sleeper.sleep($0) }, retry: retrySleeper.options)
        vm.attach(client)
        #expect(await waitUntil { vm.phase == .ready && vm.albums.count == 120 })
        for round in 1...Self.rounds {
            // 第一版：重同步的第 2 頁卡住（已送出、回覆在途，不理會取消）
            let first = Self.version(round, 1), latest = Self.version(round, 2)
            let latestTotal = 150 + round
            client.lock.withLock {
                client.version = first
                client.total = latestTotal - 1
                client.holdOnCall = client.pageCalls + 2
            }
            client.changeContinuation.yield(first)
            #expect(await waitUntil { client.heldPages == 1 }, "第 \(round) 輪第 2 頁沒有卡住")
            // 還在分頁時又換一版
            client.lock.withLock {
                client.version = latest
                client.total = latestTotal
                client.holdOnCall = nil
            }
            client.changeContinuation.yield(latest)
            client.releasePages()
            #expect(await waitUntil { vm.phase == .ready && vm.version == latest && vm.albums.count == latestTotal },
                    "第 \(round) 輪停在 version=\(vm.version) count=\(vm.albums.count) phase=\(vm.phase)")
            #expect(Set(vm.albums.map(\.id)).count == vm.albums.count, "第 \(round) 輪有重複專輯")
        }
        vm.detach()
    }
}
