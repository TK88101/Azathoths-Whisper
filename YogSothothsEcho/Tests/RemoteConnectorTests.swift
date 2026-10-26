import Foundation
import Network
import RemoteProtocol
import RemoteTransport
import Testing
@testable import YogSothothsEcho

// S2 T11（sprint-2-detail.md §4.7、§4.12）：LiveRemoteConnector 的挑選邏輯——釘選不符換下一台、其他回答即採用、
// 未配對不尋址、身分不可用時 fail closed。網路與 Bonjour 以替身注入；身分用模擬器 Keychain 當次產生、測完清除。

final class FakeMacAttempts: MacAttempting, @unchecked Sendable {
    private let lock = NSLock()
    private var pairAnswers: [String: PairingAttemptResult]
    private var connectAnswers: [String: Result<Void, ConnectFailure>]
    private(set) var attempted: [String] = []

    init(pair: [String: PairingAttemptResult] = [:], connect: [String: Result<Void, ConnectFailure>] = [:]) {
        pairAnswers = pair
        connectAnswers = connect
    }

    var attempts: [String] { lock.withLock { attempted } }

    func pair(_ mac: DiscoveredMac, payload: QRPairingPayload, deviceName: String,
              onPending: @escaping @Sendable (String) -> Void) async -> PairingAttemptResult {
        lock.withLock {
            attempted.append(mac.name)
            return pairAnswers[mac.name] ?? .failed(.network)
        }
    }

    func connect(_ mac: DiscoveredMac) async -> Result<any RemoteSessionHandle, ConnectFailure> {
        let answer = lock.withLock { () -> Result<Void, ConnectFailure> in
            attempted.append(mac.name)
            return connectAnswers[mac.name] ?? .failure(.network)
        }
        return answer.map { FakeSession(macName: mac.name) }
    }
}

struct FailingIdentityStore: DeviceIdentityStore {
    func loadOrCreate() throws(IdentityError) -> DeviceIdentity { throw .keychainUnavailable(errSecNotAvailable) }
    func reset() throws(IdentityError) {}
    func warmUp() async throws(IdentityError) {}
}

final class DiscoverySpy: @unchecked Sendable {
    private let lock = NSLock()
    private var preferences: [Set<String>] = []
    private var windowsSeen: [TimeInterval] = []
    let macs: [DiscoveredMac]
    init(_ names: [String]) {
        macs = names.map { DiscoveredMac(name: $0, endpoint: .service(name: $0, type: EchoService.type, domain: "local.", interface: nil)) }
    }
    var calls: [Set<String>] { lock.withLock { preferences } }
    var windows: [TimeInterval] { lock.withLock { windowsSeen } }
    func discover(_ preferring: Set<String>, _ window: TimeInterval) -> [DiscoveredMac] {
        lock.withLock { preferences.append(preferring); windowsSeen.append(window) }
        return macs
    }
}

@Suite(.serialized) final class RemoteConnectorTests {
    let identityStore = KeychainDeviceIdentityStore(service: "com.ibridgezhao.yse.test." + UUID().uuidString.prefix(8).lowercased(),
                                                     defaultsSuite: "yse.test.connector." + UUID().uuidString)
    let trust = InMemoryTrustStore()

    deinit { try? identityStore.reset() }

    func payload(instance: String = "Azathoth-QR") -> QRPairingPayload { ConnectionSamples.payload(instance: instance) }

    func record(local: Fingerprint) -> PeerRecord {
        PeerRecord(peerID: UUID(), fingerprint: Fingerprint(bytes: Data(repeating: 9, count: 32))!, localFingerprint: local,
                   name: "Azathoth-QR", pairedAt: Date())
    }

    func connector(_ discovery: DiscoverySpy, _ attempts: FakeMacAttempts,
                   identity: (any DeviceIdentityStore)? = nil) -> LiveRemoteConnector {
        LiveRemoteConnector(identityStore: identity ?? identityStore, trust: trust,
                            discover: { discovery.discover($0, $1) }, makeAttempts: { _ in attempts })
    }

    func pairLocally() throws {
        try trust.add(record(local: identityStore.loadOrCreate().fingerprint))
    }

    // MARK: pair

