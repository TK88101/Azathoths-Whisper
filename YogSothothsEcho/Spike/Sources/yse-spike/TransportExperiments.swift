import Foundation
import SpikeCore

// B2（暫停／繼續、下一首、上一首）與 B3（seek）。sprint-0-detail.md §4.3、§4.3.2、§4.3.3。
@MainActor
extension Experiments {
    struct B2Record: Encodable {
        let check: B2Check
        /// 上一首在播放 ≥ 5 s 時按的行為紀錄：一律不進判定
        let restartOnly: Bool
        /// 行為紀錄才有：是否回到曲首（false＝跳到了前一首或其他）
        var restarted: Bool? = nil
        /// 診斷（下一首／上一首）：送出前的曲目、指令耗時與錯誤碼、從送出到讀到期待曲目的毫秒數
        var before: String? = nil
        var commandMilliseconds: Double? = nil
        var commandError: Int? = nil
        var matchedAfterMilliseconds: Double? = nil
        /// 診斷：2 s 內沒讀到時再觀察 8 s，最後讀到的曲目與（若有）讀到期待曲目的毫秒數；不改判定
        var lateReadID: String? = nil
        var lateMatchMilliseconds: Double? = nil
    }

    struct B2Oracle: Encodable {
        let sequence: [String]
    }

    static let lateObservation: Duration = .seconds(8)

    static func b2() async -> Bool {
        await run("b2", budget: .b2) { session in
            let (oracle, identity) = try await prepare(session)
            try await resetToStart(session, oracle: oracle)
            // 還原時點歌會換掉佇列，事後讀不回當時的順序，故先存一份（只有 persistentID）
            _ = try ResultWriter.save(experiment: "b2-oracle", records: [B2Oracle(sequence: oracle.sequence)])
            try await ensurePlaying(session)
            var records = try await pauseResume(session)
            records += try await walk(session, oracle: oracle, identity: identity)
            records += try await restartBehaviour(session)
            print("B2 判定：", B2Verdict.judge(records.filter { !$0.restartOnly }.map(\.check)).rawValue)
            return records
        }
    }

    private static func pauseResume(_ session: Session) async throws -> [B2Record] {
        var records: [B2Record] = []
        for _ in 0..<steps {
            for (kind, expected) in [(B2Check.Kind.pause, PlayerStateValue.paused), (.resume, .playing)] {
                let before = session.bridge.currentTrackID().value
                _ = try await session.command { session.bridge.playPause() }
                let state = await session.waitFor(session.bridge.state) { $0 == expected }
                records.append(B2Record(check: B2Check(kind: kind, expectedID: before,
                                                       readID: session.bridge.currentTrackID().value,
                                                       expectedState: expected, readState: state.value),
                                        restartOnly: false))
            }
        }
        return records
    }

    /// 下一首 ×20（第 1 → 21 首），再「seek 0＋上一首」×20 回到第 1 首（兼作 §4.3.3 重置）
    private static func walk(_ session: Session, oracle: PlaybackOracle, identity: String) async throws -> [B2Record] {
        var records: [B2Record] = []
        for kind in [B2Check.Kind.next, .previous] {
            for _ in 0..<steps {
                try assertContext(session, identity: identity)
                let current = session.bridge.currentTrackID().value ?? ""
                let expected = kind == .next ? oracle.expectedNext(after: current) : oracle.expectedPrevious(before: current)
                if kind == .previous { _ = try await session.command { session.bridge.seek(to: 0) } }
                let sent = ContinuousClock.now
                let result = try await session.command { kind == .next ? session.bridge.next() : session.bridge.previous() }
                let read = await session.waitFor(session.bridge.currentTrackID) { $0 == expected }
                var record = B2Record(check: B2Check(kind: kind, expectedID: expected, readID: read.value,
                                                     expectedState: .playing, readState: session.bridge.state().value),
                                      restartOnly: false)
                record.before = current
                record.commandMilliseconds = result.milliseconds
                record.commandError = result.errorCode
                record.matchedAfterMilliseconds = read.matchedAt.map { Self.milliseconds(sent, $0) }
                if read.matchedAt == nil {
                    (record.lateReadID, record.lateMatchMilliseconds) = await lateObserve(session, expected: expected, since: sent)
                }
                records.append(record)
                // 確認式節奏（2026-10-15 Codex 辯論後的詳細設計修訂，非判定條件）：
                // 新曲目真的開始出聲（位置走過 1 s）才送下一個，不在 Music 還在切換時連發
                if read.matchedAt != nil { await waitUntilAudible(session) }
            }
        }
        return records
    }

