import Foundation
import Network
import Observation

/// 三張卡片的狀態。網路與 Keychain 都在背景執行、各有 10 秒逾時；結果只有狀態文字。
@MainActor @Observable
final class ProbeModel {
    private(set) var browse: ProbeDisplay = .idle
    private(set) var connect: ProbeDisplay = .idle
    private(set) var keychain: ProbeDisplay = .idle
    private var endpoint: NWEndpoint?

    func runBrowse() async {
        guard browse != .running else { return }
        browse = .running
        let outcome = await NetworkProbe.browse()
        endpoint = outcome.endpoint
        browse = ProbeSummary.browse(serviceNames: outcome.names, failure: outcome.failure)
    }

    func runConnect() async {
        guard connect != .running else { return }
        connect = .running
        let result = await NetworkProbe.connect(to: endpoint)
        connect = ProbeSummary.connect(result)
    }

    func runKeychain() async {
        guard keychain != .running else { return }
        keychain = .running
        let report = await raceTimeout(probeTimeoutSeconds) { KeychainProbe.run() }
        keychain = ProbeSummary.keychain(report)
    }
}
