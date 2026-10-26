import Foundation
import Testing
@testable import ProbeShared

@Suite struct BrowseSummaryTests {
    @Test func exactlyOneServicePassesAndListsItsName() {
        let display = ProbeSummary.browse(serviceNames: ["YSE N5 Probe"], failure: nil)
        #expect(display == .passed(headline: "找到 1 個 _yse._tcp 服務", lines: ["YSE N5 Probe"]))
    }

    @Test func noServicesFailsWithHint() {
        let display = ProbeSummary.browse(serviceNames: [], failure: nil)
        guard case .failed(let headline, let lines) = display else { Issue.record("應為 failed"); return }
        #expect(headline == "未找到 _yse._tcp 服務")
        #expect(!lines.isEmpty)
    }

    /// 安全評審 M1：多個服務時無法確定是哪台 Mac，不自動連第一個
    @Test func moreThanOneServiceIsNotAPass() {
        let display = ProbeSummary.browse(serviceNames: ["a", "b"], failure: nil)
        guard case .failed(let headline, let lines) = display else { Issue.record("應為 failed"); return }
        #expect(headline.contains("2"))
        #expect(lines.contains("a") && lines.contains("b"))
    }

    @Test func browserFailureIsShownEvenIfNamesPresent() {
        let display = ProbeSummary.browse(serviceNames: ["x"], failure: "waiting: NoAuth")
        guard case .failed(_, let lines) = display else { Issue.record("應為 failed"); return }
        #expect(lines.contains("waiting: NoAuth"))
    }
}

@Suite struct ConnectSummaryTests {
    @Test func receivedChallengeIsHeadlineWithCompareHint() {
        let display = ProbeSummary.connect(.received("123456"))
        guard case .passed(let headline, let lines) = display else { Issue.record("應為 passed"); return }
        #expect(headline == "123456")
        #expect(lines.contains { $0.contains("比對") })
    }

    @Test func eachFailureKindFails() {
        let results: [ConnectResult] = [.noEndpoint, .invalidMessage, .timedOut, .failed("posix(61)")]
        for result in results {
            guard case .failed(let headline, _) = ProbeSummary.connect(result) else {
                Issue.record("\(result) 應為 failed"); continue
            }
            #expect(!headline.isEmpty)
        }
    }

    @Test func failedCarriesErrorText() {
        guard case .failed(_, let lines) = ProbeSummary.connect(.failed("posix(61)")) else {
            Issue.record("應為 failed"); return
        }
        #expect(lines.contains { $0.contains("posix(61)") })
    }

    @Test func timeoutMentionsTenSeconds() {
        guard case .failed(let headline, _) = ProbeSummary.connect(.timedOut) else {
            Issue.record("應為 failed"); return
        }
        #expect(headline.contains("10"))
    }
}

@Suite struct KeychainSummaryTests {
    private let expected = "abc123"

    @Test func allThreeStepsOkPasses() {
        let report = KeychainReport(expected: expected, writeStatus: 0, readStatus: 0, readValue: expected, deleteStatus: 0)
        #expect(report.steps.map(\.outcome) == [.ok, .ok, .ok])
        #expect(report.passed)
        guard case .passed(_, let lines) = ProbeSummary.keychain(report) else { Issue.record("應為 passed"); return }
        #expect(lines.count == 3)
    }

    @Test func writeFailureSkipsLaterSteps() {
        let report = KeychainReport(expected: expected, writeStatus: -34018, readStatus: nil, readValue: nil, deleteStatus: nil)
        #expect(report.steps.map(\.outcome) == [.failed("OSStatus -34018"), .skipped, .skipped])
        #expect(!report.passed)
    }

    @Test func readValueMismatchFailsReadStep() {
        let report = KeychainReport(expected: expected, writeStatus: 0, readStatus: 0, readValue: "other", deleteStatus: 0)
        #expect(report.steps[1].outcome == .failed("讀回的值與寫入不一致"))
        #expect(!report.passed)
    }

    @Test func readStatusErrorFailsReadStep() {
        let report = KeychainReport(expected: expected, writeStatus: 0, readStatus: -25300, readValue: nil, deleteStatus: 0)
        #expect(report.steps[1].outcome == .failed("OSStatus -25300"))
    }

    @Test func readOkWithoutValueIsMismatch() {
        let report = KeychainReport(expected: expected, writeStatus: 0, readStatus: 0, readValue: nil, deleteStatus: 0)
        #expect(report.steps[1].outcome == .failed("讀回的值與寫入不一致"))
    }

    @Test func deleteFailureFailsOnlyDeleteStep() {
        let report = KeychainReport(expected: expected, writeStatus: 0, readStatus: 0, readValue: expected, deleteStatus: -25244)
        #expect(report.steps.map(\.outcome) == [.ok, .ok, .failed("OSStatus -25244")])
        #expect(!report.passed)
    }

    @Test func displayNeverContainsExpectedValue() {
        let report = KeychainReport(expected: expected, writeStatus: 0, readStatus: 0, readValue: "other", deleteStatus: 0)
        let text = String(describing: ProbeSummary.keychain(report))
        #expect(!text.contains(expected))
        #expect(!text.contains("other"))
    }

    @Test func timedOutReportFailsWithTenSecondHeadline() {
        guard case .failed(let headline, _) = ProbeSummary.keychain(nil) else { Issue.record("應為 failed"); return }
        #expect(headline.contains("10"))
    }
}