    /// B2 的期待值以「開始時在播放」為前提（2026-10-15 第 2 次重跑從暫停開始，80 筆狀態全部相反＝工具缺陷）
    static func ensurePlaying(_ session: Session) async throws {
        guard session.bridge.state().value != .playing else { return }
        _ = try await session.command { session.bridge.playPause() }
        guard await session.waitFor(session.bridge.state, until: { $0 == .playing }).matchedAt != nil else {
            throw Session.Stop.precondition("無法切到播放狀態")
        }
    }

    static let audibleThreshold = 1.0
    static let audibleTimeout: Duration = .seconds(5)

    /// 等新曲目播放位置走過 1 s（最多 5 s）；只是節奏控制，不影響判定
    static func waitUntilAudible(_ session: Session) async {
        let deadline = ContinuousClock.now + audibleTimeout
        while ContinuousClock.now < deadline {
            if (session.bridge.position().value ?? 0) >= audibleThreshold { return }
            try? await Task.sleep(for: Session.readInterval)
        }
    }

    /// 診斷用：2 s 內沒換到期待曲目時再觀察 8 s（只讀），區分「慢」與「被吞掉」
    private static func lateObserve(_ session: Session, expected: String?,
                                    since sent: ContinuousClock.Instant) async -> (String?, Double?) {
        let deadline = ContinuousClock.now + lateObservation
        var last = session.bridge.currentTrackID().value
        while ContinuousClock.now < deadline {
            if last == expected { return (last, milliseconds(sent, .now)) }
            try? await Task.sleep(for: Session.readInterval)
            last = session.bridge.currentTrackID().value
        }
        return (last, nil)
    }

    private static func milliseconds(_ from: ContinuousClock.Instant, _ to: ContinuousClock.Instant) -> Double {
        let elapsed = to - from
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }

    private static func restartBehaviour(_ session: Session) async throws -> [B2Record] {
        var records: [B2Record] = []
        for _ in 0..<steps {
            let current = session.bridge.currentTrackID().value
            _ = try await session.command { session.bridge.seek(to: 5) }
            _ = try await session.command { session.bridge.previous() }
            let read = await session.waitFor(session.bridge.position) { ($0 ?? 99) < 2 }
            records.append(B2Record(check: B2Check(kind: .previous, expectedID: current,
                                                   readID: session.bridge.currentTrackID().value,
                                                   expectedState: .playing, readState: session.bridge.state().value),
                                    restartOnly: true, restarted: read.matchedAt != nil))
        }
        return records
    }

    // MARK: B3

    static func b3() async -> Bool {
        await run("b3", budget: .b3) { session in
            guard let duration = session.bridge.currentDuration().value, duration >= 60 else {
                throw Session.Stop.precondition("當前曲目不足 60 s")
            }
            var checks: [SeekCheck] = []
            for target in seekTargets(duration: duration) {
                checks.append(try await seek(session, to: target, duration: duration))
            }
            print("B3 判定：", B3Verdict.judge(checks).rawValue)
            return checks
        }
    }

    /// 0 s、曲末前 5 s，其餘在 [15, 曲末 − 15] 均勻分布，共 20 個
    static func seekTargets(duration: Double) -> [Double] {
        let inner = (0..<18).map { 15 + Double($0) * (duration - 30) / 17 }
        return [0, duration - 5] + inner
    }

    private static func seek(_ session: Session, to target: Double, duration: Double) async throws -> SeekCheck {
        let start = target < duration / 2 ? min(target + 15, duration - 20) : max(target - 15, 10)
        _ = try await session.command { session.bridge.seek(to: start) }
        let track = session.bridge.currentTrackID().value
        let wasPlaying = session.bridge.state().value == .playing
        // 計時窗內不夾指令間隔；讀回照 §4.3 共通規則重試到 2 s（Music 非同步套用 seek：
        // 2026-10-15 實測送出後約 17 ms 讀回，20 筆有 17 筆仍是 seek 前的位置）
        try session.reserve()
        let sentAt = Mach.seconds(Mach.now())
        _ = session.bridge.seek(to: target)
        var check = readSeek(session, target: target, sentAt: sentAt, wasPlaying: wasPlaying, track: track)
        let deadline = sentAt + Double(Session.readDeadline.components.seconds)
        while !check.isWithinTolerance, Mach.seconds(Mach.now()) < deadline {
            try await Task.sleep(for: Session.readInterval)
            check = readSeek(session, target: target, sentAt: sentAt, wasPlaying: wasPlaying, track: track)
        }
        try await Task.sleep(for: Session.commandGap)
        return check
    }

    private static func readSeek(_ session: Session, target: Double, sentAt: Double, wasPlaying: Bool,
                                 track: String?) -> SeekCheck {
        let readBack = session.bridge.position().value
        let readAt = Mach.seconds(Mach.now())
        return SeekCheck(target: target, readBack: readBack, sentAt: sentAt, readAt: readAt, wasPlaying: wasPlaying,
                         trackChanged: session.bridge.currentTrackID().value != track)
    }
}