    @Test func pairReturnsNotFoundWhenNoMacIsDiscovered() async {
        let attempts = FakeMacAttempts()
        #expect(await connector(DiscoverySpy([]), attempts).pair(payload: payload(), deviceName: "iPad", onPending: { _ in })
                == .failed(.notFound))
        #expect(attempts.attempts.isEmpty)
    }

    @Test func pairPrefersTheInstanceNameFromTheQR() async {
        let discovery = DiscoverySpy([])
        _ = await connector(discovery, FakeMacAttempts()).pair(payload: payload(instance: "Azathoth-1234"), deviceName: "iPad",
                                                               onPending: { _ in })
        #expect(discovery.calls == [["Azathoth-1234"]])
    }

    @Test func pairSkipsMacsWithPinMismatchAndTakesTheNextAnswer() async {
        let rejected = PairingAttemptResult.failed(.rejected)
        let attempts = FakeMacAttempts(pair: ["A": .failed(.macPinMismatch), "B": rejected, "C": .failed(.network)])
        #expect(await connector(DiscoverySpy(["A", "B", "C"]), attempts).pair(payload: payload(), deviceName: "iPad",
                                                                              onPending: { _ in }) == rejected)
        #expect(attempts.attempts == ["A", "B"])   // B 是 QR 上那台的回答，不再試 C
    }

    @Test func pairReportsMismatchWhenNoMacMatchesTheQR() async {
        let attempts = FakeMacAttempts(pair: ["A": .failed(.macPinMismatch), "B": .failed(.macPinMismatch)])
        #expect(await connector(DiscoverySpy(["A", "B"]), attempts).pair(payload: payload(), deviceName: "iPad",
                                                                         onPending: { _ in }) == .failed(.macPinMismatch))
        #expect(attempts.attempts == ["A", "B"])
    }

    @Test func pairFailsClosedWhenIdentityIsUnavailable() async {
        let discovery = DiscoverySpy(["A"])
        #expect(await connector(discovery, FakeMacAttempts(), identity: FailingIdentityStore())
            .pair(payload: payload(), deviceName: "iPad", onPending: { _ in }) == .failed(.network))
        #expect(discovery.calls.isEmpty)
    }

    // MARK: connect

    @Test func connectWithoutValidTrustDoesNotBrowse() async {
        let discovery = DiscoverySpy(["A"])
        let result = await connector(discovery, FakeMacAttempts()).connect()
        #expect(result.failure == .notPaired)
        #expect(discovery.calls.isEmpty)
    }

    @Test func recordBoundToAnotherLocalIdentityDoesNotCountAsPaired() throws {
        try trust.add(record(local: Fingerprint(bytes: Data(repeating: 7, count: 32))!))
        #expect(!connector(DiscoverySpy([]), FakeMacAttempts()).hasPairedMac)
        try pairLocally()
        #expect(connector(DiscoverySpy([]), FakeMacAttempts()).hasPairedMac)
    }

    @Test func connectReturnsNotFoundWhenNoMacIsDiscovered() async throws {
        try pairLocally()
        let discovery = DiscoverySpy([])
        #expect(await connector(discovery, FakeMacAttempts()).connect().failure == .notFound)
        // S3 LOW-6：重連以已配對 Mac 的實例名當偏好（看到就提早返回，不必等滿時窗）
        #expect(discovery.calls == [["Azathoth-QR"]])
    }

    @Test func connectSkipsOtherMacsAndUsesTheFirstSuccess() async throws {
        try pairLocally()
        let attempts = FakeMacAttempts(connect: ["A": .failure(.pinMismatch), "B": .success(()), "C": .success(())])
        let result = await connector(DiscoverySpy(["A", "B", "C"]), attempts).connect()
        #expect(result.session?.macName == "B")
        #expect(attempts.attempts == ["A", "B"])
    }

    @Test func connectReportsTheLastRealFailure() async throws {
        try pairLocally()
        let attempts = FakeMacAttempts(connect: ["A": .failure(.rejectedByMac), "B": .failure(.pinMismatch)])
        #expect(await connector(DiscoverySpy(["A", "B"]), attempts).connect().failure == .rejectedByMac)
        #expect(attempts.attempts == ["A", "B"])
    }

    /// S4 F14：等任何一台配對過的 Mac、時窗照呼叫端給的（30 s 等 Mac 窗）
    @Test func connectWaitsForEveryPairedMacWithTheGivenWindow() async throws {
        try pairLocally()
        try trust.add(PeerRecord(peerID: UUID(), fingerprint: Fingerprint(bytes: Data(repeating: 8, count: 32))!,
                                 localFingerprint: identityStore.loadOrCreate().fingerprint, name: "Azathoth-SECOND", pairedAt: Date()))
        let discovery = DiscoverySpy([])
        _ = await connector(discovery, FakeMacAttempts()).connect(discoveryWindow: DiscoveryWindow.waitingForMac)
        #expect(discovery.calls == [["Azathoth-QR", "Azathoth-SECOND"]])
        #expect(discovery.windows == [DiscoveryWindow.waitingForMac])
    }

    /// 瀏覽器一開就結束（例如失敗）而什麼都沒看到：仍等滿時窗，重連迴圈不會空轉
    @Test func discoveryWithNothingFoundWaitsOutTheWindow() async {
        let (stream, continuation) = AsyncStream<[DiscoveredMac]>.makeStream()
        continuation.finish()
        let started = ContinuousClock.now
        let macs = await LiveRemoteConnector.discover(in: stream, preferring: ["Azathoth-QR"], window: 0.3)
        #expect(macs.isEmpty)
        #expect(ContinuousClock.now - started >= .milliseconds(290))
    }

    /// S4 後半 security LOW-1：看得到 Mac 但都不是配對的那台≠看不到 Mac（前者要照一般退避，不能每 2 s 去握手）
    @Test func connectReportsOtherMacsOnlyWhenEveryPinMismatches() async throws {
        try pairLocally()
        let attempts = FakeMacAttempts(connect: ["A": .failure(.pinMismatch), "B": .failure(.pinMismatch)])
        #expect(await connector(DiscoverySpy(["A", "B"]), attempts).connect().failure == .otherMacsOnly)
    }

    @Test func connectFailsClosedWhenIdentityIsUnavailable() async {
        let discovery = DiscoverySpy(["A"])
        #expect(await connector(discovery, FakeMacAttempts(), identity: FailingIdentityStore()).connect().failure == .network)
        #expect(!connector(discovery, FakeMacAttempts(), identity: FailingIdentityStore()).hasPairedMac)
        #expect(discovery.calls.isEmpty)
    }

    @Test func forgetMacsRemovesEveryTrustRecord() throws {
        try pairLocally()
        let subject = connector(DiscoverySpy([]), FakeMacAttempts())
        subject.forgetMacs()
        #expect(!subject.hasPairedMac)
    }
}

