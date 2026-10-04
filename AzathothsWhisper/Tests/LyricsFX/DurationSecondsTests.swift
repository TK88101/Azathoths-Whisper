import Testing

@testable import AzathothsWhisper

@Suite("Duration seconds")
struct DurationSecondsTests {
    @Test func convertsWholeAndFractionalSeconds() {
        #expect(Duration.seconds(2).inSeconds == 2)
        #expect(Duration.milliseconds(1500).inSeconds == 1.5)
        #expect(Duration.milliseconds(-250).inSeconds == -0.25)
        #expect(Duration.zero.inSeconds == 0)
    }
}
