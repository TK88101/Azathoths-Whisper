import Foundation
import RemoteProtocol
import RemoteTransport
import Testing

@testable import YogSothothsEcho

// F-L1 R3（s6-61-library-retry.md §5、§6）：曲目分頁的短重試是 opt-in；只重送失敗的那一頁；取消不再試、不採用
struct PlaybackClientPagingRetryTests {
    let client = FakePlaybackClient()
    let sleeper = CancellableSleeper()
    let album = PlaybackSamples.album

    init() {
        client.lock.withLock {
            client.tracks[album] = .success(PlaybackSamples.tracks([PlaybackSamples.song(PlaybackSamples.t1, 1)], next: "c2"))
            client.tracks[album + "|c2"] = .success(PlaybackSamples.tracks([PlaybackSamples.song(PlaybackSamples.t2, 2)]))
        }
    }

    private func failSecondPage(_ errors: EchoRequestError...) {
        client.lock.withLock {
            client.trackSequence[album + "|c2"] = errors.map { .failure($0) }
                + [.success(PlaybackSamples.tracks([PlaybackSamples.song(PlaybackSamples.t2, 2)]))]
        }
    }

    /// 在獨立 task 裡載入、回傳拋出的錯誤（nil＝成功）。不用 typed-throws 的 Task 閉包：Swift 6.4 生成 reabstraction thunk 時崩潰
    private func startLoad() -> Task<EchoRequestError?, Never> {
        let options = sleeper.options, client = client, album = album
        return Task {
            do throws(EchoRequestError) {
                _ = try await client.allTracks(albumID: album, retry: options)
                return nil
            } catch {
                return error
            }
        }
    }

    /// 不傳 retry（NowPlayingViewModel.fetchTitles 的背景查曲名）＝第一次 busy 即拋，不在限流時加壓
    @Test func withoutOptionsBusyThrowsImmediately() async {
        failSecondPage(.remote(.busy))
        await #expect(throws: EchoRequestError.remote(.busy)) { try await client.allTracks(albumID: album) }
        #expect(client.trackCalls(album).count == 2)
    }

    @Test func busySecondPageIsResentAlone() async throws {
        failSecondPage(.remote(.busy))
        let result = try await client.allTracks(albumID: album, retry: sleeper.options)
        #expect(result.songs.map(\.id) == [PlaybackSamples.t1, PlaybackSamples.t2])
        #expect(client.trackCalls(album) == ["tracks:\(album):-", "tracks:\(album):c2", "tracks:\(album):c2"])
        #expect(sleeper.durations == [.milliseconds(500)])
    }

    @Test func threeFailuresThrowTheLastError() async {
        failSecondPage(.remote(.busy), .remote(.rateLimited), .remote(.busy))
        await #expect(throws: EchoRequestError.remote(.busy)) { try await client.allTracks(albumID: album, retry: sleeper.options) }
        #expect(client.trackCalls(album).count == 1 + 3)
        #expect(sleeper.durations == [.milliseconds(500), .seconds(1)])
    }

    @Test func libraryUnavailableIsNotShortRetried() async {
        failSecondPage(.remote(.libraryUnavailable))
        await #expect(throws: EchoRequestError.remote(.libraryUnavailable)) {
            try await client.allTracks(albumID: album, retry: sleeper.options)
        }
        #expect(sleeper.durations.isEmpty)
    }

    @Test func cancelledWhileSleepingThrowsCancelledWithoutResending() async {
        failSecondPage(.remote(.busy))
        sleeper.lock.withLock { sleeper.hold = true }
        let task = startLoad()
        #expect(await eventually { sleeper.waiting == 1 })
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(client.trackCalls(album).count == 2)
    }

    /// 請求在途中被取消、回覆是成功：不採用該頁、拋 .cancelled、不續發
    @Test func cancelledInFlightSuccessIsNotAdopted() async {
        client.lock.withLock { client.holdTracksStubbornly = true }
        let task = startLoad()
        #expect(await eventually { client.heldStubbornTracks == 1 })
        task.cancel()
        client.releaseStubbornTracks()
        #expect(await task.value == .cancelled)
        #expect(client.trackCalls(album).count == 1)
    }

    /// 請求在途中被取消、回覆是 busy：不睡、不重送、拋 .cancelled（catch 後檢查點）
    @Test func cancelledInFlightBusyIsNotRetried() async {
        client.lock.withLock {
            client.trackSequence[album] = [.failure(.remote(.busy))]
            client.holdTracksStubbornly = true
        }
        let task = startLoad()
        #expect(await eventually { client.heldStubbornTracks == 1 })
        task.cancel()
        client.releaseStubbornTracks()
        #expect(await task.value == .cancelled)
        #expect(sleeper.durations.isEmpty)
        #expect(client.trackCalls(album).count == 1)
    }

    /// 睡眠拋非取消錯誤＝拋觸發這次重試的原錯誤（不轉 .cancelled；Codex R4-1）
    @Test func sleepFailureThrowsTheOriginalError() async {
        failSecondPage(.remote(.rateLimited))
        sleeper.lock.withLock { sleeper.failure = SleepFailure() }
        await #expect(throws: EchoRequestError.remote(.rateLimited)) {
            try await client.allTracks(albumID: album, retry: sleeper.options)
        }
        #expect(client.trackCalls(album).count == 2)
    }
}