/// 正式組裝（真 Keychain 身分＋UserDefaults 信任紀錄＋Bonjour），以隔離的 service／suite 執行、測完清除
@Suite(.serialized) final class LiveRemoteConnectorAssemblyTests {
    let service = "com.ibridgezhao.yse.test." + UUID().uuidString.prefix(8).lowercased()
    let suite = "yse.test.assembly." + UUID().uuidString

    deinit {
        try? KeychainDeviceIdentityStore(service: service, defaultsSuite: suite).reset()
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func freshInstallIsUnpairedAndConnectStopsBeforeBrowsing() async {
        let connector = LiveRemoteConnector(service: service, defaultsSuite: suite, audit: NoopAuditSink())
        #expect(!connector.hasPairedMac)
        #expect(await connector.connect().failure == .notPaired)
        connector.forgetMacs()
        #expect(!connector.hasPairedMac)
    }

    /// 尋址一定在時窗內結束（不因沒有 Mac 或瀏覽卡住而掛住配對／重連）
    @Test func bonjourDiscoveryEndsWithinItsWindow() async {
        let window: TimeInterval = 0.3
        let started = ContinuousClock.now
        let macs = await LiveRemoteConnector.bonjourDiscover(preferring: ["Azathoth-NONE"], window: window)
        #expect(ContinuousClock.now - started < .seconds(window + 2))
        #expect(macs.allSatisfy { $0.name != "Azathoth-NONE" })
    }
}

private extension Result where Success == any RemoteSessionHandle, Failure == ConnectFailure {
    var failure: ConnectFailure? { if case .failure(let error) = self { error } else { nil } }
    var session: (any RemoteSessionHandle)? { try? get() }
}
