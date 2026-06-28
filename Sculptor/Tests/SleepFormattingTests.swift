import Testing
@testable import Sculptor

@Suite struct SleepFormattingTests {
    @Test func zeroIsDoubleZero() {
        #expect(formatCountdown(0) == "00:00")
    }

    @Test func underOneMinutePadsSeconds() {
        #expect(formatCountdown(65) == "01:05")
    }

    @Test func fifteenMinutes() {
        #expect(formatCountdown(900) == "15:00")
    }

    @Test func sixtyMinutes() {
        #expect(formatCountdown(3600) == "60:00")
    }

    @Test func negativeClampsToZero() {
        #expect(formatCountdown(-5) == "00:00")
    }
}
