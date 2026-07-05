import Testing
@testable import Sculptor

@Suite struct SleepFormattingTests {
    @Test func zeroIsDoubleZero() {
        #expect(SleepFormatting.countdown(0) == "00:00")
    }

    @Test func underOneMinutePadsSeconds() {
        #expect(SleepFormatting.countdown(65) == "01:05")
    }

    @Test func fifteenMinutes() {
        #expect(SleepFormatting.countdown(900) == "15:00")
    }

    @Test func sixtyMinutes() {
        #expect(SleepFormatting.countdown(3600) == "60:00")
    }

    @Test func negativeClampsToZero() {
        #expect(SleepFormatting.countdown(-5) == "00:00")
    }
}
