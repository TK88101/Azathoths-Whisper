import Testing
@testable import SpikeCore

struct N4ResultTests {
    private let feasible = N4Result(positiveHandshake: true, positiveEcho: true, negativeHandshake: false,
                                    negotiatedVersion: "TLSv1.3")

    @Test func handshakeEchoRejectionAndTLS13MakeItFeasible() {
        #expect(feasible.isFeasible)
    }

    @Test func aWrongKeyThatStillConnectsMeansThePSKIsNotChecked() {
        let r = N4Result(positiveHandshake: true, positiveEcho: true, negativeHandshake: true, negotiatedVersion: "TLSv1.3")
        #expect(!r.isFeasible)
    }

    @Test func anOlderNegotiatedVersionIsNotFeasible() {
        let r = N4Result(positiveHandshake: true, positiveEcho: true, negativeHandshake: false, negotiatedVersion: "TLSv1.2")
        #expect(!r.isFeasible)
    }

    @Test func noEchoIsNotFeasible() {
        let r = N4Result(positiveHandshake: true, positiveEcho: false, negativeHandshake: false, negotiatedVersion: "TLSv1.3")
        #expect(!r.isFeasible)
    }
}
