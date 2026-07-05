import Testing
@testable import Sculptor

@Suite struct PresetMetricsTests {
    @Test func bandsRaisedCountsPositiveGains() {
        #expect(PresetMetrics.bandsRaisedCount([0, 0, 0, 0, 0, 0, 0, 0]) == 0)
        #expect(PresetMetrics.bandsRaisedCount([3, 0, 2, -1, 0, 5, 0, 0]) == 3)
        #expect(PresetMetrics.bandsRaisedCount([-1, -2, -3]) == 0)
    }

    @Test func copyNamePrefixesCopyOf() {
        #expect(PresetMetrics.copyName(of: "Late night") == "Copy of Late night")
    }

    @Test func sanitizedRenameTrimsWhitespace() {
        #expect(PresetMetrics.sanitizedRename(old: "Old", new: "  Hi  ") == "Hi")
    }

    @Test func sanitizedRenameEmptyRevertsToOld() {
        #expect(PresetMetrics.sanitizedRename(old: "Old", new: "   ") == "Old")
        #expect(PresetMetrics.sanitizedRename(old: "Old", new: "") == "Old")
    }
}
