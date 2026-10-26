import Testing
@testable import SpikeCore

struct OSLogLineTests {
    @Test func parsesTheFieldsB6Needs() {
        let json = #"{"timestamp":"2026-10-14 23:27:46.709740+0900","machTimestamp":4712353872551,"subsystem":"com.ibridgezhao.azathothswhisper","category":"monitor","eventMessage":"read 3 signal changed=true 41ms"}"#
        let line = OSLogLine.parse(json)
        #expect(line == OSLogLine(machTimestamp: 4_712_353_872_551, subsystem: "com.ibridgezhao.azathothswhisper",
                                  category: "monitor", message: "read 3 signal changed=true 41ms"))
    }

    @Test(arguments: [
        "Filtering the log data using \"subsystem == x\"",
        #"{"machTimestamp":"not a number","eventMessage":"x"}"#,
        #"{"eventMessage":"x"}"#,
        "",
    ])
    func headerLinesAndMalformedLinesAreSkipped(_ text: String) {
        #expect(OSLogLine.parse(text) == nil)
    }

    @Test func machTicksConvertToSecondsWithTheTimebase() {
        // Apple Silicon 常見 timebase 125/3：24 MHz
        #expect(MachTime.seconds(ticks: 24_000_000, numer: 125, denom: 3) == 1.0)
    }
}
