import Network
import Testing
@testable import ProbeShared

// 「恰好一個服務才自動連」的規則只在這裡定義；ProbeSummary 與 NetworkProbe 都消費它
@Suite struct BrowseSelectionTests {
    @Test func exactlyOneServiceIsUnique() {
        #expect(BrowseSelection.select(names: ["Mac"], failure: nil) == .unique(index: 0))
    }

    @Test func noServiceIsNone() {
        #expect(BrowseSelection.select(names: [], failure: nil) == .none)
    }

    @Test func severalServicesAreAmbiguous() {
        #expect(BrowseSelection.select(names: ["a", "b"], failure: nil) == .ambiguous(["a", "b"]))
    }

    @Test func aBrowserFailureWinsEvenWithServices() {
        #expect(BrowseSelection.select(names: ["a"], failure: "waiting: NoAuth") == .failed("waiting: NoAuth"))
    }
}

@Suite struct NetworkErrorTextTests {
    @Test func posixErrorShowsOnlyTheCode() {
        #expect(networkErrorText(.posix(.ECONNREFUSED)) == "posix(61)")
    }

    @Test func serviceTypeIsShared() {
        #expect(N5Message.serviceType == "_yse._tcp")
    }
}
